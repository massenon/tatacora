// Vue Blade maîtresse (PA-183) : pwa/hebergement/hebergement.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/mesure_texte.dart';
import '../../../core/responsive/retrecissement_flex.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../restaurant/presentation/widgets/corps_carte_commun.dart'
    show PageCarte, grandEcranCarte, styleContenuCarte;
import 'fiche_reservation.dart';
import 'providers_hebergement.dart';
import 'widgets/bouton_hebergement.dart';
import 'widgets/modale_unite.dart';
import 'widgets/vue_calendrier_occupation.dart';
import 'widgets/vue_disponibilites.dart';
import 'widgets/vue_plan_hebergement.dart';
import 'widgets/vue_reservations_en_cours.dart';

/// L'écran **Hébergement & Réservations** — les quatre onglets de la vue.
///
/// @see EF-M1-01 Référentiel des unités d'hébergement
/// @see EF-M1-02 Disponibilité et planning d'occupation
/// @see RG-01 Anti-double réservation
/// @see RG-02 La disponibilité est CALCULÉE, jamais stockée
///
/// ## L'ordre des blocs est celui de la vue (09/10/2026)
///
/// En-tête (l.77-95) : le titre, le sous-titre et, À DROITE, les quatre
/// onglets ; rangée des deux boutons (l.98-116) ; puis le panneau actif. La
/// vue ne rend QU'UN panneau visible à la fois (les autres sont `hidden`) ; ici
/// seul le panneau actif est construit.
///
/// ## Le quatrième onglet, « Disponibilités » (décision du Product Owner, 08/10/2026)
///
/// Le maître n'a que trois onglets. La vue Blade en pose un quatrième
/// (l.89-93) : « avez-vous une chambre du 12 au 15 ? ». C'est le contenu de
/// l'ancien écran `ecran_disponibilites.dart`, devenu orphelin depuis le
/// 14/09/2026 (aucun clic n'y menait — le défaut que PA-133 a coûté). Il est
/// porté dans [VueDisponibilites] ; l'écran orphelin est retiré, après
/// vérification qu'aucune route ni entrée de menu n'y menait.
///
/// ## Ce que la vue pose et que cet écran ne rend pas (motifs relus le 27/10/2026)
///
/// Chaque motif a été relu contre le code (piège 1 : une raison qui a cessé
/// d'être vraie transforme une décision en oubli). Ils vivaient dans un bloc
/// gris affiché sous le plan ; la vue ne le rend pas et sa directive du Product
/// Owner du 02/09/2026 dit « un écran dit ce qu'il FAIT — ce qu'il ne fait pas
/// se déclare dans le code ». Il est donc retiré de l'écran, et ses raisons
/// sont ICI :
///
/// - ~~**« Effectuer Check-In Client » / « Effectuer Check-Out »**~~ — PORTÉS
///   (lot D, 14/10/2026) : `sejours_local` existe et les deux boutons appellent
///   `SejourDao.checkin` / `SejourDao.checkout` (`vue_plan_hebergement.dart`),
///   comme l'accueil. Le motif du 09/10/2026 (« aucune table `sejours` »)
///   était périmé.
/// - ~~**Modale « Réservation rapide »**~~ — PORTÉE : « Réserver cette unité »
///   ouvre `ModaleReservationRapide` (`modale_reservation_rapide.dart`), qui
///   écrit par le même `CreerReservation` que la fiche. L'arbitrage « une
///   seconde saisie » est tranché par la décision du Product Owner (« le poste
///   fait comme le web »).
/// - **« Importer »** : la vue le déclare elle-même refusé (l.140-145) :
///   `unites_hebergement` n'a aucun moteur d'import. L'import des unités existe
///   à l'écran Import / Export (`ImporteurUnites`), pas ici.
/// - **Bandeaux de session** `pwa-succes`, `cycle`, `archivage`, `export`
///   (l.58-74) : ils relaient un message flash de Livewire. Ici le même message
///   s'affiche dans une barre de notification (`SnackBar`), au même moment.
/// - **Ombre `shadow-sm` de l'onglet actif** (l.86-88, `Onglets.php`) : une
///   ombre d'un pixel à 5 % d'opacité, qu'aucune mesure ne distingue. Aucun
///   jeton d'ombre ne la porte ; en créer un pour un effet invisible serait
///   une valeur de plus à maintenir.
class EcranHebergement extends ConsumerStatefulWidget {
  const EcranHebergement({super.key});

  @override
  ConsumerState<EcranHebergement> createState() => _EcranHebergementState();
}

class _EcranHebergementState extends ConsumerState<EcranHebergement> {
  int _onglet = 0;

  /// Les quatre onglets de la vue, dans son ordre (l.86-93).
  static const _onglets = [
    (cle: 'plan', libelle: "Plan d'Hébergement"),
    (cle: 'reservations', libelle: 'Réservations en cours'),
    (cle: 'calendrier', libelle: "Calendrier d'Occupation"),
    (cle: 'disponibilites', libelle: 'Disponibilités'),
  ];

