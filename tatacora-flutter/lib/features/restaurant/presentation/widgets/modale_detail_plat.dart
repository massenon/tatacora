import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/restaurant_api.dart';
import '../../domain/entities/plat.dart';
import '../../domain/messages_restaurant.dart';
import '../providers_restaurant.dart';
import 'coquille_modale_restaurant.dart';
import 'coquille_restaurant.dart';
import 'textes_modale_restaurant.dart';

/// La modale **« Détail »** du moteur CRUD — `crud-ui.js` l.106-121.
///
/// Le maître y rend une ligne par champ de `champsFormulaire`
/// (`crud-engine.js` l.447) : Nom du plat, Catégorie, Prix de vente,
/// Disponible, Ingrédients principaux. Les cinq lignes sont ici, dans son
/// ordre.
///
/// ## « Ingrédients principaux » porte enfin ce que son étiquette annonce
///
/// Le maître y affiche la chaîne libre saisie au formulaire. Elle n'existe pas
/// — et c'est PA-23 qui l'interdit. À sa place, et **sous la même étiquette**,
/// la composition réelle de la fiche technique : de vrais articles, leurs
/// quantités et leur unité de mesure, lues de la base de ce poste
/// (`ingredients_recette_local`). C'est l'Article 6 dans sa formulation
/// exacte : « on implémente la vérité sous une interface inchangée ».
///
/// ## Un coût d'ingrédient INCONNU n'est pas un coût nul
///
/// `cout_unitaire: null` nomme l'article jamais réceptionné : son coût moyen
/// pondéré vaut zéro, ce qui n'est pas un prix. La ligne le dit avec des mots ;
/// afficher « 0 F » ferait apparaître un ingrédient gratuit dans une fiche
/// technique, et le total en dessous serait sous-évalué sans que rien ne le
/// signale.
Future<void> ouvrirModaleDetailPlat(
  BuildContext context, {
  required Plat plat,
}) => showDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierColor: AppColors.voileModale,
  builder: (_) => _ModaleDetailPlat(plat: plat),
);

class _ModaleDetailPlat extends ConsumerWidget {
  const _ModaleDetailPlat({required this.plat});

  final Plat plat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CoquilleModaleRestaurant(
      cle: const Key('modale-detail-plat'),
      // Le titre du maître (l.111) : « Détail — <champ d'affichage> ».
      titre: 'Détail — ${plat.libelle}',
      largeur: AppLayout.modaleDetailPlat,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Ligne(
            cle: const Key('detail-plat-nom'),
            etiquette: 'Nom du plat',
            valeur: plat.libelle,
          ),
          _Ligne(
            cle: const Key('detail-plat-categorie'),
            etiquette: 'Catégorie',
            // Elle vient du menu, seule source. Le menu est nommé avec elle
            // pour que l'origine se voie.
            valeur: plat.categorieLibelle,
            complement: plat.menuLibelle,
          ),
          _Ligne(
            cle: const Key('detail-plat-prix'),
            etiquette: 'Prix de vente (FCFA)',
            // « FCFA » partout, PWA comprise (PA-186, décision du PO).
            valeur: formaterMontantDecimal(plat.prixVente, suffixe: 'FCFA'),
          ),
          _Ligne(
            cle: const Key('detail-plat-disponible'),
            etiquette: 'Disponible',
            // « — » et non « Oui » : un défaut permissif annoncerait qu'un plat
            // est à la carte du jour sans que personne l'ait décidé (PA-61).
            valeur: null,
            raison: MessagesRestaurant.disponibiliteAbsente,
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Ingrédients principaux',
            style: TextesModaleRestaurant.etiquette,
          ),
          const SizedBox(height: AppSpacing.unit),
          _Composition(recetteId: plat.recetteId),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('modale-detail-plat-fermer'),
          onPressed: () => Navigator.of(context).pop(),
          // Le libellé du maître (l.116).
          child: const Text('Fermer', style: TextesModaleRestaurant.bouton),
        ),
        FilledButton(
          key: const Key('modale-detail-plat-modifier'),
          onPressed: () => Navigator.of(context).pop(),
          // Le libellé du maître (l.117). Il ferme le détail ; l'ouverture du
          // formulaire est enchaînée par l'écran, comme au maître
          // (`crud-engine.js` l.442).
          child: const Text('Modifier', style: TextesModaleRestaurant.bouton),
        ),
      ],
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne({
    required Key cle,
    required this.etiquette,
    required this.valeur,
    this.complement,
    this.raison,
  }) : super(key: cle);

  final String etiquette;

  /// `null` = la donnée n'existe pas. La ligne affiche « — » et [raison].
  final String? valeur;

  final String? complement;
  final String? raison;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(etiquette, style: TextesModaleRestaurant.etiquette),
          Text(
            valeur ?? CarteIndicateurRestaurant.absent,
            style: TextesModaleRestaurant.corps.copyWith(
              color: valeur == null ? Ardoise.c400 : AppColors.anthracite,
            ),
          ),
          if (complement != null)
            Text(complement!, style: TextesModaleRestaurant.note),
          if (raison != null) Text(raison!, style: TextesModaleRestaurant.aide),
        ],
      ),
    );
  }
}

