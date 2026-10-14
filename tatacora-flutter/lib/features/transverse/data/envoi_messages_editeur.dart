/// L'envoi RÉEL des messages à l'éditeur, par SMTP — la SEULE action réseau
/// du poste (directive du Product Owner du 14/10/2026, Lot J2 partie 2).
///
/// Réplique de `MessageEditeurService` (serveur) : le message est ÉCRIT
/// d'abord (`MessagesEditeurDao.enregistrer`, `en_attente`), l'envoi est
/// ENSUITE tenté, et `envoye` n'est écrit que si le serveur SMTP a accepté le
/// message. Un échec est noté et AVALÉ : le message reste en file, la relance
/// le reprendra (`contact-editeur:rejouer` au serveur, `relancer` ici).
///
/// ## La configuration, relue à chaque envoi
///
/// * Serveur, port, sécurité, utilisateur : les quatre clés de l'onglet
///   « Email (SMTP) » de Paramètres (`email_smtp_hote`, `email_smtp_port`,
///   `email_smtp_securite`, `email_smtp_utilisateur`), lues dans
///   `parametres_systeme_local` — comme `ConfigurationMailService::appliquer`.
///   `tls` = STARTTLS (port 587 par défaut) ; `ssl` = SSL implicite (465 par
///   défaut) ; `aucune` = STARTTLS si offert, clair sinon.
/// * Mot de passe : `poste.json`, hors base (`configuration_poste.dart`).
/// * Expéditeur : l'utilisateur SMTP, nom affiché [nomExpediteurEditeur].
/// * Destinataire : [adresseSupportEditeur].
///
/// Une configuration incomplète n'est PAS une tentative : rien ne part sur le
/// réseau, `tentatives` ne bouge pas, la raison est notée et dite à l'écran.
///
/// ## Jamais deux fois le même message
///
/// Le geste de l'écran et la relance périodique passent par la MÊME instance
/// (`serviceMessagesEditeurProvider`) : un message déjà en vol n'est pas
/// renvoyé par l'autre chemin ([_enVol]).
library;

import 'dart:async';
import 'dart:io';

import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

import '../../../core/config/environnement.dart';
import '../../parametres/data/parametres_dao.dart';
import '../domain/messages_editeur.dart';
import 'configuration_poste.dart';
import 'messages_editeur_dao.dart';

/// Le support de l'éditeur — `config/contact_editeur.php` du serveur
/// (`SUPPORT_MAIL`, défaut `rarhodes06@gmail.com`, décision du PO du
/// 14/10/2026). Le serveur le lit de son `.env` ; le poste n'en a pas, la
/// valeur par défaut du serveur est donc reprise ici, en un seul endroit.
const String adresseSupportEditeur = 'rarhodes06@gmail.com';

/// Le nom affiché de l'expéditeur — directive du PO du 14/10/2026
/// (`MAIL_FROM_NAME` de l'exploitation).
const String nomExpediteurEditeur = 'LogiRestock - TATACORA AFRIQUE';

/// Les clés SMTP de Paramètres — `ConfigurationMailService::CLE_SMTP_*`.
abstract final class ClesSmtp {
  static const String hote = 'email_smtp_hote';
  static const String port = 'email_smtp_port';
  static const String securite = 'email_smtp_securite';
  static const String utilisateur = 'email_smtp_utilisateur';
}

/// L'issue d'une tentative.
enum IssueEnvoiEditeur {
  /// Accepté par le serveur SMTP.
  envoye,

  /// Tenté, refusé ou injoignable : reste en file.
  echoue,

  /// Pas tenté : la configuration du poste est incomplète.
  nonConfigure,

  /// Déjà en vol par l'autre chemin (geste ou relance).
  dejaEnCours,
}

/// Le résultat d'un envoi, avec la raison d'un échec.
typedef ResultatEnvoiEditeur = ({IssueEnvoiEditeur issue, String? raison});

/// Le bilan d'une relance.
typedef BilanRelanceEditeur = ({int envoyes, int restants});

/// Les phrases des échecs — elles vont en `derniere_erreur` et à l'écran.
abstract final class TextesEnvoiEditeur {
  static const String demo =
      'Mode démonstration : aucun message ne part de ce poste.';
  static const String hoteAbsent =
      'Serveur SMTP non renseigné (Paramètres, onglet « Email (SMTP) »).';
  static const String utilisateurAbsent =
      'Utilisateur SMTP non renseigné (Paramètres, onglet « Email (SMTP) »).';
  static const String identifiantsRefuses =
      'Le serveur SMTP a refusé les identifiants (utilisateur ou mot de passe '
      'SMTP).';
  static String injoignable(String detail) =>
      'Serveur SMTP injoignable (connexion absente ?) : $detail';
  static const String delaiDepasse =
      'Le serveur SMTP n’a pas répondu à temps (connexion absente ?).';
  static String refuse(String detail) =>
      'Envoi refusé par le serveur SMTP : '
      '$detail';
}

