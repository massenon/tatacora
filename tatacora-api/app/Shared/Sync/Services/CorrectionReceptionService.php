<?php

declare(strict_types=1);

namespace App\Shared\Sync\Services;

use App\Models\User;
use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Rbac\Models\JournalSecurite;
use App\Shared\Sync\Exceptions\RefusSynchronisationException;
use App\Shared\Sync\Models\JournalReceptionSynchronisation as Journal;
use App\Shared\Sync\Models\SessionSynchronisation;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use RuntimeException;
use Throwable;

/**
 * Corriger, relancer, ignorer une opération REÇUE d'un poste — demande du PO
 * du 26/10/2026 (« identifier la CAUSE des échecs, corriger et relancer »).
 *
 * ## Le même chemin que la synchronisation
 *
 * Une opération n'est JAMAIS réécrite par un raccourci : `relancer` la rejoue
 * par `SynchronisationService::traiterOperation`, donc par le gestionnaire et
 * le service de domaine de sa table — mêmes règles, mêmes pièces, mêmes
 * droits. Elle garde l'horodatage de SAISIE d'origine (la date métier du
 * document reste celle du poste, jamais celle de la correction), et part sous
 * un nouvel `uuid_operation` : l'ancien est mémorisé avec son rejet.
 *
 * ## Les droits : ceux du module concerné
 *
 * L'écran est réservé aux Administrateurs et au Comptable (`estAutorise`),
 * et chaque action exige en plus le niveau d'écriture (`C`) sur TOUS les
 * modules que le gestionnaire exige pour cette charge — ce que
 * l'opération aurait demandé à son auteur. Le niveau est lu par
 * `User::niveauSurModule()`, comme partout. L'auteur de chaque action est
 * tracé au journal (`traite_par`) ET au journal d'audit.
 *
 * ## Idempotence
 *
 * Une opération déjà prise en charge ne se relance pas deux fois (verrou sur
 * la ligne, état relu sous verrou) ; et un document créé deux fois sous le
 * même identifiant est de toute façon rendu tel quel par son gestionnaire.
 */
class CorrectionReceptionService
{
    /** Les clés de la charge qui ne se modifient pas à la main. */
    private const CLES_FIGEES = ['id', 'uuid', 'code_article', 'module_source', 'type_vente', 'type'];

    /** Garde-fou : un formulaire de correction ne dépasse pas ce nombre de champs. */
    private const CHAMPS_MAX = 150;

    public function __construct(
        private readonly SynchronisationService $synchronisation,
        private readonly RegistreSynchronisation $registre,
        private readonly JournalReceptionService $journal,
    ) {
    }

    // ------------------------------------------------------------------
    // Droits
    // ------------------------------------------------------------------

    /** Administrateurs et Comptable : les seuls à lire ces journaux. */
    public function estAutorise(?User $utilisateur): bool
    {
        return $utilisateur !== null
            && ($utilisateur->estAdministrateur() || (string) $utilisateur->role?->libelle === 'comptable');
    }

    /**
     * Les tables que cet utilisateur peut lire dans le journal : celles dont
     * il lit (au moins) le module. `null` = toutes (administration).
     *
     * @return list<string>|null
     */
    public function tablesVisibles(User $utilisateur): ?array
    {
        if ($utilisateur->estAdministrateur()) {
            return null;
        }

        $tables = [];

        foreach (array_keys(RegistreSynchronisation::TABLES_SYNCHRONISABLES) as $table) {
            if ($utilisateur->niveauSurModule($this->registre->pour($table)->module()) !== '-') {
                $tables[] = $table;
            }
        }

        // Le dépôt d'un reçu de dépense (fichier) suit le droit de lecture de M10.
        if ($utilisateur->niveauSurModule('M10') !== '-') {
            $tables[] = JournalReceptionService::TABLE_RECUS_DEPENSES;
        }

        return $tables;
    }

    /**
     * Les modules à écrire pour agir sur cette opération — vide si la table
     * n'est pas (ou plus) synchronisable.
     *
     * @return list<string>
     */
    public function modulesRequis(Journal $entree): array
    {
        if (! $this->registre->estSynchronisable($entree->table_concernee)) {
            return [];
        }

        $gestionnaire = $this->registre->pour($entree->table_concernee);

        return array_values(array_unique($gestionnaire->modulesRequis($entree->payload_corrige ?? $entree->payload ?? [])));
    }

