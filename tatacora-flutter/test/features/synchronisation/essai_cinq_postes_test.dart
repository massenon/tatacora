@Timeout(Duration(minutes: 15))
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
import 'package:tatacora_flutter/features/hebergement/domain/usecases/creer_reservation.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';
import 'package:tatacora_flutter/features/synchronisation/data/controle_coherence.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/service_appairage.dart';
import 'package:tatacora_flutter/features/synchronisation/data/sync_manager.dart';
import 'package:tatacora_flutter/features/synchronisation/data/transport_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/appairage.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/transverse/data/configuration_poste.dart';
import 'package:uuid/uuid.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import 'support/journee_caisse.dart';

/// L'ESSAI DE RÉCEPTION À CINQ POSTES (spécification de synchronisation,
/// « avant la PR ») contre le VRAI serveur : `php artisan serve` sur
/// `tatacora_test`, le vrai transport HTTP, cinq bases de poste.
///
/// Chaque poste vit sa journée — un client, une journée de comptoir (caisse
/// ouverte au bar, deux ventes, une dépense, caisse close), une perte de
/// stock —, puis les cinq se synchronisent dans le désordre, avec des
/// COUPURES tirées au hasard (graine fixe) : requête jamais partie, ou
/// réponse perdue après que le serveur a écrit. Enfin, réseau rétabli, deux
/// passes propres.
///
/// Ce qui doit tenir : aucune opération restée en route, aucun doublon au
/// serveur malgré les réponses perdues, et le contrôle de cohérence (P1-1)
/// de CHAQUE poste sans écart — mêmes ventes, dépenses, mouvements… que le
/// serveur, donc que les quatre autres. Les seuls refus admis sont ceux que
/// la règle impose et que « À traiter » montre : une caisse du bar ouverte
/// pendant qu'un autre poste tenait encore la sienne.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final identifiant = 'e2e.5p.${const Uuid().v4().substring(0, 8)}';
  final motDePasse = 'E2e-${const Uuid().v4()}';
  final instantane =
      '${Directory.systemTemp.path}/tatacora_e2e_5p_instantane.json';
  final journal = StringBuffer();
  late String url;
  late Directory dossier;
  final postes = <_Poste>[];

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
    HttpOverrides.global = null;
    dossier = await Directory.systemTemp.createTemp('tatacora-e2e-5p-');
    addTearDown(() => dossier.delete(recursive: true));

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

    final prep = await php({
      'action': 'preparer',
      'instantane': instantane,
      'login': identifiant,
      'mot_de_passe': motDePasse,
    });
    expect(prep['base'], 'tatacora_test');
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
      environment: {
        'DB_DATABASE': 'tatacora_test',
        'PHP_CLI_SERVER_WORKERS': '4',
      },
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

    final hasard = Random(20261018);
    final aujourdHui = DateTime.now();
    for (var i = 0; i < 5; i++) {
      final p = _Poste(
        nom: 'ESSAI-5P-${i + 1}',
        chemin: '${dossier.path}/poste-${i + 1}.json',
        url: url,
        hasard: Random(hasard.nextInt(1 << 30)),
      );
      addTearDown(p.db.close);
      final r = await p.appairage().appairer(
        identifiant: identifiant,
        motDePasse: motDePasse,
        nomPoste: p.nom,
      );
      expect(r, isA<AppairageReussi>(), reason: '${p.nom}\n$journal');
      // Cinq journées sur les cinq derniers jours, une par poste.
      final jour = DateTime(
        aujourdHui.year,
        aujourdHui.month,
        aujourdHui.day - 5 + i,
        10,
      );
      await p.vivreSaJournee(jour, i + 1);
      postes.add(p);
    }
  });

  test('cinq postes, coupures au hasard : rien de perdu, rien en double, '
      'chaque poste cohérent avec le serveur', () async {
    // 1. Six tours dans le désordre, réseau coupé au hasard.
    final ordre = Random(7);
    for (var tour = 0; tour < 6; tour++) {
      for (final p in [...postes]..shuffle(ordre)) {
        await p.synchroniser(coupures: true);
      }
    }
    // 2. Réseau rétabli : deux passes propres (la seconde descend ce que
    //    les derniers envois de la première ont posé au serveur).
    //    Entre les deux, l'HORIZON du flux (`CatalogueDescendantService::
    //    HORIZON_SECONDES`, 5 s) : une ligne plus jeune ne descend pas
    //    encore — le réveil réel du poste (30 s, 5 min) l'attend toujours.
    for (var passe = 0; passe < 2; passe++) {
      if (passe == 1) await Future<void>.delayed(const Duration(seconds: 6));
      for (final p in postes) {
        await p.synchroniser(coupures: false);
      }
    }

    final aujourdHui = DateTime.now();
    final bilans = <String>[];
    for (final p in postes) {
      final ops = await OperationsSyncDao(p.db).operations();
      // Rien n'est resté en route.
      final enRoute = [
        for (final o in ops)
          if (o.statut == StatutOperationSync.enAttente ||
              o.statut == StatutOperationSync.enCours ||
              o.statut == StatutOperationSync.bloque ||
              o.statut == StatutOperationSync.conflit)
            '${o.type.code} ${o.table.nomServeur} ${o.statut.code} '
                '${o.derniereErreur ?? ''}',
      ];
      expect(enRoute, isEmpty, reason: '${p.nom}\n$journal');
      // Les seuls refus : une caisse du bar déjà ouverte par un autre poste.
      final refus = [
        for (final o in ops)
          if (o.statut == StatutOperationSync.rejete) o,
      ];
      for (final o in refus) {
        expect(
          o.table,
          TableSynchronisee.sessionsCaisse,
          reason: '${p.nom} : ${o.table.nomServeur} ${o.resultatJson}',
        );
        expect(
          o.type,
          TypeOperationSync.creation,
          reason: '${p.nom} : ${o.resultatJson}',
        );
      }

      // Le contrôle de cohérence : ce poste contre le serveur, sept jours.
      final issue = await ControleCoherence(
        db: p.db,
        transport: TransportHttp(),
        urlServeur: url,
        lecteur: LecteurConfigurationPoste(chemin: p.cheminFuture),
      ).controler(aujourdHui: aujourdHui);
      expect(issue, isA<CoherenceMesuree>(), reason: p.nom);
      final m = issue as CoherenceMesuree;
      expect(
        [
          for (final e in m.ecarts)
            '${e.table} ${e.jour} : serveur ${e.serveur} / poste ${e.poste}',
        ],
        isEmpty,
        reason: p.nom,
      );
      expect(m.tables, containsAll(['ventes', 'depenses', 'mouvements_stock']));
      // Un REFUS de descente est une faute. Une ATTENTE de dépendance (une vente
      // dont la session de caisse arrive dans une page que la coupure a retardée)
      // est transitoire par construction : elle est reprise à la descente
      // suivante — ce que prouve l'absence d'élément gardé ci-dessous.
      expect(
        p.motifs.where((m) => !m.startsWith('attente')),
        isEmpty,
        reason: '${p.nom} : refus de descente',
      );
      final gardes = await p.db
          .customSelect(
            "SELECT cle FROM etat_synchronisation_local "
            "WHERE cle LIKE 'element_differe:%'",
          )
          .get();
      expect(
        gardes,
        isEmpty,
        reason: '${p.nom} : un élément est resté en attente de dépendance',
      );
      bilans.add('${p.nom} : ${ops.length} op., ${refus.length} refus');
    }

    // Chaque poste voit les cinq clients, une seule fois chacun — aucune
    // réponse perdue n'a doublé un document au serveur.
    for (final p in postes) {
      final clients = await p.db
          .customSelect(
            "SELECT COUNT(*) AS n FROM clients_local WHERE nom LIKE 'E5P %'",
          )
          .getSingle();
      expect(clients.data['n'], 5, reason: p.nom);
      final ventes = await p.db
          .customSelect(
            "SELECT COUNT(*) AS n FROM paniers_local WHERE statut = 'cloture'",
          )
          .getSingle();
      expect(ventes.data['n'] as int, greaterThanOrEqualTo(10), reason: p.nom);
    }
    // ignore: avoid_print
    print(bilans.join('\n'));
  });

  test(
    'un conflit RÉEL : la même chambre, aux mêmes dates, réservée sur deux '
    'postes hors ligne — le second est refusé (RG-01) et paraît dans « À '
    'traiter » ; le contrôle de cohérence montre l’écart qu’il explique',
    () async {
      final p1 = postes[0];
      final p2 = postes[1];
      final parc = ParcDao(p1.db);
      final categorie = (await parc.creerCategorie(
        libelle: 'Bungalow E5P',
        capaciteMax: 2,
        tarifBase: 25000,
      )).id;
      final unite = await parc.creerUnite(
        numero: 'E5P-CH1',
        categorieId: categorie,
      );
      await p1.synchroniser(coupures: false);
      await Future<void>.delayed(const Duration(seconds: 6));
      await p2.synchroniser(coupures: false);

      final arrivee = DateTime.now().add(const Duration(days: 10));
      final periode = PeriodeSejour(
        arrivee: DateTime(arrivee.year, arrivee.month, arrivee.day),
        depart: DateTime(arrivee.year, arrivee.month, arrivee.day + 2),
      );
      Future<String> reserver(_Poste p) async {
        final depot = ReservationRepositoryLocal(
          ReservationDao(p.db, moteur: () async => moteurSur(p.db)),
        );
        final u = (await depot.unites()).firstWhere((x) => x.id == unite);
        final client =
            (await p.db
                        .customSelect(
                          "SELECT id FROM clients_local WHERE nom LIKE 'E5P %' LIMIT 1",
                        )
                        .getSingle())
                    .data['id']
                as String;
        return (await CreerReservation(depot)(
          unite: u,
          clientId: client,
          clientNom: 'E5P',
          periode: periode,
          acompte: 0,
          modePaiement: ModePaiementReservation.especes,
          auteurId: auteurEssai,
        )).id;
      }

      final premiere = await reserver(p1);
      final seconde = await reserver(p2);
      await p1.synchroniser(coupures: false);
      await p2.synchroniser(coupures: false);

      final o1 = (await OperationsSyncDao(p1.db).operations(
        table: TableSynchronisee.reservations,
        entiteId: premiere,
      )).single;
      expect(
        o1.statut,
        StatutOperationSync.synchronise,
        reason: '${o1.resultatJson}',
      );
      final o2 = (await OperationsSyncDao(p2.db).operations(
        table: TableSynchronisee.reservations,
        entiteId: seconde,
      )).single;
      expect(
        o2.statut,
        StatutOperationSync.rejete,
        reason: '${o2.resultatJson}',
      );
      expect([
        for (final a in await OperationsSyncDao(p2.db).aTraiter())
          a.operation.entiteId,
      ], contains(seconde));

      await Future<void>.delayed(const Duration(seconds: 6));
      await p2.synchroniser(coupures: false);
      final m =
          await ControleCoherence(
                db: p2.db,
                transport: TransportHttp(),
                urlServeur: url,
                lecteur: LecteurConfigurationPoste(chemin: p2.cheminFuture),
              ).controler(aujourdHui: periode.arrivee)
              as CoherenceMesuree;
      final ecart = m.ecarts.singleWhere((e) => e.table == 'reservations');
      expect((ecart.serveur.nombre, ecart.poste.nombre), (1, 2));
    },
  );
}

