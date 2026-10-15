import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_dao.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/achats/domain/messages_achats.dart';
import 'package:tatacora_flutter/features/hebergement/data/parc_dao.dart';
import 'package:tatacora_flutter/features/hebergement/domain/refus_parc.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/etat_du_jour.dart';
import 'package:tatacora_flutter/features/hebergement/impression/etat_parc.dart';
import 'package:tatacora_flutter/features/hebergement/presentation/widgets/vue_plan_hebergement.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_repository_local.dart';
import 'package:tatacora_flutter/features/hebergement/presentation/ecran_hebergement.dart';
import 'package:tatacora_flutter/features/hebergement/presentation/providers_hebergement.dart';

/// L'onglet « Plan d'Hébergement » — les libellés de la vue, et le CRUD réel.
///
/// ## Ce que ces cas protègent
///
/// Jusqu'au 14/09/2026 cet onglet REFUSAIT le CRUD du parc, et les cas de
/// `onglets_hebergement_test.dart` vérifiaient ce refus. Le poste est zéro
/// réseau : le parc n'avait plus aucun auteur, et un poste neuf ne pouvait
/// prendre aucune réservation (PA-128). Ces cas vérifient désormais l'inverse —
/// que le parc se saisit, et que le verrou d'archivage mord.
///
/// Les libellés sont ceux de `lang/fr`, **apostrophe DROITE comprise** : la vue
/// l'écrit 581 fois contre 39 typographiques, et le comparateur de conformité
/// ne replie pas l'une sur l'autre.
void main() {
  late AppDatabase db;
  late ReservationRepositoryLocal depot;
  late ParcDao parc;

  setUp(() async {
    db = AppDatabase.enMemoire();
    depot = ReservationRepositoryLocal(ReservationDao(db));
    parc = ParcDao(db);

    await db
        .into(db.clientsLocal)
        .insert(
          ClientsLocalCompanion.insert(
            id: 'cli-1',
            nom: 'KORA',
            prenom: const Value('Jean'),
            telephone: '+229 01 00 00 00 01',
            typeClient: 'particulier',
          ),
        );
  });

  tearDown(() => db.close());

  /// Le texte de tous les `Text` sous la clé, dans l'ordre de lecture : la vue
  /// pose son décompte en morceaux (« Affichage de », « 1-1 », « sur », « 1 »),
  /// et la phrase se lit d'un seul tenant.
  String texteDe(WidgetTester tester, Key cle) => tester
      .widgetList<Text>(
        find.descendant(of: find.byKey(cle), matching: find.byType(Text)),
      )
      .map((t) => t.data ?? '')
      .join();

  /// Ouvre la bascule « Suppression d'un enregistrement » (Paramètres) : sans
  /// elle, la vue ne rend aucun bouton d'archivage d'unité (13/10/2026).
  Future<void> ouvrirSuppression() => ParametresDao(
    db,
  ).ecrire(const {'activation_suppression': 'true'}, auteurId: null);

  Future<String> uneUnite({String numero = 'BNG-01'}) async {
    final categories = await parc.categories();
    final categorie = categories.isNotEmpty
        ? categories.first
        : await parc.creerCategorie(
            libelle: 'Bungalow',
            capaciteMax: 2,
            tarifBase: 28000,
          );
    return parc.creerUnite(numero: numero, categorieId: categorie.id);
  }

  Future<void> monter(
    WidgetTester tester, {
    GardeAcces? droits,
    List<Override> surcharges = const [],
    Size taille = const Size(1500, 2600),
  }) async {
    // Assez large pour trois colonnes, assez haut pour que rien ne sorte du
    // champ : un `tap` qui vise hors fenêtre ne touche rien, et l'échec se lit
    // alors sur l'assertion suivante — qui désigne la mauvaise cause.
    tester.view.physicalSize = taille;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final conteneur = ProviderContainer(
      overrides: [
        depotReservationProvider.overrideWithValue(depot),
        baseLocaleProvider.overrideWithValue(db),
        droitsProvider.overrideWithValue(
          droits ?? GardeAcces.depuisJson(const {'M1': 'C', 'M3': 'C'}),
        ),
        ...surcharges,
      ],
    );
    addTearDown(conteneur.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: conteneur,
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranHebergement()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /* ================================================================== */
  group('Aucun débordement, quelle que soit la largeur (INSTRUCTION2.txt)', () {
    for (final largeur in [
      1500.0,
      1280.0,
      1100.0,
      1000.0,
      900.0,
      760.0,
      600.0,
      420.0,
    ]) {
      testWidgets(
        'à ${largeur.toInt()} px, des libellés LONGS ne débordent pas',
        (tester) async {
          final longue = await parc.creerCategorie(
            libelle: 'Chambre triple avec terrasse et vue sur la falaise',
            capaciteMax: 3,
            tarifBase: 1234567890,
          );
          await parc.creerUnite(
            numero: 'Amarante du Sénégal ou Coucal du Sénégal',
            categorieId: longue.id,
          );
          await parc.creerUnite(
            numero: 'AMARANTEDUSENEGALOUCOUCALDUSENEGALSANSESPACE',
            categorieId: longue.id,
          );
          await uneUnite(numero: 'BNG-01');

          await monter(tester, taille: Size(largeur, 2600));

          final erreur = tester.takeException();
          expect(
            erreur,
            isNull,
            // Le widget fautif et son fichier, pour savoir QUOI corriger.
            reason: erreur is FlutterError
                ? erreur.diagnostics.map((d) => d.toString()).join(' | ')
                : 'débordement à ${largeur.toInt()} px : $erreur',
          );
          expect(
            find.text('Amarante du Sénégal ou Coucal du Sénégal'),
            findsOneWidget,
          );

          // Les trois autres onglets, à la même largeur.
          for (final onglet in [
            'reservations',
            'calendrier',
            'disponibilites',
          ]) {
            await tester.tap(find.byKey(Key('onglet-$onglet')));
            await tester.pumpAndSettle();
            final autre = tester.takeException();
            expect(
              autre,
              isNull,
              reason: autre is FlutterError
                  ? '$onglet : ${autre.diagnostics.map((d) => d.toString()).join(' | ')}'
                  : '$onglet à ${largeur.toInt()} px : $autre',
            );
          }
        },
      );
    }
  });

  /* ================================================================== */
  group('Les libellés de la vue', () {
    testWidgets('la barre d’outils porte ses mots, au caractère près', (
      tester,
    ) async {
      await uneUnite();
      await monter(tester);

      // L'invite de recherche de la vue — apostrophe et points de suspension
      // compris. Les trois points sont ceux de la vue (« ... »), pas le
      // caractère « … » : les confondre est un écart d'un octet qui se voit.
      expect(
        find.text('Rechercher bungalow, chambre ou tente...'),
        findsOneWidget,
      );
      expect(find.text('Toutes les catégories'), findsOneWidget);
      // La vue pose ce bouton DEUX fois (l.109 et l.191) : au-dessus du plan,
      // et dans la barre d'outils du moteur CRUD. Un seul serait un écart.
      expect(find.text('Ajouter hébergement'), findsNWidgets(2));
      expect(
        find.byKey(const Key('bouton-ajouter-hebergement-entete')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('plan-ajouter')), findsOneWidget);
      expect(find.text('Générer & Télécharger'), findsOneWidget);
    });

    testWidgets('une carte porte le code, la catégorie et le tarif', (
      tester,
    ) async {
      final id = await uneUnite();
      await monter(tester);

      expect(find.byKey(Key('plan-carte-$id')), findsOneWidget);
      expect(find.text('BNG-01'), findsOneWidget);
      expect(find.text('Bungalow'), findsWidgets);
      // Le libellé exact de la vue, deux-points compris.
      expect(find.text('Tarif de base :'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(Key('plan-tarif-$id'))).data,
        '28 000 FCFA',
      );
    });

    testWidgets('la pastille dit « Libre », et le bouton propose de réserver', (
      tester,
    ) async {
      final id = await uneUnite();
      await monter(tester);

      // La pastille est un CALCUL sur les réservations (RG-02), pas la colonne
      // lue seule : sans réservation du jour, l'unité est libre.
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(Key('plan-pastille-$id')),
                matching: find.byType(Text),
              ),
            )
            .data,
        'Libre',
      );
      expect(find.text('Réserver cette unité'), findsOneWidget);
    });

    testWidgets('la pagination porte le décompte de la vue', (tester) async {
      await uneUnite();
      await monter(tester);

      expect(
        texteDe(tester, const Key('plan-decompte')),
        'Affichage de 1-1 sur 1',
      );
      expect(find.text('← Précédent'), findsOneWidget);
      expect(find.text('Suivant →'), findsOneWidget);
    });

    testWidgets('un parc vide le DIT, et offre la porte de sortie', (
      tester,
    ) async {
      await monter(tester);

      // Jusqu'à ce lot, ce message décrivait un état dont aucun chemin ne
      // permettait de sortir (PA-128). Le bouton compte autant que le texte.
      expect(find.byKey(const Key('plan-vide')), findsOneWidget);
      // La porte de sortie est celle de la barre d'outils : la vue ne pose
      // aucun bouton DANS l'état vide (l.326-329).
      expect(find.byKey(const Key('plan-ajouter')), findsOneWidget);
      expect(find.byKey(const Key('plan-vide-ajouter')), findsNothing);
      // Et la pagination n'est pas rendue sous un parc vide (l.330, `@else`).
      expect(find.byKey(const Key('plan-decompte')), findsNothing);
    });
  });

  /* ================================================================== */
  group('Créer une catégorie et une unité, depuis l’écran', () {
    testWidgets('la modale porte les libellés de la vue', (tester) async {
      await monter(tester);
      await tester.tap(find.byKey(const Key('plan-ajouter')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('modale-unite-titre'))).data,
        'Ajouter hébergement',
      );
      expect(
        find.text('Parc du Gîte Chez Noël — bungalows, chambres et tentes.'),
        findsOneWidget,
      );
      expect(find.text('Code unité'), findsOneWidget);
      expect(find.text('Ex. BNG-03'), findsOneWidget);
      expect(find.text('Catégorie'), findsOneWidget);
      expect(find.text('+ Nouvelle catégorie'), findsOneWidget);
      expect(find.text('Annuler'), findsOneWidget);
      expect(find.text('Enregistrer'), findsOneWidget);
    });

    testWidgets('une unité et sa catégorie sont réellement écrites', (
      tester,
    ) async {
      await monter(tester);
      await tester.tap(find.byKey(const Key('plan-ajouter')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('modale-unite-code')),
        'BNG-03',
      );
      await tester.tap(
        find.byKey(const Key('modale-unite-nouvelle-categorie')),
      );
      await tester.pumpAndSettle();

      // Les trois champs de la vue, avec leurs invites exactes.
      expect(
        find.text('Libellé de la catégorie (Bungalow, Chambre simple, Suite…)'),
        findsOneWidget,
      );
      expect(find.text('Tarif par nuit (FCFA)'), findsOneWidget);
      expect(find.text('Capacité (personnes)'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('modale-unite-categorie-libelle')),
        'Bungalow',
      );
      await tester.enterText(
        find.byKey(const Key('modale-unite-categorie-tarif')),
        '28000',
      );
      await tester.enterText(
        find.byKey(const Key('modale-unite-categorie-capacite')),
        '2',
      );
      await tester.tap(find.byKey(const Key('modale-unite-enregistrer')));
      await tester.pumpAndSettle();

      // EN BASE, pas seulement à l'écran : un écran qui affiche ce qu'il vient
      // de saisir ne prouve pas qu'il l'a écrit.
      final categories = await parc.categories();
      expect(categories, hasLength(1));
      expect(categories.single.tarifBase, 28000);
      expect(categories.single.capaciteMax, 2);

      final unites = await db.select(db.unitesHebergementLocal).get();
      expect(unites, hasLength(1));
      expect(unites.single.numero, 'BNG-03');
      expect(unites.single.statut, 'libre');

      // Et la grille s'est rafraîchie : sans invalidation, l'unité resterait
      // absente de l'écran alors qu'elle est en base, et on la ressaisirait.
      expect(find.text('BNG-03'), findsOneWidget);
    });

    testWidgets('un tarif nul est refusé, et la modale reste ouverte', (
      tester,
    ) async {
      await monter(tester);
      await tester.tap(find.byKey(const Key('plan-ajouter')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('modale-unite-code')),
        'BNG-04',
      );
      await tester.tap(
        find.byKey(const Key('modale-unite-nouvelle-categorie')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('modale-unite-categorie-libelle')),
        'Tente',
      );
      await tester.enterText(
        find.byKey(const Key('modale-unite-categorie-tarif')),
        '0',
      );
      await tester.enterText(
        find.byKey(const Key('modale-unite-categorie-capacite')),
        '2',
      );
      await tester.tap(find.byKey(const Key('modale-unite-enregistrer')));
      await tester.pumpAndSettle();

      // Fermer sur un refus ferait perdre la saisie.
      expect(find.byKey(const Key('modale-unite-enregistrer')), findsOneWidget);
      expect(await parc.categories(), isEmpty);
      expect(await db.select(db.unitesHebergementLocal).get(), isEmpty);
    });
  });

  /* ================================================================== */
  group('Archiver — le verrou est rendu à l’écran', () {
    testWidgets('une unité ENGAGÉE affiche « Archivage impossible »', (
      tester,
    ) async {
      final id = await uneUnite();
      final demain = DateTime.now().add(const Duration(days: 1));
      await db
          .into(db.reservationsLocal)
          .insert(
            ReservationsLocalCompanion.insert(
              id: 'res-1',
              reference: 'LOC-1',
              clientId: 'cli-1',
              uniteId: id,
              dateArrivee: DateTime.utc(demain.year, demain.month, demain.day),
              dateDepart: DateTime.utc(
                demain.year,
                demain.month,
                demain.day,
              ).add(const Duration(days: 2)),
              statut: 'confirmee',
              tarifNuit: 28000,
            ),
          );

      await ouvrirSuppression();
      await monter(tester);
      await tester.tap(find.byKey(Key('plan-archiver-$id')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('plan-archivage-impossible')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('plan-archivage-verrou')))
            .data,
        contains('Élément engagé dans 1 opération(s)'),
      );
      // Le bouton de confirmation DISPARAÎT : le laisser visible et inerte
      // laisserait croire à une panne.
      expect(find.byKey(const Key('plan-archivage-confirmer')), findsNothing);

      // Et rien n'a bougé en base.
      final unite = await (db.select(
        db.unitesHebergementLocal,
      )..where((u) => u.id.equals(id))).getSingle();
      expect(unite.statut, 'libre');
    });

    testWidgets('la bascule « Suppression » FERMÉE (son défaut) : aucun bouton '
        'd’archivage, même pour un administrateur — comme la vue', (
      tester,
    ) async {
      final id = await uneUnite();
      await monter(tester);
      expect(find.byKey(Key('plan-archiver-$id')), findsNothing);
      // Le reste de la carte est là : le geste est RETIRÉ, pas la carte.
      expect(find.byKey(Key('plan-modifier-$id')), findsOneWidget);
    });

    testWidgets('la bascule OUVERTE : le bouton d’archivage revient', (
      tester,
    ) async {
      final id = await uneUnite();
      await ouvrirSuppression();
      await monter(tester);
      expect(find.byKey(Key('plan-archiver-$id')), findsOneWidget);
    });

    testWidgets('une unité libre s’archive, et la vue le dit avec ses mots', (
      tester,
    ) async {
      final id = await uneUnite();
      await ouvrirSuppression();
      await monter(tester);
      await tester.tap(find.byKey(Key('plan-archiver-$id')));
      await tester.pumpAndSettle();

      expect(find.text('Confirmer la suppression'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('plan-archivage-question')))
            .data,
        "Voulez-vous archiver l'unité BNG-01 ?",
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('plan-archivage-rappel')))
            .data,
        "L'élément part aux archives et reste restaurable — rien n'est effacé.",
      );

      await tester.tap(find.byKey(const Key('plan-archivage-confirmer')));
      await tester.pumpAndSettle();

      // Archivée, pas supprimée — la ligne existe toujours.
      final unite = await (db.select(
        db.unitesHebergementLocal,
      )..where((u) => u.id.equals(id))).getSingleOrNull();
      expect(unite, isNotNull, reason: 'archiver n’est pas supprimer');
      expect(unite!.statut, 'hors_service');

      // La carte porte désormais « Hors service » et sa porte de retour.
      expect(find.text('Réintégrer au parc'), findsOneWidget);
      expect(find.text('Indisponible'), findsOneWidget);
    });

    testWidgets('la bascule refermée ENTRE l’ouverture de la modale et le '
        'clic : refus avec la phrase du serveur, rien n’est archivé — comme '
        '`exigerSuppressionOuverte()` au geste', (tester) async {
      final id = await uneUnite();
      await ouvrirSuppression();
      await monter(tester);
      await tester.tap(find.byKey(Key('plan-archiver-$id')));
      await tester.pumpAndSettle();
      // La modale est ouverte avec son bouton : la bascule était ouverte.
      expect(find.byKey(const Key('plan-archivage-confirmer')), findsOneWidget);

      // Un Administrateur la referme en Paramètres pendant que la modale est
      // ouverte.
      await ParametresDao(
        db,
      ).ecrire(const {'activation_suppression': 'false'}, auteurId: null);

      await tester.tap(find.byKey(const Key('plan-archivage-confirmer')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(find.byKey(const Key('plan-archivage-erreur')))
            .data,
        const SuppressionFermee().message,
      );
      // La modale reste ouverte : le refus se lit là où le geste a été tenté.
      expect(find.text('Confirmer la suppression'), findsOneWidget);
      final unite = await (db.select(
        db.unitesHebergementLocal,
      )..where((u) => u.id.equals(id))).getSingle();
      expect(unite.statut, 'libre', reason: 'un refus n’écrit rien');
    });

    test('la phrase du refus est celle du serveur (`pwa.archivage.'
        'refus_bascule`), relue par PHP au test des fournisseurs', () {
      // `MessagesAchats.refusBascule` est confrontée au PHP exécuté par
      // `archivage_contre_serveur_test.dart` : l'égalité ici ferme la chaîne.
      expect(const SuppressionFermee().message, MessagesAchats.refusBascule);
    });
  });

  /* ================================================================== */
  group('RBAC — premier niveau', () {
    testWidgets('sans droit d’écriture, aucun geste de parc n’est offert', (
      tester,
    ) async {
      final id = await uneUnite();
      await monter(tester, droits: GardeAcces.depuisJson(const {'M1': 'L'}));

      // Les boutons sont RETIRÉS, pas grisés : un bouton grisé invite à
      // cliquer et ne produit qu'un refus.
      expect(find.byKey(const Key('plan-ajouter')), findsNothing);
      expect(
        find.byKey(const Key('bouton-ajouter-hebergement-entete')),
        findsNothing,
      );
      expect(find.byKey(Key('plan-reserver-$id')), findsNothing);
      expect(find.byKey(Key('plan-modifier-$id')), findsNothing);
      expect(find.byKey(Key('plan-archiver-$id')), findsNothing);
      // La carte, elle, reste : consulter le parc est légitime en lecture.
      expect(find.byKey(Key('plan-carte-$id')), findsOneWidget);
      // L'export est une LECTURE du parc affiché : il reste offert (l.185).
      expect(find.byKey(const Key('plan-exporter')), findsOneWidget);
      // « Nouvelle réservation » mène à une fiche qui refuse elle-même : la
      // vue le pose pour tout le monde (l.99).
      expect(
        find.byKey(const Key('bouton-nouvelle-reservation-m1')),
        findsOneWidget,
      );
    });
  });

  /* ================================================================== */
  group('Le cycle de la carte (l.252-291)', () {
    Future<String> uneUniteAvecEtat(
      WidgetTester tester,
      EtatDuJour etat,
    ) async {
      final id = await uneUnite();
      await monter(
        tester,
        surcharges: [
          etatsDuJourProvider.overrideWith((ref) async => {id: etat}),
        ],
      );
      return id;
    }

    /// Le texte de la barre de notification affichée.
    String notification(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const Key('plan-cycle-message'))).data!;

    testWidgets('« Effectuer Check-In Client » est un bouton, et il DIT', (
      tester,
    ) async {
      final id = await uneUniteAvecEtat(tester, EtatDuJour.reservee);

      expect(find.text('Effectuer Check-In Client'), findsOneWidget);
      await tester.tap(find.byKey(Key('plan-checkin-$id')));
      await tester.pump();

      // Le check-in passe par `SejourDao` depuis le lot D (14/10/2026, D416).
      // Sans réservation du jour sur l'unité, le refus du composant
      // (`hebergement.checkin_impossible`) — jamais un bouton muet (Article 3.3).
      expect(
        notification(tester),
        "Aucune arrivée n'est attendue aujourd'hui sur l'unité BNG-01.",
      );
      expect(await db.select(db.sejoursLocal).get(), isEmpty);
      // Rien n'est écrit : le statut de l'unité n'a pas bougé.
      final unite = await (db.select(
        db.unitesHebergementLocal,
      )..where((u) => u.id.equals(id))).getSingle();
      expect(unite.statut, 'libre');
    });

    testWidgets('« Effectuer Check-Out » est un bouton, et il DIT', (
      tester,
    ) async {
      final id = await uneUniteAvecEtat(tester, EtatDuJour.occupee);

      expect(find.text('Effectuer Check-Out'), findsOneWidget);
      await tester.tap(find.byKey(Key('plan-checkout-$id')));
      await tester.pump();

      // Sans séjour en cours (`hebergement.checkout_impossible`, D416).
      expect(notification(tester), "Aucun séjour en cours sur l'unité BNG-01.");
    });

    testWidgets('« Marquer Nettoyé & Prêt » remet l’unité en service', (
      tester,
    ) async {
      final id = await uneUnite();
      await (db.update(
        db.unitesHebergementLocal,
      )..where((u) => u.id.equals(id))).write(
        const UnitesHebergementLocalCompanion(statut: Value('nettoyage')),
      );
      await monter(tester);

      expect(find.text('Nettoyage'), findsOneWidget);
      await tester.tap(find.byKey(Key('plan-nettoye-$id')));
      await tester.pumpAndSettle();

      final unite = await (db.select(
        db.unitesHebergementLocal,
      )..where((u) => u.id.equals(id))).getSingle();
      expect(unite.statut, 'libre');
      expect(find.text('Libre'), findsOneWidget);
    });

    testWidgets('sans état calculé, la pastille dit « — », jamais « Libre »', (
      tester,
    ) async {
      final id = await uneUnite();
      await monter(
        tester,
        surcharges: [etatsDuJourProvider.overrideWith((ref) async => {})],
      );

      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(Key('plan-pastille-$id')),
                matching: find.byType(Text),
              ),
            )
            .data,
        '—',
      );
      expect(find.text('Libre'), findsNothing);
      // Le bouton par défaut de la vue (`$etat['cle'] ?? 'hors_service'`) :
      // « Indisponible », et il ne réserve pas.
      expect(find.byKey(Key('plan-indisponible-$id')), findsOneWidget);
      expect(find.byKey(Key('plan-reserver-$id')), findsNothing);
    });
  });

  /* ================================================================== */
  group('Pagination et filtres', () {
    Future<void> onzeUnites() async {
      for (var i = 1; i <= 11; i++) {
        await uneUnite(numero: 'BNG-${i.toString().padLeft(2, '0')}');
      }
    }

    testWidgets('onze unités : dix cartes, puis une, avec le décompte', (
      tester,
    ) async {
      await onzeUnites();
      await monter(tester);

      expect(
        texteDe(tester, const Key('plan-decompte')),
        'Affichage de 1-10 sur 11',
      );
      expect(find.text('Page 1 / 2'), findsOneWidget);
      expect(find.text('BNG-10'), findsOneWidget);
      expect(find.text('BNG-11'), findsNothing);

      await tester.tap(find.byKey(const Key('plan-page-suivant')));
      await tester.pumpAndSettle();

      expect(
        texteDe(tester, const Key('plan-decompte')),
        'Affichage de 11-11 sur 11',
      );
      expect(find.text('Page 2 / 2'), findsOneWidget);
      expect(find.text('BNG-11'), findsOneWidget);
      expect(find.text('BNG-01'), findsNothing);
    });

    testWidgets('« Précédent » est inerte sur la première page', (
      tester,
    ) async {
      await onzeUnites();
      await monter(tester);

      await tester.tap(find.byKey(const Key('plan-page-precedent')));
      await tester.pumpAndSettle();

      // Inactif à 40 % d'opacité (`disabled:opacity-40`) : le clic ne change
      // pas de page, et la vue ne cache pas le bouton.
      expect(find.text('Page 1 / 2'), findsOneWidget);
    });

    testWidgets('la recherche porte sur le numéro, et revient en page 1', (
      tester,
    ) async {
      await onzeUnites();
      await monter(tester);
      await tester.tap(find.byKey(const Key('plan-page-suivant')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('plan-recherche')), 'BNG-05');
      await tester.pumpAndSettle();

      expect(
        texteDe(tester, const Key('plan-decompte')),
        'Affichage de 1-1 sur 1',
      );
      // Le numéro tapé figure aussi dans le champ : on compte les CARTES.
      final cartes = find.byWidgetPredicate(
        (w) => '${w.key}'.contains('plan-carte-'),
      );
      expect(cartes, findsOneWidget);
      expect(
        find.descendant(of: cartes, matching: find.text('BNG-05')),
        findsOneWidget,
      );
    });

    testWidgets('le filtre de catégorie ne garde que ses unités', (
      tester,
    ) async {
      await uneUnite(numero: 'BNG-01');
      final suite = await parc.creerCategorie(
        libelle: 'Suite',
        capaciteMax: 4,
        tarifBase: 60000,
      );
      await parc.creerUnite(numero: 'STE-01', categorieId: suite.id);
      await monter(tester);

      expect(
        texteDe(tester, const Key('plan-decompte')),
        'Affichage de 1-2 sur 2',
      );

      await tester.tap(find.byKey(const Key('plan-filtre-categorie')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Suite').last);
      await tester.pumpAndSettle();

      expect(
        texteDe(tester, const Key('plan-decompte')),
        'Affichage de 1-1 sur 1',
      );
      expect(find.text('STE-01'), findsOneWidget);
      expect(find.text('BNG-01'), findsNothing);
    });
  });

  /* ================================================================== */
  group('Le nombre de colonnes suit la FENÊTRE (l.226)', () {
    test('une, deux, puis trois colonnes aux points de rupture md et xl', () {
      // Les bornes de Tailwind : md = 768, xl = 1 280. La décision se prend
      // sur la fenêtre, jamais sur la largeur du contenu.
      expect(VuePlanHebergement.colonnesPour(767), 1);
      expect(VuePlanHebergement.colonnesPour(768), 2);
      expect(VuePlanHebergement.colonnesPour(1279), 2);
      expect(VuePlanHebergement.colonnesPour(1280), 3);
    });
  });

  /* ================================================================== */
  group('« Générer & Télécharger » — la modale de format de la vue', () {
    late List<EtatParc> exportes;

    Future<void> monterAvecExport(WidgetTester tester) async {
      exportes = [];
      await monter(
        tester,
        surcharges: [
          exporterParcProvider.overrideWithValue((etat) async {
            exportes.add(etat);
            return 'C:/export/parc.csv';
          }),
        ],
      );
    }

    Future<void> exporter(WidgetTester tester, {bool pdf = false}) async {
      await tester.tap(find.byKey(const Key('plan-exporter')));
      await tester.pumpAndSettle();
      // D434 : le PDF est présélectionné ; le tableur se choisit.
      if (!pdf) {
        await tester.tap(find.byKey(const Key('export-format-excel')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('export-generer')));
      await tester.pumpAndSettle();
    }

    testWidgets('la modale porte le titre et le sous-titre de la vue', (
      tester,
    ) async {
      await uneUnite();
      await monterAvecExport(tester);

      await tester.tap(find.byKey(const Key('plan-exporter')));
      await tester.pumpAndSettle();

      expect(find.text("Exporter — Unités d'hébergement"), findsOneWidget);
      expect(
        find.text("Le parc tel qu'il est affiché, filtres compris."),
        findsOneWidget,
      );
      // Le choix PAR DÉFAUT est le tableur, le seul qui s'écrive ; la ligne
      // d'aide le dit AVANT le clic.
      expect(
        tester.widget<Text>(find.byKey(const Key('export-aide'))).data,
        'Le PDF n’est pas produit sur ce poste : seul le tableur (CSV) est '
        'écrit.',
      );
    });

    testWidgets('le PDF est offert, et REFUSÉ avec son message', (
      tester,
    ) async {
      await uneUnite();
      await monterAvecExport(tester);

      await exporter(tester, pdf: true);

      expect(
        tester
            .widget<Text>(find.byKey(const Key('plan-export-pdf-absent')))
            .data,
        'Le PDF Officiel A4 du parc n’est pas produit sur ce poste : seul le '
        'tableur (CSV) est écrit. Rien n’a été exporté.',
      );
      expect(exportes, isEmpty);
    });

    testWidgets('le tableur emporte le parc ENTIER, toutes pages confondues', (
      tester,
    ) async {
      for (var i = 1; i <= 11; i++) {
        await uneUnite(numero: 'BNG-${i.toString().padLeft(2, '0')}');
      }
      await monterAvecExport(tester);

      await exporter(tester);

      // La vue exporte `parcFiltre()`, pas la page affichée (l.571-614).
      expect(exportes, hasLength(1));
      expect(exportes.single.unites, hasLength(11));
      expect(exportes.single.portee, 'Aucun filtre — parc complet');
      expect(
        tester.widget<Text>(find.byKey(const Key('plan-export-fait'))).data,
        'Export écrit : C:/export/parc.csv',
      );
    });

    testWidgets('l’export porte sur CE QUI EST AFFICHÉ, et DIT son filtre', (
      tester,
    ) async {
      await uneUnite(numero: 'BNG-01');
      await uneUnite(numero: 'BNG-02');
      await uneUnite(numero: 'BNG-03');
      await monterAvecExport(tester);

      await tester.enterText(find.byKey(const Key('plan-recherche')), 'BNG-02');
      await tester.pumpAndSettle();
      await exporter(tester);

      expect(exportes.single.unites.map((u) => u.numero), ['BNG-02']);
      expect(exportes.single.portee, 'BNG-02');
      // Et le fichier le dit, lui aussi.
      expect(exportes.single.csv(), contains('Filtre appliqué : BNG-02'));
      expect(exportes.single.csv(), isNot(contains('BNG-03')));
    });

    testWidgets('un parc filtré à vide REFUSE l’export, avec son message', (
      tester,
    ) async {
      await uneUnite();
      await monterAvecExport(tester);

      await tester.enterText(find.byKey(const Key('plan-recherche')), 'ZZZ');
      await tester.pumpAndSettle();
      await exporter(tester);

      expect(
        tester.widget<Text>(find.byKey(const Key('plan-export-vide'))).data,
        "Aucune unité ne correspond aux filtres : il n'y a rien à exporter.",
      );
      expect(exportes, isEmpty);
    });
  });
}
