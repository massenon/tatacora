import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/config/environnement.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/presentation/ecran_connexion.dart';
import 'package:tatacora_flutter/features/auth/presentation/formulaire_premier_compte.dart';

import '../../support/cas_ecrans.dart';
import '../../support/coquille_montee.dart';
import '../../support/structure_rendue.dart';

/// PHASE 1D — ALIGNEMENT mesuré en PIXELS, écran par écran (pilote : la
/// connexion).
///
/// ## Méthode
///
/// 1. **Vue Blade** : la page est ouverte dans un vrai navigateur (Chrome,
///    fenêtre pilotée), et un script relève, pour chaque texte visible et
///    chaque champ, sa boîte (`x`, `y`, `w`, `h`, en pixels CSS) dans
///    `tool/conformite_blade/geometrie/<vue>.json`, avec la taille de la
///    fenêtre. Le relevé est envoyé à un petit récepteur local (aucun fichier
///    n'est écrit à la main).
/// 2. **Flutter** : l'écran est monté dans un test de widget **à la même
///    taille de fenêtre**, avec la **police Inter** chargée (la PWA sert Inter ;
///    sans elle, un test de widget rend tout en `Ahem`, des carrés, et les
///    largeurs ne veulent rien dire). Chaque texte est apparié par son contenu
///    exact.
/// 3. Pour chaque texte apparié, on mesure l'écart de position (`dx`, `dy`) et
///    de taille (`dw`, `dh`).
///
/// ## Tolérances
///
/// Position : 8 px. Taille : 12 % de la boîte de la vue (les deux moteurs de
/// rendu de texte ne coïncident pas au pixel). Elles sont écrites ici, à un
/// seul endroit.
///
/// ## Le cliquet
///
/// `tool/conformite_blade/geometrie/dette-geometrie.json` fige le nombre
/// d'éléments alignés ; il échoue sur un recul et sur un progrès non resserré
/// (`FIGER_GEOMETRIE=1`).
///
/// ## Limites
///
/// Le relevé du navigateur est pris à UNE taille de fenêtre. Un texte absent
/// d'un côté n'a pas de boîte à comparer : il est compté « sans vis-à-vis ».
/// Couleurs et ombres ne sont pas mesurées.

const double _tolerancePosition = 8;
const double _toleranceTaille = 0.12;

Future<void> _chargerInter() async {
  final f = File('assets/fonts/Inter.ttf');
  if (!f.existsSync()) {
    fail('Police Inter introuvable : ${f.path} (échec, pas saut).');
  }
  final octets = f.readAsBytesSync();
  final chargeur = FontLoader('Inter')
    ..addFont(Future.value(ByteData.view(octets.buffer)));
  await chargeur.load();
}

class _Boite {
  const _Boite(this.texte, this.x, this.y, this.w, this.h);

  final String texte;
  final double x;
  final double y;
  final double w;
  final double h;
}

({Size fenetre, List<_Boite> elements}) _releveNavigateur(String vue) {
  final f = File(
    'tool/conformite_blade/geometrie/${vue.replaceAll('/', '__')}.json',
  );
  if (!f.existsSync()) {
    fail(
      'Géométrie introuvable : ${f.path}.\n'
      'Elle se relève dans un navigateur : voir l’en-tête de ce test.',
    );
  }
  final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  final fen = json['fenetre'] as Map<String, dynamic>;
  return (
    fenetre: Size((fen['w'] as num).toDouble(), (fen['h'] as num).toDouble()),
    elements: [
      for (final e in json['elements'] as List<dynamic>)
        _Boite(
          (e as Map<String, dynamic>)['texte'] as String,
          (e['x'] as num).toDouble(),
          (e['y'] as num).toDouble(),
          (e['w'] as num).toDouble(),
          (e['h'] as num).toDouble(),
        ),
    ],
  );
}

