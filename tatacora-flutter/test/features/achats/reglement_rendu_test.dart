@Timeout(Duration(minutes: 3))
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/achats/domain/messages_reglement.dart';
import 'package:tatacora_flutter/features/achats/presentation/ecran_approvisionnement.dart';
import 'package:tatacora_flutter/features/achats/presentation/providers_achats.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import 'support/outils_reglement.dart';

/// Le RENDU du règlement fournisseur, confronté au HTML que le vrai composant
/// `Approvisionnement` rend sur le serveur : mêmes commandes, mêmes règlements,
/// et la cellule de chaque ligne, lue des deux côtés.
///
/// Ce que ces cas ajoutent à `reglement_contre_serveur_test.dart` : celui-ci
/// compare les DONNÉES (reste dû, groupes, cartes) ; celui-là compare ce qui est
/// DIT à l'écran — le texte de chaque cellule, l'ancienneté, le total d'un
/// fournisseur, le sous-titre de la modale après un refus. Une fonction pure
/// testée sans test de l'appelant est une assertion vide (piège 5).
///
/// Les cellules du serveur sont lues du HTML rendu (`rendu_commandes`,
/// `rendu_dettes`, `rendu_kpis`), jamais recalculées par le script.
void main() {
  final maintenant = DateTime(2026, 10, 13, 10);

  late AppDatabase db;
  late Map<String, String> ids; // ref -> id

  Map<String, Object?> commande(
    String ref,
    String fournisseur,
    String date,
    String statut,
    String article,
    String quantite,
    String prix,
  ) => {
    'op': 'commande',
    'ref': ref,
    'fournisseur': fournisseur,
    'user': 'g',
    'date': date,
    'statut': statut,
    'lignes': [
      {'article': article, 'quantite': quantite, 'prix': prix},
    ],
  };

  final scenario = <Map<String, Object?>>[
    {'op': 'utilisateur', 'ref': 'g', 'role': 'gerant'},
    {'op': 'fournisseur', 'ref': 'f1', 'nom': 'Grand Marche SARL'},
    {'op': 'fournisseur', 'ref': 'f2', 'nom': 'Boulangerie du Nord'},
    {'op': 'article', 'ref': 'a1', 'libelle': 'Sucre'},
    {'op': 'article', 'ref': 'a2', 'libelle': 'Farine'},
    commande('c1', 'f1', '2026-10-01', 'envoyee', 'a1', '4', '1000'),
    commande('c2', 'f1', '2026-09-01', 'brouillon', 'a1', '2', '500'),
    commande('c3', 'f2', '2026-07-01', 'envoyee', 'a2', '10', '250.50'),
    // DATÉE DU FUTUR : une ancienneté négative (« -6 j »), que la vue affiche.
    commande('c4', 'f2', '2026-10-20', 'envoyee', 'a1', '1', '300'),
    // Réceptionnée et jamais payée : hors de l'onglet, dans le « Total dû ».
    commande('c5', 'f1', '2026-08-15', 'envoyee', 'a1', '3', '1000'),
    {'op': 'statut', 'commande': 'c5', 'statut': 'receptionnee'},
    // c1 payée en partie ; c3 SOLDÉE (reste « — », bouton « Régler » retiré).
    {
      'op': 'regler_service',
      'commande': 'c1',
      'user': 'g',
      'montant': '1500',
      'tresorerie': 'caisse',
    },
    {
      'op': 'regler_service',
      'commande': 'c3',
      'user': 'g',
      'montant': '2505',
      'tresorerie': 'momo',
    },
    {'op': 'vue', 'user': 'g'},
    // La modale : ce que le sous-titre dit APRÈS un refus (D261).
    for (final m in ['9000', '0.004', '', '-5', '1500.5'])
      {
        'op': 'regler_pwa',
        'commande': 'c1',
        'user': 'g',
        'montant': m,
        'tresorerie': 'caisse',
        'ouvrir': true,
      },
  ];

  late List<dynamic> serveur;
  late Map<String, dynamic> vueServeur;

  setUpAll(() async {
    final reponse = await executerPhp(
      'rejouer_reglements.php',
      dossier: 'achats',
      entree: {'aujourdhui': '2026-10-13', 'ops': scenario},
    );
    serveur = reponse['resultats'] as List<dynamic>;
    vueServeur =
        serveur[scenario.indexWhere((o) => o['op'] == 'vue')]
            as Map<String, dynamic>;
  });

  setUp(() async {
    db = AppDatabase.enMemoire();
    await db.customStatement('SELECT 1');
    await baseInstalleeSur(db, maintenant);
    await semerAuteur(db, id: 'u-g');
    ids = {};

    // Le MÊME scénario, par les DAO de production.
    final noms = {'f1': 'Grand Marche SARL', 'f2': 'Boulangerie du Nord'};
    for (final op in scenario) {
      switch (op['op']) {
        case 'commande':
          final ligne = (op['lignes']! as List).single as Map<String, dynamic>;
          ids[op['ref']! as String] = await semerCommande(
            db,
            fournisseurId: 'f-${op['fournisseur']}',
            fournisseur: noms[op['fournisseur']]!,
            articleId: 'a-${ligne['article']}',
            quantite: ligne['quantite']! as String,
            prix: ligne['prix']! as String,
            date: op['date']! as String,
            statut: op['statut']! as String,
            auteurId: 'u-g',
            maintenant: maintenant,
          );
        case 'statut':
          await poserStatut(db, ids[op['commande']]!, op['statut']! as String);
        case 'regler_service':
          await reglementsDaoSur(db, maintenant: maintenant).reglerParLeService(
            commandeId: ids[op['commande']]!,
            montant: op['montant']! as String,
            tresorerie: op['tresorerie']! as String,
            auteurId: 'u-g',
          );
      }
    }
  });

  tearDown(() => db.close());

  List<Override> surcharges({String m7 = 'C'}) {
    final droits = GardeAcces({'M7': m7, 'M6': 'C'});
    return [
      baseLocaleProvider.overrideWithValue(db),
      droitsProvider.overrideWithValue(droits),
      sessionProvider.overrideWithBuild(
        (ref, notifier) => Session(
          utilisateurId: 'u-g',
          login: 'g',
          nom: 'Gérant',
          role: 'gerant',
          droits: droits,
        ),
      ),
      reglementsFournisseurDaoProvider.overrideWithValue(
        reglementsDaoSur(db, maintenant: maintenant),
      ),
      horlogeApproProvider.overrideWithValue(() => maintenant),
    ];
  }

  Future<void> monter(WidgetTester tester, {String m7 = 'C'}) async {
    tester.view
      ..physicalSize = const Size(1600, 3200)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: surcharges(m7: m7),
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranApprovisionnement()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> toucher(WidgetTester tester, Key cle) async {
    final cible = find.byKey(cle);
    await tester.ensureVisible(cible);
    await tester.pumpAndSettle();
    await tester.tap(cible);
    await tester.pumpAndSettle();
  }

  String texte(WidgetTester tester, Finder f) {
    // La clé est parfois sur un conteneur (un bandeau) : son texte en descend.
    final direct = tester.widget(f);
    final w = direct is Text
        ? direct
        : tester.widget<Text>(
            find.descendant(of: f, matching: find.byType(Text)).first,
          );
    return _nettoyer(w.data ?? w.textSpan!.toPlainText());
  }

  String valeurCarte(WidgetTester tester, String cle) {
    final textes = [
      for (final t in tester.widgetList<Text>(
        find.descendant(
          of: find.byKey(Key(cle)),
          matching: find.byType(Text),
          matchRoot: true,
        ),
      ))
        _nettoyer(t.data ?? t.textSpan!.toPlainText()),
    ];
    return textes[1];
  }

  group('L’onglet Commandes : Réglé, Reste dû et « Régler »', () {
    testWidgets('chaque ligne dit ce que le HTML du serveur dit', (
      tester,
    ) async {
      await monter(tester);
      await toucher(tester, const Key('onglet-appro-commandes'));

      final lignes = (vueServeur['rendu_commandes'] as List)
          .cast<List<dynamic>>();
      expect(lignes, hasLength(5));

      for (final cellules in lignes) {
        final ref = cellules[0] as String;
        final id = ids[ref]!;
        // « Réglé » (idx 5) et « Reste dû » (idx 6) : « — » à zéro.
        expect(
          texte(tester, find.byKey(Key('commande-regle-$id'))),
          _nettoyer(cellules[5] as String),
          reason: '$ref : Réglé',
        );
        expect(
          texte(tester, find.byKey(Key('commande-reste-$id'))),
          _nettoyer(cellules[6] as String),
          reason: '$ref : Reste dû',
        );
        // Les boutons de la cellule d'actions (idx 8) : « Régler » seulement s'il
        // reste quelque chose à devoir, « Réceptionner » tant que la commande
        // n'est pas close.
        final actions = _nettoyer(cellules[8] as String);
        expect(
          find.byKey(Key('commande-regler-$id')).evaluate().isNotEmpty,
          actions.contains('Régler'),
          reason: '$ref : bouton Régler (« $actions »)',
        );
        expect(
          find.byKey(Key('commande-receptionner-$id')).evaluate().isNotEmpty,
          actions.contains('Réceptionner'),
          reason: '$ref : bouton Réceptionner (« $actions »)',
        );
      }
    });

    testWidgets('un rôle en lecture ne voit AUCUN bouton « Régler »', (
      tester,
    ) async {
      await monter(tester, m7: 'L');
      await toucher(tester, const Key('onglet-appro-commandes'));

      for (final ref in ['c1', 'c2', 'c4', 'c5']) {
        expect(
          find.byKey(Key('commande-regler-${ids[ref]}')),
          findsNothing,
          reason: ref,
        );
      }
      // Les colonnes, elles, restent : lire n'est pas écrire.
      expect(
        texte(tester, find.byKey(Key('commande-reste-${ids['c1']}'))),
        '2 500 FCFA',
      );
    });
  });

  group('L’onglet Dettes fournisseurs, cellule par cellule', () {
    testWidgets('groupes, totaux, ancienneté, montants : comme le HTML', (
      tester,
    ) async {
      await monter(tester);
      await toucher(tester, const Key('onglet-appro-dettes'));

      final groupes = (vueServeur['rendu_dettes'] as List)
          .cast<Map<String, dynamic>>();
      expect(groupes, hasLength(2));

      for (final g in groupes) {
        final nom = g['fournisseur'] as String;
        final fid = nom.startsWith('Boulangerie') ? 'f-f2' : 'f-f1';
        expect(texte(tester, find.byKey(Key('dette-groupe-$fid'))), nom);
        expect(
          texte(tester, find.byKey(Key('dette-groupe-total-$fid'))),
          _nettoyer(g['total'] as String),
          reason: 'total de $nom',
        );
        for (final l in (g['lignes'] as List).cast<List<dynamic>>()) {
          final ref = l[0] as String;
          final id = ids[ref]!;
          expect(texte(tester, find.byKey(Key('dette-commande-$id'))), id);
          expect(
            texte(tester, find.byKey(Key('dette-anciennete-$id'))),
            _nettoyer(l[2] as String),
            reason: '$ref : ancienneté',
          );
          expect(
            texte(tester, find.byKey(Key('dette-montant-$id'))),
            _nettoyer(l[3] as String),
            reason: '$ref : montant',
          );
          expect(
            texte(tester, find.byKey(Key('dette-regle-$id'))),
            _nettoyer(l[4] as String),
            reason: '$ref : réglé',
          );
          expect(
            texte(tester, find.byKey(Key('dette-reste-$id'))),
            _nettoyer(l[5] as String),
            reason: '$ref : reste dû',
          );
        }
      }

      // Une commande réceptionnée n'est PAS dans l'onglet (elle pèse dans le
      // total, pas dans la liste — D262) : ni sa ligne, ni son fournisseur n'y
      // ajoutent rien.
      expect(find.byKey(Key('dette-commande-${ids['c5']}')), findsNothing);

      // L'en-tête : « Total dû » somme TOUTES les commandes, closes comprises.
      expect(
        texte(tester, find.byKey(const Key('dettes-total-du'))),
        'Total dû ${_nettoyer(vueServeur['rendu_total_dettes'] as String)}',
      );
      // … et ce n'est PAS la somme des groupes affichés (3 800 contre 6 800).
      expect(vueServeur['rendu_total_dettes'], isNot('3 800 FCFA'));
    });

    testWidgets('l’ancienneté d’un bon daté du futur est NÉGATIVE, comme '
        'la vue', (tester) async {
      await monter(tester);
      await toucher(tester, const Key('onglet-appro-dettes'));

      expect(
        texte(tester, find.byKey(Key('dette-anciennete-${ids['c4']}'))),
        '-6 j',
      );
    });
  });

  group('Les cartes de la bande', () {
    testWidgets(
      '« Fournisseurs à payer » et « Total dû » : la valeur du HTML',
      (tester) async {
        await monter(tester);

        final kpis = (vueServeur['rendu_kpis'] as Map).cast<String, String>();
        expect(
          valeurCarte(tester, 'kpi-fournisseurs-a-payer'),
          _nettoyer(kpis['Fournisseurs à payer']!),
        );
        expect(
          valeurCarte(tester, 'kpi-total-du'),
          _nettoyer(kpis['Total dû']!),
        );
        expect(
          valeurCarte(tester, 'kpi-commandes-attente'),
          _nettoyer(kpis['Commandes en attente']!),
        );
      },
    );
  });

  group('La modale « Régler »', () {
    Future<void> ouvrir(WidgetTester tester, String ref) async {
      await toucher(tester, const Key('onglet-appro-commandes'));
      await toucher(tester, Key('commande-regler-${ids[ref]}'));
    }

    testWidgets('à l’ouverture : titre, sous-titre, montant proposé, '
        'trésorerie « Caisse », largeur 420', (tester) async {
      await monter(tester);
      await ouvrir(tester, 'c1');

      expect(find.byKey(const Key('modale-reglement')), findsOneWidget);
      expect(find.text('Régler — Grand Marche SARL'), findsOneWidget);
      expect(
        find.text('Commande ${ids['c1']} — reste dû 2 500 FCFA'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('reglement-montant')))
            .controller!
            .text,
        '2500.00',
      );
      expect(find.text('Montant réglé (FCFA)'), findsOneWidget);
      expect(find.text('Trésorerie'), findsOneWidget);
      expect(find.text('Caisse'), findsOneWidget);
      expect(find.text('Enregistrer le règlement'), findsOneWidget);
      expect(find.text('Annuler'), findsOneWidget);
      // La colonne du corps est de 420 (`largeur="420px"`), là où les deux autres
      // modales de M7 offrent les 672 de `max-w-2xl`. Sa largeur RENDUE dépend de
      // la police (celle des boutons, en test, élargit la boîte) : c'est donc le
      // réglage qui est asserté, pas un pixel.
      final colonne = tester.widget<SizedBox>(
        find
            .ancestor(
              of: find.byKey(const Key('reglement-montant')),
              matching: find.byWidgetPredicate(
                (w) => w is SizedBox && w.width != null,
              ),
            )
            .first,
      );
      expect(colonne.width, 420);
    });

    testWidgets('les trois trésoreries de la vue, dans son ordre', (
      tester,
    ) async {
      await monter(tester);
      await ouvrir(tester, 'c1');

      await tester.tap(find.byKey(const Key('reglement-tresorerie')));
      await tester.pumpAndSettle();
      expect(find.text('Caisse'), findsWidgets);
      expect(find.text('Mobile Money'), findsOneWidget);
      expect(find.text('Banque'), findsOneWidget);
      // Le mot de l'écran Dépenses (« Compte bancaire ») n'est PAS celui-ci.
      expect(find.text('Compte bancaire'), findsNothing);
    });

    testWidgets('un règlement partiel : bandeau vert, colonnes et cartes '
        'relues, pièce écrite', (tester) async {
      await monter(tester);
      await ouvrir(tester, 'c1');

      await tester.enterText(
        find.byKey(const Key('reglement-montant')),
        '1000',
      );
      await tester.pumpAndSettle();
      await toucher(tester, const Key('reglement-valider'));

      // Le message de succès recopie la SAISIE brute (D260), sans unité.
      expect(
        texte(tester, find.byKey(const Key('appro-succes'))),
        'Règlement de 1000 enregistré pour Grand Marche SARL.',
      );
      expect(find.byKey(const Key('modale-reglement')), findsNothing);

      // La ligne relit le règlement : réglé 2 500, reste 1 500.
      expect(
        texte(tester, find.byKey(Key('commande-regle-${ids['c1']}'))),
        '2 500 FCFA',
      );
      expect(
        texte(tester, find.byKey(Key('commande-reste-${ids['c1']}'))),
        '1 500 FCFA',
      );
      // La carte aussi : 6 800 - 1 000.
      expect(valeurCarte(tester, 'kpi-total-du'), '5 800 FCFA');

      // Le règlement ET sa pièce comptable sont écrits (Dr 4011 / Cr 5711).
      expect(await compterReglements(db), 3);
      final pieces = await db
          .customSelect(
            'SELECT COUNT(*) AS n FROM ecritures_local WHERE libelle LIKE '
            "'Règlement fournisseur Grand Marche SARL — %'",
          )
          .getSingle();
      expect(pieces.data['n'], 4);
    });

    testWidgets('le solde fait disparaître le bouton « Régler » et affiche '
        '« — »', (tester) async {
      await monter(tester);
      await ouvrir(tester, 'c1');
      await toucher(tester, const Key('reglement-valider')); // le reste proposé

      expect(
        texte(tester, find.byKey(const Key('appro-succes'))),
        'Règlement de 2500.00 enregistré pour Grand Marche SARL.',
      );
      expect(
        texte(tester, find.byKey(Key('commande-reste-${ids['c1']}'))),
        '—',
      );
      expect(find.byKey(Key('commande-regler-${ids['c1']}')), findsNothing);
    });

    testWidgets('un sur-règlement est REFUSÉ sous le champ, la modale reste '
        'ouverte, rien n’est écrit', (tester) async {
      await monter(tester);
      await ouvrir(tester, 'c1');

      await tester.enterText(
        find.byKey(const Key('reglement-montant')),
        '9000',
      );
      await tester.pumpAndSettle();
      await toucher(tester, const Key('reglement-valider'));

      expect(find.byKey(const Key('modale-reglement')), findsOneWidget);
      expect(
        texte(tester, find.byKey(const Key('reglement-erreur-montant'))),
        MessagesReglement.superieurAuReste('2500.00'),
      );
      expect(await compterReglements(db), 2);
    });

    testWidgets('le sous-titre suit le CHAMP après un refus : la valeur du '
        'serveur, cas par cas (D261)', (tester) async {
      await monter(tester);

      // Les opérations « regler_pwa » du scénario (9000, 0.004, '', -5, 1500.5),
      // lues à la suite de la vue.
      final apres = serveur
          .skip(scenario.indexWhere((o) => o['op'] == 'vue') + 1)
          .cast<Map<String, dynamic>>()
          .toList();
      final saisies = ['9000', '0.004', '', '-5', '1500.5'];
      expect(apres, hasLength(saisies.length));

      for (var i = 0; i < saisies.length; i++) {
        final attendu = apres[i];
        // Le serveur a REFUSÉ les quatre premières (le rendu garde la modale) ;
        // la dernière est ACCEPTÉE (1 500.50 <= 2 500) — pas de sous-titre.
        await ouvrir(tester, 'c1');
        await tester.enterText(
          find.byKey(const Key('reglement-montant')),
          saisies[i],
        );
        await tester.pumpAndSettle();
        await toucher(tester, const Key('reglement-valider'));

        if (attendu['sous_titre'] == null) {
          expect(
            find.byKey(const Key('modale-reglement')),
            findsNothing,
            reason: 'saisie « ${saisies[i]} » : acceptée par le serveur',
          );
          continue;
        }
        final reste = _nettoyer(
          (attendu['sous_titre'] as Map)['reste'] as String,
        );
        expect(
          find.text('Commande ${ids['c1']} — reste dû $reste'),
          findsOneWidget,
          reason: 'saisie « ${saisies[i]} » : sous-titre du serveur « $reste »',
        );
        // Fermer la modale pour la suivante.
        await toucher(tester, const Key('modale-achats-annuler'));
      }
    });

    testWidgets('une commande soldée entre-temps : bandeau rouge, la modale '
        'ne s’ouvre pas (erreur « selection » du serveur)', (tester) async {
      await monter(tester);
      await toucher(tester, const Key('onglet-appro-commandes'));
      expect(find.byKey(Key('commande-regler-${ids['c1']}')), findsOneWidget);

      // La commande est soldée DERRIÈRE l'écran (la liste affichée est périmée) :
      // le bouton est encore là, et le geste rouvre l'état réel.
      await reglementsDaoSur(db, maintenant: maintenant).reglerParLeService(
        commandeId: ids['c1']!,
        montant: '2500',
        tresorerie: 'banque',
        auteurId: 'u-g',
      );
      await toucher(tester, Key('commande-regler-${ids['c1']}'));

      expect(find.byKey(const Key('modale-reglement')), findsNothing);
      expect(
        texte(tester, find.byKey(const Key('appro-erreur-selection'))),
        MessagesReglement.commandeSoldee,
      );
      expect(find.byKey(const Key('appro-succes')), findsNothing);
    });
  });
}

/// Les espaces insécables du serveur (U+00A0, U+202F) ramenés à l'espace.
String _nettoyer(String s) => s
    .replaceAll(' ', ' ')
    .replaceAll(' ', ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
