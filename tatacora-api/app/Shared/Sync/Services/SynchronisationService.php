<?php

declare(strict_types=1);

namespace App\Shared\Sync\Services;

use App\Models\User;
use App\Shared\Integrite\Exceptions\ChevauchementDetecteException;
use App\Shared\Rbac\Models\JournalSecurite;
use App\Shared\Sync\Contracts\GestionnaireSynchronisation;
use App\Shared\Sync\Exceptions\DonneesSynchroniseesInvalidesException;
use App\Shared\Sync\Models\ConflitSynchronisation;
use App\Shared\Sync\Models\DeduplicationSynchronisation;
use App\Shared\Sync\Models\SessionSynchronisation;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use App\Shared\Sync\Support\OrigineDocuments;
use Carbon\Exceptions\InvalidFormatException;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
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
 * joints (§7, endpoint dédié) et **n'écrit RIEN lui-même** : depuis le
 * 15/10/2026, chaque table du registre `TABLES_SYNCHRONISABLES`
 * (`RegistreSynchronisation`) a son gestionnaire, qui écrit par son service de
 * domaine ou refuse. Le moteur garde ce qui est commun à toutes les tables —
 * idempotence, RBAC par opération, cohérence du type annoncé, traduction des
 * identifiants fusionnés, détection et arbitrage des conflits (RG-17) — et
 * délègue l'écriture. L'ancien repli `DB::table($table)->insert/update($payload)`
 * a disparu : c'était le chemin par lequel la synchronisation contournait les
 * règles de gestion qu'elle était censée respecter.
 *
 * ## Le serveur seul maître comptable (D246, décision PO du 15/10/2026)
 *
 * Les postes poussent des documents SOURCES (réservation, fiche fournisseur,
 * commande…), jamais des écritures comptables : les écritures sont produites
 * ici, par les services métier, à la date MÉTIER du document
 * (`ContexteSynchronisation`), jamais à la date de réception.
 */
class SynchronisationService
{
    /** LARAVEL_SYNC_FLUTTER.md §7 — au-delà, le client découpe en lots. */
    public const TAILLE_LOT_MAX = 50;

    /**
     * TTL de la mémoire d'idempotence, en jours (§5).
     *
     * **30 jours depuis le 15/10/2026** (7 auparavant). Le TTL doit couvrir la
     * plus longue période hors connexion réaliste, et la décision PO du
     * 15/10/2026 l'a allongée : les postes Windows des sites isolés (serveur
     * injoignable, aucune connexion) poussent désormais leurs documents —
     * fournisseurs, commandes d'achat, ventes — au retour du réseau, qui peut
     * tarder des semaines. Une opération rejouée APRÈS la purge de sa mémoire
     * serait ré-exécutée : un doublon de commande ou de vente, sans erreur ni
     * trace. Le coût est une table plus longue d'un facteur 4, purgée par
     * `NettoyerDeduplicationSyncJob` — négligeable devant ce risque.
     */
    public const TTL_DEDUPLICATION_JOURS = 30;

