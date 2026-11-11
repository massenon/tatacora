import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/data/code_secours_local.dart';
import 'package:tatacora_flutter/features/auth/data/identifiant_memorise.dart';
import 'package:tatacora_flutter/features/auth/impression/feuille_code_secours.dart';
import 'package:tatacora_flutter/features/auth/data/session_repository_local.dart';
import 'package:tatacora_flutter/features/auth/domain/mot_de_passe_perdu.dart';
import 'package:tatacora_flutter/features/auth/presentation/ecran_changement_mot_de_passe.dart';
import 'package:tatacora_flutter/features/auth/presentation/ecran_code_secours.dart';
import 'package:tatacora_flutter/features/auth/presentation/ecran_connexion.dart';
import 'package:tatacora_flutter/features/auth/presentation/formulaire_premier_compte.dart';
import 'package:tatacora_flutter/features/parametres/data/apparence_poste.dart';
import 'package:tatacora_flutter/features/transverse/data/comptes_utilisateurs_dao.dart';
import 'package:tatacora_flutter/features/transverse/data/roles_dao.dart';
import 'package:tatacora_flutter/shared_widgets/affichage_secret_unique.dart';

import '../../support/vue_blade.dart';

/// Les deux écrans « invité » du mot de passe perdu SANS e-mail (PO, 29/10/2026),
/// le lien de la connexion et le code du premier compte — rendus pour de vrai,
/// sur la vraie authentification locale (base en mémoire).
///
/// Les libellés sont confrontés à la langue du serveur, résolue par PHP : une copie
/// qui dérive fait rougir. Les secrets passent par le presse-papiers et
/// l'impression INJECTÉS (un test de widget n'ouvre pas de dialogue d'impression).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase base;
  late List<String> pressePapiers;
  late List<(String, String)> impressions;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    base = AppDatabase.enMemoire();
    await RolesDao(base).installerSocle();
    pressePapiers = [];
    impressions = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (appel) async {
          if (appel.method == 'Clipboard.setData') {
            pressePapiers.add((appel.arguments as Map)['text'] as String);
          }
          return null;
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    await base.close();
  });

  Future<void> attendre(WidgetTester tester) async {
    // `Future.delayed(Duration.zero)` des écrans (laisser le bouton se griser
    // avant PBKDF2) ne tourne que si l'horloge d'essai AVANCE.
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 900)),
    );
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// Un routeur d'essai : les trois chemins que ces écrans empruntent.
  GoRouter routeur(String depart) => GoRouter(
    initialLocation: depart,
    routes: [
      GoRoute(path: '/connexion', builder: (_, _) => const EcranConnexion()),
      GoRoute(
        path: '/mot-de-passe-administrateur-perdu',
        builder: (_, _) => const EcranCodeSecours(),
      ),
      GoRoute(
        path: '/changement-mot-de-passe',
        builder: (_, _) => const EcranChangementMotDePasse(),
      ),
    ],
  );

  Future<ProviderContainer> monter(
    WidgetTester tester,
    String depart, {
    bool aucunCompte = false,
    double largeur = 900,
  }) async {
    tester.view.physicalSize = Size(largeur, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    late ProviderContainer conteneur;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(base),
          aucunCompteProvider.overrideWith((ref) async => aucunCompte),
          logoTeleverseProvider.overrideWith((ref) async => null),
          dossierConnexionProvider.overrideWithValue(
            () async => throw StateError('pas de dossier en essai'),
          ),
          imprimerCodeSecoursProvider.overrideWithValue(
            (code, login) async => impressions.add((code, login)),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            conteneur = ProviderScope.containerOf(context);
            return MaterialApp.router(
              theme: AppTheme.clair,
              routerConfig: routeur(depart),
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return conteneur;
  }

  /// Un compte réel, et son éventuelle réinitialisation par un administrateur.
  Future<String> compteReinitialise() async {
    final depot = SessionRepositoryLocal(base);
    await depot.creerCompte(
      login: 'admin',
      nom: 'ADMIN',
      motDePasse: 'Admin-Secret-9',
      role: 'administrateur',
      droits: const {'M1': 'C', 'ROLES': 'C'},
    );
    await depot.creerCompte(
      login: 'marie',
      nom: 'MARIE',
      motDePasse: 'Ancien-Secret-9',
      role: 'receptionniste',
      droits: const {'M1': 'C'},
    );
    final ids = {
      for (final l
          in await base
              .customSelect('SELECT id, login FROM utilisateurs_local')
              .get())
        l.data['login'] as String: l.data['id'] as String,
    };
    final fait = await ComptesUtilisateursDao(base)
        .reinitialiserParAdministrateur(
          auteurId: ids['admin']!,
          compteId: ids['marie']!,
        );
    return fait.motDePasse;
  }

  Finder champ(int i) => find.byType(TextFormField).at(i);

  // ====================================================== libellés

  group('Libellés — au caractère près, relus dans la langue du serveur', () {
    test(
      '« Définissez votre nouveau mot de passe » = pwa.changement_mdp.*',
      () {
        const attendu = <String, String>{
          'pwa.changement_mdp.titre_h1': TextesChangementMotDePasse.titre,
          'pwa.changement_mdp.accroche': TextesChangementMotDePasse.accroche,
          'pwa.changement_mdp.nouveau': TextesChangementMotDePasse.nouveau,
          'pwa.changement_mdp.confirmation':
              TextesChangementMotDePasse.confirmation,
          'pwa.changement_mdp.regle': TextesChangementMotDePasse.regle,
          'pwa.changement_mdp.bouton': TextesChangementMotDePasse.bouton,
          'pwa.changement_mdp.en_cours': TextesChangementMotDePasse.enCours,
          'pwa.changement_mdp.se_deconnecter':
              TextesChangementMotDePasse.seDeconnecter,
          'pwa.profil.mdp_confirmation_invalide':
              TextesChangementMotDePasse.confirmationInvalide,
          'pwa.changement_mdp.nouveau_requis':
              MessagesMotDePassePerdu.nouveauRequis,
          'pwa.changement_mdp.confirmation_requise':
              MessagesMotDePassePerdu.confirmationRequise,
          'pwa.changement_mdp.trop_court': MessagesMotDePassePerdu.tropCourt,
          'pwa.changement_mdp.identique_temporaire':
              MessagesMotDePassePerdu.identiqueTemporaire,
          'pwa.changement_mdp.identique_ancien':
              MessagesMotDePassePerdu.identiqueAncien,
          'pwa.changement_mdp.expire': MessagesMotDePassePerdu.expire,
          'pwa.changement_mdp.succes': MessagesMotDePassePerdu.succes,
          'pwa.comptes.refus_soi_meme': MessagesMotDePassePerdu.refusSoiMeme,
          'pwa.comptes.refus_super_admin':
              MessagesMotDePassePerdu.refusSuperAdmin,
        };
        expect(attendu.length, greaterThan(15), reason: 'plancher');
        attendu.forEach((cle, dart) {
          expect(VueBlade.libelle(cle), dart, reason: 'la clé $cle a dérivé');
        });
      },
    );

    test(
      '« J’ai perdu mon mot de passe administrateur » = pwa.code_secours.*',
      () {
        const attendu = <String, String>{
          'pwa.code_secours.titre': TextesCodeSecours.titre,
          'pwa.code_secours.accroche': TextesCodeSecours.accroche,
          'pwa.code_secours.login': TextesCodeSecours.login,
          'pwa.code_secours.code': TextesCodeSecours.code,
          'pwa.code_secours.regle': TextesCodeSecours.regle,
          'pwa.code_secours.bouton': TextesCodeSecours.bouton,
          'pwa.code_secours.en_cours': TextesCodeSecours.enCours,
          'pwa.code_secours.retour_connexion':
              TextesCodeSecours.retourConnexion,
          'pwa.code_secours.nouveau_code_titre':
              TextesCodeSecours.nouveauCodeTitre,
          'pwa.code_secours.consigne_coffre': TextesCodeSecours.consigneCoffre,
          'pwa.code_secours.mdp_reinitialise':
              MessagesMotDePassePerdu.mdpReinitialise,
          'pwa.code_secours.refus': MessagesMotDePassePerdu.refusCode,
          'pwa.code_secours.login_requis': MessagesMotDePassePerdu.loginRequis,
          'pwa.code_secours.code_requis': MessagesMotDePassePerdu.codeRequis,
          'pwa.connexion.mot_de_passe_administrateur_perdu':
              TextesConnexion.motDePasseAdministrateurPerdu,
          'pwa.secret_unique.copier': TextesSecretUnique.copier,
          'pwa.secret_unique.copie': TextesSecretUnique.copie,
          'pwa.secret_unique.imprimer': TextesSecretUnique.imprimer,
        };
        expect(attendu.length, greaterThan(15), reason: 'plancher');
        attendu.forEach((cle, dart) {
          expect(VueBlade.libelle(cle), dart, reason: 'la clé $cle a dérivé');
        });
      },
    );

    test('le blocage dit « :minutes minute(s) » comme le serveur', () {
      expect(
        VueBlade.libelle(
          'pwa.code_secours.bloque',
        )!.replaceAll(':minutes', '15'),
        MessagesMotDePassePerdu.bloque(15),
      );
    });

    test('« Mon profil → Code de secours » = pwa.profil.code_secours_*', () {
      const attendu = <String, String>{
        'pwa.profil.code_secours_titre':
            MessagesMotDePassePerdu.codeSecoursTitre,
        'pwa.profil.code_secours_sous_titre':
            MessagesMotDePassePerdu.codeSecoursSousTitre,
        'pwa.profil.code_secours_absent':
            MessagesMotDePassePerdu.codeSecoursAbsent,
        'pwa.profil.code_secours_ouvrir':
            MessagesMotDePassePerdu.codeSecoursOuvrir,
        'pwa.profil.code_secours_modale_titre':
            MessagesMotDePassePerdu.codeSecoursModaleTitre,
        'pwa.profil.code_secours_modale_sous_titre':
            MessagesMotDePassePerdu.codeSecoursModaleSousTitre,
        'pwa.profil.code_secours_mot_de_passe':
            MessagesMotDePassePerdu.codeSecoursMotDePasse,
        'pwa.profil.code_secours_generer':
            MessagesMotDePassePerdu.codeSecoursGenerer,
        'pwa.profil.code_secours_affiche_titre':
            MessagesMotDePassePerdu.codeSecoursAfficheTitre,
        'pwa.profil.code_secours_consigne':
            MessagesMotDePassePerdu.codeSecoursConsigne,
        'pwa.profil.code_secours_fermer':
            MessagesMotDePassePerdu.codeSecoursFermer,
        'pwa.profil.code_secours_impression_titre':
            'Code de secours de l\'administrateur',
      };
      attendu.forEach((cle, dart) {
        expect(VueBlade.libelle(cle), dart, reason: 'la clé $cle a dérivé');
      });
      expect(
        VueBlade.libelle(
          'pwa.profil.code_secours_present',
        )!.replaceAll(':date', '29/10/2026 09:00'),
        MessagesMotDePassePerdu.codeSecoursPresent('29/10/2026 09:00'),
      );
    });
  });

  // ============================================== changement obligatoire

  group('Définissez votre nouveau mot de passe', () {
    testWidgets('les textes de la vue, les règles de saisie, le bon pied', (
      tester,
    ) async {
      final temporaire = await compteReinitialise();
      final c = await monter(tester, '/changement-mot-de-passe');
      await c.read(sessionProvider.notifier).connecter('marie', temporaire);
      await tester.pump();

      for (final t in [
        TextesChangementMotDePasse.titre,
        TextesChangementMotDePasse.accroche,
        TextesChangementMotDePasse.nouveau,
        TextesChangementMotDePasse.confirmation,
        TextesChangementMotDePasse.regle,
        TextesChangementMotDePasse.bouton,
        TextesChangementMotDePasse.seDeconnecter,
        TextesConnexion.piedDePage,
      ]) {
        expect(find.text(t), findsOneWidget, reason: '« $t » absent');
      }

      // Saisie vide, trop courte, confirmation différente.
      await tester.tap(find.text(TextesChangementMotDePasse.bouton));
      await tester.pump();
      expect(find.text(MessagesMotDePassePerdu.nouveauRequis), findsOneWidget);
      expect(
        find.text(MessagesMotDePassePerdu.confirmationRequise),
        findsOneWidget,
      );

      await tester.enterText(champ(0), 'court');
      await tester.enterText(champ(1), 'autre');
      await tester.tap(find.text(TextesChangementMotDePasse.bouton));
      await tester.pump();
      expect(find.text(MessagesMotDePassePerdu.tropCourt), findsOneWidget);
      expect(
        find.text(TextesChangementMotDePasse.confirmationInvalide),
        findsOneWidget,
      );
      expect(
        c.read(sessionProvider)!.changementObligatoire,
        isTrue,
        reason: 'rien n’a été enregistré',
      );
    });

    testWidgets('un mot de passe égal au temporaire est refusé, sous le '
        'formulaire, et les champs sont vidés', (tester) async {
      final temporaire = await compteReinitialise();
      final c = await monter(tester, '/changement-mot-de-passe');
      await c.read(sessionProvider.notifier).connecter('marie', temporaire);
      await tester.pump();

      await tester.enterText(champ(0), temporaire);
      await tester.enterText(champ(1), temporaire);
      await tester.tap(find.text(TextesChangementMotDePasse.bouton));
      await attendre(tester);

      expect(
        find.textContaining(MessagesMotDePassePerdu.identiqueTemporaire),
        findsOneWidget,
      );
      expect(tester.widget<TextFormField>(champ(0)).controller!.text, isEmpty);
      expect(c.read(sessionProvider)!.changementObligatoire, isTrue);
    });

    testWidgets('le choix valide FERME la session et la connexion le dit une '
        'fois ; le nouveau mot de passe ouvre ensuite sans blocage', (
      tester,
    ) async {
      final temporaire = await compteReinitialise();
      final c = await monter(tester, '/changement-mot-de-passe');
      await c.read(sessionProvider.notifier).connecter('marie', temporaire);
      await tester.pump();

      await tester.enterText(champ(0), 'Nouveau-Secret-7');
      await tester.enterText(champ(1), 'Nouveau-Secret-7');
      await tester.tap(find.text(TextesChangementMotDePasse.bouton));
      await attendre(tester);

      expect(c.read(sessionProvider), isNull, reason: 'session fermée');
      expect(
        c.read(infoConnexionProvider),
        MessagesMotDePassePerdu.succes,
        reason: 'la connexion le dira une fois',
      );
      final session = await c
          .read(depotSessionProvider)
          .connecter('marie', 'Nouveau-Secret-7');
      expect(session.changementObligatoire, isFalse);
    });

    testWidgets('« Se déconnecter » ferme la session sans rien changer', (
      tester,
    ) async {
      final temporaire = await compteReinitialise();
      final c = await monter(tester, '/changement-mot-de-passe');
      await c.read(sessionProvider.notifier).connecter('marie', temporaire);
      await tester.pump();

      await tester.tap(find.byKey(const Key('changement-se-deconnecter')));
      await attendre(tester);

      expect(c.read(sessionProvider), isNull);
      expect(
        (await c.read(depotSessionProvider).connecter('marie', temporaire))
            .changementObligatoire,
        isTrue,
      );
    });

    testWidgets('aucun débordement, de 320 px au plus large', (tester) async {
      for (final largeur in const [320.0, 768.0, 1440.0]) {
        await monter(tester, '/changement-mot-de-passe', largeur: largeur);
        expect(tester.takeException(), isNull, reason: 'à $largeur px');
      }
    });
  });

  // ================================================= le code de secours

  group('J’ai perdu mon mot de passe administrateur', () {
    Future<String> adminAvecCode() async {
      final depot = SessionRepositoryLocal(base);
      await depot.creerCompte(
        login: 'admin',
        nom: 'ADMIN',
        motDePasse: 'Admin-Secret-9',
        role: 'administrateur',
        droits: const {'M1': 'C', 'ROLES': 'C'},
      );
      return CodeSecoursLocal(base).poser(login: 'admin');
    }

    testWidgets('le lien du message « Contactez l’administrateur » mène à '
        'l’écran du code de secours', (tester) async {
      await adminAvecCode();
      await monter(tester, '/connexion');
      expect(
        find.byKey(const Key('connexion-lien-mot-de-passe-perdu')),
        findsNothing,
        reason: 'caché tant que « Mot de passe oublié ? » n’est pas ouvert',
      );
      await tester.tap(find.text(TextesConnexion.motDePasseOublie));
      await tester.pump();
      expect(find.text(TextesConnexion.motDePasseOublieAide), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('connexion-lien-mot-de-passe-perdu')),
      );
      await tester.pumpAndSettle();
      expect(find.text(TextesCodeSecours.titre), findsOneWidget);
    });

    testWidgets('refus : UN seul message, jamais de détail ; le nouveau mot '
        'de passe et le code sont vidés', (tester) async {
      await adminAvecCode();
      await monter(tester, '/mot-de-passe-administrateur-perdu');

      Future<void> essayer(String login) async {
        await tester.enterText(champ(0), login);
        await tester.enterText(champ(1), 'AAAAA-BBBBB-CCCCC-DDDDD-EEEEE');
        await tester.enterText(champ(2), 'Tout-Neuf-Mdp-4');
        await tester.enterText(champ(3), 'Tout-Neuf-Mdp-4');
        await tester.tap(find.text(TextesCodeSecours.bouton));
        await attendre(tester);
      }

      await essayer('admin');
      expect(
        find.textContaining(MessagesMotDePassePerdu.refusCode),
        findsOneWidget,
      );
      await essayer('inconnu');
      expect(
        find.textContaining(MessagesMotDePassePerdu.refusCode),
        findsOneWidget,
        reason: 'le même message pour un compte inconnu',
      );
      expect(tester.widget<TextFormField>(champ(1)).controller!.text, isEmpty);
      expect(tester.widget<TextFormField>(champ(2)).controller!.text, isEmpty);
    });

    testWidgets('la saisie vide ou courte est dite sous les champs, sans '
        'consommer un essai', (tester) async {
      await adminAvecCode();
      final c = await monter(tester, '/mot-de-passe-administrateur-perdu');
      await tester.tap(find.text(TextesCodeSecours.bouton));
      await tester.pump();
      for (final m in [
        MessagesMotDePassePerdu.loginRequis,
        MessagesMotDePassePerdu.codeRequis,
        MessagesMotDePassePerdu.nouveauRequis,
        MessagesMotDePassePerdu.confirmationRequise,
      ]) {
        expect(find.text(m), findsOneWidget, reason: m);
      }
      final n = await c
          .read(baseLocaleProvider)
          .customSelect(
            'SELECT COUNT(*) AS n FROM journal_securite_local '
            "WHERE action LIKE 'code_secours_refus%'",
          )
          .getSingle();
      expect(n.data['n'], 0, reason: 'aucun essai consommé');
    });

    testWidgets('succès : le nouveau code est affiché UNE fois (copier, '
        'imprimer, ranger au coffre) ; l’ancien est consommé', (tester) async {
      final ancien = await adminAvecCode();
      final c = await monter(tester, '/mot-de-passe-administrateur-perdu');

      await tester.enterText(champ(0), 'Admin');
      await tester.enterText(champ(1), ancien.toLowerCase());
      await tester.enterText(champ(2), 'Tout-Neuf-Mdp-4');
      await tester.enterText(champ(3), 'Tout-Neuf-Mdp-4');
      await tester.tap(find.text(TextesCodeSecours.bouton));
      await attendre(tester);

      expect(find.text(TextesCodeSecours.nouveauCodeTitre), findsOneWidget);
      expect(
        find.text(MessagesMotDePassePerdu.mdpReinitialise),
        findsOneWidget,
      );
      expect(find.text(TextesCodeSecours.consigneCoffre), findsOneWidget);
      final nouveau = tester
          .widget<SelectableText>(
            find.byKey(const Key('code-secours-nouveau-valeur')),
          )
          .data!;
      expect(nouveau, isNot(ancien));
      expect(nouveau, matches(RegExp(r'^([A-Z2-9]{5}-){4}[A-Z2-9]{5}$')));

      // Copier : le presse-papiers reçoit le code, le bouton dit « Copié ».
      await tester.tap(find.byKey(const Key('code-secours-nouveau-copier')));
      await tester.pump();
      expect(pressePapiers, [nouveau]);
      expect(find.text(TextesSecretUnique.copie), findsOneWidget);
      // Imprimer : l'impression injectée reçoit le code et le compte.
      await tester.tap(find.byKey(const Key('code-secours-nouveau-imprimer')));
      await tester.pump();
      expect(impressions, [(nouveau, 'admin')]);

      // Le mot de passe a changé, l'ancien code ne sert plus.
      expect(
        (await c
                .read(depotSessionProvider)
                .connecter('admin', 'Tout-Neuf-Mdp-4'))
            .login,
        'admin',
      );
      expect(
        await c
            .read(codeSecoursProvider)
            .reinitialiser(
              login: 'admin',
              code: nouveau,
              nouveau: 'Autre-Mdp-Sur-5',
            )
            .then((_) => true),
        isTrue,
      );
    });

    testWidgets('aucun débordement, de 320 px au plus large', (tester) async {
      await adminAvecCode();
      for (final largeur in const [320.0, 768.0, 1440.0]) {
        await monter(
          tester,
          '/mot-de-passe-administrateur-perdu',
          largeur: largeur,
        );
        expect(tester.takeException(), isNull, reason: 'à $largeur px');
      }
    });
  });

  // ================================================ le premier compte

  group('Premier compte : le code de secours est remis une seule fois', () {
    testWidgets('créer le compte administrateur affiche le code AVANT '
        'd’entrer ; seul son dérivé est stocké', (tester) async {
      final c = await monter(
        tester,
        '/connexion',
        aucunCompte: true,
        largeur: 1000,
      );
      expect(find.byType(FormulairePremierCompte), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), 'n.kora');
      await tester.enterText(find.byType(TextFormField).at(1), 'KORA Noël');
      await tester.enterText(
        find.byType(TextFormField).at(2),
        'Admin-Secret-9',
      );
      await tester.enterText(
        find.byType(TextFormField).at(3),
        'Admin-Secret-9',
      );
      await tester.ensureVisible(find.text('Créer le compte administrateur'));
      await tester.tap(find.text('Créer le compte administrateur'));
      await attendre(tester);
      await attendre(tester);

      // La fenêtre du secret est ouverte, la session pas encore.
      expect(
        find.text(MessagesMotDePassePerdu.codeSecoursAfficheTitre),
        findsOneWidget,
      );
      expect(
        find.text(MessagesMotDePassePerdu.codeSecoursConsigne),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('premier-compte-code-copier')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('premier-compte-code-imprimer')),
        findsOneWidget,
      );
      expect(c.read(sessionProvider), isNull);
      final code = tester
          .widget<SelectableText>(
            find.byKey(const Key('premier-compte-code-valeur')),
          )
          .data!;
      expect(code, matches(RegExp(r'^([A-Z2-9]{5}-){4}[A-Z2-9]{5}$')));

      await tester.tap(find.byKey(const Key('premier-compte-code-imprimer')));
      await tester.pump();
      expect(impressions, [(code, 'n.kora')]);

      // « J'ai rangé ce code » ferme la fenêtre et la connexion s'enchaîne.
      await tester.tap(find.text(MessagesMotDePassePerdu.codeSecoursFermer));
      await attendre(tester);
      await attendre(tester);
      expect(c.read(sessionProvider)?.login, 'n.kora');

      // Seul le dérivé est en base.
      final l = await base
          .customSelect(
            'SELECT code_secours_empreinte AS e, code_secours_sel AS s '
            "FROM utilisateurs_local WHERE login = 'n.kora'",
          )
          .getSingle();
      expect(l.data['e'], isNotNull);
      expect(l.data['e'], isNot(contains(code)));
      expect(l.data['s'], isNot(contains(code)));
    });
  });
}
