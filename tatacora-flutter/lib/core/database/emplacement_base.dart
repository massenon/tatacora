/// L'EMPLACEMENT de la base du poste — décision du Product Owner du
/// 17/10/2026 : « on va mettre la base de données SQLite dans un autre
/// dossier, pas dans Documents, pour éviter la suppression involontaire ».
///
/// ## Où
///
/// `%LOCALAPPDATA%\TATACORA\donnees\tatacora.sqlite` sous Windows : un
/// dossier caché du compte, que l'Explorateur ne montre pas, que OneDrive ne
/// synchronise pas (une base SQLite synchronisée par OneDrive se corrompt)
/// et qu'un « ménage » du dossier Documents n'atteint pas. Ailleurs (essais,
/// Linux), le dossier de support de l'application.
///
/// ## Le DÉMÉNAGEMENT d'une base existante — une fois, au démarrage
///
/// Un poste installé avant cette décision a sa base dans Documents. Au
/// premier démarrage, avant toute ouverture :
///  1. la base neuve existe déjà → elle est prise, l'ancienne n'est JAMAIS
///     relue (elle ressusciterait des données périmées) ;
///  2. sinon, l'ancienne existe → elle est COPIÉE avec ses journaux
///     (`-wal`, `-shm` : un journal non reporté porte les dernières saisies),
///     dans un fichier temporaire, tailles vérifiées, puis renommée à sa
///     place définitive ; l'ancienne est RENOMMÉE
///     `tatacora.sqlite.deplacee-vers-appdata`, jamais effacée — le jour où
///     la base neuve serait effacée, rien ne repartirait en silence sur
///     l'ancienne ;
///  3. ni l'une ni l'autre → base neuve, créée à l'ouverture.
///
/// Une copie qui échoue LÈVE et ne touche pas à l'ancienne : le logiciel ne
/// démarre pas sur une base vide en laissant les saisies derrière lui.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Le nom du fichier de la base.
const String nomFichierBase = 'tatacora.sqlite';

/// Le suffixe posé sur l'ancienne base une fois déménagée.
const String suffixeAncienneBase = '.deplacee-vers-appdata';

/// Le dossier de la base sous Windows, ou `null` hors Windows / sans
/// `LOCALAPPDATA`.
String? dossierBaseWindows(Map<String, String> environnement) {
  final local = environnement['LOCALAPPDATA'];
  if (local == null || local.isEmpty) return null;
  return p.join(local, 'TATACORA', 'donnees');
}

/// Ce qu'a fait [preparerEmplacementBase].
enum IssueEmplacement { dejaEnPlace, deplacee, neuve }

/// Prépare le fichier de la base dans [dossierNeuf] et le rend, en
/// déménageant au besoin celle de [dossierAncien] (voir l'en-tête).
Future<({File fichier, IssueEmplacement issue})> preparerEmplacementBase({
  required Directory dossierNeuf,
  required Directory? dossierAncien,
}) async {
  await dossierNeuf.create(recursive: true);
  final neuf = File(p.join(dossierNeuf.path, nomFichierBase));
  if (neuf.existsSync()) {
    return (fichier: neuf, issue: IssueEmplacement.dejaEnPlace);
  }
  if (dossierAncien == null || p.equals(dossierAncien.path, dossierNeuf.path)) {
    return (fichier: neuf, issue: IssueEmplacement.neuve);
  }
  final ancien = File(p.join(dossierAncien.path, nomFichierBase));
  if (!ancien.existsSync()) {
    return (fichier: neuf, issue: IssueEmplacement.neuve);
  }

  // Les journaux d'abord, la base en dernier : tant que `tatacora.sqlite`
  // n'est pas à sa place, un démarrage interrompu recommence la copie.
  for (final suffixe in const ['-wal', '-shm']) {
    final journal = File('${ancien.path}$suffixe');
    if (journal.existsSync()) {
      await _copierVerifie(journal, File('${neuf.path}$suffixe'));
    }
  }
  await _copierVerifie(ancien, neuf);

  for (final suffixe in const ['', '-wal', '-shm']) {
    final f = File('${ancien.path}$suffixe');
    if (f.existsSync()) {
      await f.rename('${ancien.path}$suffixe$suffixeAncienneBase');
    }
  }
  return (fichier: neuf, issue: IssueEmplacement.deplacee);
}

/// Copie [source] vers [cible] par un fichier temporaire, tailles comparées,
/// puis renommage — une copie à moitié écrite ne porte jamais le nom final.
Future<void> _copierVerifie(File source, File cible) async {
  final temporaire = File('${cible.path}.copie');
  if (temporaire.existsSync()) await temporaire.delete();
  await source.copy(temporaire.path);
  final attendu = source.lengthSync();
  final obtenu = temporaire.lengthSync();
  if (attendu != obtenu) {
    await temporaire.delete();
    throw FileSystemException(
      'Copie incomplète de la base ($obtenu octets sur $attendu)',
      source.path,
    );
  }
  await temporaire.rename(cible.path);
}
