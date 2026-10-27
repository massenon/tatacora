// Vue Blade maîtresse (PA-183) : pwa/transverse/import-export.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/fichiers/enregistrement_export.dart';
import '../../../core/fichiers/selecteur_fichiers.dart';
import '../../../core/navigation/coquille_vue.dart';
import '../../../core/navigation/trace_svg.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/mesures_transverses.dart';
import '../../../shared_widgets/bouton_standard.dart';
import '../../../shared_widgets/cadre_tirete.dart';
import '../../../core/theme/mesures_archives.dart';
import '../../../shared_widgets/toast_export.dart';
import '../../hebergement/presentation/providers_hebergement.dart'
    show rafraichirListes;
import '../../vehicules/presentation/providers_vehicules.dart'
    show rechargerVehicules;
import '../data/archives_poste.dart';
import '../domain/registre_archives.dart';
import 'providers_archives.dart';
import '../../synchronisation/domain/reinitialisation_serveur.dart';
import '../data/importeurs_locaux.dart';
import '../data/reinitialisation_locale.dart';
import '../data/sauvegardes_poste.dart';
import '../domain/import_referentiels.dart';
import 'providers_import_export.dart';
import 'widgets/briques_transverses.dart';

/// L'écran **Import & Export** — lot D du plan du Product Owner (14/10/2026).
///
/// Les QUATRE onglets de la vue, cliquables, dans son ordre : Importer les
/// données, Sauvegardes de la base, Restaurer, Réinitialiser les données de
/// test. Chaque panneau reprend les blocs, titres et aides de la vue.
///
/// ## Ce que le poste détient, et ce qu'il n'a pas (D419)
///
/// - **Tables en base** : MESURÉ — le nombre de tables de la base locale.
/// - **Import** : RÉEL depuis le 14/10/2026 (demande du PO). Le sélecteur
///   liste les modules qui ont un importeur sur ce poste
///   (`data/importeurs_locaux.dart` : M3, M1, M5, M4, M6, M7, M8, M9, l'ordre
///   du registre du serveur) et dont la session a le droit d'écriture. Le
///   modèle s'enregistre par « Enregistrer sous » ; la zone de dépôt ouvre la
///   fenêtre « Ouvrir » (aucun glisser-déposer : aucune dépendance ne le
///   porte, la zone le dit) ; « Valider et contrôler le fichier » rend le
///   rapport du serveur (ERREUR / AVERTIS., plafonnés) en SIMULANT l'écriture
///   dans une transaction annulée ; « Confirmer l'import » recontrôle et écrit
///   tout dans UNE transaction. Écart nommé : une ligne déjà présente (clé
///   naturelle) est IGNORÉE, jamais dupliquée. L'historique est celui de la
///   session (aucune table `journal_imports` sur le poste), et le dit.
/// - **Sauvegardes** (portées à la vue le 21/10/2026, `data/sauvegardes_poste.dart`) :
///   « Générer une sauvegarde de la base » RANGE une copie cohérente de la base
///   (`VACUUM INTO`) dans `sauvegardes/`, à côté de `poste.json` ; la liste,
///   les bandeaux (vert après génération, or pour la plus récente jamais
///   téléchargée), « Télécharger » (fenêtre « Enregistrer sous », qui marque la
///   copie téléchargée), « Retirer de la liste » (avec sa confirmation forte
///   quand la copie n'a jamais été téléchargée) et la rétention de trente jours
///   sont ceux de la vue. « Exporter une table existante » rend une table en
///   JSON (comptes exclus). ÉCARTS nommés (piège 13) : « Rythme automatique »
///   reste « — » (« Quotidien (02h00) » décrit le serveur ; une application de
///   bureau n'est pas allumée à 02h00), et les quatre phrases de la vue qui
///   disent « ce serveur » (« la sauvegarde automatique tourne chaque nuit… »,
///   « tant qu'elle reste sur ce serveur », la rétention, la modale de retrait)
///   disent ici « ce poste », ou la vérité du poste.
/// - **Restaurer** : REFUSÉ (21/10/2026). Le serveur tient un registre
///   d'archives (éléments supprimés de tous les modules, restaurables ou
///   purgeables depuis cet onglet) ; ce poste n'en a aucun : un élément
///   « archivé » n'y est qu'un drapeau de son module (fournisseur inactif,
///   unité hors service), qui se réintègre depuis l'écran de ce module. Un
///   registre transverse demanderait une table d'archives (changement de
///   schéma), des écritures dans des modules qui ne sont pas ceux de cet écran
///   et un contrat de synchronisation de la purge (suppression définitive,
///   que le serveur ne reçoit nulle part). L'encadré de la vue est rendu,
///   suivi d'une ligne « Sur ce poste ». Jetons, un par bloc refusé :
///     blade-refuse:transverse/import-export#restaurer
///     blade-refuse:transverse/import-export#modale:import_export.purge_titre
/// - **Réinitialiser** : « Réinitialiser comme neuf » (demande du PO du
///   14/10/2026, lot E), réplique LOCALE du serveur
///   (`data/reinitialisation_locale.dart`) : refus en build production
///   (sauf serveur réinitialisé depuis, 19/10/2026 — bandeau rouge ; et la
///   phase d'essais annoncée par le serveur — bandeau ambre, phrase de la vue),
///   bascule `reinitialisation_seeders` de Paramètres, rôles d'administration,
///   saisie du mot « VIDER », une transaction. Les trois états de la vue
///   (production, verrouillé, ouvert) et sa modale sont rendus. Depuis le
///   21/10/2026 la phrase de la vue est VRAIE : une sauvegarde complète est
///   rangée juste avant le vidage, et rien n'est vidé si elle échoue.
///
/// Droit : la route de la vue exige PARAM en lecture (`module:PARAM,L`).
class EcranImportExport extends ConsumerStatefulWidget {
  const EcranImportExport({this.moduleInitial, super.key});

  /// La clé d'un module importable (`m5-bar`…) à présélectionner — le bouton
  /// « Importer » d'un écran de module y renvoie (`?module=`).
  final String? moduleInitial;

  @override
  ConsumerState<EcranImportExport> createState() => _EcranImportExportState();
}

/// Les textes de la vue (`pwa.import_export.*`), au mot.
abstract final class TextesImportExport {
  static const String titre = 'Import & Export';
  static const String sousTitre =
      'Chargement de données par module, sauvegardes de la base, restauration des éléments archivés et réinitialisation des jeux de test.';
  static const String ongletImporter = 'Importer les données';
  static const String ongletSauvegardes = 'Sauvegardes de la base';
  static const String ongletRestaurer = 'Restaurer';
  static const String ongletSeeders = 'Réinitialiser les données de test';
  static const String importerModuleLabel = '1. Choisir le module à alimenter';
  static const String importerModuleAide =
      'Chaque module a ses propres colonnes. Le modèle et le contrôle en découlent.';
  static const String importerModuleInvite = '-- Sélectionner un module --';
  static const String importerModeleTitre = '2. Télécharger le fichier modèle';
  static const String importerModeleBouton = 'Télécharger le modèle';
  static const String importerModeleAide1 =
      "Le modèle porte les colonnes exactes et une ligne d'exemple. Ouvrez-le dans Excel, remplacez la ligne d'exemple par vos données, conservez la ligne d'en-tête, puis enregistrez en";
  static const String importerModeleAideFormat = 'CSV UTF-8';
  static const String importerDepotTitre = '3. Déposer le fichier rempli';
  static const String importerDepotAide =
      'Formats acceptés : CSV (séparateur point-virgule ou virgule).';
  static const String importerDepotGlisser = 'Glissez votre fichier ici';
  static const String importerDepotCliquer = 'ou cliquez pour le sélectionner';
  static const String importerValider = 'Valider et contrôler le fichier';
  static const String demarcheTitre = 'Démarche à suivre';
  static const String demarche1 =
      "Choisissez le module. Les colonnes attendues s'affichent.";
  static const String demarche2Avant = 'Téléchargez le modèle et remplissez-le';
  static const String demarche2Fort = "sans modifier la ligne d'en-tête";
  static const String demarche3 =
      'Enregistrez en CSV UTF-8. Sans cet encodage, les accents deviennent illisibles à la relecture.';
  static const String demarche4 =
      "Déposez le fichier et lancez le contrôle. Rien n'est importé à ce stade.";
  static const String demarche5 =
      "Corrigez les erreurs signalées, redéposez, puis confirmez l'import.";
  static const String demarcheEncadreFort = 'Aucun import partiel.';
  static const String demarcheEncadre =
      "Tant qu'une erreur subsiste, rien n'entre en base. Importer « ce qui passe » laisserait un jeu incomplet dont personne ne saurait dire ce qui manque.";
  static const String historiqueTitre = 'Historique des imports';
  static const String historiqueVide = "Aucun import réalisé pour l'instant.";
  static const String sauvegardesGenerer = 'Générer une sauvegarde de la base';
  static const String kpiTables = 'Tables en base';
  static const String kpiSauvegardes = 'Sauvegardes conservées';
  static const String kpiDerniere = 'Dernière sauvegarde';
  static const String kpiRythme = 'Rythme automatique';
  static const String exporterTableBouton = 'Exporter une table existante';
  static const String colFichier = 'FICHIER';
  static const String colDate = 'DATE';
  static const String colTable = 'TABLE';
  static const String colAction = 'ACTION';
  static const String restaurerTitre = "Aucune suppression n'est définitive";
  static const String restaurerTexte =
      "Ici, « supprimer » archive : une unité d'hébergement ou un véhicule retiré du parc est conservé au complet et peut être remis en place ci-dessous. Partout ailleurs, rien ne se supprime — on annule ou on contre-passe, et l'enregistrement reste lisible sur l'écran de son module. La purge définitive existe, mais elle est réservée à l'administrateur et n'a pas de retour : c'est le seul endroit de l'application où une donnée disparaît vraiment.";
  static const String rechercheArchives = 'Rechercher dans les archives…';
  static const String filtreRestaurables = 'À restaurer';
  static const String filtreToutes = 'Toutes les entrées';
  static const String filtreRestaurees = 'Déjà restaurées';
  static const String actionRestaurer = 'Restaurer';
  static const String badgeRestaure = 'RESTAURÉ';
  static const String archivesVide = 'Aucun élément archivé ne correspond.';
  static const String colElement = 'ÉLÉMENT';
  static const String colModule = 'MODULE';
  static const String colArchiveLe = 'ARCHIVÉ LE';
  static const String colPar = 'PAR';
  static const String seedersVerrouilleTitre = 'Réinitialisation désactivée';
  static const String seedersVerrouilleTexte =
      'Cette fonction vide les jeux de données de démonstration. Elle reste fermée par défaut : laissée ouverte sur une base d\'exploitation réelle, elle détruirait le travail de l\'entreprise.';
  static const String tiret = '—';

