import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/dev/mode_demo.dart';
import 'package:tatacora_flutter/features/achats/data/achats_dao.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/bon_reception.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/commande_achat.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/fournisseur.dart';
import 'package:tatacora_flutter/features/caisse/data/sessions_caisse_dao.dart';
import 'package:tatacora_flutter/features/caisse/domain/entities/session_caisse.dart';
import 'package:tatacora_flutter/features/crm/data/client_dao.dart';
import 'package:tatacora_flutter/features/crm/domain/entities/client.dart';
import 'package:tatacora_flutter/features/depenses/domain/categories_depense.dart';
import 'package:tatacora_flutter/features/depenses/domain/entities/depense.dart';
import 'package:tatacora_flutter/features/hebergement/data/parc_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_repository_local.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/fiche_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/usecases/creer_reservation.dart';
import 'package:tatacora_flutter/features/pos/data/catalogue_dao.dart';
import 'package:tatacora_flutter/features/pos/data/dto/catalogue_dto.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/article_vendable.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';
import 'package:tatacora_flutter/features/restaurant/data/restaurant_dao.dart';
import 'package:tatacora_flutter/features/restaurant/domain/entities/plat.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/charges_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import '../depenses/support/outils_depenses.dart';
import '../pos/support/outils_ventes.dart';
import 'support/scenario_file.dart';

