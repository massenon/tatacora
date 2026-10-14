// Vue Blade maîtresse (PA-183) : pwa/comptabilite/hub.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/format/formats.dart';
import '../../../core/navigation/coquille_vue.dart';
import '../../../core/navigation/trace_svg.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/mesures_transverses.dart';
import '../../../shared_widgets/pied_pagination.dart';
import '../../transverse/presentation/widgets/briques_transverses.dart';
import '../domain/consultation_comptable.dart';
import '../domain/entities/comptabilite.dart';
import '../domain/montant_comptable.dart';
import 'providers_consultation_comptable.dart';

/// Le hub **Comptabilité — SYSCOHADA révisé** — lot D du plan du Product
/// Owner (14/10/2026), lecture du moteur M10 LOCAL (`MoteurComptable`,
/// D192–D204).
///
/// Structure de la vue, dans son ordre : en-tête (titre, sous-titre,
/// sélecteur d'exercice, décompte « N ligne(s) · M brouillon(s) ») ; bande de
/// six indicateurs ; DIX onglets cliquables ; barre de filtres (Journal,
/// Inclure les brouillons, Réinitialiser, Exporter, mention de consultation) ;
/// panneau de l'onglet ; onze tuiles du pilotage financier.
///
/// ## Ce qui est lu, et ce qui ne l'est pas (D417)
///
/// - **Journal** et **Balance générale** : CALCULÉS sur les écritures du poste,
///   réplique de la portée du serveur (`consultation_comptable.dart`) :
///   exercice, statuts retenus, journal (le journal seulement : la balance du
///   serveur ne le filtre pas), ordre et soldes exclusifs du serveur.
/// - **Les six indicateurs** (`IndicateursComptablesService`) : non calculés
///   sur ce poste — « — », et une ligne qui le dit (jamais un zéro).
///   L'alerte « Comptabilité déséquilibrée » de la vue en dépend : non rendue.
/// - **Passer écriture** : l'encadré des contrôles est rendu ; « + Nouvelle
///   écriture » DIT que la saisie manuelle n'est pas portée (le moteur ne
///   passe ici que les pièces des ventes, dépenses, règlements et
///   encaissements).
/// - **Grand livre, Compte de résultat, Bilan, Analytique, Immobilisations,
///   Plan comptable, Clôtures** : l'onglet est cliquable et DIT qu'il n'est pas
///   calculé sur ce poste — aucun chiffre plutôt qu'un chiffre faux.
/// - **Exporter** : la vue exporte le journal (PDF/Excel) ; le clic DIT
///   qu'aucun export comptable n'est produit ici.
/// - **Tuiles** : celles qui correspondent à un onglet l'ouvrent ; Flux de
///   trésorerie, Notes annexes et États financiers DISENT qu'ils ne sont pas
///   portés (ce sont des pages séparées de la vue).
///
/// Droit : la route de la vue exige M10 en lecture.
class EcranComptabilite extends ConsumerStatefulWidget {
  const EcranComptabilite({this.ongletInitial, super.key});

  /// L'onglet demandé par le lien (`?onglet=journal`) — celui de la vue par
  /// défaut sinon (`Hub::ONGLET_DEFAUT` = « saisie »).
  final String? ongletInitial;

  @override
  ConsumerState<EcranComptabilite> createState() => _EcranComptabiliteState();
}