  @override
  Widget build(BuildContext context) {
    final peutEcrire = ref.watch(peutEcrireHebergementProvider);

    return PageCarte(
      largeurMax: AppLayout.pageHebergement,
      enfants: [
        _EnTete(
          onglets: _onglets,
          actif: _onglet,
          onChoix: (i) => setState(() => _onglet = i),
        ),
        // `mb-1` de l'en-tête et `mt-5` de la rangée de boutons : deux marges
        // verticales entre frères SE FUSIONNENT, la plus grande l'emporte — 20 px.
        const SizedBox(height: AppSpacing.mdPlus),
        _RangeeBoutons(peutEcrire: peutEcrire),
        // `mb-3` (l.98).
        const SizedBox(height: AppSpacing.sm),
        switch (_onglet) {
          1 => const VueReservationsEnCours(),
          2 => const VueCalendrierOccupation(),
          3 => const VueDisponibilites(),
          _ => const VuePlanHebergement(),
        },
      ],
    );
  }
}

/// L'en-tête (l.77-95) : à gauche le titre et son sous-titre, à droite les
/// onglets — `flex flex-col lg:flex-row lg:items-center gap-4`.
///
/// ## Le rétrécissement est celui du navigateur
///
/// À 1 383 px la ligne ne tient pas, et la vue montre ses onglets coupés en
/// deux lignes. Le partage de largeur n'est pas deviné : il rejoue celui du
/// navigateur ([partagerRetrecissement]), au niveau de la ligne puis à celui
/// des onglets. Sans lui, les onglets gardent leur largeur naturelle et
/// repoussent le sous-titre sous le titre.
class _EnTete extends StatelessWidget {
  const _EnTete({
    required this.onglets,
    required this.actif,
    required this.onChoix,
  });

  final List<({String cle, String libelle})> onglets;
  final int actif;
  final ValueChanged<int> onChoix;

  /// `h1` de la vue (l.81), au mot.
  static const String titre = 'Hébergement & Réservations';

  /// Le sous-titre de la vue (l.83), au mot, apostrophe droite comprise.
  static const String sousTitre =
      "Gestion du plan d'hébergement du Gîte Chez Noël (Bungalows, Chambres, Tentes) • Règle anti-double réservation";

  static final TextStyle _styleTitre = styleContenuCarte(
    TaillesContenu.lg,
    poids: FontWeight.bold,
    couleur: AppColors.navy,
  );

  static final TextStyle _styleSousTitre = styleContenuCarte(
    TaillesContenu.t15,
    couleur: Ardoise.c500,
  );

  static final TextStyle _styleOnglet = styleContenuCarte(
    TaillesContenu.t13,
    poids: FontWeight.w600,
  );

