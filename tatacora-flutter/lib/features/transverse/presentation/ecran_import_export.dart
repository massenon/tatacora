// Vue Blade maîtresse (PA-183) : pwa/transverse/import-export.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/navigation/coquille_vue.dart';
import '../../../core/navigation/trace_svg.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/mesures_transverses.dart';
import '../../../shared_widgets/cadre_tirete.dart';
import '../data/reinitialisation_locale.dart';
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
/// - **Import** : aucun moteur d'import n'existe sur ce poste (le registre
///   `ReferentielsImport` et le contrôle de cohérence vivent au serveur). Les
///   trois cartes et la démarche sont rendues ; le sélecteur de module est
///   inactif et dit pourquoi ; « Télécharger le modèle », la zone de dépôt et
///   « Valider et contrôler le fichier » DISENT au clic qu'aucun import n'a
///   lieu (Article 3.3). L'historique rend l'état vide de la vue — vrai ici.
/// - **Sauvegardes** : l'application ne sauvegarde pas la base du poste. Les
///   indicateurs sans source affichent « — » (jamais « 0 », jamais
///   « Quotidien (02h00) », qui décrit le serveur) ; les deux boutons DISENT
///   qu'ils n'ont pas de geste ; les trois phrases de la vue qui décrivent le
///   serveur (rythme, liste vide, rétention) sont REMPLACÉES par la phrase
///   vraie (piège 13 : jamais une affirmation fausse sur ce que le poste fait).
/// - **Restaurer** : aucun registre d'archives sur ce poste ; un élément
///   archivé s'y réintègre depuis l'écran de son module. L'encadré de la vue
///   est rendu, suivi d'une ligne « Sur ce poste ».
/// - **Réinitialiser** : « Réinitialiser comme neuf » (demande du PO du
///   14/10/2026, lot E), réplique LOCALE du serveur
///   (`data/reinitialisation_locale.dart`) : refus en build production,
///   bascule `reinitialisation_seeders` de Paramètres, rôles d'administration,
///   saisie du mot « VIDER », une transaction. Les trois états de la vue
///   (production, verrouillé, ouvert) et sa modale sont rendus. Écart NOMMÉ :
///   la vue promet « une sauvegarde complète générée juste avant » ; le poste
///   n'en produit aucune, la phrase est remplacée par la vraie (piège 13).
///
/// Droit : la route de la vue exige PARAM en lecture (`module:PARAM,L`).
class EcranImportExport extends ConsumerStatefulWidget {
  const EcranImportExport({super.key});

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
      "Le modèle porte les colonnes exactes et une ligne d'exemple. Il est généré depuis la même déclaration que le contrôle : il ne peut pas s'en écarter. Ouvrez-le dans Excel, remplacez la ligne d'exemple par vos données, conservez la ligne d'en-tête, puis enregistrez en";
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
  static const String colElement = 'ÉLÉMENT';
  static const String colModule = 'MODULE';
  static const String colArchiveLe = 'ARCHIVÉ LE';
  static const String colPar = 'PAR';
  static const String seedersVerrouilleTitre = 'Réinitialisation désactivée';
  static const String seedersVerrouilleTexte =
      'Cette fonction vide les jeux de données de démonstration. Elle reste fermée par défaut : laissée ouverte sur une base d\'exploitation réelle, elle détruirait le travail de l\'entreprise.';
  static const String tiret = '—';

