import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/caisse/data/sessions_caisse_dao.dart';
import 'package:tatacora_flutter/features/caisse/domain/entities/session_caisse.dart';
import 'package:tatacora_flutter/features/caisse/domain/especes_de_la_session.dart';
import 'package:tatacora_flutter/features/caisse/domain/messages_caisse.dart';
import 'package:tatacora_flutter/features/caisse/domain/regles_caisse.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/article_vendable.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';

import '../facturation/support/outils_encaissement.dart';
import 'support/outils_ventes.dart';

/// `ventes.session_id` à l'encaissement au comptant (D221 option a) : la session
/// ouverte du point `bar` est lue et écrite DANS la transaction de la clôture,
/// et SANS caisse l'encaissement est refusé (`PosComptant::encaissementReel`).
///
/// Le séjour n'est pas concerné : il se porte sur la note de chambre.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase base;
  late PanierDao dao;

  const biere = ArticleVendable(
    reference: ReferenceCatalogue(module: ModuleVendable.m5Bar, code: 'bsn-33'),
    libelle: 'Béninoise 33cl',
    prix: 1000,
  );

  Future<Panier> panierGarni(TypeVente type, {int quantite = 1}) async {
    final p = await dao.ouvrir(typeVente: type);
    await dao.ajouterLigne(p.id, biere, quantite: quantite);
    return p;
  }

  setUp(() async {
    base = AppDatabase.enMemoire();
    // Clôturer passe la pièce de la vente : référentiel comptable et auteur.
    await avecComptabilite(base);
    await base
        .into(base.cartesBoissonLocal)
        .insert(
          CartesBoissonLocalCompanion.insert(
            id: 'bsn-33',
            articleId: 'art-bsn',
            libelle: 'Béninoise 33cl',
            categorie: 'locale',
            prixVente: 1000,
          ),
        );
    dao = panierDaoSur(base);
  });

  tearDown(() => base.close());

  test('sans caisse ouverte : le serveur REFUSE, rien n’est clôturé', () async {
    final p = await panierGarni(TypeVente.comptant);

    await expectLater(
      dao.cloturer(p.id, modePaiement: 'especes', auteurId: caissierDeVente),
      throwsA(
        isA<RefusCaisse>().having(
          (RefusCaisse e) => e.message,
          'message',
          MessagesCaisse.refusSansCaisse,
        ),
      ),
    );

    final relu = (await dao.parId(p.id))!;
    expect(relu.statut, StatutPanier.ouvert);
    expect(relu.sessionEncaissementId, isNull);
  });

  test('la caisse d’un AUTRE point ne suffit pas', () async {
    await ouvrirCaissePour(base, point: PointDeVenteCaisse.reception);
    final p = await panierGarni(TypeVente.comptant);

    await expectLater(
      dao.cloturer(p.id, modePaiement: 'especes', auteurId: caissierDeVente),
      throwsA(isA<RefusCaisse>()),
    );
  });

  test('avec la caisse du bar : la session est écrite sur la vente', () async {
    final session = await ouvrirLaCaisseDuComptoir(base);
    final p = await panierGarni(TypeVente.comptant);

    final cloture = await dao.cloturer(
      p.id,
      modePaiement: 'mobile_money',
      auteurId: caissierDeVente,
    );

    expect(cloture.sessionEncaissementId, session.id);
    expect(
      (await dao.parId(p.id))!.sessionEncaissementId,
      session.id,
      reason: 'relue en base, pas seulement rendue par l’appel',
    );
  });

  test(
    'un panier de SÉJOUR n’exige aucune caisse et n’en porte aucune',
    () async {
      final c = await creerClient(base);
      await semerReservation(base, id: 'res-sej', clientId: c.id);
      final p = await dao.ouvrir(
        typeVente: TypeVente.surSejour,
        reservationId: 'res-sej',
      );
      await dao.ajouterLigne(p.id, biere);

      final cloture = await dao.cloturer(
        p.id,
        modePaiement: 'especes',
        auteurId: caissierDeVente,
      );

      expect(cloture.statut, StatutPanier.cloture);
      expect(cloture.sessionEncaissementId, isNull);
      // Le mode demandé (« espèces ») n'est PAS celui qui est écrit : un séjour
      // est TOUJOURS porté sur la note de chambre (`PosHeberges`).
      expect(cloture.modePaiement, 'note_chambre');
    },
  );

  test('les espèces de la session : espèces seulement, cette session seulement, '
      'clôturés seulement', () async {
    final s1 = await ouvrirLaCaisseDuComptoir(base);
    final a = await panierGarni(TypeVente.comptant, quantite: 3); // 3 000
    final b = await panierGarni(TypeVente.comptant, quantite: 2); // 2 000
    final c = await panierGarni(TypeVente.comptant, quantite: 5); // 5 000
    await panierGarni(
      TypeVente.comptant,
      quantite: 7,
    ); // ouvert : ne compte pas
    await dao.cloturer(
      a.id,
      modePaiement: 'especes',
      auteurId: caissierDeVente,
    );
    await dao.cloturer(
      b.id,
      modePaiement: 'mobile_money',
      auteurId: caissierDeVente,
    );
    await dao.cloturer(
      c.id,
      modePaiement: 'especes',
      auteurId: caissierDeVente,
    );

    // Une autre session, fermée puis rouverte : ses espèces ne sont pas les nôtres.
    await SessionsCaisseDao(base, maintenant: () => jourEncaissement).cloturer(
      point: pointDeCaisseDuComptoir,
      constateSaisi: '9000',
      peutEcrire: true,
      especesEncaisseesCentimes: 800000,
    );
    final s2 = await ouvrirCaissePour(base);
    final d = await panierGarni(TypeVente.comptant, quantite: 4); // 4 000
    await dao.cloturer(
      d.id,
      modePaiement: 'especes',
      auteurId: caissierDeVente,
    );

    final tous = await dao.paniers();
    expect(especesEncaisseesCentimes(tous, s1.id), 800000);
    expect(especesEncaisseesCentimes(tous, s2.id), 400000);
    expect(especesEncaisseesCentimes(tous, 'inconnue'), 0);
  });

  test('un panier encore OUVERT ne compte jamais, même s’il portait déjà une '
      'session', () async {
    final s1 = await ouvrirLaCaisseDuComptoir(base);
    final p = await panierGarni(TypeVente.comptant, quantite: 6);
    await base.customStatement(
      'UPDATE paniers_local SET session_encaissement_id = ?, '
      'mode_paiement = ?, montant_cloture = ? WHERE id = ?',
      [s1.id, 'especes', 6000, p.id],
    );

    expect(
      (await dao.parId(p.id))!.statut,
      StatutPanier.ouvert,
      reason: 'le cas est bien celui d’un panier ouvert',
    );
    expect(especesEncaisseesCentimes(await dao.paniers(), s1.id), 0);
  });
}
