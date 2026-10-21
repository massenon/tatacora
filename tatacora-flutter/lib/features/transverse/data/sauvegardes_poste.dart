/// Les SAUVEGARDES CONSERVÉES sur ce poste — l'onglet « Sauvegardes de la
/// base » d'Import & Export, rendu à la vue (21/10/2026).
///
/// Le serveur range ses sauvegardes sur son disque (`SauvegardeManuelleService`
/// : trente jours glissants, un fichier « non téléchargée » tant que personne ne
/// l'a sortie du serveur). Ce poste fait de même, à son échelle : la copie
/// cohérente de la base (`VACUUM INTO`, jamais le fichier recopié à chaud —
/// PA-59/60/61) est rangée dans `sauvegardes/`, à côté de `poste.json`, sous un
/// nom daté. AUCUNE colonne de plus, aucune table : le dossier est le registre.
///
///  * **Télécharger** copie le fichier là où l'opérateur le choisit (fenêtre
///    « Enregistrer sous ») et le marque téléchargé : un fichier-témoin
///    `<nom>.telechargee` à côté du sien. Une sauvegarde jamais téléchargée
///    reste signalée — « non téléchargée », bandeau d'attente — parce que, tant
///    qu'elle reste sur ce disque, elle ne protège pas d'un disque perdu.
///  * **Retirer** efface le fichier et son témoin (la confirmation forte, pour
///    une sauvegarde jamais téléchargée, est à l'écran).
///  * **Rétention** : trente jours glissants, appliquée à chaque génération
///    (`purgerAnciennes`), comme le Job du serveur.
///
/// Ce que ce poste NE fait PAS : de sauvegarde automatique nocturne (une
/// application de bureau n'est pas allumée à 02h00). Une sauvegarde de sûreté
/// est en revanche produite AVANT chaque « Réinitialiser comme neuf »
/// (`ReinitialisationLocale`), comme le serveur.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/database/app_database.dart';
import 'configuration_poste.dart';

/// Une sauvegarde rangée.
final class FichierSauvegarde {
  const FichierSauvegarde({
    required this.nom,
    required this.taille,
    required this.date,
    required this.telechargee,
  });

  final String nom;

  /// En octets.
  final int taille;

  /// L'instant de la copie (date de modification du fichier).
  final DateTime date;
  final bool telechargee;
}

/// Une sauvegarde refusée ou introuvable — la phrase est dite à l'écran.
final class SauvegardePosteRefusee implements Exception {
  const SauvegardePosteRefusee(this.message);

  final String message;

  @override
  String toString() => message;
}

class SauvegardesPoste {
  SauvegardesPoste(
    this._base, {
    Future<String> Function()? cheminConfiguration,
    DateTime Function()? maintenant,
  }) : _chemin = cheminConfiguration ?? cheminConfigurationPoste,
       _maintenant = maintenant ?? DateTime.now;

  final AppDatabase _base;
  final Future<String> Function() _chemin;
  final DateTime Function() _maintenant;

  /// La rétention du serveur : trente jours glissants.
  static const int retentionJours = 30;

  /// `tatacora_sauvegarde_AAAA-MM-JJ_HHhMMmSS.sqlite` — les secondes évitent
  /// que deux sauvegardes d'une même minute (la manuelle et celle d'avant une
  /// réinitialisation) ne s'écrasent.
  static String nomDe(DateTime d) {
    String deux(int n) => n.toString().padLeft(2, '0');
    return 'tatacora_sauvegarde_${d.year}-${deux(d.month)}-${deux(d.day)}_'
        '${deux(d.hour)}h${deux(d.minute)}m${deux(d.second)}.sqlite';
  }

  /// Un nom du poste, ni plus ni moins : aucun chemin, aucun `..`.
  static final RegExp _nomValide = RegExp(
    r'^tatacora_sauvegarde_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}h[0-9]{2}(m[0-9]{2})?\.sqlite$',
  );

  Future<Directory> _dossier() async =>
      Directory(p.join(p.dirname(await _chemin()), 'sauvegardes'));

