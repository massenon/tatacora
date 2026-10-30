import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/restaurant/data/restaurant_api.dart';
import 'package:tatacora_flutter/features/restaurant/domain/entities/carte_restaurant.dart';
import 'package:tatacora_flutter/features/restaurant/domain/entities/plat.dart';

import '../../support/vue_blade.dart';

/// Les gardes de conformité de M4.
///
/// ## Elles relisent des SOURCES EXTÉRIEURES, jamais des constantes recopiées
///
/// Quatre sources, et **aucune n'appartient à ce dépôt Flutter** :
///
///  - les deux **vues Blade** de la PWA — le maître du client Flutter depuis
///    PA-182/PA-183, `prototype_v2/` étant une ancienne version —,
///    `pwa/restaurant/carte.blade.php` (dont le corps partagé
///    `pwa/carte/corps.blade.php`) et `pwa/restaurant/restauration.blade.php`,
///    avec leurs classes Livewire (`app/Pwa/Livewire/Restaurant/`, trait
///    `Concerns/EcranDeCarte`) ;
///  - les **bascules système** de la PWA, `app/Shared/Parametres/Services/
///    OptionsSystemeService.php`, qui décident si supprimer s'affiche ;
///  - les ***FormRequest* et les *Service* du serveur**,
///    `tatacora-api/app/Domain/Restaurant/`, pour ce que l'API accepte et
///    refuse réellement ;
///  - les **routes** du serveur, `tatacora-api/routes/api.php`, pour ce qui
///    existe et ce qui n'existe pas.
///
/// Un test qui figerait `'disponible'` dans une liste écrite ici ne vérifierait
/// que lui-même, et resterait vert le jour où la colonne entrerait au schéma —
/// c'est-à-dire le jour où il compterait (piège 12).
///
/// ## ⚠ Une partie de ces gardes porte sur un corps HTTP qui n'existe plus
///
/// Depuis le 09/10/2026 (M4 local, schéma v14), `SaisiePlat.versJson` ne part
/// vers aucun serveur : le poste ne parle à aucune API. Les cas qui confrontent
/// ce corps aux *FormRequest* (champs interdits, champs exigés) restent
/// conservés et verts — ils disent encore ce que le SERVEUR accepte —, mais leur
/// prémisse (« ce corps est envoyé ») est périmée. Même cas que la garde de M6
/// (D129 a) et celle de M7 (D143 a) ; les gardes de ce poste sont ailleurs :
/// `restaurant_local_test.dart` (phrases du serveur relues par PHP),
/// `carte_contre_serveur_test.dart` (le VRAI `CarteRestaurantService` rejoué).
///
/// ## Elles ÉCHOUENT si la source manque, elles ne sautent pas
///
/// Et chaque extraction vérifie qu'elle a **réellement trouvé quelque chose** :
/// une expression régulière qui ne correspond plus rendrait une liste vide,
/// donc un test vert qui n'a rien regardé (piège 4).
void main() {
  /* ================================================================== */
  /* Lecture des sources extérieures                                     */
  /* ================================================================== */

  /// Le texte d'un écran de la PWA : ses vues Blade et ses classes Livewire,
  /// libellés résolus — BRUT (les invites vivent dans des attributs
  /// `placeholder`) PLUS sa version sans balises (une phrase coupée par un
  /// `<strong>` se lit d'un tenant).
  String ecranBlade(List<String> vues, List<String> classes) {
    final brut = [
      // COMMENTAIRES Blade retirés : ils citent les mots de l'ancien
      // prototype, et un libellé qui n'existe qu'en commentaire n'est pas
      // affiché.
      for (final v in vues)
        VueBlade.resolue(v).replaceAll(RegExp(r'\{\{--[\s\S]*?--\}\}'), ' '),
      for (final c in classes)
        VueBlade.resoudre(
          VueBlade.fichier(c, role: 'une classe Livewire de l’écran'),
        ),
    ].join('\n');
    return _normaliser('$brut\n${brut.replaceAll(RegExp(r'<[^>]*>'), '')}');
  }

  String maitreCarte() => ecranBlade(
    const ['restaurant/carte', 'carte/corps'],
    const [
      'app/Pwa/Livewire/Restaurant/CarteRestaurant.php',
      'app/Pwa/Livewire/Concerns/EcranDeCarte.php',
    ],
  );

  String maitreRestauration() => ecranBlade(
    const ['restaurant/restauration'],
    const ['app/Pwa/Livewire/Restaurant/Restauration.php'],
  );

  String serveur(String relatif) => VueBlade.fichier(
    'app/Domain/Restaurant/$relatif',
    role: 'la règle que l’API applique réellement',
  );

  String routes() => VueBlade.fichier(
    'routes/api.php',
    role: 'la liste des verbes que l’API expose réellement',
  );

  /// Les chaînes d'un `const NOM = [...]` PHP.
  List<String> constantePhp(String source, String nom) {
    final debut = source.indexOf('const $nom');
    if (debut < 0) {
      fail(
        'La constante $nom a disparu de la source du serveur. Ce test ne peut '
        'plus rien confronter : vérifiez si la règle a été renommée ou '
        'supprimée, ce qui changerait ce que l’API accepte.',
      );
    }
    final ouvrante = source.indexOf('[', debut);
    final fermante = source.indexOf('];', ouvrante);
    if (ouvrante < 0 || fermante < 0) {
      fail(
        'La constante $nom n’a plus la forme attendue (const $nom = [...]).',
      );
    }

    return RegExp("'([a-z_]+)'")
        .allMatches(source.substring(ouvrante, fermante))
        .map((m) => m.group(1)!)
        .toList();
  }

  /// Le code source de TOUS les fichiers Dart de M4, normalisé.
  ///
  /// Les littéraux adjacents sont **recollés** et les suites d'espaces réduites
  /// à un seul : sans cela, une phrase de la vue coupée en trois lignes de Dart
  /// ne serait jamais retrouvée, et le balayage passerait à vide.
  String codeDart() {
    final racine = Directory('lib/features/restaurant');
    if (!racine.existsSync()) {
      fail(
        'Le dossier lib/features/restaurant a disparu : ce test ne mesure '
        'rien.',
      );
    }

    final fichiers = racine
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    // Plancher : un dossier renommé rendrait le balayage vide, donc vert.
    expect(
      fichiers.length,
      greaterThanOrEqualTo(10),
      reason:
          'seuls ${fichiers.length} fichiers Dart de M4 ont été relus : le '
          'balayage ne couvre plus la fonctionnalité',
    );

    final tout = fichiers.map((f) => f.readAsStringSync()).join('\n');
    return _normaliser(tout.replaceAll(RegExp(r"'\s*\n\s*'"), ''));
  }

  /* ================================================================== */
  group('Ce que le serveur REFUSE, le client ne le soumet pas', () {
    test('aucun champ interdit n’entre dans le corps d’un plat', () {
      // Le serveur déclare `prohibited` des champs que l'ancien prototype
      // posait en saisie. Les envoyer ferait échouer l'enregistrement en 422
      // à tous les coups.
      final refuses = constantePhp(
        serveur('Http/Requests/EnregistrerPlatRequest.php'),
        'CHAMPS_REFUSES',
      );

      expect(
        refuses,
        isNotEmpty,
        reason:
            'extraction vide : le motif ne mord plus, et ce test passerait à '
            'vide donc vert',
      );
      expect(
        refuses,
        containsAll(<String>[
          'disponible',
          'categorie',
          'ingredients_principaux',
        ]),
      );

      // Le corps réellement envoyé, construit par le domaine — jamais une
      // liste recopiée dans ce test.
      final corps = corpsEnvoye();

      for (final champ in refuses) {
        expect(
          corps.containsKey(champ),
          isFalse,
          reason:
              '`$champ` est `prohibited` côté serveur et pourtant soumis : '
              'l’enregistrement serait refusé en 422 à tous les coups',
        );
      }
    });

    test('les deux champs que le serveur EXIGE sont soumis', () {
      // Sans eux, aucun plat ne peut être créé — le formulaire serait une
      // décoration.
      final regles = serveur('Http/Requests/EnregistrerPlatRequest.php');

      for (final champ in ['menu_id', 'recette_id']) {
        expect(
          RegExp("'$champ' => \\['required'").hasMatch(regles),
          isTrue,
          reason:
              '`$champ` n’est plus `required` côté serveur : la raison qui '
              'justifie les deux sélecteurs du formulaire a changé, et un motif '
              'de dérogation périmé transforme une décision en oubli (PA-144)',
        );
        expect(corpsEnvoye().containsKey(champ), isTrue);
      }
    });

    test('les filtres d’état SANS SCHÉMA ne sont jamais envoyés', () {
      final sansSchema = constantePhp(
        serveur('Services/CarteRestaurantService.php'),
        'ETATS_SANS_SCHEMA',
      );
      final servis = constantePhp(
        serveur('Services/CarteRestaurantService.php'),
        'ETATS',
      );

      expect(sansSchema, isNotEmpty);
      expect(servis, isNotEmpty);

      for (final e in EtatArticleCarte.values) {
        if (e.code.isEmpty) continue;

        if (sansSchema.contains(e.code)) {
          expect(
            e.servi,
            isFalse,
            reason:
                '« ${e.libelle} » est marqué servi alors que le serveur le '
                'refuse : l’écran l’enverrait et l’appel entier échouerait '
                'en 422',
          );
        } else {
          expect(
            servis.contains(e.code),
            isTrue,
            reason:
                '`${e.code}` n’est ni servi ni refusé par le serveur : le '
                'registre du client a divergé du sien',
          );
          expect(e.servi, isTrue);
        }
      }
    });

    test('le registre des catégories est celui du serveur', () {
      final types = constantePhp(serveur('Models/Menu.php'), 'TYPES');

      expect(types, isNotEmpty);
      expect(
        CategoriePlat.values.map((c) => c.code).toList(),
        equals(types),
        reason:
            'le registre des catégories du client a divergé de `Menu::TYPES` : '
            'un filtre inconnu serait rejeté en 422, ou une catégorie du '
            'serveur n’apparaîtrait dans aucun filtre et passerait pour vide',
      );
    });
  });

  /* ================================================================== */
  group('Ce que l’API N’EXPOSE PAS, l’écran ne le propose pas', () {
    test('aucune route DELETE n’existe sur le groupe restaurant', () {
      final source = routes();
      final debut = source.indexOf("Route::prefix('restaurant')");
      expect(
        debut,
        greaterThan(0),
        reason:
            'le groupe de routes du restaurant a disparu : ce test ne mesure '
            'plus rien',
      );
      // La borne : le groupe suivant. Sans elle, on lirait les DELETE des
      // autres modules et le test passerait pour la mauvaise raison.
      final fin = source.indexOf('M6 — Stocks', debut);
      expect(fin, greaterThan(debut));

      final groupe = source.substring(debut, fin);
      expect(
        RegExp(r'Route::delete').hasMatch(groupe),
        isFalse,
        reason:
            'une route DELETE est apparue sur M4 : la raison écrite dans '
            '`ecran_restauration.dart` pour ne pas rendre la modale de '
            'suppression a cessé d’être vraie, et un motif périmé transforme '
            'une décision en oubli (PA-144)',
      );

      // Le client ne doit exposer aucun verbe de suppression non plus.
      expect(
        RegExp(r'_dio\.delete').hasMatch(codeDart()),
        isFalse,
        reason:
            'le client appelle DELETE sur une API qui n’expose aucun verbe de '
            'suppression : chaque appel serait un 405',
      );
    });

    test('aucune route d’import en lot n’existe', () {
      final source = routes();
      final debut = source.indexOf("Route::prefix('restaurant')");
      final fin = source.indexOf('M6 — Stocks', debut);
      final groupe = source.substring(debut, fin);

      expect(
        RegExp(r'import').hasMatch(groupe),
        isFalse,
        reason:
            'une route d’import est apparue : le bouton « Importer » peut '
            'désormais faire quelque chose, et son refus doit être rouvert',
      );
    });

    test('le catalogue n’exporte, n’importe ni n’actualise : sa vue non plus', () {
      // PA-185 (11/09/2026) : la barre d'outils du moteur CRUD de l'ancien
      // prototype (Actualiser, Importer, Exporter) a été retirée du client,
      // parce que la vue du catalogue n'en porte AUCUN. Si la vue en gagnait
      // un, ce cas rougirait : le client devrait alors le porter.
      final vue = VueBlade.brute('restaurant/restauration');
      for (final absent in ['modale-export', 'ouvrirExport', 'ouvrirImport']) {
        expect(
          vue.contains(absent),
          isFalse,
          reason:
              'la vue du catalogue offre désormais `$absent` : le client doit '
              'le porter (il l’a retiré le 11/09/2026 parce qu’elle ne l’avait '
              'pas)',
        );
      }

      final code = codeDart();
      for (final retire in [
        'restauration-exporter',
        'restauration-importer',
        'restauration-actualiser',
        'EtatCataloguePlats',
      ]) {
        expect(
          code.contains(retire),
          isFalse,
          reason:
              '`$retire` est revenu dans le code de M4 alors que la vue du '
              'catalogue ne le porte pas (Article 1, interdit 07)',
        );
      }
    });
  });

  /* ================================================================== */
  group('Les libellés viennent de la vue Blade, au caractère près', () {
    test('la carte du restaurant porte les phrases de sa vue', () {
      final maitre = maitreCarte();
      final code = codeDart();

      const phrases = [
        'Carte du restaurant',
        'Rechercher un article',
        'Toutes les catégories',
        'Retirés du jour',
        'Liés au stock',
        'Sans lien de stock',
        'En rupture de stock',
        'Prix provisoire',
        'Point de vente',
        'Imprimer la fiche des prix',
        'Carte du jour',
        'Couverture du stock',
      ];

      for (final phrase in phrases) {
        final attendu = _normaliser(phrase);
        expect(
          maitre.contains(attendu),
          isTrue,
          reason:
              '« $phrase » n’est plus dans la vue : c’est la PWA qui a '
              'changé, pas le portage. Relisez-la avant de corriger le code.',
        );
        expect(
          code.contains(attendu),
          isTrue,
          reason: '« $phrase » a disparu du code de M4',
        );
      }
    });

    test('le catalogue porte les phrases de sa vue', () {
      final maitre = maitreRestauration();
      final code = codeDart();

      // PA-185 (11/09/2026) : les mots du moteur CRUD de l'ancien prototype
      // — « Données actualisées. », la modale d'export (« Le fichier CSV… »,
      // « Télécharger tous les résultats filtrés (.csv) »), « Enregistrer les
      // modifications », « Ajouter plat » — ont quitté le client, parce que la
      // vue ne les porte pas. Ceux-ci sont les mots de la VUE.
      const phrases = [
        'Restaurant & Cuisine',
        'Rechercher un plat...',
        'Toutes les catégories',
        'Prix de vente (FCFA)',
        'Nom du plat',
        'Ex. Poulet DG',
        'Ingrédients principaux',
        'Aucun résultat',
        'Essayez de modifier votre recherche ou vos filtres.',
        'Nouveau plat',
        'Modifier le plat',
        'Enregistrer',
        'Affichage de',
      ];

      for (final phrase in phrases) {
        final attendu = _normaliser(phrase);
        expect(
          maitre.contains(attendu),
          isTrue,
          reason:
              '« $phrase » n’est pas dans la vue du catalogue : le client emploie '
              'un mot que la PWA n’écrit pas (réinterprétation), ou la PWA a '
              'changé — relisez-la avant de corriger le code.',
        );
        expect(
          code.contains(attendu),
          isTrue,
          reason: '« $phrase » a disparu du code de M4',
        );
      }
    });

    test(
      'la PWA n’a qu’UN suffixe monétaire, « FCFA », et le client le reprend',
      () {
        // PA-186 (11/09/2026) — décision du Product Owner : « FCFA » partout.
        // `MontantFcfa::format()`, l'auteur unique des montants de la PWA, écrit
        // « FCFA » ; les deux vues de M4 passent par lui, et le client aussi.
        final formateur = VueBlade.fichier(
          'app/Pwa/Support/MontantFcfa.php',
          role: 'l’auteur unique des montants de la PWA',
        );
        // Le suffixe est une CONSTANTE du formateur, concaténée par chaque
        // méthode : on lit la constante et son emploi, pas une chaîne figée
        // qui cesserait d'exister au premier remaniement.
        expect(formateur, contains("public const SUFFIXE = 'FCFA';"));
        expect(formateur, contains("' ' . self::SUFFIXE"));
        expect(formateur, isNot(contains(". ' F';")));
        for (final vue in const ['carte/corps', 'restaurant/restauration']) {
          expect(
            VueBlade.brute(vue),
            contains('MontantFcfa::'),
            reason: 'la vue $vue ne passe plus par MontantFcfa',
          );
        }

        final code = codeDart();
        expect(code.contains("devise = 'FCFA'"), isTrue);
        expect(
          code.contains("suffixe: 'F'"),
          isFalse,
          reason:
              'le client suffixe encore « F » alors que la décision du Product '
              'Owner (PA-186) impose « FCFA » partout, la PWA comprise',
        );
      },
    );
  });

  /* ================================================================== */
  group('L’état PAR DÉFAUT de la PWA est celui qui est porté', () {
    test('supprimer est fermé par défaut, dupliquer et sélectionner '
        'n’existent pas', () {
      // La PWA retire la suppression tant que `OptionsSystemeService` ne l'a
      // pas ouverte, et ne connaît AUCUNE bascule de duplication ni de
      // sélection groupée. Si ces défauts changeaient, la raison écrite dans
      // `_NonRendu` cesserait d'être vraie.
      final options = VueBlade.fichier(
        'app/Shared/Parametres/Services/OptionsSystemeService.php',
        role: 'les bascules qui décident si supprimer s’affiche',
      );
      final defauts = RegExp(
        r'const DEFAUTS = \[(.*?)\];',
        dotAll: true,
      ).firstMatch(options);
      expect(defauts, isNotNull, reason: '`DEFAUTS` a disparu du serveur');

      expect(
        defauts!.group(1),
        contains('self::CLE_SUPPRESSION => false'),
        reason:
            'la suppression est ouverte par défaut dans la PWA : l’absence '
            'du bouton Supprimer n’est plus justifiée',
      );
      // Les bascules `duplication` et `suppression_groupee` de l'ancien
      // prototype ne sont PAS portées par la PWA : aucune n'a de défaut, donc
      // aucun bouton Dupliquer ni case de sélection groupée n'existe.
      expect(defauts.group(1), isNot(contains('duplication')));
      expect(defauts.group(1), isNot(contains('suppression_groupee')));
    });

    test('la pagination du client est celle de la PWA', () {
      final classe = VueBlade.fichier(
        'app/Pwa/Livewire/Restaurant/Restauration.php',
      );
      final trouve = RegExp(r'const PAR_PAGE = (\d+);').firstMatch(classe);
      expect(
        trouve,
        isNotNull,
        reason: 'la pagination a disparu de la classe du catalogue',
      );

      expect(
        RestaurantApi.platsParPage,
        equals(int.parse(trouve!.group(1)!)),
        reason:
            'le client pagine autrement que la PWA : « Page 1 / 1 » là où '
            'elle en montre plusieurs',
      );
    });
  });

  /* ================================================================== */
  group('Les raisons de refus sont VÉRIFIÉES, pas recopiées', () {
    test('la fiche technique EXISTE bien côté serveur', () {
      // La colonne « Article de stock » (« Fiche technique (N ingrédient(s)) »)
      // repose sur l'existence de la
      // fiche au serveur ; encore faut-il que ce soit vrai. Si ces routes
      // disparaissaient, ce que l'écran affiche deviendrait faux à son tour.
      final source = routes();

      for (final route in [
        "Route::get('/recettes'",
        "Route::get('/recettes/{recette}'",
        "Route::put('/recettes/{recette}/composition'",
      ]) {
        expect(
          source.contains(route),
          isTrue,
          reason:
              '`$route` a disparu : la carte affiche des fiches techniques que '
              'le serveur ne servirait plus, ce qui serait devenu faux',
        );
      }
    });

    test('le serveur nomme les indicateurs absents, et le client les lit', () {
      final resource = serveur('Http/Resources/CarteRestaurantResource.php');

      final absents = RegExp(
        "'([a-z_]+)' => 'restaurant.absent",
      ).allMatches(resource).map((m) => m.group(1)!).toList();

      expect(
        absents,
        isNotEmpty,
        reason:
            'extraction vide : le serveur ne nomme plus aucun indicateur '
            'absent, ou le motif ne mord plus',
      );

      final code = codeDart();
      for (final cle in absents) {
        expect(
          code.contains("raisonAbsence('$cle')"),
          isTrue,
          reason:
              'le serveur nomme l’indicateur absent `$cle` et l’écran ne le '
              'lit pas : la carte afficherait un chiffre sans dire pourquoi il '
              'manque, ou pire, en afficherait un qui n’existe pas',
        );
      }
    });
  });
}

/// Le corps RÉELLEMENT envoyé au serveur, construit par le domaine.
///
/// Il traverse `SaisiePlat.versJson` — jamais une liste de champs recopiée
/// dans ce test, qui ne vérifierait alors qu'elle-même (piège 12).
Map<String, Object?> corpsEnvoye({bool modification = false}) =>
    const SaisiePlat(
      libelle: 'Poulet DG',
      menuId: 'menu-1',
      recetteId: 'recette-1',
      prixVente: '4500',
    ).versJson(modification: modification);

String _normaliser(String texte) => texte
    .replaceAll('’', "'")
    .replaceAll(r"\'", "'")
    .replaceAll('&amp;', '&')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
