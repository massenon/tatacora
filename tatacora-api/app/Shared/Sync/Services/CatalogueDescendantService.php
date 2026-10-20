<?php

declare(strict_types=1);

namespace App\Shared\Sync\Services;

use App\Models\User;
use App\Shared\Rbac\Models\Role;
use App\Shared\Sync\Gestionnaires\GestionnaireRoles;
use Illuminate\Database\Query\Builder;
use Illuminate\Support\Facades\DB;
use InvalidArgumentException;

/**
 * Le catalogue que les postes TÉLÉCHARGENT — `GET /api/v1/referentiels`,
 * décision du Product Owner du 15/10/2026 (le serveur est maître du
 * catalogue : mêmes identifiants partout).
 *
 * Depuis le lot F3 (décision du 16/10/2026), le flux porte aussi les
 * CLIENTS et les RÉSERVATIONS de tous les postes : un poste B voit les
 * chambres prises par un poste A et ne les revend pas. Les autres documents
 * (ventes, dépenses, caisses, commandes, réceptions) NE descendent PAS : ils
 * se consultent au serveur, qui en est le seul comptable (D246).
 *
 * ## Un curseur par table, une seule chaîne opaque
 *
 * Chaque table avance sur le couple (`updated_at`, `id`) — l'horodatage seul
 * ne suffit pas : vingt articles semés dans la même seconde partageraient la
 * même valeur, et une page qui s'arrêterait au milieu en perdrait ou en
 * doublerait. L'`id` départage, l'ordre est total, la pagination stable.
 *
 * Un élément MODIFIÉ après le passage du curseur a un `updated_at` plus
 * récent : il REPASSE au téléchargement suivant. C'est ce qui rend le flux
 * incrémental sans journal des changements, et c'est pourquoi tout écrivain
 * d'une donnée descendue doit faire avancer `updated_at` (voir
 * `CompositionRecetteService::remplacerComposition()`, qui touche la fiche
 * quand seule sa composition change).
 *
 * ## L'horizon de stabilité (HORIZON_SECONDES)
 *
 * Seuls les éléments modifiés AVANT `maintenant - HORIZON_SECONDES` sont
 * servis. Sans cette marge, deux pièges perdent des éléments sans bruit :
 * - une écriture dans la seconde déjà servie (même `updated_at`, `id` plus
 *   petit que le curseur) ne repasserait jamais ;
 * - une transaction ouverte avant la lecture et validée après porte un
 *   `updated_at` antérieur au curseur.
 * La seconde servie est donc toujours une seconde CLOSE. Le prix : un élément
 * créé il y a moins de cinq secondes attend le téléchargement suivant. La
 * limite assumée : une transaction de référentiel tenue plus de cinq
 * secondes (aucune ne l'est : ce sont des écritures d'une ligne).
 *
 * ## Rien n'est jamais retiré du flux
 *
 * Un élément archivé (`articles.actif`, `fournisseurs.actif`,
 * `clients.actif`, unité `hors_service`) DESCEND, marqué `actif: false` : le poste doit savoir
 * pourquoi il ne le propose plus, et ses documents passés le citent encore.
 * Aucune suppression n'existe au catalogue (« supprimer = archiver »).
 *
 * ## Des DÉFINITIONS, jamais des valeurs calculées (leçon PA-129)
 *
 * Le stock, le coût moyen pondéré, le dernier prix d'achat, le coût matière
 * d'une fiche ne descendent PAS : ce sont des calculs (`StockTheoriqueService`,
 * `ValorisationStockService`, `CompositionRecetteService::coutMatiere()`). Les
 * envoyer comme données stockées les ferait diverger du calcul dès le premier
 * mouvement local. `COLONNES` est donc une liste BLANCHE : une colonne ajoutée
 * demain à une table n'y entre pas par omission.
 *
 * ## RBAC par table
 *
 * Une table ne descend que si l'utilisateur LIT son module (`L` ou `C`, la
 * règle de `VerifierAccesModule`) — module déclaré par le gestionnaire du
 * registre, seule source, ou `MODULES_HORS_REGISTRE`. Le curseur d'une table
 * refusée n'avance pas : le jour où le droit est accordé, elle descend
 * depuis le début.
 *
 * ## Les correspondances de CE poste
 *
 * Un poste qui a perdu la réponse `fusionne_avec` (coupure après traitement)
 * remappe par elles. Celles d'un autre poste ne le concernent pas (ses UUID
 * locaux n'existent pas ici) et ne descendent pas ; celles d'une table que
 * l'utilisateur ne lit pas non plus.
 */
