@Timeout(Duration(minutes: 6))
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/facturation/data/facture_dao.dart';
import 'package:tatacora_flutter/features/facturation/data/proforma_dao.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/piece_facturation.dart';
import 'package:tatacora_flutter/features/facturation/domain/repositories/facture_repository.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/service_appairage.dart';
import 'package:tatacora_flutter/features/synchronisation/data/sync_manager.dart';
import 'package:tatacora_flutter/features/synchronisation/data/transport_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/appairage.dart';
import 'package:tatacora_flutter/features/transverse/data/configuration_poste.dart';
import 'package:uuid/uuid.dart';

import '../comptabilite/support/outils_comptabilite.dart' show semerAuteur;
import 'support/outils_encaissement.dart';

/// VISIBILITÉ des factures et des proformas contre le VRAI serveur, MECeF ACTIVÉ (e-MECeF) — bug du PO du
/// 09/11/2026 (« j'ai activé MECeF, enregistré une réservation, et je ne vois ni proforma ni facture »).
/// `php artisan serve` sur une base d'essai PRIVÉE (`tatacora_factvis_test`, convention
/// `TATACORA_BASE_ESSAI`, CRÉÉE puis SUPPRIMÉE par ce test), le vrai transport, la vraie file, la vraie
/// descente ; ce que les ÉCRANS WEB affichent est relu par les vrais composants Livewire
/// (`tool/facturation/rejouer_visibilite_facturation.php`).
///
///  * une réservation seule ne crée NI facture NI proforma NI opération de facturation ;
///  * la MONTÉE : une proforma (brouillon, émise) et une facture écrites au poste A arrivent au serveur,
///    et les DEUX écrans web les affichent (la facture dit « en attente de normalisation », le mode étant
///    e-MECeF) ;
///  * la DESCENTE (piège 11 : les deux moitiés) : ce que le poste A a écrit descend au poste B, et ce que le
///    WEB a créé descend aux deux postes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const baseEssai = 'tatacora_factvis_test';
  final identifiant = 'e2e.visib.${const Uuid().v4().substring(0, 8)}';
  final motDePasse = 'E2e-${const Uuid().v4()}';

  late Directory dossier;
  late String url;
  late Map<String, dynamic> prep;
  late AppDatabase dbA;
  late AppDatabase dbB;
  late String cheminA;
  late String cheminB;
  final journal = StringBuffer();

  Future<Map<String, dynamic>> php(Map<String, Object?> entree) async {
    final p = await Process.start(
      'php',
      ['tool/facturation/rejouer_visibilite_facturation.php'],
      environment: {'TATACORA_BASE_ESSAI': baseEssai},
    );
    p.stdin.write(jsonEncode(entree));
    await p.stdin.close();
    final sortie = utf8.decodeStream(p.stdout);
    final erreurs = utf8.decodeStream(p.stderr);
    final code = await p.exitCode;
    if (code != 0) {
      fail(
        'rejouer_visibilite_facturation.php ${entree['action']} : code $code\n'
        '${await erreurs}\n${await sortie}',
      );
    }
    return jsonDecode(await sortie) as Map<String, dynamic>;
  }

  SyncManager moteur(AppDatabase db, String chemin, String auteur) {
    Future<String> c() async => chemin;
    return SyncManager(
      dao: OperationsSyncDao(db),
      transport: TransportHttp(),
      urlServeur: url,
      demonstration: false,
      lecteur: LecteurConfigurationPoste(chemin: c),
      ecrivain: EcrivainConfigurationPoste(chemin: c),
      descente: DescenteCatalogue(
        db: db,
        transport: TransportHttp(),
        auteur: () async => auteur,
      ),
    );
  }

  Future<Map<String, dynamic>> ecrans() =>
      php({'action': 'ecrans', 'login': identifiant});

  Future<void> appairer(String chemin, String nomPoste) async {
    Future<String> c() async => chemin;
    final r =
        await ServiceAppairage(
          transport: TransportHttp(),
          urlServeur: url,
          lecteur: LecteurConfigurationPoste(chemin: c),
          ecrivain: EcrivainConfigurationPoste(chemin: c),
        ).appairer(
          identifiant: identifiant,
          motDePasse: motDePasse,
          nomPoste: nomPoste,
        );
    expect(r, isA<AppairageReussi>(), reason: journal.toString());
  }

  Future<void> attendreHorizon() =>
      Future<void>.delayed(const Duration(seconds: 6));

  setUpAll(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora-e2e-visib-');
    cheminA = '${dossier.path}/poste_a.json';
    cheminB = '${dossier.path}/poste_b.json';
    addTearDown(() => dossier.delete(recursive: true));

    Future<void> sql(String requete) async {
      final r = await Process.run('mysql', [
        '-h127.0.0.1',
        '-utatacora',
        '-ptatacora',
        '-e',
        requete,
      ]);
      if (r.exitCode != 0) fail('mysql : ${r.stderr}');
    }

    // La base d'essai est PRIVÉE à cet essai : créée, migrée, puis SUPPRIMÉE.
    await sql(
      'DROP DATABASE IF EXISTS $baseEssai; '
      'CREATE DATABASE $baseEssai CHARACTER SET utf8mb4',
    );
    addTearDown(() => sql('DROP DATABASE IF EXISTS $baseEssai'));
    final migration = await Process.run(
      'php',
      ['artisan', 'migrate', '--force'],
      workingDirectory: '../tatacora-api',
      environment: {'DB_DATABASE': baseEssai},
    );
    if (migration.exitCode != 0) {
      fail('migration de $baseEssai : ${migration.stderr}${migration.stdout}');
    }

    prep = await php({
      'action': 'preparer',
      'login': identifiant,
      'mot_de_passe': motDePasse,
      'mode': 'emecef',
    });
    expect(prep['base'], baseEssai);

    final libre = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = libre.port;
    await libre.close();
    url = 'http://127.0.0.1:$port/api/v1';
    final serveur = await Process.start(
      'php',
      ['artisan', 'serve', '--no-reload', '--host=127.0.0.1', '--port=$port'],
      workingDirectory: '../tatacora-api',
      environment: {'DB_DATABASE': baseEssai},
    );
    serveur.stdout.transform(utf8.decoder).listen(journal.write);
    serveur.stderr.transform(utf8.decoder).listen(journal.write);
    addTearDown(() async {
      serveur.kill();
      await serveur.exitCode.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          serveur.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      await Process.run('pkill', ['-f', '[-]S 127.0.0.1:$port']);
    });

    final sonde = TransportHttp(delai: const Duration(seconds: 2));
    for (var i = 0; ; i++) {
      final r = await sonde.get(Uri.parse('$url/utilisateur'));
      if (r is ReponseHttp && r.statut == 401) break;
      if (i > 60) fail('le serveur ne démarre pas :\n$journal');
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    // Deux postes : A écrit, B ne fait que recevoir. Chacun sa base, son poste.json, son appairage.
    dbA = await baseEncaissement();
    addTearDown(() => dbA.close());
    dbB = AppDatabase.enMemoire();
    addTearDown(() => dbB.close());
    await semerAuteur(dbB, id: 'u-b');
    await appairer(cheminA, 'POSTE-A-VISIBILITE');
    await appairer(cheminB, 'POSTE-B-VISIBILITE');
  });

  test('une réservation seule ne crée NI facture NI proforma NI opération de '
      'facturation (au poste)', () async {
    final base = AppDatabase.enMemoire();
    addTearDown(base.close);
    await semerAuteur(base);
    final client = await creerClient(base);
    await semerReservation(base, id: 'r-1', clientId: client.id, total: 50000);

    expect(await FactureDao(base).pieces(), isEmpty);
    expect(await ProformaDao(base).liste(), isEmpty);
    final tables = (await OperationsSyncDao(
      base,
    ).operations()).map((o) => o.table.nomServeur).toSet();
    expect(tables, isNot(contains('factures')));
    expect(tables, isNot(contains('proformas')));
  });

  late String idBrouillon;
  late String idEmise;
  late String idFacture;

  test('MONTÉE : proformas et facture du poste A arrivent au serveur ; les '
      'DEUX écrans web les affichent, MECeF activé', () async {
    const lignes = [(designation: 'Salle', quantite: 2, prixUnitaire: 50000)];
    final proformas = ProformaDao(dbA);
    idBrouillon = (await proformas.creer(
      clientNom: 'POSTE BROUILLON',
      lignes: lignes,
    )).id;
    idEmise = (await proformas.creer(
      clientNom: 'POSTE EMISE',
      lignes: lignes,
      emettre: true,
    )).id;
    idFacture = (await FactureDao(dbA).emettre(
      BrouillonFacture(
        origine: OrigineFacture.posComptant,
        clientNom: 'Client de passage',
        modePaiement: 'especes',
        lignes: [
          LigneBrouillon(
            module: ModuleFacturable.m5Bar,
            libelle: 'Béninoise 33cl',
            prixUnitaire: 1000,
            quantite: 3,
          ),
        ],
      ),
    )).id;

    await moteur(dbA, cheminA, caissierEssai).synchroniserMaintenant();

    final rejetees = (await OperationsSyncDao(
      dbA,
    ).operations()).where((o) => o.statut.code == 'rejete');
    expect(
      rejetees,
      isEmpty,
      reason: '${rejetees.map((o) => o.derniereErreur)}',
    );

    final vu = await ecrans();
    expect(vu['mode'], 'emecef');
    final facture = (vu['factures'] as Map<String, dynamic>)[idFacture];
    expect(
      facture,
      isNotNull,
      reason: 'la facture du poste est absente du serveur',
    );
    expect(facture['affichee'], isTrue, reason: 'absente du REGISTRE web');
    expect(
      facture['libelle'],
      'en attente de normalisation',
      reason: 'non normalisée : le statut s\'affiche, elle ne disparaît pas',
    );
    expect(vu['registre_vide'], isFalse);

    final pages = vu['proformas'] as Map<String, dynamic>;
    for (final id in [idBrouillon, idEmise]) {
      expect(pages[id], isNotNull, reason: 'proforma absente du serveur');
      expect(
        (pages[id] as Map)['affichee'],
        isTrue,
        reason: 'absente de la page web',
      );
    }
    expect((pages[idBrouillon] as Map)['statut'], 'brouillon');
    expect(
      (pages[idEmise] as Map)['numero'],
      matches(r'^N°\d{4} FP-GCN/2026$'),
    );
    // Le poste A a posé le numéro du serveur à la place du provisoire.
    expect(
      (await proformas.parId(idEmise))!.numero,
      (pages[idEmise] as Map)['numero'],
    );
  });

  test('DESCENTE : ce que A a écrit descend au poste B, et ce que le WEB a '
      'créé descend aux deux postes', () async {
    final web = await php({
      'action': 'creer_au_web',
      'client_id': prep['client_id'],
    });
    // L'HORIZON du serveur : une ligne écrite à l'instant ne descend qu'après quelques secondes.
    await attendreHorizon();
    final a = moteur(dbA, cheminA, caissierEssai);
    final b = moteur(dbB, cheminB, 'u-b');
    await a.synchroniserDescenteSeule();
    await b.synchroniserDescenteSeule();

    final proformasB = ProformaDao(dbB);
    final piecesB = FactureDao(dbB);
    // Poste B reçoit l'écriture de A…
    expect(
      await piecesB.parId(idFacture),
      isNotNull,
      reason: journal.toString(),
    );
    for (final id in [idBrouillon, idEmise]) {
      expect(
        await proformasB.parId(id),
        isNotNull,
        reason: 'proforma $id absente de B',
      );
    }
    // …et les deux postes reçoivent ce que le web a créé.
    for (final (nom, proformas, pieces) in [
      ('A', ProformaDao(dbA), FactureDao(dbA)),
      ('B', proformasB, piecesB),
    ]) {
      for (final cle in ['proforma_brouillon', 'proforma_emise']) {
        expect(
          await proformas.parId(web[cle] as String),
          isNotNull,
          reason: '$cle absente du poste $nom',
        );
      }
      expect(
        await pieces.parId(web['facture'] as String),
        isNotNull,
        reason: 'facture du web absente du poste $nom',
      );
    }
    expect(
      (await proformasB.parId(web['proforma_emise'] as String))!.numero,
      web['numero_proforma_emise'],
    );
  });
}