/// La configuration SMTP complète d'un envoi. Le mot de passe n'apparaît
/// dans aucun `toString`.
final class ConfigurationSmtp {
  const ConfigurationSmtp({
    required this.hote,
    required this.port,
    required this.ssl,
    required this.clairAutorise,
    required this.utilisateur,
    required this.motDePasse,
  });

  final String hote;
  final int port;
  final bool ssl;
  final bool clairAutorise;
  final String utilisateur;
  final String motDePasse;

  SmtpServer get serveur => SmtpServer(
    hote,
    port: port,
    ssl: ssl,
    allowInsecure: clairAutorise,
    username: utilisateur,
    password: motDePasse,
  );

  @override
  String toString() => 'ConfigurationSmtp($hote:$port, $utilisateur, ***)';
}

/// Le transport : `mailer.send` en production, un double en test.
typedef TransportSmtp =
    Future<void> Function(Message message, SmtpServer serveur, Duration delai);

Future<void> _transportMailer(
  Message message,
  SmtpServer serveur,
  Duration delai,
) async {
  // Le délai borne CHAQUE attente de `mailer` (connexion, lecture) ; le
  // second borne l'ensemble, pour qu'un serveur qui répond goutte à goutte ne
  // retienne pas la file.
  await send(
    message,
    serveur,
    timeout: delai,
  ).timeout(delai + const Duration(seconds: 5));
}

/// L'unique expéditeur des messages à l'éditeur.
class ServiceMessagesEditeur {
  ServiceMessagesEditeur({
    required this._dao,
    required this._parametres,
    LecteurConfigurationPoste? configuration,
    TransportSmtp? transport,
    DateTime Function()? maintenant,
    bool? envoiAutorise,
  }) : _configuration = configuration ?? LecteurConfigurationPoste(),
       _transport = transport ?? _transportMailer,
       _maintenant = maintenant ?? DateTime.now,
       _envoiAutorise =
           envoiAutorise ?? !Environnement.actuel.estHorsLigneIntegral;

  final MessagesEditeurDao _dao;
  final ParametresDao _parametres;
  final LecteurConfigurationPoste _configuration;
  final TransportSmtp _transport;
  final DateTime Function() _maintenant;

  /// Faux en démonstration (`main_demo.dart`) : ce flavor n'émet aucun appel
  /// réseau, le message reste en file avec sa raison.
  final bool _envoiAutorise;

  final Set<String> _enVol = {};
  bool _relanceEnCours = false;

  /// Écrit le message (PREMIÈRE écriture du geste), sans rien envoyer.
  Future<MessageEditeur> enregistrer(
    SaisieMessageEditeur saisie, {
    required String? auteurId,
    required String? auteurLogin,
  }) => _dao.enregistrer(
    saisie,
    auteurId: auteurId,
    auteurLogin: auteurLogin,
    poste: _nomDuPoste(),
    maintenant: _maintenant(),
  );

  /// Tente d'envoyer [message] tout de suite (le geste de l'écran).
  Future<ResultatEnvoiEditeur> envoyer(MessageEditeur message) async {
    final configuration = await _lireConfiguration();
    if (configuration is String) {
      await _dao.marquerNonTente(message.id, erreur: configuration);
      return (issue: IssueEnvoiEditeur.nonConfigure, raison: configuration);
    }
    return _tenter(message, configuration as ConfigurationSmtp);
  }

  /// Relance les messages `en_attente`, le plus ancien d'abord. Sans
  /// [forcer], seuls ceux dont le délai est écoulé partent
  /// (`PolitiqueRelanceEditeur`) ; avec [forcer] (« Renvoyer maintenant »),
  /// les messages en `echec` repassent en file et tous sont tentés.
  ///
  /// Une relance déjà en cours rend `null` : deux relances simultanées
  /// enverraient deux fois.
  Future<BilanRelanceEditeur?> relancer({bool forcer = false}) async {
    if (_relanceEnCours) return null;
    _relanceEnCours = true;
    try {
      if (forcer) await _dao.remettreEnFile();
      final file = await _dao.enAttente();
      if (file.isEmpty) return (envoyes: 0, restants: 0);

      final maintenant = _maintenant();
      final dus = [
        for (final m in file)
          if (forcer || PolitiqueRelanceEditeur.estDu(m, maintenant)) m,
      ];
      if (dus.isEmpty) return (envoyes: 0, restants: file.length);

      final configuration = await _lireConfiguration();
      if (configuration is String) {
        for (final m in dus) {
          await _dao.marquerNonTente(m.id, erreur: configuration);
        }
        return (envoyes: 0, restants: file.length);
      }

      var envoyes = 0;
      for (final m in dus) {
        final resultat = await _tenter(m, configuration as ConfigurationSmtp);
        if (resultat.issue == IssueEnvoiEditeur.envoye) {
          envoyes++;
        } else if (resultat.issue == IssueEnvoiEditeur.echoue) {
          // Le premier échec arrête la relance : hors connexion, chaque
          // message suivant attendrait son propre délai pour rien. Les
          // suivants n'ont pas été tentés — leur compteur ne bouge pas.
          break;
        }
      }
      return (envoyes: envoyes, restants: file.length - envoyes);
    } finally {
      _relanceEnCours = false;
    }
  }