  // L'onglet « Importer les données », RÉEL depuis le 14/10/2026 — les mots
  // de la vue (`pwa.import_export.*`, `imports.*`).
  static const String colonnesAttendues = 'Colonnes attendues';
  static const String colColonne = 'COLONNE';
  static const String colObligatoire = 'OBLIGATOIRE';
  static const String colValeursAttendues = 'VALEURS ATTENDUES';
  static const String badgeObligatoire = 'OBLIGATOIRE';
  static const String badgeFacultatif = 'facultatif';
  static String exemple(String exemple) => 'ex. $exemple';
  static String fichierSelectionne(String nom, int octets) =>
      'Fichier sélectionné : $nom (${(octets / 1024).round() < 1 ? 1 : (octets / 1024).round()} Ko)';
  static const String rapportConforme = 'Fichier conforme au référentiel';
  static const String rapportNonConforme =
      "Fichier non conforme — rien n'a été importé";
  static String rapportResume(int total) => '$total ligne(s) lue(s) ·';
  static const String rapportResumeExploitables = 'exploitable(s) ·';
  static const String rapportResumeErreurs = 'en erreur ·';
  static String rapportResumeAvertissements(int nombre) =>
      '$nombre avertissement(s)';
  static const String rapportBadgeErreur = 'ERREUR';
  static const String rapportBadgeAvertissement = 'AVERTIS.';
  static String rapportLigne(int numero) => 'Ligne $numero';
  static String rapportSuiteErreurs(int nombre) =>
      '… et $nombre autre(s) erreur(s).';
  static const String rapportAucuneAnomalie =
      'Aucune anomalie relevée. Toutes les colonnes et toutes les valeurs '
      'correspondent au référentiel.';
  static String rapportConfirmer(int nombre) =>
      "Confirmer l'import de $nombre ligne(s)";
  static const String rapportCorriger =
      'Corrigez les lignes ci-dessus dans votre fichier, enregistrez-le à '
      'nouveau en CSV UTF-8, puis redéposez-le. Le contrôle se relance à '
      'chaque dépôt.';
  static String historiqueLignes(int nombre) => '$nombre ligne(s) importée(s)';
  static String importFait(int nombre, String module, int ignorees) =>
      '$nombre ligne(s) importée(s) dans $module.'
      '${ignorees > 0 ? ' $ignorees ligne(s) déjà présente(s), ignorée(s).' : ''}';

  /// AJOUTS et REMPLACEMENTS déclarés (D419, puis 14/10/2026).
  ///
  /// Mots de la vue NON RENDUS, et pourquoi :
  ///  - [importerModeleAide1] (« Le modèle porte les colonnes exactes et une
  ///    ligne d'exemple ») : le modèle du poste n'a AUCUNE ligne d'exemple
  ///    (décision du PO du 14/10/2026 pour l'import d'articles, étendue à tous
  ///    les modules : une ligne d'exemple oubliée s'importerait comme une
  ///    vraie fiche) — [importerModeleAideSurCePoste] dit le vrai ;
  ///  - [importerDepotGlisser] / [importerDepotCliquer] : aucune dépendance du
  ///    poste ne porte le glisser-déposer de Windows — la zone se clique, et
  ///    [importerDepotCliquerSurCePoste] le dit ;
  ///  - [historiqueVide] : le poste ne tient pas de journal des imports d'une
  ///    ouverture à l'autre — [historiqueVideSurCePoste] le dit.
  static const String importerModeleAideSurCePoste =
      "Le modèle porte les colonnes exactes, sans ligne d'exemple : les "
      'exemples sont dans « Colonnes attendues ». Il est généré depuis la même '
      "déclaration que le contrôle : il ne peut pas s'en écarter. Ouvrez-le "
      "dans Excel, ajoutez vos données sous la ligne d'en-tête, conservez-la, "
      'puis enregistrez en';
  static const String importerDepotCliquerSurCePoste =
      'Cliquez ici pour choisir le fichier';
  static const String importerDepotSansGlisser =
      "Fenêtre « Ouvrir » de Windows — le glisser-déposer n'est pas pris en "
      'charge sur ce poste.';
  static const String importerDepotSansModule =
      "Choisissez d'abord le module : le fichier se contrôle contre ses "
      'colonnes.';
  static const String aucunModuleImportable =
      "Votre profil n'a le droit d'écriture sur aucun des modules importables.";
  static const String rapportFichier = 'Fichier';
  static String rapportIgnorees(int nombre) =>
      '$nombre ligne(s) déjà présente(s) — ignorée(s) : un import ne crée '
      'jamais de doublon sur ce poste.';
  static const String rapportRienANouveau =
      'Rien à importer : toutes les lignes existent déjà';
  static const String importAucuneNouvelle =
      "Aucune ligne nouvelle : toutes existent déjà, rien n'a été importé.";
  static const String historiqueVideSurCePoste =
      'Aucun import pendant cette session.';

  // L'onglet « Sauvegardes de la base » — « Générer une sauvegarde » et
  // « Exporter une table existante », RÉELS depuis le 14/10/2026.
  static String sauvegardeGeneree(String fichier, String taille) =>
      'Sauvegarde générée : $fichier ($taille).';
  static String sauvegardeEnregistree(String fichier) =>
      'Sauvegarde enregistrée : $fichier.';
  static String sauvegardeEchec(Object erreur) =>
      'La sauvegarde a échoué : $erreur';
  static const String exportTableTitre = 'Exporter une table existante';
  static const String exportTableAide =
      'Le contenu actuel de la table, au format JSON.';
  static const String exportTableInvite = '-- Sélectionner une table --';
  static const String exportTableChoisir = 'Sélectionnez une table.';
  static const String actionTelecharger = 'Télécharger';

  /// `sauvegardes_vide` (au mot).
  static const String sauvegardesVide =
      'Aucune sauvegarde. Utilisez le bouton ci-dessus pour en générer une.';

  /// `sauvegarde_contenu`, `action_retirer`, `sauvegarde_non_telechargee`.
  static const String sauvegardeContenu = 'Base complète';
  static const String actionRetirer = 'Retirer de la liste';
  static const String sauvegardeNonTelechargee = 'non téléchargée';

  /// `bandeau_generee_*` et `bandeau_rappel_*` : « sur ce serveur » devient
  /// « sur ce poste » — c'est là que vivent les fichiers (ÉCART nommé).
  static const String bandeauGenereeTitre = 'Sauvegarde générée';
  static String bandeauGenereeTexte(String fichier) =>
      "$fichier — téléchargez-la : tant qu'elle reste sur ce poste, elle ne protège de rien.";
  static const String bandeauRappelTitre =
      'Sauvegarde en attente de téléchargement';
  static String bandeauRappelTexte(String fichier, String date) =>
      "$fichier du $date n'a pas été téléchargée.";

  /// `sauvegardes_retention` : « conservées sur ce serveur » devient « sur ce
  /// poste ».
  static const String sauvegardesRetention =
      "Les sauvegardes des 30 derniers jours sont conservées sur ce poste. Une sauvegarde restée sur la machine ne protège de rien : c'est le téléchargement qui la met à l'abri.";

  /// La modale de retrait — `retrait_*` (« sur ce serveur » → « sur ce poste »).
  static const String retraitTitre = 'Sauvegarde jamais téléchargée';
  static const String retraitMessage =
      "Cette sauvegarde n'existe que sur ce poste.";
  static const String retraitDetail =
      "La retirer la perd définitivement : il n'en existe aucune copie ailleurs.";
  static const String retraitConfirmer = 'Retirer quand même';
  static const String sauvegardeRetiree = 'Sauvegarde retirée de la liste.';
  // « Réinitialiser comme neuf » (lot E, 14/10/2026) — les mots de la vue.
  static const String seedersVerrouilleOuvrirAvant =
      "Un administrateur peut l'ouvrir dans";
  static const String seedersVerrouilleOuvrirLien =
      'Paramètres › Activation & Sécurité';
  static const String seedersBandeauTitre =
      "Fonction ouverte — à refermer dès que l'exploitation réelle commence";

  /// `seeders_bandeau_texte` (au mot) — vraie sur ce poste depuis le
  /// 21/10/2026 : la sauvegarde de sûreté est rangée AVANT le vidage.
  static const String seedersBandeauTexte =
      "Une sauvegarde complète est générée automatiquement avant chaque réinitialisation. C'est le seul filet si la bascule était restée ouverte par erreur.";
  static const String seedersVideTitre = 'Ce qui sera vidé';
  static const String seedersVideTexte =
      "Tout ce que l'exploitation produit : clients, employés et paie, fournisseurs, guides, réservations et séjours, ventes, factures, achats, dépenses, locations, écritures comptables, notifications, caches et files de tâches. Et tout le catalogue : plats, menus, recettes et ingrédients, articles de stock et leurs mouvements, inventaires, carte des boissons, retraits de la carte et historique des prix.";
  static const String seedersConserveTitre = 'Ce qui sera conservé';
  static const String seedersConserveTexte =
      'Comptes et droits, paramètres, journaux, chambres du parc, points de stockage et tables de salle (les lieux, sans article), véhicules, catalogue tourisme et plan comptable.';
  static const String seedersRienAVider =
      'Aucune donnée à vider — la base est déjà vierge.';
  static const String seedersBouton = 'Réinitialiser comme neuf';
  static const String seedersModaleTitre = 'Réinitialiser comme neuf ?';
  static String seedersModaleTexteAvant(int nombre) => '$nombre table(s)';
  static const String seedersModaleTexte1 =
      "vont être vidées : clients, employés, fournisseurs, guides, réservations, ventes, factures, écritures, paie, ainsi que tout le catalogue (plats, menus, recettes et ingrédients, articles de stock et leurs mouvements, inventaires, carte des boissons, retraits de la carte) et tous les jeux de démonstration. Rien n'est semé à nouveau.";
  static const String seedersModaleTexte2 =
      "Les paramètres de l'entreprise, la matrice des droits, votre compte, le journal d'audit, les chambres, les points de stockage, les tables de salle, les véhicules et le catalogue tourisme sont";
  static const String seedersModaleTexte2Fort = 'conservés';
  static const String seedersConfirmationAvant = 'Pour confirmer, saisissez';
  static const String seedersPhraseConfirmation = 'VIDER';
  static const String seedersConfirmationAide =
      "Une saisie plutôt qu'un simple clic : c'est la seule barrière qui résiste à un double-clic distrait.";
  static const String seedersConfirmer = 'Vider définitivement';
  static const String annuler = 'Annuler';
  static const String seedersPhraseInvalide =
      'La phrase tapée ne correspond pas à $seedersPhraseConfirmation.';
  // Phase d'essais en production (19/10/2026) — la phrase de la vue,
  // affichée quand le SERVEUR l'annonce (en-tête de synchronisation).
  static const String resetPhaseEssais =
      "Phase d'essais en Production : la réinitialisation reste possible pour effacer les essais avant la mise en service. Chaque poste devra ensuite être réinitialisé à son tour. Désactivez la phase d'essais le jour de la mise en service réelle.";
  static const String resetEnvironnementProduction =
      "Cet écran s'exécute en Production : la réinitialisation est désactivée, quel que soit votre rôle — c'est l'environnement qui refuse, pas un droit qui manque.";

