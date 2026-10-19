import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/achats/data/achats_api.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/archivage_fournisseur.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/commande_achat.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/fournisseur.dart';
import 'package:tatacora_flutter/features/achats/domain/messages_achats.dart';
import 'package:tatacora_flutter/features/achats/impression/etat_liste_achats.dart';
import 'package:tatacora_flutter/features/achats/presentation/ecran_fournisseurs.dart';
import 'package:tatacora_flutter/features/achats/presentation/providers_achats.dart';
import 'package:tatacora_flutter/features/achats/presentation/widgets/composants_crud_achats.dart';
import 'package:tatacora_flutter/features/achats/presentation/widgets/modale_archivage_achats.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';

/// L'écran « Fournisseurs & Achats », mesuré sur ce qu'il rend effectivement
/// — textes, boutons, messages — et non sur son code source.
///
/// Source de vérité : `pwa/achats/achats.blade.php`. Les libellés attendus ici
/// sont ceux de la vue, relus par `conformite_achats_test.dart` ; ce fichier
/// éprouve les COMPORTEMENTS (sélection, export, archivage, pagination).
///
/// Aucun réseau. Depuis le 09/10/2026 `AchatsApi` lit la base LOCALE : ce
/// fichier garde ses listes SURCHARGÉES (il éprouve les comportements de
/// l'écran, pas la source) mais monte une base en mémoire VIDE sous chaque
/// cas — un provider non surchargé lit alors une vraie base, jamais le fichier
/// de la machine. La chaîne complète, sans aucune surcharge de liste, est
/// éprouvée par `chaine_reelle_achats_test.dart`.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.enMemoire());
  tearDown(() => db.close());

  const sodis = Fournisseur(
    id: 'f1',
    raisonSociale: 'SODIS SARL',
    contact: '01 90 12 34 56',
    categorie: 'Boissons',
    conditionsPaiement: '30 jours',
    evaluationCode: 'excellent',
    actif: true,
  );
  const marche = Fournisseur(
    id: 'f2',
    raisonSociale: 'Marché Central',
    contact: null,
    categorie: null,
    conditionsPaiement: 'Comptant',
    evaluationCode: 'bon',
    actif: false,
  );
  const kora = Fournisseur(
    id: 'f3',
    raisonSociale: 'Ets Kora',
    contact: '97 00 00 00',
    categorie: 'Carburant',
    conditionsPaiement: null,
    evaluationCode: null,
    actif: true,
  );
  const trois = [sodis, marche, kora];

  Override fournisseurs(
    List<Fournisseur> liste, {
    int? total,
    int derniere = 1,
    void Function(int page, EvaluationFournisseur? evaluation)? surAppel,
  }) {
    return fournisseursProvider.overrideWith((ref, _) async {
      final page = ref.watch(pageFournisseurProvider);
      final evaluation = ref.watch(evaluationFournisseurProvider);
      surAppel?.call(page, evaluation);
      return AchatsRecu(
        PageAchats<Fournisseur>(
          elements: liste,
          total: total ?? liste.length,
          derniere: derniere,
        ),
      );
    });
  }

  /// L'ouverture de la confirmation, avec un lot composé des fiches de [trois] :
  /// les ACTIVES visées partent, les archivées sont écartées, [engages] (id ->
  /// nombre de commandes en cours) en retire et en motive. Un faux de LISTE, pas
  /// du DAO : la composition réelle est confrontée au serveur dans
  /// `archivage_contre_serveur_test.dart`.
  Override preparer({Map<String, int> engages = const {}}) {
    return preparerArchivageProvider.overrideWithValue((ids) async {
      final actives = [
        for (final f in trois)
          if (ids.contains(f.id) && f.actif) f,
      ]..sort((a, b) => a.raisonSociale.compareTo(b.raisonSociale));
      final partent = [
        for (final f in actives)
          if (!engages.containsKey(f.id)) f.id,
      ];
      return AchatsRecu(
        LotArchivage(
          ids: partent,
          motifs: [
            for (final f in actives)
              if (engages.containsKey(f.id))
                '${f.raisonSociale} — '
                    '${MessagesAchats.verrouArchivage(engages[f.id]!)}',
          ],
          conserves: engages.keys
              .where((id) => actives.any((f) => f.id == id))
              .length,
          bloque: partent.isEmpty,
          libelle: actives.length == 1 ? actives.single.raisonSociale : '',
        ),
      );
    });
  }

  Override commandes(List<CommandeAchat> liste) {
    return commandesAchatsProvider.overrideWith(
      (ref, _) async => AchatsRecu(
        PageAchats<CommandeAchat>(
          elements: liste,
          total: liste.length,
          derniere: 1,
        ),
      ),
    );
  }

  Future<void> monter(
    WidgetTester tester, {
    List<Override> surcharges = const [],
    String droit = 'C',
    String role = 'administrateur',
    bool avecSession = true,
    GoRouter? routeur,
  }) async {
    tester.view
      ..physicalSize = const Size(1600, 2400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final droits = GardeAcces.depuisJson({'M7': droit});
    final base = [
      baseLocaleProvider.overrideWithValue(db),
      droitsProvider.overrideWithValue(droits),
      // Le RÔLE de la session compte : « Supprimer » n'est offert qu'à un rôle
      // d'administration, ou à tout rôle en `C` quand la bascule est ouverte.
      // `administrateur` par défaut — le profil qui archive sans condition.
      if (avecSession)
        sessionProvider.overrideWithBuild(
          (ref, notifier) => Session(
            utilisateurId: 'u-essai',
            login: 'essai',
            nom: 'Essai',
            role: role,
            droits: droits,
          ),
        ),
      ...surcharges,
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: base,
        child: routeur == null
            ? MaterialApp(
                theme: AppTheme.clair,
                home: const Scaffold(body: EcranFournisseurs()),
              )
            : MaterialApp.router(theme: AppTheme.clair, routerConfig: routeur),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Tous les textes d'un widget, dans l'ordre.
  List<String> textesDe(WidgetTester tester, Finder dans) => [
    for (final t in tester.widgetList<Text>(
      find.descendant(of: dans, matching: find.byType(Text), matchRoot: true),
    ))
      t.data ?? t.textSpan!.toPlainText(),
  ];

  String? messageSnack(WidgetTester tester) {
    final f = find.byType(SnackBar);
    if (f.evaluate().isEmpty) return null;
    final t = find.descendant(of: f, matching: find.byType(Text));
    return tester.widget<Text>(t.first).data;
  }

  /* ================================================================== */
  group('La page, dans l’ordre de la vue', () {
    testWidgets('titre, sous-titre au mot, deux onglets cliquables', (
      tester,
    ) async {
      await monter(tester, surcharges: [fournisseurs(const [])]);

      expect(find.text('Fournisseurs & Achats'), findsOneWidget);
      // Le sous-titre de la vue, SANS la correction que ce client y portait.
      expect(
        find.text(
          "Référentiel fournisseurs, commandes d'achat et rapprochement à "
          'trois voies',
        ),
        findsOneWidget,
      );
      // ... et la réserve est dite à part, en bas de page.
      expect(
        textesDe(tester, find.byKey(const Key('achats-note-rapprochement'))),
        [
          'Le rapprochement de ce poste ne confronte que deux voies, '
              'commande et réception : la facture fournisseur n’a aucune '
              'table. Il ne vaut donc pas autorisation de paiement.',
        ],
      );

      final fournisseursOnglet = find.byKey(
        const Key('onglet-achats-fournisseurs'),
      );
      final commandesOnglet = find.byKey(const Key('onglet-achats-commandes'));
      expect(textesDe(tester, fournisseursOnglet), ['Fournisseurs']);
      expect(textesDe(tester, commandesOnglet), ["Commandes d'achat"]);

      // L'onglet bascule réellement : la recherche et les colonnes changent.
      expect(find.text('Rechercher un fournisseur...'), findsOneWidget);
      await tester.tap(commandesOnglet);
      await tester.pumpAndSettle();
      expect(find.text('Rechercher un fournisseur...'), findsNothing);
      expect(
        find.text('Rechercher une commande (fournisseur)...'),
        findsOneWidget,
      );
      expect(find.text('DATE DE COMMANDE'), findsOneWidget);
      expect(find.text('MONTANT ESTIMÉ'), findsOneWidget);
      expect(find.text('CONTACT'), findsNothing);
    });

    testWidgets('les six en-têtes de colonne, en MAJUSCULES, dans l’ordre', (
      tester,
    ) async {
      await monter(tester, surcharges: [fournisseurs(const [])]);

      final entetes = [
        'FOURNISSEUR',
        'CONTACT',
        'CATÉGORIE FOURNIE',
        'CONDITIONS',
        'ÉVALUATION',
        'ACTIONS',
      ];
      final x = [for (final e in entetes) tester.getTopLeft(find.text(e)).dx];
      expect(
        [...x]..sort(),
        x,
        reason: 'Les colonnes ne sont pas dans l’ordre de la vue',
      );
    });

    testWidgets('liste VIDE reçue : « Aucun résultat » et un décompte à zéro', (
      tester,
    ) async {
      await monter(tester, surcharges: [fournisseurs(const [])]);

      expect(find.text('Aucun résultat'), findsOneWidget);
      expect(
        find.text('Essayez de modifier votre recherche ou vos filtres.'),
        findsOneWidget,
      );
      expect(textesDe(tester, find.byType(PiedTableauAchats)), [
        'Affichage de ',
        '0',
        '-',
        '0',
        ' sur ',
        '0',
      ]);
    });

    testWidgets('liste ABSENTE : le motif, jamais « Aucun résultat »', (
      tester,
    ) async {
      // La base locale répond toujours : une liste n'est « absente » que si le
      // DROIT de lire manque (M7 à « - »). `AchatsApi` rend alors le refus.
      await monter(tester, droit: '-');

      expect(find.text('Aucun résultat'), findsNothing);
      expect(find.text(MessagesAchats.droitLectureRefuse), findsOneWidget);
      // Le décompte ne dit PAS « 0 sur 0 » : il dit qu'il ne sait pas.
      expect(textesDe(tester, find.byType(PiedTableauAchats)), [
        'Affichage de ',
        '—',
        '-',
        '—',
        ' sur ',
        '—',
      ]);
    });
  });

  /* ================================================================== */
  group('Les lignes', () {
    testWidgets('trois fiches : cellules, tirets, badges, actions', (
      tester,
    ) async {
      await monter(tester, surcharges: [fournisseurs(trois)]);

      expect(find.text('SODIS SARL'), findsOneWidget);
      expect(find.text('01 90 12 34 56'), findsOneWidget);
      expect(find.text('Boissons'), findsOneWidget);
      expect(find.text('30 jours'), findsOneWidget);

      // Évaluation : libellé en pastille, ou « — » pour une fiche non évaluée.
      expect(
        textesDe(tester, find.byKey(const Key('fournisseur-evaluation-f1'))),
        ['Excellent'],
      );
      expect(
        textesDe(tester, find.byKey(const Key('fournisseur-evaluation-f2'))),
        ['Bon'],
      );
      expect(
        find.byKey(const Key('fournisseur-evaluation-f3')),
        findsNothing,
        reason: 'Une fiche non évaluée n’a pas de pastille',
      );

      // Contact absent (f2), catégorie absente (f2), conditions absentes (f3),
      // évaluation absente (f3) : quatre tirets, pas un de plus.
      expect(find.text('—'), findsNWidgets(4));

      // « Archivé » ne marque QUE la fiche archivée.
      expect(find.byKey(const Key('fournisseur-archive-f2')), findsOneWidget);
      expect(find.byKey(const Key('fournisseur-archive-f1')), findsNothing);
      expect(find.byKey(const Key('fournisseur-archive-f3')), findsNothing);
      expect(find.text('Archivé'), findsOneWidget);

      // Une fiche active se supprime (archive) ; une fiche archivée se restaure.
      expect(find.byKey(const Key('fournisseur-supprimer-f1')), findsOneWidget);
      expect(find.byKey(const Key('fournisseur-restaurer-f1')), findsNothing);
      expect(find.byKey(const Key('fournisseur-supprimer-f2')), findsNothing);
      expect(find.byKey(const Key('fournisseur-restaurer-f2')), findsOneWidget);
      expect(find.text('Voir le détail'), findsNWidgets(3));
      expect(find.text('Modifier'), findsNWidgets(3));
      expect(find.text('Supprimer'), findsNWidgets(2));
      expect(find.text('Restaurer'), findsOneWidget);

      expect(textesDe(tester, find.byType(PiedTableauAchats)), [
        'Affichage de ',
        '1',
        '-',
        '3',
        ' sur ',
        '3',
      ]);
    });

    testWidgets(
      'en lecture seule : ni création, ni modification, ni archivage',
      (tester) async {
        await monter(tester, droit: 'L', surcharges: [fournisseurs(trois)]);

        expect(find.text('Ajouter fournisseur'), findsNothing);
        expect(find.text('Modifier'), findsNothing);
        expect(find.text('Supprimer'), findsNothing);
        expect(find.text('Restaurer'), findsNothing);
        // La consultation, elle, reste : « Voir le détail » et « Exporter ».
        expect(find.text('Voir le détail'), findsNWidgets(3));
        expect(find.text('Exporter'), findsOneWidget);
      },
    );

    testWidgets('« Voir le détail » : cinq paires, « — » pour l’absent', (
      tester,
    ) async {
      await monter(tester, surcharges: [fournisseurs(trois)]);

      await tester.tap(find.byKey(const Key('fournisseur-detail-f2')));
      await tester.pumpAndSettle();

      final modale = find.byKey(const Key('modale-detail-fournisseur'));
      expect(find.text('Détail — Marché Central'), findsOneWidget);
      expect(
        textesDe(tester, modale).where((t) => t != 'Détail — Marché Central'),
        [
          'Fournisseur',
          'Marché Central',
          'Contact',
          '—',
          'Catégorie fournie',
          '—',
          'Conditions',
          'Comptant',
          'Évaluation',
          'Bon',
          'Fermer',
          'Modifier',
        ],
      );

      await tester.tap(find.byKey(const Key('detail-fournisseur-fermer')));
      await tester.pumpAndSettle();
      expect(modale, findsNothing);
    });

    testWidgets('le détail d’une fiche NON ÉVALUÉE rend « — », pas une note', (
      tester,
    ) async {
      await monter(tester, surcharges: [fournisseurs(trois)]);

      await tester.tap(find.byKey(const Key('fournisseur-detail-f3')));
      await tester.pumpAndSettle();

      final textes = textesDe(
        tester,
        find.byKey(const Key('modale-detail-fournisseur')),
      );
      final i = textes.indexOf('Évaluation');
      expect(textes[i + 1], '—');
      expect(textes, isNot(contains('Non évaluée')));
      expect(textes, isNot(contains('À revoir')));
    });

    testWidgets('« Modifier » du détail ouvre le formulaire pré-rempli', (
      tester,
    ) async {
      await monter(tester, surcharges: [fournisseurs(trois)]);

      await tester.tap(find.byKey(const Key('fournisseur-detail-f1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('detail-fournisseur-modifier')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('modale-detail-fournisseur')), findsNothing);
      expect(find.text('Modifier le fournisseur'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('fournisseur-raison-sociale')),
            )
            .controller!
            .text,
        'SODIS SARL',
      );
    });

    testWidgets('en lecture seule le détail n’offre pas « Modifier »', (
      tester,
    ) async {
      await monter(tester, droit: 'L', surcharges: [fournisseurs(trois)]);

      await tester.tap(find.byKey(const Key('fournisseur-detail-f1')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('detail-fournisseur-fermer')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('detail-fournisseur-modifier')),
        findsNothing,
      );
    });
  });

  /* ================================================================== */
  group('Le formulaire', () {
    testWidgets('« Ajouter fournisseur » : les mots de la vue, au mot', (
      tester,
    ) async {
      await monter(tester, surcharges: [fournisseurs(const [])]);

      await tester.tap(find.byKey(const Key('achats-fournisseurs-ajouter')));
      await tester.pumpAndSettle();

      final modale = find.byKey(const Key('modale-fournisseur'));
      expect(
        textesDe(tester, modale),
        containsAllInOrder([
          'Nouveau fournisseur',
          "Le fournisseur est une vraie clé étrangère des commandes d'achat : "
              'il se choisit dans cette liste, il ne se saisit jamais en texte '
              'libre.',
          'Raison sociale',
          'Contact (téléphone)',
          'Catégorie fournie',
          'Conditions de paiement',
          'Évaluation',
          'Annuler',
          'Enregistrer',
        ]),
      );
      expect(find.text('Ex. Grand Marché Natitingou SARL'), findsOneWidget);
      expect(find.text('01 90 12 34 56'), findsOneWidget);
      // Trois listes, trois « Non renseigné » — et plus « Sans catégorie ».
      expect(find.text('Non renseigné'), findsNWidgets(3));
      expect(find.text('Sans catégorie'), findsNothing);
    });

    testWidgets('sans raison sociale : refusé AVANT tout envoi', (
      tester,
    ) async {
      await monter(tester, surcharges: [fournisseurs(const [])]);

      await tester.tap(find.byKey(const Key('achats-fournisseurs-ajouter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('fournisseur-enregistrer')));
      await tester.pumpAndSettle();

      expect(find.text('La raison sociale est obligatoire.'), findsOneWidget);
      expect(find.byKey(const Key('fournisseur-refus')), findsNothing);
    });

    testWidgets(
      'saisie valide SANS session : le refus est DIT, rien n’est écrit',
      (tester) async {
        await monter(
          tester,
          avecSession: false,
          surcharges: [fournisseurs(const [])],
        );

        await tester.tap(find.byKey(const Key('achats-fournisseurs-ajouter')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('fournisseur-raison-sociale')),
          'Brasserie du Nord',
        );
        await tester.tap(find.byKey(const Key('fournisseur-enregistrer')));
        await tester.pumpAndSettle();

        // Aucune session n'est ouverte dans ce montage : une écriture sans
        // « qui » ne s'écrit pas (RG-15). La chaîne COMPLÈTE avec une session est
        // éprouvée par `chaine_reelle_achats_test.dart`.
        expect(textesDe(tester, find.byKey(const Key('fournisseur-refus'))), [
          MessagesAchats.auteurInconnu,
        ]);
        // La saisie reste affichée.
        expect(find.text('Brasserie du Nord'), findsOneWidget);
        expect(find.byKey(const Key('modale-fournisseur')), findsOneWidget);
      },
    );
  });

  /* ================================================================== */
  group('La sélection et l’archivage', () {
    testWidgets(
      'deux cases cochées : barre « 2 sélectionné(s) », compte exact',
      (tester) async {
        await monter(tester, surcharges: [fournisseurs(trois)]);

        expect(find.byKey(const Key('achats-selection-compte')), findsNothing);

        await tester.tap(find.byKey(const Key('fournisseur-case-f1')));
        await tester.tap(find.byKey(const Key('fournisseur-case-f3')));
        await tester.pumpAndSettle();

        expect(
          textesDe(tester, find.byKey(const Key('achats-selection-compte'))),
          ['2 sélectionné(s)'],
        );
        // « Supprimer » de la barre, « Exporter » de la barre, la croix.
        expect(
          find.byKey(const Key('achats-selection-supprimer')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('achats-selection-effacer')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('achats-selection-compte')), findsNothing);
      },
    );

    testWidgets('« tout sélectionner » coche les trois lignes affichées', (
      tester,
    ) async {
      await monter(tester, surcharges: [fournisseurs(trois)]);

      await tester.tap(find.byKey(const Key('achats-fournisseurs-tout')));
      await tester.pumpAndSettle();

      expect(
        textesDe(tester, find.byKey(const Key('achats-selection-compte'))),
        ['3 sélectionné(s)'],
      );
    });

    testWidgets('la sélection ne survit pas à un changement de filtre', (
      tester,
    ) async {
      await monter(tester, surcharges: [fournisseurs(trois)]);

      await tester.tap(find.byKey(const Key('fournisseur-case-f1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('achats-selection-compte')), findsOneWidget);

      await tester.tap(find.byKey(const Key('filtre-four')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Excellent').last);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('achats-selection-compte')), findsNothing);
    });

    testWidgets(
      'archiver DEUX fiches : la question du lot, puis les ids exacts',
      (tester) async {
        final appels = <List<String>>[];
        await monter(
          tester,
          surcharges: [
            fournisseurs(trois),
            preparer(),
            archiverFournisseursProvider.overrideWithValue((ids) async {
              appels.add(ids);
              return const AchatsRecu(
                ResultatArchivage(archives: 2, refus: null),
              );
            }),
          ],
        );

        await tester.tap(find.byKey(const Key('fournisseur-case-f1')));
        await tester.tap(find.byKey(const Key('fournisseur-case-f3')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('achats-selection-supprimer')));
        await tester.pumpAndSettle();

        expect(find.text('Confirmer la suppression'), findsOneWidget);
        expect(
          textesDe(tester, find.byKey(const Key('achats-archivage-question'))),
          ['Voulez-vous archiver les 2 élément(s) sélectionnés ?'],
        );
        expect(appels, isEmpty, reason: 'Rien ne part avant la confirmation');

        await tester.tap(find.byKey(const Key('achats-archivage-confirmer')));
        await tester.pumpAndSettle();

        // Les ids du LOT (triés par raison sociale), pas ceux de la sélection.
        expect(appels, [
          ['f3', 'f1'],
        ]);
        expect(
          messageSnack(tester),
          '2 fournisseurs archivés — ils restent restaurables.',
        );
      },
    );

    testWidgets('une fiche ARCHIVÉE cochée n’est pas renvoyée à l’archivage', (
      tester,
    ) async {
      final appels = <List<String>>[];
      await monter(
        tester,
        surcharges: [
          fournisseurs(trois),
          preparer(),
          archiverFournisseursProvider.overrideWithValue((ids) async {
            appels.add(ids);
            return const AchatsRecu(
              ResultatArchivage(archives: 1, refus: null),
            );
          }),
        ],
      );

      await tester.tap(find.byKey(const Key('fournisseur-case-f1')));
      await tester.tap(find.byKey(const Key('fournisseur-case-f2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('achats-selection-supprimer')));
      await tester.pumpAndSettle();

      // La question porte sur la SEULE fiche active, nommée.
      expect(
        textesDe(tester, find.byKey(const Key('achats-archivage-question'))),
        ['Voulez-vous archiver SODIS SARL ?'],
      );
      await tester.tap(find.byKey(const Key('achats-archivage-confirmer')));
      await tester.pumpAndSettle();

      expect(appels, [
        ['f1'],
      ]);
      expect(
        messageSnack(tester),
        'Fournisseur archivé — il reste restaurable.',
      );
    });

    testWidgets(
      'que des fiches DÉJÀ archivées cochées : la modale s’ouvre BLOQUÉE, comme la vue (D271)',
      (tester) async {
        final appels = <List<String>>[];
        await monter(
          tester,
          surcharges: [
            fournisseurs(trois),
            preparer(),
            archiverFournisseursProvider.overrideWithValue((ids) async {
              appels.add(ids);
              return const AchatsRecu(
                ResultatArchivage(archives: 0, refus: null),
              );
            }),
          ],
        );

        await tester.tap(find.byKey(const Key('fournisseur-case-f2')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('achats-selection-supprimer')));
        await tester.pumpAndSettle();

        // Le serveur n'écrit PAS « déjà archivés » : il ouvre la modale, lot
        // vide donc bloqué, sans motif. Ce poste affichait un message de son cru.
        expect(
          find.byKey(const Key('modale-archivage-achats')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('achats-archivage-impossible')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('achats-archivage-confirmer')),
          findsNothing,
          reason: 'le bouton DISPARAÎT quand tout est bloqué',
        );
        expect(
          find.text('Les fournisseurs cochés sont déjà archivés.'),
          findsNothing,
        );
        expect(appels, isEmpty);
      },
    );

    testWidgets(
      'un fournisseur ENGAGÉ : l’état PARTIEL annonce AVANT le clic combien resteront',
      (tester) async {
        final appels = <List<String>>[];
        await monter(
          tester,
          surcharges: [
            fournisseurs(trois),
            preparer(engages: {'f3': 2}),
            archiverFournisseursProvider.overrideWithValue((ids) async {
              appels.add(ids);
              return const AchatsRecu(
                ResultatArchivage(archives: 1, refus: null),
              );
            }),
          ],
        );

        await tester.tap(find.byKey(const Key('fournisseur-case-f1')));
        await tester.tap(find.byKey(const Key('fournisseur-case-f3')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('achats-selection-supprimer')));
        await tester.pumpAndSettle();

        // Un seul part : la question porte sur CE nombre, pas sur la sélection.
        expect(
          textesDe(tester, find.byKey(const Key('achats-archivage-question'))),
          ['Voulez-vous archiver les 1 élément(s) sélectionnés ?'],
        );
        expect(
          textesDe(tester, find.byKey(const Key('achats-archivage-conserves'))),
          ['1 élément(s) seront conservés : ils sont engagés ailleurs.'],
        );
        expect(
          find.text(
            'Ets Kora — Engagé dans 2 commande(s) d\'achat en cours : la '
            'réception à venir a besoin de ce fournisseur au sélecteur.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('achats-archivage-confirmer')));
        await tester.pumpAndSettle();

        expect(appels, [
          ['f1'],
        ]);
      },
    );

    testWidgets(
      'tout est engagé : l’état BLOQUÉ liste les motifs, sans bouton',
      (tester) async {
        await monter(
          tester,
          surcharges: [
            fournisseurs(trois),
            preparer(engages: {'f1': 1}),
          ],
        );

        await tester.tap(find.byKey(const Key('fournisseur-supprimer-f1')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('achats-archivage-impossible')),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'SODIS SARL — Engagé dans 1 commande(s) d\'achat',
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('achats-archivage-confirmer')),
          findsNothing,
        );
      },
    );

    testWidgets('« Annuler » n’archive rien', (tester) async {
      final appels = <List<String>>[];
      await monter(
        tester,
        surcharges: [
          fournisseurs(trois),
          preparer(),
          archiverFournisseursProvider.overrideWithValue((ids) async {
            appels.add(ids);
            return const AchatsRecu(
              ResultatArchivage(archives: 1, refus: null),
            );
          }),
        ],
      );

      await tester.tap(find.byKey(const Key('fournisseur-supprimer-f1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('achats-archivage-annuler')));
      await tester.pumpAndSettle();

      expect(appels, isEmpty);
      expect(find.byKey(const Key('modale-archivage-achats')), findsNothing);
    });

    testWidgets(
      'un engagement né ENTRE l’ouverture et le clic : le succès ET le refus s’affichent',
      (tester) async {
        await monter(
          tester,
          surcharges: [
            fournisseurs(trois),
            preparer(),
            archiverFournisseursProvider.overrideWithValue(
              (ids) async => AchatsRecu(
                ResultatArchivage(
                  archives: 1,
                  refus: MessagesAchats.verrouArchivage(1),
                ),
              ),
            ),
          ],
        );

        await tester.tap(find.byKey(const Key('fournisseur-case-f1')));
        await tester.tap(find.byKey(const Key('fournisseur-case-f3')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('achats-selection-supprimer')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('achats-archivage-confirmer')));
        await tester.pumpAndSettle();

        // Le refus du service est rendu HORS de la modale (un toast posé dedans
        // n'apparaîtrait jamais), et le succès des autres reste dit.
        expect(find.byKey(const Key('achats-archivage-refus')), findsOneWidget);
        expect(
          find.byKey(const Key('achats-archivage-succes')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'un refus d’OUVERTURE (bascule fermée refermée entre-temps) est dit en toast',
      (tester) async {
        await monter(
          tester,
          surcharges: [
            fournisseurs(trois),
            preparerArchivageProvider.overrideWithValue(
              (ids) async => const AchatsRefuse<LotArchivage>(
                motif: MessagesAchats.refusBascule,
                code: 403,
              ),
            ),
          ],
        );

        await tester.tap(find.byKey(const Key('fournisseur-supprimer-f3')));
        await tester.pumpAndSettle();

        expect(messageSnack(tester), MessagesAchats.refusBascule);
        expect(find.byKey(const Key('modale-archivage-achats')), findsNothing);
      },
    );

    testWidgets('« Restaurer » : le message de la vue, nom compris', (
      tester,
    ) async {
      final appels = <String>[];
      await monter(
        tester,
        surcharges: [
          fournisseurs(trois),
          restaurerFournisseurProvider.overrideWithValue((id) async {
            appels.add(id);
            return const AchatsRecu(marche);
          }),
        ],
      );

      await tester.tap(find.byKey(const Key('fournisseur-restaurer-f2')));
      await tester.pumpAndSettle();

      expect(appels, ['f2']);
      expect(
        messageSnack(tester),
        'Fournisseur « Marché Central » restauré : il revient au sélecteur '
        'des commandes.',
      );
    });

    testWidgets('« Restaurer » rend le refus du service tel quel', (
      tester,
    ) async {
      await monter(
        tester,
        surcharges: [
          fournisseurs(trois),
          restaurerFournisseurProvider.overrideWithValue(
            (id) async => const AchatsRefuse<Fournisseur>(
              motif: MessagesAchats.droitEcritureRefuse,
              code: 403,
            ),
          ),
        ],
      );

      await tester.tap(find.byKey(const Key('fournisseur-restaurer-f2')));
      await tester.pumpAndSettle();

      expect(messageSnack(tester), MessagesAchats.droitEcritureRefuse);
    });
  });

  /* ================================================================== */
  group('QUI voit « Supprimer » : la règle unique d’archivage (D63)', () {
    Future<void> bascule(String? valeur) async {
      if (valeur == null) return;
      await db
          .into(db.parametresSystemeLocal)
          .insert(
            ParametresSystemeLocalCompanion.insert(
              cle: 'activation_suppression',
              valeur: valeur,
              modifieLe: DateTime(2026, 10, 13),
            ),
          );
    }

    Future<void> verifier(
      WidgetTester tester, {
      required String role,
      required String droit,
      String? valeur,
      required bool supprimer,
      required bool lien,
    }) async {
      await bascule(valeur);
      await monter(
        tester,
        droit: droit,
        role: role,
        surcharges: [fournisseurs(trois)],
      );
      // Un actif (f1) : son « Supprimer » de ligne. Un archivé (f2) : son
      // « Restaurer », qui n'est PAS derrière la même garde.
      expect(
        find.byKey(const Key('fournisseur-supprimer-f1')).evaluate().isNotEmpty,
        supprimer,
        reason: 'ligne : $role / $droit / bascule=$valeur',
      );
      await tester.tap(find.byKey(const Key('fournisseur-case-f1')));
      await tester.pumpAndSettle();
      expect(
        find
            .byKey(const Key('achats-selection-supprimer'))
            .evaluate()
            .isNotEmpty,
        lien,
        reason: 'barre : $role / $droit / bascule=$valeur',
      );
    }

    testWidgets('administrateur en C : oui, SANS la bascule', (tester) async {
      await verifier(
        tester,
        role: 'administrateur',
        droit: 'C',
        supprimer: true,
        lien: true,
      );
    });

    testWidgets('super_admin en C : oui, sans la bascule', (tester) async {
      await verifier(
        tester,
        role: 'super_admin',
        droit: 'C',
        supprimer: true,
        lien: true,
      );
    });

    testWidgets('un autre rôle en C, bascule ABSENTE (défaut fermé) : non', (
      tester,
    ) async {
      await verifier(
        tester,
        role: 'achats',
        droit: 'C',
        supprimer: false,
        lien: false,
      );
    });

    testWidgets('un autre rôle en C, bascule FERMÉE : non', (tester) async {
      await verifier(
        tester,
        role: 'achats',
        droit: 'C',
        valeur: 'false',
        supprimer: false,
        lien: false,
      );
    });

    testWidgets('un autre rôle en C, bascule OUVERTE : oui', (tester) async {
      await verifier(
        tester,
        role: 'achats',
        droit: 'C',
        valeur: 'true',
        supprimer: true,
        lien: true,
      );
    });

    testWidgets('un administrateur en LECTURE : jamais', (tester) async {
      await verifier(
        tester,
        role: 'administrateur',
        droit: 'L',
        valeur: 'true',
        supprimer: false,
        lien: false,
      );
    });

    testWidgets('« Restaurer » reste offert bascule fermée (jamais enfermé)', (
      tester,
    ) async {
      await monter(tester, role: 'achats', surcharges: [fournisseurs(trois)]);

      expect(find.byKey(const Key('fournisseur-supprimer-f1')), findsNothing);
      expect(find.byKey(const Key('fournisseur-restaurer-f2')), findsOneWidget);
    });
  });

  /* ================================================================== */
  group('La modale d’archivage rend les TROIS états de la vue', () {
    Future<void> poser(WidgetTester tester, Widget modale) async {
      tester.view
        ..physicalSize = const Size(1600, 2400)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.clair,
          home: Scaffold(body: modale),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('NOMINAL : la question nommée, le rappel, les deux boutons', (
      tester,
    ) async {
      await poser(tester, const ModaleArchivageAchats(element: 'SODIS SARL'));

      expect(
        textesDe(tester, find.byKey(const Key('achats-archivage-question'))),
        ['Voulez-vous archiver SODIS SARL ?'],
      );
      expect(textesDe(tester, find.byKey(const Key('achats-archivage-rappel'))), [
        "L'élément part aux archives et reste restaurable — rien n'est effacé.",
      ]);
      expect(find.text('Supprimer définitivement'), findsOneWidget);
      expect(find.text('Annuler'), findsOneWidget);
      expect(find.byKey(const Key('achats-archivage-conserves')), findsNothing);
    });

    testWidgets('PARTIEL : le décompte des conservés, AVANT le clic', (
      tester,
    ) async {
      await poser(
        tester,
        const ModaleArchivageAchats(
          nombre: 3,
          conserves: 1,
          messagesVerrou: ['Engagé dans 2 commande(s) d\'achat en cours.'],
        ),
      );

      expect(
        find.text('1 élément(s) seront conservés : ils sont engagés ailleurs.'),
        findsOneWidget,
      );
      expect(
        find.text("Engagé dans 2 commande(s) d'achat en cours."),
        findsOneWidget,
      );
      expect(find.text('Supprimer définitivement'), findsOneWidget);
    });

    testWidgets('BLOQUÉ : le bouton DISPARAÎT, il n’est pas grisé', (
      tester,
    ) async {
      await poser(
        tester,
        const ModaleArchivageAchats(
          element: 'SODIS SARL',
          bloque: true,
          messagesVerrou: ["Engagé dans 1 commande(s) d'achat en cours."],
        ),
      );

      expect(find.text('Archivage impossible'), findsOneWidget);
      expect(
        find.text("Engagé dans 1 commande(s) d'achat en cours."),
        findsOneWidget,
      );
      expect(
        find.text(
          "Retirez d'abord l'élément des opérations concernées, ou laissez-le "
          'en place : une carte historique reste lisible.',
        ),
        findsOneWidget,
      );
      expect(find.text('Supprimer définitivement'), findsNothing);
      expect(find.byKey(const Key('achats-archivage-question')), findsNothing);
      expect(find.text('Annuler'), findsOneWidget);
    });
  });

  /* ================================================================== */
  group('L’export porte sur ce qui est AFFICHÉ, et il le dit', () {
    testWidgets('trois lignes, format tableur : colonnes et lignes exactes', (
      tester,
    ) async {
      ListeAchats? produite;
      await monter(
        tester,
        surcharges: [
          fournisseurs(trois),
          exporterListeAchatsProvider.overrideWithValue((liste) async {
            produite = liste;
            return '/tmp/fournisseurs.csv';
          }),
        ],
      );

      await tester.tap(find.byKey(const Key('achats-fournisseurs-exporter')));
      await tester.pumpAndSettle();

      expect(find.text('Exporter — Fournisseurs'), findsOneWidget);
      expect(
        find.text(
          'Le document portera exactement les 3 ligne(s) affichées, filtres '
          'compris.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('export-format-excel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-generer')));
      await tester.pumpAndSettle();

      expect(produite!.entetes, [
        'Fournisseur',
        'Contact',
        'Catégorie fournie',
        'Conditions',
        'Évaluation',
      ]);
      expect(produite!.lignes, [
        ['SODIS SARL', '01 90 12 34 56', 'Boissons', '30 jours', 'Excellent'],
        ['Marché Central', '', '', 'Comptant', 'Bon'],
        ['Ets Kora', '97 00 00 00', 'Carburant', '', 'Non évaluée'],
      ]);
      expect(produite!.portee.filtre, 'Toutes les évaluations');
      expect(messageSnack(tester), 'Export enregistré : fournisseurs.csv');
    });

    testWidgets('le format PDF appelle l’export PDF, pas le tableur', (
      tester,
    ) async {
      ListeAchats? imprimee;
      var tableur = 0;
      await monter(
        tester,
        surcharges: [
          fournisseurs(trois),
          exporterListeAchatsPdfProvider.overrideWithValue((liste) async {
            imprimee = liste;
            return '/tmp/fournisseurs.pdf';
          }),
          exporterListeAchatsProvider.overrideWithValue((liste) async {
            tableur++;
            return '';
          }),
        ],
      );

      await tester.tap(find.byKey(const Key('achats-fournisseurs-exporter')));
      await tester.pumpAndSettle();
      // Le PDF est le format présélectionné de la modale.
      await tester.tap(find.byKey(const Key('export-generer')));
      await tester.pumpAndSettle();

      expect(imprimee!.lignes.length, 3);
      expect(tableur, 0);
      // L'issue est DITE par le toast commun (14/10/2026).
      expect(messageSnack(tester), 'Export enregistré : fournisseurs.pdf');
    });

    testWidgets('une sélection de UNE ligne : seule celle-là part, et le dit', (
      tester,
    ) async {
      ListeAchats? produite;
      await monter(
        tester,
        surcharges: [
          fournisseurs(trois),
          exporterListeAchatsProvider.overrideWithValue((liste) async {
            produite = liste;
            return '/tmp/x.csv';
          }),
        ],
      );

      await tester.tap(find.byKey(const Key('fournisseur-case-f3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('achats-selection-exporter')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Le document portera exactement les 1 ligne(s) sélectionnées.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('export-format-excel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-generer')));
      await tester.pumpAndSettle();

      expect(produite!.lignes, [
        ['Ets Kora', '97 00 00 00', 'Carburant', '', 'Non évaluée'],
      ]);
      expect(
        produite!.portee.filtre,
        'Toutes les évaluations — sélection de 1 ligne(s)',
      );
      expect(
        produite!.portee.estTronquee,
        isFalse,
        reason: 'Une sélection est exportée en entier',
      );
    });

    testWidgets('liste vide : l’export est REFUSÉ, avec le mot de la vue', (
      tester,
    ) async {
      await monter(tester, surcharges: [fournisseurs(const [])]);

      await tester.tap(find.byKey(const Key('achats-fournisseurs-exporter')));
      await tester.pumpAndSettle();

      expect(messageSnack(tester), messageExportVide);
      expect(find.text('Exporter — Fournisseurs'), findsNothing);
    });

    testWidgets(
      'liste ABSENTE : le refus nomme l’absence, pas un filtre vide',
      (tester) async {
        await monter(tester, droit: '-');

        await tester.tap(find.byKey(const Key('achats-fournisseurs-exporter')));
        await tester.pumpAndSettle();

        expect(messageSnack(tester), MessagesAchats.droitLectureRefuse);
      },
    );
  });

  /* ================================================================== */
  group('La pagination est réelle', () {
    testWidgets(
      '25 lignes sur 60 : décompte, page 1 / 3, « Suivant » seul actif',
      (tester) async {
        final pages = <int>[];
        final liste = [
          for (var i = 0; i < 25; i++)
            Fournisseur(
              id: 'p$i',
              raisonSociale: 'Fournisseur $i',
              contact: null,
              categorie: null,
              conditionsPaiement: null,
              evaluationCode: null,
              actif: true,
            ),
        ];
        await monter(
          tester,
          surcharges: [
            fournisseurs(
              liste,
              total: 60,
              derniere: 3,
              surAppel: (page, _) => pages.add(page),
            ),
          ],
        );

        expect(textesDe(tester, find.byType(PiedTableauAchats)).take(6), [
          'Affichage de ',
          '1',
          '-',
          '25',
          ' sur ',
          '60',
        ]);
        expect(find.text('Page 1 / 3'), findsOneWidget);
        // Page 1 : « ← Précédent » est un TEXTE grisé, pas un bouton.
        expect(
          find.ancestor(
            of: find.byKey(const Key('achats-page-precedente')),
            matching: find.byType(InkWell),
          ),
          findsNothing,
        );
        expect(find.byKey(const Key('achats-page-suivante')), findsOneWidget);
        expect(pages, [1]);

        await tester.ensureVisible(
          find.byKey(const Key('achats-page-suivante')),
        );
        await tester.tap(find.byKey(const Key('achats-page-suivante')));
        await tester.pumpAndSettle();

        expect(pages, [1, 2]);
        expect(find.text('Page 2 / 3'), findsOneWidget);
        expect(textesDe(tester, find.byType(PiedTableauAchats)).take(6), [
          'Affichage de ',
          '26',
          '-',
          '50',
          ' sur ',
          '60',
        ]);
      },
    );

    testWidgets('une seule page : aucun lien de pagination', (tester) async {
      await monter(tester, surcharges: [fournisseurs(trois)]);

      expect(find.byKey(const Key('achats-page-suivante')), findsNothing);
      expect(find.byKey(const Key('achats-page-precedente')), findsNothing);
    });

    testWidgets('changer de filtre ramène à la page 1', (tester) async {
      final appels = <(int, EvaluationFournisseur?)>[];
      await monter(
        tester,
        surcharges: [
          fournisseurs(
            trois,
            total: 60,
            derniere: 3,
            surAppel: (p, e) => appels.add((p, e)),
          ),
        ],
      );

      await tester.ensureVisible(find.byKey(const Key('achats-page-suivante')));
      await tester.tap(find.byKey(const Key('achats-page-suivante')));
      await tester.pumpAndSettle();
      expect(appels.last, (2, null));

      await tester.tap(find.byKey(const Key('filtre-four')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Moyen').last);
      await tester.pumpAndSettle();

      expect(appels.last, (1, EvaluationFournisseur.moyen));
    });
  });

  /* ================================================================== */
  group('L’onglet « Commandes d’achat »', () {
    const commande = CommandeAchat(
      id: 'c1',
      dateCommande: '2026-10-09',
      statutCode: 'receptionnee_partiellement',
      fournisseurId: 'f1',
      fournisseurRaisonSociale: 'SODIS SARL',
      nombreLignes: 2,
      montantTotal: '56000.00',
      montantRegle: '0.00',
      resteDu: '56000.00',
      receptionnable: true,
      cloturable: false,
    );
    const sansNom = CommandeAchat(
      id: 'c2',
      dateCommande: '2026-10-10',
      statutCode: 'brouillon',
      fournisseurId: 'f9',
      fournisseurRaisonSociale: '',
      nombreLignes: 1,
      montantTotal: 'illisible',
      montantRegle: '0.00',
      resteDu: '0.00',
      receptionnable: false,
      cloturable: false,
    );

    Future<void> ouvrir(WidgetTester tester, {String droit = 'C'}) async {
      await monter(
        tester,
        droit: droit,
        surcharges: [
          fournisseurs(const []),
          commandes(const [commande, sansNom]),
        ],
      );
      await tester.tap(find.byKey(const Key('onglet-achats-commandes')));
      await tester.pumpAndSettle();
    }

    testWidgets('cellules : date d/m/Y, montant FCFA, tirets, pastille', (
      tester,
    ) async {
      await ouvrir(tester);

      expect(find.text('SODIS SARL'), findsOneWidget);
      expect(find.text('09/10/2026'), findsOneWidget);
      expect(find.text('10/10/2026'), findsOneWidget);
      expect(textesDe(tester, find.byKey(const Key('commande-montant-c1'))), [
        '56 000 FCFA',
      ]);
      // Un montant illisible n'est pas zéro : il rend « — ».
      expect(textesDe(tester, find.byKey(const Key('commande-montant-c2'))), [
        '—',
      ]);
      // Une raison sociale non jointe rend « — », jamais l'identifiant.
      expect(
        textesDe(tester, find.byKey(const Key('commande-fournisseur-c2'))),
        ['—'],
      );
      expect(textesDe(tester, find.byKey(const Key('commande-statut-c1'))), [
        'Réceptionnée partiellement',
      ]);
      expect(textesDe(tester, find.byKey(const Key('commande-statut-c2'))), [
        'Brouillon',
      ]);
      expect(textesDe(tester, find.byType(PiedTableauAchats)), [
        'Affichage de ',
        '1',
        '-',
        '2',
        ' sur ',
        '2',
      ]);
    });

    testWidgets(
      'le filtre propose « Tous les statuts » puis les CINQ statuts',
      (tester) async {
        await ouvrir(tester);

        await tester.tap(find.byKey(const Key('filtre-commandes-achats')));
        await tester.pumpAndSettle();

        expect(find.text('Tous les statuts'), findsWidgets);
        for (final s in [
          'Brouillon',
          'Envoyée',
          'Réceptionnée partiellement',
          'Réceptionnée',
          'Clôturée',
        ]) {
          expect(find.text(s), findsWidgets, reason: s);
        }
      },
    );

    testWidgets(
      'la sélection n’offre PAS « Supprimer » : une commande ne s’archive pas',
      (tester) async {
        await ouvrir(tester);

        await tester.tap(find.byKey(const Key('commande-case-c1')));
        await tester.pumpAndSettle();

        expect(
          textesDe(tester, find.byKey(const Key('achats-selection-compte'))),
          ['1 sélectionné(s)'],
        );
        expect(
          find.byKey(const Key('achats-selection-supprimer')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('achats-selection-exporter')),
          findsOneWidget,
        );
      },
    );

    testWidgets('l’export des commandes : titre, colonnes, montant brut', (
      tester,
    ) async {
      ListeAchats? produite;
      await monter(
        tester,
        surcharges: [
          fournisseurs(const []),
          commandes(const [commande]),
          exporterListeAchatsProvider.overrideWithValue((liste) async {
            produite = liste;
            return '/tmp/c.csv';
          }),
        ],
      );
      await tester.tap(find.byKey(const Key('onglet-achats-commandes')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('achats-commandes-exporter')));
      await tester.pumpAndSettle();

      expect(find.text("Exporter — Commandes d'achat"), findsOneWidget);
      await tester.tap(find.byKey(const Key('export-format-excel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-generer')));
      await tester.pumpAndSettle();

      expect(produite!.entetes, [
        'Fournisseur',
        'Date de commande',
        'Montant estimé',
        'Statut',
      ]);
      expect(produite!.lignes, [
        ['SODIS SARL', '2026-10-09', '56000.00', 'Réceptionnée partiellement'],
      ]);
      expect(produite!.colonnesNumeriques, {2});
    });

    testWidgets(
      '« Voir le détail » et « Ajouter commande d’achat » mènent à l’Approvisionnement',
      (tester) async {
        var versAppro = 0;
        final routeur = GoRouter(
          initialLocation: '/fournisseurs',
          routes: [
            GoRoute(
              path: '/fournisseurs',
              builder: (_, _) => const Scaffold(body: EcranFournisseurs()),
            ),
            GoRoute(
              path: '/approvisionnement',
              builder: (_, _) {
                versAppro++;
                return const Scaffold(body: Text('APPROVISIONNEMENT'));
              },
            ),
          ],
        );
        addTearDown(routeur.dispose);

        await monter(
          tester,
          routeur: routeur,
          surcharges: [
            fournisseurs(const []),
            commandes(const [commande]),
          ],
        );
        await tester.tap(find.byKey(const Key('onglet-achats-commandes')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('commande-detail-c1')));
        await tester.pumpAndSettle();
        expect(find.text('APPROVISIONNEMENT'), findsOneWidget);
        expect(versAppro, 1);

        routeur.go('/fournisseurs');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('onglet-achats-commandes')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('achats-commandes-ajouter')));
        await tester.pumpAndSettle();
        expect(find.text('APPROVISIONNEMENT'), findsOneWidget);
        expect(versAppro, 2);
      },
    );

    testWidgets('en lecture seule : pas de « Ajouter commande d’achat »', (
      tester,
    ) async {
      await ouvrir(tester, droit: 'L');

      expect(find.text("Ajouter commande d'achat"), findsNothing);
      expect(find.text('Voir le détail'), findsNWidgets(2));
    });

    testWidgets('liste ABSENTE : le motif, jamais « Aucun résultat »', (
      tester,
    ) async {
      await monter(tester, droit: '-');
      await tester.tap(find.byKey(const Key('onglet-achats-commandes')));
      await tester.pumpAndSettle();

      expect(find.text('Aucun résultat'), findsNothing);
      expect(find.text(MessagesAchats.droitLectureRefuse), findsOneWidget);
    });
  });
}
