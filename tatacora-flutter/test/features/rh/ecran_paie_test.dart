import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/fichiers/selecteur_fichiers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/rbac/regle_archivage.dart';
import 'package:tatacora_flutter/core/theme/app_colors.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/achats/domain/messages_achats.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_dao.dart';
import 'package:tatacora_flutter/features/parametres/domain/options_systeme.dart';
import 'package:tatacora_flutter/features/restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import 'package:tatacora_flutter/features/restaurant/presentation/widgets/tableau_restaurant.dart';
import 'package:tatacora_flutter/features/rh/data/employe_dao.dart';
import 'package:tatacora_flutter/features/rh/data/paie_dao.dart';
import 'package:tatacora_flutter/features/rh/domain/entities/employe.dart';
import 'package:tatacora_flutter/features/rh/domain/entities/periode_paie.dart';
import 'package:tatacora_flutter/features/rh/domain/services/bulletin_paie_service.dart';
import 'package:tatacora_flutter/features/rh/impression/bulletin_paie_a4.dart';
import 'package:tatacora_flutter/features/rh/impression/etat_paie.dart';
import 'package:tatacora_flutter/features/rh/presentation/ecran_paie.dart';
import 'package:tatacora_flutter/features/rh/presentation/providers_rh.dart';

import '../../support/selecteur_essai.dart';

