<?php

declare(strict_types=1);

namespace App\Shared\Sync\Services;

use App\Shared\Sync\Models\JournalReceptionSynchronisation as Journal;
use Illuminate\Contracts\Database\Eloquent\Builder as BuilderContrat;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Carbon;
use Throwable;

/**
 * Le journal de RÉCEPTION : ce que le serveur reçoit de chaque poste par
 * `POST /api/v1/sync` — demande du PO du 26/10/2026 (« identifier la CAUSE
 * des échecs, corriger et relancer »).
 *
 * Seul auteur, avec `CorrectionReceptionService`, de
 * `journal_reception_synchronisation`. Il RÉUTILISE ce que le moteur sait déjà
 * au lieu de le recalculer : le résultat rendu au poste (statut, motif,
 * `fusionne_avec`, `anomalies`, `document_deja_enregistre`, `resolution`) et
 * le code de motif posé par `SynchronisationService::rejet()`. Les écarts
 * signalés restent dans `anomalies_synchronisation` ; ici, on n'en garde que
 * les codes.
 *
 * ## Une ligne par `uuid_operation`
 *
 * Un renvoi du même `uuid_operation` (coupure avant la réponse) ne crée pas de
 * seconde ligne : il incrémente `tentatives`. L'issue d'origine reste celle du
 * premier traitement — c'est elle que la mémoire d'idempotence rend.
 *
 * ## Un échec de journalisation ne fait JAMAIS échouer la synchronisation
 *
 * Le journal est une trace de lecture : si son écriture échoue (base
 * indisponible, colonne trop courte), l'erreur est signalée (`report`) et
 * l'opération garde son résultat.
 */
class JournalReceptionService
{
    /** Durée de conservation d'une ligne sans suite à donner. */
    public const RETENTION_JOURS = 90;

    /** Durée de conservation d'une ligne qui attend encore un humain. */
    public const RETENTION_A_TRAITER_JOURS = 365;

    /**
     * La « table » sous laquelle le dépôt d'un reçu de dépense (fichier, pas un
     * document du protocole) est consigné. Elle n'est pas au registre des
     * gestionnaires : rien n'est à corriger ni à rejouer côté serveur, le poste
     * renvoie un fichier valable (lot L4, 27/10/2026).
     */
    public const TABLE_RECUS_DEPENSES = 'recus_depenses';

    /** Les clés de la charge dont la valeur n'est jamais conservée. */
    private const CLES_SECRETES = '/mot_de_passe|secret|jeton|token|password/i';

    /**
     * Enregistre (ou met à jour, en cas de renvoi) l'opération reçue.
     *
     * @param  array<string, mixed>  $operation  l'opération du lot, telle que reçue
     * @param  array<string, mixed>  $resultat  la réponse rendue au poste
     * @param  array{exception?: class-string|null, module?: string|null, detail?: string|null}  $extras
     */
    public function enregistrer(
        array $operation,
        string $posteId,
        string $utilisateurId,
        ?string $sessionId,
        array $resultat,
        array $extras = [],
        ?Throwable $erreur = null,
    ): void {
        try {
            $this->ecrire($operation, $posteId, $utilisateurId, $sessionId, $resultat, $extras, $erreur);
        } catch (Throwable $e) {
            report($e);
        }
    }

    /**
     * @param  array<string, mixed>  $operation
     * @param  array<string, mixed>  $resultat
     * @param  array<string, mixed>  $extras
     */
    private function ecrire(
        array $operation,
        string $posteId,
        string $utilisateurId,
        ?string $sessionId,
        array $resultat,
        array $extras,
        ?Throwable $erreur,
    ): void {
        $uuid = (string) $operation['uuid_operation'];
        $maintenant = now();
        $existant = Journal::query()->where('uuid_operation', $uuid)->first();

        if ($existant !== null) {
            $tentative = ['tentatives' => $existant->tentatives + 1, 'derniere_tentative_le' => $maintenant];

            // Un renvoi après une ERREUR du serveur est un vrai second
            // traitement : son issue remplace l'erreur.
            if ($existant->issue === Journal::ERREUR && $erreur === null && ($resultat['rejeu_idempotent'] ?? false) !== true) {
                $analyse = $this->analyser($operation, $resultat, $extras, null);
                $existant->fill([...$analyse, ...$this->traitementInitial($analyse['issue'], (string) $operation['table']), ...$tentative])->save();

                return;
            }

            $existant->update($tentative);

            return;
        }

        $analyse = $this->analyser($operation, $resultat, $extras, $erreur);

        Journal::create([
            'uuid_operation' => $uuid,
            'session_id' => $sessionId,
            'poste_id' => $posteId,
            'utilisateur_id' => $utilisateurId,
            'table_concernee' => (string) $operation['table'],
            'entite_id' => (string) $operation['entite_id'],
            'type_operation' => (string) $operation['type'],
            'horodatage_poste' => $this->date($operation['horodatage_client'] ?? null),
            'recu_le' => $maintenant,
            'tentatives' => 1,
            'derniere_tentative_le' => $maintenant,
            'payload' => $this->charge($operation),
            ...$analyse,
            ...$this->traitementInitial($analyse['issue'], (string) $operation['table']),
        ]);
    }

