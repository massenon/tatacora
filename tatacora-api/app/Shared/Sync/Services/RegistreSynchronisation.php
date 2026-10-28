<?php

declare(strict_types=1);

namespace App\Shared\Sync\Services;

use App\Shared\Sync\Contracts\GestionnaireSynchronisation;
use App\Shared\Sync\Gestionnaires\GestionnaireArticles;
use App\Shared\Sync\Gestionnaires\GestionnaireBonsReception;
use App\Shared\Sync\Gestionnaires\GestionnaireBulletinsPaie;
use App\Shared\Sync\Gestionnaires\GestionnaireCanauxReservation;
use App\Shared\Sync\Gestionnaires\GestionnaireCartesBoisson;
use App\Shared\Sync\Gestionnaires\GestionnaireCategoriesHebergement;
use App\Shared\Sync\Gestionnaires\GestionnaireCircuits;
use App\Shared\Sync\Gestionnaires\GestionnaireClients;
use App\Shared\Sync\Gestionnaires\GestionnaireCommandesAchat;
use App\Shared\Sync\Gestionnaires\GestionnaireConges;
use App\Shared\Sync\Gestionnaires\GestionnaireContratsLocation;
use App\Shared\Sync\Gestionnaires\GestionnaireDemandesCloture;
use App\Shared\Sync\Gestionnaires\GestionnaireDepenses;
use App\Shared\Sync\Gestionnaires\GestionnaireEmployes;
use App\Shared\Sync\Gestionnaires\GestionnaireEntretiensVehicule;
use App\Shared\Sync\Gestionnaires\GestionnaireFactures;
use App\Shared\Sync\Gestionnaires\GestionnaireFournisseurs;
use App\Shared\Sync\Gestionnaires\GestionnaireGuides;
use App\Shared\Sync\Gestionnaires\GestionnaireImmobilisations;
use App\Shared\Sync\Gestionnaires\GestionnaireIndisponibilitesCarte;
use App\Shared\Sync\Gestionnaires\GestionnaireInventaires;
use App\Shared\Sync\Gestionnaires\GestionnaireMenus;
use App\Shared\Sync\Gestionnaires\GestionnaireModelesNotification;
use App\Shared\Sync\Gestionnaires\GestionnaireMouvementsStock;
use App\Shared\Sync\Gestionnaires\GestionnairePaiements;
use App\Shared\Sync\Gestionnaires\GestionnairePaniersTable;
use App\Shared\Sync\Gestionnaires\GestionnaireParametres;
use App\Shared\Sync\Gestionnaires\GestionnairePiecesSaisie;
use App\Shared\Sync\Gestionnaires\GestionnairePlanComptable;
use App\Shared\Sync\Gestionnaires\GestionnairePlannings;
use App\Shared\Sync\Gestionnaires\GestionnairePlats;
use App\Shared\Sync\Gestionnaires\GestionnairePointsStockage;
use App\Shared\Sync\Gestionnaires\GestionnaireRecettes;
use App\Shared\Sync\Gestionnaires\GestionnaireRelancesClients;
use App\Shared\Sync\Gestionnaires\GestionnaireReglementsFournisseur;
use App\Shared\Sync\Gestionnaires\GestionnaireReservations;
use App\Shared\Sync\Gestionnaires\GestionnaireReservationsTour;
use App\Shared\Sync\Gestionnaires\GestionnaireRoles;
use App\Shared\Sync\Gestionnaires\GestionnaireSejours;
use App\Shared\Sync\Gestionnaires\GestionnaireSessionsCaisse;
use App\Shared\Sync\Gestionnaires\GestionnaireTablesSalle;
use App\Shared\Sync\Gestionnaires\GestionnaireUnitesHebergement;
use App\Shared\Sync\Gestionnaires\GestionnaireVehicules;
use App\Shared\Sync\Gestionnaires\GestionnaireVentes;
use LogicException;

