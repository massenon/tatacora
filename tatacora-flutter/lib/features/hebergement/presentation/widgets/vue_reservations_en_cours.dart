import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../restaurant/presentation/widgets/coquille_restaurant.dart';
import '../../../restaurant/presentation/widgets/corps_carte_commun.dart'
    show styleContenuCarte;
import '../../../restaurant/presentation/widgets/tableau_restaurant.dart';
import '../../domain/entities/historique_reservations.dart';
import '../../domain/entities/service_reservation.dart';
import '../fiche_reservation.dart';
import '../providers_hebergement.dart';

/// L'onglet **« Réservations en cours »** — `hebergement.blade.php`
/// l.369-428.
///
/// ## Il ne montre QUE les réservations qui portent de l'hébergement
///
/// C'est le filtre du maître (`services.includes('hebergement')`), et il a une
/// raison : cet onglet répond à « qui occupe mes chambres ? ». Une fiche qui ne
/// contient qu'un circuit ou une location n'occupe aucune unité — l'y faire
/// figurer ferait chercher une chambre qui n'a jamais été retenue.
///
/// ## Les quatre états viennent du MÊME calcul que l'historique
///
/// `LigneHistorique` les dérive des dates, une fois pour tout le module. Une
/// seconde dérivation ici — la vue en a une, `$etatSejour` (l.386-391) —
/// finirait par diverger de la première, et deux écrans donneraient deux états
/// pour le même séjour. Ce fichier ne fait que NOMMER et PEINDRE.
///
/// ## Les mots de la vue (09/10/2026)
///
/// La vue écrit « Terminé » sur cette page (l.388) et « Annulée » via
/// `etat_annulee`. Jusqu'au 09/10/2026 ce fichier gardait « Terminée », pour
/// s'accorder avec le panneau Historique ; l'ancien maître en était la raison,
/// et la vue Blade le contredit (PA-182 : la vue gagne). Le panneau
/// Historique, lui, garde son propre libellé : il relève d'une autre vue.
///
/// ## La pagination est celle de la vue
///
/// Dix lignes par page (`PAR_PAGE_RESERVATIONS`, l.884), « Affichage de X-Y sur
/// Z » à gauche et, SEULEMENT s'il y a plus d'une page, les liens à droite
/// (`vendor/pagination`, `@if ($paginator->hasPages())`).
class VueReservationsEnCours extends ConsumerStatefulWidget {
  const VueReservationsEnCours({super.key});

  /// Lignes par page — `PAR_PAGE_RESERVATIONS` (`Hebergement.php` l.114).
  static const int lignesParPage = 10;

  /// Les libellés de la vue pour les quatre états (l.386-391), dans la langue
  /// de cette page et non dans celle de l'Historique.
  static String libelleEtat(EtatSejour etat) => switch (etat) {
    EtatSejour.aVenir => 'À venir',
    EtatSejour.enCours => 'En cours',
    EtatSejour.termine => 'Terminé',
    EtatSejour.annulee => 'Annulée',
  };

  @override
  ConsumerState<VueReservationsEnCours> createState() =>
      _VueReservationsEnCoursState();
}

