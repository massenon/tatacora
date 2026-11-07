@Timeout(Duration(minutes: 6))
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/facturation/data/facture_dao.dart';
import 'package:tatacora_flutter/features/facturation/data/service_facturation_en_ligne.dart';
import 'package:tatacora_flutter/features/facturation/domain/repositories/facture_repository.dart'
    show FactureDejaAnnulee;
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/service_appairage.dart';
import 'package:tatacora_flutter/features/synchronisation/data/sync_manager.dart';
import 'package:tatacora_flutter/features/synchronisation/data/transport_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/appairage.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/transverse/data/configuration_poste.dart';
import 'package:uuid/uuid.dart';

/// La FACTURATION EN LIGNE du poste contre le VRAI serveur (décisions du PO du 07/11/2026) :
/// `php artisan serve` sur une base d'essai PRIVÉE (`tatacora_factonligne_test`, convention
/// `TATACORA_BASE_ESSAI`, CRÉÉE puis SUPPRIMÉE par ce test), le vrai transport HTTP, le vrai
/// `POST /login`, les vraies routes `/sync/factures/{id}/avoir` et `…/normalisation`, et la
/// vraie descente. Aucune liste recopiée : ce que le serveur a ÉCRIT est relu par le script PHP.
///
///  * l'avoir d'une facture NORMALISÉE est créé AU SERVEUR (identifiant serveur), le poste n'écrit
///    rien, puis l'avoir DESCEND (facture annulée, avoir inscrit sous l'identifiant serveur,
///    « en attente » du boîtier parce que le serveur est en mode boîtier) ;
///  * la file du poste, elle, refuse d'envoyer un avoir d'annulation d'une facture normalisée ;
///  * hors ligne, rien n'est écrit au serveur ;
///  * la demande de normalisation e-MECeF d'une facture simple : sans accès à la DGI dans cet
///    environnement, le serveur range « en attente » avec son motif, le poste l'écrit tel quel.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const baseEssai = 'tatacora_factonligne_test';
  final identifiant = 'e2e.fact.${const Uuid().v4().substring(0, 8)}';
  final motDePasse = 'E2e-${const Uuid().v4()}';
  const poste = 'POSTE-E2E-FACTURATION';

  late Directory dossier;
  late String cheminPoste;
  late String url;
  late AppDatabase db;
  late Map<String, dynamic> prep;
  final journal = StringBuffer();

  Future<String> chemin() async => cheminPoste;

  Future<Map<String, dynamic>> php(Map<String, Object?> entree) async {
    final p = await Process.start(
      'php',
      ['tool/facturation/rejouer_facturation_en_ligne.php'],
      environment: {'TATACORA_BASE_ESSAI': baseEssai},
    );
    p.stdin.write(jsonEncode(entree));
    await p.stdin.close();
    final sortie = utf8.decodeStream(p.stdout);
    final erreurs = utf8.decodeStream(p.stderr);
    final code = await p.exitCode;
    if (code != 0) {
      fail(
        'rejouer_facturation_en_ligne.php ${entree['action']} : code $code\n'
        '${await erreurs}\n${await sortie}',
      );
    }
    return jsonDecode(await sortie) as Map<String, dynamic>;
  }

  SyncManager moteur() => SyncManager(
    dao: OperationsSyncDao(db),
    transport: TransportHttp(),
    urlServeur: url,
    demonstration: false,
    lecteur: LecteurConfigurationPoste(chemin: chemin),
    ecrivain: EcrivainConfigurationPoste(chemin: chemin),
    descente: DescenteCatalogue(
      db: db,
      transport: TransportHttp(),
      auteur: () async => 'u-admin',
    ),
  );

  ServiceFacturationEnLigne service({
    TransportSynchronisation? transport,
    Future<String> Function()? cheminDuPoste,
  }) => ServiceFacturationEnLigne(
    transport: transport ?? TransportHttp(delai: const Duration(seconds: 3)),
    url: url,
    base: db,
    lecteur: LecteurConfigurationPoste(chemin: cheminDuPoste ?? chemin),
    envoyerLaFile: () async {
      await moteur().synchroniserMaintenant();
    },
    descendre: () async {
      await moteur().synchroniserDescenteSeule();
    },
  );

  Future<void> attendreHorizon() =>
      Future<void>.delayed(const Duration(seconds: 6));

  Future<Map<String, dynamic>> relire() => php({
    'action': 'relire',
    'factures': [prep['facture_normalisee'], prep['facture_simple']],
  });

  /// La facture [id] telle que le SERVEUR la détient.
  Future<Map<String, dynamic>> duServeur(String id) async =>
      ((await relire())['factures'] as Map<String, dynamic>)[id]
          as Map<String, dynamic>;

  setUpAll(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora-e2e-fact-');
    cheminPoste = '${dossier.path}/poste.json';
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
      'mode': 'boitier',
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

    db = AppDatabase.enMemoire();
    addTearDown(() => db.close());
    await db
        .into(db.utilisateursLocal)
        .insert(
          UtilisateursLocalCompanion.insert(
            id: 'u-admin',
            login: 'admin',
            nom: 'Admin',
            role: 'administrateur',
            droitsJson: '{}',
            sel: 's',
            empreinte: 'e',
            iterations: 1,
            dateCreation: DateTime(2026, 10, 1),
            dateMotDePasse: DateTime(2026, 10, 1),
          ),
        );

    final appairage =
        await ServiceAppairage(
          transport: TransportHttp(),
          urlServeur: url,
          lecteur: LecteurConfigurationPoste(chemin: chemin),
          ecrivain: EcrivainConfigurationPoste(chemin: chemin),
        ).appairer(
          identifiant: identifiant,
          motDePasse: motDePasse,
          nomPoste: poste,
        );
    expect(appairage, isA<AppairageReussi>(), reason: journal.toString());

    // La descente apporte les factures du serveur au poste (la vraie descente).
    // L'HORIZON du serveur : une ligne écrite à l'instant ne descend qu'après quelques secondes.
    await attendreHorizon();
    await moteur().synchroniserDescenteSeule();
  });

  test('la descente a apporté les deux factures : la normalisée l\'est ici '
      'aussi, la simple ne porte rien', () async {
    final dao = FactureDao(db);
    final normalisee = await dao.parId(prep['facture_normalisee'] as String);
    final simple = await dao.parId(prep['facture_simple'] as String);

    expect(normalisee, isNotNull, reason: journal.toString());
    expect(normalisee!.estNormalisee, isTrue);
    expect(normalisee.numeroMecef, 'ED04000623-41');
    expect(simple, isNotNull);
    expect(simple!.estNormalisee, isFalse);
    expect(simple.numeroMecef, isNull);
  });

  test('hors ligne : rien n\'est écrit au serveur, la phrase est dite', () async {
    final avant = await relire();

    // Un poste appairé à un serveur qui ne répond PAS (port fermé) : le vrai transport échoue.
    final hors = '${dossier.path}/poste_hors_ligne.json';
    await EcrivainConfigurationPoste(
      chemin: () async => hors,
    ).enregistrerAppairage(
      AppairagePoste(
        posteId: poste,
        jetonApi: '7|jeton-essai',
        serveur: 'http://127.0.0.1:9/api/v1',
        appaireLe: DateTime(2026, 11, 7),
        compte: 'admin',
      ),
    );
    final r = await service(
      cheminDuPoste: () async => hors,
    ).avoir(prep['facture_normalisee'] as String, motif: 'Erreur de saisie');

    expect(r, isA<RefusEnLigne>());
    expect(
      (r as RefusEnLigne).phrase,
      'Un avoir sur une facture normalisée se fait en ligne : reconnectez le '
      'poste au serveur.',
    );
    expect(await relire(), avant);
  });

  test('AVOIR EN LIGNE : créé au serveur (identifiant serveur), le poste '
      'n\'écrit rien, puis l\'avoir DESCEND', () async {
    final dao = FactureDao(db);
    final id = prep['facture_normalisee'] as String;
    final piecesAvant = (await dao.pieces()).length;
    final opsAvant = (await OperationsSyncDao(db).operations()).length;

    final r = await service().avoir(id, motif: 'Erreur de saisie');

    expect(r, isA<AvoirCree>(), reason: journal.toString());
    final cree = r as AvoirCree;
    expect(cree.entier, isTrue);
    expect(cree.numeroAvoir, startsWith('AV-'));
    // Le serveur a écrit l'avoir, en attente du boîtier (mode boîtier).
    final serveur = await duServeur(id);
    final avoirs = serveur['avoirs'] as List<dynamic>;
    expect(avoirs, hasLength(1));
    final avoirServeur = avoirs.single as Map<String, dynamic>;
    expect(avoirServeur['numero'], cree.numeroAvoir);
    expect(avoirServeur['normalisation_statut'], 'en_attente');
    expect(avoirServeur['normalisation_mode'], 'boitier');
    expect(serveur['numero_mecef'], 'ED04000623-41', reason: 'facture intacte');

    // Le poste n'a RIEN écrit lui-même : ni pièce-avoir, ni opération en file, la facture
    // n'est pas annulée localement tant que la descente n'a pas rapporté l'avoir.
    expect(
      (await OperationsSyncDao(db).operations()).length,
      opsAvant,
      reason: 'rien en file : l\'avoir n\'est pas né sur le poste',
    );
    expect((await dao.pieces()).length, piecesAvant);
    expect((await dao.parId(id))!.estAnnulee, isFalse);

    // L'avoir DESCEND (passé l'horizon du serveur) sous l'identifiant SERVEUR.
    await attendreHorizon();
    await moteur().synchroniserDescenteSeule();
    final pieces = await dao.pieces();
    expect(pieces.length, piecesAvant + 1);
    final avoirLocal = pieces.firstWhere((p) => p.estAvoir);
    expect(avoirLocal.id, avoirServeur['id'], reason: 'identifiant serveur');
    expect(avoirLocal.numero, cree.numeroAvoir);
    expect(
      avoirLocal.normalisationStatut?.code,
      'en_attente',
      reason: 'mode boîtier : le poste avec boîtier le reprend, par bouton',
    );
    expect((await dao.parId(id))!.estAnnulee, isTrue);
  });

  test(
    'REJEU : annuler de nouveau la même facture ne double jamais l\'avoir',
    () async {
      final id = prep['facture_normalisee'] as String;
      // Déjà annulée ici : le geste est refusé AVANT toute requête.
      await expectLater(
        service().avoir(id, motif: 'Encore'),
        throwsA(isA<FactureDejaAnnulee>()),
      );
      expect((await duServeur(id))['avoirs'], hasLength(1));
    },
  );

  test('la normalisation e-MECeF demandée depuis le poste, le serveur étant en '
      'mode BOÎTIER : refusée avec SA phrase, rien n\'est écrit', () async {
    final simple = prep['facture_simple'] as String;

    final r = await service().normaliserParLeServeur(simple);

    expect(r, isA<RefusEnLigne>(), reason: journal.toString());
    expect(
      (r as RefusEnLigne).phrase,
      'En mode boîtier, la normalisation se fait au poste de la réception '
      '(boîtier CC300) : elle ne se fait pas depuis le web.',
    );
    expect((await FactureDao(db).parId(simple))!.normalisationStatut, isNull);
    expect((await duServeur(simple))['normalisation_statut'], isNull);
  });

  test(
    'l\'annulation d\'une facture SIMPLE par la file reste possible : l\'avoir '
    'naît au serveur (avoir simple)',
    () async {
      final simple = prep['facture_simple'] as String;
      await db.transaction(
        () => OperationsSyncDao(db).enfiler(
          table: TableSynchronisee.factures,
          entiteId: simple,
          type: TypeOperationSync.modification,
          payload: {'statut': 'annulee', 'motif': 'Doublon'},
        ),
      );
      await moteur().synchroniserMaintenant();

      final avoirs = (await duServeur(simple))['avoirs'] as List<dynamic>;
      expect(avoirs, hasLength(1), reason: journal.toString());
      final avoir = avoirs.single as Map<String, dynamic>;
      expect(avoir['normalisation_statut'], isNull);
      expect(avoir['numero'], startsWith('AV-'));
    },
  );
}
