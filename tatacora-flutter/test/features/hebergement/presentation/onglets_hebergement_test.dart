import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_colors.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_repository_local.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/service_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/presentation/ecran_hebergement.dart';
import 'package:tatacora_flutter/features/hebergement/presentation/providers_hebergement.dart';

/// Les quatre onglets de la vue `hebergement/hebergement.blade.php`.
///
/// ⚠ **CE FICHIER A CHANGÉ DE SUJET DEUX FOIS, ET L'ANCIEN ÉTAIT DEVENU FAUX.**
///
/// - Le 14/09/2026, il cessait de vérifier que le plan REFUSE le CRUD du parc :
///   le poste est zéro réseau, le parc se saisit sur le poste (PA-128).
/// - Le 09/10/2026, il cesse de vérifier le bloc gris « Ce que le plan de la
///   PWA propose et qui n'est pas rendu ici » : la vue ne le rend pas, et sa
///   directive du Product Owner du 02/09/2026 dit « un écran dit ce qu'il
///   FAIT ». Les refus vivent dans le code (voir le dernier cas, qui relit la
///   source). Les boutons « Effectuer Check-In Client » et « Effectuer
///   Check-Out » EXISTENT désormais, et disent ce qu'ils ne peuvent pas
///   (`plan_hebergement_test.dart`).
///
/// ## L'horloge est FIXÉE
///
/// Le 9 octobre 2026 à 10 h. Un état de séjour (à venir, en cours, terminé) et
/// la grille du mois dépendent de la date du jour : lue sur l'horloge réelle,
/// un cas passerait un mois et échouerait le suivant sans qu'aucun code n'ait
/// changé.
///
/// Le détail du plan — libellés, création, verrou d'archivage — vit dans
/// `plan_hebergement_test.dart`, celui de « Disponibilités » dans
/// `disponibilites_hebergement_test.dart`.
void main() {
  late AppDatabase db;
  late ReservationRepositoryLocal depot;

  const uniteId = 'u-bng-01';

  /// Le 9 octobre 2026, un vendredi : le 1er est un JEUDI (trois cases vides
  /// avant lui dans la grille).
  final maintenant = DateTime(2026, 10, 9, 10);

  setUp(() async {
    db = AppDatabase.enMemoire();
    depot = ReservationRepositoryLocal(ReservationDao(db));

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
    for (final numero in const ['BNG-01', 'BNG-02']) {
      await db
          .into(db.unitesHebergementLocal)
          .insert(
            UnitesHebergementLocalCompanion.insert(
              id: numero == 'BNG-01' ? uniteId : 'u-bng-02',
              categorieId: 'cat-1',
              numero: numero,
              statut: 'libre',
            ),
          );
    }
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

  /// Une réservation exprimée en jours à partir du 9 octobre.
  Future<Reservation> enBase({
    required int dansNJours,
    required int puisNJours,
    String id = '',
    String unite = uniteId,
    StatutReservation statut = StatutReservation.confirmee,
    List<LigneService>? lignes,
  }) {
    final arrivee = maintenant.add(Duration(days: dansNJours));
    final depart = maintenant.add(Duration(days: puisNJours));
    final cle = id.isEmpty ? 'res-$dansNJours-$puisNJours' : id;

    return depot.enregistrer(
      Reservation(
        id: cle,
        reference: 'LOC-$cle',
        clientId: 'cli-1',
        clientNom: 'KORA Jean',
        uniteId: unite,
        periode: PeriodeSejour(arrivee: arrivee, depart: depart),
        tarifNuit: 28000,
        statut: statut,
        statutSynchronisation: StatutSynchronisation.local,
        creeeLe: maintenant,
        lignes:
            lignes ??
            [
              LigneService(
                id: 'l-$cle',
                service: ServiceReservation.hebergement,
                itemId: unite,
                libelle: 'Bungalow (BNG-01)',
                prixUnitaire: 28000,
                quantite: (puisNJours - dansNJours).abs(),
              ),
            ],
      ),
    );
  }

  Future<void> monter(
    WidgetTester tester, {
    GardeAcces? droits,
    double largeur = 1500,
  }) async {
    tester.view.physicalSize = Size(largeur, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final conteneur = ProviderContainer(
      overrides: [
        depotReservationProvider.overrideWithValue(depot),
        baseLocaleProvider.overrideWithValue(db),
        horlogeHebergementProvider.overrideWithValue(() => maintenant),
        droitsProvider.overrideWithValue(
          droits ?? GardeAcces.depuisJson(const {'M1': 'C', 'M3': 'C'}),
        ),
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

  Future<void> ouvrir(WidgetTester tester, String onglet) async {
    await tester.tap(find.byKey(Key('onglet-$onglet')));
    await tester.pumpAndSettle();
  }

  /// Les `Text` sous une clé, lus d'un seul tenant.
  String texteDe(WidgetTester tester, Key cle) => tester
      .widgetList<Text>(
        find.descendant(of: find.byKey(cle), matching: find.byType(Text)),
      )
      .map((t) => t.data ?? '')
      .join();

  /* ================================================================== */
  group('L’en-tête', () {
    testWidgets('les quatre onglets de la vue sont là, dans son ordre', (
      tester,
    ) async {
      await monter(tester);

      const ordre = [
        ('plan', "Plan d'Hébergement"),
        ('reservations', 'Réservations en cours'),
        ('calendrier', "Calendrier d'Occupation"),
        ('disponibilites', 'Disponibilités'),
      ];
      var gauche = -1.0;
      for (final (cle, libelle) in ordre) {
        final onglet = find.byKey(Key('onglet-$cle'));
        expect(onglet, findsOneWidget, reason: 'onglet « $libelle »');
        expect(
          find.descendant(of: onglet, matching: find.text(libelle)),
          findsOneWidget,
        );
        final x = tester.getTopLeft(onglet).dx;
        expect(x, greaterThan(gauche), reason: '« $libelle » est mal ordonné');
        gauche = x;
      }
    });

    testWidgets('le sous-titre est celui de la vue, RG-01 comprise', (
      tester,
    ) async {
      await monter(tester);

      expect(
        find.text(
          "Gestion du plan d'hébergement du Gîte Chez Noël (Bungalows, "
          'Chambres, Tentes) • Règle anti-double réservation',
        ),
        findsOneWidget,
      );
      expect(find.text('Hébergement & Réservations'), findsOneWidget);
    });

    testWidgets('les onglets sont à DROITE du titre, comme la vue (lg)', (
      tester,
    ) async {
      await monter(tester);

      final titre = tester.getTopLeft(find.text('Hébergement & Réservations'));
      final plan = tester.getTopLeft(find.byKey(const Key('onglet-plan')));
      // Sur une ligne : le premier onglet est à droite du titre, pas dessous.
      expect(plan.dx, greaterThan(titre.dx + 200));
      expect(plan.dy, lessThan(titre.dy + 120));
    });

    testWidgets(
      'sous le point de rupture lg, les onglets passent SOUS le titre',
      (tester) async {
        await monter(tester, largeur: 900);

        final titre = tester.getTopLeft(
          find.text('Hébergement & Réservations'),
        );
        final plan = tester.getTopLeft(find.byKey(const Key('onglet-plan')));
        expect(plan.dy, greaterThan(titre.dy + 20));
      },
    );

    testWidgets('les deux boutons de la vue, et le second suit le droit', (
      tester,
    ) async {
      await monter(tester);
      expect(
        find.byKey(const Key('bouton-nouvelle-reservation-m1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('bouton-ajouter-hebergement-entete')),
        findsOneWidget,
      );
    });

    testWidgets('l’onglet actif est plein navy et sans bordure', (
      tester,
    ) async {
      await monter(tester);

      BoxDecoration decoration(String cle) {
        final conteneur = find.descendant(
          of: find.byKey(Key('onglet-$cle')),
          matching: find.byType(Container),
        );
        return tester.widget<Container>(conteneur.first).decoration!
            as BoxDecoration;
      }

      final actif = decoration('plan');
      expect(actif.color, AppColors.navy);
      expect(actif.border, isNull);

      final inactif = decoration('reservations');
      expect(inactif.color, AppColors.neutre0);
      expect(inactif.border, isNotNull);
    });
  });

  /* ================================================================== */
  group('Les panneaux', () {
    testWidgets('le premier onglet montre le PARC, et il se saisit', (
      tester,
    ) async {
      await monter(tester);

      // La grille de cartes de la vue, une par unité du parc.
      expect(find.byKey(const Key('plan-carte-$uniteId')), findsOneWidget);
      expect(find.text('BNG-01'), findsOneWidget);
      expect(find.text('BNG-02'), findsOneWidget);
      expect(find.byKey(const Key('plan-ajouter')), findsOneWidget);
    });

    testWidgets('un seul panneau à la fois, et chacun s’ouvre au clic', (
      tester,
    ) async {
      await monter(tester);

      expect(find.byKey(const Key('plan-carte-$uniteId')), findsOneWidget);
      expect(find.text('Disponibilités sur une période'), findsNothing);

      await ouvrir(tester, 'disponibilites');
      expect(find.text('Disponibilités sur une période'), findsOneWidget);
      expect(find.byKey(const Key('plan-carte-$uniteId')), findsNothing);

      await ouvrir(tester, 'calendrier');
      expect(find.byKey(const Key('calendrier-mois')), findsOneWidget);
      expect(find.text('Disponibilités sur une période'), findsNothing);

      await ouvrir(tester, 'reservations');
      expect(find.text('CLIENT'), findsOneWidget);

      await ouvrir(tester, 'plan');
      expect(find.byKey(const Key('plan-carte-$uniteId')), findsOneWidget);
    });

    testWidgets('changer d’onglet ne perd pas les données', (tester) async {
      await enBase(dansNJours: 10, puisNJours: 12);
      await monter(tester);

      await ouvrir(tester, 'calendrier');
      await ouvrir(tester, 'reservations');

      expect(find.text('KORA Jean'), findsOneWidget);
    });

    testWidgets('l’unité libre porte « Réserver cette unité »', (tester) async {
      await monter(tester);

      expect(
        find.byKey(const Key('plan-reserver-$uniteId')),
        findsOneWidget,
        reason: 'une unité libre doit pouvoir être réservée depuis sa carte',
      );
      expect(find.text('Réserver cette unité'), findsNWidgets(2));
    });
  });

  /* ================================================================== */
  group('« Réservations en cours »', () {
    testWidgets('les cinq en-têtes sont en MAJUSCULES, comme la vue', (
      tester,
    ) async {
      await monter(tester);
      await ouvrir(tester, 'reservations');

      for (final entete in const [
        'CLIENT',
        'UNITÉ(S) RÉSERVÉE(S)',
        'ARRIVÉE',
        'DÉPART',
        'STATUT',
      ]) {
        expect(find.text(entete), findsOneWidget, reason: entete);
      }
    });

    testWidgets('une ligne porte le client, l’unité figée, les dates, l’état', (
      tester,
    ) async {
      await enBase(dansNJours: 10, puisNJours: 12);
      await monter(tester);
      await ouvrir(tester, 'reservations');

      // Les lignes se cherchent par leur CONTENU : la clé d'un `DataRow` n'est
      // pas celle d'un widget.
      expect(find.text('KORA Jean'), findsOneWidget);
      // Le libellé FIGÉ de la ligne, avec son nombre de nuits.
      expect(find.text('Bungalow (BNG-01) × 2n'), findsOneWidget);
      expect(find.text('19/10/2026'), findsOneWidget);
      expect(find.text('21/10/2026'), findsOneWidget);
      expect(find.byKey(const Key('en-cours-etat-a_venir')), findsOneWidget);
    });

    testWidgets('les quatre états portent les MOTS de la vue (l.386-391)', (
      tester,
    ) async {
      await enBase(dansNJours: -10, puisNJours: -8); // terminé
      await enBase(dansNJours: -1, puisNJours: 1); // en cours
      await enBase(dansNJours: 10, puisNJours: 12); // à venir
      await enBase(
        dansNJours: 20,
        puisNJours: 22,
        statut: StatutReservation.annulee,
      );
      await monter(tester);
      await ouvrir(tester, 'reservations');

      String libelle(String code) => tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(Key('en-cours-etat-$code')),
              matching: find.byType(Text),
            ),
          )
          .data!;

      // « Terminé » au masculin : c'est la vue, pas le panneau Historique.
      expect(libelle('termine'), 'Terminé');
      expect(libelle('en_cours'), 'En cours');
      expect(libelle('a_venir'), 'À venir');
      expect(libelle('annulee'), 'Annulée');
    });

    testWidgets('les couleurs d’état sont celles de la vue, opaques', (
      tester,
    ) async {
      await enBase(dansNJours: -1, puisNJours: 1);
      await monter(tester);
      await ouvrir(tester, 'reservations');

      final pastille = tester.widget<Container>(
        find.byKey(const Key('en-cours-etat-en_cours')),
      );
      final decoration = pastille.decoration! as BoxDecoration;
      // `#E8F5E9` : le fond opaque du badge vert, pas l'alpha de `succesFond`.
      expect(decoration.color, AppColors.badgeVertFond);
    });

    testWidgets('une fiche SANS hébergement n’y figure pas', (tester) async {
      // L'onglet répond à « qui occupe mes chambres ? ». Un circuit seul n'en
      // retient aucune.
      await enBase(
        dansNJours: 10,
        puisNJours: 12,
        lignes: const [
          LigneService(
            id: 'l-tour',
            service: ServiceReservation.tourisme,
            itemId: 'c-1',
            libelle: 'Cascades de Tanougou',
            prixUnitaire: 15000,
            quantite: 2,
          ),
        ],
      );
      await monter(tester);
      await ouvrir(tester, 'reservations');

      expect(find.byKey(const Key('en-cours-vide')), findsOneWidget);
      // L'état vide du maître porte sa porte de sortie.
      expect(find.byKey(const Key('en-cours-creer')), findsOneWidget);
    });

    testWidgets('l’état vide dit les quatre phrases de la vue (l.401-411)', (
      tester,
    ) async {
      await monter(tester);
      await ouvrir(tester, 'reservations');

      expect(find.text('Aucun résultat'), findsOneWidget);
      expect(
        find.text('Essayez de modifier votre recherche ou vos filtres.'),
        findsOneWidget,
      );
      expect(
        find.text("Aucune réservation d'hébergement pour le moment."),
        findsOneWidget,
      );
      expect(find.text('Créer une réservation →'), findsOneWidget);
      // L'en-tête reste SOUS lequel la ligne vide se range, et le pied dit
      // zéro — jamais un compte absent.
      expect(find.text('CLIENT'), findsOneWidget);
      expect(
        texteDe(tester, const Key('en-cours-decompte')),
        'Affichage de 0-0 sur 0',
      );
    });

    testWidgets('dix lignes par page : le décompte et les liens de la vue', (
      tester,
    ) async {
      for (var i = 0; i < 11; i++) {
        await enBase(dansNJours: 20 + i * 3, puisNJours: 21 + i * 3);
      }
      await monter(tester);
      await ouvrir(tester, 'reservations');

      expect(
        texteDe(tester, const Key('en-cours-decompte')),
        'Affichage de 1-10 sur 11',
      );
      expect(find.text('Page 1 / 2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('en-cours-suivant')));
      await tester.pumpAndSettle();

      expect(
        texteDe(tester, const Key('en-cours-decompte')),
        'Affichage de 11-11 sur 11',
      );
      expect(find.text('Page 2 / 2'), findsOneWidget);
    });

    testWidgets('sans seconde page, AUCUN lien de pagination', (tester) async {
      await enBase(dansNJours: 10, puisNJours: 12);
      await monter(tester);
      await ouvrir(tester, 'reservations');

      // `@if ($paginator->hasPages())` : la vue ne rend pas la barre.
      expect(find.byKey(const Key('en-cours-suivant')), findsNothing);
      expect(find.byKey(const Key('en-cours-precedent')), findsNothing);
      expect(
        texteDe(tester, const Key('en-cours-decompte')),
        'Affichage de 1-1 sur 1',
      );
    });
  });

  /* ================================================================== */
  group('« Calendrier d’Occupation »', () {
    testWidgets('le mois, la légende, les initiales et la mention ESTIMÉ', (
      tester,
    ) async {
      await monter(tester);
      await ouvrir(tester, 'calendrier');

      expect(
        tester.widget<Text>(find.byKey(const Key('calendrier-mois'))).data,
        'octobre 2026',
      );
      for (final mot in const [
        'Faible',
        'Moyen',
        'Fort',
        'Lun',
        'Mar',
        'Mer',
        'Jeu',
        'Ven',
        'Sam',
        'Dim',
      ]) {
        expect(find.text(mot), findsOneWidget, reason: mot);
      }
      // La mention de la vue, au mot : un taux présenté comme exact serait lu
      // comme un relevé de présence. Le parc est de DEUX unités.
      expect(
        tester.widget<Text>(find.byKey(const Key('calendrier-mention'))).data,
        "Taux d'occupation estimé par jour, calculé à partir des réservations "
        "d'hébergement enregistrées (2 unités au total).",
      );
    });

    testWidgets('le 1er du mois tombe sous « Jeu » (octobre 2026)', (
      tester,
    ) async {
      await monter(tester);
      await ouvrir(tester, 'calendrier');

      // Sans les trois cases vides du début, tout le mois glisserait de trois
      // jours (l.449-455).
      final jeu = tester.getCenter(find.text('Jeu')).dx;
      final premier = tester.getCenter(find.byKey(const Key('jour-1'))).dx;
      expect(premier, closeTo(jeu, 1));
      // Et le 2 est dans la colonne suivante (« Ven »).
      expect(
        tester.getCenter(find.byKey(const Key('jour-2'))).dx,
        closeTo(tester.getCenter(find.text('Ven')).dx, 1),
      );
    });

    testWidgets('le compte N/total et la teinte suivent les paliers de la vue', (
      tester,
    ) async {
      // Unité 1 du 12 au 14 (nuits du 12 et du 13) ; unité 2 du 13 au 15
      // (nuits du 13 et du 14).
      await enBase(dansNJours: 3, puisNJours: 5, id: 'a');
      await enBase(dansNJours: 4, puisNJours: 6, id: 'b', unite: 'u-bng-02');
      await monter(tester);
      await ouvrir(tester, 'calendrier');

      String compte(int jour) =>
          tester.widget<Text>(find.byKey(Key('occupation-$jour'))).data!;
      Color? fond(int jour) =>
          (tester.widget<Container>(find.byKey(Key('jour-$jour'))).decoration!
                  as BoxDecoration)
              .color;

      expect(compte(12), '1/2');
      expect(compte(13), '2/2');
      expect(compte(14), '1/2');
      // Le jour du départ ne compte pas (bornes semi-ouvertes) : 15 est libre.
      expect(find.byKey(const Key('occupation-15')), findsNothing);

      // 1/2 = 50 % : ni `< 0.5` (vert) ; c'est le palier doré. 2/2 : rouge.
      expect(fond(12), AppColors.reserveGoldFond);
      expect(fond(13), AppColors.badgeRougeFond);
      expect(fond(15), JetonsCssMaitre.neutre50);
    });

    testWidgets('un seul jour porte la bordure navy épaisse : aujourd’hui', (
      tester,
    ) async {
      await monter(tester);
      await ouvrir(tester, 'calendrier');

      BoxBorder? bordure(int jour) =>
          (tester.widget<Container>(find.byKey(Key('jour-$jour'))).decoration!
                  as BoxDecoration)
              .border;

      final auj = bordure(9)! as Border;
      expect(auj.top.color, AppColors.navy);
      expect(auj.top.width, 2);
      final autre = bordure(10)! as Border;
      expect(autre.top.width, 1);
    });
  });

  /* ================================================================== */
  testWidgets('les refus de la vue sont écrits DANS le code, datés', (
    tester,
  ) async {
    // Le bloc gris qui les affichait sous le plan est retiré (la vue ne le
    // rend pas) : ses raisons doivent survivre ailleurs que dans la mémoire de
    // quelqu'un. Cette garde relit la source (une garde de test relit sa
    // source).
    await monter(tester);
    expect(find.byKey(const Key('m1-blocs-absents')), findsNothing);
    expect(
      find.textContaining('Ce que le plan de la PWA propose'),
      findsNothing,
    );

    final source = File(
      'lib/features/hebergement/presentation/ecran_hebergement.dart',
    ).readAsStringSync();
    expect(source.length, greaterThan(2000), reason: 'la source est relue');
    for (final refus in const [
      'Effectuer Check-In Client',
      'Effectuer Check-Out',
      'Réservation rapide',
      'Importer',
      '09/10/2026',
    ]) {
      expect(source, contains(refus), reason: 'refus « $refus » non écrit');
    }
    // Les raisons périmées ne reviennent pas (PA-144).
    expect(source, isNot(contains('BlocsAbsentsHebergement')));
    expect(source, isNot(contains('PERSONNE')));
  });
}