    /** Le premier module que l'auteur ne peut pas écrire, ou `null`. */
    public function moduleRefuse(Journal $entree, User $auteur): ?string
    {
        if (! $this->estAutorise($auteur)) {
            return '';
        }

        $niveau = $this->registre->estSynchronisable($entree->table_concernee)
            ? $this->registre->pour($entree->table_concernee)->niveauRequis()
            : 'C';

        $modules = $this->modulesRequis($entree);

        if ($modules === []) {
            // Table hors registre : seule l'administration peut la prendre en charge.
            return $auteur->estAdministrateur() ? null : '';
        }

        foreach ($modules as $module) {
            if ($auteur->niveauSurModule($module) !== $niveau) {
                return $module;
            }
        }

        return null;
    }

    public function peutCorriger(Journal $entree): bool
    {
        return in_array($entree->issue, [Journal::REJETEE, Journal::ERREUR], true)
            && in_array($entree->traitement, [Journal::A_TRAITER, Journal::CORRIGE], true)
            && is_array($entree->payload)
            && $this->registre->estSynchronisable($entree->table_concernee);
    }

    public function peutIgnorer(Journal $entree): bool
    {
        return in_array($entree->traitement, [Journal::A_TRAITER, Journal::CORRIGE], true);
    }

    // ------------------------------------------------------------------
    // Le formulaire de correction
    // ------------------------------------------------------------------

    /**
     * Les valeurs de la charge, à plat, dans un ordre stable.
     *
     * @param  array<string, mixed>  $payload
     * @return list<array{chemin: string, libelle: string, valeur: mixed, modifiable: bool}>
     */
    public function champs(array $payload): array
    {
        $champs = [];
        $this->aplatir($payload, '', $champs);

        return array_slice($champs, 0, self::CHAMPS_MAX);
    }

    /**
     * @param  array<array-key, mixed>  $valeurs
     * @param  list<array{chemin: string, libelle: string, valeur: mixed, modifiable: bool}>  $champs
     */
    private function aplatir(array $valeurs, string $prefixe, array &$champs): void
    {
        foreach ($valeurs as $cle => $valeur) {
            $chemin = $prefixe === '' ? (string) $cle : $prefixe . '.' . $cle;

            if (is_array($valeur)) {
                $this->aplatir($valeur, $chemin, $champs);

                continue;
            }

            $champs[] = [
                'chemin' => $chemin,
                'libelle' => $this->journal->libelleChamp($chemin),
                'valeur' => $valeur,
                'modifiable' => $this->estModifiable((string) $cle, $valeur),
            ];
        }
    }

    private function estModifiable(string $cle, mixed $valeur): bool
    {
        if (is_bool($valeur) || $valeur === '***') {
            return false;
        }

        return ! (in_array($cle, self::CLES_FIGEES, true) || preg_match('/(^|_)(id|uuid)$/', $cle) === 1);
    }

    /**
     * La charge, avec les valeurs saisies (index du champ → texte).
     *
     * @param  array<string, mixed>  $payload
     * @param  array<int|string, mixed>  $saisie
     * @return array{0: array<string, mixed>, 1: list<string>} la charge corrigée et les chemins modifiés
     */
    public function appliquerSaisie(array $payload, array $saisie): array
    {
        $modifies = [];

        foreach ($this->champs($payload) as $indice => $champ) {
            if (! $champ['modifiable'] || ! array_key_exists($indice, $saisie)) {
                continue;
            }

            $brut = $saisie[$indice];

            if (! is_scalar($brut) && $brut !== null) {
                continue;
            }

            $texte = trim((string) $brut);
            $actuel = $champ['valeur'];

            if ($texte === trim((string) $actuel)) {
                continue;
            }

            $nouvelle = match (true) {
                is_int($actuel) => preg_match('/^-?\d+$/', $texte) === 1 ? (int) $texte : $texte,
                is_float($actuel) => is_numeric($texte) ? (float) $texte : $texte,
                $actuel === null && $texte === '' => null,
                default => $texte,
            };

            $this->poser($payload, explode('.', $champ['chemin']), $nouvelle);
            $modifies[] = $champ['chemin'];
        }

        return [$payload, $modifies];
    }

