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
import 'package:tatacora_flutter/features/hebergement/domain/entities/fiche_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/service_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/impression/etat_historique.dart';
import 'package:tatacora_flutter/features/hebergement/presentation/panneau_historique.dart';
import 'package:tatacora_flutter/features/hebergement/presentation/providers_hebergement.dart';
import 'package:tatacora_flutter/shared_widgets/bouton_standard.dart';

import '../../comptabilite/support/outils_comptabilite.dart'
    show auteurEssai, semerAuteur;

/// Le panneau **Historique des réservations**, monté sur une vraie base locale.
///
/// Ce que ces cas protègent : le panneau existe pour répondre, au comptoir et
/// **sans réseau**, à deux questions — « ce client est-il déjà venu ? » et
/// « que doit-il encore ? ». Un panneau qui n'afficherait que les séjours en
/// cours ne répondrait ni à l'une ni à l'autre.
void main() {
  late AppDatabase db;
  late ReservationRepositoryLocal depot;

  setUp(() async {
    db = AppDatabase.enMemoire();
    depot = ReservationRepositoryLocal(ReservationDao(db));
    // L'annulation nomme celui qui annule (RG-15, clé étrangère réelle).
    await db.customStatement('SELECT 1');
    await semerAuteur(db);

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
            prenom: const Value('Jean'),
            telephone: '+229 01 00 00 00 01',
            typeClient: 'particulier',
          ),
        );
  });

  tearDown(() => db.close());

  /// Une réservation en base, exprimée en jours depuis aujourd'hui.
  ///
  /// Des dates fixes deviendraient « terminées » avec le temps et la suite se
  /// mettrait à échouer un matin sans qu'aucun code n'ait changé.
  Future<Reservation> enBase({
    required int dansNJours,
    required int puisNJours,
    StatutReservation statut = StatutReservation.confirmee,
    CanalReservation canal = CanalReservation.booking,
    int acompte = 0,
    bool avecChambre = true,
  }) {
    final arrivee = DateTime.now().add(Duration(days: dansNJours));
    final depart = DateTime.now().add(Duration(days: puisNJours));

    return depot.enregistrer(
      Reservation(
        id: 'res-$dansNJours-$puisNJours',
        reference: 'LOC-${dansNJours.abs()}${puisNJours.abs()}',
        clientId: 'cli-1',
        clientNom: 'KORA Jean',
        uniteId: 'u-1',
        periode: PeriodeSejour(arrivee: arrivee, depart: depart),
        tarifNuit: 28000,
        statut: statut,
        statutSynchronisation: StatutSynchronisation.local,
        creeeLe: DateTime.now(),
        acompte: acompte,
        canal: canal,
        lignes: avecChambre
            ? [
                LigneService(
                  id: 'l-$dansNJours',
                  service: ServiceReservation.hebergement,
                  itemId: 'u-1',
                  libelle: 'Bungalow (BNG-01)',
                  prixUnitaire: 28000,
                  quantite: (puisNJours - dansNJours).abs(),
                ),
              ]
            : const [],
      ),
    );
  }

  Future<void> monter(
    WidgetTester tester, {
    String termePrerempli = '',
    GardeAcces? droits,
    Future<void> Function(EtatHistorique)? imprimer,
    Future<String> Function(EtatHistorique)? exporter,
  }) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final conteneur = ProviderContainer(
      overrides: [
        depotReservationProvider.overrideWithValue(depot),
        baseLocaleProvider.overrideWithValue(db),
        sessionProvider.overrideWithBuild(
          (ref, notifier) => Session(
            utilisateurId: auteurEssai,
            login: 'caissier',
            nom: 'Caissier',
            role: 'gerant',
            droits: GardeAcces.depuisJson(const {'M1': 'C'}),
          ),
        ),
        droitsProvider.overrideWithValue(
          droits ?? GardeAcces.depuisJson(const {'M1': 'C'}),
        ),
        // L'impression et l'écriture de fichier sont des ACTIONS injectées :
        // un test de widget n'a pas de greffon natif, et `Printing` y lèverait.
        // C'est aussi ce qui permet d'observer ce qui part réellement au
        // document, au lieu de vérifier qu'un bouton existe.
        if (imprimer != null)
          imprimerEtatHistoriqueProvider.overrideWithValue(imprimer),
        if (exporter != null)
          exporterEtatHistoriqueProvider.overrideWithValue(exporter),
      ],
    );
    addTearDown(conteneur.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: conteneur,
        child: MaterialApp(
          theme: AppTheme.clair,
          home: Scaffold(
            body: PanneauHistorique(termePrerempli: termePrerempli),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /* ================================================================== */
  testWidgets('les six indicateurs du maître sont là, dans son ordre', (
    tester,
  ) async {
    await enBase(dansNJours: 10, puisNJours: 12, acompte: 20000);
    await monter(tester);

    for (final libelle in const [
      'Réservations',
      'À venir',
      'En cours',
      'Nuitées',
      'Chiffre d’affaires',
      'Reste à encaisser',
    ]) {
      expect(find.byKey(Key('kpi-$libelle')), findsOneWidget, reason: libelle);
    }

    // 56 000 encaissables, 20 000 déjà versés : 36 000 restent dus. Un
    // indicateur qui afficherait le total ferait relancer un client qui a payé.
    expect(find.textContaining('36 000 FCFA'), findsWidgets);
  });

  testWidgets('un séjour TERMINÉ figure à l’historique', (tester) async {
    // Le défaut que ce panneau répare : la liste principale ne montre que le
    // présent, et « ce client est-il déjà venu ? » n'avait aucune réponse.
    await enBase(dansNJours: -10, puisNJours: -8);
    await monter(tester);

    expect(find.byKey(const Key('etat-termine')), findsOneWidget);
    expect(find.text('KORA Jean'), findsOneWidget);
  });

  testWidgets('une réservation ANNULÉE reste listée, jamais retirée', (
    tester,
  ) async {
    await enBase(
      dansNJours: 10,
      puisNJours: 12,
      statut: StatutReservation.annulee,
    );
    await monter(tester);

    expect(find.byKey(const Key('etat-annulee')), findsOneWidget);
    // Elle est là, mais elle ne pèse pas : le chiffre d'affaires reste à zéro.
    expect(find.byKey(const Key('kpi-Chiffre d’affaires')), findsOneWidget);
    expect(find.textContaining('0 FCFA'), findsWidgets);
  });

  testWidgets('le filtre par état écarte ce qui ne correspond pas', (
    tester,
  ) async {
    await enBase(dansNJours: 10, puisNJours: 12);
    await enBase(dansNJours: -10, puisNJours: -8);
    await monter(tester);

    expect(find.byKey(const Key('etat-a_venir')), findsOneWidget);
    expect(find.byKey(const Key('etat-termine')), findsOneWidget);

    await tester.tap(find.byKey(const Key('hist-etat')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('À venir').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('etat-a_venir')), findsOneWidget);
    expect(find.byKey(const Key('etat-termine')), findsNothing);
  });

  testWidgets('le terme pré-rempli filtre dès l’ouverture', (tester) async {
    // C'est tout l'intérêt du second point d'entrée : on ouvre le panneau
    // depuis la fiche en cours de saisie, avec le nom déjà tapé.
    await enBase(dansNJours: 10, puisNJours: 12);
    await monter(tester, termePrerempli: 'introuvable');

    expect(find.byKey(const Key('hist-vide')), findsOneWidget);
    expect(
      find.text('Aucune réservation ne correspond à ces filtres.'),
      findsOneWidget,
    );
  });

  testWidgets('« Réinitialiser » rend tout ce que les filtres cachaient', (
    tester,
  ) async {
    await enBase(dansNJours: 10, puisNJours: 12);
    await monter(tester, termePrerempli: 'introuvable');

    expect(find.byKey(const Key('hist-vide')), findsOneWidget);

    await tester.tap(find.byKey(const Key('hist-reset')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('hist-vide')), findsNothing);
    expect(find.text('KORA Jean'), findsOneWidget);
  });

  testWidgets('sans droit d’écriture sur M1, aucune action d’annulation', (
    tester,
  ) async {
    final r = await enBase(dansNJours: 10, puisNJours: 12);
    await monter(tester, droits: GardeAcces.depuisJson(const {'M1': 'L'}));

    // Retiré, jamais grisé : un bouton grisé invite à cliquer pour ne produire
    // qu'un refus.
    expect(find.byKey(Key('hist-annuler-${r.id}')), findsNothing);
  });

  testWidgets('un séjour TERMINÉ n’est plus annulable', (tester) async {
    // Annuler un séjour consommé ne libère rien et fausserait le chiffre
    // d'affaires du mois écoulé.
    final r = await enBase(dansNJours: -10, puisNJours: -8);
    await monter(tester);

    expect(find.byKey(Key('hist-annuler-${r.id}')), findsNothing);
  });

  testWidgets('« PDF » envoie EXACTEMENT ce que l’écran affiche', (
    tester,
  ) async {
    await enBase(dansNJours: 10, puisNJours: 12, acompte: 20000);
    await enBase(dansNJours: -10, puisNJours: -8);

    EtatHistorique? envoye;
    await monter(tester, imprimer: (etat) async => envoye = etat);

    // On filtre d'abord : c'est le cas qui compte. Un export qui repartirait
    // de la base entière contredirait le tableau que l'utilisateur a sous les
    // yeux au moment où il clique.
    await tester.tap(find.byKey(const Key('hist-etat')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('À venir').last);
    await tester.pumpAndSettle();

    // D434 : UN « Exporter » ouvre la modale partagée, PDF présélectionné.
    await tester.tap(find.byKey(const Key('hist-exporter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-generer')));
    await tester.pumpAndSettle();

    expect(envoye, isNotNull);
    expect(envoye!.lignes, hasLength(1));
    expect(envoye!.lignes.single.etat.libelle, 'À venir');
    // Les indicateurs de l'état suivent le filtre eux aussi.
    expect(envoye!.indicateurs['Réservations'], '1');
  });

  testWidgets('le tableur écrit un fichier et DIT où il est', (tester) async {
    await enBase(dansNJours: 10, puisNJours: 12);

    var chemin = '';
    await monter(
      tester,
      exporter: (etat) async {
        chemin = r'C:\Documents\historique-reservations-20260925-101500.csv';
        return chemin;
      },
    );

    await tester.tap(find.byKey(const Key('hist-exporter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-format-excel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-generer')));
    await tester.pumpAndSettle();

    // Un export silencieux est un export que personne ne retrouve.
    expect(find.byKey(const Key('hist-export-chemin')), findsOneWidget);
    expect(find.textContaining(chemin), findsOneWidget);
  });

  testWidgets('« Exporter » est ACTIF dès que les données sont là', (
    tester,
  ) async {
    // Le défaut de séquence que ce cas empêche : l'en-tête se construit avant
    // le corps dans la même passe de rendu. Un état composé dans la branche
    // `data` n'aurait jamais été vu par l'en-tête du même rendu, et rien ne
    // déclenchait de rendu suivant — le bouton serait resté grisé pour
    // toujours, sur un panneau par ailleurs fonctionnel.
    await enBase(dansNJours: 10, puisNJours: 12);
    await monter(tester);

    expect(
      tester
          .widget<BoutonStandard>(find.byKey(const Key('hist-exporter')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('l’annulation depuis l’historique ouvre LA modale du serveur — '
      'un seul chemin, donc une seule pièce — et conserve la ligne', (
    tester,
  ) async {
    final r = await enBase(dansNJours: 10, puisNJours: 12);
    await monter(tester);

    // Neuf colonnes ne tiennent pas dans le panneau : le tableau défile
    // horizontalement dans son propre conteneur, comme au maître, et l'action
    // d'annulation est la DERNIÈRE colonne. Un `tap` direct viserait un point
    // hors de la fenêtre (x = 1940 sur un panneau de 1200) et ne toucherait
    // rien — le geste réel est de faire défiler jusqu'à elle.
    final bouton = find.byKey(Key('hist-annuler-${r.id}'));
    await tester.ensureVisible(bouton);
    await tester.pumpAndSettle();
    await tester.tap(bouton);
    await tester.pumpAndSettle();

    // La modale du serveur, pas l'ancienne boîte de dialogue du motif.
    expect(
      find.byKey(const Key('modale-annulation-reservation')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('hist-motif-annulation')), findsNothing);

    await tester.tap(find.byKey(const Key('annulation-confirmer')));
    await tester.pumpAndSettle();

    final relue = await depot.parId(r.id);
    expect(relue!.statut, StatutReservation.annulee);
    // 2 nuits à 28 000 F, taux de référence de 50 %.
    expect(relue.annulation!.totalCentimes, 5600000);
    expect(relue.annulation!.commissionCentimes, 2800000);
    // Conservée : elle passe en annulée, elle n'est pas effacée (RG-02).
    expect(await depot.reservations(), hasLength(1));
  });
}
