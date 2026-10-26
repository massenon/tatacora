import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/notifications/data/notifications_dao.dart';
import 'package:tatacora_flutter/features/notifications/domain/entities/canal_notification.dart';
import 'package:tatacora_flutter/features/notifications/domain/entities/declencheur_notification.dart';
import 'package:tatacora_flutter/features/notifications/domain/entities/message_notification.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_dao.dart';
import 'package:tatacora_flutter/features/transverse/data/boite_envoi_emails_dao.dart';
import 'package:tatacora_flutter/features/transverse/data/configuration_poste.dart';
import 'package:tatacora_flutter/features/transverse/data/envoi_boite_emails.dart';
import 'package:tatacora_flutter/features/transverse/data/envoi_messages_editeur.dart';
import 'package:tatacora_flutter/features/transverse/domain/boite_envoi_emails.dart';

/// M12 — l'e-mail de notification PART : composé, mis en boîte avec son
/// message, envoyé par SMTP, et « Envoyé par le système » seulement APRÈS
/// l'accusé du relais. Les autres canaux, eux, ne partent pas.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const secret = 'S3cret-Gite!';
  late AppDatabase db;
  late NotificationsDao dao;
  late BoiteEnvoiEmailsDao boite;
  late Directory dossier;
  late String cheminPoste;
  late List<Message> partis;
  Exception? panne;
  final aujourdHui = DateTime(2026, 9, 14);

  setUp(() async {
    db = AppDatabase.enMemoire();
    dao = NotificationsDao(db);
    boite = BoiteEnvoiEmailsDao(db);
    partis = [];
    panne = null;
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

  ServiceBoiteEnvoiEmails service() => ServiceBoiteEnvoiEmails(
    dao: boite,
    lecteur: LecteurSmtp(
      parametres: ParametresDao(db),
      configuration: LecteurConfigurationPoste(chemin: () async => cheminPoste),
      envoiAutorise: true,
    ),
    transport: (Message m, SmtpServer s, Duration d) async {
      partis.add(m);
      if (panne != null) throw panne!;
    },
    // Le câblage de production (`serviceBoiteEnvoiEmailsProvider`).
    auSucces: (email, quand) async {
      await dao.marquerEnvoyeParLeSysteme(email.sourceId!, envoyeLe: quand);
    },
  );

  Future<void> semerClient(String id, String? email, {bool actif = true}) => db
      .into(db.clientsLocal)
      .insert(
        ClientsLocalCompanion.insert(
          id: id,
          nom: 'KORA',
          telephone: '97000000',
          typeClient: 'particulier',
          email: Value(email),
          actif: Value(actif),
        ),
      );

  List<Reservation> arriveeDemain({String clientId = 'c1'}) => [
    Reservation(
      id: 'r1',
      reference: 'LOC-1',
      clientId: clientId,
      clientNom: 'KORA',
      uniteId: 'u1',
      periode: PeriodeSejour(
        arrivee: DateTime(2026, 9, 15),
        depart: DateTime(2026, 9, 18),
      ),
      tarifNuit: 25000,
      statut: StatutReservation.confirmee,
      statutSynchronisation: StatutSynchronisation.local,
      creeeLe: aujourdHui,
    ),
  ];

  Future<void> semerModele(CanalNotification canal) => dao.creerModele(
    declencheur: DeclencheurNotification.sejourDemain,
    canal: canal,
    contenuTemplate: 'Bonjour {client}, arrivée le {date_arrivee}.',
    objet: 'Votre séjour',
    actif: true,
  );

  Future<BilanDetection> detecter() async => dao.detecter(
    reservations: arriveeDemain(),
    aujourdHui: aujourdHui,
    emailsClients: await dao.emailsDesClients(),
  );

  Future<int> lignesBoite() async =>
      (await db
                  .customSelect(
                    'SELECT COUNT(*) AS n FROM boite_envoi_emails_local',
                  )
                  .getSingle())
              .data['n']
          as int;

  group('La composition met l’e-mail en boîte, avec son message', () {
    test('canal e-mail + adresse connue : un message ET un e-mail en boîte, '
        'au bon destinataire', () async {
      await semerClient('c1', 'kora@exemple.bj');
      await semerModele(CanalNotification.email);

      final bilan = await detecter();

      expect(bilan.composes, 1);
      final message = (await dao.file()).single;
      final email = (await boite.parSource(
        SourceEmail.notification,
        message.id,
      ))!;
      expect(email.adresse, 'kora@exemple.bj');
      expect(email.objet, 'Votre séjour');
      expect(email.corps, 'Bonjour KORA, arrivée le 15/09/2026.');
      expect(email.statut, StatutEmail.enAttente);
      expect(email.cleIdempotence, 'notification:${message.id}');
      expect(partis, isEmpty, reason: 'la détection n’envoie rien elle-même');
    });

    test('un autre canal que l’e-mail : AUCUN e-mail en boîte', () async {
      await semerClient('c1', 'kora@exemple.bj');
      await semerModele(CanalNotification.whatsapp);
      await detecter();
      expect(await lignesBoite(), 0);
    });

    test('sans adresse, adresse invalide ou client archivé : le message est '
        'composé, aucun e-mail n’est mis en boîte', () async {
      for (final (id, mail, actif) in [
        ('c1', null, true),
        ('c1', 'pas-une-adresse', true),
        ('c1', 'kora@exemple.bj', false),
      ]) {
        final base = AppDatabase.enMemoire();
        final d = NotificationsDao(base);
        await base
            .into(base.clientsLocal)
            .insert(
              ClientsLocalCompanion.insert(
                id: id,
                nom: 'KORA',
                telephone: '97000000',
                typeClient: 'particulier',
                email: Value(mail),
                actif: Value(actif),
              ),
            );
        await d.creerModele(
          declencheur: DeclencheurNotification.sejourDemain,
          canal: CanalNotification.email,
          contenuTemplate: 'Bonjour {client}.',
          actif: true,
        );
        final bilan = await d.detecter(
          reservations: arriveeDemain(),
          aujourdHui: aujourdHui,
          emailsClients: await d.emailsDesClients(),
        );
        expect(bilan.composes, 1, reason: '$mail / actif=$actif');
        final n = await base
            .customSelect('SELECT COUNT(*) AS n FROM boite_envoi_emails_local')
            .getSingle();
        expect(n.data['n'], 0, reason: '$mail / actif=$actif');
        await base.close();
      }
    });

    test(
      'relancée, la détection ne DUPLIQUE ni le message ni l’e-mail',
      () async {
        await semerClient('c1', 'kora@exemple.bj');
        await semerModele(CanalNotification.email);
        await detecter();
        await detecter();
        await detecter();
        expect((await dao.file()).length, 1);
        expect(await lignesBoite(), 1);
      },
    );

    test('RATTRAPAGE : un message composé sans adresse est mis en boîte dès '
        'que l’adresse existe, une seule fois', () async {
      await semerClient('c1', null);
      await semerModele(CanalNotification.email);
      await detecter();
      expect(await lignesBoite(), 0);

      await (db.update(db.clientsLocal)..where((c) => c.id.equals('c1'))).write(
        const ClientsLocalCompanion(email: Value('kora@exemple.bj')),
      );
      await detecter();
      await detecter();

      expect(await lignesBoite(), 1);
      expect((await dao.file()).length, 1);
    });
  });

  group('« Envoyé par le système » = l’accusé du relais, et rien d’autre', () {
    test(
      'le message reste EN FILE tant que le relais n’a pas accepté ; après '
      'l’accusé il passe « Envoyé par le système » et le compteur le dit',
      () async {
        await semerClient('c1', 'kora@exemple.bj');
        await semerModele(CanalNotification.email);
        await detecter();
        final message = (await dao.file()).single;
        final email = (await boite.parSource(
          SourceEmail.notification,
          message.id,
        ))!;

        panne = const SocketException('hors ligne');
        final rate = await service().envoyer(email.id);
        expect(rate.issue, IssueEnvoiEmail.echoue);
        expect(
          (await dao.file()).single.statut,
          StatutMessageNotification.enAttente,
        );
        expect(await dao.nombreEnvoisReels(), 0);

        panne = null;
        final ok = await service().renvoyer(email.id);
        expect(ok.issue, IssueEnvoiEmail.envoye);

        expect(await dao.file(), isEmpty);
        final envoye = (await dao.journal()).single;
        expect(envoye.statut, StatutMessageNotification.envoyeParLeSysteme);
        expect(envoye.statut.estUnEnvoiDuSysteme, isTrue);
        expect(await dao.nombreEnvoisReels(), 1);
        expect(partis, hasLength(2), reason: 'un échec puis un succès');
      },
    );

    test('« Transmis à la main » ou « Abandonner » ANNULE l’e-mail : il ne '
        'part JAMAIS', () async {
      await semerClient('c1', 'kora@exemple.bj');
      await semerClient('c2', 'autre@exemple.bj');
      await semerModele(CanalNotification.email);
      await dao.detecter(
        reservations: [
          ...arriveeDemain(),
          ...arriveeDemain(clientId: 'c2').map(
            (r) => Reservation(
              id: 'r2',
              reference: 'LOC-2',
              clientId: 'c2',
              clientNom: 'AUTRE',
              uniteId: 'u2',
              periode: r.periode,
              tarifNuit: r.tarifNuit,
              statut: r.statut,
              statutSynchronisation: r.statutSynchronisation,
              creeeLe: aujourdHui,
            ),
          ),
        ],
        aujourdHui: aujourdHui,
        emailsClients: await dao.emailsDesClients(),
      );
      final messages = await dao.file();
      expect(messages.length, 2);

      await dao.marquerTransmis(messages.first.id, auteur: 'reception');
      await dao.abandonner(
        messages.last.id,
        auteur: 'gerant',
        motif: 'doublon',
      );

      final s = service();
      await s.relancer(forcer: true);
      expect(partis, isEmpty);
      for (final m in messages) {
        final e = (await boite.parSource(SourceEmail.notification, m.id))!;
        expect(e.statut, StatutEmail.annule);
        expect((await s.envoyer(e.id)).issue, IssueEnvoiEmail.dejaEnCours);
      }
      expect(partis, isEmpty);
      expect(await dao.nombreEnvoisReels(), 0);
    });

    test(
      'un message déjà sorti de la file n’est pas ré-affirmé « envoyé »',
      () async {
        await semerClient('c1', 'kora@exemple.bj');
        await semerModele(CanalNotification.email);
        await detecter();
        final message = (await dao.file()).single;
        await dao.marquerTransmis(message.id, auteur: 'reception');

        await dao.marquerEnvoyeParLeSysteme(message.id, envoyeLe: aujourdHui);

        expect(
          (await dao.messages()).single.statut,
          StatutMessageNotification.transmisALaMain,
        );
      },
    );
  });

  group('« Envoyer » : l’adresse est LUE au geste', () {
    test(
      'un message composé avant la v39 (sans e-mail en boîte) : l’adresse '
      'du client est résolue, l’e-mail mis en boîte, une seule fois',
      () async {
        await semerClient('c1', null);
        await semerModele(CanalNotification.email);
        await detecter();
        final message = (await dao.file()).single;
        expect(await lignesBoite(), 0);

        // Le client reçoit son adresse ; AUCUNE détection n'est relancée.
        await (db.update(
          db.clientsLocal,
        )..where((c) => c.id.equals('c1'))).write(
          const ClientsLocalCompanion(email: Value('kora@exemple.bj')),
        );

        final a = await dao.mettreEnBoite(
          message.id,
          reservations: arriveeDemain(),
        );
        final b = await dao.mettreEnBoite(
          message.id,
          reservations: arriveeDemain(),
        );

        expect(a.issue, IssueMiseEnBoite.miseEnBoite);
        expect(a.email!.adresse, 'kora@exemple.bj');
        expect(b.issue, IssueMiseEnBoite.dejaEnBoite);
        expect(await lignesBoite(), 1);
      },
    );

    test('pas d’adresse connue : rien n’est mis en boîte, la raison est '
        '« sansAdresse »', () async {
      await semerClient('c1', null);
      await semerModele(CanalNotification.email);
      await detecter();
      final message = (await dao.file()).single;

      final r = await dao.mettreEnBoite(
        message.id,
        reservations: arriveeDemain(),
      );

      expect(r.issue, IssueMiseEnBoite.sansAdresse);
      expect(r.email, isNull);
      expect(await lignesBoite(), 0);
    });

    test('un canal autre que l’e-mail est REFUSÉ, un message sorti de la file '
        'aussi', () async {
      await semerClient('c1', 'kora@exemple.bj');
      await semerModele(CanalNotification.whatsapp);
      await detecter();
      final wa = (await dao.file()).single;
      await expectLater(
        dao.mettreEnBoite(wa.id, reservations: arriveeDemain()),
        throwsA(isA<RefusNotification>()),
      );

      await semerModele(CanalNotification.email);
      await detecter();
      final email = (await dao.file()).firstWhere(
        (m) => m.canal == CanalNotification.email,
      );
      await dao.abandonner(email.id, auteur: 'gerant', motif: 'doublon');
      await expectLater(
        dao.mettreEnBoite(email.id, reservations: arriveeDemain()),
        throwsA(isA<RefusNotification>()),
      );
    });
  });
}