  /// `seeders_modale_texte_2_fin` (au mot) : vraie depuis le 21/10/2026.
  static const String seedersModaleTexte2Fin =
      '. Une sauvegarde complète est générée juste avant.';
  static String seedersFaitSurCePoste(
    int tables,
    int lignes, {
    String? sauvegarde,
  }) =>
      '$tables table(s) vidée(s), $lignes ligne(s) supprimée(s). Les '
      'paramètres, les droits et les référentiels gardés sont intacts'
      '${sauvegarde == null ? '.' : ' — sauvegarde $sauvegarde générée juste avant.'}';
}

class _EcranImportExportState extends ConsumerState<EcranImportExport> {
  int _onglet = 0;

  static const _onglets = [
    (cle: 'importer', libelle: TextesImportExport.ongletImporter),
    (cle: 'sauvegardes', libelle: TextesImportExport.ongletSauvegardes),
    (cle: 'restaurer', libelle: TextesImportExport.ongletRestaurer),
    (cle: 'seeders', libelle: TextesImportExport.ongletSeeders),
  ];

  @override
  Widget build(BuildContext context) {
    final droits = ref.watch(droitsProvider);
    if (!droits.peutLire(ModuleTatacora.parametres)) {
      return const RefusDroitTransverse(message: LibellesCoquille.sansDroit);
    }
    final peutEcrire = droits.peutEcrire(ModuleTatacora.parametres);
    final nombreTables = ref.watch(baseLocaleProvider).allTables.length;

    return PageTransverse(
      largeurMax: MesuresTransverses.pageEtroite,
      enfants: [
        const EnTeteTransverse(
          trace: TracesCoquille.importExport,
          titre: TextesImportExport.titre,
          sousTitre: TextesImportExport.sousTitre,
        ),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final (i, o) in _onglets.indexed)
              OngletTransverse(
                cle: Key('ie-onglet-${o.cle}'),
                libelle: o.libelle,
                actif: _onglet == i,
                onChoix: () => setState(() => _onglet = i),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.mdPlus), // mb-5
        switch (_onglet) {
          0 => _PanneauImporter(
            peutEcrire: peutEcrire,
            moduleInitial: widget.moduleInitial,
          ),
          1 => _PanneauSauvegardes(
            peutEcrire: peutEcrire,
            nombreTables: nombreTables,
          ),
          2 => _PanneauRestaurer(peutEcrire: peutEcrire),
          _ => _PanneauSeeders(
            peutEcrire: peutEcrire,
            role: ref.watch(sessionProvider)?.role,
          ),
        },
      ],
    );
  }
}

TextStyle get _titreCarte => styleTransverse(
  TaillesContenu.sm,
  poids: FontWeight.bold,
  couleur: Ardoise.c700,
);

TextStyle get _aide =>
    styleTransverse(TaillesContenu.t13, couleur: Ardoise.c500);

/// L'onglet « Importer les données » — la démarche de la vue, RÉELLE :
/// module, modèle, dépôt, rapport de contrôle, confirmation.
///
/// Le sélecteur ne liste que les modules qui ont un importeur sur ce poste
/// (`importeursLocauxProvider`) ET dont la session a le droit d'écriture — le
/// même droit que l'écran du module exige pour créer une fiche.
class _PanneauImporter extends ConsumerStatefulWidget {
  const _PanneauImporter({required this.peutEcrire, this.moduleInitial});

  final bool peutEcrire;
  final String? moduleInitial;

  @override
  ConsumerState<_PanneauImporter> createState() => _PanneauImporterState();
}

class _PanneauImporterState extends ConsumerState<_PanneauImporter> {
  late String? _cle = widget.moduleInitial;
  FichierLu? _fichier;

  /// Le dernier rapport — il porte la clé du module contrôlé : changer de
  /// module ou de fichier le rend caduc.
  ({String cle, RapportImport rapport})? _rapport;
  String? _erreur;
  bool _enCours = false;

  List<ImporteurLocal> _disponibles() {
    final droits = ref.watch(droitsProvider);
    return [
      for (final i in ref.watch(importeursLocauxProvider))
        if (droits.peutEcrire(i.module)) i,
    ];
  }

  ImporteurLocal? _choisi(List<ImporteurLocal> disponibles) {
    for (final i in disponibles) {
      if (i.cle == _cle) return i;
    }
    return null;
  }

  Future<void> _telechargerModele(ImporteurLocal importeur) async {
    await executerExport(
      context,
      () => ref
          .read(enregistrementExportProvider)
          .enregistrerFichier(
            nomSuggere: importeur.nomModele,
            octets: importeur.modeleOctets(),
            type: TypeFichierEnregistre.csv,
          ),
      cleSucces: const Key('ie-modele-enregistre'),
    );
  }

  Future<void> _choisirFichier() async {
    final lu = await ref.read(selecteurFichiersProvider).ouvrirCsv();
    if (lu == null || !mounted) return;
    setState(() {
      _fichier = lu;
      _rapport = null;
      _erreur = null;
    });
  }

  Future<void> _controler(ImporteurLocal importeur) async {
    final fichier = _fichier;
    if (fichier == null || _enCours) return;
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final rapport = await ref
          .read(moteurImportProvider)
          .controler(importeur, fichier.octets);
      if (!mounted) return;
      setState(() => _rapport = (cle: importeur.cle, rapport: rapport));
    } on Object catch (e) {
      if (mounted) setState(() => _erreur = '$e');
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _confirmer(ImporteurLocal importeur) async {
    final fichier = _fichier;
    if (fichier == null || _enCours) return;
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    final messager = ScaffoldMessenger.of(context);
    try {
      final issue = await ref
          .read(moteurImportProvider)
          .appliquer(importeur, fichier.octets);
      if (!mounted) return;
      switch (issue) {
        case ImportFait(:final importees, :final ignorees):
          relireApresImport(ref, importeur.cle);
          ref
              .read(historiqueImportsProvider.notifier)
              .ajouter(
                EntreeHistoriqueImport(
                  module: importeur.nom,
                  lignes: importees,
                  le: DateTime.now(),
                  par: ref.read(sessionProvider)?.login,
                ),
              );
          setState(() {
            _fichier = null;
            _rapport = null;
          });
          messager
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                backgroundColor: AppColors.succes,
                content: Text(
                  importees == 0
                      ? TextesImportExport.importAucuneNouvelle
                      : TextesImportExport.importFait(
                          importees,
                          importeur.nom,
                          ignorees,
                        ),
                  key: const Key('ie-import-fait'),
                ),
              ),
            );
        case ImportNonConforme(:final rapport):
          setState(() => _rapport = (cle: importeur.cle, rapport: rapport));
        case ImportAnnule(:final message):
          setState(() => _erreur = message);
      }
    } on Object catch (e) {
      if (mounted) setState(() => _erreur = '$e');
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final peutEcrire = widget.peutEcrire;
    final disponibles = _disponibles();
    final importeur = _choisi(disponibles);
    final rapport = _rapport != null && _rapport!.cle == importeur?.cle
        ? _rapport!.rapport
        : null;
    final large = MediaQuery.sizeOf(context).width >= AppBreakpoints.lg;
    final bordure = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: const BorderSide(color: Ardoise.c200),
    );

    final gauche = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CarteTransverse(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(TextesImportExport.importerModuleLabel, style: _titreCarte),
              const SizedBox(height: AppSpacing.unit),
              Text(TextesImportExport.importerModuleAide, style: _aide),
              const SizedBox(height: AppSpacing.smPlus),
              DropdownButtonFormField<String>(
                key: const Key('ie-module-import'),
                initialValue: importeur?.cle,
                isExpanded: true,
                hint: Text(
                  TextesImportExport.importerModuleInvite,
                  style: styleTransverse(
                    TaillesContenu.sm,
                    couleur: Ardoise.c400,
                  ),
                ),
                style: styleTransverse(TaillesContenu.sm),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.neutre0,
                  border: bordure,
                  enabledBorder: bordure,
                ),
                items: [
                  for (final i in disponibles)
                    DropdownMenuItem(
                      value: i.cle,
                      child: Text('${i.module.code} — ${i.nom}'),
                    ),
                ],
                onChanged: _enCours
                    ? null
                    : (cle) => setState(() {
                        _cle = cle;
                        _rapport = null;
                        _erreur = null;
                      }),
              ),
              if (disponibles.isEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  TextesImportExport.aucunModuleImportable,
                  key: const Key('ie-aucun-module'),
                  style: _aide,
                ),
              ],
              if (importeur != null) _FicheModule(importeur: importeur),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.mdPlus),
        CarteTransverse(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      TextesImportExport.importerModeleTitre,
                      style: _titreCarte,
                    ),
                  ),
                  if (peutEcrire)
                    Opacity(
                      opacity: importeur == null
                          ? AppColors.opaciteDesactive
                          : 1,
                      child: BoutonTransverse(
                        cle: const Key('ie-modele'),
                        libelle: TextesImportExport.importerModeleBouton,
                        fond: AppColors.gold,
                        trace: TracesCoquille.importExport,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.smPlus,
                          vertical: AppSpacing.xs,
                        ),
                        onTap: () {
                          if (importeur != null) _telechargerModele(importeur);
                        },
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.unit),
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text:
                          '${TextesImportExport.importerModeleAideSurCePoste} ',
                    ),
                    TextSpan(
                      text: TextesImportExport.importerModeleAideFormat,
                      style: _aide.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
                style: _aide,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.mdPlus),
        CarteTransverse(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(TextesImportExport.importerDepotTitre, style: _titreCarte),
              const SizedBox(height: AppSpacing.unit),
              Text(TextesImportExport.importerDepotAide, style: _aide),
              const SizedBox(height: AppSpacing.smPlus),
              // Aucun glisser-déposer : aucune dépendance du poste ne le
              // porte sous Windows. La zone se CLIQUE, et elle le dit.
              InkWell(
                key: const Key('ie-zone-depot'),
                onTap: importeur != null && peutEcrire && !_enCours
                    ? _choisirFichier
                    : null,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: CadreTirete(
                  couleur: JetonsCssMaitre.neutre200,
                  epaisseur: MesuresTransverses.bordureZoneDepot,
                  rayon: AppRadius.md,
                  tiret: MesuresTransverses.tiretZoneDepot,
                  espace: MesuresTransverses.espaceZoneDepot,
                  padding: const EdgeInsets.all(AppSpacing.xl), // p-8
                  child: Column(
                    children: [
                      const IconeTrace(
                        trace:
                            r'<path stroke-linecap="round" stroke-linejoin="round" d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M17 8l-5-5-5 5M12 3v12"/>',
                        taille: MesuresTransverses.iconeDepot,
                        couleur: AppColors.neutre400,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        TextesImportExport.importerDepotCliquerSurCePoste,
                        textAlign: TextAlign.center,
                        style: styleTransverse(
                          TaillesContenu.t15,
                          poids: FontWeight.w600,
                          couleur: Ardoise.c600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.demi),
                      Text(
                        importeur == null
                            ? TextesImportExport.importerDepotSansModule
                            : TextesImportExport.importerDepotSansGlisser,
                        textAlign: TextAlign.center,
                        style: styleTransverse(
                          TaillesContenu.t13,
                          couleur: Ardoise.c400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_fichier != null) ...[
                const SizedBox(height: AppSpacing.smPlus),
                Text(
                  TextesImportExport.fichierSelectionne(
                    _fichier!.nom,
                    _fichier!.octets.length,
                  ),
                  key: const Key('ie-fichier-selectionne'),
                  style: styleTransverse(
                    TaillesContenu.t13,
                    poids: FontWeight.w600,
                    couleur: Ardoise.c600,
                  ),
                ),
              ],
              if (_erreur != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _erreur!,
                  key: const Key('ie-import-erreur'),
                  style: styleTransverse(
                    TaillesContenu.t12,
                    couleur: PaletteMaitre.rouge600,
                  ),
                ),
              ],
              if (peutEcrire) ...[
                const SizedBox(height: AppSpacing.md),
                Opacity(
                  opacity: importeur != null && _fichier != null && !_enCours
                      ? 1
                      : AppColors.opaciteDesactive,
                  child: BoutonTransverse(
                    cle: const Key('ie-valider'),
                    libelle: TextesImportExport.importerValider,
                    fond: AppColors.navy,
                    taille: TaillesContenu.sm,
                    pleineLargeur: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.mdPlus,
                      vertical: AppSpacing.xsPlus,
                    ),
                    onTap: () {
                      if (importeur != null) _controler(importeur);
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
        if (rapport != null && importeur != null) ...[
          const SizedBox(height: AppSpacing.mdPlus),
          _RapportControle(
            rapport: rapport,
            peutConfirmer: peutEcrire && !_enCours,
            onConfirmer: () => _confirmer(importeur),
          ),
        ],
      ],
    );
    final droite = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Demarche(),
        const SizedBox(height: AppSpacing.mdPlus),
        const _HistoriqueImports(),
      ],
    );
    return large
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: gauche),
              const SizedBox(width: AppSpacing.mdPlus),
              Expanded(child: droite),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              gauche,
              const SizedBox(height: AppSpacing.mdPlus),
              droite,
            ],
          );
  }
}

