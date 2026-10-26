/// La boîte d'envoi des e-mails du poste — le domaine (schéma v39).
///
/// Tout est PUR (ni base, ni réseau) : la politique de relance se vérifie sans
/// SMTP. Voir `core/database/tables/boite_envoi_emails_tables.dart`.
library;

import 'messages_editeur.dart' show PolitiqueRelanceEditeur;

/// L'origine d'un e-mail de la boîte — registre fermé.
abstract final class SourceEmail {
  /// Un message de notification M12 de canal e-mail.
  static const String notification = 'notification';

  /// La clé d'idempotence d'un message de notification.
  static String cleNotification(String messageId) => 'notification:$messageId';
}

/// Le statut d'un e-mail de la boîte.
enum StatutEmail {
  /// Écrit sur ce poste, pas encore accepté par le relais SMTP.
  enAttente('en_attente'),

  /// Accepté par le relais SMTP — le seul statut qui dit « parti ».
  envoye('envoye'),

  /// Relances automatiques épuisées ; gardé, renvoyable à la main.
  echec('echec'),

  /// Le message d'origine a été transmis à la main ou abandonné AVANT l'envoi :
  /// le courriel ne partira jamais (aucune ligne n'est supprimée).
  annule('annule');

  const StatutEmail(this.code);

  final String code;

  /// Un code inconnu vaut [enAttente] : la lecture PRUDENTE (jamais
  /// « envoyé » sur un état qu'on n'a pas compris).
  static StatutEmail depuisCode(String? code) => switch (code) {
    'envoye' => envoye,
    'echec' => echec,
    'annule' => annule,
    _ => enAttente,
  };
}

/// Un e-mail de la boîte, pour l'écran et la relance.
final class EmailEnBoite {
  const EmailEnBoite({
    required this.id,
    required this.cleIdempotence,
    required this.source,
    required this.sourceId,
    required this.adresse,
    required this.destinataireNom,
    required this.objet,
    required this.corps,
    required this.creeLe,
    required this.statut,
    required this.tentatives,
    required this.derniereErreur,
    required this.derniereTentative,
    required this.envoyeLe,
  });

  final String id;
  final String cleIdempotence;
  final String source;
  final String? sourceId;
  final String adresse;
  final String? destinataireNom;
  final String objet;
  final String corps;
  final DateTime creeLe;
  final StatutEmail statut;
  final int tentatives;
  final String? derniereErreur;
  final DateTime? derniereTentative;
  final DateTime? envoyeLe;
}

/// Ce que l'encart de l'état de la boîte affiche — tout le poste.
typedef EtatBoiteEmails = ({
  int enAttente,
  int enEchec,
  String? derniereErreur,
  DateTime? derniereTentative,
});

/// La politique de relance : la MÊME que celle des messages à l'éditeur
/// (5 minutes, doublées jusqu'à 6 heures, 30 tentatives automatiques), pour
/// qu'un poste ne se comporte pas de deux façons devant un même relais.
abstract final class PolitiqueRelanceEmail {
  static const Duration periode = PolitiqueRelanceEditeur.periode;
  static const int tentativesMax = PolitiqueRelanceEditeur.tentativesMax;
  static const Duration delaiEnvoi = PolitiqueRelanceEditeur.delaiEnvoi;

  static Duration delaiApres(int tentatives) =>
      PolitiqueRelanceEditeur.delaiApres(tentatives);

  /// Cet e-mail peut-il être relancé à [maintenant] ?
  static bool estDu(EmailEnBoite e, DateTime maintenant) {
    if (e.statut != StatutEmail.enAttente) return false;
    final derniere = e.derniereTentative;
    if (derniere == null) return true;
    return !maintenant.isBefore(derniere.add(delaiApres(e.tentatives)));
  }
}

/// Une adresse e-mail plausible — la garde de la MISE EN BOÎTE (une adresse
/// invalide ne devient pas un envoi qui échouera mille fois). La règle du
/// serveur est plus tolérante que le RFC : un `@` entouré de texte, sans
/// espace, et un point dans le domaine.
bool estAdresseEmail(String? valeur) {
  final v = valeur?.trim() ?? '';
  if (v.isEmpty || v.contains(' ')) return false;
  final arobase = v.indexOf('@');
  if (arobase <= 0 || arobase != v.lastIndexOf('@')) return false;
  final domaine = v.substring(arobase + 1);
  return domaine.contains('.') &&
      !domaine.startsWith('.') &&
      !domaine.endsWith('.');
}