/// Les textes de la vue (`pwa.comptabilite.*`, `comptabilite_pwa.*`, `Hub`).
abstract final class TextesComptabilite {
  static const String titre = 'Comptabilité — SYSCOHADA révisé';
  static const String sousTitreAvant =
      'Système Normal. Une écriture validée est ';
  static const String sousTitreFort = 'immuable';
  static const String sousTitreApres =
      ' : la seule correction est la contre-passation.';
  static const String exercice = 'Exercice';
  static const String exerciceChoisir = 'Choisir un exercice';
  static const String aucunExerciceTitre =
      "Aucun exercice comptable n'est sélectionné";
  static const String aucunExerciceDetail =
      "Tout état de comptabilité se lit dans le cadre d'un exercice : un état « toutes années confondues » n'aurait pas de sens comptable. Choisissez l'exercice à consulter.";
  static const String aucunExerciceOuvert =
      "Aucun exercice comptable n'a encore été ouvert. Cela se fait depuis l'application TATACORA.";
  static const String filtreJournal = 'Journal';
  static const String filtreTousJournaux = 'Tous les journaux';
  static const String filtreBrouillons = 'Inclure les brouillons';
  static const String statutToutes = 'Toutes';
  static const String statutValidee = 'Validées seules';
  static const String statutBrouillon = 'Brouillons seuls';
  static const String filtreReinitialiser = 'Réinitialiser';
  static const String exporter = 'Exporter';
  static const String lectureSeule =
      'Consultation — cet écran ne modifie rien.';
  static const String pilotageIntro =
      'Pilotage financier SYSCOHADA — plan comptable, journal, bilan, clôture et analytique.';
  static const String saisieIntroTitre = 'Passer une écriture comptable';
  static const String saisieIntroDetail =
      'Journal, date, libellé de pièce et lignes Compte / Libellé / Centre / Débit / Crédit. Contrôles appliqués à l’enregistrement : débit = crédit (une pièce déséquilibrée n’est jamais enregistrée), date dans un exercice ouvert, compte existant au plan, et centre analytique obligatoire sur les classes 6, 7 et 8.';
  static const String saisieAucunExercice = 'Aucun exercice ouvert.';
  static const String saisieAucunExerciceDetail =
      'Ouvrez un exercice depuis l’onglet Clôtures avant de saisir la moindre écriture.';
  static const String saisieBouton = 'Nouvelle écriture';
  static const String colNumeroPiece = 'N° pièce';
  static const String journalVide =
      'Aucune pièce ne correspond à ces critères.';
  static const String totaux = 'TOTAUX';
  static const String brouillon = 'Brouillon';
  static const String validee = 'Validée';
  static String lignes(int n) => '$n ligne(s)';
  static String brouillons(int n) => '$n brouillon(s)';
  static const String tiret = '—';

  /// AJOUTS déclarés (D417).
  static const String indicateursSurCePoste =
      'Sur ce poste : les six indicateurs ne sont pas calculés — seuls le '
      'journal et la balance générale sont lus.';
  static const String saisieNonPortee =
      "La saisie manuelle d'une écriture n'est pas portée sur ce poste : seules "
      'les pièces des ventes, dépenses, règlements et encaissements y sont '
      "passées. Rien n'a été enregistré.";
  static const String exportNonProduit =
      "Aucun export comptable n'est produit sur ce poste : rien n'a été "
      'exporté.';
  static String ongletNonCalcule(String libelle) =>
      "« $libelle » n'est pas calculé sur ce poste : seuls le journal et la "
      "balance générale y sont lus. Aucun chiffre n'est affiché plutôt qu'un "
      'chiffre faux.';
  static String tuileNonPortee(String titre) =>
      "« $titre » n'est pas porté sur ce poste : seuls le journal et la "
      'balance générale y sont lus.';
}

/// `Hub::ONGLETS`, dans son ordre et à ses mots.
const List<({String cle, String libelle})> ongletsComptabilite = [
  (cle: 'saisie', libelle: 'Passer écriture'),
  (cle: 'journal', libelle: 'Journal'),
  (cle: 'grandlivre', libelle: 'Grand livre'),
  (cle: 'balance', libelle: 'Balance générale'),
  (cle: 'resultat', libelle: 'Compte de résultat'),
  (cle: 'bilan', libelle: 'Bilan'),
  (cle: 'analytique', libelle: 'Analytique'),
  (cle: 'immo', libelle: 'Immobilisations'),
  (cle: 'plan', libelle: 'Plan comptable'),
  (cle: 'clotures', libelle: 'Clôtures'),
];

/// `Hub::TUILES` : titre, description et l'onglet de CE poste qui la porte
/// (`null` : page séparée de la vue, non portée).
const List<({String titre, String description, String? onglet})> _tuiles = [
  (
    titre: 'Plan Comptable',
    description: 'Comptes SYSCOHADA (Classes 1 à 7)',
    onglet: 'plan',
  ),
  (
    titre: 'Journal Comptable',
    description: 'Écritures Débit/Crédit, saisie manuelle',
    onglet: 'journal',
  ),
  (
    titre: "Bilan de l'Entreprise",
    description: 'Actif / Passif, équilibre comptable',
    onglet: 'bilan',
  ),
  (
    titre: 'Compte de Résultat',
    description: "Produits, charges et résultat net de l'exercice",
    onglet: 'resultat',
  ),
  (
    titre: 'Tableau des Flux de Trésorerie',
    description: 'TAFIRE — variation de trésorerie sur la période',
    onglet: null,
  ),
  (
    titre: 'Notes Annexes',
    description: "Compléments d'information au Bilan et au Compte de Résultat",
    onglet: null,
  ),
  (
    titre: 'Clôture Périodique',
    description: "Bascule d'exercice fiscal, report à nouveau",
    onglet: 'clotures',
  ),
  (
    titre: 'Comptabilité Analytique',
    description:
        'Marges réelles par filière (Hébergement, Restauration, Bar, Tourisme, Véhicules)',
    onglet: 'analytique',
  ),
  (
    titre: 'Grand Livre',
    description: 'Écritures par compte, solde progressif',
    onglet: 'grandlivre',
  ),
  (
    titre: 'Balance Générale',
    description: 'Soldes de tous les comptes',
    onglet: 'balance',
  ),
  (
    titre: 'États Financiers',
    description:
        'Vue consolidée — Bilan, Résultat, Flux, Notes Annexes en un export unique',
    onglet: null,
  ),
];