/// Un poste de l'essai : sa base, son `poste.json`, son moteur, et un
/// transport qui COUPE au hasard (avant l'envoi, ou après — réponse perdue).
final class _Poste {
  _Poste({
    required this.nom,
    required this.chemin,
    required this.url,
    required this.hasard,
  });

  final String nom;
  final String chemin;
  final String url;
  final Random hasard;
  final AppDatabase db = AppDatabase.enMemoire();
  final motifs = <String>{};

  /// L'horloge du moteur : avancée d'une heure à chaque passage, pour que
  /// les reprises après coupure soient échues sans attendre.
  var _horloge = DateTime.now();

  Future<String> cheminFuture() async => chemin;

  ServiceAppairage appairage() => ServiceAppairage(
    transport: TransportHttp(),
    urlServeur: url,
    lecteur: LecteurConfigurationPoste(chemin: cheminFuture),
    ecrivain: EcrivainConfigurationPoste(chemin: cheminFuture),
  );

  Future<void> vivreSaJournee(DateTime jour, int rang) async {
    final j = await jouerJourneeDeCaisse(db, jour: jour);
    await ClientDao(db).creer(
      nom: 'E5P $rang',
      telephone: '9700000$rang',
      type: TypeClientReferentiel.particulier,
    );
    await StocksDao(
      db,
      maintenant: () => jour.add(const Duration(hours: 6)),
    ).ajouterMouvement(
      articleId: j.article,
      pointId: j.point,
      type: TypeMouvement.perte,
      centiemes: 100,
      motif: 'Casse E5P',
      auteurId: auteurEssai,
      forcage: true,
    );
  }

