import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/notifications/data/notifications_dao.dart';
import 'package:tatacora_flutter/features/notifications/domain/entities/canal_notification.dart';
import 'package:tatacora_flutter/features/notifications/domain/entities/declencheur_notification.dart';
import 'package:tatacora_flutter/features/notifications/domain/entities/message_notification.dart';
import 'package:tatacora_flutter/features/notifications/domain/entities/modele_notification.dart';
import 'package:tatacora_flutter/features/notifications/domain/registre_notifications.dart';
import 'package:tatacora_flutter/features/notifications/impression/etat_notifications.dart';
import 'package:tatacora_flutter/features/notifications/presentation/providers_notifications.dart';

/// M12 — ce que l'écran affiche et exporte, éprouvé SANS monter de widget.
///
/// Trois choses que les cas d'écran ne tenaient pas : la valeur de chaque
/// indicateur quand elle n'est PAS nulle, le câblage de bout en bout de
/// l'export (le fichier écrit porte les lignes FILTRÉES et dit son filtre), et
/// l'ordre du journal.
void main() {
  final aujourdHui = DateTime(2026, 9, 14);

  MessageNotification message(StatutMessageNotification statut, String id) =>
      MessageNotification(
        id: id,
        modeleId: 'm1',
        declencheur: DeclencheurNotification.sejourDemain,
        canal: CanalNotification.whatsapp,
        reference: 'REF-$id',
        destinataire: 'KORA',
        contenu: 'Bonjour',
        longueur: 7,
        statut: statut,
        composeLe: aujourdHui,
      );

  group('Les six indicateurs, en valeur NON nulle', () {
    test('chaque compteur compte SON statut, et pas celui du voisin', () {
      final kpis = KpisNotifications.calculer(
        messages: [
          message(StatutMessageNotification.envoyeParLeSysteme, 'a'),
          message(StatutMessageNotification.transmisALaMain, 'b'),
          message(StatutMessageNotification.transmisALaMain, 'c'),
          message(StatutMessageNotification.abandonne, 'd'),
          message(StatutMessageNotification.abandonne, 'e'),
          message(StatutMessageNotification.abandonne, 'f'),
          message(StatutMessageNotification.enAttente, 'g'),
        ],
        modeles: const <ModeleNotification>[],
        transports: const TransportsLocaux.aucun(),
      );

      // 1 / 2 / 3 / 1 : aucune valeur n'est égale à une autre, donc un
      // compteur qui additionnerait deux statuts se verrait.
      expect(kpis.envoyesReels, 1);
      expect(kpis.transmis, 2);
      expect(kpis.abandonnes, 3);
      expect(kpis.enAttente, 1);
    });

    test('« Réellement envoyés » ne compte AUCUN geste manuel', () {
      final kpis = KpisNotifications.calculer(
        messages: [
          message(StatutMessageNotification.transmisALaMain, 'b'),
          message(StatutMessageNotification.abandonne, 'd'),
        ],
        modeles: const <ModeleNotification>[],
        transports: const TransportsLocaux.aucun(),
      );

      expect(kpis.envoyesReels, 0);
    });

    test('canaux branchés : compté sur les transports, jamais posé', () {
      final kpis = KpisNotifications.calculer(
        messages: const <MessageNotification>[],
        modeles: const <ModeleNotification>[],
        transports: const TransportsLocaux({CanalNotification.email}),
      );

      expect(kpis.canauxBranches, 1);
      expect(kpis.canauxTotal, 4);
    });
  });

  group('L’export et le journal, de bout en bout', () {
    late AppDatabase db;
    late NotificationsDao dao;
    late Directory dossier;

    setUp(() {
      db = AppDatabase.enMemoire();
      dao = NotificationsDao(db);
      dossier = Directory.systemTemp.createTempSync('export_notifications_');
    });

    tearDown(() async {
      await db.close();
      if (dossier.existsSync()) dossier.deleteSync(recursive: true);
    });

    ProviderContainer conteneur() {
      final c = ProviderContainer(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          dossierDocumentsProvider.overrideWithValue(() async => dossier),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    Reservation reservation(String id, String client, int jour) => Reservation(
      id: id,
      reference: 'LOC-$id',
      clientId: 'c-$id',
      clientNom: client,
      uniteId: 'u-$id',
      periode: PeriodeSejour(
        arrivee: DateTime(2026, 9, jour),
        depart: DateTime(2026, 9, jour + 2),
      ),
      tarifNuit: 25000,
      statut: StatutReservation.confirmee,
      statutSynchronisation: StatutSynchronisation.local,
      creeeLe: aujourdHui,
    );

    Future<void> semer() async {
      await dao.creerModele(
        declencheur: DeclencheurNotification.sejourDemain,
        canal: CanalNotification.whatsapp,
        contenuTemplate: 'Bonjour {client}, arrivée le {date_arrivee}.',
      );
      // Demain = le 15 : trois réservations qui arrivent ce jour-là.
      await dao.detecter(
        aujourdHui: aujourdHui,
        reservations: [
          reservation('1', 'KORA', 15),
          reservation('2', 'KORA BIS', 15),
          reservation('3', 'ZOLA', 15),
        ],
      );
    }

    test('le CSV écrit porte les lignes FILTRÉES et DIT son filtre', () async {
      await semer();
      expect((await dao.file()).length, 3, reason: 'trois messages semés');

      final c = conteneur();
      c.read(rechercheNotificationsProvider.notifier).definir('KORA');

      final chemin = await c.read(exporterNotificationsProvider)();

      expect(chemin.startsWith(dossier.path), isTrue);
      expect(chemin.endsWith('.csv'), isTrue);

      final octets = File(chemin).readAsBytesSync();
      // BOM UTF-8 : EF BB BF.
      expect(octets.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
      final texte = utf8.decode(octets);

      // Les deux lignes qui correspondent, et pas la troisième.
      final lignes = texte
          .split('\n')
          .where((l) => l.contains('Bonjour KORA'))
          .toList();
      expect(lignes.length, 2, reason: 'KORA et KORA BIS, ni plus ni moins');
      expect(texte, contains('KORA BIS'));
      expect(texte, isNot(contains('ZOLA')));
      // Le filtre est dit EN TÊTE du document (PA-119).
      expect(texte, contains('Onglet : File d’attente · Recherche : KORA'));
      // Et la mention qui borne sa portée.
      expect(texte, contains(EtatNotifications.mentionAucunEnvoi));
    });

    test('sans filtre, les trois lignes partent', () async {
      await semer();

      final c = conteneur();
      final chemin = await c.read(exporterNotificationsProvider)();
      final texte = utf8.decode(File(chemin).readAsBytesSync());

      expect(texte, contains('ZOLA'));
      expect(texte, contains('KORA BIS'));
      expect(texte, isNot(contains('Recherche :')));
    });

    test(
      'un filtre qui vide la liste est REFUSÉ, aucun fichier écrit',
      () async {
        await semer();

        final c = conteneur();
        c.read(rechercheNotificationsProvider.notifier).definir('zzz');

        await expectLater(
          c.read(exporterNotificationsProvider)(),
          throwsA(isA<ExportVide>()),
        );
        expect(dossier.listSync(), isEmpty);
      },
    );

    test('le journal range le plus RÉCENT d’abord', () async {
      await semer();
      final file = await dao.file();
      // Trois sorties, datées à la main : l'horloge du DAO a la seconde pour
      // grain, et un ordre qui dépendrait de `now()` serait aléatoire.
      final dates = <String, DateTime>{
        file[0].id: DateTime(2026, 9, 10),
        file[1].id: DateTime(2026, 9, 12),
        file[2].id: DateTime(2026, 9, 11),
      };
      for (final m in file) {
        await dao.marquerTransmis(m.id, auteur: 'reception');
        await (db.update(
          db.messagesNotificationLocal,
        )..where((t) => t.id.equals(m.id))).write(
          MessagesNotificationLocalCompanion(traiteLe: Value(dates[m.id])),
        );
      }

      final c = conteneur();
      final vue = await c.read(vueNotificationsProvider.future);

      expect(vue.journal.map((m) => m.id).toList(), [
        file[1].id, // 12/09
        file[2].id, // 11/09
        file[0].id, // 10/09
      ]);
    });
  });
}
