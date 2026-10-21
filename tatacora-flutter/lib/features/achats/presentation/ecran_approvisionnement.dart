// Vue Blade maîtresse (PA-183) : pwa/achats/approvisionnement.blade.php
import '../../../core/impression/visas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared_widgets/bouton_standard.dart';
import '../../../shared_widgets/modale_export.dart';
import '../../caisse/domain/montant_caisse.dart' show formaterCentimesEnFcfa;
import '../domain/messages_reglement.dart';
import '../impression/etat_liste_achats.dart';
import 'providers_achats.dart';
import 'widgets/bandeaux_appro.dart';
import 'widgets/barre_outils_achats.dart';
import 'widgets/coquille_achats.dart';
import 'widgets/vue_besoins.dart';
import 'widgets/vue_commandes.dart';
import 'widgets/vue_dettes.dart';
import 'widgets/vue_receptions.dart';

/// L'écran **Approvisionnement** — la vue `achats/approvisionnement`.
///
/// Le cycle complet : besoin détecté (seuil) → commande → réception, qui génère
/// l'entrée de stock (sans la valoriser : elle ne porte aucun coût, comme au
/// serveur — D132) → règlement → dette résiduelle.
///
/// ## La page de la vue, dans l'ordre de la vue (Phase 2, 08/10/2026)
///
/// En-tête (titre, sous-titre, « Exporter », « Commander la sélection »), les
/// cinq cartes, la barre des quatre onglets, la recherche de la page, puis la
/// section de l'onglet. La page défile d'un bloc (`p-8`, `max-w-[1440px]`).
///
/// ## Source LOCALE depuis le 09/10/2026
///
/// Commandes, réceptions et fournisseurs sont lus et écrits sur ce poste
/// (`AchatsDao`, schéma v13) ; la réception génère l'entrée de stock dans la
/// même transaction. Le règlement fournisseur (`ReglementsFournisseurDao`,
/// schéma v20, 12/10/2026) écrit son règlement ET sa pièce comptable dans la
/// leur. Rien n'est répliqué : aucun écran de M7 n'annonce
/// « en attente de synchronisation » — ce serait l'indicateur qui affirme un
/// état qu'il n'a pas vérifié (PA-59/60/61). Les écrans disent « enregistré
/// sur ce poste ».
///
/// ## Quatre onglets, tous chiffrés
///
/// « Dettes fournisseurs » est chiffré depuis le règlement fournisseur (D66,
/// 12/10/2026) : voir `VueDettes`. Le motif d'absence qui l'accompagnait
/// (« décision du Product Owner en attente ») est retiré avec ce qu'il
/// justifiait.
///
/// ## Cinq cartes, cinq servies
///
/// « Fournisseurs à payer » et « Total dû » se lisent des commandes de la liste
/// filtrée et de leurs règlements actifs (`composerIndicateursDettes`). Sans le
/// droit de lecture M7 la liste n'est pas obtenue et les deux cartes rendent
/// « — » : un indicateur dont la donnée n'a pas été obtenue ne dit jamais zéro.
///
/// ## Ce que la page ne fait pas encore, DIT
///
/// - La **recherche de page** et l'**en-tête « Exporter »** pilotent l'onglet
///   Besoins. Les trois autres onglets gardent leur barre d'outils interne
///   (recherche, filtre, export Excel/PDF) : leur rapprochement avec la vue est
///   le lot suivant de cet écran. « Exporter » n'est donc rendu que sur
///   Besoins, là où il agit — ailleurs il doublerait un export déjà présent.
class EcranApprovisionnement extends ConsumerStatefulWidget {
  const EcranApprovisionnement({super.key});

  @override
  ConsumerState<EcranApprovisionnement> createState() =>
      _EcranApprovisionnementState();
}

