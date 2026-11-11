<?php

declare(strict_types=1);

namespace App\Shared\Sync\Services;

use App\Domain\Caisse\Exceptions\RefusCaisseException;
use App\Domain\Comptabilite\Exceptions\EcritureImmuableException;
use App\Domain\Facturation\Exceptions\FactureImmuableException;
use App\Domain\Restaurant\Exceptions\RecetteManquanteException;
use App\Domain\Stocks\Exceptions\RuptureStockException;
use App\Models\User;
use App\Shared\Auth\Services\SuppressionCompteService;
use App\Shared\Integrite\Exceptions\ChevauchementDetecteException;
use App\Shared\Rbac\Models\JournalSecurite;
use App\Shared\Sync\Contracts\GestionnaireSynchronisation;
use App\Shared\Sync\Exceptions\DependanceManquanteException;
use App\Shared\Sync\Exceptions\DonneesSynchroniseesInvalidesException;
use App\Shared\Sync\Gestionnaires\GestionnaireUtilisateurs;
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
use Throwable;

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
        private readonly JournalReceptionService $journal,
        private readonly SuppressionCompteService $comptes,
        private readonly EpoqueSynchronisation $epoque,
    ) {
    }

    /**
     * Ce que le traitement de l'opération courante a appris et que le résultat
     * rendu au poste ne porte pas : l'exception métier, le module refusé. Lu
     * par le journal de réception (26/10/2026), jamais envoyé au poste.
     *
     * @var array<string, mixed>
     */
    private array $extras = [];

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
    public function traiterLot(string $posteId, array $operations, string $utilisateurId, bool $journaliser = true): array
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

        // Les éléments dont une opération vient d'être DIFFÉRÉE (dépendance pas encore
        // reçue, erreur imprévue) : les opérations suivantes du MÊME élément dans ce lot
        // attendent aussi (elles ne peuvent pas devancer la première), sans être
        // rejetées — le poste les remet en file dans l'ordre. Toute AUTRE opération du
        // lot, d'une autre table ou d'un autre élément, est traitée normalement.
        $differes = [];

        foreach ($operations as $operation) {
            $cle = (string) ($operation['table'] ?? '') . '|' . (string) ($operation['entite_id'] ?? '');

            if (isset($differes[$cle]) && ! $this->dejaTraitee((string) $operation['uuid_operation'])) {
                $resultat = $this->rejet($operation, __('sync.operation_differee'), self::CODE_DEPENDANCE);
            } else {
                $resultat = $this->traiterSansBloquerLeLot($operation, $posteId, $utilisateurId, $session->id, $journaliser);
            }

            if ($this->estDifferee($resultat)) {
                $differes[$cle] = true;
            }

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
     * Code rendu pour une opération DIFFÉRÉE : l'élément qu'elle cite n'est pas
     * encore connu du serveur. Jamais mémorisé, jamais définitif : le poste la remet
     * en file avec un repli (09/11/2026).
     */
    public const CODE_DEPENDANCE = 'dependance_manquante';

    /**
     * Code rendu pour une erreur IMPRÉVUE du serveur sur UNE opération : elle ne fait
     * plus échouer le lot entier (500), elle est différée comme une dépendance.
     */
    public const CODE_ERREUR_SERVEUR = 'erreur_serveur';

    /**
     * Traite une opération du lot SANS qu'une erreur imprévue sur elle n'emporte le
     * lot entier (décision du PO du 09/11/2026 : « aucune opération ne doit bloquer la
     * synchronisation »). Avant, un bogue sur UNE opération levait un 500 : le poste
     * renvoyait le même lot, le même 500, à chaque passage — une opération « poison »
     * bloquait tout ce qui la suivait. Désormais l'erreur est journalisée (`report`, et
     * le journal de réception par `traiterOperation`), l'opération est rendue DIFFÉRÉE
     * (`erreur_serveur`, non mémorisée : rejouée pour de bon au prochain passage) et les
     * autres opérations du lot passent.
     *
     * @param  array<string, mixed>  $operation
     * @return array<string, mixed>
     */
    private function traiterSansBloquerLeLot(array $operation, string $posteId, string $utilisateurId, string $sessionId, bool $journaliser): array
    {
        if (! $journaliser) {
            // La correction depuis la PWA veut l'exception telle quelle (elle la traduit).
            return $this->traiterOperation($operation, $posteId, $utilisateurId, $sessionId, false);
        }

        try {
            return $this->traiterOperation($operation, $posteId, $utilisateurId, $sessionId, true);
        } catch (Throwable $e) {
            report($e);

            return $this->rejet($operation, __('sync.erreur_serveur_operation'), self::CODE_ERREUR_SERVEUR);
        }
    }

    /** @param  array<string, mixed>  $resultat */
    private function estDifferee(array $resultat): bool
    {
        return ($resultat['statut'] ?? null) === 'rejete'
            && in_array($resultat['code_motif'] ?? null, [self::CODE_DEPENDANCE, self::CODE_ERREUR_SERVEUR], true);
    }

    private function dejaTraitee(string $uuidOperation): bool
    {
        return DeduplicationSynchronisation::where('uuid_operation', $uuidOperation)->exists();
    }

    /**
     * Ce que la DERNIÈRE opération traitée a appris en plus de son résultat
     * (exception métier, module refusé, compte inactif) : lu par la
     * correction depuis la PWA pour traduire la cause d'un nouvel échec.
     *
     * @return array<string, mixed>
     */
    public function extrasDeLaDerniereOperation(): array
    {
        return $this->extras;
    }

    /**
     * Traite UNE opération et la consigne au journal de réception.
     *
     * `$journaliser = false` : la CORRECTION depuis la PWA rejoue une
     * opération déjà consignée (`CorrectionReceptionService`), qui met sa
     * propre ligne à jour.
     *
     * @param  array<string, mixed>  $operation
     * @return array<string, mixed>
     */
    public function traiterOperation(array $operation, string $posteId, string $utilisateurId, string $sessionId, bool $journaliser = true): array
    {
        $this->extras = [];

        try {
            $resultat = $this->traiterOperationInterne($operation, $posteId, $utilisateurId, $sessionId);
        } catch (Throwable $e) {
            // Toute autre exception se propage (voir plus bas) : le journal
            // en garde la trace, le poste réessaiera.
            if ($journaliser) {
                $this->journal->enregistrer($operation, $posteId, $utilisateurId, $sessionId, [], $this->extras, $e);
            }

            throw $e;
        }

        if ($journaliser) {
            $this->journal->enregistrer($operation, $posteId, $utilisateurId, $sessionId, $resultat, $this->extras);
        }

        // L'ÉPOQUE (03/11/2026) : une opération ACCEPTÉE — et pas un rejeu, ni un
        // refus — change ce que les AUTRES postes ont à descendre ; le battement de
        // 30 s le leur dit. Elle n'est jamais bloquante : un cache en panne ne fait
        // pas échouer une opération déjà écrite.
        if (($resultat['statut'] ?? null) === 'synchronise' && ! isset($resultat['rejeu_idempotent'])) {
            try {
                $this->epoque->incrementer();
            } catch (Throwable) {
                // Le cycle de 5 minutes rattrape.
            }
        }

        return $resultat;
    }

    /**
     * @param  array<string, mixed>  $operation
     * @return array<string, mixed>
     */
    private function traiterOperationInterne(array $operation, string $posteId, string $utilisateurId, string $sessionId): array
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
                'table_non_synchronisable',
            ));
        }

        $gestionnaire = $this->registre->pour($table);

        // A5 (28/10/2026) : la SUPPRESSION a son propre chemin — registre
        // fermé, droit propre (super administrateur + écriture PARAM, comme
        // l'écran web), aucun arbitrage de version : la purge est un acte.
        if ($operation['type'] === 'suppression') {
            return $this->traiterSuppression($operation, $gestionnaire, $posteId, $utilisateurId);
        }

        // Le COMPTE du jeton : actif, et rien d'autre pour une opération d'usage.
        //
        // Décision du PO du 09/11/2026 : « le jeton du poste porte un seul compte ;
        // tout ce qui sort d'un poste appairé par le barman est jugé sur les droits du
        // barman : NON, ÇA NE DOIT PAS JUGER ». Les droits par module se jugent AU
        // POSTE, sur l'utilisateur connecté (RBAC local) ; le serveur reçoit les
        // opérations d'un poste de confiance (appairé par un administrateur, jeton
        // révocable) et ne garde que la liste fermée des opérations SENSIBLES
        // (`OperationsSensibles`) : un gestionnaire n'exige un module que pour elles
        // (`modulesRequis`), et leur refus est rendu SEUL.
        //
        // Un refus porte sur l'OPERATION, pas sur le lot, et il est DEFINITIF
        // (`rejete`, jamais `conflit`) : rejouer n'accorde pas de droits.
        $utilisateur = $this->utilisateurAutorise(
            $utilisateurId,
            $gestionnaire,
            is_array($operation['payload'] ?? null) ? $operation['payload'] : [],
        );

        if ($utilisateur === null) {
            return $this->memoriser($operation, $posteId, $utilisateurId, $this->rejet(
                $operation,
                __('auth.module_refuse'),
                ($this->extras['compte_inactif'] ?? false) === true ? 'compte_inactif' : 'droit_manquant',
            ));
        }

        // 09/11/2026 : le droit PARTICULIER d'une opération (en plus du module) — les
        // réglages MECeF et la forme juridique n'acceptent d'un poste que le compte d'un
        // administrateur. Refus DÉFINITIF et lisible (`droit_manquant`, « À traiter » du
        // poste), tracé comme tout accès refusé, hors de la transaction de l'opération.
        $refusDeDroit = $gestionnaire->refusDeDroit(
            is_array($operation['payload'] ?? null) ? $operation['payload'] : [],
            $utilisateur,
        );

        if ($refusDeDroit !== null) {
            JournalSecurite::create([
                'type_evenement' => 'acces_refuse_rbac',
                'utilisateur_id' => $utilisateur->id,
                'adresse_ip' => request()->ip(),
                'module_concerne' => $gestionnaire->module(),
            ]);
            $this->extras['module'] = $gestionnaire->module();

            return $this->memoriser($operation, $posteId, $utilisateurId, $this->rejet($operation, $refusDeDroit, 'droit_manquant'));
        }

        // Refus explicite d'une table qui ne synchronise pas ses
        // modifications : il n'existe plus de repli brut (15/10/2026).
        if ($operation['type'] === 'modification' && ! $gestionnaire->accepteModification()) {
            return $this->memoriser($operation, $posteId, $utilisateurId, $this->rejet(
                $operation,
                __('sync.modification_non_synchronisable'),
                'modification_non_synchronisable',
            ));
        }

        /** @var array<string, mixed> $payload */
        $payload = $operation['payload'];
        $contexte = $this->contexte($operation, $payload, $posteId, $utilisateur, $gestionnaire);

        if ($contexte === null) {
            return $this->memoriser($operation, $posteId, $utilisateurId, $this->rejet(
                $operation,
                __('sync.date_metier_invalide'),
                'date_metier_invalide',
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
                ...$this->rejet($operation, $e->getMessage(), 'chevauchement'),
                'entites_en_conflit' => $e->identifiantsEnConflit,
            ];
        } catch (DonneesSynchroniseesInvalidesException $e) {
            // Les phrases de l'API, champ par champ : le poste les affiche à
            // côté de la saisie, comme l'écran en ligne.
            $resultat = [...$this->rejet($operation, $e->getMessage(), 'donnees_invalides'), 'erreurs' => $e->erreurs];
        } catch (DependanceManquanteException $e) {
            // L'élément cité n'est pas ENCORE connu : ni définitif ni mémorisé (le même
            // identifiant d'opération, rejoué plus tard, est jugé pour de bon). Le
            // poste la remet en file avec un repli ; la trace reste au journal.
            $this->extras['exception'] = $e::class;

            return $this->rejet($operation, $e->getMessage(), self::CODE_DEPENDANCE);
        } catch (RuntimeException $e) {
            // UNIQUEMENT les refus métier. Le message est transmis au client :
            // §2.2 exige que l'application informe l'utilisateur clairement,
            // pas par une erreur technique brute.
            $this->extras['exception'] = $e::class;
            $resultat = $this->rejet($operation, $e->getMessage(), $this->codeDeLException($e));
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
     * Le module dont l'écriture est exigée pour purger (celui de l'onglet
     * « Import/Export » où vit le bouton « Purger »).
     */
    public const MODULE_PURGE = 'PARAM';

    /**
     * Rejoue une PURGE DÉFINITIVE (`suppression`) par le gestionnaire, donc par
     * le service de parc : mêmes verrous, mêmes phrases que l'écran web. Sans
     * l'élément (déjà purgé, rejeu), l'opération réussit sans rien faire —
     * idempotente.
     *
     * @param  array<string, mixed>  $operation
     * @return array<string, mixed>
     */
    private function traiterSuppression(array $operation, GestionnaireSynchronisation $gestionnaire, string $posteId, string $utilisateurId): array
    {
        if (! $gestionnaire->accepteSuppression()) {
            return $this->memoriser($operation, $posteId, $utilisateurId, $this->rejet(
                $operation,
                __('sync.suppression_non_synchronisable'),
                'suppression_non_synchronisable',
            ));
        }

        $utilisateur = $this->utilisateurs[$utilisateurId] ??= User::find($utilisateurId);

        if (! $utilisateur instanceof User || ! $utilisateur->estActif()) {
            $this->extras['compte_inactif'] = true;

            return $this->memoriser($operation, $posteId, $utilisateurId, $this->rejet($operation, __('auth.module_refuse'), 'compte_inactif'));
        }

        // 03/11/2026 : la suppression d'un COMPTE a sa propre autorité (le jeton
        // d'appairage du poste doit être un super administrateur) et sa propre
        // clé (le LOGIN).
        if ($gestionnaire instanceof GestionnaireUtilisateurs) {
            return $this->traiterSuppressionDeCompte($operation, $posteId, $utilisateur);
        }

        // Dans l'ordre de l'écran : super administrateur d'abord, puis l'écriture du module.
        if (! $utilisateur->estSuperAdmin() || $utilisateur->niveauSurModule(self::MODULE_PURGE) !== 'C') {
            JournalSecurite::create([
                'type_evenement' => 'acces_refuse_rbac',
                'utilisateur_id' => $utilisateur->id,
                'adresse_ip' => request()->ip(),
                'module_concerne' => self::MODULE_PURGE,
            ]);
            $this->extras['module'] = self::MODULE_PURGE;

            return $this->memoriser($operation, $posteId, $utilisateurId, $this->rejet(
                $operation,
                __('sync.suppression_reservee'),
                'droit_manquant',
            ));
        }

        $horodatage = Carbon::parse((string) $operation['horodatage_client']);
        $contexte = new ContexteSynchronisation($posteId, $utilisateur, $horodatage, $horodatage->copy());

        try {
            $resultat = DB::transaction(function () use ($operation, $gestionnaire, $contexte): array {
                $idPoste = (string) $operation['entite_id'];
                $entiteId = $this->correspondances->resoudre($gestionnaire->table(), $idPoste);

                if (DB::table($gestionnaire->table())->where('id', $entiteId)->doesntExist()) {
                    return $this->succes($operation, new EcritureSynchronisee($idPoste, complements: ['deja_supprime' => true]));
                }

                return $this->succes($operation, $gestionnaire->supprimer($entiteId, $contexte));
            });
        } catch (RuntimeException $e) {
            $this->extras['exception'] = $e::class;
            $resultat = $this->rejet($operation, $e->getMessage(), $this->codeDeLException($e));
        }

        return $this->memoriser($operation, $posteId, $utilisateurId, $resultat);
    }

    /**
     * Rejoue la SUPPRESSION d'un COMPTE annoncée par un poste (03/11/2026).
     *
     * L'AUTORITÉ d'abord : le compte du jeton d'appairage de ce poste doit être
     * un super administrateur actif (`User::peutSupprimerDesComptes`). Sinon
     * rejet DÉFINITIF `droit_manquant`, lisible dans « À traiter » du poste et
     * dans le journal de réception — le compte local reste supprimé chez lui, le
     * serveur n'en sait rien. Puis le service : cible non administratrice, jamais
     * le compte du jeton lui-même, compte inconnu ou déjà supprimé = no-op
     * journalisé (idempotence). Le payload ne porte que le `login` (et le login
     * local de l'auteur, pour l'audit) : jamais un mot de passe ni un hash.
     *
     * @param  array<string, mixed>  $operation
     * @return array<string, mixed>
     */
    private function traiterSuppressionDeCompte(array $operation, string $posteId, User $auteur): array
    {
        $payload = is_array($operation['payload'] ?? null) ? $operation['payload'] : [];
        $login = is_string($payload['login'] ?? null) ? trim($payload['login']) : '';

        if (! $auteur->peutSupprimerDesComptes()) {
            JournalSecurite::create([
                'type_evenement' => 'acces_refuse_rbac',
                'utilisateur_id' => $auteur->id,
                'adresse_ip' => request()->ip(),
                'module_concerne' => User::MODULE_SUPPRESSION_COMPTES,
            ]);
            $this->extras['module'] = User::MODULE_SUPPRESSION_COMPTES;

            return $this->memoriser($operation, $posteId, (string) $auteur->id, $this->rejet(
                $operation,
                __('sync.comptes.suppression_reservee'),
                'droit_manquant',
            ));
        }

        if ($login === '') {
            return $this->memoriser($operation, $posteId, (string) $auteur->id, $this->rejet(
                $operation,
                __('sync.comptes.login_manquant'),
                'donnees_invalides',
            ));
        }

        $local = is_string($payload['supprime_par'] ?? null) ? mb_substr(trim($payload['supprime_par']), 0, 100) : null;

        try {
            $supprime = DB::transaction(fn (): ?User => $this->comptes->supprimerPourUnPoste($auteur, $login, $posteId, $local));
            $resultat = $this->succes($operation, new EcritureSynchronisee(
                (string) $operation['entite_id'],
                complements: $supprime === null ? ['deja_supprime' => true] : [],
            ));
        } catch (RuntimeException $e) {
            $this->extras['exception'] = $e::class;
            $resultat = $this->rejet($operation, $e->getMessage(), $this->codeDeLException($e));
        }

        return $this->memoriser($operation, $posteId, (string) $auteur->id, $resultat);
    }

    /**
     * Le compte du JETON D'APPAIRAGE, s'il est ACTIF — `null` sinon (compte suspendu,
     * désactivé ou supprimé : refusé `compte_inactif`).
     *
     * Les modules NE SONT PLUS jugés pour une opération d'usage (décision du PO du
     * 09/11/2026, voir plus haut) : `modulesRequis()` est vide par défaut. Il ne se
     * remplit que pour la liste fermée `OperationsSensibles` (clôture d'exercice,
     * affectation du résultat), où le compte doit écrire sur le module — lu par
     * `User::niveauSurModule()`, la même source que `VerifierAccesModule`. Le contrôle
     * reste ICI, hors de la transaction de l'opération : un refus levé dans le
     * gestionnaire annulerait aussi la trace `journal_securite` qui doit lui survivre.
     *
     * @param  array<string, mixed>  $payload
     */
    private function utilisateurAutorise(string $utilisateurId, GestionnaireSynchronisation $gestionnaire, array $payload): ?User
    {
        $utilisateur = $this->utilisateurs[$utilisateurId] ??= User::find($utilisateurId);

        if (! $utilisateur instanceof User || ! $utilisateur->estActif()) {
            $this->extras['compte_inactif'] = true;

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

        $this->extras['module'] = $module;

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

            return $this->rejet($operation, __('sync.creation_entite_existante'), 'entite_existante');
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
            return $this->rejet($operation, __('sync.modification_entite_inconnue'), 'entite_inconnue');
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
    private function rejet(array $operation, string $motif, string $code = 'regle_metier'): array
    {
        return [
            'uuid_operation' => (string) $operation['uuid_operation'],
            'statut' => 'rejete',
            'entite_id' => (string) $operation['entite_id'],
            'motif' => $motif,
            // Le motif STRUCTURÉ (26/10/2026) : un code stable que le poste et
            // le journal de réception traduisent. Ajout rétro-compatible.
            'code_motif' => $code,
        ];
    }

    /**
     * Le code de motif d'un refus métier, d'après le type de l'exception.
     * Un type inconnu reste une règle de gestion générique : la phrase du
     * serveur, elle, est toujours transmise.
     */
    private function codeDeLException(RuntimeException $e): string
    {
        return match (true) {
            $e instanceof RuptureStockException => 'stock_insuffisant',
            $e instanceof RecetteManquanteException => 'recette_manquante',
            $e instanceof RefusCaisseException => 'refus_caisse',
            $e instanceof EcritureImmuableException, $e instanceof FactureImmuableException => 'piece_immuable',
            default => 'regle_metier',
        };
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