  /// `px-3.5` de chaque côté (`Onglets.php`) plus, pour l'onglet INACTIF
  /// seulement, la bordure de 1 px de chaque côté : l'actif n'en porte pas.
  static double _enrobage(bool estActif) =>
      AppSpacing.smPlus * 2 + (estActif ? 0 : AppLayout.bordureControle * 2);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, contraintes) {
        final largeur = contraintes.maxWidth;
        final bloc = _blocTitre();

        // Les bases et planchers des onglets.
        final elements = <ElementFlex>[
          for (final (i, o) in onglets.indexed)
            ElementFlex(
              base:
                  largeurMaxContent(o.libelle, _styleOnglet) +
                  _enrobage(i == actif),
              minimum:
                  largeurMinContent(o.libelle, _styleOnglet) +
                  _enrobage(i == actif),
            ),
        ];
        final ecartsOnglets = AppSpacing.xs * (onglets.length - 1);
        final baseOnglets =
            elements.fold<double>(0, (s, e) => s + e.base) + ecartsOnglets;
        final minOnglets =
            elements.fold<double>(0, (s, e) => s + e.minimum) + ecartsOnglets;

        if (!grandEcranCarte(context)) {
          // `flex-col` : le bloc, puis les onglets sur toute la largeur.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              bloc,
              const SizedBox(height: AppSpacing.md),
              _rangeeOnglets(elements, largeur),
            ],
          );
        }

        // `lg:flex-row` : le bloc titre et les onglets se partagent la ligne,
        // `gap-4` entre eux.
        final iconeEtTitre =
            AppLayout.iconeTitrePage +
            AppSpacing.xsPlus +
            largeurMaxContent(titre, _styleTitre);
        final iconeEtMot =
            AppLayout.iconeTitrePage +
            AppSpacing.xsPlus +
            largeurMinContent(titre, _styleTitre);
        final largeurs = partagerRetrecissement(
          elements: [
            ElementFlex(
              base: [
                iconeEtTitre,
                largeurMaxContent(sousTitre, _styleSousTitre),
              ].reduce((a, b) => a > b ? a : b),
              minimum: [
                iconeEtMot,
                largeurMinContent(sousTitre, _styleSousTitre),
              ].reduce((a, b) => a > b ? a : b),
            ),
            ElementFlex(base: baseOnglets, minimum: minOnglets),
          ],
          disponible: largeur,
          ecarts: AppSpacing.md,
        );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: largeurs[0], child: bloc),
            const SizedBox(width: AppSpacing.md),
            const Spacer(),
            SizedBox(
              width: largeurs[1],
              child: _rangeeOnglets(elements, largeurs[1]),
            ),
          ],
        );
      },
    );
  }

  Widget _blocTitre() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.bed_outlined,
              color: AppColors.navy,
              size: AppLayout.iconeTitrePage,
            ),
            // `gap-2.5` — 10 px.
            const SizedBox(width: AppSpacing.xsPlus),
            // MESURÉ : 17 px à 1 383 px, pas 18,5 (`lg:text-xl` ne s'applique
            // pas dans `<main>`).
            Flexible(child: Text(titre, style: _styleTitre)),
          ],
        ),
        // `mt-1.5` — 6 px.
        const SizedBox(height: AppSpacing.xxs),
        Text(sousTitre, style: _styleSousTitre),
      ],
    );
  }

  /// `flex gap-2` (l.85) : les onglets rétrécis, étirés à la hauteur du plus
  /// haut, leur texte centré (un bouton centre son contenu).
  Widget _rangeeOnglets(List<ElementFlex> elements, double largeur) {
    final ecarts = AppSpacing.xs * (onglets.length - 1);
    final tailles = partagerRetrecissement(
      elements: elements,
      disponible: largeur,
      ecarts: ecarts,
    );

    // Plus étroit que la somme des planchers : la vue (`flex gap-2`, sans
    // `flex-wrap`) déborderait. Le poste passe les onglets À LA LIGNE plutôt
    // que de les couper ou de déborder (INSTRUCTION2.txt du PO, 13/10/2026 :
    // aucun débordement). Écart à la vue, seulement sous ce seuil.
    final occupe = tailles.fold<double>(ecarts, (s, t) => s + t);
    if (occupe > largeur + 0.5) {
      return Wrap(
        key: const Key('onglets-a-la-ligne'),
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          for (final (i, o) in onglets.indexed)
            SizedBox(
              width: elements[i].base > largeur ? largeur : elements[i].base,
              child: _Onglet(
                cle: Key('onglet-${o.cle}'),
                libelle: o.libelle,
                actif: i == actif,
                style: _styleOnglet,
                onChoix: () => onChoix(i),
              ),
            ),
        ],
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, o) in onglets.indexed) ...[
            if (i > 0) const SizedBox(width: AppSpacing.xs),
            SizedBox(
              width: tailles[i],
              child: _Onglet(
                cle: Key('onglet-${o.cle}'),
                libelle: o.libelle,
                actif: i == actif,
                style: _styleOnglet,
                onChoix: () => onChoix(i),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Un onglet : `px-3.5 py-2 rounded-lg text-[13px] font-semibold`, plein navy
/// à l'état actif, blanc bordé de `slate-200` sinon (`Onglets.php`, directive du
/// Product Owner du 01/09/2026).
class _Onglet extends StatelessWidget {
  const _Onglet({
    required Key cle,
    required this.libelle,
    required this.actif,
    required this.style,
    required this.onChoix,
  }) : super(key: cle);

  final String libelle;
  final bool actif;
  final TextStyle style;
  final VoidCallback onChoix;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChoix,
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.smPlus,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: actif ? AppColors.navy : AppColors.neutre0,
          // L'onglet actif n'a AUCUNE bordure (`Onglets::ACTIF`).
          border: actif ? null : Border.all(color: Ardoise.c200),
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        ),
        child: Text(
          libelle,
          textAlign: TextAlign.center,
          style: style.copyWith(
            color: actif ? AppColors.neutre0 : Ardoise.c500,
          ),
        ),
      ),
    );
  }
}

/// La rangée de deux boutons (l.98-116) : « Nouvelle réservation » (toujours)
/// et « Ajouter hébergement » (avec le droit d'écriture), `gap-2`.
class _RangeeBoutons extends StatelessWidget {
  const _RangeeBoutons({required this.peutEcrire});

  final bool peutEcrire;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        BoutonHebergement(
          cle: const Key('bouton-nouvelle-reservation-m1'),
          libelle: 'Nouvelle réservation',
          icone: Icons.calendar_month_outlined,
          plein: true,
          onPressed: () => ouvrirFicheReservation(context),
        ),
        // 1er niveau du RBAC (l.105-107) : il ne protège rien, mais un bouton
        // offert puis refusé ferait perdre la saisie.
        if (peutEcrire)
          Consumer(
            builder: (context, ref, _) => BoutonHebergement(
              cle: const Key('bouton-ajouter-hebergement-entete'),
              libelle: 'Ajouter hébergement',
              icone: Icons.add,
              plein: false,
              onPressed: () => ouvrirModaleUnite(context, ref),
            ),
          ),
      ],
    );
  }
}