class _VueReservationsEnCoursState
    extends ConsumerState<VueReservationsEnCours> {
  int _page = 1;

  @override
  Widget build(BuildContext context) {
    final reservations = ref.watch(reservationsProvider);

    return reservations.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Center(child: Text('$e')),
      data: (liste) {
        final lignes =
            filtrerHistorique(
              liste,
              filtre: const FiltreHistorique(),
              maintenant: ref.watch(horlogeHebergementProvider)(),
            ).where((l) {
              // Une réservation d'avant le détail par service (schéma < v8)
              // n'a aucune ligne : elle porte quand même une unité, celle de
              // `unite_id`. L'exclure ferait disparaître tout l'historique du
              // poste de cet onglet.
              if (l.reservation.lignes.isEmpty) return true;
              return l.services.contains(ServiceReservation.hebergement);
            }).toList();

        final total = lignes.length;
        final pages = total == 0
            ? 1
            : ((total - 1) ~/ VueReservationsEnCours.lignesParPage) + 1;
        // La page est clampée ICI, par dérivation : jamais réécrite pendant un
        // rendu (piège 6).
        final page = _page > pages ? pages : _page;
        final debut = (page - 1) * VueReservationsEnCours.lignesParPage;
        final visibles = lignes
            .skip(debut)
            .take(VueReservationsEnCours.lignesParPage)
            .toList();

        return CadreTableauRestaurant(
          corps: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TableauRestaurant(
                colonnes: const [
                  ColonneRestaurant('Client'),
                  ColonneRestaurant('Unité(s) réservée(s)'),
                  ColonneRestaurant('Arrivée'),
                  ColonneRestaurant('Départ'),
                  ColonneRestaurant('Statut'),
                ],
                lignes: [for (final l in visibles) _ligne(l)],
                clesLignes: [
                  for (final l in visibles)
                    ValueKey('en-cours-${l.reservation.id}'),
                ],
                gabarit: _gabarit,
                pleineLargeur: true,
                repartitionProportionnelle: true,
                videSousEntete: true,
                vide: const _Vide(),
              ),
              _Pied(
                total: total,
                debut: total == 0 ? 0 : debut + 1,
                fin: total == 0 ? 0 : debut + visibles.length,
                page: page,
                pages: pages,
                onPage: (p) => setState(() => _page = p),
              ),
            ],
          ),
        );
      },
    );
  }

  /// `th px-4 py-3` sur `bg-[var(--navy)]`, `td px-4 py-3` et
  /// `border-t border-slate-100` (l.374-393) : le gabarit du moteur CRUD, à ceci
  /// près que la bordure de ligne est en HAUT.
  static const GabaritTableau _gabarit = GabaritTableau(
    enteteFond: AppColors.navy,
    entete: TextesRestaurant.enteteColonneNavy,
    cellule: EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    enBas: false,
  );

  List<Widget> _ligne(LigneHistorique l) {
    // Le maître affiche « nom de l'unité × N nuits ». Le libellé de la ligne
    // est celui FIGÉ à la réservation : reprendre le nom courant de l'unité
    // afficherait un nom qu'elle n'avait pas au moment du séjour.
    final unites = l.reservation.lignes
        .where((ligne) => ligne.service == ServiceReservation.hebergement)
        .map((ligne) => '${ligne.libelle} × ${ligne.quantite}n')
        .join(', ');

    return [
      // `font-medium text-slate-700` (l.394).
      Text(
        l.client,
        style: TextesRestaurant.corpsCrud.copyWith(
          fontWeight: FontWeight.w500,
          height: TaillesContenu.interligneSm,
        ),
      ),
      // `text-slate-600` (l.395).
      Text(
        unites.isEmpty ? '—' : unites,
        style: TextesRestaurant.corpsCrud.copyWith(color: Ardoise.c600),
      ),
      _date(formaterDate(l.reservation.periode.arrivee)),
      _date(formaterDate(l.reservation.periode.depart)),
      _Etat(etat: l.etat),
    ];
  }

  /// `text-slate-500 font-mono-tatacora text-[15px]` (l.396-397).
  static Widget _date(String valeur) => Text(
    valeur,
    style: styleContenuCarte(
      TaillesContenu.t15,
      couleur: Ardoise.c500,
    ).copyWith(fontFamily: AppTextStyles.policeMonospace),
  );
}

/// L'état vide de la vue (l.401-411) : une ligne sous l'en-tête, le contrat du
/// tableau générique (« Aucun résultat » et son conseil), puis l'invite propre
/// à l'écran avec sa porte de sortie.
class _Vide extends StatelessWidget {
  const _Vide();