class CatalogueDescendantService
{
    public const TAILLE_PAGE_DEFAUT = 200;

    public const TAILLE_PAGE_MAX = 500;

    public const HORIZON_SECONDES = 5;

    /** Pseudo-source du curseur pour les correspondances. */
    public const CORRESPONDANCES = 'correspondances';

    /**
     * Les colonnes de DÉFINITION descendues, table par table, dans l'ordre où
     * un poste doit les écrire (un élément cité avant celui qui le cite).
     *
     * Écartées délibérément : `articles.prix_achat` et `cout_moyen_pondere`,
     * `recettes.cout_matiere_calcule` (calculs), `plats.categorie` (refusée en
     * saisie : la catégorie d'un plat EST le type de son menu), les colonnes
     * d'audit (le poste n'a pas les utilisateurs du serveur).
     *
     * @var array<string, list<string>>
     */
    public const COLONNES = [
        'points_stockage' => ['libelle', 'type'],
        'articles' => ['libelle', 'categorie', 'unite_mesure', 'point_stockage_id', 'suivi', 'seuil_alerte', 'seuil_reappro', 'actif'],
        'cartes_boisson' => ['article_id', 'libelle', 'categorie', 'prix_vente', 'unites_vendables_par_unite_stock', 'prix_provisoire', 'prix_corrige_main'],
        'menus' => ['libelle', 'type', 'date_debut', 'date_fin'],
        'recettes' => ['libelle', 'composition_provisoire'],
        'plats' => ['menu_id', 'recette_id', 'article_id', 'unites_vendables_par_unite_stock', 'libelle', 'prix_vente', 'prix_provisoire', 'prix_corrige_main'],
        'categories_hebergement' => ['libelle', 'capacite_max', 'tarif_base'],
        'unites_hebergement' => ['categorie_id', 'numero', 'statut'],
        // Lot F6 (18/10/2026) : le plan de salle, pour l'arbitrage des tables.
        'tables_salle' => ['espace', 'numero', 'libelle', 'places', 'actif'],
        'fournisseurs' => ['raison_sociale', 'nom', 'contact', 'telephone', 'email', 'ville', 'ifu', 'categorie', 'conditions_paiement', 'evaluation', 'actif'],
        // Lot F3 (décision PO du 16/10/2026) : les TIERS et les SÉJOURS
        // descendent aussi, pour qu'un poste voie les chambres prises par un
        // autre (RG-01) et ses clients. `solde` n'y est pas (calcul) ; le
        // canal non plus (`canal_id` désigne un canal du serveur, le poste ne
        // connaît que des codes) ; ni les colonnes d'audit, ni l'écriture du
        // remboursement (le poste ne tient pas les pièces du serveur).
        'clients' => ['nom', 'prenom', 'telephone', 'email', 'type_client', 'actif'],
        'reservations' => [
            'client_id', 'unite_id', 'date_arrivee', 'date_depart', 'statut', 'acompte', 'tarif_nuit',
            'remise_type', 'remise_valeur', 'mode_paiement', 'taux_annulation', 'montant_total_annulation',
            'montant_commission_annulation', 'montant_rembourse_annulation', 'date_annulation',
            // Lot 10f : remplacé par le NOM du canal (`serialiser`).
            'canal_id',
        ],
        // Lot F5 : l'arrivée et le départ réels, après la réservation.
        'sejours' => ['reservation_id', 'date_checkin_reel', 'date_checkout_reel'],
        // Lot F4 (décision PO du 17/10/2026, « NE PLUS LIMITER ») : TOUS les
        // documents de TOUS les postes. Les lignes d'un document descendent
        // AVEC lui (`ENFANTS`) ; les mouvements de stock descendent tous, sauf
        // vers le poste qui les tient déjà en miroir (`origines_synchronisation`).
        'sessions_caisse' => ['point_vente', 'date_ouverture', 'montant_fond', 'date_cloture', 'montant_theorique', 'montant_constate'],
        'ventes' => [
            'numero', 'session_id', 'point_vente', 'client_id', 'reservation_id', 'client_mention', 'table_id', 'montant_total',
            'mode_paiement', 'encaisse', 'statut', 'motif_annulation', 'annulee_at', 'date_creation',
            // Lot P1-1 (18/10/2026) : `created_at` est la date MÉTIER de la
            // vente (`VenteService` y pose la clôture du poste) ;
            // `date_creation` est celle de l'audit — sa RÉCEPTION au serveur.
            'created_at',
        ],
        'depenses' => ['numero', 'date_transaction', 'tresorerie', 'montant_total', 'libelle'],
        // Lot F6 : l'OCCUPATION des tables (paniers DE TABLE seulement), après
        // la vente qui la libère ; ouverte = occupée.
        'paniers' => ['point_vente', 'table_id', 'statut', 'cloture_at'],
        // Lot F5c : les factures (numérotées par le serveur) et leurs avoirs,
        // après les ventes et les réservations qu'elles portent.
        'factures' => ['numero', 'origine', 'client_id', 'date_emission', 'montant_ht', 'montant_tva', 'montant_ttc', 'statut'],
        'avoirs' => ['facture_id', 'numero', 'motif', 'montant', 'date_emission'],
        // Lot F5d : les encaissements, après leur facture et leur caisse.
        'paiements' => ['facture_id', 'session_id', 'mode_paiement', 'montant', 'date_paiement', 'statut', 'motif_annulation', 'date_annulation'],
        'commandes_achat' => ['fournisseur_id', 'date_commande', 'statut', 'montant_total', 'date_creation'],
        'bons_reception' => ['commande_id', 'date_reception', 'conformite', 'created_at'],
        'reglements_fournisseur' => ['commande_id', 'montant', 'tresorerie', 'date_reglement', 'statut', 'motif_annulation', 'date_annulation'],
        'mouvements_stock' => ['article_id', 'point_id', 'type_mouvement', 'quantite', 'motif', 'date_mouvement'],
        'circuits' => ['nom', 'theme', 'zone', 'duree', 'prix', 'capacite_max'],
        'guides' => ['nom', 'certification', 'zone_competence', 'tarif_jour'],
        'reservations_tour' => ['circuit_id', 'client_id', 'guide_id', 'date_circuit', 'nb_participants', 'statut'],
        // Audit de couverture (18/10/2026) : le parc M8 et ses contrats.
        'vehicules' => ['immatriculation', 'categorie', 'annee', 'transmission', 'capacite', 'tarif_jour', 'statut'],
        'contrats_location' => ['vehicule_id', 'client_id', 'guide_id', 'date_debut', 'date_fin', 'numero', 'statut', 'montant'],
        // Audit de couverture (18/10/2026) : M13 — le référentiel des services,
        // le dossier des employés, puis la paie.
        'services' => ['libelle'],
        'employes' => [
            'matricule', 'nom', 'prenom', 'poste', 'service_id', 'date_embauche', 'numero_cnss', 'type_contrat',
            'date_fin_contrat', 'salaire_base', 'statut',
        ],
        'bulletins_paie' => [
            'numero', 'employe_id', 'periode', 'salaire_base', 'total_primes', 'total_retenues', 'cnss_salarie', 'its',
            'charges_patronales_confirmees', 'net_a_payer', 'statut', 'motif_annulation',
        ],
        'centres_cout' => ['libelle', 'type'],
        // Lot 10e (18/10/2026) : le paramétrage de l'établissement, et les
        // rôles avec leur matrice (`droits`, lue du pivot). Jamais un compte.
        'parametres_systeme' => ['cle', 'valeur'],
        'roles' => ['libelle', 'description'],
        // Lot 10f : la configuration M12 (les messages restent sur leur poste).
        'modeles_notification' => ['evenement', 'canal', 'objet', 'contenu_template', 'actif'],
        // Passage d'année (20/10/2026) : les exercices et leur STATUT — une
        // clôture faite au serveur verrouille aussi l'année sur les postes.
        'exercices_comptables' => ['annee', 'date_debut', 'date_fin', 'statut', 'date_cloture'],
    ];