/// `MontantFcfa::formatOuTiret` : un zéro s'affiche « — » (« une colonne de
/// zéros masque les vrais montants »).
String _montantOuTiret(int centimes) =>
    centimes == 0 ? TextesComptabilite.tiret : _montant(centimes);

String _montant(int centimes) =>
    formaterMontantDecimal(chaineDepuisCentimes(centimes), suffixe: 'FCFA') ??
    TextesComptabilite.tiret;

class _EcranComptabiliteState extends ConsumerState<EcranComptabilite> {
  late String _onglet =
      ongletsComptabilite.any((o) => o.cle == widget.ongletInitial)
      ? widget.ongletInitial!
      : 'saisie';

  /// `null` : pas encore choisi — l'exercice ouvert le plus récent s'applique.
  String? _exerciceId;
  bool _exerciceChoisi = false;
  String? _journalId;
  FiltreStatutEcritures _statut = FiltreStatutEcritures.toutes;
  int _page = 1;
  final _defilement = ScrollController();

  @override
  void didUpdateWidget(covariant EcranComptabilite ancien) {
    super.didUpdateWidget(ancien);
    // Un lien vers un autre onglet alors que le hub est déjà affiché : l'état
    // survit à la navigation, l'onglet demandé doit donc être repris ici.
    final demande = widget.ongletInitial;
    if (demande != ancien.ongletInitial &&
        ongletsComptabilite.any((o) => o.cle == demande)) {
      _onglet = demande!;
      _page = 1;
    }
  }

  @override
  void dispose() {
    _defilement.dispose();
    super.dispose();
  }

  void _choisirOnglet(String cle) => setState(() {
    _onglet = cle;
    _page = 1;
  });

