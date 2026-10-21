import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/comptabilite/data/ecritures_serveur_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/aligneur_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart';

/// Les écritures VALIDÉES du serveur descendent dans un miroir de LECTURE
/// (v34, 21/10/2026) : ajoutées si elles manquent, jamais réécrites (RG-11),
/// jamais enfilées, et sans toucher à `ecritures_local`, le journal du poste.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.enMemoire());
  tearDown(() => db.close());

  Map<String, Object?> ligne({
    Object? debit = '0.00',
    Object? credit = '1500.00',
    Object? annee = 2031,
  }) => {
    'exercice_id': 'ex-srv',
    'annee': annee,
    'code_journal': 'VTE',
    'numero_compte': '7061',
    'libelle_compte': 'Ventes de services',
    'classe': '7',
    'date_ecriture': '2031-06-15',
    'libelle': 'Vente',
    'debit': debit,
    'credit': credit,
    'numero_piece': 'VTE-2031-00001',
    'ecriture_contrepassee_id': null,
    'journal_id': 'j',
    'compte_id': 'c',
  };

  Future<IssueAlignement> descendre(
    Map<String, Object?> donnees, {
    String id = 'ec-1',
  }) => db.transaction(
    () =>
        AligneurCatalogue(
          db,
          DescenteCatalogueDao(db),
          auteur: () async => null,
        ).aligner(
          ElementCatalogue(
            table: TableDescendue.ecrituresComptables,
            id: id,
            actif: true,
            modifieLe: '2031-06-15 10:00:00',
            donnees: donnees,
          ),
        ),
  );

  test('une écriture validée est écrite en centimes, avec son compte et son '
      'journal ; rien ne part, le journal du poste est intact', () async {
    expect(await descendre(ligne()), isA<Aligne>());

    final l = await db.select(db.ecrituresServeurLocal).getSingle();
    expect(l.id, 'ec-1');
    expect(l.annee, 2031);
    expect(l.codeJournal, 'VTE');
    expect(l.numeroCompte, '7061');
    expect(l.libelleCompte, 'Ventes de services');
    expect(l.classe, '7');
    expect(l.creditCentimes, 150000);
    expect(l.debitCentimes, 0);
    expect(l.numeroPiece, 'VTE-2031-00001');
    expect(await OperationsSyncDao(db).operations(), isEmpty);
    expect(await db.select(db.ecrituresLocal).get(), isEmpty);
  });

  test('une ligne déjà reçue n’est JAMAIS réécrite (RG-11)', () async {
    await descendre(ligne());
    expect(await descendre(ligne(credit: '9999.00')), isA<Aligne>());

    final l = await db.select(db.ecrituresServeurLocal).getSingle();
    expect(l.creditCentimes, 150000, reason: 'la première version fait foi');
  });

  test('une fraction de centime, un champ absent, une année illisible : '
      'refusés, rien d’écrit', () async {
    for (final d in [
      ligne(credit: '12.345'),
      ligne(debit: null),
      ligne(annee: 'x'),
      {...ligne(), 'code_journal': null},
      {...ligne(), 'date_ecriture': null},
    ]) {
      expect(await descendre(d), isA<RefuseParLePoste>(), reason: '$d');
    }
    expect(await db.select(db.ecrituresServeurLocal).get(), isEmpty);
  });

  test('la réception se compte : nombre et dernière date', () async {
    final dao = EcrituresServeurDao(db);
    expect((await dao.reception()).nombre, 0);
    expect((await dao.reception()).derniereDate, isNull);
    await descendre(ligne());
    await descendre({...ligne(), 'date_ecriture': '2031-07-02'}, id: 'ec-2');
    final r = await dao.reception();
    expect(r.nombre, 2);
    expect(r.derniereDate, '2031-07-02');
    expect(await dao.deLAnnee(2031), hasLength(2));
    expect(await dao.deLAnnee(2030), isEmpty);
  });

  test('la table est descendue après les exercices, et porte son libellé', () {
    final noms = [for (final t in TableDescendue.values) t.nomServeur];
    expect(
      noms.indexOf('exercices_comptables'),
      lessThan(noms.indexOf('ecritures_comptables')),
    );
    expect(
      libelleTableServeur('ecritures_comptables'),
      'Écritures comptables validées',
    );
    expect(TableDescendue.ecrituresComptables.tableSynchronisee, isNull);
  });
}