    /**
     * Tables que TOUT compte qui synchronise reçoit, quel que soit son droit
     * sur leur module (lot 10e). Le paramétrage gouverne les calculs de
     * chaque module (TVA, convention de prix, taux de la paie) et la matrice
     * des rôles donne leurs droits aux comptes du poste : un caissier qui
     * synchronise en a besoin autant qu'un administrateur. Aucune ne porte
     * de secret (`RegistreParametres::MOTIFS_SECRET`, ni compte ni mot de
     * passe). Les exercices (20/10/2026) aussi : toute vente passe sa pièce
     * dans l'exercice de sa date, quel que soit le droit sur M10.
     *
     * @var list<string>
     */
    public const LECTURE_LIBRE = ['parametres_systeme', 'roles', 'exercices_comptables'];

    /**
     * Tables descendues sans être synchronisables — leur module est déclaré
     * ici faute de gestionnaire. Les centres de coût sont semés par le
     * serveur ; le poste les reçoit pour aligner ses identifiants.
     *
     * @var array<string, string>
     */
    public const MODULES_HORS_REGISTRE = [
        'centres_cout' => 'M10',
        // Audit de couverture : le référentiel des services RH n'a pas
        // d'écrivain (semé des deux côtés) ; il se lit sous M13.
        'services' => 'M13',
        // Lot F5c : l'avoir n'a pas de gestionnaire (il naît de l'annulation
        // d'une facture), il se lit sous le module de la facturation.
        'avoirs' => 'M2',
        // Passage d'année (20/10/2026) : reçus par tout compte (une vente
        // passe sa pièce dans l'exercice de sa date), écrits au seul serveur.
        'exercices_comptables' => 'M10',
    ];

