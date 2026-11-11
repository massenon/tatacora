import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/notifications/data/notifications_dao.dart';
import 'package:tatacora_flutter/features/notifications/domain/entities/canal_notification.dart';
import 'package:tatacora_flutter/features/notifications/domain/entities/declencheur_notification.dart';
import 'package:tatacora_flutter/features/notifications/presentation/ecran_notifications.dart';
import 'package:tatacora_flutter/features/notifications/presentation/providers_notifications.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_dao.dart';
import 'package:tatacora_flutter/features/transverse/data/boite_envoi_emails_dao.dart';
import 'package:tatacora_flutter/features/transverse/data/configuration_poste.dart';
import 'package:tatacora_flutter/features/transverse/data/envoi_boite_emails.dart';
import 'package:tatacora_flutter/features/transverse/data/envoi_messages_editeur.dart';
import 'package:tatacora_flutter/features/transverse/data/messages_editeur_dao.dart';
import 'package:tatacora_flutter/features/transverse/domain/boite_envoi_emails.dart';
import 'package:tatacora_flutter/features/transverse/presentation/providers_contact_editeur.dart';

/// M12 à l'écran — l'e-mail PART, et l'écran dit l'état VRAI : « Envoyer »
/// seulement quand le relais est configuré, la phrase de succès seulement après
/// l'accusé SMTP, la cause lisible et le compteur de tentatives après un échec,
/// jamais « envoyé » avant l'accusé.
/// La lecture de `poste.json` est une E/S RÉELLE : sous le faux temps d'un
/// `testWidgets`, elle ne rend la main que dans `runAsync`.
Future<void> laisserLesEntreesSorties(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}

