// Vue Blade maîtresse (PA-183) : pwa/hebergement/reservations.blade.php
// Vue Blade maîtresse (PA-183) : pwa/pos/comptant.blade.php
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/environnement.dart';

import 'tables/achats_tables.dart';
import 'tables/alertes_vues_tables.dart';
import 'tables/bar_tables.dart';
import 'tables/boite_envoi_emails_tables.dart';
import 'tables/caisse_tables.dart';
import 'auteur_ecriture.dart';
import 'declencheurs_comptables.dart';
import 'reconcilier_schema.dart';
import 'emplacement_base.dart';
import 'tables/clients_table.dart';
import 'tables/clotures_exercices_tables.dart';
import 'elargir_types_operations_sync.dart';
import 'tables/comptabilite_tables.dart';
import 'tables/depenses_tables.dart';
import 'tables/descente_sync_tables.dart';
import 'tables/historique_prix_carte_tables.dart';
import 'tables/journal_securite_tables.dart';
import 'tables/pieces_saisie_tables.dart';
import 'tables/journal_reception_tables.dart';
import 'tables/indisponibilites_carte_tables.dart';
import 'tables/conges_plannings_tables.dart';
import 'tables/complements_v35_tables.dart';
import 'tables/ecritures_serveur_tables.dart';
import 'tables/entretiens_vehicule_tables.dart';
import 'tables/occupations_tables_tables.dart';
import 'tables/origines_documents_tables.dart';
import 'tables/facturation_tables.dart';
import 'tables/hebergement_tables.dart';
import 'tables/messages_editeur_tables.dart';
import 'tables/notifications_tables.dart';
import 'tables/operations_sync_tables.dart';
import 'tables/paiements_facture_tables.dart';
import 'tables/panier_tables.dart';
import 'tables/parametres_tables.dart';
import 'tables/registre_facturation_tables.dart';
import 'tables/reglements_fournisseur_tables.dart';
import 'tables/restaurant_tables.dart';
import 'tables/roles_tables.dart';
import 'tables/rh_tables.dart';
import 'tables/sejours_tables.dart';
import 'tables/tables_pos_table.dart';
import 'tables/utilisateurs_table.dart';
import 'tables/stocks_tables.dart';
import 'tables/tourisme_tables.dart';
import 'tables/vehicules_tables.dart';

part 'app_database.g.dart';

