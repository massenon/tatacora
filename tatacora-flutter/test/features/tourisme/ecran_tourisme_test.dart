import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/fichiers/selecteur_fichiers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_colors.dart';
import 'package:tatacora_flutter/core/theme/app_spacing.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import 'package:tatacora_flutter/features/restaurant/presentation/widgets/coquille_restaurant.dart';
import 'package:tatacora_flutter/features/tourisme/data/tourisme_dao.dart';
import 'package:tatacora_flutter/features/tourisme/presentation/ecran_tourisme.dart';
import 'package:tatacora_flutter/features/tourisme/presentation/providers_tourisme.dart';
import 'package:tatacora_flutter/features/tourisme/presentation/widgets/barre_filtres_tourisme.dart';

import '../../support/selecteur_essai.dart';

/// Le rendu de l'écran **Tourisme** — vue Blade `pwa/tourisme/departs.blade.php`,
/// le maître depuis PA-182/PA-183.
///
/// ## Ces cas lisent l'ARBRE DE WIDGETS MONTÉ (Article 9.2)
///
/// Le comparateur Blade → Flutter lit le **code source** et ne distingue pas
/// une chaîne rendue d'une chaîne citée en commentaire — c'est écrit dans son
/// en-tête. Cet écran en porte beaucoup, précisément parce qu'il documente ce
/// qu'il refuse : les libellés qui comptent sont donc éprouvés ici, sur un
/// écran réellement construit.
void main() {
  late AppDatabase db;
  late TourismeDao dao;

  // Une date FIGÉE vieillirait : la fenêtre par défaut est « aujourd'hui …
  // +30 jours », et un départ du 12/10/2026 en sortirait le lendemain. Le cas
  // deviendrait rouge sans qu'une ligne de code ait changé.
  final demain = DateTime.now().add(const Duration(days: 1));
  final jour = DateTime(demain.year, demain.month, demain.day);

  setUp(() async {
    db = AppDatabase.enMemoire();
    dao = TourismeDao(db);

    await db
        .into(db.circuitsLocal)
        .insert(
          CircuitsLocalCompanion.insert(
            id: 'cir-1',
            nom: 'Cascades de Tanougou',
            theme: 'Nature',
            zone: 'Atacora',
            prix: 4500,
            capaciteMax: 12,
          ),
        );
    await db
        .into(db.guidesLocal)
        .insert(GuidesLocalCompanion.insert(id: 'gui-1', nom: 'ADJOVI Paul'));
    await db
        .into(db.clientsLocal)
        .insert(
          ClientsLocalCompanion.insert(
            id: 'cli-1',
            nom: 'KORA',
            prenom: const Value('Jean'),
            telephone: '+229 01 00 00 00 01',
            typeClient: 'particulier',
          ),
        );
  });

  tearDown(() => db.close());

  /// [droits] vaut `M9 = 'C'` par défaut — écriture permise.
  ///
  /// ⚠ Ce défaut est nécessaire depuis que l'écran masque réellement ses
  /// gestes d'écriture (14/09/2026). Avant, `monter` ne posait AUCUN droit et
  /// les boutons paraissaient quand même, faute de contrôle : cinq cas
  /// tapaient « + Prestation », « Guide » ou « Réserver » sans jamais avoir
  /// déclaré le droit de le faire. Ils l'ont toujours supposé ; ils le disent
  /// désormais. Le cas qui éprouve le masquage passe `'L'` explicitement.
  Future<void> monter(
    WidgetTester t, {
    Size taille = const Size(1600, 3000),
    GardeAcces? droits,
    List<Override> surcharges = const [],
  }) async {
    final acces = droits ?? GardeAcces(const {'M9': 'C'});
    t.view.physicalSize = taille;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    await t.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          droitsProvider.overrideWithValue(acces),
          ...surcharges,
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranTourisme()),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> ouvrirOnglet(WidgetTester t, String cle) async {
    await t.tap(find.byKey(Key('tourisme-onglet-$cle')));
    await t.pumpAndSettle();
  }

  Future<void> reserver(int participants) => dao.reserver(
    circuitId: 'cir-1',
    clientId: 'cli-1',
    guideId: 'gui-1',
    dateCircuit: jour,
    nbParticipants: participants,
  );

  /* ================================================================== */
  group('L\'en-tête de la vue', () {
    testWidgets('titre et sous-titre sont RENDUS, au mot', (t) async {
      await monter(t);

      // Le `<h1>` de la vue (l.92).
      expect(find.text('Tourisme'), findsOneWidget);
      // Le sous-titre (l.94) : il porte la règle de capacité en toutes lettres.
      expect(
        find.text(
          'Circuits, départs, guides et capacités. La capacité est contrôlée '
          'cumulée sur le départ — jamais réservation par réservation. Un '
          'départ ne peut pas exister sans guide.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('les deux champs de période sont rendus, en minuscules', (
      t,
    ) async {
      await monter(t);

      // Les étiquettes de la vue (l.98 et l.100) — EN MINUSCULES.
      expect(find.text('du'), findsOneWidget);
      expect(find.text('au'), findsOneWidget);
    });
  });

  /* ================================================================== */
  group('Les TROIS onglets — même ordre, même onglet actif par défaut', () {
    testWidgets('les trois libellés de la vue sont rendus', (t) async {
      await monter(t);

      // Vue l.170-172.
      expect(find.text('Départs planifiés'), findsWidgets);
      expect(find.text('Réservations'), findsWidgets);
      expect(find.text('Catalogue'), findsWidgets);
    });

    testWidgets('« Départs planifiés » est actif par défaut', (t) async {
      await reserver(5);
      await monter(t);

      // Le contenu des départs est à l'écran sans qu'on ait cliqué :
      // `TableauRestaurant` met les en-têtes en capitales, comme le `uppercase`
      // de la vue.
      expect(find.text('REMPLISSAGE'), findsOneWidget);
      expect(find.text('PRIX / PERS.'), findsOneWidget);
    });
  });

  /* ================================================================== */
  group('Les six indicateurs', () {
    testWidgets('les six libellés de la vue sont rendus, dans son ordre', (
      t,
    ) async {
      await monter(t);

      expect(find.text('DÉPARTS PLANIFIÉS'), findsOneWidget);
      expect(find.text('PLACES VENDUES'), findsOneWidget);
      expect(find.text('TAUX DE REMPLISSAGE'), findsOneWidget);
      // L'apostrophe DROITE de la vue.
      expect(find.text('CHIFFRE D\'AFFAIRES'), findsOneWidget);
      expect(find.text('RESTE À ENCAISSER'), findsOneWidget);
      expect(find.text('DURÉE INDÉTERMINÉE'), findsOneWidget);
    });

    testWidgets('« Reste à encaisser » porte « — », jamais « 0 FCFA »', (
      t,
    ) async {
      await reserver(5);
      await monter(t);

      // Aucune colonne d'acompte : le chiffre n'est pas calculable. Afficher
      // le montant entier le présenterait comme impayé.
      final carte = find.ancestor(
        of: find.text('RESTE À ENCAISSER'),
        matching: find.byKey(const Key('tourisme-kpi-reste')),
      );
      expect(carte, findsOneWidget);
      expect(
        find.descendant(of: carte, matching: find.text('—')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: carte, matching: find.text('Soldes clients')),
        findsOneWidget,
      );
    });

    testWidgets('« Durée indéterminée » affiche un VRAI compte', (t) async {
      await reserver(5);
      await monter(t);

      // ⚠ Ce cas exigeait « — » tant que `circuits_local` n'avait pas la
      // colonne. Elle existe depuis la v10 (14/09/2026), et le circuit semé
      // n'en porte aucune : le départ compte donc comme indéterminé.
      final carte = find.byKey(const Key('tourisme-kpi-duree'));
      expect(
        find.descendant(of: carte, matching: find.text('1')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: carte, matching: find.text('0')),
        findsNothing,
      );
    });

    testWidgets('les places vendues et le taux sont calculés', (t) async {
      await reserver(6);
      await monter(t);

      // 6 places sur 12 offertes.
      expect(find.text('6 / 12'), findsOneWidget);
      expect(find.text('50 %'), findsOneWidget);
    });
  });

  /* ================================================================== */
  group('L\'état d\'un départ, DÉDUIT et rendu', () {
    testWidgets('il reste des places : « N place(s) »', (t) async {
      await reserver(5);
      await monter(t);

      // Le libellé de la vue — « place(s) », y compris au singulier.
      expect(find.text('7 place(s)'), findsOneWidget);

      // ⚠ « 5/12 » est rendu DEUX fois, et les deux sont légitimes : la jauge
      // de la ligne, et la ligne TOTAL du tableau (vue l.342). L'assertion est
      // donc portée sur la jauge du départ, sinon elle mesurerait « l'un des
      // deux », sans dire lequel.
      expect(
        find.descendant(
          of: find.byKey(Key('tourisme-jauge-cir-1|${_iso(jour)}')),
          matching: find.text('5/12'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('tourisme-departs-total-places')),
        findsOneWidget,
      );
    });

    testWidgets('plus une place : « Complet »', (t) async {
      await reserver(12);
      await monter(t);

      expect(find.text('Complet'), findsOneWidget);
      // Et le bouton « Réserver » de la ligne DISPARAÎT : il ouvrirait une
      // modale pour se faire refuser.
      expect(find.text('Réserver'), findsNothing);
    });

    testWidgets('toutes les lignes annulées : « Annulé », sans actions', (
      t,
    ) async {
      await reserver(5);
      await dao.annulerDepart(circuitId: 'cir-1', date: jour);
      await monter(t);

      // Le filtre par défaut est « Planifiés » : le départ annulé n'est pas
      // listé. On bascule sur « Annulés » pour le voir.
      await t.tap(find.byKey(const Key('tourisme-filtre-statut')));
      await t.pumpAndSettle();
      await t.tap(find.text('Annulés').last);
      await t.pumpAndSettle();

      expect(find.text('Annulé'), findsOneWidget);
      expect(find.text('Guide'), findsNothing);
    });

    testWidgets('un départ vide affiche le message de la vue', (t) async {
      await monter(t);

      expect(
        find.text('Aucun départ ne correspond à ces critères.'),
        findsOneWidget,
      );
    });
  });

  /* ================================================================== */
  group('RG-13 — le refus de capacité cumulée est RENDU à l\'écran', () {
    testWidgets(
      'un troisième groupe de 5 sur 12 places est refusé, dans la modale',
      (t) async {
        // Deux groupes de 5 : il reste 2 places.
        await reserver(5);
        await reserver(5);
        await monter(t);

        // La modale s'ouvre depuis la ligne du départ : circuit, date et guide
        // sont alors imposés.
        // La colonne d'actions est la dernière des dix et défile
        // horizontalement : on l'amène à l'écran avant de la taper, comme le
        // fait l'utilisateur (voir le cas de la modale de guide).
        final bouton = find.byKey(Key('tourisme-reserver-cir-1|${_iso(jour)}'));
        await t.ensureVisible(bouton);
        await t.pumpAndSettle();
        await t.tap(bouton);
        await t.pumpAndSettle();

        // Le bloc de capacité dit ce que le DAO calcule — jamais une valeur
        // d'échappement.
        expect(find.byKey(const Key('tourisme-bloc-capacite')), findsOneWidget);
        expect(find.text('Capacité'), findsOneWidget);
        expect(find.text('Déjà vendues'), findsOneWidget);
        expect(find.text('Restantes'), findsOneWidget);

        await t.enterText(
          find.byKey(const Key('tourisme-resa-nb-personnes')),
          '5',
        );
        await t.tap(find.byKey(const Key('tourisme-resa-valider')));
        await t.pumpAndSettle();

        // Le refus du domaine est affiché TEL QUEL, et il nomme les trois
        // nombres : c'est le CUMUL qui bloque, pas cette réservation seule.
        expect(
          find.textContaining('Départ complet : 5 participants demandés'),
          findsOneWidget,
        );
        expect(
          find.textContaining('2 place(s) encore disponible(s)'),
          findsOneWidget,
        );

        // La saisie reste à l'écran pendant qu'on la corrige.
        expect(
          find.byKey(const Key('tourisme-modale-reservation')),
          findsOneWidget,
        );
      },
    );

    testWidgets('la note de cumul est rendue dans la modale, au mot', (
      t,
    ) async {
      await monter(t);

      await t.tap(find.byKey(const Key('tourisme-nouvelle-reservation')));
      await t.pumpAndSettle();

      expect(
        find.text(
          'Le contrôle porte sur le cumul des places vendues sur ce départ, '
          'pas sur cette seule réservation : trois groupes de 5 sur un circuit '
          'à 12 places sont refusés au troisième.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('l\'encadré de capacité de la vue est rendu', (t) async {
      await reserver(5);
      await monter(t);

      // ⚠ `EncadreRestaurant` compose titre et texte dans un SEUL `Text.rich` :
      // le libellé n'est la `data` d'aucun `Text`, et `find.text` ne le
      // trouverait jamais. On lit donc le widget monté, ce qui éprouve en plus
      // que c'est bien l'encadré de la vue qui est rendu, et pas un autre.
      final encadre = t.widget<EncadreRestaurant>(
        find.byKey(const Key('tourisme-encadre-capacite')),
      );

      expect(encadre.titre, 'La capacité vient du circuit, pas d\'une saisie.');
      expect(
        encadre.texte,
        contains('trois groupes de 5 sur un circuit à 12 places'),
      );
    });
  });

  /* ================================================================== */
  group('Le guide — « affecter » est une RÉaffectation', () {
    testWidgets('la modale porte les mots de la vue', (t) async {
      await reserver(5);
      await monter(t);

      // ⚠ La colonne d'actions est la DERNIÈRE des dix : sur une fenêtre de
      // 1600 px, elle tombe hors du champ visible du tableau, qui défile
      // horizontalement (`overflow-x-auto` de la vue). Un `tap()` direct vise
      // alors un point hors de l'arbre de rendu. On l'amène à l'écran d'abord,
      // exactement comme l'utilisateur fait défiler.
      final bouton = find.byKey(Key('tourisme-guide-cir-1|${_iso(jour)}'));
      await t.ensureVisible(bouton);
      await t.pumpAndSettle();
      await t.tap(bouton);
      await t.pumpAndSettle();

      // Le titre et la note de la vue, au mot.
      expect(find.text('Réaffecter le guide'), findsOneWidget);
      expect(find.text('Guide actuellement affecté :'), findsOneWidget);
      expect(find.text('ADJOVI Paul'), findsWidgets);
      // ⚠ L'étiquette d'un champ OBLIGATOIRE est un `Text.rich` qui porte
      // l'astérisque rouge : son texte brut est « Nouveau guide * », et
      // `find.text('Nouveau guide')` ne le trouve donc jamais. On éprouve le
      // widget d'étiquette lui-même — ce qui vérifie en plus que le champ est
      // bien marqué obligatoire, comme à la vue (l.761).
      final etiquette = t.widget<EtiquetteChampRestaurant>(
        find.byWidgetPredicate(
          (w) => w is EtiquetteChampRestaurant && w.texte == 'Nouveau guide',
        ),
      );
      expect(etiquette.obligatoire, isTrue);
      expect(
        find.text(
          'Il s\'agit d\'une réaffectation : un départ ne peut pas exister '
          'sans guide, celui-ci a donc forcément déjà le sien.',
        ),
        findsOneWidget,
      );
      expect(find.text('Réaffecter'), findsWidgets);
    });
  });

  /* ================================================================== */
  group('L\'onglet Réservations', () {
    testWidgets('les colonnes de la vue sont rendues, « Acompte » compris', (
      t,
    ) async {
      await reserver(4);
      await monter(t);
      await ouvrirOnglet(t, 'reservations');

      expect(find.text('CLIENT'), findsOneWidget);
      expect(find.text('PERS.'), findsOneWidget);
      expect(find.text('MONTANT'), findsOneWidget);
      // Les deux colonnes sans source gardent leur place.
      expect(find.text('ACOMPTE'), findsOneWidget);
      expect(find.text('RESTE DÛ'), findsOneWidget);
    });

    testWidgets('le montant est calculé : prix x participants', (t) async {
      await reserver(4);
      await monter(t);
      await ouvrirOnglet(t, 'reservations');

      // 4 x 4 500 = 18 000.
      expect(find.text('18 000 FCFA'), findsWidgets);
      expect(find.text('KORA Jean'), findsOneWidget);
    });
  });

  /* ================================================================== */
  group('L\'onglet Catalogue', () {
    testWidgets('les colonnes et le titre du cadre sont rendus', (t) async {
      await monter(t);
      await ouvrirOnglet(t, 'catalogue');

      expect(
        find.text('Catalogue — tarifs opposables au client'),
        findsOneWidget,
      );
      expect(find.text('PRESTATION'), findsOneWidget);
      expect(find.text('ZONE / THÈME'), findsOneWidget);
      expect(find.text('INDICATIF €'), findsOneWidget);
      expect(find.text('DÉPARTS PLANIFIÉS'), findsWidgets);
      // Le type est unique : aucun discriminant au schéma.
      expect(find.text('Circuit'), findsWidgets);
      expect(find.text('Atacora · Nature'), findsOneWidget);
    });

    testWidgets('« + Prestation » n\'apparaît QUE sur cet onglet', (t) async {
      await monter(t);

      // Vue l.214 : le bouton est conditionné à l'onglet Catalogue.
      expect(find.text('+ Prestation'), findsNothing);

      await ouvrirOnglet(t, 'catalogue');
      expect(find.text('+ Prestation'), findsOneWidget);
    });

    testWidgets('le champ « Durée » de la modale ENREGISTRE', (t) async {
      await monter(t);
      await ouvrirOnglet(t, 'catalogue');

      await t.tap(find.byKey(const Key('tourisme-nouvelle-prestation')));
      await t.pumpAndSettle();

      expect(find.text('Nouvelle prestation au catalogue'), findsOneWidget);

      // ⚠ On cherche l'ÉTIQUETTE, pas le mot « Durée » : il paraît aussi dans
      // le bloc « Ce que cet écran ne rend pas », derrière la modale. Et
      // l'étiquette est un `Text.rich` — libellé et astérisque en deux
      // `TextSpan` —, que `find.text` ne matche jamais. Chercher le texte
      // couplait ce cas à une prose d'écran sans rapport avec lui.
      //
      // La suite prouve les trois choses qui comptent : l'étiquette existe,
      // une seule fois, et elle n'est PAS marquée obligatoire —
      // `circuits.duree` est nullable au serveur, la vue n'en exige rien et
      // le DAO accepte le vide. Un astérisque rouge affirmerait une
      // contrainte qui n'existe nulle part.
      final etiquettes = t
          .widgetList<EtiquetteChampRestaurant>(
            find.byType(EtiquetteChampRestaurant),
          )
          .where((e) => e.texte == 'Durée');
      expect(etiquettes, hasLength(1));
      expect(etiquettes.single.obligatoire, isFalse);

      // ⚠ Ce cas exigeait un champ INERTE « avec sa raison », et c'était juste
      // tant que la colonne n'existait pas — une saisie aurait été acceptée
      // puis jetée en silence. La v10 (14/09/2026) l'a livrée : le champ doit
      // désormais être un vrai champ, et la mention d'impuissance disparaître.
      expect(
        find.byKey(const Key('tourisme-prestation-duree-inerte')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('tourisme-prestation-duree')),
        findsOneWidget,
      );
    });
  });

  /* ================================================================== */
  group('RBAC — le masquage est le SEUL niveau, et il doit tenir', () {
    // ⚠ Jusqu'au 14/09/2026, `features/tourisme/` ne portait AUCUN contrôle de
    // droits — zéro occurrence de `droitsProvider` dans tout le module —, alors
    // que la vue en pose cinq (`departs.blade.php` l.213, 326, 458, 568).
    //
    // Ce qui rend ces deux cas indispensables : le DAO est LOCAL PUR et ne
    // vérifie aucun droit. Il n'y a donc pas de second niveau derrière le
    // masquage. Si ces cas tombent, il n'y a plus de barrière du tout — un
    // profil en lecture crée une prestation, réserve, réaffecte un guide et
    // annule un départ déjà vendu.

    testWidgets('un rôle en LECTURE ne voit aucun geste d’écriture', (t) async {
      await reserver(4);
      await monter(t, droits: GardeAcces(const {'M9': 'L'}));

      // Barre d'actions (vue l.213) — les deux boutons disparaissent.
      expect(
        find.byKey(const Key('tourisme-nouvelle-reservation')),
        findsNothing,
      );

      // Ligne de départ (l.326) : « Réserver » commande les trois actions du
      // même widget — Réserver, Guide, Annuler partent ensemble.
      expect(find.text('Réserver'), findsNothing);

      await ouvrirOnglet(t, 'reservations');
      // Ligne de réservation (l.458).
      expect(find.text('Annuler'), findsNothing);

      await ouvrirOnglet(t, 'catalogue');
      expect(
        find.byKey(const Key('tourisme-nouvelle-prestation')),
        findsNothing,
      );
      // « Planifier » commande la paire Planifier / Éditer (l.568).
      expect(find.text('Planifier'), findsNothing);
    });

    testWidgets('le même écran, en ÉCRITURE, les rend tous', (t) async {
      // CONTRÔLE POSITIF, et il n'est pas décoratif : sans lui, le cas
      // ci-dessus passerait tout aussi bien si ces libellés n'existaient nulle
      // part. C'est l'erreur exacte de PA-133 — un test qui ne pouvait pas
      // échouer a laissé trois écrans livrés inatteignables.
      await reserver(4);
      await monter(t, droits: GardeAcces(const {'M9': 'C'}));

      expect(
        find.byKey(const Key('tourisme-nouvelle-reservation')),
        findsOneWidget,
      );
      expect(find.text('Réserver'), findsWidgets);

      await ouvrirOnglet(t, 'reservations');
      expect(find.text('Annuler'), findsWidgets);

      await ouvrirOnglet(t, 'catalogue');
      expect(
        find.byKey(const Key('tourisme-nouvelle-prestation')),
        findsOneWidget,
      );
      expect(find.text('Planifier'), findsWidgets);
    });
  });

  /* ================================================================== */
  group('Le panneau « non rendu » n\'existe plus : la vue ne le porte pas', () {
    testWidgets('ni son titre, ni ses raisons ne sont à l\'écran', (t) async {
      await monter(t);

      // `departs.blade.php` l.624-637 : « un écran dit ce qu'il FAIT ». Les
      // raisons sont écrites dans le code, datées (`ecran_tourisme.dart`).
      expect(find.text('Ce que cet écran ne rend pas'), findsNothing);
      expect(
        find.textContaining('Un départ n\'est pas une entité'),
        findsNothing,
      );
      expect(find.byKey(const Key('tourisme-non-rendu')), findsNothing);
    });
  });

  /* ================================================================== */
  group('Mise en page — relevé de la vue du 09/10/2026', () {
    testWidgets('la page a 32 px de marge au poste de travail (lg), 20 en '
        'dessous', (t) async {
      // Relevé à 1 383 px : le titre est à x = 330 = 264 (barre latérale) + 32
      // (`lg:p-8`) + 34 (icône de 24 + écart de 10). Ici sans barre latérale :
      // 32 + 34 = 66 à 1 600 px, 20 + 34 = 54 sous le point de rupture.
      await monter(t);
      // La page est plafonnée à `max-w-[1440px]` et centrée : à 1 600 px, 80 px
      // de part et d'autre s'ajoutent à la marge.
      expect(
        t.getTopLeft(find.text('Tourisme')).dx,
        66 + (1600 - AppLayout.maxContentWidth) / 2,
      );
    });

    testWidgets('sous 1 024 px la marge retombe à 20 px (`p-5`)', (t) async {
      await monter(t, taille: const Size(1000, 3000));
      expect(t.getTopLeft(find.text('Tourisme')).dx, 54);
    });

    testWidgets('« Exporter » est dans l\'en-tête, à droite du second champ '
        'de date, sur la même rangée', (t) async {
      await monter(t);

      final exporter = find.byKey(const Key('tourisme-exporter'));
      expect(exporter, findsOneWidget);
      expect(find.text('Exporter'), findsOneWidget);
      final fin = find.byKey(const Key('tourisme-date-fin'));
      expect(t.getTopLeft(exporter).dx, greaterThan(t.getTopRight(fin).dx));
      // Même rangée : le bouton (35,5) et le champ (36,4) se centrent.
      expect(
        (t.getCenter(exporter).dy - t.getCenter(fin).dy).abs(),
        lessThan(2),
      );
      // Il est AVANT la barre de filtres (vue l.116, puis l.176).
      expect(
        t.getBottomLeft(exporter).dy,
        lessThan(t.getTopLeft(find.byType(BarreFiltresTourisme)).dy),
      );
    });

    testWidgets('« Exporter » est une LECTURE : offert au rôle en lecture', (
      t,
    ) async {
      await monter(t, droits: GardeAcces(const {'M9': 'L'}));

      expect(find.byKey(const Key('tourisme-exporter')), findsOneWidget);
      expect(
        find.byKey(const Key('tourisme-nouvelle-reservation')),
        findsNothing,
      );
    });

    testWidgets(
      'le champ de recherche mesure 36,4 px, comme les trois listes',
      (t) async {
        await monter(t);

        // Relevé : « Circuit, client, guide, n°… » h = 36,4. Les contrôles
        // Material en font 40 à 48.
        expect(
          t.getSize(find.byKey(const Key('tourisme-recherche'))).height,
          closeTo(AppLayout.hauteurChampTourisme, 0.5),
        );
        for (final cle in [
          'tourisme-filtre-prestation',
          'tourisme-filtre-remplissage',
          'tourisme-filtre-statut',
        ]) {
          expect(
            t.getSize(find.byKey(Key(cle))).height,
            closeTo(AppLayout.hauteurChampTourisme, 1.5),
            reason: cle,
          );
        }
      },
    );

    testWidgets('les trois listes ont les largeurs déduites du relevé', (
      t,
    ) async {
      await monter(t);

      expect(
        t.getSize(find.byKey(const Key('tourisme-filtre-prestation'))).width,
        AppLayout.filtrePrestationTourisme,
      );
      expect(
        t.getSize(find.byKey(const Key('tourisme-filtre-remplissage'))).width,
        AppLayout.filtreRemplissageTourisme,
      );
      expect(
        t.getSize(find.byKey(const Key('tourisme-filtre-statut'))).width,
        AppLayout.filtreStatutTourisme,
      );
      // La somme des trois est celle MESURÉE : 1 025 - 2 x 215,1 - 115,7 - 50.
      expect(
        AppLayout.filtrePrestationTourisme +
            AppLayout.filtreRemplissageTourisme +
            AppLayout.filtreStatutTourisme,
        429,
      );
    });

    testWidgets('large, « + Réservation » est poussé à DROITE par l\'espace', (
      t,
    ) async {
      await monter(t);

      final barre = find.byType(BarreFiltresTourisme);
      final bouton = find.byKey(const Key('tourisme-nouvelle-reservation'));
      // Bord droit de la barre, moins `p-3.5` (14) et sa bordure (1).
      expect(
        t.getTopRight(bouton).dx,
        closeTo(t.getTopRight(barre).dx - 15, 0.5),
      );
      // La recherche s'étire (`flex-1`) bien au-delà de son minimum de 200 px,
      // et partage le reste avec l'espace (`flex-1`) : elle ne lui prend pas
      // tout.
      final recherche = t.getSize(find.byKey(const Key('tourisme-recherche')));
      expect(recherche.width, greaterThan(AppLayout.rechercheMinTourisme));
      expect(
        t.getTopLeft(find.byKey(const Key('tourisme-filtre-prestation'))).dx,
        closeTo(
          t.getTopLeft(find.byKey(const Key('tourisme-recherche'))).dx +
              recherche.width +
              AppSpacing.xsPlus,
          0.5,
        ),
      );
      // Entre la dernière liste et le bouton : un écart, l'espace `flex-1`
      // (égal à la recherche, 215,1 px au relevé), un écart.
      expect(
        t.getTopLeft(bouton).dx -
            t.getTopRight(find.byKey(const Key('tourisme-filtre-statut'))).dx,
        closeTo(recherche.width + 2 * AppSpacing.xsPlus, 0.5),
        reason: 'l\'espace `flex-1` doit valoir la recherche, pas zéro',
      );
    });

    testWidgets('étroit, la barre passe à la ligne : recherche à 200 px', (
      t,
    ) async {
      await monter(t, taille: const Size(800, 3000));

      expect(
        t.getSize(find.byKey(const Key('tourisme-recherche'))).width,
        AppLayout.rechercheMinTourisme,
      );
      expect(
        find.byKey(const Key('tourisme-nouvelle-reservation')),
        findsOneWidget,
      );
    });
  });

  /* ================================================================== */
  group('Les indicateurs portent de VRAIES valeurs, et leurs couleurs', () {
    Text valeurDe(WidgetTester t, String carte, String texte) => t.widget<Text>(
      find.descendant(
        of: find.byKey(Key('tourisme-kpi-$carte')),
        matching: find.text(texte),
      ),
    );

    testWidgets(
      'un départ de 5 personnes : les six cartes, valeur par valeur',
      (t) async {
        await dao.reserver(
          circuitId: 'cir-1',
          clientId: 'cli-1',
          guideId: 'gui-1',
          dateCircuit: DateTime(2026, 10, 12),
          nbParticipants: 5,
        );
        await monter(t);
        fixerPeriode(t);
        await t.pumpAndSettle();

        Finder dans(String carte, String texte) => find.descendant(
          of: find.byKey(Key('tourisme-kpi-$carte')),
          matching: find.text(texte),
        );

        expect(dans('departs', '1'), findsOneWidget);
        expect(dans('departs', '0 complet(s)'), findsOneWidget);
        expect(dans('places', '5 / 12'), findsOneWidget);
        expect(dans('places', 'Capacité offerte'), findsOneWidget);
        expect(dans('remplissage', '41.7 %'), findsOneWidget);
        expect(dans('remplissage', 'Sur la période'), findsOneWidget);
        expect(dans('ca', '22 500 FCFA'), findsOneWidget);
        expect(dans('ca', 'Réservations confirmées'), findsOneWidget);
        expect(dans('reste', '—'), findsOneWidget);
        expect(dans('reste', 'Soldes clients'), findsOneWidget);
        expect(dans('duree', '1'), findsOneWidget);
        expect(dans('duree', 'Véhicule sous-bloqué'), findsOneWidget);
      },
    );

    testWidgets('sous 50 % le taux est AMBRE, à 50 % il est NAVY', (t) async {
      await dao.reserver(
        circuitId: 'cir-1',
        clientId: 'cli-1',
        guideId: 'gui-1',
        dateCircuit: DateTime(2026, 10, 12),
        nbParticipants: 5,
      );
      await monter(t);
      fixerPeriode(t);
      await t.pumpAndSettle();

      expect(
        valeurDe(t, 'remplissage', '41.7 %').style?.color,
        PaletteMaitre.ambre600,
      );

      // 6 sur 12 : 50 % pile, le seuil est STRICT (`< 50`, vue l.139).
      await dao.reserver(
        circuitId: 'cir-1',
        clientId: 'cli-1',
        guideId: 'gui-1',
        dateCircuit: DateTime(2026, 10, 12),
        nbParticipants: 1,
      );
      rechargerAvecLaPeriode(t);
      await t.pumpAndSettle();

      expect(valeurDe(t, 'remplissage', '50 %').style?.color, AppColors.navy);
    });

    testWidgets(
      '« Durée indéterminée » : ambre à 1, ardoise à 0 (une mesure)',
      (t) async {
        await dao.reserver(
          circuitId: 'cir-1',
          clientId: 'cli-1',
          guideId: 'gui-1',
          dateCircuit: DateTime(2026, 10, 12),
          nbParticipants: 5,
        );
        await monter(t);
        fixerPeriode(t);
        await t.pumpAndSettle();

        // Le circuit semé n'a aucune durée : le départ est indéterminé.
        expect(valeurDe(t, 'duree', '1').style?.color, PaletteMaitre.ambre600);

        // Une durée chiffrée : plus aucun départ indéterminé, et « 0 » est un
        // vrai compte — en ardoise, pas en navy (vue l.163).
        await dao.enregistrerCircuit(
          id: 'cir-1',
          nom: 'Cascades de Tanougou',
          theme: 'Nature',
          zone: 'Atacora',
          prix: 4500,
          capaciteMax: 12,
          duree: '3 jours / 2 nuits',
        );
        rechargerAvecLaPeriode(t);
        await t.pumpAndSettle();

        expect(valeurDe(t, 'duree', '0').style?.color, Ardoise.c400);
      },
    );

    testWidgets('la raison d\'une absence est une INFOBULLE, jamais du texte '
        'sous le détail', (t) async {
      await monter(t);

      // Sans capacité offerte, le taux est « — » et dit pourquoi.
      final taux = t.widget<Tooltip>(
        find.byKey(const Key('tourisme-kpi-remplissage-raison')),
      );
      expect(
        taux.message,
        'Aucune capacité offerte sur la période : il n\'y a rien à remplir. '
        '« 0 % » se lirait comme un départ désert.',
      );
      final reste = t.widget<Tooltip>(
        find.byKey(const Key('tourisme-kpi-reste-raison')),
      );
      expect(
        reste.message,
        // Sans nom de table (`reservations_tour`) depuis la consigne du PO du
        // 14/10/2026 : la raison est dite en clair.
        'Aucun acompte n\'est enregistré sur une réservation de circuit : le '
        'reste à encaisser n\'est pas calculable. Afficher le montant entier '
        'le présenterait comme impayé.',
      );
      // La carte ne l'écrit pas : sa hauteur est celle de la vue.
      expect(find.text(reste.message!), findsNothing);
      expect(find.textContaining('Aucune colonne d\'acompte'), findsNothing);
    });

    testWidgets('avec une capacité offerte, le taux n\'a plus d\'infobulle', (
      t,
    ) async {
      await dao.reserver(
        circuitId: 'cir-1',
        clientId: 'cli-1',
        guideId: 'gui-1',
        dateCircuit: DateTime(2026, 10, 12),
        nbParticipants: 5,
      );
      await monter(t);
      fixerPeriode(t);
      await t.pumpAndSettle();

      expect(
        find.byKey(const Key('tourisme-kpi-remplissage-raison')),
        findsNothing,
      );
      // « Reste à encaisser » reste structurellement absent.
      expect(
        find.byKey(const Key('tourisme-kpi-reste-raison')),
        findsOneWidget,
      );
    });
  });

  /* ================================================================== */
  group('Le bandeau « durée indéterminée » de la vue (l.251-258)', () {
    Future<void> departIndetermine(String circuit, String jourReservation) =>
        dao.reserver(
          circuitId: circuit,
          clientId: 'cli-1',
          guideId: 'gui-1',
          dateCircuit: DateTime.parse(jourReservation),
          nbParticipants: 2,
        );

    testWidgets('un départ indéterminé : le bandeau, aux mots de la vue', (
      t,
    ) async {
      await departIndetermine('cir-1', '2026-10-12');
      await monter(t);
      fixerPeriode(t);
      await t.pumpAndSettle();

      final bandeau = t.widget<EncadreRestaurant>(
        find.byKey(const Key('tourisme-bandeau-duree')),
      );
      expect(bandeau.titre, '1 départ(s) à durée indéterminée.');
      expect(
        bandeau.texte,
        'La durée de ce circuit est un texte libre au catalogue : '
        '« Plusieurs jours » n\'est pas une durée exploitable. Le véhicule '
        'n\'est alors immobilisé que sur le jour de départ, et non sur la '
        'durée réelle du circuit.',
      );
      expect(bandeau.ton, TonEncadre.ambre);
    });

    testWidgets('deux circuits indéterminés : « 2 », comme la carte', (
      t,
    ) async {
      await db
          .into(db.circuitsLocal)
          .insert(
            CircuitsLocalCompanion.insert(
              id: 'cir-2',
              nom: 'Tata Somba',
              theme: 'Culture',
              zone: 'Boukoumbé',
              prix: 3000,
              capaciteMax: 10,
            ),
          );
      await departIndetermine('cir-1', '2026-10-12');
      await departIndetermine('cir-2', '2026-10-14');
      await monter(t);
      fixerPeriode(t);
      await t.pumpAndSettle();

      expect(
        t
            .widget<EncadreRestaurant>(
              find.byKey(const Key('tourisme-bandeau-duree')),
            )
            .titre,
        '2 départ(s) à durée indéterminée.',
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('tourisme-kpi-duree')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('le nombre est celui des départs INDÉTERMINÉS, pas de tous', (
      t,
    ) async {
      // Deux départs, un seul indéterminé : « 1 », et surtout pas « 2 ».
      await db
          .into(db.circuitsLocal)
          .insert(
            CircuitsLocalCompanion.insert(
              id: 'cir-2',
              nom: 'Tata Somba',
              theme: 'Culture',
              zone: 'Boukoumbé',
              prix: 3000,
              capaciteMax: 10,
              duree: const Value('1 jour'),
            ),
          );
      await departIndetermine('cir-1', '2026-10-12');
      await departIndetermine('cir-2', '2026-10-14');
      await monter(t);
      fixerPeriode(t);
      await t.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('tourisme-kpi-departs')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      expect(
        t
            .widget<EncadreRestaurant>(
              find.byKey(const Key('tourisme-bandeau-duree')),
            )
            .titre,
        '1 départ(s) à durée indéterminée.',
      );
    });

    testWidgets('une durée chiffrée : AUCUN bandeau', (t) async {
      await dao.enregistrerCircuit(
        id: 'cir-1',
        nom: 'Cascades de Tanougou',
        theme: 'Nature',
        zone: 'Atacora',
        prix: 4500,
        capaciteMax: 12,
        duree: '3 jours / 2 nuits',
      );
      await departIndetermine('cir-1', '2026-10-12');
      await monter(t);
      fixerPeriode(t);
      await t.pumpAndSettle();

      expect(find.byKey(const Key('tourisme-bandeau-duree')), findsNothing);
      expect(find.textContaining('durée indéterminée.'), findsNothing);
    });

    testWidgets('il appartient à l\'onglet des départs seulement', (t) async {
      await departIndetermine('cir-1', '2026-10-12');
      await monter(t);
      fixerPeriode(t);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tourisme-bandeau-duree')), findsOneWidget);

      await ouvrirOnglet(t, 'reservations');
      expect(find.byKey(const Key('tourisme-bandeau-duree')), findsNothing);
    });
  });

  /* ================================================================== */
  group('Le catalogue est filtré sur le nom ET la zone', () {
    testWidgets('la recherche « pendjari » retient la zone, pas le nom', (
      t,
    ) async {
      await db
          .into(db.circuitsLocal)
          .insert(
            CircuitsLocalCompanion.insert(
              id: 'cir-2',
              nom: 'Safari des éléphants',
              theme: 'Faune',
              zone: 'Pendjari',
              prix: 20000,
              capaciteMax: 6,
            ),
          );
      await monter(t);
      await ouvrirOnglet(t, 'catalogue');
      expect(find.byKey(const Key('tourisme-circuit-cir-1')), findsOneWidget);
      expect(find.byKey(const Key('tourisme-circuit-cir-2')), findsOneWidget);

      await t.enterText(
        find.byKey(const Key('tourisme-recherche')),
        'PENDJARI',
      );
      await t.pumpAndSettle();

      expect(find.byKey(const Key('tourisme-circuit-cir-1')), findsNothing);
      expect(find.byKey(const Key('tourisme-circuit-cir-2')), findsOneWidget);
    });
  });

  /* ================================================================== */
  group('« Exporter » : de la modale au fichier, de bout en bout', () {
    // La fenêtre « Enregistrer sous » remplacée (14/10/2026) : le VRAI
    // chemin `exporterTourismeProvider` → `enregistrementExportProvider` est
    // emprunté jusqu'à elle.
    late SelecteurEssai selecteur;

    setUp(() => selecteur = SelecteurEssai());

    Future<void> monterPourExporter(
      WidgetTester t, {
      GardeAcces? droits,
    }) async {
      await monter(t, droits: droits, surcharges: [...selecteur.surcharges]);
      fixerPeriode(t);
      await t.pumpAndSettle();
    }

    /// Ouvre la modale, choisit [choix] (le tableur par défaut : le PDF est
    /// présélectionné dans la modale depuis D434) et clique « Générer &
    /// Télécharger ».
    Future<void> exporter(WidgetTester t, {String? choix}) async {
      await t.tap(find.byKey(const Key('tourisme-exporter')));
      await t.pumpAndSettle();
      await t.tap(find.text(choix ?? 'Tableur Excel (.xlsx / .csv)'));
      await t.pumpAndSettle();
      await t.tap(find.text('Générer & Télécharger'));
      await t.pump();
    }

    /// La composition (un PDF surtout) peut faire de vraies E/S : on alterne
    /// un `pump` (la chaîne de futures du test) et une attente réelle, jusqu'à
    /// lire à l'écran que le fichier est enregistré.
    Future<FichierEnregistreEssai> attendreLeFichier(WidgetTester t) async {
      final fait = find.byKey(const Key('tourisme-export-fait'));
      for (var i = 0; i < 100 && fait.evaluate().isEmpty; i++) {
        await t.pump(const Duration(milliseconds: 20));
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await t.pumpAndSettle();
      expect(selecteur.ecrits, hasLength(1), reason: 'un seul fichier écrit');
      return selecteur.ecrits.single;
    }

    List<String> lignesDe(FichierEnregistreEssai f) {
      expect(f.type, TypeFichierEnregistre.csv);
      final octets = f.octets;
      // Le BOM, d'abord, avant tout décodage.
      expect(octets.take(3), [0xEF, 0xBB, 0xBF]);
      return utf8.decode(octets.sublist(3)).split('\n');
    }

    Future<void> reserverLe(
      String jourReservation,
      int participants, {
      String circuit = 'cir-1',
    }) => dao.reserver(
      circuitId: circuit,
      clientId: 'cli-1',
      guideId: 'gui-1',
      dateCircuit: DateTime.parse(jourReservation),
      nbParticipants: participants,
    );

    testWidgets('la modale porte le titre de la vue, ses deux formats et '
        'la note du CSV — plus d\'aide qui annonce un PDF refusé', (t) async {
      await monterPourExporter(t);
      await t.tap(find.byKey(const Key('tourisme-exporter')));
      await t.pumpAndSettle();

      expect(find.text('Exporter le rapport Tourisme'), findsOneWidget);
      expect(find.text('Format du document'), findsOneWidget);
      expect(find.text('PDF Officiel A4 Imprimable'), findsOneWidget);
      expect(find.text('Tableur Excel (.xlsx / .csv)'), findsOneWidget);
      expect(find.text('Générer & Télécharger'), findsOneWidget);
      // Le PDF est produit depuis le 14/10/2026 : la modale dit seulement ce
      // que produit le tableur, plus aucune aide propre à l'écran.
      expect(find.byKey(const Key('export-note-csv')), findsOneWidget);
      expect(find.byKey(const Key('export-aide')), findsNothing);
      expect(find.textContaining("n'est pas produit"), findsNothing);
    });

    testWidgets('Départs : un vrai fichier, BOM, filtre dit, valeurs exactes', (
      t,
    ) async {
      await reserverLe('2026-10-12', 5);
      await monterPourExporter(t);
      await exporter(t);
      final fichier = await attendreLeFichier(t);

      expect(
        fichier.nom,
        matches(RegExp(r'^tourisme_\d{4}-\d{2}-\d{2}\.csv$')),
      );
      expect(fichier.dossierInitial, SelecteurEssai.dossierDocuments);
      final l = lignesDe(fichier);
      expect(
        l[0],
        'Départs planifiés;du 09/10/2026 au 08/11/2026 · Statut : Planifiés',
      );
      expect(
        l[5],
        'N°;Circuit;Départ;Guide;Véhicule;Remplissage;Prix / pers.;CA;État',
      );
      expect(
        l[6],
        ';Cascades de Tanougou;12/10/2026;ADJOVI Paul;;5/12;4500;22500;'
        '7 place(s)',
      );
      expect(l.length, 8);
      // Le toast commun dit le NOM du fichier enregistré.
      expect(find.text('Export enregistré : ${fichier.nom}'), findsOneWidget);
    });

    testWidgets('Réservations : l\'export suit l\'ONGLET affiché', (t) async {
      await reserverLe('2026-10-12', 5);
      await monterPourExporter(t);
      await ouvrirOnglet(t, 'reservations');
      await exporter(t);
      final l = lignesDe(await attendreLeFichier(t));

      expect(
        l[0],
        'Réservations;du 09/10/2026 au 08/11/2026 · Statut : Planifiés',
      );
      expect(
        l[5],
        'N°;Client;Circuit;Départ;Pers.;Prix / pers.;Montant;Acompte;Reste dû',
      );
      expect(l[6], ';KORA Jean;Cascades de Tanougou;12/10/2026;5;4500;22500;;');
    });

    testWidgets('Catalogue : durée vide, un départ planifié, jamais « 0 »', (
      t,
    ) async {
      await reserverLe('2026-10-12', 5);
      await monterPourExporter(t);
      await ouvrirOnglet(t, 'catalogue');
      await exporter(t);
      final l = lignesDe(await attendreLeFichier(t));

      expect(l[0], 'Catalogue;du 09/10/2026 au 08/11/2026');
      // Trois mentions ici (deux ailleurs) : les en-têtes suivent la ligne vide.
      expect(
        l[6],
        'Prestation;Type;Durée;Zone / thème;Prix;Indicatif €;Départs planifiés',
      );
      expect(l[7], 'Cascades de Tanougou;Circuit;;Atacora · Nature;4500;;1');
      expect(l.length, 9);
    });

    testWidgets('l\'export porte sur ce qui est AFFICHÉ : filtre et recherche', (
      t,
    ) async {
      await db
          .into(db.circuitsLocal)
          .insert(
            CircuitsLocalCompanion.insert(
              id: 'cir-2',
              nom: 'Tata Somba',
              theme: 'Culture',
              zone: 'Boukoumbé',
              prix: 3000,
              capaciteMax: 10,
            ),
          );
      await reserverLe('2026-10-12', 5);
      await reserverLe('2026-10-14', 2, circuit: 'cir-2');
      await monterPourExporter(t);

      await t.enterText(find.byKey(const Key('tourisme-recherche')), 'tata');
      await t.pumpAndSettle();
      await exporter(t);
      final l = lignesDe(await attendreLeFichier(t));

      expect(
        l[0],
        'Départs planifiés;du 09/10/2026 au 08/11/2026 · Statut : Planifiés · '
        'Recherche : tata',
      );
      // Un seul départ, celui de « Tata Somba » : l'autre est filtré.
      expect(
        l[6],
        ';Tata Somba;14/10/2026;ADJOVI Paul;;2/10;3000;6000;8 place(s)',
      );
      expect(l.length, 8);
    });

    testWidgets('choisir le PDF PRODUIT l\'état A4, enregistré en .pdf, et '
        'le toast le dit', (t) async {
      await reserverLe('2026-10-12', 5);
      await monterPourExporter(t);
      await exporter(t, choix: 'PDF Officiel A4 Imprimable');
      await attendreLeFichier(t);

      expect(find.byKey(const Key('tourisme-pdf-refuse')), findsNothing);
      expect(selecteur.ecrits, hasLength(1));
      final pdf = selecteur.ecrits.single;
      expect(pdf.type, TypeFichierEnregistre.pdf);
      expect(pdf.nom, matches(RegExp(r'^tourisme_\d{4}-\d{2}-\d{2}\.pdf$')));
      expect(pdf.estUnPdf, isTrue);
      expect(find.byKey(const Key('tourisme-export-fait')), findsOneWidget);
    });

    testWidgets('une liste vide est REFUSÉE, rien n\'est écrit', (t) async {
      await monterPourExporter(t);
      await exporter(t);
      await t.pumpAndSettle();

      expect(find.byKey(const Key('tourisme-export-vide')), findsOneWidget);
      expect(
        find.text(
          'Aucune ligne à exporter sur ce filtre — un document vide se lirait '
          'comme un registre vérifié.',
        ),
        findsOneWidget,
      );
      expect(selecteur.ecrits, isEmpty);
    });

    testWidgets('un rôle en LECTURE exporte : c\'est une lecture', (t) async {
      await reserverLe('2026-10-12', 5);
      await monterPourExporter(t, droits: GardeAcces(const {'M9': 'L'}));
      await exporter(t);
      final l = lignesDe(await attendreLeFichier(t));

      expect(l[6].startsWith(';Cascades de Tanougou;12/10/2026'), isTrue);
    });
  });

  /* ================================================================== */
  group('Ce qui est refusé, déclaré, et ce qui ne l\'est plus', () {
    test('la modale d\'archivage reste le SEUL bloc refusé du code', () {
      final source = File(
        'lib/features/tourisme/presentation/ecran_tourisme.dart',
      ).readAsStringSync();

      expect(
        source,
        contains('blade-refuse:tourisme/departs#modale:modale-archivage'),
      );
      // L'export est PORTÉ : son jeton de refus serait un mensonge.
      expect(
        source,
        isNot(contains('blade-refuse:tourisme/departs#modale:modale-export')),
      );
    });
  });
}

/// Remet la fenêtre sur la période du 9 octobre au 8 novembre 2026 : sans cela
/// l'écran lit l'horloge du jour, et un départ du 12/10/2026 en sortirait.
void fixerPeriode(WidgetTester t) {
  final conteneur = ProviderScope.containerOf(
    t.element(find.byType(EcranTourisme)),
  );
  conteneur.read(periodeTourismeProvider.notifier)
    ..definirDebut(DateTime(2026, 10, 9))
    ..definirFin(DateTime(2026, 11, 8));
}

/// Force la relecture des départs après une écriture directe en base.
void rechargerAvecLaPeriode(WidgetTester t) {
  ProviderScope.containerOf(t.element(find.byType(EcranTourisme)))
    ..invalidate(registreTourismeProvider)
    ..invalidate(circuitsProvider);
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