    /**
     * Une issue qui attend un humain naît « à traiter ».
     *
     * @return array{traitement: ?string}
     */
    private function traitementInitial(string $issue, string $table): array
    {
        // Un dépôt de fichier refusé n'attend aucun humain côté serveur.
        if ($table === self::TABLE_RECUS_DEPENSES) {
            return ['traitement' => null];
        }

        return ['traitement' => in_array($issue, Journal::ISSUES_A_TRAITER, true) ? Journal::A_TRAITER : null];
    }

    /**
     * L'issue, le motif structuré et la cause d'une opération.
     *
     * @param  array<string, mixed>  $operation
     * @param  array<string, mixed>  $resultat
     * @param  array<string, mixed>  $extras
     * @return array{issue: string, code_motif: ?string, motif: ?string, cause: ?string, details: ?array<string, mixed>}
     */
    public function analyser(array $operation, array $resultat, array $extras = [], ?Throwable $erreur = null): array
    {
        $table = (string) ($operation['table'] ?? '');
        $details = [];

        if ($extras['exception'] ?? null) {
            $details['exception'] = class_basename((string) $extras['exception']);
        }

        if ($erreur !== null) {
            return [
                'issue' => Journal::ERREUR,
                'code_motif' => 'erreur_serveur',
                'motif' => __('synchronisation_journal.motifs.erreur_serveur.phrase'),
                'cause' => __('synchronisation_journal.motifs.erreur_serveur.cause'),
                'details' => ['exception' => class_basename($erreur), 'message' => mb_substr($erreur->getMessage(), 0, 500)],
            ];
        }

        $statut = (string) ($resultat['statut'] ?? '');

        if ($statut === 'rejete') {
            $code = (string) ($resultat['code_motif'] ?? 'regle_metier');
            $phrase = (string) ($resultat['motif'] ?? '');

            if (is_array($resultat['erreurs'] ?? null)) {
                $details['erreurs'] = $resultat['erreurs'];
            }
            if (is_array($resultat['entites_en_conflit'] ?? null)) {
                $details['entites_en_conflit'] = $resultat['entites_en_conflit'];
            }
            if (($extras['module'] ?? null) !== null) {
                $details['module'] = $extras['module'];
            }

            return [
                'issue' => Journal::REJETEE,
                'code_motif' => $code,
                'motif' => $phrase !== '' ? $phrase : $this->phraseDuMotif($code),
                'cause' => $this->cause($code, $table, $phrase, $details),
                'details' => $details === [] ? null : $details,
            ];
        }

        if ($statut === 'conflit') {
            $details['conflit_id'] = $resultat['conflit_id'] ?? null;

            return [
                'issue' => Journal::CONFLIT,
                'code_motif' => 'conflit_financier',
                'motif' => $this->phraseDuMotif('conflit_financier'),
                'cause' => $this->cause('conflit_financier', $table, '', $details),
                'details' => $details,
            ];
        }

        $anomalies = $this->codesAnomalies($resultat);

        if (($resultat['resolution'] ?? null) === 'version_serveur_conservee') {
            return $this->issueSansEchec(Journal::CONSERVEE, 'version_serveur_conservee', $table, $details + ['conflit_id' => $resultat['conflit_id'] ?? null]);
        }

        if ($anomalies !== []) {
            return [
                'issue' => Journal::SIGNALEE,
                'code_motif' => $anomalies[0],
                'motif' => $this->libelleAnomalie($anomalies[0]),
                'cause' => implode(' ; ', array_map($this->libelleAnomalie(...), $anomalies)) . '.',
                'details' => $details + ['anomalies' => $anomalies],
            ];
        }

        if (($resultat['document_deja_enregistre'] ?? false) === true || ($resultat['rejeu_idempotent'] ?? false) === true) {
            return $this->issueSansEchec(
                Journal::DUPLIQUEE,
                ($resultat['rejeu_idempotent'] ?? false) === true ? 'rejeu' : 'document_deja_enregistre',
                $table,
                $details,
            );
        }

        if (isset($resultat['fusionne_avec'])) {
            return $this->issueSansEchec(Journal::FUSIONNEE, 'fusion', $table, $details + ['fusionne_avec' => $resultat['fusionne_avec']]);
        }

        return ['issue' => Journal::ACCEPTEE, 'code_motif' => null, 'motif' => null, 'cause' => null, 'details' => $details === [] ? null : $details];
    }

