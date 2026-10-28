@Timeout(Duration(minutes: 2))
library;

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/format/adresse_email_facultative.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import 'package:tatacora_flutter/features/transverse/data/comptes_utilisateurs_dao.dart';
import 'package:tatacora_flutter/features/transverse/data/roles_dao.dart';
import 'package:tatacora_flutter/features/transverse/domain/comptes_utilisateurs.dart';
import 'package:tatacora_flutter/features/transverse/presentation/ecran_comptes_utilisateurs.dart';
import 'package:tatacora_flutter/features/transverse/presentation/ecran_mon_profil.dart';
import 'package:tatacora_flutter/features/transverse/domain/roles_du_poste.dart';

/// L'e-mail FACULTATIF d'un compte (28/10/2026) : saisi à la création
/// (« Comptes utilisateurs »), modifiable par son titulaire (« Mon profil »).
/// Facultatif, normalisé (trim, minuscules), validé comme le serveur (la règle
/// elle-même est confrontée au vrai PHP par `email_facultatif_contre_serveur_test`),
/// sans unicité, LOCAL (les comptes ne se synchronisent pas : aucune opération
/// n'est enfilée).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late ComptesUtilisateursDao dao;

  Future<void> poser(String id, String role, {String? email}) => db
      .into(db.utilisateursLocal)
      .insert(
        UtilisateursLocalCompanion.insert(
          id: id,
          login: id,
          nom: id.toUpperCase(),
          email: Value(email),
          role: role,
          droitsJson: '{}',
          sel: 's',
          empreinte: 'e',
          iterations: 1,
          dateCreation: DateTime(2026, 10, 1),
          dateMotDePasse: DateTime(2026, 10, 1),
        ),
      );

  setUp(() async {
    db = AppDatabase.enMemoire();
    dao = ComptesUtilisateursDao(db, horloge: () => DateTime(2026, 10, 28, 9));
    await RolesDao(db).installerSocle();
    await poser('admin', 'administrateur');
  });
  tearDown(() => db.close());

  Future<String?> emailEnBase(String id) async => (await (db.select(
    db.utilisateursLocal,
  )..where((u) => u.id.equals(id))).getSingle()).email;

  Future<String> creer(String identifiant, {String? email}) => dao.creerCompte(
    auteurId: 'admin',
    nom: 'KORA Jean',
    identifiant: identifiant,
    role: 'barman',
    motDePasse: 'comptoir2026',
    confirmation: 'comptoir2026',
    email: email,
  );

  Future<Map<String, String>> refus(Future<Object?> geste) async {
    try {
      await geste;
    } on RefusComptes catch (e) {
      return e.erreurs;
    }
    fail('aucun refus');
  }

  group('Création', () {
    test('l’e-mail est facultatif, normalisé, sans unicité ; vide : NULL, '
        'jamais une chaîne vide', () async {
      final a = await creer('a.kora', email: '  Jean.KORA@Exemple.BJ ');
      final b = await creer('b.kora', email: 'jean.kora@exemple.bj');
      final c = await creer('c.kora');
      final d = await creer('d.kora', email: '   ');

      expect(await emailEnBase(a), 'jean.kora@exemple.bj');
      expect(await emailEnBase(b), 'jean.kora@exemple.bj');
      expect(await emailEnBase(c), isNull);
      expect(await emailEnBase(d), isNull);
      expect({
        for (final x in await dao.comptes()) x.identifiant: x.email,
      }, containsPair('a.kora', 'jean.kora@exemple.bj'));
    });

    test('mal formé : la phrase du serveur SOUS le champ email, rien n’est '
        'écrit, et il se cumule avec les autres refus', () async {
      final erreurs = await refus(creer('j.kora', email: 'pas-une-adresse'));
      expect(erreurs, {'email': AdresseEmailFacultative.messageInvalide});
      expect(await db.select(db.utilisateursLocal).get(), hasLength(1));

      final cumul = await refus(
        dao.creerCompte(
          auteurId: 'admin',
          nom: '',
          identifiant: 'j.kora',
          role: 'barman',
          motDePasse: 'comptoir2026',
          confirmation: 'comptoir2026',
          email: 'a@b',
        ),
      );
      expect(cumul.keys, containsAll(['nom', 'email']));
    });

    test(
      'rien ne part au serveur : les comptes ne se synchronisent pas',
      () async {
        await creer('j.kora', email: 'a@exemple.bj');
        final file = await db
            .customSelect('SELECT COUNT(*) AS n FROM operations_sync_local')
            .getSingle();
        expect(file.data['n'], 0);
      },
    );
  });

  group('« Mon profil » : enregistrerEmail', () {
    test('le titulaire écrit, efface, et ne touche que SON compte', () async {
      await poser('moi', 'barman', email: 'ancien@exemple.bj');
      await poser('autre', 'barman', email: 'autre@exemple.bj');

      expect(
        await dao.enregistrerEmail(
          utilisateurId: 'moi',
          email: ' Nouveau@Exemple.BJ ',
        ),
        'nouveau@exemple.bj',
      );
      expect(await emailEnBase('moi'), 'nouveau@exemple.bj');
      expect(await emailEnBase('autre'), 'autre@exemple.bj');

      // Même adresse qu'un autre compte : acceptée (aucune unicité).
      await dao.enregistrerEmail(
        utilisateurId: 'moi',
        email: 'autre@exemple.bj',
      );
      expect(await emailEnBase('moi'), 'autre@exemple.bj');

      expect(
        await dao.enregistrerEmail(utilisateurId: 'moi', email: ''),
        isNull,
      );
      expect(await emailEnBase('moi'), isNull);
      expect(await dao.emailDuCompte('autre'), 'autre@exemple.bj');
    });

    test(
      'mal formé ou compte inconnu : refus, l’ancienne adresse reste',
      () async {
        await poser('moi', 'barman', email: 'ancien@exemple.bj');
        expect(
          await refus(
            dao.enregistrerEmail(utilisateurId: 'moi', email: 'faux'),
          ),
          {'email': AdresseEmailFacultative.messageInvalide},
        );
        expect(await emailEnBase('moi'), 'ancien@exemple.bj');
        expect(
          (await refus(
            dao.enregistrerEmail(
              utilisateurId: 'fantome',
              email: 'a@exemple.bj',
            ),
          )).keys,
          ['compte'],
        );
      },
    );
  });

  Future<void> monter(
    WidgetTester tester,
    Widget ecran, {
    required String id,
    required String role,
    required GardeAcces garde,
  }) async {
    tester.view
      ..physicalSize = const Size(1600, 2400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          sessionProvider.overrideWithBuild(
            (ref, notifier) => Session(
              utilisateurId: id,
              login: id,
              nom: 'Nom $id',
              role: role,
              droits: garde,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: Scaffold(body: ecran),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder cle(String k) => find.byKey(Key(k));

  testWidgets('« Nouveau compte » : le champ Email est facultatif (sans '
      'astérisque), refuse le mal formé, enregistre le bon normalisé', (
    tester,
  ) async {
    await monter(
      tester,
      const EcranComptesUtilisateurs(),
      id: 'admin',
      role: 'administrateur',
      garde: GardeAcces.depuisJson(socleRbacCdcf['administrateur']!),
    );
    await tester.tap(cle('comptes-nouveau'));
    await tester.pumpAndSettle();

    expect(cle('comptes-saisie-email'), findsOneWidget);
    // Pas d'astérisque sur l'Email ; les autres champs obligatoires gardent le leur.
    final obligatoire = {
      for (final e in tester.widgetList<EtiquetteChampRestaurant>(
        find.byType(EtiquetteChampRestaurant),
      ))
        e.texte: e.obligatoire,
    };
    expect(obligatoire['Email'], isFalse);
    expect(obligatoire['Nom complet'], isTrue);
    expect(obligatoire['Identifiant'], isTrue);

    Future<void> saisir(String champ, String texte) =>
        tester.enterText(cle('comptes-saisie-$champ'), texte);
    await saisir('nom', 'KORA Jean');
    await saisir('identifiant', 'j.kora');
    await saisir('mot-de-passe', 'comptoir2026');
    await saisir('confirmation', 'comptoir2026');
    await tester.tap(cle('comptes-saisie-role'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(libelleRole('barman')).last);
    await tester.pumpAndSettle();

    await saisir('email', 'pas-une-adresse');
    await tester.tap(cle('comptes-nouveau-enregistrer'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(cle('comptes-erreur-email')).data,
      AdresseEmailFacultative.messageInvalide,
    );
    expect(cle('comptes-modale-nouveau'), findsOneWidget);
    expect(await db.select(db.utilisateursLocal).get(), hasLength(1));

    await saisir('email', ' Jean.Kora@Exemple.BJ ');
    await tester.tap(cle('comptes-nouveau-enregistrer'));
    await tester.pumpAndSettle();
    expect(cle('comptes-modale-nouveau'), findsNothing);
    final creee = await (db.select(
      db.utilisateursLocal,
    )..where((u) => u.login.equals('j.kora'))).getSingle();
    expect(creee.email, 'jean.kora@exemple.bj');
  });

  group('« Mon profil » : Informations personnelles', () {
    Future<void> ouvrir(WidgetTester tester) => monter(
      tester,
      const EcranMonProfil(),
      id: 'moi',
      role: 'barman',
      garde: GardeAcces.depuisJson(const {'M5': 'C'}),
    );

    testWidgets('le champ Email porte l’adresse du compte ; invalide : la '
        'phrase du serveur, rien n’est écrit ; valide : écrite, normalisée, '
        'confirmée ; vide : effacée', (tester) async {
      await poser('moi', 'barman', email: 'ancien@exemple.bj');
      await ouvrir(tester);

      TextField champ() => tester.widget<TextField>(cle('profil-champ-email'));
      expect(champ().controller!.text, 'ancien@exemple.bj');
      expect(find.text('Enregistrer les informations'), findsOneWidget);

      Future<void> enregistrer(String texte) async {
        await tester.enterText(cle('profil-champ-email'), texte);
        await tester.ensureVisible(cle('profil-infos-enregistrer'));
        await tester.tap(cle('profil-infos-enregistrer'));
        await tester.pumpAndSettle();
      }

      await enregistrer('faux');
      expect(
        tester.widget<Text>(cle('profil-erreur-email')).data,
        AdresseEmailFacultative.messageInvalide,
      );
      expect(await emailEnBase('moi'), 'ancien@exemple.bj');

      await enregistrer('  Nouveau@Exemple.BJ ');
      expect(cle('profil-erreur-email'), findsNothing);
      expect(await emailEnBase('moi'), 'nouveau@exemple.bj');
      expect(champ().controller!.text, 'nouveau@exemple.bj');
      expect(
        tester.widget<Text>(cle('profil-email-enregistre')).data,
        AdresseEmailFacultative.messageEnregistree,
      );

      await enregistrer('');
      expect(await emailEnBase('moi'), isNull);
    });
  });
}
