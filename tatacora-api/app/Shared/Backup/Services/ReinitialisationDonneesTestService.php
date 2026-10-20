<?php

declare(strict_types=1);

namespace App\Shared\Backup\Services;

use App\Domain\Comptabilite\Services\ArchiveClotureService;
use App\Models\User;
use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Parametres\Services\ParametreSystemeService;
use App\Shared\Sync\Services\GenerationDonneesService;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use RuntimeException;

/**
 * « Réinitialiser comme neuf » — `import-export.html`, onglet 4.
 *
 * ## Demande du Product Owner du 14/10/2026 (lot E)
 *
 * « On doit avoir l'option de vider le système comme un neuf mais en gardant
 * les données de véhicules, articles de stock, tourisme catalogue, les
 * éléments de fiche Restaurant, les Bar et les articles ; faut compléter ce
 * qui doit être vidé : cache, cache_locks, clients, employes, reservations
 * chambres, failed_jobs, fournisseurs, guides. »
 *
 * La version du 02/09/2026 PRÉSERVAIT précisément ces tables (`clients`,
 * `fournisseurs`, `employes`, `guides`, `services`, `cache`, `cache_locks`,
 * `failed_jobs`…) : exécutée, elle laissait en place l'essentiel du jeu de
 * démonstration, ce que le Product Owner a lu, à raison, comme « je n'arrive
 * pas à vider les seeders ». Elle exigeait de plus le seul niveau `C` sur
 * PARAM ; elle est désormais réservée aux deux rôles d'administration.
 *
 * ## Ce qui est GARDÉ — liste FERMÉE et EXPLICITE
 *
 * Règle du maître (engine l.508-513), conservée : une table ajoutée demain est
 * VIDÉE par défaut, jamais conservée par accident. Sont gardés :
 *  - l'identité — comptes, rôles, droits, jetons, paramètres : sans eux
 *    plus personne ne se connecte ;
 *  - les journaux — audit, sécurité, imports, historique des prix, messages
 *    à l'éditeur, états planifiés (RG-15 : la trace survit à ce qu'elle
 *    trace ; la réinitialisation elle-même y est écrite) ;
 *  - les référentiels désignés par le Product Owner — parc d'hébergement
 *    (catégories et unités : on garde les chambres, on vide leurs
 *    réservations — interprétation de « reservations chambres » à confirmer),
 *    canaux de réservation, articles et points de stockage (SANS mouvements :
 *    le stock se dérive des mouvements, il retombe donc à zéro), fiche
 *    restaurant (menus, recettes, compositions, plats, tables de salle),
 *    cartes du bar, véhicules, circuits ;
 *  - le paramétrage comptable — plan, journaux, exercices (restent dans leur
 *    statut : vider les écritures n'en clôture ni n'en rouvre aucun), comptes
 *    bancaires, centres de coût — sans lesquels aucun encaissement ne peut
 *    produire sa pièce (règle « tout mouvement d'argent… ») ;
 *  - les services (départements RH) et les modèles de notification.
 *
 * ## Un geste d'ADMINISTRATION, hors des Observers — délibérément
 *
 * Le vidage passe par le constructeur de requêtes (`DB::table()->delete()`),
 * jamais par Eloquent : `FactureObserver`, `EcritureComptableObserver` et les
 * policies refusent toute suppression d'une pièce, et c'est juste pour
 * l'exploitation. Ici l'on ne CORRIGE pas une pièce, on remet à neuf une base
 * de démonstration — un geste qui n'existe que hors Production, derrière une
 * bascule, une saisie de confirmation, un rôle d'administration et une
 * sauvegarde préalable. Il est écrit au journal d'audit.
 *
 * ## Ordre de vidage : les ENFANTS avant les PARENTS, contraintes ACTIVES
 *
 * Les clés étrangères ne sont plus suspendues : l'ordre est un tri
 * topologique calculé sur `information_schema` (une table n'est vidée que
 * lorsque plus aucune table restante ne la référence). Une table oubliée ou
 * une référence imprévue fait donc ÉCHOUER la transaction entière au lieu de
 * laisser une clé pendante en silence. Deux cas sont traités avant le tri :
 * les auto-références (`ecritures_comptables.ecriture_contrepassee_id`) sont
 * remises à NULL, et une table GARDÉE qui pointe vers une table vidée voit sa
 * colonne remise à NULL si elle l'admet (`utilisateurs.employe_id` : le
 * compte survit, son rattachement à une fiche employé disparaît) — sinon le
 * geste est refusé.
 *
 * ## Quatre verrous, revérifiés à l'exécution
 *
 *  1. L'ENVIRONNEMENT — `app()->isProduction()` refuse, SAUF pendant la
 *     phase d'essais en production (`TATACORA_PHASE_ESSAIS=true` au `.env`,
 *     décision du Product Owner du 19/10/2026 : « les essais en production
 *     suivis de la réinitialisation ») ; la variable se retire à la mise en
 *     service réelle.
 *  2. La BASCULE `reinitialisation_seeders`, fermée par défaut.
 *  3. Le RÔLE — administrateur ou super_admin (`User::estAdministrateur()`).
 *  4. La SAISIE du mot de confirmation — vérifiée par l'écran.
 *
 * Une sauvegarde complète est générée AVANT, hors transaction : si
 * `mysqldump` échoue, rien n'est vidé et le motif s'affiche dans la modale.
 *
 * ## Les POSTES suivent : la génération des données (19/10/2026)
 *
 * La réinitialisation ouvre une GÉNÉRATION nouvelle
 * (`GenerationDonneesService`). Un poste qui a synchronisé avant est refusé
 * (409) tant qu'il n'a pas été réinitialisé à son tour : sa file d'essai ne
 * repart pas vers le serveur remis à neuf.
 *
 * @see RG-15 la réinitialisation est journalisée
 */