  Future<void> synchroniser({required bool coupures}) async {
    _horloge = _horloge.add(const Duration(hours: 1));
    final transport = coupures
        ? _TransportCoupe(TransportHttp(), hasard)
        : TransportHttp();
    final bilan = await SyncManager(
      // La MÊME horloge que le moteur : l'échéance d'une reprise se juge
      // sur elle.
      dao: OperationsSyncDao(db, maintenant: () => _horloge),
      transport: transport,
      urlServeur: url,
      demonstration: false,
      lecteur: LecteurConfigurationPoste(chemin: cheminFuture),
      ecrivain: EcrivainConfigurationPoste(chemin: cheminFuture),
      maintenant: () => _horloge,
      descente: DescenteCatalogue(
        db: db,
        transport: transport,
        auteur: () => DescenteCatalogueDao(db).auteurParDefaut(),
        maintenant: () => _horloge,
      ),
    ).synchroniserMaintenant();
    final d = bilan.descente;
    if (d != null) {
      motifs.addAll(d.motifsRefus);
      if (d.enAttenteDeDependance > 0) {
        motifs.add('attente ${d.enAttenteDeDependance}');
      }
    }
  }
}

/// Coupe une requête sur trois environ : la moitié n'est jamais partie, l'autre
/// a été TRAITÉE par le serveur et sa réponse s'est perdue.
final class _TransportCoupe implements TransportSynchronisation {
  _TransportCoupe(this._vrai, this._hasard);

  final TransportSynchronisation _vrai;
  final Random _hasard;

  Future<IssueHttp> _peutEtre(Future<IssueHttp> Function() envoyer) async {
    if (_hasard.nextDouble() < 0.15) {
      return const ServeurInjoignable('coupure avant envoi');
    }
    final r = await envoyer();
    if (_hasard.nextDouble() < 0.15) {
      return const ServeurInjoignable('réponse perdue');
    }
    return r;
  }

  @override
  Future<IssueHttp> post(
    Uri url, {
    Map<String, Object?>? corps,
    String? jeton,
  }) => _peutEtre(() => _vrai.post(url, corps: corps, jeton: jeton));

  @override
  Future<IssueHttp> get(Uri url, {String? jeton}) =>
      _peutEtre(() => _vrai.get(url, jeton: jeton));
}
