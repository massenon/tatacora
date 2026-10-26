import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/data/tables_pos_dao.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/article_vendable.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';
import 'package:tatacora_flutter/features/pos/domain/messages_ventes.dart';
import 'package:tatacora_flutter/features/pos/domain/repositories/panier_repository.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import '../synchronisation/support/faux_transport.dart' show BancSync;
import 'support/outils_ventes.dart';

/// « Vider » et « Abandonner » du panneau Panier du comptoir — le DAO, seul
/// écrivain des paniers.
///
/// Les gestes sont ceux de la vue du comptoir (`wire:click="viderPanier"` et
/// `"abandonnerPanier"`) et de `PanierService::vider` / `abandonner` :
/// « Vider » retire toutes les lignes et laisse le panier OUVERT ; « Abandonner »
/// ferme le panier SANS vente, SANS motif demandé, et garde ses lignes (le
/// registre se souvient qu'il a été ouvert puis quitté).
void main() {
  late BancSync b;
  late PanierDao dao;

  const biere = ArticleVendable(
    reference: ReferenceCatalogue(module: ModuleVendable.m5Bar, code: 'bsn-33'),
    libelle: 'Béninoise 33cl',
    prix: 1000,
    categorie: 'Bières',
  );

  setUp(() async {
    b = await BancSync.creer();
    await b.semerAuteur();
    await b.db
        .into(b.db.cartesBoissonLocal)
        .insert(
          CartesBoissonLocalCompanion.insert(
            id: 'bsn-33',
            articleId: 'art-bsn',
            libelle: 'Béninoise 33cl',
            categorie: 'locale',
            prixVente: 1000,
          ),
        );
    dao = panierDaoSur(b.db);
  });
  tearDown(() => b.fermer());

  Future<List<String>> file() async => [
    for (final o in await b.dao.operations())
      if (o.table == TableSynchronisee.paniers)
        '${o.type.code} ${jsonEncode(jsonDecode(o.payload))}',
  ];

  group('Les phrases viennent du SERVEUR (relues par PHP)', () {
    String phpLang(String fichier, String cle) {
      final r = Process.runSync('php', [
        '-r',
        'echo (require "../tatacora-api/lang/fr/$fichier.php")["$cle"];',
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      return '${r.stdout}';
    }

    test('panier clôturé : ventes.panier_cloture_immuable', () {
      expect(
        MessagesVentes.panierClotureImmuable,
        phpLang('ventes', 'panier_cloture_immuable'),
      );
    });

    test('Abandonner : pos_pwa.comptant.panier_abandonne', () {
      final r = Process.runSync('php', [
        '-r',
        'echo (require "../tatacora-api/lang/fr/pos_pwa.php")["comptant"]["panier_abandonne"];',
      ]);
      expect(MessagesVentes.panierAbandonne, '${r.stdout}');
      expect(r.stdout, isNotEmpty);
    });
  });

  group('Vider — toutes les lignes, le panier reste ouvert', () {
    test('retire toutes les lignes et ne ferme rien', () async {
      final p = await dao.ouvrir(
        typeVente: TypeVente.comptant,
        pointVente: 'Réception',
      );
      await dao.ajouterLigne(p.id, biere);
      await dao.ajouterLigne(p.id, biere, quantite: 3);

      final vide = await dao.vider(p.id);

      expect(vide.lignes, isEmpty);
      expect(vide.statut, StatutPanier.ouvert);
    });

    test('un panier déjà vide : sans effet, sans refus (la vue ne grise '
        'jamais le bouton)', () async {
      final p = await dao.ouvrir(
        typeVente: TypeVente.comptant,
        pointVente: 'Réception',
      );
      expect((await dao.vider(p.id)).lignes, isEmpty);
    });

    test('un panier clôturé REFUSE, à la phrase du serveur', () async {
      final p = await dao.ouvrir(
        typeVente: TypeVente.comptant,
        pointVente: 'Réception',
      );
      await dao.ajouterLigne(p.id, biere);
      await cloturerSansPiece(b.db, p.id, mode: 'especes');

      await expectLater(
        dao.vider(p.id),
        throwsA(
          isA<PanierNonModifiable>().having(
            (e) => e.toString(),
            'phrase',
            MessagesVentes.panierClotureImmuable,
          ),
        ),
      );
    });
  });

  group('Abandonner — ferme sans vente, sans motif saisi, lignes gardées', () {
    test('le panier est fermé sans vente, ses lignes sont CONSERVÉES', () async {
      final p = await dao.ouvrir(
        typeVente: TypeVente.comptant,
        pointVente: 'Réception',
      );
      await dao.ajouterLigne(p.id, biere);

      final ferme = await dao.abandonner(p.id);

      expect(ferme.estOuvert, isFalse);
      expect(ferme.statut, StatutPanier.annule);
      expect(ferme.motifAnnulation, MessagesVentes.motifAbandon);
      // Comme `PanierService::abandonner` : le registre garde ce qui avait été
      // saisi, `vente_id` reste vide.
      expect(ferme.lignes, hasLength(1));
      expect(ferme.montantCloture, isNull);
    });

    test(
      'il libère le séjour/la table : un nouveau panier peut s’ouvrir',
      () async {
        final r1 = (await TablesPosDao(
          b.db,
        ).toutes()).firstWhere((t) => t.libelle == 'R1').id;
        final p = await dao.ouvrir(
          typeVente: TypeVente.comptant,
          pointVente: 'Restaurant',
          tableId: r1,
          espace: 'restaurant',
        );
        await dao.abandonner(p.id);

        final neuf = await dao.ouvrir(
          typeVente: TypeVente.comptant,
          pointVente: 'Restaurant',
          tableId: r1,
          espace: 'restaurant',
        );
        expect(neuf.estOuvert, isTrue);
      },
    );

    test(
      'ENFILE la fermeture de la table quand le serveur détient le panier',
      () async {
        final r1 = (await TablesPosDao(
          b.db,
        ).toutes()).firstWhere((t) => t.libelle == 'R1').id;
        final p = await dao.ouvrir(
          typeVente: TypeVente.comptant,
          pointVente: 'Restaurant',
          tableId: r1,
          espace: 'restaurant',
        );
        await dao.abandonner(p.id);

        expect(await file(), [
          'creation {"point_vente":"Restaurant","table_id":"$r1"}',
          'modification {"statut":"cloture"}',
        ]);
      },
    );

    test('au comptoir (sans table) rien n’est enfilé', () async {
      final p = await dao.ouvrir(
        typeVente: TypeVente.comptant,
        pointVente: 'Réception',
      );
      await dao.abandonner(p.id);
      expect(await file(), isEmpty);
    });

    test(
      'un panier déjà fermé REFUSE (phrase du serveur) et n’écrit rien',
      () async {
        final p = await dao.ouvrir(
          typeVente: TypeVente.comptant,
          pointVente: 'Réception',
        );
        await dao.abandonner(p.id);

        await expectLater(
          dao.abandonner(p.id),
          throwsA(isA<PanierNonModifiable>()),
        );
        expect(
          (await dao.parId(p.id))!.motifAnnulation,
          MessagesVentes.motifAbandon,
        );
      },
    );
  });
}