    /**
     * @param  array<array-key, mixed>  $cible
     * @param  list<string>  $chemin
     */
    private function poser(array &$cible, array $chemin, mixed $valeur): void
    {
        $cle = array_shift($chemin);
        $cle = is_numeric($cle) && array_is_list($cible) ? (int) $cle : $cle;

        if ($chemin === []) {
            $cible[$cle] = $valeur;

            return;
        }

        if (! isset($cible[$cle]) || ! is_array($cible[$cle])) {
            return;
        }

        $this->poser($cible[$cle], $chemin, $valeur);
    }

    // ------------------------------------------------------------------
    // Les trois actions
    // ------------------------------------------------------------------

    /**
     * Enregistre la charge corrigée — APRÈS l'avoir fait vérifier par les
     * règles de gestion du module concerné.
     *
     * La vérification REJOUE l'opération pour de bon puis ANNULE tout ce
     * qu'elle a écrit (transaction annulée) : la correction n'est retenue que
     * si le service du domaine l'accepterait. Rien n'est appliqué à ce stade ;
     * `relancer` applique.
     *
     * @param  array<string, mixed>  $payloadCorrige
     * @return array{ok: bool, motif: ?string}
     */
    public function corriger(string $id, array $payloadCorrige, User $auteur): array
    {
        $entree = $this->entree($id);
        $this->exigerDroits($entree, $auteur);

        if (! $this->peutCorriger($entree)) {
            throw new RuntimeException(__('synchronisation_journal.ecran.refus_non_modifiable'));
        }

        $verdict = $this->verifier($entree, $payloadCorrige);

        if (! $verdict['ok']) {
            return $verdict;
        }

        DB::transaction(function () use ($entree, $payloadCorrige, $auteur): void {
            $avant = $entree->payload_corrige ?? $entree->payload;
            $entree->update([
                'payload_corrige' => $payloadCorrige,
                'traitement' => Journal::CORRIGE,
                'traite_par' => $auteur->id,
                'traite_le' => now(),
            ]);
            $this->tracer('synchronisation_corrigee', $entree, $auteur, $this->difference($avant ?? [], $payloadCorrige), $payloadCorrige);
        });

        return ['ok' => true, 'motif' => null];
    }

    /**
     * Rejoue l'opération avec la charge corrigée (à défaut, la charge reçue),
     * par le même chemin que la synchronisation.
     *
     * @return array{ok: bool, motif: ?string, issue: string}
     */
    public function relancer(string $id, User $auteur): array
    {
        $entree = $this->entree($id);
        $this->exigerDroits($entree, $auteur);

        return DB::transaction(function () use ($id, $auteur): array {
            /** @var Journal $entree */
            $entree = Journal::query()->whereKey($id)->lockForUpdate()->firstOrFail();

            if (! in_array($entree->issue, [Journal::REJETEE, Journal::ERREUR], true)) {
                throw new RuntimeException(__(
                    $entree->traitement === Journal::RELANCE
                        ? 'synchronisation_journal.ecran.relance_deja_aboutie'
                        : 'synchronisation_journal.ecran.relance_impossible',
                ));
            }

            if (! in_array($entree->traitement, [Journal::A_TRAITER, Journal::CORRIGE], true)) {
                throw new RuntimeException(__('synchronisation_journal.ecran.refus_non_modifiable'));
            }

            $charge = $entree->payload_corrige ?? $entree->payload;

            if (! is_array($charge) || $entree->utilisateur_id === null || in_array('***', array_values($this->feuilles($charge)), true)) {
                throw new RuntimeException(__('synchronisation_journal.ecran.relance_charge_absente'));
            }

            $operation = $this->operation($entree, $charge);
            $resultat = $this->synchronisation->traiterOperation(
                $operation,
                $entree->poste_id,
                (string) $entree->utilisateur_id,
                $this->session($entree),
                journaliser: false,
            );
            $analyse = $this->journal->analyser($operation, $resultat, $this->synchronisation->extrasDeLaDerniereOperation());
            $reussi = ! in_array($analyse['issue'], [Journal::REJETEE, Journal::CONFLIT, Journal::ERREUR], true);

            $entree->update([
                ...$analyse,
                'tentatives' => $entree->tentatives + 1,
                'derniere_tentative_le' => now(),
                'operation_relance_id' => $operation['uuid_operation'],
                'traitement' => $reussi ? Journal::RELANCE : Journal::A_TRAITER,
                'traite_par' => $auteur->id,
                'traite_le' => now(),
                'motif_traitement' => null,
            ]);

            $this->tracer($reussi ? 'synchronisation_relancee' : 'synchronisation_relance_echouee', $entree, $auteur, [], $charge);

            return [
                'ok' => $reussi,
                'motif' => $reussi ? null : (string) ($analyse['motif'] ?? ''),
                'issue' => $analyse['issue'],
            ];
        });
    }

