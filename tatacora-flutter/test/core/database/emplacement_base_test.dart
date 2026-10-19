import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/database/emplacement_base.dart';

/// La base hors du dossier Documents (décision du PO du 17/10/2026) : le
/// déménagement d'une base existante se prouve sur de VRAIS fichiers portant
/// des données (piège 2), journal non reporté compris.
void main() {
  late Directory racine;
  late Directory documents;
  late Directory neuf;

  setUp(() {
    racine = Directory.systemTemp.createTempSync('emplacement_base_');
    documents = Directory(p.join(racine.path, 'Documents'))..createSync();
    neuf = Directory(p.join(racine.path, 'AppData', 'TATACORA', 'donnees'));
  });
  tearDown(() => racine.deleteSync(recursive: true));

  test('Windows : %LOCALAPPDATA%\\TATACORA\\donnees, jamais Documents', () {
    final d = dossierBaseWindows({
      'LOCALAPPDATA': r'C:\Users\Caisse\AppData\Local',
    });
    expect(d, p.join(r'C:\Users\Caisse\AppData\Local', 'TATACORA', 'donnees'));
    expect(d!.toLowerCase(), isNot(contains('documents')));
    expect(dossierBaseWindows({}), isNull);
    expect(dossierBaseWindows({'LOCALAPPDATA': ''}), isNull);
  });

  test(
    'poste neuf : base neuve dans le nouveau dossier, rien dans Documents',
    () async {
      final r = await preparerEmplacementBase(
        dossierNeuf: neuf,
        dossierAncien: documents,
      );
      expect(r.issue, IssueEmplacement.neuve);
      expect(r.fichier.path, p.join(neuf.path, nomFichierBase));
      expect(neuf.existsSync(), isTrue);
    },
  );

  test('base ancienne DANS Documents, avec une saisie encore dans le journal '
      '(-wal) : déménagée, la saisie est relue, l’ancienne est renommée et '
      'jamais effacée', () async {
    // Une vraie base Drift en WAL, fermée sans reporter son journal : la
    // dernière saisie ne vit que dans `-wal`.
    // L'état des fichiers d'un poste ÉTEINT BRUTALEMENT : la base est copiée
    // pendant qu'elle est ouverte, journal compris — une fermeture propre, elle,
    // reporte le journal et l'efface.
    final vivant = Directory(p.join(racine.path, 'vivant'))..createSync();
    final db = AppDatabase.surFichier(
      File(p.join(vivant.path, nomFichierBase)),
    );
    await db.customStatement('PRAGMA journal_mode = WAL');
    await db.customStatement('PRAGMA wal_autocheckpoint = 0');
    await db.customStatement(
      'INSERT INTO clients_local (id, nom, telephone, type_client) '
      "VALUES ('c-1', 'Sabi', '96000003', 'groupe')",
    );
    final ancien = File(p.join(documents.path, nomFichierBase));
    for (final suffixe in const ['', '-wal', '-shm']) {
      final f = File(p.join(vivant.path, '$nomFichierBase$suffixe'));
      if (f.existsSync()) f.copySync('${ancien.path}$suffixe');
    }
    final avecJournal = File('${ancien.path}-wal').existsSync();
    await db.close();

    final r = await preparerEmplacementBase(
      dossierNeuf: neuf,
      dossierAncien: documents,
    );
    expect(r.issue, IssueEmplacement.deplacee);
    expect(ancien.existsSync(), isFalse, reason: 'plus relue');
    expect(
      File('${ancien.path}$suffixeAncienneBase').existsSync(),
      isTrue,
      reason: 'renommée, jamais effacée',
    );
    // Le journal non reporté a suivi la base (sans lui, la saisie serait
    // perdue) : la relecture ci-dessous le prouve.
    expect(avecJournal, isTrue, reason: 'le cas doit porter un journal');
    expect(File('${r.fichier.path}-wal').existsSync(), isTrue);

    final relue = AppDatabase.surFichier(r.fichier);
    final lignes = await relue
        .customSelect(
          'SELECT nom FROM clients_local WHERE id = ?',
          variables: [Variable.withString('c-1')],
        )
        .get();
    await relue.close();
    expect(lignes.single.data['nom'], 'Sabi');
  });

  test('la base neuve existe déjà : elle est prise, l’ancienne n’est JAMAIS '
      'relue ni touchée', () async {
    neuf.createSync(recursive: true);
    File(p.join(neuf.path, nomFichierBase)).writeAsStringSync('NEUVE');
    final ancien = File(p.join(documents.path, nomFichierBase))
      ..writeAsStringSync('ANCIENNE');

    final r = await preparerEmplacementBase(
      dossierNeuf: neuf,
      dossierAncien: documents,
    );
    expect(r.issue, IssueEmplacement.dejaEnPlace);
    expect(r.fichier.readAsStringSync(), 'NEUVE');
    expect(ancien.readAsStringSync(), 'ANCIENNE');
  });

  test('une copie interrompue (temporaire laissé derrière) est refaite '
      'proprement au démarrage suivant', () async {
    final ancien = File(p.join(documents.path, nomFichierBase))
      ..writeAsBytesSync(List.filled(4096, 7));
    neuf.createSync(recursive: true);
    File(
      p.join(neuf.path, '$nomFichierBase.copie'),
    ).writeAsBytesSync(List.filled(10, 1));

    final r = await preparerEmplacementBase(
      dossierNeuf: neuf,
      dossierAncien: documents,
    );
    expect(r.issue, IssueEmplacement.deplacee);
    expect(r.fichier.lengthSync(), 4096);
    expect(
      File(p.join(neuf.path, '$nomFichierBase.copie')).existsSync(),
      isFalse,
    );
    expect(ancien.existsSync(), isFalse);
  });

  test('l’ouverture de production passe par preparerEmplacementBase '
      '(relu du code : un commentaire n’est pas un appelant)', () {
    final source = File(
      'lib/core/database/app_database.dart',
    ).readAsStringSync();
    final ouvrir = source.substring(source.indexOf('LazyDatabase _ouvrir()'));
    expect(ouvrir, contains('preparerEmplacementBase('));
    expect(ouvrir, contains('emplacement.fichier'));
    expect(
      ouvrir.substring(0, ouvrir.indexOf('});')),
      isNot(contains("p.join(dossier.path, 'tatacora.sqlite')")),
    );
  });
}
