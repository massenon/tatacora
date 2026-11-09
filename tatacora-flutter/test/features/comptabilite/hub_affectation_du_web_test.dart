import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/impression/entete_etablissement.dart';
import 'package:tatacora_flutter/core/impression/entete_parametree.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/comptabilite/data/affectation_resultat_locale.dart';
import 'package:tatacora_flutter/features/comptabilite/data/affectations_recues_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/cloture_exercice_locale.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/moteur_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/entities/comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/ecran_comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/exercice_consulte.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/providers_cloture.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/providers_comptabilite.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import '../../support/selecteur_essai.dart';
import 'support/outils_comptabilite.dart';

/// La carte « Affectation du résultat de l'exercice N-1 » quand l'affectation a été
/// passée AILLEURS (le web, un autre poste) — v53, 09/11/2026, PO : « ÇA DOIT
/// APPARAÎTRE ». Menée sur une VRAIE base en mémoire, l'affectation reçue étant
/// inscrite par son seul écrivain (celui de la descente) :
///
///  - « Affectation passée le … par … (pièce n° …) » et la ventilation reçue ;
///  - plus de bouton « Passer l'affectation » (l'unicité est connue du poste) ;
///  - contre-passée au web, la carte offre de nouveau « Passer l'affectation », et le
///    geste enfile une pièce comme d'habitude ;
///  - l'affectation de CE poste reprise par le serveur ne s'affiche pas deux fois.
///
/// La clôture est faite ailleurs : ce poste n'a que le statut et la date de l'exercice.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late ComptabiliteDao dao;
  late Directory archives;
  late SelecteurEssai selecteur;
  final annee = DateTime.now().year - 1;

  setUp(() async {
    db = await baseInstallee(maintenant: DateTime.now());
    dao = ComptabiliteDao(db);
    archives = await Directory.systemTemp.createTemp('hub_affectation_web_');
    selecteur = SelecteurEssai();
    await dao.alignerExerciceDescendu(
      annee: annee,
      dateDebut: '$annee-01-01',
      dateFin: '$annee-12-31',
      statut: StatutExercice.cloture,
      dateCloture: DateTime(annee + 1, 1, 10, 9),
    );
    await dao.alignerExerciceDescendu(
      annee: annee + 1,
      dateDebut: '${annee + 1}-01-01',
      dateFin: '${annee + 1}-12-31',
      statut: StatutExercice.ouvert,
    );
  });
  tearDown(() async {
    await db.close();
    if (archives.existsSync()) await archives.delete(recursive: true);
  });

  Future<void> recevoir({
    String id = 'aff-web',
    String piece = 'OD-0001',
    String? pieceOrigine,
    DateTime? contrepasseeLe,
    int? pourAnnee,
  }) => AffectationsRecuesDao(db).inscrire(
    AffectationRecueDuServeur(
      id: id,
      annee: pourAnnee ?? annee,
      resultatCentimes: 7000000,
      dateApprobation: '${annee + 1}-04-30',
      reserveLegaleCentimes: 700000,
      autresReservesCentimes: 0,
      dividendesCentimes: 1000000,
      reportCrediteurCentimes: 5300000,
      reportDebiteurCentimes: 0,
      numeroPiece: piece,
      pieceOrigineId: pieceOrigine,
      auteurLogin: 'comptable-web',
      affecteeLe: DateTime(annee + 1, 5, 2, 14, 30),
      contrepasseeLe: contrepasseeLe,
    ),
  );

  Future<void> monter(WidgetTester tester, {int? anneeChoisie}) async {
    tester.view
      ..physicalSize = const Size(1800, 4200)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final garde = GardeAcces.depuisJson({'M10': 'C'});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          sansFichierDePoste(),
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
          dossierArchivesProvider.overrideWithValue(() async => archives),
          lireEnteteEtablissementProvider.overrideWithValue(
            () async => const EnteteEtablissement(),
          ),
          ...selecteur.surcharges,
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(
            body: EcranComptabilite(ongletInitial: 'clotures'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final choisi = (await dao.exerciceDeLAnnee(anneeChoisie ?? annee))!;
    ProviderScope.containerOf(
      tester.element(find.byType(EcranComptabilite)),
    ).read(exerciceChoisiProvider.notifier).choisir(choisi.id);
    await tester.pumpAndSettle();
  }

  Finder texte(String t) => find.textContaining(t);

  Future<void> taper(WidgetTester tester, String cle) async {
    final bouton = find.byKey(Key(cle));
    await tester.ensureVisible(bouton);
    await tester.tap(bouton);
    await tester.pumpAndSettle();
  }

  testWidgets('sans aucune affectation reçue, la clôture faite ailleurs ne '
      'donne pas de carte (le résultat est inconnu)', (tester) async {
    await monter(tester);
    expect(find.byKey(const Key('compta-affectation')), findsNothing);
  });

  testWidgets('une affectation passée au web APPARAÎT : date, auteur, pièce, '
      'ventilation ; pas de « Passer », pas de contre-passation ici', (
    tester,
  ) async {
    await recevoir();
    await monter(tester);

    expect(find.byKey(const Key('compta-affectation')), findsOneWidget);
    expect(
      texte(
        'Affectation passée le 02/05/${annee + 1} 14:30 par comptable-web (pièce n° OD-0001).',
      ),
      findsOneWidget,
    );
    expect(find.text('• Réserve légale : 7 000 FCFA'), findsOneWidget);
    expect(find.text('• Dividendes : 10 000 FCFA'), findsOneWidget);
    expect(find.text('• Report à nouveau : 53 000 FCFA'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('compta-affectation-resultat')),
        matching: find.text('70 000 FCFA'),
      ),
      findsOneWidget,
    );
    // « Passer l'affectation » est remplacé : ni bouton, ni champ de ventilation.
    expect(find.byKey(const Key('compta-affectation-passer')), findsNothing);
    expect(
      find.byKey(const Key('compta-affectation-dividendes')),
      findsNothing,
    );
    // La pièce est au serveur : ce poste ne la contre-passe pas, et le dit.
    expect(
      find.byKey(const Key('compta-affectation-contrepasser')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('compta-affectation-ailleurs')),
      findsOneWidget,
    );
    // Lire ne fait RIEN partir.
    expect(await OperationsSyncDao(db).operations(), isEmpty);
  });

  testWidgets('contre-passée au web : « Passer l’affectation » réapparaît, et '
      'le geste passe la pièce', (tester) async {
    await recevoir(contrepasseeLe: DateTime(annee + 1, 5, 10, 9));
    await monter(tester);

    expect(
      find.byKey(const Key('compta-affectation-passee-texte')),
      findsNothing,
    );
    expect(find.byKey(const Key('compta-affectation-passer')), findsOneWidget);

    await taper(tester, 'compta-affectation-passer');
    await taper(tester, 'compta-affectation-confirmer');

    expect(
      find.byKey(const Key('compta-affectation-passee-texte')),
      findsOneWidget,
    );
    final pieces = await OperationsSyncDao(
      db,
    ).operations(table: TableSynchronisee.piecesSaisie);
    expect(pieces, hasLength(1), reason: 'refaite ICI : une pièce enfilée');
  });

  testWidgets('l’affectation de CE poste, reprise par le serveur, ne s’affiche '
      'pas deux fois : une seule carte, la pièce du poste, contre-passable ici', (
    tester,
  ) async {
    // Une clôture faite PAR CE POSTE, dans l'année courante, puis SON affectation.
    final y = DateTime.now().year;
    final moteur = moteurSur(db, maintenant: DateTime.now);
    final centres = {for (final c in await dao.centres()) c.libelle: c.id};
    await moteur.passerEtValider(
      DemandePiece(
        journal: 'CAI',
        date: '$y-03-10',
        libelle: 'Ventes bar',
        lignes: [
          LigneDemandee(
            compte: '5711',
            debitCentimes: 10000000,
            centreId: centres['Bar'],
          ),
          LigneDemandee(
            compte: '7011',
            creditCentimes: 10000000,
            centreId: centres['Bar'],
          ),
        ],
      ),
      auteurId: auteurEssai,
    );
    final clotures = ClotureExerciceLocale(
      db,
      moteur,
      maintenant: DateTime.now,
    );
    final id = (await dao.exerciceDeLAnnee(y))!.id;
    await clotures.demarrer(id, auteurId: auteurEssai);
    await clotures.cloturer(id, auteurId: auteurEssai);
    final numeroLocal =
        await AffectationResultatLocale(
          db,
          moteur,
          maintenant: DateTime.now,
        ).affecter(
          id,
          ventilation: {'report_a_nouveau': 10000000},
          date: '${y + 1}-04-30',
          auteurId: auteurEssai,
        );
    final origine = await db
        .customSelect('SELECT id FROM pieces_saisie_local')
        .getSingle()
        .then((r) => r.data['id']! as String);

    // Le serveur l'a reprise : sa ligne porte l'identifiant d'origine de la pièce du poste.
    await recevoir(
      id: 'aff-reprise',
      piece: 'OD-0099',
      pieceOrigine: origine,
      pourAnnee: y,
    );
    await monter(tester, anneeChoisie: y);

    expect(
      find.byKey(const Key('compta-affectation-passee-texte')),
      findsOneWidget,
      reason: 'UNE seule affectation affichée',
    );
    expect(texte('(pièce n° $numeroLocal)'), findsOneWidget);
    expect(texte('OD-0099'), findsNothing);
    expect(find.byKey(const Key('compta-affectation-ailleurs')), findsNothing);
    expect(
      find.byKey(const Key('compta-affectation-contrepasser')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('compta-affectation-passer')), findsNothing);
  });
}
