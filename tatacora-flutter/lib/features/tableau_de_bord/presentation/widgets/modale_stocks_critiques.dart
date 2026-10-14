// Vue Blade maîtresse (PA-183) : pwa/livewire/accueil.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../../stocks/data/stocks_api.dart';
import '../../domain/exploitation_locale.dart';
import '../ecran_pilotage_consolide.dart' show stockPilotageProvider;

/// Ouvre la modale « Articles sous le seuil d'alerte » — `$set('etatFormulaire',
/// 'stocks-critiques')` de la vue, depuis l'accès rapide « Stocks critiques »
/// (l.349) et le lien « Voir » du bandeau rouge (l.573).
Future<void> ouvrirModaleStocksCritiques(BuildContext context) =>
    showDialog<void>(
      context: context,
      builder: (_) => const ModaleStocksCritiques(),
    );

/// La modale de la vue d'accueil (l.1689-1719), dans le châssis partagé des
/// modales ([CoquilleModaleRestaurant], l'équivalent de `x-pwa.modale`).
///
/// Un panneau de LECTURE : la liste est [articlesCritiques] — la même que le
/// bandeau et que le compte de « À traiter » (une lecture, trois usages). Les
/// colonnes de la vue : « Article », « Stock théorique » (en rouge, avec
/// l'unité), « Seuil d'alerte » ; le pied : « Annuler » et « Gérer les
/// stocks » (lien vers l'écran Stocks).
///
/// Hors `<main>` (les modales de la vue sont posées après `</main>`) : échelle
/// typographique DÉCLARÉE ([Tailles]).
class ModaleStocksCritiques extends ConsumerWidget {
  const ModaleStocksCritiques({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final critiques = switch (ref.watch(stockPilotageProvider).value) {
      StockRecu(:final etat) => articlesCritiques(etat.lignes),
      // Une lecture refusée ou en cours n'est pas « aucun article » : la
      // modale n'affirme rien tant qu'elle n'a rien lu.
      _ => null,
    };

    const corpsTexte = TextStyle(
      fontFamily: AppTextStyles.police,
      fontSize: Tailles.t14, // `text-sm`
      height: AppLayout.interligneContenu,
      letterSpacing: 0,
    );

    Widget cellule(String texte, {Color? couleur, bool droite = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, // px-3
            vertical: AppSpacing.xs, // py-2
          ),
          child: Text(
            texte,
            textAlign: droite ? TextAlign.right : TextAlign.left,
            style: corpsTexte.copyWith(color: couleur),
          ),
        );

    Widget enTete(String texte, {bool droite = false}) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Text(
        // `uppercase tracking-wide`.
        texte.toUpperCase(),
        textAlign: droite ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          fontFamily: AppTextStyles.police,
          fontSize: Tailles.t11,
          fontWeight: FontWeight.w600,
          height: AppLayout.interligneContenu,
          letterSpacing: AppTextStyles.suiviLarge * Tailles.t11,
          color: AppColors.neutre0.withValues(
            alpha: OpacitesAccueil.enTeteTableau,
          ),
        ),
      ),
    );

    final Widget corps;
    if (critiques == null) {
      corps = const SizedBox.shrink();
    } else if (critiques.isEmpty) {
      corps = const Text(
        'Aucun article sous son seuil sur les mouvements enregistrés.',
        key: Key('tdb-stocks-critiques-vide'),
        style: TextStyle(
          fontFamily: AppTextStyles.police,
          fontSize: Tailles.t13,
          color: AppColors.neutre500,
        ),
      );
    } else {
      corps = Table(
        key: const Key('tdb-stocks-critiques-table'),
        columnWidths: const {
          0: FlexColumnWidth(MesuresAccueil.poidsColonneArticleCritique),
        },
        children: [
          TableRow(
            decoration: const BoxDecoration(color: AppColors.navy),
            children: [
              enTete('Article'),
              enTete('Stock théorique', droite: true),
              enTete("Seuil d'alerte", droite: true),
            ],
          ),
          for (final (i, l) in critiques.indexed)
            TableRow(
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : const Border(top: BorderSide(color: AppColors.neutre100)),
              ),
              children: [
                cellule(l.libelle, couleur: AppColors.neutre700),
                cellule(
                  '${l.stock} ${l.uniteMesure}',
                  couleur: PaletteMaitre.rouge600,
                  droite: true,
                ),
                cellule(
                  '${l.seuilAlerte} ${l.uniteMesure}',
                  couleur: AppColors.neutre500,
                  droite: true,
                ),
              ],
            ),
        ],
      );
    }

    const libelleBouton = TextStyle(
      fontFamily: AppTextStyles.police,
      fontSize: Tailles.t13,
    );

    return CoquilleModaleRestaurant(
      cle: const Key('tdb-modale-stocks-critiques'),
      titre: "Articles sous le seuil d'alerte",
      largeur: MesuresAccueil.modaleStocksCritiques,
      corps: corps,
      actions: [
        OutlinedButton(
          key: const Key('tdb-stocks-critiques-annuler'),
          onPressed: () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Ardoise.c300),
            foregroundColor: AppColors.anthracite,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            ),
          ),
          child: const Text('Annuler', style: libelleBouton),
        ),
        FilledButton(
          key: const Key('tdb-stocks-critiques-gerer'),
          // `<a href="{{ route('pwa.stocks.liste') }}">` : l'écran Stocks.
          onPressed: () {
            // Le routeur est lu AVANT de fermer : après `pop`, le contexte
            // de la modale n'est plus monté.
            final routeur = GoRouter.of(context);
            Navigator.of(context).pop();
            routeur.go('/stocks');
          },
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.navy,
            foregroundColor: AppColors.neutre0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            ),
          ),
          child: Text(
            'Gérer les stocks',
            style: libelleBouton.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