  Future<File> _fichier(String nom) async {
    if (!_nomValide.hasMatch(nom)) {
      throw const SauvegardePosteRefusee('Sauvegarde introuvable.');
    }
    return File(p.join((await _dossier()).path, nom));
  }

  File _temoin(File fichier) => File('${fichier.path}.telechargee');

  /// Produit une sauvegarde COMPLÈTE et la range ; applique la rétention.
  ///
  /// Un fichier vide ou absent après la copie est retiré avant d'être listé
  /// (« le piège du fichier de 802 octets » : un dump incomplet au nom
  /// conforme) et la génération échoue.
  Future<FichierSauvegarde> generer() async {
    final dossier = await _dossier();
    await dossier.create(recursive: true);
    final maintenant = _maintenant();
    final nom = nomDe(maintenant);
    final fichier = File(p.join(dossier.path, nom));
    if (fichier.existsSync()) fichier.deleteSync();
    // Le chemin est une chaîne SQL : l'apostrophe se double.
    final litteral = fichier.path.replaceAll("'", "''");
    try {
      await _base.customStatement("VACUUM INTO '$litteral'");
    } on Object {
      if (fichier.existsSync()) fichier.deleteSync();
      rethrow;
    }
    if (!fichier.existsSync() || fichier.lengthSync() == 0) {
      if (fichier.existsSync()) fichier.deleteSync();
      throw const SauvegardePosteRefusee(
        'La sauvegarde est vide : elle a été retirée.',
      );
    }
    await purgerAnciennes();
    return FichierSauvegarde(
      nom: nom,
      taille: fichier.lengthSync(),
      date: fichier.lastModifiedSync(),
      telechargee: false,
    );
  }

  /// Retire les sauvegardes de plus de [retentionJours] jours.
  Future<int> purgerAnciennes() async {
    final limite = _maintenant().subtract(const Duration(days: retentionJours));
    var retirees = 0;
    for (final f in await fichiers()) {
      if (f.date.isBefore(limite)) {
        await retirer(f.nom);
        retirees++;
      }
    }
    return retirees;
  }

  /// Les sauvegardes rangées, la plus récente d'abord.
  Future<List<FichierSauvegarde>> fichiers() async {
    final Directory dossier;
    try {
      dossier = await _dossier();
    } on Object {
      return const [];
    }
    if (!dossier.existsSync()) return const [];
    final liste = <FichierSauvegarde>[];
    for (final entite in dossier.listSync()) {
      if (entite is! File) continue;
      final nom = p.basename(entite.path);
      if (!_nomValide.hasMatch(nom)) continue;
      liste.add(
        FichierSauvegarde(
          nom: nom,
          taille: entite.lengthSync(),
          date: entite.lastModifiedSync(),
          telechargee: _temoin(entite).existsSync(),
        ),
      );
    }
    return liste..sort((a, b) {
      final d = b.date.compareTo(a.date);
      return d != 0 ? d : b.nom.compareTo(a.nom);
    });
  }

  /// La sauvegarde la plus récente jamais téléchargée — celle du bandeau
  /// « en attente de téléchargement » ; `null` si la plus récente l'a été.
  Future<FichierSauvegarde?> enAttenteDeTelechargement() async {
    final liste = await fichiers();
    if (liste.isEmpty || liste.first.telechargee) return null;
    return liste.first;
  }

  /// Les octets de [nom] — ce que la fenêtre « Enregistrer sous » écrira.
  Future<List<int>> lire(String nom) async {
    final fichier = await _fichier(nom);
    if (!fichier.existsSync()) {
      throw const SauvegardePosteRefusee('Sauvegarde introuvable.');
    }
    return fichier.readAsBytes();
  }

  /// Marque [nom] téléchargée : la copie est sortie du dossier du poste.
  Future<void> marquerTelechargee(String nom) async {
    final fichier = await _fichier(nom);
    if (!fichier.existsSync()) return;
    await _temoin(fichier).writeAsString('', flush: true);
  }

  /// Efface la sauvegarde et son témoin.
  Future<void> retirer(String nom) async {
    final fichier = await _fichier(nom);
    if (fichier.existsSync()) await fichier.delete();
    final temoin = _temoin(fichier);
    if (temoin.existsSync()) await temoin.delete();
  }
}