class _EcranApprovisionnementState
    extends ConsumerState<EcranApprovisionnement> {
  int _onglet = 0;
  String _terme = '';
  final _besoins = GlobalKey<EtatVueBesoins>();

  /// Les quatre onglets de la vue, dans son ordre et à ses libellés.
  static const _onglets = [
    (cle: 'besoins', libelle: 'Besoins'),
    (cle: 'commandes', libelle: 'Commandes'),
    (cle: 'receptions', libelle: 'Réceptions'),
    (cle: 'dettes', libelle: 'Dettes fournisseurs'),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl), // lg:p-8
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppLayout.maxContentWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _EnTete(
                avecActions: _onglet == 0,
                onExporter: () => _exporter(context),
                onCommander: () => _besoins.currentState?.commander(),
              ),
              // Les deux bandeaux de la vue (succès, erreur `selection`), entre
              // l'en-tête et les cartes (l.88-97).
              const BandeauxAppro(),
              const _BandeIndicateurs(),
              _BarreOnglets(
                actif: _onglet,
                onglets: [for (final o in _onglets) o.libelle],
                onChoix: (i) {
                  // Le bandeau de la vue disparaît à la requête suivante.
                  ref.read(bandeauApproProvider.notifier).effacer();
                  setState(() => _onglet = i);
                },
              ),
              if (_onglet == 0) ...[
                _Recherche(onChange: (v) => setState(() => _terme = v)),
                VueBesoins(key: _besoins, terme: _terme),
              ] else
                switch (_onglet) {
                  1 => const VueCommandes(visas: Visas.approvisionnement),
                  2 => const VueReceptions(),
                  _ => const VueDettes(),
                },
            ],
          ),
        ),
      ),
    );
  }

  /// « Exporter » de l'en-tête : le format se choisit dans la modale d'export
  /// PARTAGÉE (PO, 14/10/2026 — l'ancien dialogue « Excel (CSV) » / « PDF »
  /// est retiré), comme dans la vue (un seul bouton, dérogation du Product
  /// Owner du 01/09/2026).
  Future<void> _exporter(BuildContext context) async {
    final liste = _besoins.currentState?.construireListe();
    if (liste == null || liste.estVide) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          key: Key('export-refuse'),
          content: Text(messageExportVide),
        ),
      );
      return;
    }

    final format = await choisirFormatExport(
      context,
      // `achats_pwa.export.titre_appro` : la vue donne UN titre à la page, quel
      // que soit l'onglet (le tableau exporté, lui, se nomme dans le fichier).
      titre: 'Exporter — Approvisionnement',
      sousTitre: 'Le fichier porte sur ce qui est affiché, filtre compris.',
    );
    if (format == null || !context.mounted) return;
    await enregistrerListeAchats(context, ref, liste, format);
  }
}

TextStyle _t(
  double taille, {
  FontWeight? poids,
  Color? couleur,
  double? espacement,
}) => TextStyle(
  fontFamily: AppTextStyles.police,
  fontSize: taille,
  fontWeight: poids,
  color: couleur,
  height: AppLayout.interligneContenu,
  letterSpacing: espacement,
);

/// L'en-tête : `mb-5 flex flex-wrap items-start justify-between gap-3`.
class _EnTete extends StatelessWidget {
  const _EnTete({
    required this.avecActions,
    required this.onExporter,
    required this.onCommander,
  });

  final bool avecActions;
  final VoidCallback onExporter;
  final VoidCallback onCommander;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.mdPlus), // mb-5
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.shopping_bag_outlined,
                    size: AppLayout.iconeTitrePage,
                    color: AppColors.navy,
                  ),
                  const SizedBox(width: AppSpacing.xsPlus), // gap-2.5
                  Text(
                    'Approvisionnement',
                    style: _t(
                      TaillesContenu.lg,
                      poids: FontWeight.bold,
                      couleur: AppColors.navy,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs), // mt-1.5
              // Le sous-titre de la vue, au mot — il porte la règle qui
              // commande tout l'écran, et son <strong> final.
              Text.rich(
                TextSpan(
                  style: _t(TaillesContenu.t15, couleur: AppColors.neutre500),
                  children: const [
                    TextSpan(
                      text:
                          "Commandes fournisseurs, réceptions et dettes — la réception génère l'entrée de stock, ",
                    ),
                    TextSpan(
                      text: 'jamais une double saisie',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(text: '.'),
                  ],
                ),
              ),
            ],
          ),
          if (avecActions)
            Wrap(
              spacing: AppSpacing.xs, // gap-2
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Le bouton standard (PO, 14/10/2026) : le même « Exporter »
                // que sur les autres écrans.
                BoutonStandard(
                  key: const Key('appro-exporter'),
                  libelle: 'Exporter',
                  onPressed: onExporter,
                ),
                _Bouton(
                  cle: const Key('besoins-commander'),
                  libelle: 'Commander la sélection',
                  plein: true,
                  onTap: onCommander,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Bouton extends StatelessWidget {
  const _Bouton({
    required Key cle,
    required this.libelle,
    required this.onTap,
    this.plein = false,
  }) : super(key: cle);

  final String libelle;
  final VoidCallback onTap;
  final bool plein;

  @override
  Widget build(BuildContext context) {
    final texte = plein ? AppColors.neutre0 : AppColors.neutre600;
    return Material(
      color: plein ? AppColors.navy : AppColors.neutre0,
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: plein ? AppSpacing.md : AppSpacing.smPlus,
            vertical: AppSpacing.xsPlus, // py-2.5
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            border: plein ? null : Border.all(color: AppColors.neutre200),
          ),
          child: Text(
            libelle,
            style: _t(
              TaillesContenu.t12,
              poids: FontWeight.w600,
              couleur: texte,
            ),
          ),
        ),
      ),
    );
  }
}

/// La bande de cinq cartes — `grid grid-cols-2 lg:grid-cols-5 gap-3 mb-5`.
class _BandeIndicateurs extends ConsumerWidget {
  const _BandeIndicateurs();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpis = ref.watch(kpisApprovisionnementProvider).value;

