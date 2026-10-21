import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_dao.dart';
import 'package:tatacora_flutter/features/parametres/presentation/ecran_parametres.dart';
import 'package:tatacora_flutter/features/transverse/data/captures_editeur.dart';
import 'package:tatacora_flutter/features/transverse/data/configuration_poste.dart';
import 'package:tatacora_flutter/features/transverse/data/envoi_messages_editeur.dart';
import 'package:tatacora_flutter/features/transverse/data/messages_editeur_dao.dart';
import 'package:tatacora_flutter/features/transverse/presentation/providers_contact_editeur.dart';

final class _MotDePasseConnu extends LecteurConfigurationPoste {
  @override
  Future<LectureMotDePasse> motDePasseSmtp() async =>
      const MotDePasseLu('S3cret-Gite!');
}

/// Les onglets de Paramètres portés à la vue le 21/10/2026 : les bascules
/// d'activation (pastille de risque, application AU CLIC), l'email de test, les
/// canaux de réservation (le jeu du poste) et les deux champs refusés de
/// l'onglet Communication.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  final courriels = <Message>[];
  Exception? erreurTransport;

  setUp(() async {
    db = AppDatabase.enMemoire();
    courriels.clear();
    erreurTransport = null;
    await db
        .into(db.utilisateursLocal)
        .insert(
          UtilisateursLocalCompanion.insert(
            id: 'u-essai',
            login: 'essai',
            nom: 'Essai',
            role: 'administrateur',
            droitsJson: '{}',
            sel: 's',
            empreinte: 'e',
            iterations: 1,
            dateCreation: DateTime(2026, 10, 9),
            dateMotDePasse: DateTime(2026, 10, 9),
          ),
        );
  });
  tearDown(() => db.close());

  Future<void> transport(Message m, SmtpServer s, Duration d) async {
    courriels.add(m);
    final e = erreurTransport;
    if (e != null) throw e;
  }

  Future<void> monter(WidgetTester tester, {String niveau = 'C'}) async {
    tester.view
      ..physicalSize = const Size(1600, 2400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final droits = GardeAcces({'PARAM': niveau});
    final service = ServiceMessagesEditeur(
      dao: MessagesEditeurDao(db),
      parametres: ParametresDao(db),
      configuration: _MotDePasseConnu(),
      captures: CapturesEditeur(
        cheminConfiguration: () async => '/inexistant/poste.json',
      ),
      transport: transport,
      envoiAutorise: true,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          droitsProvider.overrideWithValue(droits),
          serviceMessagesEditeurProvider.overrideWithValue(service),
          sessionProvider.overrideWithBuild(
            (ref, n) => Session(
              utilisateurId: 'u-essai',
              login: 'essai',
              nom: 'Essai',
              role: 'administrateur',
              droits: droits,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranParametres()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> ouvrirOnglet(WidgetTester tester, String cle) async {
    await tester.tap(find.byKey(Key('param-onglet-$cle')));
    await tester.pumpAndSettle();
  }

  Future<Map<String, String>> enBase() async => {
    for (final l in await db.select(db.parametresSystemeLocal).get())
      l.cle: l.valeur,
  };

  group('Activation & Sécurité', () {
    testWidgets('les phrases de la vue, une rangée à bascule par option, la '
        'pastille de risque du maître', (tester) async {
      await monter(tester);
      await ouvrirOnglet(tester, 'activation');

      expect(find.text('Actions sensibles'), findsOneWidget);
      expect(
        find.textContaining('à tous les profils', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'les deux s\'appliquent, et la plus restrictive gagne.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('param-activation-info')), findsOneWidget);
      expect(find.text('Rappel sur la suppression'), findsOneWidget);

      Finder risque(String cle, String libelle) => find.descendant(
        of: find.byKey(Key('param-bascule-$cle')),
        matching: find.text(libelle),
      );
      expect(risque('activation_suppression', 'Risque modéré'), findsOneWidget);
      expect(
        risque('reinitialisation_seeders', 'Risque élevé'),
        findsOneWidget,
      );
      expect(
        risque('activation_alertes_ouverture', 'Risque faible'),
        findsOneWidget,
      );
    });

    testWidgets('une bascule s\'applique AU CLIC : la base, le message de la '
        'vue, l\'état de l\'interrupteur', (tester) async {
      await monter(tester);
      await ouvrirOnglet(tester, 'activation');
      expect(await enBase(), isNot(contains('activation_suppression')));

      await tester.tap(
        find.byKey(
          const Key('param-bascule-interrupteur-activation_suppression'),
        ),
      );
      await tester.pumpAndSettle();
      expect((await enBase())['activation_suppression'], 'true');
      expect(
        find.text('Suppression d\'un enregistrement — activée.'),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(
          const Key('param-bascule-interrupteur-activation_suppression'),
        ),
      );
      await tester.pumpAndSettle();
      expect((await enBase())['activation_suppression'], 'false');
    });

    testWidgets('sans le droit d\'écrire, l\'interrupteur ne répond pas', (
      tester,
    ) async {
      await monter(tester, niveau: 'L');
      await ouvrirOnglet(tester, 'activation');
      await tester.tap(
        find.byKey(
          const Key('param-bascule-interrupteur-activation_suppression'),
        ),
      );
      await tester.pumpAndSettle();
      expect(await enBase(), isNot(contains('activation_suppression')));
    });
  });

  group('Email (SMTP) — « Envoyer un email de test »', () {
    Future<void> poser(Map<String, String> valeurs) =>
        ParametresDao(db).ecrire(valeurs, auteurId: null);

    testWidgets('sans « Email de contact » : la phrase de la vue, rien ne '
        'part', (tester) async {
      await poser({
        ClesSmtp.hote: 'mail.essai.local',
        ClesSmtp.utilisateur: 'contact@essai.local',
      });
      await monter(tester);
      await ouvrirOnglet(tester, 'email');
      await tester.ensureVisible(find.byKey(const Key('param-email-test')));
      await tester.tap(find.byKey(const Key('param-email-test')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('param-email-test-resultat')))
            .data,
        "Aucune adresse de destination : renseignez d'abord « Email de contact » (onglet Identité & Légal).",
      );
      expect(courriels, isEmpty);
    });

    testWidgets('envoyé : le courriel part à l\'adresse de contact, la phrase '
        'est verte', (tester) async {
      await poser({
        ClesSmtp.hote: 'mail.essai.local',
        ClesSmtp.utilisateur: 'contact@essai.local',
        'entreprise_email': 'gite@essai.local',
      });
      await monter(tester);
      await ouvrirOnglet(tester, 'email');
      await tester.ensureVisible(find.byKey(const Key('param-email-test')));
      await tester.tap(find.byKey(const Key('param-email-test')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('param-email-test-resultat')))
            .data,
        'Email de test envoyé à gite@essai.local.',
      );
      expect(courriels.single.subject, 'Email de test — TATACORA AFRIQUE');
      expect(courriels.single.recipients, ['gite@essai.local']);
    });

    testWidgets('échec du transport : ce qu\'il a répondu, jamais un succès '
        'simulé', (tester) async {
      erreurTransport = Exception('relais indisponible');
      await poser({
        ClesSmtp.hote: 'mail.essai.local',
        ClesSmtp.utilisateur: 'contact@essai.local',
        'entreprise_email': 'gite@essai.local',
      });
      await monter(tester);
      await ouvrirOnglet(tester, 'email');
      await tester.ensureVisible(find.byKey(const Key('param-email-test')));
      await tester.tap(find.byKey(const Key('param-email-test')));
      await tester.pumpAndSettle();
      final texte = tester
          .widget<Text>(find.byKey(const Key('param-email-test-resultat')))
          .data!;
      expect(
        texte,
        startsWith('Échec de l\'envoi — le transport a répondu : '),
      );
      expect(texte, contains('relais indisponible'));
    });

    testWidgets('sans le droit d\'écrire, le bouton n\'existe pas', (
      tester,
    ) async {
      await monter(tester, niveau: 'L');
      await ouvrirOnglet(tester, 'email');
      expect(find.byKey(const Key('param-email-test')), findsNothing);
    });
  });

  testWidgets('Canaux de réservation : le jeu du poste, l\'intro de la vue, '
      'aucun geste inerte', (tester) async {
    await monter(tester);
    await ouvrirOnglet(tester, 'canaux');
    expect(find.byKey(const Key('param-canaux-tableau')), findsOneWidget);
    for (final canal in [
      'Physique',
      'Téléphone',
      'WhatsApp',
      'Booking.com',
      'Site web',
      'Facebook',
      'Agence partenaire',
    ]) {
      expect(find.text(canal), findsOneWidget, reason: canal);
    }
    expect(
      find.textContaining(
        'Un canal utilisé ne se supprime pas, il se désactive',
        findRichText: true,
      ),
      findsOneWidget,
    );
    // Les gestes de la vue (ajout, renommage, désactivation) sont REFUSÉS : le
    // poste n'en offre aucun, et le dit.
    expect(find.text('Ajouter un canal'), findsNothing);
    expect(find.text('Renommer'), findsNothing);
    expect(find.byKey(const Key('param-canaux-sur-ce-poste')), findsOneWidget);
  });

  testWidgets('Communication : la clé API et le message de bienvenue, '
      'refusés comme valeurs et dits', (tester) async {
    await monter(tester);
    await ouvrirOnglet(tester, 'communication');
    for (final cle in ['param-cle-api-whatsapp', 'param-message-bienvenue']) {
      expect(find.byKey(Key(cle)), findsOneWidget, reason: cle);
    }
    expect(find.text('Clé API WhatsApp Business'), findsOneWidget);
    expect(
      find.text('Message de bienvenue (notifications automatiques)'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Secret technique : n\'entrera jamais dans les paramètres système',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Porté par les modèles du module Notifications'),
      findsOneWidget,
    );
  });

  group('Espaces & tables', () {
    testWidgets('« Nouvelle table » : l\'invite « Choisir un espace… », et un '
        'espace non choisi est refusé', (tester) async {
      await monter(tester);
      await ouvrirOnglet(tester, 'tables');
      await tester.tap(find.byKey(const Key('param-tables-ajouter')));
      await tester.pumpAndSettle();
      expect(find.text('Choisir un espace…'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('param-table-numero')), '7');
      await tester.tap(find.byKey(const Key('param-table-valider')));
      await tester.pumpAndSettle();
      // Refusé, la fenêtre reste ouverte, rien n'est écrit.
      expect(find.byKey(const Key('param-modale-table')), findsOneWidget);
      expect(find.textContaining('Espace inconnu'), findsOneWidget);
    });

    testWidgets('« Rétablir le jeu initial » : la confirmation de la vue, '
        'puis le message ; annuler ne change rien', (tester) async {
      await monter(tester);
      await ouvrirOnglet(tester, 'tables');
      await tester.tap(find.byKey(const Key('param-tables-retablir')));
      await tester.pumpAndSettle();
      expect(find.text('Rétablir le jeu initial ?'), findsOneWidget);
      expect(
        find.text(
          'Les treize tables d\'origine remplaceront la configuration actuelle. Les ventes déjà enregistrées ne sont pas touchées.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('param-retablir-annuler')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('param-modale-retablir')), findsNothing);

      await tester.tap(find.byKey(const Key('param-tables-retablir')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('param-retablir-confirmer')));
      await tester.pumpAndSettle();
      expect(find.text('Jeu initial rétabli.'), findsOneWidget);
    });

    testWidgets('sans le droit d\'écrire, ni « Ajouter » ni « Rétablir »', (
      tester,
    ) async {
      await monter(tester, niveau: 'L');
      await ouvrirOnglet(tester, 'tables');
      expect(find.byKey(const Key('param-tables-ajouter')), findsNothing);
      expect(find.byKey(const Key('param-tables-retablir')), findsNothing);
    });
  });
}
