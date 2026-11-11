import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/alertes/domain/modales_ouverture.dart';
import 'package:tatacora_flutter/features/alertes/presentation/modales_ouverture.dart';
import 'package:tatacora_flutter/features/alertes/presentation/providers_alertes.dart';
import 'package:tatacora_flutter/features/hebergement/data/sejour_dao.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_dao.dart';
import 'package:tatacora_flutter/features/parametres/domain/options_systeme.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';

import '../facturation/support/outils_encaissement.dart';

/// Les DEUX modales d'ouverture de session : la séquence, les blocs, les deux
/// gestes inline, les droits, et « une fois par CONNEXION ». Les règles des
/// lignes sont confrontées au vrai serveur par
/// `modales_ouverture_contre_serveur_test.dart`.
void main() {
  late AppDatabase db;

  /// « Aujourd'hui » des alertes : 27/10/2026. La réservation d'essai part le
  /// 22/10 (départ DÉPASSÉ), la facture date de 40 jours.
  final aujourdhui = DateTime(2026, 10, 27, 10);

  setUp(() async {
    db = await baseEncaissement();
  });

  tearDown(() => db.close());

  Future<void> activerBascule(bool ouverte) => ParametresDao(db).ecrire({
    OptionsSysteme.cleAlertesOuverture: ouverte ? 'true' : 'false',
  }, auteurId: null);

  /// Un client débiteur de 50 000 FCFA depuis 40 jours.
  Future<String> clientDebiteur({String nom = 'KORA', int jours = 40}) async {
    final c = await creerClient(
      db,
      nom: nom,
      telephone: '9${nom.hashCode.abs() % 10000000}',
    );
    await emettreFacture(
      db,
      clientId: c.id,
      clientNom: nom,
      horloge: aujourdhui.subtract(Duration(days: jours)),
    );
    return c.id;
  }

  /// Un séjour OUVERT dont le départ prévu (22/10) est dépassé.
  Future<void> sejourEnCours(String clientId) async {
    await semerReservation(db, id: 'r1', clientId: clientId);
    await SejourDao(db).checkin('r1');
  }

  Future<void> articleSousSeuil() async {
    final stocks = StocksDao(db);
    final point = await stocks.creerPoint(libelle: 'Magasin');
    await stocks.creerArticle(
      id: 'a1',
      libelle: 'Bière',
      categorie: null,
      uniteMesure: 'casier',
      seuilCentiemes: 500,
      suivi: SuiviArticle.permanent,
      pointStockageId: point.id,
      auteurId: caissierEssai,
      ouverture: (centiemes: 300, coutDixMilliemes: null),
    );
  }

  late ProviderContainer conteneur;
  late GoRouter routeur;

  Future<void> monter(
    WidgetTester tester, {
    Map<String, String> droits = const {'M1': 'C', 'M3': 'C', 'M6': 'C'},
  }) async {
    tester.view
      ..physicalSize = const Size(1400, 1800)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    conteneur = ProviderContainer(
      overrides: [
        ...surchargesEncaissement(db, droits: droits),
        horlogeAlertesProvider.overrideWithValue(() => aujourdhui),
      ],
    );
    routeur = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: HoteModalesOuverture()),
        ),
        for (final r in ['/stocks', '/crm', '/hebergement/reservations'])
          GoRoute(path: r, builder: (_, _) => Text('page $r')),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: conteneur,
        child: MaterialApp.router(theme: AppTheme.clair, routerConfig: routeur),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> seConnecter(WidgetTester tester) async {
    conteneur.read(ouvertureEnAttenteProvider.notifier).poser();
    await tester.pumpAndSettle();
  }

  /// Le cas qui démonte l'arbre puis libère les providers.
  void cas(String nom, Future<void> Function(WidgetTester) corps) {
    testWidgets(nom, (tester) async {
      try {
        await corps(tester);
      } finally {
        await tester.pumpWidget(const SizedBox());
        conteneur.dispose();
      }
    });
  }

  Finder titre(String t) => find.text(t);
  Finder cle(String k) => find.byKey(Key(k));

  group('Une fois par CONNEXION, jamais par page', () {
    cas('une session RESTAURÉE ne déclenche rien', (tester) async {
      final c = await clientDebiteur();
      await sejourEnCours(c);
      await monter(tester);
      expect(cle('ouverture-modale-1'), findsNothing);
    });

    cas('rien à signaler : aucune modale, et le drapeau est consommé', (
      tester,
    ) async {
      await monter(tester);
      await seConnecter(tester);
      expect(cle('ouverture-modale-1'), findsNothing);
      expect(conteneur.read(ouvertureEnAttenteProvider), isFalse);
    });

    cas(
      'la bascule « Alertes à l’ouverture » fermée : rien, drapeau consommé',
      (tester) async {
        final c = await clientDebiteur();
        await sejourEnCours(c);
        await activerBascule(false);
        await monter(tester);
        await seConnecter(tester);
        expect(cle('ouverture-modale-1'), findsNothing);
        expect(conteneur.read(ouvertureEnAttenteProvider), isFalse);
      },
    );

    cas('une nouvelle connexion les montre de nouveau', (tester) async {
      final c = await clientDebiteur();
      await sejourEnCours(c);
      await monter(tester);
      await seConnecter(tester);
      await tester.tap(cle('ouverture-avancer'));
      await tester.pumpAndSettle();
      expect(cle('ouverture-modale-1'), findsNothing);

      await seConnecter(tester);
      expect(cle('ouverture-modale-1'), findsOneWidget);
    });
  });

  group('La séquence : stock, puis opérations', () {
    cas('deux étapes : compteur « 1 / 2 », « Suivant → » puis « J’ai pris '
        'connaissance »', (tester) async {
      final c = await clientDebiteur();
      await sejourEnCours(c);
      await articleSousSeuil();
      await monter(tester);
      await seConnecter(tester);

      expect(titre(TextesOuverture.titreStock), findsOneWidget);
      expect(
        titre('${TextesOuverture.sousTitreStock} — 1 / 2'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: cle('ouverture-avancer'),
          matching: find.text('Suivant →'),
        ),
        findsOneWidget,
      );
      // La ligne de stock : libellé, détail du serveur.
      expect(find.text('Bière'), findsOneWidget);
      expect(find.text('Stock 3 casier — seuil d’alerte 5'), findsOneWidget);

      await tester.tap(cle('ouverture-avancer'));
      await tester.pumpAndSettle();
      expect(titre(TextesOuverture.titreOperations), findsOneWidget);
      expect(
        titre('${TextesOuverture.sousTitreOperations} — 2 / 2'),
        findsOneWidget,
      );
      expect(find.text('J’ai pris connaissance'), findsOneWidget);

      await tester.tap(cle('ouverture-avancer'));
      await tester.pumpAndSettle();
      expect(cle('ouverture-modale-2'), findsNothing);
    });

    cas('une seule étape : pas de compteur', (tester) async {
      final c = await clientDebiteur();
      await sejourEnCours(c);
      await monter(tester);
      await seConnecter(tester);
      expect(titre(TextesOuverture.sousTitreOperations), findsOneWidget);
      expect(find.textContaining(' / '), findsNothing);
    });

    cas('Échap fait AVANCER, comme le voile (fermer="avancer")', (
      tester,
    ) async {
      final c = await clientDebiteur();
      await sejourEnCours(c);
      await articleSousSeuil();
      await monter(tester);
      await seConnecter(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(titre(TextesOuverture.titreOperations), findsOneWidget);
    });

    cas('un bloc dont le module est masqué n’est pas lu : pas de stock', (
      tester,
    ) async {
      final c = await clientDebiteur();
      await sejourEnCours(c);
      await articleSousSeuil();
      await monter(tester, droits: const {'M1': 'C', 'M3': 'C', 'M6': '-'});
      await seConnecter(tester);
      expect(titre(TextesOuverture.titreStock), findsNothing);
      expect(titre(TextesOuverture.titreOperations), findsOneWidget);
    });

    cas('le lien de pied quitte la séquence pour l’écran du module', (
      tester,
    ) async {
      final c = await clientDebiteur();
      await sejourEnCours(c);
      await articleSousSeuil();
      await monter(tester);
      await seConnecter(tester);
      await tester.tap(cle('ouverture-lien-stock'));
      await tester.pumpAndSettle();
      expect(find.text('page /stocks'), findsOneWidget);
      expect(cle('ouverture-modale-2'), findsNothing);
    });
  });

  group('Les blocs', () {
    cas('départ dépassé : pastille rouge ; créance de 40 jours : pastille '
        'orange, 50 000 FCFA, jamais relancé', (tester) async {
      final c = await clientDebiteur();
      await sejourEnCours(c);
      await monter(tester);
      await seConnecter(tester);

      expect(titre(TextesOuverture.blocDepartsTitre), findsOneWidget);
      expect(
        find.text('Départ prévu le 22/10/2026 — check-out non effectué'),
        findsOneWidget,
      );
      Color pastille(String k) =>
          (tester.widget<Container>(cle(k)).decoration! as BoxDecoration)
              .color!;
      expect(
        pastille(
          'ouverture-pastille-sejour:${(await db.select(db.sejoursLocal).get()).single.id}',
        ),
        isNot(equals(MesuresCouleurs.creances)),
        reason: 'départ dépassé = rouge, pas la couleur du bloc',
      );
      expect(
        find.textContaining('50 000 FCFA restant dus · 40 j d’ancienneté'),
        findsOneWidget,
      );
      expect(find.textContaining('jamais relancé'), findsOneWidget);
    });

    cas('plus de dix lignes : dix visibles, le compteur dit le total, '
        '« … et 2 autre(s). »', (tester) async {
      final lignes = [
        for (var i = 0; i < 12; i++)
          LigneStockOuverture(
            articleId: 'a$i',
            libelle: 'Article $i',
            detail: 'Stock 0 kg — seuil d’alerte 1',
            critique: i.isEven,
          ),
      ];
      await monter(tester);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: conteneur,
          child: MaterialApp(
            theme: AppTheme.clair,
            home: Scaffold(
              body: ModaleEtapeOuverture(
                etape: EtapeStock(lignes),
                rang: 1,
                total: 1,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: cle('ouverture-compteur-stock'),
                matching: find.byType(Text),
              ),
            )
            .data,
        '12',
      );
      expect(find.text('Article 9'), findsOneWidget);
      expect(find.text('Article 10'), findsNothing);
      expect(find.text('… et 2 autre(s).'), findsOneWidget);
    });
  });

  group('Check-out inline', () {
    cas('écrit le départ, l’unité passe en NETTOYAGE, la ligne reste estompée '
        'avec « Fait »', (tester) async {
      final c = await clientDebiteur();
      await sejourEnCours(c);
      await monter(tester);
      await seConnecter(tester);

      final sejour = (await db.select(db.sejoursLocal).get()).single;
      await tester.tap(cle('ouverture-action-checkout:${sejour.id}'));
      await tester.pumpAndSettle();

      final apres = (await db.select(db.sejoursLocal).get()).single;
      expect(apres.dateCheckoutReel, isNotNull);
      expect(
        (await db.select(db.unitesHebergementLocal).getSingle()).statut,
        'nettoyage',
      );
      expect(
        (await db.select(db.reservationsLocal).getSingle()).statut,
        'terminee',
      );
      expect(cle('ouverture-etiquette-fait'), findsOneWidget);
      expect(cle('ouverture-action-checkout:${sejour.id}'), findsNothing);
      expect(cle('ouverture-erreur'), findsNothing);
      final ligne = tester.widget<Opacity>(
        cle('ouverture-ligne-sejour:${sejour.id}'),
      );
      expect(ligne.opacity, 0.45);
    });

    cas('le séjour a été clos ailleurs entre-temps : la phrase du service, '
        'DATE comprise, dans la bande rouge', (tester) async {
      final c = await clientDebiteur();
      await sejourEnCours(c);
      await monter(tester);
      await seConnecter(tester);
      final sejour = (await db.select(db.sejoursLocal).get()).single;
      await SejourDao(db).checkout('r1');

      await tester.tap(cle('ouverture-action-checkout:${sejour.id}'));
      await tester.pumpAndSettle();

      final message = tester
          .widget<Text>(
            find.descendant(
              of: cle('ouverture-erreur'),
              matching: find.byType(Text),
            ),
          )
          .data!;
      expect(
        message,
        matches(
          RegExp(
            r'^Le départ a déjà été enregistré le \d{2}/\d{2}/\d{4} \d{2}:\d{2}\.$',
          ),
        ),
      );
      expect(cle('ouverture-etiquette-fait'), findsNothing);
    });

    cas('sans le niveau C sur M1 : la phrase du serveur, rien d’écrit', (
      tester,
    ) async {
      final c = await clientDebiteur();
      await sejourEnCours(c);
      await monter(tester, droits: const {'M1': 'L', 'M3': 'C', 'M6': 'C'});
      await seConnecter(tester);
      final sejour = (await db.select(db.sejoursLocal).get()).single;

      await tester.tap(cle('ouverture-action-checkout:${sejour.id}'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: cle('ouverture-erreur'),
          matching: find.text(TextesOuverture.droitManquant),
        ),
        findsOneWidget,
      );
      expect(
        (await db.select(db.sejoursLocal).get()).single.dateCheckoutReel,
        isNull,
      );
    });

    cas('un séjour introuvable : « Ce séjour n’existe plus »', (tester) async {
      await expectLater(
        SejourDao(db).checkoutDuSejour('zzz'),
        throwsA(
          predicate((e) => '$e'.contains(TextesOuverture.sejourIntrouvable)),
        ),
      );
    });
  });

  group('Relance tracée', () {
    cas('le canal choisi, le reste dû RÉEL, le commentaire fixe : écrit, '
        'enfilé, ligne « Tracée »', (tester) async {
      final c = await clientDebiteur();
      await monter(tester);
      await seConnecter(tester);

      await tester.tap(cle('ouverture-canal-$c'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('WhatsApp').last);
      await tester.pumpAndSettle();
      await tester.tap(cle('ouverture-action-relancer:$c'));
      await tester.pumpAndSettle();

      final r = (await db.select(db.relancesClientsLocal).get()).single;
      expect(r.clientId, c);
      expect(r.canal, 'whatsapp');
      expect(r.montantReclameCentimes, 5000000);
      expect(r.commentaire, TextesOuverture.relanceCommentaire);
      expect(r.creePar, startsWith('compta-'));
      expect(cle('ouverture-etiquette-tracee'), findsOneWidget);
      expect(cle('ouverture-action-relancer:$c'), findsNothing);
    });

    cas('relancé il y a moins de 14 jours : listé SANS action, « relance '
        'récente »', (tester) async {
      final c = await clientDebiteur();
      await db
          .into(db.relancesClientsLocal)
          .insert(
            RelancesClientsLocalCompanion.insert(
              id: 'rl-1',
              clientId: c,
              dateRelance: '2026-10-24',
              canal: 'telephone',
              montantReclameCentimes: 100,
            ),
          );
      await monter(tester);
      await seConnecter(tester);

      expect(cle('ouverture-action-relancer:$c'), findsNothing);
      expect(cle('ouverture-etiquette-recente'), findsOneWidget);
      expect(find.textContaining('relancé le 24/10/2026'), findsOneWidget);
    });

    cas('sans le niveau C sur M3 : la phrase du serveur, aucune relance', (
      tester,
    ) async {
      final c = await clientDebiteur();
      await monter(tester, droits: const {'M1': 'C', 'M3': 'L', 'M6': 'C'});
      await seConnecter(tester);
      await tester.tap(cle('ouverture-action-relancer:$c'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: cle('ouverture-erreur'),
          matching: find.text(TextesOuverture.droitManquant),
        ),
        findsOneWidget,
      );
      expect(await db.select(db.relancesClientsLocal).get(), isEmpty);
    });

    cas('la créance a été relancée entre-temps : « pas relançable pour le '
        'moment », rien d’écrit', (tester) async {
      final c = await clientDebiteur();
      await monter(tester);
      await seConnecter(tester);
      await db
          .into(db.relancesClientsLocal)
          .insert(
            RelancesClientsLocalCompanion.insert(
              id: 'rl-2',
              clientId: c,
              dateRelance: '2026-10-26',
              canal: 'telephone',
              montantReclameCentimes: 100,
            ),
          );
      await tester.tap(cle('ouverture-action-relancer:$c'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: cle('ouverture-erreur'),
          matching: find.text(TextesOuverture.relanceIndisponible),
        ),
        findsOneWidget,
      );
      expect((await db.select(db.relancesClientsLocal).get()), hasLength(1));
    });
  });

  group('Le poste fait le lien entre la connexion et les modales', () {
    test(
      'SessionNotifier.connecter pose le drapeau ; restaurer ne le pose pas',
      () {
        final source = File('lib/core/di/providers.dart').readAsStringSync();
        final connecter = source.substring(
          source.indexOf('Future<void> connecter('),
          source.indexOf('Future<void> deconnecter('),
        );
        expect(connecter, contains('ouvertureEnAttenteProvider.notifier'));
        expect(connecter, contains('.poser()'));
        final restaurer = source.substring(
          source.indexOf('Future<void> restaurer('),
          source.indexOf('/// Ouvre la session'),
        );
        expect(restaurer, isNot(contains('ouvertureEnAttenteProvider')));
      },
    );

    test('la coquille monte l’hôte des modales', () {
      expect(
        File('lib/core/router/coquille_application.dart').readAsStringSync(),
        contains('HoteModalesOuverture()'),
      );
    });
  });
}

/// Les couleurs de bloc employées par la comparaison de pastille.
abstract final class MesuresCouleurs {
  static const Color creances = Color(0xFFED6C02);
}
