import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../fichiers/enregistrement_export.dart';
import 'entete_parametree.dart';
import 'etat_tabulaire_a4.dart';

/// Compose [etat] sous l'en-tête LU DES PARAMÈTRES et l'enregistre par la
/// fenêtre « Enregistrer sous » (`<base>_<AAAA-MM-JJ>.pdf`) — le chemin
/// commun des « PDF Officiel A4 Imprimable » des listes d'écran.
///
/// Rend le CHEMIN écrit, `null` : annulé. Appelée depuis les providers
/// d'export des modules (actions injectables), jamais depuis un widget.
Future<String?> enregistrerEtatA4(
  Ref ref,
  EtatTabulaireA4 etat, {
  required String base,
}) async {
  final entete = await ref.read(lireEnteteEtablissementProvider)();
  final octets = await etat.pdf(entete: entete);
  return ref
      .read(enregistrementExportProvider)
      .exporter(base: base, type: TypeFichierEnregistre.pdf, octets: octets);
}