    /**
     * @param  array<string, mixed>  $details
     * @return array{issue: string, code_motif: ?string, motif: ?string, cause: ?string, details: ?array<string, mixed>}
     */
    private function issueSansEchec(string $issue, string $code, string $table, array $details): array
    {
        $details = array_filter($details, static fn ($v): bool => $v !== null);

        return [
            'issue' => $issue,
            'code_motif' => $code,
            'motif' => $this->phraseDuMotif($code),
            'cause' => $this->cause($code, $table, '', $details),
            'details' => $details === [] ? null : $details,
        ];
    }

    /** @param  array<string, mixed>  $resultat  @return list<string> */
    private function codesAnomalies(array $resultat): array
    {
        $codes = [];

        foreach ((array) ($resultat['anomalies'] ?? []) as $code) {
            if (is_string($code) && ! in_array($code, $codes, true)) {
                $codes[] = $code;
            }
        }

        if (($resultat['statut'] ?? null) === 'cloture_sans_session_serveur' && ! in_array('cloture_session_inconnue', $codes, true)) {
            $codes[] = 'cloture_session_inconnue';
        }

        return $codes;
    }

    /** Le libellé d'une anomalie ; un code inconnu est rendu tel quel, jamais deviné. */
    public function libelleAnomalie(string $code): string
    {
        $cle = 'synchronisation_journal.anomalies.' . $code;
        $texte = __($cle);

        return $texte === $cle ? $code : $texte;
    }

    public function phraseDuMotif(string $code): string
    {
        $cle = 'synchronisation_journal.motifs.' . $code . '.phrase';
        $texte = __($cle);

        return $texte === $cle ? __('synchronisation_journal.motifs.regle_metier.phrase') : $texte;
    }

    /**
     * La cause expliquée en français, avec ce qu'il faut faire.
     *
     * @param  array<string, mixed>  $details
     */
    public function cause(string $code, string $table, string $phrase, array $details = []): string
    {
        $cle = 'synchronisation_journal.motifs.' . $code . '.cause';
        $modele = __($cle);

        if ($modele === $cle) {
            $modele = __('synchronisation_journal.motifs.regle_metier.cause');
        }

        $detail = $phrase;

        if ($code === 'donnees_invalides' && is_array($details['erreurs'] ?? null)) {
            $morceaux = [];
            foreach ($details['erreurs'] as $champ => $messages) {
                $morceaux[] = $this->libelleChamp((string) $champ) . ' : ' . implode(' ', (array) $messages);
            }
            $detail = implode(' ; ', $morceaux);
            $detail = $detail === '' ? $phrase : $detail . '.';
        }

        $module = (string) ($details['module'] ?? '');

        return strtr($modele, [
            ':module' => \App\Pwa\Livewire\Transverse\RolesPermissions::MODULES[$module] ?? $module,
            ':table' => $this->libelleTable($table),
            ':detail' => $detail,
        ]);
    }

    public function libelleTable(string $table): string
    {
        $cle = 'synchronisation_journal.tables.' . $table;
        $texte = __($cle);

        return $texte === $cle ? ucfirst(str_replace('_', ' ', $table)) : $texte;
    }

    public function libelleChamp(string $champ): string
    {
        $dernier = (string) (preg_match('/([^.]+)$/', $champ, $m) === 1 ? $m[1] : $champ);
        $cle = 'synchronisation_journal.champs.' . $dernier;
        $texte = __($cle);
        $base = $texte === $cle ? ucfirst(str_replace('_', ' ', $dernier)) : $texte;

        if (preg_match('/^lignes\.(\d+)\./', $champ, $ligne) === 1) {
            return __('synchronisation_journal.ecran.ligne_numero', ['n' => (int) $ligne[1] + 1]) . ' — ' . $base;
        }

        return $base;
    }

    /**
     * La charge conservée, privée de toute valeur secrète.
     *
     * @param  array<string, mixed>  $operation
     * @return array<string, mixed>|null
     */
    private function charge(array $operation): ?array
    {
        $payload = $operation['payload'] ?? null;

        if (! is_array($payload)) {
            return null;
        }

        return $this->masquer($payload);
    }

    /**
     * @param  array<array-key, mixed>  $valeurs
     * @return array<array-key, mixed>
     */
    private function masquer(array $valeurs): array
    {
        foreach ($valeurs as $cle => $valeur) {
            if (is_array($valeur)) {
                $valeurs[$cle] = $this->masquer($valeur);
            } elseif (is_string($cle) && preg_match(self::CLES_SECRETES, $cle) === 1) {
                $valeurs[$cle] = '***';
            }
        }

        return $valeurs;
    }

