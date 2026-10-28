<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Models\User;
use App\Pwa\Livewire\Accueil;
use App\Pwa\Livewire\Achats\Achats;
use App\Pwa\Livewire\Achats\Approvisionnement;
use App\Pwa\Livewire\Bar\CarteBar;
use App\Pwa\Livewire\Comptabilite\Analytique;
use App\Pwa\Livewire\Comptabilite\Balance;
use App\Pwa\Livewire\Comptabilite\Bilan;
use App\Pwa\Livewire\Comptabilite\Cloture;
use App\Pwa\Livewire\Comptabilite\CompteResultat;
use App\Pwa\Livewire\Comptabilite\CorrespondanceComptes;
use App\Pwa\Livewire\Comptabilite\EtatsFinanciers;
use App\Pwa\Livewire\Comptabilite\FluxTresorerie;
use App\Pwa\Livewire\Comptabilite\GrandLivre;
use App\Pwa\Livewire\Comptabilite\Hub;
use App\Pwa\Livewire\Comptabilite\Journal;
use App\Pwa\Livewire\Comptabilite\NotesAnnexes;
use App\Pwa\Livewire\Comptabilite\PageComptabilite;
use App\Pwa\Livewire\Comptabilite\PlanComptable;
use App\Pwa\Livewire\Connexion;
use App\Pwa\Livewire\Crm\ClientsCreances;
use App\Pwa\Livewire\Depenses\Depenses;
use App\Pwa\Livewire\Etats\Etats;
use App\Pwa\Livewire\Etats\EtatsStudio;
use App\Pwa\Livewire\Facturation\Facturation;
use App\Pwa\Livewire\Hebergement\Hebergement as PwaHebergement;
use App\Pwa\Livewire\Hebergement\Reservations as PwaReservations;
use App\Pwa\Livewire\Notifications\Hub as NotificationsHub;
use App\Pwa\Livewire\PageMetier;
use App\Pwa\Livewire\Pos\HistoriqueVentes;
use App\Pwa\Livewire\Pos\PosComptant;
use App\Pwa\Livewire\Pos\PosHeberges;
use App\Pwa\Livewire\Restaurant\CarteRestaurant;
use App\Pwa\Livewire\Restaurant\Restauration;
use App\Pwa\Livewire\Rh\CongesPlannings;
use App\Pwa\Livewire\Rh\Paie as PwaPaie;
use App\Pwa\Livewire\Stocks\Inventaires;
use App\Pwa\Livewire\Stocks\Stocks;
use App\Pwa\Livewire\Tourisme\Departs;
use App\Pwa\Livewire\Transverse\AideAPropos;
use App\Pwa\Livewire\Transverse\ContactEditeur;
use App\Pwa\Livewire\Transverse\ImportExport;
use App\Pwa\Livewire\Transverse\JournalAudit;
use App\Pwa\Livewire\Transverse\MonProfil;
use App\Pwa\Livewire\Transverse\PageTransverse;
use App\Pwa\Livewire\Transverse\Parametres;
use App\Pwa\Livewire\Transverse\RolesPermissions;
use App\Pwa\Livewire\Transverse\EnvoiSynchronisation;
use App\Pwa\Livewire\Transverse\ReceptionSynchronisation;
use App\Pwa\Livewire\Transverse\SynchronisationPostes;
use App\Pwa\Livewire\Transverse\VerrouSession;
use App\Pwa\Livewire\Vehicules\Locations;
use App\Shared\Rbac\Models\JournalSecurite;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * La SURFACE D'ACTIONS de la PWA est une liste fermée, relue action par action.
 *
 * ## Ce que ce fichier vérifie — et ce qu'il ne prétend plus
 *
 * Il s'est appelé `PwaLectureSeuleTest`, du temps où la PWA était un canal de
 * consultation strictement en lecture seule. **Ce régime est levé** : le
 * Product Owner a tranché le 27-28/08/2026 que la PWA fait le CRUD de tous les
 * modules (sans D — aucune suppression n'existe dans ce dépôt). Le fichier a
 * été renommé d'après ce qu'il vérifie réellement, qui n'a pas changé :
 * **l'exhaustivité de la liste des actions relues**.
 *
 * ## Pourquoi une liste fermée reste nécessaire (PA-67)
 *
 * `ForcerLectureSeule` refuse toute méthode non-GET **sur les routes du groupe
 * PWA**. Or une action Livewire ne passe pas par ces routes : elle transite
 * par la route POST de Livewire, hors du groupe. Le middleware l'écrit
 * lui-même dans son bloc de documentation. Toute méthode publique d'un
 * composant PWA est donc une action atteignable depuis le navigateur, et ce
 * fichier échoue dès qu'il en existe une hors de la liste — c'est-à-dire une
 * qui n'a pas été relue.
 *
 * Ce que « relue » signifie a changé de contrat : avant, chaque entrée
 * garantissait « n'écrit rien d'autre que la session ». Désormais une action
 * PEUT écrire — et c'est `PwaEcritureAutoriseeTest` qui tient ce contrat-là :
 * toute action qui persiste (Eloquent nu OU appel d'une écriture de Service)
 * doit appeler `exigerEcriture(self::MODULE)`. Les deux fichiers sont les deux
 * moitiés de la même garde : celui-ci ferme la SURFACE, l'autre impose le
 * DROIT sur ce qui écrit.
 *
 * ## Deux registres, et ce qui les sépare (31/08/2026)
 *
 * `ACTIONS_RELUES` porte le contrat. `SURFACES_EN_COURS_DE_LIVRAISON` porte
 * les composants dont la surface s'écrit en ce moment : ils comptent comme
 * inscrits pour l'exhaustivité, leurs méthodes ne sont pas encore comparées,
 * et chaque entrée dit depuis quand et pourquoi. Le second cas les parcourt
 * comme les autres.
 *
 * L'exhaustivité se mesure désormais par DIFFÉRENCE D'ENSEMBLES, plus par
 * égalité de deux totaux : « 45 ≠ 41 » ne nommait aucun des quatre composants
 * manquants, et un ajout compensé par un retrait laissait le compte juste sur
 * une liste fausse.
 *
 * ## Le reste du fichier
 *
 * Les cas qui suivent la liste vérifient les autres garanties structurantes du
 * canal : le formulaire de connexion réel (jamais la grille de comptes
 * cliquables, `SECURITY_STRICT.md` §12), le RBAC de niveau 1 sur le menu, la
 * page de repli hors connexion, et le fait que les routes `/pwa` restent
 * GET-only — les écritures passent par les actions Livewire gardées, jamais
 * par une route d'écriture.
 *
 * @see LARAVEL_PWA.md §5, §7
 * @see tests/Feature/Pwa/PwaEcritureAutoriseeTest.php
 */
final class PwaActionsReluesTest extends TestCase
{
    use RefreshDatabase;

    /**
     * La liste FERMÉE : classe → méthodes publiques relues.
     *
     * C'est la SEULE liste de composants de ce fichier — le cas
     * `aucune_action_de_composant_pwa_ne_vient_d_un_ancetre_non_relu` en
     * dérive la sienne par `array_keys()`. Il y en a eu deux, recopiées à la
     * main : elles auraient divergé, ce n'était qu'une question de temps
     * (Article 10), et l'écart se serait lu comme « classe relue » sur un
     * composant que personne n'avait relu.
     *
     * ⚠ La plupart des composants n'exposent que `render`, et c'est
     * structurel, pas une coïncidence : les filtres des écrans sont des
     * PROPRIÉTÉS Livewire liées par `wire:model`, jamais des méthodes, et les
     * bascules d'onglet passent par `$set`, action du CADRE. La déconnexion
     * est déclarée par le trait `FermeSession`, que la réflexion rapporte
     * comme DÉCLARÉE par la classe utilisatrice — elle apparaît donc sur
     * chaque classe qui l'obtient, et ne peut pas s'obtenir en silence.
     */
    private const ACTIONS_RELUES = [
        Connexion::class => ['seConnecter', 'render'],

        // ⚠ M11 — LE TABLEAU DE BORD PORTE CINQ GESTES RAPIDES (31/08/2026).
        //
        // Ses actions ecrivent sur d'AUTRES modules que M11 : le check-in et
        // la reservation rapide sont des ecritures M1, le client rapide une
        // ecriture M3. `PwaEcritureAutoriseeTest` exige donc, pour chacune, le
        // module reellement touche EN PLUS de `self::MODULE` — exiger M11 seul
        // laisserait un role ayant le tableau de bord ecrire sur M1 sans y
        // avoir droit.
        Accueil::class => [
            'render', 'mount', 'ecransVisibles',
            'ouvrirCheckinRapide', 'confirmerCheckin',
            'ouvrirCheckoutRapide', 'confirmerCheckout',
            'ouvrirClientRapide', 'enregistrerClientRapide',
            'ouvrirReservationRapide', 'enregistrerReservationRapide',
            // Check-in DEPUIS « Chambres disponibles » (02/09/2026) — bouton
            // VERT du maître, réservation ET séjour dans la même transaction.
            'ouvrirCheckinDepuisChambre', 'confirmerCheckinDepuisChambre',
            // « Payer » (PA-165, 02/09/2026) — recouvrement M2 depuis M11.
            'ouvrirRecouvrementDuJour', 'confirmerRecouvrementDuJour',
            'ouvrirExport', 'genererExport', 'fermerModales',
        ],

        // ⚠ LE SOCLE COMMUN A TOUTES LES PAGES DE DONNEES (27/08/2026).
        //
        // `PageMetier` porte `use FermeSession` et la methode `socle()`, que
        // `PageComptabilite` et `PageTransverse` dupliquaient (Article 10).
        // Consequence DIRECTE sur cette liste : la reflexion rapporte une
        // methode de trait comme DECLAREE par la classe qui utilise le trait.
        // En remontant `use FermeSession` d'un cran, `seDeconnecter` cesse
        // d'etre declaree par les deux socles et devient declaree ICI. C'est
        // une seule declaration a relire au lieu de deux, et le second cas de
        // ce fichier verifie qu'aucune methode heritee ne vient d'ailleurs.
        PageMetier::class => ['seDeconnecter'],

        // Les deux socles intermediaires ne declarent AUCUNE methode
        // publique. Ils restent inscrits : une methode ajoutee sur l'un d'eux
        // serait une action sur toutes ses descendantes a la fois, et ce cas
        // doit rougir avant qu'elle n'atteigne la route Livewire.
        PageComptabilite::class => [],

        // VAGUE E (01/09/2026) — la saisie d'écriture, le plan comptable
        // (création de compte), les immobilisations, les clôtures et l'export
        // unifié PDF/Excel du Journal. Voir le docblock de classe de `Hub`
        // pour la levée datée de chacun des refus antérieurs.
        Hub::class => [
            'render',
            'ouvrirExport', 'genererExport',
            'ouvrirFormulairePiece', 'ajouterLignePiece', 'retirerLignePiece',
            'enregistrerPieceBrouillon', 'enregistrerPieceValidee',
            'ouvrirNouveauCompte', 'enregistrerCompte',
            'ouvrirNouvelleImmo', 'enregistrerImmo', 'ouvrirPlanAmortissement',
            'ouvrirFormulaireExercice', 'enregistrerExercice', 'cloturerExercice',
            // Lot 2 (20/10/2026) : la clôture SYSCOHADA annuelle, chaque geste
            // garde `exigerEcriture(M10)` ; rouvrir est réservé au comptable
            // par le service.
            'demarrerCloture', 'reprendreSaisie', 'rouvrirExercice',
            // Lot 4 : l'archive légale — générer (écriture M10), télécharger.
            'genererArchive', 'telechargerArchive',
            'fermerModales',
        ],
        // Correspondance des comptes (26/10/2026, decision du PO : les comptes se
        // modifient sur le web). Quatre gestes, chacun garde par
        // `exigerEcriture(self::MODULE)` (M10) : ouvrir l'edition d'un role,
        // enregistrer le compte, retablir le defaut, fermer.
        CorrespondanceComptes::class => [
            'render',
            'ouvrirEditionRole', 'enregistrerRole', 'retablirRole', 'fermerModales',
        ],
        PlanComptable::class => ['render'],
        Journal::class => ['render'],
        GrandLivre::class => ['render'],
        Balance::class => ['render'],
        CompteResultat::class => ['render'],
        Bilan::class => ['render'],
        FluxTresorerie::class => ['render'],
        NotesAnnexes::class => ['render'],
        EtatsFinanciers::class => ['render'],
        Analytique::class => ['render'],
        Cloture::class => ['render'],

        // Le socle des SEPT pages transverses — abstrait, donc jamais rendu
        // seul, relu pour la meme raison que `PageComptabilite`.
        PageTransverse::class => [],

        // Certains des sept composants transverses n'exposent que `render` :
        // leurs filtres — recherche FAQ, recherche du journal — sont des
        // PROPRIETES liees par `wire:model`, et les bascules passent par
        // `$set`.
        AideAPropos::class => ['render'],

        // Contact editeur — `envoyerMessage()`/`signalerBug()` RETABLIES le
        // 01/09/2026 : la table `messages_editeur` existe desormais
        // (migration `2026_09_04_100000`) et `MessageEditeurService` en est
        // l'unique auteur (voir son docblock). Aucun module RBAC n'encadre
        // ces deux ecritures — inscrites dans `PwaEcritureAutoriseeTest::
        // ECRITURES_HORS_MODULE`, meme famille que `MonProfil::
        // changerMotDePasse`. `ouvrirFormulaireMessage`/`ouvrirFormulaireBug`/
        // `fermerModales` n'ecrivent rien : etat d'interface seul.
        // `WithFileUploads` (la capture jointe au signalement de bug) ajoute
        // les quatre memes methodes de protocole que `Stocks`/`Depenses`.
        ContactEditeur::class => [
            'render',
            'ouvrirFormulaireMessage', 'envoyerMessage',
            'ouvrirFormulaireBug', 'signalerBug',
            'fermerModales',
            '_startUpload', '_finishUpload', '_removeUpload', '_uploadErrored',
        ],
        // Import & Export — les QUATRE onglets reels depuis le 02/09/2026
        // (directive PO). Ecritures gardees par `exigerEcriture(self::MODULE)`
        // ou par le motif `FormulaireModal` (`ouvrir*`, `validerEcriture`) :
        // import controle puis applique en transaction unique, sauvegardes
        // (generation, retrait), archives (restaurer, purger — administrateur
        // seul, reverifie dans le composant), reinitialisation (phrase VIDER,
        // modale unique au markup du maitre — l'etape intermediaire
        // `passerEtapeFinaleReinitialisation` du 01/09 est supprimee).
        // LECTURES : `telechargerSauvegarde` et `telechargerModeleCsv`
        // (fichiers/flux), `ouvrirExport` (etat d'interface), `exporterTable`
        // (contenu JSON d'une table de la liste fermee `ExportTableService`).
        ImportExport::class => [
            'render',
            'telechargerModeleCsv', 'controlerFichierImport', 'confirmerImport',
            'genererSauvegarde', 'telechargerSauvegarde',
            'retirerSauvegarde', 'confirmerRetraitSauvegarde',
            'ouvrirExport', 'exporterTable',
            'restaurerArchive', 'ouvrirPurge', 'purgerArchive',
            'ouvrirReinitialisation', 'reinitialiserDonneesTest',
            'fermerModales',
            // Livewire\WithFileUploads
            '_startUpload', '_finishUpload', '_removeUpload', '_uploadErrored',
        ],
        JournalAudit::class => ['render'],

        // Le bouton « Synchroniser » du serveur (18/10/2026, décision PO) :
        // `synchroniser()` est inscrite dans
        // `PwaEcritureAutoriseeTest::ECRITURES_HORS_MODULE` (une demande
        // horodatée, aucune donnée métier).
        // Révocation d'appairage (19/10/2026) : réservée aux Administrateurs,
        // confirmée par la modale ; `demanderRevocation`/`annulerRevocation`
        // n'écrivent rien.
        SynchronisationPostes::class => ['render', 'actualiser', 'synchroniser', 'demanderRevocation', 'annulerRevocation', 'revoquer', 'changerOnglet'],

        // Onglets « Réception » et « Envoi » de « Postes & Appairage »
        // (26/10/2026, composants imbriqués). Lecture réservée aux
        // Administrateurs et au Comptable. Les ouvertures/fermetures de
        // fenêtres n'écrivent rien ; `enregistrerCorrection`, `relancer` et
        // `ignorer` écrivent par `CorrectionReceptionService` (droit
        // d'écriture sur le module DE LA DONNÉE, 403 sinon, auteur tracé) ;
        // `redescendre` pose une demande de redescente (Administrateurs).
        ReceptionSynchronisation::class => [
            'render', 'actualiser', 'ouvrirOperation', 'fermerOperation', 'ouvrirCorrection', 'fermerCorrection',
            'enregistrerCorrection', 'relancer', 'ouvrirIgnorer', 'fermerIgnorer', 'ignorer',
        ],
        EnvoiSynchronisation::class => [
            'render', 'actualiser', 'voirPoste', 'fermerPoste', 'demanderRedescente', 'annulerRedescente', 'redescendre',
        ],

        // Mon profil — le changement de mot de passe (01/09/2026, directive
        // du Product Owner). `changerMotDePasse()` n'exige AUCUN module RBAC
        // (voir son docblock) : elle est inscrite dans
        // `PwaEcritureAutoriseeTest::ECRITURES_HORS_MODULE`, jamais gardee
        // par `exigerEcriture()`, meme famille que `seConnecter`/
        // `deverrouiller`. `ouvrirFormulaireMotDePasse` et `fermerModales`
        // n'ecrivent rien : etat d'interface seul.
        MonProfil::class => ['render', 'mount', 'ouvrirFormulaireMotDePasse', 'fermerModales', 'changerMotDePasse', 'enregistrerInformations'],

        // Le voile de verrouillage — monté une seule fois par
        // `layouts.pwa`, sur CHAQUE écran authentifié. `deverrouiller()`
        // ne relève d'aucun module (voir son docblock, même famille que
        // `seConnecter`/`seDeconnecter`).
        VerrouSession::class => ['render', 'deverrouiller'],

        // Les deux widgets IMBRIQUÉS de la barre supérieure (audit PO du
        // 01/09/2026) — premiers composants non montés par une route.
        // `marquerToutLu`/`marquerLu` n'écrivent que l'état « vu » du compte
        // qui fait le geste (`alertes_vues`) : voir `ECRITURES_HORS_MODULE`.
        \App\Pwa\Livewire\Transverse\ClocheNotifications::class => ['render', 'marquerToutLu', 'marquerLu'],
        \App\Pwa\Livewire\Transverse\RechercheGlobale::class => ['render'],
        // Le sélecteur d'exercice global (20/10/2026) — quatrième widget de la
        // barre. Choisir et revenir n'écrivent que la SESSION
        // (`ExerciceConsulte`) ; voir `METHODES_DE_LECTURE`.
        \App\Pwa\Livewire\Transverse\SelecteurExercice::class => ['render', 'mount', 'updatedExerciceId', 'revenir'],
        // Les modales d'ouverture de session (02/09/2026) — troisieme
        // composant de chassis. Les deux ecritures sont declarees au
        // registre multi-modules de PwaEcritureAutoriseeTest.
        \App\Pwa\Livewire\Transverse\AlertesOuvertureModales::class => [
            'render', 'avancer', 'effectuerCheckOutOuverture', 'tracerRelanceOuverture',
        ],
        // ROLES — edition reelle depuis le 01/09/2026. `retablirSocle` appelle
        // `exigerEcriture(self::MODULE)` directement ; les cinq autres
        // ecritures delegue a `ouvrirFormulaire()`/`validerEcriture()`.
        RolesPermissions::class => [
            // « Tout retirer » (modale-role du maitre) : pose la SAISIE a
            // « - », n'ecrit rien en base ; verrou administrateur/ROLES tenu.
            'toutRetirer',
            'fermerModales',
            'render',
            'ouvrirFormulaireRole', 'enregistrerRole',
            'ouvrirFormulaireDroits', 'enregistrerDroits',
            'ouvrirRetablirSocle', 'retablirSocle',
        ],

        // PARAM — l'edition d'un parametre. Le registre des cles modifiables
        // est ferme cote serveur (`RegistreParametres`, PA-124) : cet ecran
        // n'en ouvre aucune de plus.
        //
        // Les quatre actions `*Canal` (01/09/2026) ouvrent la gestion du
        // referentiel `canaux_reservation` (PA-163), jusque-la refusee faute
        // de table a modifier — voir `CanalReservationService`.
        Parametres::class => [
            'render',
            'ouvrirEditionParametre', 'enregistrerParametre', 'fermerModales',
            'ouvrirAjoutCanal', 'ouvrirRenommageCanal', 'enregistrerCanal', 'basculerCanal',
            // Confirmation de desactivation par la MODALE du depot — jamais
            // wire:confirm (boite native, MotifsInterditsPwaTest). Pose un
            // identifiant en attente, n'ecrit rien ; garde exigerEcriture.
            'demanderDesactivationCanal',
            // Les SEPT onglets deviennent reels (02/09/2026, directive PO).
            // Bascules d'activation, appliquees AU CLIC comme le maitre le
            // documente — ecriture par `EnregistrerParametreService`, cle
            // verifiee contre le groupe `activation` du registre ferme.
            'basculerOption',
            // L'envoi de test REEL : n'ecrit rien en base, mais envoie un
            // courriel — garde `exigerEcriture(self::MODULE)` quand meme, un
            // profil en lecture n'a pas a declencher d'envoi.
            'envoyerEmailTest',
            // Mot de passe SMTP saisi, CHIFFRE en base (19/10/2026, decision
            // du PO) : `exigerEcriture(self::MODULE)` ET rôle
            // d'administration ; la valeur n'est jamais rechargee.
            'enregistrerMotDePasseSmtp', 'effacerMotDePasseSmtp',
            // Logo & Apparence — televersement reel via `WithFileUploads`
            // (fichiers remplaces, jamais accumules ; servis par la route
            // `pwa.apparence`, sans storage:link).
            'ouvrirChangementLogo', 'enregistrerLogo',
            'ouvrirChangementFavicon', 'enregistrerFavicon',
            // Espaces & tables — CRUD reel du referentiel `tables_salle`
            // (`TableSalleService`, l'unique auteur des regles du maitre :
            // unicite du numero, libelle qui suit le numero, refus de
            // desactiver une table au panier ouvert, retablissement du jeu
            // initial du seeder).
            'ouvrirAjoutTable', 'ouvrirRenumerotationTable', 'enregistrerTable',
            'basculerTable', 'ouvrirRetablirTables', 'retablirTables',
            // Statique et pure (aucune E/S) : mappe une definition du
            // registre a son onglet du maitre. Publique pour que
            // `TransversePwaTest` la confronte au maitre sans dupliquer la
            // regle — ce n'est pas une action Livewire, ForcerLectureSeule
            // n'a rien a y relire.
            'ongletDe',
            // Livewire\WithFileUploads — protocole du cadre, meme remarque
            // que `Stocks` : methodes de trait rapportees comme declarees.
            '_startUpload', '_finishUpload', '_removeUpload', '_uploadErrored',
        ],

        // ⚠ M6 — LES METHODES DE TRAIT DU CADRE COMPTENT COMME DECLAREES.
        //
        // `Stocks` utilise `WithPagination` et `WithFileUploads` de Livewire.
        // La reflexion rapporte une methode de trait comme DECLAREE par la
        // classe qui l'utilise : `getPage`, `gotoPage`, `nextPage`,
        // `previousPage`, `queryStringHandlesPagination`, `resetPage`,
        // `setPage` d'une part, `_startUpload`, `_finishUpload`,
        // `_removeUpload`, `_uploadErrored` d'autre part apparaissent donc
        // ici. Ce ne sont pas des actions metier — c'est le protocole du
        // cadre — mais ce sont bien des methodes publiques atteignables par la
        // route Livewire, et les omettre ferait rougir la liste. Les inscrire
        // les rend visibles : le jour ou un composant recevra `WithFileUploads`
        // sans en avoir besoin, cette liste le dira.
        Stocks::class => [
            'render',
            'editerArticle', 'enregistrerArticle', 'enregistrerMouvement', 'forcerMouvement',
            'nouvelArticle', 'ouvrirMouvement', 'fermerModales',
            'genererExport', 'ouvrirExport', 'lancerImport', 'ouvrirImport', 'telechargerModeleCsv',
            'messages',
            // ARCHIVAGE du referentiel (03/09/2026, demande du Product Owner).
            // Les deux premieres passent par `exigerArchivage()` — RBAC
            // `M6 = C` PUIS role/bascule ; `restaurerArticle` n'exige QUE
            // l'ecriture, deliberement (PA-59/60/61).
            'confirmerArchivageArticle', 'archiverArticles', 'restaurerArticle',
            'updatedCategorie', 'updatedEtat', 'updatedPoint', 'updatedRecherche',
            // Le crochet de la case « tout selectionner », ajoute avec la
            // selection multiple : declare, donc atteignable, donc relu.
            'updatedToutSelectionne',
            // Livewire\WithPagination
            'getPage', 'gotoPage', 'nextPage', 'previousPage',
            'queryStringHandlesPagination', 'resetPage', 'setPage',
            // Livewire\WithFileUploads
            '_startUpload', '_finishUpload', '_removeUpload', '_uploadErrored',
        ],
        Inventaires::class => [
            'render', 'mount',
            'ouvrirInventaire', 'ouvrirComptage', 'enregistrerComptage',
            'demanderCloture', 'cloturer',
            'ouvrirExport', 'genererExport', 'fermerModales',
            'messages',
        ],

        // M10 — la depense courante. Meme remarque que `Stocks` sur
        // `WithFileUploads` (le justificatif). `valeursDistinctes` alimente
        // les listes de filtres de la vue.
        Depenses::class => [
            'render', 'mount', 'messages',
            'ouvrirFormulaireDepense', 'enregistrerDepense', 'comptabiliserDepense',
            // Multi-lignes — décision du Product Owner du 31/08/2026, qui
            // renverse la lecture mono-ligne du maître. Les deux gestes de
            // lignes ne persistent rien (état du formulaire), mais portent
            // quand même `exigerEcriture(self::MODULE)` : motif de la maison,
            // un formulaire d'écriture ne se manipule pas sans le droit.
            'ajouterLigneDepense', 'retirerLigneDepense',
            'ouvrirExport', 'genererExport', 'fermerModales',
            'valeursDistinctes',
            '_startUpload', '_finishUpload', '_removeUpload', '_uploadErrored',
        ],

        // ⚠ LES DEUX PREMIERES ACTIONS D'ECRITURE DE LA PWA (27/08/2026),
        // premieres d'une serie que le plan CRUD etend vague par vague.
        //
        // Cette liste garde tout son sens — elle force la RELECTURE de chaque
        // methode publique — mais une entree ne signifie plus « n'ecrit pas ».
        // Le contrat d'ecriture est tenu par `PwaEcritureAutoriseeTest` :
        // toute action qui persiste, par Eloquent OU par un Service de
        // domaine, doit exiger `exigerEcriture(self::MODULE)` — ici `M7 = C`,
        // le meme niveau que les routes `POST/PUT /api/v1/fournisseurs`.
        Achats::class => [
            'render',
            'ouvrirFormulaireFournisseur',
            'enregistrerFournisseur',
            // ARCHIVAGE du referentiel (03/09/2026, demande du Product Owner
            // « mettre le bouton Supprimer sur chaque table, ou la suppression
            // en bulk »). Les deux premieres passent par `exigerArchivage()`
            // — RBAC `M7 = C` PUIS role/bascule ; `restaurerFournisseur`
            // n'exige QUE l'ecriture, deliberement : fermer la bascule ne doit
            // pas enfermer un fournisseur aux archives (PA-59/60/61).
            'confirmerArchivageFournisseur', 'archiverFournisseurs', 'restaurerFournisseur',
            'genererExport', 'fermerModales',
            // `updated` et `updatedToutSelectionne` sont les crochets Livewire
            // de la selection par cases a cocher du maitre : declares, donc
            // atteignables, donc relus.
            'updated', 'updatedToutSelectionne',
        ],
        Approvisionnement::class => [
            'render',
            'ouvrirFormulaireCommande', 'enregistrerCommande',
            'ouvrirFormulaireReception', 'enregistrerReception',
            // « Régler » — PA-165, 02/09/2026, ReglementFournisseurService.
            'ouvrirFormulaireReglement', 'enregistrerReglement',
            'ouvrirExport', 'genererExport', 'fermerModales',
            'messages',
            'updated', 'updatedToutSelectionne',
        ],

        // M2 — l'avoir est le SEUL geste d'ecriture de la facturation :
        // RG-03 fige une facture emise, la correction passe par contre-piece.
        Facturation::class => [
            'render',
            'ouvrirFormulaireAvoir', 'enregistrerAvoir',
            'imprimerFacture', 'fermerModales',
            // Selection + pagination du tableau generique (G6, 01/09/2026) —
            // memes crochets de cadre que `Achats`.
            'updated', 'updatedToutSelectionne',
            // Export unifié (dérogation PO du 01/09/2026, rappelée le
            // 02/09/2026) : `exporterExcel` est devenue `ouvrirExport` +
            // `genererExport` — un bouton « Exporter », la modale partagée,
            // le format PDF/Excel choisi dedans. Le PDF est le REGISTRE
            // affiché, jamais une facture (voir `Facturation::genererExport()`).
            'ouvrirExport', 'genererExport',
        ],

        // Les DEUX pages M4. `CarteRestaurant` porte les huit actions du trait
        // `EcranDeCarte` (partage avec le bar) PLUS les deux qui lui sont
        // propres : le lien au stock d'un plat se DELIE, celui d'une boisson
        // non (`cartes_boisson.article_id` est NOT NULL — arbitrage ouvert).
        // « Historique des prix » (01/09/2026, demande du Product Owner) —
        // ouvre une modale de LECTURE, comme `ouvrirHistoriqueClient` sur M3.
        CarteRestaurant::class => [
            'render',
            'ouvrirLienAuStock', 'enregistrerLienAuStock',
            'ouvrirRetraitDeLaCarte', 'enregistrerRetraitDeLaCarte', 'remettreALaCarte',
            'ouvrirRetraitDuLien', 'confirmerRetraitDuLien',
            // Modifier le prix (PO 02/09/2026) : le geste qui alimente
            // l'historique — delegue a ouvrirFormulaire/validerEcriture.
            'ouvrirModificationPrix', 'enregistrerModificationPrix', 'fermerModales',
            'ouvrirHistoriquePrix',
            'genererExport', 'imprimerFichePrix',
            // Onglet « Ventes du Restaurant » (03/09/2026, Product Owner) :
            // `updated()` est le crochet du CADRE Livewire qui remet la
            // pagination a 1 quand un filtre de l'onglet change. Il n'ecrit
            // que l'etat d'affichage — meme famille que `Facturation::
            // updated()`. Les filtres eux-memes sont des proprietes `#[Url]`,
            // pas des actions : ils n'ajoutent aucune surface.
            'updated',
        ],
        Restauration::class => [
            'render',
            'ouvrirCreationPlat', 'ouvrirModificationPlat', 'enregistrerPlat',
            'ouvrirRetraitDuPlat', 'confirmerRetraitDuPlat',
            // Selection + pagination du tableau generique (G6, 01/09/2026).
            'updated', 'updatedToutSelectionne',
            // LA SORTIE D'IMPASSE (03/09/2026) — `plats.menu_id` et
            // `plats.recette_id` sont NOT NULL, et aucun ecran de la PWA ne
            // creait ni menu ni recette : sur une base neuve, le formulaire de
            // plat ouvrait deux selecteurs vides dont rien ne permettait de
            // sortir. Les six actions ECRIVENT ou gardent une ecriture, et
            // chacune appelle `exigerEcriture(self::MODULE)` ou delegue au
            // motif `FormulaireModal` (verifie par `PwaEcritureAutoriseeTest`).
            'ouvrirCreationMenu', 'enregistrerMenu',
            'ouvrirCreationRecette', 'enregistrerRecette',
            'ajouterIngredient', 'retirerIngredient',
            'fermerFormulaireSecondaire',

            // LE DEBLOCAGE DU POS RESTAURANT (04/09/2026, Product Owner).
            // Releve en base : 83 plats, 83 recettes, TROIS lignes
            // d'ingredients — chaque fiche existait et etait VIDE, donc
            // chaque vente etait refusee (`RecetteManquanteException`). La
            // creation, livree le 03/09, ne rendait pas les 83 fiches
            // existantes atteignables : c'est la MODIFICATION qui manquait.
            // Les deux actions ouvrent un formulaire declare, donc passent
            // par `ouvrirFormulaire()` — le delegue garde du motif
            // `FormulaireModal`, verifie par `PwaEcritureAutoriseeTest`.
            'ouvrirModificationRecette', 'ouvrirModificationMenu',
        ],

        // M8 — le parc, le contrat de location et l'immobilisation.
        // `confirmerArchivage`/`executerSuppression` ne SUPPRIMENT rien :
        // « supprimer » est archiver (BasePolicy::delete() rend false pour les
        // 20 policies), et le nom de la seconde methode est le seul endroit ou
        // le mot subsiste.
        Locations::class => [
            'render', 'mount',
            'ouvrirFormulaireVehicule', 'enregistrerVehicule', 'remettreEnService',
            'ouvrirFormulaireContrat', 'enregistrerContrat',
            'ouvrirFormulaireImmobilisation', 'enregistrerImmobilisation',
            'confirmerArchivage', 'executerSuppression',
            'genererExport', 'fermerModales',
        ],

        // ⚠ LES DEUX PAGES M14 — un cas a part, et il le reste sous le
        // nouveau regime. `GenerateurEtatService::generer()` l.80 execute
        // `EtatGenere::create()` : generer ECRIT. Ces deux composants
        // n'appellent QUE `CatalogueEtatsService` et
        // `EtatInterface::calculer()`, et n'exposent que `render` — la
        // selection d'un etat est une PROPRIETE `#[Url]`, la bascule passe
        // par `$set`. Un `generer()` ajoute ici devra etre inscrit ET garde
        // (`PwaEcritureAutoriseeTest` verra l'appel de Service).
        EtatsStudio::class => ['render'],
        Etats::class => ['render'],

        // M9 — les deux crochets `updatedCircuitIdResa` / `updatedDateDepartResa`
        // recalculent la capacite restante du DEPART (cumulee, PA-51) des que
        // l'un des deux champs change : une capacite verifiee reservation par
        // reservation laisserait passer trois groupes de 5 sur 12 places.
        Departs::class => [
            'render', 'mount',
            'ouvrirFormulaireReservation', 'enregistrerReservation',
            'updatedCircuitIdResa', 'updatedDateDepartResa',
            'ouvrirAjoutGuide', 'fermerAjoutGuide', 'enregistrerGuide',
            'ouvrirFormulaireGuide', 'enregistrerReaffectationGuide',
            'ouvrirFormulairePrestation', 'enregistrerPrestation',
            'confirmerArchivage', 'executerSuppression',
            'genererExport', 'fermerModales',
        ],

        // Les QUATRE pages livrees le 28/08/2026 — M1, M3 et M5. Meme
        // structure que partout : filtres et onglets sont des PROPRIETES
        // `#[Url]` liees par `wire:model`, les bascules passent par `$set`.
        //
        // ⚠ LA VAGUE 2 (28/08/2026) : l'ecran Reservations porte les trois
        // gestes serveur de M1 — creer, modifier, annuler — via
        // `ReservationService` (RG-01 sous verrou, RG-02). Chaque action
        // exige `M1 = C` : les deux d'ouverture et l'enregistrement par les
        // delegues gardes de `FormulaireModal`, l'annulation en direct.
        // `PwaEcritureAutoriseeTest` le verifie corps par corps.
        PwaReservations::class => [
            'render',
            'ouvrirCreationReservation',
            'ouvrirModificationReservation',
            'enregistrerReservation',
            // PA-163 (01/09/2026) : la fiche COMPLETE du maitre — grille de
            // services et lignes. Les trois gestes manipulent l'etat du
            // formulaire (aucune ecriture en base : elle passe par
            // `enregistrerReservation` → `remplacerLignes`), et chacun exige
            // `M1 = C` en toutes lettres.
            'basculerServiceFiche',
            'ajouterLigneFiche',
            'retirerLigneFiche',
            'annulerReservation',
            'confirmerAnnulation',
            'ouvrirCreationClient', 'enregistrerClient',
            'imprimerConfirmation',
            'genererExport', 'fermerModales',
        ],

        // M1 — le PLAN d'hebergement. `effectuerCheckIn` / `effectuerCheckOut`
        // sont les DEUX gestes qui n'existaient nulle part dans ce depot
        // jusqu'a cette vague : `sejours.date_checkin_reel` et
        // `date_checkout_reel` existaient depuis toujours, mais aucune route
        // ni aucun service ne les ecrivait. `marquerNettoye` ecrit
        // `unites_hebergement.statut`, la colonne dont PA-118 disait que
        // « personne ne l'ecrit » — ce n'est plus vrai.
        PwaHebergement::class => [
            'render',
            'ouvrirFormulaireUnite', 'enregistrerUnite',
            'ouvrirReservationRapide', 'enregistrerReservationRapide',
            'effectuerCheckIn', 'effectuerCheckOut', 'marquerNettoye',
            'archiverUnite', 'confirmerArchivageUnite', 'restaurerUnite',
            'genererExport', 'fermerModales',
        ],
        // Export unifié (dérogation PO du 01/09/2026, rappelée le
        // 02/09/2026) : `exporterExcel` est devenue `ouvrirExport` +
        // `genererExport` — la modale partagée, PDF réel ajouté (voir
        // `ClientsCreances::genererExport()`). Les six actions
        // suivantes sont PA-165 (02/09/2026) : recouvrement (M2 depuis M3),
        // relance et création de client (M3), plus la lecture d'historique.
        ClientsCreances::class => [
            'render', 'ouvrirExport', 'genererExport',
            'ouvrirFormulaireClient', 'enregistrerClient',
            'ouvrirRecouvrement', 'updatedRecouvrementFactureId', 'enregistrerRecouvrement',
            'ouvrirRelance', 'enregistrerRelance',
            'ouvrirHistoriqueClient', 'imprimerReleveClient', 'fermerModales',
            // ARCHIVAGE du referentiel (03/09/2026, demande du Product Owner).
            // Les deux premieres passent par `exigerArchivage()` — RBAC
            // `M3 = C` PUIS role/bascule ; `restaurerClient` n'exige QUE
            // l'ecriture, deliberement (PA-59/60/61). `updatedToutSelectionne`
            // est le crochet de la case d'entete, comme en `Achats`.
            'confirmerArchivageClient', 'archiverClients', 'restaurerClient',
            'updatedToutSelectionne',
        ],

        // M5 — les huit actions du trait `EcranDeCarte`, sans les deux du
        // retrait de lien : au bar, `cartes_boisson.article_id` est NOT NULL,
        // « Delier » n'a pas de cible au schema (arbitrage ouvert).
        // « Historique des prix » (01/09/2026) — voir la note sur
        // `CarteRestaurant`, même trait, même action.
        CarteBar::class => [
            'render',
            // Creation de boisson (PO 03/09/2026) : le geste manquait
            // entierement a la PWA — l'API et l'import CSV etaient les seules
            // voies. Delegue a `ouvrirFormulaire`/`validerEcriture`.
            'ouvrirCreationBoisson', 'enregistrerCreationBoisson',
            // Modifier la boisson (PO 08/10/2026) : libelle + categorie.
            'ouvrirModificationBoisson', 'enregistrerModificationBoisson',
            'ouvrirLienAuStock', 'enregistrerLienAuStock',
            'ouvrirRetraitDeLaCarte', 'enregistrerRetraitDeLaCarte', 'remettreALaCarte',
            // Modifier le prix (PO 02/09/2026) — meme motif qu'au restaurant.
            'ouvrirModificationPrix', 'enregistrerModificationPrix', 'fermerModales',
            'ouvrirHistoriquePrix',
            'genererExport', 'imprimerFichePrix',
            // Onglet « Ventes du Bar » (03/09/2026, Product Owner) — meme
            // trait, meme action : voir la note sur `CarteRestaurant`.
            'updated',
        ],

        // ⚠ LES TROIS ECRANS DE VENTE (M2/M5), livres le 31/08/2026.
        //
        // C'est la plus grosse surface d'actions du canal, et c'est normal :
        // un panier se compose au clic. `encaisserMalgreRupture` est le seul
        // point ou un stock negatif est accepte — il est SEPARE d'`encaisser`
        // exprES, pour qu'un depassement soit un second geste explicite et
        // trace, jamais un effet de bord du premier.
        PosComptant::class => [
            'render',
            'ouvrirCaisse', 'ouvrirFormulaireOuvertureCaisse',
            'ouvrirFormulaireClotureCaisse', 'cloturerCaisse',
            'ajouterAuPanier', 'incrementerLigne', 'decrementerLigne', 'retirerLigne',
            'viderPanier', 'abandonnerPanier',
            // Remise du panier (PO 02/09/2026) — ecrit `paniers.remise_*`
            // via `PanierService::appliquerRemise()`, garde `exigerEcriture(M5)`.
            'appliquerRemise',
            'encaisser', 'encaisserMalgreRupture',
            'ouvrirAnnulationVente', 'annulerVente',
            'ouvrirJournalDuJour', 'imprimerTicketA4', 'fermerModales',
        ],
        PosHeberges::class => [
            'render', 'mount',
            'ajouterAuPanier', 'incrementerLigne', 'decrementerLigne', 'retirerLigne',
            // Remise du panier de sejour (PO 02/09/2026) — meme garde que le
            // comptoir : `exigerEcriture(M5)` puis `PanierService`.
            'appliquerRemise',
            'ouvrirClotureSejour', 'cloturerEtFacturer', 'fermerModales',
        ],
        HistoriqueVentes::class => [
            'render',
            'annulerVente', 'telechargerTicket',
            'ouvrirExport', 'genererExport', 'fermerModales',
        ],

        // Les DEUX ecrans qui NOMMENT leur refus (31/08/2026). Leurs routes
        // pointaient toutes deux sur `JournalAudit` : « Personnel & Paie » et
        // « Notifications » servaient le Journal d'Audit. Ils n'exposent que
        // `render` — et c'est structurel : M12 n'a ni table ni service, et le
        // total de charge patronale de M13 est REFUSE par `CalculPaieService`
        // (PA-53). Une action ajoutee ici devra etre relue, et gardee si elle
        // ecrit.
        // M13 — reel depuis le 31/08/2026 (l'ecran de refus est remplace).
        // Listes verifiees par reflexion contre le code, pas recopiees du
        // rapport d'agent. La consultation d'un bulletin passe par `$set`,
        // pas par une action : une methode publique est presumee ecrire, et
        // la garder aurait interdit a un `comptable` en L de lire un
        // bulletin que la page lui affiche deja.
        PwaPaie::class => [
            'render', 'mount',
            'ouvrirFormulaireEmploye', 'enregistrerEmploye',
            'ouvrirEtablissementBulletin', 'etablirBulletin', 'genererBulletinsManquants',
            'ouvrirAnnulationBulletin', 'annulerBulletin',
            'ouvrirExport', 'genererExport', 'exporterPdf', 'fermerModales',
            // Archivage du personnel (PO 02/09/2026) : supprimer = archiver
            // (statut « parti », RG-15), derriere la bascule de suppression.
            // `ouvrirArchivageEmployes` delegue a `ouvrirFormulaire()` ;
            // `archiverEmployes` appelle `exigerEcriture(self::MODULE)` ET
            // la bascule ; `updatedToutSelectionne` est un cycle de vie.
            'updatedToutSelectionne', 'ouvrirArchivageEmployes', 'archiverEmployes',
        ],
        // M13 — Conges & Plannings (21/10/2026). `ouvrirPlanification` et
        // `ouvrirDemandeConge` deleguent a `ouvrirFormulaire()` ; les deux
        // `enregistrer*` a `validerEcriture()` ; `validerConge` et
        // `refuserConge` appellent `exigerEcriture(self::MODULE)` directement.
        CongesPlannings::class => [
            'render',
            'ouvrirPlanification', 'enregistrerPlanning',
            'ouvrirDemandeConge', 'enregistrerConge',
            'validerConge', 'refuserConge', 'fermerModales',
        ],
        // M12 — referentiel reel (modeles, declencheurs, journal). La FILE
        // D'ATTENTE (01/09/2026) — cinq actions reelles. `detecterMaintenant`
        // appelle `exigerEcriture(self::MODULE)` directement ; les quatre
        // autres delegue a `ouvrirFormulaire()`/`validerEcriture()` du motif
        // `FormulaireModal`, deja gardes. `envoyerMessage` (01/09/2026,
        // directive PO « pour le moment utilise le SMTP ») appelle aussi
        // `exigerEcriture(self::MODULE)` directement — seul le canal e-mail
        // est reellement envoye, voir `EnvoiEmailNotificationService`.
        NotificationsHub::class => [
            'render',
            'ouvrirFormulaireModele', 'enregistrerModele', 'basculerModele',
            'detecterMaintenant', 'envoyerMessage',
            'ouvrirTransmission', 'enregistrerTransmission',
            'ouvrirAbandon', 'enregistrerAbandon',
            'ouvrirExport', 'genererExport', 'fermerModales',
        ],
    ];

    /**
     * Les composants dont la SURFACE est en cours de reecriture — inscrits
     * comme composants, mais dont les methodes ne sont pas encore relues.
     *
     * ## Pourquoi ce registre existe, et pourquoi il doit se vider
     *
     * La liste ci-dessus est le contrat : « toute methode publique a ete
     * relue ». On ne peut pas relire ce qui s'ecrit pendant qu'on lit. Ce
     * registre nomme donc ces composants **un par un, avec la date et la
     * raison**, plutot que de laisser le decompte global echouer sur un total
     * opaque — « 45 composants sur disque pour 41 inscrits » ne dit a personne
     * LESQUELS manquent, et c'est le genre de message qui fait relacher le
     * plancher au lieu de fermer la liste.
     *
     * ⚠ **Un registre de ce genre est un motif de refus, et un motif de refus
     * qui a cesse d'etre vrai transforme une decision en oubli** (PA-107,
     * PA-120, PA-144 — trois fois dans ce depot). Chaque entree porte donc sa
     * date. Le cas `le_registre_des_surfaces_en_cours_est_date_et_non_vide`
     * refuse une entree sans date, et le cas principal refuse une entree qui
     * ne designe plus un composant existant.
     *
     * Ce qui reste garanti pour ces composants, malgre l'attente :
     *   - le second cas les parcourt comme les autres — aucune de leurs
     *     methodes publiques ne peut venir d'un ancetre non relu ;
     *   - `PwaEcritureAutoriseeTest` les garde integralement : une action qui
     *     persiste y exige `exigerEcriture(self::MODULE)`, inscrite ici ou
     *     non. C'est le contrat des DROITS, et il ne connait pas ce registre.
     *
     * @var array<class-string, string>
     */
    private const SURFACES_EN_COURS_DE_LIVRAISON = [
        // VIDE au 31/08/2026, et c'est l'etat souhaite : les trois composants
        // qui y ont sejourne le temps de la vague M11 — `Accueil`,
        // `Parametres`, `ImportExport` — ont ete relus et inscrits ci-dessus
        // le jour meme. Ce registre n'existe que pour nommer une attente ; une
        // attente qui dure est un oubli (PA-107, PA-120, PA-144).
    ];

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    /**
     * PA-67 — le chemin d'ecriture reel de la PWA, ce sont les actions
     * Livewire, et AUCUN middleware ne les couvre.
     *
     * `ForcerLectureSeule` refuse toute methode non-GET **sur les routes du
     * groupe PWA**. Une action Livewire transite par la route POST de
     * Livewire, hors du groupe : elle ne passe jamais par lui. Ce cas rend la
     * surface d'actions FERMEE au seul moment ou elle peut l'etre — quand la
     * methode est ecrite : toute nouvelle methode publique sur un composant
     * PWA doit etre inscrite ici, donc relue.
     *
     * Depuis la levee de la lecture seule (27-28/08/2026), une action
     * inscrite peut ecrire ; le droit d'ecrire est le contrat de
     * `PwaEcritureAutoriseeTest`, jamais celui de cette liste.
     *
     * @see LARAVEL_PWA.md §7
     */
    #[Test]
    public function aucun_composant_pwa_n_expose_d_action_hors_de_la_liste_relue(): void
    {
        // ⚠ LE BALAYAGE EST RECURSIF DEPUIS LE 27/08/2026, ET IL NE L'ETAIT PAS.
        //
        // `glob(app_path('Pwa/Livewire/*.php'))` ne descend PAS dans les
        // sous-dossiers. Un composant pose dans `Pwa/Livewire/Comptabilite/`
        // n'etait donc jamais releve : le decompte restait a deux, l'egalite
        // passait, et le composant — avec toutes ses methodes publiques —
        // echappait entierement a cette liste fermee. C'est le defaut que ce
        // test existe pour empecher, dans le test lui-meme : une garde qui dit
        // « tout va bien » sans avoir regarde (PA-59/60/61).
        $composants = $this->composantsPwa();
        $this->assertNotEmpty($composants, 'Aucun composant PWA trouve : le test ne verifie plus rien.');

        // Plancher : sans lui, un dossier renomme rendrait le balayage vide,
        // donc vert — meme piege que le decompte ci-dessus.
        $this->assertGreaterThanOrEqual(
            35,
            count($composants),
            'Moins de composants PWA que prevu : le balayage a perdu un dossier.',
        );

        // ⚠ ON COMPARE DEUX ENSEMBLES, PLUS DEUX NOMBRES (31/08/2026).
        //
        // `assertCount()` rendait « 45 n est pas identique a 41 » — un total
        // opaque qui ne nomme aucun des quatre composants manquants et qui,
        // pire, se satisfait d'une compensation : un composant ajoute et un
        // autre retire laissent le compte juste et la liste fausse. La
        // comparaison ci-dessous nomme les deux sens.
        $inscrits = array_merge(
            array_keys(self::ACTIONS_RELUES),
            array_keys(self::SURFACES_EN_COURS_DE_LIVRAISON),
        );

        $absents = array_values(array_diff($composants, $inscrits));
        $fantomes = array_values(array_diff($inscrits, $composants));

        $this->assertSame(
            [],
            $absents,
            count($absents).' composant(s) PWA existent sans etre inscrits dans la liste relue : '
            .implode(', ', $absents)."\n"
            .'Chaque methode publique de ces classes est atteignable par la route Livewire et '
            .'echappe donc a `ForcerLectureSeule` (PA-67). Les relire, puis les inscrire dans '
            .'ACTIONS_RELUES — ou, si leur surface est en cours de reecriture, dans '
            .'SURFACES_EN_COURS_DE_LIVRAISON avec la date et la raison.',
        );

        $this->assertSame(
            [],
            $fantomes,
            count($fantomes).' classe(s) inscrites ne designent aucun composant sur disque : '
            .implode(', ', $fantomes)."\n"
            .'Une entree qui ne correspond plus a rien fait croire la liste plus complete '
            .'qu elle ne l est.',
        );

        foreach (self::ACTIONS_RELUES as $composant => $attendues) {
            $reflet = new \ReflectionClass($composant);

            $publiques = [];
            foreach ($reflet->getMethods(\ReflectionMethod::IS_PUBLIC) as $methode) {
                // Seules les methodes DECLAREES par le composant sont
                // exposees comme actions ; celles heritees de Livewire sont
                // du cadre, pas de la surface metier.
                if ($methode->getDeclaringClass()->getName() === $composant) {
                    $publiques[] = $methode->getName();
                }
            }

            sort($publiques);
            $triees = $attendues;
            sort($triees);

            $this->assertSame(
                $triees,
                $publiques,
                "Le composant PWA {$composant} expose une action non relue. "
                .'Une action Livewire echappe a ForcerLectureSeule : la relire '
                .'— et si elle ecrit, `PwaEcritureAutoriseeTest` exigera sa '
                .'garde RBAC — avant de l inscrire.',
            );
        }
    }

    /**
     * Toute methode publique atteignable sur un composant PWA vient d'une
     * classe RELUE — jamais d'un ancetre hors du balayage.
     *
     * Le cas precedent compare les methodes DECLAREES, classe par classe. Il
     * ne dirait rien d'une methode heritee d'une classe posee ailleurs
     * qu'`app/Pwa/Livewire/` : elle serait exposee comme action sur chaque
     * descendant, et n'apparaitrait dans la liste fermee d'aucun d'eux.
     *
     * Ce cas ferme cette porte : le declarant de chaque methode publique est
     * soit un composant relu, soit le cadre Livewire lui-meme. Sa liste est
     * DERIVEE des deux registres — il y en a eu une seconde, recopiee a la
     * main, qui aurait diverge en silence.
     *
     * ⚠ Les composants de `SURFACES_EN_COURS_DE_LIVRAISON` sont parcourus
     * ICI comme les autres : ce que leur attente suspend, c'est la relecture
     * de leurs PROPRES methodes, jamais la garantie que rien ne leur arrive
     * par heritage depuis une classe posee hors du balayage.
     */
    #[Test]
    public function aucune_action_de_composant_pwa_ne_vient_d_un_ancetre_non_relu(): void
    {
        $relues = array_merge(
            array_keys(self::ACTIONS_RELUES),
            array_keys(self::SURFACES_EN_COURS_DE_LIVRAISON),
        );

        $verifiees = 0;

        foreach ($relues as $composant) {
            $reflet = new \ReflectionClass($composant);

            foreach ($reflet->getMethods(\ReflectionMethod::IS_PUBLIC) as $methode) {
                $declarant = $methode->getDeclaringClass()->getName();

                if (! str_starts_with($declarant, 'App\\')) {
                    // Le cadre Livewire : `mount`, `render` de base, `$set`...
                    // Il n'est pas de notre ressort et ne touche aucune donnee
                    // metier de ce depot.
                    continue;
                }

                $verifiees++;

                $this->assertContains(
                    $declarant,
                    $relues,
                    "La methode publique {$methode->getName()} du composant PWA {$composant} "
                    ."est declaree par {$declarant}, qui n'est PAS dans la liste relue. "
                    .'Une action Livewire heritee echappe autant a ForcerLectureSeule '
                    ."qu'une action declaree.",
                );
            }
        }

        // Plancher : si plus aucune methode n'etait attribuee a `App\`, la
        // boucle passerait au vert sans rien examiner.
        $this->assertGreaterThanOrEqual(15, $verifiees);
    }

    /**
     * Le registre d'attente DATE chacune de ses raisons.
     *
     * Trois fois dans ce depot un motif de refus a cesse d'etre vrai sans que
     * personne ne le rouvre — PA-107, PA-120, puis PA-144, la premiere dans du
     * code. Un composant laisse ici « le temps que ca se stabilise » produit
     * exactement le meme effet : la surface n'est plus relue, et rien ne le
     * rappelle. Une date rend l'anciennete visible a la lecture.
     *
     * Le registre peut etre VIDE — c'est meme l'etat souhaite. Ce cas ne
     * verifie donc pas qu'il contient quelque chose, seulement que ce qu'il
     * contient est date et designe un composant reel.
     */
    #[Test]
    public function chaque_surface_en_attente_de_relecture_est_datee_et_reelle(): void
    {
        $fautifs = [];

        // Le registre est VIDE aujourd'hui, et c'est l'etat souhaite. Le type
        // est elargi pour que ce cas reste ecrit tel qu'il doit tourner le
        // jour ou il se remplit — le supprimer parce qu'il n'a rien a relire
        // aujourd'hui reviendrait a retirer la garde en meme temps que la
        // derniere entree.
        /** @var array<class-string, string> $registre */
        $registre = self::SURFACES_EN_COURS_DE_LIVRAISON;

        foreach ($registre as $composant => $raison) {
            if (preg_match('#\b\d{2}/\d{2}/\d{4}\b#', $raison) !== 1) {
                $fautifs[] = "{$composant} : raison non datee (« {$raison} »)";
            }

            if (! class_exists($composant)) {
                $fautifs[] = "{$composant} : la classe n existe pas";
            }
        }

        $this->assertSame(
            [],
            $fautifs,
            "Le registre des surfaces en attente de relecture est mal tenu.\n"
            .'Chaque entree suspend une garantie : elle doit dire depuis QUAND, sinon '
            ."l attente devient un oubli (PA-107, PA-120, PA-144).\n  "
            .implode("\n  ", $fautifs),
        );
    }

    /**
     * Tous les composants sous `app/Pwa/Livewire/`, sous-dossiers COMPRIS.
     *
     * Les TRAITS (`Livewire/Concerns/`) n'y figurent pas : un trait n'est pas
     * atteignable comme composant, et ses methodes sont relevees par la
     * reflexion sur chaque classe qui l'utilise — c'est la seule lecture qui
     * compte. Un fichier qui ne porte NI classe NI trait fait echouer le
     * balayage au lieu d'etre saute : un composant au nom mal derive
     * echapperait sinon a la liste entiere.
     *
     * @return list<class-string>
     */
    private function composantsPwa(): array
    {
        $racine = app_path('Pwa/Livewire');

        $iterateur = new \RecursiveIteratorIterator(
            new \RecursiveDirectoryIterator($racine, \FilesystemIterator::SKIP_DOTS),
        );

        $classes = [];

        foreach ($iterateur as $fichier) {
            if (! $fichier instanceof \SplFileInfo || $fichier->getExtension() !== 'php') {
                continue;
            }

            $relatif = str_replace([app_path('Pwa'), '.php'], '', $fichier->getPathname());
            $symbole = 'App\\Pwa'.str_replace(['/', '\\'], '\\', $relatif);

            if (trait_exists($symbole)) {
                continue;
            }

            $this->assertTrue(
                class_exists($symbole),
                "Le fichier {$fichier->getPathname()} ne porte ni la classe ni le trait "
                ."{$symbole} : impossible de le relire, donc impossible de garantir "
                .'que ses methodes publiques sont dans la liste fermee.',
            );

            $classes[] = $symbole;
        }

        sort($classes);

        return $classes;
    }

    #[Test]
    public function un_invite_est_redirige_vers_le_formulaire_de_connexion(): void
    {
        $this->get('/pwa')->assertRedirect(route('pwa.connexion'));
    }

    #[Test]
    public function le_formulaire_de_connexion_s_affiche_reellement(): void
    {
        $this->get('/pwa/connexion')
            ->assertOk()
            ->assertSee('Identifiant')
            ->assertSee('Se connecter');
    }

    /**
     * SECURITY_STRICT.md §12 — la grille de comptes cliquables du prototype
     * ne doit jamais apparaître, dans AUCUN environnement. Ce test est le
     * garde-fou automatisé de cette interdiction.
     */
    #[Test]
    public function la_page_de_connexion_n_expose_aucune_grille_de_comptes_cliquables(): void
    {
        $html = (string) $this->get('/pwa/connexion')->getContent();

        // L'assertion porte sur le TEXTE VISIBLE, jamais sur le HTML brut.
        //
        // Chercher dans le HTML brut revient a fouiller aussi les attributs et
        // les scripts, qui contiennent des chaines aleatoires — jeton CSRF de
        // 40 caracteres, instantane Livewire. Ce test a echoue deux fois de
        // facon aleatoire pour cette raison, sans qu'aucun code de la PWA n'ait
        // change. Un test instable est pire qu'un test absent : il apprend a
        // relancer jusqu'au vert.
        $sansScripts = (string) preg_replace('#<(script|style)\b[^>]*>.*?</\1>#is', ' ', $html);
        $texteVisible = strip_tags($sansScripts);

        // Le retrait opere-t-il reellement ? La regex portait `\b` et `\1`
        // ecrits comme CARACTERES DE CONTROLE (0x08, 0x01) : elle ne
        // correspondait jamais, `strip_tags()` laissait donc passer le contenu
        // des scripts — jeton CSRF, instantane Livewire — dans le « texte
        // visible ». Le commentaire ci-dessus decrivait une protection que la
        // ligne n'appliquait pas. Corrige le 20/08/2026, a la relecture de B1.
        //
        // Une page Livewire porte toujours au moins un `<script>` : si le
        // retrait cessait d'operer, cette assertion le dirait aussitot.
        $this->assertStringNotContainsString(
            'wire:',
            $texteVisible,
            'Les scripts ne sont pas retires : leur contenu coule dans le texte visible.',
        );

        $this->assertStringNotContainsString('Comptes de démonstration', $texteVisible);
        $this->assertStringNotContainsString('Se connecter en tant que', $texteVisible);

        // ------------------------------------------------------------------
        // Controle STRUCTUREL : la page ne porte qu'UN seul element cliquable,
        // le bouton de soumission. Zero lien, zero autre bouton.
        //
        // C'est ce qui rend la grille impossible, quel que soit son etiquetage.
        // Une version anterieure de ce test parcourait le texte visible a la
        // recherche des cles de la matrice RBAC (`administrateur`, `gerant`,
        // `achats`...). Deux defauts a cette approche, decouverts en portant la
        // maquette validee (B1, 20/08/2026) :
        //
        //  1. Elle ne detecte pas la grille reelle. `login.html` affiche le NOM
        //     et la FONCTION du compte (« Rachida SEIDOU », « Responsable des
        //     achats »), jamais la cle de role : le balayage serait passe a
        //     cote de l'objet meme qu'il nomme.
        //  2. Elle produit un faux positif sur le texte que le client a
        //     valide. L'accroche du panneau de gauche enumere les activites du
        //     Gite — « ...tourisme, vehicules, achats, stocks... » — ou
        //     « achats » est un nom commun, homonyme d'une cle de role.
        //
        // Le controle ci-dessous ne partage aucun de ces deux defauts : il ne
        // regarde pas des mots, il compte des elements interactifs. Un
        // selecteur de comptes en un clic en exige un par role
        // (SECURITY_STRICT.md §12).
        //
        // ⚠ DEUX boutons depuis le 01/09/2026, pas un seul : l'oeil de
        // visibilite du mot de passe (`type="button"`, jamais `submit`,
        // aucun libelle de role — un controle d'affichage, pas un compte).
        // La grille que ce controle interdit se caracterise par UN BOUTON
        // PAR ROLE, portant le NOM et la FONCTION d'un compte
        // (SECURITY_STRICT.md §12) : ce que le bloc ci-dessous verifie
        // reste vrai, juste sur un compte de deux plutot qu'un.
        $this->assertSame(2, substr_count($html, '<button'), 'La page de connexion ne doit porter que le bouton de soumission et l\'oeil du mot de passe.');
        $this->assertSame(0, substr_count($html, '<a '), 'La page de connexion ne doit porter aucun lien.');

        preg_match_all('#<button[^>]*type="(submit|button)"[^>]*>(.*?)</button>#s', $html, $boutons, PREG_SET_ORDER);
        $this->assertCount(2, $boutons, 'Les deux boutons doivent porter un type explicite.');

        $soumission = array_values(array_filter($boutons, static fn (array $b): bool => $b[1] === 'submit'));
        $this->assertCount(1, $soumission, 'Un seul bouton de soumission.');
        $this->assertSame(
            __('pwa.connexion.valider'),
            trim(strip_tags($soumission[0][2])),
            'Le bouton de soumission doit porter le libelle de connexion.',
        );

        // L'autre bouton — l'oeil — ne porte NI nom NI fonction de role : son
        // texte visible est vide (icones SVG seules), ce qui interdit
        // structurellement qu'il soit pris pour une tuile de compte.
        $autre = array_values(array_filter($boutons, static fn (array $b): bool => $b[1] === 'button'));
        $this->assertCount(1, $autre);
        $this->assertSame('', trim(strip_tags($autre[0][2])), 'Le bouton hors soumission ne doit porter aucun texte visible.');

        // Aucune cle de role ne sert d'etiquette a un element interactif.
        preg_match_all('#<(?:button|a)\b[^>]*>(.*?)</(?:button|a)>#is', $html, $interactifs);
        $texteInteractif = strip_tags(implode(' ', $interactifs[1]));

        // Le balayage ci-dessous ne vaut que s'il porte sur quelque chose.
        // La regex a d'abord ete ecrite avec `\b` corrompu en caractere de
        // controle : elle ne correspondait jamais, la liste des elements
        // interactifs sortait vide, et la boucle passait au vert sans rien
        // examiner. Corrige le 20/08/2026, a la relecture de B1.
        $this->assertNotEmpty(
            $interactifs[1],
            'Aucun element interactif capture : le balayage qui suit ne verifierait rien.',
        );

        foreach (array_keys(RolePermissionSeeder::MATRICE) as $role) {
            $this->assertStringNotContainsStringIgnoringCase(
                $role,
                $texteInteractif,
                "Un element cliquable de l'ecran de connexion porte le libelle de role « {$role} » : "
                . 'la grille de comptes cliquables du prototype est interdite dans TOUT '
                . 'environnement (SECURITY_STRICT.md §12).',
            );
        }
    }

    /**
     * Les routes `/pwa` restent GET-only, meme sous le regime CRUD.
     *
     * Ce n'est plus « la lecture seule est structurelle » : la PWA ecrit.
     * Mais elle ecrit par les actions Livewire gardees
     * (`PwaEcritureAutoriseeTest`), JAMAIS par une route d'ecriture sous
     * `/pwa` — une telle route echapperait aux deux listes de ce dossier.
     * `ForcerLectureSeule` interdit qu'on en ajoute une, et ce cas verifie
     * qu'il le fait vraiment.
     */
    #[Test]
    public function une_requete_d_ecriture_sur_une_route_pwa_est_refusee(): void
    {
        $this->post('/pwa')->assertStatus(405);
        $this->put('/pwa')->assertStatus(405);
        $this->delete('/pwa')->assertStatus(405);
    }

    #[Test]
    public function un_identifiant_invalide_est_refuse_et_trace(): void
    {
        Livewire::test(Connexion::class)
            ->set('login', 'inconnu')
            ->set('motDePasse', 'mauvais-mot-de-passe')
            ->call('seConnecter')
            ->assertHasErrors('identifiants');

        $this->assertGuest();
        $this->assertSame(1, JournalSecurite::where('type_evenement', 'connexion_echouee')->count());
    }

    #[Test]
    public function un_compte_desactive_ne_peut_pas_se_connecter_malgre_un_mot_de_passe_valide(): void
    {
        $this->creerUtilisateur('gerant', 'desactive');

        Livewire::test(Connexion::class)
            ->set('login', 'compte.test')
            ->set('motDePasse', 'mot-de-passe-de-test')
            ->call('seConnecter')
            ->assertHasErrors('identifiants');

        $this->assertGuest();
    }

    #[Test]
    public function un_compte_actif_accede_a_l_accueil(): void
    {
        $this->creerUtilisateur('gerant');

        Livewire::test(Connexion::class)
            ->set('login', 'compte.test')
            ->set('motDePasse', 'mot-de-passe-de-test')
            ->call('seConnecter')
            ->assertHasNoErrors()
            ->assertRedirect(route('pwa.accueil'));

        $this->assertAuthenticated();
    }

    /*
     * ⚠ LES DEUX CAS DE MASQUAGE DU MENU ONT ETE RETIRES D'ICI (31/08/2026),
     * ET LA PROPRIETE EST TOUJOURS MESUREE — mieux qu'elle ne l'etait.
     *
     * Ils cherchaient des LIBELLES dans le rendu du composant
     * (`assertDontSee('Tableau de bord')`, `assertDontSee('État des stocks')`).
     * Deux defauts, decouverts en fermant la fuite RBAC de l'ecran d'accueil :
     *
     *  1. **Faux positif mesure.** « État des stocks » figure dans le texte du
     *     refus `accueil_pwa.refus_rapports_m14`, qui ENUMERE les etats que
     *     l'ecran ne produit pas. La garde accusait donc l'ecran de rendre une
     *     entree de menu, alors qu'elle lisait une phrase qui explique
     *     precisement le contraire. Une garde qui accuse du code correct finit
     *     desarmee.
     *  2. **Doublon.** `ConformiteMaquettePwaTest::
     *     le_menu_lateral_masque_les_modules_sans_droit` tient deja ce
     *     contrat, et le tient plus strictement : sur la PAGE reellement
     *     servie (pas le composant seul), sur les libelles DERIVES du registre
     *     (jamais recopies), avec les groupes devenus vides, et avec la
     *     contre-epreuve — les memes entrees sont exigees PRESENTES pour un
     *     role qui y a droit, sans quoi un menu vide par erreur passerait au
     *     vert.
     *
     * Ne pas les remettre ici : deux gardes du meme contrat divergent, et
     * c'est celle qu'on oublie qui laisse passer.
     */

    #[Test]
    public function la_page_de_repli_hors_connexion_est_servie_sans_authentification(): void
    {
        $this->get('/pwa/hors-connexion')
            ->assertOk()
            ->assertSee('Connexion Internet requise');
    }

    private function creerUtilisateur(string $role, string $statut = 'actif'): User
    {
        return User::create([
            'login' => 'compte.test',
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => $statut,
        ]);
    }
}
