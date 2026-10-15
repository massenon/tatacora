/// La configuration LOCALE du poste, hors de la base et hors du dossier
/// d'installation — Lot J2 partie 2, directive du Product Owner du 14/10/2026.
///
/// ## Ce qu'elle porte, et pourquoi pas ailleurs
///
/// Le MOT DE PASSE SMTP de l'envoi à l'éditeur et, depuis le lot F2a
/// (15/10/2026), l'APPAIRAGE du poste au serveur : son nom (`poste_id`), son
/// jeton Sanctum (`jeton_api`), le serveur, la date et le compte qui l'a
/// appairé. Le mot de passe du compte serveur, lui, n'est écrit NULLE PART :
/// il sert à `POST /login`, une fois, puis disparaît.
/// Un secret n'entre JAMAIS dans la base Drift (registre fermé des
/// paramètres, `RegistreParametresLocal`) : la base se copie (« Générer une
/// sauvegarde »), s'exporte table par table, et tout compte qui ouvre
/// Paramètres la lit. Il n'est pas non plus dans le code ni dans le dépôt : un
/// mot de passe livré avec le binaire est connu de quiconque a le binaire.
/// C'est la règle du serveur (`MAIL_PASSWORD` en `.env` seulement,
/// `ConfigurationMailService`), transposée au poste.
///
/// ## Où
///
/// Sous Windows : `%APPDATA%\TATACORA\poste.json` — typiquement
/// `C:\Users\<compte Windows>\AppData\Roaming\TATACORA\poste.json`. Hors du
/// dossier d'installation (`Program Files`), que la désinstallation efface et
/// qu'un compte ordinaire ne peut pas écrire. Ailleurs (poste de
/// développement) : `poste.json` dans le dossier de support de l'application
/// (`getApplicationSupportDirectory`). Modèle livré :
/// `installer/poste.example.json` ; `poste.json` est ignoré par git.
///
/// ```json
/// {
///   "smtp_mot_de_passe": "...",
///   "poste_id": "COMPTOIR-1",
///   "jeton_api": "12|…",
///   "serveur": "https://logirestock.digitonpro.com/api/v1",
///   "appaire_le": "2026-10-15T09:12:00.000Z",
///   "compte": "gerant"
/// }
/// ```
///
/// Les cinq clés d'appairage sont écrites par l'écran Paramètres →
/// « Synchronisation » ([EcrivainConfigurationPoste]), jamais à la main ; le
/// mot de passe SMTP reste posé à la main. Chaque écriture relit le fichier,
/// ne change que ses clés et remplace le fichier ATOMIQUEMENT (fichier
/// temporaire puis renommage) : une coupure de courant pendant l'écriture
/// laisse l'ancien fichier entier, jamais un fichier tronqué qui aurait
/// emporté le mot de passe SMTP.
///
/// ## Quand
///
/// Relu À CHAQUE envoi, jamais gardé en mémoire au-delà de l'envoi : un mot de
/// passe posé ou corrigé dans le fichier sert au prochain envoi, sans
/// redémarrer. Un fichier absent, illisible ou sans la clé n'est pas une
/// erreur du poste : le message reste en file et l'écran DIT pourquoi.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// La clé du mot de passe SMTP dans `poste.json`.
const String cleMotDePasseSmtp = 'smtp_mot_de_passe';

/// Le chemin à DIRE à l'opérateur (sans dépendre de la machine).
const String cheminConfigurationPosteAffiche = r'%APPDATA%\TATACORA\poste.json';

/// Le résultat d'une lecture du mot de passe.
sealed class LectureMotDePasse {
  const LectureMotDePasse();
}

/// Le mot de passe est là. Son `toString` ne le révèle pas.
final class MotDePasseLu extends LectureMotDePasse {
  const MotDePasseLu(this.valeur);

  final String valeur;

  @override
  String toString() => 'MotDePasseLu(***)';
}

/// Le mot de passe manque — [raison] se dit à l'écran.
final class MotDePasseAbsent extends LectureMotDePasse {
  const MotDePasseAbsent(this.raison);

  final String raison;
}

/// Les phrases de la lecture.
abstract final class TextesConfigurationPoste {
  static String fichierAbsent(String chemin) =>
      'Mot de passe SMTP non configuré sur ce poste : le fichier $chemin '
      "n'existe pas.";
  static String fichierIllisible(String chemin) =>
      'Mot de passe SMTP non configuré sur ce poste : le fichier $chemin est '
      'illisible (JSON attendu).';
  static String cleAbsente(String chemin) =>
      'Mot de passe SMTP non configuré sur ce poste : la clé '
      '« $cleMotDePasseSmtp » est absente ou vide dans $chemin.';
}

