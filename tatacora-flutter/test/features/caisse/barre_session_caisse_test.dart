import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_colors.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/caisse/data/sessions_caisse_dao.dart';
import 'package:tatacora_flutter/features/caisse/domain/entities/session_caisse.dart';
import 'package:tatacora_flutter/features/caisse/presentation/providers_caisse.dart';
import 'package:tatacora_flutter/features/caisse/presentation/widgets/barre_session_caisse.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_repository_local.dart';
import 'package:tatacora_flutter/features/hebergement/presentation/providers_hebergement.dart';
import 'package:tatacora_flutter/features/pos/data/catalogue_dao.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/data/panier_repository_local.dart';
import 'package:tatacora_flutter/features/pos/presentation/ecran_pos_comptant.dart';
import 'package:tatacora_flutter/features/pos/presentation/providers_pos.dart';

import '../facturation/support/outils_encaissement.dart'
    show semerBoisson, vendreAuComptant;
import 'support/outils_caisse.dart';

/// La barre de session de caisse et ses deux modales, MONTÉES sur une vraie
/// base locale : ce que le caissier voit, tape et lit.
///
/// Chaque cas passe par le chemin de production — le bouton, la modale, le
/// fournisseur, le DAO, la base — et relit l'EFFET en base. Un cas qui
/// affirmerait un texte sans avoir écrit la ligne serait le toast vert sur une
/// caisse qui ne bouge pas.
void main() {
  late AppDatabase db;
  late DateTime horloge;

  setUp(() async {
    db = await baseCaisse();
    horloge = ouvertureDeReference;
  });

  tearDown(() => db.close());

  Session session() => Session(
    utilisateurId: ouvreurEssai,
    login: 'gerant',
    nom: 'Gérant',
    role: 'Gerant',
    droits: GardeAcces.depuisJson(const {'M5': 'C'}),
  );

  /// Monte [enfant] sous un Scaffold (le toast de succès est un `SnackBar`).
  Future<void> monter(
    WidgetTester tester, {
    Widget enfant = const BarreSessionCaisse(),
    GardeAcces? droits,
    bool avecPos = false,
    List<Override> surcharges = const [],
  }) async {
    tester.view
      ..physicalSize = const Size(1600, 1000)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          depotSessionsCaisseProvider.overrideWithValue(
            SessionsCaisseDao(db, maintenant: () => horloge),
          ),
          horlogeCaisseProvider.overrideWithValue(() => horloge),
          sessionProvider.overrideWithBuild((ref, notifier) => session()),
          if (avecPos) ...[
            depotPanierProvider.overrideWithValue(
              PanierRepositoryLocal(PanierDao(db)),
            ),
            catalogueProvider.overrideWithValue(CatalogueDao(db)),
            depotReservationProvider.overrideWithValue(
              ReservationRepositoryLocal(ReservationDao(db)),
            ),
          ],
          droitsProvider.overrideWithValue(
            droits ?? GardeAcces.depuisJson(const {'M5': 'C'}),
          ),
          ...surcharges,
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: Scaffold(body: Column(children: [enfant])),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> saisir(WidgetTester tester, String cle, String texte) async {
    await tester.enterText(find.byKey(Key(cle)), texte);
    await tester.pump();
  }

  Future<void> toucher(WidgetTester tester, String cle) async {
    await tester.ensureVisible(find.byKey(Key(cle)));
    await tester.tap(find.byKey(Key(cle)));
    await tester.pumpAndSettle();
  }

  Future<List<SessionCaisse>> sessions() =>
      daoCaisseSur(db, horloge: horloge).sessions();

  String texteDe(WidgetTester tester, String cle) =>
      tester.widget<Text>(find.byKey(Key(cle))).data!;

  group('caisse fermée', () {
    testWidgets('dit « Aucune caisse ouverte » et propose de l’ouvrir', (
      tester,
    ) async {
      await monter(tester);

      expect(find.text('Aucune caisse ouverte'), findsOneWidget);
      expect(find.text('Ouvrir la caisse'), findsOneWidget);
      // Aucun bouton de clôture sur une caisse fermée.
      expect(find.byKey(const Key('caisse-cloturer')), findsNothing);
    });

    testWidgets('dit, avec la phrase de la vue, qu’aucune vente n’est '
        'possible sans caisse — VRAI depuis le lot 5 (la clôture d’un panier '
        'au comptant refuse sans caisse `bar` ouverte, D221) — et ne '
        'synchronise rien', (tester) async {
      // Jusqu'au lot 5, la phrase était FAUSSE sur ce poste (le panier
      // s'encaissait sans session) et ce test la refusait. Le refus du DAO la
      // rend vraie : elle est rendue (`pos_pwa.comptant.caisse_aucune_aide`).
      await monter(tester);

      expect(
        find.text(
          "Aucune vente n'est possible tant que la caisse n'est pas ouverte.",
        ),
        findsOneWidget,
      );
      expect(find.textContaining('synchronisation'), findsNothing);
      expect(find.textContaining('vente(s)'), findsNothing);
    });

    testWidgets('« Ouvrir la caisse » ouvre la modale aux mots de la vue, '
        'champ VIDE', (tester) async {
      await monter(tester);
      await toucher(tester, 'caisse-ouvrir');

      expect(find.byKey(const Key('modale-ouverture-caisse')), findsOneWidget);
      expect(find.text('Ouvrir la caisse bar'), findsOneWidget);
      expect(find.text('Fond de caisse (FCFA)'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('caisse-fond-saisi')))
            .controller!
            .text,
        isEmpty,
        reason: 'un fond prérempli serait un montant inventé',
      );
      expect(await sessions(), isEmpty);
    });
  });

  group('ouvrir la caisse', () {
    testWidgets('un fond saisi OUVRE la caisse : la ligne est en base, la '
        'barre la lit', (tester) async {
      await monter(tester);
      await toucher(tester, 'caisse-ouvrir');
      await saisir(tester, 'caisse-fond-saisi', '25000');
      await toucher(tester, 'caisse-ouvrir-confirmer');

      // L'EFFET en base : la ligne, son auteur, son fond en centimes.
      final lues = await sessions();
      expect(lues, hasLength(1));
      expect(lues.single.point, PointDeVenteCaisse.bar);
      expect(lues.single.utilisateurOuvertureId, ouvreurEssai);
      expect(lues.single.fondCentimes, 2500000);
      expect(lues.single.estOuverte, isTrue);
      expect(lues.single.dateOuverture, ouvertureDeReference);

      // Le toast, puis la barre RELUE de la base.
      expect(find.text('Caisse bar ouverte.'), findsOneWidget);
      expect(find.byKey(const Key('modale-ouverture-caisse')), findsNothing);
      expect(texteDe(tester, 'caisse-ouverte'), 'Caisse bar ouverte');
      expect(texteDe(tester, 'caisse-depuis'), 'depuis 07:00');
      expect(texteDe(tester, 'caisse-duree'), '· 0 min');
      expect(texteDe(tester, 'caisse-fond'), 'Fond 25 000 FCFA');
      expect(find.text('Aucune caisse ouverte'), findsNothing);
      expect(find.byKey(const Key('caisse-ouvrir')), findsNothing);
    });

    testWidgets('un fond vide est refusé SOUS le champ, la modale reste, '
        'rien n’est écrit', (tester) async {
      await monter(tester);
      await toucher(tester, 'caisse-ouvrir');
      await toucher(tester, 'caisse-ouvrir-confirmer');

      expect(
        texteDe(tester, 'caisse-refus'),
        'Le champ fond caisse saisi est obligatoire.',
      );
      expect(find.byKey(const Key('modale-ouverture-caisse')), findsOneWidget);
      expect(await sessions(), isEmpty);
    });

    testWidgets('chaque refus de forme dit la phrase du serveur', (
      tester,
    ) async {
      await monter(tester);
      await toucher(tester, 'caisse-ouvrir');

      await saisir(tester, 'caisse-fond-saisi', 'abc');
      await toucher(tester, 'caisse-ouvrir-confirmer');
      expect(
        texteDe(tester, 'caisse-refus'),
        'Le champ fond caisse saisi doit être un nombre.',
      );

      await saisir(tester, 'caisse-fond-saisi', '-5');
      await toucher(tester, 'caisse-ouvrir-confirmer');
      expect(
        texteDe(tester, 'caisse-refus'),
        'Le champ fond caisse saisi doit etre au minimum de 0.',
      );
      expect(await sessions(), isEmpty);
    });

    testWidgets('une caisse déjà ouverte à ce point refuse la seconde '
        'ouverture', (tester) async {
      await monter(tester);
      await toucher(tester, 'caisse-ouvrir');
      // Une autre fenêtre du poste ouvre la caisse pendant que la modale est là.
      await daoCaisseSur(db, horloge: horloge).ouvrir(
        point: PointDeVenteCaisse.bar,
        fondSaisi: '10000',
        auteurId: ouvreurEssai,
        peutEcrire: true,
      );
      await saisir(tester, 'caisse-fond-saisi', '99999');
      await toucher(tester, 'caisse-ouvrir-confirmer');

      expect(
        texteDe(tester, 'caisse-refus'),
        'Une caisse est déjà ouverte à ce point de vente. '
        'Clôturez-la avant d\'en ouvrir une seconde.',
      );
      final lues = await sessions();
      expect(lues, hasLength(1), reason: 'la seconde n’a pas été écrite');
      expect(lues.single.fondCentimes, 1000000);
    });

    testWidgets('« Annuler » ferme la modale sans rien écrire', (tester) async {
      await monter(tester);
      await toucher(tester, 'caisse-ouvrir');
      await saisir(tester, 'caisse-fond-saisi', '5000');
      await toucher(tester, 'caisse-annuler');

      expect(find.byKey(const Key('modale-ouverture-caisse')), findsNothing);
      expect(await sessions(), isEmpty);
      expect(find.text('Aucune caisse ouverte'), findsOneWidget);
    });
  });

  group('clôturer la caisse', () {
    Future<void> ouvertureAvecFond(String fond) async {
      await daoCaisseSur(db, horloge: horloge).ouvrir(
        point: PointDeVenteCaisse.bar,
        fondSaisi: fond,
        auteurId: ouvreurEssai,
        peutEcrire: true,
      );
    }

    testWidgets('la modale rend le récapitulatif aux mots de la vue : fond, '
        'ESPÈCES DES VENTES de la session, théorique — et pré-remplit le champ '
        'compté du théorique', (tester) async {
      await ouvertureAvecFond('25000');
      // Trois bières en espèces (3 000), une vente en Mobile Money (5 000) : seules
      // les espèces remplissent un tiroir.
      await semerBoisson(db);
      await vendreAuComptant(db, quantite: 3);
      await vendreAuComptant(db, mode: 'mobile_money', quantite: 5);
      await monter(tester);
      await toucher(tester, 'caisse-cloturer');

      expect(find.text('Clôturer la caisse bar'), findsOneWidget);
      expect(find.text('Théorique — fond + ventes encaissées'), findsOneWidget);
      expect(find.text('Fond de caisse'), findsOneWidget);
      expect(texteDe(tester, 'cloture-recap-fond'), '25 000 FCFA');
      expect(find.text('Espèces encaissées'), findsOneWidget);
      expect(texteDe(tester, 'cloture-recap-especes'), '3 000 FCFA');
      expect(find.text('Théorique en caisse'), findsOneWidget);
      expect(texteDe(tester, 'cloture-recap-theorique'), '28 000 FCFA');
      expect(find.text('Montant réellement compté'), findsOneWidget);
      expect(
        find.text(
          'Seules les espèces sont dans le tiroir. Mobile Money, carte et '
          'notes de chambre en sont exclus.',
        ),
        findsOneWidget,
      );
      // Plus de phrase « aucune vente n'est rattachée » : elle serait fausse.
      expect(find.byKey(const Key('cloture-sans-source')), findsNothing);
      // `value="${theorique}"` de la vue : le champ naît du théorique.
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('caisse-constate-saisi')))
            .controller!
            .text,
        '28000.00',
      );
    });

    testWidgets('réserve R2 : une vente en espèces SANS session, clôturée '
        'depuis l’ouverture, est DITE dans la modale — jamais un théorique '
        'présenté comme un fait', (tester) async {
      await ouvertureAvecFond('25000');
      await semerBoisson(db);
      final avant = await vendreAuComptant(db, quantite: 2);
      await vendreAuComptant(db, quantite: 1);
      // La vente d'AVANT la v18 : elle ne porte pas sa session.
      await db.customStatement(
        'UPDATE paniers_local SET session_encaissement_id = NULL WHERE id = ?',
        [avant.id],
      );
      await monter(tester);
      await toucher(tester, 'caisse-cloturer');

      expect(
        find.byKey(const Key('cloture-avertissement-sans-session')),
        findsOneWidget,
      );
      expect(find.textContaining('rattachée à aucune session'), findsOneWidget);
      expect(find.textContaining('2 000 FCFA'), findsWidgets);
      // Le théorique reste celui de la formule (fond + espèces rattachées).
      expect(texteDe(tester, 'cloture-recap-especes'), '1 000 FCFA');
    });

    testWidgets('réserve R2 : sans vente orpheline, aucun avertissement '
        '(il ne doit pas s’afficher pour rien)', (tester) async {
      await ouvertureAvecFond('25000');
      await semerBoisson(db);
      await vendreAuComptant(db, quantite: 2);
      await monter(tester);
      await toucher(tester, 'caisse-cloturer');

      expect(
        find.byKey(const Key('cloture-avertissement-sans-session')),
        findsNothing,
      );
    });

    testWidgets('une caisse sans vente a pour théorique son fond — et c’est un '
        'ZÉRO vrai, pas un tiret', (tester) async {
      await ouvertureAvecFond('25000');
      await monter(tester);
      await toucher(tester, 'caisse-cloturer');

      expect(texteDe(tester, 'cloture-recap-especes'), '0 FCFA');
      expect(texteDe(tester, 'cloture-recap-theorique'), '25 000 FCFA');
    });

    testWidgets('une vente d’une AUTRE session n’entre pas dans ce théorique', (
      tester,
    ) async {
      await ouvertureAvecFond('25000');
      await semerBoisson(db);
      await vendreAuComptant(db, quantite: 2);
      // Cette session est close ; une autre s'ouvre.
      await daoCaisseSur(db, horloge: horloge).cloturer(
        point: PointDeVenteCaisse.bar,
        constateSaisi: '27000',
        peutEcrire: true,
        especesEncaisseesCentimes: 200000,
      );
      await daoCaisseSur(db, horloge: horloge).ouvrir(
        point: PointDeVenteCaisse.bar,
        fondSaisi: '10000',
        auteurId: ouvreurEssai,
        peutEcrire: true,
      );
      await monter(tester);
      await toucher(tester, 'caisse-cloturer');

      expect(texteDe(tester, 'cloture-recap-especes'), '0 FCFA');
      expect(texteDe(tester, 'cloture-recap-theorique'), '10 000 FCFA');
    });

    testWidgets('le pré-remplissage ne passe JAMAIS par-dessus une saisie '
        'commencée (les espèces se lisent APRÈS le premier rendu)', (
      tester,
    ) async {
      await ouvertureAvecFond('25000');
      final attente = Completer<int>();
      await monter(
        tester,
        surcharges: [
          especesDeLaSessionProvider.overrideWithValue(
            (session) => attente.future,
          ),
        ],
      );
      await toucher(tester, 'caisse-cloturer');

      // Les espèces ne sont pas là : des tirets, jamais des zéros, et le champ est
      // vide.
      expect(texteDe(tester, 'cloture-recap-especes'), '—');
      expect(texteDe(tester, 'cloture-recap-theorique'), '—');
      await saisir(tester, 'caisse-constate-saisi', '123');

      attente.complete(400000);
      await tester.pumpAndSettle();

      expect(texteDe(tester, 'cloture-recap-especes'), '4 000 FCFA');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('caisse-constate-saisi')))
            .controller!
            .text,
        '123',
        reason: 'la saisie du caissier est respectée',
      );
    });

    testWidgets('un montant compté CLÔT la caisse : dates, montants en base, '
        'théorique ET écart annoncés comme au serveur', (tester) async {
      await ouvertureAvecFond('25000');
      horloge = ouvertureDeReference.add(const Duration(hours: 9));
      await monter(tester);
      await toucher(tester, 'caisse-cloturer');
      await saisir(tester, 'caisse-constate-saisi', '24500');
      await toucher(tester, 'caisse-cloturer-confirmer');

      final s = (await sessions()).single;
      expect(s.estOuverte, isFalse);
      expect(s.dateCloture, horloge);
      expect(s.constateCentimes, 2450000);
      expect(s.theoriqueCentimes, 2500000, reason: 'fond + 0 espèce');
      expect(s.fondCentimes, 2500000, reason: 'le fond ne bouge pas');

      // 24 500 comptés pour 25 000 attendus.
      expect(
        find.text('Caisse bar clôturée — écart de -500 FCFA.'),
        findsOneWidget,
      );
      expect(find.textContaining('non calculé'), findsNothing);
      // La barre relit la base : plus de caisse ouverte.
      expect(find.text('Aucune caisse ouverte'), findsOneWidget);
      expect(find.byKey(const Key('caisse-cloturer')), findsNothing);
    });

    testWidgets('un montant compté refusé reste SOUS le champ, rien n’est '
        'écrit', (tester) async {
      await ouvertureAvecFond('25000');
      await monter(tester);
      await toucher(tester, 'caisse-cloturer');

      await saisir(tester, 'caisse-constate-saisi', 'abc');
      await toucher(tester, 'caisse-cloturer-confirmer');
      expect(
        texteDe(tester, 'caisse-refus'),
        'Le champ montant constate saisi doit être un nombre.',
      );

      await saisir(tester, 'caisse-constate-saisi', '');
      await toucher(tester, 'caisse-cloturer-confirmer');
      expect(
        texteDe(tester, 'caisse-refus'),
        'Le champ montant constate saisi est obligatoire.',
      );

      expect(find.byKey(const Key('modale-cloture-caisse')), findsOneWidget);
      expect((await sessions()).single.estOuverte, isTrue);
    });

    testWidgets('une caisse close entre l’ouverture de la modale et le clic '
        'est refusée aux mots du serveur', (tester) async {
      await ouvertureAvecFond('25000');
      await monter(tester);
      await toucher(tester, 'caisse-cloturer');
      // Une autre fenêtre du poste clôt la caisse entre-temps.
      await daoCaisseSur(db, horloge: horloge).cloturer(
        point: PointDeVenteCaisse.bar,
        constateSaisi: '25000',
        peutEcrire: true,
        especesEncaisseesCentimes: 0,
      );
      await saisir(tester, 'caisse-constate-saisi', '25000');
      await toucher(tester, 'caisse-cloturer-confirmer');

      expect(
        texteDe(tester, 'caisse-refus'),
        'Aucune caisse n\'est ouverte à ce point de vente. Ouvrez-la avant '
        'd\'encaisser : sans elle, la vente ne serait rattachée à aucun fond.',
      );
    });
  });

  group('la durée écoulée', () {
    Future<void> ouvertureAvecFond() async {
      await daoCaisseSur(db, horloge: ouvertureDeReference).ouvrir(
        point: PointDeVenteCaisse.bar,
        fondSaisi: '10000',
        auteurId: ouvreurEssai,
        peutEcrire: true,
      );
    }

    testWidgets('se met à jour toutes les 30 secondes, comme le setInterval '
        'de la vue', (tester) async {
      await ouvertureAvecFond();
      await monter(tester);
      expect(texteDe(tester, 'caisse-duree'), '· 0 min');

      horloge = ouvertureDeReference.add(const Duration(minutes: 12));
      // Rien ne bouge avant l'échéance du minuteur…
      await tester.pump(const Duration(seconds: 29));
      expect(texteDe(tester, 'caisse-duree'), '· 0 min');
      // …puis la barre relit l'horloge.
      await tester.pump(const Duration(seconds: 2));
      expect(texteDe(tester, 'caisse-duree'), '· 12 min');
    });

    testWidgets('passé 24 h, la durée passe en rouge et en gras : une clôture '
        'oubliée', (tester) async {
      await ouvertureAvecFond();
      horloge = ouvertureDeReference.add(const Duration(hours: 25, minutes: 5));
      await monter(tester);

      expect(texteDe(tester, 'caisse-duree'), '· 25h05');
      final style = tester
          .widget<Text>(find.byKey(const Key('caisse-duree')))
          .style!;
      expect(style.color, PaletteMaitre.rouge600);
      expect(style.fontWeight, FontWeight.w600);
    });

    testWidgets('à 24 h PILE, elle est déjà rouge (h >= 24, pas h > 24)', (
      tester,
    ) async {
      await ouvertureAvecFond();
      horloge = ouvertureDeReference.add(const Duration(hours: 24));
      await monter(tester);

      expect(texteDe(tester, 'caisse-duree'), '· 24h00');
      expect(
        tester.widget<Text>(find.byKey(const Key('caisse-duree'))).style!.color,
        PaletteMaitre.rouge600,
      );
    });

    testWidgets('sous 24 h, elle reste grise', (tester) async {
      await ouvertureAvecFond();
      horloge = ouvertureDeReference.add(
        const Duration(hours: 23, minutes: 59),
      );
      await monter(tester);

      expect(texteDe(tester, 'caisse-duree'), '· 23h59');
      expect(
        tester.widget<Text>(find.byKey(const Key('caisse-duree'))).style!.color,
        Ardoise.c400,
      );
    });

    testWidgets('le minuteur est annulé à la fermeture de l’écran', (
      tester,
    ) async {
      await ouvertureAvecFond();
      await monter(tester);
      // Démonter la barre : un minuteur resté vivant ferait échouer le test
      // ("A Timer is still pending even after the widget tree was disposed").
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 61));
    });
  });

  group('les droits', () {
    testWidgets('sans droit d’écriture sur M5, « Ouvrir la caisse » est '
        'désactivé et n’ouvre rien', (tester) async {
      await monter(tester, droits: GardeAcces.depuisJson(const {'M5': 'L'}));

      await tester.tap(find.byKey(const Key('caisse-ouvrir')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('modale-ouverture-caisse')), findsNothing);
      expect(await sessions(), isEmpty);
    });

    testWidgets('sans droit d’écriture sur M5, « Clôturer la caisse » est '
        'désactivé', (tester) async {
      await daoCaisseSur(db, horloge: horloge).ouvrir(
        point: PointDeVenteCaisse.bar,
        fondSaisi: '10000',
        auteurId: ouvreurEssai,
        peutEcrire: true,
      );
      await monter(tester, droits: GardeAcces.depuisJson(const {'M5': 'L'}));

      await tester.tap(find.byKey(const Key('caisse-cloturer')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('modale-cloture-caisse')), findsNothing);
      expect((await sessions()).single.estOuverte, isTrue);
    });
  });

  group('dans l’écran du point de vente comptant', () {
    testWidgets('la barre précède les panneaux, et ne casse pas le panier', (
      tester,
    ) async {
      await db
          .into(db.cartesBoissonLocal)
          .insert(
            CartesBoissonLocalCompanion.insert(
              id: 'bsn-33',
              articleId: 'art-bsn',
              libelle: 'Béninoise 33cl',
              categorie: 'locale',
              prixVente: 1000,
            ),
          );
      await monter(
        tester,
        enfant: const Expanded(child: EcranPosComptant()),
        avecPos: true,
      );
      // Le montage ci-dessus pose les deux dépôts du POS sur la même base.
      expect(find.byKey(const Key('barre-session-caisse')), findsOneWidget);
      final barre = tester.getRect(
        find.byKey(const Key('barre-session-caisse')),
      );
      final salle = tester.getRect(find.byKey(const Key('pos-choix-comptoir')));
      expect(
        barre.bottom,
        lessThanOrEqualTo(salle.top),
        reason: 'la barre est AU-DESSUS des panneaux, comme dans la vue',
      );
      // La barre fait toute la largeur de la page.
      expect(barre.width, 1600);
    });

    testWidgets('le panier s’ouvre sans session de caisse : c’est '
        'l’ENCAISSEMENT qui est conditionné, pas la prise de commande', (
      tester,
    ) async {
      // Comme le serveur : `ouvrirPourPoste` / `ajouterAuPanier` ne regardent
      // pas la caisse, seul le bouton « Encaisser » (désactivé, libellé « Ouvrez
      // la caisse pour encaisser ») et `encaissementReel` l'exigent. Depuis le
      // lot 5 (12/10/2026, D221 option a) l'encaissement est rattaché à la
      // session ; le test qui figeait « non conditionné ici » est remplacé.
      await monter(
        tester,
        enfant: const Expanded(child: EcranPosComptant()),
        avecPos: true,
      );

      expect(find.text('Aucune caisse ouverte'), findsOneWidget);
      final bouton = tester.widget<FilledButton>(
        find.ancestor(
          // Libellé de la consigne du PO (14/10/2026).
          of: find.text('Nouvelle vente au comptoir'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(bouton.onPressed, isNotNull);
    });
  });
}
