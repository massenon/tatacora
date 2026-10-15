@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_dao.dart';
import 'package:tatacora_flutter/features/parametres/domain/options_systeme.dart';
import 'package:tatacora_flutter/features/transverse/data/configuration_poste.dart';
import 'package:tatacora_flutter/features/transverse/data/envoi_messages_editeur.dart';
import 'package:tatacora_flutter/features/transverse/data/messages_editeur_dao.dart';
import 'package:tatacora_flutter/features/transverse/data/reinitialisation_locale.dart';
import 'package:tatacora_flutter/features/transverse/domain/messages_editeur.dart';
import 'package:tatacora_flutter/features/transverse/presentation/providers_contact_editeur.dart';

import '../comptabilite/support/outils_comptabilite.dart';

/// Un transport SMTP d'essai : AUCUN réseau. Il note chaque courriel, peut
/// lever ([erreur]) ou retenir l'envoi ([retenue]) pour éprouver la
/// concurrence, et appelle [pendant] au moment où l'envoi a lieu.
final class TransportEssai {
  final List<Message> courriels = [];
  final List<SmtpServer> serveurs = [];
  Exception? erreur;
  Completer<void>? retenue;
  Future<void> Function(Message)? pendant;

  int get appels => courriels.length;

  Future<void> call(Message m, SmtpServer s, Duration delai) async {
    courriels.add(m);
    serveurs.add(s);
    await pendant?.call(m);
    final r = retenue;
    if (r != null) await r.future;
    final e = erreur;
    if (e != null) throw e;
  }
}

