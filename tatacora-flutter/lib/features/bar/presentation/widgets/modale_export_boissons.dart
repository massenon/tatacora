import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
// Le moteur CRUD du maître est unique et son portage vit dans
// `features/restaurant/` — voir l'en-tête de `ecran_catalogue_boissons.dart`.
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../../restaurant/presentation/widgets/textes_modale_restaurant.dart';
import '../../impression/etat_catalogue_boissons.dart';

/// La modale **« Exporter »** du moteur CRUD — `crud-ui.js` l.142-159, servie
/// à `prototype_v2/pages/m5-bar.html`.
///
/// Structure du maître, zone par zone : titre « Exporter — `<pluriel>` », la
/// phrase qui annonce les colonnes, le bouton pleine largeur, la note de bas.
///
/// ## Les colonnes annoncées sont celles du fichier
///
/// [EtatCatalogueBoissons.colonnes] est la **seule** liste : la modale
/// l'annonce, le fichier la porte. Les quatre colonnes d'export du maître
/// (l.113-118) ont toutes une source — contrairement à M4, où deux d'entre
/// elles n'existaient nulle part.
///
/// ## La note du maître sur la sélection est REFUSÉE
///
/// « Astuce : utilisez la case à cocher du tableau pour n'exporter qu'une
/// sélection. » Les cases à cocher n'existent pas : `OptionsSysteme` pose
/// `suppression_groupee: false` **par défaut** (`options-systeme.js` l.41), et
/// le moteur les retire alors de l'écran (`crud-engine.js` l.198-201). Une
/// astuce qui renvoie à un contrôle absent envoie chercher un défaut là où il
/// n'y en a pas.
Future<bool?> ouvrirModaleExportBoissons(
  BuildContext context, {
  required int nombre,
  required String filtre,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: true,
  barrierColor: AppColors.voileModale,
  builder: (_) => _ModaleExportBoissons(nombre: nombre, filtre: filtre),
);

class _ModaleExportBoissons extends StatelessWidget {
  const _ModaleExportBoissons({required this.nombre, required this.filtre});

  final int nombre;
  final String filtre;

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleRestaurant(
      cle: const Key('modale-export-boissons'),
      // Le titre du maître (`crud-ui.js` l.147) : « Exporter —
      // <entiteLabelPluriel> », et `entiteLabelPluriel` vaut « Boissons »
      // (`m5-bar.html` l.76).
      titre: 'Exporter — Boissons',
      largeur: AppLayout.modaleExportPlats,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // La phrase du maître (l.151), au mot.
          Text(
            'Le fichier CSV (compatible Excel) contiendra les colonnes : '
            '${EtatCatalogueBoissons.colonnes.join(', ')}',
            style: TextesModaleRestaurant.corps,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Filtre appliqué : $filtre',
            key: const Key('modale-export-boissons-filtre'),
            style: TextesModaleRestaurant.note,
          ),
          const SizedBox(height: AppSpacing.sm),
          // La colonne `stock_disponible` part au fichier, mais elle est
          // CALCULÉE : le dire évite qu'on la prenne pour une saisie, et qu'on
          // corrige le fichier au lieu du stock.
          Text(
            'La colonne stock_disponible est calculée par le serveur, jamais '
            'saisie. Une case vide veut dire « le serveur ne sait pas » — '
            'aucun point de stockage « bar » n’est défini —, jamais « zéro ».',
            key: const Key('modale-export-boissons-stock-calcule'),
            style: TextesModaleRestaurant.aide,
          ),
          for (final (colonne, raison)
              in EtatCatalogueBoissons.colonnesAbsentes)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.unit),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$colonne — ',
                      style: TextesModaleRestaurant.aide.copyWith(
                        fontWeight: FontWeight.w700,
                        color: PaletteMaitre.ambre700,
                      ),
                    ),
                    TextSpan(text: raison, style: TextesModaleRestaurant.aide),
                  ],
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('modale-export-boissons-annuler'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Annuler', style: TextesModaleRestaurant.bouton),
        ),
        FilledButton(
          key: const Key('modale-export-boissons-telecharger'),
          // Une liste vide se **refuse** (PA-119) : une page blanche remise au
          // comptable se lit comme « aucune boisson », alors qu'elle veut dire
          // « le filtre n'a rien retenu ».
          onPressed: nombre == 0 ? null : () => Navigator.of(context).pop(true),
          // Le libellé du maître (l.154), au mot.
          child: const Text(
            'Télécharger tous les résultats filtrés (.csv)',
            style: TextesModaleRestaurant.bouton,
          ),
        ),
      ],
    );
  }
}