  /// AJOUTS et REMPLACEMENTS déclarés (D419).
  static const String sansImport =
      "Ce poste n'a aucun moteur d'import : aucun module ne s'y alimente par "
      "fichier, aucun modèle n'est produit et rien n'est importé.";
  static const String sansSauvegarde =
      "Ce poste ne génère ni n'exporte aucune sauvegarde de sa base : aucun "
      "fichier n'a été produit.";
  static const String rythmeSurCePoste =
      "Sur ce poste : aucune sauvegarde automatique n'a lieu, et aucune n'est "
      'conservée.';
  static const String sauvegardesVideSurCePoste =
      "Aucune sauvegarde : l'application n'en produit pas sur ce poste.";
  static const String restaurerSurCePoste =
      "Sur ce poste : aucun registre d'archives n'est tenu ici — un élément "
      "archivé se réintègre depuis l'écran de son module.";
  static const String archivesVideSurCePoste =
      "Aucun registre d'archives sur ce poste.";
  // « Réinitialiser comme neuf » (lot E, 14/10/2026) — les mots de la vue.
  static const String seedersVerrouilleOuvrirAvant =
      "Un administrateur peut l'ouvrir dans";
  static const String seedersVerrouilleOuvrirLien =
      'Paramètres › Activation & Sécurité';
  static const String seedersBandeauTitre =
      "Fonction ouverte — à refermer dès que l'exploitation réelle commence";
  static const String seedersVideTitre = 'Ce qui sera vidé';
  static const String seedersVideTexte =
      "Tout ce que l'exploitation produit : clients, employés et paie, fournisseurs, guides, réservations et séjours, ventes, factures, mouvements de stock, achats, dépenses, locations, écritures comptables, notifications, caches et files de tâches.";
  static const String seedersConserveTitre = 'Ce qui sera conservé';
  static const String seedersConserveTexte =
      'Comptes et droits, paramètres, journaux, chambres du parc, articles de stock (sans mouvements), fiche restaurant, carte du bar, véhicules, catalogue tourisme et plan comptable.';
  static const String seedersRienAVider =
      'Aucune donnée à vider — la base est déjà vierge.';
  static const String seedersBouton = 'Réinitialiser comme neuf';
  static const String seedersModaleTitre = 'Réinitialiser comme neuf ?';
  static String seedersModaleTexteAvant(int nombre) => '$nombre table(s)';
  static const String seedersModaleTexte1 =
      "vont être vidées : clients, employés, fournisseurs, guides, réservations, ventes, factures, stocks, écritures, paie, et tous les jeux de démonstration. Rien n'est semé à nouveau.";
  static const String seedersModaleTexte2 =
      "Les paramètres de l'entreprise, la matrice des droits, votre compte, le journal d'audit, les chambres, les articles, la fiche restaurant, la carte du bar, les véhicules et le catalogue tourisme sont";
  static const String seedersModaleTexte2Fort = 'conservés';
  static const String seedersConfirmationAvant = 'Pour confirmer, saisissez';
  static const String seedersPhraseConfirmation = 'VIDER';
  static const String seedersConfirmationAide =
      "Une saisie plutôt qu'un simple clic : c'est la seule barrière qui résiste à un double-clic distrait.";
  static const String seedersConfirmer = 'Vider définitivement';
  static const String annuler = 'Annuler';
  static const String seedersPhraseInvalide =
      'La phrase tapée ne correspond pas à $seedersPhraseConfirmation.';
  static const String resetEnvironnementProduction =
      "Cet écran s'exécute en Production : la réinitialisation est désactivée, quel que soit votre rôle — c'est l'environnement qui refuse, pas un droit qui manque.";

  /// REMPLACEMENTS déclarés (piège 13) — la vue annonce une sauvegarde
  /// complète générée avant chaque réinitialisation (bandeau et modale de
  /// l'onglet « seeders ») ; le poste n'en produit AUCUNE : la phrase vraie
  /// prend sa place, avec le maximum des mots de la vue.
  static const String seedersBandeauTexteSurCePoste =
      "Sur ce poste, aucune sauvegarde n'est générée avant la réinitialisation : "
      'rien ne permet de revenir en arrière si la bascule était restée ouverte par erreur.';
  static const String seedersModaleTexte2FinSurCePoste =
      ". Sur ce poste, aucune sauvegarde n'est générée juste avant.";
  static String seedersFaitSurCePoste(int tables, int lignes) =>
      '$tables table(s) vidée(s), $lignes ligne(s) supprimée(s). Les '
      'paramètres, les droits et les référentiels gardés sont intacts.';
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
          0 => _PanneauImporter(peutEcrire: peutEcrire),
          1 => _PanneauSauvegardes(
            peutEcrire: peutEcrire,
            nombreTables: nombreTables,
          ),
          2 => const _PanneauRestaurer(),
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

void _direSansImport(BuildContext context) => direTransverse(
  context,
  TextesImportExport.sansImport,
  cle: const Key('ie-sans-import'),
);

class _PanneauImporter extends StatelessWidget {
  const _PanneauImporter({required this.peutEcrire});

