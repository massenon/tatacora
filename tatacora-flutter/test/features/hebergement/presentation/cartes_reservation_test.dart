import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_repository_local.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/fiche_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/service_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/presentation/ecran_reservations.dart';
import 'package:tatacora_flutter/features/hebergement/presentation/fiche_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/presentation/providers_hebergement.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/article_vendable.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';

/// Les cartes de la grille — `reservations-services.js`,
/// `rendreCarteReservation()`.
///
/// Ce que ces cas protègent : une carte dit ce qu'un client doit, et de quoi
/// c'est fait. Un montant unique laisserait croire que la nuitée a changé de
/// prix ; un total dénormalisé sur la réservation deviendrait faux au premier
/// article ajouté depuis le point de vente.
void main() {
  late AppDatabase db;
  late ReservationRepositoryLocal depot;

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
    for (final (id, nom, prenom) in const [
      ('cli-1', 'KORA', 'Jean'),
      ('cli-2', 'DOSSOU', 'Marie'),
    ]) {
      await db
          .into(db.clientsLocal)
          .insert(
            ClientsLocalCompanion.insert(
              id: id,
              nom: nom,
              prenom: Value(prenom),
              telephone: '+229 01 00 00 00 0$id'.substring(0, 17),
              typeClient: 'particulier',
            ),
          );
    }
  });

  tearDown(() => db.close());

  LigneService ligne(
    ServiceReservation service, {
    required String id,
    required String libelle,
    int prix = 28000,
    int quantite = 2,
  }) => LigneService(
    id: id,
    service: service,
    itemId: service == ServiceReservation.hebergement ? 'u-1' : id,
    libelle: libelle,
    prixUnitaire: prix,
    quantite: quantite,
  );

  Future<Reservation> enBase({
    String id = 'res-1',
    String clientId = 'cli-1',
    String client = 'KORA Jean',
    int acompte = 0,
    TypeRemise? remiseType,
    num? remiseValeur,
    List<LigneService>? lignes,
    StatutReservation statut = StatutReservation.confirmee,
  }) => depot.enregistrer(
    Reservation(
      id: id,
      reference: 'LOC-$id',
      clientId: clientId,
      clientNom: client,
      uniteId: 'u-1',
      periode: PeriodeSejour(
        arrivee: DateTime.now().add(const Duration(days: 10)),
        depart: DateTime.now().add(const Duration(days: 12)),
      ),
      tarifNuit: 28000,
      statut: statut,
      statutSynchronisation: StatutSynchronisation.local,
      creeeLe: DateTime.now(),
      acompte: acompte,
      typeClient: TypeClient.agencePartenaire,
      canal: CanalReservation.booking,
      remiseType: remiseType,
      remiseValeur: remiseValeur,
      lignes:
          lignes ??
          [
            // L'identifiant de ligne porte celui de la réservation : deux
            // réservations semées dans le même test se heurteraient sinon sur
            // la clé primaire de `lignes_reservation_local`.
            ligne(
              ServiceReservation.hebergement,
              id: 'l-$id',
              libelle: 'Bungalow (BNG-01)',
            ),
          ],
    ),
  );

  /// Ouvre un panier de séjour et y met une consommation.
  Future<void> consommer(String reservationId, {int prix = 1200}) async {
    await db
        .into(db.cartesBoissonLocal)
        .insert(
          CartesBoissonLocalCompanion.insert(
            id: 'b-1',
            articleId: 'art-1',
            libelle: 'Bière Béninoise',
            categorie: 'locale',
            prixVente: prix.toDouble(),
          ),
        );

    final dao = PanierDao(db);
    final panier = await dao.ouvrir(
      typeVente: TypeVente.surSejour,
      pointVente: 'Bar',
      reservationId: reservationId,
    );
    await dao.ajouterLigne(
      panier.id,
      const ArticleVendable(
        reference: ReferenceCatalogue(
          module: ModuleVendable.m5Bar,
          code: 'b-1',
        ),
        libelle: 'Bière Béninoise',
        prix: 1200,
      ),
    );
  }

  Future<void> monter(WidgetTester tester, {GardeAcces? droits}) async {
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final conteneur = ProviderContainer(
      overrides: [
        depotReservationProvider.overrideWithValue(depot),
        baseLocaleProvider.overrideWithValue(db),
        droitsProvider.overrideWithValue(
          droits ?? GardeAcces.depuisJson(const {'M1': 'C'}),
        ),
      ],
    );
    addTearDown(conteneur.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: conteneur,
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranReservations()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /* ================================================================== */
  testWidgets('la carte porte l’identité du maître : type, canal, dates', (
    tester,
  ) async {
    await enBase();
    await monter(tester);

    expect(find.byKey(const Key('carte-res-1')), findsOneWidget);
    final identite = tester
        .widget<Text>(find.byKey(const Key('identite-res-1')))
        .data!;

    expect(identite, contains('Agence partenaire'));
    expect(identite, contains('Booking.com'));
    // « (:nombre nuit(s)) » — le mot de la vue (PA-185), pas un pluriel accordé.
    expect(identite, contains('2 nuit(s)'));
  });

  testWidgets('un canal absent s’écrit « — », jamais rien', (tester) async {
    // Une place vide se lit comme un oubli d'affichage ; un tiret dit qu'on
    // ne sait pas — et c'est une information, notamment pour l'analyse par
    // canal.
    await depot.enregistrer(
      Reservation(
        id: 'res-sans-canal',
        reference: 'LOC-X',
        clientId: 'cli-1',
        clientNom: 'KORA Jean',
        uniteId: 'u-1',
        periode: PeriodeSejour(
          arrivee: DateTime.now().add(const Duration(days: 10)),
          depart: DateTime.now().add(const Duration(days: 12)),
        ),
        tarifNuit: 28000,
        statut: StatutReservation.confirmee,
        statutSynchronisation: StatutSynchronisation.local,
        creeeLe: DateTime.now(),
      ),
    );
    await monter(tester);

    final identite = tester
        .widget<Text>(find.byKey(const Key('identite-res-sans-canal')))
        .data!;
    expect(identite, contains('—'));
  });

  testWidgets('une pastille par service, à sa couleur', (tester) async {
    await enBase(
      lignes: [
        ligne(
          ServiceReservation.hebergement,
          id: 'l-1',
          libelle: 'Bungalow (BNG-01)',
        ),
        ligne(
          ServiceReservation.tourisme,
          id: 'l-2',
          libelle: 'Cascades de Tanougou',
          prix: 15000,
        ),
      ],
    );
    await monter(tester);

    expect(find.byKey(const Key('pastille-res-1-hebergement')), findsOneWidget);
    expect(find.byKey(const Key('pastille-res-1-tourisme')), findsOneWidget);
    // Un service que la réservation ne porte pas n'a pas de pastille : une
    // pastille grise « non retenu » ferait chercher ce qui n'existe pas.
    expect(find.byKey(const Key('pastille-res-1-bar')), findsNothing);
  });

  testWidgets('la carte dit l’unité, comme la vue — pas le détail des lignes', (
    tester,
  ) async {
    // PA-185 (11/09/2026) : la carte de la vue écrit « Unité : BNG-01 —
    // Bungalow » (l.229-230) et ne détaille AUCUNE ligne. Le détail à quatre
    // lignes et son « + N autre(s) ligne(s) » venaient de l'ancien prototype.
    await enBase(
      lignes: [
        for (var i = 1; i <= 6; i++)
          ligne(
            i == 1 ? ServiceReservation.hebergement : ServiceReservation.bar,
            id: 'l-$i',
            libelle: 'Article $i',
            prix: 1000,
            quantite: 1,
          ),
      ],
    );
    await monter(tester);

    expect(
      tester.widget<Text>(find.byKey(const Key('unite-res-1'))).data,
      'Unité : BNG-01 — Bungalow',
    );
    expect(find.textContaining('Article 1'), findsNothing);
    expect(find.byKey(const Key('lignes-restantes-res-1')), findsNothing);
  });

  testWidgets('les quatre montants de la vue, et un tiret sans consommation', (
    tester,
  ) async {
    // Séjour, Consommations, Acompte versé, Reste à payer — la vue, l.242-259.
    // Sans panier ouvert, « Consommations » vaut « — » : un « 0 » se lirait
    // comme un panier ouvert et vide. Et toujours aucun « Total ».
    await enBase(acompte: 20000);
    await monter(tester);

    expect(find.byKey(const Key('sejour-res-1')), findsOneWidget);
    expect(find.byKey(const Key('consommations-res-1')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('consommations-res-1')),
        matching: find.text('—'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('acompte-res-1')), findsOneWidget);
    expect(find.byKey(const Key('reste-res-1')), findsOneWidget);
    expect(find.byKey(const Key('total-res-1')), findsNothing);
  });

  testWidgets('un panier ouvert donne ses consommations, sans total unique', (
    tester,
  ) async {
    await enBase();
    await consommer('res-1');
    await monter(tester);

    // 56 000 (séjour) et 1 200 (consommations) sur DEUX lignes. Aucun total
    // de 57 200 : un montant unique laisserait croire que la nuitée a changé
    // de prix (PA-112) — et la vue n'en affiche pas.
    expect(find.textContaining('56 000 FCFA'), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const Key('consommations-res-1')),
        matching: find.text('1 200 FCFA'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('57 200 FCFA'), findsNothing);
    expect(find.textContaining('panier ouvert'), findsNothing);
  });

  testWidgets('le reste dû tient compte de la remise ET de l’acompte', (
    tester,
  ) async {
    await enBase(
      acompte: 20000,
      remiseType: TypeRemise.pourcentage,
      remiseValeur: 10,
    );
    await monter(tester);

    // 56 000 − 10 % = 50 400 ; reste 30 400. Jusqu'au 25/08/2026, la remise
    // était ignorée du reste dû : on aurait réclamé au client l'argent qu'on
    // venait de lui accorder.
    expect(find.textContaining('50 400 FCFA'), findsWidgets);
    expect(find.textContaining('30 400 FCFA'), findsOneWidget);
  });

  testWidgets('aucun bouton de facture tant qu’aucune facture n’existe', (
    tester,
  ) async {
    // Un téléchargement qui ne pointe vers rien est pire qu'un bouton absent :
    // l'utilisateur clique, rien ne vient, et il ne sait pas si le document
    // manque ou si l'écran est cassé.
    await enBase();
    await monter(tester);

    expect(find.byKey(const Key('facture-res-1')), findsNothing);
  });

  testWidgets('la recherche filtre sur le NOM du client', (tester) async {
    await enBase();
    await enBase(id: 'res-2', clientId: 'cli-2', client: 'DOSSOU Marie');
    await monter(tester);

    expect(find.byKey(const Key('carte-res-1')), findsOneWidget);
    expect(find.byKey(const Key('carte-res-2')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('recherche-reservation')),
      'dossou',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('carte-res-1')), findsNothing);
    expect(find.byKey(const Key('carte-res-2')), findsOneWidget);
  });

  testWidgets('une recherche sans résultat DIT qu’il n’y a rien', (
    tester,
  ) async {
    await enBase();
    await monter(tester);

    await tester.enterText(
      find.byKey(const Key('recherche-reservation')),
      'zzz',
    );
    await tester.pumpAndSettle();

    // Une grille vide sans phrase se lit comme un écran cassé.
    expect(find.byKey(const Key('grille-vide')), findsOneWidget);
  });

  testWidgets('l’œil ouvre le détail, avec les sept champs de la vue', (
    tester,
  ) async {
    await enBase(acompte: 20000);
    await monter(tester);

    await tester.tap(find.byKey(const Key('voir-res-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('modale-detail-reservation')), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('titre-detail-reservation')))
          .data,
      'Détail — KORA Jean',
    );

    String valeur(String cle) =>
        tester.widget<Text>(find.byKey(Key('detail-$cle'))).data!;

    // Les champs de la vue, l.908-918 (PA-185).
    expect(valeur('unite'), 'BNG-01');
    expect(valeur('nuits'), '2');
    expect(valeur('acompte'), contains('20 000'));
    // Le statut STOCKÉ, par son code comme la vue ; l'état du jour DÉDUIT des
    // dates — arrivée dans dix jours, donc « À venir » (PA-111).
    expect(valeur('statut'), 'confirmee');
    expect(valeur('etat'), 'À venir');

    // Les champs de l'ancien prototype ne reviennent pas.
    expect(find.byKey(const Key('detail-client')), findsNothing);
    expect(find.byKey(const Key('detail-canal')), findsNothing);
    expect(find.text('LIGNES RÉSERVÉES'), findsNothing);
    expect(find.text('RÉCAPITULATIF'), findsNothing);
  });

  testWidgets('« Modifier » du détail ouvre la MÊME fiche, pré-remplie', (
    tester,
  ) async {
    await enBase();
    await monter(tester);

    await tester.tap(find.byKey(const Key('voir-res-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('modifier-detail-reservation')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('modale-detail-reservation')), findsNothing);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('titre-modale-reservation')))
          .data,
      'Modifier la réservation',
    );
  });

  testWidgets('avec le droit, le pied du détail est celui de la vue', (
    tester,
  ) async {
    await enBase();
    await monter(tester);

    await tester.tap(find.byKey(const Key('voir-res-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('annuler-detail-reservation')), findsOneWidget);
    expect(find.text('Annuler la réservation'), findsOneWidget);
    expect(find.byKey(const Key('fermer-detail-reservation')), findsOneWidget);
    expect(
      find.byKey(const Key('modifier-detail-reservation')),
      findsOneWidget,
    );
  });

  testWidgets('sans droit d’écriture, le détail n’offre que « Fermer »', (
    tester,
  ) async {
    await enBase();
    await monter(tester, droits: GardeAcces.depuisJson(const {'M1': 'L'}));

    await tester.tap(find.byKey(const Key('voir-res-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('annuler-detail-reservation')), findsNothing);
    expect(find.byKey(const Key('modifier-detail-reservation')), findsNothing);
    expect(find.byKey(const Key('fermer-detail-reservation')), findsOneWidget);
  });

  testWidgets('le détail se ferme, et la grille reste', (tester) async {
    await enBase();
    await monter(tester);

    await tester.tap(find.byKey(const Key('voir-res-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fermer-detail-reservation')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('modale-detail-reservation')), findsNothing);
    expect(find.byKey(const Key('carte-res-1')), findsOneWidget);
  });

  testWidgets('« Nouvelle réservation » ouvre la fiche EN MODALE', (
    tester,
  ) async {
    await enBase();
    await monter(tester);

    await tester.tap(find.byKey(const Key('bouton-nouvelle-reservation')));
    await tester.pumpAndSettle();

    expect(find.byType(FicheReservation), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('titre-modale-reservation')))
          .data,
      'Nouvelle réservation',
    );

    // LA GRILLE RESTE DERRIÈRE. C'est tout l'intérêt de la modale : on revient
    // sur ce qu'on regardait, et non sur une page qu'il faut retrouver.
    expect(find.byKey(const Key('carte-res-1')), findsOneWidget);
  });

  testWidgets('« Modifier » ouvre la MÊME fiche, pré-remplie', (tester) async {
    await enBase();
    await monter(tester);

    await tester.tap(find.byKey(const Key('modifier-res-1')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const Key('titre-modale-reservation')))
          .data,
      'Modifier la réservation',
    );
  });

  testWidgets('la croix referme la fiche, et rien n’est écrit', (tester) async {
    await monter(tester);

    await tester.tap(find.byKey(const Key('bouton-nouvelle-reservation')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fermer-fiche-reservation')));
    await tester.pumpAndSettle();

    expect(find.byType(FicheReservation), findsNothing);
    expect(await depot.reservations(), isEmpty);
  });

  testWidgets('un clic DEHORS ne referme pas : la saisie n’est pas perdue', (
    tester,
  ) async {
    await monter(tester);

    await tester.tap(find.byKey(const Key('bouton-nouvelle-reservation')));
    await tester.pumpAndSettle();

    // Le coin supérieur gauche est hors de la boîte. Fermer là-dessus
    // perdrait une fiche à moitié remplie **sans rien demander** — et le
    // maître ne le permet pas non plus : sa boîte n'a que la croix et
    // « Annuler ».
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(find.byType(FicheReservation), findsOneWidget);
  });

  testWidgets('la boîte tient dans les bornes du maître', (tester) async {
    await monter(tester);

    await tester.tap(find.byKey(const Key('bouton-nouvelle-reservation')));
    await tester.pumpAndSettle();

    // La fiche est REMPLIE jusqu'à déborder : la borne de hauteur ne se voit
    // que sur un contenu plus grand qu'elle. Une première version de ce cas
    // mesurait une fiche courte — retirer la borne ne la faisait pas rougir.
    for (final service in const [
      'restauration',
      'bar',
      'tourisme',
      'vehicule',
    ]) {
      await tester.tap(find.byKey(Key('service-$service')));
      await tester.pumpAndSettle();
    }

    final boite = tester.getSize(find.byType(FicheReservation));
    // `max-width:760px` et `max-h-[72vh]` — mesurés sur le maître, pas
    // supposés. Sans la seconde borne, une fiche à cinq services pousserait
    // l'en-tête et le pied hors de l'écran, avec le bouton d'enregistrement.
    expect(boite.width, lessThanOrEqualTo(760));
    expect(boite.height, lessThanOrEqualTo(2200 * 0.72 + 1));
  });

  testWidgets('l’historique s’ouvre PAR-DESSUS la fiche, qui reste', (
    tester,
  ) async {
    await enBase();
    await monter(tester);

    await tester.tap(find.byKey(const Key('bouton-nouvelle-reservation')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bouton-historique-client')));
    await tester.pumpAndSettle();

    // Trois plans superposés — la grille, la fiche, l'historique — et chacun
    // garde son état. C'est la raison que le maître donne lui-même : devoir
    // fermer la fiche pour vérifier si un client est déjà venu ferait perdre
    // la saisie en cours.
    expect(find.byKey(const Key('fermer-historique')), findsOneWidget);
    expect(find.byType(FicheReservation), findsOneWidget);
  });

  testWidgets('sans droit d’écriture, aucun bouton Annuler sur la carte', (
    tester,
  ) async {
    await enBase();
    await monter(tester, droits: GardeAcces.depuisJson(const {'M1': 'L'}));

    expect(find.byKey(const Key('annuler-res-1')), findsNothing);
  });

  testWidgets('une réservation d’avant la v8 garde son unité et son montant', (
    tester,
  ) async {
    // Sans ligne de service, la carte n'a plus rien de vide à signaler depuis
    // PA-185 : elle ne détaille aucune ligne, comme la vue. L'hébergement a
    // sa pastille d'office, l'unité et le montant restent lisibles —
    // `tarifNuit × nuits`, la seule information qu'elle porte.
    await enBase(lignes: const []);
    await monter(tester);

    expect(find.byKey(const Key('pastille-res-1-hebergement')), findsOneWidget);
    expect(find.byKey(const Key('unite-res-1')), findsOneWidget);
    expect(find.textContaining('56 000 FCFA'), findsWidgets);
  });
}