  @override
  Widget build(BuildContext context) {
    final droits = ref.watch(droitsProvider);
    if (!droits.peutLire(ModuleTatacora.m10Comptabilite)) {
      return const RefusDroitTransverse(message: LibellesCoquille.sansDroit);
    }
    final lu = ref.watch(donneesComptabiliteProvider);
    final donnees = lu.value;
    final exerciceId = _exerciceChoisi
        ? _exerciceId
        : donnees?.exerciceOuvert?.id;
    final exercice = donnees?.exercices
        .where((e) => e.id == exerciceId)
        .firstOrNull;

    return PageTransverse(
      largeurMax: MesuresTransverses.pageComptabilite,
      controleur: _defilement,
      enfants: [
        _EnTete(
          exercices: donnees?.exercices ?? const [],
          exerciceId: exerciceId,
          repartition: (donnees == null || exercice == null)
              ? null
              : repartitionStatuts(donnees.ecritures, exerciceId: exercice.id),
          onExercice: (id) => setState(() {
            _exerciceChoisi = true;
            _exerciceId = id;
            _page = 1;
          }),
        ),
        const _BandeIndicateurs(),
        const SizedBox(height: AppSpacing.mdPlus), // mb-5
        Wrap(
          spacing: AppSpacing.xxs, // gap-1.5
          runSpacing: AppSpacing.xxs,
          children: [
            for (final o in ongletsComptabilite)
              OngletTransverse(
                cle: Key('compta-onglet-${o.cle}'),
                libelle: o.libelle,
                actif: o.cle == _onglet,
                onChoix: () => _choisirOnglet(o.cle),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md), // mb-4
        _BarreFiltres(
          journaux: donnees?.journaux ?? const [],
          journalId: _journalId,
          statut: _statut,
          consultation: !const {'saisie', 'immo', 'clotures'}.contains(_onglet),
          onJournal: (id) => setState(() {
            _journalId = id;
            _page = 1;
          }),
          onStatut: (s) => setState(() {
            _statut = s;
            _page = 1;
          }),
          onReinitialiser: () => setState(() {
            _journalId = null;
            _statut = FiltreStatutEcritures.toutes;
            _page = 1;
          }),
        ),
        const SizedBox(height: AppSpacing.md),
        if (lu.hasError)
          Text(
            "Les écritures de ce poste n'ont pas pu être lues.",
            key: const Key('compta-lecture-impossible'),
            style: styleTransverse(
              TaillesContenu.t13,
              couleur: AppColors.erreur,
            ),
          )
        else if (donnees != null)
          _Panneau(
            onglet: _onglet,
            donnees: donnees,
            exercice: exercice,
            journalId: _journalId,
            statut: _statut,
            page: _page,
            onPage: (p) => setState(() => _page = p),
          ),
        const SizedBox(height: AppSpacing.xl), // mt-8
        Text(
          TextesComptabilite.pilotageIntro,
          style: styleTransverse(TaillesContenu.t15, couleur: Ardoise.c500),
        ),
        const SizedBox(height: AppSpacing.sm), // mb-3
        _Tuiles(
          onOnglet: (cle) {
            _choisirOnglet(cle);
            if (_defilement.hasClients) _defilement.jumpTo(0);
          },
        ),
      ],
    );
  }
}

/// `mb-5 flex flex-wrap items-start justify-between gap-3`.
class _EnTete extends StatelessWidget {
  const _EnTete({
    required this.exercices,
    required this.exerciceId,
    required this.repartition,
    required this.onExercice,
  });

  final List<ExerciceComptable> exercices;
  final String? exerciceId;
  final ({int validee, int brouillon})? repartition;
  final ValueChanged<String?> onExercice;

  @override
  Widget build(BuildContext context) {
    final petit = styleTransverse(TaillesContenu.t13);
    final cadre = BoxDecoration(
      color: AppColors.neutre0,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: Ardoise.c300),
    );
    final r = repartition;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.mdPlus),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.start,
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          EnTeteTransverse(
            trace: IconeComptabiliteHub.trace,
            titre: TextesComptabilite.titre,
            sousTitre: '',
            margeBas: 0,
            sousTitreRiche: TextSpan(
              children: [
                const TextSpan(text: TextesComptabilite.sousTitreAvant),
                TextSpan(
                  text: TextesComptabilite.sousTitreFort,
                  style: styleTransverse(
                    TaillesContenu.t15,
                    poids: FontWeight.bold,
                    couleur: Ardoise.c500,
                  ),
                ),
                const TextSpan(text: TextesComptabilite.sousTitreApres),
              ],
            ),
          ),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.smPlus,
                ),
                decoration: cadre,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    key: const Key('compta-exercice'),
                    value: exerciceId,
                    style: petit,
                    hint: Text(
                      TextesComptabilite.exerciceChoisir,
                      style: petit,
                    ),
                    onChanged: onExercice,
                    items: [
                      DropdownMenuItem<String?>(
                        child: Text(
                          TextesComptabilite.exerciceChoisir,
                          style: petit,
                        ),
                      ),
                      for (final e in exercices)
                        DropdownMenuItem<String?>(
                          value: e.id,
                          child: Text(
                            '${TextesComptabilite.exercice} ${e.annee}',
                            style: petit,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (r != null)
                Container(
                  key: const Key('compta-decompte'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.smPlus,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: cadre,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: TextesComptabilite.lignes(
                            r.validee + r.brouillon,
                          ),
                        ),
                        if (r.brouillon > 0) ...[
                          const TextSpan(text: ' · '),
                          TextSpan(
                            text: TextesComptabilite.brouillons(r.brouillon),
                            style: petit.copyWith(
                              color: PaletteMaitre.ambre700,
                            ),
                          ),
                        ],
                      ],
                    ),
                    style: petit,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Le tracé de l'icône du titre du hub (`hub.blade.php`, en-tête).
abstract final class IconeComptabiliteHub {
  static const String trace =
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M9 17V7m4 10V11m4 6V9M4 21h16a1 1 0 001-1V4a1 1 0 00-1-1H4a1 1 0 00-1 1v16a1 1 0 001 1z"/>';
}

/// La bande des six indicateurs (`grid grid-cols-2 lg:grid-cols-6 gap-3`),
/// libellés et mentions de liasse de la vue, valeurs « — » (voir l'en-tête).
class _BandeIndicateurs extends StatelessWidget {
  const _BandeIndicateurs();

  static const _cartes = [
    ("Chiffre d'affaires", 'XB — hors TVA'),
    ('Valeur ajoutée', 'XC'),
    ('Excédent brut', 'XD — EBE'),
    ('Résultat net', 'XI'),
    ('Trésorerie', 'Classe 5'),
    ('Total bilan', ''),
  ];

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.sizeOf(context).width >= AppBreakpoints.lg;
    final petit = styleTransverse(TaillesContenu.t11, couleur: Ardoise.c400);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GrilleTransverse(
          colonnes: large
              ? MesuresTransverses.colonnesKpiComptaLg
              : MesuresTransverses.colonnesKpiCompta,
          ecart: AppSpacing.sm,
          enfants: [
            for (final (libelle, detail) in _cartes)
              CarteTransverse(
                padding: const EdgeInsets.all(AppSpacing.smPlus),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      libelle.toUpperCase(),
                      style: petit.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing:
                            AppTextStyles.suiviLarge * TaillesContenu.t11,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.unit),
                    Text(
                      TextesComptabilite.tiret,
                      style: styleTransverse(
                        TaillesContenu.t17,
                        poids: FontWeight.bold,
                        couleur: AppColors.navy,
                      ),
                    ),
                    if (detail.isNotEmpty) Text(detail, style: petit),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          TextesComptabilite.indicateursSurCePoste,
          key: const Key('compta-indicateurs-sur-ce-poste'),
          style: styleTransverse(TaillesContenu.t12, couleur: Ardoise.c400),
        ),
      ],
    );
  }
}

/// `bg-white rounded-xl border border-slate-200 p-3.5 mb-4` : Journal,
/// Inclure les brouillons, Réinitialiser, Exporter, mention de consultation.
class _BarreFiltres extends StatelessWidget {
  const _BarreFiltres({
    required this.journaux,
    required this.journalId,
    required this.statut,
    required this.consultation,
    required this.onJournal,
    required this.onStatut,
    required this.onReinitialiser,
  });

