import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/format/formats.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_colors.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/caisse/domain/messages_caisse.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_repository_local.dart';
import 'package:tatacora_flutter/features/hebergement/presentation/providers_hebergement.dart';
import 'package:tatacora_flutter/features/pos/data/catalogue_dao.dart';
import 'package:tatacora_flutter/features/pos/data/panier_repository_local.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/repositories/panier_repository.dart';
import 'package:tatacora_flutter/features/pos/presentation/ecran_pos_comptant.dart';
import 'package:tatacora_flutter/features/pos/presentation/ecran_pos_heberges.dart';
import 'package:tatacora_flutter/features/pos/presentation/providers_pos.dart';
import 'package:tatacora_flutter/features/pos/presentation/widgets/modale_cloture_sejour.dart';
import 'package:tatacora_flutter/features/pos/presentation/widgets/panier_heberges.dart';

import '../facturation/support/outils_encaissement.dart'
    show ouvrirLaCaisseDuComptoir;
import 'support/outils_ventes.dart';

/// Les deux écrans de point de vente, montés sur une **vraie base locale**.
///
/// ⚠ **Portage d'une PROPOSITION non ratifiée**
/// (`docs/PROPOSITION_MODELE_PANIER_POS.md`, Q1/Q2/Q3).
///
/// Le cas qui compte le plus ici est le **piège PA-79** : changer de filtre de
/// catalogue ne doit pas toucher au panier. Le défaut interdisait une addition
/// mêlant bar et restaurant, c'est-à-dire exactement ce que le client demande.
void main() {
  late AppDatabase db;
  late PanierRepositoryLocal depotPanier;

  setUp(() async {
    db = AppDatabase.enMemoire();
    // Horloge FIXÉE au 10/10/2026, deux jours avant le départ du séjour de
    // l'essai : la clôture y est ANTICIPÉE (règle 5) quel que soit le jour où
    // la suite tourne. Une clôture passe la pièce de la vente : le référentiel
    // comptable est installé à cette date, et le moteur branché.
    await avecComptabilite(db, maintenant: DateTime(2026, 10, 10, 9));
    depotPanier = PanierRepositoryLocal(
      panierDaoSur(db, horloge: DateTime(2026, 10, 10, 9)),
    );

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
        .into(db.circuitsLocal)
        .insert(
          CircuitsLocalCompanion.insert(
            id: 'cir-1',
            nom: 'Cascades de Tanougou',
            theme: 'Nature',
            zone: 'Atacora',
            prix: 4500,
            capaciteMax: 12,
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
        .into(db.reservationsLocal)
        .insert(
          ReservationsLocalCompanion.insert(
            id: 'res-1',
            reference: 'LOC-RES1',
            clientId: 'cli-1',
            uniteId: 'u-1',
            // Horloge FIXÉE : trois nuits, du 09 au 12/10/2026. Avec
            // `DateTime.now()`, la date de départ affichée changerait chaque
            // jour.
            dateArrivee: DateTime(2026, 10, 9),
            dateDepart: DateTime(2026, 10, 12),
            statut: 'confirmee',
            tarifNuit: 28000,
          ),
        );
  });

  tearDown(() => db.close());

  /// Un écran large : les trois colonnes du POS hébergés n'existent qu'au-delà
  /// du seuil desktop de 1024 px, et le poste du comptoir en est un.
  Future<void> monter(
    WidgetTester tester,
    Widget ecran, {
    GardeAcces? droits,
  }) async {
    tester.view
      ..physicalSize = const Size(1600, 1000)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          // Celui qui encaisse : la clôture nomme son auteur (RG-15).
          sessionProvider.overrideWithBuild(
            (ref, notifier) => Session(
              utilisateurId: caissierDeVente,
              login: 'caissier',
              nom: 'Caissier',
              role: 'gerant',
              droits: GardeAcces.depuisJson(const {'M5': 'C', 'M1': 'C'}),
            ),
          ),
          depotPanierProvider.overrideWithValue(depotPanier),
          catalogueProvider.overrideWithValue(CatalogueDao(db)),
          depotReservationProvider.overrideWithValue(
            ReservationRepositoryLocal(ReservationDao(db)),
          ),
          droitsProvider.overrideWithValue(
            droits ?? GardeAcces.depuisJson(const {'M5': 'C', 'M1': 'C'}),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: Scaffold(body: ecran),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Choisit un rayon dans le sélecteur de famille (`pos-famille`).
  Future<void> choisirRayon(WidgetTester tester, String code) async {
    await tester.tap(find.byKey(const Key('pos-famille')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('pos-rayon-$code')).last);
    await tester.pumpAndSettle();
  }

  /* ================================================================== */
  group('POS au comptant', () {
    testWidgets('aucun panier n’est ouvert tout seul au chargement', (
      tester,
    ) async {
      // Ouvrir automatiquement créerait un panier vide à chaque passage, et la
      // liste s'emplirait de coquilles que personne n'a voulues.
      await monter(tester, const EcranPosComptant());

      expect(find.byKey(const Key('pos-comptant-ouvrir')), findsOneWidget);
      expect(await depotPanier.paniers(), isEmpty);
    });

    testWidgets('une vente s’ouvre, un article s’ajoute, le total suit', (
      tester,
    ) async {
      await monter(tester, const EcranPosComptant());

      await tester.tap(find.byKey(const Key('pos-comptant-ouvrir')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pos-article-M5:bsn-33')));
      await tester.pumpAndSettle();

      // Le total est CALCULÉ et affiché en lecture seule, jamais saisi.
      expect(find.byKey(const Key('pos-total')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('pos-total'))).data,
        formaterFcfa(1000),
      );
      expect((await depotPanier.paniers()).single.total, 1000);
    });

    testWidgets('sans caisse ouverte, le bouton d’encaissement est GRISÉ et '
        'dit pourquoi (D221)', (tester) async {
      await monter(tester, const EcranPosComptant());
      await tester.tap(find.byKey(const Key('pos-comptant-ouvrir')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pos-article-M5:bsn-33')));
      await tester.pumpAndSettle();

      final bouton = tester.widget<FilledButton>(
        find.byKey(const Key('pos-cloturer')),
      );
      expect(bouton.onPressed, isNull);
      expect(
        find.descendant(
          of: find.byKey(const Key('pos-cloturer')),
          matching: find.text(MessagesCaisse.encaisserSansCaisse),
        ),
        findsOneWidget,
      );
    });

    testWidgets('avec la caisse du bar, le bouton s’ouvre et l’encaissement '
        'écrit la session sur la vente', (tester) async {
      final session = await ouvrirLaCaisseDuComptoir(db);
      await monter(tester, const EcranPosComptant());
      await tester.tap(find.byKey(const Key('pos-comptant-ouvrir')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pos-article-M5:bsn-33')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('pos-cloturer')))
            .onPressed,
        isNotNull,
      );
      expect(find.text(MessagesCaisse.encaisserSansCaisse), findsNothing);

      await tester.tap(find.byKey(const Key('pos-cloturer')));
      await tester.pumpAndSettle();

      expect(
        (await depotPanier.paniers()).single.sessionEncaissementId,
        session.id,
      );
    });

    testWidgets('⚠ PA-79 — changer de filtre ne vide PAS le panier', (
      tester,
    ) async {
      // Le défaut : le sélecteur de catalogue désignait aussi la caisse, si
      // bien qu'un client prenant une bière puis un circuit perdait sa
      // première ligne — et l'addition unique qu'il demandait devenait
      // impossible.
      await monter(tester, const EcranPosComptant());

      await tester.tap(find.byKey(const Key('pos-comptant-ouvrir')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pos-article-M5:bsn-33')));
      await tester.pumpAndSettle();

      // On change de rayon — le geste qui vidait le panier. Le rayon est un
      // SÉLECTEUR depuis le POS en trois colonnes (14/10/2026).
      await choisirRayon(tester, 'M9');

      final panier = (await depotPanier.paniers()).single;
      expect(
        panier.lignes,
        hasLength(1),
        reason: 'le filtre est un filtre, pas une caisse',
      );

      // Et l'article de l'autre rayon rejoint le MÊME panier (règle 4).
      await tester.tap(find.byKey(const Key('pos-article-M9:cir-1')));
      await tester.pumpAndSettle();

      final apres = (await depotPanier.paniers()).single;
      expect(apres.lignes, hasLength(2));
      expect(apres.total, 5500);
      expect(apres.ventilation.keys, hasLength(2));
    });

    testWidgets('un rayon vide dit POURQUOI il l’est', (tester) async {
      // Le catalogue du restaurant de ce poste est vide (M4 est local depuis le
      // 09/10/2026). Un onglet présent et vide sans explication passerait pour
      // cassé (leçon PA-90) ; la raison dit quoi faire, pas qu'il faut une
      // connexion.
      await monter(tester, const EcranPosComptant());

      await choisirRayon(tester, 'M4');

      final message = tester.widget<Text>(
        find.byKey(const Key('pos-catalogue-vide')),
      );
      expect(message.data, contains('Aucun plat'));
      expect(message.data, isNot(contains('connexion')));
    });

    testWidgets('sans droit d’écriture sur M5, aucune vente ne s’ouvre', (
      tester,
    ) async {
      await monter(
        tester,
        const EcranPosComptant(),
        droits: GardeAcces.depuisJson(const {'M5': 'L'}),
      );

      final bouton = tester.widget<FilledButton>(
        find.ancestor(
          // Libellé de la consigne du PO (14/10/2026).
          of: find.text('Nouvelle vente au comptoir'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(bouton.onPressed, isNull);
    });

    testWidgets('l’écran ne prétend PAS que le panier est synchronisé', (
      tester,
    ) async {
      // Annoncer « en attente de synchronisation » serait un indicateur
      // affirmant un état qu'il n'a pas vérifié (PA-59/60/61) : `paniers`
      // n'est pas au registre des tables synchronisables du serveur.
      await monter(tester, const EcranPosComptant());
      await tester.tap(find.byKey(const Key('pos-comptant-ouvrir')));
      await tester.pumpAndSettle();

      final mention = tester.widget<Text>(
        find.byKey(const Key('pos-transmission')),
      );
      expect(mention.data, contains('ce poste'));
      expect(mention.data, isNot(contains('en attente de synchronisation')));
    });
  });

  /* ================================================================== */
  group('POS clients hébergés', () {
    /// Texte d'un widget identifié par sa clé — la valeur EXACTE affichée.
    String texteDe(WidgetTester tester, String cle) =>
        tester.widget<Text>(find.byKey(Key(cle))).data!;

    /// Sélectionne le séjour de l'essai.
    Future<void> selectionner(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('pos-sejour-res-1')));
      await tester.pumpAndSettle();
    }

    /// Ajoute la Béninoise 33 cl (1 000 FCFA) au panier du séjour sélectionné.
    Future<void> ajouterBiere(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('pos-article-M5:bsn-33')));
      await tester.pumpAndSettle();
    }

    testWidgets('l’en-tête dit le titre de la vue et deux indicateurs à zéro', (
      tester,
    ) async {
      await monter(tester, const EcranPosHeberges());

      expect(find.text('Point de vente — clients hébergés'), findsOneWidget);
      expect(
        find.text(
          'Le panier reste ouvert de l’arrivée au départ. Bar, restaurant, '
          'tourisme et location y entrent ensemble — un seul panier, une '
          'seule facture à la clôture.',
        ),
        findsOneWidget,
      );
      // Les indicateurs se lisent des paniers RÉELS : aucun panier, « 0 ».
      expect(
        find.descendant(
          of: find.byKey(const Key('pos-kpi-paniers')),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('pos-kpi-encours')),
          matching: find.text('0 FCFA'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('le séjour est listé sans panier, sans bouton « ouvrir »', (
      tester,
    ) async {
      await monter(tester, const EcranPosHeberges());

      expect(find.text('Séjours en cours'), findsOneWidget);
      expect(find.text('Un panier par séjour, jamais deux.'), findsOneWidget);
      expect(find.byKey(const Key('pos-sejour-res-1')), findsOneWidget);
      expect(find.text('KORA'), findsOneWidget);
      expect(find.text('AUCUN PANIER'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('AUCUN PANIER')).style!.color,
        Ardoise.c500,
      );
      expect(find.text('BNG-01 · Départ prévu le 12/10/2026'), findsOneWidget);
      // La vue n'a pas de bouton « ouvrir le panier » : le geste est celui de
      // l'article (l.152).
      expect(find.byKey(const Key('pos-ouvrir-res-1')), findsNothing);
      expect(
        texteDe(tester, 'pos-aucun-panier-selectionne'),
        'Sélectionnez un séjour à gauche pour voir ou ouvrir son panier.',
      );
    });

    testWidgets('sélectionner un séjour n’écrit AUCUN panier', (tester) async {
      await monter(tester, const EcranPosHeberges());
      await selectionner(tester);

      // L'en-tête du panneau prend la date de départ du séjour.
      expect(find.text('Départ prévu le 12/10/2026'), findsOneWidget);
      expect(
        texteDe(tester, 'pos-panier-vide'),
        'Panier ouvert, aucune consommation. Choisissez un article dans le '
        'catalogue.',
      );
      expect(
        await depotPanier.paniers(),
        isEmpty,
        reason: 'un panier ne naît qu’au premier article, jamais d’un clic',
      );
    });

    testWidgets('le premier article OUVRE le panier du séjour et s’y ajoute', (
      tester,
    ) async {
      await monter(tester, const EcranPosHeberges());
      await selectionner(tester);
      await ajouterBiere(tester);

      final panier = (await depotPanier.paniers()).single;
      expect(panier.typeVente, TypeVente.surSejour);
      expect(panier.reservationId, 'res-1');
      expect(panier.clientNom, 'KORA');
      expect(panier.lignes, hasLength(1));
      expect(panier.total, 1000);

      // L'écran restitue la base : badge, total du panneau, ligne de liste,
      // indicateurs de l'en-tête.
      expect(find.text('PANIER OUVERT'), findsOneWidget);
      expect(find.text('AUCUN PANIER'), findsNothing);
      // Vert quand le panier est ouvert, gris sinon (l.105, l.107).
      expect(
        tester.widget<Text>(find.text('PANIER OUVERT')).style!.color,
        PaletteMaitre.emeraude700,
      );
      final pastille = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('PANIER OUVERT'),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (pastille.decoration! as BoxDecoration).color,
        PaletteMaitre.emeraude50,
      );
      expect(texteDe(tester, 'pos-total'), '1 000 FCFA');
      expect(find.text('1 000 FCFA · 1'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('pos-kpi-paniers')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('pos-kpi-encours')),
          matching: find.text('1 000 FCFA'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('sans séjour sélectionné, un article n’ajoute rien', (
      tester,
    ) async {
      await monter(tester, const EcranPosHeberges());
      // L'article reste VISIBLE mais inerte (`@disabled`, l.154).
      expect(
        tester
            .widget<InkWell>(find.byKey(const Key('pos-article-M5:bsn-33')))
            .onTap,
        isNull,
      );
      await tester.tap(
        find.byKey(const Key('pos-article-M5:bsn-33')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(await depotPanier.paniers(), isEmpty);
    });

    testWidgets('sous « Tout », une recherche sans résultat garde la phrase '
        'de la vue', (tester) async {
      // Le rayon Restaurant est vide PAR CONSTRUCTION, mais son motif ne se dit
      // que sur sa pastille : ici, la cause est la recherche.
      await monter(tester, const EcranPosHeberges());
      await tester.enterText(find.byKey(const Key('pos-recherche')), 'zzz');
      await tester.pumpAndSettle();

      expect(
        texteDe(tester, 'pos-catalogue-vide'),
        'Aucun article ne correspond à cette recherche.',
      );
    });

    testWidgets('Q2 — un second article rejoint LE panier, jamais un second', (
      tester,
    ) async {
      await monter(tester, const EcranPosHeberges());
      await selectionner(tester);
      await ajouterBiere(tester);
      await tester.tap(find.byKey(const Key('pos-article-M9:cir-1')));
      await tester.pumpAndSettle();

      final paniers = await depotPanier.paniers();
      expect(paniers, hasLength(1));
      expect(paniers.single.lignes, hasLength(2));
      expect(paniers.single.total, 5500);
      // La mixité est restituée, pas séparée (règle 4).
      expect(find.text('Bar : 1 000 FCFA'), findsOneWidget);
      expect(find.text('Tourisme : 4 500 FCFA'), findsOneWidget);
      expect(texteDe(tester, 'pos-total'), '5 500 FCFA');
    });

    testWidgets('⚠ PA-79 — changer de pastille ne touche PAS le panier', (
      tester,
    ) async {
      await monter(tester, const EcranPosHeberges());
      await selectionner(tester);
      await ajouterBiere(tester);

      await tester.tap(find.byKey(const Key('pos-categorie-prestations')));
      await tester.pumpAndSettle();

      // Le filtre filtre : seule la prestation reste visible.
      expect(find.byKey(const Key('pos-article-M9:cir-1')), findsOneWidget);
      expect(find.byKey(const Key('pos-article-M5:bsn-33')), findsNothing);
      final panier = (await depotPanier.paniers()).single;
      expect(panier.lignes, hasLength(1));
      expect(panier.total, 1000);
    });

    testWidgets('la recherche et la pastille s’appliquent ENSEMBLE', (
      tester,
    ) async {
      await monter(tester, const EcranPosHeberges());
      await tester.enterText(
        find.byKey(const Key('pos-recherche')),
        'Cascades',
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pos-article-M9:cir-1')), findsOneWidget);
      expect(find.byKey(const Key('pos-article-M5:bsn-33')), findsNothing);

      // Pastille « Bar » + terme « Cascades » : l'intersection est vide, et la
      // phrase de la vue le dit.
      await tester.tap(find.byKey(const Key('pos-categorie-bar')));
      await tester.pumpAndSettle();
      expect(
        texteDe(tester, 'pos-catalogue-vide'),
        'Aucun article ne correspond à cette recherche.',
      );
    });

    testWidgets('la pastille Restauration dit POURQUOI elle est vide', (
      tester,
    ) async {
      // Le catalogue du restaurant de ce poste est vide (M4 est local depuis le
      // 09/10/2026). Un onglet présent et vide sans explication passerait pour
      // cassé (leçon PA-90).
      await monter(tester, const EcranPosHeberges());
      await tester.tap(find.byKey(const Key('pos-categorie-restauration')));
      await tester.pumpAndSettle();

      expect(texteDe(tester, 'pos-catalogue-vide'), contains('Aucun plat'));
    });

    testWidgets('« + », « − » et « ✕ » ajustent la ligne, le total suit', (
      tester,
    ) async {
      await monter(tester, const EcranPosHeberges());
      await selectionner(tester);
      await ajouterBiere(tester);
      final ligne = (await depotPanier.paniers()).single.lignes.single;

      await tester.tap(find.byKey(Key('pos-plus-${ligne.id}')));
      await tester.pumpAndSettle();
      expect((await depotPanier.paniers()).single.lignes.single.quantite, 2);
      expect(texteDe(tester, 'pos-total'), '2 000 FCFA');

      await tester.tap(find.byKey(Key('pos-moins-${ligne.id}')));
      await tester.pumpAndSettle();
      expect((await depotPanier.paniers()).single.lignes.single.quantite, 1);
      expect(texteDe(tester, 'pos-total'), '1 000 FCFA');

      await tester.tap(find.byKey(Key('pos-retirer-${ligne.id}')));
      await tester.pumpAndSettle();
      final apres = (await depotPanier.paniers()).single;
      expect(apres.lignes, isEmpty);
      expect(texteDe(tester, 'pos-total'), '0 FCFA');
      // Le panier reste OUVERT et vide : la vue n'a aucun geste d'annulation.
      expect(apres.statut, StatutPanier.ouvert);
      // Panier ouvert mais VIDÉ : rien à facturer, le bouton est grisé.
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('pos-cloturer')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('⚠ Q3 — l’hébergement n’entre PAS dans le total du panier', (
      tester,
    ) async {
      // Le panneau de droite ne totalise que les consommations ; les nuitées
      // sont dans la modale de clôture, nommées à part.
      await monter(tester, const EcranPosHeberges());
      await selectionner(tester);
      await ajouterBiere(tester);

      expect(texteDe(tester, 'pos-total'), '1 000 FCFA');
      expect(find.textContaining('84 000'), findsNothing);
    });

    testWidgets('la remise dit qu’elle n’agit pas, et ne change rien', (
      tester,
    ) async {
      await monter(tester, const EcranPosHeberges());
      await selectionner(tester);
      await ajouterBiere(tester);

      await tester.tap(find.byKey(const Key('pos-remise-type')));
      await tester.pump();

      const message =
          'La remise ne s’applique pas sur ce poste : le panier de séjour ne '
          'porte aucune remise, donc le total facturé reste le total des '
          'lignes. Rien n’a été enregistré.';
      expect(PanierHeberges.remiseNonDisponible, message);
      expect(find.text(message), findsOneWidget);
      expect(texteDe(tester, 'pos-total'), '1 000 FCFA');
      expect((await depotPanier.paniers()).single.total, 1000);
    });

    testWidgets('« Clôturer et facturer » est grisé tant que le panier est '
        'vide', (tester) async {
      await monter(tester, const EcranPosHeberges());
      await selectionner(tester);

      final bouton = tester.widget<FilledButton>(
        find.byKey(const Key('pos-cloturer')),
      );
      expect(bouton.onPressed, isNull);
    });

    testWidgets('la clôture OUVRE le récapitulatif, sans rien clôturer', (
      tester,
    ) async {
      await monter(tester, const EcranPosHeberges());
      await selectionner(tester);
      await ajouterBiere(tester);

      await tester.tap(find.byKey(const Key('pos-cloturer')));
      await tester.pumpAndSettle();

      expect(find.text('Clôturer avant le départ ?'), findsOneWidget);
      expect(
        find.text(
          'Aucune consommation ne pourra plus être enregistrée pour ce séjour.',
        ),
        findsOneWidget,
      );
      expect(find.text(ModaleClotureSejour.detail), findsOneWidget);
      // Trois nuits du 09 au 12/10/2026 à 28 000, puis la bière : deux
      // montants NOMMÉS, jamais un total opaque (Q3).
      expect(texteDe(tester, 'cloture-nuitees'), '3 nuitée(s) × 28 000 FCFA');
      expect(find.text('84 000 FCFA'), findsOneWidget);
      expect(find.text('Béninoise 33cl × 1'), findsOneWidget);
      expect(texteDe(tester, 'cloture-total-facture'), '85 000 FCFA');
      // La case « Payer séparément » n'existe pas ici.
      expect(find.textContaining('Payer séparément'), findsNothing);
      expect(
        await depotPanier.panierOuvertPour('res-1'),
        isNotNull,
        reason: 'rien n’est clôturé tant que « Facture » n’est pas pressé',
      );
    });

    testWidgets('« Annuler » referme la modale : le panier survit', (
      tester,
    ) async {
      await monter(tester, const EcranPosHeberges());
      await selectionner(tester);
      await ajouterBiere(tester);
      await tester.tap(find.byKey(const Key('pos-cloturer')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cloture-annuler')));
      await tester.pumpAndSettle();

      expect(find.text('Clôturer avant le départ ?'), findsNothing);
      final panier = await depotPanier.panierOuvertPour('res-1');
      expect(panier, isNotNull);
      expect(panier!.statut, StatutPanier.ouvert);
    });

    testWidgets('« Facture » clôture à 1 000 et émet nuitées + consommations', (
      tester,
    ) async {
      await monter(tester, const EcranPosHeberges());
      await selectionner(tester);
      await ajouterBiere(tester);
      // La prémisse du cas : sans confirmation, le dépôt REFUSE cette
      // clôture (règle 5). Seule la modale la confirme.
      final ouvert = (await depotPanier.paniers()).single;
      await expectLater(
        depotPanier.cloturer(ouvert.id, auteurId: caissierDeVente),
        throwsA(isA<ClotureAnticipeeNonConfirmee>()),
      );
      await tester.tap(find.byKey(const Key('pos-cloturer')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('pos-confirmer-cloture-anticipee')),
      );
      await tester.pumpAndSettle();

      expect(await depotPanier.panierOuvertPour('res-1'), isNull);
      final cloture = (await depotPanier.paniers()).single;
      expect(cloture.statut, StatutPanier.cloture);
      expect(cloture.montantCloture, 1000);

      // UNE pièce, deux lignes : la nuitée d'abord, la consommation ensuite.
      final pieces = await db.select(db.piecesFacturationLocal).get();
      expect(pieces, hasLength(1));
      final lignes = await db.select(db.lignesPieceFacturationLocal).get();
      expect(lignes.map((l) => l.libelle).toList(), [
        startsWith('Hébergement — 3 nuit(s)'),
        'Béninoise 33cl',
      ]);
    });

    testWidgets('la phrase du panier dit « enregistré sur ce poste »', (
      tester,
    ) async {
      // Annoncer « en attente de synchronisation » serait un indicateur
      // affirmant un état qu'il n'a pas vérifié (PA-59/60/61) : `paniers`
      // n'est pas au registre des tables synchronisables du serveur.
      await monter(tester, const EcranPosHeberges());

      const attendu =
          'Panier ouvert de l’arrivée au départ : il survit au changement '
          'd’équipe et à la fermeture de l’application. Enregistré sur ce '
          'poste — il ne part vers aucun autre.';
      expect(PanierHeberges.surCePoste, attendu);
      expect(find.text(attendu), findsOneWidget);
      expect(attendu, isNot(contains('en attente de synchronisation')));
    });

    testWidgets('sans droit d’écriture, le séjour se consulte mais rien ne '
        's’ajoute', (tester) async {
      await monter(
        tester,
        const EcranPosHeberges(),
        droits: GardeAcces.depuisJson(const {'M5': 'L', 'M1': 'L'}),
      );
      await selectionner(tester);
      await tester.tap(
        find.byKey(const Key('pos-article-M5:bsn-33')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('Départ prévu le 12/10/2026'), findsOneWidget);
      expect(
        tester
            .widget<InkWell>(find.byKey(const Key('pos-article-M5:bsn-33')))
            .onTap,
        isNull,
      );
      expect(await depotPanier.paniers(), isEmpty);
    });
  });
}
