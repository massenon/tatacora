@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_dao.dart';
import 'package:tatacora_flutter/features/transverse/data/boite_envoi_emails_dao.dart';
import 'package:tatacora_flutter/features/transverse/data/configuration_poste.dart';
import 'package:tatacora_flutter/features/transverse/data/envoi_boite_emails.dart';
import 'package:tatacora_flutter/features/transverse/data/envoi_messages_editeur.dart';
import 'package:tatacora_flutter/features/transverse/domain/boite_envoi_emails.dart';

import 'support/serveur_smtp_essai.dart';

/// Un transport d'essai : AUCUN réseau. Il note chaque courriel, peut lever
/// ([erreur]) ou retenir l'envoi ([retenue]) pour éprouver la concurrence.
final class TransportEssai {
  final List<Message> courriels = [];
  Exception? erreur;
  Completer<void>? retenue;

  int get appels => courriels.length;

  Future<void> call(Message m, SmtpServer s, Duration delai) async {
    courriels.add(m);
    final r = retenue;
    if (r != null) await r.future;
    final e = erreur;
    if (e != null) throw e;
  }
}

/// La boîte d'envoi des e-mails du poste (schéma v39) : écrit AVANT d'envoyer,
/// « envoyé » seulement après l'accusé SMTP, jamais deux fois, relances
/// espacées, jamais de secret en base, indifférent à l'interrupteur de
/// synchronisation — et un essai de bout en bout contre un VRAI serveur SMTP
/// sur socket locale.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const secret = 'S3cret-Gite!';
  late AppDatabase db;
  late BoiteEnvoiEmailsDao dao;
  late TransportEssai transport;
  late Directory dossier;
  late String cheminPoste;
  late DateTime horloge;
  final envoyesPour = <String>[];

  setUp(() async {
    db = AppDatabase.enMemoire();
    dao = BoiteEnvoiEmailsDao(db);
    transport = TransportEssai();
    horloge = DateTime(2026, 10, 26, 8);
    envoyesPour.clear();
    dossier = Directory.systemTemp.createTempSync('poste_json_');
    cheminPoste = '${dossier.path}/poste.json';
    File(
      cheminPoste,
    ).writeAsStringSync(jsonEncode({cleMotDePasseSmtp: secret}));
    await ParametresDao(db).ecrire({
      ClesSmtp.hote: 'mail.essai.local',
      ClesSmtp.port: '587',
      ClesSmtp.securite: 'tls',
      ClesSmtp.utilisateur: 'contact@essai.local',
    }, auteurId: null);
  });
  tearDown(() async {
    await db.close();
    dossier.deleteSync(recursive: true);
  });

  LecteurSmtp lecteur({bool envoiAutorise = true, String? chemin}) =>
      LecteurSmtp(
        parametres: ParametresDao(db),
        configuration: LecteurConfigurationPoste(
          chemin: () async => chemin ?? cheminPoste,
        ),
        envoiAutorise: envoiAutorise,
      );

  ServiceBoiteEnvoiEmails service({
    bool envoiAutorise = true,
    TransportSmtp? transportPerso,
  }) => ServiceBoiteEnvoiEmails(
    dao: dao,
    lecteur: lecteur(envoiAutorise: envoiAutorise),
    transport: transportPerso ?? transport.call,
    maintenant: () => horloge,
    auSucces: (email, quand) async => envoyesPour.add(email.id),
  );

  Future<EmailEnBoite> mettre({
    String cle = 'notification:m-1',
    String adresse = 'kora@exemple.bj',
  }) async => (await dao.mettreEnFile(
    cleIdempotence: cle,
    source: SourceEmail.notification,
    sourceId: cle,
    adresse: adresse,
    destinataireNom: 'KORA',
    objet: 'Votre séjour',
    corps: 'Bonjour KORA, arrivée demain.',
    maintenant: horloge,
  )).email;

  Future<int> lignes() async =>
      (await db
                  .customSelect(
                    'SELECT COUNT(*) AS n FROM boite_envoi_emails_local',
                  )
                  .getSingle())
              .data['n']
          as int;

  Future<EmailEnBoite> relu(String id) async => (await dao.parId(id))!;

  group('Écrit AVANT d’envoyer, jamais perdu', () {
    test('au moment de l’envoi la ligne EXISTE déjà, en_attente ; le transport '
        'lève : elle reste, tentative comptée, raison lisible', () async {
      final e = await mettre();
      expect(e.statut, StatutEmail.enAttente);
      expect(e.tentatives, 0);

      transport.erreur = const SocketException('Connexion refusée');
      final r = await service().envoyer(e.id);

      expect(r.issue, IssueEnvoiEmail.echoue);
      final apres = await relu(e.id);
      expect(apres.statut, StatutEmail.enAttente);
      expect(apres.tentatives, 1);
      expect(apres.derniereErreur, contains('injoignable'));
      expect(apres.derniereErreur, contains('Connexion refusée'));
      expect(apres.derniereTentative, horloge);
      expect(apres.envoyeLe, isNull, reason: 'jamais « envoyé » sans accusé');
      expect(envoyesPour, isEmpty);
    });

    test('un refus d’identifiants a sa phrase, sans le mot de passe', () async {
      final e = await mettre();
      transport.erreur = SmtpClientAuthenticationException(
        'Auth refused avec $secret',
      );
      await service().envoyer(e.id);

      final apres = await relu(e.id);
      expect(apres.derniereErreur, contains('refusé les identifiants'));
      expect(apres.derniereErreur, isNot(contains(secret)));
    });

    test('le délai dépassé est dit', () async {
      final e = await mettre();
      transport.erreur = TimeoutException('trop long');
      await service().envoyer(e.id);
      expect(
        (await relu(e.id)).derniereErreur,
        contains('n’a pas répondu à temps'),
      );
    });

    test('un message d’erreur qui emporte le mot de passe est EXPURGÉ avant '
        'd’être écrit', () async {
      final e = await mettre();
      transport.erreur = SmtpClientCommunicationException('Refus pour $secret');
      await service().envoyer(e.id);

      final brut = await db
          .customSelect('SELECT derniere_erreur FROM boite_envoi_emails_local')
          .getSingle();
      expect(brut.data['derniere_erreur'], isNot(contains(secret)));
      expect(brut.data['derniere_erreur'], contains('***'));
    });

    test('le succès : le courriel est celui du message, « envoyé » n’est écrit '
        'qu’APRÈS le transport, et l’objet d’origine est prévenu', () async {
      final e = await mettre();
      final statutsPendant = <StatutEmail>[];
      final s = service(
        transportPerso: (m, srv, d) async {
          statutsPendant.add((await dao.parId(e.id))!.statut);
          transport.courriels.add(m);
        },
      );

      final r = await s.envoyer(e.id);

      expect(r.issue, IssueEnvoiEmail.envoye);
      expect(statutsPendant, [
        StatutEmail.enAttente,
      ], reason: 'au moment du transport rien n’est encore « envoyé »');
      final m = transport.courriels.single;
      expect(
        [for (final a in m.recipients) a is Address ? a.mailAddress : '$a'],
        ['kora@exemple.bj'],
      );
      expect(m.subject, 'Votre séjour');
      expect(m.text, 'Bonjour KORA, arrivée demain.');
      expect((m.from as Address).mailAddress, 'contact@essai.local');
      final apres = await relu(e.id);
      expect(apres.statut, StatutEmail.envoye);
      expect(apres.envoyeLe, horloge);
      expect(apres.tentatives, 1);
      expect(apres.derniereErreur, isNull);
      expect(envoyesPour, [e.id]);
    });

    test('si l’objet d’origine ne peut pas être prévenu, RIEN n’est écrit '
        '« envoyé » (même transaction)', () async {
      final e = await mettre();
      final s = ServiceBoiteEnvoiEmails(
        dao: dao,
        lecteur: lecteur(),
        transport: transport.call,
        maintenant: () => horloge,
        auSucces: (email, quand) async => throw StateError('base verrouillée'),
      );
      await expectLater(s.envoyer(e.id), throwsStateError);
      expect((await relu(e.id)).statut, StatutEmail.enAttente);
    });
  });

  group('Jamais deux e-mails pour une même chose', () {
    test('la même clé d’idempotence : une seule ligne, la première', () async {
      final a = await dao.mettreEnFile(
        cleIdempotence: 'notification:m-9',
        source: SourceEmail.notification,
        sourceId: 'm-9',
        adresse: 'a@b.bj',
        destinataireNom: 'A',
        objet: 'O1',
        corps: 'C1',
        maintenant: horloge,
      );
      final b = await dao.mettreEnFile(
        cleIdempotence: 'notification:m-9',
        source: SourceEmail.notification,
        sourceId: 'm-9',
        adresse: 'autre@b.bj',
        destinataireNom: 'A',
        objet: 'O2',
        corps: 'C2',
        maintenant: horloge,
      );
      expect(a.cree, isTrue);
      expect(b.cree, isFalse);
      expect(b.email.id, a.email.id);
      expect(b.email.objet, 'O1');
      expect(await lignes(), 1);
    });

    test(
      'deux envois SIMULTANÉS du même e-mail : un seul courriel part',
      () async {
        final e = await mettre();
        final s = service();
        transport.retenue = Completer<void>();

        final premier = s.envoyer(e.id);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final second = await s.envoyer(e.id);
        expect(second.issue, IssueEnvoiEmail.dejaEnCours);

        transport.retenue!.complete();
        expect((await premier).issue, IssueEnvoiEmail.envoye);
        expect(transport.appels, 1);
      },
    );

    test('un e-mail déjà envoyé n’est JAMAIS renvoyé, ni par le geste ni par '
        'la relance forcée ni par « Renvoyer »', () async {
      final e = await mettre();
      final s = service();
      await s.envoyer(e.id);
      expect(transport.appels, 1);

      expect((await s.envoyer(e.id)).issue, IssueEnvoiEmail.dejaEnCours);
      expect((await s.renvoyer(e.id)).issue, IssueEnvoiEmail.dejaEnCours);
      await s.relancer(forcer: true);
      expect(transport.appels, 1);
      expect((await relu(e.id)).statut, StatutEmail.envoye);
    });

    test('deux relances simultanées : la seconde rend null', () async {
      await mettre();
      final s = service();
      transport.retenue = Completer<void>();
      final premiere = s.relancer();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await s.relancer(), isNull);
      transport.retenue!.complete();
      await premiere;
      expect(transport.appels, 1);
    });

    test(
      'un e-mail ANNULÉ (message transmis ou abandonné) ne part jamais',
      () async {
        final e = await mettre();
        await dao.annulerPourSource(
          SourceEmail.notification,
          'notification:m-1',
        );
        final s = service();
        expect((await s.envoyer(e.id)).issue, IssueEnvoiEmail.dejaEnCours);
        await s.relancer(forcer: true);
        expect(transport.appels, 0);
        expect((await relu(e.id)).statut, StatutEmail.annule);
      },
    );

    test('annuler ne touche PAS un e-mail déjà envoyé', () async {
      final e = await mettre();
      await service().envoyer(e.id);
      await dao.annulerPourSource(SourceEmail.notification, 'notification:m-1');
      expect((await relu(e.id)).statut, StatutEmail.envoye);
    });
  });

  group('Pas de configuration : rien ne part, la raison est dite', () {
    test(
      'serveur SMTP non renseigné : pas tenté, tentatives inchangées',
      () async {
        await ParametresDao(db).ecrire({ClesSmtp.hote: ''}, auteurId: null);
        final e = await mettre();
        final r = await service().envoyer(e.id);

        expect(r.issue, IssueEnvoiEmail.nonConfigure);
        expect(r.raison, TextesEnvoiEditeur.hoteAbsent);
        expect(transport.appels, 0);
        final apres = await relu(e.id);
        expect(apres.tentatives, 0, reason: 'aucune connexion n’a eu lieu');
        expect(apres.derniereErreur, TextesEnvoiEditeur.hoteAbsent);
        expect(apres.statut, StatutEmail.enAttente);
      },
    );

    test('mot de passe absent de poste.json : la raison du poste', () async {
      File(cheminPoste).writeAsStringSync('{}');
      final e = await mettre();
      final r = await service().envoyer(e.id);
      expect(r.issue, IssueEnvoiEmail.nonConfigure);
      expect(r.raison, contains('Mot de passe SMTP non configuré'));
      expect(transport.appels, 0);
    });

    test('la démonstration n’émet rien', () async {
      final e = await mettre();
      final r = await service(envoiAutorise: false).envoyer(e.id);
      expect(r.issue, IssueEnvoiEmail.nonConfigure);
      expect(r.raison, TextesEnvoiEditeur.demo);
      expect(transport.appels, 0);
    });

    test(
      'la configuration revient : la relance envoie ce qui attendait',
      () async {
        File(cheminPoste).writeAsStringSync('{}');
        final e = await mettre();
        final s = service();
        await s.relancer();
        expect(transport.appels, 0);

        File(
          cheminPoste,
        ).writeAsStringSync(jsonEncode({cleMotDePasseSmtp: secret}));
        final bilan = await s.relancer();
        expect(bilan, (envoyes: 1, restants: 0));
        expect((await relu(e.id)).statut, StatutEmail.envoye);
      },
    );
  });

  group('Relances espacées, plafond, « Renvoyer »', () {
    test('après un échec la relance ATTEND son délai, puis réessaie', () async {
      final e = await mettre();
      final s = service();
      transport.erreur = const SocketException('hors ligne');
      await s.relancer();
      expect(transport.appels, 1);

      horloge = horloge.add(const Duration(minutes: 1));
      await s.relancer();
      expect(transport.appels, 1, reason: 'le délai de 5 min n’est pas écoulé');

      horloge = horloge.add(PolitiqueRelanceEmail.delaiApres(1));
      transport.erreur = null;
      final bilan = await s.relancer();
      expect(transport.appels, 2);
      expect(bilan, (envoyes: 1, restants: 0));
      expect((await relu(e.id)).statut, StatutEmail.envoye);
    });

    test('le délai double jusqu’au plafond de six heures', () {
      expect(PolitiqueRelanceEmail.delaiApres(0), Duration.zero);
      expect(PolitiqueRelanceEmail.delaiApres(1), const Duration(minutes: 5));
      expect(PolitiqueRelanceEmail.delaiApres(2), const Duration(minutes: 10));
      expect(PolitiqueRelanceEmail.delaiApres(3), const Duration(minutes: 20));
      expect(PolitiqueRelanceEmail.delaiApres(40), const Duration(hours: 6));
    });

    test('au plafond de tentatives l’e-mail passe « echec », gardé, et '
        '« Renvoyer » le remet en file puis l’envoie', () async {
      final e = await mettre();
      final s = service();
      transport.erreur = const SocketException('hors ligne');
      for (var i = 0; i < PolitiqueRelanceEmail.tentativesMax; i++) {
        await s.envoyer(e.id);
        // `envoyer` ne regarde pas le délai : chaque appel est une tentative.
        final etat = await relu(e.id);
        if (etat.statut == StatutEmail.echec) break;
        // l'état `echec` interdit d'autres envois directs ; on rouvre pas.
      }
      final echec = await relu(e.id);
      expect(echec.statut, StatutEmail.echec);
      expect(echec.tentatives, PolitiqueRelanceEmail.tentativesMax);
      expect(echec.derniereErreur, isNotNull);

      // La relance automatique l'ignore : plus rien ne part.
      final avant = transport.appels;
      await s.relancer();
      expect(transport.appels, avant);
      expect(await lignes(), 1, reason: 'jamais supprimé');

      // « Renvoyer » : en file, tenté tout de suite.
      transport.erreur = null;
      final r = await s.renvoyer(e.id);
      expect(r.issue, IssueEnvoiEmail.envoye);
      final fini = await relu(e.id);
      expect(fini.statut, StatutEmail.envoye);
      expect(fini.tentatives, PolitiqueRelanceEmail.tentativesMax + 1);
    });

    test('hors connexion, le premier échec arrête la relance : les suivants '
        'ne sont pas tentés', () async {
      final a = await mettre(cle: 'notification:a');
      horloge = horloge.add(const Duration(minutes: 1));
      final b = await mettre(cle: 'notification:b');
      transport.erreur = const SocketException('hors ligne');
      await service().relancer();
      expect(transport.appels, 1);
      expect((await relu(a.id)).tentatives, 1);
      expect((await relu(b.id)).tentatives, 0);
    });

    test('l’état de la boîte compte et dit la dernière raison', () async {
      final e = await mettre();
      await mettre(cle: 'notification:m-2');
      transport.erreur = const SocketException('hors ligne');
      await service().envoyer(e.id);
      final etat = await dao.etatFile();
      expect(etat.enAttente, 2);
      expect(etat.enEchec, 0);
      expect(etat.derniereErreur, contains('injoignable'));
    });
  });

  group('Le mot de passe ne va JAMAIS en base', () {
    test('après un envoi réussi et un échec, aucune cellule de la boîte ne '
        'contient le secret', () async {
      final e = await mettre();
      transport.erreur = SmtpClientCommunicationException('refus $secret');
      await service().envoyer(e.id);
      transport.erreur = null;
      await service().renvoyer(e.id);

      final tout = await db
          .customSelect('SELECT * FROM boite_envoi_emails_local')
          .get();
      for (final ligne in tout) {
        for (final valeur in ligne.data.values) {
          expect('$valeur', isNot(contains(secret)));
        }
      }
      expect(
        ConfigurationSmtp(
          hote: 'h',
          port: 25,
          ssl: false,
          clairAutorise: true,
          utilisateur: 'u',
          motDePasse: secret,
        ).toString(),
        isNot(contains(secret)),
      );
    });
  });

  group('L’interrupteur « Synchronisation activée » ne coupe PAS l’e-mail', () {
    test('synchronisation désactivée dans poste.json : l’e-mail part quand '
        'même (SMTP direct, pas de la synchronisation)', () async {
      File(cheminPoste).writeAsStringSync(
        jsonEncode({
          cleMotDePasseSmtp: secret,
          cleSynchronisationActivee: false,
        }),
      );
      expect(
        await LecteurConfigurationPoste(
          chemin: () async => cheminPoste,
        ).synchronisationActivee(),
        isFalse,
        reason: 'le test désactive bien la synchronisation',
      );
      final e = await mettre();
      final r = await service().envoyer(e.id);

      expect(r.issue, IssueEnvoiEmail.envoye);
      expect(transport.appels, 1);
      expect((await relu(e.id)).statut, StatutEmail.envoye);
    });
  });

  group('De BOUT EN BOUT contre un VRAI serveur SMTP (socket locale)', () {
    Future<void> viser(ServeurSmtpEssai srv) => ParametresDao(db).ecrire({
      ClesSmtp.hote: '127.0.0.1',
      ClesSmtp.port: '${srv.port}',
      ClesSmtp.securite: 'aucune',
      ClesSmtp.utilisateur: srv.utilisateur,
    }, auteurId: null);

    ServiceBoiteEnvoiEmails reel() => ServiceBoiteEnvoiEmails(
      dao: dao,
      lecteur: lecteur(),
      maintenant: () => horloge,
      auSucces: (email, quand) async => envoyesPour.add(email.id),
    );

    test('le courriel ARRIVE au serveur, avec son objet, son destinataire et '
        'son corps — puis seulement « envoyé »', () async {
      final srv = await ServeurSmtpEssai.demarrer();
      addTearDown(srv.arreter);
      await viser(srv);
      final e = await mettre();

      final r = await reel().envoyer(e.id);

      expect(r.issue, IssueEnvoiEmail.envoye, reason: '${r.raison}');
      expect(srv.recus, hasLength(1));
      expect(srv.recus.single, contains('kora@exemple.bj'));
      expect(srv.sujet(0), 'Votre séjour');
      expect(srv.corpsTexte(0).trim(), 'Bonjour KORA, arrivée demain.');
      expect(srv.destinataires.single.single, contains('kora@exemple.bj'));
      expect(srv.authentificationsRefusees, 0);
      expect((await relu(e.id)).statut, StatutEmail.envoye);
      expect(envoyesPour, [e.id]);
    });

    test('un mauvais mot de passe : le serveur REFUSE, la cause est lisible, '
        'rien n’est « envoyé » et le secret n’est écrit nulle part', () async {
      final srv = await ServeurSmtpEssai.demarrer(motDePasse: 'autre-mot');
      addTearDown(srv.arreter);
      await viser(srv);
      final e = await mettre();

      final r = await reel().envoyer(e.id);

      expect(r.issue, IssueEnvoiEmail.echoue);
      expect(r.raison, isNotNull);
      expect(srv.recus, isEmpty);
      expect(srv.authentificationsRefusees, greaterThan(0));
      final apres = await relu(e.id);
      expect(apres.statut, StatutEmail.enAttente);
      expect(apres.tentatives, 1);
      expect(apres.derniereErreur, isNot(contains(secret)));
    });

    test(
      'le serveur REFUSE le message (554) : la cause est celle du serveur',
      () async {
        final srv = await ServeurSmtpEssai.demarrer();
        addTearDown(srv.arreter);
        srv.refusDeData = '554 5.7.1 Message refuse par la politique';
        await viser(srv);
        final e = await mettre();

        final r = await reel().envoyer(e.id);

        expect(r.issue, IssueEnvoiEmail.echoue);
        expect((await relu(e.id)).statut, StatutEmail.enAttente);
        expect(srv.recus, isEmpty);
      },
    );

    test('hors réseau : le message ATTEND dans la boîte, puis PART plus tard '
        'quand le serveur revient', () async {
      final premier = await ServeurSmtpEssai.demarrer();
      final port = premier.port;
      await viser(premier);
      await premier.arreter();
      final e = await mettre();
      final s = reel();

      final rate = await s.envoyer(e.id);
      expect(rate.issue, IssueEnvoiEmail.echoue);
      expect(rate.raison, contains('injoignable'));
      expect((await relu(e.id)).statut, StatutEmail.enAttente);

      // Le réseau revient : un nouveau serveur sur le MÊME port.
      final revenu = await ServeurSmtpEssai.demarrer(port: port);
      addTearDown(revenu.arreter);
      horloge = horloge.add(PolitiqueRelanceEmail.delaiApres(1));
      final bilan = await s.relancer();

      expect(bilan, (envoyes: 1, restants: 0));
      expect(revenu.recus, hasLength(1));
      expect((await relu(e.id)).statut, StatutEmail.envoye);
      expect(
        (await relu(e.id)).tentatives,
        2,
        reason: 'l’échec ET le succès sont des tentatives réelles',
      );
    });
  });
}
