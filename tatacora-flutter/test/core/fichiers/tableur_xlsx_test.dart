import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/fichiers/ecriture_xlsx.dart';
import 'package:tatacora_flutter/core/fichiers/lecture_tableur.dart';
import 'package:tatacora_flutter/features/transverse/data/importeurs_locaux.dart';
import 'package:tatacora_flutter/features/transverse/presentation/providers_import_export.dart';

import '../../features/transverse/support/outils_import.dart';

/// Le classeur `.xlsx` d'import (PO, 30/10/2026). Cause du bogue rapporté —
/// « toutes les colonnes dans une seule colonne » : le modèle était un CSV au
/// point-virgule, qu'un Excel réglé sur la virgule ouvre en UNE colonne. Ces
/// cas prouvent l'aller-retour du classeur, la tolérance du CSV de secours et
/// l'import des fichiers de la carte du Gîte Chez Noël déposés dans
/// `docs/data/` (importés dans l'ordre m6 → m5 → m4).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const colonnes = [
    ColonneTableur(libelle: 'Nom', requis: true, format: 'Texte libre'),
    ColonneTableur(
      libelle: 'Prix',
      requis: false,
      format: 'Montant en FCFA',
      numerique: true,
      montant: true,
    ),
    ColonneTableur(libelle: 'Téléphone', requis: false, format: 'Texte libre'),
  ];

  test('un classeur écrit se relit à l’identique : une cellule par colonne, '
      'les nombres sans « .0 », le zéro de tête d’un texte conservé', () {
    final octets = ecrireClasseurXlsx(
      nomModule: 'Essai & <co>',
      description: 'd',
      colonnes: colonnes,
      lignes: [
        ["Jus d'ananas (moyen)", '1500', '0197355974'],
        ['Crêpe "flambée"', null, null],
      ],
    );
    expect(octets.sublist(0, 4), [0x50, 0x4B, 3, 4]);
    expect(lireTableur(octets), [
      ['Nom', 'Prix', 'Téléphone'],
      ["Jus d'ananas (moyen)", '1500', '0197355974'],
      ['Crêpe "flambée"'], // cellules vides de queue omises
    ]);
  });

  test('le modèle vide se relit avec ses en-têtes et son exemple', () {
    final octets = ecrireClasseurXlsx(
      nomModule: 'M',
      description: 'd',
      colonnes: const [
        ColonneTableur(
          libelle: 'Nom',
          requis: true,
          format: 'Texte libre',
          exemple: 'Riz',
        ),
        ColonneTableur(
          libelle: 'Prix',
          requis: true,
          format: 'Nombre',
          numerique: true,
          exemple: '1200',
        ),
      ],
    );
    expect(lireTableur(octets), [
      ['Nom', 'Prix'],
      ['(exemple) Riz', '1200'],
    ]);
  });

  test('le CSV de secours : séparateur, BOM, Windows-1252, UTF-16, sep=', () {
    const attendu = [
      ['Nom', 'Prix'],
      ['Crêpe', '1000'],
    ];
    for (final sep in [';', ',', '\t']) {
      expect(
        lireTableur(utf8.encode('Nom${sep}Prix\r\nCrêpe${sep}1000\r\n')),
        attendu,
      );
      expect(
        lireTableur([
          0xEF,
          0xBB,
          0xBF,
          ...utf8.encode('Nom${sep}Prix\nCrêpe${sep}1000'),
        ]),
        attendu,
      );
    }
    // Windows-1252 : « ê » = 0xEA.
    expect(
      lireTableur([
        ...'Nom;Prix\nCr'.codeUnits,
        0xEA,
        ...'pe;1000\n'.codeUnits,
      ]),
      attendu,
    );
    // UTF-16 LE avec BOM.
    expect(
      lireTableur([
        0xFF,
        0xFE,
        for (final u in 'Nom\tPrix\nCrêpe\t1000\n'.codeUnits) ...[
          u & 255,
          u >> 8,
        ],
      ]),
      attendu,
    );
    expect(lireTableur(utf8.encode('sep=;\nNom;Prix\nCrêpe;1000\n')), attendu);
  });

  test(
    'un ancien .xls et un fichier vide sont refusés avec la marche à suivre',
    () {
      expect(
        () => lireTableur([0xD0, 0xCF, 0x11, 0xE0, 0, 0]),
        throwsA(isA<TableurIllisible>()),
      );
      expect(() => lireTableur([]), throwsA(isA<TableurIllisible>()));
      expect(
        () => lireTableur([0x50, 0x4B, 3, 4, 1, 2, 3]),
        throwsA(isA<TableurIllisible>()),
      );
    },
  );

  test('les classeurs embarqués (assets/import) sont ceux de docs/data', () {
    for (final c in ['m6-stocks', 'm5-bar', 'm4-restaurant']) {
      expect(
        File('assets/import/modele_import_$c.xlsx').readAsBytesSync(),
        File('../docs/data/modele_import_$c.xlsx').readAsBytesSync(),
        reason: 'recopier docs/data/modele_import_$c.xlsx dans assets/import/',
      );
    }
  });

  group('la carte du Gîte Chez Noël (docs/data), importée par le poste', () {
    late AppDatabase db;
    late ProviderContainer conteneur;
    late MoteurImportLocal moteur;

    setUp(() async {
      db = await baseImport();
      conteneur = conteneurImport(db);
      moteur = conteneur.read(moteurImportProvider);
    });
    tearDown(() async {
      conteneur.dispose();
      await db.close();
    });

    List<int> fichier(String cle) {
      final f = File('../docs/data/modele_import_$cle.xlsx');
      expect(f.existsSync(), isTrue, reason: f.path);
      return f.readAsBytesSync();
    }

    ImporteurLocal importeur(String cle) => conteneur
        .read(importeursLocauxProvider)
        .singleWhere((i) => i.cle == cle);

    test(
      'm6 → m5 → m4 : 9 articles, 9 boissons, 86 plats, aucun mouvement',
      () async {
        final tableaux = {
          for (final c in ['m6-stocks', 'm5-bar', 'm4-restaurant'])
            c: lireTableur(fichier(c)),
        };
        expect(tableaux['m6-stocks']!.length - 1, 9);
        expect(tableaux['m5-bar']!.length - 1, 9);
        expect(tableaux['m4-restaurant']!.length - 1, 86);

        // m5 avant m6 : refusé, la boisson se lie à un article existant.
        final tropTot = await moteur.controler(
          importeur('m5-bar'),
          fichier('m5-bar'),
        );
        expect(tropTot.ok, isFalse);

        Future<int> compter(String table) async =>
            (await db
                    .customSelect('SELECT COUNT(*) AS n FROM $table')
                    .getSingle())
                .read<int>('n');
        final avant = {
          for (final t in [
            'articles_local',
            'cartes_boisson_local',
            'plats_local',
            'mouvements_stock_local',
          ])
            t: await compter(t),
        };

        for (final cle in ['m6-stocks', 'm5-bar', 'm4-restaurant']) {
          final issue = await moteur.appliquer(importeur(cle), fichier(cle));
          expect(issue, isA<ImportFait>(), reason: '$cle : $issue');
          expect((issue as ImportFait).importees, tableaux[cle]!.length - 1);
        }

        expect(await compter('articles_local'), avant['articles_local']! + 9);
        expect(
          await compter('cartes_boisson_local'),
          avant['cartes_boisson_local']! + 9,
        );
        expect(await compter('plats_local'), avant['plats_local']! + 86);
        expect(
          await compter('mouvements_stock_local'),
          avant['mouvements_stock_local'],
          reason: 'le stock s’ajoute après : aucune quantité importée',
        );

        Future<String> prix(String table, String libelle) async =>
            (await db
                    .customSelect(
                      'SELECT prix_vente AS p FROM $table WHERE libelle = ?',
                      variables: [Variable.withString(libelle)],
                    )
                    .getSingle())
                .data['p']
                .toString();
        expect(
          await prix('cartes_boisson_local', "Jus d'ananas (moyen)"),
          contains('1500'),
        );
        expect(
          await prix('cartes_boisson_local', "Jus d'ananas (grand)"),
          contains('2000'),
        );
        expect(await prix('plats_local', 'Salade du Chef'), contains('4000'));
        expect(await prix('plats_local', 'Wassa wassa'), '0');
      },
    );
  });
}
