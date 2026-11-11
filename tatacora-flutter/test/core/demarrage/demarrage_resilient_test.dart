import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/demarrage/demarrage_resilient.dart';
import 'package:tatacora_flutter/core/demarrage/journal_demarrage.dart';
import 'package:tatacora_flutter/core/demarrage/textes_demarrage.dart';

/// R1 — jamais un écran vide : une base cassée donne l'écran de panne ET une
/// ligne de journal ; une préparation trop longue donne « préparation bloquée ».
void main() {
  late Directory dossier;
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  setUp(() => dossier = Directory.systemTemp.createTempSync('demarrage_'));
  tearDown(() => dossier.deleteSync(recursive: true));

  group('journal', () {
    test('les secrets sont expurgés, la rotation garde 5 fichiers', () {
      final j = JournalDemarrage(
        dossier,
        tailleMax: 200,
        secrets: ['abc123secret'],
      );
      for (var i = 0; i < 12; i++) {
        j.nouvelleSession('session $i');
        j.ecrire('jeton=ZZZ mot de passe: hunter2 valeur abc123secret fin');
      }
      final tout = dossier
          .listSync()
          .whereType<File>()
          .map((f) => f.readAsStringSync())
          .join();
      expect(tout, isNot(contains('abc123secret')));
      expect(tout, isNot(contains('hunter2')));
      expect(tout, isNot(contains('ZZZ')));
      expect(tout, contains('***'));
      final noms = dossier.listSync().map((e) => e.path.split('/').last);
      expect(noms.where((n) => n.startsWith('demarrage')).length, 5);
    });

    test('écriture synchrone : la ligne est sur disque au retour', () {
      JournalDemarrage(dossier).ecrire('bonjour');
      expect(
        File('${dossier.path}/$nomJournalDemarrage').readAsStringSync(),
        contains('bonjour'),
      );
    });
  });

  Future<void> monter(
    WidgetTester tester,
    ControleurDemarrage c,
    Future<AppDatabase> Function() preparer, {
    Duration delai = const Duration(seconds: 45),
  }) => tester.pumpWidget(
    DemarrageResilient(
      controleur: c,
      preparer: preparer,
      delai: delai,
      dossierDonnees: dossier.path,
      construire: (_) => const MaterialApp(home: Text('ECRAN METIER')),
    ),
  );

  testWidgets(
    'base volontairement cassée : écran de panne et ligne de journal',
    (tester) async {
      final fichier = File('${dossier.path}/tatacora.sqlite')
        ..writeAsBytesSync(List.filled(4096, 7));
      final c = ControleurDemarrage()
        ..attacherJournal(JournalDemarrage(dossier)..nouvelleSession('test'));
      await tester.runAsync(() async {
        await monter(tester, c, () async {
          final base = AppDatabase.surFichier(fichier);
          base.journalDemarrage = c.journal!.ecrire;
          await base.customSelect('SELECT 1').get();
          return base;
        });
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();
      expect(find.text(TextesDemarrage.titrePanne), findsOneWidget);
      expect(find.text(TextesDemarrage.copier), findsOneWidget);
      expect(find.text(TextesDemarrage.ouvrirDossier), findsOneWidget);
      expect(find.text(TextesDemarrage.quitter), findsOneWidget);
      expect(find.text('ECRAN METIER'), findsNothing);
      expect(
        File('${dossier.path}/$nomJournalDemarrage').readAsStringSync(),
        contains('ERREUR ouverture de la base'),
      );
    },
  );

  testWidgets(
    'une préparation qui dépasse le délai : « préparation bloquée »',
    (tester) async {
      final c = ControleurDemarrage()
        ..attacherJournal(JournalDemarrage(dossier)..nouvelleSession('test'));
      final jamais = Completer<AppDatabase>();
      await monter(
        tester,
        c,
        () => jamais.future,
        delai: const Duration(seconds: 45),
      );
      expect(find.text(TextesDemarrage.attente), findsOneWidget);
      await tester.pump(const Duration(seconds: 44));
      expect(find.text(TextesDemarrage.titreBloquee), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text(TextesDemarrage.titreBloquee), findsOneWidget);
      expect(find.text(TextesDemarrage.copier), findsOneWidget);
      expect(find.text(TextesDemarrage.quitter), findsOneWidget);
      expect(
        File('${dossier.path}/$nomJournalDemarrage').readAsStringSync(),
        contains('préparation bloquée'),
      );
    },
  );

  testWidgets('copier le détail : le détail expurgé part au presse-papiers', (
    tester,
  ) async {
    String? copie;
    final c = ControleurDemarrage()
      ..attacherJournal(
        JournalDemarrage(dossier, secrets: ['SECRET9'])..nouvelleSession('t'),
      );
    await tester.pumpWidget(
      DemarrageResilient(
        controleur: c,
        preparer: () async => throw StateError('mot de passe: SECRET9 refusé'),
        dossierDonnees: dossier.path,
        actions: ActionsPanne(copier: (t) async => copie = t),
        construire: (_) => const SizedBox(),
      ),
    );
    await tester.pump();
    await tester.tap(find.text(TextesDemarrage.copier));
    expect(copie, contains('refusé'));
    expect(copie, isNot(contains('SECRET9')));
    expect(copie, contains(c.journal!.chemin));
  });

  testWidgets('une base saine mène au premier écran métier', (tester) async {
    final c = ControleurDemarrage()
      ..attacherJournal(JournalDemarrage(dossier)..nouvelleSession('t'));
    await tester.runAsync(() async {
      await monter(tester, c, () async {
        final base = AppDatabase.enMemoire();
        await base.customSelect('SELECT 1').get();
        return base;
      });
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    expect(find.text('ECRAN METIER'), findsOneWidget);
  });
}
