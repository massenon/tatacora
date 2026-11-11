import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/caisse/data/sessions_caisse_dao.dart';
import 'package:tatacora_flutter/features/caisse/domain/entities/session_caisse.dart';
import 'package:tatacora_flutter/features/facturation/domain/usecases/facturer.dart';
import 'package:tatacora_flutter/features/facturation/data/facture_dao.dart';
import 'package:tatacora_flutter/features/facturation/data/facture_repository_local.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/fiche_reservation.dart'
    show TypeRemise;
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/article_vendable.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';
import 'package:tatacora_flutter/features/pos/domain/messages_ventes.dart';
import 'package:tatacora_flutter/features/pos/domain/remise_panier.dart';
import 'package:tatacora_flutter/features/pos/domain/repositories/panier_repository.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/ventes/domain/entities/vente.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import 'support/outils_ventes.dart';

/// La REMISE du panier (21/10/2026, v35) — la formule, son stockage, le net
/// encaissé, la vente qui part avec. La confrontation au VRAI serveur (net,
/// centimes, pièce, phrases) est dans `ventes_contre_serveur_test.dart` ; ici
/// la mécanique du poste.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('la formule (réplique de Panier::remiseSur)', () {
    test(
      'pourcentage tronqué à deux décimales, montant tel quel, aucune = 0',
      () {
        int r(int total, TypeRemise t, int v) => montantRemiseCentimes(
          totalFrancs: total,
          type: t,
          valeurCentiemes: v,
        );
        expect(r(3000, TypeRemise.pourcentage, 1000), 30000);
        // 12,5 % de 4 333 F = 541,625 → 541,62 (bcmath tronque).
        expect(r(4333, TypeRemise.pourcentage, 1250), 54162);
        expect(r(1005, TypeRemise.pourcentage, 1250), 12562);
        expect(r(5000, TypeRemise.montant, 50000), 50000);
        expect(r(5000, TypeRemise.aucune, 99999), 0);
        expect(r(5000, TypeRemise.pourcentage, 10000), 500000);
        expect(r(5000, TypeRemise.montant, 500000), 500000);
      },
    );

    test('les bornes refusent avec la phrase du serveur', () {
      void refuse(int total, TypeRemise t, int v, String phrase) => expect(
        () => montantRemiseCentimes(
          totalFrancs: total,
          type: t,
          valeurCentiemes: v,
        ),
        throwsA(isA<RefusVente>().having((e) => e.message, 'message', phrase)),
      );
      refuse(
        1000,
        TypeRemise.pourcentage,
        10001,
        MessagesVentes.remisePourcentageHorsBornes,
      );
      refuse(
        1000,
        TypeRemise.montant,
        100001,
        MessagesVentes.remiseSuperieureAuTotal,
      );
      refuse(1000, TypeRemise.montant, -1, MessagesVentes.remiseValeurInvalide);
    });

    test('la saisie : deux décimales, virgule admise, le reste illisible', () {
      expect(centiemesDepuisSaisie('10'), 1000);
      expect(centiemesDepuisSaisie(' 12,5 '), 1250);
      expect(centiemesDepuisSaisie('12.05'), 1205);
      expect(centiemesDepuisSaisie('-5'), -500);
      expect(centiemesDepuisSaisie('abc'), isNull);
      expect(centiemesDepuisSaisie(''), isNull);
      expect(centiemesDepuisSaisie('1.234'), isNull);
    });

    test(
      'ventilerAuNet : prorata tronqué, le DERNIER module prend l’écart',
      () {
        expect(ventilerAuNet({'M4': 500000, 'M5': 300000}, 720000), {
          'M4': 450000,
          'M5': 270000,
        });
        final v = ventilerAuNet({'M4': 33300, 'M5': 66700, 'M8': 1}, 90001);
        expect(v.values.fold<int>(0, (t, x) => t + x), 90001);
        // Sans remise, rien ne change.
        expect(ventilerAuNet({'M4': 100}, 100), {'M4': 100});
      },
    );
  });

  group('le panier et sa clôture', () {
    late AppDatabase db;
    late PanierDao dao;
    final h = jourDeVente;

    setUp(() async {
      db = AppDatabase.enMemoire();
      await avecComptabilite(db, maintenant: h);
      dao = panierDaoSur(db, horloge: h);
      await SessionsCaisseDao(db, maintenant: () => h).ouvrir(
        point: PointDeVenteCaisse.bar,
        fondSaisi: '10000',
        auteurId: auteurEssai,
        peutEcrire: true,
      );
      await db
          .into(db.cartesBoissonLocal)
          .insert(
            CartesBoissonLocalCompanion.insert(
              id: 'b-1',
              articleId: '',
              libelle: 'Bière',
              categorie: 'locale',
              prixVente: 1000,
            ),
          );
    });
    tearDown(() => db.close());

    final biere = ArticleVendable(
      reference: ReferenceCatalogue(module: ModuleVendable.m5Bar, code: 'b-1'),
      libelle: 'Bière',
      prix: 1000,
    );

    Future<Panier> ouvert(int quantite) async {
      final p = await dao.ouvrir(
        typeVente: TypeVente.comptant,
        pointVente: 'Bar',
      );
      return dao.ajouterLigne(p.id, biere, quantite: quantite);
    }

    test('appliquerRemise stocke le TYPE et la VALEUR, jamais un montant : '
        'le net suit les lignes', () async {
      var p = await ouvert(3);
      p = await dao.appliquerRemise(p.id, TypeRemise.pourcentage, '10');
      expect(p.remiseType, TypeRemise.pourcentage);
      expect(p.remiseValeurCentiemes, 1000);
      expect((p.total, p.remiseFrancs, p.net), (3000, 300, 2700));
      // Un article de plus : la remise suit (10 % de 4 000).
      p = await dao.ajouterLigne(p.id, biere);
      expect((p.total, p.remiseFrancs, p.net), (4000, 400, 3600));
      // « Aucune » ramène la valeur à zéro.
      p = await dao.appliquerRemise(p.id, TypeRemise.aucune, '999');
      expect((p.remiseValeurCentiemes, p.net), (0, 4000));
    });

    test('un refus n’écrit rien ; un panier clôturé ne reçoit plus de '
        'remise', () async {
      var p = await ouvert(1);
      p = await dao.appliquerRemise(p.id, TypeRemise.montant, '300');
      await expectLater(
        dao.appliquerRemise(p.id, TypeRemise.pourcentage, '150'),
        throwsA(isA<RefusVente>()),
      );
      await expectLater(
        dao.appliquerRemise(p.id, TypeRemise.pourcentage, 'abc'),
        throwsA(isA<RefusVente>()),
      );
      p = (await dao.parId(p.id))!;
      expect(
        (p.remiseType, p.remiseValeurCentiemes),
        (TypeRemise.montant, 30000),
      );

      await dao.cloturer(p.id, modePaiement: 'especes', auteurId: auteurEssai);
      await expectLater(
        dao.appliquerRemise(p.id, TypeRemise.aucune, ''),
        throwsA(isA<PanierNonModifiable>()),
      );
    });

    test('la clôture fige le NET, enfile la vente avec type et valeur, et '
        'la vente relit sa remise', () async {
      var p = await ouvert(3);
      p = await dao.appliquerRemise(p.id, TypeRemise.pourcentage, '10');
      final cloture = await dao.cloturer(
        p.id,
        modePaiement: 'especes',
        auteurId: auteurEssai,
      );
      expect(cloture.montantCloture, 2700);

      final ops = await OperationsSyncDao(
        db,
      ).operations(table: TableSynchronisee.ventes);
      final charge = jsonDecode(ops.single.payload) as Map<String, dynamic>;
      expect(charge['montant_cloture'], 2700);
      expect(charge['remise_type'], 'pourcentage');
      expect(charge['remise_valeur'], '10.00');

      final vente = Vente.depuisPanier(cloture)!;
      expect((vente.montant, vente.remiseDeduite), (2700, 300));
    });

    test('sans remise, le document d’avant est inchangé (aucune clé de '
        'remise)', () async {
      final p = await ouvert(2);
      await dao.cloturer(p.id, modePaiement: 'especes', auteurId: auteurEssai);
      final ops = await OperationsSyncDao(
        db,
      ).operations(table: TableSynchronisee.ventes);
      final charge = jsonDecode(ops.single.payload) as Map<String, dynamic>;
      expect(charge.containsKey('remise_type'), isFalse);
      expect(charge['montant_cloture'], 2000);
    });

    test('une remise en francs devenue SUPÉRIEURE au total (ligne retirée '
        'après coup) fait refuser l’encaissement, sans rien écrire', () async {
      var p = await ouvert(3);
      p = await dao.appliquerRemise(p.id, TypeRemise.montant, '2500');
      p = await dao.modifierQuantite(p.id, p.lignes.single.id, 1);
      expect(
        p.remiseCentimes,
        0,
        reason: 'l’affichage tolère (remisePourAffichage)',
      );
      await expectLater(
        dao.cloturer(p.id, modePaiement: 'especes', auteurId: auteurEssai),
        throwsA(
          isA<RefusVente>().having(
            (e) => e.message,
            'message',
            MessagesVentes.remiseSuperieureAuTotal,
          ),
        ),
      );
      expect((await dao.parId(p.id))!.statut, StatutPanier.ouvert);
    });

    test('la facture du comptoir porte des lignes NÉGATIVES de remise, une par '
        'module : son total égale le net', () async {
      var p = await ouvert(3);
      p = await dao.appliquerRemise(p.id, TypeRemise.pourcentage, '10');
      final cloture = await dao.cloturer(
        p.id,
        modePaiement: 'especes',
        auteurId: auteurEssai,
      );
      final facturer = Facturer(
        FactureRepositoryLocal(FactureDao(db, maintenant: () => h)),
      );
      final piece = await facturer.emettreAuComptant(cloture);
      final remises = piece.lignes.where((l) => l.prixUnitaire < 0).toList();
      expect(remises, hasLength(1));
      expect(remises.single.libelle, 'Remise sur consommations — Bar');
      expect(remises.single.prixUnitaire, -300);
      expect(
        piece.lignes.fold<int>(0, (t, l) => t + l.prixUnitaire * l.quantite),
        2700,
      );
    });
  });
}
