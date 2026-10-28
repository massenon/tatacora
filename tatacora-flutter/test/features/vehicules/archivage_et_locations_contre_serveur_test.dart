@Timeout(Duration(minutes: 3))
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/etats/domain/apercus_etats.dart';
import 'package:tatacora_flutter/features/vehicules/data/vehicule_dao.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/contrat_location.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/vehicule.dart';
import 'package:tatacora_flutter/features/vehicules/domain/regles_vehicules.dart';

import '../comptabilite/support/outils_comptabilite.dart';

/// PRD « Deux corrections Locations / archivage véhicule » (B1, B2), CONFRONTÉES
/// au serveur en l'exécutant (piège 12) : `tool/vehicules/rejouer_archivage_et_locations.php`
/// fait tourner le vrai `ParcVehiculeService::contratsEngages` et le vrai
/// `EtatLocations`, au 21/10/2026, sur quatre véhicules : contrat fini hier,
/// fini aujourd'hui, fini demain, annulé.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Map<String, dynamic> serveur;
  late AppDatabase db;
  late VehiculeDao dao;
  final aujourdhui = DateTime(2026, 10, 21, 10);

  const cas = <String, (String, String, String?)>{
    'fin_hier': ('2026-10-18', '2026-10-20', 'actif'),
    'fin_aujourdhui': ('2026-10-19', '2026-10-21', 'actif'),
    'fin_demain': ('2026-10-19', '2026-10-22', 'actif'),
    'annule': ('2026-10-25', '2026-10-28', statutContratAnnule),
  };

  setUpAll(() async {
    serveur = await executerPhp(
      'rejouer_archivage_et_locations.php',
      dossier: 'vehicules',
    );
  });

  setUp(() async {
    db = AppDatabase.enMemoire();
    dao = VehiculeDao(db);
    await db
        .into(db.clientsLocal)
        .insert(
          ClientsLocalCompanion.insert(
            id: 'cli-1',
            nom: 'KORA',
            telephone: '97000001',
            typeClient: 'particulier',
          ),
        );
  });
  tearDown(() => db.close());

  /// Un véhicule et un contrat par cas, posés tels quels (dates passées
  /// comprises : `creerContrat` refuserait un départ révolu).
  Future<Map<String, Vehicule>> poser() async {
    final vehicules = <String, Vehicule>{};
    var n = 0;
    for (final MapEntry(:key, :value) in cas.entries) {
      n++;
      final v = await dao.enregistrerVehicule(
        immatriculation: 'BJ-$n',
        categorie: CategorieVehicule.voiture,
        tarifJour: 10000,
      );
      vehicules[key] = v;
      final (debut, fin, statut) = value;
      final jours = DateTime.parse(
        fin,
      ).difference(DateTime.parse(debut)).inDays;
      await db
          .into(db.contratsLocationLocal)
          .insert(
            ContratsLocationLocalCompanion.insert(
              id: 'c-$key',
              vehiculeId: v.id,
              clientId: 'cli-1',
              dateDebut: DateTime.parse(debut),
              dateFin: DateTime.parse(fin),
              statut: Value(statut),
              montant: Value(10000 * jours),
            ),
          );
    }
    return vehicules;
  }

  test('le script a rendu les quatre cas et l’état (extraction non vide)', () {
    expect((serveur['engages'] as Map).keys, cas.keys);
    expect((serveur['etat'] as Map<String, dynamic>)['lignes'], isNotEmpty);
  });

  test(
    'B2 : archiver un véhicule répond comme '
    '`ParcVehiculeService::contratsEngages`, jour de restitution compris',
    () async {
      final vehicules = await poser();
      final engages = serveur['engages'] as Map<String, dynamic>;

      for (final cle in cas.keys) {
        final id = vehicules[cle]!.id;
        final attendu = (engages[cle] as int) > 0;
        if (attendu) {
          await expectLater(
            dao.archiverVehicule(id, aujourdHui: aujourdhui),
            throwsA(
              isA<RefusVehicule>().having(
                (e) => e.message,
                'message',
                MessagesVehicules.archivageVerrouille(engages[cle] as int),
              ),
            ),
            reason: cle,
          );
        } else {
          final v = await dao.archiverVehicule(id, aujourdHui: aujourdhui);
          expect(v.statut, StatutVehicule.horsService, reason: cle);
        }
      }
      // Les trois jours significatifs, ancrés en dur : fin aujourd'hui REFUSE.
      expect(engages['fin_aujourdhui'], 1);
      expect(engages['fin_hier'], 0);
      expect(engages['annule'], 0);
    },
  );

  test('B1 : l’aperçu « Locations » exclut les contrats annulés, comme '
      '`EtatLocations`', () async {
    await poser();
    final parc = await dao.parc();
    final a = apercuLocations(await dao.contrats(), parc);
    final etat = serveur['etat'] as Map<String, dynamic>;

    expect(a.indicateur('Contrats'), etat['nombre']);
    expect(a.indicateur('Montant total'), etat['montant']);
    expect(
      a.lignes.map((l) => l[1]).toList()..sort(),
      (etat['lignes'] as List).cast<String>().toList()..sort(),
    );
  });
}