/// « Contactez l'éditeur » — la boîte d'envoi et son expéditeur (Lot J2
/// partie 2) : écrit AVANT d'envoyer, jamais perdu, jamais deux fois, jamais
/// de secret en base, relances espacées, démonstration muette. Le transport
/// est un double : aucun octet ne part sur le réseau.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const secret = 'S3cret-Gite!';
  late AppDatabase db;
  late MessagesEditeurDao dao;
  late TransportEssai transport;
  late Directory dossier;
  late String cheminPoste;
  late DateTime horloge;

  setUp(() async {
    db = AppDatabase.enMemoire();
    dao = MessagesEditeurDao(db);
    transport = TransportEssai();
    horloge = DateTime(2026, 10, 15, 8);
    dossier = Directory.systemTemp.createTempSync('poste_json_');
    cheminPoste = '${dossier.path}/poste.json';
    File(
      cheminPoste,
    ).writeAsStringSync(jsonEncode({cleMotDePasseSmtp: secret}));
    await ParametresDao(db).ecrire({
      ClesSmtp.hote: 'mail.essai.local',
      ClesSmtp.port: '587',
      ClesSmtp.securite: 'tls',
      ClesSmtp.utilisateur: 'contact@essai.local',
    }, auteurId: null);
  });
  tearDown(() async {
    await db.close();
    dossier.deleteSync(recursive: true);
  });

  ServiceMessagesEditeur service({bool envoiAutorise = true, String? chemin}) =>
      ServiceMessagesEditeur(
        dao: dao,
        parametres: ParametresDao(db),
        configuration: LecteurConfigurationPoste(
          chemin: () async => chemin ?? cheminPoste,
        ),
        transport: transport.call,
        maintenant: () => horloge,
        envoiAutorise: envoiAutorise,
      );

  Future<MessageEditeur> ecrire(
    ServiceMessagesEditeur s, {
    String sujet = 'Question',
    String corps = 'Bonjour',
  }) => s.enregistrer(
    (
      type: TypeMessageEditeur.message,
      sujet: sujet,
      moduleConcerne: null,
      corps: corps,
      etapes: null,
    ),
    auteurId: null,
    auteurLogin: 'j.kora',
  );

  Future<int> lignes() async =>
      (await db
                  .customSelect(
                    'SELECT COUNT(*) AS n FROM messages_editeur_local',
                  )
                  .getSingle())
              .data['n']
          as int;

  Future<MessageEditeur> relu(String id) async => (await dao.parId(id))!;

  group('Écrit AVANT d’envoyer, jamais perdu', () {
    test(
      'au moment de l’envoi la ligne EXISTE déjà, en_attente ; le '
      'transport lève : elle reste, tentative comptée, raison notée',
      () async {
        final s = service();
        final statutsVus = <String?>[];
        transport.pendant = (m) async {
          final brut = await db.select(db.messagesEditeurLocal).get();
          statutsVus.addAll(brut.map((l) => l.statut));
        };
        transport.erreur = const SocketException('Connexion refusée');

        final m = await ecrire(s);
        final r = await s.envoyer(m);

        expect(statutsVus, ['en_attente'], reason: 'écrit avant la tentative');
        expect(r.issue, IssueEnvoiEditeur.echoue);
        final apres = await relu(m.id);
        expect(apres.statut, StatutMessageEditeur.enAttente);
        expect(apres.tentatives, 1);
        expect(
          apres.derniereErreur,
          TextesEnvoiEditeur.injoignable('Connexion refusée'),
        );
        expect(apres.derniereTentative, horloge);
        expect(apres.envoyeLe, isNull);
        expect(await lignes(), 1);
      },
    );

    test(
      'accepté : envoye + envoye_le ; la ligne reste (jamais supprimée)',
      () async {
        final s = service();
        final m = await ecrire(s);
        horloge = horloge.add(const Duration(minutes: 1));
        final r = await s.envoyer(m);
        expect(r.issue, IssueEnvoiEditeur.envoye);
        final apres = await relu(m.id);
        expect(apres.statut, StatutMessageEditeur.envoye);
        expect(apres.envoyeLe, horloge);
        expect(apres.derniereErreur, isNull);
        expect(await lignes(), 1);
        // Le DAO n'a aucun chemin de suppression.
        final source = File(
          'lib/features/transverse/data/messages_editeur_dao.dart',
        ).readAsStringSync();
        expect(source, contains('update(messagesEditeurLocal)'));
        expect(source, isNot(contains('delete(')));
      },
    );
  });

  group('Configuration absente : rien ne part, rien n’est compté', () {
    test('poste.json ABSENT : non tenté, compteur à 0, la raison nomme le '
        'chemin exact', () async {
      final absent = '${dossier.path}/inexistant/poste.json';
      final s = service(chemin: absent);
      final m = await ecrire(s);
      final r = await s.envoyer(m);
      expect(r.issue, IssueEnvoiEditeur.nonConfigure);
      expect(r.raison, TextesConfigurationPoste.fichierAbsent(absent));
      expect(r.raison, contains(absent));
      expect(transport.appels, 0);
      final apres = await relu(m.id);
      expect(apres.tentatives, 0);
      expect(apres.derniereTentative, isNull);
      expect(apres.statut, StatutMessageEditeur.enAttente);
      expect(apres.derniereErreur, r.raison);

      // La relance non plus ne compte rien.
      await s.relancer();
      await s.relancer();
      expect(transport.appels, 0);
      expect((await relu(m.id)).tentatives, 0);
    });

    test('clé absente, fichier illisible, serveur ou utilisateur SMTP '
        'manquant : non tenté, raison dite', () async {
      final s = service();
      final m = await ecrire(s);

      File(cheminPoste).writeAsStringSync(jsonEncode({'autre': 'x'}));
      expect(
        (await s.envoyer(m)).raison,
        TextesConfigurationPoste.cleAbsente(cheminPoste),
      );
      File(cheminPoste).writeAsStringSync('{ pas du json');
      expect(
        (await s.envoyer(m)).raison,
        TextesConfigurationPoste.fichierIllisible(cheminPoste),
      );
      File(
        cheminPoste,
      ).writeAsStringSync(jsonEncode({cleMotDePasseSmtp: secret}));
      await ParametresDao(db).ecrire({ClesSmtp.hote: null}, auteurId: null);
      expect((await s.envoyer(m)).raison, TextesEnvoiEditeur.hoteAbsent);
      await ParametresDao(db).ecrire({
        ClesSmtp.hote: 'mail.essai.local',
        ClesSmtp.utilisateur: '  ',
      }, auteurId: null);
      expect((await s.envoyer(m)).raison, TextesEnvoiEditeur.utilisateurAbsent);

      expect(transport.appels, 0);
      expect((await relu(m.id)).tentatives, 0);
    });

    test('la DÉMONSTRATION n’envoie jamais, même configurée', () async {
      final s = service(envoiAutorise: false);
      final m = await ecrire(s);
      final r = await s.envoyer(m);
      expect(r.issue, IssueEnvoiEditeur.nonConfigure);
      expect(r.raison, TextesEnvoiEditeur.demo);
      await s.relancer(forcer: true);
      expect(transport.appels, 0);
      expect((await relu(m.id)).tentatives, 0);

      // Et le point d'entrée de démonstration ne démarre pas la relance ;
      // celui de production, si.
      final demo = File('lib/main_demo.dart').readAsStringSync();
      final prod = File('lib/main.dart').readAsStringSync();
      expect(prod, contains('ref.read(relanceMessagesEditeurProvider)'));
      expect(demo, isNot(contains('relanceMessagesEditeurProvider')));
    });
  });

  test('le mot de passe SMTP n’est écrit NULLE PART en base, même quand '
      'l’erreur du serveur le cite', () async {
    final s = service();
    final a = await ecrire(s, sujet: 'A');
    transport.erreur = SocketException('auth refusée pour $secret');
    final r = await s.envoyer(a);
    expect(r.raison, isNot(contains(secret)));
    expect(r.raison, contains('***'));
    transport.erreur = null;
    final b = await ecrire(s, sujet: 'B');
    await s.envoyer(b);
    // Il est bien passé AU TRANSPORT (sinon l'essai ne prouverait rien).
    expect(transport.serveurs.last.password, secret);

    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%'",
        )
        .get();
    expect(tables.length, greaterThan(40), reason: 'balayage non vide');
    var cellules = 0;
    for (final t in tables) {
      final nom = t.data['name'] as String;
      for (final ligne in await db.customSelect('SELECT * FROM "$nom"').get()) {
        for (final e in ligne.data.entries) {
          cellules++;
          expect(
            '${e.value}'.contains(secret),
            isFalse,
            reason: '$nom.${e.key}',
          );
        }
      }
    }
    expect(cellules, greaterThan(20));
  });

  group('Relances', () {
    test('délais : 5, 10, 20, 40, 80, 160, 320 min, puis 6 h', () {
      expect(PolitiqueRelanceEditeur.delaiApres(0), Duration.zero);
      expect(
        [for (var n = 1; n <= 10; n++) PolitiqueRelanceEditeur.delaiApres(n)],
        [
          for (final m in [5, 10, 20, 40, 80, 160, 320]) Duration(minutes: m),
          const Duration(hours: 6),
          const Duration(hours: 6),
          const Duration(hours: 6),
        ],
      );
    });

    test('due / pas due selon l’horloge : un message échoué n’est repris '
        'qu’à l’échéance de SON délai', () async {
      final s = service();
      transport.erreur = const SocketException('hors ligne');
      final m = await ecrire(s);
      final t0 = horloge;
      await s.relancer(); // 1re tentative (jamais tentée : due)
      expect(transport.appels, 1);

      horloge = t0.add(const Duration(minutes: 4, seconds: 59));
      expect(await s.relancer(), (envoyes: 0, restants: 1));
      expect(transport.appels, 1, reason: 'pas dû avant 5 min');

      horloge = t0.add(const Duration(minutes: 5));
      await s.relancer();
      expect(transport.appels, 2);
      expect((await relu(m.id)).tentatives, 2);

      final t1 = horloge;
      horloge = t1.add(const Duration(minutes: 9));
      await s.relancer();
      expect(transport.appels, 2, reason: 'pas dû avant 10 min');
      horloge = t1.add(const Duration(minutes: 10));
      transport.erreur = null;
      final bilan = await s.relancer();
      expect(bilan, (envoyes: 1, restants: 0));
      expect((await relu(m.id)).statut, StatutMessageEditeur.envoye);
    });

    test('après 30 tentatives RÉELLES : echec, GARDÉ, plus relancé seul ; '
        '« Renvoyer maintenant » le remet en file et l’envoie', () async {
      final s = service();
      transport.erreur = const SocketException('hors ligne');
      final m = await ecrire(s);
      for (var i = 0; i < PolitiqueRelanceEditeur.tentativesMax; i++) {
        await s.relancer();
        horloge = horloge.add(const Duration(hours: 7));
      }
      expect(transport.appels, 30);
      var apres = await relu(m.id);
      expect(apres.statut, StatutMessageEditeur.echec);
      expect(apres.tentatives, 30);
      expect(await lignes(), 1);
      expect((await dao.etatFile()).enEchec, 1);

      horloge = horloge.add(const Duration(days: 3));
      await s.relancer();
      expect(transport.appels, 30, reason: 'echec : plus relancé seul');

      transport.erreur = null;
      final bilan = await s.relancer(forcer: true);
      expect(bilan, (envoyes: 1, restants: 0));
      expect(transport.appels, 31);
      apres = await relu(m.id);
      expect(apres.statut, StatutMessageEditeur.envoye);
      expect(apres.tentatives, 30, reason: 'le compteur dit l’histoire');
    });

    test(
      'le plus ANCIEN d’abord ; la relance S’ARRÊTE au premier échec',
      () async {
        final s = service();
        horloge = DateTime(2026, 10, 15, 9);
        await ecrire(s, sujet: 'deuxième');
        horloge = DateTime(2026, 10, 15, 10);
        await ecrire(s, sujet: 'troisième');
        horloge = DateTime(2026, 10, 15, 8);
        await ecrire(s, sujet: 'premier');
        horloge = DateTime(2026, 10, 15, 11);

        transport.erreur = const SocketException('hors ligne');
        expect(await s.relancer(), (envoyes: 0, restants: 3));
        expect(transport.appels, 1, reason: 'arrêt au premier échec');
        expect(transport.courriels.single.subject, '[TATACORA] premier');
        final file = await dao.enAttente();
        expect(file.map((m) => m.tentatives), [1, 0, 0]);

        transport.erreur = null;
        await s.relancer(forcer: true);
        expect(transport.courriels.skip(1).map((c) => c.subject), [
          '[TATACORA] premier',
          '[TATACORA] deuxième',
          '[TATACORA] troisième',
        ]);
      },
    );
  });

  group('Jamais deux fois le même message', () {
    /// Laisse tourner les tâches en cours, borné : une attente qui ne
    /// finirait jamais ferait expirer l'essai au lieu de le faire échouer.
    Future<void> laisser() async {
      for (var i = 0; i < 200; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('geste et relance SIMULTANÉS : un seul envoi', () async {
      final s = service();
      final m = await ecrire(s);
      final retenue = transport.retenue = Completer<void>();
      addTearDown(() {
        if (!retenue.isCompleted) retenue.complete();
      });

      final geste = s.envoyer(m);
      await laisser();
      expect(transport.appels, 1, reason: 'le geste est en vol');
      // Pendant le vol : la relance périodique trouve le message en_attente,
      // et un second geste aussi.
      final relance = s.relancer();
      final second = s.envoyer(m);
      await laisser();
      expect(transport.appels, 1, reason: 'déjà en vol : pas de second envoi');

      retenue.complete();
      expect((await relance)?.envoyes, 0);
      expect((await second).issue, IssueEnvoiEditeur.dejaEnCours);
      expect((await geste).issue, IssueEnvoiEditeur.envoye);
      await s.relancer(forcer: true);
      expect(transport.appels, 1);
      expect((await relu(m.id)).statut, StatutMessageEditeur.envoye);
    });

    test('deux relances simultanées : la seconde ne fait rien', () async {
      final s = service();
      await ecrire(s);
      final retenue = transport.retenue = Completer<void>();
      addTearDown(() {
        if (!retenue.isCompleted) retenue.complete();
      });
      final premiere = s.relancer();
      await laisser();
      expect(transport.appels, 1);
      final seconde = s.relancer(forcer: true);
      await laisser();
      retenue.complete();
      expect(await seconde, isNull);
      expect(await premiere, (envoyes: 1, restants: 0));
      expect(transport.appels, 1);
    });
  });

  group('Le courriel', () {
    test('destinataire = le défaut de config/contact_editeur.php du SERVEUR '
        '(relu par PHP), expéditeur et serveur SMTP du poste', () async {
      final r = await Process.run('php', [
        '-r',
        r'function env($k, $d = null) { return $d; } '
            r'echo json_encode(require "config/contact_editeur.php");',
      ], workingDirectory: '../tatacora-api');
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final destinataires =
          ((jsonDecode(r.stdout as String) as Map)['destinataires'] as List)
              .cast<String>();
      expect(destinataires, isNotEmpty);
      expect(destinataires, [adresseSupportEditeur]);

      final s = service();
      await s.envoyer(await ecrire(s));
      final c = transport.courriels.single;
      expect(c.recipients, destinataires);
      final from = c.from as Address;
      expect(from.mailAddress, 'contact@essai.local');
      expect(from.name, nomExpediteurEditeur);
      final srv = transport.serveurs.single;
      expect(srv.host, 'mail.essai.local');
      expect(srv.port, 587);
      expect(srv.ssl, isFalse);
      expect(srv.username, 'contact@essai.local');

      await ParametresDao(
        db,
      ).ecrire({ClesSmtp.securite: 'ssl', ClesSmtp.port: null}, auteurId: null);
      await s.envoyer(await ecrire(s));
      expect(transport.serveurs.last.ssl, isTrue);
      expect(transport.serveurs.last.port, 465);
    });

    test('objet et corps : ceux de MessageEditeurMail du SERVEUR, exécuté par '
        'PHP — le poste n’ajoute que le poste et la date', () async {
      final s = service();
      final m = await s.enregistrer(
        (
          type: TypeMessageEditeur.bug,
          sujet: sujetBug('M2 — Facturation'),
          moduleConcerne: 'M2 — Facturation',
          corps: 'Le total TTC est faux',
          etapes: '1. Ouvrir une facture',
        ),
        auteurId: null,
        auteurLogin: 'j.kora',
      );
      await s.envoyer(m);
      final c = transport.courriels.single;

      const php = r'''
require 'vendor/autoload.php';
$app = require 'bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$e = json_decode($argv[1], true);
$m = new App\Shared\ContactEditeur\Models\MessageEditeur();
$m->forceFill(['type' => $e['type'], 'objet' => $e['objet'], 'module_concerne' => $e['module'], 'corps' => $e['corps'], 'etapes' => $e['etapes']]);
$m->setRelation('auteur', (object) ['login' => $e['login']]);
$mail = new App\Shared\ContactEditeur\Mail\MessageEditeurMail($m);
echo json_encode(['objet' => $mail->envelope()->subject, 'corps' => $mail->corps()]);
''';
      final r = await Process.run(
        'php',
        [
          '-r',
          php,
          jsonEncode({
            'type': m.type.code,
            'objet': m.sujet,
            'module': m.moduleConcerne,
            'corps': m.corps,
            'etapes': m.etapes,
            'login': m.auteurLogin,
          }),
        ],
        workingDirectory: '../tatacora-api',
        stdoutEncoding: utf8,
      );
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final serveur = jsonDecode(r.stdout as String) as Map<String, dynamic>;
      expect(c.subject, serveur['objet']);

      // Chaque ligne du serveur, dans son ordre ; les seules lignes en plus
      // sont « Poste : » et « Date : ».
      final attendues = (serveur['corps'] as String).split('\n');
      expect(attendues.length, greaterThan(5));
      final lignesPoste = c.text!.split('\n');
      final enPlus = [...lignesPoste];
      var i = 0;
      for (final l in attendues) {
        i = lignesPoste.indexOf(l, i);
        expect(i, greaterThanOrEqualTo(0), reason: 'ligne du serveur : $l');
        enPlus.remove(l);
        i++;
      }
      expect(enPlus, hasLength(2));
      expect(enPlus.first, startsWith('Poste : '));
      expect(enPlus.last, 'Date : ${dateHeureEditeur(m.creeLe)}');
    });
  });

  test('« Réinitialiser comme neuf » GARDE la boîte d’envoi', () async {
    final base = await baseInstallee(maintenant: DateTime(2031, 6, 15));
    addTearDown(base.close);
    final d = MessagesEditeurDao(base);
    final a = await d.enregistrer(
      (
        type: TypeMessageEditeur.message,
        sujet: 'en attente',
        moduleConcerne: null,
        corps: 'x',
        etapes: null,
      ),
      auteurId: auteurEssai,
      auteurLogin: 'compta',
      poste: 'P',
      maintenant: DateTime(2031, 6, 1),
    );
    final b = await d.enregistrer(
      (
        type: TypeMessageEditeur.bug,
        sujet: 'envoyé',
        moduleConcerne: 'Paramètres',
        corps: 'y',
        etapes: null,
      ),
      auteurId: auteurEssai,
      auteurLogin: 'compta',
      poste: 'P',
      maintenant: DateTime(2031, 6, 2),
    );
    await d.marquerEnvoye(b.id, maintenant: DateTime(2031, 6, 2, 1));
    await ParametresDao(
      base,
    ).ecrire({OptionsSysteme.cleReinitialisationSeeders: '1'}, auteurId: null);

    final moteur = ReinitialisationLocale(base);
    expect(
      await moteur.tablesEffacables(),
      isNot(contains('messages_editeur_local')),
    );
    final bilan = await moteur.executer(role: 'administrateur');
    expect(bilan.tablesVidees, greaterThan(0), reason: 'la remise a eu lieu');

    expect((await d.parId(a.id))!.statut, StatutMessageEditeur.enAttente);
    expect((await d.parId(b.id))!.statut, StatutMessageEditeur.envoye);
  });

  testWidgets('la relance de main.dart : une fois au démarrage, puis toutes '
      'les 5 minutes ; arrêtée avec son conteneur', (tester) async {
    final s = service();
    await tester.runAsync(() async {
      transport.erreur = const SocketException('hors ligne');
      await ecrire(s);
    });
    final conteneur = ProviderContainer(
      overrides: [
        baseLocaleProvider.overrideWithValue(db),
        serviceMessagesEditeurProvider.overrideWithValue(s),
      ],
    );
    final revisionAvant = conteneur.read(revisionBoiteEditeurProvider);

    Future<void> laisserTourner() async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }
    }

    conteneur.read(relanceMessagesEditeurProvider);
    await laisserTourner();
    expect(transport.appels, 1, reason: 'relance au démarrage');
    expect(conteneur.read(revisionBoiteEditeurProvider), revisionAvant + 1);

    // Cinq minutes plus tard (horloge du service ET minuteur).
    horloge = horloge.add(PolitiqueRelanceEditeur.periode);
    await tester.pump(PolitiqueRelanceEditeur.periode);
    await laisserTourner();
    expect(transport.appels, 2, reason: 'relance périodique');

    conteneur.dispose();
    horloge = horloge.add(const Duration(hours: 1));
    await tester.pump(const Duration(hours: 1));
    await laisserTourner();
    expect(transport.appels, 2, reason: 'minuteur arrêté');
  });
}
