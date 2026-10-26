@Timeout(Duration(minutes: 3))
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/crm/data/archivage_clients.dart';
import 'package:tatacora_flutter/features/vehicules/data/vehicule_dao.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/contrat_location.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/vehicule.dart';
import 'package:tatacora_flutter/features/vehicules/domain/regles_vehicules.dart';

import '../comptabilite/support/outils_comptabilite.dart';

/// L'ANNULATION d'un contrat de location, CONFRONTÉE au serveur en l'exécutant
/// (piège 12) : `tool/vehicules/rejouer_annulation_contrat.php` fait tourner le
/// vrai `ContratLocationService`, `ParcVehiculeService` et
/// `ReferentielClientService` (en transaction annulée), et le poste monte la
/// MÊME histoire sur sa base locale :
///
///  * RG-08 : le contrat actif bloque la plage (même phrase) ; annulé, il la
///    libère et un second contrat passe ;
///  * annuler deux fois : la phrase du serveur ;
///  * un contrat annulé n'engage plus le véhicule (archivage) ;
///  * un contrat annulé n'est plus un verrou d'archivage du client — l'écart
///    nommé « un contrat annulé au serveur compte encore ici » est LEVÉ ;
///  * les trois phrases de la vue (question, succès, verrou) sont relues du
///    fichier de langue exécuté, jamais recopiées.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Map<String, dynamic> serveur;
  late AppDatabase db;
  late VehiculeDao dao;
  late Vehicule vehicule;

  final aujourdhui = DateTime(2026, 10, 21, 10);

  setUpAll(() async {
    serveur = await executerPhp(
      'rejouer_annulation_contrat.php',
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
    vehicule = await dao.enregistrerVehicule(
      immatriculation: 'BJ-1',
      categorie: CategorieVehicule.voiture,
      tarifJour: 25000,
    );
  });
  tearDown(() => db.close());

  Future<ContratLocation> louer(String debut, String fin) => dao.creerContrat(
    SaisieContrat(
      vehiculeId: vehicule.id,
      clientId: 'cli-1',
      debut: DateTime.parse(debut),
      fin: DateTime.parse(fin),
      pieceIdentite: 'CNI-1',
      permisConduire: 'P-1',
    ),
  );

  Future<List<String>> verrousClient() => ArchivageClients(
    db,
    creances: () async => const [],
    maintenant: () => aujourdhui,
  ).verrous('cli-1');

  test('le script a rendu toute l’histoire (l’extraction n’est pas vide)', () {
    expect(serveur['annulation'], 'ok');
    expect(serveur['statut_apres'], 'annule');
    expect(serveur['rows_conservees'], 2, reason: 'rien n’est supprimé');
    expect((serveur['phrases'] as Map).length, 3);
  });

  test('les trois phrases de la vue sont celles du serveur, mot pour mot', () {
    final p = serveur['phrases'] as Map<String, dynamic>;
    expect(
      MessagesVehicules.questionAnnulerContrat('AB 1234 RB'),
      p['question'],
    );
    expect(MessagesVehicules.contratAnnule('AB 1234 RB'), p['succes']);
    expect(MessagesVehicules.contratDejaAnnule, p['deja_annule']);
    expect(MessagesVehicules.contratDejaAnnule, serveur['double_annulation']);
  });

  test('RG-08 : actif, le contrat bloque la plage ; annulé, il la libère '
      '— comme le serveur', () async {
    final c = await louer('2026-10-25', '2026-10-28');

    // Avant : même refus, même phrase.
    await expectLater(
      louer('2026-10-26', '2026-10-27'),
      throwsA(
        isA<RefusVehicule>().having(
          (e) => e.message,
          'message',
          serveur['chevauchement_avant'],
        ),
      ),
    );

    await dao.annulerContrat(c.id);

    final libre = await dao.disponibilite(
      vehiculeId: vehicule.id,
      debut: DateTime(2026, 10, 25),
      fin: DateTime(2026, 10, 28),
    );
    expect(libre.calendrierLibre, serveur['disponible_apres']);
    expect(
      (await louer('2026-10-26', '2026-10-27')).statut,
      statutContratActif,
      reason: serveur['second_contrat_apres'] as String,
    );
    expect(await db.select(db.contratsLocationLocal).get(), hasLength(2));
  });

  test('annuler deux fois : la phrase du serveur', () async {
    final c = await louer('2026-10-25', '2026-10-28');
    await dao.annulerContrat(c.id);

    await expectLater(
      dao.annulerContrat(c.id),
      throwsA(
        isA<RefusVehicule>().having(
          (e) => e.message,
          'message',
          serveur['double_annulation'],
        ),
      ),
    );
  });

  test('un contrat annulé n’engage plus le véhicule (archivage), comme '
      '`contratsEngages`', () async {
    final c = await louer('2026-10-25', '2026-10-28');
    expect(serveur['engages_avant'], 1);
    await expectLater(
      dao.archiverVehicule(vehicule.id, aujourdHui: aujourdhui),
      throwsA(isA<RefusVehicule>()),
    );

    expect(serveur['engages_apres_annulation'], 0);
    await dao.annulerContrat(c.id);
    await dao.archiverVehicule(vehicule.id, aujourdHui: aujourdhui);
    expect(
      (await dao.vehicule(vehicule.id))!.statut,
      StatutVehicule.horsService,
    );
  });

  test('le verrou « location » de l’archivage d’un client ignore un contrat '
      'ANNULÉ — les motifs sont ceux du serveur', () async {
    final c = await louer('2026-10-25', '2026-10-28');

    // Actif : le motif du serveur, au mot près.
    expect(await verrousClient(), serveur['verrous_client_avant']);

    await dao.annulerContrat(c.id);

    expect(serveur['verrous_client_apres'], isEmpty);
    expect(await verrousClient(), isEmpty);
  });

  test(
    'un contrat SANS statut (d’avant la v38) reste un verrou actif',
    () async {
      final c = await louer('2026-10-25', '2026-10-28');
      await db.customStatement(
        "UPDATE contrats_location_local SET statut = NULL WHERE id = '${c.id}'",
      );
      expect(await verrousClient(), isNotEmpty);
    },
  );
}
