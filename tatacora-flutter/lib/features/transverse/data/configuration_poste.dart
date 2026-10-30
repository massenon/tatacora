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

/// Quand et par qui le mot de passe SMTP a été saisi à l'écran (19/10/2026) —
/// l'écran ne montre que cet ÉTAT, jamais la valeur.
const String cleMotDePasseSmtpLe = 'smtp_mot_de_passe_le';
const String cleMotDePasseSmtpPar = 'smtp_mot_de_passe_par';

/// L'état du mot de passe SMTP du poste, sans sa valeur.
final class EtatMotDePasseSmtp {
  const EtatMotDePasseSmtp({required this.renseigne, this.le, this.par});

  final bool renseigne;

  /// `null` : posé à la main dans le fichier, ou jamais saisi.
  final DateTime? le;
  final String? par;
}

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

  /// Le chemin de `poste.json` que ce lecteur lit — les captures d'écran des
  /// signalements se rangent à côté.
  Future<String> Function() get chemin => _chemin;

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

  /// L'ÉTAT du mot de passe SMTP — jamais sa valeur.
  Future<EtatMotDePasseSmtp> etatMotDePasseSmtp() async {
    final contenu = await _lireObjet(await _chemin());
    final valeur = contenu?[cleMotDePasseSmtp];
    if (valeur is! String || valeur.isEmpty) {
      return const EtatMotDePasseSmtp(renseigne: false);
    }
    final par = contenu?[cleMotDePasseSmtpPar];
    return EtatMotDePasseSmtp(
      renseigne: true,
      le: DateTime.tryParse('${contenu?[cleMotDePasseSmtpLe]}'),
      par: par is String && par.isNotEmpty ? par : null,
    );
  }

  /// L'appairage du poste, relu à CHAQUE appel — `null` quand le poste n'est
  /// pas appairé (fichier absent ou illisible, clé manquante ou vide).
  Future<AppairagePoste?> appairage() async {
    final contenu = await _lireObjet(await _chemin());
    return contenu == null ? null : AppairagePoste.depuisJson(contenu);
  }

  /// L'INTERRUPTEUR « Synchronisation activée » du poste, relu à CHAQUE appel
  /// (aucun cache : une bascule vaut pour la requête qui suit). Absent ou
  /// illisible : ACTIVÉE — un poste qui n'a jamais été touché garde le
  /// comportement d'avant. Seul `false` écrit la désactive.
  Future<bool> synchronisationActivee() async {
    final contenu = await _lireObjet(await _chemin());
    return contenu?[cleSynchronisationActivee] != false;
  }

  /// L'adresse de l'API enregistrée (`serveur`), MÊME sans jeton : l'adresse
  /// choisie à l'écran vaut aussi pour un poste pas encore appairé. `null` :
  /// aucune (fichier absent, illisible ou clé vide) — le poste prend alors
  /// l'adresse du build.
  Future<String?> adresseServeur() async {
    final contenu = await _lireObjet(await _chemin());
    final v = contenu?[ClesAppairage.serveur];
    return v is String && v.trim().isNotEmpty ? v.trim() : null;
  }

  /// L'adresse a-t-elle été CHOISIE à l'écran (Paramètres → Synchronisation) ?
  /// Alors l'appairage ne se compare plus à l'adresse du build : c'est
  /// l'opérateur qui a décidé du serveur.
  Future<bool> adresseServeurChoisie() async {
    final contenu = await _lireObjet(await _chemin());
    final v = contenu?[cleServeurModifieLe];
    return v is String && v.trim().isNotEmpty;
  }

  /// La fréquence du réveil périodique, en minutes (`0` : manuelle), ou `null`
  /// quand le fichier n'en dit rien (le défaut s'applique).
  Future<int?> frequenceSynchronisationMinutes() async {
    final contenu = await _lireObjet(await _chemin());
    final v = contenu?[cleFrequenceSynchronisation];
    return v is int ? v : null;
  }

  /// Qui a désactivé la synchronisation, et quand (`null` : activée, ou
  /// désactivée avant que l'on consigne qui).
  Future<({String? par, DateTime? le})> desactivation() async {
    final contenu = await _lireObjet(await _chemin());
    final par = contenu?[cleSynchronisationDesactiveePar];
    return (
      par: par is String && par.isNotEmpty ? par : null,
      le: DateTime.tryParse('${contenu?[cleSynchronisationDesactiveeLe]}'),
    );
  }
}

/// Les clés de l'interrupteur de synchronisation dans `poste.json`. Le choix
/// est PAR POSTE (comme l'appairage) : il ne voyage pas par la synchronisation
/// (il n'aurait aucun sens qu'un autre poste éteigne celui-ci), il survit à
/// la réinitialisation de la base (`etat_synchronisation_local` est vidé),
/// et il se lit sans ouvrir la base — le moteur le relit avant chaque requête.
const String cleSynchronisationActivee = 'synchronisation_activee';
const String cleSynchronisationDesactiveeLe = 'synchronisation_desactivee_le';
const String cleSynchronisationDesactiveePar = 'synchronisation_desactivee_par';

/// L'adresse du serveur CHOISIE à l'écran (29/10/2026) : quand et par qui. La
/// clé de l'adresse elle-même est `serveur` ([ClesAppairage.serveur]) ; ces
/// deux clés disent seulement qu'elle est un CHOIX de l'opérateur, pas celle
/// qu'un appairage a recopiée du build. Jamais le jeton.
const String cleServeurModifieLe = 'serveur_modifie_le';
const String cleServeurModifiePar = 'serveur_modifie_par';