  final List<JournalComptable> journaux;
  final String? journalId;
  final FiltreStatutEcritures statut;
  final bool consultation;
  final ValueChanged<String?> onJournal;
  final ValueChanged<FiltreStatutEcritures> onStatut;
  final VoidCallback onReinitialiser;

  @override
  Widget build(BuildContext context) {
    final etiquette = styleTransverse(
      TaillesContenu.t12,
      couleur: Ardoise.c500,
    );
    final valeur = styleTransverse(TaillesContenu.t13);
    Widget cadre(Widget enfant) => Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Ardoise.c300),
      ),
      child: DropdownButtonHideUnderline(child: enfant),
    );
    final bouton = EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    );
    return CarteTransverse(
      padding: const EdgeInsets.all(AppSpacing.smPlus),
      child: Wrap(
        spacing: AppSpacing.xsPlus,
        runSpacing: AppSpacing.xsPlus,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(TextesComptabilite.filtreJournal, style: etiquette),
          cadre(
            DropdownButton<String?>(
              key: const Key('compta-filtre-journal'),
              value: journalId,
              style: valeur,
              onChanged: onJournal,
              items: [
                DropdownMenuItem<String?>(
                  child: Text(
                    TextesComptabilite.filtreTousJournaux,
                    style: valeur,
                  ),
                ),
                for (final j in journaux)
                  DropdownMenuItem<String?>(
                    value: j.id,
                    child: Text('${j.code} — ${j.libelle}', style: valeur),
                  ),
              ],
            ),
          ),
          Text(TextesComptabilite.filtreBrouillons, style: etiquette),
          cadre(
            DropdownButton<FiltreStatutEcritures>(
              key: const Key('compta-filtre-statut'),
              value: statut,
              style: valeur,
              onChanged: (s) => s == null ? null : onStatut(s),
              items: [
                for (final (s, libelle) in const [
                  (
                    FiltreStatutEcritures.toutes,
                    TextesComptabilite.statutToutes,
                  ),
                  (
                    FiltreStatutEcritures.validee,
                    TextesComptabilite.statutValidee,
                  ),
                  (
                    FiltreStatutEcritures.brouillon,
                    TextesComptabilite.statutBrouillon,
                  ),
                ])
                  DropdownMenuItem(
                    value: s,
                    child: Text(libelle, style: valeur),
                  ),
              ],
            ),
          ),
          BoutonTransverse(
            cle: const Key('compta-reinitialiser'),
            libelle: TextesComptabilite.filtreReinitialiser,
            taille: TaillesContenu.t12,
            padding: bouton,
            onTap: onReinitialiser,
          ),
          BoutonTransverse(
            cle: const Key('compta-exporter'),
            libelle: TextesComptabilite.exporter,
            taille: TaillesContenu.t12,
            padding: bouton,
            onTap: () => direTransverse(
              context,
              TextesComptabilite.exportNonProduit,
              cle: const Key('compta-export-non-produit'),
            ),
          ),
          if (consultation)
            Text(
              TextesComptabilite.lectureSeule,
              style: styleTransverse(TaillesContenu.t12, couleur: Ardoise.c400),
            ),
        ],
      ),
    );
  }
}

