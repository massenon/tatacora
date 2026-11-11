/// Le JOURNAL DE DÉMARRAGE du poste : `demarrage.log`, dans le dossier de
/// données (`%LOCALAPPDATA%\TATACORA\donnees\`, voir `emplacement_base.dart`).
///
/// PRD réinstallation et démarrage résilient, exigence R1 : un démarrage qui
/// échoue laisse TOUJOURS une ligne ici, même quand la fenêtre n'a pas pu
/// s'afficher.
///
/// - Écriture SYNCHRONE et vidée sur disque à chaque ligne : un processus tué
///   au milieu d'une migration garde ce qu'il avait déjà dit.
/// - TOURNANT : [fichiers] fichiers au plus (`demarrage.log`, `demarrage.1.log`
///   ... `demarrage.4.log`). Un nouveau démarrage fait tourner ; un fichier qui
///   dépasse [tailleMax] octets tourne aussi.
/// - Aucun secret : chaque valeur de [secrets] est remplacée par `***`
///   (`expurgerSecret`, le même outil que les envois SMTP), et toute paire
///   `jeton=...`, `mot de passe: ...` l'est aussi.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../features/transverse/data/envoi_messages_editeur.dart'
    show expurgerSecret;

/// Le nom du fichier courant.
const String nomJournalDemarrage = 'demarrage.log';

class JournalDemarrage {
  JournalDemarrage(
    this.dossier, {
    this.fichiers = 5,
    this.tailleMax = 256 * 1024,
    DateTime Function()? horloge,
    Iterable<String> secrets = const [],
  }) : _horloge = horloge ?? DateTime.now,
       _secrets = List.of(secrets);

  final Directory dossier;
  final int fichiers;
  final int tailleMax;
  final DateTime Function() _horloge;
  final List<String> _secrets;

  /// Le chemin du fichier courant.
  String get chemin => p.join(dossier.path, nomJournalDemarrage);

  /// Le chemin du n-ième fichier ancien (`demarrage.1.log`).
  String cheminAncien(int n) => p.join(dossier.path, 'demarrage.$n.log');

  /// Déclare une valeur secrète à ne jamais écrire.
  void declarerSecret(String secret) {
    if (secret.isNotEmpty) _secrets.add(secret);
  }

  static final RegExp _paireSecrete = RegExp(
    r'(token|jeton|password|passwd|mot[ _]de[ _]passe|secret|authorization)'
    r'(\s*[=:]\s*)([^\s,;]+)',
    caseSensitive: false,
  );

  /// Le texte débarrassé de tout secret.
  String expurger(String texte) {
    var sortie = texte;
    for (final s in _secrets) {
      sortie = expurgerSecret(sortie, s);
    }
    return sortie.replaceAllMapped(_paireSecrete, (m) => '${m[1]}${m[2]}***');
  }

  /// Ouvre une nouvelle session : fait tourner les fichiers puis écrit
  /// l'en-tête. Ne lève jamais (un journal ne doit pas empêcher de démarrer).
  void nouvelleSession(String entete) {
    try {
      dossier.createSync(recursive: true);
      if (File(chemin).existsSync()) _tourner();
    } on Object {
      // Écrit quand même ci-dessous, ou échoue en silence.
    }
    ecrire('=== $entete');
  }

  /// Écrit une ligne, de façon synchrone. Rend `false` si le disque refuse.
  bool ecrire(String message) {
    try {
      final f = File(chemin);
      if (f.existsSync() && f.lengthSync() > tailleMax) _tourner();
      final ligne = expurger(
        '${_horloge().toIso8601String()} $message'.replaceAll('\n', '\n    '),
      );
      f.writeAsStringSync('$ligne\n', mode: FileMode.append, flush: true);
      return true;
    } on Object {
      return false;
    }
  }

  /// Une erreur, avec sa pile, expurgées.
  void ecrireErreur(String contexte, Object erreur, StackTrace? pile) {
    ecrire('ERREUR $contexte : $erreur${pile == null ? '' : '\n$pile'}');
  }

  void _tourner() {
    final dernier = File(cheminAncien(fichiers - 1));
    if (dernier.existsSync()) dernier.deleteSync();
    for (var n = fichiers - 2; n >= 1; n--) {
      final f = File(cheminAncien(n));
      if (f.existsSync()) f.renameSync(cheminAncien(n + 1));
    }
    File(chemin).renameSync(cheminAncien(1));
  }
}
