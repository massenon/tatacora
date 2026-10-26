@Timeout(Duration(minutes: 6))
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/journal_reception_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/service_appairage.dart';
import 'package:tatacora_flutter/features/synchronisation/data/sync_manager.dart';
import 'package:tatacora_flutter/features/synchronisation/data/transport_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/appairage.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/cause_envoi.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/journal_reception.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/transverse/data/configuration_poste.dart';
import 'package:uuid/uuid.dart';

/// Le JOURNAL DE RÉCEPTION et la CORRECTION D'ENVOI contre le VRAI serveur
/// (26/10/2026) : `php artisan serve` sur une base d'essai PRIVÉE
/// (`tatacora_syncposte_test`, convention `TATACORA_BASE_ESSAI`), le vrai
/// transport HTTP, le vrai `POST /login`, `/sync` et `/referentiels`. La base
/// est à CET essai : aucun verrou partagé n'est nécessaire.
///
///  * ENVOI : un client à l'adresse e-mail invalide est REFUSÉ par le serveur
///    (phrases par champ), la cause est lue, la charge CORRIGÉE par le
///    formulaire généré, renvoyée sous un nouvel uuid — et ACCEPTÉE.
///  * RÉCEPTION : un point de stockage au type inconnu de ce poste est REFUSÉ,
///    ce qui le cite attend (cascade) ; un poste sans compte local ne peut pas
///    écrire un menu. Le compte est créé, la donnée corrigée à la source,
///    « Relancer tout » — et tout ABOUTIT, le journal le dit.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const baseEssai = 'tatacora_syncposte_test';
  final identifiant = 'e2e.recep.${const Uuid().v4().substring(0, 8)}';
  final motDePasse = 'E2e-${const Uuid().v4()}';
  const poste = 'POSTE-E2E-RECEPTION';
  final instantane =
      '${Directory.systemTemp.path}/tatacora_e2e_reception_instantane.json';

  late Directory dossier;
  late String cheminPoste;
  late String url;
  late AppDatabase db;
  final journal = StringBuffer();

  Future<String> chemin() async => cheminPoste;

  Future<Map<String, dynamic>> php(Map<String, Object?> entree) async {
    final p = await Process.start(
      'php',
      ['tool/sync/serveur_reel.php'],
      environment: {'TATACORA_BASE_ESSAI': baseEssai},
    );
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

  late DescenteCatalogue descente;

  SyncManager moteur() => SyncManager(
    dao: OperationsSyncDao(db),
    transport: TransportHttp(),
    urlServeur: url,
    demonstration: false,
    lecteur: LecteurConfigurationPoste(chemin: chemin),
    ecrivain: EcrivainConfigurationPoste(chemin: chemin),
    descente: descente,
  );

  setUpAll(() async {
    HttpOverrides.global = null;
    dossier = await Directory.systemTemp.createTemp('tatacora-e2e-recep-');
    cheminPoste = '${dossier.path}/poste.json';
    addTearDown(() => dossier.delete(recursive: true));

    final prep = await php({
      'action': 'preparer',
      'instantane': instantane,
      'login': identifiant,
      'mot_de_passe': motDePasse,
    });
    expect(prep['base'], baseEssai);
    addTearDown(() async {
      await php({'action': 'restaurer', 'instantane': instantane});
    });

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
    descente = DescenteCatalogue(
      db: db,
      transport: TransportHttp(),
      // Aucun compte sur ce poste au départ : `null`, donc rien à écrire pour
      // un menu ; le compte créé plus loin le rend.
      auteur: () => DescenteCatalogueDao(db).auteurParDefaut(),
    );
  });

  Future<void> attendreHorizon() =>
      Future<void>.delayed(const Duration(seconds: 6));

  test('appairage par le VRAI /login', () async {
    final r = await appairage().appairer(
      identifiant: identifiant,
      motDePasse: motDePasse,
      nomPoste: poste,
    );
    expect(r, isA<AppairageReussi>(), reason: journal.toString());
  });

  test('ENVOI : refusé par le serveur (e-mail invalide), cause lue, charge '
      'CORRIGÉE par le formulaire généré, renvoyée sous un nouvel uuid — '
      'ACCEPTÉE', () async {
    final id = const Uuid().v4();
    final dao = OperationsSyncDao(db);
    await db.transaction(
      () => dao.enfiler(
        table: TableSynchronisee.clients,
        entiteId: id,
        type: TypeOperationSync.creation,
        payload: {
          'nom': 'Kossi',
          'telephone': '97001234',
          'type_client': 'particulier',
          'email': 'pas-un-email',
        },
      ),
    );
    await moteur().synchroniserMaintenant();

    final refusee = (await dao.operations(entiteId: id)).single;
    expect(refusee.statut, StatutOperationSync.rejete, reason: '$journal');
    expect(codeMotifDe(refusee), 'donnees_invalides');
    final cause = causeDe(refusee, motif: refusee.derniereErreur ?? '');
    expect(cause.titre, 'Donnée refusée par le serveur');
    expect(
      cause.erreurs.map((e) => e.libelle),
      contains('Adresse e-mail'),
      reason: 'le champ fautif est celui du serveur : ${cause.erreurs}',
    );
    expect(
      champsEditables(refusee).map((c) => c.cle),
      containsAll(['nom', 'telephone', 'email']),
    );

    // Une saisie encore fausse n'est pas refusée par le formulaire (le
    // serveur seul juge une adresse) ; une saisie vide, si.
    expect(corrigerCharge(refusee, {'nom': ' '}).charge, isNull);

    final v = corrigerCharge(refusee, {'email': 'kossi@exemple.bj'});
    expect(v.erreurs, isEmpty);
    final nouvelle = await dao.renvoyer(
      refusee.uuidOperation,
      chargeCorrigee: v.charge,
    );
    expect(nouvelle, isNot(refusee.uuidOperation));

    await moteur().synchroniserMaintenant();
    final ops = await dao.operations(entiteId: id);
    expect(ops, hasLength(2));
    expect(ops.first.statut, StatutOperationSync.rejete);
    expect(
      ops.last.statut,
      StatutOperationSync.synchronise,
      reason: '${ops.last.resultatJson}\n$journal',
    );
    final serveur = await php({
      'action': 'relire',
      'poste_id': poste,
      'elements': [
        {'table': 'clients', 'id': id},
      ],
      'comptes': <String>[],
    });
    final ligne = (serveur['lignes'] as Map)['clients:$id'] as Map;
    expect(ligne['email'], 'kossi@exemple.bj');
  });

  test('RÉCEPTION : refusé (type inconnu), en attente (sans compte, '
      'dépendance) ; compte créé, donnée corrigée à la source, « Relancer '
      'tout » — tout ABOUTIT', () async {
    final ids =
        (await php({'action': 'creer_catalogue'}))['ids']
            as Map<String, dynamic>;
    String id(String t) => ids[t]! as String;
    await php({
      'action': 'modifier',
      'table': 'points_stockage',
      'id': id('points_stockage'),
      'valeurs': {'type': 'type-du-futur'},
    });
    await attendreHorizon();

    await moteur().synchroniserMaintenant();
    final jr = JournalReceptionDao(db);

    final point = (await jr.lire('points_stockage', id('points_stockage')))!;
    expect(point.issue, IssueReception.refuse, reason: '$journal');
    expect(point.cause, CauseReception.valeurInconnue);
    expect(point.explication.phrase, contains('type-du-futur'));

    final article = (await jr.lire('articles', id('articles')))!;
    expect(article.issue, IssueReception.enAttente);
    expect(article.dependance, 'points_stockage');

    final menu = (await jr.lire('menus', id('menus')))!;
    expect(menu.issue, IssueReception.enAttente);
    expect(menu.cause, CauseReception.sansCompteLocal);
    final plat = (await jr.lire('plats', id('plats')))!;
    expect(plat.issue, IssueReception.enAttente);

    final avant = await jr.compter();
    expect(avant.aTraiter, greaterThan(0));
    expect(avant.refuse, 1);
    expect(
      await db.select(db.platsLocal).get(),
      isEmpty,
      reason: 'rien n’est écrit tant que la cause demeure',
    );

    // CORRIGER 1 : le compte manquant (l'écran des comptes le crée).
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
    // RELANCER (local, sans réseau) : le menu puis le plat passent.
    final reste = await descente.relancerTout();
    expect((await jr.lire('menus', id('menus')))!.issue, IssueReception.aligne);
    // Le plat cite sa fiche technique, qui cite l'article, qui cite le point
    // de stockage REFUSÉ : la cascade tient jusqu'à la source.
    final platEnAttente = (await jr.lire('plats', id('plats')))!;
    expect(platEnAttente.issue, IssueReception.enAttente);
    expect(platEnAttente.dependance, 'recettes');
    expect(await db.select(db.platsLocal).get(), isEmpty);
    expect(
      (await jr.lire('points_stockage', id('points_stockage')))!.issue,
      IssueReception.refuse,
      reason: 'la même version reste refusée : la source est fausse',
    );
    expect(reste, greaterThan(0));

    // CORRIGER 2 : à la source, puis RELANCER TOUT (réseau).
    await php({
      'action': 'modifier',
      'table': 'points_stockage',
      'id': id('points_stockage'),
      'valeurs': {'type': 'bar'},
    });
    await attendreHorizon();
    await descente.leverRepli();
    await moteur().synchroniserMaintenant();

    final apres = await jr.compter();
    expect(apres.aTraiter, 0, reason: '${await jr.lister(aTraiter: true)}');
    final corrige = (await jr.lire('points_stockage', id('points_stockage')))!;
    expect(corrige.issue, IssueReception.aligne);
    expect(corrige.elementJson, isNull);
    expect(
      (await jr.lire('articles', id('articles')))!.issue,
      IssueReception.aligne,
    );
    expect(
      (await jr.lire('plats', id('plats')))!.issue,
      IssueReception.aligne,
      reason: 'la cascade se résout une fois la source corrigée',
    );
    expect(await db.select(db.platsLocal).get(), hasLength(1));
    expect(await db.select(db.articlesLocal).get(), hasLength(1));
    expect(await db.select(db.pointsStockageLocal).get(), hasLength(1));
    expect(
      await OperationsSyncDao(
        db,
      ).operations(table: TableSynchronisee.pointsStockage),
      isEmpty,
      reason: 'ce qui descend ne remonte jamais',
    );
  });
}
