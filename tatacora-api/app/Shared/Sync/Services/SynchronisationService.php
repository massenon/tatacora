<?php

declare(strict_types=1);

namespace App\Shared\Sync\Services;

use App\Domain\Hebergement\Services\ReservationService;
use App\Models\User;
use App\Shared\Integrite\Exceptions\ChevauchementDetecteException;
use App\Shared\Rbac\Models\JournalSecurite;
use App\Shared\Sync\Models\ConflitSynchronisation;
use App\Shared\Sync\Models\DeduplicationSynchronisation;
use App\Shared\Sync\Models\SessionSynchronisation;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use RuntimeException;

/**
 * Traitement d'un lot d'opérations de synchronisation — LARAVEL_SYNC_FLUTTER.md.
 *
 * ## Trois garanties, dans cet ordre de priorité
 *
 * 1. **Idempotence** (§5) — une opération déjà traitée retourne son résultat
 *    d'origine sans rien ré-exécuter. Sans cela, une coupure réseau après
 *    traitement mais avant réception de la réponse ferait créer deux fois la
 *    même réservation, ou compter deux fois une sortie de stock.
 * 2. **Isolation par opération** (§2.1) — chaque opération a sa propre
 *    transaction. Un rejet RG-01 sur la troisième opération d'un lot ne doit
 *    pas annuler les deux premières, déjà valides : le poste devrait alors
 *    tout rejouer, et l'utilisateur ne comprendrait pas pourquoi une saisie
 *    correcte a disparu.
 * 3. **Aucune perte financière silencieuse** (RG-17) — sur une table
 *    financière, jamais de résolution automatique, quel que soit l'horodatage.
 *
 * ## Ce que ce service ne fait pas
 *
 * Il ne pousse rien vers le client (pas de « pull »), ne gère pas les fichiers
 * joints (§7, endpoint dédié) et n'écrit que sur les tables déclarées dans
 * `TABLES_SYNCHRONISABLES`. Toute table absente de ce registre est refusée
 * explicitement : accepter une écriture sur une table inconnue reviendrait à
 * contourner les règles de gestion de son domaine.
 */
class SynchronisationService
{
    /** LARAVEL_SYNC_FLUTTER.md §7 — au-delà, le client découpe en lots. */
    public const TAILLE_LOT_MAX = 50;

    /** TTL de la mémoire d'idempotence, en jours (§5). */
    public const TTL_DEDUPLICATION_JOURS = 7;

    /**
     * Registre FERMÉ des tables acceptées en synchronisation, et du service de
     * domaine par lequel l'écriture doit passer.
     *
     * `null` signifie « écriture directe autorisée » : uniquement pour les
     * référentiels sans règle de gestion à l'écriture. Toute table portant une
     * RG doit nommer son service — sinon la synchronisation deviendrait le
     * chemin par lequel on contourne les règles.
     *
     * **Chaque table nomme aussi son module, et ce n'est pas facultatif**
     * (PA-65, 19/08/2026). Le raisonnement ci-dessus valait pour les RG ; il
     * vaut identiquement pour le RBAC, et il n'était pas appliqué : `/api/v1/sync`
     * ne porte aucun `VerifierAccesModule` — il ne peut pas, un lot étant
     * multi-modules par nature — et rien ne vérifiait les droits par opération.
     * Un `barman` (`M1 = '-'`) créait donc une réservation par ce chemin, alors
     * que `POST /hebergement/reservations` la lui refuse. Porter le module dans
     * le registre plutôt que dans une table parallèle rend l'oubli impossible :
     * on ne peut pas ajouter une table synchronisable sans déclarer qui a le
     * droit d'y écrire.
     *
     * @var array<string, array{module: string, service: class-string|null}>
     */
    public const TABLES_SYNCHRONISABLES = [
        'reservations' => ['module' => 'M1', 'service' => ReservationService::class],
        'clients' => ['module' => 'M3', 'service' => null],
    ];

    public function __construct(
        private readonly ClassificationConflitService $classification,
        private readonly ReservationService $reservations,
    ) {
    }

    /**
     * Utilisateurs deja resolus, pour ne pas interroger la base a chaque
     * operation d'un lot qui en compte cinquante.
     *
     * @var array<string, User|null>
     */
    private array $utilisateurs = [];

