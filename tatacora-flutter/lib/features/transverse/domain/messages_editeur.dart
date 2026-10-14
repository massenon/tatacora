/// « Contactez l'éditeur » — le domaine de la boîte d'envoi (Lot J2 partie 2,
/// directive du Product Owner du 14/10/2026 : le poste ENVOIE réellement).
///
/// Réplique de `MessageEditeurService` / `MessageEditeurMail` du serveur :
/// mêmes types (`message` / `bug`), même objet (« [TATACORA] » + sujet), même
/// corps (Type, Auteur, Module concerné, le message, les étapes). Le poste
/// ajoute au corps le nom du POSTE et la DATE de saisie : un message peut
/// partir des heures après avoir été écrit (relance), l'éditeur doit savoir
/// quand et d'où il vient.
///
/// Tout ici est PUR (aucune base, aucun réseau) : la composition du courriel
/// et la politique de relance se vérifient sans SMTP.
library;

import '../../../core/format/formats.dart';

/// `messages_editeur.type` — registre fermé.
enum TypeMessageEditeur {
  message('message'),
  bug('bug');

  const TypeMessageEditeur(this.code);

  /// La valeur stockée, celle du serveur.
  final String code;

  static TypeMessageEditeur depuisCode(String code) =>
      code == bug.code ? bug : message;
}

/// Le statut d'un envoi — voir `tables/messages_editeur_tables.dart`.
enum StatutMessageEditeur {
  /// Écrit sur ce poste, pas encore accepté par le serveur SMTP.
  enAttente('en_attente'),

  /// Accepté par le serveur SMTP (`transmis` au serveur).
  envoye('envoye'),

  /// Relances automatiques épuisées ; gardé, renvoyable à la main.
  echec('echec');

  const StatutMessageEditeur(this.code);

  final String code;

  static StatutMessageEditeur depuisCode(String code) => switch (code) {
    'envoye' => envoye,
    'echec' => echec,
    _ => enAttente,
  };
}

/// Un envoi de la boîte, pour l'écran.
final class MessageEditeur {
  const MessageEditeur({
    required this.id,
    required this.type,
    required this.sujet,
    required this.moduleConcerne,
    required this.corps,
    required this.etapes,
    required this.auteurLogin,
    required this.poste,
    required this.creeLe,
    required this.statut,
    required this.tentatives,
    required this.derniereErreur,
    required this.derniereTentative,
    required this.envoyeLe,
  });

  final String id;
  final TypeMessageEditeur type;
  final String sujet;
  final String? moduleConcerne;
  final String corps;
  final String? etapes;
  final String? auteurLogin;
  final String? poste;
  final DateTime creeLe;
  final StatutMessageEditeur statut;
  final int tentatives;
  final String? derniereErreur;
  final DateTime? derniereTentative;
  final DateTime? envoyeLe;
}

/// La saisie d'un formulaire de l'écran, avant écriture.
typedef SaisieMessageEditeur = ({
  TypeMessageEditeur type,
  String sujet,
  String? moduleConcerne,
  String corps,
  String? etapes,
});

/// Ce que l'encart « Messages en attente d'envoi » affiche — tout le poste,
/// tous comptes confondus.
typedef EtatFileEditeur = ({
  int enAttente,
  int enEchec,
  String? derniereErreur,
  DateTime? derniereTentative,
});

/// Les dix-neuf entrées du sélecteur « Module concerné » de la vue —
/// `ContactEditeur::MODULES` du serveur, à l'identique et dans l'ordre.
const List<String> modulesContactEditeur = [
  'M1 — Hébergement & Réservations',
  'M2 — Facturation',
  'M3 — Clients & Créances',
  'M4 — Restaurant',
  'M5 — Bar & Point de vente',
  'M6 — Stocks',
  'M7 — Achats & Fournisseurs',
  'M8 — Véhicules & Locations',
  'M9 — Tourisme',
  'M10 — Comptabilité SYSCOHADA',
  'M11 — Tableau de bord',
  'M12 — Notifications',
  'M13 — Personnel & Paie',
  'M14 — États & Rapports',
  'Rôles & Permissions',
  'Paramètres',
  'Import & Export',
  'Connexion / navigation générale',
  'Autre / je ne sais pas',
];

/// Les bornes de saisie du serveur (`max:255` pour l'objet, `max:4096` pour
/// les textes).
abstract final class BornesMessageEditeur {
  static const int sujet = 255;
  static const int texte = 4096;
}

/// Le sujet d'un signalement — `pwa.contact.bug_objet` (« Bug — :module »).
String sujetBug(String module) => 'Bug — $module';

/// `d/m/Y H:i` — le format de « Vos envois » de la vue
/// (`date_creation->format('d/m/Y H:i')`).
String dateHeureEditeur(DateTime d) =>
    '${formaterDate(d)} '
    '${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}';

/// L'objet du courriel — `MessageEditeurMail::envelope()`.
String objetCourrielEditeur(String sujet) => '[TATACORA] $sujet';

/// Le corps du courriel — `MessageEditeurMail::corps()`, plus le poste et la
/// date de saisie (voir l'en-tête).
String corpsCourrielEditeur(MessageEditeur m) {
  final lignes = <String>[
    'Type : ${m.type.code}',
    'Auteur : ${m.auteurLogin ?? '—'}',
    'Poste : ${m.poste ?? '—'}',
    'Date : ${dateHeureEditeur(m.creeLe)}',
    if (m.moduleConcerne != null) 'Module concerné : ${m.moduleConcerne}',
    '',
    m.corps,
  ];
  final etapes = m.etapes;
  if (etapes != null && etapes.trim().isNotEmpty) {
    lignes
      ..add('')
      ..add('Étapes pour reproduire :')
      ..add(etapes);
  }
  return lignes.join('\n');
}

/// La politique de relance des messages en attente.
///
/// * La relance tourne au démarrage du poste, puis toutes les [periode].
/// * Après la n-ième tentative échouée, le message attend
///   `min(base × 2^(n-1), plafond)` avant la suivante : 5, 10, 20, 40, 80,
///   160, 320 min, puis 6 h. Un poste hors ligne tout un week-end ne martèle pas
///   le serveur SMTP, et repart dans les 5 minutes qui suivent le retour du
///   réseau pour un message neuf.
/// * Après [tentativesMax] tentatives réelles (environ six jours), le message
///   passe à `echec` : il n'est plus relancé SEUL, mais il n'est jamais
///   supprimé, et « Renvoyer maintenant » le remet en file.
abstract final class PolitiqueRelanceEditeur {
  static const Duration periode = Duration(minutes: 5);
  static const Duration base = Duration(minutes: 5);
  static const Duration plafond = Duration(hours: 6);
  static const int tentativesMax = 30;

  /// Le délai d'attente du serveur SMTP pour UNE tentative.
  static const Duration delaiEnvoi = Duration(seconds: 20);

  /// Le délai avant la tentative suivant la [tentatives]-ième.
  static Duration delaiApres(int tentatives) {
    if (tentatives <= 0) return Duration.zero;
    var delai = base;
    for (var i = 1; i < tentatives; i++) {
      delai *= 2;
      if (delai >= plafond) return plafond;
    }
    return delai;
  }

  /// Ce message peut-il être relancé à [maintenant] ?
  static bool estDu(MessageEditeur m, DateTime maintenant) {
    if (m.statut != StatutMessageEditeur.enAttente) return false;
    final derniere = m.derniereTentative;
    if (derniere == null) return true;
    return !maintenant.isBefore(derniere.add(delaiApres(m.tentatives)));
  }
}