/**
 * Registre FERMÉ des tables synchronisables — l'UNIQUE endroit où une table
 * devient synchronisable, en nommant son gestionnaire.
 *
 * ## Pourquoi un registre de gestionnaires (15/10/2026)
 *
 * Le registre précédent (`SynchronisationService::TABLES_SYNCHRONISABLES`,
 * table → module + service ou `null`) admettait « `null` = écriture directe ».
 * C'était la porte : toute table sans service recevait le payload brut, et
 * toute `modification` — même sur `reservations` — passait par un `UPDATE`
 * brut. La décision du Product Owner du 15/10/2026 étend la synchronisation
 * aux fournisseurs, aux commandes d'achat puis aux ventes : élargir le
 * registre sans fermer la porte aurait multiplié les contournements.
 *
 * Désormais chaque entrée nomme une classe qui implémente
 * `GestionnaireSynchronisation` : module, niveau, service et refus explicite
 * des modifications sont DÉCLARÉS, et il n'existe plus de chemin d'écriture
 * en dehors d'eux. Le nom `TABLES_SYNCHRONISABLES` est conservé : une
 * vingtaine de docblocks du dépôt s'y réfèrent (« X n'est pas au registre
 * `TABLES_SYNCHRONISABLES` »), et leur sens est inchangé.
 *
 * Toute table absente est refusée explicitement : accepter une écriture sur
 * une table inconnue reviendrait à contourner les règles de son domaine.
 *
 * ## Le catalogue (lot S2, 15/10/2026)
 *
 * Points de stockage, articles, boissons, menus, fiches, plats, catégories et
 * unités d'hébergement entrent au registre — création avec fusion sur clé
 * naturelle (`GestionnaireReferentielAbstrait`). « Création seule » ne vaut
 * plus : depuis la décision PO du 15/10/2026 (offline-first total), leurs
 * MODIFICATIONS remontent aussi, en dernier écrit gagnant sur l'horodatage
 * de saisie, par le service de chaque table. Les centres de coût n'y
 * entrent PAS : ils sont semés par le serveur et le poste les installe à
 * l'identique (`ResolveurCentresCout` les retrouve par libellé).
 *
 * ## Les documents (lot S3, 15/10/2026)
 *
 * Commandes d'achat, bons de réception, sessions de caisse, ventes et
 * dépenses — des documents SOURCES (D246) : chacun passe par son service de
 * domaine, qui produit côté serveur la pièce comptable et le mouvement de
 * stock, à la date métier. L'ordre du registre est l'ordre dans lequel un
 * poste doit les pousser : un document passe après ce qu'il cite (le
 * fournisseur et les articles avant la commande, la commande avant son bon,
 * l'ouverture de caisse avant ses ventes). La CLÔTURE d'une session est une
 * `modification` de la même entité : le poste la pousse dans l'ordre de sa
 * file (seq), APRÈS les ventes de la session — sans quoi le théorique
 * recalculé par le serveur ne les compterait pas (l'écart serait signalé).
 */
