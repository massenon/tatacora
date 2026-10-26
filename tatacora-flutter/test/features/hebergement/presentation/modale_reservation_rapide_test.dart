import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_repository_local.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/unite_hebergement.dart';
import 'package:tatacora_flutter/features/hebergement/presentation/providers_hebergement.dart';
import 'package:tatacora_flutter/features/hebergement/presentation/widgets/modale_reservation_rapide.dart';

import '../../comptabilite/support/outils_comptabilite.dart';

/// La modale « Réservation rapide » du parc (`hebergement.blade.php`
/// l.560-628), depuis « Réserver cette unité » et les disponibilités.
///
/// ## Ce que ces cas protègent
///
/// Que la modale **écrive vraiment** (une réservation d'hébergement seul, au
/// client choisi), qu'elle **refuse** par le chemin de la fiche complète (RG-01,
/// client obligatoire) SANS se fermer, et que nuits et montant soient CALCULÉS —
/// « un total modifiable finit par contredire les dates ».
void main() {
  late AppDatabase db;
  late ReservationRepositoryLocal depot;

  const uniteId = 'u-bng-01';

  const unite = UniteHebergement(
    id: uniteId,
    numero: 'BNG-01',
    categorieId: 'cat-1',
    categorieLibelle: 'Bungalow',
    statut: StatutUnite.libre,
    tarifBase: 28000,
    capaciteMax: 2,
  );

  DateTime jour(int dansNJours) {
    final auj = DateTime.now();
    return DateTime(auj.year, auj.month, auj.day + dansNJours);
  }

  setUp(() async {
    db = AppDatabase.enMemoire();
    await db.customStatement('SELECT 1');
    await semerAuteur(db);
    await baseInstalleeSur(db, DateTime.now());
    depot = ReservationRepositoryLocal(
      ReservationDao(
        db,
        moteur: () async => moteurSur(db, maintenant: DateTime.now),
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
            id: uniteId,
            categorieId: 'cat-1',
            numero: 'BNG-01',
            statut: 'libre',
          ),
        );
    await db
        .into(db.clientsLocal)
        .insert(
          ClientsLocalCompanion.insert(
            id: 'cli-comptoir',
            nom: 'Comptoir',
            telephone: '+229 01 00 00 00 00',
            typeClient: 'particulier',
          ),
        );
    await db
        .into(db.clientsLocal)
        .insert(
          ClientsLocalCompanion.insert(
            id: 'cli-dossou',
            nom: 'DOSSOU',
            prenom: const Value('Marie'),
            telephone: '+229 01 00 00 00 02',
            typeClient: 'particulier',
          ),
        );
  });

  tearDown(() async => db.close());

  Future<void> ouvrir(
    WidgetTester tester, {
    DateTime? arrivee,
    DateTime? depart,
  }) async {
    tester.view
      ..physicalSize = const Size(1000, 1600)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          depotReservationProvider.overrideWithValue(depot),
          baseLocaleProvider.overrideWithValue(db),
          sessionProvider.overrideWithBuild(
            (ref, notifier) => Session(
              utilisateurId: auteurEssai,
              login: 'caissier',
              nom: 'Caissier',
              role: 'gerant',
              droits: GardeAcces.depuisJson(const {'M1': 'C', 'M3': 'C'}),
            ),
          ),
          droitsProvider.overrideWithValue(
            GardeAcces.depuisJson(const {'M1': 'C', 'M3': 'C'}),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                key: const Key('ouvrir'),
                onPressed: () => ouvrirReservationRapideParc(
                  context,
                  unite: unite,
                  arrivee: arrivee,
                  depart: depart,
                ),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ouvrir')));
    await tester.pumpAndSettle();
  }

  Future<void> choisirClient(WidgetTester tester, String nom) async {
    await tester.tap(find.byKey(const Key('rapide-client')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(nom).last);
    await tester.pumpAndSettle();
  }

  String texte(WidgetTester tester, String cle) =>
      tester.widget<Text>(find.byKey(Key(cle))).data!;

  testWidgets('elle s’ouvre aux mots de la vue : titre, unité en sous-titre, '
      'cette nuit calculée', (tester) async {
    await ouvrir(tester);

    expect(find.text('Réservation rapide'), findsOneWidget);
    expect(find.text('BNG-01 · Bungalow'), findsOneWidget);
    expect(find.text('Choisir un client…'), findsOneWidget);
    expect(find.text('Nombre de nuits'), findsOneWidget);
    expect(find.text('Montant hébergement'), findsOneWidget);
    // Par défaut : aujourd'hui → demain, une nuit au tarif de base.
    expect(texte(tester, 'rapide-nuits'), '1 nuit(s)');
    expect(texte(tester, 'rapide-montant'), '28 000 FCFA');
    expect(
      texte(tester, 'rapide-pied'),
      'La réservation est créée avec l\'hébergement seul. Restauration, bar, '
      'tourisme et véhicule s\'ajoutent dans Réservations.',
    );
    expect(find.text('Enregistrer et compléter plus tard'), findsOneWidget);
  });

  testWidgets('la période CHERCHÉE devient la période réservée', (
    tester,
  ) async {
    await ouvrir(tester, arrivee: jour(5), depart: jour(8));

    expect(texte(tester, 'rapide-nuits'), '3 nuit(s)');
    expect(texte(tester, 'rapide-montant'), '84 000 FCFA');
  });

  testWidgets('une période cherchée invalide retombe sur cette nuit', (
    tester,
  ) async {
    await ouvrir(tester, arrivee: jour(5), depart: jour(5));

    expect(texte(tester, 'rapide-nuits'), '1 nuit(s)');
  });

  testWidgets('sans client, le geste est REFUSÉ sous le champ, rien n’est '
      'écrit et la modale reste', (tester) async {
    await ouvrir(tester);

    await tester.tap(find.byKey(const Key('rapide-enregistrer')));
    await tester.pumpAndSettle();

    expect(texte(tester, 'rapide-erreur-client'), 'Choisissez un client.');
    expect(find.byKey(const Key('modale-reservation-rapide')), findsOneWidget);
    expect(await depot.reservations(), isEmpty);
  });

  testWidgets('avec un client, elle ÉCRIT la réservation d’hébergement seul et '
      'le dit', (tester) async {
    await ouvrir(tester);

    await choisirClient(tester, 'Comptoir');
    await tester.tap(find.byKey(const Key('rapide-enregistrer')));
    await tester.pumpAndSettle();

    final liste = await depot.reservations();
    expect(liste, hasLength(1));
    final r = liste.single;
    expect(r.clientId, 'cli-comptoir');
    expect(r.uniteId, uniteId);
    expect(r.nuits, 1);
    expect(r.tarifNuit, 28000);
    // Hébergement seul : ni canal, ni acompte, ni service annexe — la modale
    // les laisse à « Réservations ».
    expect(r.canal, isNull);
    expect(r.acompte, 0);
    expect(find.byKey(const Key('modale-reservation-rapide')), findsNothing);
    expect(
      texte(tester, 'rapide-succes'),
      'Réservation enregistrée pour Comptoir — 1 nuit(s) sur l\'unité BNG-01.',
    );
  });

  testWidgets('RG-01 : une unité déjà prise est refusée SUR L’UNITÉ, la '
      'modale reste ouverte', (tester) async {
    // Le second client prend la nuit d'abord.
    await ouvrir(tester, arrivee: jour(2), depart: jour(4));
    await choisirClient(tester, 'DOSSOU');
    await tester.tap(find.byKey(const Key('rapide-enregistrer')));
    await tester.pumpAndSettle();
    expect(await depot.reservations(), hasLength(1));

    // Une seconde saisie sur la même période.
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ouvrir')));
    await tester.pumpAndSettle();
    await choisirClient(tester, 'Comptoir');
    await tester.tap(find.byKey(const Key('rapide-enregistrer')));
    await tester.pumpAndSettle();

    expect(
      texte(tester, 'rapide-erreur-unite'),
      startsWith('Unité déjà réservée par DOSSOU Marie'),
    );
    expect(find.byKey(const Key('modale-reservation-rapide')), findsOneWidget);
    expect(await depot.reservations(), hasLength(1));
  });

  testWidgets('un départ non postérieur à l’arrivée est refusé aux mots de la '
      'vue', (tester) async {
    await ouvrir(tester, arrivee: jour(5), depart: jour(6));
    await choisirClient(tester, 'Comptoir');

    // Départ ramené au jour de l'arrivée.
    await tester.tap(find.byKey(const Key('rapide-depart')));
    await tester.pumpAndSettle();
    // Le sélecteur s'ouvre sur le mois du départ : quand l'arrivée tombe le mois
    // d'avant (fin de mois), on y revient avant de choisir le jour.
    if (jour(5).month != jour(6).month) {
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('${jour(5).day}').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(texte(tester, 'rapide-nuits'), '—');
    expect(texte(tester, 'rapide-montant'), '—');
    await tester.tap(find.byKey(const Key('rapide-enregistrer')));
    await tester.pumpAndSettle();

    expect(
      texte(tester, 'rapide-erreur-depart'),
      'La date de départ doit être postérieure à la date d\'arrivée.',
    );
    expect(await depot.reservations(), isEmpty);
  });

  testWidgets('« Annuler » ferme la modale sans rien écrire', (tester) async {
    await ouvrir(tester);

    await tester.tap(find.byKey(const Key('caisse-annuler')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('modale-reservation-rapide')), findsNothing);
    expect(await depot.reservations(), isEmpty);
  });
}