    /**
     * @param  list<array<string, mixed>>  $operations
     * @return array{session_id: string, resultats: list<array<string, mixed>>}
     */
    public function traiterLot(string $posteId, array $operations, string $utilisateurId): array
    {
        $session = SessionSynchronisation::create([
            'poste_id' => $posteId,
            'date_sync' => now(),
            'nb_enregistrements' => count($operations),
            'conflits_detectes' => 0,
            'statut' => 'succes',
        ]);

        $resultats = [];
        $conflits = 0;
        $echecs = 0;

        foreach ($operations as $operation) {
            $resultat = $this->traiterOperation($operation, $posteId, $utilisateurId, $session->id);

            $resultats[] = $resultat;
            $conflits += $resultat['statut'] === 'conflit' ? 1 : 0;
            $echecs += $resultat['statut'] === 'rejete' ? 1 : 0;
        }

        $session->update([
            'conflits_detectes' => $conflits,
            'statut' => match (true) {
                $echecs === count($operations) && $echecs > 0 => 'echec',
                $echecs > 0 || $conflits > 0 => 'partiel',
                default => 'succes',
            },
        ]);

        return ['session_id' => $session->id, 'resultats' => $resultats];
    }

    /**
     * @param  array<string, mixed>  $operation
     * @return array<string, mixed>
     */
    public function traiterOperation(array $operation, string $posteId, string $utilisateurId, string $sessionId): array
    {
        $uuidOperation = (string) $operation['uuid_operation'];

        // §5 — idempotence AVANT toute logique métier.
        if ($dejaTraite = $this->resultatDejaObtenu($uuidOperation)) {
            return $dejaTraite;
        }

        $table = (string) $operation['table'];

        if (! array_key_exists($table, self::TABLES_SYNCHRONISABLES)) {
            return $this->memoriser($operation, $posteId, $utilisateurId, [
                'uuid_operation' => $uuidOperation,
                'statut' => 'rejete',
                'entite_id' => (string) $operation['entite_id'],
                'motif' => __('sync.table_non_synchronisable', ['table' => $table]),
            ]);
        }

        // RBAC par operation — 2e niveau, applique ici faute de pouvoir l'etre
        // sur la route (PA-65). Un lot est multi-modules par nature : un seul
        // `VerifierAccesModule` sur `/api/v1/sync` serait soit trop laxiste,
        // soit bloquant pour un lot legitime.
        //
        // Le refus porte sur l'OPERATION, pas sur le lot : echouer le lot
        // entier ferait perdre a un utilisateur legitime les operations qu'il
        // avait le droit de pousser, a cause d'une seule qu'il n'avait pas.
        //
        // Et il est DEFINITIF (`rejete`, jamais `conflit`) : rejouer n'accorde
        // pas de droits. Le client le retire de sa file avec son motif, ce qui
        // est le comportement voulu — au contraire d'un bogue serveur, qui doit
        // remonter en 500 pour etre rejoue plus tard.
        if (! $this->droitEcriture($utilisateurId, $table)) {
            return $this->memoriser($operation, $posteId, $utilisateurId, [
                'uuid_operation' => $uuidOperation,
                'statut' => 'rejete',
                'entite_id' => (string) $operation['entite_id'],
                'motif' => __('auth.module_refuse'),
            ]);
        }

        try {
            $resultat = DB::transaction(
                fn (): array => $this->appliquer($operation, $posteId, $sessionId, $table),
            );
        } catch (ChevauchementDetecteException $e) {
            // §4.2, catégorie structurelle : ce n'est pas un conflit de versions
            // mais un rejet — deux enregistrements distincts qui ne peuvent pas
            // coexister (RG-01/RG-08/RG-13).
            $resultat = [
                'uuid_operation' => $uuidOperation,
                'statut' => 'rejete',
                'entite_id' => (string) $operation['entite_id'],
                'motif' => $e->getMessage(),
                'entites_en_conflit' => $e->identifiantsEnConflit,
            ];
        } catch (RuntimeException $e) {
            // UNIQUEMENT les refus métier. Le message est transmis au client :
            // §2.2 exige que l'application informe l'utilisateur clairement,
            // pas par une erreur technique brute.
            $resultat = [
                'uuid_operation' => $uuidOperation,
                'statut' => 'rejete',
                'entite_id' => (string) $operation['entite_id'],
                'motif' => $e->getMessage(),
            ];
        }

        // Toute autre exception — bogue de programmation, panne de base — se
        // propage volontairement.
        //
        // La capturer pour la renvoyer en `rejete` serait le pire comportement
        // possible : le client marquerait l'opération comme DÉFINITIVEMENT
        // refusée et la retirerait de sa file. Une saisie hors connexion
        // parfaitement valide serait perdue à cause d'un bogue serveur, sans
        // que personne ne s'en aperçoive. Ce cas s'est produit pendant le
        // développement — un `use` manquant est remonté au client sous la forme
        // « votre réservation a été refusée ».
        //
        // En laissant l'exception remonter, la requête échoue en 500, le client
        // rejoue plus tard, et l'idempotence (§5) protège les opérations du
        // même lot déjà traitées.

        return $this->memoriser($operation, $posteId, $utilisateurId, $resultat);
    }

