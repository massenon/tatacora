import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/facturation/data/prefill_proforma_poste.dart';

/// Le préremplissage du poste : mêmes règles et libellés que `PrefillProforma.php`.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await db
        .into(db.clientsLocal)
        .insert(
          ClientsLocalCompanion.insert(
            id: 'c1',
            nom: 'KORA',
            prenom: const Value('Jean'),
            telephone: '0190123456',
            typeClient: 'particulier',
            ifu: const Value('0202011344660'),
          ),
        );
  });
  tearDown(() => db.close());

  test('un circuit : client, objet, circuit x participants', () async {
    await db
        .into(db.circuitsLocal)
        .insert(
          CircuitsLocalCompanion.insert(
            id: 'ci1',
            nom: 'Pendjari',
            theme: 'Nature',
            zone: 'Nord',
            prix: 75000,
            capaciteMax: 10,
          ),
        );
    await db
        .into(db.guidesLocal)
        .insert(
          GuidesLocalCompanion.insert(
            id: 'g1',
            nom: 'Guide',
            certification: const Value('Officielle'),
            zoneCompetence: const Value('Nord'),
            tarifJour: const Value(10000),
          ),
        );
    await db
        .into(db.reservationsTourLocal)
        .insert(
          ReservationsTourLocalCompanion.insert(
            id: 'rt1',
            circuitId: 'ci1',
            clientId: 'c1',
            guideId: 'g1',
            dateCircuit: DateTime(2026, 12, 1),
            nbParticipants: 4,
            statut: 'reservee',
          ),
        );

    final p = (await PrefillProformaPoste.depuis(db, 'tourisme', 'rt1'))!;
    expect(p.clientNom, 'Jean KORA');
    expect(p.clientIfu, '0202011344660');
    expect(p.objet, 'Circuit touristique — Pendjari');
    expect(p.sourceModule, 'tourisme');
    expect(p.lignes.single, (
      designation: 'Circuit Pendjari du 01/12/2026 (par participant)',
      quantite: 4,
      prixUnitaire: 75000,
    ));
  });

  test(
    'une source inconnue donne null ; un événement donne une proforma vide',
    () async {
      expect(
        await PrefillProformaPoste.depuis(db, 'location', 'absent'),
        isNull,
      );
      expect(await PrefillProformaPoste.depuis(db, 'tourisme', null), isNull);
      expect(await PrefillProformaPoste.depuis(db, 'inconnu', 'x'), isNull);
      final e = (await PrefillProformaPoste.depuis(db, 'evenement', null))!;
      expect(e.sourceModule, 'evenement');
      expect(e.clientNom, '');
      expect(e.lignes, isEmpty);
    },
  );
}