class ReinitialisationDonneesTestService
{
    /**
     * La clé de la bascule — `RegistreParametres`, groupe `activation`.
     * Absente en base, `get()` rend le défaut FERMÉ.
     */
    public const CLE_BASCULE = 'reinitialisation_seeders';

    /**
     * Les tables que la réinitialisation NE TOUCHE PAS — voir l'entête.
     *
     * @var list<string>
     */
    public const TABLES_PRESERVEES = [
        // Framework — le registre des migrations seulement.
        'migrations',
        // Identité et réglages — le compte, les droits, les paramètres.
        'utilisateurs', 'roles', 'permissions', 'permission_role',
        'personal_access_tokens', 'parametres_systeme', 'secrets_configuration',
        // La génération des données : l'historique des réinitialisations.
        'generations_donnees',
        // Journaux et traces — RG-15.
        'journal_audit', 'journal_securite', 'journal_imports',
        'historique_prix_carte', 'messages_editeur', 'etats_planifies',
        // M1 — le parc (les chambres), sans leurs réservations.
        'categories_hebergement', 'unites_hebergement', 'canaux_reservation',
        // M6 — les articles et leurs lieux, sans leurs mouvements.
        'articles', 'points_stockage',
        // M4 — la fiche restaurant.
        'menus', 'recettes', 'ingredients_recette', 'plats', 'tables_salle',
        // M5 — la carte du bar.
        'cartes_boisson',
        // M8 / M9 — véhicules et catalogue tourisme.
        'vehicules', 'circuits',
        // M10 — le paramétrage comptable.
        'plan_comptable', 'journaux_comptables', 'exercices_comptables',
        'comptes_bancaires', 'centres_cout',
        // M13 / M12 — référentiels sans donnée personnelle.
        'services', 'modeles_notification',
    ];

    /**
     * Vidée SAUF la session de l'administrateur qui agit : le vider le
     * déconnecterait au milieu de son propre geste (pilote `database`).
     */
    private const TABLE_SESSIONS = 'sessions';

    public function __construct(
        private readonly SauvegardeManuelleService $sauvegardes,
        private readonly ParametreSystemeService $parametres,
        private readonly GenerationDonneesService $generations,
    ) {
    }

    public function estAutorisee(): bool
    {
        return ! app()->isProduction() || $this->enPhaseEssais();
    }

    /** La phase d'essais en production (`.env`) — voir `config/tatacora.php`. */
    public function enPhaseEssais(): bool
    {
        return app()->isProduction() && config('tatacora.phase_essais') === true;
    }

    /**
     * La bascule d'activation — l'état VERROUILLÉ/OUVERT de l'onglet.
     */
    public function estOuverte(): bool
    {
        return filter_var($this->parametres->get(self::CLE_BASCULE, '0'), FILTER_VALIDATE_BOOLEAN);
    }

    /**
     * Le geste est réservé aux rôles d'administration.
     */
    public function estPermisA(?User $utilisateur): bool
    {
        return $utilisateur !== null && $utilisateur->estActif() && $utilisateur->estAdministrateur();
    }

    /**
     * Les tables qui seront VIDÉES — mesurées sur la base réelle, jamais
     * recopiées : « Ce qui sera vidé » à l'écran vient d'ici.
     *
     * @return list<string>
     */
    public function tablesEffacables(): array
    {
        $effacables = array_values(array_filter(
            $this->tablesReelles(),
            static fn (string $table): bool => ! in_array($table, self::TABLES_PRESERVEES, true),
        ));

        sort($effacables);

        return $effacables;
    }

