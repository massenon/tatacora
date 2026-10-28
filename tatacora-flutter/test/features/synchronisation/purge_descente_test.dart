import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/hebergement/data/parc_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/aligneur_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/data/journal_reception_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/journal_reception.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/vehicules/data/vehicule_dao.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/vehicule.dart';

import 'support/faux_transport.dart';

/// A5 (28/10/2026) — LA DESCENTE d'une purge faite ailleurs : le serveur sert un
/// élément `supprime: true` (unités d'hébergement et véhicules seulement) ; le
/// poste le rejoue SEULEMENT si aucune saisie locale n'y est rattachée, sinon il
/// le CONSERVE et le dit au journal de réception. Rien n'est enfilé : le serveur a
/// déjà purgé.
void main() {
  late BancSync b;
  late ParcDao parc;
  late VehiculeDao vehicules;
  late String categorie;

  setUp(() async {
    b = await BancSync.creer();
    await b.semerAuteur();
    parc = ParcDao(b.db);
    vehicules = VehiculeDao(b.db);
    categorie = (await parc.creerCategorie(
      libelle: 'Standard',
      capaciteMax: 2,
      tarifBase: 10000,
    )).id;
    await b.db
        .into(b.db.clientsLocal)
        .insert(
          ClientsLocalCompanion.insert(
            id: 'cli-1',
            nom: 'KORA',
            telephone: '+229 01 00 00 00 01',
            typeClient: 'particulier',
          ),
        );
    // Ce que le poste a déjà envoyé n'est pas l'objet : la file repart vide.
    await b.db.customStatement('DELETE FROM operations_sync_local');
  });
  tearDown(() => b.fermer());

  /// Ce que le serveur sert pour une purge : `donnees` vide.
  Map<String, Object?> purge(String table, String id) => {
    'table': table,
    'id': id,
    'supprime': true,
    'actif': false,
    'modifie_le': '2026-10-28 08:00:00',
    'donnees': <String, Object?>{},
  };

  Future<BilanDescente> descendre(List<Map<String, Object?>> elements) async =>
      b
          .descente(FauxTransport((r) => FauxCatalogue(elements).repondre(r)))
          .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});

  Future<bool> uniteExiste(String id) async =>
      (await (b.db.select(
        b.db.unitesHebergementLocal,
      )..where((u) => u.id.equals(id))).getSingleOrNull()) !=
      null;

  Future<bool> vehiculeExiste(String id) async =>
      (await (b.db.select(
        b.db.vehiculesLocal,
      )..where((v) => v.id.equals(id))).getSingleOrNull()) !=
      null;

  Future<String> unite(String numero) async {
    final id = await parc.creerUnite(numero: numero, categorieId: categorie);
    await b.db.customStatement(
      "UPDATE unites_hebergement_local SET statut = 'hors_service' "
      "WHERE id = '$id'",
    );
    await b.db.customStatement('DELETE FROM operations_sync_local');
    return id;
  }

  Future<String> vehicule(String plaque) async {
    final v = await vehicules.enregistrerVehicule(
      immatriculation: plaque,
      categorie: CategorieVehicule.values.first,
      tarifJour: 20000,
    );
    await b.db.customStatement(
      "UPDATE vehicules_local SET statut = 'hors_service' WHERE id = '${v.id}'",
    );
    await b.db.customStatement('DELETE FROM operations_sync_local');
    return v.id;
  }

  Future<EntreeJournalReception?> journal(String table, String id) =>
      JournalReceptionDao(b.db).lire(table, id);

  test('rien de rattaché : l’unité et le véhicule sont retirés, le journal le '
      'DIT, et rien n’est enfilé', () async {
    final u = await unite('U1');
    final v = await vehicule('AB-123');

    final bilan = await descendre([
      purge('unites_hebergement', u),
      purge('vehicules', v),
    ]);

    expect(bilan.etat, EtatDescente.aJour, reason: '$bilan');
    expect(
      (bilan.recus, bilan.appliques, bilan.conservesLocalement),
      (2, 2, 0),
    );
    expect(await uniteExiste(u), isFalse);
    expect(await vehiculeExiste(v), isFalse);
    expect(await OperationsSyncDao(b.db).operations(), isEmpty);
    final e = (await journal('unites_hebergement', u))!;
    expect(e.issue, IssueReception.aligne);
    expect(e.motif, contains('Purgé définitivement sur un autre poste'));
    expect(e.etiquette, 'Purge définitive');
  });

  test('une réservation LOCALE cite l’unité : elle est CONSERVÉE, le journal '
      'dit pourquoi, et la descente suivante ne la lâche pas', () async {
    final u = await unite('U2');
    await b.db
        .into(b.db.reservationsLocal)
        .insert(
          ReservationsLocalCompanion.insert(
            id: 'res-1',
            reference: 'RES-1',
            clientId: 'cli-1',
            uniteId: u,
            dateArrivee: DateTime(2026, 9, 1),
            dateDepart: DateTime(2026, 9, 3),
            statut: 'terminee',
            tarifNuit: 10000,
          ),
        );

    final bilan = await descendre([purge('unites_hebergement', u)]);

    expect((bilan.appliques, bilan.conservesLocalement), (0, 1));
    expect(await uniteExiste(u), isTrue);
    final e = (await journal('unites_hebergement', u))!;
    expect(e.issue, IssueReception.conserve);
    expect(e.motif, AligneurCatalogue.raisonPurgeSaisieRattachee);
    expect(e.motif, contains('réservation'));

    // Repassage : toujours conservée (la reprise ne la supprime pas).
    final encore = await descendre([purge('unites_hebergement', u)]);
    expect(encore.conservesLocalement, 1);
    expect(await uniteExiste(u), isTrue);
  });

  test(
    'un contrat OU un entretien local cite le véhicule : conservé',
    () async {
      final avecContrat = await vehicule('CT-1');
      final avecEntretien = await vehicule('EN-1');
      final libre = await vehicule('OK-1');
      await b.db
          .into(b.db.contratsLocationLocal)
          .insert(
            ContratsLocationLocalCompanion.insert(
              id: 'ctr-1',
              vehiculeId: avecContrat,
              clientId: 'cli-1',
              dateDebut: DateTime(2026, 9, 1),
              dateFin: DateTime(2026, 9, 3),
            ),
          );
      await b.db
          .into(b.db.entretiensVehiculeLocal)
          .insert(
            EntretiensVehiculeLocalCompanion.insert(
              id: 'ent-1',
              vehiculeId: avecEntretien,
              type: 'entretien',
              date: DateTime(2026, 9, 1),
              cout: 15000,
            ),
          );

      final bilan = await descendre([
        purge('vehicules', avecContrat),
        purge('vehicules', avecEntretien),
        purge('vehicules', libre),
      ]);

      expect((bilan.appliques, bilan.conservesLocalement), (1, 2));
      expect(await vehiculeExiste(avecContrat), isTrue);
      expect(await vehiculeExiste(avecEntretien), isTrue);
      expect(await vehiculeExiste(libre), isFalse);
      expect(
        (await journal('vehicules', avecContrat))!.motif,
        contains('contrat de location'),
      );
    },
  );

  test('une saisie locale qui ATTEND de partir (même sans réservation) '
      'protège aussi l’élément', () async {
    final u = await unite('U3');
    await b.db.transaction(
      () => b.dao.enfiler(
        table: TableSynchronisee.unitesHebergement,
        entiteId: u,
        type: TypeOperationSync.modification,
        payload: const {'actif': true},
      ),
    );

    final bilan = await descendre([purge('unites_hebergement', u)]);

    expect(bilan.conservesLocalement, 1);
    expect(await uniteExiste(u), isTrue);
    expect(
      (await journal('unites_hebergement', u))!.motif,
      AligneurCatalogue.raisonPurgeSaisieEnAttente,
    );
  });

  test(
    'un élément que ce poste n’a jamais eu : rien à retirer, aligné',
    () async {
      final bilan = await descendre([
        purge('unites_hebergement', 'inconnue-1'),
        purge('vehicules', 'inconnu-1'),
      ]);
      expect((bilan.appliques, bilan.refuses), (2, 0));
    },
  );

  test('REGISTRE FERMÉ : une suppression d’une autre table est un élément '
      'ILLISIBLE, refusé et compté — jamais rejoué', () async {
    final bilan = await descendre([purge('clients', 'cli-1')]);

    expect((bilan.appliques, bilan.refuses), (0, 1));
    expect(
      (await b.db.select(b.db.clientsLocal).get()).map((c) => c.id),
      contains('cli-1'),
    );
  });

  test('l’élément JSON : `donnees` vide en liste (PHP rend [] pour un tableau '
      'vide) ou en objet, et il survit à la garde (aller-retour)', () {
    for (final donnees in <Object>[<String, Object?>{}, <Object?>[]]) {
      final brut = {...purge('vehicules', 'v-1'), 'donnees': donnees};
      final e = ElementCatalogue.depuisJson(brut)!;
      expect(e.supprime, isTrue);
      expect(e.actif, isFalse);
      expect(e.donnees, isEmpty);
      final relu = ElementCatalogue.depuisJson(e.versJson())!;
      expect((relu.supprime, relu.table, relu.id), (true, e.table, 'v-1'));
    }
    // Un élément ordinaire n'est jamais « supprimé » par omission.
    final ordinaire = ElementCatalogue.depuisJson(
      element('unites_hebergement', 'u-1', {'numero': '1'}),
    )!;
    expect(ordinaire.supprime, isFalse);
    expect(ordinaire.versJson().containsKey('supprime'), isFalse);
    // Une table hors registre fermé, ou une donnée absente d'un élément ordinaire.
    expect(ElementCatalogue.depuisJson(purge('clients', 'c-1')), isNull);
    expect(
      ElementCatalogue.depuisJson({
        ...element('unites_hebergement', 'u-1', {}),
        'donnees': <Object?>[],
      }),
      isNull,
    );
  });
}