File get _fichierDette =>
    File('tool/conformite_blade/geometrie/dette-geometrie.json');

/// Compare un relevé du navigateur à ce que Flutter rend, puis applique le
/// cliquet. Les éléments de la vue qui sortent de la fenêtre (barre latérale
/// défilante) sont écartés : une liste paresseuse ne construit que ce qu'elle
/// montre, les comparer serait mesurer le défilement.
void _evaluer({
  required String vue,
  required ({Size fenetre, List<_Boite> elements}) releve,
  required List<ElementRendu> rendu,
}) {
  final visibles = [
    for (final b in releve.elements)
      if (b.y + b.h <= releve.fenetre.height) b,
  ];
  final utilises = <int>{};
  var apparies = 0;
  var alignes = 0;
  var dimensionnes = 0;
  final sansVisAVis = <String>[];
  final ecarts = <String>[];

  for (final b in visibles) {
    final cible = normaliser(b.texte);
    final i = rendu.indexWhere(
      (r) =>
          !utilises.contains(rendu.indexOf(r)) && normaliser(r.texte) == cible,
    );
    if (i < 0) {
      sansVisAVis.add(b.texte);
      continue;
    }
    utilises.add(i);
    final r = rendu[i].boite;
    apparies++;
    final dx = r.left - b.x;
    final dy = r.top - b.y;
    final dw = r.width - b.w;
    final dh = r.height - b.h;
    final position =
        dx.abs() <= _tolerancePosition && dy.abs() <= _tolerancePosition;
    final taille =
        dw.abs() <= b.w * _toleranceTaille + 1 &&
        dh.abs() <= b.h * _toleranceTaille + 1;
    if (position) alignes++;
    if (taille) dimensionnes++;
    ecarts.add(
      '${b.texte.length > 30 ? '${b.texte.substring(0, 30)}…' : b.texte}'
      ' dx=${dx.toStringAsFixed(1)} dy=${dy.toStringAsFixed(1)}'
      ' dw=${dw.toStringAsFixed(1)} dh=${dh.toStringAsFixed(1)}'
      '${position ? '' : '  ← POSITION'}${taille ? '' : '  ← TAILLE'}',
    );
  }

  final total = visibles.length;
  // ignore: avoid_print
  print(
    '\nGÉOMÉTRIE — $vue @ ${releve.fenetre.width.toInt()}×'
    '${releve.fenetre.height.toInt()} : $total éléments de la vue dans la '
    'fenêtre, $apparies appariés, $alignes alignés (±$_tolerancePosition px), '
    '$dimensionnes de bonne taille (±${(_toleranceTaille * 100).toInt()} %), '
    '${sansVisAVis.length} sans vis-à-vis\n  ${ecarts.join('\n  ')}'
    '${sansVisAVis.isEmpty ? '' : '\n  sans vis-à-vis : ${sansVisAVis.join(' | ')}'}',
  );

  expect(total, greaterThan(5), reason: 'Relevé trop court : plancher.');

  final courant = {
    'elements': total,
    'apparies': apparies,
    'alignes': alignes,
    'dimensionnes': dimensionnes,
  };

  if (Platform.environment['FIGER_GEOMETRIE'] == '1') {
    final existant = _fichierDette.existsSync()
        ? jsonDecode(_fichierDette.readAsStringSync()) as Map<String, dynamic>
        : <String, dynamic>{};
    existant['_lisez-moi'] =
        'PRODUIT par FIGER_GEOMETRIE=1 flutter test --dart-define=ENV='
        'production test/core/qualite/geometrie_blade_test.dart. Alignement '
        'en pixels par vue (Phase 1D).';
    existant[vue] = courant;
    _fichierDette.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(existant)}\n',
    );
    return;
  }

  expect(_fichierDette.existsSync(), isTrue, reason: 'Cliquet introuvable.');
  final fige =
      (jsonDecode(_fichierDette.readAsStringSync())
              as Map<String, dynamic>)[vue]
          as Map<String, dynamic>?;
  expect(fige, isNotNull, reason: '$vue sans cliquet : FIGER_GEOMETRIE=1.');
  expect(
    jsonEncode(courant),
    jsonEncode({for (final k in courant.keys) k: fige![k]}),
    reason:
        'La géométrie de $vue a changé : un recul est une régression, un '
        'progrès se fige (FIGER_GEOMETRIE=1).',
  );
}

