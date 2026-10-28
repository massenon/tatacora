import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/format/formats.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/ecritures_serveur_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/moteur_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/ecran_comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/providers_comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/widgets/onglets_etats_financiers.dart';
import 'package:tatacora_flutter/features/synchronisation/presentation/providers_synchronisation.dart';

import 'support/outils_comptabilite.dart';

/// Le poste est opérationnel SANS le serveur : son compte de résultat et son
/// bilan se calculent sur ses propres écritures validées quand la
/// synchronisation est désactivée, ou quand rien n'a été reçu du serveur.
void main() {
  late AppDatabase db;
  late Directory dossier;
  final annee = DateTime.now().year;

  setUp(() async {
    db = await baseInstallee(maintenant: DateTime.now());
    dossier = await Directory.systemTemp.createTemp('tatacora-etats-');
  });
  tearDown(() async {
    await db.close();
    await dossier.delete(recursive: true);
  });

  /// Deux pièces VALIDÉES du poste : une vente de 25 000 F, un achat de
  /// 10 000 F — 15 000 F au net.
  Future<void> passerLesPiecesDuPoste() async {
    final dao = ComptabiliteDao(db);
    final restaurant = (await dao.centreParLibelle('Restaurant'))!.id;
    final moteur = moteurSur(db, maintenant: DateTime.now);
    final date = '$annee-03-04';
    await moteur.passerEtValider(
      DemandePiece(
        journal: 'VTE',
        date: date,
        libelle: 'Vente comptoir',
        lignes: [
          const LigneDemandee(compte: '5711', debitCentimes: 250000),
          LigneDemandee(
            compte: '7061',
            creditCentimes: 250000,
            centreId: restaurant,
          ),
        ],
      ),
      auteurId: auteurEssai,
    );
    await moteur.passerEtValider(
      DemandePiece(
        journal: 'CAI',
        date: date,
        libelle: 'Achat',
        lignes: [
          LigneDemandee(
            compte: '6011',
            debitCentimes: 100000,
            centreId: restaurant,
          ),
          const LigneDemandee(compte: '5711', creditCentimes: 100000),
        ],
      ),
      auteurId: auteurEssai,
    );
  }

  Future<void> recevoirDuServeur() async {
    final miroir = EcrituresServeurDao(db);
    Future<void> ligne(String id, String compte, {int d = 0, int c = 0}) =>
        miroir.ajouterSiAbsente(
          id: id,
          annee: annee,
          codeJournal: 'VTE',
          numeroCompte: compte,
          libelleCompte: 'Compte $compte',
          classe: compte.substring(0, 1),
          dateEcriture: '$annee-06-15',
          libelle: 'Pièce du serveur',
          debitCentimes: d,
          creditCentimes: c,
        );
    await ligne('s1', '5711', d: 900000);
    await ligne('s2', '7061', c: 900000);
  }

  Future<void> monter(
    WidgetTester tester, {
    required bool synchroActivee,
    String onglet = 'resultat',
  }) async {
    final fichier = File('${dossier.path}/poste.json');
    if (!synchroActivee) {
      fichier.writeAsStringSync('{"synchronisation_activee": false}');
    }
    tester.view
      ..physicalSize = const Size(1800, 3200)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final garde = GardeAcces.depuisJson(const {'M10': 'C'});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          cheminConfigurationPosteProvider.overrideWithValue(
            () async => fichier.path,
          ),
          moteurComptableProvider.overrideWith(
            (ref) async => moteurSur(db, maintenant: DateTime.now),
          ),
          droitsProvider.overrideWithValue(garde),
          sessionProvider.overrideWithBuild(
            (ref, notifier) => Session(
              utilisateurId: auteurEssai,
              login: 'compta-$auteurEssai',
              nom: 'Comptable',
              role: 'comptable',
              droits: garde,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: Scaffold(body: EcranComptabilite(ongletInitial: onglet)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String fcfa(int centimes) =>
      formaterMontantDecimal('${centimes ~/ 100}.00', suffixe: 'FCFA')!;
  String net(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('compta-resultat-net'))).data!;

  testWidgets('rien reçu du serveur : le résultat vient des pièces du poste, '
      'et le dit', (tester) async {
    await passerLesPiecesDuPoste();
    await monter(tester, synchroActivee: true);

    expect(net(tester), fcfa(150000));
    expect(find.text(TextesEtatsFinanciers.piecesDuPoste), findsOneWidget);
  });

  testWidgets('synchronisation DÉSACTIVÉE : les pièces du poste, même si le '
      'serveur en a envoyé d’autres', (tester) async {
    await passerLesPiecesDuPoste();
    await recevoirDuServeur();
    await monter(tester, synchroActivee: false);

    expect(net(tester), fcfa(150000), reason: 'le miroir n’est pas mêlé');
    expect(find.text(TextesEtatsFinanciers.piecesDuPoste), findsOneWidget);
  });

  testWidgets('synchronisation ACTIVÉE et écritures reçues : le miroir du '
      'serveur reste la source', (tester) async {
    await passerLesPiecesDuPoste();
    await recevoirDuServeur();
    await monter(tester, synchroActivee: true);

    expect(net(tester), fcfa(900000));
    expect(find.text(TextesEtatsFinanciers.piecesDuPoste), findsNothing);
  });

  testWidgets('les six indicateurs du bandeau sont CALCULÉS, plus de « — »', (
    tester,
  ) async {
    await passerLesPiecesDuPoste();
    await monter(tester, synchroActivee: false);

    String indicateur(String libelle) => tester
        .widget<Text>(find.byKey(Key('compta-indicateur-$libelle')))
        .data!;
    expect(indicateur("Chiffre d'affaires"), fcfa(250000));
    expect(indicateur('Résultat net'), fcfa(150000));
    // La banque : 2 500 F encaissés, 1 000 F payés.
    expect(indicateur('Trésorerie'), fcfa(150000));
    expect(find.text('Équilibré'), findsOneWidget);
  });

  testWidgets('Grand livre : un compte à la fois, soldes progressifs, '
      'totaux, ouverture et clôture', (tester) async {
    await passerLesPiecesDuPoste();
    await monter(tester, synchroActivee: false, onglet: 'grandlivre');

    expect(
      find.byKey(const Key('compta-non-calcule-grandlivre')),
      findsNothing,
    );
    // Le premier compte mouvementé par numéro : 5711, débit 2 500 - crédit 1 000.
    expect(
      tester
          .widget<Text>(find.byKey(const Key('compta-grand-livre-total')))
          .data,
      '${fcfa(150000)} D',
    );
    expect(
      find.byKey(const Key('compta-grand-livre-ouverture')),
      findsOneWidget,
    );
  });

  testWidgets('Analytique : la marge par centre et le total', (tester) async {
    await passerLesPiecesDuPoste();
    await monter(tester, synchroActivee: false, onglet: 'analytique');

    expect(
      find.byKey(const Key('compta-non-calcule-analytique')),
      findsNothing,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('compta-analytique-total-marge')))
          .data,
      fcfa(150000),
    );
    expect(find.text('Restaurant'), findsOneWidget);
  });

  Future<void> ouvrirTuile(WidgetTester tester, int rang) async {
    final tuile = find.byKey(Key('compta-tuile-$rang'));
    await tester.ensureVisible(tuile);
    await tester.pumpAndSettle();
    await tester.tap(tuile);
    await tester.pumpAndSettle();
  }

  testWidgets('la tuile « Flux de trésorerie » ouvre le TAFIRE CALCULÉ sur ce '
      'poste, cohérent', (tester) async {
    await passerLesPiecesDuPoste();
    await monter(tester, synchroActivee: false);
    await ouvrirTuile(tester, 4);

    expect(find.byKey(const Key('modale-flux-tresorerie')), findsOneWidget);
    String t(String cle) => tester.widget<Text>(find.byKey(Key(cle))).data!;
    // CAFG = résultat (1 500 F) ; ressources = CAFG ; la variation de
    // trésorerie réelle = la banque : 2 500 − 1 000.
    expect(t('flux-cafg'), fcfa(150000));
    expect(t('flux-total-ressources'), fcfa(150000));
    expect(t('flux-reelle'), fcfa(150000));
    expect(
      find.textContaining('Contrôle de cohérence réussi', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('la tuile « Notes annexes » ouvre les sept notes, dont les '
      'deux qui disent pourquoi elles sont indisponibles', (tester) async {
    await passerLesPiecesDuPoste();
    await monter(tester, synchroActivee: false);
    await ouvrirTuile(tester, 5);

    expect(find.byKey(const Key('modale-notes-annexes')), findsOneWidget);
    for (final n in [
      '1. Règles et méthodes comptables',
      '5. État des stocks',
      '6. Effectif du personnel',
      '7. Événements postérieurs à la clôture',
    ]) {
      expect(find.text(n), findsOneWidget, reason: n);
    }
    expect(
      tester.widget<Text>(find.byKey(const Key('note-6-motif'))).data,
      "L'effectif relève des ressources humaines, hors de la comptabilité.",
    );
  });

  testWidgets('la tuile « États financiers » réunit Bilan, Résultat, Flux et '
      'Notes', (tester) async {
    await passerLesPiecesDuPoste();
    await monter(tester, synchroActivee: false);
    await ouvrirTuile(tester, 10);

    expect(find.byKey(const Key('modale-etats-financiers')), findsOneWidget);
    for (final o in ['bilan', 'resultat', 'flux', 'notes']) {
      expect(find.byKey(Key('etats-onglet-$o')), findsOneWidget, reason: o);
    }
    await tester.tap(find.byKey(const Key('etats-onglet-flux')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('flux-cafg')), findsOneWidget);
  });
}