/// La fiche du module : description, puis « Colonnes attendues » — COLONNE,
/// OBLIGATOIRE, VALEURS ATTENDUES — tirée de la MÊME déclaration que le
/// modèle et le contrôle.
class _FicheModule extends StatelessWidget {
  const _FicheModule({required this.importeur});

  final ImporteurLocal importeur;

  @override
  Widget build(BuildContext context) {
    final entete = styleTransverse(
      TaillesContenu.t12,
      poids: FontWeight.bold,
      couleur: Ardoise.c500,
    );
    Widget badge(bool requis) => Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxs,
        vertical: AppSpacing.demi,
      ),
      decoration: BoxDecoration(
        color: requis ? AppColors.badgeRougeFond : Ardoise.c100,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        requis
            ? TextesImportExport.badgeObligatoire
            : TextesImportExport.badgeFacultatif,
        style: styleTransverse(
          TaillesContenu.t11,
          poids: FontWeight.bold,
          couleur: requis ? AppColors.erreur : Ardoise.c400,
        ),
      ),
    );

    return Container(
      key: Key('ie-fiche-${importeur.cle}'),
      margin: const EdgeInsets.only(top: AppSpacing.md),
      padding: const EdgeInsets.only(top: AppSpacing.md),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Ardoise.c100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(importeur.description, style: _aide),
          const SizedBox(height: AppSpacing.sm),
          Text(
            TextesImportExport.colonnesAttendues,
            style: styleTransverse(
              TaillesContenu.t13,
              poids: FontWeight.bold,
              couleur: Ardoise.c700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Container(
            color: Ardoise.c50,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(TextesImportExport.colColonne, style: entete),
                ),
                Expanded(
                  flex: 2,
                  child: Text(TextesImportExport.colObligatoire, style: entete),
                ),
                Expanded(
                  flex: 4,
                  child: Text(
                    TextesImportExport.colValeursAttendues,
                    style: entete,
                  ),
                ),
              ],
            ),
          ),
          for (final c in importeur.colonnes)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Ardoise.c100)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.libelle,
                          style: styleTransverse(
                            TaillesContenu.t13,
                            poids: FontWeight.w600,
                            couleur: Ardoise.c700,
                          ),
                        ),
                        Text(
                          c.champ,
                          style: styleTransverse(
                            TaillesContenu.t12,
                            couleur: Ardoise.c400,
                            police: AppTextStyles.policeMonospace,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: badge(c.requis),
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (c.valeurs != null)
                          Wrap(
                            spacing: AppSpacing.unit,
                            runSpacing: AppSpacing.unit,
                            children: [
                              for (final v in c.valeurs!)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.xxs,
                                    vertical: AppSpacing.demi,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Ardoise.c200),
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.sm,
                                    ),
                                  ),
                                  child: Text(
                                    v,
                                    style: styleTransverse(
                                      TaillesContenu.t12,
                                      couleur: Ardoise.c500,
                                    ),
                                  ),
                                ),
                            ],
                          )
                        else
                          Text(
                            c.type.libelle,
                            style: styleTransverse(
                              TaillesContenu.t13,
                              couleur: Ardoise.c500,
                            ),
                          ),
                        if (c.exemple.isNotEmpty)
                          Text(
                            TextesImportExport.exemple(c.exemple),
                            style: styleTransverse(
                              TaillesContenu.t12,
                              couleur: Ardoise.c400,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Le rapport de contrôle — bandeau conforme / non conforme, décompte, lignes
/// ERREUR / AVERTIS. plafonnées comme au serveur, puis l'action.
class _RapportControle extends StatelessWidget {
  const _RapportControle({
    required this.rapport,
    required this.peutConfirmer,
    required this.onConfirmer,
  });

  final RapportImport rapport;
  final bool peutConfirmer;
  final VoidCallback onConfirmer;

  /// `ImportExport::PLAFOND_ERREURS` / `PLAFOND_AVERTISSEMENTS`.
  static const int plafondErreurs = 60;
  static const int plafondAvertissements = 40;

  @override
  Widget build(BuildContext context) {
    final ok = rapport.ok;
    final couleur = ok ? AppColors.succes : AppColors.erreur;
    final texte = styleTransverse(TaillesContenu.t13, couleur: Ardoise.c600);
    final fort = texte.copyWith(fontWeight: FontWeight.bold);
    final erreurs = rapport.erreurs.take(plafondErreurs).toList();
    final avertissements = rapport.avertissements
        .take(plafondAvertissements)
        .toList();

    Widget anomalie(AnomalieImport a, {required bool erreur}) => Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.mdPlus,
        vertical: AppSpacing.xs,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Ardoise.c100)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: AppSpacing.unit),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxs,
              vertical: AppSpacing.demi,
            ),
            decoration: BoxDecoration(
              color: erreur ? AppColors.badgeRougeFond : PaletteMaitre.ambre50,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              erreur
                  ? TextesImportExport.rapportBadgeErreur
                  : TextesImportExport.rapportBadgeAvertissement,
              style: styleTransverse(
                TaillesContenu.t10,
                poids: FontWeight.bold,
                couleur: erreur ? AppColors.erreur : PaletteTransverse.texteOr,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xsPlus),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: a.ligne == 0
                            ? TextesImportExport.rapportFichier
                            : TextesImportExport.rapportLigne(a.ligne),
                        style: fort.copyWith(
                          fontFamily: AppTextStyles.policeMonospace,
                          color: Ardoise.c700,
                        ),
                      ),
                      if (a.colonne != null) ...[
                        const TextSpan(text: ' · '),
                        TextSpan(
                          text: a.colonne,
                          style: fort.copyWith(color: Ardoise.c700),
                        ),
                      ],
                    ],
                  ),
                  style: texte.copyWith(color: Ardoise.c700),
                ),
                Text(a.message, style: texte.copyWith(color: Ardoise.c500)),
              ],
            ),
          ),
        ],
      ),
    );

    return CarteTransverse(
      key: const Key('ie-rapport'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: ok ? AppColors.badgeVertFond : AppColors.badgeRougeFond,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.mdPlus,
              vertical: AppSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconeTrace(
                  trace: ok
                      ? '<path stroke-linecap="round" stroke-linejoin="round" d="M20 6L9 17l-5-5"/>'
                      : '<circle cx="12" cy="12" r="10"/><path stroke-linecap="round" d="M15 9l-6 6M9 9l6 6"/>',
                  taille: MesuresTransverses.iconeModule,
                  couleur: couleur,
                  epaisseur: MesuresTransverses.traitAppuye,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ok
                            ? TextesImportExport.rapportConforme
                            : TextesImportExport.rapportNonConforme,
                        key: const Key('ie-rapport-verdict'),
                        style: styleTransverse(
                          TaillesContenu.sm,
                          poids: FontWeight.bold,
                          couleur: couleur,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.demi),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text:
                                  '${TextesImportExport.rapportResume(rapport.total)} ',
                            ),
                            TextSpan(text: '${rapport.valides}', style: fort),
                            const TextSpan(
                              text:
                                  ' ${TextesImportExport.rapportResumeExploitables} ',
                            ),
                            TextSpan(text: '${rapport.enErreur}', style: fort),
                            const TextSpan(
                              text:
                                  ' ${TextesImportExport.rapportResumeErreurs} ',
                            ),
                            TextSpan(
                              text:
                                  TextesImportExport.rapportResumeAvertissements(
                                    rapport.avertissements.length,
                                  ),
                            ),
                          ],
                        ),
                        key: const Key('ie-rapport-resume'),
                        style: texte,
                      ),
                      if (rapport.ignorees > 0)
                        Text(
                          TextesImportExport.rapportIgnorees(rapport.ignorees),
                          key: const Key('ie-rapport-ignorees'),
                          style: texte,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: MesuresTransverses.hauteurRapportImport,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final a in erreurs) anomalie(a, erreur: true),
                  for (final a in avertissements) anomalie(a, erreur: false),
                  if (rapport.erreurs.length > erreurs.length)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.mdPlus,
                        vertical: AppSpacing.xs,
                      ),
                      child: Text(
                        TextesImportExport.rapportSuiteErreurs(
                          rapport.erreurs.length - erreurs.length,
                        ),
                        style: texte.copyWith(color: Ardoise.c400),
                      ),
                    ),
                  if (rapport.erreurs.isEmpty && rapport.avertissements.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.mdPlus,
                        vertical: AppSpacing.md,
                      ),
                      child: Text(
                        TextesImportExport.rapportAucuneAnomalie,
                        style: texte.copyWith(color: Ardoise.c500),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.mdPlus,
              vertical: AppSpacing.md,
            ),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Ardoise.c100)),
            ),
            child: ok
                ? Opacity(
                    opacity: peutConfirmer ? 1 : AppColors.opaciteDesactive,
                    child: BoutonTransverse(
                      cle: const Key('ie-confirmer-import'),
                      libelle: rapport.lignes.isEmpty
                          ? TextesImportExport.rapportRienANouveau
                          : TextesImportExport.rapportConfirmer(
                              rapport.lignes.length,
                            ),
                      fond: AppColors.succes,
                      taille: TaillesContenu.sm,
                      pleineLargeur: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.mdPlus,
                        vertical: AppSpacing.xsPlus,
                      ),
                      onTap: () {
                        if (peutConfirmer && rapport.lignes.isNotEmpty) {
                          onConfirmer();
                        }
                      },
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.smPlus,
                      vertical: AppSpacing.xsPlus,
                    ),
                    decoration: BoxDecoration(
                      color: PaletteMaitre.ambre50,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Text(
                      TextesImportExport.rapportCorriger,
                      style: styleTransverse(
                        TaillesContenu.t13,
                        couleur: PaletteTransverse.texteOr,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// « Historique des imports » — ceux de CETTE session de l'application.
class _HistoriqueImports extends ConsumerWidget {
  const _HistoriqueImports();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entrees = ref.watch(historiqueImportsProvider);
    String deux(int n) => n.toString().padLeft(2, '0');
    return CarteTransverse(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.mdPlus,
              vertical: AppSpacing.smPlus,
            ),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Ardoise.c100)),
            ),
            child: Text(TextesImportExport.historiqueTitre, style: _titreCarte),
          ),
          if (entrees.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.mdPlus,
                vertical: AppSpacing.xl,
              ),
              child: Text(
                TextesImportExport.historiqueVideSurCePoste,
                key: const Key('ie-historique-vide'),
                textAlign: TextAlign.center,
                style: styleTransverse(
                  TaillesContenu.t13,
                  couleur: Ardoise.c400,
                ),
              ),
            )
          else
            for (final e in entrees)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.mdPlus,
                  vertical: AppSpacing.sm,
                ),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Ardoise.c100)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.module,
                      style: styleTransverse(
                        TaillesContenu.t15,
                        poids: FontWeight.w600,
                        couleur: Ardoise.c700,
                      ),
                    ),
                    Text(
                      TextesImportExport.historiqueLignes(e.lignes),
                      style: styleTransverse(
                        TaillesContenu.t13,
                        couleur: Ardoise.c500,
                      ),
                    ),
                    Text(
                      '${deux(e.le.day)}/${deux(e.le.month)}/${e.le.year} '
                      '${deux(e.le.hour)}:${deux(e.le.minute)} · '
                      '${e.par ?? TextesImportExport.tiret}',
                      style: styleTransverse(
                        TaillesContenu.t12,
                        couleur: Ardoise.c400,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// « Démarche à suivre » : cinq étapes numérotées, puis l'encadré or.
class _Demarche extends StatelessWidget {
  const _Demarche();

  @override
  Widget build(BuildContext context) {
    final texte = styleTransverse(TaillesContenu.t13, couleur: Ardoise.c600);
    Widget etape(int n, InlineSpan contenu) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: MesuresTransverses.pastilleEtape,
            height: MesuresTransverses.pastilleEtape,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.navy,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$n',
              style: styleTransverse(
                TaillesContenu.t11,
                poids: FontWeight.bold,
                couleur: AppColors.neutre0,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xsPlus),
          Expanded(child: Text.rich(contenu, style: texte)),
        ],
      ),
    );
    return CarteTransverse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(TextesImportExport.demarcheTitre, style: _titreCarte),
          const SizedBox(height: AppSpacing.sm),
          etape(1, const TextSpan(text: TextesImportExport.demarche1)),
          etape(
            2,
            TextSpan(
              children: [
                const TextSpan(text: '${TextesImportExport.demarche2Avant} '),
                TextSpan(
                  text: TextesImportExport.demarche2Fort,
                  style: texte.copyWith(fontWeight: FontWeight.bold),
                ),
                const TextSpan(text: '.'),
              ],
            ),
          ),
          etape(3, const TextSpan(text: TextesImportExport.demarche3)),
          etape(4, const TextSpan(text: TextesImportExport.demarche4)),
          etape(5, const TextSpan(text: TextesImportExport.demarche5)),
          const SizedBox(height: AppSpacing.unit),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xsPlus,
            ),
            decoration: BoxDecoration(
              color: PaletteMaitre.ambre50,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${TextesImportExport.demarcheEncadreFort} ',
                    style: styleTransverse(
                      TaillesContenu.t13,
                      poids: FontWeight.bold,
                      couleur: PaletteTransverse.texteOr,
                    ),
                  ),
                  const TextSpan(text: TextesImportExport.demarcheEncadre),
                ],
              ),
              style: styleTransverse(
                TaillesContenu.t13,
                couleur: PaletteTransverse.texteOr,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// L'onglet « Sauvegardes de la base » — « Générer une sauvegarde de la
/// base » enregistre une copie COHÉRENTE (`VACUUM INTO`) de la base du poste
/// par la fenêtre « Enregistrer sous » ; « Exporter une table existante »
/// rend le contenu d'une table en JSON (`data/sauvegarde_locale.dart`).
class _PanneauSauvegardes extends ConsumerStatefulWidget {
  const _PanneauSauvegardes({
    required this.peutEcrire,
    required this.nombreTables,
  });

  final bool peutEcrire;
  final int nombreTables;

  @override
  ConsumerState<_PanneauSauvegardes> createState() =>
      _PanneauSauvegardesState();
}

class _PanneauSauvegardesState extends ConsumerState<_PanneauSauvegardes> {
  bool _enCours = false;

  /// Le nom de la sauvegarde que ce geste vient de produire : le bandeau VERT
  /// (`sauvegardeGeneree` du composant) ; sinon, le bandeau OR dit celle qui
  /// n'a jamais été téléchargée.
  String? _genere;

  static const String _corbeille =
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M3 6h18M8 6V4a2 2 0 012-2h4a2 2 0 012 2v2m3 0v14a2 2 0 01-2 2H7a2 2 0 01-2-2V6h14z"/>';
  static const String _traceTelecharger =
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M7 10l5 5 5-5M12 15V3"/>';

  static String _taille(int octets) {
    if (octets >= 1024 * 1024) {
      return '${(octets / (1024 * 1024)).toStringAsFixed(1)} Mo';
    }
    return '${(octets / 1024).ceil()} Ko';
  }

  static String _deux(int n) => n.toString().padLeft(2, '0');
  static String _jour(DateTime d) =>
      '${_deux(d.day)}/${_deux(d.month)}/${d.year}';
  static String _heure(DateTime d) => '${_deux(d.hour)}:${_deux(d.minute)}';

  void _dire(String texte, Color fond, Key cle) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: fond,
          content: Text(texte, key: cle),
        ),
      );
  }

  /// « Générer une sauvegarde de la base » : une copie complète RANGÉE sur le
  /// poste (`SauvegardesPoste.generer`), puis le bandeau vert.
  Future<void> _generer() async {
    if (_enCours) return;
    setState(() => _enCours = true);
    try {
      final fichier = await ref.read(sauvegardesPosteProvider).generer();
      ref.invalidate(fichiersSauvegardeProvider);
      if (mounted) {
        setState(() => _genere = fichier.nom);
        _dire(
          TextesImportExport.sauvegardeGeneree(
            fichier.nom,
            _taille(fichier.taille),
          ),
          AppColors.succes,
          const Key('ie-sauvegarde-generee'),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        _dire(
          TextesImportExport.sauvegardeEchec(e),
          AppColors.erreur,
          const Key('ie-sauvegarde-echec'),
        );
      }
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  /// « Télécharger » : la copie rangée est écrite là où l'opérateur le choisit
  /// (fenêtre « Enregistrer sous ») ; ce n'est qu'alors qu'elle est marquée
  /// téléchargée — annuler dans la fenêtre ne met rien à l'abri.
  Future<void> _telecharger(String nom) async {
    try {
      final sauvegardes = ref.read(sauvegardesPosteProvider);
      final octets = await sauvegardes.lire(nom);
      final chemin = await ref
          .read(enregistrementExportProvider)
          .enregistrerFichier(
            nomSuggere: nom,
            octets: octets,
            type: TypeFichierEnregistre.sauvegarde,
          );
      if (chemin == null) return;
      await sauvegardes.marquerTelechargee(nom);
      ref.invalidate(fichiersSauvegardeProvider);
      if (mounted) {
        if (_genere == nom) setState(() => _genere = null);
        _dire(
          TextesImportExport.sauvegardeEnregistree(nomDuFichier(chemin)),
          AppColors.succes,
          const Key('ie-sauvegarde-telechargee'),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        _dire(
          TextesImportExport.sauvegardeEchec(e),
          AppColors.erreur,
          const Key('ie-sauvegarde-echec'),
        );
      }
    }
  }

  /// « Retirer de la liste » : la confirmation forte ne s'ouvre QUE pour une
  /// sauvegarde jamais téléchargée (`retirerSauvegarde` du composant) ; une
  /// sauvegarde téléchargée se retire directement.
  Future<void> _retirer(FichierSauvegarde fichier) async {
    if (!fichier.telechargee) {
      final confirme = await showDialog<bool>(
        context: context,
        barrierColor: AppColors.voileModale,
        builder: (_) => const _ModaleRetraitSauvegarde(),
      );
      if (confirme != true || !mounted) return;
    }
    try {
      await ref.read(sauvegardesPosteProvider).retirer(fichier.nom);
      ref.invalidate(fichiersSauvegardeProvider);
      if (mounted) {
        if (_genere == fichier.nom) setState(() => _genere = null);
        _dire(
          TextesImportExport.sauvegardeRetiree,
          AppColors.succes,
          const Key('ie-sauvegarde-retiree'),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        _dire(
          TextesImportExport.sauvegardeEchec(e),
          AppColors.erreur,
          const Key('ie-sauvegarde-echec'),
        );
      }
    }
  }

  Future<void> _exporterTable() async {
    final service = ref.read(sauvegardeLocaleProvider);
    final table = await showDialog<String>(
      context: context,
      barrierColor: AppColors.voileModale,
      builder: (_) => _ModaleExportTable(tables: service.tablesExportables()),
    );
    if (table == null || !mounted) return;
    await executerExport(
      context,
      () async => ref
          .read(enregistrementExportProvider)
          .exporter(
            base: table,
            type: TypeFichierEnregistre.json,
            octets: await service.exporterTableJson(table),
          ),
      cleSucces: const Key('ie-export-table-enregistre'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final peutEcrire = widget.peutEcrire;
    final nombreTables = widget.nombreTables;
    final largeur = MediaQuery.sizeOf(context).width;
    final fichiers =
        ref.watch(fichiersSauvegardeProvider).value ??
        const <FichierSauvegarde>[];
    final enAttente = fichiers.isNotEmpty && !fichiers.first.telechargee
        ? fichiers.first
        : null;
    Widget kpi(String libelle, String valeur, {Key? cle}) => CarteTransverse(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            libelle,
            style: styleTransverse(TaillesContenu.t12, couleur: Ardoise.c500),
          ),
          const SizedBox(height: AppSpacing.demi),
          Text(
            valeur,
            key: cle,
            style: styleTransverse(
              TaillesContenu.lg,
              poids: FontWeight.bold,
              couleur: AppColors.navy,
              police: AppTextStyles.policeMonospace,
            ),
          ),
        ],
      ),
    );

    // Un bandeau de la vue : icône, titre, texte, et « Télécharger » à droite
    // pour qui écrit.
    Widget bandeau({
      required Key cle,
      required Key cleBouton,
      required Color fond,
      required Color bordure,
      required Color encre,
      required Color bouton,
      required String titre,
      required String texte,
      required String nom,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.mdPlus), // mb-5
      child: EncadreTransverse(
        key: cle,
        fond: fond,
        bordure: bordure,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titre,
                    style: styleTransverse(
                      TaillesContenu.t15,
                      poids: FontWeight.bold,
                      couleur: encre,
                    ),
                  ),
                  Text(
                    texte,
                    style: styleTransverse(TaillesContenu.t13, couleur: encre),
                  ),
                ],
              ),
            ),
            if (peutEcrire) ...[
              const SizedBox(width: AppSpacing.sm),
              BoutonTransverse(
                cle: Key(
                  '${cle.toString().replaceAll(RegExp(r"[\[\]<>']"), '')}-telecharger',
                ),
                libelle: TextesImportExport.actionTelecharger,
                fond: bouton,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                onTap: () => _telecharger(nom),
              ),
            ],
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_genere != null)
          bandeau(
            cle: const Key('ie-bandeau-generee'),
            cleBouton: const Key('ie-bandeau-generee-telecharger'),
            fond: AppColors.badgeVertFond,
            bordure: PaletteTransverse.vert300,
            encre: PaletteTransverse.texteVert,
            bouton: AppColors.succes,
            titre: TextesImportExport.bandeauGenereeTitre,
            texte: TextesImportExport.bandeauGenereeTexte(_genere!),
            nom: _genere!,
          )
        else if (enAttente != null)
          bandeau(
            cle: const Key('ie-bandeau-rappel'),
            cleBouton: const Key('ie-bandeau-rappel-telecharger'),
            fond: PaletteMaitre.ambre50,
            bordure: PaletteMaitre.ambre200,
            encre: PaletteTransverse.texteOr,
            bouton: AppColors.gold,
            titre: TextesImportExport.bandeauRappelTitre,
            texte: TextesImportExport.bandeauRappelTexte(
              enAttente.nom,
              _jour(enAttente.date),
            ),
            nom: enAttente.nom,
          ),
        GrilleTransverse(
          colonnes: largeur >= AppBreakpoints.sm
              ? MesuresTransverses.colonnesKpiSauvegardes
              : 1,
          ecart: AppSpacing.smPlus,
          enfants: [
            kpi(
              TextesImportExport.kpiTables,
              '$nombreTables',
              cle: const Key('ie-kpi-tables'),
            ),
            kpi(
              TextesImportExport.kpiSauvegardes,
              '${fichiers.length}',
              cle: const Key('ie-kpi-sauvegardes'),
            ),
            kpi(
              TextesImportExport.kpiDerniere,
              fichiers.isEmpty
                  ? TextesImportExport.tiret
                  : _jour(fichiers.first.date),
              cle: const Key('ie-kpi-derniere'),
            ),
            kpi(TextesImportExport.kpiRythme, TextesImportExport.tiret),
          ],
        ),
        const SizedBox(height: AppSpacing.mdPlus),
        Wrap(
          spacing: AppSpacing.xsPlus,
          runSpacing: AppSpacing.xsPlus,
          children: [
            if (peutEcrire)
              Opacity(
                opacity: _enCours ? AppColors.opaciteDesactive : 1,
                child: BoutonTransverse(
                  cle: const Key('ie-generer-sauvegarde'),
                  libelle: TextesImportExport.sauvegardesGenerer,
                  fond: AppColors.navy,
                  taille: TaillesContenu.sm,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.mdPlus,
                    vertical: AppSpacing.xsPlus,
                  ),
                  onTap: _generer,
                ),
              ),
            BoutonTransverse(
              cle: const Key('ie-exporter-table'),
              libelle: TextesImportExport.exporterTableBouton,
              trace: TracesCoquille.importExport,
              taille: TaillesContenu.sm,
              couleurContour: Ardoise.c200,
              couleurTexteContour: Ardoise.c600,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.mdPlus,
                vertical: AppSpacing.xsPlus,
              ),
              onTap: _exporterTable,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        CarteTransverse(
          padding: EdgeInsets.zero,
          child: TableauTransverse(
            colonnes: const [
              (
                titre: TextesImportExport.colFichier,
                alignement: TextAlign.left,
              ),
              (titre: TextesImportExport.colDate, alignement: TextAlign.left),
              (titre: TextesImportExport.colTable, alignement: TextAlign.left),
              (
                titre: TextesImportExport.colAction,
                alignement: TextAlign.right,
              ),
            ],
            lignes: [
              for (final f in fichiers)
                [
                  Column(
                    key: Key('ie-sauvegarde-${f.nom}'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      celluleTexte(
                        f.nom,
                        couleur: Ardoise.c700,
                        poids: FontWeight.w600,
                        mono: true,
                      ),
                      celluleTexte(
                        '${_taille(f.taille)}${f.telechargee ? '' : ' · ${TextesImportExport.sauvegardeNonTelechargee}'}',
                        couleur: Ardoise.c400,
                        taille: TaillesContenu.t12,
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      celluleTexte(_jour(f.date)),
                      celluleTexte(
                        _heure(f.date),
                        couleur: Ardoise.c400,
                        taille: TaillesContenu.t12,
                      ),
                    ],
                  ),
                  celluleTexte(TextesImportExport.sauvegardeContenu),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (peutEcrire) ...[
                        BoutonTransverse(
                          cle: Key('ie-telecharger-${f.nom}'),
                          libelle: TextesImportExport.actionTelecharger,
                          fond: AppColors.navy,
                          trace: _traceTelecharger,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xxs,
                          ),
                          onTap: () => _telecharger(f.nom),
                        ),
                        const SizedBox(width: AppSpacing.unit),
                        Tooltip(
                          message: TextesImportExport.actionRetirer,
                          child: InkWell(
                            key: Key('ie-retirer-${f.nom}'),
                            onTap: () => _retirer(f),
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.xxs),
                              child: IconeTrace(
                                trace: _corbeille,
                                taille: MesuresTransverses.iconePetite,
                                couleur: Ardoise.c400,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
            ],
            vide: TextesImportExport.sauvegardesVide,
            cleVide: const Key('ie-sauvegardes-vide'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm), // mt-3
        Text(TextesImportExport.sauvegardesRetention, style: _aide),
      ],
    );
  }
}

/// La confirmation forte de « Retirer de la liste » pour une sauvegarde jamais
/// téléchargée (`Dialogue.confirmer`) : titre, message, détail, Annuler /
/// « Retirer quand même ». Rend `true` quand on retire.
class _ModaleRetraitSauvegarde extends StatelessWidget {
  const _ModaleRetraitSauvegarde();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('ie-modale-retrait'),
      backgroundColor: AppColors.neutre0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Largeurs.maxSm),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                TextesImportExport.retraitTitre,
                style: styleTransverse(
                  TaillesContenu.base,
                  poids: FontWeight.bold,
                  couleur: AppColors.navy,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                TextesImportExport.retraitMessage,
                style: styleTransverse(TaillesContenu.t13),
              ),
              const SizedBox(height: AppSpacing.unit),
              Text(
                TextesImportExport.retraitDetail,
                style: styleTransverse(
                  TaillesContenu.t13,
                  couleur: Ardoise.c500,
                ),
              ),
              const SizedBox(height: AppSpacing.mdPlus),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  BoutonTransverse(
                    cle: const Key('ie-retrait-annuler'),
                    libelle: TextesImportExport.annuler,
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                  BoutonTransverse(
                    cle: const Key('ie-retrait-confirmer'),
                    libelle: TextesImportExport.retraitConfirmer,
                    fond: AppColors.erreur,
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La modale « Exporter une table existante » : la liste des tables, puis
/// Annuler / « Télécharger ». Rend la table choisie, `null` : annulé.
class _ModaleExportTable extends StatefulWidget {
  const _ModaleExportTable({required this.tables});

  final List<String> tables;

  @override
  State<_ModaleExportTable> createState() => _ModaleExportTableState();
}

class _ModaleExportTableState extends State<_ModaleExportTable> {
  String? _table;
  String? _erreur;

  @override
  Widget build(BuildContext context) {
    final bordure = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: const BorderSide(color: Ardoise.c200),
    );
    return Dialog(
      key: const Key('ie-modale-export-table'),
      backgroundColor: AppColors.neutre0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Largeurs.maxMd),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                TextesImportExport.exportTableTitre,
                style: styleTransverse(
                  TaillesContenu.base,
                  poids: FontWeight.bold,
                  couleur: AppColors.navy,
                ),
              ),
              const SizedBox(height: AppSpacing.unit),
              Text(TextesImportExport.exportTableAide, style: _aide),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                key: const Key('ie-export-table-choix'),
                initialValue: _table,
                isExpanded: true,
                hint: Text(
                  TextesImportExport.exportTableInvite,
                  style: styleTransverse(
                    TaillesContenu.sm,
                    couleur: Ardoise.c400,
                  ),
                ),
                style: styleTransverse(TaillesContenu.sm),
                decoration: InputDecoration(
                  isDense: true,
                  border: bordure,
                  enabledBorder: bordure,
                ),
                items: [
                  for (final t in widget.tables)
                    DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: (t) => setState(() {
                  _table = t;
                  _erreur = null;
                }),
              ),
              if (_erreur != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  _erreur!,
                  style: styleTransverse(
                    TaillesContenu.t12,
                    couleur: PaletteMaitre.rouge600,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.mdPlus),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  BoutonStandard(
                    key: const Key('ie-export-table-annuler'),
                    libelle: TextesImportExport.annuler,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  BoutonStandard(
                    key: const Key('ie-export-table-telecharger'),
                    variante: VarianteBouton.primaire,
                    libelle: TextesImportExport.actionTelecharger,
                    onPressed: () {
                      if (_table == null) {
                        setState(
                          () => _erreur = TextesImportExport.exportTableChoisir,
                        );
                        return;
                      }
                      Navigator.of(context).pop(_table);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// L'onglet « Restaurer » — le registre DÉRIVÉ des unités d'hébergement et des
/// véhicules `hors_service` (`registre_archives.dart`), sa recherche, son filtre
/// et son seul geste, « Restaurer ». Aucune table d'archives, ici comme au web.
class _PanneauRestaurer extends ConsumerStatefulWidget {
  const _PanneauRestaurer({required this.peutEcrire});

  final bool peutEcrire;

  @override
  ConsumerState<_PanneauRestaurer> createState() => _PanneauRestaurerState();
}

class _PanneauRestaurerState extends ConsumerState<_PanneauRestaurer> {
  static const String _retour =
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M3 12a9 9 0 109-9 9 9 0 00-6.36 2.64L3 8"/><path stroke-linecap="round" stroke-linejoin="round" d="M3 3v5h5"/>';

  final _recherche = TextEditingController();
  FiltreArchives _filtre = FiltreArchives.restaurables;

  /// `@error('archives')` : le refus de la dernière restauration.
  String? _refus;

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  Future<void> _restaurer(EntreeArchive entree) async {
    setState(() => _refus = null);
    final messager = ScaffoldMessenger.of(context);
    try {
      final libelle = await ref.read(restaurerArchiveProvider)(
        entree.type,
        entree.id,
      );
      // Les écrans des deux modules relisent leur parc : l'élément y revient.
      rafraichirListes(ref);
      rechargerVehicules(ref);
      messager
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            key: const Key('ie-archive-restauree'),
            content: Text(MessagesArchives.restauree(libelle)),
          ),
        );
    } on RefusArchive catch (refus) {
      if (mounted) setState(() => _refus = refus.message);
    }
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _heure(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final bleu = styleTransverse(
      TaillesContenu.t13,
      couleur: PaletteMaitre.bleu900,
      interligne: AppLayout.interligneDetendu,
    );
    final registre = ref.watch(registreArchivesProvider);
    final entrees = registre.hasValue
        ? filtrerArchives(
            registre.requireValue,
            filtre: _filtre,
            recherche: _recherche.text,
          )
        : const <EntreeArchive>[];

    Widget cellule(String texte, {bool fort = false}) => Text(
      texte,
      style: fort
          ? styleTransverse(
              TaillesContenu.t15,
              poids: FontWeight.w600,
              couleur: Ardoise.c700,
            )
          : styleTransverse(TaillesContenu.t13, couleur: Ardoise.c600),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EncadreTransverse(
          fond: AppColors.badgeBleuFond,
          bordure: PaletteTransverse.bordureBleue,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const IconeTrace(
                trace: _retour,
                taille: MesuresTransverses.iconeModule,
                couleur: AppColors.info,
                epaisseur: MesuresTransverses.traitAppuye,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      TextesImportExport.restaurerTitre,
                      style: styleTransverse(
                        TaillesContenu.t15,
                        poids: FontWeight.bold,
                        couleur: PaletteMaitre.bleu900,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.unit),
                    Text(TextesImportExport.restaurerTexte, style: bleu),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.mdPlus),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('ie-recherche-archives'),
                controller: _recherche,
                onChanged: (_) => setState(() {}),
                style: styleTransverse(TaillesContenu.t15),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: TextesImportExport.rechercheArchives,
                  filled: true,
                  fillColor: AppColors.neutre0,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: const BorderSide(color: Ardoise.c200),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.unit,
              ),
              decoration: BoxDecoration(
                color: AppColors.neutre0,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: Ardoise.c200),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<FiltreArchives>(
                  key: const Key('ie-filtre-archives'),
                  value: _filtre,
                  style: styleTransverse(TaillesContenu.t15),
                  items: const [
                    DropdownMenuItem(
                      value: FiltreArchives.restaurables,
                      child: Text(TextesImportExport.filtreRestaurables),
                    ),
                    DropdownMenuItem(
                      value: FiltreArchives.toutes,
                      child: Text(TextesImportExport.filtreToutes),
                    ),
                    DropdownMenuItem(
                      value: FiltreArchives.restaurees,
                      child: Text(TextesImportExport.filtreRestaurees),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _filtre = v);
                  },
                ),
              ),
            ),
          ],
        ),
        if (_refus != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            _refus!,
            key: const Key('ie-archives-refus'),
            style: styleTransverse(
              TaillesContenu.t12,
              couleur: PaletteMaitre.rouge600,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        CarteTransverse(
          padding: EdgeInsets.zero,
          child: TableauTransverse(
            colonnes: const [
              (
                titre: TextesImportExport.colElement,
                alignement: TextAlign.left,
              ),
              (titre: TextesImportExport.colModule, alignement: TextAlign.left),
              (
                titre: TextesImportExport.colArchiveLe,
                alignement: TextAlign.left,
              ),
              (titre: TextesImportExport.colPar, alignement: TextAlign.left),
              (
                titre: TextesImportExport.colAction,
                alignement: TextAlign.right,
              ),
            ],
            lignes: [
              for (final e in entrees)
                [
                  Opacity(
                    key: Key('ie-archive-${e.type.code}-${e.id}'),
                    // `opacity-60` d'une ligne déjà restaurée.
                    opacity: e.restaure
                        ? MesuresArchives.opaciteLigneRestauree
                        : 1,
                    child: cellule(e.libelle, fort: true),
                  ),
                  cellule(e.type.libelleModule),
                  e.archiveLe == null
                      ? cellule(TextesImportExport.tiret)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            cellule(_date(e.archiveLe!)),
                            Text(
                              _heure(e.archiveLe!),
                              style: styleTransverse(
                                TaillesContenu.t12,
                                couleur: Ardoise.c400,
                              ),
                            ),
                          ],
                        ),
                  cellule(e.archivePar ?? TextesImportExport.tiret),
                  if (e.restaure)
                    Container(
                      key: Key('ie-archive-badge-${e.id}'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: AppSpacing.unit,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.badgeVertFond,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        TextesImportExport.badgeRestaure,
                        style: styleTransverse(
                          TaillesContenu.t12,
                          poids: FontWeight.bold,
                          couleur: AppColors.succes,
                        ),
                      ),
                    )
                  else if (widget.peutEcrire)
                    BoutonTransverse(
                      cle: Key('ie-archive-restaurer-${e.id}'),
                      libelle: TextesImportExport.actionRestaurer,
                      fond: AppColors.succes,
                      trace: _retour,
                      onTap: () => _restaurer(e),
                    )
                  else
                    const SizedBox.shrink(),
                ],
            ],
            vide: TextesImportExport.archivesVide,
            cleVide: const Key('ie-archives-vide'),
          ),
        ),
      ],
    );
  }
}

/// L'onglet « Réinitialiser » — les trois états de la vue : Production
/// (encadré rouge), VERROUILLÉ (bascule fermée : cadenas et renvoi aux
/// Paramètres), OUVERT (bandeau, les deux listes mesurées sur la base, le
/// bouton « Réinitialiser comme neuf » et sa modale).
class _PanneauSeeders extends ConsumerStatefulWidget {
  const _PanneauSeeders({required this.peutEcrire, required this.role});

  final bool peutEcrire;
  final String? role;

  @override
  ConsumerState<_PanneauSeeders> createState() => _PanneauSeedersState();
}

typedef _EtatSeeders = ({
  bool ouverte,
  List<String> effacables,
  List<String> preservees,
  // Le serveur a été réinitialisé (19/10/2026) : la remise à neuf de CE
  // poste s'ouvre, même en build production et bascule fermée.
  DateTime? serveurReinitialiseLe,
  // Le serveur annonce la phase d'essais en production.
  bool phaseEssais,
});

class _PanneauSeedersState extends ConsumerState<_PanneauSeeders> {
  static const String _cadenas =
      r'<rect x="3" y="11" width="18" height="11" rx="2"/><path stroke-linecap="round" d="M7 11V7a5 5 0 0110 0v4"/>';
  static const String _alerte =
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M12 9v4m0 4h.01M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/>';
  static const String _corbeille =
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M3 6h18M8 6V4a2 2 0 012-2h4a2 2 0 012 2v2m3 0v14a2 2 0 01-2 2H7a2 2 0 01-2-2V6h14z"/>';

  late Future<_EtatSeeders> _etat;

  ReinitialisationLocale get _moteur => ReinitialisationLocale(
    ref.read(baseLocaleProvider),
    sauvegardes: ref.read(sauvegardesPosteProvider),
  );

  @override
  void initState() {
    super.initState();
    _etat = _lire();
  }

  // La bascule et les listes sont relues à chaque ouverture de l'onglet et
  // après chaque réinitialisation, jamais gardées d'une visite à l'autre.
  Future<_EtatSeeders> _lire() async {
    final moteur = _moteur;
    final serveurReinitialiseLe = await moteur.reinitialisationServeur();
    return (
      ouverte: serveurReinitialiseLe != null || await moteur.estOuverte(),
      effacables: await moteur.tablesEffacables(),
      preservees: await moteur.tablesPreservees(),
      serveurReinitialiseLe: serveurReinitialiseLe,
      phaseEssais: await moteur.phaseEssaisServeur(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_EtatSeeders>(
      future: _etat,
      builder: (context, instantane) {
        final etat = instantane.data;
        final reinitialiseLe = etat?.serveurReinitialiseLe;
        final autorisee = _moteur.estAutorisee || reinitialiseLe != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (reinitialiseLe != null) ...[
              EncadreTransverse(
                key: const Key('ie-seeders-serveur-reinitialise'),
                fond: PaletteMaitre.rouge50,
                bordure: PaletteMaitre.rouge200,
                child: Text(
                  TextesReinitialisationServeur.constatee(reinitialiseLe),
                  style: styleTransverse(
                    TaillesContenu.t13,
                    poids: FontWeight.w600,
                    couleur: PaletteMaitre.rouge900,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.mdPlus),
            ],
            if (etat?.phaseEssais ?? false) ...[
              EncadreTransverse(
                key: const Key('ie-seeders-phase-essais'),
                fond: PaletteMaitre.ambre50,
                bordure: PaletteMaitre.ambre200,
                child: Text(
                  TextesImportExport.resetPhaseEssais,
                  style: styleTransverse(
                    TaillesContenu.t13,
                    couleur: PaletteMaitre.ambre900,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.mdPlus),
            ],
            if (!autorisee) ...[
              EncadreTransverse(
                key: const Key('ie-seeders-production'),
                fond: PaletteMaitre.rouge50,
                bordure: PaletteMaitre.rouge200,
                child: Text(
                  TextesImportExport.resetEnvironnementProduction,
                  style: styleTransverse(
                    TaillesContenu.t13,
                    couleur: PaletteMaitre.rouge900,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.mdPlus),
            ],
            // Pendant la lecture, l'état VERROUILLÉ : une fonction
            // destructrice n'apparaît pas par défaut d'information.
            if (etat == null || !etat.ouverte)
              _verrouille(context)
            else
              ..._ouvert(context, etat, autorisee),
          ],
        );
      },
    );
  }

  Widget _verrouille(BuildContext context) => CarteTransverse(
    key: const Key('ie-seeders-verrouille'),
    padding: const EdgeInsets.all(AppSpacing.xl),
    child: Column(
      children: [
        Container(
          width: MesuresTransverses.cadenasReinitialisation,
          height: MesuresTransverses.cadenasReinitialisation,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.badgeGrisFond,
            shape: BoxShape.circle,
          ),
          child: const IconeTrace(
            trace: _cadenas,
            taille: AppLayout.iconeTitrePage,
            couleur: AppColors.neutre400,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(TextesImportExport.seedersVerrouilleTitre, style: _titreCarte),
        const SizedBox(height: AppSpacing.xxs),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Largeurs.maxLg),
          child: Text(
            TextesImportExport.seedersVerrouilleTexte,
            textAlign: TextAlign.center,
            style: styleTransverse(TaillesContenu.t15, couleur: Ardoise.c500),
          ),
        ),
        const SizedBox(height: AppSpacing.xsPlus),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            Text(
              '${TextesImportExport.seedersVerrouilleOuvrirAvant} ',
              style: styleTransverse(TaillesContenu.t13, couleur: Ardoise.c400),
            ),
            InkWell(
              key: const Key('ie-seeders-ouvrir-parametres'),
              onTap: () => context.go('/parametres'),
              child: Text(
                TextesImportExport.seedersVerrouilleOuvrirLien,
                style: styleTransverse(
                  TaillesContenu.t13,
                  poids: FontWeight.w600,
                  couleur: Ardoise.c400,
                ).copyWith(decoration: TextDecoration.underline),
              ),
            ),
            Text(
              '.',
              style: styleTransverse(TaillesContenu.t13, couleur: Ardoise.c400),
            ),
          ],
        ),
      ],
    ),
  );

  List<Widget> _ouvert(
    BuildContext context,
    _EtatSeeders etat,
    bool autorisee,
  ) {
    Widget liste({
      required Key cle,
      required String titre,
      required String texte,
      required Color couleurTitre,
      required Color fond,
      required Color encre,
      required List<String> tables,
      String? vide,
    }) => CarteTransverse(
      key: cle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            titre,
            style: styleTransverse(
              TaillesContenu.sm,
              poids: FontWeight.bold,
              couleur: couleurTitre,
            ),
          ),
          const SizedBox(height: AppSpacing.unit),
          Text(texte, style: _aide),
          const SizedBox(height: AppSpacing.sm),
          if (tables.isEmpty && vide != null)
            Text(
              vide,
              style: styleTransverse(TaillesContenu.t13, couleur: Ardoise.c400),
            ),
          for (final t in tables)
            Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.unit),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: fond,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Text(
                t,
                style: styleTransverse(
                  TaillesContenu.t13,
                  couleur: encre,
                  police: AppTextStyles.policeMonospace,
                ),
              ),
            ),
        ],
      ),
    );

    final vide = liste(
      cle: const Key('ie-seeders-vide'),
      titre: TextesImportExport.seedersVideTitre,
      texte: TextesImportExport.seedersVideTexte,
      couleurTitre: AppColors.erreur,
      fond: AppColors.badgeRougeFond,
      encre: PaletteTransverse.texteRouge,
      tables: etat.effacables,
      vide: TextesImportExport.seedersRienAVider,
    );
    final conserve = liste(
      cle: const Key('ie-seeders-conserve'),
      titre: TextesImportExport.seedersConserveTitre,
      texte: TextesImportExport.seedersConserveTexte,
      couleurTitre: AppColors.succes,
      fond: AppColors.badgeVertFond,
      encre: PaletteTransverse.texteVert,
      tables: etat.preservees,
    );
    final large = MediaQuery.sizeOf(context).width >= AppBreakpoints.lg;

    return [
      EncadreTransverse(
        key: const Key('ie-seeders-bandeau'),
        fond: AppColors.badgeRougeFond,
        bordure: PaletteTransverse.bordureRouge,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const IconeTrace(
              trace: _alerte,
              taille: MesuresTransverses.iconeModule,
              couleur: AppColors.erreur,
              epaisseur: MesuresTransverses.traitAppuye,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    TextesImportExport.seedersBandeauTitre,
                    style: styleTransverse(
                      TaillesContenu.t15,
                      poids: FontWeight.bold,
                      couleur: PaletteTransverse.texteRouge,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.unit),
                  Text(
                    TextesImportExport.seedersBandeauTexte,
                    style: styleTransverse(
                      TaillesContenu.t13,
                      couleur: PaletteTransverse.texteRouge,
                      interligne: AppLayout.interligneDetendu,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.mdPlus),
      if (large)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: vide),
            const SizedBox(width: AppSpacing.mdPlus),
            Expanded(child: conserve),
          ],
        )
      else ...[
        vide,
        const SizedBox(height: AppSpacing.mdPlus),
        conserve,
      ],
      if (widget.peutEcrire &&
          autorisee &&
          ReinitialisationLocale.estPermisA(widget.role)) ...[
        const SizedBox(height: AppSpacing.mdPlus),
        BoutonTransverse(
          cle: const Key('ie-seeders-bouton'),
          libelle: TextesImportExport.seedersBouton,
          fond: AppColors.erreur,
          trace: _corbeille,
          taille: TaillesContenu.sm,
          pleineLargeur: true,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.mdPlus,
            vertical: AppSpacing.sm,
          ),
          onTap: () => _ouvrirModale(etat.effacables.length),
        ),
      ],
    ];
  }

  Future<void> _ouvrirModale(int nombre) async {
    final bilan = await showDialog<BilanReinitialisation>(
      context: context,
      builder: (_) => _ModaleReinitialisation(
        nombre: nombre,
        executer: () => _moteur.executer(role: widget.role),
      ),
    );
    if (!mounted || bilan == null) return;
    setState(() => _etat = _lire());
    direTransverse(
      context,
      TextesImportExport.seedersFaitSurCePoste(
        bilan.tablesVidees,
        bilan.lignesSupprimees,
        sauvegarde: bilan.sauvegarde,
      ),
      cle: const Key('ie-seeders-fait'),
    );
  }
}

/// La modale de la vue : titre, texte, saisie du mot « VIDER », Annuler /
/// « Vider définitivement » — inerte tant que le mot n'est pas tapé ; le mot
/// est REVÉRIFIÉ au clic, et le moteur relit bascule, rôle et environnement.
class _ModaleReinitialisation extends StatefulWidget {
  const _ModaleReinitialisation({required this.nombre, required this.executer});

  final int nombre;
  final Future<BilanReinitialisation> Function() executer;

  @override
  State<_ModaleReinitialisation> createState() =>
      _ModaleReinitialisationState();
}

class _ModaleReinitialisationState extends State<_ModaleReinitialisation> {
  final _saisie = TextEditingController();
  String? _erreur;
  bool _enCours = false;

  bool get _motTape =>
      _saisie.text.trim().toUpperCase() ==
      TextesImportExport.seedersPhraseConfirmation;

  @override
  void dispose() {
    _saisie.dispose();
    super.dispose();
  }

  Future<void> _confirmer() async {
    if (!_motTape) {
      setState(() => _erreur = TextesImportExport.seedersPhraseInvalide);
      return;
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final bilan = await widget.executer();
      if (mounted) Navigator.of(context).pop(bilan);
    } on ReinitialisationRefusee catch (refus) {
      if (mounted) {
        setState(() {
          _enCours = false;
          _erreur = refus.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final texte = styleTransverse(
      TaillesContenu.t15,
      couleur: Ardoise.c600,
      interligne: AppLayout.interligneDetendu,
    );
    return Dialog(
      key: const Key('ie-seeders-modale'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Largeurs.maxLg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                TextesImportExport.seedersModaleTitre,
                style: styleTransverse(
                  TaillesContenu.base,
                  poids: FontWeight.bold,
                  couleur: AppColors.erreur,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text:
                          '${TextesImportExport.seedersModaleTexteAvant(widget.nombre)} ',
                      style: texte.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const TextSpan(
                      text: '${TextesImportExport.seedersModaleTexte1}\n\n',
                    ),
                    const TextSpan(
                      text: '${TextesImportExport.seedersModaleTexte2} ',
                    ),
                    TextSpan(
                      text: TextesImportExport.seedersModaleTexte2Fort,
                      style: texte.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const TextSpan(
                      text: TextesImportExport.seedersModaleTexte2Fin,
                    ),
                  ],
                ),
                style: texte,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                '${TextesImportExport.seedersConfirmationAvant} '
                '${TextesImportExport.seedersPhraseConfirmation}',
                style: styleTransverse(
                  TaillesContenu.t13,
                  poids: FontWeight.w600,
                  couleur: Ardoise.c700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              TextField(
                key: const Key('ie-seeders-saisie'),
                controller: _saisie,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) => setState(() {}),
                style: styleTransverse(
                  TaillesContenu.sm,
                  police: AppTextStyles.policeMonospace,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: TextesImportExport.seedersPhraseConfirmation,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                TextesImportExport.seedersConfirmationAide,
                style: styleTransverse(
                  TaillesContenu.t12,
                  couleur: Ardoise.c400,
                ),
              ),
              if (_erreur != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _erreur!,
                  key: const Key('ie-seeders-erreur'),
                  style: styleTransverse(
                    TaillesContenu.t12,
                    couleur: PaletteMaitre.rouge600,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.mdPlus),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  BoutonTransverse(
                    cle: const Key('ie-seeders-annuler'),
                    libelle: TextesImportExport.annuler,
                    taille: TaillesContenu.sm,
                    couleurContour: Ardoise.c200,
                    couleurTexteContour: Ardoise.c600,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Opacity(
                    opacity: _motTape && !_enCours ? 1 : 0.5,
                    child: BoutonTransverse(
                      cle: const Key('ie-seeders-confirmer'),
                      libelle: TextesImportExport.seedersConfirmer,
                      fond: AppColors.erreur,
                      taille: TaillesContenu.sm,
                      onTap: () {
                        if (_motTape && !_enCours) _confirmer();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