    /**
     * Les lignes d'une table qui ne descendent PAS (lot F6) : un panier de
     * comptoir n'occupe rien, seul un panier de table compte.
     *
     * @var array<string, string>  table → colonne qui doit être renseignée
     */
    public const NON_NULS = [
        'paniers' => 'table_id',
    ];

    /**
     * Les LIGNES qui descendent avec leur document : table, clé vers le
     * document, colonnes, ordre.
     *
     * @var array<string, array{table: string, cle: string, colonnes: list<string>, ordre: string}>
     */
    public const ENFANTS = [
        // Lot F6 (audit de couverture, 18/10/2026) : les services d'une
        // réservation (restauration, bar, tourisme, véhicule) descendent avec elle.
        'reservations' => ['table' => 'lignes_reservation', 'cle' => 'reservation_id', 'colonnes' => ['service', 'source_id', 'libelle', 'quantite', 'prix_unitaire', 'montant'], 'ordre' => 'created_at'],
        'ventes' => ['table' => 'lignes_vente', 'cle' => 'vente_id', 'colonnes' => ['code', 'nom', 'categorie', 'module', 'prix_unitaire', 'quantite', 'montant'], 'ordre' => 'created_at'],
        'depenses' => ['table' => 'lignes_depense', 'cle' => 'depense_id', 'colonnes' => ['libelle', 'compte_charge', 'nature', 'famille', 'montant'], 'ordre' => 'created_at'],
        'factures' => ['table' => 'lignes_facture', 'cle' => 'facture_id', 'colonnes' => ['source_module', 'source_id', 'libelle', 'quantite', 'prix_unitaire', 'prix_catalogue', 'montant'], 'ordre' => 'created_at'],
        'commandes_achat' => ['table' => 'lignes_commande_achat', 'cle' => 'commande_id', 'colonnes' => ['article_id', 'quantite_commandee', 'prix_unitaire'], 'ordre' => 'created_at'],
    ];

    /** @var list<string> */
    private const BOOLEENS = ['actif', 'prix_provisoire', 'prix_corrige_main', 'composition_provisoire', 'encaisse'];

    /** @var list<string> */
    private const ENTIERS = ['capacite_max', 'nb_participants'];

    /** Les colonnes ENTIÈRES des lignes (les autres restent des chaînes). */
    private const ENTIERS_ENFANTS = ['quantite'];

    /**
     * `updated_at` d'abord ; une ligne insérée sans horodatage (semeur brut)
     * descend quand même, en tête, plutôt que jamais.
     */
    private const FILIGRANE = "COALESCE(updated_at, created_at, '1970-01-02 00:00:00')";

    public function __construct(private readonly RegistreSynchronisation $registre)
    {
    }

