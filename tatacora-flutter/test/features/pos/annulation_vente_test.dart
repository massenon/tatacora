import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/article_vendable.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';
import 'package:tatacora_flutter/features/pos/domain/messages_ventes.dart';
import 'package:tatacora_flutter/features/pos/data/piece_de_la_vente.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import '../facturation/support/outils_encaissement.dart';
import 'support/outils_ventes.dart';

/// L'annulation d'une VENTE du poste (`pos/comptant`, « annuler » du journal du
/// jour) sur le chemin réel : `PanierDao.annulerVente` -> contre-passation de la
/// pièce `VTE` -> statut `annule` -> opération `ventes` / modification en file.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late PanierDao dao;
  late ComptabiliteDao compta;

  const biere = ArticleVendable(
    reference: ReferenceCatalogue(module: ModuleVendable.m5Bar, code: 'bsn-33'),
    libelle: 'Béninoise 33cl',
    prix: 1000,
  );

  setUp(() async {
    db = AppDatabase.enMemoire();
    await avecComptabilite(db);
    compta = ComptabiliteDao(db);
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
    await ouvrirCaissePour(db);
  });

  tearDown(() => db.close());

  Future<Panier> venteEncaissee() async {
    var p = await dao.ouvrir(
      typeVente: TypeVente.comptant,
      pointVente: 'Comptoir',
    );
    p = await dao.ajouterLigne(p.id, biere, quantite: 3);
    return dao.cloturer(
      p.id,
      modePaiement: 'especes',
      auteurId: caissierDeVente,
      anticipe: false,
    );
  }

  Future<int> ecritures() async => (await compta.toutesLesEcritures()).length;

  test('annuler contre-passe la pièce, fige le montant, garde le motif et '
      'enfile la modification', () async {
    final vente = await venteEncaissee();
    final avant = await ecritures();

    final annulee = await dao.annulerVente(
      vente.id,
      '  erreur de saisie ',
      auteurId: caissierDeVente,
    );

    expect(annulee.statut, StatutPanier.annule);
    expect(
      annulee.montantCloture,
      3000,
      reason: 'le montant encaissé reste dit',
    );
    expect(annulee.motifAnnulation, 'erreur de saisie');
    expect(await ecritures(), greaterThan(avant), reason: 'contre-pièce');
    // La pièce d'origine n'est JAMAIS supprimée (RG-11).
    expect(
      await compta.lignesParLibelle(libelleDeLaPiece(vente.id)),
      isNotEmpty,
    );

    final ops = await OperationsSyncDao(db).operations(entiteId: vente.id);
    expect(
      ops.where((o) => o.type == TypeOperationSync.modification),
      hasLength(1),
    );
  });

  test('refus dans l’ordre : motif vide, vente absente, panier ouvert, déjà '
      'annulée', () async {
    await expectLater(
      dao.annulerVente('x', '   ', auteurId: caissierDeVente),
      throwsA(
        isA<RefusVente>().having(
          (e) => e.message,
          'message',
          MessagesVentes.motifAnnulationObligatoire,
        ),
      ),
    );
    await expectLater(
      dao.annulerVente('inconnue', 'motif', auteurId: caissierDeVente),
      throwsA(
        isA<RefusVente>().having(
          (e) => e.message,
          'message',
          MessagesVentes.venteAbsente,
        ),
      ),
    );

    final ouvert = await dao.ouvrir(
      typeVente: TypeVente.comptant,
      pointVente: 'Comptoir',
    );
    await expectLater(
      dao.annulerVente(ouvert.id, 'motif', auteurId: caissierDeVente),
      throwsA(isA<RefusVente>()),
    );

    final vente = await venteEncaissee();
    await dao.annulerVente(vente.id, 'motif', auteurId: caissierDeVente);
    final avant = await ecritures();
    await expectLater(
      dao.annulerVente(vente.id, 'encore', auteurId: caissierDeVente),
      throwsA(isA<RefusVente>()),
    );
    expect(await ecritures(), avant, reason: 'une seule contre-pièce');
  });
}
