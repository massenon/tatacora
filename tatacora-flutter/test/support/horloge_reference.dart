// L'HORLOGE DE RÉFÉRENCE des tests de mesure (emplacement, géométrie).
//
// Règle : tout test de mesure fige l'horloge. Le relevé de la vue Blade
// (`tool/conformite_blade/structure/*.json`) a été rendu un jour donné — le
// 26/10/2026 — et porte donc « octobre 2026 », « lundi 26 octobre », « Du
// 01/10/2026 au 31/10/2026 ». Un écran Flutter mesuré à l'heure réelle
// compare ces textes au mois COURANT : le cliquet d'emplacement a ainsi reculé
// de 1 (hébergement, accueil) et 7 (paie) le 03/11/2026 sans qu'une ligne de
// code ait changé. Le générateur PHP (`ExtraireStructureBladeTest`) fige la
// même date (`Carbon::setTestNow`) : relevé et mesure partagent UN instant.
//
// Changer cette date, c'est régénérer le relevé web ET refiger les cliquets.

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:tatacora_flutter/features/comptabilite/presentation/exercice_consulte.dart';
import 'package:tatacora_flutter/features/hebergement/presentation/providers_hebergement.dart';

/// 26/10/2026 12:00 (heure locale du processus de test) : le jour du relevé.
final DateTime instantDeReference = DateTime(2026, 10, 26, 12);

DateTime _horloge() => instantDeReference;

/// Les surcharges qui rendent « maintenant » constant pour les écrans mesurés.
List<Override> surchargesHorlogeDeReference() => [
  horlogeHebergementProvider.overrideWithValue(_horloge),
  horlogeAnnulationProvider.overrideWithValue(_horloge),
  horlogeExerciceConsulteProvider.overrideWithValue(_horloge),
];