    /**
     * L'utilisateur a-t-il le droit d'ECRIRE dans le module de cette table ?
     *
     * Toute operation de synchronisation est une ecriture (`creation` ou
     * `modification`, seuls types acceptes par `SynchroniserRequest`) : le
     * niveau requis est donc toujours `C`, jamais `L`.
     *
     * Le niveau est lu par `User::niveauSurModule()`, la meme source que
     * `VerifierAccesModule` — reecrire le calcul ici ferait diverger les deux
     * chemins le jour ou la matrice changerait.
     */
    private function droitEcriture(string $utilisateurId, string $table): bool
    {
        $module = self::TABLES_SYNCHRONISABLES[$table]['module'];

        $utilisateur = $this->utilisateurs[$utilisateurId] ??= User::find($utilisateurId);

        if (! $utilisateur instanceof User || ! $utilisateur->estActif()) {
            return false;
        }

        if ($utilisateur->niveauSurModule($module) === 'C') {
            return true;
        }

        // SECURITY_STRICT.md §10 — toute tentative d'acces refusee est tracee
        // dans `journal_securite`, distinct du journal d'audit metier. Une
        // tentative par la synchronisation merite la meme trace qu'une tentative
        // par une route : c'est le meme geste, par une autre porte.
        JournalSecurite::create([
            'type_evenement' => 'acces_refuse_rbac',
            'utilisateur_id' => $utilisateur->id,
            'adresse_ip' => request()->ip(),
            'module_concerne' => $module,
        ]);

        return false;
    }

    /**
     * @param  array<string, mixed>  $operation
     * @return array<string, mixed>
     */
    private function appliquer(array $operation, string $posteId, string $sessionId, string $table): array
    {
        $entiteId = (string) $operation['entite_id'];
        /** @var array<string, mixed> $payload */
        $payload = $operation['payload'];
        $horodatageClient = Carbon::parse((string) $operation['horodatage_client']);

        $existant = DB::table($table)->where('id', $entiteId)->first();

        if ($existant === null) {
            return $this->creer($table, $entiteId, $payload, $operation);
        }

        // §4.1 — conflit si l'enregistrement a été modifié côté serveur APRÈS
        // l'horodatage de saisie du client, par un AUTRE poste.
        if (! $this->estEnConflit($existant, $horodatageClient, $posteId)) {
            return $this->mettreAJour($table, $entiteId, $payload, $operation);
        }

        return $this->traiterConflit($table, $entiteId, $payload, $existant, $operation, $sessionId, $horodatageClient);
    }

    /**
     * @param  array<string, mixed>  $payload
     * @param  array<string, mixed>  $operation
     * @return array<string, mixed>
     */
    private function creer(string $table, string $entiteId, array $payload, array $operation): array
    {
        $service = self::TABLES_SYNCHRONISABLES[$table]['service'];

        if ($service === ReservationService::class) {
            // Passage OBLIGATOIRE par le service : c'est lui qui porte le verrou
            // de RG-01. Une insertion directe ici ferait de la synchronisation
            // le seul chemin par lequel une double-réservation devient possible
            // — précisément le scénario que RG-01 existe pour empêcher.
            $this->reservations->creer([...$payload, 'id' => $entiteId]);
        } else {
            DB::table($table)->insert([...$payload, 'id' => $entiteId]);
        }

        return [
            'uuid_operation' => (string) $operation['uuid_operation'],
            'statut' => 'synchronise',
            'entite_id' => $entiteId,
        ];
    }