    /**
     * Une page du catalogue.
     *
     * @return array{elements: list<array<string, mixed>>, correspondances: list<array<string, string>>, curseur: string, complet: bool}
     *
     * @throws InvalidArgumentException curseur illisible
     */
    public function page(User $utilisateur, string $posteId, ?string $curseur, int $taille): array
    {
        $positions = $this->decoder($curseur);
        $taille = max(1, min($taille, self::TAILLE_PAGE_MAX));
        $horizon = now()->subSeconds(self::HORIZON_SECONDES)->format('Y-m-d H:i:s');

        $restant = $taille;
        $complet = true;
        $elements = [];
        $correspondances = [];
        $lisibles = [];

        foreach (array_keys(self::COLONNES) as $table) {
            if (! $this->lisible($utilisateur, $table)) {
                continue;
            }

            $lisibles[] = $table;

            if (! $complet) {
                continue;
            }

            if ($restant === 0) {
                $complet = false;

                continue;
            }

            [$lignes, $reste] = $this->lire(
                $this->sansMiroirsDuPoste(
                    DB::table($table)
                        ->select(['id', ...self::COLONNES[$table]])
                        ->when(isset(self::NON_NULS[$table]), fn (Builder $q): Builder => $q->whereNotNull(self::NON_NULS[$table])),
                    $table,
                    $posteId,
                ),
                self::FILIGRANE,
                $positions[$table] ?? null,
                $horizon,
                $restant,
            );

            if ($lignes !== []) {
                $derniere = end($lignes);
                $positions[$table] = [(string) $derniere->filigrane, (string) $derniere->id];
                $elements = [...$elements, ...$this->serialiser($table, $lignes)];
                $restant -= count($lignes);
            }

            $complet = ! $reste;
        }

        if ($complet && $restant === 0) {
            $complet = false;
        } elseif ($complet && $lisibles !== []) {
            [$lignes, $reste] = $this->lire(
                DB::table('correspondances_synchronisation')
                    ->select(['id', 'table_concernee', 'id_poste', 'id_serveur'])
                    ->where('poste_id', $posteId)
                    ->whereIn('table_concernee', $lisibles),
                'created_at',
                $positions[self::CORRESPONDANCES] ?? null,
                $horizon,
                $restant,
            );

            if ($lignes !== []) {
                $derniere = end($lignes);
                $positions[self::CORRESPONDANCES] = [(string) $derniere->filigrane, (string) $derniere->id];

                foreach ($lignes as $ligne) {
                    $correspondances[] = [
                        'table' => (string) $ligne->table_concernee,
                        'id_poste' => (string) $ligne->id_poste,
                        'id_serveur' => (string) $ligne->id_serveur,
                    ];
                }
            }

            $complet = ! $reste;
        }

        return [
            'elements' => $elements,
            'correspondances' => $correspondances,
            'curseur' => $this->encoder($positions),
            'complet' => $complet,
        ];
    }

    /**
     * Les lignes après `$position`, strictement, et avant l'horizon — au plus
     * `$limite`, et si d'autres restent.
     *
     * @param  array{0: string, 1: string}|null  $position
     * @return array{0: list<object>, 1: bool}
     */
    private function lire(Builder $requete, string $filigrane, ?array $position, string $horizon, int $limite): array
    {
        $requete
            ->addSelect(DB::raw("{$filigrane} as filigrane"))
            ->whereRaw("{$filigrane} < ?", [$horizon])
            ->orderByRaw($filigrane)
            ->orderBy('id')
            ->limit($limite + 1);

        if ($position !== null) {
            [$apres, $id] = $position;

            $requete->where(static function (Builder $w) use ($filigrane, $apres, $id): void {
                $w->whereRaw("{$filigrane} > ?", [$apres])
                    ->orWhere(static function (Builder $egal) use ($filigrane, $apres, $id): void {
                        $egal->whereRaw("{$filigrane} = ?", [$apres])->where('id', '>', $id);
                    });
            });
        }

        $lignes = $requete->get()->all();
        $reste = count($lignes) > $limite;

        return [array_slice($lignes, 0, $limite), $reste];
    }

    /**
     * Retire du flux de CE poste les lignes dérivées qu'il tient déjà en
     * miroir (les entrées de stock de SA réception) — lot F4.
     */
    private function sansMiroirsDuPoste(Builder $requete, string $table, string $posteId): Builder
    {
        return $requete->whereNotExists(static function (Builder $o) use ($table, $posteId): void {
            $o->from('origines_synchronisation')
                ->where('table_concernee', $table)
                ->whereColumn('origines_synchronisation.entite_id', "{$table}.id")
                ->where('poste_id', $posteId)
                ->where('exclu_pour_poste', true);
        });
    }

    private function lisible(User $utilisateur, string $table): bool
    {
        if (in_array($table, self::LECTURE_LIBRE, true)) {
            return true;
        }

        $module = self::MODULES_HORS_REGISTRE[$table] ?? $this->registre->pour($table)->module();

        return in_array($utilisateur->niveauSurModule($module), ['L', 'C'], true);
    }