    /** Marque l'opération comme traitée, sans la rejouer — le motif est exigé et tracé. */
    public function ignorer(string $id, string $motif, User $auteur): void
    {
        $entree = $this->entree($id);
        $this->exigerDroits($entree, $auteur);
        $motif = trim($motif);

        if ($motif === '') {
            throw new RuntimeException(__('synchronisation_journal.ecran.ignorer_motif_requis'));
        }

        DB::transaction(function () use ($id, $motif, $auteur): void {
            /** @var Journal $entree */
            $entree = Journal::query()->whereKey($id)->lockForUpdate()->firstOrFail();

            if (! $this->peutIgnorer($entree)) {
                throw new RuntimeException(__('synchronisation_journal.ecran.refus_non_modifiable'));
            }

            $entree->update([
                'traitement' => Journal::IGNORE,
                'traite_par' => $auteur->id,
                'traite_le' => now(),
                'motif_traitement' => mb_substr($motif, 0, 1000),
            ]);

            $this->tracer('synchronisation_ignoree', $entree, $auteur, [], null, $motif);
        });
    }

    // ------------------------------------------------------------------
    // Internes
    // ------------------------------------------------------------------

    private function entree(string $id): Journal
    {
        $entree = Journal::query()->find($id);

        if ($entree === null) {
            throw new RuntimeException(__('synchronisation_journal.ecran.refus_inconnue'));
        }

        return $entree;
    }

    private function exigerDroits(Journal $entree, User $auteur): void
    {
        $refus = $this->moduleRefuse($entree, $auteur);

        if ($refus === null) {
            return;
        }

        if ($refus === '') {
            throw new RefusSynchronisationException(__('synchronisation_journal.ecran.refus_role'));
        }

        // SECURITY_STRICT : toute tentative d'accès refusée est tracée.
        JournalSecurite::create([
            'type_evenement' => 'acces_refuse_rbac',
            'utilisateur_id' => $auteur->id,
            'adresse_ip' => request()->ip(),
            'module_concerne' => $refus,
        ]);

        throw new RefusSynchronisationException(__('synchronisation_journal.ecran.refus_droit', [
            'module' => \App\Pwa\Livewire\Transverse\RolesPermissions::MODULES[$refus] ?? $refus,
        ]), $refus);
    }

    /**
     * @param  array<string, mixed>  $charge
     * @return array{ok: bool, motif: ?string}
     */
    private function verifier(Journal $entree, array $charge): array
    {
        if (! $this->registre->estSynchronisable($entree->table_concernee)) {
            return ['ok' => false, 'motif' => __('synchronisation_journal.motifs.table_non_synchronisable.phrase')];
        }

        $operation = $this->operation($entree, $charge);
        $session = $this->session($entree);
        $niveau = DB::transactionLevel();
        $resultat = null;

        DB::beginTransaction();

        try {
            $resultat = $this->synchronisation->traiterOperation(
                $operation,
                $entree->poste_id,
                (string) $entree->utilisateur_id,
                $session,
                journaliser: false,
            );
        } catch (Throwable $e) {
            report($e);
            $resultat = ['statut' => 'rejete', 'motif' => __('synchronisation_journal.motifs.erreur_serveur.phrase')];
        } finally {
            // Tout ce que la vérification a écrit est annulé.
            while (DB::transactionLevel() > $niveau) {
                DB::rollBack();
            }
        }

        $analyse = $this->journal->analyser($operation, $resultat, $this->synchronisation->extrasDeLaDerniereOperation());

        if (in_array($analyse['issue'], [Journal::REJETEE, Journal::CONFLIT, Journal::ERREUR], true)) {
            return ['ok' => false, 'motif' => $this->phraseComplete($analyse)];
        }

        return ['ok' => true, 'motif' => null];
    }

