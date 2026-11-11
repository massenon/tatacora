import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/fichiers/selecteur_fichiers.dart';
import 'package:tatacora_flutter/core/impression/entete_etablissement.dart';
import 'package:tatacora_flutter/core/impression/entete_parametree.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
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

/// L'onglet « Clôtures » du hub (26/10/2026) : la clôture annuelle SYSCOHADA
/// menée AU CLIC, sur une VRAIE base en mémoire, écrite par le VRAI moteur —
/// démarrer, clôturer (pièces CL et AN, archive et son empreinte), rouvrir (le
/// comptable seul), télécharger l'archive. Chaque geste RELIT la base : un
/// bouton qui n'écrirait rien rougit (piège 5).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late ComptabiliteDao dao;
  late Directory archives;
  late SelecteurEssai selecteur;
  final annee = DateTime.now().year;

  setUp(() async {
    db = await baseInstallee(maintenant: DateTime.now());
    dao = ComptabiliteDao(db);
    archives = await Directory.systemTemp.createTemp('hub_clotures_');
    selecteur = SelecteurEssai();
  });
  tearDown(() async {
    await db.close();
    if (archives.existsSync()) await archives.delete(recursive: true);
  });

  Future<void> exploiter({bool brouillon = false}) async {
    final moteur = moteurSur(db, maintenant: DateTime.now);
    final centres = {for (final c in await dao.centres()) c.libelle: c.id};
    Future<void> piece(
      String libelle,
      String debit,
      String credit,
      int montant,
      String centre, {
      bool valide = true,
    }) async {
      final demande = DemandePiece(
        journal: 'CAI',
        date: '$annee-03-10',
        libelle: libelle,
        lignes: [
          LigneDemandee(
            compte: debit,
            debitCentimes: montant,
            centreId: centres[centre],
          ),
          LigneDemandee(
            compte: credit,
            creditCentimes: montant,
            centreId: centres[centre],
          ),
        ],
      );
      valide
          ? await moteur.passerEtValider(demande, auteurId: auteurEssai)
          : await moteur.passer(demande, auteurId: auteurEssai);
    }

    await piece('Ventes bar', '5711', '7011', 10000000, 'Bar');
    await piece('Marché', '6011', '5711', 3000000, 'Restaurant');
    if (brouillon) {
      await piece('En attente', '6011', '5711', 100, 'Bar', valide: false);
    }
  }

  ClotureExerciceLocale serviceDirect() => ClotureExerciceLocale(
    db,
    moteurSur(db, maintenant: DateTime.now),
    maintenant: DateTime.now,
  );

  Future<String> idExercice() async => (await dao.exerciceDeLAnnee(annee))!.id;

  Future<void> monter(
    WidgetTester tester, {
    String role = 'comptable',
    String droit = 'C',
    Directory? racineArchives,
  }) async {
    tester.view
      ..physicalSize = const Size(1800, 3600)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final garde = GardeAcces.depuisJson({'M10': droit});
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
              role: role,
              droits: garde,
            ),
          ),
          dossierArchivesProvider.overrideWithValue(
            () async => racineArchives ?? archives,
          ),
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
    // Un exercice en clôture n'est plus le défaut du sélecteur (l'ouvert le
    // plus récent, N+1) : on le CHOISIT, comme au sélecteur de la barre.
    final choisi = (await dao.exerciceDeLAnnee(annee))!;
    if (choisi.statut != StatutExercice.ouvert) {
      ProviderScope.containerOf(
        tester.element(find.byType(EcranComptabilite)),
      ).read(exerciceChoisiProvider.notifier).choisir(choisi.id);
      await tester.pumpAndSettle();
    }
  }

  /// Laisse les écritures de fichiers (le vrai disque) se terminer, puis
  /// relit l'écran : `flutter_test` ne les attend pas.
  Future<void> attendre(WidgetTester tester, Finder jusqua) async {
    for (var i = 0; i < 40 && jusqua.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
    }
  }

  Finder texte(String t) => find.textContaining(t);

  Future<void> taper(WidgetTester tester, String cle) async {
    final bouton = find.byKey(Key(cle));
    await tester.ensureVisible(bouton);
    await tester.tap(bouton);
    await tester.pumpAndSettle();
  }

  group('La carte de clôture de l’exercice consulté', () {
    testWidgets('le résultat à reporter, ses blocages et ses avertissements, '
        'aux mots de la vue', (tester) async {
      await exploiter();
      await monter(tester);

      expect(texte("Clôture de l'exercice $annee"), findsOneWidget);
      expect(
        texte('Trois opérations enchaînées : solde des comptes de gestion'),
        findsOneWidget,
      );
      final resultat = find.byKey(const Key('compta-cloture-resultat'));
      expect(
        find.descendant(
          of: resultat,
          matching: find.text('RÉSULTAT À REPORTER'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: resultat, matching: find.text('70 000 FCFA')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: resultat,
          matching: find.text('Vers le compte 131 (bénéfice)'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('compta-cloture-controles-ok')),
        findsOneWidget,
      );
      expect(
        texte('Tous les contrôles bloquants sont satisfaits.'),
        findsOneWidget,
      );
      // L'impôt non comptabilisé avertit sans bloquer.
      expect(
        find.descendant(
          of: find.byKey(const Key('compta-cloture-avertissements')),
          matching: find.textContaining(
            "Aucun impôt sur le résultat n'est comptabilisé en classe 89.",
          ),
        ),
        findsOneWidget,
      );
      // Le poste DIT ce qu'il fait : ses pièces, une demande au serveur.
      expect(
        find.byKey(const Key('compta-cloture-note-du-poste')),
        findsOneWidget,
      );
    });

    testWidgets('une perte se lit « Vers le compte 139 (perte) », en rouge', (
      tester,
    ) async {
      final moteur = moteurSur(db, maintenant: DateTime.now);
      final centres = {for (final c in await dao.centres()) c.libelle: c.id};
      await moteur.passerEtValider(
        DemandePiece(
          journal: 'CAI',
          date: '$annee-03-11',
          libelle: 'Marché',
          lignes: [
            LigneDemandee(
              compte: '6011',
              debitCentimes: 500000,
              centreId: centres['Bar'],
            ),
            LigneDemandee(
              compte: '5711',
              creditCentimes: 500000,
              centreId: centres['Bar'],
            ),
          ],
        ),
        auteurId: auteurEssai,
      );
      await monter(tester);
      final resultat = find.byKey(const Key('compta-cloture-resultat'));
      expect(
        find.descendant(of: resultat, matching: find.text('-5 000 FCFA')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: resultat,
          matching: find.text('Vers le compte 139 (perte)'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('un brouillon BLOQUE : le compte, la phrase, plus de « tout '
        'est satisfait »', (tester) async {
      await exploiter(brouillon: true);
      await monter(tester);

      expect(
        find.descendant(
          of: find.byKey(const Key('compta-cloture-nb-blocages')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('compta-cloture-controles-ok')),
        findsNothing,
      );
      final blocages = find.byKey(const Key('compta-cloture-blocages'));
      expect(
        find.descendant(
          of: blocages,
          matching: find.text("La clôture est impossible en l'état :"),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: blocages,
          matching: find.textContaining('Des écritures restent en brouillon.'),
        ),
        findsOneWidget,
      );
    });
  });

  group('Démarrer la clôture, reprendre la saisie', () {
    testWidgets('« Démarrer » met l’exercice EN CLÔTURE, enfile la demande et '
        'change le geste proposé', (tester) async {
      await exploiter();
      await monter(tester);

      expect(find.byKey(const Key('compta-cloture-demarrer')), findsOneWidget);
      expect(texte('Démarrer la clôture de l’exercice $annee'), findsWidgets);
      await taper(tester, 'compta-cloture-demarrer');

      expect(
        (await dao.exerciceDeLAnnee(annee))!.statut,
        StatutExercice.enCloture,
      );
      expect(
        find.text(
          'Exercice $annee en clôture : les modules n’y passent plus de pièce.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('compta-cloture-demarrer')), findsNothing);
      expect(find.byKey(const Key('compta-cloture-cloturer')), findsOneWidget);
      expect(find.byKey(const Key('compta-cloture-reprendre')), findsOneWidget);
      expect(texte('En clôture'), findsWidgets);

      final file = await OperationsSyncDao(
        db,
      ).operations(table: TableSynchronisee.demandesClotureExercice);
      expect(file, hasLength(1));
      expect(file.single.payload, contains('"action":"demarrer"'));
      expect(file.single.payload, contains('"annee":$annee'));
    });

    testWidgets('« Reprendre la saisie » rouvre l’exercice aux modules', (
      tester,
    ) async {
      await exploiter();
      await serviceDirect().demarrer(await idExercice(), auteurId: auteurEssai);
      await monter(tester);

      await taper(tester, 'compta-cloture-reprendre');

      expect(
        (await dao.exerciceDeLAnnee(annee))!.statut,
        StatutExercice.ouvert,
      );
      expect(
        find.text('Exercice $annee rouvert à la saisie des modules.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('compta-cloture-demarrer')), findsOneWidget);
    });

    testWidgets('sans droit d’écriture, le bouton DIT le refus et rien ne '
        'bouge', (tester) async {
      await exploiter();
      await monter(tester, droit: 'L');
      await taper(tester, 'compta-cloture-demarrer');

      expect(
        find.byKey(const Key('compta-cloture-sans-droit')),
        findsOneWidget,
      );
      expect(
        (await dao.exerciceDeLAnnee(annee))!.statut,
        StatutExercice.ouvert,
      );
      expect(
        await OperationsSyncDao(db).operations(),
        isEmpty,
        reason: 'aucune demande n’est enfilée',
      );
    });
  });

  group('Clôturer définitivement', () {
    testWidgets('un brouillon : le refus est DIT à la phrase du serveur, '
        'rien n’est écrit', (tester) async {
      await exploiter(brouillon: true);
      await serviceDirect().demarrer(await idExercice(), auteurId: auteurEssai);
      await monter(tester);
      final avant = (await dao.toutesLesEcritures()).length;

      await taper(tester, 'compta-cloture-cloturer');

      final erreur = find.byKey(const Key('compta-cloture-erreur'));
      expect(erreur, findsOneWidget);
      expect(
        tester.widget<Text>(erreur).data,
        "L'exercice $annee ne peut pas être clôturé : Des écritures restent "
        'en brouillon.',
      );
      expect((await dao.toutesLesEcritures()).length, avant);
      expect(
        (await dao.exerciceDeLAnnee(annee))!.statut,
        StatutExercice.enCloture,
      );
    });

    testWidgets('la clôture passe : pièces CL et AN, verrou, archive et son '
        'EMPREINTE à l’écran, résultat dans la liste', (tester) async {
      await exploiter();
      await serviceDirect().demarrer(await idExercice(), auteurId: auteurEssai);
      await monter(tester);

      await taper(tester, 'compta-cloture-cloturer');
      await attendre(tester, find.byKey(const Key('compta-archive-empreinte')));

      final ex = (await dao.exerciceDeLAnnee(annee))!;
      expect(ex.statut, StatutExercice.cloture);
      final lignes = await dao.lignesPourArchive(ex.id);
      expect(
        lignes
            .where((l) => l.codeJournal == 'CL')
            .map((l) => l.numeroPiece)
            .toSet(),
        {'CL-$annee-00001'},
      );
      final suivant = (await dao.exerciceDeLAnnee(annee + 1))!;
      expect(
        (await dao.lignesPourArchive(suivant.id))
            .where((l) => l.codeJournal == 'AN')
            .map((l) => l.numeroPiece)
            .toSet(),
        {'AN-${annee + 1}-00001'},
      );

      expect(
        find.text(
          'Exercice $annee clôturé : comptes de gestion soldés, à-nouveaux '
          'reportés, exercice verrouillé.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'pièce de clôture CL-$annee-00001, à-nouveaux '
          'AN-${annee + 1}-00001.',
        ),
        findsOneWidget,
      );
      // L'empreinte SHA-256 de l'archive est AFFICHÉE, et c'est celle de la base.
      final cloture = (await serviceDirect().clotureActive(ex.id))!;
      expect(cloture.archiveEmpreinte, hasLength(64));
      expect(
        tester
            .widget<Text>(find.byKey(const Key('compta-archive-empreinte')))
            .textSpan!
            .toPlainText(),
        contains(cloture.archiveEmpreinte!),
      );
      expect(
        find.byKey(const Key('compta-archive-telecharger')),
        findsOneWidget,
      );
      expect(
        Directory('${archives.path}/${cloture.archiveChemin}').existsSync(),
        isTrue,
      );
      // Le résultat reporté est dans la liste des exercices (70 000 FCFA).
      expect(
        find.descendant(
          of: find.byKey(const Key('compta-exercices')),
          matching: find.text('70 000 FCFA'),
        ),
        findsOneWidget,
      );
      // Les demandes : démarrer (directe), puis clôturer.
      final actions = (await OperationsSyncDao(db).operations(
        table: TableSynchronisee.demandesClotureExercice,
      )).map((o) => o.payload).toList();
      expect(actions, hasLength(2));
      expect(actions.last, contains('"action":"cloturer"'));
    });

    testWidgets('une archive qui ÉCHOUE ne défait pas la clôture : l’onglet '
        'propose « Générer l’archive »', (tester) async {
      await exploiter();
      await serviceDirect().demarrer(await idExercice(), auteurId: auteurEssai);
      // Un FICHIER là où le dossier des archives devrait être : écrire échoue.
      final bouche = File('${archives.path}/pas_un_dossier')
        ..writeAsStringSync('x');
      await monter(tester, racineArchives: Directory(bouche.path));

      await taper(tester, 'compta-cloture-cloturer');
      await attendre(tester, find.byKey(const Key('compta-archive-absente')));

      expect(
        (await dao.exerciceDeLAnnee(annee))!.statut,
        StatutExercice.cloture,
        reason: 'la clôture tient',
      );
      expect(find.byKey(const Key('compta-cloture-erreur')), findsNothing);
      expect(find.byKey(const Key('compta-archive-generer')), findsOneWidget);
      expect(find.byKey(const Key('compta-archive-empreinte')), findsNothing);
      expect(
        (await serviceDirect().clotureActive(
          await idExercice(),
        ))!.archiveEmpreinte,
        isNull,
      );
    });

    testWidgets('« Télécharger l’archive (ZIP) » enregistre l’archive, '
        'vérifiée', (tester) async {
      await exploiter();
      await serviceDirect().demarrer(await idExercice(), auteurId: auteurEssai);
      await monter(tester);
      await taper(tester, 'compta-cloture-cloturer');
      await attendre(tester, find.byKey(const Key('compta-archive-empreinte')));

      await tester.ensureVisible(
        find.byKey(const Key('compta-archive-telecharger')),
      );
      await tester.tap(find.byKey(const Key('compta-archive-telecharger')));
      await attendre(tester, texte('Archive enregistrée'));

      expect(selecteur.ecrits, hasLength(1));
      final zip = selecteur.dernier;
      expect(zip.type, TypeFichierEnregistre.zip);
      expect(zip.nom, startsWith('archive_exercice_${annee}_'));
      expect(zip.nom, endsWith('.zip'));
      expect(String.fromCharCodes(zip.octets.take(2)), 'PK');
      expect(texte('Archive enregistrée : C:/essai/'), findsOneWidget);
    });

    testWidgets('une archive absente se GÉNÈRE à la demande ; la clôture '
        'tient sans elle', (tester) async {
      await exploiter();
      final service = serviceDirect();
      final id = await idExercice();
      await service.demarrer(id, auteurId: auteurEssai);
      await service.cloturer(id, auteurId: auteurEssai);
      await monter(tester);

      expect(find.byKey(const Key('compta-archive-absente')), findsOneWidget);
      expect(
        texte('L’archive de cette clôture n’a pas été générée.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('compta-archive-telecharger')), findsNothing);

      await tester.ensureVisible(
        find.byKey(const Key('compta-archive-generer')),
      );
      await tester.tap(find.byKey(const Key('compta-archive-generer')));
      await attendre(tester, find.byKey(const Key('compta-archive-empreinte')));

      expect(find.byKey(const Key('compta-archive-absente')), findsNothing);
      expect(
        (await service.clotureActive(id))!.archiveEmpreinte,
        hasLength(64),
      );
      expect(
        find.text('Archive de clôture de l’exercice $annee générée.'),
        findsOneWidget,
      );
    });
  });

  group('Rouvrir : le comptable seul, un motif', () {
    Future<void> cloturerDirect() async {
      await exploiter();
      final service = serviceDirect();
      final id = await idExercice();
      await service.demarrer(id, auteurId: auteurEssai);
      await service.cloturer(id, auteurId: auteurEssai);
    }

    testWidgets('le comptable : un motif trop court est refusé, un motif '
        'valable rouvre l’exercice en clôture', (tester) async {
      await cloturerDirect();
      await monter(tester);

      expect(find.byKey(const Key('compta-cloture-rouvrir')), findsOneWidget);
      expect(texte('Motif de la réouverture'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('compta-cloture-motif')),
        'court',
      );
      await taper(tester, 'compta-cloture-rouvrir');
      expect(
        tester
            .widget<Text>(find.byKey(const Key('compta-cloture-erreur')))
            .data,
        'Le motif de la réouverture est obligatoire (10 caractères au moins) : '
        "il est écrit au journal d'audit et sur les contre-passations.",
      );
      expect(
        (await dao.exerciceDeLAnnee(annee))!.statut,
        StatutExercice.cloture,
      );

      await tester.enterText(
        find.byKey(const Key('compta-cloture-motif')),
        'Facture fournisseur oubliée',
      );
      await taper(tester, 'compta-cloture-rouvrir');
      expect(
        (await dao.exerciceDeLAnnee(annee))!.statut,
        StatutExercice.enCloture,
      );
      expect(
        find.text('Exercice $annee rouvert : il repasse en clôture.'),
        findsOneWidget,
      );
      // La clôture rouverte est en historique, avec son motif ; plus d'active.
      final service = serviceDirect();
      expect(await service.clotureActive(await idExercice()), isNull);
      expect(
        (await service.clotures()).single.motifReouverture,
        'Facture fournisseur oubliée',
      );
      expect(find.byKey(const Key('compta-cloture-cloturer')), findsOneWidget);
    });

    testWidgets('un autre rôle ne voit ni motif ni bouton : la phrase du '
        'serveur', (tester) async {
      await cloturerDirect();
      await monter(tester, role: 'administrateur');

      expect(find.byKey(const Key('compta-cloture-rouvrir')), findsNothing);
      expect(find.byKey(const Key('compta-cloture-motif')), findsNothing);
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('compta-cloture-reouverture-reservee')),
            )
            .data,
        'Seul le comptable peut rouvrir un exercice clôturé.',
      );
    });
  });
}
