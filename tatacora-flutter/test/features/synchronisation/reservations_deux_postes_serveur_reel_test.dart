@Timeout(Duration(minutes: 10))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/crm/data/client_dao.dart';
import 'package:tatacora_flutter/features/crm/domain/entities/client.dart';
import 'package:tatacora_flutter/features/hebergement/data/parc_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_repository_local.dart';
import 'package:tatacora_flutter/features/hebergement/data/sejour_dao.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/fiche_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/service_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/unite_hebergement.dart';
import 'package:tatacora_flutter/features/hebergement/domain/usecases/creer_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/usecases/modifier_reservation.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/sejour_au_pos.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/service_appairage.dart';
import 'package:tatacora_flutter/features/synchronisation/data/sync_manager.dart';
import 'package:tatacora_flutter/features/synchronisation/data/transport_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/appairage.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/tourisme/data/tourisme_dao.dart';
import 'package:tatacora_flutter/features/transverse/data/configuration_poste.dart';
import 'package:uuid/uuid.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import '../pos/support/outils_ventes.dart';

/// LES RÉSERVATIONS À DEUX POSTES, contre le VRAI serveur (09/11/2026, spécification
/// du PO : « chaque poste voit SA réservation `En attente d'envoi` alors que l'autre l'a
/// reçue ; les montants et les services d'une même réservation diffèrent d'un poste à
/// l'autre ; le POS hébergés ne montre aucun client »).
///
/// Base : `TATACORA_BASE_ESSAI` (une base PRIVÉE `tatacora_<nom>_test`), sinon
/// `tatacora_test`. Deux postes (A = barman, B = gérant), un seul compte d'appairage.
///
/// Ce que le test prouve, chaque cas une cause :
///  1. l'ACCUSÉ pose « Synchronisée » sur la ligne (jamais posé avant : seul un test
///     appelait `majStatutSync`) ;
///  2. une MODIFICATION (service, prix, acompte) part, arrive à l'autre poste, avec les
///     lignes, le total, l'acompte et le reste à payer IDENTIQUES ;
///  3. une modification locale en attente n'est pas écrasée par la descente ;
///  4. un REFUS du serveur est lisible (badge « Refusée », « À traiter ») ;
///  5. le rattrapage d'une modification d'avant la correction (ligne locale, aucune
///     opération, déjà connue du serveur) ;
///  6. check-in au poste A → séjour visible au POS hébergés du poste B.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final base = Platform.environment['TATACORA_BASE_ESSAI'] ?? 'tatacora_test';
  final identifiant = 'e2e.resa.${const Uuid().v4().substring(0, 8)}';
  final motDePasse = 'E2e-${const Uuid().v4()}';
  final instantane =
      '${Directory.systemTemp.path}/${base}_resa_instantane.json';
  final journal = StringBuffer();
  late String url;
  late Directory dossier;
  late _Poste a;
  late _Poste b;
  late String uniteId;
  late String circuitId;
  late String clientId;

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

  setUpAll(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora-e2e-resa-');
    addTearDown(() => dossier.delete(recursive: true));

    final tenu = Completer<void>();
    final liberer = Completer<void>();
    final verrou = sousVerrouBaseDeTest<void>(() async {
      tenu.complete();
      await liberer.future;
    }, nom: base);
    await tenu.future;
    addTearDown(() async {
      liberer.complete();
      await verrou;
    });

    final prep = await php({
      'action': 'preparer',
      'instantane': instantane,
      'login': identifiant,
      'mot_de_passe': motDePasse,
    });
    expect(prep['base'], base);
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
      environment: {'DB_DATABASE': base, 'PHP_CLI_SERVER_WORKERS': '4'},
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

    a = _Poste(
      nom: 'RESA-A-BARMAN',
      chemin: '${dossier.path}/a.json',
      url: url,
    );
    b = _Poste(
      nom: 'RESA-B-GERANT',
      chemin: '${dossier.path}/b.json',
      url: url,
    );
    for (final p in [a, b]) {
      addTearDown(p.db.close);
      await avecComptabilite(p.db, maintenant: DateTime.now());
      final r = await p.appairage().appairer(
        identifiant: identifiant,
        motDePasse: motDePasse,
        nomPoste: p.nom,
      );
      expect(r, isA<AppairageReussi>(), reason: '${p.nom}\n$journal');
    }

    // Le parc, un client et une prestation de tourisme : écrits au poste A.
    final suffixe = const Uuid().v4().substring(0, 6);
    final parc = ParcDao(a.db);
    final categorie = (await parc.creerCategorie(
      libelle: 'Studio E2E $suffixe',
      capaciteMax: 2,
      tarifBase: 37500,
    )).id;
    uniteId = await parc.creerUnite(
      numero: 'E2E-$suffixe',
      categorieId: categorie,
    );
    clientId = (await ClientDao(a.db).creer(
      nom: 'Issa $suffixe',
      prenom: 'Robert',
      telephone: '9711${Random().nextInt(9000) + 1000}',
      type: TypeClientReferentiel.particulier,
    )).id;
    circuitId = (await TourismeDao(a.db).enregistrerCircuit(
      nom: 'Tanougou $suffixe',
      theme: 'nature',
      zone: 'Atacora',
      prix: 5000,
      capaciteMax: 10,
    )).id;
    await a.synchroniser();
    await Future<void>.delayed(const Duration(seconds: 6));
    await b.synchroniser();
  });

  final aujourdHui = DateTime.now();
  final arrivee = DateTime.utc(
    aujourdHui.year,
    aujourdHui.month,
    aujourdHui.day,
  );
  final periode = PeriodeSejour(
    arrivee: arrivee,
    depart: DateTime.utc(arrivee.year, arrivee.month, arrivee.day + 2),
  );
  late String reservationId;

  LigneService chambre({int prix = 37500}) => LigneService(
    id: 'l-${const Uuid().v4()}',
    service: ServiceReservation.hebergement,
    itemId: uniteId,
    libelle: 'Studio (E2E)',
    prixUnitaire: prix,
    quantite: 2,
  );
  LigneService tourisme() => LigneService(
    id: 'l-${const Uuid().v4()}',
    service: ServiceReservation.tourisme,
    itemId: circuitId,
    libelle: 'Tanougou',
    prixUnitaire: 5000,
    quantite: 1,
  );

  Future<Reservation> lire(_Poste p) async =>
      (await ReservationDao(p.db).parId(reservationId))!;

  Future<void> attendreHorizon() =>
      Future<void>.delayed(const Duration(seconds: 6));

  Future<UniteHebergement> uniteDe(_Poste p) async =>
      (await _depot(p).unites()).firstWhere((u) => u.id == uniteId);

  test('1. l’ACCUSÉ pose « Synchronisée » : A crée, le serveur accepte, B '
      'reçoit — le statut de A ne reste pas « En attente d’envoi »', () async {
    final creee = await CreerReservation(_depot(a))(
      unite: await uniteDe(a),
      clientId: clientId,
      clientNom: 'Robert Issa',
      periode: periode,
      acompte: 40000,
      modePaiement: ModePaiementReservation.especes,
      lignes: [chambre()],
      auteurId: caissierDeVente,
    );
    reservationId = creee.id;
    expect(
      (await lire(a)).statutSynchronisation,
      StatutSynchronisation.local,
      reason: 'à la création, avant tout envoi : en attente d’envoi',
    );

    await a.synchroniser();
    final o = (await OperationsSyncDao(a.db).operations(
      table: TableSynchronisee.reservations,
      entiteId: reservationId,
    )).single;
    expect(
      o.statut,
      StatutOperationSync.synchronise,
      reason: '${o.resultatJson}\n$journal',
    );

    expect(
      (await lire(a)).statutSynchronisation,
      StatutSynchronisation.synchronise,
      reason: 'accusé reçu, plus aucune opération en file : synchronisée',
    );

    await attendreHorizon();
    await b.synchroniser();
    final chezB = await lire(b);
    expect(chezB.statutSynchronisation, StatutSynchronisation.synchronise);
    expect(chezB.recapitulatif.total, 75000);
    expect(chezB.acompte, 40000);
  });

  test(
    '2. B ajoute un service Tourisme et change l’acompte : la '
    'modification arrive à A, lignes, total, acompte et reste identiques',
    () async {
      final avant = await lire(b);
      final modifiee = await ModifierReservation(_depot(b))(
        existante: avant,
        unite: await uniteDe(b),
        clientNom: 'Robert Issa',
        periode: periode,
        acompte: 45000,
        modePaiement: ModePaiementReservation.especes,
        lignes: [chambre(), tourisme()],
      );
      expect(modifiee.recapitulatif.total, 80000);
      expect(modifiee.statutSynchronisation, StatutSynchronisation.local);
      expect(
        await OperationsSyncDao(b.db).enSuspens('reservations', reservationId),
        isTrue,
        reason:
            'la modification est réellement en file : c’est ce qui justifie '
            '« En attente d’envoi »',
      );

      await b.synchroniser();
      final o = (await OperationsSyncDao(b.db).operations(
        table: TableSynchronisee.reservations,
        entiteId: reservationId,
      )).last;
      expect(o.type, TypeOperationSync.modification);
      expect(
        o.statut,
        StatutOperationSync.synchronise,
        reason: '${o.resultatJson}\n$journal',
      );
      expect(
        (await lire(b)).statutSynchronisation,
        StatutSynchronisation.synchronise,
      );

      await attendreHorizon();
      await a.synchroniser();
      final chezA = await lire(a);
      final chezB = await lire(b);
      expect(
        chezA.lignes.map((l) => l.service.cle).toSet(),
        contains('tourisme'),
      );
      expect(chezA.recapitulatif.total, 80000);
      expect(chezA.acompte, 45000);
      expect(chezA.resteAPayer, 35000);
      expect(chezA.statutSynchronisation, StatutSynchronisation.synchronise);
      expect(_fiche(chezA), _fiche(chezB));
    },
  );

  test('3. A change le prix de la nuit ; pendant ce temps B modifie : la '
      'modification locale en attente de A n’est JAMAIS écrasée par la '
      'descente, puis tout converge', () async {
    final avant = await lire(a);
    await ModifierReservation(_depot(a))(
      existante: avant,
      unite: await uniteDe(a),
      clientNom: 'Robert Issa',
      periode: periode,
      acompte: 45000,
      modePaiement: ModePaiementReservation.especes,
      lignes: [chambre(prix: 40000), tourisme()],
    );
    // La descente de A (sans envoi de sa file) ne doit pas toucher la ligne.
    await attendreHorizon();
    await a.descendreSeulement();
    final localA = await lire(a);
    expect(localA.tarifNuit, 40000);
    expect(localA.statutSynchronisation, StatutSynchronisation.local);

    await a.synchroniser();
    await attendreHorizon();
    await b.synchroniser();
    final chezA = await lire(a);
    final chezB = await lire(b);
    expect(chezB.tarifNuit, 40000);
    expect(chezB.recapitulatif.total, 85000);
    expect(_fiche(chezA), _fiche(chezB));
    expect(chezA.statutSynchronisation, StatutSynchronisation.synchronise);
    expect(chezB.statutSynchronisation, StatutSynchronisation.synchronise);
  });

  test('4. rattrapage : une modification d’AVANT la correction (ligne locale, '
      'connue du serveur, aucune opération) est envoyée', () async {
    // L’état laissé par l’ancienne version : la fiche est modifiée en base, le
    // statut est « local » et RIEN n’est dans la file.
    await b.db.customStatement(
      'UPDATE reservations_local SET acompte = 20000, '
      "statut_sync = 'local' WHERE id = ?",
      [reservationId],
    );
    expect(
      await OperationsSyncDao(b.db).enSuspens('reservations', reservationId),
      isFalse,
    );
    await b.synchroniser();
    expect(
      (await lire(b)).statutSynchronisation,
      StatutSynchronisation.synchronise,
    );
    await attendreHorizon();
    await a.synchroniser();
    expect((await lire(a)).acompte, 20000);
  });

  test('5. un REFUS du serveur est lisible : badge « Refusée », motif, et '
      'ligne dans « À traiter »', () async {
    // Un autre séjour de A sur la même chambre, créé hors ligne ; B déplace
    // d’abord sa propre réservation sur ces dates et l’envoie.
    final arriveeLoin = DateTime.utc(
      arrivee.year,
      arrivee.month,
      arrivee.day + 20,
    );
    final loin = PeriodeSejour(
      arrivee: arriveeLoin,
      depart: DateTime.utc(
        arriveeLoin.year,
        arriveeLoin.month,
        arriveeLoin.day + 2,
      ),
    );
    final concurrente = await CreerReservation(_depot(a))(
      unite: await uniteDe(a),
      clientId: clientId,
      clientNom: 'Robert Issa',
      periode: loin,
      acompte: 0,
      modePaiement: ModePaiementReservation.especes,
      lignes: [chambre()],
      auteurId: caissierDeVente,
    );
    final avant = await lire(b);
    await ModifierReservation(_depot(b))(
      existante: avant,
      unite: await uniteDe(b),
      clientNom: 'Robert Issa',
      periode: loin,
      acompte: 20000,
      modePaiement: ModePaiementReservation.especes,
      lignes: [chambre(prix: 40000), tourisme()],
    );
    await b.synchroniser();
    await a.synchroniser();

    final refusee = (await ReservationDao(a.db).parId(concurrente.id))!;
    expect(refusee.statutSynchronisation, StatutSynchronisation.rejete);
    expect(refusee.motifRejet, isNotNull);
    expect(refusee.motifRejet, isNotEmpty);
    expect([
      for (final t in await OperationsSyncDao(a.db).aTraiter())
        t.operation.entiteId,
    ], contains(concurrente.id));
    // La réservation de B, elle, a été acceptée : « Synchronisée ».
    expect(
      (await lire(b)).statutSynchronisation,
      StatutSynchronisation.synchronise,
    );
  });

  test(
    '6. POS hébergés : une réservation créée en A, check-in en A — visible '
    'au POS hébergés de B après synchronisation ; sans check-in, non',
    () async {
      await attendreHorizon();
      await a.synchroniser();
      await b.synchroniser();
      expect(
        (await lire(b)).statut,
        isNot(StatutReservation.enCours),
        reason:
            'pas de check-in : une réservation « en attente » n’est pas un séjour',
      );
      expect(
        [
          for (final r in await ReservationDao(b.db).reservations()) r,
        ].where(estSejourAuPos).map((r) => r.id),
        isNot(contains(reservationId)),
      );

      await SejourDao(a.db).checkin(reservationId);
      await a.synchroniser();
      await attendreHorizon();
      await b.synchroniser();

      final chezB = await lire(b);
      expect(chezB.statut, StatutReservation.enCours);
      expect(
        (await ReservationDao(
          b.db,
        ).reservations()).where(estSejourAuPos).map((r) => r.id),
        contains(reservationId),
      );
    },
  );
}

