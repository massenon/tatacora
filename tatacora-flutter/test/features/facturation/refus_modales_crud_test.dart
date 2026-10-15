import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/vue_blade.dart';

/// Les modales d'archivage et d'import que la FACTURATION ne rend pas.
///
/// ## Pourquoi cette garde a dû être écrite le 26/08/2026
///
/// Les modales de suppression, d'import et d'export étaient un **balisage
/// partagé** de l'ancien prototype, portées sur un écran et refusées sur un
/// autre, et le comparateur de l'époque confondait les deux dès qu'un libellé
/// commun existait ailleurs dans `lib/`. Cette garde tenait le contrôle côté
/// Flutter, là où le comparateur ne le pouvait plus.
///
/// ## Depuis PA-182/PA-183, elle s'ancre sur la VUE BLADE
///
/// `prototype_v2/` est une ancienne version : la question n'est plus « le
/// prototype pose-t-il cette modale ? », mais « la PWA la pose-t-elle sur CET
/// écran ? ». La vue `pwa/facturation/facturation.blade.php` ne pose ni
/// archivage (une facture ne s'archive pas, elle s'annule par avoir), ni
/// import ; `pwa/achats/achats.blade.php`, elle, pose l'archivage d'un
/// fournisseur. Le contraste est la substance de la règle, et il est
/// **re-mesuré dans la vue** à chaque exécution : un motif de refus qui a
/// cessé d'être vrai transforme une décision en oubli (PA-107, PA-120,
/// PA-144).
///
/// La modale d'EXPORT, elle, est posée par la vue de la facturation (le
/// partiel partagé `pwa/partials/modale-export`) : son absence côté Flutter
/// est une dette mesurée par `tool/conformite_blade/t-blade-flutter.js`, pas
/// un refus — elle n'est donc plus gardée ici.
///
/// Elle **échoue** si la vue est introuvable : un balayage vide est vert.
void main() {
  String lireDart(String relatif) {
    final f = File(relatif);
    if (!f.existsSync()) {
      fail(
        'Fichier introuvable : $relatif. Cette garde ne vérifie plus rien, et '
        'elle serait verte.',
      );
    }
    return f.readAsStringSync();
  }

  /// Les libellés de la modale d'archivage de la PWA, lus dans le composant
  /// partagé `components/pwa/modale-archivage.blade.php` et résolus.
  List<String> libellesArchivage() {
    final composant = VueBlade.fichier(
      'resources/views/components/pwa/modale-archivage.blade.php',
      role: 'la modale d’archivage partagée de la PWA',
    );
    final cles = RegExp(
      r"__\('(pwa\.archivage\.[a-z_]+)'",
    ).allMatches(composant).map((m) => m.group(1)!).toSet();
    final libelles = [
      for (final c in cles)
        if (VueBlade.libelle(c) case final l? when !l.contains(':')) l,
    ];
    return libelles;
  }

  /* ================================================================== */
  group('Le motif du refus est ENCORE vrai dans la vue Blade', () {
    test('sur M2, la vue ne pose ni archivage ni import', () {
      final vue = VueBlade.brute('facturation/facturation');

      expect(
        vue,
        contains('x-pwa.modale'),
        reason:
            'la vue de la facturation ne pose plus aucune modale : ce cas ne '
            'confronte plus rien',
      );
      expect(
        vue.contains('x-pwa.modale-archivage'),
        isFalse,
        reason:
            'La vue de la facturation pose désormais une modale d’archivage. '
            'Le refus côté Flutter est devenu un oubli : l’écran doit la porter.',
      );
      expect(
        RegExp(
          r'[Ii]mport',
        ).hasMatch(vue.replaceAll(RegExp(r'\{\{--[\s\S]*?--\}\}'), '')),
        isFalse,
        reason:
            'La vue de la facturation propose un import : le refus côté '
            'Flutter est devenu un oubli.',
      );
    });

    test(
      'sur M7, la vue pose l’archivage — le contraste qui fonde la règle',
      () {
        // La même modale se pose là et pas ici, et rien d'autre que cette
        // différence ne justifie qu'elle manque à la facturation.
        final vue = VueBlade.brute('achats/achats');
        expect(
          vue,
          contains('x-pwa.modale-archivage'),
          reason:
              'La vue des fournisseurs ne pose plus d’archivage : la raison du '
              'contraste a changé, relisez les deux vues.',
        );
      },
    );
  });

  /* ================================================================== */
  group('Le refus est TENU côté Flutter', () {
    test('la facturation ne rend AUCUN libellé de la modale d’archivage', () {
      final dossier = Directory('lib/features/facturation');
      expect(dossier.existsSync(), isTrue);

      // Les COMMENTAIRES sont retirés : un refus se raconte en commentaire, et
      // `ecran_facturation.dart` cite « Confirmer la suppression » pour
      // expliquer d'où venait un ancien refus. Ce qui est interdit ici, c'est
      // de RENDRE la modale, pas d'en écrire l'histoire.
      final source = dossier
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map(
            (f) => f
                .readAsStringSync()
                .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ')
                .replaceAll(RegExp(r'//[^\n]*'), ' '),
          )
          .join('\n');

      expect(
        source.length,
        greaterThan(1000),
        reason:
            'Le module de facturation relu fait ${source.length} octets : le '
            'balayage s est vidé, donc il est vert.',
      );

      final libelles = libellesArchivage();
      expect(
        libelles,
        isNotEmpty,
        reason:
            'aucun libellé extrait de la modale d’archivage : le balayage est '
            'vide, donc vert',
      );

      for (final libelle in libelles) {
        expect(
          source.contains(libelle),
          isFalse,
          reason:
              'La facturation porte « $libelle », un libellé de la modale '
              'd’archivage de la PWA, que la vue de la facturation ne pose pas.',
        );
      }
    });

    test('l’écran de facturation cite sa vue Blade', () {
      // L'ancrage du comparateur Blade -> Flutter : sans lui, l'écran n'est
      // pas mesuré du tout.
      expect(
        lireDart(
          'lib/features/facturation/presentation/ecran_facturation.dart',
        ),
        contains('pwa/facturation/facturation.blade.php'),
      );
    });
  });
}
