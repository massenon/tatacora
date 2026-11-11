// Vue Blade maîtresse (PA-183) : pwa/vehicules/locations.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/contrat_location.dart';
import '../providers_vehicules.dart';

import '../../../restaurant/presentation/widgets/coquille_restaurant.dart';
import '../../../restaurant/presentation/widgets/tableau_restaurant.dart';
import 'vue_parc.dart' show EtatVideVehicules;

/// L'onglet **« Immobilisations »** de la vue
/// (`vehicules/locations.blade.php` l.528-581).
///
/// ## Il lit `entretiens_vehicule_local` (v32, 21/10/2026)
///
/// Sept colonnes, comme la vue, TOUJOURS affichées, l'état vide logé dans le
/// tableau (l.531-538, l.573-575). Les lignes viennent des entretiens saisis
/// ici ou descendus du serveur.
///
/// ## Trois colonnes restent « — », et la vue aussi
///
/// | Colonne | Source |
/// |---|---|
/// | Véhicule | le véhicule immobilisé |
/// | Motif | `type` (Entretien / Carburation) |
/// | Du | `date` — une seule date |
/// | Au / Jours / Commentaire | aucune colonne au schéma (vue l.564-568 : « — ») |
/// | Enregistré par | login de qui l'a saisi ; « — » pour une ligne descendue |
class VueImmobilisations extends ConsumerWidget {
  const VueImmobilisations({super.key});

  /// Les colonnes du maître (l.203), dans son ordre. Il ne déclare aucun
  /// `gauche` : seule la première est à gauche.
  static const colonnes = [
    ColonneRestaurant('Véhicule'),
    ColonneRestaurant('Motif', aDroite: true),
    ColonneRestaurant('Du', aDroite: true),
    ColonneRestaurant('Au', aDroite: true),
    ColonneRestaurant('Jours', aDroite: true),
    ColonneRestaurant('Commentaire', aDroite: true),
    ColonneRestaurant('Enregistré par', aDroite: true),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entretiens = switch (ref.watch(entretiensProvider)) {
      AsyncData(value: final v) => v,
      _ => const <EntretienVehicule>[],
    };
    const tiret = Text('—', style: TextesRestaurant.mention);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CadreTableauRestaurant(
          // `immo_titre` (vue l.541).
          titre: 'Immobilisations du parc',
          corps: TableauRestaurant(
            gabarit: GabaritTableau.carte,
            colonnes: colonnes,
            clesLignes: [
              for (final e in entretiens) Key('vehicules-immo-${e.id}'),
            ],
            lignes: [
              for (final e in entretiens)
                [
                  Text(e.immatriculation, style: TextesRestaurant.corpsFort),
                  Text(e.type.libelle, style: TextesRestaurant.secondaire),
                  Text(_jour(e.date), style: TextesRestaurant.secondaire),
                  tiret,
                  tiret,
                  tiret,
                  Text(e.auteur ?? '—', style: TextesRestaurant.mention),
                ],
            ],
            // L'en-tête reste AU-DESSUS de l'état vide (vue l.545-576).
            videSousEntete: true,
            vide: const EtatVideVehicules(
              cle: Key('vehicules-immo-vide'),
              // `immo_vide` (vue l.574), au mot, dans son propre `Text`.
              message: 'Aucune immobilisation enregistrée.',
            ),
          ),
        ),
      ],
    );
  }

  /// `AAAA-MM-JJ` → `JJ/MM/AAAA` (vue : `format('d/m/Y')`).
  static String _jour(String iso) {
    final p = iso.split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : iso;
  }
}
