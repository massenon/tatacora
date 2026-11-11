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
import 'package:tatacora_flutter/features/facturation/domain/entities/piece_facturation.dart';
import 'package:tatacora_flutter/features/facturation/domain/repositories/facture_repository.dart';
import 'package:tatacora_flutter/features/facturation/presentation/ecran_facturation.dart';
import 'package:tatacora_flutter/features/facturation/presentation/providers_facturation.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_depot_local.dart';
import 'package:tatacora_flutter/features/synchronisation/presentation/providers_synchronisation.dart'
    show cheminConfigurationPosteProvider;

import 'support/outils_encaissement.dart';

import 'package:tatacora_flutter/features/facturation/data/facture_dao.dart';
import 'package:tatacora_flutter/features/facturation/impression/etat_registre_factures.dart';

/// La colonne « N° » du registre au poste (PO, 09/11/2026) : le numéro FISCAL quand la facture est normalisée,
/// SINON le numéro INTERNE (provisoire `PROV-…` tant que le serveur n'a pas régularisé, puis `F-…`) suivi de la
/// légende « n° interne » — jamais « — ». Facture simple : aucune mention de normalisation. La recherche trouve
/// par l'un ou l'autre ; l'export et le PDF portent la même valeur que l'écran.
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

  const fiscal = 'ED04000623-41';

  Future<void> poser(String id, String statut) async {
    final reel = statut == 'normalisee';
    await db.customStatement(
      'UPDATE pieces_facturation_local SET normalisation_statut = ?, '
      'normalisation_mode = ?, numero_mecef = ?, qr_code_fiscal = ? WHERE id = ?',
      [
        statut,
        'boitier',
        reel ? fiscal : null,
        reel ? 'F;ED04000623;ABCDEFGH;3201910768821;20261107101500' : null,
        id,
      ],
    );
  }

  Finder numero(String id) => find.byKey(Key('facturation-numero-$id'));
  Finder legende(String id) =>
      find.byKey(Key('facturation-numero-interne-$id'));

  testWidgets('une facture normalisée affiche son numéro fiscal, sans légende '
      'ni numéro interne', (tester) async {
    await ParametresDepotLocal(
      db,
    ).inscrireDescendue('facturation_mode', 'boitier');
    final p = await vente();
    await poser(p.id, 'normalisee');
    await monter(tester, const EcranFacturation());

    expect(
      find.descendant(of: numero(p.id), matching: find.text(fiscal)),
      findsOneWidget,
    );
    expect(legende(p.id), findsNothing);
    expect(find.text(p.numero), findsNothing);
    expect(find.text('—'), findsNothing);
  });

  testWidgets('une facture simple (mode désactivé) affiche son numéro interne '
      'provisoire, la légende, et rien sur la normalisation', (tester) async {
    await ParametresDepotLocal(
      db,
    ).inscrireDescendue('facturation_mode', 'desactive');
    final p = await vente();
    expect(p.estProvisoire, isTrue, reason: 'poste synchronisé : PROV-…');
    await monter(tester, const EcranFacturation());

    expect(
      find.descendant(of: numero(p.id), matching: find.text(p.numero)),
      findsOneWidget,
    );
    expect(legende(p.id), findsOneWidget);
    expect(find.text('n° interne'), findsOneWidget);
    final ligne = find.byKey(Key('facturation-piece-${p.id}'));
    expect(
      find.descendant(of: ligne, matching: find.textContaining('ormalis')),
      findsNothing,
      reason: 'facture simple : aucune mention de normalisation',
    );
  });

  testWidgets('refusée et à vérifier : numéro interne et statut côte à côte', (
    tester,
  ) async {
    await ParametresDepotLocal(
      db,
    ).inscrireDescendue('facturation_mode', 'boitier');
    final refusee = await vente();
    final averifier = await vente();
    await poser(refusee.id, 'refusee');
    await poser(averifier.id, 'a_verifier');
    await monter(tester, const EcranFacturation());

    for (final p in [refusee, averifier]) {
      expect(
        find.descendant(of: numero(p.id), matching: find.text(p.numero)),
        findsOneWidget,
      );
      expect(legende(p.id), findsOneWidget);
    }
    expect(
      find.descendant(
        of: find.byKey(Key('facturation-normalisation-${refusee.id}')),
        matching: find.text('refusée'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(Key('facturation-normalisation-${averifier.id}')),
        matching: find.text('à vérifier'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('le serveur régularise : le numéro provisoire cède la place au '
      'numéro continu, la légende reste', (tester) async {
    await ParametresDepotLocal(
      db,
    ).inscrireDescendue('facturation_mode', 'desactive');
    final p = await vente();
    final provisoire = p.numero;
    await FactureDao(db).regulariserNumeros(p.id, numero: 'F-2026-00042');
    await monter(tester, const EcranFacturation());

    expect(find.text(provisoire), findsNothing);
    expect(
      find.descendant(of: numero(p.id), matching: find.text('F-2026-00042')),
      findsOneWidget,
    );
    expect(legende(p.id), findsOneWidget);
  });

  testWidgets('la recherche trouve par le numéro fiscal comme par le numéro '
      'interne', (tester) async {
    await ParametresDepotLocal(
      db,
    ).inscrireDescendue('facturation_mode', 'boitier');
    final normalisee = await vente();
    final simple = await vente();
    await poser(normalisee.id, 'normalisee');
    await monter(tester, const EcranFacturation());

    Future<void> chercher(String t) async {
      await tester.enterText(find.byKey(const Key('facturation-recherche')), t);
      await laisserTourner(tester);
    }

    await chercher(fiscal);
    expect(
      find.byKey(Key('facturation-piece-${normalisee.id}')),
      findsOneWidget,
    );
    expect(find.byKey(Key('facturation-piece-${simple.id}')), findsNothing);

    await chercher(normalisee.numero);
    expect(
      find.byKey(Key('facturation-piece-${normalisee.id}')),
      findsOneWidget,
    );
    expect(find.byKey(Key('facturation-piece-${simple.id}')), findsNothing);

    await chercher(simple.numero);
    expect(find.byKey(Key('facturation-piece-${simple.id}')), findsOneWidget);
    expect(find.byKey(Key('facturation-piece-${normalisee.id}')), findsNothing);
  });

  test('l\'export (tableur et PDF) porte la même valeur que l\'écran, avoir '
      'compris', () async {
    final normalisee = await vente();
    final simple = await vente();
    await poser(normalisee.id, 'normalisee');
    final dao = FactureDao(db);
    final pieces = [
      for (final p in [normalisee, simple]) (await dao.parId(p.id))!,
    ];
    final etat = EtatRegistreFactures(
      pieces: pieces,
      filtre: 'Toutes périodes',
    );

    expect(etat.cellules(pieces[0]).first, fiscal);
    expect(etat.cellules(pieces[1]).first, simple.numero);
    final csv = etat.csv();
    expect(csv, contains('"$fiscal"'));
    expect(csv, contains('"${simple.numero}"'));
    expect(csv, isNot(contains('"${normalisee.numero}"')));
    expect((await etat.pdf()).length, greaterThan(500));

    // Un avoir : même règle (son numéro interne `PROV-…`, pas « — »).
    final avoir = (await factureDaoSur(db).annuler(simple.id, 'Erreur')).avoir;
    expect(etat.cellules(avoir).first, avoir.numero);
    expect(avoir.numeroRegistreEstInterne, isTrue);
  });
}