/// Lit `poste.json`. Injectable : un test passe son propre [chemin].
class LecteurConfigurationPoste {
  LecteurConfigurationPoste({Future<String> Function()? chemin})
    : _chemin = chemin ?? cheminConfigurationPoste;

  final Future<String> Function() _chemin;

  Future<LectureMotDePasse> motDePasseSmtp() async {
    final chemin = await _chemin();
    final fichier = File(chemin);
    if (!fichier.existsSync()) {
      return MotDePasseAbsent(TextesConfigurationPoste.fichierAbsent(chemin));
    }
    final Object? contenu;
    try {
      contenu = jsonDecode(await fichier.readAsString());
    } on Object {
      return MotDePasseAbsent(
        TextesConfigurationPoste.fichierIllisible(chemin),
      );
    }
    final valeur = contenu is Map<String, Object?>
        ? contenu[cleMotDePasseSmtp]
        : null;
    if (valeur is! String || valeur.isEmpty) {
      return MotDePasseAbsent(TextesConfigurationPoste.cleAbsente(chemin));
    }
    return MotDePasseLu(valeur);
  }

  /// L'appairage du poste, relu à CHAQUE appel — `null` quand le poste n'est
  /// pas appairé (fichier absent ou illisible, clé manquante ou vide).
  Future<AppairagePoste?> appairage() async {
    final contenu = await _lireObjet(await _chemin());
    return contenu == null ? null : AppairagePoste.depuisJson(contenu);
  }
}

/// Le contenu de `poste.json`, ou `null` s'il est absent ou n'est pas un objet
/// JSON.
Map<String, Object?>? _lireObjetSync(String chemin) {
  try {
    final contenu = jsonDecode(File(chemin).readAsStringSync());
    return contenu is Map<String, Object?> ? contenu : null;
  } on Object {
    return null;
  }
}

/// La même lecture, asynchrone.
Future<Map<String, Object?>?> _lireObjet(String chemin) async {
  final fichier = File(chemin);
  if (!fichier.existsSync()) return null;
  try {
    final contenu = jsonDecode(await fichier.readAsString());
    return contenu is Map<String, Object?> ? contenu : null;
  } on Object {
    return null;
  }
}

/// Les clés d'appairage de `poste.json`.
abstract final class ClesAppairage {
  static const posteId = 'poste_id';
  static const jetonApi = 'jeton_api';
  static const serveur = 'serveur';
  static const appaireLe = 'appaire_le';
  static const compte = 'compte';

  /// `{ "code": 401|403, "le": "<ISO>" }` — posé par le moteur d'envoi quand
  /// le serveur refuse le jeton (401) ou le poste (403) : plus aucun envoi
  /// avant un nouvel appairage (ou un « Tester la connexion » réussi).
  static const refus = 'appairage_refuse';

  static const toutes = {posteId, jetonApi, serveur, appaireLe, compte, refus};
}

/// Le refus du jeton ou du poste par le serveur, consigné.
final class RefusAppairage {
  const RefusAppairage({required this.codeHttp, required this.le});

  final int codeHttp;
  final DateTime le;
}

/// L'appairage du poste. Son `toString` ne révèle pas le jeton.
final class AppairagePoste {
  const AppairagePoste({
    required this.posteId,
    required this.jetonApi,
    required this.serveur,
    required this.appaireLe,
    required this.compte,
    this.refus,
  });

  /// Le nom du poste — le nom du jeton au serveur, et le `poste_id` de
  /// chaque lot (`PosteDuJeton::concorde`).
  final String posteId;
  final String jetonApi;

  /// L'adresse de l'API (`…/api/v1`), celle du build qui a appairé.
  final String serveur;
  final DateTime appaireLe;

  /// L'identifiant du compte serveur qui a appairé.
  final String compte;

  /// Non nul : le serveur a refusé ce jeton ou ce poste.
  final RefusAppairage? refus;

