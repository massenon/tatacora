import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../hebergement/domain/entities/reservation.dart';
import '../../../restaurant/presentation/widgets/corps_carte_commun.dart'
    show styleContenuCarte;
import '../../domain/entities/panier.dart';
import '../providers_pos.dart';
import 'modale_cloture_sejour.dart';

/// La colonne PANIER DU SÉJOUR du point de vente clients hébergés —
/// `heberges.blade.php` l.171-275.
///
/// Quatre blocs, dans l'ordre de la vue : l'en-tête (l.173-182), la phrase qui
/// dit où vit ce panier (l.190-192), les lignes (l.194-223), le pied (l.225-274)
/// avec la ventilation, le total, la remise et « Clôturer et facturer ».
///
/// ## Rien de la caisse ne change ici
///
/// Les gestes — diminuer, augmenter, retirer, clôturer — appellent les mêmes cas
/// d'usage que l'ancien panneau (`GererPanier`). Seule la présentation suit la
/// vue.
///
/// ## Ce que cette colonne ne rend pas
///
/// - **Le montant de la remise et le net** (l.261-268). La vue les dérive de
///   `Panier::remiseSur()`. Ce poste n'a AUCUNE colonne de remise sur
///   `paniers` (`panier_tables.dart`, relu le 09/10/2026) : le total facturé est
///   le total brut des lignes. La ligne « Remise » est rendue, et la toucher dit
///   ce qui manque — jamais un champ qui accepterait une valeur sans effet.
/// - **Le bandeau « Vider » / « Annuler »** de l'ancien panneau. La vue n'a pas
///   de bouton d'annulation de panier : l'annulation avec motif et la
///   conservation des lignes (règle de `PanierRepository.annuler`) restent dans
///   le domaine, sans geste à l'écran sur ce poste tant que la vue n'en pose
///   pas. Relu le 09/10/2026 : `heberges.blade.php` ne contient ni
///   `annulerPanier` ni `viderPanier`.
class PanierHeberges extends ConsumerWidget {
  const PanierHeberges({
    required this.reservation,
    required this.panier,
    super.key,
  });

  /// Le séjour sélectionné, ou `null`.
  final Reservation? reservation;

  /// Son panier ouvert, ou `null` (séjour sans panier, ou aucun séjour).
  final Panier? panier;

  /// `pos_pwa.heberges.panier`.
  static const String titreParDefaut = 'Panier';

  /// `pos_pwa.heberges.panier_aucun_sejour`.
  static const String aucunSejour =
      'Sélectionnez un séjour à gauche pour voir ou ouvrir son panier.';

  /// `pos_pwa.heberges.panier_vide`.
  static const String panierVide =
      'Panier ouvert, aucune consommation. Choisissez un article dans le '
      'catalogue.';

  /// `pos_pwa.heberges.panier_sur_ce_poste`, « de navigateur » remplacé.
  ///
  /// ÉCART DÉLIBÉRÉ — `lang/fr/pos_pwa.php`, `heberges.panier_sur_ce_poste` :
  /// « … il survit au changement d’équipe et de navigateur. Enregistré sur ce
  /// poste — il ne part vers aucun autre. » Ici, « et à la fermeture de
  /// l’application » à la place de « et de navigateur ».
  /// Raison (09/10/2026) : ce client est une application de bureau, il n'y a
  /// aucun navigateur à changer ; la mention décrirait un cas qui n'existe pas
  /// ici. Le cas qui existe, lui, est la fermeture de la fenêtre. Le reste
  /// est vrai tel quel : le panier est une ligne de la base du
  /// poste (`paniers_local`) et `paniers` n'est pas au registre synchronisable.
  static const String surCePoste =
      'Panier ouvert de l’arrivée au départ : il survit au changement '
      'd’équipe et à la fermeture de l’application. Enregistré sur ce poste — il ne part vers aucun autre.';

  /// `pos_pwa.heberges.total_sejour`.
  static const String totalSejour = 'Total du séjour';

  /// `pos_pwa.commun.remise`.
  static const String remise = 'Remise';

  /// `pos_pwa.commun.remise_aucune`.
  static const String remiseAucune = 'Aucune';

  /// `pos_pwa.commun.remise_valeur` — l'`aria-label` du champ de valeur
  /// (l.255), ici son libellé d'accessibilité.
  static const String remiseValeur = 'Valeur de la remise';

