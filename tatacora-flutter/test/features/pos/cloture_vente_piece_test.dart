import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/caisse/domain/messages_caisse.dart';
import 'package:tatacora_flutter/features/caisse/domain/regles_caisse.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/calcul_tva.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/entities/comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/refus_comptable.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_dao.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/data/piece_de_la_vente.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/article_vendable.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';
import 'package:tatacora_flutter/features/pos/domain/messages_ventes.dart';
import 'package:tatacora_flutter/features/pos/domain/repositories/panier_repository.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import '../facturation/support/outils_encaissement.dart';
import 'support/outils_ventes.dart';

/// La clôture d'un panier PASSE la pièce de la vente — sur le chemin réel :
/// `PanierDao.cloturer` -> `MoteurComptable` -> `ecritures_local`, avec le vrai
/// référentiel installé (le plan du PO, ses triggers de RG-11).
///
/// La confrontation au vrai serveur (`ventes_contre_serveur_test.dart`) compare
/// les lignes et les phrases ; ce fichier tient ce que la comparaison ne dit
/// pas : l'ATOMICITÉ (une pièce refusée n'écrit RIEN), l'absence de moteur, et
/// ce que devient une vente d'AVANT.
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
  const riz = ArticleVendable(
    reference: ReferenceCatalogue(
      module: ModuleVendable.m4Restaurant,
      code: 'p-1',
    ),
    libelle: 'Riz sauce',
    prix: 2500,
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
    await db
        .into(db.menusLocal)
        .insert(
          MenusLocalCompanion.insert(
            id: 'm-1',
            libelle: 'Carte',
            type: 'local',
            creeLe: DateTime(2026, 10, 1),
            creePar: auteurEssai,
          ),
        );
    await db
        .into(db.recettesLocal)
        .insert(
          RecettesLocalCompanion.insert(
            id: 'r-1',
            libelle: 'Fiche',
            creeLe: DateTime(2026, 10, 1),
            creePar: auteurEssai,
          ),
        );
    await db
        .into(db.platsLocal)
        .insert(
          PlatsLocalCompanion.insert(
            id: 'p-1',
            menuId: 'm-1',
            recetteId: 'r-1',
            libelle: 'Riz sauce',
            prixVente: 2500,
            creeLe: DateTime(2026, 10, 1),
            creePar: auteurEssai,
          ),
        );
    await ouvrirCaissePour(db);
  });

  tearDown(() => db.close());

  Future<Panier> garni({
    TypeVente type = TypeVente.comptant,
    List<(ArticleVendable, int)> lignes = const [(biere, 3)],
  }) async {
    var p = await dao.ouvrir(
      typeVente: type,
      pointVente: 'Comptoir',
      reservationId: type == TypeVente.surSejour ? 'res-1' : null,
      dateDepartPrevue: type == TypeVente.surSejour
          ? DateTime(2026, 10, 20)
          : null,
    );
    for (final (article, quantite) in lignes) {
      p = await dao.ajouterLigne(p.id, article, quantite: quantite);
    }
    return p;
  }

  Future<List<String>> piece(String panierId) async {
    final lignes = await compta.lignesParLibelle(libelleDeLaPiece(panierId));
    final comptes = {
      for (final l in lignes)
        l.id: (await compta.compteParId(l.compteId))!.numero,
    };
    return [
      for (final l in lignes)
        '${comptes[l.id]} ${l.debitCentimes > 0 ? 'D' : 'C'}'
            '${l.debitCentimes > 0 ? l.debitCentimes : l.creditCentimes}',
    ];
  }

  Future<int> ecritures() async => (await compta.toutesLesEcritures()).length;

  Future<int> sequences() async =>
      (await db
                  .customSelect(
                    'SELECT COALESCE(SUM(dernier_rang), 0) AS n FROM sequences_piece_local',
                  )
                  .getSingle())
              .data['n']
          as int;

  Future<Panier> cloturer(
    Panier p, {
    String? mode = 'especes',
    String auteur = caissierDeVente,
    PanierDao? avec,
    bool anticipe = true,
  }) => (avec ?? dao).cloturer(
    p.id,
    modePaiement: mode,
    auteurId: auteur,
    anticipe: anticipe,
  );

  group('La pièce est passée DANS la transaction de la clôture', () {
    test('une vente au comptant en espèces : le panier se fige ET sa pièce '
        'naît (Dr 5711 / Cr 7011)', () async {
      final p = await garni();
      final c = await cloturer(p);

      expect(c.statut, StatutPanier.cloture);
      expect(c.montantCloture, 3000);
      expect(c.modePaiement, 'especes');
      expect(c.sessionEncaissementId, isNotNull);
      expect(await piece(p.id), ['5711 D300000', '7011 C300000']);
      // Validée d'emblée : immuable (RG-11), visible du grand livre.
      expect(
        (await compta.lignesParLibelle(
          libelleDeLaPiece(p.id),
        )).every((l) => l.statut == StatutEcriture.validee),
        isTrue,
      );
    });

    test(
      'la pièce porte le NET : bar et restaurant sur leurs deux comptes',
      () async {
        final p = await garni(lignes: const [(biere, 2), (riz, 1)]);
        await cloturer(p, mode: 'mobile_money');
        expect(await piece(p.id), [
          '552 D450000',
          '7061 C250000',
          '7011 C200000',
        ]);
      },
    );

    test('une vente refusée par le moteur n’écrit RIEN : ni la clôture, ni la '
        'pièce, ni le compteur de séquence', () async {
      final p = await garni();
      final avant = (await ecritures(), await sequences());

      // Une horloge qui sort de l'exercice ouvert : la pièce est refusée.
      final hors = panierDaoSur(db, horloge: DateTime(2040, 1, 2, 10));
      await expectLater(
        cloturer(p, avec: hors),
        throwsA(
          isA<RefusComptable>().having(
            (e) => e.motif,
            'motif',
            MotifRefus.exerciceAbsent,
          ),
        ),
      );

      final relu = (await dao.parId(p.id))!;
      expect(
        relu.statut,
        StatutPanier.ouvert,
        reason: 'le panier est conservé',
      );
      expect(relu.montantCloture, isNull);
      expect(relu.sessionEncaissementId, isNull);
      expect(relu.modePaiement, isNull);
      expect((await ecritures(), await sequences()), avant);
    });

    test('une pièce refusée au MILIEU (le centre « Bar » a disparu) emporte '
        'aussi ce que la transaction avait déjà écrit', () async {
      final p = await garni(lignes: const [(biere, 1), (riz, 1)]);
      await db.customStatement(
        "DELETE FROM centres_cout_local WHERE libelle = 'Bar'",
      );
      final avant = await sequences();

      await expectLater(
        cloturer(p),
        throwsA(
          isA<RefusComptable>().having(
            (e) => e.motif,
            'motif',
            MotifRefus.centreAbsent,
          ),
        ),
      );
      expect((await dao.parId(p.id))!.statut, StatutPanier.ouvert);
      expect(await ecritures(), 0);
      expect(await sequences(), avant);
    });

    test('un DAO sans moteur LÈVE : jamais une vente sans sa pièce par '
        'omission', () async {
      final p = await garni();
      final sans = panierDaoSur(db, sansMoteur: true);

      await expectLater(cloturer(p, avec: sans), throwsStateError);
      expect((await dao.parId(p.id))!.statut, StatutPanier.ouvert);
      expect(await ecritures(), 0);
    });

    test(
      'sans auteur, la pièce est refusée (RG-15) et rien n’est écrit',
      () async {
        final p = await garni();
        await expectLater(
          cloturer(p, auteur: ''),
          throwsA(
            isA<RefusComptable>().having(
              (e) => e.motif,
              'motif',
              MotifRefus.auteurAbsent,
            ),
          ),
        );
        expect((await dao.parId(p.id))!.statut, StatutPanier.ouvert);
        expect(await ecritures(), 0);
      },
    );

    test('deux ventes de suite : deux pièces numérotées à la suite', () async {
      final a = await garni();
      final b = await garni();
      await cloturer(a);
      await cloturer(b);

      final numeros = {
        for (final e in await compta.toutesLesEcritures()) e.numeroPiece,
      };
      expect(numeros, {'VTE-2026-00001', 'VTE-2026-00002'});
    });
  });

  group('Les refus du serveur, dans son ORDRE', () {
    test('panier vide : « rien à encaisser » au comptoir, « du séjour » au '
        'séjour', () async {
      final comptoir = await dao.ouvrir(typeVente: TypeVente.comptant);
      await expectLater(
        cloturer(comptoir),
        throwsA(
          isA<PanierVide>().having(
            (e) => e.message,
            'message',
            const PanierVide.auComptoir().message,
          ),
        ),
      );
      expect(
        const PanierVide.auComptoir().message,
        'Le panier est vide : il n\'y a rien à encaisser.',
      );
      expect(
        const PanierVide.duSejour().message,
        'Le panier du séjour est vide : il n\'y a rien à facturer.',
      );
    });

    test('la note de chambre est refusée au comptoir AVANT de regarder la '
        'caisse', () async {
      // Aucune caisse ouverte : si la caisse passait en premier, on lirait la
      // phrase de la caisse.
      await db.customStatement(
        'UPDATE sessions_caisse_local SET date_cloture = 1787000000',
      );
      final p = await garni();
      await expectLater(
        cloturer(p, mode: 'note_chambre'),
        throwsA(
          isA<RefusVente>().having(
            (e) => e.message,
            'message',
            MessagesVentes.noteChambreAuComptoir,
          ),
        ),
      );
    });

    test('puis la caisse, puis le mode : « inconnu » n’est vu qu’APRÈS la '
        'caisse', () async {
      await db.customStatement(
        'UPDATE sessions_caisse_local SET date_cloture = 1787000000',
      );
      final p = await garni();
      await expectLater(
        cloturer(p, mode: 'cheque'),
        throwsA(
          isA<RefusCaisse>().having(
            (e) => e.message,
            'message',
            MessagesCaisse.refusSansCaisse,
          ),
        ),
      );
      await ouvrirCaissePour(db);
      await expectLater(
        cloturer(p, mode: 'cheque'),
        throwsA(
          isA<RefusVente>().having(
            (e) => e.message,
            'message',
            MessagesVentes.modeInconnu('cheque'),
          ),
        ),
      );
    });

    test('un mode ABSENT est refusé : le poste ne range pas une vente en '
        'espèces par défaut (écart nommé avec le serveur)', () async {
      final p = await garni();
      await expectLater(
        cloturer(p, mode: null),
        throwsA(
          isA<RefusVente>().having(
            (e) => e.message,
            'message',
            MessagesVentes.modeReglementAbsent,
          ),
        ),
      );
      expect((await dao.parId(p.id))!.statut, StatutPanier.ouvert);
    });

    test('un circuit ou une location au panier : le module n’est pas '
        'encaissable, nommé comme le serveur', () async {
      await db
          .into(db.circuitsLocal)
          .insert(
            CircuitsLocalCompanion.insert(
              id: 'cir-1',
              nom: 'Cascades',
              theme: 'Nature',
              zone: 'Atacora',
              prix: 4500,
              capaciteMax: 12,
            ),
          );
      const circuit = ArticleVendable(
        reference: ReferenceCatalogue(
          module: ModuleVendable.m9Tourisme,
          code: 'cir-1',
        ),
        libelle: 'Cascades',
        prix: 4500,
      );
      final p = await garni(lignes: const [(biere, 1), (circuit, 1)]);
      await expectLater(
        cloturer(p),
        throwsA(
          isA<RefusVente>().having(
            (e) => e.message,
            'message',
            MessagesVentes.moduleNonEncaissable('Tourisme'),
          ),
        ),
      );
      expect(await ecritures(), 0);
    });

    test('un article RETIRÉ du catalogue depuis l’ajout : « introuvable au '
        'catalogue », avec son identifiant', () async {
      final p = await garni();
      await db.customStatement(
        "DELETE FROM cartes_boisson_local WHERE id = 'bsn-33'",
      );
      await expectLater(
        cloturer(p),
        throwsA(
          isA<RefusVente>().having(
            (e) => e.message,
            'message',
            MessagesVentes.referenceInconnue('bsn-33'),
          ),
        ),
      );
    });
  });

  group('La TVA, lue des paramètres du poste', () {
    Future<void> poser(Map<String, String?> valeurs) =>
        ParametresDao(db).ecrire(valeurs, auteurId: null);

    test('active SANS taux : la vente est refusée, rien n’est écrit', () async {
      await poser({'tva_active': 'true'});
      final p = await garni();
      await expectLater(
        cloturer(p),
        throwsA(
          isA<RefusTva>().having(
            (e) => e.message,
            'message',
            PhrasesTva.tauxAbsent('taux_tva'),
          ),
        ),
      );
      expect((await dao.parId(p.id))!.statut, StatutPanier.ouvert);
      expect(await ecritures(), 0);
    });

    test(
      'active, TTC à 18 % : le produit est HT et la TVA a son compte',
      () async {
        await poser({
          'tva_active': 'true',
          'taux_tva': '18',
          'convention_prix': 'ttc',
        });
        final p = await garni(lignes: const [(biere, 3), (riz, 1)]);
        await cloturer(p);
        // 3 000 F au bar, 2 500 F au restaurant.
        expect(await piece(p.id), [
          '5711 D550000',
          '7061 C211864',
          '7011 C254237',
          '4432 C38136',
          '4431 C45763',
        ]);
      },
    );

    test('un paramètre CHANGÉ après coup ne réécrit pas une pièce déjà '
        'passée', () async {
      final a = await garni();
      await cloturer(a);
      await poser({
        'tva_active': 'true',
        'taux_tva': '18',
        'convention_prix': 'ttc',
      });
      expect(await piece(a.id), ['5711 D300000', '7011 C300000']);
    });
  });

  group('Un séjour est porté sur la note de chambre', () {
    setUp(() async {
      final c = await creerClient(db);
      await semerReservation(db, id: 'res-1', clientId: c.id);
    });

    test('quel que soit le mode que l’écran avait en mémoire : créance 4111, '
        'aucune trésorerie, aucune caisse requise', () async {
      await db.customStatement(
        'UPDATE sessions_caisse_local SET date_cloture = 1787000000',
      );
      final p = await garni(type: TypeVente.surSejour);
      final c = await cloturer(p, mode: 'especes');

      expect(c.modePaiement, 'note_chambre');
      expect(c.sessionEncaissementId, isNull);
      expect(await piece(p.id), ['4111 D300000', '7011 C300000']);
    });

    test(
      'un séjour sans consommation : « Le panier du séjour est vide »',
      () async {
        final p = await dao.ouvrir(
          typeVente: TypeVente.surSejour,
          reservationId: 'res-1',
          dateDepartPrevue: DateTime(2026, 10, 20),
        );
        await expectLater(
          cloturer(p),
          throwsA(
            isA<PanierVide>().having(
              (e) => e.message,
              'message',
              const PanierVide.duSejour().message,
            ),
          ),
        );
      },
    );
  });

  group('Les ventes d’AVANT — rien n’est fabriqué rétroactivement', () {
    test('un panier clôturé sans pièce reste sans pièce ; les ventes '
        'd’aujourd’hui n’y touchent pas ; on sait les COMPTER', () async {
      // Une vente d'avant : clôturée comme l'ancienne version le faisait.
      final ancien = await garni();
      await cloturerSansPiece(db, ancien.id, mode: 'especes');
      expect(await piece(ancien.id), isEmpty);

      final recent = await garni();
      await cloturer(recent);

      expect(await piece(ancien.id), isEmpty);
      expect(await piece(recent.id), isNotEmpty);

      // « Combien de ventes clôturées n'ont aucune pièce ? » — la question que
      // l'exploitant (ou l'audit) pose, et sa réponse par SQL, sans rien déduire.
      final sansPiece = await db
          .customSelect(
            "SELECT COUNT(*) AS n FROM paniers_local p WHERE p.statut = 'cloture' "
            'AND NOT EXISTS (SELECT 1 FROM ecritures_local e '
            "WHERE e.libelle LIKE 'Vente %' || p.id)",
          )
          .getSingle();
      expect(sansPiece.data['n'], 1);
    });
  });

  test('lot F5 : la vente de SÉJOUR part au serveur, en note de chambre, '
      'rattachée à sa réservation ; le comptoir reste au comptant', () async {
    final c = await creerClient(db);
    await semerReservation(db, id: 'res-1', clientId: c.id);
    final sejour = await garni(type: TypeVente.surSejour);
    await cloturer(sejour);
    final comptoir = await garni();
    await cloturer(comptoir);

    final ops = await OperationsSyncDao(db).operations();
    final s = ops.singleWhere((o) => o.entiteId == sejour.id);
    expect(s.payload, contains('"type_vente":"sur_sejour"'));
    expect(s.payload, contains('"reservation_id":"res-1"'));
    expect(s.payload, contains('"mode_paiement":"note_chambre"'));
    final o = ops.singleWhere((x) => x.entiteId == comptoir.id);
    expect(o.payload, contains('"type_vente":"comptant"'));
    expect(o.payload, isNot(contains('reservation_id')));
  });
}
