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
import 'package:tatacora_flutter/features/hebergement/domain/entities/fiche_reservation.dart'
    show TypeRemise;
import 'package:tatacora_flutter/features/pos/domain/messages_ventes.dart';
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

    testWidgets('REMISE au comptoir (21/10/2026) : « FCFA » puis une valeur — '
        'le total devient le net, « Sur un total de » dit le brut, « Aucune » '
        'la retire', (tester) async {
      await monter(tester, const EcranPosComptant());
      await tester.tap(find.byKey(const Key('pos-comptant-ouvrir')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pos-article-M5:bsn-33')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pos-remise-appliquee')), findsNothing);

      await tester.tap(find.byKey(const Key('pos-remise-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('FCFA').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('pos-remise-valeur')), '250');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('pos-total'))).data,
        '750 FCFA',
      );
      expect(find.text('Sur un total de 1 000 FCFA'), findsOneWidget);
      expect(find.text('- 250 FCFA'), findsOneWidget);

      await tester.tap(find.byKey(const Key('pos-remise-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aucune').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('pos-total'))).data,
        '1 000 FCFA',
      );
      expect(find.byKey(const Key('pos-remise-appliquee')), findsNothing);
      expect(
        (await depotPanier.paniers()).single.remiseType,
        TypeRemise.aucune,
      );
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

    testWidgets('l’encaissement OUVRE « Vente encaissée » (total, 3 boutons), '
        'puis le journal du jour liste la vente et l’ANNULE avec son '
        'motif', (tester) async {
      await ouvrirLaCaisseDuComptoir(db);
      await monter(tester, const EcranPosComptant());
      await tester.tap(find.byKey(const Key('pos-comptant-ouvrir')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pos-article-M5:bsn-33')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pos-cloturer')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('modale-vente-encaissee')), findsOneWidget);
      expect(find.text('PRIX UNITAIRE'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('vente-encaissee-total')))
            .data,
        contains('1 000'),
      );
      expect(
        find.byKey(const Key('vente-encaissee-ticket-80')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('vente-encaissee-facture')), findsOneWidget);
      await tester.tap(find.byKey(const Key('vente-encaissee-fermer')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('modale-vente-encaissee')), findsNothing);

      // Le journal du jour : la vente y est, « annuler » exige un motif.
      await tester.tap(find.byKey(const Key('caisse-journal')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('modale-journal-du-jour')), findsOneWidget);
      final id = (await depotPanier.paniers()).single.id;
      expect(find.byKey(Key('journal-vente-$id')), findsOneWidget);

      await tester.tap(find.byKey(Key('journal-annuler-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('annulation-vente-confirmer')));
      await tester.pumpAndSettle();
      expect(
        find.text(MessagesVentes.motifAnnulationObligatoire),
        findsOneWidget,
        reason: 'sans motif, le refus est dit sous le champ',
      );
      expect(
        (await depotPanier.paniers()).single.statut,
        isNot(StatutPanier.annule),
      );

      await tester.enterText(
        find.byKey(const Key('annulation-vente-motif')),
        'erreur de saisie',
      );
      await tester.tap(find.byKey(const Key('annulation-vente-confirmer')));
      await tester.pumpAndSettle();
      expect((await depotPanier.paniers()).single.statut, StatutPanier.annule);
      expect(find.byKey(const Key('annulation-vente-message')), findsOneWidget);
      expect(find.byKey(Key('journal-annulee-$id')), findsOneWidget);
    });

    testWidgets('⚠ PA-79 — changer de filtre ne vide PAS le panier', (
      tester,
    ) async {
      // Le défaut : le sélecteur de catalogue désignait aussi la caisse, si
      // bien qu'un client prenant une bière puis un plat perdait sa première
      // ligne — et l'addition unique qu'il demandait devenait impossible.
      await db
          .into(db.menusLocal)
          .insert(
            MenusLocalCompanion.insert(
              id: 'm-1',
              libelle: 'Carte',
              type: 'local',
              creeLe: DateTime(2026, 10, 1),
              creePar: caissierDeVente,
            ),
          );
      await db
          .into(db.recettesLocal)
          .insert(
            RecettesLocalCompanion.insert(
              id: 'r-1',
              libelle: 'Fiche',
              creeLe: DateTime(2026, 10, 1),
              creePar: caissierDeVente,
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
              creePar: caissierDeVente,
            ),
          );
      await monter(
        tester,
        const EcranPosComptant(),
        droits: GardeAcces.depuisJson(const {'M5': 'C', 'M4': 'C'}),
      );

      await tester.tap(find.byKey(const Key('pos-comptant-ouvrir')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pos-article-M5:bsn-33')));
      await tester.pumpAndSettle();

      // On change de rayon — le geste qui vidait le panier. Le rayon est un
      // SÉLECTEUR depuis le POS en trois colonnes (14/10/2026).
      await choisirRayon(tester, 'M4');

      final panier = (await depotPanier.paniers()).single;
      expect(
        panier.lignes,
        hasLength(1),
        reason: 'le filtre est un filtre, pas une caisse',
      );

      // Et l'article de l'autre rayon rejoint le MÊME panier (règle 4).
      await tester.tap(find.byKey(const Key('pos-article-M4:p-1')));
      await tester.pumpAndSettle();

      final apres = (await depotPanier.paniers()).single;
      expect(apres.lignes, hasLength(2));
      expect(apres.total, 3500);
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

    testWidgets('TOURISME et LOCATION (26/10/2026) : AUCUN rayon, AUCUNE carte '
        'au comptoir — même avec un circuit et un véhicule en base', (
      tester,
    ) async {
      // Directive du PO : « il faut enlever cette catégorie de la sélection ».
      // Le circuit `cir-1` (semé par `setUp`) et ce véhicule EXISTENT au
      // catalogue local ; le comptoir ne les propose pas. Aucune carte
      // grisée non plus : elles n'existent plus.
      await db
          .into(db.vehiculesLocal)
          .insert(
            VehiculesLocalCompanion.insert(
              id: 'veh-1',
              categorie: '4x4',
              immatriculation: 'AB-123-CD',
              tarifJour: 65000,
              statut: 'disponible',
            ),
          );
      await ouvrirLaCaisseDuComptoir(db);
      await monter(
        tester,
        const EcranPosComptant(),
        droits: GardeAcces.depuisJson(const {'M5': 'C', 'M8': 'C', 'M9': 'C'}),
      );
      await tester.tap(find.byKey(const Key('pos-comptant-ouvrir')));
      await tester.pumpAndSettle();

      // La bière, elle, est bien là : le catalogue n'est pas vide pour autant.
      expect(find.byKey(const Key('pos-article-M5:bsn-33')), findsOneWidget);
      expect(find.byKey(const Key('pos-article-M9:cir-1')), findsNothing);
      expect(find.byKey(const Key('pos-article-M8:veh-1')), findsNothing);
      expect(find.textContaining('Cascades de Tanougou'), findsNothing);
      expect(find.textContaining('AB-123-CD'), findsNothing);

      // Le sélecteur de famille ne propose que « Tout », Bar et Restaurant.
      await tester.tap(find.byKey(const Key('pos-famille')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pos-rayon-M5')), findsWidgets);
      expect(find.byKey(const Key('pos-rayon-M4')), findsWidgets);
      expect(find.byKey(const Key('pos-rayon-M9')), findsNothing);
      expect(find.byKey(const Key('pos-rayon-M8')), findsNothing);
      expect(find.text('Tourisme'), findsNothing);
      expect(find.text('Location'), findsNothing);

      // Une recherche ne les ressort pas non plus (elle ignore le rayon actif).
      await tester.tap(find.byKey(const Key('pos-rayon-tout')).last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('pos-recherche')),
        'Cascades',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pos-article-M9:cir-1')), findsNothing);
      expect((await depotPanier.paniers()).single.lignes, isEmpty);
    });

    group('panneau Panier : « Vider » et « Abandonner » (26/10/2026)', () {
      // La vue (`comptant.blade.php` l.322-325) pose les deux boutons dans
      // l'en-tête du panneau, TOUJOURS, sans condition ni confirmation :
      // `wire:click="viderPanier"` / `"abandonnerPanier"`.
      Finder vider() => find.byKey(const Key('pos-vider-panier'));
      Finder abandonner() => find.byKey(const Key('pos-abandonner-panier'));

      bool actif(WidgetTester tester, Finder f) =>
          tester.widget<InkWell>(f).onTap != null;

      testWidgets('présents dès l’ouverture de l’écran, AVANT tout panier, '
          'aux mots de la vue', (tester) async {
        await monter(tester, const EcranPosComptant());

        expect(vider(), findsOneWidget);
        expect(abandonner(), findsOneWidget);
        expect(
          find.descendant(of: vider(), matching: find.text('Vider')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: abandonner(), matching: find.text('Abandonner')),
          findsOneWidget,
        );
        expect(actif(tester, vider()), isTrue);
        expect(actif(tester, abandonner()), isTrue);
        expect(await depotPanier.paniers(), isEmpty);
      });

      testWidgets('sans panier ouvert : « Vider » ne fait rien, aucun panier '
          'n’est créé', (tester) async {
        await monter(tester, const EcranPosComptant());

        await tester.tap(vider());
        await tester.pumpAndSettle();

        expect(await depotPanier.paniers(), isEmpty);
        expect(find.byType(SnackBar), findsNothing);
      });

      testWidgets('sans panier ouvert : « Abandonner » dit « Panier '
          'abandonné. » et n’écrit rien', (tester) async {
        await monter(tester, const EcranPosComptant());

        await tester.tap(abandonner());
        await tester.pumpAndSettle();

        expect(find.text('Panier abandonné.'), findsOneWidget);
        expect(await depotPanier.paniers(), isEmpty);
      });

      testWidgets(
        '« Vider » retire TOUTES les lignes, SANS confirmation, et le '
        'panier reste ouvert',
        (tester) async {
          await monter(tester, const EcranPosComptant());
          await tester.tap(find.byKey(const Key('pos-comptant-ouvrir')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('pos-article-M5:bsn-33')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('pos-article-M5:bsn-33')));
          await tester.pumpAndSettle();
          expect(actif(tester, vider()), isTrue);

          await tester.tap(vider());
          await tester.pumpAndSettle();

          expect(find.byType(AlertDialog), findsNothing);
          final panier = (await depotPanier.paniers()).single;
          expect(panier.lignes, isEmpty);
          expect(panier.estOuvert, isTrue);
          // Le panneau reste celui d'un panier OUVERT, boutons compris.
          expect(vider(), findsOneWidget);
          expect(abandonner(), findsOneWidget);
        },
      );

      testWidgets('« Vider » reste actif sur un panier ouvert encore vide '
          '(la vue ne le grise jamais)', (tester) async {
        await monter(tester, const EcranPosComptant());
        await tester.tap(find.byKey(const Key('pos-comptant-ouvrir')));
        await tester.pumpAndSettle();

        expect(actif(tester, vider()), isTrue);
        await tester.tap(vider());
        await tester.pumpAndSettle();
        expect((await depotPanier.paniers()).single.estOuvert, isTrue);
      });

      testWidgets('« Abandonner » ferme le panier ouvert SANS motif demandé, '
          'garde ses lignes et rend le comptoir', (tester) async {
        await monter(tester, const EcranPosComptant());
        await tester.tap(find.byKey(const Key('pos-comptant-ouvrir')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('pos-article-M5:bsn-33')));
        await tester.pumpAndSettle();

        await tester.tap(abandonner());
        await tester.pumpAndSettle();

        // Pas de dialogue de motif : la vue n'en pose aucun.
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byKey(const Key('pos-motif-annulation')), findsNothing);
        expect(find.text('Panier abandonné.'), findsOneWidget);

        final panier = (await depotPanier.paniers()).single;
        expect(panier.estOuvert, isFalse);
        expect(panier.statut, StatutPanier.annule);
        expect(panier.motifAnnulation, MessagesVentes.motifAbandon);
        expect(panier.lignes, hasLength(1));
        // Le panneau est revenu à « aucun panier ouvert », boutons compris.
        expect(find.byKey(const Key('pos-comptant-ouvrir')), findsOneWidget);
        expect(vider(), findsOneWidget);
        expect(abandonner(), findsOneWidget);
      });

      testWidgets('droits identiques à la vue (écriture sur M5) : sans eux, '
          'les deux boutons sont inertes', (tester) async {
        await monter(
          tester,
          const EcranPosComptant(),
          droits: GardeAcces.depuisJson(const {'M5': 'L'}),
        );

        expect(vider(), findsOneWidget);
        expect(abandonner(), findsOneWidget);
        expect(actif(tester, vider()), isFalse);
        expect(actif(tester, abandonner()), isFalse);
      });

      testWidgets('un panier déjà fermé ailleurs : le refus est dit à la '
          'phrase du serveur', (tester) async {
        await monter(tester, const EcranPosComptant());
        await tester.tap(find.byKey(const Key('pos-comptant-ouvrir')));
        await tester.pumpAndSettle();
        final p = (await depotPanier.paniers()).single;
        // Une autre fenêtre encaisse le panier sous les pieds de l'écran.
        await cloturerSansPiece(db, p.id, mode: 'especes');

        await tester.tap(vider());
        await tester.pumpAndSettle();

        expect(find.text(MessagesVentes.panierClotureImmuable), findsOneWidget);
      });
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
          'Le panier reste ouvert de l’arrivée au départ. Bar et restaurant '
          'y entrent ensemble — un seul panier, une seule facture à la '
          'clôture.',
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

    testWidgets('Q2 — un second article rejoint LE panier, jamais un second '
        '(et le circuit en base n’est PAS proposé)', (tester) async {
      await monter(tester, const EcranPosHeberges());
      await selectionner(tester);
      await ajouterBiere(tester);
      // Tourisme et location ne sont plus proposés (26/10/2026) : ni carte
      // grisée, ni phrase de refus, ni pastille — le circuit `cir-1` existe
      // pourtant au catalogue local.
      expect(find.byKey(const Key('pos-article-M9:cir-1')), findsNothing);
      expect(
        find.byKey(const Key('pos-prestation-refusee-cir-1')),
        findsNothing,
      );
      expect(find.byKey(const Key('pos-categorie-prestations')), findsNothing);
      expect(find.textContaining('Tourisme'), findsNothing);
      expect(find.textContaining('Location'), findsNothing);

      var paniers = await depotPanier.paniers();
      expect(paniers, hasLength(1));
      expect(paniers.single.lignes, hasLength(1));

      // Un second article rejoint le MÊME panier.
      await ajouterBiere(tester);
      paniers = await depotPanier.paniers();
      expect(paniers, hasLength(1));
      expect(paniers.single.lignes.single.quantite, 2);
      expect(paniers.single.total, 2000);
      expect(texteDe(tester, 'pos-total'), '2 000 FCFA');
    });

    testWidgets('⚠ PA-79 — changer de pastille ne touche PAS le panier', (
      tester,
    ) async {
      await monter(tester, const EcranPosHeberges());
      await selectionner(tester);
      await ajouterBiere(tester);

      await tester.tap(find.byKey(const Key('pos-categorie-restauration')));
      await tester.pumpAndSettle();

      // Le filtre filtre : la bière n'est plus affichée, mais elle reste au
      // panier.
      expect(find.byKey(const Key('pos-article-M5:bsn-33')), findsNothing);
      final panier = (await depotPanier.paniers()).single;
      expect(panier.lignes, hasLength(1));
      expect(panier.total, 1000);
    });

    testWidgets('les pastilles sont Tout, Bar et Restauration — plus de '
        '« Tourisme & location » (26/10/2026)', (tester) async {
      await monter(tester, const EcranPosHeberges());

      expect(find.byKey(const Key('pos-categorie-tout')), findsOneWidget);
      expect(find.byKey(const Key('pos-categorie-bar')), findsOneWidget);
      expect(
        find.byKey(const Key('pos-categorie-restauration')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('pos-categorie-prestations')), findsNothing);
      expect(find.text('Tourisme & location'), findsNothing);
    });

    testWidgets('la recherche et la pastille s’appliquent ENSEMBLE', (
      tester,
    ) async {
      await monter(tester, const EcranPosHeberges());
      await tester.enterText(find.byKey(const Key('pos-recherche')), 'Bénin');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pos-article-M5:bsn-33')), findsOneWidget);

      // Pastille « Bar » + un terme qui n'est pas au bar : l'intersection est
      // vide, et la phrase de la vue le dit.
      await tester.tap(find.byKey(const Key('pos-categorie-bar')));
      await tester.enterText(find.byKey(const Key('pos-recherche')), 'Riz');
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

    testWidgets('la remise du séjour s’applique : le net remplace le total, '
        'la ligne dit le brut et la remise', (tester) async {
      await monter(tester, const EcranPosHeberges());
      await selectionner(tester);
      await ajouterBiere(tester);

      await tester.tap(find.byKey(const Key('pos-remise-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('%').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('pos-remise-valeur')), '10');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(texteDe(tester, 'pos-total'), '900 FCFA');
      expect(find.text('Sur un total de 1 000 FCFA'), findsOneWidget);
      expect(find.text('- 100 FCFA'), findsOneWidget);
      final p = (await depotPanier.paniers()).single;
      expect(p.remiseType, TypeRemise.pourcentage);
      expect(p.remiseValeurCentiemes, 1000);
      expect(p.total, 1000, reason: 'les lignes restent au prix brut');
    });

    testWidgets('une remise hors bornes est refusée SOUS la ligne, avec la '
        'phrase du serveur, et rien n’est posé', (tester) async {
      await monter(tester, const EcranPosHeberges());
      await selectionner(tester);
      await ajouterBiere(tester);

      await tester.tap(find.byKey(const Key('pos-remise-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('%').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('pos-remise-valeur')), '120');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        texteDe(tester, 'pos-remise-erreur'),
        MessagesVentes.remisePourcentageHorsBornes,
      );
      expect(texteDe(tester, 'pos-total'), '1 000 FCFA');
      expect(
        (await depotPanier.paniers()).single.remiseType,
        TypeRemise.aucune,
      );
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
      // La case « Payer séparément » existe, DÉCOCHÉE : la facture porte
      // l'hébergement ET les consommations, et le rappel n'est pas affiché.
      expect(
        find.text(ModaleClotureSejour.payerSeparementLibelle),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Checkbox>(
              find.descendant(
                of: find.byKey(const Key('cloture-payer-separement')),
                matching: find.byType(Checkbox),
              ),
            )
            .value,
        isFalse,
      );
      expect(find.byKey(const Key('cloture-rappel-hebergement')), findsNothing);
      expect(
        await depotPanier.panierOuvertPour('res-1'),
        isNotNull,
        reason: 'rien n’est clôturé tant que « Facture » n’est pas pressé',
      );
    });

    testWidgets('« Payer séparément » COCHÉE : le rappel de l’hébergement '
        'apparaît et le total facturé ne porte plus que les consommations', (
      tester,
    ) async {
      await monter(tester, const EcranPosHeberges());
      await selectionner(tester);
      await ajouterBiere(tester);
      await tester.tap(find.byKey(const Key('pos-cloturer')));
      await tester.pumpAndSettle();

      expect(texteDe(tester, 'cloture-total-facture'), '85 000 FCFA');
      await tester.tap(find.byKey(const Key('cloture-payer-separement')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('cloture-rappel-hebergement')),
        findsOneWidget,
      );
      expect(
        find.textContaining('resteront dues sur la fiche du client'),
        findsOneWidget,
      );
      expect(texteDe(tester, 'cloture-total-facture'), '1 000 FCFA');

      // Rien n'est clôturé tant que « Facture » n'est pas pressé.
      expect(await depotPanier.panierOuvertPour('res-1'), isNotNull);

      // Décocher rend l'hébergement à la facture.
      await tester.tap(find.byKey(const Key('cloture-payer-separement')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cloture-rappel-hebergement')), findsNothing);
      expect(texteDe(tester, 'cloture-total-facture'), '85 000 FCFA');
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