    public function __construct(
        private readonly ClassificationConflitService $classification,
        private readonly RegistreSynchronisation $registre,
        private readonly ResolveurCorrespondances $correspondances,
        private readonly OrigineDocuments $origines,
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

        if (! $this->registre->estSynchronisable($table)) {
            return $this->memoriser($operation, $posteId, $utilisateurId, $this->rejet(
                $operation,
                __('sync.table_non_synchronisable', ['table' => $table]),
            ));
        }

        $gestionnaire = $this->registre->pour($table);

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
        $utilisateur = $this->utilisateurAutorise(
            $utilisateurId,
            $gestionnaire,
            is_array($operation['payload'] ?? null) ? $operation['payload'] : [],
        );

        if ($utilisateur === null) {
            return $this->memoriser($operation, $posteId, $utilisateurId, $this->rejet(
                $operation,
                __('auth.module_refuse'),
            ));
        }

        // Refus explicite d'une table qui ne synchronise pas ses
        // modifications : il n'existe plus de repli brut (15/10/2026).
        if ($operation['type'] === 'modification' && ! $gestionnaire->accepteModification()) {
            return $this->memoriser($operation, $posteId, $utilisateurId, $this->rejet(
                $operation,
                __('sync.modification_non_synchronisable'),
            ));
        }

        /** @var array<string, mixed> $payload */
        $payload = $operation['payload'];
        $contexte = $this->contexte($operation, $payload, $posteId, $utilisateur, $gestionnaire);

        if ($contexte === null) {
            return $this->memoriser($operation, $posteId, $utilisateurId, $this->rejet(
                $operation,
                __('sync.date_metier_invalide'),
            ));
        }

        // `date_metier` est une donnée du PROTOCOLE, pas du document : elle
        // vit dans le contexte, jamais dans les colonnes de la table.
        unset($payload['date_metier']);

        try {
            $resultat = DB::transaction(
                fn (): array => $this->appliquer($operation, $payload, $gestionnaire, $contexte, $sessionId),
            );
        } catch (ChevauchementDetecteException $e) {
            // §4.2, catégorie structurelle : ce n'est pas un conflit de versions
            // mais un rejet — deux enregistrements distincts qui ne peuvent pas
            // coexister (RG-01/RG-08/RG-13).
            $resultat = [
                ...$this->rejet($operation, $e->getMessage()),
                'entites_en_conflit' => $e->identifiantsEnConflit,
            ];
        } catch (DonneesSynchroniseesInvalidesException $e) {
            // Les phrases de l'API, champ par champ : le poste les affiche à
            // côté de la saisie, comme l'écran en ligne.
            $resultat = [...$this->rejet($operation, $e->getMessage()), 'erreurs' => $e->erreurs];
        } catch (RuntimeException $e) {
            // UNIQUEMENT les refus métier. Le message est transmis au client :
            // §2.2 exige que l'application informe l'utilisateur clairement,
            // pas par une erreur technique brute.
            $resultat = $this->rejet($operation, $e->getMessage());
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
     * L'utilisateur, s'il a le droit d'écrire dans le module du gestionnaire.
     *
     * Toute operation de synchronisation est une ecriture (`creation` ou
     * `modification`, seuls types acceptes par `SynchroniserRequest`) : le
     * niveau requis, declare par le gestionnaire, est `C`, jamais `L`.
     *
     * Le niveau est lu par `User::niveauSurModule()`, la meme source que
     * `VerifierAccesModule` — reecrire le calcul ici ferait diverger les deux
     * chemins le jour ou la matrice changerait.
     */
    /**
     * Depuis le 15/10/2026 (lot S3), un document peut exiger PLUSIEURS
     * modules (`modulesRequis()`) : une vente qui porte des plats est une
     * écriture sur M5 ET M4, exactement comme `PosComptant::encaissementReel`
     * l'exige en ligne. Le contrôle reste ICI, hors de la transaction de
     * l'opération : un refus levé dans le gestionnaire annulerait aussi la
     * trace `journal_securite` qui doit lui survivre.
     *
     * @param  array<string, mixed>  $payload
     */
    private function utilisateurAutorise(string $utilisateurId, GestionnaireSynchronisation $gestionnaire, array $payload): ?User
    {
        $utilisateur = $this->utilisateurs[$utilisateurId] ??= User::find($utilisateurId);

        if (! $utilisateur instanceof User || ! $utilisateur->estActif()) {
            return null;
        }

        $module = null;

        foreach ($gestionnaire->modulesRequis($payload) as $requis) {
            if ($utilisateur->niveauSurModule($requis) !== $gestionnaire->niveauRequis()) {
                $module = $requis;

                break;
            }
        }

        if ($module === null) {
            return $utilisateur;
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

        return null;
    }

    /**
     * Le contexte de l'opération — `null` si la date métier est illisible.
     *
     * Date métier, par ordre de priorité : `payload.date_metier` explicite →
     * champ date du document déclaré par le gestionnaire → date de SAISIE
     * (`horodatage_client`). Jamais `now()` : un document saisi lundi et
     * synchronisé jeudi est un document de lundi (D246, 15/10/2026).
     *
     * @param  array<string, mixed>  $operation
     * @param  array<string, mixed>  $payload
     */
    private function contexte(
        array $operation,
        array $payload,
        string $posteId,
        User $utilisateur,
        GestionnaireSynchronisation $gestionnaire,
    ): ?ContexteSynchronisation {
        $horodatageClient = Carbon::parse((string) $operation['horodatage_client']);

        $champ = $gestionnaire->champDateDocument();
        $brute = $payload['date_metier'] ?? ($champ !== null ? ($payload[$champ] ?? null) : null);

        try {
            $dateMetier = $brute === null ? $horodatageClient->copy() : Carbon::parse((string) $brute);
        } catch (InvalidFormatException) {
            return null;
        }

        return new ContexteSynchronisation($posteId, $utilisateur, $horodatageClient, $dateMetier);
    }

    /**
     * @param  array<string, mixed>  $operation
     * @param  array<string, mixed>  $payload
     * @return array<string, mixed>
     */
    private function appliquer(
        array $operation,
        array $payload,
        GestionnaireSynchronisation $gestionnaire,
        ContexteSynchronisation $contexte,
        string $sessionId,
    ): array {
        $table = $gestionnaire->table();
        $idPoste = (string) $operation['entite_id'];

        // Un élément créé hors connexion puis FUSIONNÉ côté serveur est désigné
        // par l'UUID du poste dans les opérations suivantes de ce poste : on
        // travaille sur l'élément serveur (décision PO du 15/10/2026).
        $entiteId = $this->correspondances->resoudre($table, $idPoste);

        // Lecture seule : savoir si l'élément existe, et sa version serveur
        // pour l'arbitrage. Aucune écriture ne passe plus par le query builder.
        $existant = DB::table($table)->where('id', $entiteId)->first();

        if ($operation['type'] === 'creation') {
            return $this->creer($operation, $payload, $gestionnaire, $contexte, $idPoste, $entiteId, $existant);
        }

        if ($existant === null) {
            return $this->modifierInconnu($operation, $payload, $gestionnaire, $contexte, $idPoste);
        }

        $horodatageClient = $contexte->horodatageClient;

        // §4.1 — conflit si l'enregistrement a été modifié côté serveur APRÈS
        // l'horodatage de saisie du client, par un AUTRE poste.
        //
        // Et, hors table financière (décision PO du 15/10/2026, catalogue
        // modifiable hors connexion), si une saisie PLUS RÉCENTE a déjà été
        // appliquée — même venue de ce poste : le dernier écrit gagnant se
        // juge sur l'horodatage de SAISIE, jamais sur l'ordre d'arrivée. Une
        // modification plus ancienne que la dernière appliquée perd
        // (`version_serveur_conservee`), la ligne de conflit en garde trace.
        $enConflit = $this->estEnConflit($existant, $horodatageClient, $contexte->posteId, $table, $entiteId)
            || (! $gestionnaire->estFinanciere() && $this->estPerimee($entiteId, $horodatageClient));

        $resultat = $enConflit
            ? $this->traiterConflit($gestionnaire, $entiteId, $payload, $existant, $operation, $sessionId, $contexte)
            : $this->succes($operation, $gestionnaire->modifier($entiteId, $payload, $contexte));

        // Le poste a désigné l'élément par son UUID local, fusionné depuis :
        // il doit apprendre l'UUID serveur pour remapper.
        if ($entiteId !== $idPoste && $resultat['statut'] !== 'rejete') {
            $resultat['entite_id'] = $entiteId;
            $resultat['fusionne_avec'] = $entiteId;
        }

        return $resultat;
    }

    /**
     * Le TYPE annoncé doit correspondre à l'état serveur.
     *
     * Avant le 15/10/2026, une `creation` sur un identifiant existant devenait
     * silencieusement une mise à jour brute : un poste pouvait ainsi réécrire
     * n'importe quelle fiche en l'annonçant « nouvelle ». Désormais :
     * - l'identifiant est celui d'une fusion déjà faite (correspondance) →
     *   même réponse que la fusion d'origine, rien n'est écrit ;
     * - l'identifiant existe tel quel → rejet explicite, SAUF pour un
     *   DOCUMENT (vente, dépense, commande, bon, session — lot S3,
     *   15/10/2026) : son UUID est celui du poste, et l'y retrouver signifie
     *   que ce même document a déjà été écrit (rejeu après purge de la
     *   mémoire d'idempotence, ou nouvelle tentative sous un autre
     *   `uuid_operation`). Le gestionnaire rend alors le résultat d'origine
     *   — sans rien réécrire, sans second numéro, sans seconde pièce. Le
     *   rejeter ferait retirer au poste, comme « refusé », un document que
     *   le serveur détient bel et bien.
     *
     * @param  array<string, mixed>  $operation
     * @param  array<string, mixed>  $payload
     * @return array<string, mixed>
     */
    private function creer(
        array $operation,
        array $payload,
        GestionnaireSynchronisation $gestionnaire,
        ContexteSynchronisation $contexte,
        string $idPoste,
        string $entiteId,
        ?object $existant,
    ): array {
        if ($existant !== null) {
            if ($entiteId !== $idPoste) {
                return $this->succes($operation, new EcritureSynchronisee($entiteId, fusionneAvec: $entiteId));
            }

            $reprise = $gestionnaire->reprendreExistant($entiteId, $contexte);

            if ($reprise !== null) {
                return [...$this->succes($operation, $reprise), 'document_deja_enregistre' => true];
            }

            return $this->rejet($operation, __('sync.creation_entite_existante'));
        }

        // Lot F4 : tout ce que le service écrit dans cette portée (le
        // document, ses mouvements de stock…) est attribué au poste.
        $ecriture = $this->origines->pendant(
            $contexte->posteId,
            $gestionnaire->tablesMiroirs(),
            function () use ($gestionnaire, $idPoste, $payload, $contexte): EcritureSynchronisee {
                $ecriture = $gestionnaire->creer($idPoste, $payload, $contexte);
                $this->origines->retenir($gestionnaire->table(), $ecriture->entiteId, derive: false);

                return $ecriture;
            },
        );

        if ($ecriture->fusionneAvec !== null) {
            $this->correspondances->enregistrer($contexte->posteId, $gestionnaire->table(), $idPoste, $ecriture->fusionneAvec);
        }

        return $this->succes($operation, $ecriture);
    }

    /**
     * Une `modification` dont la cible est inconnue du serveur — ni telle
     * quelle, ni par correspondance.
     *
     * Avant le 15/10/2026 : toujours un rejet. Depuis la décision du Product
     * Owner du 15/10/2026, le gestionnaire décide (`modificationSurInconnu()`) :
     * le catalogue y voit une création perdue en route (créée si le payload
     * est complet, fusion comprise — la correspondance est alors retenue
     * comme pour une création), la caisse une clôture de session inconnue
     * (acceptée, jamais bloquée). `null` garde le rejet.
     *
     * @param  array<string, mixed>  $operation
     * @param  array<string, mixed>  $payload
     * @return array<string, mixed>
     */
    private function modifierInconnu(
        array $operation,
        array $payload,
        GestionnaireSynchronisation $gestionnaire,
        ContexteSynchronisation $contexte,
        string $idPoste,
    ): array {
        $ecriture = $gestionnaire->modificationSurInconnu($idPoste, $payload, $contexte);

        if ($ecriture === null) {
            return $this->rejet($operation, __('sync.modification_entite_inconnue'));
        }

        if ($ecriture->fusionneAvec !== null) {
            $this->correspondances->enregistrer($contexte->posteId, $gestionnaire->table(), $idPoste, $ecriture->fusionneAvec);
        }

        return $this->succes($operation, $ecriture);
    }

    /**
     * Une saisie POSTÉRIEURE à celle-ci a-t-elle déjà été appliquée sur cet
     * élément (dernier écrit gagnant, décision PO du 15/10/2026) ?
     */
    private function estPerimee(string $entiteId, Carbon $horodatageClient): bool
    {
        $derniere = $this->horodatageSaisiePrecedente($entiteId);

        return $derniere !== null && $horodatageClient->lessThan($derniere);
    }

    /**
     * @param  array<string, mixed>  $operation
     * @return array<string, mixed>
     */
    private function succes(array $operation, EcritureSynchronisee $ecriture): array
    {
        return [
            'uuid_operation' => (string) $operation['uuid_operation'],
            'statut' => $ecriture->statut,
            'entite_id' => $ecriture->entiteId,
            ...($ecriture->fusionneAvec !== null ? ['fusionne_avec' => $ecriture->fusionneAvec] : []),
            ...$ecriture->complements,
        ];
    }

    /**
     * @param  array<string, mixed>  $operation
     * @return array<string, mixed>
     */
    private function rejet(array $operation, string $motif): array
    {
        return [
            'uuid_operation' => (string) $operation['uuid_operation'],
            'statut' => 'rejete',
            'entite_id' => (string) $operation['entite_id'],
            'motif' => $motif,
        ];
    }

    /**
     * @param  array<string, mixed>  $payload
     * @param  array<string, mixed>  $operation
     * @return array<string, mixed>
     */
    private function traiterConflit(
        GestionnaireSynchronisation $gestionnaire,
        string $entiteId,
        array $payload,
        object $existant,
        array $operation,
        string $sessionId,
        ContexteSynchronisation $contexte,
    ): array {
        $table = $gestionnaire->table();
        $versionServeur = (array) $existant;
        $automatique = ! $gestionnaire->estFinanciere()
            && $this->classification->autoriseResolutionAutomatique($table);

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
        $reference = $this->referenceDuDernierEcrit($entiteId, $existant);

        if ($reference !== null && $contexte->horodatageClient->lessThan($reference)) {
            $conflit->update(['statut' => 'resolu_serveur']);

            return [
                'uuid_operation' => (string) $operation['uuid_operation'],
                'statut' => 'synchronise',
                'entite_id' => $entiteId,
                'resolution' => 'version_serveur_conservee',
                'conflit_id' => $conflit->id,
            ];
        }

        // La version locale gagne : elle est écrite par le GESTIONNAIRE, donc
        // par le service de domaine — validation, audit RG-15 et horodatage de
        // modification compris. L'`UPDATE` brut d'avant devait avancer
        // `date_modification` à la main, faute de quoi §4.1 cessait de
        // détecter le moindre conflit ; Eloquent (`Auditable`) le tient.
        $ecriture = $gestionnaire->modifier($entiteId, $payload, $contexte);

        return [
            ...$this->succes($operation, $ecriture),
            'resolution' => 'version_locale_conservee',
            'conflit_id' => $conflit->id,
        ];
    }

    /**
     * La date contre laquelle une saisie concurrente est jugée.
     *
     * La dernière saisie APPLIQUÉE par synchronisation ; à défaut, la date de
     * modification serveur. Et depuis le 15/10/2026 (catalogue modifiable
     * hors connexion) : si l'élément a été réécrit HORS synchronisation
     * (écran en ligne, API) APRÈS la dernière opération appliquée, cette
     * écriture compte aussi — sinon la correction faite par le gérant à
     * l'écran perdrait contre une saisie de poste plus ancienne qu'elle,
     * au seul motif qu'une saisie de poste encore plus ancienne existait.
     */
    private function referenceDuDernierEcrit(string $entiteId, object $existant): ?Carbon
    {
        $saisie = $this->horodatageSaisiePrecedente($entiteId);
        $dateServeur = $this->dateModificationServeur($existant);

        if ($saisie === null || $dateServeur === null) {
            return $saisie ?? $dateServeur;
        }

        $dernierTraitement = $this->dernierTraitementApplique($entiteId);

        if ($dernierTraitement !== null && $dateServeur->greaterThan($dernierTraitement)) {
            return $saisie->max($dateServeur);
        }

        return $saisie;
    }

    private function dernierTraitementApplique(string $entiteId): ?Carbon
    {
        $candidates = DeduplicationSynchronisation::where('entite_id', $entiteId)
            ->orderByDesc('date_traitement')
            ->get(['resultat', 'date_traitement']);

        foreach ($candidates as $candidate) {
            $resultat = $candidate->resultat;

            if (($resultat['statut'] ?? null) === 'synchronise'
                && ($resultat['resolution'] ?? null) !== 'version_serveur_conservee') {
                return Carbon::parse((string) $candidate->date_traitement);
            }
        }

        return null;
    }

    private function estEnConflit(
        object $existant,
        Carbon $horodatageClient,
        string $posteId,
        string $table,
        string $entiteId,
    ): bool {
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

        // Même principe quand la table ne porte pas `poste_id` (15/10/2026) :
        // si la DERNIÈRE écriture serveur de cet élément est celle de CE poste,
        // par la synchronisation, personne d'autre n'y a touché depuis.
        //
        // Le piège corrigé : une session de caisse OUVERTE puis CLÔTURÉE hors
        // connexion arrive dans le même lot. L'ouverture est écrite à la
        // réception (`updated_at` = maintenant), la clôture a été saisie AVANT
        // (`horodatage_client` = 22 h la veille) — la comparaison brute y
        // voyait une « modification concurrente sur une donnée financière » et
        // envoyait la clôture en arbitrage. Ce n'est pas une écriture
        // concurrente : c'est la suite du même document, par le même poste.
        if ($this->derniereEcritureEstDuPoste($table, $entiteId, $posteId, $dateServeur)) {
            return false;
        }

        return $dateServeur->greaterThan($horodatageClient);
    }

    /**
     * La dernière opération APPLIQUÉE sur cet élément vient-elle de ce poste,
     * et est-elle postérieure (ou égale, à la seconde) à la date de
     * modification serveur ? Une écriture d'un tiers (PWA, autre poste)
     * survenue après ferait avancer la date serveur au-delà : le conflit
     * reste alors détecté.
     */
    private function derniereEcritureEstDuPoste(string $table, string $entiteId, string $posteId, Carbon $dateServeur): bool
    {
        $candidates = DeduplicationSynchronisation::query()
            ->where('table_concernee', $table)
            ->where('entite_id', $entiteId)
            ->orderByDesc('date_traitement')
            ->get(['poste_id', 'resultat', 'date_traitement']);

        foreach ($candidates as $candidate) {
            $resultat = $candidate->resultat;

            if (($resultat['statut'] ?? null) !== 'synchronise'
                || ($resultat['resolution'] ?? null) === 'version_serveur_conservee') {
                continue;
            }

            return $candidate->poste_id === $posteId
                && Carbon::parse((string) $candidate->date_traitement)->greaterThanOrEqualTo($dateServeur);
        }

        return false;
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
            // L'identifiant SERVEUR quand il diffère (fusion) : c'est sur lui
            // que `horodatageSaisiePrecedente()` cherchera le dernier écrivain.
            'entite_id' => (string) ($resultat['entite_id'] ?? $operation['entite_id']),
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