  static AppairagePoste? depuisJson(Map<String, Object?> json) {
    String? texte(String cle) {
      final v = json[cle];
      return v is String && v.trim().isNotEmpty ? v : null;
    }

    final posteId = texte(ClesAppairage.posteId);
    final jeton = texte(ClesAppairage.jetonApi);
    final serveur = texte(ClesAppairage.serveur);
    if (posteId == null || jeton == null || serveur == null) return null;
    final refus = json[ClesAppairage.refus];
    RefusAppairage? refusLu;
    if (refus is Map<String, Object?> && refus['code'] is int) {
      refusLu = RefusAppairage(
        codeHttp: refus['code']! as int,
        le:
            DateTime.tryParse('${refus['le']}') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
    }
    return AppairagePoste(
      posteId: posteId,
      jetonApi: jeton,
      serveur: serveur,
      appaireLe:
          DateTime.tryParse(texte(ClesAppairage.appaireLe) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      compte: texte(ClesAppairage.compte) ?? '',
      refus: refusLu,
    );
  }

  Map<String, Object?> versJson() => {
    ClesAppairage.posteId: posteId,
    ClesAppairage.jetonApi: jetonApi,
    ClesAppairage.serveur: serveur,
    ClesAppairage.appaireLe: appaireLe.toUtc().toIso8601String(),
    ClesAppairage.compte: compte,
  };

  @override
  String toString() =>
      'AppairagePoste($posteId @ $serveur, compte $compte, jeton ***)';
}

/// `poste.json` existe mais n'est pas un objet JSON : l'écrire l'écraserait,
/// mot de passe SMTP compris. L'écran le DIT, le fichier n'est pas touché.
final class ConfigurationPosteIllisible implements Exception {
  const ConfigurationPosteIllisible(this.chemin);

  final String chemin;

  @override
  String toString() =>
      'Le fichier $chemin est illisible (JSON attendu) : il n’a pas été '
      'modifié. Corrigez-le ou supprimez-le, puis recommencez.';
}

/// Écrit les clés d'APPAIRAGE de `poste.json` — et elles seules : le mot de
/// passe SMTP et toute autre clé posée à la main sont conservés.
///
/// L'écriture est ATOMIQUE : le contenu complet part dans `poste.json.tmp`
/// (même dossier, donc même volume), vidé sur le disque, puis renommé sur
/// `poste.json` — `File.rename` remplace la cible, sous Windows comme
/// ailleurs. Les écritures d'un même processus sont mises en file.
class EcrivainConfigurationPoste {
  EcrivainConfigurationPoste({Future<String> Function()? chemin})
    : _chemin = chemin ?? cheminConfigurationPoste;

  final Future<String> Function() _chemin;

  /// Enregistre un appairage NEUF (un éventuel refus antérieur est effacé).
  Future<void> enregistrerAppairage(AppairagePoste appairage) =>
      _modifier((contenu) {
        contenu
          ..remove(ClesAppairage.refus)
          ..addAll(appairage.versJson());
      });

  /// Retire l'appairage (« Dissocier ») ; le reste du fichier demeure.
  Future<void> retirerAppairage() => _modifier((contenu) {
    for (final cle in ClesAppairage.toutes) {
      contenu.remove(cle);
    }
  });

  /// Consigne le refus du jeton (401) ou du poste (403) par le serveur.
  Future<void> consignerRefus(int codeHttp, DateTime le) =>
      _modifier((contenu) {
        if (contenu[ClesAppairage.jetonApi] == null) return;
        contenu[ClesAppairage.refus] = {
          'code': codeHttp,
          'le': le.toUtc().toIso8601String(),
        };
      });

  /// Efface le refus consigné (le serveur a de nouveau accepté le jeton).
  Future<void> effacerRefus() =>
      _modifier((contenu) => contenu.remove(ClesAppairage.refus));

  /// Lire, changer, écrire : en entrées-sorties SYNCHRONES, donc sans
  /// entrelacement possible avec une autre écriture du même processus (le
  /// fichier fait quelques centaines d'octets).
  Future<void> _modifier(void Function(Map<String, Object?>) changer) async {
    final chemin = await _chemin();
    final fichier = File(chemin);
    final Map<String, Object?> contenu;
    if (fichier.existsSync()) {
      final lu = _lireObjetSync(chemin);
      if (lu == null) throw ConfigurationPosteIllisible(chemin);
      contenu = Map.of(lu);
    } else {
      contenu = <String, Object?>{};
    }
    changer(contenu);
    fichier.parent.createSync(recursive: true);
    File('$chemin.tmp')
      ..writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(contenu),
        flush: true,
      )
      ..renameSync(chemin);
  }
}

/// Le chemin de `poste.json` sur CE poste — voir l'en-tête.
Future<String> cheminConfigurationPoste() async {
  final appData = Platform.environment['APPDATA'];
  if (Platform.isWindows && appData != null && appData.isNotEmpty) {
    return p.join(appData, 'TATACORA', 'poste.json');
  }
  final dossier = await getApplicationSupportDirectory();
  return p.join(dossier.path, 'poste.json');
}
