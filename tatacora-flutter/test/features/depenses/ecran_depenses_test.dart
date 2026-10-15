import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/theme/app_text_styles.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/messages_comptables.dart';
import 'package:tatacora_flutter/features/depenses/data/depense_dao.dart';
import 'package:tatacora_flutter/features/depenses/domain/categories_depense.dart';
import 'package:tatacora_flutter/features/depenses/domain/entities/depense.dart';
import 'package:tatacora_flutter/features/depenses/impression/etat_depenses.dart';
import 'package:tatacora_flutter/features/depenses/presentation/ecran_depenses.dart';
import 'package:tatacora_flutter/features/depenses/presentation/providers_depenses.dart';

import 'support/outils_depenses.dart';

/// Le rendu de **Dépense courante** — vue Blade `depenses/depenses.blade.php`
/// (chemin sans préfixe : ce fichier ne porte pas la vue, PA-187).
///
/// ## Ces cas lisent l'ARBRE DE WIDGETS MONTÉ
///
/// Le comparateur de conformité lit le **source** et ne distingue pas une
/// chaîne rendue d'une chaîne citée en commentaire. Cet écran en porte
/// beaucoup, précisément parce qu'il documente ce qu'il refuse : les libellés
/// qui comptent sont donc éprouvés ici, sur un écran réellement construit.
///
/// ## Et ils empruntent le VRAI chemin d'écriture
///
/// La base est en mémoire, mais c'est le DAO réel qui écrit, et la liste est
/// relue de la base. Un dépôt bouché prouverait que l'écran sait afficher une
/// liste ; il ne prouverait pas qu'une dépense saisie s'enregistre.
void main() {
  late AppDatabase db;
  late DepenseDao dao;

  setUp(() async {
    // Le référentiel comptable est installé par la vraie fonction : une
    // dépense ne s'enregistre jamais sans sa pièce.
    db = await baseDepenses();
    dao = depenseDaoSur(db);
  });

  tearDown(() => db.close());

  /// Deux dépenses COMPTABILISÉES, par le chemin réel : chacune a sa pièce.
  Future<void> semer() async {
    await dao.enregistrer(
      dateTransaction: DateTime(2026, 9, 10),
      tresorerie: TresorerieDepense.caisse,
      libelle: 'Marché du matin — Légumes & condiments',
      auteurId: auteurDepense,
      centreId: await centreDe(db, 'Restaurant'),
      lignes: const [
        SaisieLigneDepense(
          libelle: 'Achat d\'oignons (2 sacs)',
          compteCharge: '6011',
          nature: NatureDepense.oignon,
          montant: 15000,
        ),
        SaisieLigneDepense(
          libelle: 'Tomates fraîches',
          compteCharge: '6011',
          nature: NatureDepense.tomate,
          montant: 8500,
        ),
      ],
    );
    await dao.enregistrer(
      dateTransaction: DateTime(2026, 9, 1),
      tresorerie: TresorerieDepense.banque,
      libelle: 'Facture d\'électricité SBEE & Eau SONEB',
      auteurId: auteurDepense,
      centreId: await centreDe(db, 'Structure'),
      lignes: const [
        SaisieLigneDepense(
          libelle: 'Recharge compteur Électricité',
          compteCharge: '6052',
          nature: NatureDepense.electriciteEau,
          montant: 45000,
        ),
      ],
    );
  }

  /// Une dépense d'AVANT la comptabilité : aucune pièce, comme sur un poste
  /// migré depuis la v15 — écrite DIRECTEMENT en base, parce que le compte d'une
  /// telle dépense (l'ancien registre à six chiffres) n'est plus au plan et que
  /// le DAO le refuserait.
  Future<void> semerSansPiece({String compte = '6052'}) =>
      semerDepenseAncienne(db, compte: compte);

  Future<void> monter(
    WidgetTester tester, {
    List<Override> surcharges = const [],
    Map<String, String> droits = const {'M10': 'C'},
  }) async {
    tester.view
      ..physicalSize = const Size(1800, 2600)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...surchargesDepenses(db, droits: droits),
          ...surcharges,
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranDepenses()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Choisit [libelle] dans le select du bandeau de rattrapage.
  Future<void> choisirCentre(WidgetTester tester, String libelle) async {
    final liste = find.byKey(const Key('depenses-centre-rattrapage'));
    await tester.ensureVisible(liste);
    await tester.pumpAndSettle();
    await tester.tap(liste);
    await tester.pumpAndSettle();
    await tester.tap(find.text(libelle).last);
    await tester.pumpAndSettle();
  }

  group('Les libellés de la vue sont rendus', () {
    testWidgets('titre, sous-titre et bouton de saisie', (tester) async {
      await monter(tester);

      expect(find.text('Dépense courante'), findsOneWidget);
      expect(find.byKey(const Key('depenses-nouvelle')), findsOneWidget);
      expect(find.text('Nouvelle Dépense'), findsOneWidget);

      // Le sous-titre est rendu en `Text.rich` : on cherche donc le fragment
      // dans le texte COMPOSÉ, pas un `find.text` exact.
      final sousTitre = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.textSpan?.toPlainText() ?? t.data ?? '')
          .join(' ');
      expect(sousTitre, contains('décaissées directement'));
      expect(sousTitre, contains('Approvisionnement'));
    });

    testWidgets('les six libellés d’indicateur, dans l’ordre', (tester) async {
      await monter(tester);

      // `CarteIndicateurRestaurant` rend son libellé en CAPITALES, comme la
      // vue (`uppercase` est une transformation CSS).
      for (final libelle in const [
        'TOTAL DÉCAISSÉ',
        'DÉPENSE MOYENNE',
        'MARCHÉ',
        'SERVICES',
        'CAISSE',
        'SANS ÉCRITURE',
      ]) {
        expect(find.text(libelle), findsOneWidget, reason: libelle);
      }

      expect(find.text('denrées'), findsOneWidget);
      expect(find.text('charges externes'), findsOneWidget);
      expect(find.text('espèces'), findsOneWidget);
    });

    testWidgets('les sept en-têtes de colonne', (tester) async {
      await semer();
      await monter(tester);

      for (final colonne in const [
        'DATE',
        'LIBELLÉ',
        'NATURE',
        'CHARGE (SYSCOHADA)',
        'TRÉSORERIE',
        'MONTANT',
        'PIÈCES',
      ]) {
        expect(find.text(colonne), findsWidgets, reason: colonne);
      }
    });

    testWidgets('les cinq contrôles de la barre de filtres', (tester) async {
      await monter(tester);

      expect(find.byKey(const Key('depenses-recherche')), findsOneWidget);
      expect(find.byKey(const Key('depenses-du')), findsOneWidget);
      expect(find.byKey(const Key('depenses-au')), findsOneWidget);
      expect(find.byKey(const Key('depenses-tresorerie')), findsOneWidget);
      expect(find.byKey(const Key('depenses-famille')), findsOneWidget);
      expect(find.text('Réinitialiser'), findsOneWidget);
      expect(find.text('Exporter'), findsOneWidget);
      // Les libellés des deux options « aucun filtre », au mot de la vue.
      expect(find.text('Toute trésorerie'), findsOneWidget);
      expect(find.text('Toute catégorie'), findsOneWidget);
    });

    testWidgets('l’état vide sans filtre appelle à SAISIR', (tester) async {
      await monter(tester);

      expect(find.byKey(const Key('depenses-vide')), findsOneWidget);
      expect(find.byKey(const Key('depenses-vide-filtre')), findsNothing);
    });
  });

  group('La page suit la structure de la vue', () {
    testWidgets('le titre est à 17 px, jamais à 18,5 (lg:text-xl ne s’applique '
        'pas dans <main>)', (tester) async {
      await monter(tester);

      // La fenêtre fait 1 800 px : au-delà de `lg`, où une variante
      // `lg:text-xl` s'appliquerait si `app.css` ne la battait pas en
      // spécificité (`main .text-lg`). Mesuré dans le navigateur à 1 383 px :
      // 17 px.
      final titre = tester.widget<Text>(find.text('Dépense courante'));
      expect(titre.style?.fontSize, TaillesContenu.lg);
      expect(titre.style?.fontSize, isNot(TaillesContenu.xl));
    });

    testWidgets('les sept en-têtes restent affichés quand la liste est vide', (
      tester,
    ) async {
      await monter(tester);

      // La vue pose son `<thead>` hors de la boucle : l'état vide est une
      // ligne SOUS les en-têtes, pas à leur place.
      for (final colonne in const [
        'DATE',
        'LIBELLÉ',
        'NATURE',
        'CHARGE (SYSCOHADA)',
        'TRÉSORERIE',
        'MONTANT',
        'PIÈCES',
      ]) {
        expect(find.text(colonne), findsOneWidget, reason: colonne);
      }
      expect(find.byKey(const Key('depenses-vide')), findsOneWidget);
    });

    testWidgets('le tableau n’est plus suivi du bloc « ce que cet écran ne '
        'rend pas »', (tester) async {
      await monter(tester);

      // La vue retire ce bloc (l.307-318, directive du 02/09/2026).
      expect(find.byKey(const Key('depenses-non-rendu')), findsNothing);
      expect(find.text('Ce que cet écran ne rend pas'), findsNothing);
    });

    testWidgets('la bande d’indicateurs se replie, sans icône', (tester) async {
      await monter(tester);

      expect(find.byKey(const Key('depenses-kpi-total')), findsOneWidget);
      // La bascule de la vue n'a aucune flèche (l.153-157).
      expect(find.byIcon(Icons.expand_less), findsNothing);
      expect(find.byIcon(Icons.expand_more), findsNothing);

      await tester.tap(find.byKey(const Key('depenses-kpis-bascule')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('depenses-kpi-total')), findsNothing);

      await tester.tap(find.byKey(const Key('depenses-kpis-bascule')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('depenses-kpi-total')), findsOneWidget);
    });

    testWidgets('les six cartes tiennent sur UNE rangée à 1 800 px (xl:grid-'
        'cols-6)', (tester) async {
      await monter(tester);

      final haut = <double>{
        for (final k in const [
          'total',
          'moyenne',
          'marche',
          'services',
          'caisse',
          'sans-ecriture',
        ])
          tester.getTopLeft(find.byKey(Key('depenses-kpi-$k'))).dy,
      };
      expect(haut, hasLength(1));
    });
  });

  group('Les messages d’honnêteté sont dits au mot près', () {
    testWidgets('« Sans écriture » : « 0 » est une MESURE quand tout est '
        'comptabilisé', (tester) async {
      await semer();
      await monter(tester);

      final carte = find.byKey(const Key('depenses-kpi-sans-ecriture'));
      expect(
        find.descendant(of: carte, matching: find.text('0')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: carte,
          matching: find.text('tout est comptabilisé'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('depenses-bandeau-rattrapage')),
        findsNothing,
      );
    });

    testWidgets(
      '« sans reçu » : l’infobulle dit que c’est vrai pour toutes les '
      'lignes',
      (tester) async {
        await semer();
        await monter(tester);

        final pastille = find.byKey(const Key('depenses-sans-recu'));
        expect(pastille, findsNWidgets(2));
        final infobulle = tester.widget<Tooltip>(
          find
              .ancestor(of: pastille.first, matching: find.byType(Tooltip))
              .first,
        );
        expect(
          infobulle.message,
          'Aucun reçu ne peut être joint sur ce poste : aucun sélecteur de '
          'fichier n’est embarqué dans ce client. La pastille est donc vraie '
          'pour toutes les lignes, ce n’est pas un état parmi deux.',
        );
        // Aucun lien « reçu » (aucun fichier joignable), et rien « non
        // comptabilisée » : les deux dépenses semées ont leur pièce.
        expect(find.text('reçu'), findsNothing);
        expect(find.text('non comptabilisée'), findsNothing);
        expect(find.text('Comptabiliser'), findsNothing);
      },
    );

    testWidgets('le champ « Reçu / facture (photo) » dit pourquoi il est '
        'absent', (tester) async {
      await monter(tester);
      await tester.tap(find.byKey(const Key('depenses-nouvelle')));
      await tester.pumpAndSettle();

      expect(find.text('Reçu / facture (photo)'), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('depense-recu-absent')),
                matching: find.byType(Text),
              ),
            )
            .data,
        'Aucun reçu ne peut être joint sur ce poste : ce client n\'embarque '
        'pas de sélecteur de fichier. Conservez la pièce papier — la '
        'dépense reste enregistrée sans elle.',
      );
    });

    testWidgets('le total de la modale tombe sous la TROISIÈME colonne, comme '
        'la vue', (tester) async {
      await monter(tester);
      await tester.tap(find.byKey(const Key('depenses-nouvelle')));
      await tester.pumpAndSettle();

      final total = tester.getRect(find.byKey(const Key('depense-total')));
      final nature = tester.getRect(
        find.byKey(const Key('depense-ligne-nature-0')),
      );
      final prix = tester.getRect(
        find.byKey(const Key('depense-ligne-montant-0')),
      );
      // Sous « Catégorie de dépenses » (l.454-456), pas sous « Prix ».
      expect(total.center.dx, greaterThan(nature.left));
      expect(total.right, lessThan(prix.left));
    });
  });

  group('« Exporter » ouvre la modale de format de la vue', () {
    /// Ouvre la modale puis valide. Le PDF est présélectionné partout depuis
    /// le 14/10/2026 (D434) : sans [pdf], le tableur est choisi EXPLICITEMENT.
    Future<void> exporter(WidgetTester tester, {bool pdf = false}) async {
      await tester.tap(find.byKey(const Key('depenses-exporter')));
      await tester.pumpAndSettle();
      expect(find.text('Exporter — Dépenses'), findsOneWidget);
      if (!pdf) {
        await tester.tap(find.byKey(const Key('export-format-excel')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('export-generer')));
      await tester.pumpAndSettle();
    }

    // D434 (PO, 14/10/2026) : le PDF est présélectionné comme dans la vue
    // (`$formatExport = 'pdf'`) ; son refus reste dit APRÈS le clic.
    testWidgets('le PDF est le choix par défaut, comme la vue, avec l’aide '
        'dite avant le clic', (tester) async {
      await monter(tester);
      await tester.tap(find.byKey(const Key('depenses-exporter')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('export-aide'))).data,
        'Le PDF n’est pas produit sur ce poste : seul le tableur (CSV) est '
        'écrit.',
      );
      // Le choix coché est le PDF : l'icône du radio « plein » est la sienne.
      expect(
        find.descendant(
          of: find.byKey(const Key('export-format-pdf')),
          matching: find.byIcon(Icons.radio_button_checked),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('export-format-excel')),
          matching: find.byIcon(Icons.radio_button_checked),
        ),
        findsNothing,
      );
      expect(find.byKey(const Key('export-note-csv')), findsOneWidget);
    });

    testWidgets('le tableur écrit la liste AFFICHÉE (2 lignes) et dit son '
        'filtre', (tester) async {
      await semer();
      final appels = <EtatDepenses>[];
      await monter(
        tester,
        surcharges: [
          exporterDepensesProvider.overrideWithValue((etat) async {
            appels.add(etat);
            return 'C:/export/etat.csv';
          }),
        ],
      );

      // « e » est dans les deux libellés : DEUX lignes restent affichées, et
      // l'export doit les porter toutes les deux (PA-119).
      await tester.enterText(find.byKey(const Key('depenses-recherche')), 'e');
      await tester.pumpAndSettle();
      final affichees = [
        'Marché du matin — Légumes & condiments',
        "Facture d'électricité SBEE & Eau SONEB",
      ];
      for (final libelle in affichees) {
        expect(find.text(libelle), findsOneWidget);
      }

      await exporter(tester);

      expect(appels, hasLength(1));
      expect(appels.single.lignes, hasLength(affichees.length));
      expect(appels.single.lignes.map((d) => d.libelle), affichees);
      // La portée part avec le document et NOMME le filtre.
      expect(appels.single.portee, isNotEmpty);
      expect(appels.single.portee, contains('recherche « e »'));
      expect(find.text('Export écrit : C:/export/etat.csv'), findsOneWidget);
    });

    testWidgets('DE BOUT EN BOUT : le clic écrit un fichier dont les OCTETS '
        'portent le BOM, la comptabilisation et le numéro de pièce', (
      tester,
    ) async {
      await semer();
      await semerDepenseAncienne(db);
      final dossier = Directory.systemTemp.createTempSync('depenses_csv_');
      addTearDown(() => dossier.deleteSync(recursive: true));
      final chemin = '${dossier.path}${Platform.pathSeparator}etat.csv';

      await monter(
        tester,
        surcharges: [
          // Le seul substitut : le DOSSIER (path_provider n'a pas de greffon en
          // test). Les octets sont ceux de `EtatDepenses.csvOctets`, écrits
          // comme `exporterDepensesProvider` les écrit.
          exporterDepensesProvider.overrideWithValue((etat) async {
            // Synchrone : l'E/S asynchrone ne rend jamais la main dans la zone
            // simulée d'un `testWidgets`.
            File(chemin).writeAsBytesSync(etat.csvOctets());
            return chemin;
          }),
        ],
      );
      await exporter(tester);

      final octets = File(chemin).readAsBytesSync();
      // Le BOM est ENCODÉ par `utf8.encode`, pas recopié comme un caractère.
      expect(octets.take(3), utf8.encode('\u{FEFF}'));
      final texte = utf8.decode(octets);
      expect(texte, contains(';Comptabilisation;Pièce comptable'));
      expect(texte, contains(';comptabilisée;CAI-2026-00001'));
      expect(texte, contains(';comptabilisée;BQ-2026-00001'));
      expect(texte, contains(';non comptabilisée;—'));
      // 3 dépenses : 23 500 + 45 000 + 12 000 FCFA, en nombres bruts.
      expect(texte, contains(';23500;'));
      expect(texte, contains(';45000;'));
      expect(texte, contains(';12000;'));
      expect(find.text('Export écrit : $chemin'), findsOneWidget);
    });

    testWidgets('le PDF n’est pas produit, et le poste le DIT', (tester) async {
      await semer();
      final appels = <EtatDepenses>[];
      await monter(
        tester,
        surcharges: [
          exporterDepensesProvider.overrideWithValue((etat) async {
            appels.add(etat);
            return 'C:/export/ne-doit-pas-exister.csv';
          }),
        ],
      );

      // Le PDF est le choix par défaut de la modale (`$formatExport = 'pdf'`).
      await exporter(tester, pdf: true);

      expect(appels, isEmpty, reason: 'aucun fichier ne doit être écrit');
      expect(
        tester
            .widget<Text>(find.byKey(const Key('depenses-export-pdf-absent')))
            .data,
        'Le PDF de la dépense courante n’est pas produit sur ce poste : aucun '
        'état A4 de cet écran n’est classé dans l’en-tête et les visas de '
        'l’application. Rien n’a été écrit. Choisissez « Tableur Excel » pour '
        'obtenir la liste affichée en CSV.',
      );
    });

    testWidgets('une liste vide se REFUSE : aucun fichier sans ligne', (
      tester,
    ) async {
      final appels = <EtatDepenses>[];
      await monter(
        tester,
        surcharges: [
          exporterDepensesProvider.overrideWithValue((etat) async {
            appels.add(etat);
            return 'C:/export/vide.csv';
          }),
        ],
      );

      await exporter(tester);

      expect(appels, isEmpty);
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('depenses-export-vide')),
                matching: find.byType(Text),
              ),
            )
            .data,
        'La liste filtrée est vide : il n’y a rien à exporter. Élargissez la '
        'période ou retirez un filtre.',
      );
    });
  });

  group('Valeurs affichées, droits et « Réinitialiser »', () {
    testWidgets('les cartes portent les VALEURS de la base semée', (
      tester,
    ) async {
      await semer();
      await monter(tester);

      String valeur(String cle) => tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(Key('depenses-kpi-$cle')),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data!)
          .firstWhere((t) => t.endsWith('FCFA'));

      // 15 000 + 8 500 en caisse (Marché) ; 45 000 de Services en banque.
      expect(valeur('total'), '68 500 FCFA');
      expect(valeur('marche'), '23 500 FCFA');
      expect(valeur('services'), '45 000 FCFA');
      expect(valeur('caisse'), '23 500 FCFA');
      expect(valeur('moyenne'), '34 250 FCFA');
    });

    testWidgets('en lecture seule sur M10, « Nouvelle Dépense » est absent', (
      tester,
    ) async {
      await monter(tester, droits: const {'M10': 'L'});

      expect(find.byKey(const Key('depenses-nouvelle')), findsNothing);
      expect(find.text('Nouvelle Dépense'), findsNothing);
      // La page, elle, reste lisible.
      expect(find.text('Dépense courante'), findsOneWidget);
    });

    testWidgets('« Réinitialiser » vide le champ de recherche', (tester) async {
      await semer();
      await monter(tester);

      await tester.enterText(
        find.byKey(const Key('depenses-recherche')),
        'zzz-introuvable',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('depenses-reinitialiser')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('depenses-recherche')))
            .controller!
            .text,
        isEmpty,
      );
    });
  });

  // Le groupe « pièce comptable » est plus bas, après la modale.

  group('La modale « Nouvelle Dépense »', () {
    Future<void> ouvrir(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('depenses-nouvelle')));
      await tester.pumpAndSettle();
    }

    testWidgets('rend les libellés de la vue', (tester) async {
      await monter(tester);
      await ouvrir(tester);

      // ⚠ `textContaining`, pas `text` : les étiquettes obligatoires sont des
      // `Text.rich` — le libellé et son astérisque rouge sont deux `TextSpan`
      // (marqueur du maître pour un champ requis). `find.text` ne compare
      // qu'un `Text` dont la donnée est la chaîne ENTIÈRE, et ne trouvait donc
      // rien. L'écran était juste ; le finder ne l'était pas.
      expect(find.textContaining('Date de la transaction'), findsOneWidget);
      expect(find.textContaining('Libellé de la dépense'), findsOneWidget);
      expect(find.textContaining('Lignes de la dépense'), findsOneWidget);
      expect(find.text('+ Ajouter une ligne'), findsOneWidget);
      // Les en-têtes du tableau des lignes sont en CAPITALES, comme la vue
      // (`uppercase`, l.373) : le libellé reste celui du lexique, la casse est
      // une transformation d'affichage.
      expect(find.text('CATÉGORIE DES CHARGES (SYSCOHADA)'), findsOneWidget);
      expect(find.text('CATÉGORIE DE DÉPENSES'), findsOneWidget);
      expect(find.text('PRIX'), findsOneWidget);
      expect(find.text('Montant décaissé (FCFA)'), findsOneWidget);
      // Obligatoire, donc `Text.rich` comme les trois du haut : même piège,
      // même finder. Il était resté en `find.text` et ne trouvait rien.
      expect(find.textContaining('Compte de trésorerie'), findsOneWidget);
      expect(find.text('Reçu / facture (photo)'), findsOneWidget);
      expect(find.text('Enregistrer la dépense'), findsOneWidget);
      expect(find.text('Annuler'), findsOneWidget);
    });

    testWidgets('le montant décaissé est la SOMME des lignes, recalculée', (
      tester,
    ) async {
      await monter(tester);
      await ouvrir(tester);

      // Une seule ligne à l'ouverture : le total part de zéro.
      expect(
        tester.widget<Text>(find.byKey(const Key('depense-total'))).data,
        '0 FCFA',
      );

      await tester.enterText(
        find.byKey(const Key('depense-ligne-montant-0')),
        '15000',
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('depense-total'))).data,
        '15 000 FCFA',
      );

      // Une seconde ligne : le total suit, à la frappe.
      await tester.tap(find.byKey(const Key('depense-ligne-ajouter')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('depense-ligne-montant-1')),
        '8500',
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('depense-total'))).data,
        '23 500 FCFA',
      );

      // Il n'existe AUCUN champ de saisie du montant décaissé : c'est un
      // `Text`, et la règle n° 2 du dépôt en dépend.
      expect(find.byKey(const Key('depense-total')), findsOneWidget);
      expect(
        tester.widget(find.byKey(const Key('depense-total'))),
        isA<Text>(),
      );
    });

    testWidgets('une ligne à moitié tapée est ignorée du total', (
      tester,
    ) async {
      await monter(tester);
      await ouvrir(tester);

      await tester.enterText(
        find.byKey(const Key('depense-ligne-montant-0')),
        '15000',
      );
      await tester.tap(find.byKey(const Key('depense-ligne-ajouter')));
      await tester.pumpAndSettle();

      // La seconde ligne n'a pas de prix : le total ne tombe pas, et ne compte
      // pas cette ligne à zéro non plus.
      expect(
        tester.widget<Text>(find.byKey(const Key('depense-total'))).data,
        '15 000 FCFA',
      );
    });

    testWidgets('une saisie complète est ENREGISTRÉE et apparaît', (
      tester,
    ) async {
      await monter(tester);
      await ouvrir(tester);

      await tester.enterText(
        find.byKey(const Key('depense-libelle')),
        'Marché du matin — Légumes',
      );
      await tester.enterText(
        find.byKey(const Key('depense-ligne-libelle-0')),
        'Tomates fraîches',
      );
      await tester.enterText(
        find.byKey(const Key('depense-ligne-montant-0')),
        '8500',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('depense-ligne-compte-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('6011 — dans la Région').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('depense-ligne-nature-0')));
      await tester.pumpAndSettle();
      // « Marché · Tomate » et non « Tomate » : les intitulés de famille ont
      // quitté l'espace des valeurs du menu, et chaque nature porte désormais
      // sa famille sur sa propre ligne (écart nommé dans `modale_depense`).
      await tester.tap(find.text('Marché · Tomate').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('depense-tresorerie')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Caisse').last);
      await tester.pumpAndSettle();

      // 6011 ne porte aucun centre par défaut : le centre est choisi (RG-12).
      await tester.tap(find.byKey(const Key('depense-centre')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restaurant').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('depense-enregistrer')));
      await tester.pumpAndSettle();

      // La dépense est en base — relue, pas insérée dans la liste affichée.
      final enBase = await dao.depenses();
      expect(enBase, hasLength(1));
      expect(enBase.single.montantTotal, 8500);
      expect(enBase.single.lignes.single.famille, 'Marché');

      // ET sa pièce : deux lignes sous un numéro du journal de caisse, relues
      // de la base, équilibrées, au centre choisi.
      expect(enBase.single.estComptabilisee, isTrue);
      expect(enBase.single.numeroPiece, 'CAI-2026-00001');
      final piece = await ComptabiliteDao(db).lignesDeLaPiece('CAI-2026-00001');
      expect(piece, hasLength(2));
      expect(piece.map((l) => l.debitCentimes).reduce((a, b) => a + b), 850000);
      expect(
        piece.map((l) => l.creditCentimes).reduce((a, b) => a + b),
        850000,
      );
      final restaurant = await centreDe(db, 'Restaurant');
      expect(piece.map((l) => l.centreId), everyElement(restaurant));

      expect(find.byKey(const Key('depenses-succes')), findsOneWidget);
      expect(find.text('Dépense de 8 500 FCFA enregistrée.'), findsOneWidget);
      expect(find.text('Marché du matin — Légumes'), findsOneWidget);
    });

    testWidgets('« Centre de coût » : « Défaut du compte » puis les sept '
        'centres, dans l’ordre de la vue', (tester) async {
      await monter(tester);
      await ouvrir(tester);

      expect(find.text('Centre de coût'), findsOneWidget);
      expect(find.text('Défaut du compte'), findsOneWidget);

      await tester.tap(find.byKey(const Key('depense-centre')));
      await tester.pumpAndSettle();
      // MySQL trie sans tenir compte de la casse : « Restaurant » avant « RH ».
      final ordre = [
        'Bar',
        'Hébergement',
        'Restaurant',
        'RH',
        'Structure',
        'Tourisme',
        'Véhicules',
      ];
      final hauteurs = [
        for (final c in ordre) tester.getTopLeft(find.text(c).last).dy,
      ];
      expect(hauteurs, orderedEquals([...hauteurs]..sort()));
      expect(hauteurs.toSet(), hasLength(7));
    });

    testWidgets('sans centre ni défaut du compte, la pièce est REFUSÉE avec la '
        'phrase du serveur, et RIEN n’est écrit', (tester) async {
      await monter(tester);
      await ouvrir(tester);

      await tester.enterText(
        find.byKey(const Key('depense-libelle')),
        'Marché du matin',
      );
      await tester.enterText(
        find.byKey(const Key('depense-ligne-libelle-0')),
        'Tomates',
      );
      await tester.enterText(
        find.byKey(const Key('depense-ligne-montant-0')),
        '8500',
      );
      await tester.tap(find.byKey(const Key('depense-ligne-compte-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('6011 — dans la Région').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('depense-ligne-nature-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Marché · Tomate').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('depense-tresorerie')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Caisse').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('depense-enregistrer')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('depense-refus')),
                matching: find.byType(Text),
              ),
            )
            .data,
        MessagesComptables.dire('depenses.centre_absent', {'numero': '6011'}),
      );
      // La modale reste ouverte avec la saisie, et la base n'a pas bougé.
      expect(find.byKey(const Key('depense-modale')), findsOneWidget);
      expect(await compter(db, 'depenses_local'), 0);
      expect(await compter(db, 'lignes_depense_local'), 0);
      expect(await compter(db, 'ecritures_local'), 0);
      expect(await compter(db, 'sequences_piece_local'), 0);
    });

    testWidgets('un libellé de ligne manquant NOMME la ligne fautive', (
      tester,
    ) async {
      await monter(tester);
      await ouvrir(tester);

      await tester.enterText(
        find.byKey(const Key('depense-libelle')),
        'Marché du matin',
      );
      await tester.tap(find.byKey(const Key('depense-tresorerie')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Caisse').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('depense-enregistrer')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('depense-refus')), findsOneWidget);
      expect(
        find.text('Ligne 1 : le libellé de l\'achat est obligatoire.'),
        findsOneWidget,
      );
      // Rien n'a été écrit.
      expect(await dao.depenses(), isEmpty);
    });
  });

  group('La pièce comptable se VOIT, et son absence aussi', () {
    testWidgets('le numéro de la pièce du moteur est affiché sur chaque '
        'dépense comptabilisée', (tester) async {
      await semer();
      await monter(tester);

      // Journal de caisse pour l'espèce, journal de banque pour la banque.
      expect(find.text('CAI-2026-00001'), findsOneWidget);
      expect(find.text('BQ-2026-00001'), findsOneWidget);
      expect(
        find.byKey(Key('depense-piece-${(await dao.depenses()).first.id}')),
        findsOneWidget,
      );
    });

    testWidgets('une dépense SANS pièce est dite telle : pastille, bandeau, '
        'indicateur et bouton', (tester) async {
      await semerSansPiece();
      await monter(tester);

      expect(find.text('non comptabilisée'), findsOneWidget);
      expect(find.text('Comptabiliser'), findsOneWidget);
      expect(
        find.text(
          '1 dépense(s) ne portent aucune écriture comptable : elles '
          'manquent au grand livre, à la balance et au compte de résultat '
          'tant que la pièce n\'a pas été passée.',
        ),
        findsOneWidget,
      );
      final carte = find.byKey(const Key('depenses-kpi-sans-ecriture'));
      expect(
        find.descendant(of: carte, matching: find.text('1')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: carte, matching: find.text('à régulariser')),
        findsOneWidget,
      );
      // Elle n'affiche aucun numéro de pièce : elle n'en a pas.
      expect(find.textContaining('CAI-2026'), findsNothing);
    });

    testWidgets('le bandeau porte le select du centre : libellé, option '
        'vide « Choisir un centre » au départ, et les sept centres dans '
        'l’ordre de la vue', (tester) async {
      await semerSansPiece();
      await monter(tester);

      expect(find.text(LibellesRattrapage.centre), findsOneWidget);
      expect(
        find.text(
          'Centre de coût de la pièce (obligatoire pour comptabiliser)',
        ),
        findsOneWidget,
      );
      final liste = find.byKey(const Key('depenses-centre-rattrapage'));
      expect(liste, findsOneWidget);
      // Le bandeau le CONTIENT (comme la vue l.124-131).
      expect(
        find.descendant(
          of: find.byKey(const Key('depenses-bandeau-rattrapage')),
          matching: liste,
        ),
        findsOneWidget,
      );
      // La dépense ne mémorise aucun centre : le choix démarre sur l'option
      // vide, rendue.
      expect(tester.widget<DropdownButton<String>>(liste).value, '');
      expect(
        find.descendant(of: liste, matching: find.text('Choisir un centre')),
        findsOneWidget,
      );

      await tester.ensureVisible(liste);
      await tester.tap(liste);
      await tester.pumpAndSettle();
      final centres = (await ComptabiliteDao(
        db,
      ).centres()).map((c) => c.libelle).toList();
      expect(centres, hasLength(7));
      for (final libelle in centres) {
        expect(find.text(libelle), findsWidgets);
      }
      // L'ordre de la vue : alphabétique sans tenir compte de la casse.
      final ordonnes = [...centres]
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      final hauteurs = [
        for (final libelle in ordonnes)
          tester.getTopLeft(find.text(libelle).last).dy,
      ];
      expect([...hauteurs]..sort(), hauteurs);
    });

    testWidgets('sans dépense à reprendre, ni bandeau ni select', (
      tester,
    ) async {
      await semer();
      await monter(tester);
      expect(
        find.byKey(const Key('depenses-bandeau-rattrapage')),
        findsNothing,
      );
      expect(find.byKey(const Key('depenses-centre-rattrapage')), findsNothing);
    });

    testWidgets('« Comptabiliser » avec le centre CHOISI passe la pièce : '
        'charges ET trésorerie y sont imputées, et l’écran le montre', (
      tester,
    ) async {
      await semerSansPiece();
      // Aucun défaut posé sur le compte : le centre vient du bandeau seul.
      await monter(tester);

      await choisirCentre(tester, 'Tourisme');
      // La police d'essai (Ahem) élargit le tableau au-delà du cadre : on le
      // fait défiler jusqu'au bouton avant de cliquer.
      await tester.ensureVisible(find.text('Comptabiliser'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Comptabiliser'));
      await tester.pumpAndSettle();

      final apres = await dao.depenses();
      expect(apres.single.estComptabilisee, isTrue);
      expect(apres.single.numeroPiece, 'CAI-2026-00001');
      // La pièce porte la date de la dépense (20/08), pas celle du geste.
      final piece = await ComptabiliteDao(db).lignesDeLaPiece('CAI-2026-00001');
      expect(piece, hasLength(2));
      expect(piece.map((l) => l.dateEcriture), everyElement('2026-08-20'));
      expect(piece.map((l) => l.statut.name), everyElement('validee'));
      // Le centre choisi est sur la charge ET sur la trésorerie.
      expect(
        piece.map((l) => l.centreId),
        everyElement(await centreDe(db, 'Tourisme')),
      );

      expect(find.text('non comptabilisée'), findsNothing);
      expect(find.text('Comptabiliser'), findsNothing);
      expect(find.text('CAI-2026-00001'), findsOneWidget);
      expect(
        find.byKey(const Key('depenses-bandeau-rattrapage')),
        findsNothing,
      );
      expect(
        find.text('Dépense CAI-2026-00001 comptabilisée.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'SANS centre choisi, le rattrapage est refusé (RG-12) avec la phrase '
      'du serveur ; choisir un centre puis recliquer aboutit',
      (tester) async {
        await semerSansPiece();
        await monter(tester);

        // La police d'essai (Ahem) élargit le tableau au-delà du cadre : on le
        // fait défiler jusqu'au bouton avant de cliquer.
        await tester.ensureVisible(find.text('Comptabiliser'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Comptabiliser'));
        await tester.pumpAndSettle();

        final phrase = MessagesComptables.dire('depenses.centre_absent', {
          'numero': '6052',
        });
        expect(find.text(phrase), findsOneWidget);
        expect(await compter(db, 'ecritures_local'), 0);
        expect(await compter(db, 'sequences_piece_local'), 0);
        final refusee = (await dao.depenses()).single;
        expect(refusee.estComptabilisee, isFalse);
        // La raison est consignée sur la dépense.
        expect(refusee.ecritureRefus, phrase);
        // Le choix est resté sur « Choisir un centre » : rien n'a été deviné.
        expect(
          tester
              .widget<DropdownButton<String>>(
                find.byKey(const Key('depenses-centre-rattrapage')),
              )
              .value,
          '',
        );

        await choisirCentre(tester, 'Structure');
        await tester.ensureVisible(find.text('Comptabiliser'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Comptabiliser'));
        await tester.pumpAndSettle();

        final faite = (await dao.depenses()).single;
        expect(faite.estComptabilisee, isTrue);
        expect(faite.ecritureRefus, isNull);
        expect(
          (await ComptabiliteDao(
            db,
          ).lignesDeLaPiece('CAI-2026-00001')).map((l) => l.centreId),
          everyElement(await centreDe(db, 'Structure')),
        );
        // Le refus affiché a disparu avec le succès.
        expect(find.text(phrase), findsNothing);
      },
    );

    testWidgets('un rattrapage REFUSÉ dit pourquoi, consigne la raison et '
        'n’écrit rien', (tester) async {
      // Un compte de l'ancien registre à six chiffres : absent du plan.
      await semerSansPiece(compte: '601100');
      await monter(tester);

      await choisirCentre(tester, 'Structure');
      // La police d'essai (Ahem) élargit le tableau au-delà du cadre : on le
      // fait défiler jusqu'au bouton avant de cliquer.
      await tester.ensureVisible(find.text('Comptabiliser'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Comptabiliser'));
      await tester.pumpAndSettle();

      final phrase = MessagesComptables.dire('depenses.compte_inconnu', {
        'numero': '601100',
      });
      expect(find.text(phrase), findsOneWidget);
      expect(await compter(db, 'ecritures_local'), 0);
      expect((await dao.depenses()).single.estComptabilisee, isFalse);
      // La raison est consignée sur la dépense, lue par l'infobulle.
      expect((await dao.depenses()).single.ecritureRefus, phrase);
      final pastille = tester.widget<Tooltip>(
        find
            .ancestor(
              of: find.text('non comptabilisée'),
              matching: find.byType(Tooltip),
            )
            .first,
      );
      expect(pastille.message, phrase);
      // Le bandeau et le bouton restent : la dépense manque toujours au grand
      // livre.
      expect(find.text('Comptabiliser'), findsOneWidget);
      // Et l'ancien libellé du compte reste lisible dans la colonne.
      expect(
        find.textContaining('Achats denrées alimentaires (cuisine)'),
        findsOneWidget,
      );
    });

    testWidgets('en lecture seule sur M10, le bouton « Comptabiliser » est '
        'absent mais la pastille reste', (tester) async {
      await semerSansPiece();
      await monter(tester, droits: const {'M10': 'L'});

      expect(find.text('non comptabilisée'), findsOneWidget);
      expect(find.text('Comptabiliser'), findsNothing);
    });
  });

  group('Les filtres', () {
    testWidgets('la trésorerie ne retient que ses pièces', (tester) async {
      await semer();
      await monter(tester);

      // Les deux dépenses sont là au départ.
      expect(
        find.text('Marché du matin — Légumes & condiments'),
        findsOneWidget,
      );
      expect(
        find.text('Facture d\'électricité SBEE & Eau SONEB'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('depenses-tresorerie')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compte bancaire').last);
      await tester.pumpAndSettle();

      expect(find.text('Marché du matin — Légumes & condiments'), findsNothing);
      expect(
        find.text('Facture d\'électricité SBEE & Eau SONEB'),
        findsOneWidget,
      );

      // Et les indicateurs suivent la liste AFFICHÉE : 45 000 seul, plus rien
      // en caisse.
      expect(find.text('45 000 FCFA'), findsWidgets);
    });

    testWidgets('« Réinitialiser » rend la liste entière', (tester) async {
      await semer();
      await monter(tester);

      await tester.tap(find.byKey(const Key('depenses-tresorerie')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compte bancaire').last);
      await tester.pumpAndSettle();
      expect(find.text('Marché du matin — Légumes & condiments'), findsNothing);

      await tester.tap(find.byKey(const Key('depenses-reinitialiser')));
      await tester.pumpAndSettle();

      expect(
        find.text('Marché du matin — Légumes & condiments'),
        findsOneWidget,
      );
      // La liste déroulante revient à son libellé vide : sans cela, l'écran
      // montrerait tout sous un filtre qui dit encore « Compte bancaire ».
      expect(find.text('Toute trésorerie'), findsOneWidget);
    });

    testWidgets('un filtre sans résultat propose d’élargir', (tester) async {
      await semer();
      await monter(tester);

      await tester.enterText(
        find.byKey(const Key('depenses-recherche')),
        'zzz-introuvable',
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('depenses-vide-filtre')), findsOneWidget);
      expect(find.byKey(const Key('depenses-tout-afficher')), findsOneWidget);
      // L'autre message — celui qui appelle à saisir — ne doit PAS s'afficher :
      // les deux appellent des gestes opposés.
      expect(find.byKey(const Key('depenses-vide')), findsNothing);
    });
  });
}