ReservationRepositoryLocal _depot(_Poste p) => ReservationRepositoryLocal(
  ReservationDao(p.db, moteur: () async => moteurSur(p.db)),
);

/// Ce qui doit être IDENTIQUE d’un poste à l’autre.
Map<String, Object?> _fiche(Reservation r) => {
  'unite': r.uniteId,
  'arrivee': r.periode.arrivee,
  'depart': r.periode.depart,
  'tarif': r.tarifNuit,
  'acompte': r.acompte,
  'total': r.recapitulatif.total,
  'reste': r.resteAPayer,
  'remise': r.remiseType ?? TypeRemise.aucune,
  'mode': r.modePaiement,
  'services': ([
    for (final l in r.lignes)
      if (l.service != ServiceReservation.hebergement)
        '${l.service.cle}:${l.itemId}:${l.prixUnitaire}x${l.quantite}',
  ]..sort()),
};

final class _Poste {
  _Poste({required this.nom, required this.chemin, required this.url});

  final String nom;
  final String chemin;
  final String url;
  final AppDatabase db = AppDatabase.enMemoire();
  var _horloge = DateTime.now();

  Future<String> cheminFuture() async => chemin;

  ServiceAppairage appairage() => ServiceAppairage(
    transport: TransportHttp(),
    urlServeur: url,
    lecteur: LecteurConfigurationPoste(chemin: cheminFuture),
    ecrivain: EcrivainConfigurationPoste(chemin: cheminFuture),
  );

  SyncManager _manager() => SyncManager(
    dao: OperationsSyncDao(db, maintenant: () => _horloge),
    transport: TransportHttp(),
    urlServeur: url,
    demonstration: false,
    lecteur: LecteurConfigurationPoste(chemin: cheminFuture),
    ecrivain: EcrivainConfigurationPoste(chemin: cheminFuture),
    maintenant: () => _horloge,
    descente: DescenteCatalogue(
      db: db,
      transport: TransportHttp(),
      auteur: () => DescenteCatalogueDao(db).auteurParDefaut(),
      maintenant: () => _horloge,
    ),
  );

  /// Envoi puis descente (un passage complet).
  Future<void> synchroniser() async {
    _horloge = _horloge.add(const Duration(hours: 1));
    await _manager().synchroniserMaintenant();
  }

  /// La descente SEULE — jamais un envoi (le battement de 30 s).
  Future<void> descendreSeulement() async {
    _horloge = _horloge.add(const Duration(hours: 1));
    await _manager().synchroniserDescenteSeule();
  }
}
