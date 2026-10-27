import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/depenses/data/depense_dao.dart';
import 'package:tatacora_flutter/features/depenses/data/recus_depenses_locaux.dart';
import 'package:tatacora_flutter/features/depenses/domain/categories_depense.dart';
import 'package:tatacora_flutter/features/depenses/domain/entities/depense.dart';
import 'package:tatacora_flutter/features/depenses/domain/recu_depense.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/envoi_recus_depenses.dart';
import 'package:tatacora_flutter/features/synchronisation/data/sync_manager.dart';
import 'package:tatacora_flutter/features/synchronisation/data/telechargement_recu_depense.dart';
import 'package:tatacora_flutter/features/synchronisation/data/transport_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/bilan_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import '../depenses/support/corpus_recus.dart';
import '../depenses/support/faux_transport_fichiers.dart';
import '../depenses/support/outils_depenses.dart';
import 'support/faux_transport.dart';

/// Le reçu d'une dépense DANS la synchronisation (lot L4, décision D4 du PO du
/// 27/10/2026) : le fichier a sa propre porte (`PUT /sync/depenses/{id}/recu`),
/// branchée sur le MÊME passage que la file — même interrupteur, même
/// génération, mêmes refus 401/403 — et son état ne se dit que de l'accusé.
void main() {
  late BancSync b;
  late DepenseDao dao;
  late RecusDepensesLocaux recus;
  late List<String> journal;
  late FauxTransportFichiers fichiers;

  final jour = DateTime(2026, 10, 15, 10);

  setUp(() async {
    b = await BancSync.creer();
    b.maintenant = jour;
    await depenseDaoPrepare(b.db, jour);
    recus = RecusDepensesLocaux(
      () async => Directory('${b.dossier.path}/recus_depenses'),
    );
    dao = DepenseDao(
      b.db,
      maintenant: () => jour,
      moteur: () async => moteurSur(b.db, maintenant: () => jour),
      recus: recus,
    );
    journal = [];
    fichiers = FauxTransportFichiers((r) => depotAccepte(), journal: journal);
  });
  tearDown(() => b.fermer());

  EnvoiRecusDepenses envoi() => EnvoiRecusDepenses(
    db: b.db,
    transport: fichiers,
    recus: recus,
    maintenant: () => jour,
  );

  Future<Depense> saisir({bool avecRecu = true}) async => dao.enregistrer(
    dateTransaction: DateTime(2026, 10, 14),
    tresorerie: TresorerieDepense.caisse,
    libelle: 'Marché',
    auteurId: auteurDepense,
    centreId: await centreDe(b.db, 'Restaurant'),
    lignes: const [
      SaisieLigneDepense(
        libelle: 'Tomates',
        compteCharge: '6011',
        nature: NatureDepense.tomate,
        montant: 8500,
      ),
    ],
    recu: avecRecu
        ? RecuAJoindre(nom: 't.png', octets: octetsPng(), type: TypeRecu.png)
        : null,
  );

  /// La création de la dépense est ACCUSÉE par le serveur.
  Future<void> accuserCreation(String id) async {
    final op = (await b.dao.operations(
      table: TableSynchronisee.depenses,
      entiteId: id,
    )).single;
    await b.dao.marquerResultat(
      op.uuidOperation,
      resultat: {
        'uuid_operation': op.uuidOperation,
        'statut': 'synchronise',
        'entite_id': id,
      },
      codeHttp: 200,
    );
  }

  Future<StatutRecu?> statut(String id) async =>
      (await dao.parId(id))!.recu?.statut;

  Future<BilanEnvoiRecus> passer({String? generation = 'gen-1'}) async =>
      envoi().envoyer((await b.lecteur.appairage())!, generation: generation);

  group('l’envoi du reçu', () {
    test('un reçu ne part JAMAIS avant l’accusé de sa dépense : aucune '
        'requête, il reste « en attente »', () async {
      final d = await saisir();
      final bilan = await passer();
      expect(fichiers.requetes, isEmpty);
      expect(bilan.enAttente, 1);
      expect(await statut(d.id), StatutRecu.enAttente);
    });

    test('la dépense accusée, le reçu part : fichier BRUT, empreinte, jeton, '
        'poste et génération ; l’accusé seul le fait « envoyé »', () async {
      final d = await saisir();
      await accuserCreation(d.id);

      final bilan = await passer();

      final depot = fichiers.depots.single;
      expect(depot.chemin, '/api/v1/sync/depenses/${d.id}/recu');
      expect(depot.url.queryParameters, {
        'poste_id': BancSync.poste,
        'generation': 'gen-1',
      });
      expect(depot.octets, octetsPng());
      expect(depot.type, 'image/png');
      expect(
        depot.entetes['X-Recu-Sha256'],
        RecusDepensesLocaux.empreinte(octetsPng()),
      );
      expect(depot.jeton, BancSync.jeton);
      expect(bilan.envoyes, 1);
      expect(await statut(d.id), StatutRecu.envoye);
      expect(await dao.recusEnAttente(), isEmpty);
    });

    test('une dépense sans reçu ne déclenche AUCUN dépôt', () async {
      final d = await saisir(avecRecu: false);
      await accuserCreation(d.id);
      await passer();
      expect(fichiers.requetes, isEmpty);
    });

    test('REJEU après coupure : la réponse est perdue, le reçu reste « en '
        'attente » (jamais « envoyé » sans accusé) ; le renvoi du MÊME fichier '
        'est accusé', () async {
      final d = await saisir();
      await accuserCreation(d.id);

      fichiers.repondre = (r) => const ServeurInjoignable('délai dépassé');
      final coupe = await passer();
      expect(coupe.arret, ArretEnvoiRecus.serveurIndisponible);
      expect(await statut(d.id), StatutRecu.enAttente);

      fichiers.repondre = (r) => depotAccepte(rejeu: true);
      final bilan = await passer();
      expect(bilan.envoyes, 1);
      expect(await statut(d.id), StatutRecu.envoye);
      expect(
        fichiers.depots[0].octets,
        fichiers.depots[1].octets,
        reason: 'le MÊME fichier est renvoyé',
      );
      expect(
        fichiers.depots[0].entetes['X-Recu-Sha256'],
        fichiers.depots[1].entetes['X-Recu-Sha256'],
      );
    });

    test('404 « dépense inconnue » : la dépense n’est pas encore arrivée au '
        'serveur, le reçu attend et les suivants passent', () async {
      final premier = await saisir();
      final second = await saisir();
      await accuserCreation(premier.id);
      await accuserCreation(second.id);
      fichiers.repondre = (r) => r.chemin.contains(premier.id)
          ? refusServeur(
              404,
              'depense_inconnue',
              'Cette dépense n’est pas encore connue du serveur.',
              champ: false,
            )
          : depotAccepte();

      final bilan = await passer();
      expect(bilan.arret, isNull);
      expect(await statut(premier.id), StatutRecu.enAttente);
      expect(await statut(second.id), StatutRecu.envoye);
    });

    for (final (statut, code) in const [
      (422, 'recu_invalide'),
      (413, 'recu_trop_lourd'),
      (409, 'recu_deja_rattache'),
      (403, 'recu_autre_poste'),
    ]) {
      test('un refus de FOND ($statut $code) est définitif : « refusé », avec '
          'la phrase du serveur, jamais renvoyé', () async {
        final d = await saisir();
        await accuserCreation(d.id);
        fichiers.repondre = (r) =>
            refusServeur(statut, code, 'Phrase du serveur pour $code.');

        final bilan = await passer();
        expect(bilan.refuses, 1);
        final recu = (await dao.parId(d.id))!.recu!;
        expect(recu.statut, StatutRecu.refuse);
        expect(recu.cause, 'Phrase du serveur pour $code.');

        fichiers.requetes.clear();
        await passer();
        expect(
          fichiers.requetes,
          isEmpty,
          reason: 'un refus ne se renvoie pas',
        );
      });
    }

    test(
      'un refus sans phrase lisible dit tout de même le code HTTP',
      () async {
        final d = await saisir();
        await accuserCreation(d.id);
        fichiers.repondre = (r) => const ReponseHttp(statut: 418, corps: null);
        await passer();
        expect(
          (await dao.parId(d.id))!.recu!.cause,
          TextesRecuPoste.refuseParLeServeur(418),
        );
      },
    );

    for (final statutHttp in const [408, 429, 500, 503]) {
      test('HTTP $statutHttp : le serveur est indisponible, le reçu reste en '
          'attente et le passage s’arrête', () async {
        final premier = await saisir();
        final second = await saisir();
        await accuserCreation(premier.id);
        await accuserCreation(second.id);
        fichiers.repondre = (r) => ReponseHttp(statut: statutHttp, corps: null);

        final bilan = await passer();
        expect(bilan.arret, ArretEnvoiRecus.serveurIndisponible);
        expect(fichiers.requetes.length, 1, reason: 'on s’arrête au premier');
        expect(await statut(premier.id), StatutRecu.enAttente);
        expect(await statut(second.id), StatutRecu.enAttente);
      });
    }

    test(
      '401 : le jeton est refusé — arrêt, le reçu reste en attente',
      () async {
        final d = await saisir();
        await accuserCreation(d.id);
        fichiers.repondre = (r) => const ReponseHttp(statut: 401, corps: null);
        expect((await passer()).arret, ArretEnvoiRecus.jetonRefuse);
        expect(await statut(d.id), StatutRecu.enAttente);
      },
    );

    test('403 SANS code : le poste n’est pas celui du jeton — arrêt', () async {
      final d = await saisir();
      await accuserCreation(d.id);
      fichiers.repondre = (r) => const ReponseHttp(
        statut: 403,
        corps: {'message': 'Le poste déclaré ne correspond pas…'},
      );
      expect((await passer()).arret, ArretEnvoiRecus.posteNonReconnu);
      expect(await statut(d.id), StatutRecu.enAttente);
    });

    test('409 « génération périmée » : le serveur a été réinitialisé — arrêt '
        'avec sa date', () async {
      final d = await saisir();
      await accuserCreation(d.id);
      fichiers.repondre = (r) => const ReponseHttp(
        statut: 409,
        corps: {
          'code': 'generation_perimee',
          'reinitialisee_le': '2026-10-20T08:00:00+00:00',
        },
      );
      final bilan = await passer();
      expect(bilan.arret, ArretEnvoiRecus.serveurReinitialise);
      expect(bilan.reinitialiseLe, DateTime.parse('2026-10-20T08:00:00+00:00'));
      expect(await statut(d.id), StatutRecu.enAttente);
    });

    test('le fichier a disparu du poste : « refusé » avec la cause, SANS '
        'requête', () async {
      final d = await saisir();
      await accuserCreation(d.id);
      File('${b.dossier.path}/recus_depenses/${d.id}.png').deleteSync();
      await passer();
      expect(fichiers.requetes, isEmpty);
      final recu = (await dao.parId(d.id))!.recu!;
      expect(recu.statut, StatutRecu.refuse);
      expect(recu.cause, TextesRecuPoste.fichierIntrouvable);
    });

    test('le fichier a CHANGÉ depuis qu’il a été joint : « refusé », SANS '
        'requête (l’empreinte jointe n’est plus la sienne)', () async {
      final d = await saisir();
      await accuserCreation(d.id);
      File(
        '${b.dossier.path}/recus_depenses/${d.id}.png',
      ).writeAsBytesSync(octetsJpeg());
      await passer();
      expect(fichiers.requetes, isEmpty);
      expect(
        (await dao.parId(d.id))!.recu!.cause,
        TextesRecuPoste.fichierModifie,
      );
    });

    test('au plus `maxParPassage` dépôts par passage', () async {
      for (var i = 0; i < 3; i++) {
        final d = await saisir();
        await accuserCreation(d.id);
      }
      final court = EnvoiRecusDepenses(
        db: b.db,
        transport: fichiers,
        recus: recus,
        maxParPassage: 2,
      );
      await court.envoyer((await b.lecteur.appairage())!);
      expect(fichiers.depots.length, 2);
      expect((await dao.recusEnAttente()).length, 1);
    });
  });

  group('dans le passage du SyncManager', () {
    SyncManager gestionnaire(TransportSynchronisation t) => SyncManager(
      dao: b.dao,
      transport: t,
      urlServeur: BancSync.urlServeur,
      demonstration: false,
      lecteur: b.lecteur,
      ecrivain: b.ecrivain,
      maintenant: () => b.maintenant,
      recus: envoi(),
    );

    test('APRÈS l’envoi de la file (la dépense est acceptée d’abord) : la '
        'création part par POST /sync, PUIS le reçu par PUT — et il est '
        'accusé', () async {
      final d = await saisir();
      final json = FauxTransport((r) {
        journal.add('POST ${r.url.path}');
        return reponseLot(r);
      });

      final bilan = await gestionnaire(json).synchroniserMaintenant();

      expect(bilan.etat, EtatSynchronisation.termine);
      expect(journal, [
        'POST /api/v1/sync',
        'PUT /api/v1/sync/depenses/${d.id}/recu',
      ]);
      expect(await statut(d.id), StatutRecu.envoye);
    });

    test('la dépense REJETÉE par le serveur : son reçu ne part pas, il reste '
        '« en attente »', () async {
      final d = await saisir();
      final json = FauxTransport(
        (r) => reponseLot(
          r,
          particulier: (o) => {
            'uuid_operation': o['uuid_operation'],
            'statut': 'rejete',
            'entite_id': o['entite_id'],
            'motif': 'Refusée.',
            'code_motif': 'regle_metier',
          },
        ),
      );
      await gestionnaire(json).synchroniserMaintenant();
      expect(fichiers.requetes, isEmpty);
      expect(await statut(d.id), StatutRecu.enAttente);
    });

    test('INTERRUPTEUR éteint : AUCUNE requête, ni JSON ni fichier ; le reçu '
        'reste « en attente » et part à la réactivation', () async {
      final d = await saisir();
      await b.ecrivain.enregistrerSynchronisationActivee(
        false,
        par: 'gerant',
        le: jour,
      );
      final json = FauxTransport((r) => throw StateError('RÉSEAU : ${r.url}'));
      fichiers.repondre = (r) => throw StateError('FICHIER : ${r.url}');

      final bilan = await gestionnaire(json).synchroniserMaintenant();

      expect(bilan.etat, EtatSynchronisation.desactivee);
      expect(json.requetes, isEmpty);
      expect(fichiers.requetes, isEmpty);
      expect(await statut(d.id), StatutRecu.enAttente);

      await b.ecrivain.enregistrerSynchronisationActivee(
        true,
        par: 'gerant',
        le: jour,
      );
      fichiers.repondre = (r) => depotAccepte();
      final repris = FauxTransport((r) => reponseLot(r));
      await gestionnaire(repris).synchroniserMaintenant();
      expect(await statut(d.id), StatutRecu.envoye);
    });

    test('hors réseau : le serveur ne répond pas — le reçu reste « en '
        'attente », la dépense aussi', () async {
      final d = await saisir();
      final json = FauxTransport((r) => const ServeurInjoignable('réseau'));
      fichiers.repondre = (r) => const ServeurInjoignable('réseau');
      final bilan = await gestionnaire(json).synchroniserMaintenant();
      expect(bilan.etat, EtatSynchronisation.serveurIndisponible);
      expect(fichiers.requetes, isEmpty, reason: 'la file n’est pas passée');
      expect(await statut(d.id), StatutRecu.enAttente);
    });

    test(
      'un 401 au dépôt est consigné comme celui de la file : jeton refusé',
      () async {
        final d = await saisir();
        fichiers.repondre = (r) => const ReponseHttp(statut: 401, corps: null);
        final bilan = await gestionnaire(
          FauxTransport((r) => reponseLot(r)),
        ).synchroniserMaintenant();
        expect(bilan.etat, EtatSynchronisation.jetonRefuse);
        expect(bilan.codeHttp, 401);
        expect((await b.fichier())['appairage_refuse'], isNotNull);
        expect(await statut(d.id), StatutRecu.enAttente);
      },
    );

    test('un 409 « génération périmée » au dépôt est consigné : serveur '
        'réinitialisé, plus aucune requête ensuite', () async {
      await saisir();
      fichiers.repondre = (r) => const ReponseHttp(
        statut: 409,
        corps: {
          'code': 'generation_perimee',
          'reinitialisee_le': '2026-10-20T08:00:00+00:00',
        },
      );
      final bilan = await gestionnaire(
        FauxTransport((r) => reponseLot(r)),
      ).synchroniserMaintenant();
      expect(bilan.etat, EtatSynchronisation.serveurReinitialise);
      expect(
        await DescenteCatalogueDao(b.db).reinitialisationServeur(),
        isNotNull,
      );
    });
  });

  group('le téléchargement à la demande', () {
    final sha = RecusDepensesLocaux.empreinte(octetsPng());

    Future<String> depenseDuServeur({
      String? empreinte,
      bool avecRecu = true,
    }) async {
      final d = await saisir(avecRecu: false);
      if (avecRecu) {
        await dao.retenirReferenceRecu(
          d.id,
          sha256: empreinte ?? sha,
          taille: octetsPng().length,
          type: 'image/png',
        );
      }
      return d.id;
    }

    TelechargementRecuDepense service({
      bool demonstration = false,
      String? url = BancSync.urlServeur,
    }) => TelechargementRecuDepense(
      db: b.db,
      transport: fichiers,
      recus: recus,
      urlServeur: url,
      demonstration: demonstration,
      lecteur: b.lecteur,
    );

    ReponseHttp fichier(List<int> octets, {String? entete}) => ReponseHttp(
      statut: 200,
      corps: null,
      octets: octets,
      entetes: {'x-recu-sha256': ?entete},
    );

    test('le fichier vient AU CLIC : une requête, vérifié, rangé — et il ne '
        'se retélécharge plus', () async {
      final id = await depenseDuServeur();
      fichiers.repondre = (r) => fichier(octetsPng(), entete: sha);

      final issue = await service().obtenir(id);
      expect(issue, isA<RecuDisponible>());
      expect((issue as RecuDisponible).octets, octetsPng());
      final requete = fichiers.requetes.single;
      expect(requete.methode, 'GET');
      expect(requete.chemin, '/api/v1/sync/depenses/$id/recu');
      expect(requete.url.queryParameters['poste_id'], BancSync.poste);
      expect(requete.jeton, BancSync.jeton);

      final recu = (await dao.parId(id))!.recu!;
      expect(recu.nom, '$id.png');
      expect(recu.statut, StatutRecu.duServeur);
      expect(
        File('${b.dossier.path}/recus_depenses/$id.png').existsSync(),
        isTrue,
      );

      final encore = await service().obtenir(id);
      expect(encore, isA<RecuDisponible>());
      expect(fichiers.requetes.length, 1, reason: 'déjà sur le poste');
    });

    test('le fichier reçu ne correspond pas à la référence : refusé, RIEN '
        'n’est conservé', () async {
      final id = await depenseDuServeur(empreinte: 'f' * 64);
      fichiers.repondre = (r) => fichier(octetsPng());
      final issue = await service().obtenir(id);
      expect(issue, isA<RecuIndisponible>());
      expect((issue as RecuIndisponible).phrase, TextesRecuDistant.empreinte);
      expect((await dao.parId(id))!.recu!.nom, isNull);
      expect(
        Directory('${b.dossier.path}/recus_depenses').existsSync(),
        isFalse,
      );
    });

    test('l’en-tête d’empreinte du serveur ment : refusé', () async {
      final id = await depenseDuServeur();
      fichiers.repondre = (r) => fichier(octetsPng(), entete: 'e' * 64);
      expect(
        ((await service().obtenir(id)) as RecuIndisponible).phrase,
        TextesRecuDistant.empreinte,
      );
    });

    test(
      'ce qui vient n’est pas une image : refusé, rien n’est conservé',
      () async {
        final id = await depenseDuServeur(empreinte: null.toString());
        fichiers.repondre = (r) => fichier('pas une image'.codeUnits);
        expect(
          ((await service().obtenir(id)) as RecuIndisponible).phrase,
          TextesRecuDistant.illisible,
        );
        expect((await dao.parId(id))!.recu!.nom, isNull);
      },
    );

    test('un reçu web d’avant les empreintes (référence sans empreinte) se '
        'télécharge, et l’empreinte observée complète la ligne', () async {
      final d = await saisir(avecRecu: false);
      await dao.retenirReferenceRecu(
        d.id,
        sha256: null,
        taille: null,
        type: null,
      );
      fichiers.repondre = (r) => fichier(octetsPng());
      expect(await service().obtenir(d.id), isA<RecuDisponible>());
      final recu = (await dao.parId(d.id))!.recu!;
      expect(recu.sha256, sha);
      expect(recu.taille, octetsPng().length);
      expect(recu.type, 'image/png');
    });

    test('un fichier démesuré n’est pas pris', () async {
      final id = await depenseDuServeur();
      fichiers.repondre = (r) =>
          fichier(complete(octetsPng(), 6 * 1024 * 1024));
      expect(
        ((await service().obtenir(id)) as RecuIndisponible).phrase,
        TextesRecuDistant.tropLourd,
      );
    });

    test(
      'INTERRUPTEUR éteint : AUCUNE requête, et la phrase DIT pourquoi',
      () async {
        final id = await depenseDuServeur();
        await b.ecrivain.enregistrerSynchronisationActivee(
          false,
          par: 'gerant',
          le: jour,
        );
        fichiers.repondre = (r) => throw StateError('FICHIER : ${r.url}');
        expect(
          ((await service().obtenir(id)) as RecuIndisponible).phrase,
          TextesRecuDistant.desactivee,
        );
        expect(fichiers.requetes, isEmpty);
      },
    );

    test('démonstration, non appairé, jeton refusé, autre serveur : une '
        'phrase, aucune requête', () async {
      final id = await depenseDuServeur();
      fichiers.repondre = (r) => throw StateError('FICHIER : ${r.url}');

      expect(
        ((await service(demonstration: true).obtenir(id)) as RecuIndisponible)
            .phrase,
        TextesRecuDistant.demonstration,
      );
      expect(
        ((await service(url: 'https://autre.serveur/api/v1').obtenir(id))
                as RecuIndisponible)
            .phrase,
        TextesRecuDistant.autreServeur,
      );
      await b.ecrivain.consignerRefus(401, jour);
      expect(
        ((await service().obtenir(id)) as RecuIndisponible).phrase,
        TextesRecuDistant.refuse,
      );
      final neuf = await BancSync.creer(appaire: false);
      addTearDown(neuf.fermer);
      expect(
        ((await TelechargementRecuDepense(
                  db: b.db,
                  transport: fichiers,
                  recus: recus,
                  urlServeur: BancSync.urlServeur,
                  demonstration: false,
                  lecteur: neuf.lecteur,
                ).obtenir(id))
                as RecuIndisponible)
            .phrase,
        TextesRecuDistant.nonAppaire,
      );
      expect(fichiers.requetes, isEmpty);
    });

    for (final (reponse, phrase) in <(IssueHttp, String)>[
      (const ServeurInjoignable('réseau'), TextesRecuDistant.injoignable),
      (
        const ReponseHttp(statut: 503, corps: null),
        TextesRecuDistant.injoignable,
      ),
      (
        const ReponseHttp(statut: 404, corps: null),
        TextesRecuDistant.introuvable,
      ),
      (const ReponseHttp(statut: 403, corps: null), TextesRecuDistant.droit),
      (const ReponseHttp(statut: 401, corps: null), TextesRecuDistant.refuse),
      (
        const ReponseHttp(statut: 409, corps: null),
        TextesRecuDistant.reinitialise,
      ),
    ]) {
      test('réponse ${reponse is ReponseHttp ? reponse.statut : 'aucune'} : '
          'la phrase est « $phrase »', () async {
        final id = await depenseDuServeur();
        fichiers.repondre = (r) => reponse;
        expect(
          ((await service().obtenir(id)) as RecuIndisponible).phrase,
          phrase,
        );
        expect((await dao.parId(id))!.recu!.nom, isNull);
      });
    }

    test('une dépense sans reçu n’a rien à télécharger', () async {
      final id = await depenseDuServeur(avecRecu: false);
      expect(
        ((await service().obtenir(id)) as RecuIndisponible).phrase,
        TextesRecuDistant.inconnue,
      );
      expect(fichiers.requetes, isEmpty);
    });
  });

  group('la descente', () {
    Future<BilanDescente> descendre(List<Map<String, Object?>> elements) async {
      await DescenteCatalogueDao(b.db).effacerCurseur();
      return b
          .descente(
            FauxTransport(
              (r) => r.methode == 'GET'
                  ? FauxCatalogue(elements).repondre(r)
                  : reponseLot(r),
            ),
          )
          .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
    }

    Map<String, Object?> docDepense(String id, Object? recu) => {
      ...element('depenses', id, {
        'numero': 'DEP-1',
        'date_transaction': '2026-10-15',
        'tresorerie': 'caisse',
        'montant_total': '12500.00',
        'libelle': 'Marché du matin',
        'lignes': [
          {
            'libelle': 'Tomates',
            'compte_charge': '6011',
            'nature': 'Tomate',
            'famille': 'Marché',
            'montant': '12500.00',
          },
        ],
        'recu': recu,
      }),
      'poste_origine': 'POSTE-A',
    };

    final sha = RecusDepensesLocaux.empreinte(octetsPng());
    Object referencePng() => {
      'sha256': sha,
      'taille': octetsPng().length,
      'type': 'image/png',
    };

    test('la dépense d’un autre poste arrive avec la RÉFÉRENCE de son reçu — '
        'jamais le fichier', () async {
      await b.semerAuteur();
      await descendre([docDepense('dep-1', referencePng())]);
      final recu = (await DepenseDao(b.db).parId('dep-1'))!.recu!;
      expect(recu.statut, StatutRecu.duServeur);
      expect(recu.sha256, sha);
      expect(recu.taille, octetsPng().length);
      expect(recu.nom, isNull);
      expect(
        Directory('${b.dossier.path}/recus_depenses').existsSync(),
        isFalse,
        reason: 'jamais en masse',
      );
    });

    test('sans reçu au serveur : « sans reçu »', () async {
      await b.semerAuteur();
      await descendre([docDepense('dep-1', null)]);
      expect((await DepenseDao(b.db).parId('dep-1'))!.recu, isNull);
    });

    test('un reçu web d’avant les empreintes : référence à trois `null`, '
        'toujours « du serveur »', () async {
      await b.semerAuteur();
      await descendre([
        docDepense('dep-1', {'sha256': null, 'taille': null, 'type': null}),
      ]);
      final recu = (await DepenseDao(b.db).parId('dep-1'))!.recu!;
      expect(recu.statut, StatutRecu.duServeur);
      expect(recu.sha256, isNull);
    });

    test(
      'la dépense de CE poste redescend : la référence de la MÊME '
      'empreinte vaut accusé (réponse du dépôt perdue) — « envoyé »',
      () async {
        await b.semerAuteur();
        final d = await saisir();
        expect(await statut(d.id), StatutRecu.enAttente);
        // La dépense est acceptée (sans quoi l'aligneur CONSERVE la ligne
        // locale tant qu'une opération l'attend) ; seul le reçu a perdu sa
        // réponse.
        await accuserCreation(d.id);
        final bilan = await descendre([docDepense(d.id, referencePng())]);
        expect(bilan.refuses, 0, reason: bilan.motifsRefus.join(' ; '));
        expect(bilan.conservesLocalement, 0);
        expect(await statut(d.id), StatutRecu.envoye);
      },
    );

    test('la dépense de CE poste redescend SANS reçu : le reçu reste « en '
        'attente » (rien n’a été accusé)', () async {
      await b.semerAuteur();
      final d = await saisir();
      await accuserCreation(d.id);
      await descendre([docDepense(d.id, null)]);
      expect(await statut(d.id), StatutRecu.enAttente);
    });

    test(
      'une dépense déjà détenue n’est jamais réécrite, hors la référence',
      () async {
        await b.semerAuteur();
        final d = await saisir(avecRecu: false);
        await accuserCreation(d.id);
        final avant = (await dao.parId(d.id))!;
        await descendre([docDepense(d.id, referencePng())]);
        final apres = (await dao.parId(d.id))!;
        expect(apres.libelle, avant.libelle);
        expect(apres.montantTotal, avant.montantTotal);
        expect(apres.recu!.statut, StatutRecu.duServeur);
        expect(apres.recueDuServeur, isFalse, reason: 'l’origine ne bouge pas');
      },
    );
  });
}