    private function date(mixed $valeur): ?Carbon
    {
        try {
            return $valeur === null ? null : Carbon::parse((string) $valeur);
        } catch (Throwable) {
            return null;
        }
    }

    // ------------------------------------------------------------------
    // Lecture
    // ------------------------------------------------------------------

    /**
     * `tables` restreint aux données que le lecteur a le droit de lire
     * (`null` = toutes).
     *
     * @param  array{poste?: ?string, table?: ?string, issue?: ?string, periode?: ?string, a_traiter?: bool, tables?: list<string>|null}  $filtres
     * @return Builder<Journal>
     */
    public function requete(array $filtres = []): Builder
    {
        $depuis = match ($filtres['periode'] ?? 'toutes') {
            'aujourdhui' => now()->startOfDay(),
            '7j' => now()->subDays(7)->startOfDay(),
            '30j' => now()->subDays(30)->startOfDay(),
            default => null,
        };

        return Journal::query()
            ->when(($filtres['poste'] ?? '') !== '' && ($filtres['poste'] ?? null) !== null, static fn (Builder $q) => $q->where('poste_id', $filtres['poste']))
            ->when(($filtres['table'] ?? '') !== '' && ($filtres['table'] ?? null) !== null, static fn (Builder $q) => $q->where('table_concernee', $filtres['table']))
            ->when(($filtres['issue'] ?? '') !== '' && ($filtres['issue'] ?? null) !== null, static function (Builder $q) use ($filtres): void {
                // « Déjà reçue » = le document redit sous un autre numéro OU le même renvoyé.
                if ($filtres['issue'] === Journal::DUPLIQUEE) {
                    $q->where(static fn (BuilderContrat $w) => $w->where('issue', Journal::DUPLIQUEE)->orWhere('tentatives', '>', 1));

                    return;
                }
                $q->where('issue', $filtres['issue']);
            })
            ->when(isset($filtres['tables']), static fn (Builder $q) => $q->whereIn('table_concernee', $filtres['tables']))
            ->when($depuis !== null, static fn (Builder $q) => $q->where('recu_le', '>=', $depuis))
            ->when(($filtres['a_traiter'] ?? false) === true, static fn (Builder $q) => $q->whereIn('traitement', [Journal::A_TRAITER, Journal::CORRIGE]));
    }

    /**
     * Les compteurs de l'en-tête, sur les mêmes critères de poste, de donnée
     * et de période (pas d'issue : chaque compteur EST une issue).
     *
     * @param  array{poste?: ?string, table?: ?string, periode?: ?string, tables?: list<string>|null}  $filtres
     * @return array{total: int, acceptees: int, a_traiter: int, rejetees: int, rejeux: int, signalees: int}
     */
    public function compteurs(array $filtres = []): array
    {
        $base = $this->requete([...$filtres, 'issue' => null, 'a_traiter' => false]);

        return [
            'total' => (clone $base)->count(),
            'acceptees' => (clone $base)->whereIn('issue', [Journal::ACCEPTEE, Journal::FUSIONNEE, Journal::CONSERVEE])->count(),
            'a_traiter' => (clone $base)->whereIn('traitement', [Journal::A_TRAITER, Journal::CORRIGE])->count(),
            'rejetees' => (clone $base)->whereIn('issue', [Journal::REJETEE, Journal::ERREUR, Journal::CONFLIT])->count(),
            'rejeux' => (clone $base)->where(static fn (BuilderContrat $w) => $w->where('issue', Journal::DUPLIQUEE)->orWhere('tentatives', '>', 1))->count(),
            'signalees' => (clone $base)->where('issue', Journal::SIGNALEE)->count(),
        ];
    }

    /**
     * Rétention bornée : les lignes sans suite à donner après
     * `RETENTION_JOURS`, celles qui attendent encore un humain après
     * `RETENTION_A_TRAITER_JOURS`. Appelée par `NettoyerDeduplicationSyncJob`.
     */
    public function purger(): int
    {
        $sansSuite = Journal::query()
            ->where('recu_le', '<', now()->subDays(self::RETENTION_JOURS))
            ->where(static fn (BuilderContrat $w) => $w->whereNull('traitement')->orWhereIn('traitement', [Journal::RELANCE, Journal::IGNORE]))
            ->delete();

        $anciennes = Journal::query()
            ->where('recu_le', '<', now()->subDays(self::RETENTION_A_TRAITER_JOURS))
            ->delete();

        return $sansSuite + $anciennes;
    }
}