    /**
     * @param  list<object>  $lignes
     * @return list<array<string, mixed>>
     */
    private function serialiser(string $table, array $lignes): array
    {
        $compositions = $table === 'recettes' ? $this->compositions($lignes) : [];
        $ids = array_map(static fn (object $l): string => (string) $l->id, $lignes);
        $enfants = isset(self::ENFANTS[$table]) ? $this->enfants(self::ENFANTS[$table], $ids) : [];
        $lignesBons = $table === 'bons_reception' ? $this->lignesDesBons($ids) : [];
        $droits = $table === 'roles' ? $this->droitsDesRoles($ids) : [];
        $canaux = $table === 'reservations' ? DB::table('canaux_reservation')->pluck('nom', 'id')->all() : [];
        $origines = DB::table('origines_synchronisation')
            ->where('table_concernee', $table)
            ->whereIn('entite_id', $ids)
            ->pluck('poste_id', 'entite_id')
            ->all();
        $elements = [];

        foreach ($lignes as $ligne) {
            $donnees = [];

            foreach (self::COLONNES[$table] as $colonne) {
                $valeur = $ligne->{$colonne};

                $donnees[$colonne] = match (true) {
                    $valeur === null => null,
                    in_array($colonne, self::BOOLEENS, true) => (bool) $valeur,
                    in_array($colonne, self::ENTIERS, true) => (int) $valeur,
                    // Les montants et quantités restent des CHAÎNES décimales,
                    // comme partout dans l'API (PA-55) : un flottant réarrondi
                    // côté poste ferait diverger un prix.
                    default => (string) $valeur,
                };
            }

            $actif = match ($table) {
                'articles', 'fournisseurs', 'clients', 'tables_salle', 'modeles_notification' => (bool) $donnees['actif'],
                'unites_hebergement', 'vehicules' => $donnees['statut'] !== 'hors_service',
                default => true,
            };
            unset($donnees['actif']);

            if ($table === 'recettes') {
                $donnees['lignes'] = $compositions[(string) $ligne->id] ?? [];
            }

            if (isset(self::ENFANTS[$table])) {
                $donnees['lignes'] = $enfants[(string) $ligne->id] ?? [];
            }

            if ($table === 'bons_reception') {
                $donnees['lignes'] = $lignesBons[(string) $ligne->id] ?? [];
            }

            if ($table === 'roles') {
                $donnees['droits'] = $droits[(string) $ligne->id] ?? [];
            }

            if ($table === 'reservations') {
                $donnees['canal'] = $canaux[(string) $donnees['canal_id']] ?? null;
                unset($donnees['canal_id']);
            }

            $elements[] = [
                'table' => $table,
                'id' => (string) $ligne->id,
                'actif' => $actif,
                'modifie_le' => (string) $ligne->filigrane,
                // Lot F4 : le poste qui a saisi le document ; `null` = saisi
                // au serveur (PWA), ou poussé avant `origines_synchronisation`
                // et au-delà de la rétention de la déduplication.
                'poste_origine' => isset($origines[(string) $ligne->id]) ? (string) $origines[(string) $ligne->id] : null,
                'donnees' => $donnees,
            ];
        }

        return $elements;
    }

    /**
     * La matrice de chaque rôle de la page : module → `C` / `L` / `-`, lue
     * par `Role::niveauSurModule` (la source de `VerifierAccesModule`).
     *
     * @param  list<string>  $ids
     * @return array<string, array<string, string>>
     */
    private function droitsDesRoles(array $ids): array
    {
        $parRole = [];

        foreach (Role::query()->with('permissions')->whereIn('id', $ids)->get() as $role) {
            foreach (GestionnaireRoles::modules() as $module) {
                $parRole[(string) $role->id][$module] = $role->niveauSurModule($module);
            }
        }

        return $parRole;
    }

    /**
     * La composition des fiches de la page — une requête, pas une par fiche.
     *
     * @param  list<object>  $recettes
     * @return array<string, list<array{article_id: string, quantite_unitaire: string}>>
     */
    private function compositions(array $recettes): array
    {
        $parRecette = [];

        DB::table('ingredients_recette')
            ->whereIn('recette_id', array_map(static fn (object $r): string => (string) $r->id, $recettes))
            ->orderBy('recette_id')
            ->orderBy('article_id')
            ->get(['recette_id', 'article_id', 'quantite_unitaire'])
            ->each(static function (object $ligne) use (&$parRecette): void {
                $parRecette[(string) $ligne->recette_id][] = [
                    'article_id' => (string) $ligne->article_id,
                    'quantite_unitaire' => (string) $ligne->quantite_unitaire,
                ];
            });

        return $parRecette;
    }

