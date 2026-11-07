import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/facturation/data/lecteur_mode_facturation.dart';
import 'package:tatacora_flutter/features/facturation/data/pilote_boitier.dart';
import 'package:tatacora_flutter/features/facturation/data/service_normalisation.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/piece_facturation.dart';
import 'package:tatacora_flutter/features/facturation/domain/repositories/facture_repository.dart';
import 'package:tatacora_flutter/features/facturation/presentation/ecran_facturation.dart';
import 'package:tatacora_flutter/features/facturation/presentation/providers_facturation.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_depot_local.dart';
import 'package:tatacora_flutter/features/transverse/data/configuration_poste.dart';

import '../../support/faux_pilote_boitier.dart';
import 'support/outils_encaissement.dart';

/// L'écran Facturation : l'indicateur d'état, le bouton « Normaliser » /
/// « Réessayer » / « Vérifier », seulement quand ce poste certifie par son
/// boîtier — sur une vraie base et un FAUX pilote.
void main() {
  HttpOverrides.global = null;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late FauxPilote faux;
  late Directory dossier;
  late String cheminPoste;

  setUp(() async {
    // `flutter_test` répond 400 à tout HttpClient : on parle à un VRAI faux pilote.
    HttpOverrides.global = null;
    db = await baseEncaissement();
    faux = await FauxPilote.demarrer();
    faux.surBill = (_) =>
        (statut: 200, corps: jsonEncode({'qr_code': qrDuPilote()}));
    dossier = await Directory.systemTemp.createTemp('tatacora-norm-ecran-');
    cheminPoste = '${dossier.path}/poste.json';
    final depot = ParametresDepotLocal(db);
    for (final e in {
      'facturation_mode': 'boitier',
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
    await faux.arreter();
    await db.close();
    if (dossier.existsSync()) await dossier.delete(recursive: true);
  });

  Future<void> laisserTourner(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump();
    }
  }

  Future<PieceFacturation> vente() => factureDaoSur(db).emettre(
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

  Future<void> monter(
    WidgetTester tester, {
    String niveau = 'C',
    double largeur = 1600,
  }) async {
    tester.view
      ..physicalSize = Size(largeur, 1000)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final droits = GardeAcces.depuisJson({'M2': niveau, 'M5': 'C'});
    final lecteur = LecteurModeFacturation(
      db,
      lecteur: LecteurConfigurationPoste(chemin: () async => cheminPoste),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          sessionProvider.overrideWithBuild(
            (ref, notifier) => Session(
              utilisateurId: caissierEssai,
              login: 'caissier',
              nom: 'Caissier',
              role: 'gerant',
              droits: droits,
            ),
          ),
          droitsProvider.overrideWithValue(droits),
          logoEtablissementProvider.overrideWith((ref) async => null),
          serviceNormalisationProvider.overrideWithValue(
            ServiceNormalisation(
              db,
              lecteur: lecteur,
              fabriquePilote: (_) => PiloteBoitier(
                racine: faux.racine,
                delaiInfo: const Duration(seconds: 5),
              ),
              attenteApresDelai: Duration.zero,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranFacturation()),
        ),
      ),
    );
    await laisserTourner(tester);
  }

  testWidgets('« Normaliser » : le boîtier est appelé, l’indicateur passe à '
      '« normalisée », le bouton disparaît', (tester) async {
    final p = await vente();
    await monter(tester);

    final bouton = find.byKey(Key('facturation-ligne-normaliser-${p.id}'));
    expect(bouton, findsOneWidget);
    expect(find.text('Normaliser'), findsOneWidget);
    expect(find.byKey(Key('facturation-normalisation-${p.id}')), findsNothing);

    await tester.tap(bouton);
    await laisserTourner(tester);

    expect(faux.corpsPost, hasLength(1));
    expect(
      find.descendant(
        of: find.byKey(Key('facturation-normalisation-${p.id}')),
        matching: find.text('normalisée'),
      ),
      findsOneWidget,
    );
    expect(find.text('Normaliser'), findsNothing, reason: 'plus de bouton');
    expect(find.text('Réessayer'), findsNothing);
    expect(find.textContaining('Facture normalisée : ED04000623-41'), findsOne);
    final n = (await factureDaoSur(db).parId(p.id))!;
    expect(n.estNormalisee, isTrue);
  });

  testWidgets('un échec laisse « en attente » avec « Réessayer », et la phrase '
      'du motif', (tester) async {
    faux.appareilAbsent = true;
    final p = await vente();
    await monter(tester);

    await tester.tap(find.byKey(Key('facturation-ligne-normaliser-${p.id}')));
    await laisserTourner(tester);

    expect(
      find.descendant(
        of: find.byKey(Key('facturation-normalisation-${p.id}')),
        matching: find.text('en attente de normalisation'),
      ),
      findsOneWidget,
    );
    expect(find.text('Réessayer'), findsOneWidget);
    expect(find.textContaining('n’est pas branché'), findsOneWidget);

    // Rebranché : « Réessayer » aboutit.
    faux.appareilAbsent = false;
    await tester.tap(find.byKey(Key('facturation-ligne-normaliser-${p.id}')));
    await laisserTourner(tester);
    expect(
      find.descendant(
        of: find.byKey(Key('facturation-normalisation-${p.id}')),
        matching: find.text('normalisée'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('« à vérifier » : le bouton se nomme « Vérifier » et ne reposte '
      'pas', (tester) async {
    faux
      ..couperApresTraitement = true
      ..surBill = (_) => (statut: 200, corps: '{}');
    final p = await vente();
    await monter(tester);
    await tester.tap(find.byKey(Key('facturation-ligne-normaliser-${p.id}')));
    await laisserTourner(tester);
    expect(find.text('Vérifier'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(Key('facturation-normalisation-${p.id}')),
        matching: find.text('à vérifier'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(Key('facturation-ligne-normaliser-${p.id}')));
    await laisserTourner(tester);
    expect(faux.corpsPost, hasLength(1), reason: 'jamais un second POST');
  });

  testWidgets('hors mode « boîtier » : aucun bouton, aucune requête', (
    tester,
  ) async {
    await ParametresDepotLocal(
      db,
    ).inscrireDescendue('facturation_mode', 'emecef');
    await vente();
    await monter(tester);
    expect(find.text('Normaliser'), findsNothing);
    expect(faux.requetes, isEmpty);
  });

  testWidgets('en lecture seule (M2 = L) : pas de bouton ; une facture '
      'normalisée n’en a plus', (tester) async {
    await vente();
    await monter(tester, niveau: 'L');
    expect(find.text('Normaliser'), findsNothing);
  });

  for (final largeur in [1100.0, 1600.0]) {
    testWidgets('aucun débordement, largeur $largeur, pièce en attente avec '
        'motif affiché', (tester) async {
      faux.appareilAbsent = true;
      final p = await vente();
      await monter(tester, largeur: largeur);
      await tester.tap(find.byKey(Key('facturation-ligne-normaliser-${p.id}')));
      await laisserTourner(tester);
      expect(tester.takeException(), isNull);
    });
  }
}
