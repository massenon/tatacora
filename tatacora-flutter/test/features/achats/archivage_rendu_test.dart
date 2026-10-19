@Timeout(Duration(minutes: 3))
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/achats/presentation/ecran_fournisseurs.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_dao.dart';
import 'package:tatacora_flutter/features/parametres/domain/options_systeme.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import 'support/outils_reglement.dart';

/// Ce que l'écran « Fournisseurs & Achats » MONTRE à chaque profil, confronté au
/// HTML que le vrai composant `Achats` rend sur le serveur : quels boutons
/// portent la ligne d'un fournisseur actif et celle d'un fournisseur archivé, et
/// si la barre de sélection offre le lien « Supprimer ».
///
/// `archivage_contre_serveur_test.dart` compare la RÈGLE (qui peut archiver) ;
/// celui-ci compare ce qui est RENDU : un bouton qui apparaît pour un profil que
/// la règle exclut, ou disparaît pour celui qu'elle admet, ne se voit que sur
/// l'écran. Les cellules du serveur sont lues du HTML rendu, jamais recalculées.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final maintenant = DateTime(2026, 10, 13, 10);

  Map<String, Object?> liste(String user) => {'op': 'liste', 'user': user};
  Map<String, Object?> barre(String user) => {
    'op': 'barre_lot',
    'user': user,
    'fournisseurs': ['f1'],
  };

  // Les profils, dans l'ordre où le scénario les joue.
  final profils = <({String user, String role, String droit, String? bascule})>[
    (user: 'a', role: 'administrateur', droit: 'C', bascule: null),
    (user: 'ac', role: 'achats', droit: 'C', bascule: null),
    (user: 'ac', role: 'achats', droit: 'C', bascule: 'true'),
    (user: 'ac', role: 'achats', droit: 'C', bascule: 'false'),
    (user: 'co', role: 'comptable', droit: 'L', bascule: 'true'),
  ];

  final scenario = <Map<String, Object?>>[
    {'op': 'utilisateur', 'ref': 'a', 'role': 'administrateur'},
    {'op': 'utilisateur', 'ref': 'ac', 'role': 'achats'},
    {'op': 'utilisateur', 'ref': 'co', 'role': 'comptable'},
    {'op': 'fournisseur', 'ref': 'f1', 'nom': 'Alpha'},
    {'op': 'fournisseur', 'ref': 'f2', 'nom': 'Bravo'},
    {
      'op': 'archiver',
      'user': 'a',
      'fournisseurs': ['f2'],
      'confirmer': true,
    },
    for (final p in profils) ...[
      {'op': 'parametre', 'valeur': p.bascule},
      liste(p.user),
      barre(p.user),
    ],
  ];

  late List<dynamic> serveur;

  setUpAll(() async {
    final reponse = await executerPhp(
      'rejouer_archivage.php',
      dossier: 'achats',
      entree: {'aujourdhui': '2026-10-13', 'ops': scenario},
    );
    serveur = reponse['resultats'] as List<dynamic>;
  });

  /// Les cellules du serveur pour le profil de rang [i] : (lignes, lien).
  (List<Map<String, dynamic>>, bool) rendu(int i) {
    final base = scenario.indexWhere((o) => o['op'] == 'liste');
    final r = serveur[base + i * 3] as Map<String, dynamic>;
    final b = serveur[base + i * 3 + 1] as Map<String, dynamic>;
    return (
      (r['lignes'] as List).cast<Map<String, dynamic>>(),
      b['lien_supprimer'] as bool,
    );
  }

  Future<AppDatabase> poste() async {
    final db = AppDatabase.enMemoire();
    addTearDown(db.close);
    await db.customStatement('SELECT 1');
    await semerAuteur(db, id: 'u-a');
    final achats = achatsDaoSur(db, maintenant: maintenant);
    for (final (id, nom) in [('f-f1', 'Alpha'), ('f-f2', 'Bravo')]) {
      await semerCommande(
        db,
        fournisseurId: id,
        fournisseur: nom,
        auteurId: 'u-a',
        statut: 'cloturee',
        maintenant: maintenant,
      );
    }
    // Bravo est ARCHIVÉ (sa commande clôturée ne l'engage pas).
    await achats.archiverFournisseur('f-f2', auteurId: 'u-a');
    return db;
  }

  Future<void> monter(
    WidgetTester tester,
    AppDatabase db, {
    required String role,
    required String droit,
  }) async {
    tester.view
      ..physicalSize = const Size(1600, 2400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final droits = GardeAcces.depuisJson({'M7': droit});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          droitsProvider.overrideWithValue(droits),
          sessionProvider.overrideWithBuild(
            (ref, notifier) => Session(
              utilisateurId: 'u-a',
              login: 'essai',
              nom: 'Essai',
              role: role,
              droits: droits,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranFournisseurs()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Le libellé des boutons d'une ligne, dans l'ordre de la vue.
  String actions(WidgetTester tester, String id) => [
    if (find.byKey(Key('fournisseur-detail-$id')).evaluate().isNotEmpty)
      'Voir le détail',
    if (find.byKey(Key('fournisseur-modifier-$id')).evaluate().isNotEmpty)
      'Modifier',
    if (find.byKey(Key('fournisseur-restaurer-$id')).evaluate().isNotEmpty)
      'Restaurer',
    if (find.byKey(Key('fournisseur-supprimer-$id')).evaluate().isNotEmpty)
      'Supprimer',
  ].join(' ');

  for (var i = 0; i < profils.length; i++) {
    final p = profils[i];
    testWidgets(
      '${p.role} en ${p.droit}, bascule ${p.bascule ?? 'absente'} : les '
      'boutons du serveur',
      (tester) async {
        final db = await poste();
        await ParametresDao(
          db,
          maintenant: () => maintenant,
        ).ecrire({OptionsSysteme.cleSuppression: p.bascule}, auteurId: null);
        await monter(tester, db, role: p.role, droit: p.droit);

        final (lignes, lien) = rendu(i);
        expect(lignes, hasLength(2), reason: 'deux fournisseurs listés');

        for (final ligne in lignes) {
          final id = 'f-${ligne['ref']}';
          expect(
            actions(tester, id),
            ligne['actions'],
            reason: 'actions de ${ligne['ref']}',
          );
          // La pastille « Archivé » suit le badge du serveur.
          final archive = (ligne['fournisseur'] as String).endsWith('Archivé');
          expect(
            find.byKey(Key('fournisseur-archive-$id')).evaluate().isNotEmpty,
            archive,
            reason: 'badge de ${ligne['ref']}',
          );
        }

        // La barre de sélection : le lien « Supprimer » n'existe que pour qui
        // peut archiver (jamais grisé, retiré).
        await tester.tap(find.byKey(const Key('fournisseur-case-f-f1')));
        await tester.pumpAndSettle();
        expect(
          find
              .byKey(const Key('achats-selection-supprimer'))
              .evaluate()
              .isNotEmpty,
          lien,
          reason: 'lien de la barre',
        );
      },
    );
  }

  test('le scénario a de quoi comparer : les cinq profils ne disent pas tous '
      'la même chose', () {
    final vus = {
      for (var i = 0; i < profils.length; i++)
        '${rendu(i).$1.map((l) => l['actions']).join('|')}/${rendu(i).$2}',
    };
    expect(vus.length, greaterThanOrEqualTo(3));
    // Le serveur a offert « Supprimer » à l'un, retiré à d'autres.
    expect([
      for (var i = 0; i < profils.length; i++) rendu(i).$2,
    ], containsAll([true, false]));
  });
}