/// Base locale Drift — `FULL_MIGRATIONS_DATABASE_FLUTTER.md`.
///
/// ## Périmètre : ce qui est répliqué, et ce qui ne l'est pas
///
/// Seuls **M1, M2, M5, M6, M8, M9** et les référentiels transverses sont
/// répliqués localement (§0). M4, M7, M10 à M13 ne le sont **pas** : leurs
/// écrans affichent « fonctionnalité nécessitant une connexion » hors ligne.
///
/// ⚠ Cette liste est celle du Sprint 0, et elle a vieilli : depuis la décision
/// « zéro réseau » du 14/09/2026, M10 et M13 ont leur source locale (v10), puis
/// M6 (v12), M7 (v13) et M4 (v14) le 09/10/2026, puis le moteur comptable de M10
/// (v15) le 10/10/2026. L'historique de chaque
/// version, avec sa raison, est dans les commentaires de `schemaVersion` plus
/// bas.
///
/// Le cas de M4 a changé deux fois : le cadrage le laissait en ligne (la salle
/// avait une connectivité jugée stable), puis la décision « zéro réseau » l'a
/// laissé sans aucune source, et le PO a tranché que sa source de données est
/// LOCALE (09/10/2026) — voir `tables/restaurant_tables.dart`.
///
/// N'ajouter aucune table hors de ce périmètre « pendant qu'on y est » : la
/// taille de la base locale conditionne la durée de la fenêtre offline, et un
/// guide en circuit de plusieurs jours n'a pas de marge.
@DriftDatabase(
  tables: [
    UtilisateursLocal,
    ClientsLocal,
    CategoriesHebergementLocal,
    UnitesHebergementLocal,
    ReservationsLocal,
    LignesReservationLocal,
    FacturesLocal,
    LignesFactureLocal,
    PaiementsLocal,
    CartesBoissonLocal,
    VentesBarLocal,
    LignesVenteBarLocal,
    PointsStockageLocal,
    ArticlesLocal,
    MouvementsStockLocal,
    VehiculesLocal,
    ContratsLocationLocal,
    CircuitsLocal,
    GuidesLocal,
    ReservationsTourLocal,
    PaniersLocal,
    LignesPanierLocal,
    PiecesFacturationLocal,
    LignesPieceFacturationLocal,
    SequencesFactureLocal,
    TablesLocal,

    // Les quatre modules d'exploitation portés en LOCAL PUR le 14/09/2026
    // (décision « zéro réseau » du Product Owner). Ils étendent délibérément
    // le périmètre du §0 ci-dessus : M10 et M13 n'étaient pas répliqués tant
    // qu'un serveur les portait. Aucune de ces tables ne remonte nulle part,
    // et aucune ne porte de `statutSync` — l'annoncer « en attente de
    // synchronisation » serait affirmer une attente sans fin (PA-59/60/61).
    DepensesLocal,
    LignesDepenseLocal,
    ModelesNotificationLocal,
    MessagesNotificationLocal,
    ServicesRhLocal,
    EmployesLocal,
    BulletinsPaieLocal,
    TauxPaieLocal,

    // v11 (09/10/2026) — les paramètres du système saisis sur ce poste, source
    // locale de l'écran Paramètres (décision du PO : sources locales). Table
    // NEUVE, aucune table existante touchée, aucune ligne semée.
    ParametresSystemeLocal,

    // v13 (09/10/2026) — M7 Achats, source LOCALE : cinq tables NEUVES
    // (fournisseurs, commandes, leurs lignes, bons de réception, leurs
    // lignes). Aucune table existante n'est touchée, rien n'est semé.
    FournisseursLocal,
    CommandesAchatLocal,
    LignesCommandeAchatLocal,
    BonsReceptionLocal,
    LignesBonReceptionLocal,

    // v14 (09/10/2026) — M4 Restaurant, source LOCALE : quatre tables NEUVES
    // (menus, fiches techniques, leur composition, plats). Aucune table
    // existante n'est touchée, rien n'est semé.
    MenusLocal,
    RecettesLocal,
    IngredientsRecetteLocal,
    PlatsLocal,

    // v15 (10/10/2026) — M10 Comptabilité, MOTEUR LOCAL réplique du serveur :
    // six tables NEUVES (centres, journaux, plan comptable, exercices,
    // écritures, séquence des pièces). Aucune table existante n'est touchée ;
    // le référentiel est installé au démarrage, jamais semé par la migration.
    CentresCoutLocal,
    JournauxLocal,
    PlanComptableLocal,
    ExercicesLocal,
    EcrituresLocal,
    SequencesPieceLocal,

    // v17 (12/10/2026) — SESSIONS DE CAISSE, réplique du serveur : UNE table
    // NEUVE. Aucune table existante n'est touchée, rien n'est semé. Seul auteur :
    // `SessionsCaisseDao` (voir `tables/caisse_tables.dart`).
    SessionsCaisseLocal,

    // v18 (12/10/2026) — ENCAISSEMENT DE FACTURE, réplique du serveur : UNE table
    // NEUVE (`paiements_facture_local`) et UNE colonne ajoutée à `paniers_local`
    // (`session_encaissement_id`, le `ventes.session_id` du serveur). Seul auteur
    // de la table : `PaiementsFactureDao`. L'ancienne `PaiementsLocal` (schéma du
    // Sprint 0, REAL, sans session) reste sans écrivain et n'est pas réutilisée.
    PaiementsFactureLocal,

    // v20 (12/10/2026) — RÈGLEMENT FOURNISSEUR, réplique du serveur (lot 7,
    // D66) : UNE table NEUVE. Aucune table existante n'est touchée, rien n'est
    // semé. Seul auteur : `ReglementsFournisseurDao` (voir
    // `tables/reglements_fournisseur_tables.dart`).
    ReglementsFournisseurLocal,

    // v22 (14/10/2026) — L'ÉTAT « VU » DES ALERTES DE LA CLOCHE, réplique de la
    // table `alertes_vues` du serveur : UNE table NEUVE. Aucune table existante
    // n'est touchée, rien n'est semé. Seul auteur : `AlertesVuesDao` (voir
    // `tables/alertes_vues_tables.dart`).
    AlertesVuesLocal,

    // v23 (14/10/2026) — LES SÉJOURS, réplique de la table `sejours` du serveur
    // (lot C du plan du PO, D408) : UNE table NEUVE. Aucune table existante
    // n'est touchée, rien n'est semé. Seul auteur : `SejourDao` (voir
    // `tables/sejours_tables.dart`).
    SejoursLocal,

    // v24 (14/10/2026) — LE RÉFÉRENTIEL DES RÔLES, réplique de `roles` et de
    // sa matrice au serveur (écran Rôles & Permissions complet) : UNE table
    // NEUVE. Aucune table existante n'est touchée ; la migration ne sème rien
    // (le socle du CdCF est posé par `RolesDao.installerSocle`). Seul auteur :
    // `RolesDao` (voir `tables/roles_tables.dart`).
    RolesLocal,

    // v25 (14/10/2026) — LA BOÎTE D'ENVOI DE « CONTACTEZ L'ÉDITEUR », réplique
    // de `messages_editeur` au serveur (directive du PO, Lot J2 partie 2) : UNE
    // table NEUVE. Aucune table existante n'est touchée, rien n'est semé. Seul
    // auteur : `MessagesEditeurDao` (voir `tables/messages_editeur_tables.dart`).
    MessagesEditeurLocal,

    // v26 (15/10/2026) — LA FILE D'ENVOI du poste (décisions du PO des
    // 14–15/10/2026 : la synchronisation revient comme tâche de fond) : UNE
    // table NEUVE. Aucune table existante n'est touchée, rien n'est semé. Seul
    // auteur : `OperationsSyncDao` (voir `tables/operations_sync_tables.dart`).
    OperationsSyncLocal,

    // v27 (15/10/2026) — LA DESCENTE DU CATALOGUE (lot F2b) : DEUX tables
    // NEUVES, l'état de la synchronisation (clé/valeur : curseur, repli,
    // éléments à rejouer) et les correspondances identifiant serveur →
    // identifiant local. Aucune table existante n'est touchée, rien n'est
    // semé. Qui écrit, qui lit : voir `tables/descente_sync_tables.dart`.
    EtatSynchronisationLocal,
    CorrespondancesSyncLocal,
    OriginesDocumentsLocal,
    // v29 (18/10/2026, lot F6) : l'occupation des tables par les AUTRES
    // postes. Qui écrit, qui lit : `tables/occupations_tables_tables.dart`.
    OccupationsTablesLocal,
    // v31 (21/10/2026) : les retraits de la carte du jour (boissons, plats).
    IndisponibilitesCarteLocal,
    // v32 (21/10/2026) : entretiens et carburations des véhicules.
    EntretiensVehiculeLocal,
    PlanningsLocal,
    CongesLocal,
    EcrituresServeurLocal,
    ImmobilisationsLocal,
    RelancesClientsLocal,
    InventairesLocal,
    LignesInventaireLocal,
    CanauxReservationLocal,
    // v37 (26/10/2026) : le journal de réception du poste (chaque élément
    // reçu du serveur, son issue et sa cause). Seul auteur :
    // `JournalReceptionDao` (voir `tables/journal_reception_tables.dart`).
    JournalReceptionLocal,
    // v38 (26/10/2026) : l'historique des prix de la carte (bar et restaurant).
    // Seul auteur : `HistoriquePrixCarteDao` (voir
    // `tables/historique_prix_carte_tables.dart`).
    HistoriquePrixCarteLocal,
    // v39 (26/10/2026) : la boîte d'envoi des e-mails du poste (notifications
    // M12). Seul auteur : `BoiteEnvoiEmailsDao` (voir
    // `tables/boite_envoi_emails_tables.dart`).
    BoiteEnvoiEmailsLocal,
    // v40 (26/10/2026) : les clôtures d'exercice du poste (pièces CL et AN,
    // résultat, archive légale et son empreinte, réouverture). Seul auteur :
    // `ClotureExerciceLocale` (voir `tables/clotures_exercices_tables.dart`).
    CloturesExercicesLocal,
    // v44 (28/10/2026) : les pièces saisies à la main sur le poste, partagées
    // avec le serveur (D246 rouvert). Seul auteur : `MoteurComptable.saisirPiece`
    // (voir `tables/pieces_saisie_tables.dart`).
    PiecesSaisieLocal,
    // v46 (29/10/2026) : le journal de sécurité du poste (réinitialisations de
    // mot de passe, code de secours). Seul auteur : `JournalSecuriteDao` (voir
    // `tables/journal_securite_tables.dart`). LOCAL : ne part jamais au serveur.
    JournalSecuriteLocal,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// La base du poste. [fileSynchronisation] vaut `false` par défaut dans le
  /// flavor de démonstration (`ENV=demo`) : un jeu fictif ne doit jamais
  /// entrer dans la file d'envoi — voir [fileSynchronisationActive].
  AppDatabase({bool? fileSynchronisation})
    : fileSynchronisationActive =
          fileSynchronisation ?? !Environnement.actuel.estHorsLigneIntegral,
      super(_ouvrir());

  /// Constructeur de test — base en mémoire (`SEEDER_TEST_FLUTTER.md` §2).
  ///
  /// Sans lui, chaque test toucherait le fichier réel de la machine et les
  /// tests deviendraient dépendants de leur ordre d'exécution.
  AppDatabase.enMemoire({bool fileSynchronisation = true})
    : fileSynchronisationActive = fileSynchronisation,
      super(NativeDatabase.memory());

  /// Constructeur de test sur un **fichier réel**.
  ///
  /// La base en mémoire ne prouve rien de ce qui compte le jour d'une mise à
  /// jour : ni la survie des données à la fermeture de l'application, ni le
  /// passage par `onUpgrade`. Les deux chemins n'existent que sur fichier, et
  /// tant qu'aucun test ne les emprunte, ils ne sont écrits que sur le papier.
  AppDatabase.surFichier(File fichier, {bool fileSynchronisation = true})
    : fileSynchronisationActive = fileSynchronisation,
      super(NativeDatabase(fichier, logStatements: false));

  /// La file d'envoi (`operations_sync_local`, v26) reçoit-elle les écritures
  /// métier de cette base ?
  ///
  /// `false` en mode DÉMONSTRATION (décision du 15/10/2026, lot F1) : le jeu
  /// de démonstration et tout ce qu'on y saisit sont fictifs, et la file est
  /// la seule voie par laquelle une donnée du poste atteint le serveur. Plutôt
  /// qu'une file « qui ne part jamais » (une attente sans fin, PA-59/60/61),
  /// rien n'y entre : `OperationsSyncDao.enfiler` ne fait rien, et le dit en
  /// rendant `null`. `main_demo.dart` le pose EXPLICITEMENT, en plus du défaut
  /// lié au flavor.
  final bool fileSynchronisationActive;

  /// QUI écrit et depuis quel poste, relu À CHAQUE écriture qui le consigne
  /// (l'enfilement dans la file d'envoi, la trace d'un changement de prix) —
  /// voir `auteur_ecriture.dart`. Posé par `baseLocaleProvider` ; sans lui,
  /// l'auteur est inconnu et l'écran dit « — ».
  AuteurEcriture Function() auteurEcriture = () => aucunAuteurEcriture;

  /// Où la migration écrit ce qu'elle fait (`demarrage.log`, PRD réinstallation
  /// R1/R2). Posé par le démarrage avant la première ouverture ; `null` en test.
  void Function(String ligne)? journalDemarrage;

  /// v2 (18/08/2026) — M1 Hébergement : `reference`, `tarifNuit`, `motifRejet`
  /// et `motifAnnulation` ajoutés à `ReservationsLocal`, et `statutSync`
  /// ramené à `local` par défaut. Motifs détaillés dans `hebergement_tables.dart`.
  ///
  /// v3 (20/08/2026) — D2 : `PaniersLocal` et `LignesPanierLocal`.
  /// **Portage d'une proposition non ratifiée** — l'avertissement complet et
  /// les trois points Q1/Q2/Q3 sont en tête de `tables/panier_tables.dart`.
  /// Aucune table existante n'est touchée : la v3 n'ajoute que deux tables.
  ///
  /// v4 (20/08/2026) — D3 : `PiecesFacturationLocal`,
  /// `LignesPieceFacturationLocal` et `SequencesFactureLocal`. Trois tables
  /// **neuves**, aucune table existante touchée. L'avertissement complet — et
  /// notamment pourquoi ce registre ne réutilise pas `FacturesLocal`, qui est
  /// déclarée et n'a aucun appelant — est en tête de
  /// `tables/registre_facturation_tables.dart`.
  /// v11 (09/10/2026) — `parametres_systeme_local` : la source LOCALE de
  /// l'écran Paramètres (décision du PO, sources locales). Table neuve, rien
  /// de semé, rien de touché.
  ///
  /// v10 (14/09/2026) — **ZÉRO RÉSEAU**. Décision du Product Owner : le poste
  /// ne parle plus à aucun serveur. `sync_queue` et `sync_conflict_local`
  /// disparaissent, et les quatre modules d'exploitation (dépenses,
  /// notifications, personnel & paie, plus la durée des circuits) entrent au
  /// périmètre local. Détail et justification dans `onUpgrade`.
  ///
  /// v12 (09/10/2026) — M6 Stocks, source LOCALE : sept colonnes AJOUTÉES aux
  /// trois tables de stock (type du point ; suivi et rattachement de l'article ;
  /// coût unitaire, auteur, rupture forcée et rang d'écriture du mouvement).
  /// Aucune table neuve, aucune ligne semée — voir `tables/stocks_tables.dart`.
  ///
  /// v13 (09/10/2026) — M7 Achats, source LOCALE : cinq tables neuves
  /// (`fournisseurs_local`, `commandes_achat_local`,
  /// `lignes_commande_achat_local`, `bons_reception_local`,
  /// `lignes_bon_reception_local`). Qui écrit, qui lit, qui descend : voir
  /// `tables/achats_tables.dart`.
  ///
  /// v14 (09/10/2026) — M4 Restaurant, source LOCALE : quatre tables neuves
  /// (`menus_local`, `recettes_local`, `ingredients_recette_local`,
  /// `plats_local`). Qui écrit, qui lit, qui descend : voir
  /// `tables/restaurant_tables.dart`.
  ///
  /// v15 (10/10/2026) — M10 Comptabilité, MOTEUR LOCAL : six tables neuves
  /// (`centres_cout_local`, `journaux_local`, `plan_comptable_local`,
  /// `exercices_local`, `ecritures_local`, `sequences_piece_local`) et les
  /// quatre triggers de RG-11. Qui écrit, qui lit, qui descend : voir
  /// `tables/comptabilite_tables.dart`.
  ///
  /// v16 (10/10/2026) — M10 Dépenses, PIÈCE COMPTABLE : deux colonnes
  /// AJOUTÉES à `depenses_local` (`ecriture_id`, `ecriture_refus`), aucune table
  /// neuve. Qui les écrit, qui les lit : voir `tables/depenses_tables.dart`.
  ///
  /// v17 (12/10/2026) — SESSIONS DE CAISSE, réplique du serveur : une table
  /// neuve (`sessions_caisse_local`), 50 -> 51 tables. Qui l'écrit, qui la lit,
  /// qui la descend : voir `tables/caisse_tables.dart`.
  ///
  /// v18 (12/10/2026) — ENCAISSEMENT DE FACTURE : une table neuve
  /// (`paiements_facture_local`, 51 -> 52 tables) et une colonne AJOUTÉE à
  /// `paniers_local` (`session_encaissement_id`). Voir
  /// `tables/paiements_facture_tables.dart`.
  ///
  /// v19 (12/10/2026) — L'ANNULATION AVEC COMMISSION ET REMBOURSEMENT
  /// (EF-M1-06) : HUIT colonnes AJOUTÉES à `reservations_local`, AUCUNE table
  /// neuve (52 tables inchangées). Les ventes du comptoir, l'acompte et le
  /// remboursement passent désormais leur PIÈCE comptable dans la transaction du
  /// geste (lot 6) — ce qui n'exige AUCUNE colonne : la pièce se retrouve par
  /// son libellé (PA-52), comme au serveur. Qui écrit, qui lit, qui descend :
  /// voir `tables/hebergement_tables.dart`.
  ///
  /// v20 (12/10/2026) — LE RÈGLEMENT FOURNISSEUR (M7, D66) : une table neuve
  /// (`reglements_fournisseur_local`, 52 -> 53 tables), aucune colonne ajoutée.
  /// Le règlement passe sa pièce comptable (Dr 4011 / Cr trésorerie) dans la
  /// même transaction. Qui écrit, qui lit, qui descend : voir
  /// `tables/reglements_fournisseur_tables.dart`.
  ///
  /// v21 (12/10/2026) — L'ARCHIVAGE D'UN FOURNISSEUR (M7, D63) : UNE colonne
  /// AJOUTÉE à `fournisseurs_local` (`actif`, `true` par défaut), aucune table
  /// neuve (53 inchangé). Qui l'écrit, qui la lit : voir
  /// `tables/achats_tables.dart`.
  ///
  /// v22 (14/10/2026) — LA CLOCHE DE LA BARRE SUPÉRIEURE (lot B du plan du
  /// PO) : une table neuve (`alertes_vues_local`, 53 -> 54 tables), aucune
  /// colonne ajoutée. Les alertes sont DÉRIVÉES à la lecture ; seul l'état
  /// « vu » d'un compte se stocke, comme au serveur. Qui écrit, qui lit, qui
  /// descend : voir `tables/alertes_vues_tables.dart`.
  ///
  /// v23 (14/10/2026) — LES SÉJOURS (lot C du plan du PO, D408) : une table
  /// neuve (`sejours_local`, 54 -> 55 tables), aucune colonne ajoutée. Le
  /// check-in et le check-out de l'accueil l'écrivent, comme `SejourService`
  /// au serveur. Qui écrit, qui lit, qui descend : voir
  /// `tables/sejours_tables.dart`.
  ///
  /// v24 (14/10/2026) — LES RÔLES (écran Rôles & Permissions complet, demande
  /// du PO) : une table neuve (`roles_local`, 55 -> 56 tables), aucune colonne
  /// ajoutée. Création d'un rôle, droits d'un rôle recopiés sur ses comptes,
  /// rétablissement du socle, comme `RolePermissionService` au serveur. Qui
  /// écrit, qui lit, qui descend : voir `tables/roles_tables.dart`.
  ///
  /// v25 (14/10/2026) — « CONTACTEZ L'ÉDITEUR » ENVOIE (directive du PO, Lot
  /// J2 partie 2) : une table neuve (`messages_editeur_local`, 56 -> 57
  /// tables), aucune colonne ajoutée. Le message s'y écrit AVANT la tentative
  /// SMTP (action réseau du poste, avec la synchronisation). Qui écrit, qui lit, qui
  /// descend : voir `tables/messages_editeur_tables.dart`.
  ///
  /// v26 (15/10/2026) — LA FILE D'ENVOI (décisions du PO des 14–15/10/2026,
  /// lot F1) : une table neuve (`operations_sync_local`, 57 -> 58 tables) et
  /// ses deux index, aucune colonne ajoutée. Chaque écrivain d'une table
  /// synchronisée y dépose, dans SA transaction, le document source au
  /// contrat du serveur. Qui écrit, qui lit, qui descend : voir
  /// `tables/operations_sync_tables.dart`.
  ///
  /// v27 (15/10/2026) — LA DESCENTE DU CATALOGUE (lot F2b) : deux tables
  /// neuves (`etat_synchronisation_local`, `correspondances_sync_local`, 58 ->
  /// 60 tables), aucune colonne ajoutée. Le catalogue du serveur descend sur
  /// le poste par `GET /referentiels` ; le curseur, le repli de la descente et
  /// les correspondances d'identifiants y vivent. Qui écrit, qui lit : voir
  /// `tables/descente_sync_tables.dart`.
  ///
  /// v28 (17/10/2026) — L'ORIGINE DES DOCUMENTS DESCENDUS (lot F4, « NE PLUS
  /// LIMITER ») : une table neuve (`origines_documents_local`, 60 -> 61
  /// tables), aucune colonne ajoutée. Les documents des autres postes
  /// descendent sans pièce locale ; cette table dit lesquels, et de quel
  /// poste. Qui écrit, qui lit : voir `tables/origines_documents_tables.dart`.
  ///
  /// v29 (18/10/2026) — L'ARBITRAGE DES TABLES (lot F6, décision du PO :
  /// « il faut le créer ») : une table neuve (`occupations_tables_local`,
  /// 61 -> 62 tables), aucune colonne ajoutée. Une table occupée sur un autre
  /// poste (ou à la PWA) l'est aussi ici.
  ///
  /// v31 (21/10/2026) — LES RETRAITS DE LA CARTE DU JOUR : une table neuve
  /// (`indisponibilites_carte_local`, 62 -> 63 tables), aucune colonne ajoutée.
  /// Le poste retire et remet boissons et plats, et reçoit ceux des autres
  /// postes et de la PWA.
  ///
  /// v32 (21/10/2026) — LES ENTRETIENS DE VÉHICULES : une table neuve
  /// (`entretiens_vehicule_local`, 63 -> 64 tables), aucune colonne ajoutée.
  ///
  /// v36 (21/10/2026) — LE LIEN DIRECT PLAT -> ARTICLE : deux colonnes
  /// nullables sur `plats_local` (`article_id`, `unites_vendables`), aucune
  /// table.
  ///
  /// v37 (26/10/2026) — LE JOURNAL DE RÉCEPTION : une table neuve
  /// (`journal_reception_local`, 72 -> 73 tables), aucune colonne ajoutée. Elle
  /// se remplit à la prochaine descente ; aucune ligne n'est fabriquée.
  ///
  /// v38 (26/10/2026) — « LE POSTE FAIT CE QUE LE WEB FAIT » (décision du PO) :
  /// une table neuve (`historique_prix_carte_local`, 73 -> 74 tables) et six
  /// colonnes NULLABLES AJOUTÉES, jamais une table recréée : `contrats_location_local.statut`
  /// (l'annulation d'un contrat), `operations_sync_local.auteur_login` et
  /// `.poste_nom` (l'utilisateur et le poste du journal d'audit),
  /// `paniers_local.numero_vente` et `.auteur_login` (le numéro `V-` du serveur
  /// et l'auteur d'une vente). Aucune valeur n'est fabriquée pour l'existant :
  /// une ligne d'avant la v38 garde « — ».
  ///
  /// v39 (26/10/2026) — L'ENVOI RÉEL D'E-MAILS (décision du PO) : une table
  /// neuve (`boite_envoi_emails_local`, la boîte d'envoi des e-mails de
  /// notification : statuts, tentatives, repli, cause d'échec, clé
  /// d'idempotence), aucune colonne ajoutée. Elle apparaît VIDE : aucune ligne
  /// n'est fabriquée pour les messages d'avant (leur adresse n'a jamais été
  /// lue ; « Envoyer » la résout à la demande).
  ///
  /// v40 (26/10/2026) — LA CLÔTURE ANNUELLE SYSCOHADA SUR LE POSTE (décision du
  /// PO) : une table neuve (`clotures_exercices_local`, l'historique des
  /// clôtures du poste : pièces CL et AN, résultat, empreinte de l'archive,
  /// réouverture), aucune colonne ajoutée. Elle apparaît VIDE : un exercice
  /// déjà « clôturé » d'avant (statut descendu du serveur) n'a pas de clôture
  /// locale et son ouverture reste « inconnue » — aucune ligne n'est fabriquée.
  ///
  /// v41 (27/10/2026) — LES CHAMPS QUE LE WEB SAISIT ET QUE LE POSTE NE PORTAIT PAS
  /// (décisions D1 et D2 du PO : « convertir en CRUD, même logique que le web ») :
  /// aucune table neuve, DIX colonnes NULLABLES — `vehicules_local` (annee,
  /// capacite, transmission), `contrats_location_local` (numero, remise, acompte,
  /// montant FIGÉ à la signature), `plats_local` (categorie, les dix valeurs de la
  /// carte), `guides_local` (certification, tarif_jour). Rien n'est fabriqué pour
  /// l'existant : « — » à l'écran, et le montant d'un ancien contrat n'est PAS
  /// recalculé au tarif courant. Le curseur de descente est oublié : le catalogue
  /// redescend avec ces champs.
  ///
  /// v42 (27/10/2026) — LE REÇU EN IMAGE D'UNE DÉPENSE (lot L4, décision D4 du
  /// PO : un transport de fichier dans la synchronisation) : aucune table neuve,
  /// SIX colonnes NULLABLES sur `depenses_local` (`recu_nom`, `recu_sha256`,
  /// `recu_taille`, `recu_type`, `recu_statut`, `recu_cause`). Le fichier reste
  /// hors de la base (`recus_depenses/` à côté de `poste.json`). Rien n'est
  /// fabriqué pour l'existant : « sans reçu ». Le curseur de descente est oublié :
  /// les dépenses déjà au serveur redescendent avec la référence de leur reçu.
  ///
  /// v43 (28/10/2026) — A5 « PURGER » : la file d'envoi (`operations_sync_local`)
  /// accepte le type `suppression` (la purge définitive d'une unité d'hébergement
  /// ou d'un véhicule archivé). Aucune colonne, aucune table : la contrainte
  /// `CHECK` du type est élargie, ce qu'SQLite n'autorise que par une table
  /// RECRÉE — `elargirTypesOperationsSync`, conditionnel, copie intégrale avant
  /// tout abandon, `seq` conservé. Aucune ligne n'est fabriquée.
  ///
  /// v44 (28/10/2026) — D246 ROUVERT PAR LE PO (« le poste fait ce que le web fait
  /// + synchronisation ») : les comptes du plan et les pièces saisies à la main
  /// sont partagés. UNE table neuve, `pieces_saisie_local` (l'identifiant d'origine
  /// de chaque pièce de saisie manuelle), et UNE colonne NULLABLE,
  /// `ecritures_serveur_local.piece_origine_id` (l'origine d'une pièce redescendue).
  /// Rien n'est fabriqué : les pièces saisies avant la v44 ne sont ni marquées ni
  /// envoyées (le serveur ne les a jamais reçues et n'a pas de moyen sûr de les
  /// distinguer de celles d'un module). Le curseur de descente est oublié : le
  /// plan comptable du serveur et l'origine des pièces redescendent.
  ///
  /// v45 (28/10/2026) — L'E-MAIL FACULTATIF d'un employé et d'un compte (décision du
  /// PO) : DEUX colonnes NULLABLES, `employes_local.email` et
  /// `utilisateurs_local.email`, aucune table. Rien n'est déduit : les lignes d'avant
  /// n'ont pas d'adresse. Celle de l'employé part au serveur (charge `employes`) et
  /// redescend ; celle du compte reste LOCALE (les comptes ne se synchronisent pas).
  /// Le curseur de descente est oublié : les adresses des employés déjà au serveur
  /// redescendent.
  ///
  /// v46 (29/10/2026) — MOT DE PASSE PERDU SANS E-MAIL (décision du PO, option A) :
  /// ONZE colonnes ADDITIVES sur `utilisateurs_local` (indicateur « changement
  /// obligatoire », expiration du temporaire, dérivé de l'ancien mot de passe, dérivé
  /// du code de secours, compteur et horodatage des échecs) et UNE table locale neuve,
  /// `journal_securite_local`. Aucune ligne fabriquée : un compte d'avant la v46
  /// fonctionne sans changement et n'a pas de code de secours. Rien ne se
  /// synchronise : les comptes restent LOCAUX et aucun hash ne part.
  @override
  int get schemaVersion => 46;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      // Les gardes de RG-11 ne sont pas des tables : `createAll` ne les crée
      // pas. Sans elles, une écriture validée se modifierait par n'importe
      // quel UPDATE.
      await creerDeclencheursComptables(this);
    },

    /// Migration **additive**, jamais destructive.
    ///
    /// Une mise à jour de l'application ne doit pas perdre ce qui n'a pas
    /// encore été synchronisé : c'est précisément la donnée la plus fragile du
    /// poste, celle qui n'existe nulle part ailleurs. Recréer la table aurait
    /// été plus court et aurait effacé les réservations saisies hors ligne.
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // `reference` et `tarifNuit` sont NOT NULL sans valeur par défaut au
        // schéma. SQLite REFUSE d'ajouter une telle colonne à une table qui
        // contient déjà des lignes — et `m.addColumn` produit exactement cet
        // ordre. La migration aurait donc planté chez tout utilisateur ayant
        // au moins une réservation : c'est-à-dire tous, sauf celui qui vient
        // d'installer. Le défaut a été trouvé le 18/08/2026 en écrivant le
        // premier test qui emprunte réellement `onUpgrade`.
        //
        // On passe donc par un ordre SQL explicite portant un DEFAULT. Il ne
        // vaut que pour la migration : les nouvelles lignes reçoivent leur
        // valeur du code applicatif.
        await m.database.customStatement(
          'ALTER TABLE reservations_local '
          "ADD COLUMN reference TEXT NOT NULL DEFAULT ''",
        );
        await m.database.customStatement(
          'ALTER TABLE reservations_local '
          'ADD COLUMN tarif_nuit INTEGER NOT NULL DEFAULT 0',
        );

        // Ces deux-là sont nullables : `addColumn` suffit.
        await m.addColumn(reservationsLocal, reservationsLocal.motifRejet);
        await m.addColumn(reservationsLocal, reservationsLocal.motifAnnulation);

        // Une référence lisible pour les lignes reprises. Sans elle, l'écran
        // afficherait une ligne sans nom, que le réceptionniste ne pourrait
        // rapprocher d'aucun document.
        await m.database.customStatement(
          'UPDATE reservations_local '
          "SET reference = 'MIG-' || upper(substr(id, 1, 8)) "
          "WHERE reference = ''",
        );

        // `tarif_nuit` RESTE à 0 sur les lignes reprises, délibérément.
        // Le tarif d'origine n'existe nulle part : ni la table v1, ni le
        // serveur ne le portent. Un montant à 0 est visiblement faux, donc
        // visible ; un montant recalculé au tarif du jour serait plausible et
        // faux, donc invisible — et il figerait un prix que le client n'a
        // jamais accepté.
        //
        // Les lignes déjà présentes portaient `statutSync = 'synchronise'`.
        // On ne les requalifie PAS en `local` : elles viennent d'une version
        // où la valeur signifiait « état inconnu », et les rejouer toutes
        // créerait des doublons que rien ne rattrape.
      }

      if (from < 3) {
        // Deux tables NEUVES. Rien d'existant n'est réécrit : c'est la forme
        // la plus sûre de migration, et c'est aussi celle qui se teste le plus
        // mal — `createTable` sur une base vide passe toujours. Le test qui
        // compte part donc d'un fichier v2 **portant des réservations**, et
        // vérifie qu'elles sont encore là après (voir `cycle_de_vie_test.dart`,
        // groupe « Migration v2 → v3 »).
        //
        // Aucune donnée n'est reprise : il n'existait aucun panier avant la v3.
        // Y inventer des lignes depuis les ventes bar existantes créerait des
        // consommations que personne n'a saisies.
        await m.createTable(paniersLocal);
        await m.createTable(lignesPanierLocal);
      }

      if (from < 4) {
        // Trois tables NEUVES (D3). Même forme que la v3, et même piège : un
        // `createTable` sur une base vide passe toujours. Le test qui compte
        // part d'un fichier v3 **portant une réservation et un panier**, et
        // vérifie qu'ils sont encore là après — voir
        // `test/features/facturation/facture_cycle_de_vie_test.dart`, groupe
        // « Migration v3 → v4 ».
        //
        // Aucune donnée n'est reprise, et surtout aucune facture n'est déduite
        // des paniers déjà clôturés : émettre rétroactivement des pièces
        // numérotées pour des ventes passées créerait des documents fiscaux
        // que personne n'a émis, et leur donnerait des numéros de l'année
        // courante pour des ventes d'une autre.
        await m.createTable(piecesFacturationLocal);
        await m.createTable(lignesPieceFacturationLocal);
        await m.createTable(sequencesFactureLocal);
      }

      if (from < 5) {
        // Le referentiel des utilisateurs SUR LE POSTE.
        //
        // Decision du Product Owner du 21/08/2026 : l'authentification ne
        // passe pas par Laravel. La synchronisation porte sur les modules
        // metier — ventes, POS, stocks, rapports —, jamais sur la connexion.
        //
        // Table NEUVE, migration additive : aucune donnee existante n'est
        // touchee. Et surtout **aucun compte n'est cree ici** — un compte pose
        // par une migration aurait un mot de passe ecrit dans le code, donc
        // connu de quiconque lit le depot. Le premier compte se cree au
        // premier demarrage, avec un mot de passe choisi par l'exploitant.
        await m.createTable(utilisateursLocal);
      }

      if (from < 6) {
        // Le referentiel des TABLES DE SALLE, et le rattachement du panier.
        //
        // Le maitre (`prototype_v2/pages/pos.html`) pose un troisieme panneau
        // permanent — la salle — que ce client n'avait pas : un serveur qui
        // doit ouvrir une fenetre pour savoir quelles tables sont servies ne
        // la consulte pas, il retient de tete et se trompe.
        //
        // Une table NEUVE, et deux colonnes ajoutees a `paniers_local`. Les
        // deux sont NULLABLES, et c'est ce qui rend la migration sure : les
        // paniers deja ouverts restent valides sans table, ce qui est
        // exactement leur etat reel — ils ont ete saisis quand la notion
        // n'existait pas. Leur en attribuer une par defaut inventerait une
        // table ou le client ne s'est jamais assis.
        //
        // Et c'est aussi l'etat legitime d'une vente au COMPTOIR, qui n'a
        // jamais de table : la colonne restera nulle pour toujours sur
        // celles-la.
        await m.createTable(tablesLocal);

        // ⚠ LE PIEGE DE `createTable`, ET IL A REELLEMENT PLANTE.
        //
        // `m.createTable` cree la table avec sa definition COURANTE, pas avec
        // celle qu'elle avait a la version d'origine. Un poste venant d'avant
        // la v3 recoit donc `paniers_local` **deja pourvue** de `table_id` et
        // `espace` au passage `from < 3` — et l'`addColumn` ci-dessous echoue
        // alors sur « duplicate column name: table_id ».
        //
        // Le cas n'est pas theorique : c'est le poste qui a saute plusieurs
        // livraisons, exactement celui que la chaine v2 → v4 avait deja mis en
        // evidence. On n'ajoute donc les colonnes que si la table PRE-EXISTAIT
        // sous une forme qui ne les avait pas.
        if (from >= 3) {
          await m.addColumn(paniersLocal, paniersLocal.tableId);
          await m.addColumn(paniersLocal, paniersLocal.espace);
        }

        // AUCUNE table n'est semee ici. Le jeu initial (6 + 4 + 3) est pose
        // par le DAO au premier acces, la ou l'exploitant peut le voir et le
        // corriger depuis Parametres. Le semer dans une migration le rendrait
        // invisible et non rejouable : un poste dont l'exploitant a supprime
        // les tables les verrait revenir a la mise a jour suivante.
      }

      if (from < 7) {
        // La FICHE de reservation du maitre : quatre attributs plus la remise.
        //
        // `prototype_v2/pages/reservations.html` demande le type de client, le
        // canal, le mode de paiement et la remise. Le schema les ignorait, si
        // bien que le formulaire les aurait recueillis pour rien — une saisie
        // qui disparait est pire qu'un champ absent, parce qu'elle donne
        // l'impression d'avoir ete enregistree.
        //
        // `reservations_local` existe depuis la v1 et n'est recreee par aucune
        // branche : contrairement a `paniers_local` (v6), `addColumn` ne peut
        // donc pas se heurter a une table deja pourvue. Aucune garde `from >=`
        // n'est necessaire ici, et en poser une par mimetisme laisserait
        // croire a un risque qui n'existe pas.
        //
        // Les cinq sont NULLABLES : les reservations anterieures n'en portent
        // pas, et leur attribuer un canal par defaut affirmerait une origine
        // que personne n'a choisie — l'analyse par canal deviendrait fausse
        // sans que rien ne le signale.
        await m.addColumn(reservationsLocal, reservationsLocal.typeClient);
        await m.addColumn(reservationsLocal, reservationsLocal.canal);
        await m.addColumn(reservationsLocal, reservationsLocal.modePaiement);
        await m.addColumn(reservationsLocal, reservationsLocal.remiseType);
        await m.addColumn(reservationsLocal, reservationsLocal.remiseValeur);
      }

      if (from < 8) {
        // Les LIGNES DE SERVICE de la reservation.
        //
        // Le maitre compose une reservation de cinq services combinables ; ce
        // schema n'en connaissait qu'un, l'hebergement, et encore : une seule
        // chambre, par la colonne `unite_id`. Une table NEUVE, aucune table
        // existante touchee.
        //
        // AUCUNE ligne n'est deduite des reservations existantes. La tentation
        // serait d'en fabriquer une par reservation — service `hebergement`,
        // quantite = nuits, prix = `tarif_nuit` — et elle serait fausse pour
        // les lignes reprises de la v1, dont le `tarif_nuit` vaut 0 par
        // decision explicite (voir la branche v2). On inventerait des lignes a
        // zero franc, plausibles et invisibles. Les reservations anterieures
        // n'ont donc pas de ligne, et leur montant continue de se lire ou il a
        // toujours ete : `tarif_nuit x nuits`.
        await m.createTable(lignesReservationLocal);
      }

      if (from < 9) {
        // RENOMMAGE des tables du RESTAURANT : prefixe « T » -> « R ».
        //
        // Decision du Product Owner du 25/08/2026, repercutee au maitre
        // (`tables-engine.js` l.39). Changer le prefixe ne suffit PAS : le
        // libelle est STOCKE a la creation de la table, et les postes deja en
        // service portent « T1 »... « T8 ». Sans cette migration, un serveur
        // verrait « T1 » et « R9 » cote a cote sur le meme ecran et croirait a
        // deux salles.
        //
        // Migration de DONNEES, pas de schema : aucune colonne n'est touchee,
        // et elle ne porte que sur l'espace `restaurant` — les prefixes J et P
        // sont inchanges.
        //
        // Le libelle est RECOMPOSE depuis `numero`, jamais obtenu en coupant
        // l'ancienne chaine : « T12 » traite par un remplacement de caractere
        // marcherait, mais une table renumerotee a la main hors convention
        // deviendrait illisible.
        await customStatement(
          "UPDATE tables_local SET libelle = 'R' || numero "
          "WHERE espace = 'restaurant'",
        );
      }

      if (from < 10) {
        // ZÉRO RÉSEAU — décision du Product Owner du 14/09/2026.
        //
        // ## La SEULE migration destructrice de ce dépôt, et pourquoi
        //
        // Toutes les autres sont additives, par une règle que ce fichier
        // répète : la donnée non synchronisée est la seule copie qui existe.
        // Ici, précisément, elle ne l'est plus — il n'y a plus de serveur où
        // la pousser, ni aujourd'hui ni demain. Garder la file, ce serait
        // laisser grossir une attente que personne ne viendra jamais purger,
        // et tout écran qui la lirait annoncerait « en attente de
        // synchronisation » sur des lignes qui ne partiront pas. C'est
        // exactement l'indicateur qui affirme un état qu'il n'a pas vérifié
        // (PA-59/60/61), et c'est ce que la suppression empêche.
        //
        // ⚠ Elle ne se défait pas. Revenir à la v9 recrée les deux tables
        // VIDES : les opérations qu'elles portaient sont perdues. Le registre
        // de retour arrière le dit aussi, pour qu'aucun lecteur ne suppose une
        // symétrie qui n'existe pas.
        await m.deleteTable('sync_queue');
        await m.deleteTable('sync_conflict_local');

        // Les quatre modules d'exploitation, portés en local pur le même jour.
        // Huit tables NEUVES : aucune donnée existante n'est touchée.
        await m.createTable(depensesLocal);
        await m.createTable(lignesDepenseLocal);
        await m.createTable(modelesNotificationLocal);
        await m.createTable(messagesNotificationLocal);
        await m.createTable(servicesRhLocal);
        await m.createTable(employesLocal);
        await m.createTable(bulletinsPaieLocal);
        await m.createTable(tauxPaieLocal);

        // M9 — la durée d'un circuit, `varchar` LIBRE au serveur (PA-51) et
        // donc nullable ici. Sans elle, la colonne « Durée » et l'indicateur
        // « Durée indéterminée » comptaient l'absence de la colonne, pas les
        // durées.
        //
        // ⚠ L'ajout est CONDITIONNEL, et ce n'est pas une précaution de style.
        // `m.addColumn` échoue sur « duplicate column name » quand la colonne
        // est déjà là — ce qui arrive dès qu'une base est créée par
        // `createAll` à la définition COURANTE puis ramenée en arrière par une
        // fixture : la table renaît avec `duree`, et le rejeu de la v10
        // plantait (trouvé le 14/09/2026 sur la migration v8 → v9). Une
        // migration doit pouvoir se rejouer sur un fichier dans n'importe quel
        // état sans exploser.
        final colonnes = await m.database
            .customSelect('PRAGMA table_info(circuits_local)')
            .get();
        final aDejaDuree = colonnes.any((c) => c.data['name'] == 'duree');
        if (!aDejaDuree) {
          await m.addColumn(circuitsLocal, circuitsLocal.duree);
        }
      }

      if (from < 11) {
        // Les PARAMÈTRES DU SYSTÈME saisis sur ce poste (09/10/2026).
        //
        // Une table NEUVE, additive : aucune table existante n'est touchée, et
        // surtout AUCUNE ligne n'est semée. Un taux de TVA, une tolérance de
        // réception ou un taux CNSS « d'usine » posé par une migration serait
        // plausible, donc invisible, et deviendrait la règle appliquée en
        // production (PA-53, PA-19). Un paramètre non saisi reste « — ».
        //
        // Les taux de charges sociales ne sont PAS repris ici : ils ont leur
        // auteur (`taux_paie_local`), que cette migration ne touche pas.
        await m.createTable(parametresSystemeLocal);
      }

      if (from < 12) {
        // M6 STOCKS — source LOCALE (09/10/2026). Aucune table neuve : les
        // trois tables de stock existent depuis la v1, VIDES et sans auteur
        // (PA-134). La v12 leur donne ce qu'il manque pour être écrites et
        // lues sur ce poste, par des colonnes AJOUTÉES — jamais une table
        // recréée (les trois sont vides sur tout poste réel, mais un fichier
        // de développement peut en porter des lignes, et recréer effacerait).
        //
        // Aucune ligne n'est semée et aucune n'est déduite : un point, un
        // article ou un mouvement « d'usine » serait plausible, donc invisible.
        //
        // ⚠ L'ajout est CONDITIONNEL (piège 3, rencontré deux fois) : une base
        // créée par `createAll` à la définition COURANTE puis ramenée en
        // arrière par une fixture porte déjà certaines colonnes. Une migration
        // doit pouvoir se rejouer sur un fichier dans n'importe quel état.
        Future<Set<String>> colonnesDe(String table) async {
          final lignes = await m.database
              .customSelect('PRAGMA table_info($table)')
              .get();
          return {for (final c in lignes) c.data['name'] as String};
        }

        final points = await colonnesDe('points_stockage_local');
        if (!points.contains('type')) {
          await m.addColumn(pointsStockageLocal, pointsStockageLocal.type);
        }

        final articles = await colonnesDe('articles_local');
        if (!articles.contains('suivi')) {
          await m.addColumn(articlesLocal, articlesLocal.suivi);
        }
        if (!articles.contains('point_stockage_id')) {
          await m.addColumn(articlesLocal, articlesLocal.pointStockageId);
        }

        final mouvements = await colonnesDe('mouvements_stock_local');
        if (!mouvements.contains('cout_unitaire_dix_milliemes')) {
          await m.addColumn(
            mouvementsStockLocal,
            mouvementsStockLocal.coutUnitaireDixMilliemes,
          );
        }
        if (!mouvements.contains('utilisateur_id')) {
          await m.addColumn(
            mouvementsStockLocal,
            mouvementsStockLocal.utilisateurId,
          );
        }
        if (!mouvements.contains('rupture_forcee')) {
          await m.addColumn(
            mouvementsStockLocal,
            mouvementsStockLocal.ruptureForcee,
          );
        }
        if (!mouvements.contains('ordre')) {
          await m.addColumn(mouvementsStockLocal, mouvementsStockLocal.ordre);
        }
      }

      if (from < 13) {
        // M7 ACHATS — source LOCALE (09/10/2026). Cinq tables NEUVES, dans
        // l'ordre des clés étrangères (le parent avant l'enfant). Aucune table
        // existante n'est touchée et AUCUNE ligne n'est semée ni déduite : un
        // fournisseur ou une commande « d'usine » serait plausible, donc
        // invisible. `createTable` crée la définition COURANTE, ce qui est
        // exact ici puisque aucune version ultérieure n'a encore modifié ces
        // tables — le jour où la v14 y ajoutera une colonne, elle devra la
        // tester avant `addColumn` (piège 3).
        await m.createTable(fournisseursLocal);
        await m.createTable(commandesAchatLocal);
        await m.createTable(lignesCommandeAchatLocal);
        await m.createTable(bonsReceptionLocal);
        await m.createTable(lignesBonReceptionLocal);
      }

      if (from < 14) {
        // M4 RESTAURANT — source LOCALE (09/10/2026). Quatre tables NEUVES,
        // dans l'ordre des clés étrangères (le parent avant l'enfant : le menu
        // et la fiche avant le plat, la fiche avant sa composition). Aucune
        // table existante n'est touchée — la composition référence
        // `articles_local`, qui date de la v1 — et AUCUNE ligne n'est semée ni
        // déduite : un menu ou un plat « d'usine » se vendrait au comptoir à un
        // prix que personne n'a décidé. `createTable` crée la définition
        // COURANTE, exacte ici puisqu'aucune version ultérieure n'a modifié ces
        // tables (le jour où la v15 y ajoutera une colonne, elle devra la
        // tester avant `addColumn` — piège 3).
        await m.createTable(menusLocal);
        await m.createTable(recettesLocal);
        await m.createTable(ingredientsRecetteLocal);
        await m.createTable(platsLocal);
      }

      if (from < 15) {
        // M10 COMPTABILITÉ — moteur LOCAL (10/10/2026). Six tables NEUVES, dans
        // l'ordre des clés étrangères (centres et journaux avant le plan, le
        // plan et les exercices avant les écritures, la séquence après les
        // journaux). Aucune table existante n'est touchée et AUCUNE ligne n'est
        // semée ici : le plan comptable (1 332 comptes), les journaux, les
        // centres et l'exercice de l'année sont installés par
        // `installerReferentielComptable`, appelé au démarrage — une migration
        // ne lit pas un asset, et un référentiel recopié à la main divergerait
        // du fichier du PO. `createTable` crée la définition COURANTE, exacte
        // ici puisqu'aucune version ultérieure n'a modifié ces tables (le jour
        // où la v16 y ajoutera une colonne, elle devra la tester avant
        // `addColumn` — piège 3).
        await m.createTable(centresCoutLocal);
        await m.createTable(journauxLocal);
        await m.createTable(planComptableLocal);
        await m.createTable(exercicesLocal);
        await m.createTable(ecrituresLocal);
        await m.createTable(sequencesPieceLocal);
        await creerDeclencheursComptables(this);
      }

      if (from < 16) {
        // M10 DÉPENSES — la pièce comptable (10/10/2026). Deux colonnes
        // AJOUTÉES à `depenses_local`, qui existe depuis la v10 : jamais une
        // table recréée (elle porte les dépenses saisies sur ce poste, la seule
        // copie qui existe). Aucune pièce n'est fabriquée pour les dépenses
        // existantes : `ecriture_id` reste NULL, et l'écran les dit « sans pièce
        // comptable » jusqu'au geste explicite de rattrapage.
        //
        // ⚠ L'ajout est CONDITIONNEL (piège 3) : une base créée par `createAll`
        // à la définition courante puis ramenée en arrière par une fixture porte
        // déjà ces colonnes.
        final colonnes = await m.database
            .customSelect('PRAGMA table_info(depenses_local)')
            .get();
        final noms = {for (final c in colonnes) c.data['name'] as String};
        if (!noms.contains('ecriture_id')) {
          await m.addColumn(depensesLocal, depensesLocal.ecritureId);
        }
        if (!noms.contains('ecriture_refus')) {
          await m.addColumn(depensesLocal, depensesLocal.ecritureRefus);
        }
      }

      if (from < 17) {
        // SESSIONS DE CAISSE (12/10/2026). Une table NEUVE : aucune table
        // existante n'est touchée, AUCUNE ligne n'est fabriquée — une migration
        // ne sait pas quelle caisse était ouverte hier, et en inventer une
        // ferait lire un fond de caisse que personne n'a compté (PA-59/60/61).
        // `createTable` crée la définition COURANTE, exacte ici puisqu'aucune
        // version ultérieure n'a modifié cette table (le jour où une v18 y
        // ajoutera une colonne, elle devra la tester avant `addColumn` —
        // piège 3).
        await m.createTable(sessionsCaisseLocal);
      }

      if (from < 18) {
        // ENCAISSEMENT DE FACTURE (12/10/2026). Une table NEUVE et une colonne
        // AJOUTÉE : aucune table existante n'est recréée, AUCUNE ligne n'est
        // fabriquée. Une migration ne sait pas quelle facture a été réglée
        // hier, ni dans quelle session une vente a été encaissée : en déduire
        // serait deviner où l'argent est entré (PA-59/60/61). Les paniers déjà
        // clôturés gardent donc `session_encaissement_id` NULL — comme les
        // ventes que le serveur n'a pas rattachées à une session.
        //
        // `createTable` crée la définition COURANTE, exacte ici puisqu'aucune
        // version ultérieure n'a modifié cette table (le jour où une v19 y
        // ajoutera une colonne, elle devra la tester avant `addColumn` —
        // piège 3).
        await m.createTable(paiementsFactureLocal);

        // ⚠ L'ajout de la colonne est CONDITIONNEL (piège 3, rencontré pour de
        // vrai) : `paniers_local` est créée par `m.createTable` à sa définition
        // COURANTE quand le poste vient d'avant la v3 — elle porte alors déjà
        // `session_encaissement_id`, et un `addColumn` échouerait sur
        // « duplicate column name ». Même cas pour une fixture de retour arrière.
        final colonnes = await m.database
            .customSelect('PRAGMA table_info(paniers_local)')
            .get();
        final noms = {for (final c in colonnes) c.data['name'] as String};
        if (!noms.contains('session_encaissement_id')) {
          await m.addColumn(paniersLocal, paniersLocal.sessionEncaissementId);
        }
      }

      if (from < 19) {
        // L'ANNULATION AVEC COMMISSION ET REMBOURSEMENT (12/10/2026). Huit
        // colonnes AJOUTÉES à `reservations_local`, qui existe depuis la v1 :
        // jamais une table recréée (elle porte les réservations saisies sur ce
        // poste, la seule copie qui existe). TOUTES nullables, AUCUNE valeur
        // fabriquée : une réservation passée à l'état « annule » avant la v19
        // n'avait ni taux, ni commission, ni remboursement — lui en prêter un
        // affirmerait une
        // commission que personne n'a retenue, sur le compte d'un client. Elle
        // garde donc ses colonnes à NULL, et l'onglet « Annulations » la montre
        // avec des tirets.
        //
        // ⚠ L'ajout est CONDITIONNEL, colonne par colonne (piège 3) : une base
        // créée par `createAll` à la définition courante puis ramenée en
        // arrière par une fixture porte déjà certaines de ces colonnes, et un
        // `addColumn` échouerait sur « duplicate column name ».
        final colonnes = await m.database
            .customSelect('PRAGMA table_info(reservations_local)')
            .get();
        final noms = {for (final c in colonnes) c.data['name'] as String};
        final r = reservationsLocal;
        final aAjouter = <String, GeneratedColumn>{
          'taux_annulation_centiemes': r.tauxAnnulationCentiemes,
          'montant_total_annulation_centimes': r.montantTotalAnnulationCentimes,
          'montant_commission_annulation_centimes':
              r.montantCommissionAnnulationCentimes,
          'montant_rembourse_annulation_centimes':
              r.montantRembourseAnnulationCentimes,
          'mode_saisie_remboursement': r.modeSaisieRemboursement,
          'date_annulation': r.dateAnnulation,
          'utilisateur_annulation_id': r.utilisateurAnnulationId,
          'ecriture_remboursement_id': r.ecritureRemboursementId,
        };
        for (final e in aAjouter.entries) {
          if (!noms.contains(e.key)) await m.addColumn(r, e.value);
        }
      }

      if (from < 20) {
        // LE RÈGLEMENT FOURNISSEUR (12/10/2026, D66). Une table NEUVE : aucune
        // table existante n'est touchée, AUCUNE ligne n'est fabriquée. Une
        // migration ne sait pas quelle commande a été payée hier ni par quelle
        // trésorerie : lui prêter un règlement ferait lire un décaissement que
        // personne n'a constaté, et le « Reste dû » de chaque commande d'avant
        // reste donc égal à son montant (aucun règlement n'est connu — ce qui
        // est vrai du poste, pas de la réalité, et l'écran du Gîte ne peut pas
        // le deviner). `createTable` crée la définition COURANTE, exacte ici
        // puisqu'aucune version ultérieure n'a modifié cette table (le jour où
        // une v21 y ajoutera une colonne, elle devra la tester avant
        // `addColumn` — piège 3).
        await m.createTable(reglementsFournisseurLocal);
      }

      if (from < 21) {
        // L'ARCHIVAGE D'UN FOURNISSEUR (12/10/2026, D63). Une colonne AJOUTÉE à
        // `fournisseurs_local`, qui existe depuis la v13 : jamais une table
        // recréée (elle porte les fournisseurs saisis sur ce poste, la seule
        // copie qui existe). `DEFAULT 1` : tout fournisseur d'avant est ACTIF,
        // et c'est un fait — le geste d'archivage était refusé, aucun n'a donc
        // été archivé. Rien n'est déduit.
        //
        // ⚠ L'ajout est CONDITIONNEL (piège 3) : une base créée par `createAll`
        // à la définition courante puis ramenée en arrière par une fixture porte
        // déjà la colonne, et `addColumn` échouerait sur « duplicate column
        // name ».
        final colonnes = await m.database
            .customSelect('PRAGMA table_info(fournisseurs_local)')
            .get();
        final noms = {for (final c in colonnes) c.data['name'] as String};
        if (!noms.contains('actif')) {
          await m.addColumn(fournisseursLocal, fournisseursLocal.actif);
        }
      }

      if (from < 22) {
        // L'ÉTAT « VU » DES ALERTES (14/10/2026, lot B). Une table NEUVE :
        // aucune table existante n'est touchée, AUCUNE ligne n'est fabriquée —
        // une migration ne sait pas quelle alerte un compte a lue hier ; toutes
        // les alertes dérivées d'un poste mis à jour s'affichent donc « non
        // lues », ce qui est vrai de ce poste. `createTable` crée la définition
        // COURANTE, exacte ici puisqu'aucune version ultérieure n'a modifié
        // cette table (le jour où une v23 y ajoutera une colonne, elle devra la
        // tester avant `addColumn` — piège 3).
        await m.createTable(alertesVuesLocal);
      }

      if (from < 23) {
        // LES SÉJOURS (14/10/2026, lot C, D408). Une table NEUVE : aucune table
        // existante n'est touchée, AUCUNE ligne n'est fabriquée — une migration
        // ne sait pas quel client est réellement arrivé hier. Toute réservation
        // d'avant reste donc « sans séjour » : son arrivée se pointe au geste,
        // jamais par déduction. `createTable` crée la définition COURANTE,
        // exacte ici puisqu'aucune version ultérieure n'a modifié cette table
        // (le jour où une v24 y ajoutera une colonne, elle devra la tester
        // avant `addColumn` — piège 3).
        await m.createTable(sejoursLocal);
      }

      if (from < 24) {
        // LES RÔLES (14/10/2026). Une table NEUVE : aucune table existante
        // n'est touchée, AUCUNE ligne n'est fabriquée ici — le socle du CdCF
        // est posé par `RolesDao.installerSocle` à la première lecture de
        // l'écran, qui ne crée que les rôles ABSENTS et ne réécrit jamais un
        // rôle présent (règle de `RolePermissionSeeder`). Les droits des
        // comptes existants ne sont pas touchés : seul un geste de l'écran les
        // réécrit. `createTable` crée la définition COURANTE, exacte ici
        // puisqu'aucune version ultérieure n'a modifié cette table (piège 3).
        await m.createTable(rolesLocal);
      }

      if (from < 25) {
        // LA BOÎTE D'ENVOI DE « CONTACTEZ L'ÉDITEUR » (14/10/2026, Lot J2
        // partie 2). Une table NEUVE : aucune table existante n'est touchée,
        // AUCUNE ligne n'est fabriquée — avant la v25, le poste n'enregistrait
        // aucun envoi (l'écran le disait), il n'y a donc rien à reprendre.
        // `createTable` crée la définition COURANTE, exacte ici puisqu'aucune
        // version ultérieure n'a modifié cette table (le jour où une v26 y
        // ajoutera une colonne, elle devra la tester avant `addColumn` —
        // piège 3).
        await m.createTable(messagesEditeurLocal);
      }

      if (from < 26) {
        // LA FILE D'ENVOI (15/10/2026, lot F1). Une table NEUVE et ses deux
        // index : aucune table existante n'est touchée, AUCUNE ligne n'est
        // fabriquée — la migration ne sait pas ce que le serveur détient
        // déjà ; reprendre l'existant d'un poste est une décision à part
        // (amorçage, F2), pas un effet de bord de la mise à jour.
        // `createTable` crée la définition COURANTE, exacte ici puisqu'aucune
        // version ultérieure n'a modifié cette table (le jour où une v27 y
        // ajoutera une colonne, elle devra la tester avant `addColumn` —
        // piège 3). `createTable` ne pose PAS les index déclarés par
        // `@TableIndex` : ils sont créés ici, chacun SEULEMENT s'il manque —
        // un fichier dont la version a été rabaissée sans retirer la table
        // (fixtures de `cycle_de_vie_test`) les porte déjà, et un
        // `CREATE INDEX` nu y échoue sur « index already exists » (rencontré
        // en écrivant cette version). Le test de migration v26 les relit dans
        // `sqlite_master`.
        await m.createTable(operationsSyncLocal);
        for (final index in [
          idxOperationsSyncStatutSeq,
          idxOperationsSyncEntite,
        ]) {
          final present = await m.database
              .customSelect(
                "SELECT 1 FROM sqlite_master WHERE type = 'index' "
                'AND name = ?',
                variables: [Variable.withString(index.entityName)],
              )
              .get();
          if (present.isEmpty) await m.createIndex(index);
        }
      }

      if (from < 27) {
        // LA DESCENTE DU CATALOGUE (15/10/2026, lot F2b). Deux tables NEUVES,
        // sans index déclaré : aucune table existante n'est touchée, AUCUNE
        // ligne n'est fabriquée — sans curseur, la première descente part du
        // début du catalogue serveur, ce qui est exact pour un poste qui n'a
        // jamais rien reçu ; sans correspondance, chaque identifiant serveur
        // est pris tel quel, et la file (`fusionne_avec`) puis le flux du
        // serveur les rétablissent à la première descente. `createTable` crée
        // la définition COURANTE, exacte ici puisqu'aucune version ultérieure
        // n'a modifié ces tables (le jour où une v28 y ajoutera une colonne,
        // elle devra la tester avant `addColumn` — piège 3).
        await m.createTable(etatSynchronisationLocal);
        await m.createTable(correspondancesSyncLocal);
      }
      if (from < 28) {
        // L'ORIGINE DES DOCUMENTS DESCENDUS (17/10/2026, lot F4). Une table
        // NEUVE, sans index déclaré : rien d'existant n'est touché, AUCUNE
        // ligne n'est fabriquée — tout ce que le poste détient avant la v28
        // a été saisi ICI (rien d'autre que le catalogue, les clients et les
        // réservations ne descendait), ce que l'absence de ligne signifie.
        // Pour les réservations et les clients DÉJÀ descendus (F3), l'origine
        // est inconnue : aucune pièce n'en dépend (ni rattrapage, ni
        // annulation ne lisent cette table pour eux). `createTable` crée la
        // définition COURANTE, exacte ici (piège 3 : une v29 qui y ajoute une
        // colonne la testera avant `addColumn`).
        await m.createTable(originesDocumentsLocal);
      }
      if (from < 29) {
        // L'OCCUPATION DES TABLES PAR LES AUTRES POSTES (18/10/2026, lot F6).
        // Une table NEUVE, sans index ni clé étrangère : rien d'existant
        // n'est touché, aucune ligne n'est fabriquée (la descente la remplit).
        await m.createTable(occupationsTablesLocal);
      }
      if (from < 31) {
        // LES RETRAITS DE LA CARTE DU JOUR (21/10/2026). Une table NEUVE, sans
        // index ni clé étrangère : rien d'existant n'est touché, aucune ligne
        // n'est fabriquée (la descente la remplit). Le curseur est oublié pour
        // que les retraits déjà au serveur descendent.
        await m.createTable(indisponibilitesCarteLocal);
        await customStatement(
          "DELETE FROM etat_synchronisation_local WHERE cle = 'descente.curseur'",
        );
      }
      if (from < 32) {
        // LES ENTRETIENS DE VÉHICULES (21/10/2026). Une table NEUVE, sans index
        // ni clé étrangère ; aucune ligne fabriquée. Le curseur est oublié :
        // les entretiens déjà au serveur redescendent.
        await m.createTable(entretiensVehiculeLocal);
        await customStatement(
          "DELETE FROM etat_synchronisation_local WHERE cle = 'descente.curseur'",
        );
      }
      if (from < 34) {
        // LES ÉCRITURES VALIDÉES DU SERVEUR (21/10/2026), en miroir de lecture
        // seule pour les états financiers. Une table NEUVE, sans clé étrangère ;
        // aucune ligne fabriquée. Le curseur est oublié : les écritures déjà au
        // serveur descendent.
        await m.createTable(ecrituresServeurLocal);
        await customStatement(
          "DELETE FROM etat_synchronisation_local WHERE cle = 'descente.curseur'",
        );
      }

      if (from < 35) {
        // LES COMPLÉMENTS DE LA PWA (21/10/2026, « tout au complet ») : quatre
        // tables NEUVES et cinq colonnes AJOUTÉES (jamais une table recréée : les
        // saisies hors ligne sont la seule copie). Défauts = faits : tout
        // article et tout client d'avant est actif, aucune composition n'est
        // provisoire, aucun panier n'a de remise. Rien n'est déduit.
        // ⚠ Ajouts CONDITIONNELS (piège 3).
        Future<Set<String>> colonnesDe(String t) async => {
          for (final c
              in await m.database.customSelect('PRAGMA table_info($t)').get())
            c.data['name'] as String,
        };
        if (!(await colonnesDe('articles_local')).contains('actif')) {
          await m.addColumn(articlesLocal, articlesLocal.actif);
        }
        if (!(await colonnesDe('clients_local')).contains('actif')) {
          await m.addColumn(clientsLocal, clientsLocal.actif);
        }
        if (!(await colonnesDe(
          'recettes_local',
        )).contains('composition_provisoire')) {
          await m.addColumn(recettesLocal, recettesLocal.compositionProvisoire);
        }
        final paniers = await colonnesDe('paniers_local');
        if (!paniers.contains('remise_type')) {
          await m.addColumn(paniersLocal, paniersLocal.remiseType);
        }
        if (!paniers.contains('remise_valeur_centiemes')) {
          await m.addColumn(paniersLocal, paniersLocal.remiseValeurCentiemes);
        }
        await m.createTable(immobilisationsLocal);
        await m.createTable(relancesClientsLocal);
        await m.createTable(inventairesLocal);
        await m.createTable(lignesInventaireLocal);
        await m.createTable(canauxReservationLocal);
        await customStatement(
          "DELETE FROM etat_synchronisation_local WHERE cle = 'descente.curseur'",
        );
      }
      if (from < 36) {
        // LE LIEN DIRECT PLAT -> ARTICLE DE STOCK (21/10/2026, « Lier au
        // stock » du restaurant). Deux colonnes NULLABLES AJOUTÉES à
        // `plats_local`, jamais une table recréée : aucune valeur fabriquée
        // (un plat d'avant n'a pas de lien). Le curseur est oublié : le
        // catalogue redescend une fois et l'aligneur remplit les colonnes.
        // ⚠ Ajouts CONDITIONNELS (piège 3).
        final colonnes = {
          for (final c
              in await m.database
                  .customSelect('PRAGMA table_info(plats_local)')
                  .get())
            c.data['name'] as String,
        };
        if (!colonnes.contains('article_id')) {
          await m.addColumn(platsLocal, platsLocal.articleId);
        }
        if (!colonnes.contains('unites_vendables')) {
          await m.addColumn(platsLocal, platsLocal.unitesVendables);
        }
        await customStatement(
          "DELETE FROM etat_synchronisation_local WHERE cle = 'descente.curseur'",
        );
      }
      if (from < 37) {
        // LE JOURNAL DE RÉCEPTION (26/10/2026). Une table NEUVE, sans index ni
        // clé étrangère ; aucune ligne fabriquée (la descente la remplit).
        // Ajout CONDITIONNEL (piège 3) : une fixture ramenée en arrière
        // depuis la définition courante peut la porter déjà.
        final existe = await m.database
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' "
              "AND name = 'journal_reception_local'",
            )
            .get();
        if (existe.isEmpty) await m.createTable(journalReceptionLocal);
      }
      if (from < 38) {
        // « LE POSTE FAIT CE QUE LE WEB FAIT » (26/10/2026) : l'historique des
        // prix de la carte (table NEUVE) et six colonnes NULLABLES. Jamais une
        // table recréée ; aucune valeur fabriquée (l'auteur, le statut, le
        // numéro d'une ligne d'avant restent inconnus : « — »). Le curseur est
        // oublié : l'historique et les statuts déjà au serveur redescendent.
        // ⚠ Ajouts CONDITIONNELS (piège 3) : une fixture ramenée en arrière
        // depuis la définition courante porte déjà tout cela.
        Future<Set<String>> colonnesDe(String t) async => {
          for (final c
              in await m.database.customSelect('PRAGMA table_info($t)').get())
            c.data['name'] as String,
        };
        final existe = await m.database
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' "
              "AND name = 'historique_prix_carte_local'",
            )
            .get();
        if (existe.isEmpty) await m.createTable(historiquePrixCarteLocal);
        if (!(await colonnesDe('contrats_location_local')).contains('statut')) {
          await m.addColumn(
            contratsLocationLocal,
            contratsLocationLocal.statut,
          );
        }
        final operations = await colonnesDe('operations_sync_local');
        if (!operations.contains('auteur_login')) {
          await m.addColumn(
            operationsSyncLocal,
            operationsSyncLocal.auteurLogin,
          );
        }
        if (!operations.contains('poste_nom')) {
          await m.addColumn(operationsSyncLocal, operationsSyncLocal.posteNom);
        }
        final paniers = await colonnesDe('paniers_local');
        if (!paniers.contains('numero_vente')) {
          await m.addColumn(paniersLocal, paniersLocal.numeroVente);
        }
        if (!paniers.contains('auteur_login')) {
          await m.addColumn(paniersLocal, paniersLocal.auteurLogin);
        }
        await customStatement(
          "DELETE FROM etat_synchronisation_local WHERE cle = 'descente.curseur'",
        );
      }
      if (from < 39) {
        // LA BOÎTE D'ENVOI DES E-MAILS (26/10/2026). Une table NEUVE, sans clé
        // étrangère ; aucune ligne fabriquée. Ajout CONDITIONNEL (piège 3) :
        // une fixture ramenée en arrière depuis la définition courante peut la
        // porter déjà.
        final existe = await m.database
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' "
              "AND name = 'boite_envoi_emails_local'",
            )
            .get();
        if (existe.isEmpty) await m.createTable(boiteEnvoiEmailsLocal);
      }
      if (from < 40) {
        // LES CLÔTURES D'EXERCICE DU POSTE (26/10/2026). Une table NEUVE ; aucune
        // ligne fabriquée (un exercice déjà clôturé n'a pas de clôture locale).
        // Ajout CONDITIONNEL (piège 3) : une fixture ramenée en arrière depuis
        // la définition courante peut la porter déjà.
        final existe = await m.database
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' "
              "AND name = 'clotures_exercices_local'",
            )
            .get();
        if (existe.isEmpty) await m.createTable(cloturesExercicesLocal);
      }
      if (from < 41) {
        // LES CHAMPS DU WEB QUE LE POSTE NE PORTAIT PAS (27/10/2026) : dix colonnes
        // NULLABLES, aucune table, aucune valeur fabriquée (un ancien contrat garde
        // montant, acompte et N° nuls : « — »). Ajouts CONDITIONNELS (piège 3) : une
        // fixture ramenée en arrière depuis la définition courante les porte déjà,
        // et un fichier déjà à la forme v41 mais marqué v40 doit se rejouer. Le
        // curseur est oublié : plats, véhicules, contrats et guides déjà au serveur
        // redescendent avec leurs nouveaux champs.
        Future<Set<String>> colonnesDe(String t) async => {
          for (final c
              in await m.database.customSelect('PRAGMA table_info($t)').get())
            c.data['name'] as String,
        };
        final vehicules = await colonnesDe('vehicules_local');
        if (!vehicules.contains('annee')) {
          await m.addColumn(vehiculesLocal, vehiculesLocal.annee);
        }
        if (!vehicules.contains('capacite')) {
          await m.addColumn(vehiculesLocal, vehiculesLocal.capacite);
        }
        if (!vehicules.contains('transmission')) {
          await m.addColumn(vehiculesLocal, vehiculesLocal.transmission);
        }
        final contrats = await colonnesDe('contrats_location_local');
        if (!contrats.contains('numero')) {
          await m.addColumn(
            contratsLocationLocal,
            contratsLocationLocal.numero,
          );
        }
        if (!contrats.contains('remise')) {
          await m.addColumn(
            contratsLocationLocal,
            contratsLocationLocal.remise,
          );
        }
        if (!contrats.contains('acompte')) {
          await m.addColumn(
            contratsLocationLocal,
            contratsLocationLocal.acompte,
          );
        }
        if (!contrats.contains('montant')) {
          await m.addColumn(
            contratsLocationLocal,
            contratsLocationLocal.montant,
          );
        }
        if (!(await colonnesDe('plats_local')).contains('categorie')) {
          await m.addColumn(platsLocal, platsLocal.categorie);
        }
        final guides = await colonnesDe('guides_local');
        if (!guides.contains('certification')) {
          await m.addColumn(guidesLocal, guidesLocal.certification);
        }
        if (!guides.contains('tarif_jour')) {
          await m.addColumn(guidesLocal, guidesLocal.tarifJour);
        }
        await customStatement(
          "DELETE FROM etat_synchronisation_local WHERE cle = 'descente.curseur'",
        );
      }
      if (from < 42) {
        // LE REÇU EN IMAGE D'UNE DÉPENSE (27/10/2026) : six colonnes NULLABLES,
        // aucune table, aucune valeur fabriquée. Ajouts CONDITIONNELS (piège 3) :
        // une fixture ramenée en arrière depuis la définition courante les porte
        // déjà, et un fichier à la forme v42 marqué v41 doit se rejouer. Le curseur
        // est oublié : les dépenses déjà au serveur redescendent avec la référence
        // de leur reçu.
        final depenses = {
          for (final c
              in await m.database
                  .customSelect('PRAGMA table_info(depenses_local)')
                  .get())
            c.data['name'] as String,
        };
        if (!depenses.contains('recu_nom')) {
          await m.addColumn(depensesLocal, depensesLocal.recuNom);
        }
        if (!depenses.contains('recu_sha256')) {
          await m.addColumn(depensesLocal, depensesLocal.recuSha256);
        }
        if (!depenses.contains('recu_taille')) {
          await m.addColumn(depensesLocal, depensesLocal.recuTaille);
        }
        if (!depenses.contains('recu_type')) {
          await m.addColumn(depensesLocal, depensesLocal.recuType);
        }
        if (!depenses.contains('recu_statut')) {
          await m.addColumn(depensesLocal, depensesLocal.recuStatut);
        }
        if (!depenses.contains('recu_cause')) {
          await m.addColumn(depensesLocal, depensesLocal.recuCause);
        }
        await customStatement(
          "DELETE FROM etat_synchronisation_local WHERE cle = 'descente.curseur'",
        );
      }
      if (from < 43) {
        // A5 « PURGER » (28/10/2026) : la file d'envoi accepte le type
        // `suppression`. Le CHECK d'une table ne se modifie pas : la table est
        // RECRÉE par `elargirTypesOperationsSync` (conditionnel, copie intégrale
        // avant tout abandon, `seq` conservé). Aucune ligne n'est fabriquée.
        await elargirTypesOperationsSync(m, operationsSyncLocal);
      }
      if (from < 44) {
        // D246 ROUVERT (28/10/2026) : une table NEUVE et une colonne NULLABLE, aucune
        // ligne fabriquée. Ajouts CONDITIONNELS (piège 3) : une fixture ramenée en
        // arrière depuis la définition courante les porte déjà, et un fichier déjà
        // à la forme v44 mais marqué v42 ou v43 doit se rejouer. Le curseur est
        // oublié : le plan du serveur et l'origine des pièces redescendent.
        final tables = {
          for (final t
              in await m.database
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type = 'table'",
                  )
                  .get())
            t.data['name'] as String,
        };
        if (!tables.contains('pieces_saisie_local')) {
          await m.createTable(piecesSaisieLocal);
        }
        final miroir = {
          for (final c
              in await m.database
                  .customSelect('PRAGMA table_info(ecritures_serveur_local)')
                  .get())
            c.data['name'] as String,
        };
        if (!miroir.contains('piece_origine_id')) {
          await m.addColumn(
            ecrituresServeurLocal,
            ecrituresServeurLocal.pieceOrigineId,
          );
        }
        await customStatement(
          "DELETE FROM etat_synchronisation_local WHERE cle = 'descente.curseur'",
        );
      }
      if (from < 45) {
        // L'E-MAIL FACULTATIF d'un employé et d'un compte (28/10/2026) : DEUX colonnes
        // NULLABLES, aucune table, aucune adresse déduite. Ajouts CONDITIONNELS
        // (piège 3) : une fixture ramenée en arrière depuis la définition courante les
        // porte déjà, et un fichier à la forme v45 marqué v44 doit se rejouer. Une table
        // absente (jeu de colonnes vide) n'est pas touchée ici : la réconciliation finale
        // la complète. Le curseur est oublié : les e-mails des employés déjà au serveur
        // redescendent.
        Future<Set<String>> colonnes(String table) async => {
          for (final c
              in await m.database
                  .customSelect('PRAGMA table_info($table)')
                  .get())
            c.data['name'] as String,
        };
        final employes = await colonnes('employes_local');
        if (employes.isNotEmpty && !employes.contains('email')) {
          await m.addColumn(employesLocal, employesLocal.email);
        }
        final comptes = await colonnes('utilisateurs_local');
        if (comptes.isNotEmpty && !comptes.contains('email')) {
          await m.addColumn(utilisateursLocal, utilisateursLocal.email);
        }
        await customStatement(
          "DELETE FROM etat_synchronisation_local WHERE cle = 'descente.curseur'",
        );
      }
      if (from < 46) {
        // MOT DE PASSE PERDU SANS E-MAIL (29/10/2026) : colonnes ADDITIVES sur les
        // comptes et UNE table locale. Ajouts CONDITIONNELS (piège 3) : une fixture
        // ramenée en arrière depuis la définition courante porte déjà les colonnes
        // des comptes (`retour_arriere_schema.dart`), et un fichier à la forme v46
        // marqué v45 doit se rejouer. Une table absente (jeu de colonnes vide) n'est
        // pas touchée ici : la réconciliation finale la complète. Aucune ligne n'est
        // fabriquée, aucun code de secours posé.
        final comptes = {
          for (final c
              in await m.database
                  .customSelect('PRAGMA table_info(utilisateurs_local)')
                  .get())
            c.data['name'] as String,
        };
        if (comptes.isNotEmpty) {
          final ajouts = <(String, GeneratedColumn<Object>)>[
            ('changement_obligatoire', utilisateursLocal.changementObligatoire),
            (
              'mdp_temporaire_expire_le',
              utilisateursLocal.mdpTemporaireExpireLe,
            ),
            ('sel_precedent', utilisateursLocal.selPrecedent),
            ('empreinte_precedente', utilisateursLocal.empreintePrecedente),
            ('iterations_precedentes', utilisateursLocal.iterationsPrecedentes),
            ('code_secours_sel', utilisateursLocal.codeSecoursSel),
            ('code_secours_empreinte', utilisateursLocal.codeSecoursEmpreinte),
            (
              'code_secours_iterations',
              utilisateursLocal.codeSecoursIterations,
            ),
            ('code_secours_genere_le', utilisateursLocal.codeSecoursGenereLe),
            ('code_secours_echecs', utilisateursLocal.codeSecoursEchecs),
            (
              'code_secours_dernier_echec_le',
              utilisateursLocal.codeSecoursDernierEchecLe,
            ),
          ];
          for (final (nom, colonne) in ajouts) {
            if (!comptes.contains(nom)) {
              await m.addColumn(utilisateursLocal, colonne);
            }
          }
        }
        final tables = {
          for (final t
              in await m.database
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type = 'table'",
                  )
                  .get())
            t.data['name'] as String,
        };
        if (!tables.contains('journal_securite_local')) {
          await m.createTable(journalSecuriteLocal);
        }
      }
      if (from < 33) {
        // LES PLANNINGS ET LES CONGÉS (21/10/2026). Deux tables NEUVES, sans
        // index ni clé étrangère ; aucune ligne fabriquée. Le curseur est oublié :
        // les créneaux et les demandes déjà au serveur redescendent.
        await m.createTable(planningsLocal);
        await m.createTable(congesLocal);
        await customStatement(
          "DELETE FROM etat_synchronisation_local WHERE cle = 'descente.curseur'",
        );
      }
      if (from < 30) {
        // LE FACTEUR DE CONVERSION DES BOISSONS (21/10/2026, stock estimé hors
        // ligne). Une colonne AJOUTÉE à `cartes_boisson_local`, jamais une
        // table recréée. NULLABLE : aucune valeur n'est fabriquée pour les
        // boissons d'avant (un défaut de 1 serait faux pour un casier de 24).
        // Le curseur de descente est OUBLIÉ : le catalogue redescend une fois,
        // et l'aligneur — idempotent — remplit la colonne.
        //
        // ⚠ Ajout CONDITIONNEL (piège 3) : une fixture ramenée en arrière
        // depuis la définition courante porte déjà la colonne.
        final colonnes = await m.database
            .customSelect('PRAGMA table_info(cartes_boisson_local)')
            .get();
        final noms = {for (final c in colonnes) c.data['name'] as String};
        if (!noms.contains('unites_vendables')) {
          await m.addColumn(
            cartesBoissonLocal,
            cartesBoissonLocal.unitesVendables,
          );
        }
        await m.database.customStatement(
          "DELETE FROM etat_synchronisation_local WHERE cle = 'descente.curseur'",
        );
      }

      // Filet final (PRD réinstallation R2) : ce que les paliers n'ont pas posé
      // (palier sauté, branche parallèle) est complété, jamais retiré.
      await reconcilierSchema(this);
    },

    beforeOpen: (details) async {
      journalDemarrage?.call(
        'Base ouverte : schéma v${details.versionNow}'
        '${details.hadUpgrade ? ' (migrée depuis v${details.versionBefore})' : ''}'
        '${details.wasCreated ? ' (créée)' : ''}',
      );
      // Version courante mais schéma incomplet : réparée AVANT d'activer les
      // clés étrangères (un `ADD COLUMN ... REFERENCES` les refuserait).
      if (!details.wasCreated &&
          !details.hadUpgrade &&
          await ecartRapide(this)) {
        await reconcilierSchema(this);
      }
      // Les clés étrangères ne sont PAS actives par défaut sous SQLite.
      // Sans cette ligne, une ligne de facture peut survivre à sa facture,
      // et l'incohérence ne se voit qu'à la synchronisation.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

/// Ouvre la base — depuis le 17/10/2026 HORS du dossier Documents
/// (`emplacement_base.dart` : `%LOCALAPPDATA%\TATACORA\donnees`, décision du
/// PO), en déménageant au premier démarrage celle qu'un poste plus ancien a
/// laissée dans Documents.
///
/// **Divergence assumée avec le Sprint 0 (à consigner au registre PA).** La
/// spécification liste `sqlite3_flutter_libs` et son
/// `applyWorkaroundToOpenSqlite3OnOldAndroidVersions()`. Depuis
/// `package:sqlite3` 3.x — la version qu'embarque Drift 2.34 —, ce paquet ne
/// fait plus rien : sa version `0.6.0+eol` est une coquille vide, et son
/// mainteneur demande explicitement de le retirer des dépendances.
///
/// Conserver un paquet no-op parce qu'un document l'énumère serait pire qu'une
/// divergence signalée : personne ne saurait, dans six mois, s'il est encore
/// nécessaire.
Future<Directory> dossierDonneesDuPoste() async {
  final windows = Platform.isWindows
      ? dossierBaseWindows(Platform.environment)
      : null;
  return windows != null
      ? Directory(windows)
      : Directory(
          p.join((await getApplicationSupportDirectory()).path, 'donnees'),
        );
}

LazyDatabase _ouvrir() {
  return LazyDatabase(() async {
    final neuf = await dossierDonneesDuPoste();
    final emplacement = await preparerEmplacementBase(
      dossierNeuf: neuf,
      dossierAncien: await getApplicationDocumentsDirectory(),
    );
    return NativeDatabase.createInBackground(emplacement.fichier);
  });
}