class RegistreSynchronisation
{
    /**
     * @var array<string, class-string<GestionnaireSynchronisation>>
     */
    public const TABLES_SYNCHRONISABLES = [
        'reservations' => GestionnaireReservations::class,
        // Lot F5 (17/10/2026) : l'arrivée et le départ réels, après la
        // réservation qu'ils réalisent.
        'sejours' => GestionnaireSejours::class,
        'clients' => GestionnaireClients::class,
        // 21/10/2026 : les relances d'un client (création seule), APRÈS le client.
        'relances_clients' => GestionnaireRelancesClients::class,
        'fournisseurs' => GestionnaireFournisseurs::class,
        // Catalogue (S2) — dans l'ordre où un poste doit les pousser : un
        // élément cité passe avant celui qui le cite.
        'points_stockage' => GestionnairePointsStockage::class,
        'articles' => GestionnaireArticles::class,
        'cartes_boisson' => GestionnaireCartesBoisson::class,
        'menus' => GestionnaireMenus::class,
        'recettes' => GestionnaireRecettes::class,
        'plats' => GestionnairePlats::class,
        // Lot « indisponibilités de la carte » (21/10/2026) : APRÈS les boissons
        // et les plats qu'elles citent.
        'indisponibilites_carte' => GestionnaireIndisponibilitesCarte::class,
        'categories_hebergement' => GestionnaireCategoriesHebergement::class,
        'unites_hebergement' => GestionnaireUnitesHebergement::class,
        // Documents (S3) — même règle d'ordre. Achats : la commande avant son
        // bon. Caisse : l'ouverture (creation) avant les ventes, la clôture
        // (modification) après elles, dans l'ordre de la file du poste.
        'commandes_achat' => GestionnaireCommandesAchat::class,
        'bons_reception' => GestionnaireBonsReception::class,
        // Audit de couverture (18/10/2026) : le règlement après sa commande.
        'reglements_fournisseur' => GestionnaireReglementsFournisseur::class,
        'sessions_caisse' => GestionnaireSessionsCaisse::class,
        // Lot F6 (18/10/2026) : le plan de salle, puis l'OCCUPATION d'une
        // table (le panier ouvert) avant la vente qui la libère.
        'tables_salle' => GestionnaireTablesSalle::class,
        'paniers' => GestionnairePaniersTable::class,
        'ventes' => GestionnaireVentes::class,
        'depenses' => GestionnaireDepenses::class,
        // Lot F5c : la facture APRÈS la vente qu'elle porte.
        'factures' => GestionnaireFactures::class,
        // Lot F5d : l'encaissement APRÈS sa facture (et après la caisse).
        'paiements' => GestionnairePaiements::class,
        // Tourisme (lot F4, 17/10/2026) : les définitions avant la
        // réservation qui les cite (le client est plus haut).
        'circuits' => GestionnaireCircuits::class,
        'guides' => GestionnaireGuides::class,
        'reservations_tour' => GestionnaireReservationsTour::class,
        // Audit de couverture (18/10/2026) : le parc M8, puis ses contrats
        // (après le client et le guide qu'ils citent).
        'vehicules' => GestionnaireVehicules::class,
        'contrats_location' => GestionnaireContratsLocation::class,
        'entretiens_vehicule' => GestionnaireEntretiensVehicule::class,
        // Audit de couverture (18/10/2026) : le dossier RH, puis la paie.
        'employes' => GestionnaireEmployes::class,
        'bulletins_paie' => GestionnaireBulletinsPaie::class,
        // 21/10/2026 : les plannings (RG-13) puis les congés (RG-14).
        'plannings' => GestionnairePlannings::class,
        'conges' => GestionnaireConges::class,
        // Lot 10e : le paramétrage (un enregistrement de l'écran = une
        // opération) et le référentiel des rôles. Jamais les comptes.
        'parametres_systeme' => GestionnaireParametres::class,
        'roles' => GestionnaireRoles::class,
        // Lot 10f : les mouvements de stock SAISIS sur un poste (ceux d'un
        // document s'écrivent en appliquant le document).
        'mouvements_stock' => GestionnaireMouvementsStock::class,
        // Lot 10f : la configuration M12 (jamais les messages tracés).
        'modeles_notification' => GestionnaireModelesNotification::class,
        // 28/10/2026 (D246 rouvert par le PO) : un COMPTE du plan créé sur un poste
        // (création seule, `PlanComptableService`), AVANT les pièces manuelles et
        // les immobilisations qui le citent par son numéro.
        'plan_comptable' => GestionnairePlanComptable::class,
        // 28/10/2026 : une PIÈCE saisie à la main sur un poste (brouillon ou
        // validée), rejouée par `PasserEcritureService` — le serveur passe SA pièce.
        'pieces_saisie' => GestionnairePiecesSaisie::class,
        // 21/10/2026 : les immobilisations (M10), création seule — le plan
        // d'amortissement est calculé, jamais stocké.
        'immobilisations' => GestionnaireImmobilisations::class,
        // 21/10/2026 : les canaux de réservation (Paramètres), par le nom —
        // la descente les sert AVANT les réservations qui les citent.
        'canaux_reservation' => GestionnaireCanauxReservation::class,
        // 21/10/2026 : l'inventaire physique CLÔTURÉ d'un poste, document
        // complet (en-tête + lignes) ; sa régularisation arrive en mouvements.
        'inventaires' => GestionnaireInventaires::class,
        // 26/10/2026 : la DEMANDE de clôture ou de réouverture d'un exercice
        // (M10), document source : le serveur rejoue ses règles de clôture.
        'demandes_cloture_exercice' => GestionnaireDemandesCloture::class,
    ];

    /** @var array<string, GestionnaireSynchronisation> */
    private array $instances = [];

    public function estSynchronisable(string $table): bool
    {
        return array_key_exists($table, self::TABLES_SYNCHRONISABLES);
    }

    /**
     * @throws LogicException table hors registre — le moteur vérifie avant
     */
    public function pour(string $table): GestionnaireSynchronisation
    {
        if (! $this->estSynchronisable($table)) {
            throw new LogicException(__('sync.interne.hors_registre', ['table' => $table]));
        }

        if (! isset($this->instances[$table])) {
            $gestionnaire = app(self::TABLES_SYNCHRONISABLES[$table]);

            // La clé du registre et la table déclarée par le gestionnaire ne
            // peuvent pas diverger : un gestionnaire branché sous le mauvais nom
            // écrirait dans une table avec le RBAC d'une autre.
            if ($gestionnaire->table() !== $table) {
                throw new LogicException(__('sync.interne.table_incoherente', [
                    'gestionnaire' => $gestionnaire::class,
                    'declaree' => $gestionnaire->table(),
                    'cle' => $table,
                ]));
            }

            $this->instances[$table] = $gestionnaire;
        }

        return $this->instances[$table];
    }

    /**
     * @return array<string, GestionnaireSynchronisation>
     */
    public function tous(): array
    {
        $tous = [];

        foreach (array_keys(self::TABLES_SYNCHRONISABLES) as $table) {
            $tous[$table] = $this->pour($table);
        }

        return $tous;
    }
}