/// Le panneau de l'onglet actif.
class _Panneau extends StatelessWidget {
  const _Panneau({
    required this.onglet,
    required this.donnees,
    required this.exercice,
    required this.journalId,
    required this.statut,
    required this.page,
    required this.onPage,
  });

  final String onglet;
  final DonneesComptabilite donnees;
  final ExerciceComptable? exercice;
  final String? journalId;
  final FiltreStatutEcritures statut;
  final int page;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    if (onglet == 'saisie') return _Saisie(exercice: exercice);
    final ex = exercice;
    if (ex == null) return _AucunExercice(vide: donnees.exercices.isEmpty);
    switch (onglet) {
      case 'journal':
        return _Journal(
          lignes: porteeEcritures(
            donnees.ecritures,
            exerciceId: ex.id,
            statut: statut,
            journalId: journalId,
          ),
          donnees: donnees,
          page: page,
          onPage: onPage,
        );
      case 'balance':
        return _Balance(
          lignes: balanceGenerale(
            porteeEcritures(
              donnees.ecritures,
              exerciceId: ex.id,
              statut: statut,
            ),
            donnees.comptes,
          ),
        );
      default:
        final libelle = ongletsComptabilite
            .firstWhere((o) => o.cle == onglet)
            .libelle;
        return CarteTransverse(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacingLarge.p14,
            horizontal: AppSpacing.mdPlus,
          ),
          child: Text(
            TextesComptabilite.ongletNonCalcule(libelle),
            key: Key('compta-non-calcule-$onglet'),
            textAlign: TextAlign.center,
            style: styleTransverse(TaillesContenu.t13, couleur: Ardoise.c400),
          ),
        );
    }
  }
}

/// L'état « aucun exercice choisi » de la vue — deux messages distincts.
class _AucunExercice extends StatelessWidget {
  const _AucunExercice({required this.vide});

  final bool vide;

  @override
  Widget build(BuildContext context) => CarteTransverse(
    padding: const EdgeInsets.symmetric(
      vertical: AppSpacingLarge.p14,
      horizontal: AppSpacing.mdPlus,
    ),
    child: Column(
      children: [
        Text(
          TextesComptabilite.aucunExerciceTitre,
          textAlign: TextAlign.center,
          style: styleTransverse(
            TaillesContenu.t15,
            poids: FontWeight.w600,
            couleur: AppColors.navy,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: MesuresTransverses.texteAucunExercice,
          ),
          child: Text(
            vide
                ? TextesComptabilite.aucunExerciceOuvert
                : TextesComptabilite.aucunExerciceDetail,
            key: const Key('compta-aucun-exercice'),
            textAlign: TextAlign.center,
            style: styleTransverse(TaillesContenu.t13, couleur: Ardoise.c500),
          ),
        ),
      ],
    ),
  );
}

/// L'onglet « Passer écriture » : l'encadré gris des contrôles, puis
/// l'encadré rouge sans exercice ouvert, ou la carte du bouton.
class _Saisie extends StatelessWidget {
  const _Saisie({required this.exercice});

  final ExerciceComptable? exercice;

