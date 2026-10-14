// Vue Blade maîtresse (PA-183) : pwa/vehicules/locations.blade.php
import 'package:flutter/material.dart';

import '../../../restaurant/presentation/widgets/coquille_restaurant.dart';
import '../../../restaurant/presentation/widgets/tableau_restaurant.dart';
import 'vue_parc.dart' show EtatVideVehicules;

/// L'onglet **« Immobilisations »** de la vue
/// (`vehicules/locations.blade.php` l.528-581).
///
/// ## Il est RENDU comme la vue le rend, et il est vide
///
/// La vue montre TOUJOURS ses sept colonnes, même sans ligne, et loge l'état
/// vide dans le tableau (une ligne `colspan` sous l'en-tête, l.531-538 et
/// l.573-575). Ce client fait de même (`videSousEntete`).
///
/// ⚠ Corrigé le 09/10/2026. Cette doc affirmait que « les en-têtes de colonnes
/// ne sont PAS affichées, et c'est le maître », d'après l'ancien maître
/// (`prototype_v2/pages/m8-locations.js` l.202 : `if (!l.length) return
/// vide(...)`). La vue Blade a tranché dans l'autre sens — l'audit navigateur
/// du Product Owner avait relevé exactement cette absence (commentaire de la
/// vue, l.531-538) — et elle est le seul maître (PA-182, PA-183). Le motif
/// du refus avait cessé d'être vrai : il transformait une décision en oubli
/// (PA-144).
///
/// ## Le tableau est vide, et le dit
///
/// ÉCART DÉLIBÉRÉ — `vehicules/locations.blade.php` l.557-571.
/// La vue : sept colonnes remplies depuis `$immobilisations`, relues sur
/// `entretiens_vehicule`.
/// Ici : aucune table d'entretiens n'existe sur ce poste (zéro réseau,
/// 14/09/2026). Le tableau garde ses colonnes et son message (l'encadré qui
/// disait pourquoi il reste vide est retiré le 14/10/2026, directive du PO).
/// Raison : écrire « — » dans des lignes qui n'existent pas serait inventer
/// des immobilisations ; ne rien dire laisserait croire qu'aucun véhicule n'a
/// été immobilisé.
///
/// ## Quatre des sept colonnes n'auraient de toute façon aucune source
///
/// | Colonne de la vue | Source |
/// |---|---|
/// | Véhicule | le véhicule immobilisé |
/// | Motif | `type` (Entretien / Carburation) |
/// | Du | `date` — **une seule date, pas une plage** |
/// | Au | **aucune colonne** (vue l.566 : « — ») |
/// | Jours | **aucune colonne** (vue l.567 : « — ») |
/// | Commentaire | **aucune colonne** (vue l.568 : « — ») |
/// | Enregistré par | auteur de la ligne |
///
///  - maitre-refuse:m8-locations.html#immo
class VueImmobilisations extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
            lignes: const [],
            // L'en-tête reste AU-DESSUS de l'état vide (vue l.545-576).
            videSousEntete: true,
            vide: const EtatVideVehicules(
              cle: Key('vehicules-immo-vide'),
              // `immo_vide` (vue l.574), au mot, dans son propre `Text`.
              message: 'Aucune immobilisation enregistrée.',
              // La précision « Aucune table ne les porte… » et l'encadré ambre
              // « Cet onglet ne peut rien afficher » qui suivait le tableau
              // sont RETIRÉS (directive du PO, 14/10/2026) : l'onglet se
              // termine sur l'état vide de la vue, au mot. L'écart (aucune
              // table d'entretiens sur ce poste) reste nommé dans la doc
              // ci-dessus.
            ),
          ),
        ),
      ],
    );
  }
}