  /// `pos_pwa.heberges.cloturer`.
  static const String cloturer = 'Clôturer et facturer';

  /// Ce que dit la ligne « Remise » quand on la touche.
  ///
  /// Une remise sans colonne pour la porter n'aurait aucun effet sur le total
  /// facturé : la laisser se saisir ferait croire à un rabais accordé qui ne
  /// serait pas facturé (PA-59/60/61). Daté et relu le 09/10/2026 contre
  /// `panier_tables.dart`.
  static const String remiseNonDisponible =
      'La remise ne s’applique pas sur ce poste : le panier de séjour ne porte '
      'aucune remise, donc le total facturé reste le total des lignes. Rien '
      'n’a été enregistré.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lignes = panier?.lignes ?? const <LignePanier>[];

    return Container(
      color: AppColors.neutre0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // `shrink-0 px-4 py-3 border-b border-slate-200 bg-slate-50`.
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: const BoxDecoration(
              color: Ardoise.c50,
              border: Border(bottom: BorderSide(color: Ardoise.c200)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reservation?.clientNom ?? titreParDefaut,
                  // 13 → 14 : le titre « Panier » du comptant (`text-[14px]`),
                  // consigne du PO du 14/10/2026 (vue des hébergés l.174 :
                  // 13). Même rapport sur les lignes, le total et le bouton.
                  style: styleContenuCarte(
                    TaillesContenu.t14,
                    poids: FontWeight.bold,
                    couleur: AppColors.navy,
                  ),
                ),
                if (reservation != null) ...[
                  // `mt-0.5`.
                  const SizedBox(height: AppSpacing.demi),
                  Text(
                    'Départ prévu le ${formaterDate(reservation!.periode.depart)}',
                    style: styleContenuCarte(
                      TaillesContenu.t11,
                      couleur: Ardoise.c400,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // `px-4 py-2.5 text-[11px] text-slate-500 bg-slate-50 border-b`.
          Container(
            key: const Key('pos-transmission'),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xsPlus,
            ),
            decoration: const BoxDecoration(
              color: Ardoise.c50,
              border: Border(bottom: BorderSide(color: Ardoise.c200)),
            ),
            child: Text(
              surCePoste,
              style: styleContenuCarte(
                TaillesContenu.t11,
                couleur: Ardoise.c500,
              ),
            ),
          ),
          Expanded(
            child: reservation == null
                ? const _MessageCentre(
                    cle: Key('pos-aucun-panier-selectionne'),
                    texte: aucunSejour,
                  )
                : lignes.isEmpty
                ? const _MessageCentre(
                    cle: Key('pos-panier-vide'),
                    texte: panierVide,
                  )
                : ListView(
                    children: [
                      for (final ligne in lignes)
                        _Ligne(panier: panier!, ligne: ligne),
                    ],
                  ),
          ),
          _Pied(reservation: reservation, panier: panier),
        ],
      ),
    );
  }
}

/// `px-4 py-16 text-center text-[13px] text-slate-400` (l.196, l.198).
class _MessageCentre extends StatelessWidget {
  const _MessageCentre({required this.cle, required this.texte});

  final Key cle;
  final String texte;

  @override
  Widget build(BuildContext context) {
    // En HAUT de la colonne, texte centré : la vue le pose dans un bloc de flux
    // (`py-16 text-center`), pas au milieu de la hauteur.
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacingLarge.p16,
      ),
      child: SizedBox(
        width: double.infinity,
        child: Text(
          key: cle,
          texte,
          textAlign: TextAlign.center,
          style: styleContenuCarte(TaillesContenu.t13, couleur: Ardoise.c400),
        ),
      ),
    );
  }
}

/// Une ligne du panier (l.200-220) : libellé et prix figé, « − » quantité « + »,
/// montant, retrait.
class _Ligne extends ConsumerWidget {
  const _Ligne({required this.panier, required this.ligne});

  final Panier panier;
  final LignePanier ligne;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modifiable = panier.estModifiable;