  @override
  Widget build(BuildContext context) {
    final ouvert = exercice?.statut == StatutExercice.ouvert;
    final gris = styleTransverse(TaillesContenu.t13, couleur: Ardoise.c700);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EncadreTransverse(
          fond: Ardoise.c50,
          bordure: Ardoise.c200,
          padding: const EdgeInsets.all(AppSpacing.smPlus),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${TextesComptabilite.saisieIntroTitre} ',
                  style: gris.copyWith(fontWeight: FontWeight.bold),
                ),
                const TextSpan(text: TextesComptabilite.saisieIntroDetail),
              ],
            ),
            style: gris,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (!ouvert)
          EncadreTransverse(
            fond: PaletteMaitre.rouge50,
            bordure: PaletteMaitre.rouge200,
            padding: const EdgeInsets.all(AppSpacing.smPlus),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${TextesComptabilite.saisieAucunExercice} ',
                    style: styleTransverse(
                      TaillesContenu.t13,
                      poids: FontWeight.bold,
                      couleur: PaletteMaitre.rouge900,
                    ),
                  ),
                  const TextSpan(
                    text: TextesComptabilite.saisieAucunExerciceDetail,
                  ),
                ],
              ),
              style: styleTransverse(
                TaillesContenu.t13,
                couleur: PaletteMaitre.rouge900,
              ),
            ),
          )
        else
          CarteTransverse(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    TextesComptabilite.saisieIntroDetail,
                    style: styleTransverse(
                      TaillesContenu.t13,
                      couleur: Ardoise.c500,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                BoutonTransverse(
                  cle: const Key('compta-nouvelle-ecriture'),
                  libelle: '+ ${TextesComptabilite.saisieBouton}',
                  fond: AppColors.navy,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xsPlus,
                  ),
                  onTap: () => direTransverse(
                    context,
                    TextesComptabilite.saisieNonPortee,
                    cle: const Key('compta-saisie-non-portee'),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Une pastille de statut — `text-[10px] px-1.5 py-0.5 rounded`.
Widget _pastilleStatut(StatutEcriture s) {
  final brouillon = s == StatutEcriture.brouillon;
  return Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.xxs,
      vertical: AppSpacing.demi,
    ),
    decoration: BoxDecoration(
      color: brouillon ? Ardoise.c100 : PaletteMaitre.emeraude50,
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
    child: Text(
      brouillon ? TextesComptabilite.brouillon : TextesComptabilite.validee,
      style: styleTransverse(
        TaillesContenu.t10,
        couleur: brouillon ? Ardoise.c600 : PaletteMaitre.emeraude700,
      ),
    ),
  );
}

/// L'onglet « Journal » : « N ligne(s) », huit colonnes, TOTAUX, paginé.
class _Journal extends StatelessWidget {
  const _Journal({
    required this.lignes,
    required this.donnees,
    required this.page,
    required this.onPage,
  });

  final List<EcritureComptable> lignes;
  final DonneesComptabilite donnees;
  final int page;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final centres = {for (final c in donnees.centres) c.id: c};
    final tranche = TranchePage.de(
      total: lignes.length,
      page: page,
      parPage: MesuresTransverses.lignesParPage,
    );
    final totalDebit = lignes.fold<int>(0, (s, e) => s + e.debitCentimes);
    final totalCredit = lignes.fold<int>(0, (s, e) => s + e.creditCentimes);
    final blanc = styleTransverse(
      TaillesContenu.t13,
      poids: FontWeight.bold,
      couleur: AppColors.neutre0,
    );

    return CarteTransverse(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Ardoise.c200)),
            ),
            child: Text(
              TextesComptabilite.lignes(lignes.length),
              key: const Key('compta-journal-lignes'),
              style: styleTransverse(
                TaillesContenu.t14,
                poids: FontWeight.bold,
                couleur: AppColors.navy,
              ),
            ),
          ),
          TableauTransverse(
            largeurs: const {
              3: MesuresTransverses.colonneLibelleCompta,
              4: MesuresTransverses.colonneLibelleCompta,
            },
            colonnes: const [
              (
                titre: TextesComptabilite.colNumeroPiece,
                alignement: TextAlign.left,
              ),
              (titre: 'Date', alignement: TextAlign.left),
              (titre: 'Compte', alignement: TextAlign.left),
              (titre: 'Intitulé', alignement: TextAlign.left),
              (titre: 'Libellé / centre', alignement: TextAlign.left),
              (titre: 'Débit', alignement: TextAlign.right),
              (titre: 'Crédit', alignement: TextAlign.right),
              (titre: 'Statut', alignement: TextAlign.right),
            ],
            vide: TextesComptabilite.journalVide,
            cleVide: const Key('compta-journal-vide'),
            lignes: [
              for (final e in tranche.decouper(lignes))
                [
                  celluleTexte(
                    e.numeroPiece ?? TextesComptabilite.tiret,
                    mono: true,
                    taille: TaillesContenu.t12,
                  ),
                  celluleTexte(_date(e.dateEcriture)),
                  celluleTexte(
                    donnees.comptes[e.compteId]?.numero ??
                        TextesComptabilite.tiret,
                    mono: true,
                    taille: TaillesContenu.t12,
                  ),
                  celluleTexte(donnees.comptes[e.compteId]?.libelle ?? ''),
                  celluleTexte(
                    centres[e.centreId] == null
                        ? e.libelle
                        : '${e.libelle} · ${centres[e.centreId]!.libelle}',
                    couleur: Ardoise.c400,
                    taille: TaillesContenu.t12,
                  ),
                  celluleTexte(
                    _montantOuTiret(e.debitCentimes),
                    alignement: TextAlign.right,
                  ),
                  celluleTexte(
                    _montantOuTiret(e.creditCentimes),
                    alignement: TextAlign.right,
                  ),
                  _pastilleStatut(e.statut),
                ],
            ],
            pied: [
              Text(TextesComptabilite.totaux, style: blanc),
              const SizedBox.shrink(),
              const SizedBox.shrink(),
              const SizedBox.shrink(),
              const SizedBox.shrink(),
              Text(_montant(totalDebit), style: blanc),
              Text(_montant(totalCredit), style: blanc),
              const SizedBox.shrink(),
            ],
          ),
          PiedPagination(
            tranche: tranche,
            onPage: onPage,
            prefixeCle: 'compta-journal',
          ),
        ],
      ),
    );
  }

  /// `d/m/Y` — la date comptable `AAAA-MM-JJ`, sans fuseau.
  static String _date(String iso) {
    final p = iso.split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : iso;
  }
}