/// L'écran Personnel & Paie, monté sur une **vraie base locale**.
///
/// ⚠ **Ce fichier ne compile pas tant que les quatre tables de
/// `core/database/tables/rh_tables.dart` ne sont pas déclarées au
/// `@DriftDatabase` d'`app_database.dart` et le code régénéré**
/// (`dart run build_runner build --delete-conflicting-outputs`). C'est
/// délibéré : l'enregistrement des tables appartient à la session qui tient
/// `app_database.dart`, et le nombre de tables y est figé par
/// `app_database_test.dart` pour qu'on se demande, à chaque ajout, si la table
/// a sa place dans la fenêtre hors ligne.
///
/// ## Ce que ces cas vérifient
///
/// Les **libellés du maître**, onglet par onglet — c'est le contrat de la
/// directive de conformité — et surtout que les deux refus de PA-53 sont
/// **visibles à l'écran**, pas seulement corrects dans le domaine. Un calcul
/// qui refuse pendant qu'un écran affiche un chiffre unique serait le pire des
/// deux mondes.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late EmployeDao employes;
  late PaieDao paie;

  DateTime maintenant() => DateTime(2026, 9, 14, 10);

  setUp(() async {
    db = AppDatabase.enMemoire();
    employes = EmployeDao(db, maintenant: maintenant);
    paie = PaieDao(db, maintenant: maintenant);

    await employes.installerServices();
    await paie.installerReferentielConfirme();
  });

  tearDown(() => db.close());

  Future<Employe> semerUnSalarie({
    String nom = 'KORA',
    String prenom = 'Jean-Baptiste',
    int salaire = 150000,
    String? numeroCnss = 'BJ-CNSS-0088412',
  }) async {
    final services = await employes.services();

    return employes.creer(
      nom: nom,
      prenom: prenom,
      poste: 'Réceptionniste',
      serviceId: services.first.id,
      dateEmbauche: DateTime(2023, 3, 15),
      salaireBase: salaire,
      numeroCnss: numeroCnss,
      typeContrat: TypeContrat.cdi,
    );
  }

  /// La période de TOUS les cas : septembre 2026, celle de [maintenant].
  ///
  /// ⚠ Le fournisseur de période prend le mois de l'HORLOGE RÉELLE
  /// (`PeriodePaie.deLaDate(DateTime.now())`), alors que les DAO ci-dessus
  /// reçoivent une horloge fixe. Sans cette ligne, l'écran vivait à la date du
  /// jour et le cas des déclarations attendait « 10/10/2026 » en dur : vrai en
  /// septembre 2026, faux dès octobre (l'échéance du VPS est le 10 du mois
  /// SUIVANT la période). Le test choisit maintenant sa période, comme un
  /// utilisateur qui la choisit dans le sélecteur.
  const periodeDeTest = '2026-09';

  Future<void> monter(
    WidgetTester tester, {
    String niveauM13 = 'C',
    String role = 'Administrateur',
    AppDatabase? base,
    List<Override> surcharges = const [],
    bool fixerPeriode = true,
  }) async {
    tester.view
      ..physicalSize = const Size(1600, 1400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final droits = GardeAcces({'M13': niveauM13});
    final session = Session(
      utilisateurId: 'u-essai',
      login: 'essai',
      nom: 'essai',
      role: role,
      droits: droits,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(base ?? db),
          droitsProvider.overrideWithValue(droits),
          sessionProvider.overrideWithBuild((ref, notifier) => session),
          ...surcharges,
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranPaie()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    if (!fixerPeriode) return;

    ProviderScope.containerOf(
      tester.element(find.byType(EcranPaie)),
    ).read(periodePaieProvider.notifier).definir(periodeDeTest);
    await tester.pumpAndSettle();
  }

  /// Amène un bouton à l'écran, le touche, attend la fin des animations : le
  /// tableau DÉFILE horizontalement (`overflow-x-auto`).
  Future<void> toucher(WidgetTester tester, Key cle) async {
    final cible = find.byKey(cle);
    await tester.ensureVisible(cible);
    await tester.pumpAndSettle();
    await tester.tap(cible);
    await tester.pumpAndSettle();
  }

  Future<void> ouvrirOnglet(WidgetTester tester, String nom) async {
    await tester.tap(find.byKey(Key('paie-onglet-$nom')));
    await tester.pumpAndSettle();
  }

  /// Le tableau du personnel DÉFILE horizontalement — `overflow-x-auto` du
  /// maître, qui laisse défiler plutôt que comprimer : un montant comprimé
  /// serait tronqué, donc faux. À 1600 px, la colonne d'actions est hors du
  /// cadre, et un `tap` direct y échouait sur un bouton pourtant présent. On
  /// l'amène à l'écran, exactement comme le fait l'utilisateur — élargir la
  /// fenêtre d'essai aurait masqué le défilement au lieu de l'éprouver.
  Future<void> ouvrirEtablissement(
    WidgetTester tester,
    String employeId,
  ) async {
    final bouton = find.byKey(Key('paie-etablir-$employeId'));
    await tester.ensureVisible(bouton);
    await tester.pumpAndSettle();
    await tester.tap(bouton);
    await tester.pumpAndSettle();
  }

  /* ================================================================== */
  group("L'en-tête et les bandeaux du maître", () {
    testWidgets('le titre et les cinq onglets sont rendus', (tester) async {
      await monter(tester);

      expect(find.byKey(const Key('paie-titre')), findsOneWidget);
      expect(find.text('Personnel & Paie'), findsOneWidget);

      for (final libelle in const [
        'Personnel',
        'Bulletins de paie',
        'Livre de paie',
        'Déclarations',
        'Barèmes & taux',
      ]) {
        expect(find.text(libelle), findsWidgets, reason: 'onglet « $libelle »');
      }
    });

    testWidgets(
      'le bandeau des risques professionnels est affiché sur les CINQ '
      'onglets',
      (tester) async {
        await monter(tester);

        // Une fourchette sans son explication se lirait comme une imprécision
        // d'affichage : le bandeau ne doit disparaître sur aucun onglet.
        for (final onglet in const [
          'personnel',
          'bulletins',
          'livre',
          'declarations',
          'bareme',
        ]) {
          await ouvrirOnglet(tester, onglet);
          expect(
            find.byKey(const Key('paie-bandeau-rp')),
            findsOneWidget,
            reason: 'onglet $onglet',
          );
        }
      },
    );

    testWidgets(
      'le bandeau « taux non paramétrés » est ABSENT quand le référentiel '
      'est installé',
      (tester) async {
        // Il doit rester une branche réelle, pas un décor permanent : c'est
        // l'installation du référentiel qui le fait disparaître.
        await monter(tester);
        expect(find.byKey(const Key('paie-bandeau-referentiel')), findsNothing);
      },
    );
  });

  /* ================================================================== */
  group('Onglet Personnel — les colonnes et le coût en fourchette', () {
    testWidgets('les sept colonnes du maître sont rendues', (tester) async {
      await semerUnSalarie();
      await monter(tester);

      // ⚠ Les en-têtes se cherchent DANS le tableau, pas dans l'écran entier.
      // « COÛT EMPLOYEUR » y paraît deux fois, légitimement : la colonne du
      // tableau (`ColonneTableau`, mise en capitales au rendu) et le titre de
      // la carte de synthèse (`titre.toUpperCase()`). Chercher la phrase dans
      // tout l'écran trouvait les deux et faisait échouer un écran juste —
      // rendre la phrase unique aurait masqué l'une des deux.
      for (final colonne in const [
        'MATRICULE',
        'EMPLOYÉ',
        'CONTRAT',
        'EMBAUCHE',
        'N° CNSS',
        'SALAIRE DE BASE',
        'COÛT EMPLOYEUR',
      ]) {
        expect(
          find.descendant(
            of: find.byType(TableauRestaurant).first,
            matching: find.text(colonne),
          ),
          findsOneWidget,
          reason: colonne,
        );
      }
    });

    testWidgets(
      'le coût employeur est une FOURCHETTE sur la ligne, jamais un chiffre',
      (tester) async {
        await semerUnSalarie();
        // ⚠ UN SECOND salarié, et ce n'est pas un ornement : le tableau se
        // termine par une ligne TOTAL qui porte, elle aussi, une fourchette.
        // Avec un seul salarié, la masse VAUT son coût — la phrase paraissait
        // deux fois à l'identique, et l'assertion ne pouvait plus distinguer
        // la ligne du total. Sur deux salaires différents, la ligne de KORA
        // est la seule à porter cette fourchette-là.
        await semerUnSalarie(
          nom: 'DOSSOU',
          prenom: 'Awa',
          salaire: 200000,
          numeroCnss: 'BJ-CNSS-0099001',
        );
        await monter(tester);

        // 150 000 + 29 100 confirmées + [1 500 ; 6 000] = [180 600 ; 185 100].
        // Cherchée DANS le tableau : la carte de synthèse porte la même
        // fourchette, légitimement (voir le cas des colonnes ci-dessus).
        expect(
          find.descendant(
            of: find.byType(TableauRestaurant).first,
            matching: find.text('180 600 FCFA — 185 100 FCFA'),
          ),
          findsOneWidget,
        );

        // Et surtout : aucune des deux bornes ne se présente seule comme « le »
        // coût employeur. C'est la forme que prendrait l'hypothèse refusée.
        expect(find.text('180 600 FCFA'), findsNothing);
        expect(find.text('185 100 FCFA'), findsNothing);
      },
    );

    testWidgets('un salarié sans numéro CNSS est signalé « absent »', (
      tester,
    ) async {
      await semerUnSalarie(numeroCnss: null);
      await monter(tester);

      // Son bulletin reste calculable : le badge signale la déclaration
      // impossible, il ne bloque rien.
      expect(find.text('absent'), findsOneWidget);
    });

    testWidgets(
      'sans droit d\'écriture, aucun bouton d\'action n\'est offert',
      (tester) async {
        await semerUnSalarie();
        await monter(tester, niveauM13: 'L');

        expect(find.byKey(const Key('paie-nouvel-employe')), findsNothing);
        expect(find.text('Établir'), findsNothing);
        expect(find.text('Modifier'), findsNothing);
      },
    );
  });

  /* ================================================================== */
  group('Onglet Barèmes & taux — le refus, rendu visible', () {
    testWidgets('le haut de barème est rendu comme un REFUS', (tester) async {
      await monter(tester);
      await ouvrirOnglet(tester, 'bareme');

      expect(find.byKey(const Key('paie-bareme-refus')), findsOneWidget);
      expect(find.text('non tranché'), findsOneWidget);
      expect(
        find.text(
          'Calcul refusé — deux sources divergent sur le haut de barème',
        ),
        findsOneWidget,
      );
    });

    testWidgets('la ligne des risques professionnels porte « non confirmé », '
        'et elle seule', (tester) async {
      await monter(tester);
      await ouvrirOnglet(tester, 'bareme');

      expect(find.text('1 % à 4 %'), findsOneWidget);
      expect(find.text('non confirmé'), findsOneWidget);
      // Les cinq autres taux sont, eux, confirmés.
      expect(find.text('confirmé'), findsNWidgets(5));
    });

    testWidgets('le simulateur chiffre CE QUI MANQUE', (tester) async {
      await monter(tester);
      await ouvrirOnglet(tester, 'bareme');

      expect(find.byKey(const Key('paie-simulateur-manque')), findsOneWidget);
      expect(find.text('Risques prof. à 1 %'), findsOneWidget);
      expect(find.text('Risques prof. à 4 %'), findsOneWidget);
      expect(find.text('Écart annuel'), findsOneWidget);
      // 4 500 x 12 — ce que le refus protège, sur un seul salarié.
      expect(find.text('54 000 FCFA'), findsOneWidget);
    });

    testWidgets('un brut au-delà du plafond affiche le refus, pas un montant', (
      tester,
    ) async {
      await monter(tester);
      await ouvrirOnglet(tester, 'bareme');

      await tester.enterText(
        find.byKey(const Key('paie-simulateur-brut')),
        '600000',
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('paie-simulateur-refus')), findsOneWidget);
      // Le refus est cherché DANS son encart : la même raison est aussi dite
      // par la ligne « au-delà de 500 000 FCFA » du barème, juste en dessous.
      expect(
        find.descendant(
          of: find.byKey(const Key('paie-simulateur-refus')),
          matching: find.textContaining(
            'deux sources divergent',
            findRichText: true,
          ),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('paie-simulateur-manque')), findsNothing);
    });
  });

  /* ================================================================== */
  group('Établir un bulletin', () {
    testWidgets("l'aperçu montre le net calculé et le coût en fourchette", (
      tester,
    ) async {
      final employe = await semerUnSalarie();
      await monter(tester);

      await ouvrirEtablissement(tester, employe.id);

      expect(find.text('Établir le bulletin'), findsWidgets);
      expect(find.text('136 140 FCFA'), findsOneWidget); // le net

      // Cherchée DANS la modale : la même fourchette paraît aussi sur la ligne
      // du salarié et au total de l'effectif, derrière le voile. Les trois
      // sont justes — c'est l'aperçu qu'on éprouve ici.
      expect(
        find.descendant(
          of: find.byType(CoquilleModaleRestaurant),
          matching: find.text('180 600 FCFA — 185 100 FCFA'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('le bulletin établi rejoint le registre et le livre', (
      tester,
    ) async {
      final employe = await semerUnSalarie();
      await monter(tester);

      await ouvrirEtablissement(tester, employe.id);
      await tester.tap(find.byKey(const Key('paie-etablissement-confirmer')));
      await tester.pumpAndSettle();

      // La modale de consultation s'ouvre sur le bulletin fraîchement établi.
      expect(find.byKey(const Key('paie-bulletin-entete')), findsOneWidget);
      // Le numéro porte l'ANNÉE de l'horloge du bureau : l'établissement par
      // l'écran se fait à la date du jour (les DAO ci-dessus ont une horloge
      // fixe, pas celui que l'écran construit). Écrire 2026 en dur cassait le
      // cas au 1er janvier.
      expect(
        find.textContaining('BUL-${DateTime.now().year}-00001'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('paie-bulletin-fermer')));
      await tester.pumpAndSettle();

      await ouvrirOnglet(tester, 'livre');
      expect(find.text('NET À PAYER AUX SALARIÉS'), findsOneWidget);
      expect(find.text('COÛT TOTAL EMPLOYEUR'), findsOneWidget);
      // Même au livre, le coût total est une fourchette.
      expect(find.text('180 600 FCFA — 185 100 FCFA'), findsOneWidget);
    });

    testWidgets(
      'un salarié hors barème voit le REFUS dans la modale ; le bouton reste '
      'actif comme dans la vue, et son clic rend le refus du service sans '
      'établir aucun bulletin',
      (tester) async {
        final employe = await semerUnSalarie(salaire: 600000);
        await monter(tester);

        await ouvrirEtablissement(tester, employe.id);

        expect(
          find.byKey(const Key('paie-etablissement-refus')),
          findsOneWidget,
        );

        // Le bouton n'est pas grisé (vue l.1005) : un bouton inerte ne dit pas
        // s'il est cassé. Son clic rend la raison exacte du service.
        final bouton = tester.widget<FilledButton>(
          find.byKey(const Key('paie-etablissement-confirmer')),
        );
        expect(bouton.onPressed, isNotNull);

        await tester.tap(find.byKey(const Key('paie-etablissement-confirmer')));
        await tester.pumpAndSettle();

        final erreur = tester.widget<Text>(
          find.byKey(const Key('paie-etablissement-erreur')),
        );
        expect(
          erreur.data,
          startsWith('Revenu imposable de 578 400 FCFA, au-delà du plafond'),
        );
        expect(erreur.data, contains('deux sources divergent'));

        // Et rien n'a été écrit : le refus n'est pas un enregistrement raté.
        expect(await paie.bulletinsDuMois(periodeDeTest), isEmpty);
      },
    );
  });

  /* ================================================================== */
  group('Onglet Livre — ce qui est refusé y est NOMMÉ', () {
    testWidgets(
      "l'écriture comptable proposée est un état vide qui dit pourquoi",
      (tester) async {
        await monter(tester);
        await ouvrirOnglet(tester, 'livre');

        expect(find.byKey(const Key('paie-ecriture-absente')), findsOneWidget);
        // Les colonnes du maître sont rendues, sans une seule ligne inventée.
        expect(find.text('COMPTE'), findsOneWidget);
        expect(find.text('LIBELLÉ'), findsOneWidget);
        expect(find.text('DÉBIT'), findsOneWidget);
        expect(find.text('CRÉDIT'), findsOneWidget);
      },
    );
  });

  /* ================================================================== */
  group('Onglet Déclarations', () {
    testWidgets('la CNSS est « Incomplet », le VPS et l\'ITS « arrêtés »', (
      tester,
    ) async {
      final employe = await semerUnSalarie();
      await monter(tester);

      await ouvrirEtablissement(tester, employe.id);
      await tester.tap(find.byKey(const Key('paie-etablissement-confirmer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('paie-bulletin-fermer')));
      await tester.pumpAndSettle();

      await ouvrirOnglet(tester, 'declarations');

      expect(find.text('CNSS'), findsOneWidget);
      expect(find.text('VPS'), findsOneWidget);
      expect(find.text('ITS'), findsOneWidget);

      // La CNSS est amputée des risques professionnels : la présenter comme
      // arrêtée ferait déclarer une cotisation minorée.
      expect(find.text('Incomplet'), findsOneWidget);
      expect(find.text('Montant arrêté'), findsNWidgets(2));

      // L'échéance du VPS est calculée : le 10 du mois suivant.
      expect(find.text('10/10/2026'), findsOneWidget);
    });
  });

  /* ================================================================== */
  group("L'en-tête, la bande d'indicateurs et les filtres", () {
    testWidgets(
      'un référentiel vide nomme les quatre clés et le coût employeur est un '
      'tiret, jamais un zéro',
      (tester) async {
        final vierge = AppDatabase.enMemoire();
        addTearDown(vierge.close);

        await monter(
          tester,
          base: vierge,
          surcharges: [
            // La base est montée SANS l'amorçage de l'écran : c'est l'état que
            // la vue a rendu (base fraîchement semée, aucun taux).
            referentielPaieProvider.overrideWith(
              (ref) => ref.watch(bulletinPaieServiceProvider).etatReferentiel(),
            ),
          ],
        );

        final bandeau = find.byKey(const Key('paie-bandeau-referentiel'));
        expect(bandeau, findsOneWidget);
        final texte = tester
            .widget<Text>(
              find.descendant(of: bandeau, matching: find.byType(Text)),
            )
            .textSpan!
            .toPlainText();
        expect(texte, startsWith('Les taux de paie ne sont pas paramétrés.'));
        expect(
          texte,
          contains(
            'taux_cnss_salarie, taux_cnss_pension_employeur, '
            'taux_cnss_prestations_familiales, taux_vps',
          ),
        );
        // La phrase de la vue, au mot : ce poste écrit bien ces taux depuis
        // Paramètres (`RegistreParametresLocal.clesDeLaPaie`), donc « un
        // Administrateur peut les renseigner depuis l’écran Paramètres » est
        // vrai ici. Elle remplace la phrase du poste du 09/10/2026.
        expect(
          texte,
          contains(
            'Ils sont posés par le référentiel de paie, et un Administrateur '
            'peut les renseigner depuis l’écran Paramètres. Aucune valeur '
            'n’est supposée à leur place',
          ),
        );
        expect(texte, isNot(contains('réinstalle')));

        // Valeur ET détail du coût employeur : deux tirets, aucun montant.
        expect(
          find.descendant(
            of: find.byKey(const Key('paie-kpi-cout')),
            matching: find.text('—'),
          ),
          findsNWidgets(2),
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('paie-kpi-cout')),
            matching: find.textContaining('FCFA'),
          ),
          findsNothing,
        );
      },
    );

    testWidgets('la bande des six indicateurs se replie et se déplie', (
      tester,
    ) async {
      await monter(tester);

      for (final cle in const [
        'effectif',
        'masse',
        'cout',
        'net',
        'vps',
        'manquants',
      ]) {
        expect(find.byKey(Key('paie-kpi-$cle')), findsOneWidget, reason: cle);
      }

      await tester.tap(find.byKey(const Key('paie-kpis-bascule')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('paie-kpi-net')), findsNothing);
      // L'en-tête de la bande, lui, reste : c'est lui qui rouvre.
      expect(find.text('Indicateurs de la paie'), findsOneWidget);

      await tester.tap(find.byKey(const Key('paie-kpis-bascule')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('paie-kpi-net')), findsOneWidget);
    });

    testWidgets(
      '« Bulletins manquants » est rouge tant qu\'un bulletin manque, vert '
      'quand tout est établi',
      (tester) async {
        final employe = await semerUnSalarie();
        await monter(tester);

        Color? couleurDe(String valeur) => tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('paie-kpi-manquants')),
                matching: find.text(valeur),
              ),
            )
            .style
            ?.color;

        expect(couleurDe('1'), PaletteMaitre.rouge600);

        await ouvrirEtablissement(tester, employe.id);
        await tester.tap(find.byKey(const Key('paie-etablissement-confirmer')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('paie-bulletin-fermer')));
        await tester.pumpAndSettle();

        expect(couleurDe('0'), PaletteMaitre.emeraude600);
      },
    );

    testWidgets('un contrat à durée déterminée dit sa fin, sous le contrat', (
      tester,
    ) async {
      final services = await employes.services();
      await employes.creer(
        nom: 'DOSSOU',
        prenom: 'Awa',
        poste: 'Serveuse',
        serviceId: services.first.id,
        dateEmbauche: DateTime(2026, 6, 1),
        dateFinContrat: DateTime(2026, 12, 31),
        salaireBase: 90000,
        typeContrat: TypeContrat.cdd,
      );
      await monter(tester);

      expect(find.text('CDD'), findsOneWidget);
      expect(find.text('jusqu’au 31/12/2026'), findsOneWidget);
    });

    testWidgets('« Tous » montre un salarié parti, que « Actifs » cache — et '
        'une ligne partie n\'offre ni case ni bouton « Archiver »', (
      tester,
    ) async {
      final actif = await semerUnSalarie();
      final parti = await semerUnSalarie(
        nom: 'DOSSOU',
        prenom: 'Awa',
        numeroCnss: 'BJ-CNSS-0099001',
      );
      await employes.archiver(parti.id);
      await monter(tester);

      expect(find.byKey(Key('paie-employe-${actif.id}')), findsOneWidget);
      expect(find.byKey(Key('paie-employe-${parti.id}')), findsNothing);

      await tester.tap(find.byKey(const Key('paie-filtre-statut')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tous').last);
      await tester.pumpAndSettle();

      expect(find.byKey(Key('paie-employe-${parti.id}')), findsOneWidget);
      expect(find.byKey(Key('paie-archiver-${actif.id}')), findsOneWidget);
      expect(find.byKey(Key('paie-archiver-${parti.id}')), findsNothing);
      expect(find.byKey(Key('paie-case-${actif.id}')), findsOneWidget);
      expect(find.byKey(Key('paie-case-${parti.id}')), findsNothing);
    });
  });

  /* ================================================================== */
  group("L'archivage — « Supprimer » veut dire archiver", () {
    /// La bascule `activation_suppression` de Paramètres, telle que la lit la
    /// règle UNIQUE (`regle_archivage.dart`).
    Future<void> poserBascule(String? valeur) => ParametresDao(
      db,
      maintenant: maintenant,
    ).ecrire({OptionsSysteme.cleSuppression: valeur}, auteurId: null);

    testWidgets(
      'la règle du web : administrateur et super_admin voient la case et le '
      'bouton « Archiver » SANS la bascule ; tout autre rôle en écriture '
      'seulement quand la bascule est OUVERTE ; en lecture, jamais',
      (tester) async {
        final employe = await semerUnSalarie();

        for (final cas in const [
          ('Administrateur', 'C', 'false', true),
          ('super_admin', 'C', 'false', true),
          ('Super admin', 'C', 'false', true),
          ('Comptable', 'C', 'false', false),
          ('Gerant', 'C', 'false', false),
          // Bascule ouverte : tout rôle en écriture archive (D272 levée).
          ('Comptable', 'C', 'true', true),
          ('Gerant', 'C', 'true', true),
          // Un administrateur en lecture seule n'écrit pas : le niveau passe
          // avant le rôle, bascule ouverte ou non.
          ('Administrateur', 'L', 'false', false),
          ('Comptable', 'L', 'true', false),
        ]) {
          await poserBascule(cas.$3);
          await monter(tester, role: cas.$1, niveauM13: cas.$2);

          final raison = '${cas.$1} en ${cas.$2}, bascule ${cas.$3}';
          expect(
            find.byKey(Key('paie-archiver-${employe.id}')),
            cas.$4 ? findsOneWidget : findsNothing,
            reason: raison,
          );
          expect(
            find.byKey(const Key('paie-case-tout')),
            cas.$4 ? findsOneWidget : findsNothing,
            reason: raison,
          );

          await tester.pumpWidget(const SizedBox());
        }
      },
    );

    testWidgets(
      'la bascule se REFERME entre l\'ouverture et le clic : rien n\'est '
      'archivé, la phrase du serveur est dite (la règle est relue à chaque '
      'geste, le rôle est celui de la session)',
      (tester) async {
        final employe = await semerUnSalarie();
        await poserBascule('true');
        await monter(tester, role: 'Comptable');

        await toucher(tester, Key('paie-archiver-${employe.id}'));
        expect(find.text('Archiver cet employé ?'), findsOneWidget);

        await poserBascule('false');
        await tester.tap(find.byKey(const Key('paie-archivage-confirmer')));
        await tester.pumpAndSettle();

        expect((await employes.parId(employe.id))!.statut, StatutEmploye.actif);
        expect(
          tester
              .widget<Text>(find.byKey(const Key('paie-archivage-bilan')))
              .data,
          MessagesAchats.refusBascule,
        );
      },
    );

    testWidgets(
      'la bascule est fermée quand on clique « Archiver » (ligne restée à '
      'l\'écran) : la confirmation ne s\'ouvre pas, la phrase est dite',
      (tester) async {
        final employe = await semerUnSalarie();
        await poserBascule('true');
        await monter(tester, role: 'Comptable');
        await poserBascule('false');

        await toucher(tester, Key('paie-archiver-${employe.id}'));

        expect(find.text('Archiver cet employé ?'), findsNothing);
        expect(
          find.descendant(
            of: find.byKey(const Key('paie-archivage-refuse')),
            matching: find.text(MessagesAchats.refusBascule),
          ),
          findsOneWidget,
        );
        expect((await employes.parId(employe.id))!.statut, StatutEmploye.actif);
      },
    );

    testWidgets(
      'un comptable, bascule ouverte, archive réellement (le DAO enfile '
      'l\'archivage dans sa transaction)',
      (tester) async {
        final employe = await semerUnSalarie();
        await poserBascule('true');
        await monter(tester, role: 'Comptable');

        await toucher(tester, Key('paie-archiver-${employe.id}'));
        await tester.tap(find.byKey(const Key('paie-archivage-confirmer')));
        await tester.pumpAndSettle();

        expect((await employes.parId(employe.id))!.statut, StatutEmploye.parti);
        expect(
          tester
              .widget<Text>(find.byKey(const Key('paie-archivage-bilan')))
              .data,
          '1 employé archivé.',
        );
      },
    );

    testWidgets(
      'archiver une ligne sans bulletin : la modale NOMME le salarié et '
      'avertit, la confirmation passe le statut à « parti »',
      (tester) async {
        final employe = await semerUnSalarie();
        await monter(tester);

        await toucher(tester, Key('paie-archiver-${employe.id}'));

        expect(find.text('Archiver cet employé ?'), findsOneWidget);
        expect(
          find.text(
            '« Supprimer » veut dire archiver : le statut passe à « parti », '
            "le salarié n'est pas effacé, sa fiche et ses bulletins restent "
            'lisibles.',
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(CoquilleModaleRestaurant),
            matching: find.text('KORA Jean-Baptiste'),
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(const Key('paie-archivage-sans-bulletin')),
              )
              .data,
          "KORA Jean-Baptiste n'a pas de bulletin sur septembre 2026 : une "
          "fois parti, la génération de bulletins l'ignorera. Établissez "
          "d'abord son solde de tout compte s'il est dû.",
        );
        expect(
          find.text(
            "Réversible : la fiche de l'employé permet de repasser son statut "
            'à « actif ».',
          ),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('paie-archivage-confirmer')));
        await tester.pumpAndSettle();

        expect((await employes.parId(employe.id))!.statut, StatutEmploye.parti);
        expect(
          tester
              .widget<Text>(find.byKey(const Key('paie-archivage-bilan')))
              .data,
          '1 employé archivé.',
        );
        // Sous le filtre « Actifs », la ligne a quitté la liste : elle n'est
        // pas supprimée, elle est partie.
        expect(find.byKey(Key('paie-employe-${employe.id}')), findsNothing);
      },
    );

    testWidgets(
      'un salarié DÉJÀ pourvu d\'un bulletin ne déclenche pas l\'avertissement',
      (tester) async {
        final employe = await semerUnSalarie();
        await BulletinPaieService(
          paie,
          employes,
        ).etablirBulletin(employe, periodeDeTest);
        await monter(tester);

        await toucher(tester, Key('paie-archiver-${employe.id}'));

        expect(find.text('Archiver cet employé ?'), findsOneWidget);
        expect(
          find.byKey(const Key('paie-archivage-sans-bulletin')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'la sélection n\'archive que les lignes AFFICHÉES : cocher tout puis '
      'filtrer réduit le lot',
      (tester) async {
        final kora = await semerUnSalarie();
        final dossou = await semerUnSalarie(
          nom: 'DOSSOU',
          prenom: 'Awa',
          numeroCnss: 'BJ-CNSS-0099001',
        );
        await monter(tester);

        // Rien de coché : aucun bouton rouge permanent.
        expect(find.textContaining('Archiver la sélection'), findsNothing);

        await toucher(tester, const Key('paie-case-tout'));
        expect(find.text('Archiver la sélection (2)'), findsOneWidget);

        // La recherche ne retient plus que KORA : le lot suit l'écran.
        await tester.enterText(find.byKey(const Key('paie-recherche')), 'KORA');
        await tester.pumpAndSettle();
        expect(find.text('Archiver la sélection (1)'), findsOneWidget);

        await toucher(tester, const Key('paie-archiver-selection'));
        expect(find.text('Archiver cet employé ?'), findsOneWidget);

        await tester.tap(find.byKey(const Key('paie-archivage-confirmer')));
        await tester.pumpAndSettle();

        expect((await employes.parId(kora.id))!.statut, StatutEmploye.parti);
        // DOSSOU était coché mais masqué : il n'est PAS archivé.
        expect((await employes.parId(dossou.id))!.statut, StatutEmploye.actif);
      },
    );

    testWidgets('un lot de deux : titre, avertissement au pluriel, bilan', (
      tester,
    ) async {
      final kora = await semerUnSalarie();
      final dossou = await semerUnSalarie(
        nom: 'DOSSOU',
        prenom: 'Awa',
        numeroCnss: 'BJ-CNSS-0099001',
      );
      await monter(tester);

      await toucher(tester, const Key('paie-case-tout'));
      await toucher(tester, const Key('paie-archiver-selection'));

      expect(find.text('Archiver ces 2 employés ?'), findsOneWidget);
      // DOSSOU précède KORA : le registre est ordonné par nom.
      expect(
        tester
            .widget<Text>(find.byKey(const Key('paie-archivage-sans-bulletin')))
            .data,
        "DOSSOU Awa, KORA Jean-Baptiste n'ont pas de bulletin sur septembre "
        '2026 : une fois partis, la génération de bulletins les ignorera. '
        "Établissez d'abord leurs soldes de tout compte s'ils sont dus.",
      );
      expect(find.text('Archiver le lot'), findsOneWidget);

      await tester.tap(find.byKey(const Key('paie-archivage-confirmer')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('paie-archivage-bilan'))).data,
        '2 employés archivés.',
      );
      expect((await employes.parId(kora.id))!.statut, StatutEmploye.parti);
      expect((await employes.parId(dossou.id))!.statut, StatutEmploye.parti);
    });
  });

  /* ================================================================== */
  group('Exporter — ce qui est affiché, et rien d\'autre', () {
    late List<EtatPaie> ecrits;

    Override capture() => exporterPaieProvider.overrideWithValue((etat) async {
      ecrits.add(etat);
      return 'C:/essai/paie.csv';
    });

    setUp(() => ecrits = []);

    Future<void> exporter(WidgetTester tester, {bool pdf = false}) async {
      await tester.tap(find.byKey(const Key('paie-exporter')));
      await tester.pumpAndSettle();
      // D434 : le PDF est présélectionné partout ; le tableur se choisit.
      if (!pdf) {
        await tester.tap(find.byKey(const Key('export-format-excel')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('export-generer')));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'le personnel exporté est celui du FILTRE : deux lignes sur trois, et '
      'la portée le dit',
      (tester) async {
        final services = await employes.services();
        Future<void> creer(String nom, String prenom, String cnss) =>
            employes.creer(
              nom: nom,
              prenom: prenom,
              poste: 'Réceptionniste',
              serviceId: services.first.id,
              dateEmbauche: DateTime(2023, 3, 15),
              salaireBase: 150000,
              numeroCnss: cnss,
              typeContrat: TypeContrat.cdi,
            );
        await creer('KORA', 'Jean-Baptiste', 'BJ-CNSS-0088412');
        await creer('KORA', 'Awa', 'BJ-CNSS-0088413');
        await creer('DOSSOU', 'Marc', 'BJ-CNSS-0099001');
        await monter(tester, surcharges: [capture()]);

        await tester.enterText(find.byKey(const Key('paie-recherche')), 'KORA');
        await tester.pumpAndSettle();
        await exporter(tester);

        expect(ecrits, hasLength(1));
        final etat = ecrits.single;
        expect(etat.titreOnglet, 'Personnel');
        expect(etat.entetes, [
          'Matricule',
          'Employé',
          'Poste',
          'Service',
          'Contrat',
          'Embauche',
          'N° CNSS',
          'Salaire de base',
        ]);
        // Deux lignes, jamais trois : DOSSOU est masqué par la recherche.
        expect(etat.lignes, hasLength(2));
        // L'ordre entre deux homonymes de nom tient à l'identifiant tiré au
        // hasard : seul l'ENSEMBLE est une assertion.
        expect(
          etat.lignes.map((l) => l[1]),
          unorderedEquals(['KORA Awa', 'KORA Jean-Baptiste']),
        );
        expect(
          etat.portee,
          'Onglet : Personnel · Période : septembre 2026 · Statut : Actifs · '
          'Recherche : KORA',
        );
        // Le fichier DIT sa portée : un document qui ne la dit pas se lit
        // comme s'il portait tout le personnel.
        final csv = etat.csv();
        expect(csv, startsWith('\u{FEFF}Personnel;${etat.portee}'));
        expect(csv, contains('150000'));
        expect(csv, isNot(contains('DOSSOU')));

        expect(
          tester.widget<Text>(find.byKey(const Key('paie-export-fait'))).data,
          'Export enregistré : paie.csv',
        );
      },
    );

    testWidgets(
      'les bulletins exportés portent la part patronale CONFIRMÉE, jamais un '
      'total de charge patronale',
      (tester) async {
        final kora = await semerUnSalarie();
        final dossou = await semerUnSalarie(
          nom: 'DOSSOU',
          prenom: 'Awa',
          salaire: 200000,
          numeroCnss: 'BJ-CNSS-0099001',
        );
        final service = BulletinPaieService(paie, employes);
        await service.etablirBulletin(kora, periodeDeTest);
        await service.etablirBulletin(dossou, periodeDeTest);
        await monter(tester, surcharges: [capture()]);
        await ouvrirOnglet(tester, 'bulletins');

        await exporter(tester);

        final etat = ecrits.single;
        expect(etat.titreOnglet, 'Bulletins de paie');
        expect(etat.entetes.last, 'Charges patronales');
        expect(etat.lignes, hasLength(2));
        // 19,4 % du brut : 29 100 sur 150 000, 38 800 sur 200 000 — la part
        // confirmée, que la colonne « * » du tableau annonce comme telle.
        expect(etat.lignes.map((l) => l.last), ['38800', '29100']);
        expect(
          etat.portee,
          'Onglet : Bulletins de paie · Période : septembre 2026',
        );
      },
    );

    testWidgets(
      'le livre exporte son coût total en FOURCHETTE, et les déclarations '
      'leur état',
      (tester) async {
        final employe = await semerUnSalarie();
        await BulletinPaieService(
          paie,
          employes,
        ).etablirBulletin(employe, periodeDeTest);
        await monter(tester, surcharges: [capture()]);

        await ouvrirOnglet(tester, 'livre');
        await exporter(tester);
        final livre = ecrits.last;
        expect(livre.entetes, ['Rubrique', 'Montant']);
        expect(livre.lignes, hasLength(11));
        expect(livre.lignes.last, ['COÛT TOTAL EMPLOYEUR', '180600 — 185100']);
        expect(
          livre.lignes.firstWhere(
            (l) => l[0] == 'CNSS — risques professionnels (1 % à 4 %)',
          )[1],
          '1500 — 6000',
        );

        await ouvrirOnglet(tester, 'declarations');
        await exporter(tester);
        final decl = ecrits.last;
        expect(decl.lignes, hasLength(3));
        expect(decl.lignes.map((l) => l.last), [
          'Incomplet',
          'Montant arrêté',
          'Montant arrêté',
        ]);
        expect(decl.lignes[1][3], '10/10/2026');
      },
    );

    testWidgets(
      'une liste vide se REFUSE : aucun fichier, et le message le dit',
      (tester) async {
        await semerUnSalarie();
        await monter(tester, surcharges: [capture()]);

        await tester.enterText(
          find.byKey(const Key('paie-recherche')),
          'INTROUVABLE',
        );
        await tester.pumpAndSettle();
        await exporter(tester);

        expect(ecrits, isEmpty);
        expect(
          tester.widget<Text>(find.byKey(const Key('paie-export-vide'))).data,
          'Aucune ligne à exporter : la liste affichée est vide.',
        );
      },
    );

    testWidgets(
      'le choix « PDF » est offert comme dans la vue, et PRODUIT : l\'état A4 '
      'enregistré en .pdf, le toast le dit',
      (tester) async {
        await semerUnSalarie();
        // La fenêtre « Enregistrer sous » remplacée : le VRAI
        // `exporterPaiePdfProvider` est emprunté jusqu'à elle.
        final selecteur = SelecteurEssai();
        await monter(tester, surcharges: [capture(), ...selecteur.surcharges]);

        await tester.tap(find.byKey(const Key('paie-exporter')));
        await tester.pumpAndSettle();
        // Plus aucune aide n'annonce le PDF refusé (14/10/2026).
        expect(find.byKey(const Key('export-aide')), findsNothing);
        await tester.tap(find.byKey(const Key('export-annuler')));
        await tester.pumpAndSettle();
        expect(selecteur.ecrits, isEmpty, reason: '« Annuler » n\'écrit rien');

        await exporter(tester, pdf: true);

        expect(ecrits, isEmpty, reason: 'le PDF ne passe pas par le tableur');
        expect(find.byKey(const Key('paie-export-pdf-absent')), findsNothing);
        final pdf = selecteur.ecrits.single;
        expect(pdf.type, TypeFichierEnregistre.pdf);
        expect(pdf.nom, endsWith('.pdf'));
        expect(pdf.estUnPdf, isTrue);
        expect(
          tester.widget<Text>(find.byKey(const Key('paie-export-fait'))).data,
          'Export enregistré : ${pdf.nom}',
        );
      },
    );

    testWidgets(
      'exporter est une LECTURE : offert à un rôle en lecture seule',
      (tester) async {
        await semerUnSalarie();
        await monter(
          tester,
          niveauM13: 'L',
          role: 'Comptable',
          surcharges: [capture()],
        );

        await exporter(tester);

        expect(ecrits, hasLength(1));
      },
    );

    test('le document : BOM, séparateur protégé, mentions de portée', () {
      const etat = EtatPaie(
        cleOnglet: 'livre',
        titreOnglet: 'Livre de paie',
        entetes: ['Rubrique', 'Montant'],
        lignes: [
          ['Coût; total', '180600 — 185100'],
          ['Net', '136140'],
        ],
        portee: 'Onglet : Livre de paie',
      );

      final csv = etat.csv();
      expect(csv.codeUnitAt(0), 0xFEFF);
      expect(csv, contains('Rubrique;Montant'));
      // Un point-virgule DANS une valeur casserait la colonne.
      expect(csv, contains('Coût, total;180600 — 185100'));
      expect(csv, contains('Net;136140'));
      for (final mention in EtatPaie.mentions) {
        expect(csv, contains(mention.replaceAll(';', ',')));
      }
      expect(etat.prefixeFichier, 'paie_livre');
      expect(etat.vide, isFalse);
    });
  });

  /* ================================================================== */
  group('Le bulletin en consultation', () {
    testWidgets('« Imprimer » envoie le papier A4 à l\'impression (action '
        'injectable), « PDF » l\'enregistre en bulletin_<numéro>.pdf', (
      tester,
    ) async {
      final employe = await semerUnSalarie();
      final imprimes = <BulletinPaieA4>[];
      final selecteur = SelecteurEssai();
      await monter(
        tester,
        surcharges: [
          imprimerBulletinProvider.overrideWithValue((b) async {
            imprimes.add(b);
          }),
          ...selecteur.surcharges,
        ],
      );
      await ouvrirEtablissement(tester, employe.id);
      await tester.tap(find.byKey(const Key('paie-etablissement-confirmer')));
      await tester.pumpAndSettle();

      // Plus aucune phrase d'absence : le document existe.
      expect(
        find.byKey(const Key('paie-bulletin-impression-absente')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('paie-bulletin-imprimer')));
      await tester.pumpAndSettle();
      expect(imprimes, hasLength(1));
      expect(imprimes.single.bulletin.employe.id, employe.id);
      expect(imprimes.single.periodeLongue, 'septembre 2026');
      expect(imprimes.single.auteur, 'essai');
      expect(
        selecteur.ecrits,
        isEmpty,
        reason: '« Imprimer » n\'écrit aucun fichier',
      );

      await tester.tap(find.byKey(const Key('paie-bulletin-pdf')));
      await tester.pumpAndSettle();
      final pdf = selecteur.ecrits.single;
      expect(pdf.type, TypeFichierEnregistre.pdf);
      expect(pdf.estUnPdf, isTrue);
      expect(pdf.nom, startsWith('bulletin_BUL-2026-'));
      expect(pdf.nom, endsWith('.pdf'));
      expect(
        tester
            .widget<Text>(find.byKey(const Key('paie-bulletin-pdf-enregistre')))
            .data,
        'Export enregistré : ${pdf.nom}',
      );
    });

    testWidgets(
      'un rôle en LECTURE imprime et télécharge son bulletin (lecture, comme '
      '`exporterPdf`)',
      (tester) async {
        final employe = await semerUnSalarie();
        await BulletinPaieService(
          paie,
          employes,
        ).etablirBulletin(employe, periodeDeTest);
        final selecteur = SelecteurEssai();
        await monter(
          tester,
          niveauM13: 'L',
          role: 'Comptable',
          surcharges: selecteur.surcharges,
        );
        await toucher(tester, Key('paie-voir-bulletin-${employe.id}'));
        await tester.tap(find.byKey(const Key('paie-bulletin-pdf')));
        await tester.pumpAndSettle();
        expect(selecteur.ecrits, hasLength(1));
      },
    );

    testWidgets(
      'le document porte l\'identité, le salarié, les montants calculés et '
      'les risques professionnels en fourchette',
      (tester) async {
        final employe = await semerUnSalarie();
        // Établi par le service à horloge fixe (14/09/2026) : la date de
        // l'encart « Établi le » est ainsi connue, quel que soit le jour.
        final bulletin = await BulletinPaieService(
          paie,
          employes,
        ).etablirBulletin(employe, periodeDeTest);
        await monter(tester);
        await toucher(tester, Key('paie-voir-bulletin-${employe.id}'));
        expect(bulletin.etabliLe, DateTime(2026, 9, 14, 10));

        final dialogue = find.byType(CoquilleModaleRestaurant);
        Finder dans(String texte) =>
            find.descendant(of: dialogue, matching: find.text(texte));

        expect(dans('TATACORA AFRIQUE — Gîte Chez Noël'), findsOneWidget);
        expect(dans('Natitingou, Bénin'), findsOneWidget);
        expect(dans('septembre 2026'), findsOneWidget);
        expect(dans('Matricule ${employe.matricule}'), findsOneWidget);
        expect(dans('N° CNSS BJ-CNSS-0088412'), findsOneWidget);
        expect(dans('Établi le 14/09/2026'), findsOneWidget);
        expect(dans('NET À PAYER'), findsOneWidget);
        // 150 000 − 5 400 de CNSS − 8 460 d'ITS.
        expect(dans('136 140 FCFA'), findsOneWidget);
        expect(dans('1 500 FCFA — 6 000 FCFA'), findsOneWidget);
        expect(dans('180 600 FCFA — 185 100 FCFA'), findsOneWidget);
        expect(dans('29 100 FCFA'), findsOneWidget);
        // L'en-tête des cinq colonnes du tableau, en capitales comme la vue.
        for (final colonne in const [
          'DÉSIGNATION',
          'BASE',
          'TAUX',
          'GAIN',
          'RETENUE',
        ]) {
          expect(dans(colonne), findsOneWidget, reason: colonne);
        }
      },
    );

    testWidgets(
      'fermer ne ferme QUE la modale : l\'écran reste, et le même bulletin se '
      'rouvre',
      (tester) async {
        final employe = await semerUnSalarie();
        await monter(tester);
        await ouvrirEtablissement(tester, employe.id);
        await tester.tap(find.byKey(const Key('paie-etablissement-confirmer')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('paie-bulletin-fermer')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('paie-bulletin-entete')), findsNothing);
        expect(find.byKey(const Key('paie-titre')), findsOneWidget);

        // La ligne propose maintenant « Bulletin », et rouvre le même.
        await toucher(tester, Key('paie-voir-bulletin-${employe.id}'));
        expect(find.byKey(const Key('paie-bulletin-entete')), findsOneWidget);
        expect(
          find.textContaining('BUL-${DateTime.now().year}-00001'),
          findsOneWidget,
        );
      },
    );
  });

  /* ================================================================== */
  group("Les indicateurs d'argent — valeurs exactes sur données connues", () {
    testWidgets(
      'masse, net, VPS et coût employeur (valeur ET borne haute) d\'un salarié '
      'à 150 000 FCFA',
      (tester) async {
        final employe = await semerUnSalarie();
        await BulletinPaieService(
          paie,
          employes,
        ).etablirBulletin(employe, periodeDeTest);
        await monter(tester);

        Finder dans(String kpi, String texte) => find.descendant(
          of: find.byKey(Key('paie-kpi-$kpi')),
          matching: find.text(texte),
        );

        // Masse : le seul salaire de base. Net : 150 000 − 5 400 − 8 460.
        // VPS : 4 % du brut. Coût : 150 000 + 29 100 confirmés + [1 500 ; 6 000].
        expect(dans('masse', '150 000 FCFA'), findsOneWidget);
        expect(dans('net', '136 140 FCFA'), findsOneWidget);
        expect(dans('net', '1 bulletin(s)'), findsOneWidget);
        expect(dans('vps', '6 000 FCFA'), findsOneWidget);
        expect(dans('cout', '180 600 FCFA'), findsOneWidget);
        expect(dans('cout', 'à 185 100 FCFA'), findsOneWidget);
      },
    );
  });

  /* ================================================================== */
  group(
    'Un salarié archivé : ses bulletins restent, et le geste se défait',
    () {
      testWidgets('ses bulletins restent affichés dans le registre', (
        tester,
      ) async {
        final employe = await semerUnSalarie();
        final bulletin = await BulletinPaieService(
          paie,
          employes,
        ).etablirBulletin(employe, periodeDeTest);
        await employes.archiver(employe.id);
        await monter(tester);

        // Il a quitté l'effectif « Actifs »…
        expect(find.byKey(Key('paie-employe-${employe.id}')), findsNothing);

        // … mais son bulletin est toujours au registre, avec son net.
        await ouvrirOnglet(tester, 'bulletins');
        expect(find.byKey(Key('paie-bulletin-${bulletin.id}')), findsOneWidget);
        expect(find.text('KORA Jean-Baptiste'), findsOneWidget);
        expect(find.text('136 140 FCFA'), findsWidgets);
      });

      testWidgets(
        'la fiche permet de repasser le statut à « actif » : la réversibilité '
        'annoncée par la modale est réelle',
        (tester) async {
          final employe = await semerUnSalarie();
          await employes.archiver(employe.id);
          await monter(tester);

          await tester.tap(find.byKey(const Key('paie-filtre-statut')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Tous').last);
          await tester.pumpAndSettle();

          await toucher(tester, Key('paie-modifier-${employe.id}'));
          await tester.tap(find.byKey(const Key('paie-champ-statut')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('actif').last);
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('paie-fiche-enregistrer')));
          await tester.pumpAndSettle();

          expect(
            (await employes.parId(employe.id))!.statut,
            StatutEmploye.actif,
          );
          // Et il revient dans l'effectif « Actifs » (le filtre est « Tous »
          // ici : la ligne y offre de nouveau « Archiver »).
          expect(
            find.byKey(Key('paie-archiver-${employe.id}')),
            findsOneWidget,
          );
        },
      );
    },
  );

  /* ================================================================== */
  group("La période par défaut n'est pas fixée par le test", () {
    testWidgets('l\'écran s\'ouvre sur le MOIS COURANT de l\'horloge', (
      tester,
    ) async {
      await monter(tester, fixerPeriode: false);

      expect(
        find.text(
          'Effectif — ${PeriodePaie.deLaDate(DateTime.now()).libelleLong}',
        ),
        findsOneWidget,
      );
    });
  });

  /* ================================================================== */
  group(
    'Les gardes relisent le SERVEUR, elles ne recopient pas ses listes',
    () {
      test(
        'les rôles qui archivent sont ceux de `User::ROLES_ADMINISTRATION`',
        () {
          final source = File('../tatacora-api/app/Models/User.php');
          expect(
            source.existsSync(),
            isTrue,
            reason: 'Source introuvable : échec.',
          );

          final texte = source.readAsStringSync();
          const ancre = 'ROLES_ADMINISTRATION = [';
          final debut = texte.indexOf(ancre);
          expect(debut, greaterThanOrEqualTo(0), reason: 'Constante disparue.');
          final fin = texte.indexOf(']', debut);
          final serveur = texte
              .substring(debut + ancre.length, fin)
              .split(',')
              .map((r) => r.trim().replaceAll("'", ''))
              .where((r) => r.isNotEmpty)
              .toSet();

          // Prouvée NON VIDE : un balayage vide serait vert à vide.
          expect(serveur, containsAll(['administrateur', 'super_admin']));
          // La Paie n'a plus de constante propre (D272 levée) : elle emploie
          // la règle UNIQUE du poste, relue ici contre le serveur.
          expect(rolesAdministration, serveur);
        },
      );

      test(
        'les en-têtes de l\'export sont ceux de `PaieExport::entetesDe()`',
        () {
          final export = File('../tatacora-api/app/Exports/PaieExport.php');
          final langue = File('../tatacora-api/lang/fr/rh_pwa.php');
          expect(export.existsSync() && langue.existsSync(), isTrue);

          final lang = <String, String>{};
          for (final ligne in langue.readAsStringSync().split('\n')) {
            final t = ligne.trim();
            final eq = t.indexOf("' => '");
            if (!t.startsWith("'") || eq < 0 || !t.endsWith("',")) continue;
            lang[t.substring(1, eq)] = t.substring(eq + 6, t.length - 2);
          }
          expect(
            lang['col_matricule'],
            'Matricule',
            reason: 'Lecture de la langue.',
          );

          final php = export.readAsStringSync();
          final corps = php.substring(php.indexOf('function entetesDe'));

          List<String> entetesDuServeur(String arme) {
            final debut = corps.indexOf(arme);
            expect(debut, greaterThanOrEqualTo(0), reason: arme);
            final fin = corps.indexOf('],', debut);
            final cles = <String>[];
            var curseur = corps.indexOf("__('rh_pwa.", debut);
            while (curseur >= 0 && curseur < fin) {
              final finCle = corps.indexOf("'", curseur + 11);
              cles.add(corps.substring(curseur + 11, finCle));
              curseur = corps.indexOf("__('rh_pwa.", finCle);
            }
            return [for (final c in cles) lang[c]!];
          }

          final attendu = {
            OngletPaie.personnel: entetesDuServeur('default => ['),
            OngletPaie.bulletins: entetesDuServeur("'bulletins' => ["),
            OngletPaie.livre: entetesDuServeur("'livre' => ["),
            OngletPaie.declarations: entetesDuServeur("'declarations' => ["),
            OngletPaie.bareme: entetesDuServeur("'bareme' => ["),
          };

          // Chaque liste est non vide, et la première est celle du personnel.
          for (final e in attendu.entries) {
            expect(e.value, isNotEmpty, reason: e.key.name);
          }
          expect(attendu[OngletPaie.personnel]!.first, 'Matricule');

          final conteneurTest = ProviderContainer(
            overrides: [baseLocaleProvider.overrideWithValue(db)],
          );
          addTearDown(conteneurTest.dispose);

          return Future(() async {
            for (final e in attendu.entries) {
              conteneurTest.read(ongletPaieProvider.notifier).definir(e.key);
              final etat = await conteneurTest.read(etatPaieProvider.future);
              expect(etat.entetes, e.value, reason: e.key.name);
            }
          });
        },
      );
    },
  );
}
