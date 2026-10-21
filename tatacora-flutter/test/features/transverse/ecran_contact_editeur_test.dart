import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/fichiers/selecteur_fichiers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_dao.dart';
import 'package:tatacora_flutter/features/transverse/data/captures_editeur.dart';
import 'package:tatacora_flutter/features/transverse/data/configuration_poste.dart';
import 'package:tatacora_flutter/features/transverse/data/envoi_messages_editeur.dart';
import 'package:tatacora_flutter/features/transverse/data/messages_editeur_dao.dart';
import 'package:tatacora_flutter/features/transverse/domain/messages_editeur.dart';
import 'package:tatacora_flutter/features/transverse/presentation/ecran_contact_editeur.dart';
import 'package:tatacora_flutter/features/transverse/presentation/widgets/modales_contact_editeur.dart';
import 'package:tatacora_flutter/features/transverse/presentation/providers_contact_editeur.dart';

import '../../support/selecteur_essai.dart';

/// Un `poste.json` lu sans entrée-sortie réelle (le temps d'un test de widget
/// est simulé) — le cas « fichier absent » passe, lui, par le vrai lecteur.
final class _MotDePasseConnu extends LecteurConfigurationPoste {
  @override
  Future<LectureMotDePasse> motDePasseSmtp() async =>
      const MotDePasseLu('S3cret-Gite!');
}

