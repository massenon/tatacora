import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/transverse/data/sauvegardes_poste.dart';

/// Les sauvegardes CONSERVÉES sur le poste : une copie cohérente rangée sous
/// un nom daté, jamais écrasée, « non téléchargée » tant qu'elle n'est pas
/// sortie, retirable, et purgée au bout de trente jours.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late Directory dossier;
  late DateTime horloge;
  late SauvegardesPoste sauvegardes;

  setUp(() {
    db = AppDatabase.enMemoire();
    dossier = Directory.systemTemp.createTempSync('sauvegardes_poste_');
    horloge = DateTime(2026, 10, 21, 8, 30, 5);
    sauvegardes = SauvegardesPoste(
      db,
      cheminConfiguration: () async => '${dossier.path}/poste.json',
      maintenant: () => horloge,
    );
  });
  tearDown(() async {
    await db.close();
    dossier.deleteSync(recursive: true);
  });

  test('le nom : daté à la seconde, et seul un nom du poste est admis', () {
    expect(
      SauvegardesPoste.nomDe(DateTime(2026, 10, 21, 8, 30, 5)),
      'tatacora_sauvegarde_2026-10-21_08h30m05.sqlite',
    );
    expect(
      sauvegardes.lire('../poste.json'),
      throwsA(isA<SauvegardePosteRefusee>()),
    );
    expect(
      sauvegardes.retirer('/etc/passwd'),
      throwsA(isA<SauvegardePosteRefusee>()),
    );
  });

  test(
    'générer : une base SQLite valide, rangée, jamais téléchargée',
    () async {
      expect(await sauvegardes.fichiers(), isEmpty);
      final f = await sauvegardes.generer();
      expect(f.nom, 'tatacora_sauvegarde_2026-10-21_08h30m05.sqlite');
      expect(f.telechargee, isFalse);
      expect(f.taille, greaterThan(0));
      final copie = sqlite3.open(
        '${dossier.path}/sauvegardes/${f.nom}',
        mode: OpenMode.readOnly,
      );
      addTearDown(copie.close);
      expect(
        copie.select('SELECT COUNT(*) AS n FROM clients_local').single['n'],
        0,
      );
      expect((await sauvegardes.fichiers()).map((x) => x.nom), [f.nom]);
      // Elle est « en attente de téléchargement » : le bandeau or.
      expect((await sauvegardes.enAttenteDeTelechargement())?.nom, f.nom);
    },
  );

  test(
    'télécharger MARQUE la copie ; une plus récente reste en attente',
    () async {
      final premiere = await sauvegardes.generer();
      await sauvegardes.marquerTelechargee(premiere.nom);
      expect((await sauvegardes.fichiers()).single.telechargee, isTrue);
      expect(await sauvegardes.enAttenteDeTelechargement(), isNull);

      horloge = horloge.add(const Duration(minutes: 5));
      final seconde = await sauvegardes.generer();
      final liste = await sauvegardes.fichiers();
      // Même mtime à la seconde près : l'ordre se départage par le nom.
      expect(liste.first.nom, seconde.nom);
      expect((await sauvegardes.enAttenteDeTelechargement())?.nom, seconde.nom);
      expect(liste.length, 2);
    },
  );

  test('retirer efface la copie ET son témoin', () async {
    final f = await sauvegardes.generer();
    await sauvegardes.marquerTelechargee(f.nom);
    await sauvegardes.retirer(f.nom);
    expect(await sauvegardes.fichiers(), isEmpty);
    expect(
      Directory('${dossier.path}/sauvegardes').listSync(),
      isEmpty,
      reason: 'ni la copie ni le témoin ne restent',
    );
  });

  test(
    'la rétention : trente jours glissants, appliquée à la génération',
    () async {
      final vieille = await sauvegardes.generer();
      File(
        '${dossier.path}/sauvegardes/${vieille.nom}',
      ).setLastModifiedSync(horloge.subtract(const Duration(days: 31)));
      horloge = horloge.add(const Duration(minutes: 1));
      final recente = await sauvegardes.generer();
      expect((await sauvegardes.fichiers()).map((f) => f.nom), [recente.nom]);
    },
  );
}
