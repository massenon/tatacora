import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/article_vendable.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';
import 'package:tatacora_flutter/features/pos/domain/mention_client.dart';
import 'package:tatacora_flutter/features/pos/domain/repositories/panier_repository.dart';
import 'package:tatacora_flutter/features/pos/presentation/widgets/vue_panier.dart'
    show ChampClientComptant;
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/ventes/domain/entities/vente.dart';
import 'package:tatacora_flutter/features/ventes/impression/ticket_vente.dart';

import '../facturation/support/outils_encaissement.dart' show ouvrirCaissePour;
import 'support/outils_ventes.dart';

/// La MENTION client du comptoir (« Client (facultatif) — Nom à imprimer sur le
/// ticket »), du panier à la file d'envoi : saisie posée sur le panier par son
/// écrivain unique, conservée à la clôture, imprimée sur le ticket, portée par
/// la charge de la vente. Le POSTE n'a besoin d'aucun serveur : rien ici ne
/// touche le réseau. La confrontation au VRAI PHP est dans
/// `mention_client_contre_serveur_test.dart` (la règle) et
/// `charges_contre_serveur_test.dart` (la vente rangée).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late PanierDao dao;

  const biere = ArticleVendable(
    reference: ReferenceCatalogue(module: ModuleVendable.m5Bar, code: 'bsn-33'),
    libelle: 'Béninoise 33cl',
    prix: 1000,
  );

  setUp(() async {
    db = AppDatabase.enMemoire();
    await avecComptabilite(db);
    dao = panierDaoSur(db);
    await db
        .into(db.cartesBoissonLocal)
        .insert(
          CartesBoissonLocalCompanion.insert(
            id: 'bsn-33',
            articleId: 'art-bsn',
            libelle: 'Béninoise 33cl',
            categorie: 'locale',
            prixVente: 1000,
          ),
        );
    await ouvrirCaissePour(db, horloge: jourDeVente);
  });

  tearDown(() => db.close());

  Future<Panier> garni({String point = 'Comptoir'}) async {
    var p = await dao.ouvrir(typeVente: TypeVente.comptant, pointVente: point);
    p = await dao.ajouterLigne(p.id, biere, quantite: 2);
    return p;
  }

  Future<Map<String, Object?>> chargeDeLaVente() async {
    final o = (await OperationsSyncDao(
      db,
    ).operations()).singleWhere((o) => o.table == TableSynchronisee.ventes);
    return jsonDecode(o.payload) as Map<String, Object?>;
  }

  /// Les textes lisibles d'un PDF dont les flux sont compressés : chaque flux
  /// est décompressé, puis les chaînes `( … ) Tj` sont relues.
  String texteDuPdf(Uint8List octets) {
    final brut = latin1.decode(octets);
    final sortie = StringBuffer();
    var depart = 0;
    while (true) {
      final debut = brut.indexOf('stream', depart);
      if (debut < 0) break;
      var premier = debut + 'stream'.length;
      if (brut.codeUnitAt(premier) == 13) premier++;
      if (brut.codeUnitAt(premier) == 10) premier++;
      final fin = brut.indexOf('endstream', premier);
      if (fin < 0) break;
      depart = fin + 'endstream'.length;
      try {
        final plat = latin1.decode(
          ZLibDecoder().convert(octets.sublist(premier, fin)),
        );
        // Chaque mot est un `[(mot)]TJ` : la ligne se relit mots joints.
        sortie.writeln(
          RegExp(
            r'\[\((.*?)\)\]TJ',
          ).allMatches(plat).map((m) => m[1]).join(' '),
        );
      } on Object {
        // Un flux qui n'est pas du texte (image, police) : sans intérêt.
      }
    }
    return sortie.toString();
  }

  group('le champ du panier', () {
    Panier panierDe(String id, String? nom) => Panier(
      id: id,
      typeVente: TypeVente.comptant,
      statut: StatutPanier.ouvert,
      ouvertLe: DateTime(2026, 10, 12),
      lignes: const [],
      clientNom: nom,
    );

    Widget monter(Panier p) => ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: ChampClientComptant(panier: p)),
      ),
    );

    testWidgets('un AUTRE panier repart du champ de CE panier, jamais du '
        'texte du précédent', (tester) async {
      await tester.pumpWidget(monter(panierDe('a', 'Jean')));
      final champ = find.byKey(const Key('pos-client-mention'));
      expect(tester.widget<TextField>(champ).controller!.text, 'Jean');

      await tester.pumpWidget(monter(panierDe('b', null)));
      expect(tester.widget<TextField>(champ).controller!.text, isEmpty);

      await tester.pumpWidget(monter(panierDe('c', 'Awa')));
      expect(tester.widget<TextField>(champ).controller!.text, 'Awa');
    });

    testWidgets('la saisie est bornée à 255 caractères dans le champ même', (
      tester,
    ) async {
      await tester.pumpWidget(monter(panierDe('a', null)));
      final champ = find.byKey(const Key('pos-client-mention'));
      await tester.enterText(champ, 'N' * 400);
      expect(
        tester.widget<TextField>(champ).controller!.text.length,
        MentionClient.longueurMax,
      );
    });
  });

  group('la règle (réplique de VenteService::normaliserMentionClient)', () {
    test('rognée, sans contrôle, bornée, vide = aucune', () {
      expect(MentionClient.normaliser(null), isNull);
      expect(MentionClient.normaliser(''), isNull);
      expect(MentionClient.normaliser('   '), isNull);
      expect(MentionClient.normaliser('  Jean  '), 'Jean');
      expect(MentionClient.normaliser('A\nB\tC\u0000D'), 'A B C D');
      expect(MentionClient.normaliser('\u0007  Nom  \u0008'), 'Nom');
      expect(MentionClient.normaliser('x' * 300), 'x' * 255);
      expect(MentionClient.normaliser('😀' * 300)!.runes.length, 255);
    });
  });

  group('au panier (écrivain unique : PanierDao)', () {
    test('la saisie est posée sur le panier ouvert, normalisée', () async {
      final p = await garni();
      final apres = await dao.definirMentionClient(
        p.id,
        '  Mme Aïssatou N’DOUR\n',
      );
      expect(apres.clientNom, 'Mme Aïssatou N’DOUR');
      expect((await dao.parId(p.id))!.clientNom, 'Mme Aïssatou N’DOUR');
      // Rien n'est mis en file par la mention : elle part avec la VENTE, à la
      // clôture (aucune opération de vente avant elle).
      expect(
        (await OperationsSyncDao(
          db,
        ).operations()).where((o) => o.table == TableSynchronisee.ventes),
        isEmpty,
      );
    });

    test(
      'effacer le champ retire la mention (null, jamais une chaîne vide)',
      () async {
        final p = await garni();
        await dao.definirMentionClient(p.id, 'Jean');
        final apres = await dao.definirMentionClient(p.id, '   ');
        expect(apres.clientNom, isNull);
      },
    );

    test(
      'un panier de SÉJOUR est refusé : son nom est celui de la réservation',
      () async {
        await db
            .into(db.clientsLocal)
            .insert(
              ClientsLocalCompanion.insert(
                id: 'cli-1',
                nom: 'KORA',
                telephone: '+229 01 00 00 00 01',
                typeClient: 'particulier',
              ),
            );
        await db
            .into(db.categoriesHebergementLocal)
            .insert(
              CategoriesHebergementLocalCompanion.insert(
                id: 'cat-1',
                libelle: 'Bungalow',
                capaciteMax: 2,
                tarifBase: 28000,
              ),
            );
        await db
            .into(db.unitesHebergementLocal)
            .insert(
              UnitesHebergementLocalCompanion.insert(
                id: 'u-1',
                categorieId: 'cat-1',
                numero: 'BNG-01',
                statut: 'libre',
              ),
            );
        await db
            .into(db.reservationsLocal)
            .insert(
              ReservationsLocalCompanion.insert(
                id: 'res-1',
                reference: 'LOC-RES1',
                clientId: 'cli-1',
                uniteId: 'u-1',
                dateArrivee: DateTime(2026, 10, 9),
                dateDepart: DateTime(2026, 10, 12),
                statut: 'confirmee',
                tarifNuit: 28000,
              ),
            );
        final sejour = await dao.ouvrir(
          typeVente: TypeVente.surSejour,
          reservationId: 'res-1',
          clientNom: 'KORA',
          dateDepartPrevue: DateTime(2026, 10, 20),
        );
        await expectLater(
          dao.definirMentionClient(sejour.id, 'Autre nom'),
          throwsArgumentError,
        );
        expect((await dao.parId(sejour.id))!.clientNom, 'KORA');
      },
    );

    test('un panier clôturé ne change plus : la mention est figée', () async {
      final p = await garni();
      await dao.definirMentionClient(p.id, 'Jean');
      await dao.cloturer(
        p.id,
        modePaiement: 'especes',
        auteurId: caissierDeVente,
      );
      await expectLater(
        dao.definirMentionClient(p.id, 'Autre'),
        throwsA(isA<PanierNonModifiable>()),
      );
      expect((await dao.parId(p.id))!.clientNom, 'Jean');
    });
  });

  group('à la clôture : vente, ticket, file d’envoi', () {
    test(
      'la mention suit la vente : charge, ticket (texte ET octets du PDF)',
      () async {
        final p = await garni();
        await dao.definirMentionClient(p.id, 'Mme Aïssatou NDOUR');
        final cloture = await dao.cloturer(
          p.id,
          modePaiement: 'especes',
          auteurId: caissierDeVente,
        );

        // 1. La charge de synchronisation de la vente.
        expect((await chargeDeLaVente())['client_nom'], 'Mme Aïssatou NDOUR');

        // 2. La vente du journal.
        final vente = Vente.depuisPanier(cloture)!;
        expect(vente.clientNom, 'Mme Aïssatou NDOUR');

        // 3. Le ticket 80 mm : la ligne « Client : … », dans le texte composé…
        final ticket = TicketVente.composer(vente);
        expect(ticket.texteBrut, contains('Client : Mme Aïssatou NDOUR'));

        // 4. … ET dans les octets du PDF réellement produit. Les polices
        // intégrées sont Latin-1 : « ï » survit, c'est ce que le papier garde.
        final octets = await ticket.pdf();
        expect(String.fromCharCodes(octets.take(4)), '%PDF');
        final lisible = texteDuPdf(octets);
        expect(
          lisible,
          contains('Client : Mme Aïssatou NDOUR'),
          reason: 'le PDF doit porter la ligne Client',
        );
      },
    );

    test(
      'sans mention : ni ligne « Client », ni client_nom dans la charge',
      () async {
        final p = await garni();
        final cloture = await dao.cloturer(
          p.id,
          modePaiement: 'especes',
          auteurId: caissierDeVente,
        );
        expect((await chargeDeLaVente())['client_nom'], isNull);
        final ticket = TicketVente.composer(Vente.depuisPanier(cloture)!);
        expect(ticket.texteBrut, isNot(contains('Client :')));
        expect(texteDuPdf(await ticket.pdf()), isNot(contains('Client :')));
      },
    );

    test('le ticket ne porte jamais de caractère de contrôle', () async {
      final p = await garni();
      await dao.definirMentionClient(p.id, 'Jean\nDupont\u0000\u001B\tX');
      final cloture = await dao.cloturer(
        p.id,
        modePaiement: 'especes',
        auteurId: caissierDeVente,
      );
      final ticket = TicketVente.composer(Vente.depuisPanier(cloture)!);
      final controle = RegExp(r'[\u0000-\u001F\u007F-\u009F]');
      for (final t in ticket.textes) {
        expect(controle.hasMatch(t), isFalse, reason: 'texte « $t »');
      }
      expect(ticket.texteBrut, contains('Client : Jean Dupont'));
    });

    test(
      'un nom très long est borné à 255 caractères, avec la vente',
      () async {
        final p = await garni();
        await dao.definirMentionClient(p.id, 'N' * 400);
        await dao.cloturer(
          p.id,
          modePaiement: 'especes',
          auteurId: caissierDeVente,
        );
        expect(
          ((await chargeDeLaVente())['client_nom'] as String).length,
          MentionClient.longueurMax,
        );
      },
    );

    test(
      'un panier ABANDONNÉ emporte sa mention : aucune vente, aucune charge',
      () async {
        final p = await garni();
        await dao.definirMentionClient(p.id, 'Jean');
        await dao.abandonner(p.id);
        expect(
          (await OperationsSyncDao(
            db,
          ).operations()).where((o) => o.table == TableSynchronisee.ventes),
          isEmpty,
        );
        expect((await dao.parId(p.id))!.statut, StatutPanier.annule);
      },
    );

    test(
      'le client suivant n’hérite de rien : son panier naît sans mention',
      () async {
        final premier = await garni();
        await dao.definirMentionClient(premier.id, 'Jean');
        await dao.cloturer(
          premier.id,
          modePaiement: 'especes',
          auteurId: caissierDeVente,
        );
        final suivant = await garni(point: 'Bar');
        expect(suivant.clientNom, isNull);
        await dao.definirMentionClient(suivant.id, 'Awa');
        expect((await dao.parId(premier.id))!.clientNom, 'Jean');
        expect((await dao.parId(suivant.id))!.clientNom, 'Awa');
      },
    );
  });
}