/// L'écran « Contactez l'éditeur » (Lot J2 partie 2) avec un transport SMTP
/// d'essai : ce que l'opérateur LIT après chaque issue — envoyé, hors
/// connexion, mot de passe non configuré (avec le chemin exact) — et la file
/// « Messages en attente d'envoi » avec « Renvoyer maintenant ».
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  final courriels = <Message>[];
  Exception? erreur;
  Duration? lenteur;

  setUp(() async {
    db = AppDatabase.enMemoire();
    courriels.clear();
    erreur = null;
    lenteur = null;
    await db
        .into(db.utilisateursLocal)
        .insert(
          UtilisateursLocalCompanion.insert(
            id: 'u1',
            login: 'j.kora',
            nom: 'KORA Jean',
            role: 'receptionniste',
            droitsJson: '{}',
            sel: 's',
            empreinte: 'e',
            iterations: 1,
            dateCreation: DateTime(2026, 10, 1),
            dateMotDePasse: DateTime(2026, 10, 1),
          ),
        );
    await ParametresDao(db).ecrire({
      ClesSmtp.hote: 'mail.essai.local',
      ClesSmtp.utilisateur: 'contact@essai.local',
    }, auteurId: null);
  });
  tearDown(() => db.close());

  Future<void> transport(Message m, SmtpServer s, Duration d) async {
    courriels.add(m);
    final l = lenteur;
    if (l != null) await Future<void>.delayed(l);
    final e = erreur;
    if (e != null) throw e;
  }

  Future<void> monter(
    WidgetTester tester, {
    LecteurConfigurationPoste? configuration,
    FichierLu? capture,
  }) async {
    tester.view
      ..physicalSize = const Size(1600, 2400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final service = ServiceMessagesEditeur(
      dao: MessagesEditeurDao(db),
      parametres: ParametresDao(db),
      configuration: configuration ?? _MotDePasseConnu(),
      // Un dossier sans capture, sans entrée-sortie asynchrone : le temps d'un
      // test de widget est simulé.
      captures: CapturesEditeur(
        cheminConfiguration: () async => '/inexistant/poste.json',
      ),
      transport: transport,
      maintenant: () => DateTime(2026, 10, 15, 9, 30),
      envoiAutorise: true,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          serviceMessagesEditeurProvider.overrideWithValue(service),
          selecteurFichiersProvider.overrideWithValue(
            SelecteurEssai(lu: capture),
          ),
          sessionProvider.overrideWithBuild(
            (ref, notifier) => Session(
              utilisateurId: 'u1',
              login: 'j.kora',
              nom: 'KORA Jean',
              role: 'receptionniste',
              droits: GardeAcces.depuisJson(const {}),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranContactEditeur()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder cle(String k) => find.byKey(Key(k));

  Future<void> envoyerMessage(WidgetTester tester) async {
    await tester.tap(cle('contact-envoyer-message'));
    await tester.pumpAndSettle();
    await tester.enterText(cle('contact-saisie-objet'), 'Question');
    await tester.enterText(cle('contact-saisie-corps'), 'Bonjour');
    await tester.tap(cle('contact-modale-envoyer'));
    await tester.pumpAndSettle();
  }

  String texte(WidgetTester tester, String k) =>
      tester.widget<Text>(cle(k)).data!;

  Future<List<MessageEditeur>> boite() =>
      MessagesEditeurDao(db).envoisDuCompte('u1');

  /// Le statut affiché sur la ligne de « Vos envois » du message unique.
  Future<Finder> statutAffiche(String statut) async => find.descendant(
    of: cle('contact-envoi-${(await boite()).single.id}'),
    matching: find.textContaining(statut, findRichText: true),
  );

  testWidgets('envoyé : toast de succès, « Transmis », aucune file', (
    tester,
  ) async {
    await monter(tester);
    await envoyerMessage(tester);

    expect(courriels, hasLength(1));
    expect(texte(tester, 'contact-toast-envoye'), TextesContact.messageEnvoye);
    expect(
      await statutAffiche(TextesContact.envoisStatutTransmis),
      findsOneWidget,
    );
    expect(cle('contact-file-en-attente'), findsNothing);
    expect((await boite()).single.statut, StatutMessageEditeur.envoye);
  });

  testWidgets('un serveur SMTP LENT : « En attente d’envoi » pendant la '
      'tentative, « Transmis » dès qu’elle aboutit (l’écran se relit après '
      'l’envoi)', (tester) async {
    lenteur = const Duration(seconds: 5);
    await monter(tester);
    await envoyerMessage(tester);
    expect(courriels, hasLength(1));
    expect(
      await statutAffiche(TextesContact.envoisStatutATransmettre),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(texte(tester, 'contact-toast-envoye'), TextesContact.messageEnvoye);
    expect(
      await statutAffiche(TextesContact.envoisStatutTransmis),
      findsOneWidget,
    );
  });

  testWidgets('signalement de bug : son toast, l’objet « Bug — module »', (
    tester,
  ) async {
    await monter(tester);
    await tester.tap(cle('contact-signaler-bug'));
    await tester.pumpAndSettle();
    await tester.tap(cle('contact-saisie-module'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(modulesContactEditeur[1]).last);
    await tester.pumpAndSettle();
    await tester.enterText(cle('contact-saisie-corps'), 'Le total est faux');
    await tester.tap(cle('contact-modale-envoyer'));
    await tester.pumpAndSettle();
    expect(texte(tester, 'contact-toast-envoye'), TextesContact.bugSignale);
    expect(
      courriels.single.subject,
      objetCourrielEditeur(sujetBug(modulesContactEditeur[1])),
    );
  });

  testWidgets('capture d’écran : le champ de la vue, sa consigne, le nom '
      'choisi', (tester) async {
    await monter(
      tester,
      capture: FichierLu(
        nom: 'ecran.png',
        octets: Uint8List.fromList([1, 2, 3]),
      ),
    );
    await tester.tap(cle('contact-signaler-bug'));
    await tester.pumpAndSettle();
    expect(find.text(TextesModalesContact.bugCapture), findsOneWidget);
    expect(find.text(TextesModalesContact.bugCaptureInvite), findsOneWidget);
    expect(
      texte(tester, 'contact-capture-nom'),
      TextesModalesContact.captureAucune,
    );
    await tester.tap(cle('contact-capture-choisir'));
    await tester.pumpAndSettle();
    expect(texte(tester, 'contact-capture-nom'), 'ecran.png');
  });

  testWidgets('capture refusée : la phrase du serveur, rien n’est écrit', (
    tester,
  ) async {
    await monter(
      tester,
      capture: FichierLu(nom: 'ecran.gif', octets: Uint8List.fromList([1])),
    );
    await tester.tap(cle('contact-signaler-bug'));
    await tester.pumpAndSettle();
    await tester.tap(cle('contact-capture-choisir'));
    await tester.pumpAndSettle();
    await tester.tap(cle('contact-saisie-module'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(modulesContactEditeur[1]).last);
    await tester.pumpAndSettle();
    await tester.enterText(cle('contact-saisie-corps'), 'Le total est faux');
    await tester.tap(cle('contact-modale-envoyer'));
    await tester.pumpAndSettle();
    expect(texte(tester, 'contact-erreur-capture'), TextesCapture.nonImage);
    expect(await boite(), isEmpty);
  });

  testWidgets('hors connexion : « enregistré, partira », la file compte 1 et '
      'dit la dernière erreur ; « Renvoyer maintenant » l’envoie', (
    tester,
  ) async {
    erreur = const SocketException('Network is unreachable');
    await monter(tester);
    await envoyerMessage(tester);

    expect(
      texte(tester, 'contact-toast-en-file'),
      TextesContact.enregistreEnFile,
    );
    expect(cle('contact-file-en-attente'), findsOneWidget);
    expect(
      find.text('${TextesContact.fileTitre} (1)', findRichText: true),
      findsOneWidget,
    );
    expect(
      tester.widget<SelectableText>(cle('contact-file-erreur')).data,
      TextesContact.derniereErreur(
        TextesEnvoiEditeur.injoignable('Network is unreachable'),
      ),
    );
    expect(
      await statutAffiche(TextesContact.envoisStatutATransmettre),
      findsOneWidget,
    );

    // Le réseau revient.
    erreur = null;
    await tester.ensureVisible(cle('contact-renvoyer'));
    await tester.tap(cle('contact-renvoyer'));
    await tester.pumpAndSettle();
    expect(
      texte(tester, 'contact-toast-renvoi'),
      TextesContact.bilanRenvoi(1, 0),
    );
    expect(cle('contact-file-en-attente'), findsNothing);
    expect(courriels, hasLength(2));
    expect((await boite()).single.statut, StatutMessageEditeur.envoye);
    expect(
      await statutAffiche(TextesContact.envoisStatutTransmis),
      findsOneWidget,
    );
  });

  testWidgets('mot de passe NON configuré : l’écran le dit avec le chemin '
      'EXACT, rien ne part, aucune tentative comptée', (tester) async {
    final chemin =
        '${Directory.systemTemp.path}/tatacora-absent-${DateTime.now().microsecondsSinceEpoch}/poste.json';
    await monter(
      tester,
      configuration: LecteurConfigurationPoste(chemin: () async => chemin),
    );
    await envoyerMessage(tester);

    final raison = TextesConfigurationPoste.fichierAbsent(chemin);
    final toast = texte(tester, 'contact-toast-non-configure');
    expect(toast, TextesContact.enregistreNonConfigure(raison));
    expect(toast, contains(chemin));
    expect(toast, contains('Mot de passe SMTP non configuré'));
    expect(
      tester.widget<SelectableText>(cle('contact-file-erreur')).data,
      contains(chemin),
    );
    expect(courriels, isEmpty);
    final m = (await boite()).single;
    expect(m.tentatives, 0);
    expect(m.statut, StatutMessageEditeur.enAttente);
  });
}
