// Vue Blade maîtresse (PA-183) : pwa/pos/heberges.blade.php

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/format/formats.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../hebergement/domain/entities/reservation.dart';
import '../../hebergement/presentation/providers_hebergement.dart';
import '../../restaurant/presentation/widgets/corps_carte_commun.dart'
    show styleContenuCarte;
import '../domain/entities/article_vendable.dart';
import '../domain/entities/panier.dart';
import '../domain/repositories/panier_repository.dart';
import '../domain/unicite_panier_ouvert.dart';
import 'providers_pos.dart';
import 'widgets/catalogue_heberges.dart';
import 'widgets/panier_heberges.dart';

/// **POS clients hébergés** — le panier reste ouvert de l'arrivée au départ.
/// Transcription de `heberges.blade.php`.
///
/// ⚠ **Portage d'une PROPOSITION non ratifiée**
/// (`docs/PROPOSITION_MODELE_PANIER_POS.md`) : Q1 (rattachement des lignes),
/// Q2 (unicité du panier ouvert) et Q3 (place de l'hébergement) restent
/// ouvertes auprès de l'Architecte.
///
/// ## L'ordre des blocs est celui de la vue
///
/// En-tête avec ses deux indicateurs (l.58-75) ; puis trois colonnes — séjours
/// en cours (l.79-122), catalogue (l.124-169), panier du séjour (l.171-275) ;
/// la modale de clôture (l.291-369) est posée dans
/// `widgets/modale_cloture_sejour.dart`.
///
/// ## Ce que cet écran montre, et qui n'existait nulle part
///
/// Les consommations du bar et du restaurant s'ajoutent au fil
/// des jours au **même** panier, et une seule facture est produite au départ.
/// C'est l'exigence explicite du client : « pas de panier différent ».
///
/// ## Un séjour se SÉLECTIONNE, son panier s'ouvre au premier article
///
/// La vue n'a pas de bouton « Ouvrir le panier » : cliquer un séjour le
/// sélectionne (l.97), cliquer un article l'ajoute et ouvre le panier du séjour
/// s'il n'existe pas (`ajouterAuPanier`, l.152). L'ancien écran ouvrait le
/// panier par un bouton dédié ; il est retiré, le geste est celui de la vue.
/// La règle Q2 est intacte : `ouvrirPourSejour` lève toujours
/// `PanierDejaOuvertException`, affichée telle quelle.
///
/// ## ⚠ Q3 — l'hébergement n'est PAS une ligne de ce panier
///
/// La nuitée est déjà engagée à la réservation, avec son tarif figé. La porter
/// aussi au panier ferait exister le même montant à deux endroits, et deux
/// sources pour un même montant finissent toujours par diverger. La
/// composition de la facture de départ est donc explicite —
/// `CompositionFactureSejour` —, jamais un total opaque : la modale de clôture
/// nomme « Hébergement » et « Consommations » séparément. Voir
/// `domain/place_hebergement.dart`.
///
/// ## Ce que cet écran ne rend pas (09/10/2026)
///
/// - **La ligne « Hébergement … FCFA, hors panier »** de l'ancienne liste des
///   séjours : la vue n'en a pas, le montant est dans la modale de clôture.
/// - Les motifs de refus propres à la PWA : les `refus_*` de la clôture sont
///   ceux du dépôt (`ModaleClotureSejour`). Tourisme et location ne sont plus
///   proposés (26/10/2026) : plus de `prestation_refusee`.
class EcranPosHeberges extends ConsumerWidget {
  const EcranPosHeberges({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peutVendre = ref
        .watch(droitsProvider)
        .peutEcrire(ModuleTatacora.m5Bar);
    final large = MediaQuery.sizeOf(context).width >= AppBreakpoints.xl;

    final sejours = ref.watch(sejoursEnCoursProvider).value;
    final paniers =
        ref.watch(paniersDesSejoursProvider).value ?? const <String, Panier>{};
    final selection = ref.watch(sejourSelectionneProvider);
    final reservation = sejours
        ?.where((Reservation r) => r.id == selection)
        .firstOrNull;
    final panier = reservation == null ? null : paniers[reservation.id];

    final catalogue = CatalogueHeberges(
      actif: peutVendre && reservation != null,
      onAjouter: (article) =>
          _ajouter(context, ref, reservation, panier, article),
    );
    final colonnePanier = PanierHeberges(
      reservation: reservation,
      panier: panier,
    );
    const colonneSejours = _ColonneSejours();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _EnTete(),
        Expanded(
          child: large
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // `xl:w-[320px] border-r border-slate-200`. La consigne du
                    // PO (NOUVELLE_INSTRUCTION2 §2) parle de « ~25/50/25 » ;
                    // la vue pose 320 px / reste / 380 px, et la vue gagne
                    // (14/10/2026) — à 1 600 px de contenu, c'est ~20/56/24.
                    const SizedBox(
                      width: LargeursPos.sejours,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.neutre0,
                          border: Border(
                            right: BorderSide(color: Ardoise.c200),
                          ),
                        ),
                        child: colonneSejours,
                      ),
                    ),
                    Expanded(child: catalogue),
                    // `xl:w-[380px] border-l border-slate-200`.
                    SizedBox(
                      width: LargeursPos.panier,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          border: Border(left: BorderSide(color: Ardoise.c200)),
                        ),
                        child: colonnePanier,
                      ),
                    ),
                  ],
                )
              // Sous le palier `xl`, la vue empile les trois sections
              // (`flex-col`) ; la séparation est un filet horizontal.
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(
                      height: LargeursPos.sejoursEmpiles,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.neutre0,
                          border: Border(
                            bottom: BorderSide(color: Ardoise.c200),
                          ),
                        ),
                        child: colonneSejours,
                      ),
                    ),
                    Expanded(child: catalogue),
                    SizedBox(
                      height: LargeursPos.panierEmpile,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          border: Border(top: BorderSide(color: Ardoise.c200)),
                        ),
                        child: colonnePanier,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  /// Ajoute un article au panier du séjour sélectionné, en l'OUVRANT d'abord
  /// s'il n'existe pas (`ajouterAuPanier`, `heberges.blade.php` l.152).
  ///
  /// Les deux appels sont ceux de l'ancien écran (`ouvrirPourSejour`, puis
  /// `ajouter`) : aucune règle de panier ne change. Un refus de Q2 ou un prix
  /// inconnu s'affiche tel quel, le panier restant intact.
  Future<void> _ajouter(
    BuildContext context,
    WidgetRef ref,
    Reservation? reservation,
    Panier? panier,
    ArticleVendable article,
  ) async {
    if (reservation == null) return;
    final gerer = ref.read(gererPanierProvider);
    try {
      final cible =
          panier ??
          await gerer.ouvrirPourSejour(
            reservationId: reservation.id,
            clientNom: reservation.clientNom,
            dateDepartPrevue: reservation.periode.depart,
          );
      await gerer.ajouter(cible.id, article);
      rafraichirPaniers(ref);
    } on PanierDejaOuvertException catch (e) {
      // ⚠ Q2 — le message dit la CONSÉQUENCE, pas la règle.
      if (context.mounted) _signaler(context, '$e');
    } on PrixInconnu catch (e) {
      if (context.mounted) _signaler(context, '$e');
    }
  }

  static void _signaler(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// L'en-tête de page (l.58-75) : titre, sous-titre, et les deux indicateurs.
///
/// Les indicateurs se dérivent des paniers RÉELS ([paniersDesSejoursProvider]) :
/// un compteur tenu à part afficherait « 3 paniers ouverts » sur une base qui
/// n'en a plus un seul (PA-59/60/61).
class _EnTete extends ConsumerWidget {
  const _EnTete();

  /// `pos_pwa.heberges.titre`.
  static const String titre = 'Point de vente — clients hébergés';

  /// `pos_pwa.heberges.sous_titre`.
  static const String sousTitre =
      'Le panier reste ouvert de l’arrivée au départ. Bar et '
      'restaurant y entrent ensemble — un seul panier, une seule facture à la '
      'clôture.';

  /// `pos_pwa.heberges.kpi_paniers`.
  static const String kpiPaniers = 'Paniers ouverts';

  /// `pos_pwa.heberges.kpi_encours`.
  static const String kpiEncours = 'En-cours séjours';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paniers =
        ref.watch(paniersDesSejoursProvider).value ?? const <String, Panier>{};
    final encours = paniers.values.fold<int>(0, (t, p) => t + p.total);

    // `shrink-0 px-5 py-3 border-b border-slate-200 bg-white flex flex-wrap
    // items-start justify-between gap-3`.
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.mdPlus,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        color: AppColors.neutre0,
        border: Border(bottom: BorderSide(color: Ardoise.c200)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.start,
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          ConstrainedBox(
            // `max-w-3xl` sur le sous-titre (l.62).
            constraints: const BoxConstraints(maxWidth: AppLayout.largeur3xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titre,
                  style: styleContenuCarte(
                    TaillesContenu.t15,
                    poids: FontWeight.bold,
                    couleur: AppColors.navy,
                  ),
                ),
                // `mt-0.5`.
                const SizedBox(height: AppSpacing.demi),
                Text(
                  sousTitre,
                  style: styleContenuCarte(
                    TaillesContenu.t12,
                    couleur: Ardoise.c500,
                  ),
                ),
              ],
            ),
          ),
          // `flex items-center gap-2.5`.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Indicateur(
                cle: const Key('pos-kpi-paniers'),
                libelle: kpiPaniers,
                valeur: '${paniers.length}',
                couleur: AppColors.navy,
              ),
              const SizedBox(width: AppSpacing.xsPlus),
              _Indicateur(
                cle: const Key('pos-kpi-encours'),
                libelle: kpiEncours,
                valeur: formaterFcfa(encours),
                couleur: AppColors.gold,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Une carte d'indicateur (l.66-73) : `rounded-lg border px-3 py-2 text-right`.
class _Indicateur extends StatelessWidget {
  const _Indicateur({
    required this.cle,
    required this.libelle,
    required this.valeur,
    required this.couleur,
  });

  final Key cle;
  final String libelle;
  final String valeur;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: cle,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        border: Border.all(color: Ardoise.c200),
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            libelle.toUpperCase(),
            style: styleContenuCarte(
              TaillesContenu.t10,
              poids: FontWeight.w600,
              couleur: Ardoise.c400,
              interlettrage: TaillesContenu.t10 * AppTextStyles.suiviLarge,
            ),
          ),
          Text(
            valeur,
            style: styleContenuCarte(
              TaillesContenu.t15,
              poids: FontWeight.bold,
              couleur: couleur,
            ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }
}

/// La colonne « Séjours en cours » (l.79-122).
class _ColonneSejours extends ConsumerWidget {
  const _ColonneSejours();

  /// `pos_pwa.heberges.sejours`.
  static const String titre = 'Séjours en cours';

  /// `pos_pwa.heberges.sejours_aide`.
  static const String aide = 'Un panier par séjour, jamais deux.';

  /// `pos_pwa.heberges.sejours_vide`.
  static const String vide =
      'Aucun séjour en cours. Le POS hébergés n’a de sens que pour un client '
      'présent.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sejours = ref.watch(sejoursEnCoursProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // `px-4 py-3 border-b border-slate-200 sticky top-0 bg-white`.
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: const BoxDecoration(
            color: AppColors.neutre0,
            border: Border(bottom: BorderSide(color: Ardoise.c200)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titre,
                key: const Key('pos-titre-sejours'),
                // Corps agrandi au rapport du point de vente comptant
                // (consigne du PO, 14/10/2026) : le titre de colonne suit
                // « Salle » (`text-[14px]`) au lieu de `text-[13px]` (vue
                // l.82). Même rapport sur tout le corps de cet écran.
                style: styleContenuCarte(
                  TaillesContenu.t14,
                  poids: FontWeight.bold,
                  couleur: AppColors.navy,
                ),
              ),
              // `mt-0.5`.
              const SizedBox(height: AppSpacing.demi),
              Text(
                aide,
                style: styleContenuCarte(
                  TaillesContenu.t11,
                  couleur: Ardoise.c400,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: sejours.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (liste) => liste.isEmpty
                ? SingleChildScrollView(
                    // `px-4 py-10 text-center` : EN HAUT de la colonne, comme
                    // le bloc de flux de la vue, pas au milieu de sa hauteur.
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xlPlus,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: Text(
                        key: const Key('pos-aucun-sejour'),
                        vide,
                        textAlign: TextAlign.center,
                        style: styleContenuCarte(
                          TaillesContenu.t13,
                          couleur: Ardoise.c400,
                        ),
                      ),
                    ),
                  )
                : ListView(children: [for (final r in liste) _LigneSejour(r)]),
          ),
        ),
      ],
    );
  }
}