    /**
     * @param  array<string, mixed>  $payload
     * @param  array<string, mixed>  $operation
     * @return array<string, mixed>
     */
    private function mettreAJour(string $table, string $entiteId, array $payload, array $operation): array
    {
        $this->ecrire($table, $entiteId, $payload);

        return [
            'uuid_operation' => (string) $operation['uuid_operation'],
            'statut' => 'synchronise',
            'entite_id' => $entiteId,
        ];
    }

    /**
     * @param  array<string, mixed>  $payload
     * @param  array<string, mixed>  $operation
     * @return array<string, mixed>
     */
    private function traiterConflit(
        string $table,
        string $entiteId,
        array $payload,
        object $existant,
        array $operation,
        string $sessionId,
        Carbon $horodatageClient,
    ): array {
        $versionServeur = (array) $existant;
        $automatique = $this->classification->autoriseResolutionAutomatique($table);

        $conflit = ConflitSynchronisation::create([
            'session_id' => $sessionId,
            'table_concernee' => $table,
            'entite_id' => $entiteId,
            'version_locale' => $payload,
            'version_serveur' => $versionServeur,
            // Table financière : arbitrage manuel obligatoire (RG-17).
            // Table non-financière : résolue ici, mais la version perdante est
            // conservée — jamais écrasée sans trace (§4.2).
            'statut' => $automatique ? 'resolu_local' : 'en_attente_arbitrage',
        ]);

        if (! $automatique) {
            return [
                'uuid_operation' => (string) $operation['uuid_operation'],
                'statut' => 'conflit',
                'entite_id' => $entiteId,
                'type_conflit' => 'financier_arbitrage_requis',
                'conflit_id' => $conflit->id,
            ];
        }

        // Last-write-wins par horodatage CLIENT (§4.2) — on compare deux dates
        // de SAISIE, jamais une saisie à une date de réception serveur.
        //
        // Sans cela : le poste A saisit à 10 h et synchronise à 14 h ; le poste
        // B saisit à 11 h et synchronise à 14 h 05. B est plus récent en saisie
        // et doit gagner — comparer son horodatage à la date de modification
        // serveur (14 h) ferait gagner A. C'est le scénario normal du guide
        // revenu de circuit, pas un cas de bord.
        // À défaut de saisie antérieure connue — entité créée directement par
        // l'API, jamais passée par la synchronisation — on retombe sur la date
        // de modification serveur. Dans le doute sur la provenance, on ne
        // remplace pas une donnée serveur par une donnée plus ancienne.
        $reference = $this->horodatageSaisiePrecedente($entiteId)
            ?? $this->dateModificationServeur($existant);

        if ($reference !== null && $horodatageClient->lessThan($reference)) {
            $conflit->update(['statut' => 'resolu_serveur']);

            return [
                'uuid_operation' => (string) $operation['uuid_operation'],
                'statut' => 'synchronise',
                'entite_id' => $entiteId,
                'resolution' => 'version_serveur_conservee',
                'conflit_id' => $conflit->id,
            ];
        }

        $this->ecrire($table, $entiteId, $payload);

        return [
            'uuid_operation' => (string) $operation['uuid_operation'],
            'statut' => 'synchronise',
            'entite_id' => $entiteId,
            'resolution' => 'version_locale_conservee',
            'conflit_id' => $conflit->id,
        ];
    }

    /**
     * Écriture d'une modification synchronisée, horodatage de suivi compris.
     *
     * Le query builder ne touche PAS aux colonnes d'horodatage, contrairement à
     * Eloquent. Sans cette avance explicite, l'entité paraîtrait ne plus jamais
     * avoir été modifiée après sa première synchronisation — et §4.1, qui
     * détecte les conflits par comparaison à la date de modification serveur,
     * cesserait d'en détecter un seul. Le bug est silencieux : tout continue de
     * fonctionner, les conflits disparaissent simplement des radars.
     *
     * @param  array<string, mixed>  $payload
     */
    private function ecrire(string $table, string $entiteId, array $payload): void
    {
        foreach (['date_modification', 'updated_at'] as $colonne) {
            if ($this->colonneExiste($table, $colonne)) {
                $payload[$colonne] = now();
            }
        }

        DB::table($table)->where('id', $entiteId)->update($payload);
    }

