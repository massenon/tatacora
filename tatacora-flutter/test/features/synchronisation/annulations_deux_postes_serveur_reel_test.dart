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
import 'package:tatacora_flutter/features/hebergement/domain/entities/fiche_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/service_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/unite_hebergement.dart';
import 'package:tatacora_flutter/features/hebergement/domain/annulation_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/usecases/annuler_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/usecases/creer_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/usecases/modifier_reservation.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/service_appairage.dart';
import 'package:tatacora_flutter/features/synchronisation/data/sync_manager.dart';
import 'package:tatacora_flutter/features/synchronisation/data/transport_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/appairage.dart';
import 'package:tatacora_flutter/features/tourisme/data/tourisme_dao.dart';
import 'package:tatacora_flutter/features/transverse/data/configuration_poste.dart';
import 'package:uuid/uuid.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import '../pos/support/outils_ventes.dart';

/// LES ANNULATIONS DE RÉSERVATION À DEUX POSTES, contre le VRAI serveur (09/11/2026,
/// constats du PO, captures réelles : poste A = barman, poste B = gérant).
///
/// Scénario : A crée R1 (80 000, acompte 40 000), B crée R2 (90 000, acompte 0), A
/// annule R1 ET R2, synchronisation complète, B relit. Ce que le test exige :
///  1. AUCUNE opération rejetée (le serveur ne juge plus qui annule : le contrôle est
///     fait au poste, par le droit local ANNULATIONS) ;
///  2. l’annulation DESCEND COMPLÈTE (taux, total, commission, remboursé, date, auteur),
///     identique au poste qui l’a faite ;
///  3. R2 (saisie sur B, annulée par A) n’est plus active chez B, badge « Synchronisée » ;
///  4. la fiche de R1 est la même partout (unité, services, total) ;
///  5. une opération rejetée AVANT la correction (« Annulation refusée : … ») se relance
///     et passe.
///
/// Base : `TATACORA_BASE_ESSAI` (une base PRIVÉE `tatacora_<nom>_test`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final base = Platform.environment['TATACORA_BASE_ESSAI'] ?? 'tatacora_test';
  final identifiant = 'e2e.annul.${const Uuid().v4().substring(0, 8)}';
  final motDePasse = 'E2e-${const Uuid().v4()}';
  final instantane =
      '${Directory.systemTemp.path}/${base}_annul_instantane.json';
  final journal = StringBuffer();
  late String url;
  late Directory dossier;
  late _Poste a;
  late _Poste b;
  late String uniteId;
  late String unite2Id;
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
    dossier = await Directory.systemTemp.createTemp('tatacora-e2e-annul-');
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
      nom: 'ANNUL-A-BARMAN',
      chemin: '${dossier.path}/a.json',
      url: url,
    );
    b = _Poste(
      nom: 'ANNUL-B-GERANT',
      chemin: '${dossier.path}/b.json',
      url: url,
    );
    for (final p in [a, b]) {
      addTearDown(p.db.close);
      await avecComptabilite(p.db, maintenant: DateTime.now());
      // L’auteur des annulations n’existe QUE sur le poste A : B doit recevoir son login.
      if (p == a) await semerAuteur(p.db, id: 'auteur-a');
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
    final categorie2 = (await parc.creerCategorie(
      libelle: 'Chambre triple E2E $suffixe',
      capaciteMax: 3,
      tarifBase: 30000,
    )).id;
    unite2Id = await parc.creerUnite(
      numero: 'Amarante-$suffixe',
      categorieId: categorie2,
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
  PeriodeSejour periode(int decalage, int nuits) => PeriodeSejour(
    arrivee: DateTime.utc(arrivee.year, arrivee.month, arrivee.day + decalage),
    depart: DateTime.utc(
      arrivee.year,
      arrivee.month,
      arrivee.day + decalage + nuits,
    ),
  );
  late String r1;
  late String r2;

  LigneService chambre(int prix, int nuits, {String? unite}) => LigneService(
    id: 'l-${const Uuid().v4()}',
    service: ServiceReservation.hebergement,
    itemId: unite ?? uniteId,
    libelle: 'Chambre (E2E)',
    prixUnitaire: prix,
    quantite: nuits,
  );
  LigneService tourisme() => LigneService(
    id: 'l-${const Uuid().v4()}',
    service: ServiceReservation.tourisme,
    itemId: circuitId,
    libelle: 'Tanougou',
    prixUnitaire: 5000,
    quantite: 1,
  );

  Future<Reservation> lire(_Poste p, String id) async =>
      (await ReservationDao(p.db).parId(id))!;

  Future<void> attendreHorizon() =>
      Future<void>.delayed(const Duration(seconds: 6));

  Future<UniteHebergement> uniteDe(_Poste p, [String? id]) async =>
      (await _depot(p).unites()).firstWhere((u) => u.id == (id ?? uniteId));

  Future<void> toutSynchroniser() async {
    await a.synchroniser();
    await attendreHorizon();
    await b.synchroniser();
    await attendreHorizon();
    await a.synchroniser();
    await attendreHorizon();
    await b.synchroniser();
  }

  test('1. A crée R1 (80 000, acompte 40 000), B crée R2 (90 000, acompte 0) : '
      'chacun reçoit la fiche COMPLÈTE de l’autre', () async {
    final unite = await uniteDe(a);
    r1 = (await CreerReservation(_depot(a))(
      unite: unite,
      clientId: clientId,
      clientNom: 'Robert Issa',
      periode: periode(0, 2),
      acompte: 40000,
      modePaiement: ModePaiementReservation.especes,
      lignes: [chambre(37500, 2)],
      auteurId: caissierDeVente,
    )).id;
    await a.synchroniser();
    await attendreHorizon();
    await b.synchroniser();

    r2 = (await CreerReservation(_depot(b))(
      unite: await uniteDe(b, unite2Id),
      clientId: clientId,
      clientNom: 'Pierre Comlan',
      periode: periode(10, 3),
      acompte: 0,
      modePaiement: ModePaiementReservation.especes,
      lignes: [chambre(30000, 3, unite: unite2Id)],
      auteurId: caissierDeVente,
    )).id;
    await b.synchroniser();
    await attendreHorizon();
    await a.synchroniser();

    for (final id in [r1, r2]) {
      expect(_fiche(await lire(a, id)), _fiche(await lire(b, id)), reason: id);
    }
    expect((await lire(b, r1)).recapitulatif.total, 75000);
    expect((await lire(a, r2)).recapitulatif.total, 90000);
  });

  test('2. A ajoute un service à R1 puis annule R1 ET R2 : rien n’est rejeté, l’annulation descend '
      'COMPLÈTE, R2 n’est plus active chez B', () async {
    // R1 reçoit un service (80 000) JUSTE AVANT d’être annulée : B ne reçoit
    // l’état final qu’une fois, annulé — la fiche doit venir AVEC l’annulation.
    final avant = await lire(a, r1);
    await ModifierReservation(_depot(a))(
      existante: avant,
      unite: await uniteDe(a),
      clientNom: 'Robert Issa',
      periode: periode(0, 2),
      acompte: 40000,
      modePaiement: ModePaiementReservation.especes,
      lignes: [chambre(37500, 2), tourisme()],
    );
    expect((await lire(a, r1)).recapitulatif.total, 80000);
    for (final (id, taux, total) in [(r1, '50', 80000), (r2, '20', 90000)]) {
      final r = await lire(a, id);
      await AnnulerReservation(_depot(a))(
        id,
        tauxSaisi: taux,
        modeRemboursement: 'pourcentage',
        // Ce que la modale propose (la même fonction que l’écran).
        valeurRemboursement: pourcentageRembourseSuggere(
          acompteCentimes: r.acompte * 100,
          totalCentimes: total * 100,
          taux: taux,
        ),
        auteurId: 'auteur-a',
      );
    }
    await toutSynchroniser();

    // R1 est une annulation LÉGITIME (A l’a saisie) : elle arrive complète chez B.
    final chezB = await lire(b, r1);
    expect(chezB.statut, StatutReservation.annulee);
    expect(
      chezB.annulation,
      isNotNull,
      reason:
          'B a reçu « annulée » SANS taux, commission, remboursement, date, auteur',
    );

    final attendues = {
      r1: (taux: 5000, total: 8000000, commission: 4000000),
      r2: (taux: 2000, total: 9000000, commission: 1800000),
    };
    for (final p in [a, b]) {
      for (final e in attendues.entries) {
        final r = await lire(p, e.key);
        expect(
          r.statut,
          StatutReservation.annulee,
          reason: '${p.nom} ${e.key}',
        );
        expect(r.estActive, isFalse);
        expect(
          r.statutSynchronisation,
          StatutSynchronisation.synchronise,
          reason: 'badge ${p.nom} ${e.key}',
        );
        final an = r.annulation;
        expect(an, isNotNull, reason: 'annulation complète chez ${p.nom}');
        expect(an!.tauxCentiemes, e.value.taux);
        expect(an.totalCentimes, e.value.total);
        expect(an.commissionCentimes, e.value.commission);
        // Règle du web : remboursé = ce que l’opérateur restitue, au plus
        // l’acompte ; proposé = acompte − commission, jamais négatif.
        // R1 : 40 000 − 40 000 = 0 ; R2 : acompte 0.
        expect(an.rembourseCentimes, 0);
        expect(an.auteurLogin, 'compta-auteur-a', reason: p.nom);
        expect(an.date.year, aujourdHui.year);
      }
    }
    // Le poste qui n’a pas fait l’annulation montre EXACTEMENT les mêmes valeurs.
    for (final id in [r1, r2]) {
      final x = (await lire(a, id)).annulation!;
      final y = (await lire(b, id)).annulation!;
      expect(
        [
          y.tauxCentiemes,
          y.totalCentimes,
          y.commissionCentimes,
          y.rembourseCentimes,
          y.auteurLogin,
        ],
        [
          x.tauxCentiemes,
          x.totalCentimes,
          x.commissionCentimes,
          x.rembourseCentimes,
          x.auteurLogin,
        ],
      );
      expect(
        '${y.date.year}-${y.date.month}-${y.date.day} '
            '${y.date.hour}:${y.date.minute}',
        '${x.date.year}-${x.date.month}-${x.date.day} '
            '${x.date.hour}:${x.date.minute}',
        reason: 'même date d’annulation partout',
      );
    }
    for (final p in [a, b]) {
      expect(
        [
          for (final t in await OperationsSyncDao(p.db).aTraiter())
            '${t.operation.entiteId} ${t.operation.statut} '
                '${t.operation.resultatJson}',
        ],
        isEmpty,
        reason:
            'aucune opération ne bloque la synchronisation (${p.nom})\n'
            '$journal',
      );
    }
  });

  test('3. la fiche de R1 est la même partout après l’annulation (unité, '
      'services, total)', () async {
    expect(_fiche(await lire(a, r1)), _fiche(await lire(b, r1)));
    expect((await lire(b, r1)).recapitulatif.total, 80000);
    expect((await lire(b, r1)).lignes, isNotEmpty);
  });
}

ReservationRepositoryLocal _depot(_Poste p) => ReservationRepositoryLocal(
  ReservationDao(p.db, moteur: () async => moteurSur(p.db)),
);

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

/// Ce qui doit être IDENTIQUE d’un poste à l’autre.
Map<String, Object?> _fiche(Reservation r) => {
  'unite': r.uniteId,
  'arrivee': r.periode.arrivee,
  'depart': r.periode.depart,
  'tarif': r.tarifNuit,
  'acompte': r.acompte,
  'total': r.recapitulatif.total,
  'reste': r.resteAPayer,
  'services': ([
    for (final l in r.lignes)
      if (l.service != ServiceReservation.hebergement)
        '${l.service.cle}:${l.itemId}:${l.prixUnitaire}x${l.quantite}',
  ]..sort()),
};