/// La fréquence du réveil périodique, en minutes (`0` : manuelle seulement).
/// Absente : 5 minutes. Par poste, comme l'interrupteur.
const String cleFrequenceSynchronisation = 'synchronisation_frequence_minutes';

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
    // Lecture SYNCHRONE : le fichier fait quelques centaines d'octets, et
    // une lecture asynchrone ne se termine pas sous l'horloge simulée d'un
    // banc de widget (l'interrupteur de synchronisation est lu partout).
    final contenu = jsonDecode(fichier.readAsStringSync());
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

/// Écrit les clés d'APPAIRAGE de `poste.json` et, depuis le 19/10/2026
/// (décision du PO : « enregistrer les configurations dans le poste »), le
/// mot de passe SMTP saisi dans Paramètres → Email (SMTP). Chaque geste ne
/// touche que SES clés : toute autre clé posée à la main est conservée.
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

  /// Retire l'appairage (« Dissocier ») ; le reste du fichier demeure. Une
  /// adresse CHOISIE à l'écran demeure aussi : dissocier le poste ne change
  /// pas de serveur.
  Future<void> retirerAppairage() => _modifier(
    (contenu) => _viderAppairage(
      contenu,
      garderServeur: contenu[cleServeurModifieLe] != null,
    ),
  );

  static void _viderAppairage(
    Map<String, Object?> contenu, {
    required bool garderServeur,
  }) {
    for (final cle in ClesAppairage.toutes) {
      if (cle == ClesAppairage.serveur && garderServeur) continue;
      contenu.remove(cle);
    }
  }

  /// Enregistre l'adresse du serveur choisie à l'écran ([urlApi] : déjà
  /// validée, `…/api/v1`), avec quand et par qui. [effacerJeton] : le jeton
  /// et le reste de l'appairage partent dans la MÊME écriture atomique.
  /// Jamais le jeton ailleurs que dans ce fichier ; la file d'envoi n'est pas
  /// concernée.
  Future<void> enregistrerAdresseServeur(
    String urlApi, {
    required String par,
    required DateTime le,
    bool effacerJeton = false,
  }) => _modifier((contenu) {
    if (effacerJeton) _viderAppairage(contenu, garderServeur: true);
    contenu
      ..[ClesAppairage.serveur] = urlApi
      ..[cleServeurModifieLe] = le.toUtc().toIso8601String()
      ..[cleServeurModifiePar] = par;
  });

  /// Enregistre la fréquence du réveil périodique ([minutes] : 0 = manuelle).
  /// Le défaut (5) retire la clé : un fichier jamais touché reste inchangé.
  Future<void> enregistrerFrequenceSynchronisation(int minutes) =>
      _modifier((contenu) {
        if (minutes == 5) {
          contenu.remove(cleFrequenceSynchronisation);
        } else {
          contenu[cleFrequenceSynchronisation] = minutes;
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

  /// Enregistre le mot de passe SMTP saisi à l'écran, avec quand et par qui.
  /// Le fichier reste dans le profil Windows de l'utilisateur, hors du dépôt
  /// et hors de la base ; la valeur n'est jamais relue par l'écran.
  Future<void> enregistrerMotDePasseSmtp(
    String valeur, {
    required String par,
    required DateTime le,
  }) {
    if (valeur.isEmpty) {
      throw ArgumentError.value('***', 'valeur', 'mot de passe vide');
    }
    return _modifier((contenu) {
      contenu
        ..[cleMotDePasseSmtp] = valeur
        ..[cleMotDePasseSmtpLe] = le.toUtc().toIso8601String()
        ..[cleMotDePasseSmtpPar] = par;
    });
  }

  /// Efface le mot de passe SMTP (et son état) ; le reste du fichier demeure.
  Future<void> effacerMotDePasseSmtp() => _modifier((contenu) {
    contenu
      ..remove(cleMotDePasseSmtp)
      ..remove(cleMotDePasseSmtpLe)
      ..remove(cleMotDePasseSmtpPar);
  });

  /// Bascule l'interrupteur « Synchronisation activée ». Désactivée : la
  /// file continue de se remplir, rien ne part ni ne descend. Le reste du
  /// fichier (appairage compris) demeure : réactiver ne demande aucun
  /// nouvel appairage.
  Future<void> enregistrerSynchronisationActivee(
    bool activee, {
    required String par,
    required DateTime le,
  }) => _modifier((contenu) {
    if (activee) {
      contenu
        ..remove(cleSynchronisationActivee)
        ..remove(cleSynchronisationDesactiveeLe)
        ..remove(cleSynchronisationDesactiveePar);
    } else {
      contenu
        ..[cleSynchronisationActivee] = false
        ..[cleSynchronisationDesactiveeLe] = le.toUtc().toIso8601String()
        ..[cleSynchronisationDesactiveePar] = par;
    }
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
  // Sous `flutter test` il n'y a pas de dossier d'application (le greffon
  // `path_provider` n'existe pas) : la demande ne se termine JAMAIS sous
  // l'horloge simulée d'un banc de widget, et tout écran qui lit
  // l'interrupteur de synchronisation resterait en « chargement ». Un fichier
  // qui n'existe pas lit « synchronisation activée, poste non appairé ».
  if (Platform.environment['FLUTTER_TEST'] == 'true') {
    return p.join(Directory.systemTemp.path, 'tatacora-banc-sans-poste.json');
  }
  final appData = Platform.environment['APPDATA'];
  if (Platform.isWindows && appData != null && appData.isNotEmpty) {
    return p.join(appData, 'TATACORA', 'poste.json');
  }
  final dossier = await getApplicationSupportDirectory();
  return p.join(dossier.path, 'poste.json');
}
