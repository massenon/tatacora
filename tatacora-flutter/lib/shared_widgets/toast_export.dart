/// Le message rendu à la fin d'un export — UN seul auteur pour tous les écrans
/// (demande du PO du 14/10/2026).
///
/// Réussi : un toast vert « Export enregistré : `nom du fichier` ». Annulé dans
/// la fenêtre « Enregistrer sous » : rien, ni toast ni fichier. Échoué (le
/// document n'a pu être composé, ou le fichier n'a pu être écrit) : un toast
/// rouge qui le DIT — un export qui échoue en silence est un export que le
/// gérant croit avoir fait.
///
/// Brique commune (`shared_widgets/`) : les couleurs viennent de
/// `lib/core/theme/`, le comportement flottant du thème des `SnackBar`.
library;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/theme/app_colors.dart';

/// Les mots des toasts d'export.
abstract final class TextesToastExport {
  static String enregistre(String nomFichier) =>
      'Export enregistré : $nomFichier';

  static String echec(Object erreur) => "L'export a échoué : $erreur";
}

/// Le nom du fichier d'un chemin — le toast le dit, pas le dossier entier.
String nomDuFichier(String chemin) => p.basename(chemin);

/// Toast vert : l'export est enregistré à [chemin].
void signalerExportEnregistre(
  BuildContext context,
  String chemin, {
  Key cle = const Key('export-enregistre'),
}) => _succes(ScaffoldMessenger.of(context), chemin, cle);

/// Toast rouge : l'export a échoué, avec la raison.
void signalerEchecExport(
  BuildContext context,
  Object erreur, {
  Key cle = const Key('export-echec'),
}) => _echec(ScaffoldMessenger.of(context), erreur, cle);

void _succes(ScaffoldMessengerState messager, String chemin, Key cle) {
  messager
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.succes,
        content: Text(
          TextesToastExport.enregistre(nomDuFichier(chemin)),
          key: cle,
        ),
      ),
    );
}

void _echec(ScaffoldMessengerState messager, Object erreur, Key cle) {
  messager
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.erreur,
        content: Text(TextesToastExport.echec(erreur), key: cle),
      ),
    );
}

/// Exécute un export et en DIT l'issue : [action] compose le document et
/// l'enregistre (`EnregistrementExport`), rend le chemin écrit ou `null`
/// quand l'utilisateur a annulé.
///
/// Rend le chemin écrit, `null` sur annulation comme sur échec.
Future<String?> executerExport(
  BuildContext context,
  Future<String?> Function() action, {
  Key cleSucces = const Key('export-enregistre'),
}) => executerExportAvec(
  ScaffoldMessenger.of(context),
  action,
  cleSucces: cleSucces,
);

/// [executerExport] quand le contexte de l'appelant disparaît avant la fin —
/// une modale fermée AVANT l'enregistrement : le messager est pris avant.
Future<String?> executerExportAvec(
  ScaffoldMessengerState messager,
  Future<String?> Function() action, {
  Key cleSucces = const Key('export-enregistre'),
}) async {
  final String? chemin;
  try {
    chemin = await action();
  } on Object catch (erreur) {
    if (messager.mounted) {
      _echec(messager, erreur, const Key('export-echec'));
    }
    return null;
  }
  if (chemin == null) return null;
  if (messager.mounted) _succes(messager, chemin, cleSucces);
  return chemin;
}
