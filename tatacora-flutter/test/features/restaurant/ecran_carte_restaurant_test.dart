import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/donnees_absentes.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/restaurant/data/restaurant_api.dart';
import 'package:tatacora_flutter/features/restaurant/domain/entities/carte_restaurant.dart';
import 'package:tatacora_flutter/features/restaurant/presentation/ecran_carte_restaurant.dart';
import 'package:tatacora_flutter/features/restaurant/presentation/providers_restaurant.dart';
import 'package:tatacora_flutter/features/restaurant/presentation/widgets/cadre_ventes_carte.dart';

import '../../support/vue_blade.dart';

/// L'écran Carte du restaurant, monté pour de vrai — Phase 2, 09/10/2026.
///
/// ## Ce que ces cas protègent
///
/// L'ORDRE et la PLACE des blocs de la vue (`pwa/carte/corps.blade.php`), que
/// la carte du bar tient déjà : jusqu'à cette date, l'écran posait « Excel » et
/// « PDF » au lieu de « Exporter », n'avait que deux onglets, et rendait un
/// panneau « Ce que cet écran ne rend pas » que la vue n'a pas. Les mesures de
/// géométrie (`geometrie_blade_test.dart`) le disent en pixels ; ces cas le
/// disent en termes que la revue lit sans ouvrir un relevé.
///
/// Les clés relues ici sont celles de l'écran ; les registres (états de
/// filtre, onglets) sont relus de la SOURCE, jamais recopiés.
void main() {
  LigneCarteRestaurant ligne(
    String id,
    String libelle, {
    bool lie = true,
    int? portions = 4,
  }) => LigneCarteRestaurant(
    id: id,
    libelle: libelle,
    categorieBrute: 'local',
    prixVente: '4500',
    lieAuStock: lie,
    nbIngredients: lie ? 3 : 0,
    portionsVendables: portions,
    ingredientLimitant: lie
        ? const IngredientLimitant(
            id: 'i-1',
            libelle: 'Poulet',
            uniteMesure: 'kg',
          )
        : null,
    motifSansStock: portions == null
        ? MotifSansStock.recetteSansIngredient
        : null,
  );

  CarteRestaurant carte({
    List<LigneCarteRestaurant>? lignes,
    String? pointCuisineId = 'point-cuisine',
  }) {
    final l =
        lignes ??
        [ligne('p-1', 'Poulet DG'), ligne('p-2', 'Riz sauce', lie: false)];

    return CarteRestaurant(
      lignes: l,
      indicateurs: IndicateursCarte(
        plats: l.length,
        lies: l.where((x) => x.lieAuStock).length,
        sansLien: l.where((x) => !x.lieAuStock).length,
        enRupture: 0,
        sousSeuil: 0,
        coutMatiereInconnu: 0,
        tauxCouverture: l.isEmpty ? null : '50',
        absents: const {
          'disponibles': 'Aucune colonne ne porte la disponibilité du jour.',
          'indisponibles': 'Aucune colonne ne porte la disponibilité du jour.',
          'prix_provisoires': 'Le prix provisoire n’est pas lu sur ce poste.',
        },
      ),
      couverture: const [
        CouvertureCategorie(
          categorieBrute: 'local',
          plats: 2,
          lies: 1,
          sansLien: 1,
          taux: '50',
        ),
      ],
      filtresAppliques: const {},
      arreteAu: '2031-01-01',
      pointCuisineId: pointCuisineId,
    );
  }

  Future<void> monter(
    WidgetTester tester, {
    ResultatRestaurant<CarteRestaurant>? resultat,
    List<Override> surcharges = const [],

    /// Une lecture qui DÉPEND d'un filtre, comme la vraie (chaque frappe
    /// relance le fournisseur) — à la place de [resultat].
    Future<ResultatRestaurant<CarteRestaurant>> Function(Ref ref)? lecture,
  }) async {
    tester.view
      ..physicalSize = const Size(1383, 1400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          carteRestaurantProvider.overrideWith(
            (ref) async =>
                await lecture?.call(ref) ?? resultat ?? RestaurantRecu(carte()),
          ),
          ...surcharges,
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranCarteRestaurant()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'les cinq boutons d’en-tête sont ceux de la vue, dans son ordre',
    (tester) async {
      await monter(tester);

      // `corps.blade.php` l.86-141 : liens, Exporter, fiche des prix, puis le
      // lien du catalogue — tous AU-DESSUS des onglets.
      final cles = [
        'carte-restaurant-vers-pos',
        'carte-restaurant-vers-stocks',
        'carte-restaurant-exporter',
        'carte-restaurant-fiche-prix',
        'carte-restaurant-vers-plats',
      ];
      final haut = tester
          .getRect(find.byKey(const Key('onglet-carte-restaurant-carte')))
          .top;
      var gauche = -1.0;
      for (final cle in cles) {
        final boite = tester.getRect(find.byKey(Key(cle)));
        expect(boite.left, greaterThan(gauche), reason: cle);
        gauche = boite.left;
        expect(
          boite.bottom,
          lessThan(haut),
          reason: '$cle précède les onglets',
        );
      }

      // « Excel » et « PDF » étaient deux boutons de l’ancien prototype : la
      // vue n’a qu’un « Exporter », dont la modale choisit le format.
      expect(find.text('Excel'), findsNothing);
      expect(find.text('PDF'), findsNothing);
      expect(find.text('Plats'), findsNothing);
      expect(find.text('Plats, fiches techniques & menus'), findsOneWidget);
    },
  );

  testWidgets('la vue a TROIS onglets, tous cliquables', (tester) async {
    await monter(tester);

    // Un onglet par valeur du registre, relu de la source : en ajouter un à
    // l’énumération sans l’écran ferait échouer ce cas.
    for (final o in OngletCarte.values) {
      expect(
        find.byKey(Key('onglet-carte-restaurant-${o.cle}')),
        findsOneWidget,
        reason: o.libelle,
      );
    }
    // Les trois de la vue (`corps.blade.php` l.213-226), dont l’onglet ajouté
    // par le Product Owner le 03/09/2026.
    expect(
      OngletCarte.values.map((o) => o.libelle),
      contains('Ventes du Restaurant'),
    );
    expect(find.text('Ventes du Restaurant'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('onglet-carte-restaurant-couverture')),
    );
    await tester.pumpAndSettle();
    // Des en-têtes qui n'existent QUE dans le tableau de couverture (les
    // libellés « Liés au stock » et « Prix provisoires » sont aussi ceux de
    // deux cartes d'indicateur).
    expect(find.text('SANS LIEN'), findsOneWidget);
    expect(find.text('INDISPONIBLES'), findsOneWidget);
    expect(find.text('TOTAL'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onglet-carte-restaurant-carte')));
    await tester.pumpAndSettle();
    expect(find.text('STOCK VENDABLE'), findsOneWidget);
  });

  group('l’onglet « Ventes du Restaurant »', () {
    Future<void> ouvrirVentes(WidgetTester tester) async {
      await monter(tester);
      await tester.tap(find.byKey(const Key('onglet-carte-restaurant-ventes')));
      await tester.pumpAndSettle();
    }

    final phraseAbsence = donneeNonDisponible(
      'Les lignes de vente du restaurant',
    );

    testWidgets(
      'rend le CADRE de la vue — titre, neuf colonnes, total — sans un seul chiffre',
      (tester) async {
        await ouvrirVentes(tester);

        // L'état vide dit pourquoi, avec la phrase UNIQUE de l'écran des
        // données absentes, et ne prétend pas qu'un filtre n'a rien retenu.
        final message = tester.widget<Text>(
          find.byKey(const Key('carte-restaurant-ventes-absentes')),
        );
        expect(message.data, phraseAbsence);
        expect(
          find.text('Aucune ligne de vente ne correspond à ces critères.'),
          findsNothing,
          reason: 'cette phrase affirme qu’un filtre a été appliqué',
        );

        // Le compteur de la vue (`ventes_compteur`), avec des tirets : un
        // « 0 ligne(s) · Total validé : 0 FCFA » dirait « aucune vente ».
        expect(find.text('— ligne(s) · Total validé : —'), findsOneWidget);
        expect(find.textContaining('0 ligne(s)'), findsNothing);
        expect(find.text('0 FCFA'), findsNothing);
        // La note sur le stock (`ventes_stock_aide`), dans l'en-tête du cadre.
        expect(find.text(TextesVentesCarte.stockAide), findsOneWidget);

        // La ligne de total existe et vaut « — ».
        expect(find.text('TOTAL DE LA PAGE'), findsOneWidget);
        expect(find.text(TextesVentesCarte.totalPageAide), findsOneWidget);
        // La pagination numérote des lignes qui n'existent pas : refusée.
        expect(find.textContaining('Affichage de'), findsNothing);
      },
    );

    testWidgets('les neuf colonnes sont celles de la vue, dans son ordre', (
      tester,
    ) async {
      await ouvrirVentes(tester);

      // L'ordre de la vue (`corps.blade.php` l.619-627), RELU de la langue
      // servie par la PWA : une liste recopiée ici ne vérifierait qu'elle-même.
      final attendues = [
        for (final cle in const [
          'date',
          'ticket',
          'article',
          'stock',
          'prix',
          'quantite',
          'montant',
          'statut',
          'utilisateur',
        ])
          VueBlade.libelle('carte_pwa.commun.ventes_col_$cle')!.toUpperCase(),
      ];
      expect(attendues, hasLength(9));
      expect(
        colonnesVentesCarte.map((c) => c.titre.toUpperCase()).toList(),
        attendues,
      );

      // À l'écran : une seule rangée, de gauche à droite.
      final boites = [
        for (final titre in attendues) tester.getRect(find.text(titre)),
      ];
      for (var i = 1; i < boites.length; i++) {
        expect(
          boites[i].left,
          greaterThan(boites[i - 1].left),
          reason: attendues[i],
        );
        expect(boites[i].top, boites[0].top, reason: attendues[i]);
      }
    });

    testWidgets(
      'les blocs sont dans l’ordre de la vue : filtres, cadre, total',
      (tester) async {
        await ouvrirVentes(tester);

        double haut(Finder f) => tester.getRect(f).top;
        final ordre = [
          haut(find.byKey(const Key('carte-restaurant-ventes-recherche'))),
          haut(find.text(TextesVentesCarte.bornesAide)),
          haut(find.text('— ligne(s) · Total validé : —')),
          haut(find.text('DATE')),
          haut(find.byKey(const Key('carte-restaurant-ventes-absentes'))),
          haut(find.text('TOTAL DE LA PAGE')),
        ];
        for (var i = 1; i < ordre.length; i++) {
          expect(ordre[i], greaterThan(ordre[i - 1]), reason: 'bloc $i');
        }
      },
    );

    for (final cle in const [
      'carte-restaurant-ventes-du',
      'carte-restaurant-ventes-au',
    ]) {
      testWidgets('le champ $cle dit pourquoi il ne choisit aucune date', (
        tester,
      ) async {
        await ouvrirVentes(tester);

        await tester.tap(find.byKey(Key(cle)));
        await tester.pump();

        expect(
          tester
              .widget<Text>(
                find.byKey(
                  const Key('carte-restaurant-ventes-filtre-indisponible'),
                ),
              )
              .data,
          phraseAbsence,
        );
      });
    }

    testWidgets('la recherche est en lecture seule et dit pourquoi', (
      tester,
    ) async {
      await ouvrirVentes(tester);

      final champ = tester.widget<TextField>(
        find.byKey(const Key('carte-restaurant-ventes-recherche')),
      );
      expect(champ.readOnly, isTrue);
      expect(champ.decoration?.hintText, TextesVentesCarte.recherche);

      await tester.tap(
        find.byKey(const Key('carte-restaurant-ventes-recherche')),
      );
      await tester.pump();
      expect(
        tester
            .widget<Text>(
              find.byKey(
                const Key('carte-restaurant-ventes-filtre-indisponible'),
              ),
            )
            .data,
        phraseAbsence,
      );
    });

    testWidgets(
      'choisir un statut le dit et NE change PAS la valeur affichée',
      (tester) async {
        await ouvrirVentes(tester);

        await tester.tap(
          find.byKey(const Key('carte-restaurant-ventes-statut')),
        );
        await tester.pumpAndSettle();
        // Les trois options de la vue (`ventes_tous_statuts`, `…_validee`,
        // `…_annulee`).
        expect(find.text('Validée'), findsOneWidget);
        await tester.tap(find.text('Annulée').last);
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<Text>(
                find.byKey(
                  const Key('carte-restaurant-ventes-filtre-indisponible'),
                ),
              )
              .data,
          phraseAbsence,
        );
        // Une liste qui afficherait « Annulée » sous un tableau qui ne filtre
        // rien affirmerait un état qu'elle n'a pas vérifié.
        final liste = tester.widget<DropdownButton<String>>(
          find.byKey(const Key('carte-restaurant-ventes-statut')),
        );
        expect(liste.value, '');
        expect(find.text('Tous les statuts'), findsOneWidget);
      },
    );
  });

  group('la conclusion de l’onglet « Couverture du stock »', () {
    testWidgets(
      '« Couverture complète. » : le titre et le texte sont DEUX éléments, sur une ligne',
      (tester) async {
        await monter(
          tester,
          resultat: RestaurantRecu(carte(lignes: [ligne('p-1', 'Poulet DG')])),
        );
        await tester.tap(
          find.byKey(const Key('onglet-carte-restaurant-couverture')),
        );
        await tester.pumpAndSettle();

        // Les mots de la vue (`couverture_complete_titre`, `…_texte`).
        final titre = VueBlade.libelle(
          'carte_pwa.commun.couverture_complete_titre',
        )!;
        final texte = VueBlade.libelle(
          'carte_pwa.commun.couverture_complete_texte',
        )!;
        final boiteTitre = tester.getRect(find.text(titre));
        final boiteTexte = tester.getRect(find.text(texte));

        expect(boiteTexte.left, greaterThan(boiteTitre.right));
        expect((boiteTexte.top - boiteTitre.top).abs(), lessThan(1));
        expect(
          find.byKey(const Key('couverture-restaurant-avertissement')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'l’avertissement ambre reste UN seul paragraphe : le texte enchaîne le titre',
      (tester) async {
        await monter(tester);
        await tester.tap(
          find.byKey(const Key('onglet-carte-restaurant-couverture')),
        );
        await tester.pumpAndSettle();

        final textes = find.descendant(
          of: find.byKey(const Key('couverture-restaurant-avertissement')),
          matching: find.byType(Text),
        );
        expect(textes, findsOneWidget);
        final brut = tester.widget<Text>(textes).textSpan!.toPlainText();
        expect(
          brut,
          startsWith(
            '1 article(s) ne décrémentent rien à la vente. Chaque vente',
          ),
        );
      },
    );
  });

  testWidgets('le bandeau est SOUS les filtres, et reprend le texte de la vue', (
    tester,
  ) async {
    await monter(tester);

    final onglets = tester.getRect(
      find.byKey(const Key('onglet-carte-restaurant-carte')),
    );
    final filtres = tester.getRect(
      find.byKey(const Key('carte-restaurant-recherche')),
    );
    final bandeau = tester.getRect(
      find.byKey(const Key('carte-restaurant-bandeau')),
    );

    expect(onglets.top, lessThan(filtres.top));
    expect(filtres.bottom, lessThan(bandeau.top));

    // Le texte de la VUE (`carte_pwa.restaurant.bandeau_texte`), dont le compte
    // vient des indicateurs reçus : 1 plat sans fiche sur 2.
    final texte = tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(const Key('carte-restaurant-bandeau')),
            matching: find.byType(Text),
          ),
        )
        .textSpan!
        .toPlainText();
    expect(texte, contains("Un plat n'est pas un article de stock"));
    expect(texte, contains('1 article(s) sur 2 ne décrémentent rien'));
    expect(texte, contains('Un plat peut néanmoins être rattaché à la main'));
  });

  testWidgets(
    'la bande compte SIX cartes, sur une seule rangée en grand écran',
    (tester) async {
      await monter(tester);

      const cles = [
        'carte-restaurant-kpi-articles',
        'carte-restaurant-kpi-retires',
        'carte-restaurant-kpi-lies',
        'carte-restaurant-kpi-sans-lien',
        'carte-restaurant-kpi-rupture',
        'carte-restaurant-kpi-provisoires',
      ];
      final hauts = {
        for (final c in cles) tester.getRect(find.byKey(Key(c))).top,
      };
      expect(hauts, hasLength(1), reason: 'une seule rangée à 1 383 px');
    },
  );

  testWidgets(
    'un indicateur sans source rend « — » et sa raison, jamais « 0 »',
    (tester) async {
      await monter(tester);

      for (final cle in [
        'carte-restaurant-kpi-retires',
        'carte-restaurant-kpi-provisoires',
      ]) {
        final carteKpi = find.byKey(Key(cle));
        expect(
          find.descendant(of: carteKpi, matching: find.text('—')),
          findsOneWidget,
          reason: cle,
        );
        expect(
          find.descendant(of: carteKpi, matching: find.text('0')),
          findsNothing,
          reason: '$cle ne doit jamais afficher un zéro plausible',
        );
      }
      // La raison est une INFOBULLE : le « — » reste seul à l'écran (la vue n'a
      // pas de ligne de plus), et le survol dit pourquoi.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Tooltip &&
              (w.message ?? '').contains(
                'Aucune colonne ne porte la disponibilité',
              ),
        ),
        findsWidgets,
      );
    },
  );

  testWidgets('le tableau suit les colonnes de la vue, en capitales', (
    tester,
  ) async {
    await monter(tester);

    for (final entete in [
      'ARTICLE',
      'CATÉGORIE',
      'PRIX',
      'DISPONIBLE',
      'ARTICLE DE STOCK',
      'STOCK VENDABLE',
      'RÉSERVE',
    ]) {
      expect(find.text(entete), findsOneWidget, reason: entete);
    }
    // La colonne d’actions n’a PAS d’entête (`<th class="px-3 py-2.5"></th>`).
    expect(find.text('ACTIONS'), findsNothing);
    expect(tester.takeException(), isNull, reason: 'aucun débordement');
  });

  testWidgets(
    '« Disponible » et « Réserve » rendent « — » : aucune source, aucun faux oui/non',
    (tester) async {
      await monter(tester);

      expect(
        find.byKey(const Key('carte-restaurant-disponible-inconnu')),
        findsNWidgets(2),
      );
      expect(
        find.byKey(const Key('carte-restaurant-reserve-inconnue')),
        findsNWidgets(2),
      );
      expect(find.text('oui'), findsNothing);
      expect(find.text('non'), findsNothing);
    },
  );

  // Les quatre boutons de ligne, avec le message EXACT que chacun doit dire :
  // une écriture refusée (`ecritureNonDisponible`) ou une lecture absente
  // (`donneeNonDisponible`). Un message vide, ou remplacé par « Aucun
  // changement », se lirait comme un geste réussi ou une liste vide.
  final boutons = <(String, String)>[
    (
      'carte-restaurant-rendre-indispo-p-1',
      ecritureNonDisponible('Le retrait de la carte du jour'),
    ),
    ('carte-restaurant-lier-p-1', ecritureNonDisponible('Le lien au stock')),
    ('carte-restaurant-prix-p-1', ecritureNonDisponible('Le nouveau prix')),
    (
      'carte-restaurant-historique-prix-p-1',
      donneeNonDisponible('Les changements de prix'),
    ),
  ];

  for (final (cle, message) in boutons) {
    testWidgets('le bouton $cle dit exactement pourquoi il ne peut pas', (
      tester,
    ) async {
      await monter(tester);

      // La colonne d'actions est la dernière du tableau, qui défile en
      // horizontal comme celui de la vue (`overflow-x-auto`, l.310).
      await tester.ensureVisible(find.byKey(Key(cle)));
      await tester.tap(find.byKey(Key(cle)));
      await tester.pump();

      expect(find.text(message), findsOneWidget);
      expect(find.textContaining('Aucun changement'), findsNothing);
    });
  }

  testWidgets(
    'une carte vide rend l’état vide de la vue, pas un tableau blanc',
    (tester) async {
      await monter(tester, resultat: RestaurantRecu(carte(lignes: const [])));

      expect(find.byKey(const Key('carte-restaurant-vide')), findsOneWidget);
      expect(
        find.text('Aucun article ne correspond à ces critères.'),
        findsOneWidget,
      );
      expect(find.text('ARTICLE'), findsNothing);
    },
  );

  testWidgets(
    'sans point « cuisine », l’écran le dit au lieu d’afficher des zéros',
    (tester) async {
      await monter(
        tester,
        resultat: RestaurantRecu(carte(pointCuisineId: null)),
      );

      expect(
        find.byKey(const Key('carte-restaurant-sans-point-cuisine')),
        findsOneWidget,
      );
      expect(find.textContaining('de type « cuisine »'), findsOneWidget);
    },
  );

  testWidgets(
    'les états de filtre sans schéma restent visibles et non choisissables',
    (tester) async {
      await monter(tester);

      await tester.tap(find.byKey(const Key('carte-restaurant-filtre-etat')));
      await tester.pumpAndSettle();

      // Le registre est relu de la source : un état ajouté demain sera vérifié
      // sans toucher à ce test.
      for (final e in EtatArticleCarte.values) {
        final items = tester
            .widgetList<DropdownMenuItem<EtatArticleCarte>>(
              find.byWidgetPredicate(
                (w) => w is DropdownMenuItem<EtatArticleCarte> && w.value == e,
              ),
            )
            .toList();
        expect(items, isNotEmpty, reason: '${e.libelle} reste dans la liste');
        expect(
          items.every((i) => i.enabled == e.servi),
          isTrue,
          reason:
              '« ${e.libelle} » : choisissable seulement si le serveur le sert',
        );
      }
      expect(
        EtatArticleCarte.values.any((e) => !e.servi),
        isTrue,
        reason: 'sans état refusé, ce cas ne prouverait rien',
      );
    },
  );

  testWidgets('taper dans la recherche ne remplace pas la page par une roue', (
    tester,
  ) async {
    await monter(
      tester,
      // Une lecture qui DÉPEND de la recherche et qui PREND DU TEMPS, comme la
      // vraie : chaque frappe relance le fournisseur, et pendant la relecture
      // il est en chargement. Sans délai, l'état de chargement ne durerait pas
      // une image et le cas ne verrait rien.
      lecture: (ref) async {
        ref.watch(rechercheCarteRestaurantProvider);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return RestaurantRecu(carte());
      },
    );

    await tester.enterText(
      find.byKey(const Key('carte-restaurant-recherche')),
      'poul',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // Pendant la relecture, la barre de filtres est toujours là, texte compris,
    // et aucune roue ne remplace la page.
    expect(find.byKey(const Key('carte-restaurant-recherche')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpAndSettle();

    final champ = tester.widget<TextField>(
      find.byKey(const Key('carte-restaurant-recherche')),
    );
    expect(champ.controller!.text, 'poul');
  });

  group('« Exporter »', () {
    testWidgets('porte sur le tableau AFFICHÉ et dit son filtre', (
      tester,
    ) async {
      List<LigneCarteRestaurant>? recues;
      String? filtre;
      await monter(
        tester,
        resultat: RestaurantRecu(
          CarteRestaurant(
            lignes: carte().lignes,
            indicateurs: carte().indicateurs,
            couverture: const [],
            filtresAppliques: const {'categorie': 'local'},
            arreteAu: '2031-01-01',
            pointCuisineId: 'pc',
          ),
        ),
        surcharges: [
          exporterCarteRestaurantPdfProvider.overrideWithValue((
            lignes,
            f,
          ) async {
            recues = lignes;
            filtre = f;
            return 'C:/Documents/carte_restaurant.pdf';
          }),
        ],
      );

      await tester.tap(find.byKey(const Key('carte-restaurant-exporter')));
      await tester.pumpAndSettle();
      expect(find.text('Exporter — Carte du restaurant'), findsOneWidget);
      await tester.tap(find.byKey(const Key('export-generer')));
      await tester.pumpAndSettle();

      expect(recues, isNotNull);
      expect(recues!.map((l) => l.id), ['p-1', 'p-2']);
      expect(filtre, contains('categorie : local'));
      // L'issue est DITE par le toast commun (14/10/2026).
      expect(find.text('Export enregistré : carte_restaurant.pdf'), findsOne);
    });

    testWidgets('une liste vide se REFUSE, avec la phrase de la vue', (
      tester,
    ) async {
      var appele = false;
      await monter(
        tester,
        resultat: RestaurantRecu(carte(lignes: const [])),
        surcharges: [
          exporterCarteRestaurantPdfProvider.overrideWithValue((_, _) async {
            appele = true;
            return 'jamais.pdf';
          }),
        ],
      );

      await tester.tap(find.byKey(const Key('carte-restaurant-exporter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-generer')));
      await tester.pumpAndSettle();

      expect(appele, isFalse, reason: 'aucune page blanche n’est produite');
      expect(
        find.byKey(const Key('carte-restaurant-export-vide')),
        findsOneWidget,
      );
    });

    testWidgets('sur l’onglet Ventes, il dit que la donnée est absente', (
      tester,
    ) async {
      await monter(tester);
      await tester.tap(find.byKey(const Key('onglet-carte-restaurant-ventes')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('carte-restaurant-exporter')));
      await tester.pumpAndSettle();

      // La modale NOMME l'onglet exporté (vue : `export_titre_ventes`), et ne
      // porte pas le titre de la carte.
      expect(find.text('Exporter — Ventes du Restaurant'), findsOneWidget);
      expect(find.text('Exporter — Carte du restaurant'), findsNothing);
      await tester.tap(find.byKey(const Key('export-generer')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('carte-restaurant-export-ventes-absentes')),
            )
            .data,
        donneeNonDisponible('Les lignes de vente du restaurant'),
      );
      // Aucun fichier, aucun document : le refus tombe après le choix.
      expect(find.byKey(const Key('export-generer')), findsNothing);
    });

    testWidgets('sur l’onglet Carte, la modale porte le titre de la carte', (
      tester,
    ) async {
      await monter(tester);

      await tester.tap(find.byKey(const Key('carte-restaurant-exporter')));
      await tester.pumpAndSettle();

      expect(find.text('Exporter — Carte du restaurant'), findsOneWidget);
      expect(find.text('Exporter — Ventes du Restaurant'), findsNothing);
    });
  });

  group('sans donnée du serveur', () {
    testWidgets('la coquille reste, avec la raison, et aucun chiffre', (
      tester,
    ) async {
      await monter(
        tester,
        resultat: const RestaurantRefuse<CarteRestaurant>(
          motif: 'La carte et les fiches du restaurant (M4) ne figurent pas.',
        ),
      );

      expect(find.text('Carte du restaurant'), findsOneWidget);
      expect(find.byKey(const Key('carte-restaurant-refus')), findsOneWidget);
      expect(
        find.byKey(const Key('carte-restaurant-kpi-articles')),
        findsNothing,
      );
      expect(find.byKey(const Key('carte-restaurant-bandeau')), findsNothing);
    });

    testWidgets(
      'les boutons de document disent pourquoi ils ne produisent rien',
      (tester) async {
        await monter(
          tester,
          resultat: const RestaurantRefuse<CarteRestaurant>(
            motif: 'Motif du refus affiché tel quel.',
          ),
        );

        await tester.tap(find.byKey(const Key('carte-restaurant-fiche-prix')));
        await tester.pump();
        expect(
          find.byKey(const Key('carte-restaurant-fiche-indisponible')),
          findsOneWidget,
        );
      },
    );
  });
}