/// Un séjour (l.97-119) : toute la ligne est le bouton de sélection.
class _LigneSejour extends ConsumerWidget {
  const _LigneSejour(this.reservation);

  final Reservation reservation;

  /// `pos_pwa.heberges.badge_aucun_panier`.
  static const String badgeAucunPanier = 'AUCUN PANIER';

  /// `pos_pwa.heberges.badge_panier_ouvert`.
  static const String badgePanierOuvert = 'PANIER OUVERT';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panier = ref.watch(paniersDesSejoursProvider).value?[reservation.id];
    final selectionne = ref.watch(sejourSelectionneProvider) == reservation.id;
    final numero = ref
        .watch(unitesProvider)
        .value
        ?.where((u) => u.id == reservation.uniteId)
        .map((u) => u.numero)
        .firstOrNull;
    final depart =
        'Départ prévu le ${formaterDate(reservation.periode.depart)}';

    return InkWell(
      key: Key('pos-sejour-${reservation.id}'),
      onTap: () =>
          ref.read(sejourSelectionneProvider.notifier).definir(reservation.id),
      child: Container(
        // `px-4 py-3 border-b border-slate-100 border-l-4`.
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selectionne ? Ardoise.c50 : null,
          border: Border(
            bottom: const BorderSide(color: Ardoise.c100),
            left: BorderSide(
              width: AppSpacing.unit,
              color: selectionne ? AppColors.gold : Colors.transparent,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    reservation.clientNom,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // ×1,08 (13 → 14), rapport du comptant — 14/10/2026.
                    style: styleContenuCarte(
                      TaillesContenu.t14,
                      poids: FontWeight.bold,
                      couleur: AppColors.navy,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                _Badge(ouvert: panier != null),
              ],
            ),
            // `mt-0.5`.
            const SizedBox(height: AppSpacing.demi),
            Text(
              numero == null ? depart : '$numero · $depart',
              // 11 → 12 (rapport du comptant, 14/10/2026).
              style: styleContenuCarte(
                TaillesContenu.t12,
                couleur: Ardoise.c500,
              ),
            ),
            if (panier != null) ...[
              // `mt-1`.
              const SizedBox(height: AppSpacing.unit),
              Text.rich(
                TextSpan(
                  text: formaterFcfa(panier.total),
                  // 12 → 13 (rapport du comptant, 14/10/2026).
                  style: styleContenuCarte(
                    TaillesContenu.t13,
                    poids: FontWeight.bold,
                    couleur: AppColors.gold,
                  ),
                  children: [
                    TextSpan(
                      text: ' · ${panier.lignes.length}',
                      style: styleContenuCarte(
                        TaillesContenu.t13,
                        poids: FontWeight.normal,
                        couleur: Ardoise.c400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// `shrink-0 text-[10px] font-bold px-2 py-0.5 rounded-full border` (l.105,
/// l.107) : gris sans panier, vert avec.
class _Badge extends StatelessWidget {
  const _Badge({required this.ouvert});

  final bool ouvert;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.demi,
      ),
      decoration: BoxDecoration(
        color: ouvert ? PaletteMaitre.emeraude50 : Ardoise.c100,
        border: Border.all(
          color: ouvert ? PaletteMaitre.emeraude200 : Ardoise.c200,
        ),
        borderRadius: BorderRadius.circular(AppRadius.roundedFull),
      ),
      child: Text(
        ouvert ? _LigneSejour.badgePanierOuvert : _LigneSejour.badgeAucunPanier,
        style: styleContenuCarte(
          TaillesContenu.t10,
          poids: FontWeight.bold,
          couleur: ouvert ? PaletteMaitre.emeraude700 : Ardoise.c500,
        ),
      ),
    );
  }
}