    private function colonneExiste(string $table, string $colonne): bool
    {
        // Mémorisé par requête : Schema::hasColumn interroge la base à chaque
        // appel, et la synchronisation traite jusqu'à 50 opérations par lot.
        static $connues = [];

        return $connues[$table][$colonne] ??= Schema::hasColumn($table, $colonne);
    }

    private function estEnConflit(object $existant, Carbon $horodatageClient, string $posteId): bool
    {
        $dateServeur = $this->dateModificationServeur($existant);

        if ($dateServeur === null) {
            return false;
        }

        // Le poste d'origine n'entre pas en conflit avec lui-même : rejouer sa
        // propre modification n'est pas une divergence.
        $posteServeur = property_exists($existant, 'poste_id') ? (string) $existant->poste_id : null;

        if ($posteServeur !== null && $posteServeur === $posteId) {
            return false;
        }

        return $dateServeur->greaterThan($horodatageClient);
    }

    /**
     * Horodatage de saisie du dernier poste ayant écrit cette entité par
     * synchronisation.
     *
     * La collection documentaire ne prévoit nulle part où conserver cette
     * donnée, alors que §4.2 en dépend — écart signalé en PA-44. Elle est donc
     * lue depuis la mémoire d'idempotence, qui la porte pour cet usage.
     *
     * Retourne `null` si l'entité n'a jamais été écrite par synchronisation
     * (créée directement par l'API) : aucune saisie antérieure à comparer.
     */
    private function horodatageSaisiePrecedente(string $entiteId): ?Carbon
    {
        // Seules comptent les opérations RÉELLEMENT APPLIQUÉES. Une opération
        // rejetée (RG-01) ou perdue en arbitrage n'a pas produit l'état
        // serveur courant : la retenir comme « dernière saisie » ferait perdre
        // une saisie plus récente contre une version qui n'a jamais existé.
        $candidates = DeduplicationSynchronisation::where('entite_id', $entiteId)
            ->whereNotNull('horodatage_client')
            ->orderByDesc('horodatage_client')
            ->get(['resultat', 'horodatage_client']);

        foreach ($candidates as $candidate) {
            $resultat = $candidate->resultat;

            $appliquee = ($resultat['statut'] ?? null) === 'synchronise'
                && ($resultat['resolution'] ?? null) !== 'version_serveur_conservee';

            if ($appliquee) {
                return Carbon::parse((string) $candidate->horodatage_client);
            }
        }

        return null;
    }

    private function dateModificationServeur(object $existant): ?Carbon
    {
        foreach (['date_modification', 'updated_at'] as $colonne) {
            if (property_exists($existant, $colonne) && $existant->{$colonne} !== null) {
                return Carbon::parse((string) $existant->{$colonne});
            }
        }

        return null;
    }

    /**
     * @return array<string, mixed>|null
     */
    private function resultatDejaObtenu(string $uuidOperation): ?array
    {
        $memoire = DeduplicationSynchronisation::where('uuid_operation', $uuidOperation)->first();

        if ($memoire === null) {
            return null;
        }

        // Le résultat d'origine est restitué tel quel, y compris un rejet : le
        // client doit obtenir la même réponse au rejeu qu'au premier envoi.
        return [...$memoire->resultat, 'rejeu_idempotent' => true];
    }

    /**
     * @param  array<string, mixed>  $operation
     * @param  array<string, mixed>  $resultat
     * @return array<string, mixed>
     */
    private function memoriser(array $operation, string $posteId, string $utilisateurId, array $resultat): array
    {
        DeduplicationSynchronisation::create([
            'uuid_operation' => (string) $operation['uuid_operation'],
            'utilisateur_id' => $utilisateurId,
            'poste_id' => $posteId,
            'table_concernee' => (string) $operation['table'],
            'entite_id' => (string) $operation['entite_id'],
            'resultat' => $resultat,
            // Conservé pour arbitrer les conflits futurs sur cette entité (§4.2).
            'horodatage_client' => $operation['horodatage_client'] ?? null,
            'date_traitement' => now(),
        ]);

        return $resultat;
    }

    /**
     * Purge de la mémoire d'idempotence — appelée par
     * `NettoyerDeduplicationSyncJob` (LISTE_DES_CRON_JOBS_CPANEL.md).
     */
    public function purgerDeduplication(): int
    {
        return DeduplicationSynchronisation::where(
            'date_traitement',
            '<',
            now()->subDays(self::TTL_DEDUPLICATION_JOURS),
        )->delete();
    }
}
