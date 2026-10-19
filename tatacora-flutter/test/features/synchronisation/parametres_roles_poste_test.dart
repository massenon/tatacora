import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_dao.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_depot_local.dart';
import 'package:tatacora_flutter/features/rh/data/paie_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/aligneur_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/transverse/data/roles_dao.dart';

/// Lot 10e (audit de couverture du 18/10/2026) : un enregistrement de l'écran
/// Paramètres part en UN lot ; un rôle part avec son libellé et sa matrice
/// entière. Ce que le serveur paramètre descend — les taux de la paie vers
/// leur seul auteur, la matrice d'un rôle recopiée sur ses comptes — sans
/// écraser une saisie locale qui attend de partir.
void main() {
  late AppDatabase db;
  final admin = GardeAcces(const {'ROLES': 'C'});

  setUp(() => db = AppDatabase.enMemoire());
  tearDown(() => db.close());

  Future<List<OperationSync>> file(TableSynchronisee t) =>
      OperationsSyncDao(db).operations(table: t);

  Map<String, Object?> charge(OperationSync o) =>
      jsonDecode(o.payload) as Map<String, Object?>;

  Future<IssueAlignement> descendre(
    TableDescendue table,
    String id,
    Map<String, Object?> donnees,
  ) => db.transaction(
    () =>
        AligneurCatalogue(
          db,
          DescenteCatalogueDao(db),
          auteur: () async => null,
        ).aligner(
          ElementCatalogue(
            table: table,
            id: id,
            actif: true,
            modifieLe: '2026-10-18 10:00:00',
            donnees: donnees,
          ),
        ),
  );

  Future<void> compte(String id, String role) => db
      .into(db.utilisateursLocal)
      .insert(
        UtilisateursLocalCompanion.insert(
          id: id,
          login: id,
          nom: id,
          role: role,
          droitsJson: '{}',
          sel: 's',
          empreinte: 'e',
          iterations: 1,
          dateCreation: DateTime(2026, 10, 1),
          dateMotDePasse: DateTime(2026, 10, 1),
        ),
      );

  group('Paramètres', () {
    test('un enregistrement part en UN lot : les clés modifiées seules, '
        'taux de la paie compris, vidée = null', () async {
      final depot = ParametresDepotLocal(db);
      await depot.ecrire({
        'tva_active': 'true',
        'taux_tva': '18',
        'taux_vps': '4',
      }, auteurId: null);
      await depot.ecrire({
        'tva_active': 'true',
        'taux_tva': null,
      }, auteurId: null);

      final ops = await file(TableSynchronisee.parametresSysteme);
      expect(ops, hasLength(2));
      expect(ops.first.type, TypeOperationSync.creation);
      expect(ops.first.entiteId, isNot(ops.last.entiteId));
      expect(charge(ops.first), {
        'valeurs': {'taux_vps': '4', 'tva_active': 'true', 'taux_tva': '18'},
      });
      expect(charge(ops.last), {
        'valeurs': {'taux_tva': null},
      });

      // Rien de modifié : rien ne part.
      await depot.ecrire({'tva_active': 'true'}, auteurId: null);
      expect(await file(TableSynchronisee.parametresSysteme), hasLength(2));
    });

    test('la descente pose la valeur du serveur (taux de la paie vers '
        'PaieDao), vide = vidée, hors registre ignorée, sans rien '
        'renvoyer', () async {
      expect(
        await descendre(TableDescendue.parametresSysteme, 's-1', {
          'cle': 'tolerance_reception_pct',
          'valeur': '5',
        }),
        isA<Aligne>(),
      );
      await descendre(TableDescendue.parametresSysteme, 's-2', {
        'cle': 'taux_vps',
        'valeur': '4',
      });
      await descendre(TableDescendue.parametresSysteme, 's-3', {
        'cle': 'cle_inventee',
        'valeur': 'x',
      });

      expect((await ParametresDao(db).lireTout()), {
        'tolerance_reception_pct': '5',
      });
      expect((await PaieDao(db).taux())['taux_vps'], '4');

      await descendre(TableDescendue.parametresSysteme, 's-1', {
        'cle': 'tolerance_reception_pct',
        'valeur': '',
      });
      expect(await ParametresDao(db).lireTout(), isEmpty);
      expect(await OperationsSyncDao(db).operations(), isEmpty);
    });

    test('un enregistrement local qui attend de partir est conservé', () async {
      await ParametresDepotLocal(
        db,
      ).ecrire({'tolerance_reception_pct': '7'}, auteurId: null);

      expect(
        await descendre(TableDescendue.parametresSysteme, 's-1', {
          'cle': 'tolerance_reception_pct',
          'valeur': '5',
        }),
        isA<ConserveLocalement>(),
      );
      expect(
        (await ParametresDao(db).lireTout())['tolerance_reception_pct'],
        '7',
      );
    });
  });

  group('Rôles', () {
    test('créer un rôle et définir ses droits part au serveur, la matrice '
        'ENTIÈRE et le libellé à chaque fois', () async {
      final dao = RolesDao(db);
      final id = await dao.creerRole(auteur: admin, libelle: 'Économe');
      await dao.definirDroits(
        auteur: admin,
        roleId: id,
        niveaux: {ModuleTatacora.m6Stocks: NiveauAcces.complet},
      );

      final ops = await file(TableSynchronisee.roles);
      expect(ops.map((o) => o.type), [
        TypeOperationSync.creation,
        TypeOperationSync.modification,
      ]);
      expect(ops.every((o) => o.entiteId == id), isTrue);
      final droits = charge(ops.last)['droits']! as Map;
      expect(charge(ops.last)['libelle'], 'Économe');
      expect(droits['M6'], 'C');
      expect(droits['M1'], '-');
      expect(droits.containsKey('ANNULATIONS'), isTrue);
    });

    test('un rôle du socle descend par son libellé : correspondance '
        'retenue, matrice recopiée sur ses comptes, rien ne repart', () async {
      final dao = RolesDao(db);
      await dao.installerSocle();
      await compte('u-1', 'barman');
      final local = (await dao.parLibelle('barman'))!;

      expect(
        await descendre(TableDescendue.roles, 'srv-barman', {
          'libelle': 'barman',
          'description': 'Bar',
          'droits': {'M5': 'C', 'M9': 'L', 'M1': '-'},
        }),
        isA<Aligne>(),
      );

      expect(
        await DescenteCatalogueDao(db).idLocal('roles', 'srv-barman'),
        local.id,
      );
      final u = await (db.select(
        db.utilisateursLocal,
      )..where((u) => u.id.equals('u-1'))).getSingle();
      expect((jsonDecode(u.droitsJson) as Map)['M9'], 'L');
      expect((await dao.parLibelle('barman'))!.description, 'Bar');
      expect(await OperationsSyncDao(db).operations(), isEmpty);

      // Un rôle inconnu du poste y naît sous l'identifiant du serveur.
      await descendre(TableDescendue.roles, 'srv-econome', {
        'libelle': 'econome',
        'droits': {'M6': 'C'},
      });
      expect((await dao.parLibelle('econome'))!.id, 'srv-econome');
    });

    test('une matrice locale qui attend de partir est conservée', () async {
      final dao = RolesDao(db);
      await dao.installerSocle();
      final barman = (await dao.parLibelle('barman'))!;
      await dao.definirDroits(
        auteur: admin,
        roleId: barman.id,
        niveaux: {ModuleTatacora.m5Bar: NiveauAcces.lecture},
      );

      expect(
        await descendre(TableDescendue.roles, 'srv-barman', {
          'libelle': 'barman',
          'droits': {'M5': 'C'},
        }),
        isA<ConserveLocalement>(),
      );
      expect(
        (jsonDecode((await dao.parLibelle('barman'))!.droitsJson) as Map)['M5'],
        'L',
      );
    });
  });
}