    /** @param  array{motif: ?string, cause: ?string}  $analyse */
    private function phraseComplete(array $analyse): string
    {
        return trim((string) ($analyse['cause'] ?? '')) !== ''
            ? (string) $analyse['cause']
            : (string) ($analyse['motif'] ?? '');
    }

    /**
     * L'opération telle que le poste l'aurait envoyée, sous un NOUVEL
     * identifiant d'opération et avec l'horodatage de saisie d'origine.
     *
     * @param  array<string, mixed>  $charge
     * @return array<string, mixed>
     */
    private function operation(Journal $entree, array $charge): array
    {
        return [
            'uuid_operation' => (string) Str::uuid(),
            'table' => $entree->table_concernee,
            'type' => $entree->type_operation,
            'entite_id' => $entree->entite_id,
            'payload' => $charge,
            'horodatage_client' => ($entree->horodatage_poste ?? $entree->recu_le)->toIso8601String(),
        ];
    }

    /** La session du lot d'origine ; à défaut, une session de reprise. */
    private function session(Journal $entree): string
    {
        if ($entree->session_id !== null && SessionSynchronisation::query()->whereKey($entree->session_id)->exists()) {
            return (string) $entree->session_id;
        }

        return SessionSynchronisation::create([
            'poste_id' => $entree->poste_id,
            'date_sync' => now(),
            'nb_enregistrements' => 1,
            'conflits_detectes' => 0,
            'statut' => 'succes',
        ])->id;
    }

    /**
     * @param  array<array-key, mixed>  $valeurs
     * @return list<mixed>
     */
    private function feuilles(array $valeurs): array
    {
        $feuilles = [];

        array_walk_recursive($valeurs, static function (mixed $v) use (&$feuilles): void {
            $feuilles[] = $v;
        });

        return $feuilles;
    }

    /**
     * Les valeurs qui ont changé, chemin par chemin.
     *
     * @param  array<string, mixed>  $avant
     * @param  array<string, mixed>  $apres
     * @return array<string, array{avant: mixed, apres: mixed}>
     */
    private function difference(array $avant, array $apres): array
    {
        $a = [];
        $b = [];

        foreach ($this->champs($avant) as $champ) {
            $a[$champ['chemin']] = $champ['valeur'];
        }
        foreach ($this->champs($apres) as $champ) {
            $b[$champ['chemin']] = $champ['valeur'];
        }

        $diff = [];

        foreach (array_unique([...array_keys($a), ...array_keys($b)]) as $chemin) {
            if (($a[$chemin] ?? null) !== ($b[$chemin] ?? null)) {
                $diff[(string) $chemin] = ['avant' => $a[$chemin] ?? null, 'apres' => $b[$chemin] ?? null];
            }
        }

        return $diff;
    }

    /**
     * La trace d'audit de l'action : qui, quoi, sur quelle opération.
     *
     * @param  array<string, mixed>  $differences
     * @param  array<string, mixed>|null  $charge
     */
    private function tracer(string $action, Journal $entree, User $auteur, array $differences, ?array $charge, ?string $motif = null): void
    {
        JournalAudit::create([
            'id' => (string) Str::uuid(),
            'utilisateur_id' => $auteur->id,
            'action' => $action,
            'entite_concernee' => 'journal_reception_synchronisation',
            'entite_id' => $entree->id,
            'valeur_avant' => $differences === [] ? null : array_map(static fn (array $d): mixed => $d['avant'], $differences),
            'valeur_apres' => [
                'poste' => $entree->poste_id,
                'donnee' => $entree->table_concernee,
                'entite' => $entree->entite_id,
                'issue' => $entree->issue,
                ...($differences === [] ? [] : ['corrections' => array_map(static fn (array $d): mixed => $d['apres'], $differences)]),
                ...($motif !== null ? ['motif' => $motif] : []),
            ],
            'adresse_poste' => request()->ip(),
        ]);
    }
}