/// Les ÉCRIVAINS des tables synchronisées déposent leur document dans la file
/// d'envoi, DANS leur transaction, au contrat du serveur (lot F1, 15/10/2026).
///
/// Trois familles de preuves :
///  1. le document exact, écrivain par écrivain (et, pour une modification,
///     les SEULS champs changés) — l'ancrage au serveur est dans
///     `charges_contre_serveur_test.dart`, qui pousse ces mêmes documents au
///     vrai moteur PHP ;
///  2. l'ATOMICITÉ, pour chaque écrivain : une file en panne défait l'écriture
///     métier, une écriture métier en panne ne laisse aucune ligne de file
///     (déclencheurs SQLite qui lèvent, posés le temps du geste) ;
///  3. ce qui ne part JAMAIS : la vente sur séjour, le mode démonstration, les
///     écritures comptables.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final h = jourScenario;
  DateTime horloge() => h;

  late AppDatabase db;
  late OperationsSyncDao file;
  late StocksDao stocks;
  late CatalogueDao catalogue;
  late RestaurantDao resto;
  late ParcDao parc;
  late AchatsDao achats;
  late SessionsCaisseDao caisse;
  late PanierDao paniers;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await avecComptabilite(db, maintenant: h);
    file = OperationsSyncDao(db);
    stocks = StocksDao(db, maintenant: horloge);
    catalogue = CatalogueDao(db);
    resto = RestaurantDao(db, stocks: stocks, maintenant: horloge);
    parc = ParcDao(db, maintenant: horloge);
    achats = AchatsDao(db, stocks: stocks, maintenant: horloge);
    caisse = SessionsCaisseDao(db, maintenant: horloge);
    paniers = panierDaoSur(db, horloge: h);
    await db
        .into(db.parametresSystemeLocal)
        .insertOnConflictUpdate(
          ParametresSystemeLocalCompanion.insert(
            cle: AchatsDao.cleTolerance,
            valeur: '5',
            modifieLe: h,
          ),
        );
  });

  tearDown(() => db.close());

  /* ------------------------------------------------------------------ */
  /* Aides                                                               */
  /* ------------------------------------------------------------------ */

  /// La DERNIÈRE opération enfilée, pour [table] — type et document.
  Future<(TypeOperationSync, Map<String, Object?>)> derniere(
    TableSynchronisee table,
  ) async {
    final o = (await file.operations(table: table)).last;
    return (o.type, jsonDecode(o.payload) as Map<String, Object?>);
  }

  /// La dernière opération de [table] est-elle [type], de document [charge] ?
  Future<void> attendre(
    TableSynchronisee table,
    TypeOperationSync type,
    Map<String, Object?> charge,
  ) async {
    final (t, c) = await derniere(table);
    expect(t, type);
    expect(c, charge);
  }

  Future<int> nombre([TableSynchronisee? table]) async =>
      (await file.operations(table: table)).length;

  Future<String> point([String libelle = 'Bar']) async =>
      (await stocks.creerPoint(libelle: libelle, type: TypePoint.bar)).id;

  Future<void> article(String id, {String? point, String? categorie}) =>
      stocks.creerArticle(
        id: id,
        libelle: 'Bière 65cl',
        categorie: categorie,
        uniteMesure: 'bouteille',
        seuilCentiemes: 500,
        suivi: SuiviArticle.permanent,
        pointStockageId: point,
        auteurId: auteurEssai,
      );

  BoissonDistante boisson(double prix, {String? articleId = 'art-1'}) =>
      BoissonDistante(
        id: 'bsn-1',
        articleId: articleId,
        libelle: 'Bière 65cl',
        categorie: 'locale',
        prixVente: prix,
        stockDisponible: null,
      );

  Future<({String menu, String recette, String plat})> carte() async {
    await article('riz');
    final menu = (await resto.enregistrerMenu(
      const SaisieMenu(libelle: 'Carte', type: 'local'),
      auteurId: auteurEssai,
    )).id;
    final recette = (await resto.enregistrerRecette(
      const SaisieFiche(
        libelle: 'Riz sauce',
        lignes: [LigneSaisieComposition(articleId: 'riz', quantite: '0,25')],
      ),
      auteurId: auteurEssai,
    )).id;
    final plat = (await resto.enregistrerPlat(
      SaisiePlat(
        libelle: 'Riz sauce',
        menuId: menu,
        recetteId: recette,
        prixVente: '2500',
      ),
      modification: false,
      auteurId: auteurEssai,
    )).id;
    return (menu: menu, recette: recette, plat: plat);
  }

  SaisieFournisseur fiche({String? contact}) => SaisieFournisseur(
    id: 'f-1',
    raisonSociale: 'Brasserie',
    contact: contact,
    categorie: 'Boissons',
    conditionsPaiement: '30 jours',
    evaluationCode: 'bon',
  );

  Future<String> commande() async {
    await article('art-1');
    await achats.creerFournisseur(fiche(), auteurId: auteurEssai);
    return (await achats.creerCommande(
      const SaisieCommande(
        fournisseurId: 'f-1',
        dateCommande: '2026-10-11',
        statut: StatutCommande.brouillon,
        lignes: [
          LigneSaisieCommande(
            articleId: 'art-1',
            libelle: 'ignoré',
            uniteMesure: 'ignorée',
            quantite: '24',
            prixUnitaire: '650,50',
          ),
        ],
      ),
      auteurId: auteurEssai,
    )).commande.id;
  }

  SaisieReception reception(String commandeId, String pointId) =>
      SaisieReception(
        commandeId: commandeId,
        pointStockageId: pointId,
        dateReception: '2026-10-12',
        lignes: const [
          LigneSaisieReception(
            articleId: 'art-1',
            libelle: 'Bière',
            uniteMesure: 'bouteille',
            quantiteCommandee: '24',
            quantiteDejaRecue: '0',
            quantiteRecue: '24',
          ),
        ],
      );

  Future<SessionCaisse> ouvrirCaisse() => caisse.ouvrir(
    point: PointDeVenteCaisse.bar,
    fondSaisi: '10000',
    auteurId: auteurEssai,
    peutEcrire: true,
  );

  Future<Panier> panierGarni() async {
    await article('art-1');
    await catalogue.enregistrerBoisson(boisson(1100));
    var p = await paniers.ouvrir(
      typeVente: TypeVente.comptant,
      pointVente: 'Bar',
    );
    p = await paniers.ajouterLigne(
      p.id,
      const ArticleVendable(
        reference: ReferenceCatalogue(
          module: ModuleVendable.m5Bar,
          code: 'bsn-1',
        ),
        libelle: 'Bière 65cl',
        prix: 1100,
      ),
      quantite: 3,
    );
    return p;
  }

  Future<({String unite, String client})> parcEtClient() async {
    final categorie = (await parc.creerCategorie(
      libelle: 'Bungalow',
      capaciteMax: 2,
      tarifBase: 28000,
    )).id;
    final unite = await parc.creerUnite(
      numero: 'BNG-01',
      categorieId: categorie,
    );
    final client = (await ClientDao(db).creer(
      nom: 'KORA',
      telephone: '97000001',
      type: TypeClientReferentiel.particulier,
    )).id;
    return (unite: unite, client: client);
  }

  ReservationRepositoryLocal depot() => ReservationRepositoryLocal(
    ReservationDao(
      db,
      maintenant: horloge,
      moteur: () async => moteurSur(db, maintenant: horloge),
    ),
  );

  Future<String> reserver(
    String unite,
    String client, {
    int acompte = 0,
  }) async {
    final d = depot();
    final u = (await d.unites()).firstWhere((x) => x.id == unite);
    return (await CreerReservation(d, maintenant: horloge)(
      unite: u,
      clientId: client,
      clientNom: 'KORA',
      periode: PeriodeSejour(
        arrivee: DateTime(2026, 10, 20),
        depart: DateTime(2026, 10, 22),
      ),
      acompte: acompte,
      modePaiement: ModePaiementReservation.mobileMoney,
      remiseType: TypeRemise.pourcentage,
      remiseValeur: 10,
      auteurId: auteurEssai,
    )).id;
  }

  Future<Depense> depenser() async => depenseDaoSur(db, horloge: h).enregistrer(
    dateTransaction: DateTime(2026, 10, 12),
    tresorerie: TresorerieDepense.momo,
    libelle: 'Marché',
    lignes: const [
      SaisieLigneDepense(
        libelle: 'Tomates',
        compteCharge: '6011',
        nature: NatureDepense.tomate,
        montant: 12500,
      ),
    ],
    auteurId: auteurEssai,
    centreId: await centreDe(db, 'Restaurant'),
  );

  /* ------------------------------------------------------------------ */
  /* 1. Les documents, écrivain par écrivain                             */
  /* ------------------------------------------------------------------ */

  group('catalogue : création complète, modification PARTIELLE', () {
    test('points_stockage — StocksDao.creerPoint', () async {
      final id = await point();
      final (type, charge) = await derniere(TableSynchronisee.pointsStockage);
      expect(type, TypeOperationSync.creation);
      expect(charge, {'libelle': 'Bar', 'type': 'bar'});
      expect((await file.operations()).single.entiteId, id);
    });

    test('articles — creerArticle : seuil en DÉCIMAL, catégorie par défaut '
        'documentée ; modifierArticle : les seuls champs changés', () async {
      final p = await point();
      await article('art-1', point: p);
      var (type, charge) = await derniere(TableSynchronisee.articles);
      expect(type, TypeOperationSync.creation);
      expect(charge, {
        'libelle': 'Bière 65cl',
        'categorie': categorieArticleNonRenseignee,
        'unite_mesure': 'bouteille',
        'seuil_alerte': '5.00',
        'suivi': 'permanent',
        'point_stockage_id': p,
      });

      Future<void> modifier({int seuil = 500, String? categorie}) =>
          stocks.modifierArticle(
            id: 'art-1',
            libelle: 'Bière 65cl',
            categorie: categorie,
            uniteMesure: 'bouteille',
            seuilCentiemes: seuil,
            suivi: SuiviArticle.permanent,
            pointStockageId: p,
          );

      await modifier(seuil: 1250);
      (type, charge) = await derniere(TableSynchronisee.articles);
      expect(type, TypeOperationSync.modification);
      expect(charge, {'seuil_alerte': '12.50'});

      await modifier(seuil: 1250, categorie: 'Boissons');
      expect((await derniere(TableSynchronisee.articles)).$2, {
        'categorie': 'Boissons',
      });

      // Rien de changé : rien n'est enfilé.
      final avant = await nombre();
      await modifier(seuil: 1250, categorie: 'Boissons');
      expect(await nombre(), avant);
    });

    test('cartes_boisson — enregistrerBoisson : création, puis le seul prix ; '
        'l’alignement descendu n’enfile RIEN', () async {
      await article('art-1');
      await catalogue.enregistrerBoisson(boisson(1000));
      var (type, charge) = await derniere(TableSynchronisee.cartesBoisson);
      expect(type, TypeOperationSync.creation);
      expect(charge, {
        'libelle': 'Bière 65cl',
        'article_id': 'art-1',
        'categorie': 'locale',
        'prix_vente': 1000,
      });
      await catalogue.enregistrerBoisson(boisson(1100));
      (type, charge) = await derniere(TableSynchronisee.cartesBoisson);
      expect(type, TypeOperationSync.modification);
      expect(charge, {'prix_vente': 1100});

      final avant = await nombre();
      await catalogue.alignerCatalogue(boissons: [boisson(1200)]);
      expect(await nombre(), avant, reason: 'ce qui descend ne remonte pas');
    });

    test('menus, recettes (composition en décimal), plats — création puis '
        'modification partielle', () async {
      final c = await carte();
      expect((await derniere(TableSynchronisee.menus)).$2, {
        'libelle': 'Carte',
        'type': 'local',
        'date_debut': null,
        'date_fin': null,
      });
      expect((await derniere(TableSynchronisee.recettes)).$2, {
        'libelle': 'Riz sauce',
        'lignes': [
          {'article_id': 'riz', 'quantite_unitaire': '0.250'},
        ],
      });
      expect((await derniere(TableSynchronisee.plats)).$2, {
        'libelle': 'Riz sauce',
        'menu_id': c.menu,
        'recette_id': c.recette,
        'prix_vente': 2500,
        'prix_provisoire': false,
        'prix_corrige_main': false,
      });

      await resto.enregistrerMenu(
        SaisieMenu(
          id: c.menu,
          libelle: 'Carte',
          type: 'local',
          dateDebut: '2026-11-01',
        ),
        auteurId: auteurEssai,
      );
      await attendre(TableSynchronisee.menus, TypeOperationSync.modification, {
        'date_debut': '2026-11-01',
      });

      await resto.enregistrerRecette(
        SaisieFiche(
          id: c.recette,
          libelle: 'Riz sauce',
          lignes: const [
            LigneSaisieComposition(articleId: 'riz', quantite: '0,3'),
          ],
        ),
        auteurId: auteurEssai,
      );
      await attendre(
        TableSynchronisee.recettes,
        TypeOperationSync.modification,
        {
          'lignes': [
            {'article_id': 'riz', 'quantite_unitaire': '0.300'},
          ],
        },
      );

      await resto.enregistrerPlat(
        SaisiePlat(
          id: c.plat,
          libelle: 'Riz sauce',
          menuId: c.menu,
          recetteId: c.recette,
          prixVente: '2700',
        ),
        modification: true,
        auteurId: auteurEssai,
      );
      await attendre(TableSynchronisee.plats, TypeOperationSync.modification, {
        'prix_vente': 2700,
      });
    });

    test('categories et unites d’hébergement — le statut ne part jamais ; '
        'archiver / réintégrer partent en « actif »', () async {
      final categorie = (await parc.creerCategorie(
        libelle: 'Bungalow',
        capaciteMax: 2,
        tarifBase: 28000,
      )).id;
      expect((await derniere(TableSynchronisee.categoriesHebergement)).$2, {
        'libelle': 'Bungalow',
        'tarif_base': 28000,
        'capacite_max': 2,
      });
      await parc.modifierCategorie(
        categorie,
        libelle: 'Bungalow',
        capaciteMax: 3,
        tarifBase: 28000,
      );
      expect((await derniere(TableSynchronisee.categoriesHebergement)).$2, {
        'capacite_max': 3,
      });

      final unite = await parc.creerUnite(
        numero: 'BNG-01',
        categorieId: categorie,
      );
      expect((await derniere(TableSynchronisee.unitesHebergement)).$2, {
        'numero': 'BNG-01',
        'categorie_id': categorie,
      });
      await parc.modifierUnite(unite, numero: 'BNG-1A', categorieId: categorie);
      expect((await derniere(TableSynchronisee.unitesHebergement)).$2, {
        'numero': 'BNG-1A',
      });
      await parc.archiver(unite);
      await attendre(
        TableSynchronisee.unitesHebergement,
        TypeOperationSync.modification,
        {'actif': false},
      );
      await parc.restaurer(unite);
      expect((await derniere(TableSynchronisee.unitesHebergement)).$2, {
        'actif': true,
      });
      // Le nettoyage est un geste du CYCLE : il ne part pas.
      final avant = await nombre();
      await parc.marquerNettoyee(unite);
      expect(await nombre(), avant);
    });

    test('fournisseurs — création, modification partielle, archivage et '
        'restauration', () async {
      await achats.creerFournisseur(fiche(), auteurId: auteurEssai);
      expect((await derniere(TableSynchronisee.fournisseurs)).$2, {
        'raison_sociale': 'Brasserie',
        'contact': null,
        'categorie': 'Boissons',
        'conditions_paiement': '30 jours',
        'evaluation': 'bon',
      });
      await achats.modifierFournisseur(
        fiche(contact: '97000002'),
        auteurId: auteurEssai,
      );
      expect((await derniere(TableSynchronisee.fournisseurs)).$2, {
        'contact': '97000002',
      });
      await achats.archiverFournisseur('f-1', auteurId: auteurEssai);
      expect((await derniere(TableSynchronisee.fournisseurs)).$2, {
        'actif': false,
      });
      await achats.restaurerFournisseur('f-1', auteurId: auteurEssai);
      expect((await derniere(TableSynchronisee.fournisseurs)).$2, {
        'actif': true,
      });
      // Déjà actif : rien ne change, rien ne part.
      final avant = await nombre();
      await achats.restaurerFournisseur('f-1', auteurId: auteurEssai);
      expect(await nombre(), avant);
    });
  });

  group('clients et réservations', () {
    test('clients — ClientDao.creer', () async {
      final c = await ClientDao(db).creer(
        nom: ' KORA ',
        prenom: 'Aline',
        telephone: '97000001',
        email: 'aline@exemple.bj',
        type: TypeClientReferentiel.agence,
      );
      final o = (await file.operations()).single;
      expect(o.entiteId, c.id);
      expect(jsonDecode(o.payload), {
        'nom': 'KORA',
        'prenom': 'Aline',
        'telephone': '97000001',
        'email': 'aline@exemple.bj',
        'type_client': 'agence',
      });
    });

    test(
      'reservations — ReservationDao.creer : création seule, acompte et '
      'remise à deux décimales, mode au code du serveur, canal absent',
      () async {
        final pc = await parcEtClient();
        final id = await reserver(pc.unite, pc.client, acompte: 15000);
        final (type, charge) = await derniere(TableSynchronisee.reservations);
        expect(type, TypeOperationSync.creation);
        expect(
          (await file.operations(
            table: TableSynchronisee.reservations,
          )).single.entiteId,
          id,
        );
        expect(charge, {
          'client_id': pc.client,
          'unite_id': pc.unite,
          'date_arrivee': '2026-10-20',
          'date_depart': '2026-10-22',
          'statut': 'en_attente',
          'acompte': '15000.00',
          'tarif_nuit': '28000.00',
          'remise_type': 'pourcentage',
          'remise_valeur': '10.00',
          'mode_paiement': 'mobile_money',
        });
      },
    );
  });

  group('documents', () {
    test('commandes_achat — création seule ; l’envoi reste LOCAL (le serveur '
        'ne modifie pas une commande)', () async {
      final id = await commande();
      final (type, charge) = await derniere(TableSynchronisee.commandesAchat);
      expect(type, TypeOperationSync.creation);
      final ligne = await (db.select(
        db.lignesCommandeAchatLocal,
      )..where((l) => l.commandeId.equals(id))).getSingle();
      expect(charge, {
        'fournisseur_id': 'f-1',
        'date_commande': '2026-10-11',
        'statut': 'brouillon',
        'lignes': [
          {
            'article_id': 'art-1',
            'article_libelle': 'Bière 65cl',
            'unite_mesure': 'bouteille',
            'quantite_centiemes': 2400,
            'prix_unitaire_centimes': 65050,
            'rang': ligne.rang,
          },
        ],
      });
      expect(
        (await file.operations(
          table: TableSynchronisee.commandesAchat,
        )).single.dateMetier,
        '2026-10-11',
      );
      final avant = await nombre();
      await achats.envoyerCommande(id);
      expect(await nombre(), avant);
    });

    test(
      'bons_reception — le verdict du poste part pour comparaison',
      () async {
        final id = await commande();
        final p = await point();
        final bon = await achats.enregistrerReception(
          reception(id, p),
          auteurId: auteurEssai,
        );
        final o = (await file.operations(
          table: TableSynchronisee.bonsReception,
        )).single;
        expect(o.entiteId, bon.id);
        expect(jsonDecode(o.payload), {
          'commande_id': id,
          'date_reception': '2026-10-12',
          'point_stockage_id': p,
          'conformite': 'totale',
          'lignes': [
            {'article_id': 'art-1', 'quantite_centiemes': 2400},
          ],
        });
      },
    );

    test('sessions_caisse — l’ouverture (création), puis la CLÔTURE '
        '(modification) avec ses trois champs ET le rappel fond / date / '
        'point', () async {
      final s = await ouvrirCaisse();
      await attendre(
        TableSynchronisee.sessionsCaisse,
        TypeOperationSync.creation,
        {
          'point_vente': 'bar',
          'date_ouverture': '2026-10-12 10:00:00',
          'montant_fond_centimes': 1000000,
        },
      );
      await SessionsCaisseDao(
        db,
        maintenant: () => h.add(const Duration(hours: 9, minutes: 5)),
      ).cloturer(
        point: PointDeVenteCaisse.bar,
        constateSaisi: '13300',
        peutEcrire: true,
        especesEncaisseesCentimes: 330000,
      );
      final cloture = (await file.operations(
        table: TableSynchronisee.sessionsCaisse,
      )).last;
      expect(cloture.entiteId, s.id);
      expect(cloture.type, TypeOperationSync.modification);
      expect(jsonDecode(cloture.payload), {
        'date_cloture': '2026-10-12 19:05:00',
        'montant_constate_centimes': 1330000,
        'montant_theorique_centimes': 1330000,
        'montant_fond_centimes': 1000000,
        'date_ouverture': '2026-10-12 10:00:00',
        'point_vente': 'bar',
      });
      expect(cloture.dateMetier, '2026-10-12');
    });

    test('ventes — la clôture d’un panier AU COMPTANT, au total figé ; la '
        'pièce VTE ne part pas', () async {
      final s = await ouvrirCaisse();
      final p = await panierGarni();
      await paniers.cloturer(
        p.id,
        modePaiement: 'especes',
        auteurId: auteurEssai,
      );
      final o = (await file.operations(table: TableSynchronisee.ventes)).single;
      expect(o.entiteId, p.id);
      expect(jsonDecode(o.payload), {
        'type_vente': 'comptant',
        'mode_paiement': 'especes',
        'session_encaissement_id': s.id,
        'cloture_le': '2026-10-12 10:00:00',
        'point_vente': 'Bar',
        'table_id': null,
        'client_nom': null,
        'montant_cloture': 3300,
        'lignes': [
          {
            'module_source': 'M5',
            'code_article': 'bsn-1',
            'libelle': 'Bière 65cl',
            'prix_unitaire': 1100,
            'quantite': 3,
          },
        ],
      });
      // L'ordre : l'ouverture de la caisse, puis la vente.
      final ordre = [for (final x in await file.operations()) x.table];
      expect(
        ordre.indexOf(TableSynchronisee.sessionsCaisse) <
            ordre.indexOf(TableSynchronisee.ventes),
        isTrue,
      );
    });

    test('ventes — un panier SUR SÉJOUR (note de chambre) n’est PAS enfilé : '
        'le serveur le refuse (phase 2), il reste sur le poste', () async {
      final pc = await parcEtClient();
      final reservation = await reserver(pc.unite, pc.client);
      await article('art-1');
      await catalogue.enregistrerBoisson(boisson(1100));
      var p = await paniers.ouvrir(
        typeVente: TypeVente.surSejour,
        reservationId: reservation,
        dateDepartPrevue: DateTime(2026, 10, 22),
      );
      p = await paniers.ajouterLigne(
        p.id,
        const ArticleVendable(
          reference: ReferenceCatalogue(
            module: ModuleVendable.m5Bar,
            code: 'bsn-1',
          ),
          libelle: 'Bière 65cl',
          prix: 1100,
        ),
        quantite: 2,
      );
      final ecrituresAvant = await compter(db, 'ecritures_local');
      final clos = await paniers.cloturer(
        p.id,
        anticipe: true,
        auteurId: auteurEssai,
      );
      expect(clos.statut, StatutPanier.cloture);
      expect(
        await compter(db, 'ecritures_local'),
        greaterThan(ecrituresAvant),
        reason: 'la vente est bien close sur le poste, pièce comprise',
      );
      expect(await nombre(TableSynchronisee.ventes), 0);
    });

    test('depenses — le centre relu sur la PIÈCE passée (id ET libellé), '
        'montants en francs entiers', () async {
      final d = await depenser();
      final o = (await file.operations(
        table: TableSynchronisee.depenses,
      )).single;
      expect(o.entiteId, d.id);
      expect(jsonDecode(o.payload), {
        'date_transaction': '2026-10-12',
        'tresorerie': 'momo',
        'libelle': 'Marché',
        'centre_id': await centreDe(db, 'Restaurant'),
        'centre_libelle': 'Restaurant',
        'lignes': [
          {
            'libelle': 'Tomates',
            'compte_charge': '6011',
            'nature': NatureDepense.tomate.libelle,
            'famille': NatureDepense.tomate.famille.libelle,
            'montant': 12500,
          },
        ],
      });
      expect(o.dateMetier, '2026-10-12');
    });
  });

  /* ------------------------------------------------------------------ */
  /* 2. L'atomicité, pour CHAQUE écrivain                                */
  /* ------------------------------------------------------------------ */

  group('ATOMICITÉ : écriture métier et entrée de file, une seule '
      'transaction', () {
    /// L'empreinte d'une table : toutes ses lignes, sérialisées.
    Future<String> empreinte(String table) async => jsonEncode([
      for (final l in await db.customSelect('SELECT * FROM $table').get())
        l.data,
    ]);

    /// Prouve, pour [geste], les deux sens :
    ///  (a) la file tombe en panne → [tables] restent INTACTES ;
    ///  (b) l'écriture métier tombe en panne ([evenement] sur [tables].first)
    ///      → AUCUNE ligne de file.
    Future<void> prouver(
      Future<void> Function() geste, {
      required List<String> tables,
      required String evenement,
    }) async {
      final avant = {for (final t in tables) t: await empreinte(t)};
      final fileAvant = await empreinte('operations_sync_local');

      await db.customStatement(
        'CREATE TEMP TRIGGER panne_file BEFORE INSERT ON operations_sync_local '
        "BEGIN SELECT RAISE(ABORT, 'panne de la file'); END",
      );
      await expectLater(geste(), throwsA(anything), reason: '(a) panne file');
      await db.customStatement('DROP TRIGGER panne_file');
      for (final t in tables) {
        expect(await empreinte(t), avant[t], reason: '(a) $t a bougé');
      }
      expect(await empreinte('operations_sync_local'), fileAvant);

      await db.customStatement(
        'CREATE TEMP TRIGGER panne_metier BEFORE $evenement ON ${tables.first} '
        "BEGIN SELECT RAISE(ABORT, 'panne de l''écriture métier'); END",
      );
      await expectLater(geste(), throwsA(anything), reason: '(b) panne métier');
      await db.customStatement('DROP TRIGGER panne_metier');
      expect(
        await empreinte('operations_sync_local'),
        fileAvant,
        reason: '(b) une ligne de file a survécu à l’écriture métier',
      );

      // Sans panne, le geste passe et enfile : le cas n'était pas vide.
      await geste();
      expect(await empreinte('operations_sync_local'), isNot(fileAvant));
    }

    test('points_stockage', () async {
      await prouver(
        () => point(),
        tables: ['points_stockage_local'],
        evenement: 'INSERT',
      );
    });

    test(
      'articles : création (et son stock d’ouverture), modification',
      () async {
        final p = await point();
        await prouver(
          () => stocks.creerArticle(
            id: 'art-x',
            libelle: 'Huile',
            categorie: null,
            uniteMesure: 'litre',
            seuilCentiemes: 100,
            suivi: SuiviArticle.permanent,
            pointStockageId: p,
            auteurId: auteurEssai,
            ouverture: (centiemes: 1000, coutDixMilliemes: null),
          ),
          tables: ['articles_local', 'mouvements_stock_local'],
          evenement: 'INSERT',
        );
        await prouver(
          () => stocks.modifierArticle(
            id: 'art-x',
            libelle: 'Huile',
            categorie: 'Épicerie',
            uniteMesure: 'litre',
            seuilCentiemes: 300,
            suivi: SuiviArticle.permanent,
            pointStockageId: p,
          ),
          tables: ['articles_local'],
          evenement: 'UPDATE',
        );
      },
    );

    test('articles : le stock d’ouverture refusé APRÈS l’enfilement défait '
        'l’article ET sa ligne de file', () async {
      await expectLater(
        stocks.creerArticle(
          id: 'art-y',
          libelle: 'Huile',
          categorie: null,
          uniteMesure: 'litre',
          seuilCentiemes: 100,
          suivi: SuiviArticle.permanent,
          pointStockageId: null,
          auteurId: auteurEssai,
          ouverture: (centiemes: 1000, coutDixMilliemes: null),
        ),
        throwsA(isA<RefusStock>()),
      );
      expect(await compter(db, 'articles_local'), 0);
      expect(await nombre(), 0);
    });

    test('cartes_boisson', () async {
      await article('art-1');
      await prouver(
        () => catalogue.enregistrerBoisson(boisson(1000)),
        tables: ['cartes_boisson_local'],
        evenement: 'INSERT',
      );
      await prouver(
        () => catalogue.enregistrerBoisson(boisson(1500)),
        tables: ['cartes_boisson_local'],
        evenement: 'INSERT',
      );
    });

    test('menus, recettes, plats', () async {
      final c = await carte();
      await prouver(
        () => resto.enregistrerMenu(
          const SaisieMenu(libelle: 'Carte du soir', type: 'europeen'),
          auteurId: auteurEssai,
        ),
        tables: ['menus_local'],
        evenement: 'INSERT',
      );
      await prouver(
        () => resto.enregistrerMenu(
          SaisieMenu(id: c.menu, libelle: 'Carte bis', type: 'local'),
          auteurId: auteurEssai,
        ),
        tables: ['menus_local'],
        evenement: 'UPDATE',
      );
      await prouver(
        () => resto.enregistrerRecette(
          const SaisieFiche(
            libelle: 'Riz gras',
            lignes: [LigneSaisieComposition(articleId: 'riz', quantite: '1')],
          ),
          auteurId: auteurEssai,
        ),
        tables: ['recettes_local', 'ingredients_recette_local'],
        evenement: 'INSERT',
      );
      await prouver(
        () => resto.enregistrerPlat(
          SaisiePlat(
            libelle: 'Riz sauce bis',
            menuId: c.menu,
            recetteId: c.recette,
            prixVente: '3000',
          ),
          modification: false,
          auteurId: auteurEssai,
        ),
        tables: ['plats_local'],
        evenement: 'INSERT',
      );
      await prouver(
        () => resto.enregistrerPlat(
          SaisiePlat(
            id: c.plat,
            libelle: 'Riz sauce',
            menuId: c.menu,
            recetteId: c.recette,
            prixVente: '2600',
          ),
          modification: true,
          auteurId: auteurEssai,
        ),
        tables: ['plats_local'],
        evenement: 'UPDATE',
      );
    });

    test('categories et unites d’hébergement (création, modification, '
        'archivage, réintégration)', () async {
      await prouver(
        () => parc.creerCategorie(
          libelle: 'Suite',
          capaciteMax: 4,
          tarifBase: 50000,
        ),
        tables: ['categories_hebergement_local'],
        evenement: 'INSERT',
      );
      final cat = (await parc.categories()).single.id;
      await prouver(
        () => parc.modifierCategorie(
          cat,
          libelle: 'Suite',
          capaciteMax: 5,
          tarifBase: 50000,
        ),
        tables: ['categories_hebergement_local'],
        evenement: 'UPDATE',
      );
      await prouver(
        () => parc.creerUnite(numero: 'S-1', categorieId: cat),
        tables: ['unites_hebergement_local'],
        evenement: 'INSERT',
      );
      final unite =
          (await db.select(db.unitesHebergementLocal).get()).single.id;
      await prouver(
        () => parc.modifierUnite(unite, numero: 'S-2', categorieId: cat),
        tables: ['unites_hebergement_local'],
        evenement: 'UPDATE',
      );
      await prouver(
        () => parc.archiver(unite),
        tables: ['unites_hebergement_local'],
        evenement: 'UPDATE',
      );
      await prouver(
        () => parc.restaurer(unite),
        tables: ['unites_hebergement_local'],
        evenement: 'UPDATE',
      );
    });

    test(
      'fournisseurs (création, modification, archivage, restauration)',
      () async {
        await prouver(
          () => achats.creerFournisseur(fiche(), auteurId: auteurEssai),
          tables: ['fournisseurs_local'],
          evenement: 'INSERT',
        );
        await prouver(
          () => achats.modifierFournisseur(
            fiche(contact: '97'),
            auteurId: auteurEssai,
          ),
          tables: ['fournisseurs_local'],
          evenement: 'UPDATE',
        );
        await prouver(
          () => achats.archiverFournisseur('f-1', auteurId: auteurEssai),
          tables: ['fournisseurs_local'],
          evenement: 'UPDATE',
        );
        await prouver(
          () => achats.restaurerFournisseur('f-1', auteurId: auteurEssai),
          tables: ['fournisseurs_local'],
          evenement: 'UPDATE',
        );
      },
    );

    test('clients et réservations (pièce d’acompte comprise)', () async {
      await prouver(
        () => ClientDao(db).creer(
          nom: 'DOSSOU',
          telephone: '97',
          type: TypeClientReferentiel.particulier,
        ),
        tables: ['clients_local'],
        evenement: 'INSERT',
      );
      final pc = await parcEtClient();
      await prouver(
        () => reserver(pc.unite, pc.client, acompte: 10000),
        tables: ['reservations_local', 'ecritures_local'],
        evenement: 'INSERT',
      );
    });

    test('commandes et bons de réception (entrée de stock comprise)', () async {
      await article('art-1');
      await achats.creerFournisseur(fiche(), auteurId: auteurEssai);
      final p = await point();
      await prouver(
        () => achats.creerCommande(
          const SaisieCommande(
            fournisseurId: 'f-1',
            dateCommande: '2026-10-11',
            statut: StatutCommande.envoyee,
            lignes: [
              LigneSaisieCommande(
                articleId: 'art-1',
                libelle: 'x',
                uniteMesure: 'x',
                quantite: '24',
                prixUnitaire: '650',
              ),
            ],
          ),
          auteurId: auteurEssai,
        ),
        tables: ['commandes_achat_local', 'lignes_commande_achat_local'],
        evenement: 'INSERT',
      );
      final id = (await db.select(db.commandesAchatLocal).get()).single.id;
      await prouver(
        () => achats.enregistrerReception(
          reception(id, p),
          auteurId: auteurEssai,
        ),
        tables: [
          'bons_reception_local',
          'mouvements_stock_local',
          'commandes_achat_local',
        ],
        evenement: 'INSERT',
      );
    });

    test('sessions de caisse : ouverture et clôture', () async {
      await prouver(
        ouvrirCaisse,
        tables: ['sessions_caisse_local'],
        evenement: 'INSERT',
      );
      await prouver(
        () => caisse.cloturer(
          point: PointDeVenteCaisse.bar,
          constateSaisi: '10000',
          peutEcrire: true,
          especesEncaisseesCentimes: 0,
        ),
        tables: ['sessions_caisse_local'],
        evenement: 'UPDATE',
      );
    });

    test('ventes : la clôture du panier ET sa pièce', () async {
      await ouvrirCaisse();
      final p = await panierGarni();
      await prouver(
        () => paniers.cloturer(
          p.id,
          modePaiement: 'especes',
          auteurId: auteurEssai,
        ),
        tables: ['paniers_local', 'ecritures_local'],
        evenement: 'UPDATE',
      );
    });

    test('dépenses : la dépense, ses lignes ET sa pièce', () async {
      await prouver(
        depenser,
        tables: ['depenses_local', 'lignes_depense_local', 'ecritures_local'],
        evenement: 'INSERT',
      );
    });
  });

  /* ------------------------------------------------------------------ */
  /* 3. Ce qui ne part jamais                                            */
  /* ------------------------------------------------------------------ */

  group('ce qui ne part JAMAIS', () {
    test('le MODE DÉMONSTRATION n’enfile rien — ni l’amorçage, ni les gestes '
        'qui suivent', () async {
      final demo = AppDatabase.enMemoire(fileSynchronisation: false);
      await avecComptabilite(demo, maintenant: h);
      await amorcerModeDemo(demo, modeDemo: true, maintenant: h);
      await ClientDao(demo).creer(
        nom: 'Démo',
        telephone: '00',
        type: TypeClientReferentiel.particulier,
      );
      await StocksDao(demo).creerPoint(libelle: 'Bar démo');
      await SessionsCaisseDao(demo).ouvrir(
        point: PointDeVenteCaisse.bar,
        fondSaisi: '1000',
        auteurId: auteurEssai,
        peutEcrire: true,
      );
      expect(await OperationsSyncDao(demo).operations(), isEmpty);
      expect(await compter(demo, 'clients_local'), greaterThan(0));
      await demo.close();
    });

    test('main_demo.dart ouvre sa base SANS file, et le flavor demo en fait '
        'le défaut (relus dans le code)', () {
      final demo = File('lib/main_demo.dart').readAsStringSync();
      expect(demo, contains('AppDatabase(fileSynchronisation: false)'));
      final base = File(
        'lib/core/database/app_database.dart',
      ).readAsStringSync();
      expect(
        base,
        contains(
          'fileSynchronisation ?? !Environnement.actuel.estHorsLigneIntegral',
        ),
      );
    });

    test(
      'AUCUNE écriture comptable n’est enfilée : balayage de lib/ (D246)',
      () {
        final appels = <String, Set<String>>{};
        for (final f in Directory('lib').listSync(recursive: true)) {
          if (f is! File || !f.path.endsWith('.dart')) continue;
          if (f.path.endsWith('.g.dart')) continue;
          final code = f.readAsStringSync();
          if (!code.contains('.enfiler(')) continue;
          appels[f.path] = {
            for (final m in RegExp(
              r'TableSynchronisee\.(\w+)',
            ).allMatches(code))
              m.group(1)!,
          };
        }
        // Plancher : le balayage n'est pas vide (piège 4).
        expect(appels.length, greaterThanOrEqualTo(10), reason: '$appels');
        final noms = {for (final t in TableSynchronisee.values) t.name};
        for (final e in appels.entries) {
          expect(noms, containsAll(e.value), reason: e.key);
          expect(
            e.value.where((t) => t.toLowerCase().contains('ecriture')),
            isEmpty,
            reason: e.key,
          );
        }
        // Le seul auteur d'écritures ne touche pas à la file, et inversement.
        for (final chemin in [
          'lib/features/comptabilite/data/moteur_comptable.dart',
          'lib/features/comptabilite/data/comptabilite_dao.dart',
        ]) {
          final code = File(chemin).readAsStringSync();
          expect(code, isNot(contains('OperationsSyncDao')), reason: chemin);
          expect(code, isNot(contains('enfiler')), reason: chemin);
        }
        final dao = File(
          'lib/features/synchronisation/data/operations_sync_dao.dart',
        ).readAsStringSync();
        expect(dao, isNot(contains('ecritures')));
      },
    );

    test('un SEUL auteur de la file : OperationsSyncDao', () {
      final ecrivains = <String>[];
      final motifs = [
        RegExp(r'\boperationsSyncLocal\b'),
        RegExp(r'OperationsSyncLocalCompanion\b'),
        RegExp(
          r'(INSERT\s+(OR\s+\w+\s+)?INTO|UPDATE|DELETE\s+FROM)\s+operations_sync_local',
        ),
      ];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('.g.dart')) continue;
        if (f.path.endsWith('app_database.dart')) continue;
        final code = f.readAsStringSync();
        if (motifs.any((m) => m.hasMatch(code))) ecrivains.add(f.path);
      }
      expect(ecrivains, [
        'lib/features/synchronisation/data/operations_sync_dao.dart',
      ]);
    });

    test('chaque fichier qui ÉCRIT une table synchronisée enfile, sauf les '
        'exceptions NOMMÉES', () {
      // Le nom Drift de chaque table locale synchronisée.
      const tablesLocales = [
        'pointsStockageLocal',
        'articlesLocal',
        'cartesBoissonLocal',
        'menusLocal',
        'recettesLocal',
        'platsLocal',
        'categoriesHebergementLocal',
        'unitesHebergementLocal',
        'fournisseursLocal',
        'clientsLocal',
        'reservationsLocal',
        'commandesAchatLocal',
        'bonsReceptionLocal',
        'sessionsCaisseLocal',
        'paniersLocal',
        'depensesLocal',
      ];
      // Les écrivains qui n'enfilent pas, et pourquoi — tous nommés.
      const exceptions = {
        // Le cycle des unités (occupée, nettoyage) appartient au serveur.
        'lib/features/hebergement/data/sejour_dao.dart',
        // « Réinitialiser comme neuf » vide les tables : rien à pousser.
        'lib/features/transverse/data/reinitialisation_locale.dart',
        // Ce qui DESCEND du serveur n'y remonte pas (une boucle) — lots F2b
        // et F3. Jusqu'au F3, ce fichier échappait à la sonde : il écrivait
        // par un alias (`_db.into(t)`), que le motif ne lit pas. Le F3
        // (`_db.into(_db.clientsLocal)`) l'a rendu visible ; « n'enfile
        // jamais » est tenu par son propre balayage (descente_catalogue_test).
        'lib/features/synchronisation/data/aligneur_catalogue.dart',
      };
      final fautifs = <String>[];
      final vus = <String>[];
      var ecrivains = 0;
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('.g.dart')) continue;
        final code = f.readAsStringSync();
        final ecrit = tablesLocales.any(
          (t) =>
              RegExp('\\b(into|update)\\(\\s*(\\w+\\.)*$t\\b').hasMatch(code),
        );
        if (!ecrit) continue;
        ecrivains++;
        vus.add(f.path);
        if (code.contains('.enfiler(') || exceptions.contains(f.path)) {
          continue;
        }
        fautifs.add(f.path);
      }
      expect(ecrivains, greaterThanOrEqualTo(9), reason: '$vus');
      expect(fautifs, isEmpty);
    });
  });
}