/// La mesure ne vaut que SANS la pastille « Environnement : … », qui décale la
/// page de ~20 px : `--dart-define=ENV=production`, sinon le cas s'ignore (même
/// mécanisme que les tests d'intégration).
bool _horsProduction() {
  if (!Environnement.actuel.bandeauVisible) return false;
  markTestSkipped(
    'Mesure de géométrie : lancer avec --dart-define=ENV=production '
    '(la pastille d’environnement décale la page).',
  );
  return true;
}

Future<void> _capturer(WidgetTester tester, Key cle, String vue) async {
  if (Platform.environment['FIGER_GEOMETRIE'] != '1') return;
  await tester.runAsync(() async {
    final frontiere = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(cle),
    );
    final image = await frontiere.toImage();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final dossier = Directory('tool/conformite_blade/captures')
      ..createSync(recursive: true);
    File(
      '${dossier.path}/flutter__${vue.replaceAll('/', '__')}.png',
    ).writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('livewire/connexion : alignement en pixels', (tester) async {
    if (_horsProduction()) return;
    await _chargerInter();
    const vue = 'livewire/connexion';
    final releve = _releveNavigateur(vue);

    tester.view
      ..physicalSize = releve.fenetre
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const cleCapture = Key('capture-flutter');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [aucunCompteProvider.overrideWith((ref) async => false)],
        child: RepaintBoundary(
          key: cleCapture,
          child: MaterialApp(
            // Le ruban « DEBUG » n'est pas un élément de l'écran.
            debugShowCheckedModeBanner: false,
            theme: AppTheme.clair,
            home: const EcranConnexion(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await _capturer(tester, cleCapture, vue);
    _evaluer(vue: vue, releve: releve, rendu: collecterGlyphes(tester));
  });

  testWidgets('chassis/administrateur : barres en pixels', (tester) async {
    if (_horsProduction()) return;
    await _chargerInter();
    const vue = 'chassis/administrateur';
    final releve = _releveNavigateur(vue);

    // Les droits de l'administrateur : ceux que la vue a servis (Phase 1B).
    final barre =
        jsonDecode(
              File(
                'tool/conformite_blade/structure/barre-laterale.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final droits =
        ((barre['roles'] as Map<String, dynamic>)['administrateur']
                as Map<String, dynamic>)['droits']
            as Map<String, dynamic>;

    await monterCoquille(
      tester,
      role: 'administrateur',
      droits: droits,
      routeActive: '/tableau-de-bord',
      taille: releve.fenetre,
      login: 'capture.admin',
    );

    await _capturer(tester, const Key('capture-flutter'), vue);
    _evaluer(vue: vue, releve: releve, rendu: collecterGlyphes(tester));
  });

  // Complétude : toute vue portée est relevée dans le navigateur, sauf l'écran
  // de démarrage (minuteur, jamais au repos). Sans cette garde, une vue
  // ajoutée sans relevé échapperait à la mesure en silence.
  test('toute vue portée a un relevé de géométrie', () {
    const sansReleve = {
      'demarrage',
      // Les sept vues du lot D, entrées à `casEcrans` le 15/10/2026 pour la
      // mesure d'EMPLACEMENT (Phase 1A, relevé PHP). Leur relevé de GÉOMÉTRIE
      // se prend dans un navigateur avec le script de capture de la Phase 1D,
      // absent du dépôt (seuls ses relevés, à 1383 × 729 et DPR 2,5, y sont) :
      // le fabriquer ici donnerait un autre instrument que celui des
      // vingt-quatre vues relevées. À capturer, puis à retirer d'ici une par
      // une — chacune le DIT, aucune n'est oubliée.
      'comptabilite/hub',
      'transverse/aide-a-propos',
      'transverse/contact-editeur',
      'transverse/import-export',
      'transverse/journal-audit',
      'transverse/mon-profil',
      'transverse/roles-permissions',
      // « Synchroniser les postes » (18/10/2026, décision PO) : même cas —
      // mesurée en emplacement, relevé de géométrie à capturer.
      'transverse/synchronisation-postes',
      // « Congés & Plannings » (21/10/2026) : mesurée en emplacement ; relevé
      // de géométrie à capturer dans le navigateur de la Phase 1D.
      'rh/conges-plannings',
    };
    final manquantes = [
      for (final cas in casEcrans)
        if (!sansReleve.contains(cas.vue) &&
            !File(
              'tool/conformite_blade/geometrie/${cas.vue.replaceAll('/', '__')}.json',
            ).existsSync())
          cas.vue,
    ];
    expect(
      manquantes,
      isEmpty,
      reason: 'Vues sans relevé de géométrie : $manquantes.',
    );
    // Une exemption PÉRIMÉE (le relevé existe désormais) se retire.
    expect(
      [
        for (final v in sansReleve)
          if (File(
            'tool/conformite_blade/geometrie/${v.replaceAll('/', '__')}.json',
          ).existsSync())
            v,
      ],
      isEmpty,
      reason: 'Relevé présent : retirer la vue de `sansReleve`.',
    );
  });

  // Toutes les vues dont la géométrie a été relevée dans le navigateur.
  for (final cas in casEcrans) {
    const speciaux = {'livewire/connexion', 'demarrage'};
    final fichier = File(
      'tool/conformite_blade/geometrie/${cas.vue.replaceAll('/', '__')}.json',
    );
    if (speciaux.contains(cas.vue) || !fichier.existsSync()) continue;

    testWidgets('${cas.vue} : alignement en pixels', (tester) async {
      if (_horsProduction()) return;
      await _chargerInter();
      final releve = _releveNavigateur(cas.vue);

      final db = AppDatabase.enMemoire();
      addTearDown(db.close);
      switch (cas.jeu) {
        case JeuEcran.clients:
          await semerClients(db);
        case JeuEcran.parc:
          await semerParc(db);
        case JeuEcran.vide:
          break;
      }

      // La page est montée DANS la coquille, à la taille de la fenêtre du
      // navigateur : le contenu part du même point (264 px, 64 px).
      final droits = {
        for (final m in const [
          'M1',
          'M2',
          'M3',
          'M4',
          'M5',
          'M6',
          'M7',
          'M8',
          'M9',
          'M10',
          'M11',
          'M12',
          'M13',
          'M14',
          'ROLES',
          'PARAM',
        ])
          m: 'C',
      };
      await monterCoquille(
        tester,
        role: 'administrateur',
        droits: droits,
        routeActive: '/tableau-de-bord',
        taille: releve.fenetre,
        login: 'capture.admin',
        enfant: cas.ecran(),
        surcharges: [
          baseLocaleProvider.overrideWithValue(db),
          ...cas.surcharges(db),
        ],
      );
      await tester.pumpAndSettle();

      // Le CONTENU de la page seulement : les barres ont leur mesure.
      final contenu = (
        fenetre: releve.fenetre,
        elements: [
          for (final b in releve.elements)
            if (b.x >= 264 && b.y >= 64) b,
        ],
      );
      _evaluer(
        vue: cas.vue,
        releve: contenu,
        rendu: [
          for (final e in collecterGlyphes(tester))
            if (e.boite.left >= 264 && e.boite.top >= 64) e,
        ],
      );
    });
  }
}