  final bool peutEcrire;

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.sizeOf(context).width >= AppBreakpoints.lg;
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
              Tooltip(
                message: TextesImportExport.sansImport,
                child: Container(
                  key: const Key('ie-module-import'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xsPlus,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.neutre0,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: Ardoise.c200),
                  ),
                  child: Text(
                    TextesImportExport.importerModuleInvite,
                    style: styleTransverse(
                      TaillesContenu.sm,
                      couleur: Ardoise.c400,
                    ),
                  ),
                ),
              ),
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
                    BoutonTransverse(
                      cle: const Key('ie-modele'),
                      libelle: TextesImportExport.importerModeleBouton,
                      fond: AppColors.gold,
                      trace: TracesCoquille.importExport,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.smPlus,
                        vertical: AppSpacing.xs,
                      ),
                      onTap: () => _direSansImport(context),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.unit),
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: '${TextesImportExport.importerModeleAide1} ',
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
              InkWell(
                key: const Key('ie-zone-depot'),
                onTap: () => _direSansImport(context),
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
                        TextesImportExport.importerDepotGlisser,
                        textAlign: TextAlign.center,
                        style: styleTransverse(
                          TaillesContenu.t15,
                          poids: FontWeight.w600,
                          couleur: Ardoise.c600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.demi),
                      Text(
                        TextesImportExport.importerDepotCliquer,
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
              if (peutEcrire) ...[
                const SizedBox(height: AppSpacing.md),
                BoutonTransverse(
                  cle: const Key('ie-valider'),
                  libelle: TextesImportExport.importerValider,
                  fond: AppColors.navy,
                  taille: TaillesContenu.sm,
                  pleineLargeur: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.mdPlus,
                    vertical: AppSpacing.xsPlus,
                  ),
                  onTap: () => _direSansImport(context),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    final droite = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Demarche(),
        const SizedBox(height: AppSpacing.mdPlus),
        CarteTransverse(
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
                child: Text(
                  TextesImportExport.historiqueTitre,
                  style: _titreCarte,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.mdPlus,
                  vertical: AppSpacing.xl,
                ),
                child: Text(
                  TextesImportExport.historiqueVide,
                  key: const Key('ie-historique-vide'),
                  textAlign: TextAlign.center,
                  style: styleTransverse(
                    TaillesContenu.t13,
                    couleur: Ardoise.c400,
                  ),
                ),
              ),
            ],
          ),
        ),
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

class _PanneauSauvegardes extends StatelessWidget {
  const _PanneauSauvegardes({
    required this.peutEcrire,
    required this.nombreTables,
  });

  final bool peutEcrire;
  final int nombreTables;

