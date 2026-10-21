import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_repository_local.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/disponibilite.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/unite_hebergement.dart';
import 'package:tatacora_flutter/features/hebergement/presentation/ecran_hebergement.dart';
import 'package:tatacora_flutter/features/hebergement/presentation/providers_hebergement.dart';
import 'package:tatacora_flutter/features/hebergement/presentation/widgets/vue_disponibilites.dart';

/// L'onglet « Disponibilités » de `hebergement/hebergement.blade.php`
/// (l.478-550) — ajouté par décision du Product Owner du 08/10/2026.
///
/// Il reprend les cas de l'ancien écran `ecran_disponibilites.dart`, retiré le
/// 09/10/2026 (orphelin depuis le 14/09/2026 : aucun clic n'y menait), et
/// ajoute ceux que la vue impose : il PART VIDE, son motif dit les dates et non
/// le client, son résumé et ses en-têtes sont ceux de la vue.
///
/// ## La logique de disponibilité n'est PAS ici
///
/// `ConsulterDisponibilites` (RG-01, RG-02, bornes semi-ouvertes) est inchangé
/// et testé dans `usecases_test.dart`. Ces cas vérifient ce que l'onglet
/// AFFICHE de ce calcul, et que les bornes arrivent jusqu'à l'écran.
///
/// ## L'horloge est FIXÉE : le 9 octobre 2026, à 10 h
///
/// Le sélecteur de dates est ouvert sur octobre 2026, et les jours se cherchent
/// par leur numéro. Lu sur l'horloge réelle, le cas échouerait au changement de
/// mois.
void main() {
  late AppDatabase db;
  late ReservationRepositoryLocal depot;
  late ProviderContainer conteneur;

  final maintenant = DateTime(2026, 10, 9, 10);

  Future<void> semer({bool avecParc = true}) async {
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
        .into(db.clientsLocal)
        .insert(
          ClientsLocalCompanion.insert(
            id: 'cli-1',
            nom: 'DOSSOU',
            prenom: const Value('Marie'),
            telephone: '+229 01 00 00 00 02',
            typeClient: 'particulier',
          ),
        );
    if (!avecParc) return;
    for (final (id, numero, statut) in const [
      ('u-bng-01', 'BNG-01', 'libre'),
      ('u-bng-02', 'BNG-02', 'libre'),
      ('u-hs', 'CH-999', 'hors_service'),
    ]) {
      await db
          .into(db.unitesHebergementLocal)
          .insert(
            UnitesHebergementLocalCompanion.insert(
              id: id,
              categorieId: 'cat-1',
              numero: numero,
              statut: statut,
            ),
          );
    }
  }

  /// BNG-01 est retenue du 14 au 17 octobre.
  Future<void> reserverBng01() => depot.enregistrer(
    Reservation(
      id: 'res-1',
      reference: 'LOC-1',
      clientId: 'cli-1',
      clientNom: 'DOSSOU Marie',
      uniteId: 'u-bng-01',
      periode: PeriodeSejour(
        arrivee: DateTime(2026, 10, 14),
        depart: DateTime(2026, 10, 17),
      ),
      tarifNuit: 28000,
      statut: StatutReservation.confirmee,
      statutSynchronisation: StatutSynchronisation.local,
      creeeLe: maintenant,
    ),
  );

  setUp(() {
    db = AppDatabase.enMemoire();
    depot = ReservationRepositoryLocal(ReservationDao(db));
  });

  tearDown(() => db.close());

  Future<void> monter(
    WidgetTester tester, {
    GardeAcces? droits,
    Size taille = const Size(1500, 2400),
    List<Override> surcharges = const [],
  }) async {
    tester.view.physicalSize = taille;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    conteneur = ProviderContainer(
      overrides: [
        depotReservationProvider.overrideWithValue(depot),
        baseLocaleProvider.overrideWithValue(db),
        horlogeHebergementProvider.overrideWithValue(() => maintenant),
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
    await tester.tap(find.byKey(const Key('onglet-disponibilites')));
    await tester.pumpAndSettle();
  }

  /// Ouvre le sélecteur du champ, retient le [jour] d'octobre 2026 et valide.
  Future<void> choisir(WidgetTester tester, String champ, int jour) async {
    await tester.tap(find.byKey(Key(champ)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('$jour').last);
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  Future<void> chercher(WidgetTester tester, int du, int au) async {
    await choisir(tester, 'dispo-arrivee', du);
    await choisir(tester, 'dispo-depart', au);
  }

  Text texte(WidgetTester tester, String cle) =>
      tester.widget<Text>(find.byKey(Key(cle)));

  /* ================================================================== */
  group('Au repos', () {
    testWidgets('il PART VIDE : aucune période n’est devinée (l.158-161)', (
      tester,
    ) async {
      await semer();
      await monter(tester);

      expect(find.text('Disponibilités sur une période'), findsOneWidget);
      expect(
        find.text(
          'Choisissez une arrivée et un départ : chaque unité du parc est '
          'listée, libre ou non, avec son motif. Le départ est exclu (la nuit '
          'du départ reste libre).',
        ),
        findsOneWidget,
      );
      expect(find.text('Arrivée'), findsOneWidget);
      expect(find.text('Départ'), findsOneWidget);
      expect(find.text('jj/mm/aaaa'), findsNWidgets(2));
      // Rien n'a été demandé : ni résumé, ni tableau, ni message d'erreur.
      expect(find.byKey(const Key('dispo-resume')), findsNothing);
      expect(find.text('UNITÉ'), findsNothing);
      expect(find.byKey(const Key('dispo-invalide')), findsNothing);
    });

    testWidgets('une seule date choisie : toujours rien à calculer', (
      tester,
    ) async {
      await semer();
      await monter(tester);

      await choisir(tester, 'dispo-arrivee', 12);

      expect(find.text('12/10/2026'), findsOneWidget);
      expect(find.byKey(const Key('dispo-resume')), findsNothing);
      expect(find.byKey(const Key('dispo-invalide')), findsNothing);
    });
  });

  /* ================================================================== */
  group('Une période choisie', () {
    testWidgets('le résumé, les en-têtes et chaque unité portent les mots de '
        'la vue', (tester) async {
      await semer();
      await reserverBng01();
      await monter(tester);

      await chercher(tester, 12, 15);

      // « N libre(s) sur M unité(s) pour K nuit(s). » — 12 → 15 : TROIS nuits,
      // BNG-02 seule est libre (BNG-01 est retenue le 14, CH-999 est hors
      // service).
      expect(
        texte(tester, 'dispo-resume').data,
        '1 libre(s) sur 3 unité(s) pour 3 nuit(s).',
      );
      for (final entete in const [
        'UNITÉ',
        'CATÉGORIE',
        'CAPACITÉ',
        'MONTANT DU SÉJOUR',
        'DISPONIBILITÉ',
      ]) {
        expect(find.text(entete), findsOneWidget, reason: entete);
      }
      // Le montant est CALCULÉ : 28 000 × 3 nuits, et aucun champ ne le reçoit.
      expect(find.text('84 000 FCFA'), findsNWidgets(3));
      expect(find.text('Bungalow'), findsNWidgets(3));
      expect(find.text('2'), findsNWidgets(3));
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('une unité prise dit LES DATES de la réservation, pas QUI', (
      tester,
    ) async {
      await semer();
      await reserverBng01();
      await monter(tester);

      await chercher(tester, 12, 15);

      expect(
        texte(tester, 'dispo-motif-u-bng-01').data,
        'Réservée du 14/10/2026 au 17/10/2026',
      );
      // La vue ne nomme pas le client (`dispo_motif_reservation`).
      expect(find.textContaining('DOSSOU'), findsNothing);
      expect(texte(tester, 'dispo-motif-u-hs').data, 'Hors service');
      // Les deux unités prises portent le badge rouge ; la libre, le vert.
      expect(find.text('Indisponible'), findsNWidgets(2));
      expect(find.text('Libre'), findsOneWidget);
    });

    testWidgets('les bornes sont SEMI-OUVERTES jusqu’à l’écran (RG-01)', (
      tester,
    ) async {
      await semer();
      await reserverBng01();
      await monter(tester);

      // Départ le 14 = arrivée de l'autre séjour : la chambre est libre.
      await chercher(tester, 12, 14);
      expect(
        texte(tester, 'dispo-resume').data,
        '2 libre(s) sur 3 unité(s) pour 2 nuit(s).',
      );
      expect(find.byKey(const Key('dispo-motif-u-bng-01')), findsNothing);

      // Arrivée le 17 = départ de l'autre séjour : libre aussi.
      await chercher(tester, 17, 19);
      expect(
        texte(tester, 'dispo-resume').data,
        '2 libre(s) sur 3 unité(s) pour 2 nuit(s).',
      );

      // Mais une nuit de chevauchement suffit : 16 → 18 retient BNG-01.
      await chercher(tester, 16, 18);
      expect(
        texte(tester, 'dispo-resume').data,
        '1 libre(s) sur 3 unité(s) pour 2 nuit(s).',
      );
      expect(find.byKey(const Key('dispo-motif-u-bng-01')), findsOneWidget);
    });

    testWidgets('un départ qui ne suit pas l’arrivée est REFUSÉ, et dit', (
      tester,
    ) async {
      await semer();
      await monter(tester);

      await choisir(tester, 'dispo-arrivee', 15);
      await choisir(tester, 'dispo-depart', 12);

      expect(
        texte(tester, 'dispo-invalide').data,
        "Le départ doit suivre l'arrivée.",
      );
      expect(find.byKey(const Key('dispo-resume')), findsNothing);
      expect(find.text('UNITÉ'), findsNothing);
      // Et la fiche ne reçoit pas la période refusée (15 → 12). Ancré sur la
      // période elle-même et non sur « l'arrivée n'est pas le 15 » : le 15 du
      // mois, l'arrivée PAR DÉFAUT (aujourd'hui) vaut 15, et l'ancienne
      // assertion rougissait ce jour-là sans défaut (mesuré le 15/10/2026).
      final periode = conteneur.read(periodeConsulteeProvider);
      expect(periode.depart, isNot(DateTime.utc(2026, 10, 12)));
      expect(periode.depart.isAfter(periode.arrivee), isTrue);
    });

    testWidgets('un parc vide le DIT, sans masquer le résumé', (tester) async {
      await semer(avecParc: false);
      await monter(tester);

      await chercher(tester, 12, 15);

      expect(
        texte(tester, 'dispo-resume').data,
        '0 libre(s) sur 0 unité(s) pour 3 nuit(s).',
      );
      expect(
        texte(tester, 'dispo-vide').data,
        'Le parc ne compte aucune unité.',
      );
      expect(find.text('UNITÉ'), findsNothing);
    });

    testWidgets('une erreur de calcul s’affiche EN ENTIER, sans déborder', (
      tester,
    ) async {
      await semer();
      final bavarde = Exception(
        'Le calcul des disponibilités a échoué : la base du poste ne répond '
        'pas. Fermez puis rouvrez l’application ; si le message revient, '
        'relevez-le tel quel avant d’appeler le support.',
      );
      await monter(
        tester,
        taille: const Size(1000, 1400),
        surcharges: [
          disponibilitesProvider.overrideWith(
            (ref) => Future<List<Disponibilite>>.error(bavarde),
          ),
        ],
      );

      await chercher(tester, 12, 15);

      // Le message est rendu tel quel : le masquer obligerait à ouvrir les
      // journaux pour un diagnostic que l'utilisateur peut faire lui-même.
      expect(
        texte(tester, 'dispo-erreur').data,
        contains('relevez-le tel quel avant d’appeler le support.'),
      );
      expect(tester.takeException(), isNull);
    });
  });

  /* ================================================================== */
  group('« Réserver »', () {
    testWidgets('le bouton n’est offert qu’aux unités LIBRES', (tester) async {
      await semer();
      await reserverBng01();
      await monter(tester);

      await chercher(tester, 12, 15);

      expect(find.text('Réserver'), findsOneWidget);
      expect(find.byKey(const Key('dispo-reserver-u-bng-02')), findsOneWidget);
      expect(find.byKey(const Key('dispo-reserver-u-bng-01')), findsNothing);
      expect(find.byKey(const Key('dispo-reserver-u-hs')), findsNothing);
    });

    testWidgets(
      'la période CHERCHÉE devient celle de la réservation rapide (l.538)',
      (tester) async {
        await semer();
        await monter(tester);

        await chercher(tester, 12, 15);
        expect(
          conteneur.read(periodeConsulteeProvider).arrivee,
          DateTime.utc(2026, 10, 12),
        );
        expect(
          conteneur.read(periodeConsulteeProvider).depart,
          DateTime.utc(2026, 10, 15),
        );

        await tester.tap(find.byKey(const Key('dispo-reserver-u-bng-02')));
        await tester.pumpAndSettle();

        // La modale « Réservation rapide » s'ouvre PAR-DESSUS, sur l'unité
        // retenue, avec la période cherchée : trois nuits, 3 × 28 000.
        expect(
          find.byKey(const Key('modale-reservation-rapide')),
          findsOneWidget,
        );
        expect(
          tester.widget<Text>(find.byKey(const Key('rapide-nuits'))).data,
          '3 nuit(s)',
        );
        expect(
          tester.widget<Text>(find.byKey(const Key('rapide-montant'))).data,
          '84 000 FCFA',
        );
      },
    );

    testWidgets('sans droit d’écriture, le bouton est RETIRÉ, pas grisé', (
      tester,
    ) async {
      await semer();
      await monter(tester, droits: GardeAcces.depuisJson(const {'M1': 'L'}));

      await chercher(tester, 12, 15);

      // La lecture reste entière…
      expect(find.byKey(const Key('dispo-resume')), findsOneWidget);
      expect(find.text('Libre'), findsNWidgets(2));
      // …mais un bouton grisé inviterait à cliquer pour ne produire qu'un
      // refus.
      expect(find.text('Réserver'), findsNothing);
    });
  });

  /* ================================================================== */
  group('Les mots du motif', () {
    UniteHebergement unite() => const UniteHebergement(
      id: 'u',
      numero: 'BNG-01',
      categorieId: 'c',
      categorieLibelle: 'Bungalow',
      statut: StatutUnite.libre,
      tarifBase: 28000,
      capaciteMax: 2,
    );
    final periode = PeriodeSejour(
      arrivee: DateTime(2026, 10, 12),
      depart: DateTime(2026, 10, 15),
    );

    test('hors service, déjà réservée, et le repli « Indisponible »', () {
      expect(
        VueDisponibilites.motif(Disponibilite.horsService(unite(), periode)),
        'Hors service',
      );
      expect(
        VueDisponibilites.motif(
          Disponibilite.occupee(
            unite(),
            periode,
            reservationId: 'r',
            periodeOccupee: PeriodeSejour(
              arrivee: DateTime(2026, 10, 14),
              depart: DateTime(2026, 10, 17),
            ),
            clientNom: 'DOSSOU Marie',
          ),
        ),
        'Réservée du 14/10/2026 au 17/10/2026',
      );
      // Sans réservation désignée, la vue retombe sur « Indisponible ».
      expect(
        VueDisponibilites.motif(
          Disponibilite(unite: unite(), periode: periode, disponible: false),
        ),
        'Indisponible',
      );
    });
  });
}
