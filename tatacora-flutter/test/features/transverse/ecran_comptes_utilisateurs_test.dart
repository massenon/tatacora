import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/transverse/domain/comptes_utilisateurs.dart';
import 'package:tatacora_flutter/features/transverse/domain/roles_du_poste.dart';
import 'package:tatacora_flutter/features/transverse/presentation/ecran_comptes_utilisateurs.dart';
import 'package:tatacora_flutter/features/transverse/presentation/widgets/modales_comptes.dart';
import 'package:tatacora_flutter/shared_widgets/affichage_secret_unique.dart';

/// L'écran « Comptes utilisateurs » (Lot J2) monté sur une base RÉELLE en
/// mémoire : qui y entre, la liste paginée, la modale « + Nouveau compte »
/// et ses refus sous le champ fautif, la désactivation — et l'absence du
/// bouton « Désactiver » sur sa propre ligne.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  setUp(() => db = AppDatabase.enMemoire());
  tearDown(() => db.close());

  Future<void> poser(String id, String role, {bool actif = true}) => db
      .into(db.utilisateursLocal)
      .insert(
        UtilisateursLocalCompanion.insert(
          id: id,
          login: id,
          nom: 'Nom $id',
          role: role,
          droitsJson: '{}',
          sel: 's',
          empreinte: 'e',
          iterations: 1,
          dateCreation: DateTime(2026, 10, 1),
          dateMotDePasse: DateTime(2026, 10, 1),
          actif: Value(actif),
        ),
      );

  Future<void> monter(
    WidgetTester tester, {
    String id = 'admin',
    String role = 'administrateur',
    Map<String, String>? droits,
    bool connecte = true,
  }) async {
    tester.view
      ..physicalSize = const Size(1600, 2400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final garde = GardeAcces.depuisJson(
      droits ?? socleRbacCdcf['administrateur']!,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          sessionProvider.overrideWithBuild(
            (ref, notifier) => connecte
                ? Session(
                    utilisateurId: id,
                    login: id,
                    nom: 'Nom $id',
                    role: role,
                    droits: garde,
                  )
                : null,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranComptesUtilisateurs()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder cle(String k) => find.byKey(Key(k));

  Future<void> saisir(WidgetTester tester, String champ, String texte) =>
      tester.enterText(cle('comptes-saisie-$champ'), texte);

  group('Qui y entre', () {
    testWidgets('un rôle hors administration est REFUSÉ, même avec le droit C '
        'sur ROLES', (tester) async {
      await poser('recep', 'receptionniste');
      await monter(
        tester,
        id: 'recep',
        role: 'receptionniste',
        droits: {...socleRbacCdcf['administrateur']!, 'ROLES': 'C'},
      );
      expect(find.text(MessagesComptes.refusDroit), findsOneWidget);
      expect(cle('comptes-nouveau'), findsNothing);
    });

    testWidgets(
      'un administrateur SANS droit de lecture sur ROLES est refusé',
      (tester) async {
        await poser('admin', 'administrateur');
        await monter(
          tester,
          droits: {...socleRbacCdcf['administrateur']!, 'ROLES': '-'},
        );
        expect(cle('transverse-refus-droit'), findsOneWidget);
      },
    );

    testWidgets('administrateur et super_admin y entrent', (tester) async {
      await poser('admin', 'administrateur');
      await monter(tester);
      expect(cle('comptes-nouveau'), findsOneWidget);
      expect(find.text(TextesComptes.titre), findsWidgets);

      await poser('sa', 'super_admin');
      await monter(tester, id: 'sa', role: 'super_admin');
      expect(cle('comptes-nouveau'), findsOneWidget);
    });
  });

  group('La liste', () {
    testWidgets('sa propre ligne n’offre NI « Désactiver » NI « Réinitialiser le '
        'mot de passe » ; les autres, si', (tester) async {
      await poser('admin', 'administrateur');
      await poser('barman1', 'barman');
      await monter(tester);

      expect(cle('comptes-nom-admin'), findsOneWidget);
      final nom = tester.widget<Text>(cle('comptes-nom-admin'));
      expect(nom.textSpan!.toPlainText(), contains(TextesComptes.vous));
      expect(cle('comptes-basculer-admin'), findsNothing);
      // Un administrateur change son mot de passe par « Mon profil » (29/10/2026).
      expect(cle('comptes-reinitialiser-admin'), findsNothing);
      expect(cle('comptes-reinitialiser-barman1'), findsOneWidget);
      expect(cle('comptes-basculer-barman1'), findsOneWidget);
    });

    testWidgets('paginée : dix lignes, la suite en page 2', (tester) async {
      await poser('admin', 'administrateur');
      for (var i = 10; i < 23; i++) {
        await poser('compte$i', 'barman');
      }
      await monter(tester);
      Finder lignes() => find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('comptes-nom-'),
      );
      expect(lignes(), findsNWidgets(10));
      await tester.ensureVisible(cle('comptes-pagination-suivant'));
      await tester.tap(cle('comptes-pagination-suivant'));
      await tester.pumpAndSettle();
      expect(lignes(), findsNWidgets(4));
    });
  });

  group('« Réinitialiser le mot de passe » (option A, 29/10/2026)', () {
    testWidgets('confirmation, puis le mot de passe TEMPORAIRE montré UNE fois '
        '(copier), « Changement requis » dans la liste', (tester) async {
      final copies = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (appel) async {
            if (appel.method == 'Clipboard.setData') {
              copies.add((appel.arguments as Map)['text'] as String);
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await poser('admin', 'administrateur');
      await poser('barman1', 'barman');
      await monter(tester);
      expect(find.text(TextesComptes.changementRequis), findsNothing);

      await tester.tap(cle('comptes-reinitialiser-barman1'));
      await tester.pumpAndSettle();
      // La confirmation dit ce qui va se passer — et ne demande AUCUN mot de passe.
      expect(
        find.text(TextesModalesComptes.reinitialiserTitre('barman1')),
        findsOneWidget,
      );
      expect(
        find.text(TextesModalesComptes.reinitialiserTexte(24)),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);

      await tester.tap(cle('comptes-mot-de-passe-enregistrer'));
      await tester.pump(const Duration(milliseconds: 1));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1500)),
      );
      await tester.pumpAndSettle();

      // Le temporaire est affiché, une fois, avec « Copier ».
      final temporaire = tester
          .widget<SelectableText>(cle('comptes-temporaire-valeur'))
          .data!;
      expect(temporaire.length, greaterThanOrEqualTo(12));
      expect(
        find.text(TextesModalesComptes.resultatTitre('barman1')),
        findsOneWidget,
      );
      expect(find.textContaining('Valable jusqu’au'), findsNothing);
      expect(find.textContaining("Valable jusqu'au"), findsOneWidget);
      await tester.tap(cle('comptes-temporaire-copier'));
      await tester.pump();
      expect(copies, [temporaire]);
      expect(find.text(TextesSecretUnique.copie), findsOneWidget);
      // Pas d'« Imprimer » pour un mot de passe temporaire.
      expect(cle('comptes-temporaire-imprimer'), findsNothing);

      await tester.tap(cle('comptes-temporaire-fermer'));
      await tester.pumpAndSettle();
      // Il ne revient plus : la fenêtre est fermée, la liste dit seulement
      // l'état du compte.
      expect(cle('comptes-temporaire-valeur'), findsNothing);
      expect(find.text(temporaire), findsNothing);
      expect(
        tester.widget<Text>(cle('comptes-changement-barman1')).data,
        TextesComptes.changementRequis,
      );
    });

    testWidgets('un temporaire expiré se lit « Temporaire expiré »', (
      tester,
    ) async {
      await poser('admin', 'administrateur');
      await poser('barman1', 'barman');
      await (db.update(
        db.utilisateursLocal,
      )..where((u) => u.id.equals('barman1'))).write(
        UtilisateursLocalCompanion(
          changementObligatoire: const Value(true),
          mdpTemporaireExpireLe: Value(
            DateTime.now().subtract(const Duration(hours: 1)),
          ),
        ),
      );
      await monter(tester);
      expect(
        tester.widget<Text>(cle('comptes-changement-barman1')).data,
        TextesComptes.temporaireExpire,
      );
    });
  });

  group('« + Nouveau compte »', () {
    testWidgets('chaque refus s’affiche SOUS son champ, la modale reste ; '
        'valide : créée, toast, ligne ajoutée ; doublon refusé', (
      tester,
    ) async {
      await poser('admin', 'administrateur');
      await monter(tester);

      await tester.tap(cle('comptes-nouveau'));
      await tester.pumpAndSettle();
      expect(cle('comptes-modale-nouveau'), findsOneWidget);

      // Rien de saisi.
      await tester.tap(cle('comptes-nouveau-enregistrer'));
      await tester.pumpAndSettle();
      expect(find.text(MessagesComptes.nomObligatoire), findsOneWidget);
      expect(find.text(MessagesComptes.identifiantObligatoire), findsOneWidget);
      expect(cle('comptes-erreur-role'), findsOneWidget);
      expect(find.text(MessagesComptes.motDePasseCourt), findsOneWidget);
      expect(cle('comptes-modale-nouveau'), findsOneWidget);

      // Saisie fautive : identifiant trop court, mot de passe court, la
      // confirmation diffère.
      await saisir(tester, 'nom', 'KORA Jean');
      await saisir(tester, 'identifiant', 'jk');
      await saisir(tester, 'mot-de-passe', 'court');
      await saisir(tester, 'confirmation', 'autre');
      await tester.tap(cle('comptes-saisie-role'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(libelleRole('barman')).last);
      await tester.pumpAndSettle();
      await tester.tap(cle('comptes-nouveau-enregistrer'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(cle('comptes-erreur-identifiant')).data,
        MessagesComptes.identifiantLongueur,
      );
      expect(
        tester.widget<Text>(cle('comptes-erreur-mot-de-passe')).data,
        MessagesComptes.motDePasseCourt,
      );
      expect(
        tester.widget<Text>(cle('comptes-erreur-confirmation')).data,
        MessagesComptes.confirmationDifferente,
      );
      expect(cle('comptes-erreur-nom'), findsNothing);
      expect(cle('comptes-erreur-role'), findsNothing);
      expect(await db.select(db.utilisateursLocal).get(), hasLength(1));

      // Valide.
      await saisir(tester, 'identifiant', 'J.Kora');
      await saisir(tester, 'mot-de-passe', 'comptoir2026');
      await saisir(tester, 'confirmation', 'comptoir2026');
      await tester.tap(cle('comptes-nouveau-enregistrer'));
      await tester.pumpAndSettle();
      expect(cle('comptes-modale-nouveau'), findsNothing);
      expect(
        tester.widget<Text>(cle('comptes-succes')).data,
        MessagesComptes.compteCree('j.kora'),
      );
      expect(cle('comptes-nom-j.kora'), findsOneWidget);
      expect(
        tester.widget<Text>(cle('comptes-statut-j.kora')).data,
        TextesComptes.actif,
      );

      // Le même identifiant une seconde fois : refusé sous son champ.
      await tester.tap(cle('comptes-nouveau'));
      await tester.pumpAndSettle();
      await saisir(tester, 'nom', 'Autre');
      await saisir(tester, 'identifiant', 'j.kora');
      await saisir(tester, 'mot-de-passe', 'comptoir2026');
      await saisir(tester, 'confirmation', 'comptoir2026');
      await tester.tap(cle('comptes-saisie-role'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(libelleRole('cuisine')).last);
      await tester.pumpAndSettle();
      await tester.tap(cle('comptes-nouveau-enregistrer'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(cle('comptes-erreur-identifiant')).data,
        MessagesComptes.identifiantPris('j.kora'),
      );
      expect(await db.select(db.utilisateursLocal).get(), hasLength(2));
    });
  });

  testWidgets('« Désactiver » passe par sa confirmation, « Réactiver » est '
      'immédiat ; rien n’est supprimé', (tester) async {
    await poser('admin', 'administrateur');
    await poser('barman1', 'barman');
    await monter(tester);

    await tester.ensureVisible(cle('comptes-basculer-barman1'));
    await tester.tap(cle('comptes-basculer-barman1'));
    await tester.pumpAndSettle();
    expect(cle('comptes-modale-desactiver'), findsOneWidget);
    await tester.tap(cle('comptes-desactiver-confirmer'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(cle('comptes-statut-barman1')).data,
      TextesComptes.desactive,
    );
    expect(find.text(TextesComptes.reactiver), findsOneWidget);

    await tester.ensureVisible(cle('comptes-basculer-barman1'));
    await tester.tap(cle('comptes-basculer-barman1'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(cle('comptes-statut-barman1')).data,
      TextesComptes.actif,
    );
    expect(await db.select(db.utilisateursLocal).get(), hasLength(2));
  });
}