    /**
     * Les tables préservées EXISTANTES — « Ce qui sera conservé » à l'écran.
     *
     * @return list<string>
     */
    public function tablesPreservees(): array
    {
        $preservees = array_values(array_intersect(self::TABLES_PRESERVEES, $this->tablesReelles()));

        sort($preservees);

        return $preservees;
    }

    /**
     * L'ordre de vidage — enfants avant parents, calculé sur les clés
     * étrangères réelles. Exposé pour être vérifiable sans rien vider.
     *
     * @return list<string>
     *
     * @throws RuntimeException sur un cycle de références entre tables vidées
     */
    public function ordreDeVidage(): array
    {
        $effacables = $this->tablesEffacables();
        $index = array_fill_keys($effacables, true);

        /** @var array<string, array<string, true>> $referencesPar table => tables vidées qu'elle référence */
        $referencesPar = array_fill_keys($effacables, []);

        foreach ($this->referencesEtrangeres() as $reference) {
            if ($reference['source'] !== $reference['cible']
                && isset($index[$reference['source']], $index[$reference['cible']])) {
                $referencesPar[$reference['source']][$reference['cible']] = true;
            }
        }

        $restantes = $effacables;
        $ordre = [];

        while ($restantes !== []) {
            $retirees = [];

            foreach ($restantes as $table) {
                $encoreReferencee = false;

                foreach ($restantes as $autre) {
                    if ($autre !== $table && isset($referencesPar[$autre][$table])) {
                        $encoreReferencee = true;
                        break;
                    }
                }

                if (! $encoreReferencee) {
                    $retirees[] = $table;
                }
            }

            if ($retirees === []) {
                throw new RuntimeException(__('pwa.import_export.reset_cycle', [
                    'tables' => implode(', ', $restantes),
                ]));
            }

            array_push($ordre, ...$retirees);
            $restantes = array_values(array_diff($restantes, $retirees));
        }

        return $ordre;
    }

    /**
     * @return array{videes: int, lignes: int, sauvegarde: string, generation: string}
     */
    public function executer(?User $auteur, ?string $sessionConservee = null): array
    {
        if (! $this->estAutorisee()) {
            throw new RuntimeException(__('pwa.import_export.reset_refuse_production'));
        }

        // L'ouverture de l'onglet ne garantit rien : bascule et rôle sont
        // relus ICI, au moment d'agir.
        if (! $this->estOuverte()) {
            throw new RuntimeException(__('pwa.import_export.reset_refuse_bascule'));
        }

        if (! $this->estPermisA($auteur)) {
            throw new RuntimeException(__('pwa.import_export.reset_refuse_role'));
        }

        $ordre = $this->ordreDeVidage();
        $effacables = array_fill_keys($ordre, true);
        $preservees = array_fill_keys($this->tablesPreservees(), true);
        $references = $this->referencesEtrangeres();

        // Une table gardée qui pointe vers une table vidée sur une colonne
        // NOT NULL rendrait le vidage impossible : refus AVANT la sauvegarde.
        $aDetacher = [];
        foreach ($references as $reference) {
            if (isset($preservees[$reference['source']]) && isset($effacables[$reference['cible']])) {
                if (! $reference['nullable']) {
                    throw new RuntimeException(__('pwa.import_export.reset_reference_bloquante', [
                        'reference' => $reference['source'].'.'.$reference['colonne'].' -> '.$reference['cible'],
                    ]));
                }
                $aDetacher[] = $reference;
            }
        }

        // La sauvegarde d'abord, HORS transaction : si `mysqldump` échoue,
        // rien n'est vidé — pas de filet, pas de saut.
        $sauvegarde = basename($this->sauvegardes->genererMaintenant()['fichier']);

        $lignes = DB::transaction(function () use ($ordre, $effacables, $references, $aDetacher, $auteur, $sessionConservee, $sauvegarde): array {
            // 1. Les tables gardées lâchent leurs références vers les vidées.
            foreach ($aDetacher as $reference) {
                DB::table($reference['source'])
                    ->whereNotNull($reference['colonne'])
                    ->update([$reference['colonne'] => null]);
            }

            // 2. Les auto-références d'une table vidée sont rompues, sans quoi
            //    un DELETE de la table entière peut buter sur ses propres lignes.
            foreach ($references as $reference) {
                if ($reference['source'] === $reference['cible'] && isset($effacables[$reference['source']])) {
                    DB::table($reference['source'])
                        ->whereNotNull($reference['colonne'])
                        ->update([$reference['colonne'] => null]);
                }
            }

            // 3. Vidage, enfants d'abord, contraintes ACTIVES. `DELETE`
            //    (transactionnel), jamais `TRUNCATE` (commit implicite).
            $total = 0;
            foreach ($ordre as $table) {
                $requete = DB::table($table);

                if ($table === self::TABLE_SESSIONS && $sessionConservee !== null) {
                    $requete->where('id', '!=', $sessionConservee);
                }

                $total += $requete->delete();
            }

            // 4. Remise en cohérence des statuts OPÉRATIONNELS des
            //    référentiels gardés : une unité « occupée » sans séjour, un
            //    véhicule « loué » sans contrat affirmeraient un état que plus
            //    rien ne porte (PA-59/60/61). `hors_service` (l'archive) et
            //    `entretien` (un fait d'atelier) restent.
            //    `updated_at` avance avec le statut : les postes téléchargent
            //    le parc par curseur sur cette colonne (15/10/2026), et une
            //    remise à `libre` non datée ne redescendrait jamais.
            DB::table('unites_hebergement')
                ->whereIn('statut', ['occupee', 'reservee', 'nettoyage'])
                ->update(['statut' => 'libre', 'updated_at' => now()]);
            DB::table('vehicules')
                ->where('statut', 'loue')
                ->update(['statut' => 'disponible']);
            //    Un exercice démarré en clôture ou clôturé PENDANT LES ESSAIS
            //    (20/10/2026) : ses écritures et sa clôture sont effacées, il
            //    redevient ouvert — daté, pour redescendre aux postes.
            DB::table('exercices_comptables')
                ->where('statut', '!=', 'ouvert')
                ->update([
                    'statut' => 'ouvert',
                    'date_cloture' => null,
                    'utilisateur_cloture_id' => null,
                    'updated_at' => now(),
                ]);

            // 5. Une génération NOUVELLE : les postes d'avant s'arrêtent.
            $generation = $this->generations->ouvrir($auteur);

            // 6. La trace — RG-15 : le journal d'audit survit et le dit.
            JournalAudit::create([
                'utilisateur_id' => $auteur?->id,
                'action' => 'Réinitialisation',
                'entite_concernee' => 'systeme',
                'entite_id' => (string) Str::uuid(),
                'valeur_apres' => [
                    'geste' => 'reinitialiser_comme_neuf',
                    'tables_videes' => $ordre,
                    'lignes_supprimees' => $total,
                    'sauvegarde' => $sauvegarde,
                    'generation' => $generation->generation,
                    'phase_essais' => $this->enPhaseEssais(),
                ],
                'adresse_poste' => request()->ip(),
            ]);

            return ['total' => $total, 'generation' => $generation->generation];
        });

        // Les archives de clôture des essais suivent leurs clôtures (vidées
        // ci-dessus) : une « archive légale » d'un exercice d'essai ne doit
        // pas survivre. Hors transaction — un fichier ne se défait pas.
        Storage::disk(ArchiveClotureService::DISQUE)->deleteDirectory('archives/exercices');

        return [
            'videes' => count($ordre),
            'lignes' => $lignes['total'],
            'sauvegarde' => $sauvegarde,
            'generation' => $lignes['generation'],
        ];
    }