/// L'onglet « Balance générale » : six colonnes et les totaux.
class _Balance extends StatelessWidget {
  const _Balance({required this.lignes});

  final List<LigneBalance> lignes;

  @override
  Widget build(BuildContext context) {
    int somme(int Function(LigneBalance) f) =>
        lignes.fold<int>(0, (s, l) => s + f(l));
    final blanc = styleTransverse(
      TaillesContenu.t13,
      poids: FontWeight.bold,
      couleur: AppColors.neutre0,
    );
    return CarteTransverse(
      padding: EdgeInsets.zero,
      child: TableauTransverse(
        largeurs: const {1: MesuresTransverses.colonneLibelleCompta},
        colonnes: const [
          (titre: 'Compte', alignement: TextAlign.left),
          (titre: 'Intitulé', alignement: TextAlign.left),
          (titre: 'Mouvements débit', alignement: TextAlign.right),
          (titre: 'Mouvements crédit', alignement: TextAlign.right),
          (titre: 'Solde débiteur', alignement: TextAlign.right),
          (titre: 'Solde créditeur', alignement: TextAlign.right),
        ],
        vide: TextesComptabilite.journalVide,
        cleVide: const Key('compta-balance-vide'),
        lignes: [
          for (final l in lignes)
            [
              celluleTexte(l.numero, mono: true, taille: TaillesContenu.t12),
              celluleTexte(l.libelle),
              celluleTexte(
                _montantOuTiret(l.debit),
                alignement: TextAlign.right,
              ),
              celluleTexte(
                _montantOuTiret(l.credit),
                alignement: TextAlign.right,
              ),
              celluleTexte(
                _montantOuTiret(l.soldeDebiteur),
                alignement: TextAlign.right,
              ),
              celluleTexte(
                _montantOuTiret(l.soldeCrediteur),
                alignement: TextAlign.right,
              ),
            ],
        ],
        pied: [
          Text(TextesComptabilite.totaux, style: blanc),
          const SizedBox.shrink(),
          Text(_montant(somme((l) => l.debit)), style: blanc),
          Text(_montant(somme((l) => l.credit)), style: blanc),
          Text(_montant(somme((l) => l.soldeDebiteur)), style: blanc),
          Text(_montant(somme((l) => l.soldeCrediteur)), style: blanc),
        ],
      ),
    );
  }
}

/// Les onze tuiles (`grid grid-cols-1 lg:grid-cols-2 gap-4`).
class _Tuiles extends StatelessWidget {
  const _Tuiles({required this.onOnglet});

  final ValueChanged<String> onOnglet;

  static const String _chevron =
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M9 18l6-6-6-6"/>';

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.sizeOf(context).width >= AppBreakpoints.lg;
    return GrilleTransverse(
      colonnes: large ? MesuresTransverses.colonnesTuilesCompta : 1,
      ecart: AppSpacing.md,
      enfants: [
        for (final (i, t) in _tuiles.indexed)
          InkWell(
            key: Key('compta-tuile-$i'),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: () => t.onglet == null
                ? direTransverse(
                    context,
                    TextesComptabilite.tuileNonPortee(t.titre),
                  )
                : onOnglet(t.onglet!),
            child: CarteTransverse(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: MesuresTransverses.avatarRole,
                    height: MesuresTransverses.avatarRole,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.navy.withValues(
                        alpha: PaletteTransverse.fondPastilleTuile,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: const IconeTrace(
                      trace: _chevron,
                      taille: MesuresTransverses.iconeModule,
                      couleur: AppColors.navy,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.titre,
                          style: styleTransverse(
                            TaillesContenu.t15,
                            poids: FontWeight.bold,
                            couleur: Ardoise.c800,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.unit),
                        Text(
                          t.description,
                          style: styleTransverse(
                            TaillesContenu.t13,
                            couleur: Ardoise.c500,
                            interligne: AppLayout.interligneDetendu,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const IconeTrace(
                    trace: _chevron,
                    taille: MesuresTransverses.iconeModule,
                    couleur: AppColors.neutre400,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
