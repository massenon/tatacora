// Vue Blade maîtresse (PA-183) : pwa/tourisme/departs.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../restaurant/presentation/widgets/coquille_restaurant.dart';
import '../../../restaurant/presentation/widgets/tableau_restaurant.dart';
import '../../domain/entities/circuit.dart';
import '../providers_tourisme.dart';
import 'coquille_tourisme.dart';
import 'modale_prestation.dart';
import 'modale_reservation.dart';

/// L'onglet **« Catalogue »** — vue l.532-622.
///
/// Son titre de cadre dit ce qu'est ce tableau : **« tarifs opposables au
/// client »**. C'est la raison pour laquelle aucun prix n'y est inventé et
/// pourquoi la suppression d'une prestation n'est pas offerte (RG-02).
class VueCatalogue extends ConsumerWidget {
  const VueCatalogue({super.key});

  /// Les colonnes de la vue (l.543-550), dans son ordre.
  static const colonnes = [
    ColonneRestaurant('Prestation'),
    ColonneRestaurant('Type', aDroite: true),
    ColonneRestaurant('Durée', aDroite: true),
    ColonneRestaurant('Zone / thème', aDroite: true),
    ColonneRestaurant('Prix', aDroite: true),
    ColonneRestaurant('Indicatif €', aDroite: true),
    ColonneRestaurant('Départs planifiés', aDroite: true),
    ColonneRestaurant('', aDroite: true),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // La vue filtre le catalogue sur le nom ET la zone (l.720-724) : le filtre
    // vit dans `catalogueAfficheProvider`, que l'export lit aussi.
    final circuits = ref.watch(catalogueAfficheProvider);
    final departsParCircuit = ref.watch(departsParCircuitProvider);

    return circuits.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => NoteRestaurant(
        cle: const Key('tourisme-catalogue-erreur'),
        texte: '$e',
        icone: Icons.error_outline,
      ),
      data: (filtres) {
        if (filtres.isEmpty) {
          return const EtatVideTourisme(
            cle: Key('tourisme-catalogue-vide'),
            // Le message de la vue (l.533), au mot.
            message: 'Aucune prestation ne correspond.',
          );
        }

        return _Corps(
          circuits: filtres,
          departsParCircuit:
              donneeOuNull(departsParCircuit) ?? const <String, int>{},
        );
      },
    );
  }
}

class _Corps extends StatelessWidget {
  const _Corps({required this.circuits, required this.departsParCircuit});

  final List<Circuit> circuits;
  final Map<String, int> departsParCircuit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CadreTableauRestaurant(
          // Le titre du cadre à la vue (l.537), au mot — tiret cadratin
          // compris.
          titre: 'Catalogue — tarifs opposables au client',
          corps: TableauRestaurant(
            gabarit: gabaritTourisme,
            colonnes: VueCatalogue.colonnes,
            clesLignes: [
              for (final c in circuits) Key('tourisme-circuit-${c.id}'),
            ],
            lignes: [for (final c in circuits) _ligne(context, c)],
          ),
        ),
        // L'encadré « Le catalogue est enregistré sur ce poste » (absent de
        // la vue) qui suivait est RETIRÉ (directive absolue du PO,
        // 14/10/2026) : l'onglet se termine après le tableau.
      ],
    );
  }

  List<Widget> _ligne(BuildContext context, Circuit c) {
    final departs = departsParCircuit[c.id];

    return [
      Text(c.nom, style: TextesRestaurant.corpsFort),
      // « Type » — le schéma ne connaît que `circuits` : aucun discriminant
      // ne sépare un circuit d'une excursion. La valeur est donc unique, et
      // la vue l'écrit en pastille (l.558-560).
      Tooltip(
        message:
            'Le schéma ne porte AUCUN discriminant entre un circuit et une '
            'excursion : la colonne vaut « Circuit » pour toute prestation. '
            'C\'est aussi pourquoi le filtre du haut porte sur la prestation '
            'et non sur le type.',
        child: PastilleRestaurant(
          cle: Key('tourisme-type-${c.id}'),
          compacte: true,
          texte: Circuit.type,
          fond: AppColors.badgeGrisFond,
          couleur: Ardoise.c600,
        ),
      ),
      // « Durée » — texte LIBRE du catalogue, lu depuis la v10 (14/09/2026).
      // « — » quand rien n'est renseigné : c'est une donnée absente, plus une
      // colonne manquante, et la nuance change ce que le lecteur en conclut.
      Text(
        c.duree ?? CarteIndicateurRestaurant.absent,
        style: TextesRestaurant.secondaire,
      ),
      // La vue réunit zone et thème avec un point médian (l.562).
      Text('${c.zone} · ${c.theme}', style: TextesRestaurant.secondaire),
      Text(
        formaterFcfa(c.prix),
        style: TextesRestaurant.corpsFort.copyWith(color: AppColors.navy),
      ),
      // « Indicatif € » — aucune colonne au schéma.
      const CelluleAbsenteTourisme(
        raison:
            'L’indicatif en euros n’est pas enregistré : un taux de '
            'conversion figé ne serait celui d’aucun jour, sur un tarif '
            'opposable au client.',
      ),
      Text(
        departs?.toString() ?? CarteIndicateurRestaurant.absent,
        style: TextesRestaurant.corps,
      ),
      _ActionsCatalogue(circuit: c),
    ];
  }
}

/// Les deux actions de ligne — « Planifier » et « Éditer » (vue l.569-572).
///
/// « Planifier » ouvre la réservation sur ce circuit : c'est le geste qui fait
/// naître un départ, puisqu'un départ n'existe que par ses réservations.
/// Aucune suppression n'est offerte — une prestation ne se supprime pas
/// (RG-02).
class _ActionsCatalogue extends ConsumerWidget {
  const _ActionsCatalogue({required this.circuit});

  final Circuit circuit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `@if ($peutEcrire)` de la vue (l.568).
    if (!ref.watch(peutEcrireTourismeProvider)) return const SizedBox.shrink();

    return Wrap(
      alignment: WrapAlignment.end,
      spacing: AppSpacing.unit,
      runSpacing: AppSpacing.unit,
      children: [
        ActionLigneTourisme(
          cle: Key('tourisme-planifier-${circuit.id}'),
          libelle: 'Planifier',
          onPresse: () =>
              ouvrirModaleReservation(context, circuitId: circuit.id),
        ),
        ActionLigneTourisme(
          cle: Key('tourisme-editer-${circuit.id}'),
          libelle: 'Éditer',
          onPresse: () => ouvrirModalePrestation(context, circuit: circuit),
        ),
      ],
    );
  }
}
