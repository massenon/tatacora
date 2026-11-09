import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/aligneur_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart';

/// La VALEUR D'ACHAT DE RÉFÉRENCE descend du serveur (`articles.prix_achat`,
/// poste v57, 09/11/2026) — sans jamais effacer ni écraser celle du poste.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.enMemoire());
  tearDown(() => db.close());

  Future<IssueAlignement> descendre(Map<String, Object?> donnees) =>
      db.transaction(
        () =>
            AligneurCatalogue(
              db,
              DescenteCatalogueDao(db),
              auteur: () async => null,
            ).aligner(
              ElementCatalogue(
                table: TableDescendue.articles,
                id: 'a-1',
                actif: true,
                modifieLe: '2026-11-09 10:00:00',
                donnees: {
                  'libelle': 'Huile',
                  'unite_mesure': 'L',
                  'suivi': 'permanent',
                  'seuil_alerte': '0.00',
                  ...donnees,
                },
              ),
            ),
      );

  Future<int?> reference() async => (await (db.select(
    db.articlesLocal,
  )..where((a) => a.id.equals('a-1'))).getSingle()).prixAchatReference;

  test('le prix du serveur est posé quand le poste n’en a pas', () async {
    expect(await descendre({'prix_achat': '1200.00'}), isA<Aligne>());
    expect(await reference(), 12000000);
  });

  test('un article sans prix au serveur ne l’efface jamais au poste', () async {
    await descendre({'prix_achat': '1200.00'});
    await descendre({'prix_achat': null});
    expect(await reference(), 12000000);
  });

  test(
    'une valeur locale n’est jamais écrasée par une valeur du serveur',
    () async {
      await descendre({});
      expect(
        await StocksDao(db).poserValeurAchatReference('a-1', 5000000),
        isTrue,
      );

      await descendre({'prix_achat': '1200.00'});
      expect(await reference(), 5000000);
    },
  );

  test('« poser » ne remplace jamais, et zéro ne pose rien', () async {
    await descendre({});
    final dao = StocksDao(db);
    expect(await dao.poserValeurAchatReference('a-1', 0), isFalse);
    expect(await reference(), isNull);
    expect(await dao.poserValeurAchatReference('a-1', 700000), isTrue);
    expect(await dao.poserValeurAchatReference('a-1', 900000), isFalse);
    expect(await reference(), 700000);
  });
}