    /**
     * Les lignes des documents de la page — une requête par table.
     *
     * @param  array{table: string, cle: string, colonnes: list<string>, ordre: string}  $definition
     * @param  list<string>  $ids
     * @return array<string, list<array<string, int|string|null>>>
     */
    private function enfants(array $definition, array $ids): array
    {
        $parDocument = [];

        DB::table($definition['table'])
            ->whereIn($definition['cle'], $ids)
            ->orderBy($definition['cle'])
            ->orderBy($definition['ordre'])
            ->orderBy('id')
            ->get([$definition['cle'], ...$definition['colonnes']])
            ->each(static function (object $ligne) use (&$parDocument, $definition): void {
                $valeurs = [];

                foreach ($definition['colonnes'] as $colonne) {
                    $v = $ligne->{$colonne};
                    $valeurs[$colonne] = match (true) {
                        $v === null => null,
                        in_array($colonne, self::ENTIERS_ENFANTS, true) && $definition['table'] === 'lignes_vente' => (int) $v,
                        default => (string) $v,
                    };
                }

                $parDocument[(string) $ligne->{$definition['cle']}][] = $valeurs;
            });

        return $parDocument;
    }

    /**
     * Les lignes d'un bon de réception. Le serveur n'a PAS de table de lignes
     * de bon : ce qu'un bon a reçu, ce sont les ENTRÉES de stock que
     * `ReceptionService::receptionner()` écrit, dont le motif cite le bon
     * (`achats.motif_reception`). Elles sont relues ici — écart nommé :
     * une entrée dont le motif aurait été réécrit ne serait plus rattachée.
     *
     * @param  list<string>  $ids
     * @return array<string, list<array{article_id: string, point_id: string, quantite: string}>>
     */
    private function lignesDesBons(array $ids): array
    {
        $parBon = [];

        foreach ($ids as $id) {
            DB::table('mouvements_stock')
                ->where('type_mouvement', 'entree')
                ->where('motif', 'like', '%' . $id . '%')
                ->orderBy('created_at')
                ->orderBy('id')
                ->get(['article_id', 'point_id', 'quantite'])
                ->each(static function (object $m) use (&$parBon, $id): void {
                    $parBon[$id][] = [
                        'article_id' => (string) $m->article_id,
                        'point_id' => (string) $m->point_id,
                        'quantite' => (string) $m->quantite,
                    ];
                });
        }

        return $parBon;
    }

    /**
     * @param  array<string, array{0: string, 1: string}>  $positions
     */
    private function encoder(array $positions): string
    {
        ksort($positions);

        return rtrim(strtr(base64_encode((string) json_encode(['v' => 1, 'p' => $positions])), '+/', '-_'), '=');
    }

    /**
     * @return array<string, array{0: string, 1: string}>
     *
     * @throws InvalidArgumentException
     */
    private function decoder(?string $curseur): array
    {
        if ($curseur === null || $curseur === '') {
            return [];
        }

        $brut = base64_decode(strtr($curseur, '-_', '+/'), true);
        $contenu = $brut === false ? null : json_decode($brut, true);

        if (! is_array($contenu) || ($contenu['v'] ?? null) !== 1 || ! is_array($contenu['p'] ?? null)) {
            throw new InvalidArgumentException(__('sync.referentiels.curseur_invalide'));
        }

        $sources = [...array_keys(self::COLONNES), self::CORRESPONDANCES];
        $positions = [];

        foreach ($contenu['p'] as $source => $position) {
            $valide = in_array($source, $sources, true)
                && is_array($position)
                && array_is_list($position)
                && count($position) === 2
                && is_string($position[0])
                && preg_match('/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/', $position[0]) === 1
                && is_string($position[1])
                && preg_match('/^[0-9a-f-]{36}$/i', $position[1]) === 1;

            if (! $valide) {
                throw new InvalidArgumentException(__('sync.referentiels.curseur_invalide'));
            }

            $positions[(string) $source] = [$position[0], $position[1]];
        }

        return $positions;
    }
}
