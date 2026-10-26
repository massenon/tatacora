/// L'envoi RÉEL des e-mails de la boîte (schéma v39) — par SMTP, DIRECTEMENT
/// depuis le poste (décision du PO du 26/10/2026 : « l'envoi réel d'e-mails
/// DOIT ÊTRE IMPLÉMENTÉ EN POSTE ET WEB »).
///
/// Même contrat que `ServiceMessagesEditeur` (le message à l'éditeur), pour la
/// boîte des e-mails de notification : l'e-mail est ÉCRIT d'abord
/// (`BoiteEnvoiEmailsDao.mettreEnFile`), l'envoi est ENSUITE tenté, et
/// `envoye` n'est écrit que si le relais SMTP a accepté le message. Un échec
/// est noté (tentatives, cause, date) et AVALÉ : l'e-mail reste, la relance le
/// reprendra avec un repli exponentiel (`PolitiqueRelanceEmail`).
///
/// ## L'interrupteur « Synchronisation activée » ne le coupe PAS
///
/// L'envoi SMTP n'est pas de la synchronisation avec le serveur TATACORA : le
/// poste parle directement au relais SMTP configuré dans Paramètres → Email.
/// Synchronisation désactivée, un e-mail part quand même (le réseau suffit) ;
/// c'est voulu, documenté (`docs/AUDIT_POSTE_AUTONOME.md` §1) et testé. Les
/// seuls interrupteurs de l'envoi sont l'absence de configuration et le mode
/// démonstration.
///
/// ## Jamais deux fois le même e-mail
///
/// Le geste de l'écran et la relance périodique passent par la MÊME instance
/// (`serviceBoiteEnvoiEmailsProvider`) : un e-mail déjà en vol n'est pas
/// renvoyé par l'autre chemin ([_enVol]) ; l'état est relu avant la tentative
/// (un e-mail déjà `envoye` n'est jamais renvoyé) ; et la clé d'idempotence est
/// UNIQUE au schéma.
///
/// ## Le mot de passe
///
/// Relu de `poste.json` à CHAQUE envoi (`LecteurSmtp`), jamais écrit en base ni
/// dans un journal ; toute cause d'échec est expurgée du secret avant d'être
/// écrite.
library;

import 'dart:async';

import 'package:mailer/mailer.dart';

import '../domain/boite_envoi_emails.dart';
import 'boite_envoi_emails_dao.dart';
import 'envoi_messages_editeur.dart';

/// L'issue d'une tentative.
enum IssueEnvoiEmail {
  /// Accepté par le relais SMTP.
  envoye,

  /// Tenté, refusé ou injoignable : reste en boîte.
  echoue,

  /// Pas tenté : la configuration du poste est incomplète.
  nonConfigure,

  /// Déjà en vol par l'autre chemin, ou déjà parti.
  dejaEnCours,
}

typedef ResultatEnvoiEmail = ({IssueEnvoiEmail issue, String? raison});

typedef BilanRelanceEmails = ({int envoyes, int restants});

/// L'unique expéditeur de la boîte d'envoi des e-mails.
class ServiceBoiteEnvoiEmails {
  ServiceBoiteEnvoiEmails({
    required this._dao,
    required this._lecteur,
    TransportSmtp? transport,
    DateTime Function()? maintenant,
    this.auSucces,
  }) : _transport = transport ?? transportSmtpParDefaut,
       _maintenant = maintenant ?? DateTime.now;

  final BoiteEnvoiEmailsDao _dao;
  final LecteurSmtp _lecteur;
  final TransportSmtp _transport;
  final DateTime Function() _maintenant;

  /// Appelé DANS la même transaction que l'écriture `envoye`, après l'accusé
  /// SMTP : l'objet d'origine (le message de notification) passe « Envoyé par
  /// le système » EN MÊME TEMPS que la boîte, ou aucun des deux.
  final Future<void> Function(EmailEnBoite email, DateTime envoyeLe)? auSucces;

  final Set<String> _enVol = {};
  bool _relanceEnCours = false;