  @override
  Widget build(BuildContext context) {
    final texte = styleContenuCarte(TaillesContenu.sm, couleur: Ardoise.c400);

    return Container(
      // `px-4 py-16 text-center`.
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacingLarge.p16,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Ardoise.c100)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Aucun résultat',
            style: texte.copyWith(
              fontWeight: FontWeight.w600,
              color: Ardoise.c500,
            ),
          ),
          Text(
            'Essayez de modifier votre recherche ou vos filtres.',
            style: styleContenuCarte(TaillesContenu.xs, couleur: Ardoise.c400),
          ),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.unit,
            children: [
              Text(
                "Aucune réservation d'hébergement pour le moment.",
                key: const Key('en-cours-vide'),
                style: texte,
              ),
              // L'état vide du maître porte sa porte de sortie : un écran vide
              // sans issue laisse l'utilisateur chercher où aller.
              InkWell(
                key: const Key('en-cours-creer'),
                onTap: () => ouvrirFicheReservation(context),
                child: Text(
                  'Créer une réservation →',
                  style: texte.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.gold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Le pied du cadre (l.419-426) : `flex items-center justify-between px-4 py-3
/// border-t border-slate-100`.
class _Pied extends StatelessWidget {
  const _Pied({
    required this.total,
    required this.debut,
    required this.fin,
    required this.page,
    required this.pages,
    required this.onPage,
  });

  final int total;
  final int debut;
  final int fin;
  final int page;
  final int pages;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final texte = TextesRestaurant.petitCrud;
    final fort = texte.copyWith(fontWeight: FontWeight.bold);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Ardoise.c100)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            key: const Key('en-cours-decompte'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Affichage de ', style: texte),
              Text('$debut-$fin', style: fort),
              Text(' sur ', style: texte),
              Text('$total', style: fort),
            ],
          ),
          // `@if ($paginator->hasPages())` : sans seconde page, aucun lien.
          if (pages > 1)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Lien(
                  cle: const Key('en-cours-precedent'),
                  libelle: '← Précédent',
                  onPressed: page <= 1 ? null : () => onPage(page - 1),
                ),
                // `flex items-center gap-2` (`vendor/pagination`) : 8 px de
                // chaque côté, plus le `px-2` de la mention de page.
                const SizedBox(width: AppSpacing.xs),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                  child: Text(
                    'Page $page / $pages',
                    key: const Key('en-cours-page'),
                    style: texte.copyWith(color: Ardoise.c600),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                _Lien(
                  cle: const Key('en-cours-suivant'),
                  libelle: 'Suivant →',
                  onPressed: page >= pages ? null : () => onPage(page + 1),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// `px-3 py-1.5 text-xs rounded-lg border border-slate-200`, inactif à 40 %.
class _Lien extends StatelessWidget {
  const _Lien({
    required this.cle,
    required this.libelle,
    required this.onPressed,
  });

  final Key cle;
  final String libelle;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: InkWell(
        key: cle,
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xxs,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: Ardoise.c200),
            borderRadius: BorderRadius.circular(AppRadius.roundedLg),
          ),
          child: Text(
            libelle,
            style: TextesRestaurant.petitCrud.copyWith(color: Ardoise.c600),
          ),
        ),
      ),
    );
  }
}

/// La pastille d'état (l.398) : `text-[15px] font-semibold px-2.5 py-1
/// rounded`, aux couleurs de CETTE page — à venir en doré, en cours en vert,
/// terminé en gris, annulé en rouge. Le panneau Historique, lui, peint « à
/// venir » en bleu : deux pages, deux palettes, et c'est la vue qui en décide.
class _Etat extends StatelessWidget {
  const _Etat({required this.etat});

  final EtatSejour etat;

  @override
  Widget build(BuildContext context) {
    final (fond, texte) = switch (etat) {
      EtatSejour.aVenir => (AppColors.reserveGoldFond, AppColors.gold),
      EtatSejour.enCours => (AppColors.badgeVertFond, AppColors.succes),
      EtatSejour.termine => (AppColors.badgeGrisFond, AppColors.badgeGrisTexte),
      EtatSejour.annulee => (AppColors.badgeRougeFond, AppColors.erreur),
    };

    return Container(
      key: Key('en-cours-etat-${etat.code}'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xsPlus,
        vertical: AppSpacing.unit,
      ),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(AppRadius.rounded),
      ),
      child: Text(
        VueReservationsEnCours.libelleEtat(etat),
        style: styleContenuCarte(
          TaillesContenu.t15,
          poids: FontWeight.w600,
          couleur: texte,
        ),
      ),
    );
  }
}