/// La composition réelle de la fiche technique.
class _Composition extends ConsumerWidget {
  const _Composition({required this.recetteId});

  final String recetteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (recetteId.isEmpty) {
      return const Text(
        'Aucune fiche technique n’est rattachée à ce plat.',
        style: TextesModaleRestaurant.aide,
      );
    }

    final resultat = ref.watch(compositionProvider(recetteId));

    return resultat.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('$e', style: TextesModaleRestaurant.aide),
      data: (r) => switch (r) {
        RestaurantRecu<RecetteDetail>(:final donnees) => _Lignes(
          detail: donnees,
        ),
        RestaurantRefuse<RecetteDetail>(:final motif) => Text(
          motif,
          key: const Key('detail-plat-composition-refus'),
          style: TextesModaleRestaurant.aide,
        ),
        // Jamais produite : une base locale n'est pas hors connexion.
        RestaurantInjoignable<RecetteDetail>() => const Text(
          'La composition n’a pas pu être lue. Elle n’est pas vide — elle est '
          'inconnue.',
          key: Key('detail-plat-composition-hors-ligne'),
          style: TextesModaleRestaurant.aide,
        ),
      },
    );
  }
}

class _Lignes extends StatelessWidget {
  const _Lignes({required this.detail});

  final RecetteDetail detail;

  @override
  Widget build(BuildContext context) {
    if (detail.composition.isEmpty) {
      return const Text(
        'Fiche technique vide : la vente de ce plat ne décrémente aucun stock, '
        'et sa transmission en cuisine sera refusée.',
        key: Key('detail-plat-composition-vide'),
        style: TextesModaleRestaurant.aide,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(detail.recette.libelle, style: TextesModaleRestaurant.note),
        for (final l in detail.composition)
          Padding(
            key: Key('detail-plat-ingredient-${l.articleId}'),
            padding: const EdgeInsets.only(top: AppSpacing.unit),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    // Jamais l'identifiant à la place du nom : un UUID affiché
                    // dans une liste d'ingrédients ne se lit pas.
                    l.articleLibelle ?? 'Article inconnu du référentiel',
                    style: TextesModaleRestaurant.corps,
                  ),
                ),
                Text(
                  '${l.quantiteUnitaire} ${l.uniteMesure ?? ''}'.trim(),
                  style: TextesModaleRestaurant.note,
                ),
              ],
            ),
          ),
        if (detail.recette.coutMatiereIncomplet) ...[
          const SizedBox(height: AppSpacing.unit),
          Text(
            // Inconnu n'est PAS zéro : sur l'écran où l'on fixe un prix, un
            // zéro afficherait « marge = prix de vente entier ».
            'Coût matière inconnu : '
            '${detail.recette.articlesSansCout.join(', ')} '
            'n’a jamais été réceptionné, son coût moyen pondéré vaut zéro — ce '
            'qui n’est pas un prix.',
            key: const Key('detail-plat-cout-inconnu'),
            style: TextesModaleRestaurant.aide.copyWith(
              color: PaletteMaitre.ambre700,
            ),
          ),
        ],
      ],
    );
  }
}
