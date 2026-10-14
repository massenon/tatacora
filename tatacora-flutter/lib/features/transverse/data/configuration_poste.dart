/// La configuration LOCALE du poste, hors de la base et hors du dossier
/// d'installation — Lot J2 partie 2, directive du Product Owner du 14/10/2026.
///
/// ## Ce qu'elle porte, et pourquoi pas ailleurs
///
/// Le MOT DE PASSE SMTP de l'envoi à l'éditeur, et rien d'autre aujourd'hui.
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
/// { "smtp_mot_de_passe": "..." }
/// ```
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