    final cartes = <Widget>[
      CarteKpiAchats(
        cle: const Key('kpi-sous-seuil'),
        libelle: 'Articles sous seuil',
        // `null` tant que le serveur n'a pas répondu, et si son refus porte :
        // « — », jamais zéro. Un zéro se lit comme une mesure — « rien à
        // commander ».
        valeur: kpis?.articlesSousSeuil?.toString(),
        raisonAbsence: kpis?.articlesSousSeuil == null
            ? 'Le droit de consulter les stocks manque (M6).'
            : null,
        accent: AppColors.erreur,
      ),
      CarteKpiAchats(
        cle: const Key('kpi-commandes-attente'),
        libelle: 'Commandes en attente',
        valeur: kpis?.commandesEnAttente?.toString(),
        raisonAbsence: kpis?.commandesEnAttente == null
            ? 'Le droit de consulter les achats manque (M7).'
            : null,
      ),
      CarteKpiAchats(
        cle: const Key('kpi-receptions-partielles'),
        libelle: 'Réceptions partielles',
        valeur: kpis?.receptionsPartielles?.toString(),
        raisonAbsence: kpis?.receptionsPartielles == null
            ? 'Le droit de consulter les achats manque (M7).'
            : null,
        accent: AppColors.gold,
      ),
      // Les deux dernières, chiffrées depuis le règlement fournisseur (D66) :
      // `render()` du serveur les somme sur la liste des commandes (D262).
      CarteKpiAchats(
        cle: const Key('kpi-fournisseurs-a-payer'),
        libelle: MessagesReglement.kpiAPayer,
        valeur: kpis?.fournisseursAPayer?.toString(),
        raisonAbsence: kpis?.fournisseursAPayer == null
            ? 'Le droit de consulter les achats manque (M7).'
            : null,
        accent: (kpis?.fournisseursAPayer ?? 0) > 0
            ? PaletteMaitre.ambre600
            : null,
      ),
      CarteKpiAchats(
        cle: const Key('kpi-total-du'),
        libelle: MessagesReglement.totalDu,
        valeur: kpis?.totalDuCentimes == null
            ? null
            : formaterCentimesEnFcfa(kpis!.totalDuCentimes!),
        raisonAbsence: kpis?.totalDuCentimes == null
            ? 'Le droit de consulter les achats manque (M7).'
            : null,
        accent: (kpis?.totalDuCentimes ?? 0) > 0
            ? PaletteMaitre.rouge600
            : null,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.mdPlus), // mb-5
      child: LayoutBuilder(
        builder: (context, contraintes) {
          // `grid-cols-2 lg:grid-cols-5` : cinq colonnes dès 1 024 px.
          final colonnes = contraintes.maxWidth >= 1024 ? 5 : 2;
          final largeur =
              (contraintes.maxWidth - AppSpacing.sm * (colonnes - 1)) /
              colonnes;
          return Wrap(
            spacing: AppSpacing.sm, // gap-3
            runSpacing: AppSpacing.sm,
            children: [
              for (final c in cartes) SizedBox(width: largeur, child: c),
            ],
          );
        },
      ),
    );
  }
}

/// La barre d'onglets : `flex gap-1 mb-5 border-b border-slate-200`, les
/// boutons de `Onglets::classes()`.
class _BarreOnglets extends StatelessWidget {
  const _BarreOnglets({
    required this.actif,
    required this.onglets,
    required this.onChoix,
  });

  final int actif;
  final List<String> onglets;
  final ValueChanged<int> onChoix;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.mdPlus), // mb-5
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.neutre200)),
      ),
      child: Wrap(
        spacing: AppSpacing.unit, // gap-1
        runSpacing: AppSpacing.unit,
        children: [
          for (final (i, libelle) in onglets.indexed)
            Material(
              key: Key('onglet-appro-${_cles[i]}'),
              color: i == actif ? AppColors.navy : AppColors.neutre0,
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
              child: InkWell(
                onTap: () => onChoix(i),
                borderRadius: BorderRadius.circular(AppRadius.roundedLg),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.smPlus, // px-3.5
                    vertical: AppSpacing.xs, // py-2
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.roundedLg),
                    // Le contour existe aussi sur l'onglet actif (marine sur
                    // marine) : sans lui le bouton est 2 px plus court.
                    border: Border.all(
                      color: i == actif ? AppColors.navy : AppColors.neutre200,
                    ),
                  ),
                  child: Text(
                    libelle,
                    style: _t(
                      TaillesContenu.t13,
                      poids: FontWeight.w600,
                      couleur: i == actif
                          ? AppColors.neutre0
                          : AppColors.neutre500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static const _cles = ['besoins', 'commandes', 'receptions', 'dettes'];
}

/// La recherche de la page : `mb-4`, `w-56`, `px-3 py-1.5 text-[13px]`.
class _Recherche extends StatelessWidget {
  const _Recherche({required this.onChange});

  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md), // mb-4
        child: SizedBox(
          width: AppLayout.rechercheAchats,
          child: TextField(
            key: const Key('rech-bes'),
            style: _t(TaillesContenu.t13),
            decoration: InputDecoration(
              hintText: 'Article, point de stockage…',
              hintStyle: _t(TaillesContenu.t13, couleur: AppColors.neutre400),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, // px-3
                vertical: AppSpacing.xxs, // py-1.5
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.roundedLg),
                borderSide: const BorderSide(color: AppColors.neutre300),
              ),
            ),
            onChanged: onChange,
          ),
        ),
      ),
    );
  }
}
