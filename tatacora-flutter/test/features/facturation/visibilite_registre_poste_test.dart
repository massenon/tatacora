import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/facturation/data/proforma_dao.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/piece_facturation.dart';
import 'package:tatacora_flutter/features/facturation/domain/repositories/facture_repository.dart';
import 'package:tatacora_flutter/features/facturation/domain/textes_proforma.dart';
import 'package:tatacora_flutter/features/facturation/domain/textes_registre_facture.dart';
import 'package:tatacora_flutter/features/facturation/presentation/ecran_facturation.dart';
import 'package:tatacora_flutter/features/facturation/presentation/ecran_proformas.dart';
import 'package:tatacora_flutter/features/facturation/presentation/providers_facturation.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_depot_local.dart';
import 'package:tatacora_flutter/features/synchronisation/presentation/providers_synchronisation.dart'
    show cheminConfigurationPosteProvider;

import 'support/outils_encaissement.dart';

/// VISIBILITÉ au poste (bug du PO du 09/11/2026 : « j'ai activé MECeF, enregistré une réservation, et je ne
/// vois ni proforma ni facture ») :
///  * une facture émise reste au registre quel que soit le mode de facturation et l'état de sa
///    normalisation — son statut s'affiche, elle ne disparaît jamais ;
///  * un registre vide DIT qu'une réservation ne crée pas de facture, mène aux proformas, et nomme les
///    factures qui existent hors de l'exercice consulté ;
///  * la page Proformas liste brouillons, émises et reçues du serveur, et son état vide dit où créer.
void main() {
  HttpOverrides.global = null;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late Directory dossier;
  late String cheminPoste;

  setUp(() async {
    db = await baseEncaissement();
    dossier = await Directory.systemTemp.createTemp('tatacora-visib-');
    cheminPoste = '${dossier.path}/poste.json';
    final depot = ParametresDepotLocal(db);
    for (final e in {
      'entreprise_ifu': '3201910768821',
      'mecef_operateur_id': 'RECEPTION01',
      'mecef_operateur_nom': 'Réception',
      'tva_active': 'false',
      'convention_prix': 'ttc',
    }.entries) {
      await depot.inscrireDescendue(e.key, e.value);
    }
  });

  tearDown(() async {
    await db.close();
    if (dossier.existsSync()) await dossier.delete(recursive: true);
  });

  Future<void> laisserTourner(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump();
    }
  }

  Future<PieceFacturation> vente({DateTime? horloge}) =>
      factureDaoSur(db, horloge: horloge).emettre(
        BrouillonFacture(
          origine: OrigineFacture.posComptant,
          clientNom: 'Client de passage',
          modePaiement: 'especes',
          lignes: [
            LigneBrouillon(
              module: ModuleFacturable.m5Bar,
              libelle: 'Béninoise 33cl',
              prixUnitaire: 1000,
              quantite: 2,
            ),
          ],
        ),
      );

  Future<void> poserNormalisation(
    String id,
    String? statut, {
    String? motif,
  }) async {
    if (statut == null) return;
    final reel = statut == 'normalisee';
    await db.customStatement(
      'UPDATE pieces_facturation_local SET normalisation_statut = ?, '
      'normalisation_motif = ?, normalisation_mode = ?, numero_mecef = ?, '
      'qr_code_fiscal = ? WHERE id = ?',
      [
        statut,
        motif,
        'boitier',
        reel ? 'ED04000623-41' : null,
        reel ? 'F;ED04000623;ABCDEFGH;3201910768821;20261107101500' : null,
        id,
      ],
    );
  }

  Future<void> monter(
    WidgetTester tester,
    Widget ecran, {
    String niveau = 'C',
    double largeur = 1600,
    GoRouter? routeur,
  }) async {
    tester.view
      ..physicalSize = Size(largeur, 1400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final droits = GardeAcces.depuisJson({'M2': niveau, 'M5': 'C'});
    final surcharges = [
      baseLocaleProvider.overrideWithValue(db),
      sessionProvider.overrideWithBuild(
        (ref, notifier) => Session(
          utilisateurId: caissierEssai,
          login: 'nabogou',
          nom: 'Nabogou',
          role: 'administrateur',
          droits: droits,
        ),
      ),
      droitsProvider.overrideWithValue(droits),
      logoEtablissementProvider.overrideWith((ref) async => null),
      cheminConfigurationPosteProvider.overrideWithValue(
        () async => cheminPoste,
      ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: surcharges,
        child: routeur == null
            ? MaterialApp(
                theme: AppTheme.clair,
                home: Scaffold(body: ecran),
              )
            : MaterialApp.router(theme: AppTheme.clair, routerConfig: routeur),
      ),
    );
    await laisserTourner(tester);
  }

  const etats = <String?>[
    null,
    'en_attente',
    'refusee',
    'a_verifier',
    'normalisee',
  ];

  for (final mode in ['desactive', 'emecef', 'boitier']) {
    testWidgets('mode $mode : toute facture reste au registre, quel que soit '
        'l\'état de sa normalisation', (tester) async {
      await ParametresDepotLocal(
        db,
      ).inscrireDescendue('facturation_mode', mode);
      final ids = <String?, String>{};
      for (final etat in etats) {
        final p = await vente();
        await poserNormalisation(p.id, etat, motif: 'motif $etat');
        ids[etat] = p.id;
      }
      await monter(tester, const EcranFacturation());

      for (final etat in etats) {
        expect(
          find.byKey(Key('facturation-piece-${ids[etat]}')),
          findsOneWidget,
          reason: 'la facture « $etat » a disparu du registre en mode $mode',
        );
      }
      expect(find.byKey(const Key('facturation-registre-vide')), findsNothing);
      // Le statut de normalisation s'affiche, sauf pour une facture simple.
      for (final etat in etats.whereType<String>()) {
        expect(
          find.byKey(Key('facturation-normalisation-${ids[etat]}')),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(
          of: find.byKey(Key('facturation-normalisation-${ids['refusee']}')),
          matching: find.text('refusée'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(Key('facturation-normalisation-${ids['a_verifier']}')),
          matching: find.text('à vérifier'),
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets('registre vide : une réservation ne crée pas de facture, et le '
      'bouton mène aux proformas', (tester) async {
    final routeur = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: EcranFacturation()),
        ),
        GoRoute(
          path: '/facturation/proformas',
          builder: (_, _) => const Scaffold(body: Text('PAGE PROFORMAS')),
        ),
      ],
    );
    await monter(tester, const SizedBox.shrink(), routeur: routeur);

    expect(find.byKey(const Key('facturation-registre-vide')), findsOneWidget);
    expect(find.text(TextesRegistreFacture.registreVideAide), findsOneWidget);
    expect(
      find.textContaining('clôturez le séjour pour facturer'),
      findsOneWidget,
    );
    expect(
      find.textContaining('créez une proforma depuis la réservation'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('facturation-registre-hors-exercice')),
      findsNothing,
    );

    await tester.ensureVisible(
      find.byKey(const Key('facturation-registre-vide-proformas')),
    );
    await tester.tap(
      find.byKey(const Key('facturation-registre-vide-proformas')),
    );
    await laisserTourner(tester);
    expect(find.text('PAGE PROFORMAS'), findsOneWidget);
  });

  testWidgets('une facture d\'un autre exercice est masquée par le sélecteur, '
      'et l\'écran le DIT', (tester) async {
    // Un exercice 2025 existe au poste (clôturé), l'exercice 2026 est celui qu'on consulte.
    await vente(horloge: DateTime(2025, 6, 1, 10));
    await monter(tester, const EcranFacturation());

    expect(find.byKey(const Key('facturation-registre-vide')), findsOneWidget);
    expect(
      find.text(TextesRegistreFacture.horsExercice(nombre: 1, annee: 2026)),
      findsOneWidget,
    );
  });

  testWidgets('un registre filtré vide ne prétend pas qu\'aucune facture '
      'n\'existe', (tester) async {
    await vente();
    await monter(tester, const EcranFacturation());
    await tester.enterText(
      find.byKey(const Key('facturation-recherche')),
      'zzz-introuvable',
    );
    await laisserTourner(tester);

    expect(find.byKey(const Key('facturation-registre-vide')), findsOneWidget);
    expect(
      find.byKey(const Key('facturation-registre-vide-aide')),
      findsNothing,
    );
  });

  testWidgets('la recherche retrouve une facture non normalisée par son '
      'numéro', (tester) async {
    await ParametresDepotLocal(
      db,
    ).inscrireDescendue('facturation_mode', 'boitier');
    final p = await vente();
    await monter(tester, const EcranFacturation());
    await tester.enterText(
      find.byKey(const Key('facturation-recherche')),
      p.numero,
    );
    await laisserTourner(tester);
    expect(find.byKey(Key('facturation-piece-${p.id}')), findsOneWidget);
  });

  testWidgets('page Proformas : un brouillon, une émise et une proforma reçue '
      'du serveur sont listés', (tester) async {
    final dao = ProformaDao(db, maintenant: () => DateTime(2026, 11, 9, 10));
    const lignes = [(designation: 'Salle', quantite: 2, prixUnitaire: 50000)];
    final brouillon = await dao.creer(
      clientNom: 'BROUILLON SARL',
      lignes: lignes,
    );
    final emise = await dao.creer(
      clientNom: 'EMISE SARL',
      lignes: lignes,
      emettre: true,
    );
    await dao.adopterDescendue(
      id: 'p-serveur',
      numero: 'N°0007 FP-GCN/2026',
      reference: 'GCN',
      statut: 'emise',
      clientId: null,
      clientNom: 'RECUE SARL',
      clientTelephone: null,
      clientIfu: null,
      objet: null,
      dateEmission: DateTime(2026, 11, 2),
      ville: null,
      valideJusquAu: null,
      total: 100000,
      factureId: null,
      motifAnnulation: null,
      sourceModule: 'hebergement',
      lignes: lignes,
    );
    await monter(tester, const EcranProformas());

    expect(find.byKey(const Key('proformas-vide')), findsNothing);
    expect(find.text('BROUILLON SARL'), findsOneWidget);
    expect(find.text('EMISE SARL'), findsOneWidget);
    expect(find.text('RECUE SARL'), findsOneWidget);
    expect(find.text('N°0007 FP-GCN/2026'), findsOneWidget);
    expect(find.text(emise.numero!), findsOneWidget);
    expect(find.text(brouillon.id), findsNothing);
  });

  testWidgets('page Proformas : plus de dix proformas restent toutes '
      'atteignables par la pagination', (tester) async {
    final dao = ProformaDao(db, maintenant: () => DateTime(2026, 11, 9, 10));
    const lignes = [(designation: 'Salle', quantite: 1, prixUnitaire: 1000)];
    for (var i = 1; i <= 12; i++) {
      await dao.creer(clientNom: 'CLIENT $i', lignes: lignes);
    }
    await monter(tester, const EcranProformas());

    expect(find.textContaining('CLIENT '), findsNWidgets(10));
    expect(find.byKey(const Key('proformas-pagination')), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('proformas-pagination-suivant')),
    );
    await tester.tap(find.byKey(const Key('proformas-pagination-suivant')));
    await tester.pumpAndSettle();
    expect(find.textContaining('CLIENT '), findsNWidgets(2));
  });

  testWidgets('page Proformas vide : l\'aide dit qu\'une réservation ne crée '
      'pas de facture et où créer une proforma', (tester) async {
    await monter(tester, const EcranProformas());

    expect(find.byKey(const Key('proformas-vide')), findsOneWidget);
    expect(find.byKey(const Key('proformas-vide-aide')), findsOneWidget);
    expect(find.text(TextesProforma.ui['vide_aide']!), findsOneWidget);
    expect(
      find.textContaining('Une réservation ne crée pas de facture'),
      findsOneWidget,
    );

    // Un filtre qui ne retient rien n'affiche pas l'aide « aucune proforma ».
    await tester.enterText(find.byKey(const Key('proformas-recherche')), 'zzz');
    await tester.pump();
    expect(find.byKey(const Key('proformas-vide-aide')), findsNothing);
  });
}
