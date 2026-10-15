import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/theme/app_breakpoints.dart';
import 'package:tatacora_flutter/core/theme/app_colors.dart';
import 'package:tatacora_flutter/core/theme/app_durations.dart';
import 'package:tatacora_flutter/core/theme/app_shadows.dart';
import 'package:tatacora_flutter/core/theme/app_spacing.dart';
import 'package:tatacora_flutter/core/theme/app_text_styles.dart';

import '../../support/vue_blade.dart';

/// La garde du système de design — `DIRECTIVE_CONFORMITE_100.md` Article 2.
///
/// ## Elle RELIT LE MAÎTRE, elle ne fige pas de constantes
///
/// Le maître est la **vue Blade de la PWA** (PA-182, PA-183) : ce que
/// `tatacora-api` SERT. Trois sources, et **aucune n'appartient à ce dépôt
/// Flutter** :
///
/// - `tatacora-api/public/assets/css/app.css` — la feuille servie : variables
///   `:root`, ombres, durées d'animation et remappage typographique ;
/// - `tatacora-api/public/assets/js/vendor/tailwind-play-cdn.js` — le bundle
///   Tailwind **réellement servi** par la PWA : palettes, échelle
///   d'espacement, rayons, points de rupture, courbes. On ne lit pas une
///   documentation en ligne, on lit le fichier que le navigateur exécute ;
/// - `resources/views/pwa/demarrage.blade.php` et les partiels
///   `menu-lateral` / `entree-menu` — les valeurs que le CSS ne porte pas
///   (cascade du démarrage, gabarit de la barre latérale).
///
/// Jusqu'au 10/09/2026, ces trois sources étaient lues dans `prototype_v2/`,
/// une ancienne version. Mesuré au passage : le bundle Tailwind est le MÊME
/// fichier (empreintes identiques), et la feuille servie porte les mêmes
/// règles — seuls son en-tête et le paramètre `?v=` de son import diffèrent.
///
/// Un test qui figerait `#14213D` dans une liste écrite ici ne vérifierait que
/// lui-même, et resterait vert le jour où la PWA change (piège 12 : un
/// prédicat dérivé du champ qu'il vérifie ne vérifie rien).
///
/// ## Elle ÉCHOUE si la source manque, elle ne saute pas
///
/// Et elle porte un **plancher de confrontations**. Sans lui, une expression
/// régulière qui ne correspondrait plus rendrait une extraction vide, donc un
/// test vert qui n'a rien regardé — c'est exactement le défaut qu'elle protège,
/// et il est arrivé trois fois dans ce dépôt (piège 4).
void main() {
  // Le nombre de jetons réellement confrontés au maître pendant l'exécution.
  var confrontations = 0;

  /// Plancher global. Il ne se relève pas « parce que la suite a grossi » : il
  /// se relève quand on ajoute délibérément des jetons, et il se lit comme un
  /// contrat — en dessous, le balayage a cessé de balayer.
  ///
  /// Mesuré le 26/08/2026 : la suite confronte **180** jetons. Le plancher est
  /// posé à 170, c est-à-dire au-dessus de 180 moins le plus petit groupe : la
  /// disparition de n importe quel groupe le franchit.
  const plancherGlobal = 170;

  // `VueBlade.fichier` ÉCHOUE si la source manque, il ne saute pas — un
  // balayage vide est vert, et c est le défaut même que cette garde protège.
  late final String css = VueBlade.fichier(
    'public/assets/css/app.css',
    role: 'les couleurs, ombres, durées et tailles',
  );
  late final String bundle = VueBlade.fichier(
    'public/assets/js/vendor/tailwind-play-cdn.js',
    role: 'les échelles Tailwind (palettes, espacements, rayons, seuils)',
  );
  late final String splash = VueBlade.brute('demarrage');
  // Le gabarit de la barre latérale vit dans deux partiels : le conteneur
  // (`id="sidebar"`, sa largeur, sa durée de glissement) et l'entrée (sa
  // densité `py-[7px]`). Ils sont lus ENSEMBLE, dans l'ordre du rendu.
  late final String shell =
      '${VueBlade.brute('partials/menu-lateral')}\n'
      '${VueBlade.brute('partials/entree-menu')}';

  /// Toutes les vues de la PWA — pages, partiels, composants et gabarits.
  /// C'est ce que le navigateur reçoit, là où l'ancien test balayait les pages
  /// de `prototype_v2/`.
  List<File> vuesDeLaPwa() {
    final racine = Directory('${VueBlade.racine}/resources/views');
    if (!racine.existsSync()) {
      fail('Les vues de la PWA sont introuvables : ${racine.path}');
    }
    final vues = racine
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.blade.php'))
        .toList();
    // Mesuré le 10/09/2026 (PA-183) : 118 vues. Plancher posé dessous.
    expect(
      vues.length,
      greaterThanOrEqualTo(100),
      reason:
          'Seules ${vues.length} vues relues : le répertoire a été renommé ou '
          'déplacé, et le balayage passerait à vide.',
    );
    return vues;
  }

  /// Une table `nom:{cle:"valeur",…}` du bundle Tailwind.
  ///
  /// L'extraction est **prouvée non vide** : un renommage rendrait une table
  /// vide, et toutes les assertions qui en dépendent passeraient à vide.
  Map<String, String> tableBundle(String nom) {
    final bloc = RegExp('$nom:\\{([^}]*)\\}').firstMatch(bundle);
    if (bloc == null) {
      fail(
        'La table `$nom` a disparu du bundle Tailwind vendorisé du maître. '
        'Cette garde ne peut plus rien confronter : vérifiez si le bundle a '
        'été remplacé par une autre version de Tailwind, ce qui changerait '
        'toutes les valeurs que le maître rend.',
      );
    }
    final entrees = <String, String>{};
    // La clé peut être entre guillemets : le bundle écrit `"2xl":"1rem"` mais
    // `lg:"0.5rem"`. Ne lire que la forme nue laissait tomber `2xl` en
    // silence — c'est-à-dire rendre `null` là où la garde attend une valeur.
    for (final m in RegExp(
      r'"?([A-Za-z0-9.]+)"?:"([^"]*)"',
    ).allMatches(bloc.group(1)!)) {
      entrees[m.group(1)!] = m.group(2)!;
    }
    if (entrees.isEmpty) {
      fail('La table `$nom` du bundle est vide — extraction à blanc.');
    }
    return entrees;
  }

  /// `0.5rem` → 8, `640px` → 640, `9999px` → 9999.
  double enPixels(String valeur) {
    if (valeur.endsWith('rem')) {
      return double.parse(valeur.substring(0, valeur.length - 3)) * 16;
    }
    if (valeur.endsWith('px')) {
      return double.parse(valeur.substring(0, valeur.length - 2));
    }
    return double.parse(valeur);
  }

  /// Un palier du remappage typographique. **Échoue si le palier manque** :
  /// rendre `null` ferait passer la confrontation à vide, ce qui est le défaut
  /// que cette garde protège.
  double palier(Map<double, double> table, double cle) {
    final v = table[cle];
    if (v == null) {
      fail(
        'Le palier `text-[$cle px]` a disparu du remappage de app.css. '
        'Le jeton Dart correspondant ne décrit plus rien de rendu.',
      );
    }
    return v;
  }

  /// `#f8fafc` → `Color(0xFFF8FAFC)`.
  Color enCouleur(String hex) =>
      Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));

  void confronter(String quoi, Object attenduMaitre, Object jetonDart) {
    expect(
      jetonDart,
      attenduMaitre,
      reason:
          'Le jeton Dart a dérivé du maître sur « $quoi ». '
          'Le maître fait foi (Article 0) : c est le jeton qu il faut '
          'corriger, jamais l attendu de ce test.',
    );
    confrontations++;
  }

  // =========================================================================
  group('Les couleurs — bloc `:root` de app.css', () {
    Map<String, String> variablesRoot() {
      final debut = css.indexOf(':root {');
      if (debut < 0) fail('Le bloc `:root` a disparu de app.css.');
      final fin = css.indexOf('}', debut);
      final vars = <String, String>{};
      for (final m in RegExp(
        r'--([a-z0-9-]+):\s*(#[0-9A-Fa-f]{6})\s*;',
      ).allMatches(css.substring(debut, fin))) {
        vars[m.group(1)!] = m.group(2)!;
      }
      if (vars.length < 15) {
        fail(
          'Seules ${vars.length} variables `:root` ont été extraites de '
          'app.css, contre 17 attendues au minimum. L extraction est '
          'partielle : elle passerait à vide sans ce contrôle.',
        );
      }
      return vars;
    }

    test('les dix-sept variables du maître sont portées, au bit près', () {
      final v = variablesRoot();

      // La correspondance nom CSS -> jeton Dart, écrite une fois. Une variable
      // ajoutée au maître fait échouer le contrôle d exhaustivité plus bas :
      // c est ce qui oblige à rouvrir ce fichier plutôt qu à l ignorer.
      final attendus = <String, Color>{
        'navy': JetonsCssMaitre.navy,
        'gold': JetonsCssMaitre.gold,
        'gold-actif': JetonsCssMaitre.goldActif,
        'fond-clair': JetonsCssMaitre.fondClair,
        'texte': JetonsCssMaitre.texte,
        'succes': JetonsCssMaitre.succes,
        'alerte': JetonsCssMaitre.alerte,
        'erreur': JetonsCssMaitre.erreur,
        'info': JetonsCssMaitre.info,
        'gris': JetonsCssMaitre.gris,
        'neutre-0': JetonsCssMaitre.neutre0,
        'neutre-50': JetonsCssMaitre.neutre50,
        'neutre-100': JetonsCssMaitre.neutre100,
        'neutre-200': JetonsCssMaitre.neutre200,
        'neutre-400': JetonsCssMaitre.neutre400,
        'neutre-600': JetonsCssMaitre.neutre600,
        'neutre-900': JetonsCssMaitre.neutre900,
      };

      expect(
        v.keys.toSet(),
        attendus.keys.toSet(),
        reason:
            'Le jeu de variables `:root` du maître a changé. Une variable '
            'ajoutée sans jeton Dart resterait invisible au portage ; une '
            'variable retirée laisserait un jeton orphelin.',
      );

      attendus.forEach((nom, jeton) {
        confronter('--$nom', enCouleur(v[nom]!), jeton);
      });
    });

    test('les alias lisibles de AppColors pointent bien sur ces variables', () {
      final v = variablesRoot();
      confronter('AppColors.navy', enCouleur(v['navy']!), AppColors.navy);
      confronter('AppColors.gold', enCouleur(v['gold']!), AppColors.gold);
      confronter(
        'AppColors.goldActif',
        enCouleur(v['gold-actif']!),
        AppColors.goldActif,
      );
      confronter(
        'AppColors.fondClair',
        enCouleur(v['fond-clair']!),
        AppColors.fondClair,
      );
      confronter(
        'AppColors.anthracite',
        enCouleur(v['texte']!),
        AppColors.anthracite,
      );
      confronter('AppColors.succes', enCouleur(v['succes']!), AppColors.succes);
      confronter('AppColors.alerte', enCouleur(v['alerte']!), AppColors.alerte);
      confronter('AppColors.erreur', enCouleur(v['erreur']!), AppColors.erreur);
      confronter('AppColors.info', enCouleur(v['info']!), AppColors.info);
      confronter('AppColors.gris', enCouleur(v['gris']!), AppColors.gris);
    });

    test('gold-actif n est PAS gold — le maître les distingue', () {
      // Le maître écrit en commentaire que l état actif du menu doit être
      // « plus lumineux que --gold, pour que la page courante se distingue du
      // fond navy sans relecture ». Les aliaser effacerait ce repère, et le
      // contrôle ci-dessus resterait vert puisque les deux jetons existeraient.
      expect(AppColors.goldActif, isNot(AppColors.gold));
      confrontations++;
    });

    test('les dérivées d opacité suivent encore leur jeton', () {
      // Elles sont `const`, donc recopiées ; ce contrôle est ce qui les
      // rattache. Une dérivée qui cesserait de suivre `erreur` afficherait un
      // fond d une autre teinte que sa bordure, sans que rien ne le signale.
      int rvb(Color c) => c.toARGB32() & 0x00FFFFFF;

      confronter(
        'erreurFond suit erreur',
        rvb(AppColors.erreur),
        rvb(AppColors.erreurFond),
      );
      confronter(
        'erreurFondLeger suit erreur',
        rvb(AppColors.erreur),
        rvb(AppColors.erreurFondLeger),
      );
      confronter(
        'erreurBordure suit erreur',
        rvb(AppColors.erreur),
        rvb(AppColors.erreurBordure),
      );
      confronter(
        'succesFond suit succes',
        rvb(AppColors.succes),
        rvb(AppColors.succesFond),
      );
    });
  });

  // =========================================================================
  group('Les gris — famille `slate` du bundle', () {
    test('Ardoise porte la famille slate, pas une autre', () {
      final slate = tableBundle('slate');
      final attendus = <String, Color>{
        '50': Ardoise.c50,
        '100': Ardoise.c100,
        '200': Ardoise.c200,
        '300': Ardoise.c300,
        '400': Ardoise.c400,
        '500': Ardoise.c500,
        '600': Ardoise.c600,
        '700': Ardoise.c700,
        '800': Ardoise.c800,
        '900': Ardoise.c900,
      };
      attendus.forEach((rang, jeton) {
        confronter('slate-$rang', enCouleur(slate[rang]!), jeton);
      });
    });

    test('AppColors.neutreN est le rang slate-N, pas neutral-N', () {
      // La dérive corrigée le 26/08/2026. `neutral` est une VRAIE famille de
      // Tailwind, dont les valeurs sont plausibles et proches : c est pour
      // cela que l écart a tenu 216 emplois sans se voir. Ce contrôle
      // l ancre sur la famille que le maître emploie réellement.
      final slate = tableBundle('slate');
      final neutral = tableBundle('neutral');

      confronter('neutre100', enCouleur(slate['100']!), AppColors.neutre100);
      confronter('neutre200', enCouleur(slate['200']!), AppColors.neutre200);
      confronter('neutre300', enCouleur(slate['300']!), AppColors.neutre300);
      confronter('neutre500', enCouleur(slate['500']!), AppColors.neutre500);
      confronter('neutre700', enCouleur(slate['700']!), AppColors.neutre700);

      for (final rang in ['100', '200', '300', '500', '700']) {
        expect(
          enCouleur(neutral[rang]!),
          isNot(enCouleur(slate[rang]!)),
          reason:
              'Le contrôle ci-dessus ne prouve quelque chose que si les deux '
              'familles diffèrent réellement au rang $rang. Si Tailwind les '
              'alignait un jour, ce test passerait à vide.',
        );
        confrontations++;
      }
    });

    test('la PWA n emploie AUCUNE autre famille de gris', () {
      // La raison d être de `Ardoise`. Si une vue se mettait à écrire
      // `text-gray-500`, l échelle de ce dépôt cesserait d être la bonne — et
      // rien d autre ne le dirait.
      final pages = vuesDeLaPwa();

      final interdites = RegExp(
        r'\b(?:bg|text|border|ring|divide|from|via|to|placeholder)'
        r'-(?:gray|neutral|zinc|stone)-\d+',
      );
      final fautives = <String>[];
      for (final f in pages) {
        if (interdites.hasMatch(f.readAsStringSync())) {
          fautives.add(f.uri.pathSegments.last);
        }
      }
      expect(
        fautives,
        isEmpty,
        reason:
            'Ces pages du maître emploient une famille de gris que `Ardoise` '
            'ne porte pas. Le jeton doit suivre le maître, pas l inverse.',
      );
      confrontations++;
    });
  });

  // =========================================================================
  group('Les rangs sémantiques employés par le maître', () {
    test('PaletteMaitre porte les valeurs du bundle', () {
      final rouge = tableBundle('red');
      final emeraude = tableBundle('emerald');
      final ambre = tableBundle('amber');
      final bleu = tableBundle('blue');

      confronter('red-50', enCouleur(rouge['50']!), PaletteMaitre.rouge50);
      confronter('red-100', enCouleur(rouge['100']!), PaletteMaitre.rouge100);
      confronter('red-200', enCouleur(rouge['200']!), PaletteMaitre.rouge200);
      confronter('red-300', enCouleur(rouge['300']!), PaletteMaitre.rouge300);
      confronter('red-500', enCouleur(rouge['500']!), PaletteMaitre.rouge500);
      confronter('red-600', enCouleur(rouge['600']!), PaletteMaitre.rouge600);
      confronter('red-700', enCouleur(rouge['700']!), PaletteMaitre.rouge700);
      confronter('red-800', enCouleur(rouge['800']!), PaletteMaitre.rouge800);

      confronter(
        'emerald-50',
        enCouleur(emeraude['50']!),
        PaletteMaitre.emeraude50,
      );
      confronter(
        'emerald-200',
        enCouleur(emeraude['200']!),
        PaletteMaitre.emeraude200,
      );
      confronter(
        'emerald-300',
        enCouleur(emeraude['300']!),
        PaletteMaitre.emeraude300,
      );
      confronter(
        'emerald-600',
        enCouleur(emeraude['600']!),
        PaletteMaitre.emeraude600,
      );
      confronter(
        'emerald-700',
        enCouleur(emeraude['700']!),
        PaletteMaitre.emeraude700,
      );

      confronter('amber-50', enCouleur(ambre['50']!), PaletteMaitre.ambre50);
      confronter('amber-200', enCouleur(ambre['200']!), PaletteMaitre.ambre200);
      confronter('amber-600', enCouleur(ambre['600']!), PaletteMaitre.ambre600);
      confronter('amber-700', enCouleur(ambre['700']!), PaletteMaitre.ambre700);

      confronter('blue-50', enCouleur(bleu['50']!), PaletteMaitre.bleu50);
      confronter('blue-100', enCouleur(bleu['100']!), PaletteMaitre.bleu100);
      confronter('blue-700', enCouleur(bleu['700']!), PaletteMaitre.bleu700);
    });

    test('--info du maître EST blue-700, et le dépôt ne les dédouble pas', () {
      confronter(
        'info == blue-700',
        PaletteMaitre.bleu700,
        JetonsCssMaitre.info,
      );
    });
  });

  // =========================================================================
  group('Les rayons — table `borderRadius` du bundle et règles de app.css', () {
    test('AppRadius porte l échelle du bundle', () {
      final r = tableBundle('borderRadius');
      confronter('rounded', enPixels(r['DEFAULT']!), AppRadius.rounded);
      confronter('rounded-md', enPixels(r['md']!), AppRadius.roundedMd);
      confronter('rounded-lg', enPixels(r['lg']!), AppRadius.roundedLg);
      confronter('rounded-xl', enPixels(r['xl']!), AppRadius.roundedXl);
      confronter('rounded-2xl', enPixels(r['2xl']!), AppRadius.rounded2xl);
      confronter('rounded-full', enPixels(r['full']!), AppRadius.roundedFull);
    });

    test('les alias courts ne portent pas une seconde échelle', () {
      confronter('AppRadius.sm', AppRadius.rounded, AppRadius.sm);
      confronter('AppRadius.md', AppRadius.roundedLg, AppRadius.md);
      confronter('AppRadius.lg', AppRadius.roundedXl, AppRadius.lg);
      confronter('AppRadius.xl', AppRadius.rounded2xl, AppRadius.xl);
      confronter('AppRadius.pleine', AppRadius.roundedFull, AppRadius.pleine);
    });

    test('les deux rayons écrits en dur dans app.css sont couverts', () {
      // Un sélecteur apparaît plusieurs fois dans app.css : `.boite-modale`
      // porte DEUX règles, dont l'une ne fixe que `transform` et `opacity`.
      // Prendre la première rendait un bloc sans `border-radius`, et la garde
      // concluait à une disparition qui n'avait pas eu lieu.
      double rayonDe(String selecteur) {
        final blocs = RegExp(
          '\\$selecteur\\s*\\{([^}]*)\\}',
        ).allMatches(css).toList();
        if (blocs.isEmpty) {
          fail('La règle `$selecteur` a disparu de app.css.');
        }
        for (final bloc in blocs) {
          final m = RegExp(
            r'border-radius:\s*([\d.]+)px',
          ).firstMatch(bloc.group(1)!);
          if (m != null) return double.parse(m.group(1)!);
        }
        fail(
          'Aucune des ${blocs.length} règles `$selecteur` de app.css ne porte '
          'de `border-radius` en pixels.',
        );
      }

      confronter(
        '.boite-modale',
        rayonDe('.boite-modale'),
        AppRadius.roundedXl,
      );
      confronter('.toast', rayonDe('.toast'), AppRadius.roundedLg);
    });
  });

  // =========================================================================
  group('Les points de rupture — table `screens` du bundle', () {
    test('les cinq seuils sont portés', () {
      final s = tableBundle('screens');
      confronter('sm:', enPixels(s['sm']!), AppBreakpoints.sm);
      confronter('md:', enPixels(s['md']!), AppBreakpoints.md);
      confronter('lg:', enPixels(s['lg']!), AppBreakpoints.lg);
      confronter('xl:', enPixels(s['xl']!), AppBreakpoints.xl);
      confronter('2xl:', enPixels(s['2xl']!), AppBreakpoints.xxl);
    });

    test('la PWA ne redéfinit pas `screens`', () {
      // Article 1 n° 12 : « changer un point de rupture responsive » est
      // interdit. Encore faut-il savoir si la PWA en a changé un elle-même —
      // sa configuration Tailwind vit dans `partials/tete.blade.php`.
      final pages = vuesDeLaPwa();
      expect(
        pages.where((f) => f.readAsStringSync().contains('tailwind.config')),
        isNotEmpty,
        reason:
            'Aucune vue ne porte plus `tailwind.config` : ce contrôle ne '
            'regarderait plus rien, et il serait vert.',
      );

      for (final f in pages) {
        final conf = RegExp(
          r'tailwind\.config\s*=\s*(\{[^\n]*\})',
        ).firstMatch(f.readAsStringSync());
        if (conf == null) continue;
        expect(
          conf.group(1),
          isNot(contains('screens')),
          reason:
              '${f.uri.pathSegments.last} redéfinit `screens` : les seuils de '
              'AppBreakpoints ne sont plus ceux que le maître rend.',
        );
      }
      confrontations++;
    });
  });

  // =========================================================================
  group('Les espacements — table `spacing` du bundle', () {
    test('AppSpacing porte les rangs employés par le maître', () {
      final s = tableBundle('spacing');
      confronter('0.5', enPixels(s['.5']!), AppSpacing.demi);
      confronter('1', enPixels(s['1']!), AppSpacing.unit);
      confronter('1.5', enPixels(s['1.5']!), AppSpacing.xxs);
      confronter('2', enPixels(s['2']!), AppSpacing.xs);
      confronter('2.5', enPixels(s['2.5']!), AppSpacing.xsPlus);
      confronter('3', enPixels(s['3']!), AppSpacing.sm);
      confronter('3.5', enPixels(s['3.5']!), AppSpacing.smPlus);
      confronter('4', enPixels(s['4']!), AppSpacing.md);
      confronter('5', enPixels(s['5']!), AppSpacing.mdPlus);
      confronter('6', enPixels(s['6']!), AppSpacing.lg);
      confronter('7', enPixels(s['7']!), AppSpacing.lgPlus);
      confronter('8', enPixels(s['8']!), AppSpacing.xl);
      confronter('10', enPixels(s['10']!), AppSpacingLarge.p10);
      confronter('12', enPixels(s['12']!), AppSpacingLarge.p12);
      confronter('16', enPixels(s['16']!), AppSpacingLarge.p16);
    });

    test(
      'py-2.5 (10 px) n est PAS py-[7px] — l échelle nommée n est pas le crochet',
      () {
        // Les deux valeurs vivent dans le même menu du maître, à quatre lignes
        // d écart. Les confondre est l erreur que ce dépôt s est écrite en
        // toutes lettres, et elle ne se voit pas : 7 et 10 px sont tous deux
        // plausibles sur une entrée de menu.
        final s = tableBundle('spacing');
        confronter('py-2.5', enPixels(s['2.5']!), AppSpacing.xsPlus);

        final m = RegExp(r'py-\[(\d+)px\]').firstMatch(shell);
        if (m == null) {
          fail(
            'La classe `py-[7px]` a disparu des partiels du menu latéral. La densité de la '
            'barre latérale du maître ne peut plus être confrontée.',
          );
        }
        confronter(
          'py-[7px]',
          double.parse(m.group(1)!),
          AppSpacing.entreeSidebar,
        );
        expect(AppSpacing.entreeSidebar, isNot(AppSpacing.xsPlus));
        confrontations++;
      },
    );

    test(
      'la largeur de la barre latérale vient des partiels du menu latéral',
      () {
        // Ancré sur l'élément lui-même. `min-w-[14px]` — la pastille de
        // notification — précède `w-[264px]` dans le fichier, et un motif non
        // ancré rendait **14** : une largeur de barre latérale absurde que rien
        // d'autre n'aurait signalée, sur un test qui se serait dit vérifié.
        final m = RegExp(
          r'id="sidebar" class="w-\[(\d+)px\]',
        ).firstMatch(shell);
        if (m == null) {
          fail(
            'L élément `id="sidebar"` des partiels du menu latéral ne porte plus sa largeur en '
            'classe : le gabarit de la barre latérale ne peut plus être '
            'confronté.',
          );
        }
        confronter(
          'w-[264px]',
          double.parse(m.group(1)!),
          AppLayout.sidebarWidth,
        );
      },
    );
  });

  // =========================================================================
  group('Les ombres — règles `box-shadow` de app.css', () {
    /// Les cinq ombres du maître, dans l'ordre où app.css les déclare.
    List<List<num>> ombresCss() {
      final re = RegExp(
        r'box-shadow:\s*(-?[\d.]+)(?:px)?\s+(-?[\d.]+)(?:px)?\s+'
        r'(-?[\d.]+)(?:px)?(?:\s+(-?[\d.]+)(?:px)?)?\s+'
        r'rgba\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*([\d.]+)\s*\)',
      );
      final ombres = <List<num>>[];
      for (final m in re.allMatches(css)) {
        final alphaBrut = m.group(8)!;
        final alpha = double.parse(
          alphaBrut.startsWith('.') ? '0$alphaBrut' : alphaBrut,
        );
        ombres.add([
          double.parse(m.group(2)!), // décalage vertical
          double.parse(m.group(3)!), // flou
          double.parse(m.group(4) ?? '0'), // étalement
          int.parse(m.group(5)!),
          int.parse(m.group(6)!),
          int.parse(m.group(7)!),
          (alpha * 255).round(),
        ]);
      }
      if (ombres.length < 5) {
        fail(
          'Seules ${ombres.length} règles `box-shadow` ont été extraites de '
          'app.css, contre 5 attendues. L extraction est partielle : sans ce '
          'contrôle les assertions passeraient à vide.',
        );
      }
      return ombres;
    }

    void confronterOmbre(String nom, List<num> maitre, BoxShadow dart) {
      confronter('$nom — décalage', maitre[0].toDouble(), dart.offset.dy);
      confronter('$nom — flou', maitre[1].toDouble(), dart.blurRadius);
      confronter('$nom — étalement', maitre[2].toDouble(), dart.spreadRadius);
      confronter(
        '$nom — couleur',
        (maitre[6].toInt() << 24) |
            (maitre[3].toInt() << 16) |
            (maitre[4].toInt() << 8) |
            maitre[5].toInt(),
        dart.color.toARGB32(),
      );
    }

    test('les cinq ombres du maître sont portées au pixel et à l alpha', () {
      final o = ombresCss();
      // L ordre est celui de app.css : focus, focus en erreur, modale, toast,
      // carte au survol. Il est vérifié par les valeurs elles-mêmes — une
      // permutation ferait rougir la confrontation, pas passer.
      confronterOmbre('focus du champ', o[0], AppShadows.focusChamp.single);
      confronterOmbre(
        'focus en erreur',
        o[1],
        AppShadows.focusChampErreur.single,
      );
      confronterOmbre('modale', o[2], AppShadows.modale.single);
      confronterOmbre('toast', o[3], AppShadows.toast.single);
      confronterOmbre('carte au survol', o[4], AppShadows.carteSurvol.single);
    });

    test('le flou d arrière-plan de la modale est porté', () {
      final m = RegExp(
        r'backdrop-filter:\s*blur\(([\d.]+)px\)',
      ).firstMatch(css);
      if (m == null) {
        fail('`backdrop-filter: blur(…)` a disparu de app.css.');
      }
      confronter(
        'backdrop blur',
        double.parse(m.group(1)!),
        AppShadows.flouArrierePlanModale,
      );
    });

    test('le déplacement au survol vient bien du maître', () {
      final m = RegExp(
        r'transform:\s*translateY\((-?[\d.]+)px\)',
      ).firstMatch(css);
      if (m == null) fail('`translateY(…)` a disparu de app.css.');
      confronter(
        'translateY au survol',
        double.parse(m.group(1)!),
        AppShadows.carteSurvolTranslation,
      );
    });
  });

  // =========================================================================
  group('Les durées et les courbes', () {
    test('toute durée déclarée dans app.css a un jeton, et réciproquement', () {
      // Le contrôle est BIDIRECTIONNEL, et c est ce qui fait sa valeur : une
      // animation ajoutée au maître sans jeton correspondant fait rougir la
      // suite. Article 1 n° 11 — « raccourcir ou supprimer une animation » est
      // interdit ; encore faut-il savoir qu elle existe.
      final duMaitre = <int>{};
      for (final m in RegExp(
        r'(?:transition|animation):\s*([^;]+);',
      ).allMatches(css)) {
        for (final d in RegExp(
          r'(?<![\d.])(\d*\.?\d+)s\b',
        ).allMatches(m.group(1)!)) {
          final brut = d.group(1)!;
          duMaitre.add(
            (double.parse(brut.startsWith('.') ? '0$brut' : brut) * 1000)
                .round(),
          );
        }
      }
      if (duMaitre.isEmpty) {
        fail('Aucune durée extraite de app.css — extraction à blanc.');
      }

      final jetons = <int>{
        AppDurations.pression.inMilliseconds,
        AppDurations.courte.inMilliseconds,
        AppDurations.modale.inMilliseconds,
        AppDurations.toastEntree.inMilliseconds,
        AppDurations.toastVie.inMilliseconds,
      };

      expect(
        duMaitre,
        jetons,
        reason:
            'Les durées de app.css et les jetons AppDurations ont divergé. '
            'Le maître fait foi : ajoutez ou corrigez le jeton.',
      );
      confrontations += duMaitre.length;
    });

    test('la cascade du démarrage a la durée et les retards du maître', () {
      final anims = RegExp(
        r'animation:\s*apparition\s+([\d.]+)s\s+ease'
        r'(?:\s+([\d.]+)s)?',
      ).allMatches(splash).toList();
      if (anims.length < 4) {
        fail(
          'Seules ${anims.length} classes `.anim-*` ont été extraites de '
          'demarrage.blade.php, contre 4. Article 4.1 exige « mêmes retards en '
          'cascade » : sans les quatre, ce test ne vérifie rien.',
        );
      }

      double sec(String? v) =>
          v == null ? 0 : double.parse(v.startsWith('.') ? '0$v' : v);

      for (final a in anims) {
        confronter(
          'durée d apparition',
          (sec(a.group(1)) * 1000).round(),
          AppDurations.apparition.inMilliseconds,
        );
      }
      final retards = anims
          .map((a) => Duration(milliseconds: (sec(a.group(2)) * 1000).round()))
          .toList();
      confronter('cascade', retards, AppDurations.cascadeApparition);
    });

    test(
      'la cadence et la pause du démarrage viennent de demarrage.blade.php',
      () {
        final minuteries = RegExp(
          r'\},\s*(\d+)\)',
        ).allMatches(splash).map((m) => int.parse(m.group(1)!)).toSet();
        if (minuteries.isEmpty) {
          fail(
            'Aucune minuterie extraite de demarrage.blade.php — extraction à blanc.',
          );
        }
        confronter('cadence et pause', minuteries, {
          AppDurations.pasProgression.inMilliseconds,
          AppDurations.pauseAvantAiguillage.inMilliseconds,
        });
      },
    );

    test(
      'la barre latérale glisse sur la durée des partiels du menu latéral',
      () {
        final m = RegExp(r'duration-(\d+)').firstMatch(shell);
        if (m == null) {
          fail('`duration-200` a disparu des partiels du menu latéral.');
        }
        confronter(
          'duration-200',
          int.parse(m.group(1)!),
          AppDurations.modale.inMilliseconds,
        );
      },
    );

    test('les courbes portent les coefficients du bundle, pas une voisine', () {
      final t = tableBundle('transitionTimingFunction');

      List<double> bezier(String v) => RegExp(
        r'-?[\d.]+',
      ).allMatches(v).map((m) => double.parse(m.group(0)!)).toList();

      final defaut = bezier(t['DEFAULT']!);
      final courbe = AppDurations.tailwindDefaut as Cubic;
      confronter('Tailwind DEFAULT a', defaut[0], courbe.a);
      confronter('Tailwind DEFAULT b', defaut[1], courbe.b);
      confronter('Tailwind DEFAULT c', defaut[2], courbe.c);
      confronter('Tailwind DEFAULT d', defaut[3], courbe.d);

      // La courbe `ease` de CSS n est PAS dans la table de Tailwind : c est
      // une valeur du langage CSS, cubic-bezier(0.25, 0.1, 0.25, 1). Elle est
      // confrontée ici parce que le maître l écrit dans TOUTES ses règles
      // manuelles, et la confondre avec la précédente change chaque ouverture
      // de modale.
      final ease = AppDurations.ease as Cubic;
      confronter('CSS ease a', 0.25, ease.a);
      confronter('CSS ease b', 0.1, ease.b);
      confronter('CSS ease c', 0.25, ease.c);
      confronter('CSS ease d', 1.0, ease.d);
      expect(
        AppDurations.ease,
        isNot(AppDurations.tailwindDefaut),
        reason:
            'Les deux courbes du maître ont été aliasées l une sur l autre : '
            'les contrôles ci-dessus ne prouveraient plus rien.',
      );
      confrontations++;

      expect(css, contains('ease'));
      expect(splash, contains('ease-linear'));
      confrontations++;
    });
  });

  // =========================================================================
  group('La typographie — remappage `main` de app.css', () {
    test('l échelle EFFECTIVE du contenu est celle du maître', () {
      // Le piège que la doctrine annonce §3.1 : une classe peut être surchargée
      // par une règle locale. Ici `text-[13px]` rend 12,5 px. Déduire la taille
      // du nom de la classe serait « une erreur en attente » (Article 2).
      final sansEchappement = css.replaceAll(r'\', '');

      final crochets = <double, double>{};
      for (final m in RegExp(
        r'main \.text-\[([\d.]+)px\]\s*\{\s*font-size:\s*([\d.]+)px',
      ).allMatches(sansEchappement)) {
        crochets[double.parse(m.group(1)!)] = double.parse(m.group(2)!);
      }
      if (crochets.length < 12) {
        fail(
          'Seuls ${crochets.length} paliers entre crochets extraits du '
          'remappage, contre 12 attendus. Extraction partielle.',
        );
      }

      confronter('text-[8px]', palier(crochets, 8), TaillesContenu.t8);
      confronter('text-[9px]', palier(crochets, 9), TaillesContenu.t9);
      confronter('text-[10px]', palier(crochets, 10), TaillesContenu.t10);
      confronter('text-[10.5px]', palier(crochets, 10.5), TaillesContenu.t10_5);
      confronter('text-[11px]', palier(crochets, 11), TaillesContenu.t11);
      confronter('text-[11.5px]', palier(crochets, 11.5), TaillesContenu.t11_5);
      confronter('text-[12px]', palier(crochets, 12), TaillesContenu.t12);
      confronter('text-[12.5px]', palier(crochets, 12.5), TaillesContenu.t12_5);
      confronter('text-[13px]', palier(crochets, 13), TaillesContenu.t13);
      confronter('text-[14px]', palier(crochets, 14), TaillesContenu.t14);
      confronter('text-[15px]', palier(crochets, 15), TaillesContenu.t15);
      confronter('text-[17px]', palier(crochets, 17), TaillesContenu.t17);

      // Et le fait qui ne se devine pas : la classe ne dit pas le pixel.
      expect(
        palier(crochets, 13),
        isNot(13),
        reason:
            'Le maître ne remappe plus `text-[13px]`. Si c est voulu, '
            '`TaillesContenu` doit rejoindre `Tailles` ; en attendant, ce '
            'contrôle prouve que les deux échelles sont bien distinctes.',
      );
      confrontations++;
    });

    test('les six paliers nommés portent leur taille ET leur interligne', () {
      final sansEchappement = css.replaceAll(r'\', '');
      final nommes = <String, List<double>>{};
      for (final m in RegExp(
        r'main \.text-(xs|sm|base|lg|xl|2xl)\s*\{\s*font-size:\s*([\d.]+)px;'
        r'\s*line-height:\s*([\d.]+)',
      ).allMatches(sansEchappement)) {
        nommes[m.group(1)!] = [
          double.parse(m.group(2)!),
          double.parse(m.group(3)!),
        ];
      }
      if (nommes.length != 6) {
        fail(
          'Seuls ${nommes.length} paliers nommés extraits, contre 6. '
          'Extraction partielle : les interlignes ne seraient plus gardés.',
        );
      }

      confronter('text-xs', nommes['xs']![0], TaillesContenu.xs);
      confronter(
        'text-xs interligne',
        nommes['xs']![1],
        TaillesContenu.interligneXs,
      );
      confronter('text-sm', nommes['sm']![0], TaillesContenu.sm);
      confronter(
        'text-sm interligne',
        nommes['sm']![1],
        TaillesContenu.interligneSm,
      );
      confronter('text-base', nommes['base']![0], TaillesContenu.base);
      confronter(
        'text-base interligne',
        nommes['base']![1],
        TaillesContenu.interligneBase,
      );
      confronter('text-lg', nommes['lg']![0], TaillesContenu.lg);
      confronter(
        'text-lg interligne',
        nommes['lg']![1],
        TaillesContenu.interligneLg,
      );
      confronter('text-xl', nommes['xl']![0], TaillesContenu.xl);
      confronter(
        'text-xl interligne',
        nommes['xl']![1],
        TaillesContenu.interligneXl,
      );
      confronter('text-2xl', nommes['2xl']![0], TaillesContenu.xxl);
      confronter(
        'text-2xl interligne',
        nommes['2xl']![1],
        TaillesContenu.interligneXxl,
      );
    });

    test('l échelle DÉCLARÉE est celle que les pages écrivent', () {
      // ⚠ Ce contrôle est né d'un accident, et il mérite d'être conservé pour
      // ce qu'il a montré. Le 26/08/2026, une mutation de `TaillesContenu.t13`
      // a été mal défaite : le motif a mordu sur `Tailles.t13`, laissé à 12,5
      // au lieu de 13. **La suite est restée verte** — l'échelle déclarée
      // n'était confrontée à rien.
      //
      // C'est le piège 5 du dépôt sous une autre forme : une assertion qui
      // existe à côté du chemin ne protège pas le chemin. `Tailles` est
      // l'échelle des écrans hors `main` (connexion, démarrage, barre
      // supérieure, modales) ; la laisser dériver aurait faussé exactement les
      // écrans que `TaillesContenu` ne couvre pas.
      //
      // L'ancrage est extérieur : les classes `text-[Npx]` réellement écrites
      // dans les vues de la PWA, comptées. Un jeton qui prétendrait valoir
      // 12,5 alors qu'aucune vue n'écrit `text-[12.5px]` ne décrit rien.
      final pages = vuesDeLaPwa();

      // L'ancre est l'UNION de deux sources servies, et il faut les deux :
      //  - les tailles réellement écrites dans les vues ;
      //  - les paliers que la feuille servie nomme dans son remappage.
      // Elles ne se recouvrent pas forcément : un palier peut être remappé
      // sans être écrit, ou écrit sans être remappé. Ne retenir que l'une des
      // deux rejetterait des jetons légitimes, ou en laisserait passer un qui
      // ne décrit rien.
      final declarees = <double>{};
      final re = RegExp(r'text-\[([\d.]+)px\]');
      for (final f in pages) {
        for (final m in re.allMatches(f.readAsStringSync())) {
          declarees.add(double.parse(m.group(1)!));
        }
      }
      final ecritesDansLesPages = declarees.length;
      for (final m in re.allMatches(
        css.replaceAll(r'\', '').replaceAll('main ', ''),
      )) {
        declarees.add(double.parse(m.group(1)!));
      }
      if (ecritesDansLesPages < 8 || declarees.length < 12) {
        fail(
          'Extraction partielle : $ecritesDansLesPages tailles relevées dans '
          'les pages (8 attendues au minimum) et ${declarees.length} au total '
          'avec le remappage (12 attendues). Sans ce contrôle les assertions '
          'ci-dessous passeraient à vide.',
        );
      }

      for (final entree in <String, double>{
        'Tailles.t8': Tailles.t8,
        'Tailles.t9': Tailles.t9,
        'Tailles.t10': Tailles.t10,
        'Tailles.t10_5': Tailles.t10_5,
        'Tailles.t11': Tailles.t11,
        'Tailles.t11_5': Tailles.t11_5,
        'Tailles.t12': Tailles.t12,
        'Tailles.t12_5': Tailles.t12_5,
        'Tailles.t13': Tailles.t13,
        'Tailles.t14': Tailles.t14,
        'Tailles.t15': Tailles.t15,
        'Tailles.t17': Tailles.t17,
        'Tailles.t19': Tailles.t19,
      }.entries) {
        expect(
          declarees,
          contains(entree.value),
          reason:
              '${entree.key} vaut ${entree.value}, mais aucune vue de la PWA '
              'n écrit `text-[${entree.value}px]`. Le jeton a dérivé de ce '
              'qu il prétend décrire.',
        );
        confrontations++;
      }

      // Et la distinction qui donne son sens aux deux classes.
      expect(
        Tailles.t13,
        isNot(TaillesContenu.t13),
        reason:
            'L échelle déclarée et l échelle effective se sont confondues. '
            'Le maître les distingue (app.css remappe `text-[13px]` à '
            '12,5 px) ; les aliaser efface la distinction et rend l un des '
            'deux jetons faux partout où il est employé.',
      );
      confrontations++;
    });

    test('la barre latérale est hors du remappage, à 14 px', () {
      final m = RegExp(
        r'#shell-sidebar \.lien-sidebar\s*\{\s*font-size:\s*([\d.]+)px',
      ).firstMatch(css);
      if (m == null) {
        fail('La règle de taille du menu latéral a disparu de app.css.');
      }
      confronter(
        'lien de la barre latérale',
        double.parse(m.group(1)!),
        Tailles.lienSidebar,
      );
    });

    test('les familles de police sont celles du maître', () {
      final corps = RegExp(
        r"font-family:\s*'([^']+)'",
      ).allMatches(css).map((m) => m.group(1)!);
      expect(corps, isNotEmpty, reason: 'Aucune police extraite de app.css.');
      expect(corps, contains(AppTextStyles.police));
      expect(corps, contains('JetBrains Mono'));
      confrontations += 2;
    });
  });

  // =========================================================================
  tearDownAll(() {
    // LE PLANCHER. Il est vérifié en dernier, une fois tous les groupes passés.
    //
    // Sans lui, un sélecteur CSS renommé ou un répertoire déplacé rendrait
    // chaque extraction vide et cette suite resterait VERTE — c est le défaut
    // qu elle est faite pour attraper, et il est déjà arrivé trois fois ici.
    expect(
      confrontations,
      greaterThanOrEqualTo(plancherGlobal),
      reason:
          'Seulement $confrontations jetons ont été confrontés au maître, '
          'contre $plancherGlobal attendus au minimum. La garde a cessé de '
          'garder : une extraction est passée à vide, ou des contrôles ont '
          'été retirés sans que le plancher soit rouvert.',
    );
  });
}