  Future<ResultatEnvoiEditeur> _tenter(
    MessageEditeur message,
    ConfigurationSmtp configuration,
  ) async {
    if (!_enVol.add(message.id)) {
      return (issue: IssueEnvoiEditeur.dejaEnCours, raison: null);
    }
    try {
      // Relu : l'autre chemin a pu l'envoyer entre la lecture de la file et
      // cette tentative.
      final courant = await _dao.parId(message.id);
      if (courant == null || courant.statut == StatutMessageEditeur.envoye) {
        return (issue: IssueEnvoiEditeur.dejaEnCours, raison: null);
      }
      final courriel = Message()
        ..from = Address(configuration.utilisateur, nomExpediteurEditeur)
        ..recipients = [adresseSupportEditeur]
        ..subject = objetCourrielEditeur(courant.sujet)
        ..text = corpsCourrielEditeur(courant);
      try {
        await _transport(
          courriel,
          configuration.serveur,
          PolitiqueRelanceEditeur.delaiEnvoi,
        );
      } on Object catch (erreur) {
        final raison = _expurger(_raison(erreur), configuration.motDePasse);
        await _dao.marquerTentativeEchouee(
          message.id,
          erreur: raison,
          maintenant: _maintenant(),
        );
        return (issue: IssueEnvoiEditeur.echoue, raison: raison);
      }
      await _dao.marquerEnvoye(message.id, maintenant: _maintenant());
      return (issue: IssueEnvoiEditeur.envoye, raison: null);
    } finally {
      _enVol.remove(message.id);
    }
  }

  /// La configuration complète, ou la RAISON de son absence (une chaîne).
  Future<Object> _lireConfiguration() async {
    if (!_envoiAutorise) return TextesEnvoiEditeur.demo;
    final valeurs = await _parametres.lireTout();
    final hote = valeurs[ClesSmtp.hote]?.trim() ?? '';
    if (hote.isEmpty) return TextesEnvoiEditeur.hoteAbsent;
    final utilisateur = valeurs[ClesSmtp.utilisateur]?.trim() ?? '';
    if (utilisateur.isEmpty) return TextesEnvoiEditeur.utilisateurAbsent;

    final lecture = await _configuration.motDePasseSmtp();
    final String motDePasse;
    switch (lecture) {
      case MotDePasseAbsent(:final raison):
        return raison;
      case MotDePasseLu(:final valeur):
        motDePasse = valeur;
    }

    final securite = valeurs[ClesSmtp.securite]?.trim().toLowerCase() ?? 'tls';
    final ssl = securite == 'ssl';
    final port = int.tryParse(valeurs[ClesSmtp.port]?.trim() ?? '');
    return ConfigurationSmtp(
      hote: hote,
      port: port ?? (ssl ? 465 : 587),
      ssl: ssl,
      clairAutorise: securite == 'aucune',
      utilisateur: utilisateur,
      motDePasse: motDePasse,
    );
  }

  static String _raison(Object erreur) => switch (erreur) {
    SmtpClientAuthenticationException() =>
      TextesEnvoiEditeur.identifiantsRefuses,
    TimeoutException() => TextesEnvoiEditeur.delaiDepasse,
    SocketException(:final message) => TextesEnvoiEditeur.injoignable(message),
    MailerException(:final message) => TextesEnvoiEditeur.refuse(message),
    _ => TextesEnvoiEditeur.refuse(erreur.toString()),
  };

  /// Un message d'erreur ne doit jamais emporter le secret en base.
  static String _expurger(String texte, String secret) =>
      secret.isEmpty ? texte : texte.replaceAll(secret, '***');

  static String? _nomDuPoste() {
    try {
      return Platform.localHostname;
    } on Object {
      return null;
    }
  }
}