Future<void> appuyer(WidgetTester tester, Key cle) async {
  await tester.tap(find.byKey(cle));
  await laisserLesEntreesSorties(tester);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const secret = 'S3cret-Gite!';
  late AppDatabase db;
  late NotificationsDao dao;
  late Directory dossier;
  late String cheminPoste;
  late List<Message> partis;
  Exception? panne;
  final aujourdHui = DateTime(2026, 9, 14);

  setUp(() async {
    db = AppDatabase.enMemoire();
    dao = NotificationsDao(db);
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

  Future<void> semerMessageEmail({String? adresse}) async {
    await db
        .into(db.clientsLocal)
        .insert(
          ClientsLocalCompanion.insert(
            id: 'c1',
            nom: 'KORA',
            telephone: '97000000',
            typeClient: 'particulier',
            email: Value(adresse),
          ),
        );
    await dao.creerModele(
      declencheur: DeclencheurNotification.sejourDemain,
      canal: CanalNotification.email,
      contenuTemplate: 'Bonjour {client}, arrivée le {date_arrivee}.',
      objet: 'Votre séjour',
    );
    await dao.detecter(
      aujourdHui: aujourdHui,
      emailsClients: await dao.emailsDesClients(),
      reservations: [
        Reservation(
          id: 'r1',
          reference: 'LOC-1',
          clientId: 'c1',
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
      ],
    );
  }

  Future<void> monter(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(2200, 2400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final editeur = ServiceMessagesEditeur(
      dao: MessagesEditeurDao(db),
      parametres: ParametresDao(db),
      configuration: LecteurConfigurationPoste(chemin: () async => cheminPoste),
      envoiAutorise: true,
    );
    final boite = BoiteEnvoiEmailsDao(db);
    final surcharges = <Override>[
      baseLocaleProvider.overrideWithValue(db),
      droitsProvider.overrideWithValue(
        GardeAcces.depuisJson(const {'M12': 'C'}),
      ),
      serviceMessagesEditeurProvider.overrideWithValue(editeur),
      serviceBoiteEnvoiEmailsProvider.overrideWithValue(
        ServiceBoiteEnvoiEmails(
          dao: boite,
          lecteur: editeur.lecteurSmtp,
          transport: (Message m, SmtpServer s, Duration d) async {
            partis.add(m);
            if (panne != null) throw panne!;
          },
          auSucces: (email, quand) =>
              dao.marquerEnvoyeParLeSysteme(email.sourceId!, envoyeLe: quand),
        ),
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: surcharges,
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranNotifications()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await laisserLesEntreesSorties(tester);
  }

  Future<String> idDuMessage() async => (await dao.file()).single.id;

  testWidgets('relais configuré : « Envoyer » existe, l’envoi réussi dit la '
      'phrase de la vue APRÈS l’accusé, le message quitte la file', (
    tester,
  ) async {
    await semerMessageEmail(adresse: 'kora@exemple.bj');
    final id = await idDuMessage();
    await monter(tester);

    expect(find.byKey(Key('notifications-envoyer-$id')), findsOneWidget);
    expect(find.text('Envoyer'), findsOneWidget);
    expect(find.byKey(Key('notifications-sans-relais-$id')), findsNothing);
    expect(partis, isEmpty, reason: 'rien ne part avant le geste');

    await appuyer(tester, Key('notifications-envoyer-$id'));

    expect(partis, hasLength(1));
    expect(find.text('Message envoyé par e-mail.'), findsOneWidget);
    expect(find.byKey(Key('notifications-message-$id')), findsNothing);
    expect(await dao.file(), isEmpty);
    expect(await dao.nombreEnvoisReels(), 1);
  });

  testWidgets('l’envoi échoue : la cause lisible et les tentatives sont '
      'dites, « Renvoyer » remplace « Envoyer », le message reste « non '
      'envoyé » et EN FILE', (tester) async {
    await semerMessageEmail(adresse: 'kora@exemple.bj');
    final id = await idDuMessage();
    await monter(tester);
    panne = const SocketException('Connexion refusée');

    await appuyer(tester, Key('notifications-envoyer-$id'));

    expect(find.text('Message envoyé par e-mail.'), findsNothing);
    final etat = tester.widget<Text>(
      find.byKey(Key('notifications-etat-envoi-$id')),
    );
    expect(etat.data, contains('Tentatives d’envoi : 1'));
    expect(etat.data, contains('Dernière erreur : Serveur SMTP injoignable'));
    expect(etat.data, contains('Connexion refusée'));
    expect(find.text('Renvoyer'), findsOneWidget);
    expect(find.byKey(Key('notifications-non-envoye-$id')), findsOneWidget);
    expect(find.byKey(Key('notifications-message-$id')), findsOneWidget);
    expect(await dao.nombreEnvoisReels(), 0);

    // Le réseau revient : « Renvoyer » envoie, et seulement alors c'est parti.
    panne = null;
    await appuyer(tester, Key('notifications-envoyer-$id'));
    expect(find.text('Message envoyé par e-mail.'), findsOneWidget);
    expect(await dao.nombreEnvoisReels(), 1);
  });

  testWidgets('relais non configuré : la raison REMPLACE le bouton, rien ne '
      'peut partir', (tester) async {
    File(cheminPoste).writeAsStringSync('{}');
    await semerMessageEmail(adresse: 'kora@exemple.bj');
    final id = await idDuMessage();
    await monter(tester);

    expect(find.byKey(Key('notifications-envoyer-$id')), findsNothing);
    expect(find.byKey(Key('notifications-sans-relais-$id')), findsOneWidget);
    expect(find.text('Aucun relais SMTP réel configuré'), findsWidgets);
    expect(partis, isEmpty);
  });

  testWidgets('aucune adresse connue : « Envoyer » le DIT et ne met rien en '
      'boîte', (tester) async {
    await semerMessageEmail(adresse: null);
    final id = await idDuMessage();
    await monter(tester);

    await appuyer(tester, Key('notifications-envoyer-$id'));

    expect(
      find.text(
        'Aucune adresse e-mail connue pour ce destinataire — à transmettre à la main.',
      ),
      findsOneWidget,
    );
    expect(partis, isEmpty);
    final n = await db
        .customSelect('SELECT COUNT(*) AS n FROM boite_envoi_emails_local')
        .getSingle();
    expect(n.data['n'], 0);
    expect(await dao.file(), hasLength(1));
  });

  testWidgets('un message d’un autre canal garde l’étiquette du maître, sans '
      'bouton d’envoi', (tester) async {
    await dao.creerModele(
      declencheur: DeclencheurNotification.sejourDemain,
      canal: CanalNotification.whatsapp,
      contenuTemplate: 'Bonjour {client}.',
    );
    await dao.detecter(
      aujourdHui: aujourdHui,
      reservations: [
        Reservation(
          id: 'r1',
          reference: 'LOC-1',
          clientId: 'c1',
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
      ],
    );
    final id = await idDuMessage();
    await monter(tester);

    expect(find.byKey(Key('notifications-envoyer-$id')), findsNothing);
    expect(find.byKey(Key('notifications-a-parametrer-$id')), findsOneWidget);
  });

  testWidgets('relances automatiques ÉPUISÉES : l’écran le dit, et « Renvoyer » '
      'remet en file puis envoie', (tester) async {
    await semerMessageEmail(adresse: 'kora@exemple.bj');
    final id = await idDuMessage();
    final email = (await BoiteEnvoiEmailsDao(
      db,
    ).parSource(SourceEmail.notification, id))!;
    await db.customStatement(
      "UPDATE boite_envoi_emails_local SET statut = 'echec', tentatives = 30, "
      "derniere_erreur = 'Serveur SMTP injoignable (connexion absente ?) : x' "
      "WHERE id = '${email.id}'",
    );
    await monter(tester);

    final etat = tester.widget<Text>(
      find.byKey(Key('notifications-etat-envoi-$id')),
    );
    expect(etat.data, contains('Tentatives d’envoi : 30'));
    expect(etat.data, contains('Relances automatiques épuisées'));
    expect(find.text('Renvoyer'), findsOneWidget);

    await appuyer(tester, Key('notifications-envoyer-$id'));

    expect(partis, hasLength(1));
    expect(find.text('Message envoyé par e-mail.'), findsOneWidget);
    expect(await dao.nombreEnvoisReels(), 1);
  });
}