    Widget bouton(Key cle, String signe, Future<void> Function()? action) =>
        InkWell(
          key: cle,
          borderRadius: BorderRadius.circular(AppRadius.rounded),
          onTap: action,
          child: Container(
            width: LargeursPos.controleQuantite,
            height: LargeursPos.controleQuantite,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: Ardoise.c300),
              borderRadius: BorderRadius.circular(AppRadius.rounded),
            ),
            child: Text(
              signe,
              style: styleContenuCarte(
                TaillesContenu.t13,
                poids: FontWeight.bold,
              ).copyWith(height: Tailles.interligneAucun),
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xsPlus,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Ardoise.c100)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ligne.libelle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // 12 → 13, comme la ligne du comptant (14/10/2026).
                  style: styleContenuCarte(
                    TaillesContenu.t13,
                    poids: FontWeight.w600,
                    couleur: AppColors.navy,
                  ),
                ),
                // Le prix FIGÉ, et son module : ce n'est pas le prix du jour.
                Text(
                  '${formaterFcfa(ligne.prixUnitaire)} · '
                  '${ligne.reference.module.libelle}',
                  style: styleContenuCarte(
                    TaillesContenu.t11,
                    couleur: Ardoise.c400,
                  ),
                ),
              ],
            ),
          ),
          // `gap-3`.
          const SizedBox(width: AppSpacing.sm),
          if (modifiable)
            bouton(Key('pos-moins-${ligne.id}'), '−', () async {
              await ref.read(gererPanierProvider).diminuer(panier.id, ligne);
              rafraichirPaniers(ref);
            }),
          SizedBox(
            width: LargeursPos.controleQuantite,
            child: Text(
              '${ligne.quantite}',
              textAlign: TextAlign.center,
              style: styleContenuCarte(
                TaillesContenu.t13,
                poids: FontWeight.bold,
              ),
            ),
          ),
          if (modifiable)
            bouton(Key('pos-plus-${ligne.id}'), '+', () async {
              await ref
                  .read(gererPanierProvider)
                  .changerQuantite(panier.id, ligne.id, ligne.quantite + 1);
              rafraichirPaniers(ref);
            }),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: LargeursPos.montantLigne,
            child: Text(
              // Calculé, jamais stocké ni saisi.
              formaterFcfa(ligne.montant),
              textAlign: TextAlign.right,
              style: styleContenuCarte(
                TaillesContenu.t13,
                poids: FontWeight.bold,
                couleur: AppColors.navy,
              ),
            ),
          ),
          if (modifiable) ...[
            const SizedBox(width: AppSpacing.sm),
            InkWell(
              key: Key('pos-retirer-${ligne.id}'),
              onTap: () async {
                await ref
                    .read(gererPanierProvider)
                    .retirer(panier.id, ligne.id);
                rafraichirPaniers(ref);
              },
              // `text-slate-300 text-lg leading-none` : la croix de la vue.
              child: Text(
                '✕',
                style: styleContenuCarte(
                  TaillesContenu.lg,
                  couleur: Ardoise.c300,
                ).copyWith(height: Tailles.interligneAucun),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Le pied (l.225-274) : ventilation, total, remise, « Clôturer et facturer ».
class _Pied extends ConsumerWidget {
  const _Pied({required this.reservation, required this.panier});

  final Reservation? reservation;
  final Panier? panier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = panier?.total ?? 0;
    final ventilation = panier?.ventilation ?? const {};
    final peutCloturer = panier != null && panier!.lignes.isNotEmpty;

    void direRemise() => ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(PanierHeberges.remiseNonDisponible)),
    );

    return Container(
      // `shrink-0 border-t border-slate-200 p-4 bg-slate-50`.
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: const BoxDecoration(
        color: Ardoise.c50,
        border: Border(top: BorderSide(color: Ardoise.c200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ventilation.length > 1) ...[
            // `flex flex-wrap gap-1.5 mb-3` — la mixité est RESTITUÉE, jamais
            // séparée en plusieurs paniers (règle 4).
            Wrap(
              spacing: AppSpacing.xxs,
              runSpacing: AppSpacing.xxs,
              children: [
                for (final e in ventilation.entries)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: AppSpacing.demi,
                    ),
                    decoration: BoxDecoration(
                      color: Ardoise.c100,
                      borderRadius: BorderRadius.circular(
                        AppRadius.roundedFull,
                      ),
                    ),
                    child: Text(
                      '${e.key.libelle} : ${formaterFcfa(e.value)}',
                      style: styleContenuCarte(
                        TaillesContenu.t10,
                        poids: FontWeight.w500,
                        couleur: Ardoise.c600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          // `flex items-center justify-between mb-1`.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                PanierHeberges.totalSejour,
                style: styleContenuCarte(
                  TaillesContenu.t13,
                  poids: FontWeight.w600,
                  couleur: Ardoise.c600,
                ),
              ),
              // `Flexible` : un total à sept chiffres ne doit pas faire sortir
              // l'étiquette de la colonne (le navigateur laisse le texte
              // passer à la ligne, un `Row` Flutter déborde).
              Flexible(
                child: Text(
                  key: const Key('pos-total'),
                  formaterFcfa(total),
                  textAlign: TextAlign.right,
                  // `text-[19px]` à la vue (l.238) ; porté au `text-2xl` du
                  // total du comptant (22 px remappés, TaillesContenu.xxl) sur
                  // consigne du PO du 14/10/2026.
                  style: styleContenuCarte(
                    TaillesContenu.xxl,
                    poids: FontWeight.bold,
                    couleur: AppColors.navy,
                  ).copyWith(height: TaillesContenu.interligneXxl),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.unit),
          // La ligne « Remise » (l.246-257) : étiquette, type, valeur.
          Row(
            children: [
              Text(
                PanierHeberges.remise,
                style: styleContenuCarte(
                  TaillesContenu.t11,
                  poids: FontWeight.w600,
                  couleur: Ardoise.c500,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _ChampRemise(
                cle: const Key('pos-remise-type'),
                texte: PanierHeberges.remiseAucune,
                onTap: direRemise,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _ChampRemise(
                  cle: const Key('pos-remise-valeur'),
                  texte: '',
                  libelleAcces: PanierHeberges.remiseValeur,
                  onTap: direRemise,
                ),
              ),
            ],
          ),
          // `mb-2` (l.267).
          const SizedBox(height: AppSpacing.xs),
          _BoutonCloturer(
            actif: peutCloturer,
            onPressed: () => ouvrirModaleClotureSejour(
              context,
              ref,
              reservation: reservation!,
              panier: panier!,
            ),
          ),
        ],
      ),
    );
  }
}

/// Un des deux champs de la ligne « Remise » : même gabarit qu'un `<select>` /
/// `<input>` de la vue (`text-[12px] border border-slate-300 rounded-lg px-2
/// py-1.5 bg-white`), mais qui, touché, DIT pourquoi il n'agit pas.
class _ChampRemise extends StatelessWidget {
  const _ChampRemise({
    required this.cle,
    required this.texte,
    required this.onTap,
    this.libelleAcces,
  });

  final Key cle;
  final String texte;
  final VoidCallback onTap;

  /// Le libellé d'accessibilité, quand la vue en pose un (`aria-label`).
  final String? libelleAcces;

  @override
  Widget build(BuildContext context) {
    final champ = InkWell(
      key: cle,
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: LargeursPos.montantLigne),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: AppColors.neutre0,
          border: Border.all(color: Ardoise.c300),
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        ),
        child: Text(texte, style: styleContenuCarte(TaillesContenu.t12)),
      ),
    );
    return libelleAcces == null
        ? champ
        : Semantics(label: libelleAcces, child: champ);
  }
}

/// `w-full text-[13px] px-4 py-2.5 rounded-lg font-semibold bg-[var(--gold)]
/// text-[var(--navy)] disabled:opacity-40` (l.270-273).
class _BoutonCloturer extends StatelessWidget {
  const _BoutonCloturer({required this.actif, required this.onPressed});

  final bool actif;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      key: const Key('pos-cloturer'),
      onPressed: actif ? onPressed : null,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.navy,
        disabledBackgroundColor: AppColors.gold.withValues(
          alpha: AppColors.opaciteDesactive,
        ),
        disabledForegroundColor: AppColors.navy.withValues(
          alpha: AppColors.opaciteDesactive,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xsPlus,
        ),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        ),
        // 13 → 14, la taille d'« Encaisser » (14/10/2026).
        textStyle: styleContenuCarte(
          TaillesContenu.t14,
          poids: FontWeight.w600,
        ),
      ),
      child: const Text(PanierHeberges.cloturer),
    );
  }
}
