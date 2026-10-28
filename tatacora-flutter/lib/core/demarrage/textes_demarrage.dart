import 'dart:io';

import 'package:drift/native.dart' show SqliteException;

/// Les libellés de l'écran d'attente et de l'écran de panne — UN SEUL endroit.
abstract final class TextesDemarrage {
  static const String attente = 'Mise à jour de la base du poste…';
  static const String attenteExplication =
      'Cela peut prendre un moment après une mise à jour du logiciel. '
      'Ne fermez pas la fenêtre.';

  static const String titrePanne = "L'application ne peut pas démarrer";
  static const String titreBloquee = 'Préparation bloquée';
  static const String explicationPanne =
      'Vos données n’ont pas été effacées. Copiez le détail ci-dessous '
      "et transmettez-le à l'éditeur.";
  static const String explicationBloquee =
      'La préparation de la base du poste dure plus longtemps que prévu. '
      'Patientez encore un peu, ou copiez le détail et quittez.';

  static const String libelleCause = 'Cause';
  static const String libelleJournal = 'Journal';
  static const String journalIndisponible = 'journal indisponible';

  static const String copier = 'Copier le détail';
  static const String copie = 'Détail copié.';
  static const String ouvrirDossier = 'Ouvrir le dossier des données';
  static const String quitter = 'Quitter';

  /// Cause en clair d'une erreur de démarrage.
  static String cause(Object erreur) => switch (erreur) {
    SqliteException(:final message) =>
      'La base de données du poste est illisible ou incomplète ($message).',
    FileSystemException(:final message, :final path) =>
      'Un fichier du poste est inaccessible : $message'
          '${path == null || path.isEmpty ? '' : ' ($path)'}.',
    _ => erreur.toString(),
  };
}