  /// Tente d'envoyer l'e-mail [id] tout de suite (le geste de l'écran).
  Future<ResultatEnvoiEmail> envoyer(String id) async {
    final configuration = await _lecteur.lire();
    if (configuration is String) {
      await _dao.marquerNonTente(id, erreur: configuration);
      return (issue: IssueEnvoiEmail.nonConfigure, raison: configuration);
    }
    return _tenter(id, configuration as ConfigurationSmtp);
  }

  /// « Renvoyer » : remet l'e-mail [id] en file (s'il était en échec) et le
  /// tente aussitôt.
  Future<ResultatEnvoiEmail> renvoyer(String id) async {
    await _dao.remettreEnFile(id: id);
    return envoyer(id);
  }

  /// Relance les e-mails `en_attente`, le plus ancien d'abord. Sans [forcer],
  /// seuls ceux dont le délai est écoulé partent ; avec [forcer], les e-mails
  /// en `echec` repassent en file et tous sont tentés. Une relance déjà en
  /// cours rend `null` : deux relances simultanées enverraient deux fois.
  Future<BilanRelanceEmails?> relancer({bool forcer = false}) async {
    if (_relanceEnCours) return null;
    _relanceEnCours = true;
    try {
      if (forcer) await _dao.remettreEnFile();
      final file = await _dao.enAttente();
      if (file.isEmpty) return (envoyes: 0, restants: 0);

      final maintenant = _maintenant();
      final dus = [
        for (final e in file)
          if (forcer || PolitiqueRelanceEmail.estDu(e, maintenant)) e,
      ];
      if (dus.isEmpty) return (envoyes: 0, restants: file.length);

      final configuration = await _lecteur.lire();
      if (configuration is String) {
        for (final e in dus) {
          await _dao.marquerNonTente(e.id, erreur: configuration);
        }
        return (envoyes: 0, restants: file.length);
      }

      var envoyes = 0;
      for (final e in dus) {
        final resultat = await _tenter(
          e.id,
          configuration as ConfigurationSmtp,
        );
        if (resultat.issue == IssueEnvoiEmail.envoye) {
          envoyes++;
        } else if (resultat.issue == IssueEnvoiEmail.echoue) {
          // Le premier échec arrête la relance : hors connexion, chaque
          // e-mail suivant attendrait son propre délai pour rien.
          break;
        }
      }
      return (envoyes: envoyes, restants: file.length - envoyes);
    } finally {
      _relanceEnCours = false;
    }
  }

  Future<ResultatEnvoiEmail> _tenter(
    String id,
    ConfigurationSmtp configuration,
  ) async {
    if (!_enVol.add(id)) {
      return (issue: IssueEnvoiEmail.dejaEnCours, raison: null);
    }
    try {
      // Relu : l'autre chemin a pu l'envoyer entre la lecture de la boîte et
      // cette tentative.
      final courant = await _dao.parId(id);
      if (courant == null || courant.statut != StatutEmail.enAttente) {
        return (issue: IssueEnvoiEmail.dejaEnCours, raison: null);
      }
      final courriel = Message()
        ..from = Address(configuration.utilisateur, nomExpediteurEditeur)
        ..recipients = [courant.adresse]
        ..subject = courant.objet
        ..text = courant.corps;
      try {
        await _transport(
          courriel,
          configuration.serveur,
          PolitiqueRelanceEmail.delaiEnvoi,
        );
      } on Object catch (erreur) {
        final raison = expurgerSecret(
          raisonEchecSmtp(erreur),
          configuration.motDePasse,
        );
        await _dao.marquerTentativeEchouee(
          id,
          erreur: raison,
          maintenant: _maintenant(),
        );
        return (issue: IssueEnvoiEmail.echoue, raison: raison);
      }
      // L'accusé SMTP est là : la boîte ET l'objet d'origine, ensemble.
      final quand = _maintenant();
      await _dao.transaction(() async {
        await _dao.marquerEnvoye(
          id,
          maintenant: quand,
          tentatives: courant.tentatives + 1,
        );
        await auSucces?.call(courant, quand);
      });
      return (issue: IssueEnvoiEmail.envoye, raison: null);
    } finally {
      _enVol.remove(id);
    }
  }
}
