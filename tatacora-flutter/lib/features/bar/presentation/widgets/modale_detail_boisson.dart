import 'package:flutter/material.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
// Le moteur CRUD du maître est unique et son portage vit dans
// `features/restaurant/` — voir l'en-tête de `ecran_catalogue_boissons.dart`.
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../../restaurant/presentation/widgets/textes_modale_restaurant.dart';
import '../../domain/entities/boisson.dart';

/// La modale **« Voir le détail »** du moteur CRUD — `crud-ui.js` l.105-125,
/// servie à `prototype_v2/pages/m5-bar.html`.
///
/// Le moteur y rend **une ligne par champ de `champsFormulaire`**, dans l'ordre
/// du formulaire, avec l'étiquette du champ et sa valeur. Les quatre champs de
/// `m5-bar.html` l.121-160 sont donc les quatre lignes de cette modale, dans
/// cet ordre — y compris « Stock disponible (unités) », qui n'a pas d'équivalent
/// en saisie mais en a un en LECTURE : c'est la valeur calculée par le serveur.
///
/// ## Une cinquième ligne est ajoutée, et elle est nommée
///
/// ÉCART DÉLIBÉRÉ — `prototype_v2/pages/m5-bar.html` l.121-160.
/// Le maître : quatre lignes, une par champ de formulaire.
/// Ici : une cinquième, « Article de stock », qui porte `article_id`.
/// Raison : c'est le champ que le serveur exige et que le maître ignore. Une
/// fiche qui ne le montrerait pas laisserait sans réponse la seule question
/// qu'on se pose devant un stock à « — » : à quel casier cette boisson est-elle
/// rattachée ?
Future<void> ouvrirModaleDetailBoisson(
  BuildContext context, {
  required Boisson boisson,
}) => showDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierColor: AppColors.voileModale,
  builder: (_) => _ModaleDetailBoisson(boisson: boisson),
);

class _ModaleDetailBoisson extends StatelessWidget {
  const _ModaleDetailBoisson({required this.boisson});

  final Boisson boisson;

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleRestaurant(
      cle: const Key('modale-detail-boisson'),
      // Le titre du maître — `crud-engine.js` l.362 : « Détail — <valeur du
      // champ d'affichage principal> », qui vaut `nom` (l.77).
      titre: 'Détail — ${boisson.libelle}',
      largeur: AppLayout.modaleDetailPlat,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Ligne(
            cle: const Key('detail-boisson-nom'),
            etiquette: 'Nom de la boisson',
            valeur: boisson.libelle,
          ),
          _Ligne(
            cle: const Key('detail-boisson-categorie'),
            etiquette: 'Catégorie',
            valeur: boisson.categorieLibelle,
          ),
          _Ligne(
            cle: const Key('detail-boisson-prix'),
            etiquette: 'Prix de vente (FCFA)',
            valeur: formaterMontantDecimal(boisson.prixVente, suffixe: 'FCFA'),
          ),
          _Ligne(
            cle: const Key('detail-boisson-stock'),
            etiquette: 'Stock disponible (unités)',
            // `null` reste `null` : la ligne rend « — » et sa note dit
            // pourquoi. Écrire « 0 » ici se lirait « rupture ».
            valeur: boisson.stockDisponible,
            note: boisson.stockDisponible == null
                ? 'Le serveur ne sait pas : aucun point de stockage « bar » '
                      'n’est défini. « — » n’est pas « 0 ».'
                : 'Calculé, en lecture seule.',
          ),
          _Ligne(
            cle: const Key('detail-boisson-article'),
            etiquette: 'Article de stock',
            valeur: boisson.articleId.isEmpty ? null : boisson.articleId,
            note:
                // Ligne absente de la vue, ajoutée : le serveur exige
                // `article_id` (NOT NULL). Note réécrite le 14/10/2026.
                'Le lien qui permet à une vente de décrémenter le casier.',
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('modale-detail-boisson-fermer'),
          onPressed: () => Navigator.of(context).pop(),
          // Le libellé du maître — `crud-ui.js` l.122.
          child: const Text('Fermer', style: TextesModaleRestaurant.bouton),
        ),
      ],
    );
  }
}

/// Une ligne étiquette / valeur — `crud-engine.js` l.370-376.
class _Ligne extends StatelessWidget {
  const _Ligne({
    required Key cle,
    required this.etiquette,
    required this.valeur,
    this.note,
  }) : super(key: cle);

  final String etiquette;

  /// `null` quand la donnée n'existe pas — rendu « — », jamais vide ni zéro
  /// (Article 7).
  final String? valeur;

  final String? note;

  /// Le tiret de l'Article 7, écrit à UN seul endroit dans cette modale.
  static const String absent = '—';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(etiquette, style: TextesModaleRestaurant.etiquette),
          const SizedBox(height: AppSpacing.demi),
          Text(valeur ?? absent, style: TextesModaleRestaurant.corps),
          if (note != null) ...[
            const SizedBox(height: AppSpacing.demi),
            Text(note!, style: TextesModaleRestaurant.aide),
          ],
        ],
      ),
    );
  }
}