    /**
     * Les tables de LA base courante — `information_schema` filtré par
     * `DATABASE()`, jamais `Schema::getTables()` : mesuré le 02/09/2026, ce
     * dernier remonte les tables de TOUTES les bases accessibles au compte
     * MySQL, et le vidage aurait visé des bases étrangères.
     *
     * @return list<string>
     */
    private function tablesReelles(): array
    {
        $lignes = DB::select(
            "SELECT TABLE_NAME AS nom FROM information_schema.TABLES"
            ." WHERE TABLE_SCHEMA = DATABASE() AND TABLE_TYPE = 'BASE TABLE'",
        );

        return array_map(static fn (object $ligne): string => (string) $ligne->nom, $lignes);
    }

    /**
     * Les clés étrangères de la base courante, avec la nullabilité de leur
     * colonne source.
     *
     * @return list<array{source: string, colonne: string, cible: string, nullable: bool}>
     */
    private function referencesEtrangeres(): array
    {
        $lignes = DB::select(
            'SELECT k.TABLE_NAME AS source, k.COLUMN_NAME AS colonne, k.REFERENCED_TABLE_NAME AS cible,'
            .' c.IS_NULLABLE AS nullable'
            .' FROM information_schema.KEY_COLUMN_USAGE k'
            .' JOIN information_schema.COLUMNS c ON c.TABLE_SCHEMA = k.TABLE_SCHEMA'
            .' AND c.TABLE_NAME = k.TABLE_NAME AND c.COLUMN_NAME = k.COLUMN_NAME'
            .' WHERE k.TABLE_SCHEMA = DATABASE() AND k.REFERENCED_TABLE_NAME IS NOT NULL',
        );

        return array_map(static fn (object $ligne): array => [
            'source' => (string) $ligne->source,
            'colonne' => (string) $ligne->colonne,
            'cible' => (string) $ligne->cible,
            'nullable' => (string) $ligne->nullable === 'YES',
        ], $lignes);
    }
}
