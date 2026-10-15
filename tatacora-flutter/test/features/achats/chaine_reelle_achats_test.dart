import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/achats/data/achats_api.dart';
import 'package:tatacora_flutter/features/achats/data/achats_dao.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/bon_reception.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/commande_achat.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/fournisseur.dart';
import 'package:tatacora_flutter/features/achats/domain/messages_achats.dart';
import 'package:tatacora_flutter/features/achats/impression/etat_liste_achats.dart';
import 'package:tatacora_flutter/features/achats/presentation/ecran_approvisionnement.dart';
import 'package:tatacora_flutter/features/achats/presentation/ecran_fournisseurs.dart';
import 'package:tatacora_flutter/features/achats/presentation/providers_achats.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';

/// M7 par la CHAÎNE RÉELLE : l'écran, les providers, `AchatsApi`, `AchatsDao`,
/// `StocksDao` et la base — **aucune liste surchargée**.
///
/// `ecran_fournisseurs_test.dart` surcharge ses listes et éprouve les
/// comportements de l'écran ; il ne dit rien de ce que la base reçoit. Ces cas
/// partent d'un poste réel (base en mémoire, session ouverte) et vont jusqu'à
/// la ligne écrite : une fonction pure testée sans test de l'appelant est une
/// assertion vide.
void main() {
  late AppDatabase db;
  late StocksDao stocks;
  late Directory dossier;

  setUp(() async {
    db = AppDatabase.enMemoire();
    stocks = StocksDao(db);
    dossier = Directory.systemTemp.createTempSync('chaine_achats_');
    await db
        .into(db.utilisateursLocal)
        .insert(
          UtilisateursLocalCompanion.insert(
            id: 'u-essai',
            login: 'acheteur',
            nom: 'Aïcha',
            role: 'achats',
            droitsJson: '{}',
            sel: 's',
            empreinte: 'e',
            iterations: 1,
            dateCreation: DateTime(2026, 10, 1),
            dateMotDePasse: DateTime(2026, 10, 1),
          ),
        );
  });

  tearDown(() async {
    await db.close();
    if (dossier.existsSync()) dossier.deleteSync(recursive: true);
  });

  List<Override> surcharges({
    String m7 = 'C',
    String m6 = 'C',
    String role = 'achats',
    List<Override> plus = const [],
  }) {
    final droits = GardeAcces({'M7': m7, 'M6': m6});
    return [
      baseLocaleProvider.overrideWithValue(db),
      droitsProvider.overrideWithValue(droits),
      sessionProvider.overrideWithBuild(
        (ref, notifier) => Session(
          utilisateurId: 'u-essai',
          login: 'acheteur',
          nom: 'Aïcha',
          role: role,
          droits: droits,
        ),
      ),
      ...plus,
    ];
  }

  Future<void> monter(
    WidgetTester tester,
    Widget ecran, {
    List<Override>? avec,
  }) async {
    tester.view
      ..physicalSize = const Size(1600, 3200)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: avec ?? surcharges(),
        child: MaterialApp(
          theme: AppTheme.clair,
          home: Scaffold(body: ecran),
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

  Future<void> saisir(WidgetTester tester, Key cle, String texte) async {
    final cible = find.byKey(cle);
    await tester.ensureVisible(cible);
    await tester.pumpAndSettle();
    await tester.enterText(cible, texte);
    await tester.pumpAndSettle();
  }

  Future<void> choisir(WidgetTester tester, Key liste, String libelle) async {
    await toucher(tester, liste);
    await tester.tap(find.text(libelle).last);
    await tester.pumpAndSettle();
  }

  List<String> textesDe(WidgetTester tester, Finder dans) => [
    for (final t in tester.widgetList<Text>(
      find.descendant(of: dans, matching: find.byType(Text), matchRoot: true),
    ))
      t.data ?? t.textSpan!.toPlainText(),
  ];

  String? messageSnack(WidgetTester tester) {
    final f = find.byType(SnackBar);
    if (f.evaluate().isEmpty) return null;
    return tester
        .widget<Text>(find.descendant(of: f, matching: find.byType(Text)).first)
        .data;
  }

  /// La valeur d'une carte de la bande : [libellé en majuscules, valeur].
  String valeurCarte(WidgetTester tester, String cle) =>
      textesDe(tester, find.byKey(Key(cle)))[1];

  Future<void> tolerance(String valeur) => db
      .into(db.parametresSystemeLocal)
      .insertOnConflictUpdate(
        ParametresSystemeLocalCompanion.insert(
          cle: 'tolerance_reception_pct',
          valeur: valeur,
          modifieLe: DateTime(2026, 10, 2),
        ),
      );

  Future<void> semerStock() async {
    await tolerance('5');
    await stocks.creerPoint(libelle: 'Magasin', id: 'p-mag');
    // Riz : 2 sacs en stock à 1 000 F, seuil 5 -> sous le seuil, prix connu.
    await stocks.creerArticle(
      id: 'a-riz',
      libelle: 'Riz local',
      categorie: 'Denrées',
      uniteMesure: 'sac',
      seuilCentiemes: 500,
      suivi: SuiviArticle.permanent,
      pointStockageId: null,
    );
    await stocks.ajouterMouvement(
      articleId: 'a-riz',
      pointId: 'p-mag',
      type: TypeMouvement.entree,
      centiemes: 200,
      motif: 'Reprise',
      auteurId: 'u-essai',
      coutDixMilliemes: 10000000,
    );
    // Sel : 0 en stock, seuil 3, JAMAIS réceptionné -> prix inconnu.
    await stocks.creerArticle(
      id: 'a-sel',
      libelle: 'Sel',
      categorie: 'Denrées',
      uniteMesure: 'kg',
      seuilCentiemes: 300,
      suivi: SuiviArticle.permanent,
      pointStockageId: null,
    );
  }

  Future<int> compte(ResultSetImplementation<HasResultSet, dynamic> t) async =>
      (await db.select(t).get()).length;

  /* ==================================================================== */
  /* Fournisseurs & Achats                                                 */
  /* ==================================================================== */

  group('Fournisseurs & Achats, par la chaîne réelle', () {
    testWidgets(
      'un poste neuf : « Aucun résultat » est la VÉRITÉ, pas un refus',
      (tester) async {
        await monter(tester, const EcranFournisseurs());

        expect(find.text('Aucun résultat'), findsOneWidget);
        expect(find.text(MessagesAchats.droitLectureRefuse), findsNothing);
      },
    );

    testWidgets(
      'créer un fournisseur par la fenêtre : la ligne est ÉCRITE, relue, et dite « sur ce poste »',
      (tester) async {
        await monter(tester, const EcranFournisseurs());

        await toucher(tester, const Key('achats-fournisseurs-ajouter'));
        await saisir(
          tester,
          const Key('fournisseur-raison-sociale'),
          'Brasserie du Nord',
        );
        await toucher(tester, const Key('fournisseur-enregistrer'));

        // La fenêtre se ferme, le message dit OÙ c'est enregistré.
        expect(find.byKey(const Key('modale-fournisseur')), findsNothing);
        expect(
          messageSnack(tester),
          'Fournisseur « Brasserie du Nord » enregistré sur ce poste.',
        );
        expect(messageSnack(tester), isNot(contains('synchronisation')));

        // La ligne est réellement en base, sous l'identité de la session.
        final ligne = await db.select(db.fournisseursLocal).getSingle();
        expect(ligne.raisonSociale, 'Brasserie du Nord');
        expect(ligne.creePar, 'u-essai');
        expect(ligne.contact, isNull);

        // ... et la liste l'a RELUE : elle n'a pas été insérée en mémoire.
        expect(
          find.byKey(Key('fournisseur-ligne-${ligne.id}')),
          findsOneWidget,
        );
        expect(find.text('Aucun résultat'), findsNothing);
      },
    );

    testWidgets(
      'modifier : le formulaire est pré-rempli, la ligne est mise à jour, la création est conservée',
      (tester) async {
        final api = AchatsDao(db, stocks: stocks);
        await api.creerFournisseur(
          const SaisieFournisseur(
            id: 'f-1',
            raisonSociale: 'SODIS',
            contact: '01 90',
            categorie: 'Boissons',
            conditionsPaiement: '30 jours',
            evaluationCode: 'bon',
          ),
          auteurId: 'u-essai',
        );
        await monter(tester, const EcranFournisseurs());

        await toucher(tester, const Key('fournisseur-modifier-f-1'));
        final champ = tester.widget<TextFormField>(
          find.byKey(const Key('fournisseur-raison-sociale')),
        );
        expect(champ.controller?.text, 'SODIS');

        await saisir(
          tester,
          const Key('fournisseur-raison-sociale'),
          'SODIS SARL',
        );
        await toucher(tester, const Key('fournisseur-enregistrer'));

        final ligne = await db.select(db.fournisseursLocal).getSingle();
        expect(ligne.raisonSociale, 'SODIS SARL');
        // Rouvrir la fiche ne remplace PAS en silence les autres champs.
        expect(ligne.categorie, 'Boissons');
        expect(ligne.conditionsPaiement, '30 jours');
        expect(ligne.evaluation, 'bon');
        expect(ligne.modifiePar, 'u-essai');
        expect(find.text('SODIS SARL'), findsOneWidget);
      },
    );

    /// Un fournisseur « SODIS » (f-1) par le DAO de production.
    Future<void> sodis({String id = 'f-1', String nom = 'SODIS'}) =>
        AchatsDao(db, stocks: stocks).creerFournisseur(
          SaisieFournisseur(
            id: id,
            raisonSociale: nom,
            contact: null,
            categorie: null,
            conditionsPaiement: null,
            evaluationCode: null,
          ),
          auteurId: 'u-essai',
        );

    testWidgets(
      '« Supprimer » ARCHIVE pour de vrai : la fiche est marquée, jamais effacée, et '
      'restaurable (administrateur, sans la bascule)',
      (tester) async {
        await sodis();
        await monter(
          tester,
          const EcranFournisseurs(),
          avec: surcharges(role: 'administrateur'),
        );

        await toucher(tester, const Key('fournisseur-supprimer-f-1'));
        // La question porte sur la fiche nommée, puis le rappel : rien n'est effacé.
        expect(
          textesDe(tester, find.byKey(const Key('achats-archivage-question'))),
          ['Voulez-vous archiver SODIS ?'],
        );
        await toucher(tester, const Key('achats-archivage-confirmer'));

        final ligne = await db.select(db.fournisseursLocal).getSingle();
        expect(ligne.actif, isFalse);
        expect(ligne.modifiePar, 'u-essai');
        expect(ligne.modifieLe, isNotNull);
        expect(messageSnack(tester), MessagesAchats.archivesSucces(1));
        // La fiche reste dans la liste, marquée « Archivé », et ne propose plus
        // que « Restaurer ».
        expect(
          find.byKey(const Key('fournisseur-archive-f-1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('fournisseur-supprimer-f-1')),
          findsNothing,
        );

        // Le message précédent est dit ; on le retire pour lire le suivant.
        ScaffoldMessenger.of(
          tester.element(find.byType(Scaffold).first),
        ).clearSnackBars();
        await tester.pumpAndSettle();

        await toucher(tester, const Key('fournisseur-restaurer-f-1'));
        expect(
          (await db.select(db.fournisseursLocal).getSingle()).actif,
          isTrue,
        );
        expect(messageSnack(tester), MessagesAchats.restaure('SODIS'));
        expect(find.byKey(const Key('fournisseur-archive-f-1')), findsNothing);
      },
    );

    testWidgets(
      'un fournisseur ENGAGÉ dans une commande en cours : la modale s’ouvre BLOQUÉE et '
      'RIEN n’est écrit',
      (tester) async {
        await sodis();
        await stocks.creerArticle(
          id: 'a-riz',
          libelle: 'Riz',
          categorie: 'Denrées',
          uniteMesure: 'sac',
          seuilCentiemes: 500,
          suivi: SuiviArticle.permanent,
          pointStockageId: null,
        );
        await AchatsDao(db, stocks: stocks).creerCommande(
          const SaisieCommande(
            fournisseurId: 'f-1',
            dateCommande: '2026-10-09',
            statut: StatutCommande.envoyee,
            lignes: [
              LigneSaisieCommande(
                articleId: 'a-riz',
                libelle: 'Riz',
                uniteMesure: 'sac',
                quantite: '5',
                prixUnitaire: '1000',
              ),
            ],
          ),
          auteurId: 'u-essai',
        );
        await monter(
          tester,
          const EcranFournisseurs(),
          avec: surcharges(role: 'administrateur'),
        );
        final avant = await db.select(db.fournisseursLocal).getSingle();

        await toucher(tester, const Key('fournisseur-supprimer-f-1'));

        expect(
          find.byKey(const Key('achats-archivage-impossible')),
          findsOneWidget,
        );
        expect(
          find.text('SODIS — ${MessagesAchats.verrouArchivage(1)}'),
          findsOneWidget,
        );
        // Le bouton de confirmation DISPARAÎT : il n'y a rien à confirmer.
        expect(
          find.byKey(const Key('achats-archivage-confirmer')),
          findsNothing,
        );
        await toucher(tester, const Key('achats-archivage-annuler'));

        final apres = await db.select(db.fournisseursLocal).getSingle();
        expect(apres.actif, isTrue);
        expect(apres.modifieLe, avant.modifieLe);
      },
    );

    testWidgets(
      'la BASCULE ouverte en Paramètres ouvre « Supprimer » à un rôle ordinaire — '
      'et sa fermeture le retire (lue depuis la base, sans cache)',
      (tester) async {
        await sodis();

        // Fermée (défaut) : un acheteur ne voit pas « Supprimer ».
        await monter(
          tester,
          const EcranFournisseurs(),
          avec: surcharges(role: 'achats'),
        );
        expect(
          find.byKey(const Key('fournisseur-supprimer-f-1')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('fournisseur-modifier-f-1')),
          findsOneWidget,
        );

        // Ouverte par un Administrateur : l'écran SUIVANT le montre. L'écran
        // précédent est d'abord démonté (un écran quitté oublie la valeur, qui est
        // `autoDispose`) — comme la navigation de l'application.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await db
            .into(db.parametresSystemeLocal)
            .insert(
              ParametresSystemeLocalCompanion.insert(
                cle: 'activation_suppression',
                valeur: 'true',
                modifieLe: DateTime(2026, 10, 13),
              ),
            );
        await monter(
          tester,
          const EcranFournisseurs(),
          avec: surcharges(role: 'achats'),
        );
        expect(
          find.byKey(const Key('fournisseur-supprimer-f-1')),
          findsOneWidget,
        );
        await toucher(tester, const Key('fournisseur-supprimer-f-1'));
        await toucher(tester, const Key('achats-archivage-confirmer'));
        expect(
          (await db.select(db.fournisseursLocal).getSingle()).actif,
          isFalse,
        );

        // Refermée : « Restaurer » reste offert (jamais enfermé), « Supprimer » non.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await db.customStatement(
          "UPDATE parametres_systeme_local SET valeur = 'false' "
          "WHERE cle = 'activation_suppression'",
        );
        await sodis(id: 'f-2', nom: 'Marché');
        await monter(
          tester,
          const EcranFournisseurs(),
          avec: surcharges(role: 'achats'),
        );
        expect(
          find.byKey(const Key('fournisseur-restaurer-f-1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('fournisseur-supprimer-f-2')),
          findsNothing,
        );
      },
    );

    test(
      'le SÉLECTEUR de la commande n’offre plus un fournisseur archivé',
      () async {
        await sodis();
        await sodis(id: 'f-2', nom: 'Marché');
        await AchatsDao(
          db,
          stocks: stocks,
        ).archiverFournisseur('f-2', auteurId: 'u-essai');

        final conteneur = ProviderContainer(
          overrides: surcharges(role: 'administrateur'),
        );
        addTearDown(conteneur.dispose);
        final liste = await conteneur.read(tousLesFournisseursProvider.future);

        expect([for (final f in liste!) f.raisonSociale], ['SODIS']);
      },
    );

    testWidgets(
      'sans le droit de lecture : le motif, jamais « Aucun résultat »',
      (tester) async {
        await monter(
          tester,
          const EcranFournisseurs(),
          avec: surcharges(m7: '-'),
        );
        expect(find.text('Aucun résultat'), findsNothing);
        expect(find.text(MessagesAchats.droitLectureRefuse), findsOneWidget);
      },
    );

    testWidgets(
      'l’onglet « Commandes d’achat » lit les commandes réellement écrites',
      (tester) async {
        await semerStock();
        final dao = AchatsDao(db, stocks: stocks);
        await dao.creerFournisseur(
          const SaisieFournisseur(
            id: 'f-1',
            raisonSociale: 'SODIS',
            contact: null,
            categorie: null,
            conditionsPaiement: null,
            evaluationCode: null,
          ),
          auteurId: 'u-essai',
        );
        await dao.creerCommande(
          const SaisieCommande(
            fournisseurId: 'f-1',
            dateCommande: '2026-10-09',
            statut: StatutCommande.envoyee,
            lignes: [
              LigneSaisieCommande(
                articleId: 'a-riz',
                libelle: 'x',
                uniteMesure: 'x',
                quantite: '10',
                prixUnitaire: '1200',
              ),
            ],
          ),
          auteurId: 'u-essai',
        );
        await monter(tester, const EcranFournisseurs());
        await toucher(tester, const Key('onglet-achats-commandes'));

        expect(find.text('SODIS'), findsWidgets);
        expect(find.text('09/10/2026'), findsOneWidget);
        // 10 × 1 200 = 12 000 F, calculé des lignes.
        expect(find.textContaining('12 000'), findsWidgets);
      },
    );
  });

  /* ==================================================================== */
  /* Approvisionnement                                                     */
  /* ==================================================================== */

  group('Approvisionnement, du besoin à l’entrée en stock', () {
    Future<void> fournisseurSodis() =>
        AchatsDao(db, stocks: stocks).creerFournisseur(
          const SaisieFournisseur(
            id: 'f-1',
            raisonSociale: 'SODIS',
            contact: null,
            categorie: null,
            conditionsPaiement: null,
            evaluationCode: null,
          ),
          auteurId: 'u-essai',
        );

    testWidgets(
      '« Prix d’achat » : le DERNIER prix connu là où il existe, « — » ailleurs, jamais zéro',
      (tester) async {
        await semerStock();
        // Une SECONDE entrée valorisée, à 1 400 F : le dernier prix d'achat est
        // 1 400, le coût moyen pondéré (2 × 1 000 + 1 × 1 400) / 3 =
        // 1 133,3333. Sans cet écart, afficher le CMP au lieu du dernier prix
        // passerait inaperçu (les deux valaient 1 000).
        await stocks.ajouterMouvement(
          articleId: 'a-riz',
          pointId: 'p-mag',
          type: TypeMouvement.entree,
          centiemes: 100,
          motif: 'Réception',
          auteurId: 'u-essai',
          coutDixMilliemes: 14000000,
        );
        final riz = (await stocks.etat()).lignes.firstWhere(
          (l) => l.id == 'a-riz',
        );
        expect(riz.coutMoyenPondere, '1133.3333');
        await monter(tester, const EcranApprovisionnement());

        // Le riz a des entrées valorisées : son DERNIER prix d'achat est connu.
        expect(textesDe(tester, find.byKey(const Key('besoin-prix-a-riz'))), [
          '1 400 FCFA',
        ]);
        // Le sel n'a jamais été réceptionné : « — », avec sa raison.
        expect(
          textesDe(tester, find.byKey(const Key('besoin-prix-absent-a-sel'))),
          ['—'],
        );
        expect(find.byKey(const Key('besoin-prix-a-sel')), findsNothing);
      },
    );

    testWidgets(
      'la bande : sous seuil réel, et « à payer » / « total dû » CHIFFRÉS — un zéro CONSULTÉ, pas un tiret',
      (tester) async {
        await semerStock();
        await monter(tester, const EcranApprovisionnement());

        expect(valeurCarte(tester, 'kpi-sous-seuil'), '2');
        expect(valeurCarte(tester, 'kpi-commandes-attente'), '0');
        expect(valeurCarte(tester, 'kpi-receptions-partielles'), '0');
        // Aucune commande n'existe : la liste a été LUE et elle est vide, donc
        // « 0 fournisseur à payer » et « 0 FCFA » sont des mesures (le tiret est
        // réservé à une liste qu'on n'a pas pu lire — voir le cas suivant).
        expect(valeurCarte(tester, 'kpi-fournisseurs-a-payer'), '0');
        expect(valeurCarte(tester, 'kpi-total-du'), '0 FCFA');
        // Le motif périmé « règlement non porté (D66) » n'est plus affiché.
        expect(find.textContaining('lot D66'), findsNothing);
        expect(find.byKey(const Key('appro-note-indicateurs')), findsNothing);
      },
    );

    testWidgets(
      'sans le droit de lire les achats : « à payer » et « total dû » sont « — », jamais zéro',
      (tester) async {
        await semerStock();
        await monter(
          tester,
          const EcranApprovisionnement(),
          avec: surcharges(m7: '-'),
        );

        expect(valeurCarte(tester, 'kpi-fournisseurs-a-payer'), '—');
        expect(valeurCarte(tester, 'kpi-total-du'), '—');
      },
    );

    testWidgets(
      'commander la sélection, émettre, réceptionner : chaque geste ÉCRIT, et le stock bouge',
      (tester) async {
        await semerStock();
        await fournisseurSodis();
        await monter(tester, const EcranApprovisionnement());

        // ---- 1. Commander la sélection (riz 8, sel 6 : le double du seuil) ----
        expect(
          (tester.widget<TextField>(
            find.byKey(const Key('besoin-qte-a-riz')),
          )).controller?.text,
          '8',
        );
        await toucher(tester, const Key('besoins-commander'));
        await choisir(tester, const Key('commande-fournisseur'), 'SODIS');
        await saisir(tester, const Key('commande-pu-a-riz'), '1200');
        await saisir(tester, const Key('commande-pu-a-sel'), '500');
        // 8 × 1 200 + 6 × 500 = 9 600 + 3 000 = 12 600, calculé, jamais saisi.
        expect(textesDe(tester, find.byKey(const Key('commande-total'))), [
          '12600.00',
        ]);
        await toucher(tester, const Key('commande-valider'));

        expect(
          messageSnack(tester),
          'Bon de commande enregistré sur ce poste — 12600.00.',
        );
        final commande = await db.select(db.commandesAchatLocal).getSingle();
        expect(commande.statut, 'brouillon');
        expect(commande.utilisateurId, 'u-essai');
        final lignes = await (db.select(
          db.lignesCommandeAchatLocal,
        )..orderBy([(l) => OrderingTerm.asc(l.rang)])).get();
        expect(
          [for (final l in lignes) l.articleLibelle],
          ['Riz local', 'Sel'],
        );
        expect([for (final l in lignes) l.quantiteCentiemes], [800, 600]);
        expect(
          [for (final l in lignes) l.prixUnitaireCentimes],
          [120000, 50000],
        );

        // ---- 2. Émettre : brouillon -> envoyée --------------------------------
        await toucher(tester, const Key('onglet-appro-commandes'));
        expect(
          textesDe(tester, find.byKey(Key('commande-statut-${commande.id}'))),
          ['Brouillon'],
        );
        await toucher(tester, Key('commande-envoyer-${commande.id}'));
        expect(
          (await db.select(db.commandesAchatLocal).getSingle()).statut,
          'envoyee',
        );
        expect(
          textesDe(tester, find.byKey(Key('commande-statut-${commande.id}'))),
          ['Envoyée'],
        );

        // Les messages précédents se retirent avant de lire celui de la
        // réception : les barres de message se mettent en file.
        ScaffoldMessenger.of(
          tester.element(find.byType(Scaffold).first),
        ).clearSnackBars();
        await tester.pumpAndSettle();

        // ---- 3. Réceptionner : 8 de riz, 5 de sel sur 6 (-16,67 % > 5 %) -----
        await toucher(tester, Key('commande-receptionner-${commande.id}'));
        await choisir(tester, const Key('reception-point'), 'Magasin');
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('reception-qte-a-riz')))
              .controller
              ?.text,
          '8.00',
          reason: 'le reste à recevoir est proposé par défaut',
        );
        await saisir(tester, const Key('reception-qte-a-sel'), '5');
        await toucher(tester, const Key('reception-valider'));

        expect(find.byKey(const Key('modale-reception')), findsNothing);
        expect(
          messageSnack(tester),
          contains(
            'Réception enregistrée sur ce poste — conformité : Partielle',
          ),
        );

        // Le bon, ses lignes, le statut posé sur la commande.
        final bon = await db.select(db.bonsReceptionLocal).getSingle();
        expect(bon.conformite, 'partielle');
        expect(bon.pointStockageId, 'p-mag');
        expect(bon.utilisateurId, 'u-essai');
        expect(await compte(db.lignesBonReceptionLocal), 2);
        expect(
          (await db.select(db.commandesAchatLocal).getSingle()).statut,
          'receptionnee_partiellement',
        );

        // Le STOCK a bougé, mais la réception ne valorise RIEN (comme le
        // serveur, D132) : riz 2 + 8 = 10 avec le coût d'avant (1 000, et non
        // (2 × 1 000 + 8 × 1 200) / 10 = 1 160) ; le sel, jamais valorisé,
        // reste sans coût connu — « inconnu », pas 500.
        final etat = await stocks.etat();
        final riz = etat.lignes.firstWhere((l) => l.id == 'a-riz');
        expect(riz.stock, '10.00');
        expect(riz.coutMoyenPondere, '1000.0000');
        expect(riz.prixAchat, '1000.0000');
        final sel = etat.lignes.firstWhere((l) => l.id == 'a-sel');
        expect(sel.stock, '5.00');
        expect(sel.cmpInconnu, isTrue);
        expect(sel.prixAchat, isNull);
        expect(sel.valeurInconnue, isTrue);

        // ---- 4. L'écran relit tout : la bande n'est pas restée sur « 2 » -----
        // Riz 10 > seuil 5 et sel 5 > seuil 3 : plus rien à réapprovisionner.
        expect(valeurCarte(tester, 'kpi-sous-seuil'), '0');
        expect(valeurCarte(tester, 'kpi-commandes-attente'), '0');
        expect(valeurCarte(tester, 'kpi-receptions-partielles'), '1');

        // ---- 5. L'onglet Réceptions : point et articles RÉELS ----------------
        await toucher(tester, const Key('onglet-appro-receptions'));
        expect(textesDe(tester, find.byKey(Key('reception-point-${bon.id}'))), [
          'Magasin',
        ]);
        expect(
          textesDe(tester, find.byKey(Key('reception-articles-${bon.id}'))),
          ['2'],
        );
        expect(
          textesDe(tester, find.byKey(Key('reception-conformite-${bon.id}'))),
          ['Partielle'],
        );

        // ---- 6. Le rapprochement : deux voies, l'écart, le libellé figé ------
        await toucher(tester, const Key('onglet-appro-commandes'));
        await toucher(tester, Key('commande-rapprochement-${commande.id}'));
        expect(find.byKey(const Key('modale-rapprochement')), findsOneWidget);
        expect(
          textesDe(tester, find.byKey(const Key('rapprochement-voies'))).first,
          'Voies confrontées : commande, reception',
        );
        // Le libellé de l'article, pas son identifiant.
        expect(find.text('Sel'), findsOneWidget);
        expect(find.text('a-sel'), findsNothing);
        expect(find.text('manquant'), findsOneWidget);
        expect(find.text('-1.00'), findsOneWidget);
        expect(find.text(MessagesAchats.factureAbsente), findsOneWidget);
        // La phrase de « reconstitution » serait FAUSSE sur ce poste.
        expect(find.textContaining('reconstitué'), findsNothing);
      },
    );

    testWidgets(
      'la tolérance non configurée : le pavé le dit, le stock ne bouge pas',
      (tester) async {
        await semerStock();
        await db.delete(db.parametresSystemeLocal).go();
        await fournisseurSodis();
        final detail = await AchatsDao(db, stocks: stocks).creerCommande(
          const SaisieCommande(
            fournisseurId: 'f-1',
            dateCommande: '2026-10-09',
            statut: StatutCommande.envoyee,
            lignes: [
              LigneSaisieCommande(
                articleId: 'a-riz',
                libelle: 'x',
                uniteMesure: 'x',
                quantite: '8',
                prixUnitaire: '1200',
              ),
            ],
          ),
          auteurId: 'u-essai',
        );
        final mouvementsAvant = await compte(db.mouvementsStockLocal);

        await monter(tester, const EcranApprovisionnement());
        await toucher(tester, const Key('onglet-appro-commandes'));
        await toucher(
          tester,
          Key('commande-receptionner-${detail.commande.id}'),
        );
        await choisir(tester, const Key('reception-point'), 'Magasin');
        await toucher(tester, const Key('reception-valider'));

        expect(
          find.byKey(const Key('reception-tolerance-absente')),
          findsOneWidget,
        );
        expect(find.text(MessagesAchats.toleranceAbsente), findsOneWidget);
        // La modale reste ouverte, rien n'est écrit.
        expect(find.byKey(const Key('modale-reception')), findsOneWidget);
        expect(await compte(db.bonsReceptionLocal), 0);
        expect(await compte(db.mouvementsStockLocal), mouvementsAvant);
      },
    );

    testWidgets(
      'sans point de stockage, la réception le dit au lieu de s’ouvrir sur un sélecteur vide',
      (tester) async {
        await tolerance('5');
        await db
            .into(db.articlesLocal)
            .insert(
              ArticlesLocalCompanion.insert(
                id: 'a-riz',
                libelle: 'Riz',
                categorie: '',
                uniteMesure: 'sac',
                seuilAlerte: 5,
              ),
            );
        await fournisseurSodis();
        final detail = await AchatsDao(db, stocks: stocks).creerCommande(
          const SaisieCommande(
            fournisseurId: 'f-1',
            dateCommande: '2026-10-09',
            statut: StatutCommande.envoyee,
            lignes: [
              LigneSaisieCommande(
                articleId: 'a-riz',
                libelle: 'x',
                uniteMesure: 'x',
                quantite: '8',
                prixUnitaire: '1200',
              ),
            ],
          ),
          auteurId: 'u-essai',
        );
        await monter(tester, const EcranApprovisionnement());
        await toucher(tester, const Key('onglet-appro-commandes'));
        await toucher(
          tester,
          Key('commande-receptionner-${detail.commande.id}'),
        );

        expect(find.text(MessagesAchats.aucunPoint), findsOneWidget);
      },
    );

    testWidgets(
      'Réceptions : point et nombre d’articles inconnus rendent « — », jamais 0',
      (tester) async {
        await monter(
          tester,
          const EcranApprovisionnement(),
          avec: surcharges(
            plus: [
              receptionsProvider.overrideWith(
                (ref, _) async => const AchatsRecu(
                  PageAchats<BonReception>(
                    elements: [
                      BonReception(
                        id: 'b-1',
                        commandeId: 'c-1',
                        dateReception: '2026-10-09',
                        conformiteCode: 'totale',
                        fournisseurRaisonSociale: 'SODIS',
                        lignesNonStockees: true,
                      ),
                    ],
                    total: 1,
                    derniere: 1,
                  ),
                ),
              ),
            ],
          ),
        );
        await toucher(tester, const Key('onglet-appro-receptions'));

        expect(
          textesDe(tester, find.byKey(const Key('reception-articles-b-1'))),
          ['—'],
        );
        expect(textesDe(tester, find.byKey(const Key('reception-point-b-1'))), [
          '—',
        ]);
      },
    );

    testWidgets(
      'l’onglet Dettes sans commande : son état vide RÉEL, aucun motif périmé',
      (tester) async {
        await semerStock();
        await monter(tester, const EcranApprovisionnement());
        await toucher(tester, const Key('onglet-appro-dettes'));

        // La phrase de la vue, au mot (`pwa.appro.dettes_vide`).
        expect(
          find.text(
            'Aucune dette fournisseur. Toutes les commandes sont soldées.',
          ),
          findsOneWidget,
        );
        // L'en-tête du tableau reste sous l'état vide (vue l.358-364).
        // (en capitales : `uppercase` du gabarit d'en-tête de la vue)
        expect(find.text('N° COMMANDE'), findsOneWidget);
        // Le « Total dû » de l'en-tête vaut zéro APRÈS arrondi : un tiret.
        expect(textesDe(tester, find.byKey(const Key('dettes-total-du'))), [
          'Total dû —',
        ]);
        // Plus de bloc « non implémentable » ni de motif périmé.
        expect(find.byKey(const Key('dettes-non-implementable')), findsNothing);
        expect(find.textContaining('PA-21'), findsNothing);
        expect(find.textContaining('lot D66'), findsNothing);
      },
    );

    testWidgets(
      'sans le droit de lire les stocks : « — » et la raison, jamais zéro',
      (tester) async {
        await semerStock();
        await monter(
          tester,
          const EcranApprovisionnement(),
          avec: surcharges(m6: '-'),
        );
        expect(valeurCarte(tester, 'kpi-sous-seuil'), '—');
      },
    );
  });

  /* ==================================================================== */
  /* L'export tableur, de bout en bout                                     */
  /* ==================================================================== */

  group('L’export, de bout en bout avec un dossier injecté', () {
    ProviderContainer conteneur() {
      final c = ProviderContainer(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          dossierExportAchatsProvider.overrideWithValue(() async => dossier),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test(
      'l’action réelle écrit un CSV : BOM EF BB BF, UTF-8 valide, accents, montants bruts',
      () async {
        final c = conteneur();
        final liste = ListeAchats(
          titre: 'Bons de commande fournisseurs',
          visas: const [],
          portee: const Portee(
            filtre: 'Statut : Envoyée',
            lignesRapportees: 1,
            totalServeur: 1,
          ),
          entetes: const ['Référence', 'Fournisseur', 'Montant'],
          colonnesNumeriques: const {2},
          lignes: const [
            ['c-1', 'Éts Kora — Natitingou', '12000.00'],
          ],
        );

        final chemin = await c.read(exporterListeAchatsProvider)(liste);

        expect(chemin.startsWith(dossier.path), isTrue);
        expect(chemin.endsWith('.csv'), isTrue);
        final octets = File(chemin).readAsBytesSync();
        expect(octets.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
        final texte = utf8.decode(octets.sublist(3));
        // Les accents et le tiret long ont survécu à l'écriture : un
        // `codeUnits` les aurait tronqués à un octet (D77).
        expect(texte, contains('Éts Kora — Natitingou'));
        expect(texte, contains('Statut : Envoyée'));
        // Un montant part en nombre BRUT, un tableur ne sait pas additionner
        // « 12 000 FCFA ».
        expect(texte, contains('12000.00'));
      },
    );

    testWidgets(
      'la liste exportée par l’écran réel porte ce qui est AFFICHÉ, et dit son filtre',
      (tester) async {
        await semerStock();
        await AchatsDao(db, stocks: stocks).creerFournisseur(
          const SaisieFournisseur(
            id: 'f-1',
            raisonSociale: 'Éts Kora',
            contact: '97 00 00 00',
            categorie: null,
            conditionsPaiement: null,
            evaluationCode: 'bon',
          ),
          auteurId: 'u-essai',
        );
        await AchatsDao(db, stocks: stocks).creerFournisseur(
          const SaisieFournisseur(
            id: 'f-2',
            raisonSociale: 'SODIS',
            contact: null,
            categorie: null,
            conditionsPaiement: null,
            evaluationCode: null,
          ),
          auteurId: 'u-essai',
        );

        // L'action d'export est CAPTURÉE : ce que l'écran réel lui remet est
        // ensuite écrit par l'action RÉELLE (ci-dessous), dans le dossier injecté.
        ListeAchats? capturee;
        await monter(
          tester,
          const EcranFournisseurs(),
          avec: surcharges(
            plus: [
              exporterListeAchatsProvider.overrideWithValue((liste) async {
                capturee = liste;
                return 'capture';
              }),
            ],
          ),
        );
        await saisir(
          tester,
          const Key('achats-fournisseurs-recherche'),
          'kora',
        );
        await toucher(tester, const Key('achats-fournisseurs-exporter'));
        // La modale de format : le tableur (CSV) est le seul format écrit.
        await tester.tap(find.byKey(const Key('export-format-excel')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('export-generer')));
        await tester.pumpAndSettle();

        expect(capturee, isNotNull);
        expect(capturee!.lignes, hasLength(1));
        expect(capturee!.lignes.single.first, 'Éts Kora');
        expect(capturee!.portee.filtre, contains('kora'));

        // L'écriture réelle de CETTE liste, relue octet par octet.
        final chemin = await tester.runAsync(() async {
          final c = ProviderContainer(
            overrides: [
              dossierExportAchatsProvider.overrideWithValue(
                () async => dossier,
              ),
            ],
          );
          try {
            return await c.read(exporterListeAchatsProvider)(capturee!);
          } finally {
            c.dispose();
          }
        });
        final octets = File(chemin!).readAsBytesSync();
        expect(octets.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
        final texte = utf8.decode(octets.sublist(3));
        expect(texte, contains('Éts Kora'));
        expect(texte, isNot(contains('SODIS')));
        expect(texte, contains('recherche « kora »'));
      },
    );

    testWidgets(
      'un filtre qui vide la liste REFUSE l’export : rien n’est remis',
      (tester) async {
        await AchatsDao(db, stocks: stocks).creerFournisseur(
          const SaisieFournisseur(
            id: 'f-1',
            raisonSociale: 'SODIS',
            contact: null,
            categorie: null,
            conditionsPaiement: null,
            evaluationCode: null,
          ),
          auteurId: 'u-essai',
        );
        var appels = 0;
        await monter(
          tester,
          const EcranFournisseurs(),
          avec: surcharges(
            plus: [
              exporterListeAchatsProvider.overrideWithValue((liste) async {
                appels++;
                return 'capture';
              }),
            ],
          ),
        );
        await saisir(tester, const Key('achats-fournisseurs-recherche'), 'zzz');
        await toucher(tester, const Key('achats-fournisseurs-exporter'));

        expect(messageSnack(tester), messageExportVide);
        expect(appels, 0);
        expect(find.byKey(const Key('modale-export-carte')), findsNothing);
      },
    );

    testWidgets(
      'les commandes de l’Approvisionnement : montant brut calculé des lignes, statut en mots',
      (tester) async {
        await semerStock();
        final dao = AchatsDao(db, stocks: stocks);
        await dao.creerFournisseur(
          const SaisieFournisseur(
            id: 'f-1',
            raisonSociale: 'SODIS',
            contact: null,
            categorie: null,
            conditionsPaiement: null,
            evaluationCode: null,
          ),
          auteurId: 'u-essai',
        );
        final c = await dao.creerCommande(
          const SaisieCommande(
            fournisseurId: 'f-1',
            dateCommande: '2026-10-09',
            statut: StatutCommande.envoyee,
            lignes: [
              LigneSaisieCommande(
                articleId: 'a-riz',
                libelle: 'x',
                uniteMesure: 'x',
                quantite: '8',
                prixUnitaire: '1200',
              ),
              LigneSaisieCommande(
                articleId: 'a-sel',
                libelle: 'x',
                uniteMesure: 'x',
                quantite: '6',
                prixUnitaire: '500',
              ),
            ],
          ),
          auteurId: 'u-essai',
        );

        ListeAchats? capturee;
        await monter(
          tester,
          const EcranApprovisionnement(),
          avec: surcharges(
            plus: [
              exporterListeAchatsProvider.overrideWithValue((liste) async {
                capturee = liste;
                return 'capture';
              }),
            ],
          ),
        );
        await toucher(tester, const Key('onglet-appro-commandes'));
        await toucher(tester, const Key('excel-cmd'));

        expect(capturee, isNotNull);
        expect(capturee!.entetes, [
          'Référence',
          'Fournisseur',
          'Date',
          'Lignes',
          'Montant',
          'Statut',
        ]);
        expect(capturee!.lignes.single, [
          c.commande.id,
          'SODIS',
          '2026-10-09',
          '2',
          '12600.00',
          'Envoyée',
        ]);
      },
    );
  });
}
