@Timeout(Duration(minutes: 3))
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/crm/data/client_dao.dart';
import 'package:tatacora_flutter/features/crm/domain/entities/client.dart';
import 'package:tatacora_flutter/features/tourisme/data/tourisme_dao.dart';
import 'package:tatacora_flutter/features/tourisme/domain/departs.dart';
import 'package:tatacora_flutter/features/tourisme/domain/entities/circuit.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import '../synchronisation/support/scenario_file.dart';

/// Les gestes d'écriture de l'écran Tourisme du poste — « + Prestation »
/// (thème « Autre » compris), « Ajouter un guide touristique » et
/// « + Réservation » — rejoués contre le VRAI serveur
/// (`tool/sync/valider_charge.php`, règles de l'API, gestionnaires de
/// synchronisation) : un geste que le serveur rejette est un geste que le poste
/// n'aurait pas dû accepter.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('les trois gestes du poste sont acceptés par le serveur, thème Autre '
      'et capacité cumulée comprises', () async {
    final db = AppDatabase.enMemoire();
    final dao = TourismeDao(db);

    final client = (await ClientDao(db).creer(
      nom: 'KORA TOURISME',
      telephone: '97000077',
      type: TypeClientReferentiel.particulier,
    )).id;
    final circuit = (await dao.enregistrerCircuit(
      nom: 'Soirée contes Natitingou',
      theme: 'autre',
      zone: 'Atacora',
      prix: 5000,
      capaciteMax: 6,
      duree: 'Soirée',
    )).id;
    final guide = (await dao.enregistrerGuide(
      nom: 'KOTO Jean',
      zoneCompetence: 'Nord Bénin',
      certification: 'Guide national',
      tarifJourFrancs: 20000,
    )).id;
    await dao.reserver(
      circuitId: circuit,
      clientId: client,
      guideId: guide,
      dateCircuit: DateTime(2026, 11, 20),
      nbParticipants: 4,
    );
    // Le DAO refuse le dépassement du cumul AVANT d'écrire, comme le serveur.
    await expectLater(
      dao.reserver(
        circuitId: circuit,
        clientId: client,
        guideId: guide,
        dateCircuit: DateTime(2026, 11, 20),
        nbParticipants: 3,
      ),
      throwsA(isA<RefusTourisme>()),
    );

    final operations = await fileAuProtocole(db);
    await db.close();

    final sortie = await executerPhp(
      'valider_charge.php',
      dossier: 'sync',
      entree: {
        'aujourdhui': '2026-10-26',
        'poste_id': 'poste-essai-tourisme',
        'operations': operations,
      },
    );

    final resultats = [
      for (final r in sortie['resultats'] as List) r as Map<String, dynamic>,
    ];
    expect(resultats.map((r) => r['statut']).toSet(), {
      'synchronise',
    }, reason: 'motifs : ${resultats.map((r) => r['motif']).toList()}');

    final etats = sortie['etats'] as Map<String, dynamic>;
    expect((etats['circuits:$circuit'] as Map)['theme'], 'autre');
    final g = etats['guides:$guide'] as Map;
    expect(
      (g['certification'], g['zone_competence'], g['tarif_jour']),
      ('Guide national', 'Nord Bénin', '20000.00'),
    );
  });

  test('le thème d’une prestation est celui du registre fermé du serveur', () {
    expect(themesCircuit, ['aventure', 'culture', 'faune', 'nature', 'autre']);
    expect(libelleTheme('autre'), 'Autre');
  });
}
