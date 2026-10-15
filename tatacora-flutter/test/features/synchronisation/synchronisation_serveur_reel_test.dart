@Timeout(Duration(minutes: 6))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/service_appairage.dart';
import 'package:tatacora_flutter/features/synchronisation/data/sync_manager.dart';
import 'package:tatacora_flutter/features/synchronisation/data/transport_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/appairage.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/bilan_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/transverse/data/configuration_poste.dart';
import 'package:uuid/uuid.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import 'support/journee_caisse.dart';

/// De BOUT EN BOUT contre le VRAI serveur (lot F2a) : `php artisan serve` sur
/// `tatacora_test`, le VRAI transport HTTP du poste, le vrai `POST /login`,
/// le vrai `POST /sync`. Rien n'est simulé entre la file du poste et les
/// tables du serveur.
///
/// ⚠ `TestWidgetsFlutterBinding` installe un `HttpOverrides` qui rend 400 à
/// toute requête SANS L'ÉMETTRE (leçon du socle réseau, 27/08/2026) :
/// `HttpOverrides.global = null`, sans quoi cet essai ne toucherait aucun
/// serveur. L'appairage refusé puis accepté le prouve : un bouchon ne
/// distinguerait pas les deux.
///
/// Le serveur ÉCRIT pour de bon : `tool/sync/serveur_reel.php` prend un
/// instantané de `tatacora_test` avant, et restaure après chaque table
/// modifiée. Le verrou de `tatacora_test` (D279) est tenu pendant TOUT
/// l'essai : aucun script PHP d'un autre fichier ne s'intercale.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final identifiant = 'e2e.sync.${const Uuid().v4().substring(0, 8)}';
  final motDePasse = 'E2e-${const Uuid().v4()}';
  const poste = 'POSTE-E2E-F2A';
  final instantane =
      '${Directory.systemTemp.path}/tatacora_e2e_sync_instantane.json';

  late Directory dossier;
  late String cheminPoste;
  late String url;
  late AppDatabase db;
  late JourneeDeCaisse journee;
  final journal = StringBuffer();

  Future<String> chemin() async => cheminPoste;

  /// `tool/sync/serveur_reel.php`, SANS passer par `executerPhp` : le verrou
  /// est déjà tenu par cet essai.
  Future<Map<String, dynamic>> php(Map<String, Object?> entree) async {
    final p = await Process.start('php', ['tool/sync/serveur_reel.php']);
    p.stdin.write(jsonEncode(entree));
    await p.stdin.close();
    final sortie = utf8.decodeStream(p.stdout);
    final erreurs = utf8.decodeStream(p.stderr);
    final code = await p.exitCode;
    if (code != 0) {
      fail(
        'serveur_reel.php ${entree['action']} : code $code\n'
        '${await erreurs}\n${await sortie}',
      );
    }
    return jsonDecode(await sortie) as Map<String, dynamic>;
  }

  ServiceAppairage appairage() => ServiceAppairage(
    transport: TransportHttp(),
    urlServeur: url,
    lecteur: LecteurConfigurationPoste(chemin: chemin),
    ecrivain: EcrivainConfigurationPoste(chemin: chemin),
  );

  SyncManager moteur() => SyncManager(
    dao: OperationsSyncDao(db),
    transport: TransportHttp(),
    urlServeur: url,
    demonstration: false,
    lecteur: LecteurConfigurationPoste(chemin: chemin),
    ecrivain: EcrivainConfigurationPoste(chemin: chemin),
  );

  setUpAll(() async {
    HttpOverrides.global = null;
    dossier = await Directory.systemTemp.createTemp('tatacora-e2e-sync-');
    cheminPoste = '${dossier.path}/poste.json';
    addTearDown(() => dossier.delete(recursive: true));

    // 1. Le verrou de tatacora_test, tenu jusqu'à la fin.
    final tenu = Completer<void>();
    final liberer = Completer<void>();
    final verrou = sousVerrouBaseDeTest<void>(() async {
      tenu.complete();
      await liberer.future;
    });
    await tenu.future;
    addTearDown(() async {
      liberer.complete();
      await verrou;
    });

    // 2. L'instantané, puis rôles, référentiel comptable et compte gérant.
    final prep = await php({
      'action': 'preparer',
      'instantane': instantane,
      'login': identifiant,
      'mot_de_passe': motDePasse,
    });
    expect(prep['base'], 'tatacora_test');
    addTearDown(() async {
      final r = await php({'action': 'restaurer', 'instantane': instantane});
      // ignore: avoid_print
      print('tatacora_test restaurée : ${r['restaurees']}');
    });

    // 3. Le serveur, sur un port libre, sur tatacora_test (`--no-reload` :
    //    sans lui, `artisan serve` retire DB_DATABASE de l'environnement du
    //    serveur, qui relirait `.env` — la base de développement).
    final libre = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = libre.port;
    await libre.close();
    url = 'http://127.0.0.1:$port/api/v1';
    final serveur = await Process.start(
      'php',
      ['artisan', 'serve', '--no-reload', '--host=127.0.0.1', '--port=$port'],
      workingDirectory: '../tatacora-api',
      environment: {'DB_DATABASE': 'tatacora_test'},
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
      // Le `php -S` enfant d'artisan, s'il survivait à son parent.
      await Process.run('pkill', ['-f', '[-]S 127.0.0.1:$port']);
    });

    // Prêt quand /utilisateur répond 401 (sans jeton) — en JSON.
    final sonde = TransportHttp(delai: const Duration(seconds: 2));
    for (var i = 0; ; i++) {
      final r = await sonde.get(Uri.parse('$url/utilisateur'));
      if (r is ReponseHttp && r.statut == 401) break;
      if (i > 60) fail('le serveur ne démarre pas :\n$journal');
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    db = AppDatabase.enMemoire();
    addTearDown(() => db.close());
  });

  /// Les lignes du serveur, relues par PHP sur tatacora_test.
  Future<Map<String, dynamic>> relire(
    List<(String, String)> elements, {
    List<String> comptes = const [],
  }) => php({
    'action': 'relire',
    'poste_id': poste,
    'elements': [
      for (final (t, id) in elements) {'table': t, 'id': id},
    ],
    'comptes': comptes,
  });

  const tablesComptees = [
    'points_stockage',
    'articles',
    'cartes_boisson',
    'sessions_caisse',
    'ventes',
    'lignes_vente',
    'depenses',
    'ecritures_comptables',
    'mouvements_stock',
  ];

  test('appairage par le VRAI /login : mauvais mot de passe refusé, bon '
      'mot de passe → jeton du poste enregistré', () async {
    final refus = await appairage().appairer(
      identifiant: identifiant,
      motDePasse: 'pas-le-bon',
      nomPoste: poste,
    );
    expect(
      (refus as AppairageRefuse).message,
      TextesAppairage.identifiantsRefuses,
    );

    final r = await appairage().appairer(
      identifiant: identifiant,
      motDePasse: motDePasse,
      nomPoste: poste,
    );
    expect(r, isA<AppairageReussi>(), reason: journal.toString());
    final lu = await LecteurConfigurationPoste(chemin: chemin).appairage();
    expect(lu!.posteId, poste);
    expect(lu.serveur, url);
    expect(lu.compte, identifiant);
    expect(await File(cheminPoste).readAsString(), isNot(contains(motDePasse)));
    expect((await relire(const []))['jetons_du_poste'], 1);

    expect(
      await appairage().testerConnexion(),
      TextesAppairage.connexionEtablie(identifiant),
    );
  });

  test('une journée de comptoir, poussée par le moteur : CHAQUE opération '
      'synchronisée, et les lignes existent au serveur', () async {
    final hier = DateTime.now().subtract(const Duration(days: 1));
    journee = await jouerJourneeDeCaisse(
      db,
      jour: DateTime(hier.year, hier.month, hier.day, 10),
    );
    final ops = await OperationsSyncDao(db).operations();
    expect(ops.map((o) => '${o.type.code} ${o.table.nomServeur}'), [
      'creation points_stockage',
      'creation articles',
      'creation cartes_boisson',
      'creation sessions_caisse',
      'creation ventes',
      'creation ventes',
      'creation depenses',
      'modification sessions_caisse',
    ]);

    final bilan = await moteur().synchroniserMaintenant();
    final refus = [
      for (final o in await OperationsSyncDao(db).operations())
        if (o.statut != StatutOperationSync.synchronise)
          '${o.type.code} ${o.table.nomServeur} : ${o.statut.code} '
              '${o.resultatJson ?? o.derniereErreur}',
    ];
    expect(refus, isEmpty, reason: '$bilan\n$journal');
    expect(bilan.etat, EtatSynchronisation.termine);
    expect(bilan.synchronisees, 8);

    final serveur = await relire([
      ('points_stockage', journee.point),
      ('articles', journee.article),
      ('cartes_boisson', journee.boisson),
      ('sessions_caisse', journee.session),
      ('ventes', journee.vente1),
      ('ventes', journee.vente2),
      ('depenses', journee.depense),
    ]);
    final lignes = serveur['lignes'] as Map<String, dynamic>;
    Map<String, dynamic> ligne(String t, String id) {
      final l = lignes['$t:$id'];
      expect(l, isNotNull, reason: '$t $id absent du serveur');
      return l as Map<String, dynamic>;
    }

    expect(
      ligne('articles', journee.article)['point_stockage_id'],
      journee.point,
    );
    expect(ligne('cartes_boisson', journee.boisson)['prix_vente'], '1000.00');
    expect(ligne('ventes', journee.vente1)['montant_total'], '2000.00');
    expect(ligne('ventes', journee.vente2)['montant_total'], '3000.00');
    expect(ligne('ventes', journee.vente1)['session_id'], journee.session);
    final session = ligne('sessions_caisse', journee.session);
    expect(session['date_cloture'], isNotNull, reason: 'clôturée au serveur');
    expect(session['montant_constate'], '15000.00');
    expect(ligne('depenses', journee.depense)['libelle'], 'Glace E2E');
  });

  test('REJEU : la même file renvoyée (réponse perdue) puis les documents '
      'sous un nouvel uuid_operation — aucun doublon au serveur', () async {
    final avant = (await relire(const [], comptes: tablesComptees))['comptes'];

    // 1. La réponse s'était perdue : tout redevient en attente, mêmes uuid.
    await db.customStatement(
      "UPDATE operations_sync_local SET statut = 'en_attente', "
      'synchronise_le = NULL, resultat_json = NULL',
    );
    final rejeu = await moteur().synchroniserMaintenant();
    expect(rejeu.synchronisees, 8, reason: '$rejeu');
    for (final o in await OperationsSyncDao(db).operations()) {
      expect(o.statut, StatutOperationSync.synchronise);
      expect((jsonDecode(o.resultatJson!) as Map)['rejeu_idempotent'], isTrue);
    }

    // 2. La mémoire d'idempotence du serveur a été purgée : les DOCUMENTS
    //    repartent sous un nouvel uuid_operation.
    await db.customStatement(
      "UPDATE operations_sync_local SET statut = 'en_attente', "
      "uuid_operation = lower(hex(randomblob(4))) || '-' || "
      "lower(hex(randomblob(2))) || '-4' || substr(lower(hex(randomblob(2))),2) "
      "|| '-a' || substr(lower(hex(randomblob(2))),2) || '-' || "
      "lower(hex(randomblob(6))) WHERE table_serveur IN ('ventes', 'depenses')",
    );
    final second = await moteur().synchroniserMaintenant();
    expect(second.synchronisees, 3, reason: '$second');
    for (final o in await OperationsSyncDao(
      db,
    ).operations(table: TableSynchronisee.ventes)) {
      expect(
        (jsonDecode(o.resultatJson!) as Map)['document_deja_enregistre'],
        isTrue,
      );
    }

    final apres = (await relire(const [], comptes: tablesComptees))['comptes'];
    expect(apres, avant, reason: 'un rejeu n’écrit RIEN de plus');
  });

  test('jeton révoqué au serveur : 401 RÉEL → jeton refusé, la file '
      'intacte ; « Dissocier » révoque par le vrai /logout', () async {
    final ancien = (await LecteurConfigurationPoste(
      chemin: chemin,
    ).appairage())!;

    expect(await appairage().dissocier(), TextesAppairage.dissocie);
    expect((await relire(const []))['jetons_du_poste'], 0);
    expect(
      (await moteur().synchroniserMaintenant()).etat,
      EtatSynchronisation.nonAppaire,
    );

    // Le poste croit encore détenir le jeton révoqué.
    await EcrivainConfigurationPoste(
      chemin: chemin,
    ).enregistrerAppairage(ancien);
    await db.transaction(
      () => OperationsSyncDao(db).enfiler(
        table: TableSynchronisee.clients,
        entiteId: const Uuid().v4(),
        type: TypeOperationSync.creation,
        payload: {'nom': 'CLIENT E2E', 'telephone': '97990001'},
      ),
    );
    final bilan = await moteur().synchroniserMaintenant();
    expect(bilan.etat, EtatSynchronisation.jetonRefuse);
    expect(bilan.codeHttp, 401);
    final client = (await OperationsSyncDao(
      db,
    ).operations(table: TableSynchronisee.clients)).single;
    expect(client.statut, StatutOperationSync.enAttente);
    expect(client.tentatives, 0);
  });
}