  @override
  Widget build(BuildContext context) {
    final largeur = MediaQuery.sizeOf(context).width;
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
    void dire() => direTransverse(
      context,
      TextesImportExport.sansSauvegarde,
      cle: const Key('ie-sans-sauvegarde'),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
            kpi(TextesImportExport.kpiSauvegardes, TextesImportExport.tiret),
            kpi(TextesImportExport.kpiDerniere, TextesImportExport.tiret),
            kpi(TextesImportExport.kpiRythme, TextesImportExport.tiret),
          ],
        ),
        const SizedBox(height: AppSpacing.mdPlus),
        Wrap(
          spacing: AppSpacing.xsPlus,
          runSpacing: AppSpacing.xsPlus,
          children: [
            if (peutEcrire)
              BoutonTransverse(
                cle: const Key('ie-generer-sauvegarde'),
                libelle: TextesImportExport.sauvegardesGenerer,
                fond: AppColors.navy,
                taille: TaillesContenu.sm,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.mdPlus,
                  vertical: AppSpacing.xsPlus,
                ),
                onTap: dire,
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
              onTap: dire,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: MesuresTransverses.texteRythmeSauvegardes,
          ),
          child: Text(TextesImportExport.rythmeSurCePoste, style: _aide),
        ),
        const SizedBox(height: AppSpacing.md),
        const CarteTransverse(
          padding: EdgeInsets.zero,
          child: TableauTransverse(
            colonnes: [
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
            lignes: [],
            vide: TextesImportExport.sauvegardesVideSurCePoste,
            cleVide: Key('ie-sauvegardes-vide'),
          ),
        ),
      ],
    );
  }
}

class _PanneauRestaurer extends StatelessWidget {
  const _PanneauRestaurer();

  static const String _retour =
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M3 12a9 9 0 109-9 9 9 0 00-6.36 2.64L3 8"/><path stroke-linecap="round" stroke-linejoin="round" d="M3 3v5h5"/>';

  @override
  Widget build(BuildContext context) {
    final bleu = styleTransverse(
      TaillesContenu.t13,
      couleur: PaletteMaitre.bleu900,
      interligne: AppLayout.interligneDetendu,
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
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      TextesImportExport.restaurerSurCePoste,
                      style: bleu.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.mdPlus),
        Tooltip(
          message: TextesImportExport.archivesVideSurCePoste,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('ie-recherche-archives'),
                  enabled: false,
                  style: styleTransverse(TaillesContenu.t15),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: TextesImportExport.rechercheArchives,
                    filled: true,
                    fillColor: AppColors.neutre0,
                    disabledBorder: OutlineInputBorder(
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
                  vertical: AppSpacing.xsPlus,
                ),
                decoration: BoxDecoration(
                  color: AppColors.neutre0,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: Ardoise.c200),
                ),
                child: Text(
                  TextesImportExport.filtreRestaurables,
                  style: styleTransverse(
                    TaillesContenu.t15,
                    couleur: Ardoise.c400,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const CarteTransverse(
          padding: EdgeInsets.zero,
          child: TableauTransverse(
            colonnes: [
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
            lignes: [],
            vide: TextesImportExport.archivesVideSurCePoste,
            cleVide: Key('ie-archives-vide'),
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
});

class _PanneauSeedersState extends ConsumerState<_PanneauSeeders> {
  static const String _cadenas =
      r'<rect x="3" y="11" width="18" height="11" rx="2"/><path stroke-linecap="round" d="M7 11V7a5 5 0 0110 0v4"/>';
  static const String _alerte =
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M12 9v4m0 4h.01M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/>';
  static const String _corbeille =
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M3 6h18M8 6V4a2 2 0 012-2h4a2 2 0 012 2v2m3 0v14a2 2 0 01-2 2H7a2 2 0 01-2-2V6h14z"/>';

  late Future<_EtatSeeders> _etat;

  ReinitialisationLocale get _moteur =>
      ReinitialisationLocale(ref.read(baseLocaleProvider));

  @override
  void initState() {
    super.initState();
    _etat = _lire();
  }

  // La bascule et les listes sont relues à chaque ouverture de l'onglet et
  // après chaque réinitialisation, jamais gardées d'une visite à l'autre.
  Future<_EtatSeeders> _lire() async {
    final moteur = _moteur;
    return (
      ouverte: await moteur.estOuverte(),
      effacables: await moteur.tablesEffacables(),
      preservees: await moteur.tablesPreservees(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final autorisee = _moteur.estAutorisee;
    return FutureBuilder<_EtatSeeders>(
      future: _etat,
      builder: (context, instantane) {
        final etat = instantane.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                    TextesImportExport.seedersBandeauTexteSurCePoste,
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
                      text: TextesImportExport.seedersModaleTexte2FinSurCePoste,
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
