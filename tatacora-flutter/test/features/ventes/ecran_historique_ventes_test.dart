import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/format/formats.dart';
import 'package:tatacora_flutter/core/theme/app_colors.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/caisse/data/sessions_caisse_dao.dart';
import 'package:tatacora_flutter/features/caisse/domain/entities/session_caisse.dart'
    show pointDeCaisseDuComptoir;
import 'package:tatacora_flutter/features/facturation/data/facture_dao.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/piece_facturation.dart';
import 'package:tatacora_flutter/features/facturation/domain/repositories/facture_repository.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/article_vendable.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/mode_reglement.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/pos/data/panier_repository_local.dart';
import 'package:tatacora_flutter/features/pos/presentation/providers_pos.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';
import 'package:tatacora_flutter/features/ventes/domain/entities/vente.dart';
import 'package:tatacora_flutter/features/ventes/domain/journal_ventes.dart';
import 'package:tatacora_flutter/features/ventes/impression/etat_journal_ventes.dart';
import 'package:tatacora_flutter/features/ventes/presentation/ecran_historique_ventes.dart';
import 'package:tatacora_flutter/features/ventes/presentation/providers_ventes.dart';
import 'package:tatacora_flutter/features/ventes/presentation/widgets/barre_filtres_ventes.dart';
import 'package:tatacora_flutter/features/ventes/presentation/widgets/dialogue_detail_vente.dart';
import 'package:tatacora_flutter/features/ventes/presentation/widgets/table_ventes.dart';
import '../comptabilite/support/outils_comptabilite.dart'
    show baseInstalleeSur, moteurSur;
import '../facturation/support/outils_encaissement.dart'
    show caissierEssai, ouvrirLaCaisseDuComptoir;
import '../pos/support/outils_ventes.dart' show cloturerSansPiece;

/// L'écran « Historique des ventes », monté sur une **vraie base locale**.
///
/// ## Le cas qui compte le plus ici
///
/// **L'écran est branché.** Un journal dont aucune route ne mène nulle part
/// serait PA-133 : trois écrans livrés sont restés inatteignables par un clic
/// pendant plusieurs livraisons. La couverture du menu est vérifiée à part
/// (`coquille_conformite_test.dart`), contre le code source du routeur.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late PanierDao paniers;
  late FactureDao factures;

  /// Les documents « exportés » et « imprimés » pendant le test — l'export réel
  /// n'existe pas ici, mais **l'appel** doit être éprouvé : c'est lui qui
  /// manquerait si le bouton n'était branché sur rien.
  late List<EtatJournalVentes> exportes;
  late List<EtatJournalVentes> imprimes;

  DateTime maintenant() => DateTime(2026, 8, 26, 18);

  const biere = ArticleVendable(
    reference: ReferenceCatalogue(module: ModuleVendable.m5Bar, code: 'bsn-33'),
    libelle: 'Béninoise 33cl',
    prix: 1000,
    categorie: 'locale',
  );

  setUp(() async {
    db = AppDatabase.enMemoire();
    await ouvrirLaCaisseDuComptoir(db);
    // Une vente passe sa pièce comptable (l'exercice 2026) à la clôture.
    await baseInstalleeSur(db, maintenant());
    paniers = PanierDao(
      db,
      maintenant: maintenant,
      moteur: () async => moteurSur(db, maintenant: maintenant),
    );
    factures = FactureDao(db, maintenant: maintenant);

    await db
        .into(db.cartesBoissonLocal)
        .insert(
          CartesBoissonLocalCompanion.insert(
            id: 'bsn-33',
            articleId: 'art-bsn',
            libelle: 'Béninoise 33cl',
            categorie: 'locale',
            prixVente: 1000,
          ),
        );
  });

  tearDown(() => db.close());

  Future<Panier> vente({
    String? modePaiement = 'especes',
    String pointVente = 'Bar principal',
    int articles = 1,
    bool annulee = false,
  }) async {
    var p = await paniers.ouvrir(
      typeVente: TypeVente.comptant,
      pointVente: pointVente,
    );
    p = await paniers.ajouterLigne(p.id, biere, quantite: articles);
    if (annulee) return paniers.annuler(p.id, 'Erreur de saisie');
    // Un mode « non renseigné » et une note de chambre au COMPTOIR, la clôture
    // d'aujourd'hui les refuse : ce sont des ventes HISTORIQUES, écrites sans
    // pièce par une version antérieure — le journal doit pouvoir les montrer.
    if (modePaiement == null ||
        modePaiement == ModeReglement.noteChambre.code) {
      final session = await SessionsCaisseDao(
        db,
      ).sessionOuverte(pointDeCaisseDuComptoir);
      await cloturerSansPiece(
        db,
        p.id,
        mode: modePaiement,
        quand: maintenant(),
        sessionId: session?.id,
      );
      return (await paniers.parId(p.id))!;
    }
    return paniers.cloturer(
      p.id,
      modePaiement: modePaiement,
      auteurId: caissierEssai,
    );
  }

  Future<void> monter(
    WidgetTester tester, {
    Size taille = const Size(1600, 1200),
    Map<String, String>? droits,
  }) async {
    exportes = [];
    imprimes = [];
    tester.view
      ..physicalSize = taille
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          if (droits != null) ...[
            droitsProvider.overrideWithValue(GardeAcces.depuisJson(droits)),
            // Celui qui annule : la contre-pièce nomme son auteur (RG-15).
            sessionProvider.overrideWithBuild(
              (ref, notifier) => Session(
                utilisateurId: caissierEssai,
                login: 'caissier',
                nom: 'Caissier',
                role: 'gerant',
                droits: GardeAcces.depuisJson(droits),
              ),
            ),
            // Le DAO de l'essai, branché sur le moteur de la base d'essai.
            depotPanierProvider.overrideWithValue(
              PanierRepositoryLocal(paniers),
            ),
          ],
          exporterJournalVentesProvider.overrideWithValue((etat) async {
            exportes.add(etat);
            return 'C:/documents/journal_ventes.csv';
          }),
          exporterJournalVentesPdfProvider.overrideWithValue((etat) async {
            imprimes.add(etat);
            return 'C:/documents/journal_ventes.pdf';
          }),
          imprimerVenteProvider.overrideWithValue((etat) async {}),
          exporterVenteProvider.overrideWithValue(
            (etat) async => 'C:/documents/vente.pdf',
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranHistoriqueVentes()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /* ================================================================== */
  group('Ce que l’écran dit de lui-même', () {
    testWidgets('il reprend le sous-titre du maître, au mot', (tester) async {
      await vente();
      await monter(tester);

      final texte = tester
          .widget<Text>(find.byKey(const Key('ventes-sous-titre')))
          .textSpan!
          .toPlainText();
      expect(texte, contains('Le journal des ventes, pas des factures.'));
      expect(
        texte,
        contains('V-2026-00016'),
        reason:
            'la phrase porte la règle qui commande tout l’écran ; la '
            'reformuler effacerait la règle en même temps que le numéro',
      );
    });

    testWidgets('l’en-tête du tableau est BLANC sur le fond navy (la vue : '
        '`text-white/90`), jamais le gris des en-têtes clairs', (tester) async {
      await monter(tester);

      for (final titre in ['N°', 'DATE', 'POSTE', 'MONTANT', 'ACTIONS']) {
        final texte = tester.widget<Text>(
          find
              .descendant(
                of: find.byType(TableauVentes),
                matching: find.text(titre),
              )
              .first,
        );
        expect(texte.style?.color, AppColors.neutre0, reason: titre);
      }
    });

    testWidgets(
      'le bandeau « Journal enregistré sur ce poste » est RETIRÉ (demande du '
      'PO, la vue ne l’a pas) — et rien ne promet un envoi au serveur',
      (tester) async {
        await vente();
        await monter(tester);

        expect(find.byKey(const Key('ventes-bandeau-local')), findsNothing);
        expect(find.textContaining('Journal enregistré'), findsNothing);
        expect(find.textContaining('ne remontent pas'), findsNothing);

        // Le balayage porte sur TOUT le texte rendu : la formulation entière de
        // l'écran ne doit jamais promettre un envoi (PA-59/60/61).
        final tousLesTextes = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .join(' ');
        expect(tousLesTextes, isNot(contains('attente de synchronisation')));
        expect(tousLesTextes, isNot(contains('synchronisé')));
      },
    );

    test('il nomme ce qu’il ne rend pas, au lieu de le taire', () {
      // Le panneau « Ce que cet écran ne rend pas » n'est plus affiché
      // (Phase 2, 08/10/2026) : les refus sont dits à la source, à l'endroit
      // où le code les prend. Ce cas empêche qu'ils soient retirés en silence.
      final source = File(
        'lib/features/ventes/presentation/widgets/table_ventes.dart',
      ).readAsStringSync();

      expect(source, contains('Le numéro « V-2026-00016 »'));
      expect(source, contains('stock ✕'));
      expect(source, contains('La recherche par chambre'));
    });

    testWidgets(
      'le texte d’aide de la recherche DIT ce qu’elle couvre réellement',
      (tester) async {
        await vente();
        await monter(tester);

        final champ = tester.widget<TextField>(
          find.byKey(const Key('ventes-recherche')),
        );
        expect(champ.decoration!.hintText, BarreFiltresVentes.texteAide);
        expect(
          champ.decoration!.hintText,
          isNot(contains('N° de vente')),
          reason:
              'promettre une recherche par numéro de vente, qui n’existe pas, '
              'ferait passer le champ pour cassé',
        );
        expect(champ.decoration!.hintText, isNot(contains('chambre')));
      },
    );
  });

  /* ================================================================== */
  group('La bande d’indicateurs', () {
    testWidgets('les cinq cartes du maître sont là', (tester) async {
      await vente();
      await monter(tester);

      for (final cle in const [
        'ventes-kpi-nombre',
        'ventes-kpi-ca',
        'ventes-kpi-encaisse',
        'ventes-kpi-note',
        'ventes-kpi-stock',
      ]) {
        expect(find.byKey(Key(cle)), findsOneWidget, reason: cle);
      }
    });

    testWidgets(
      '« Sans impact stock » est CHIFFRÉ : zéro quand tous les articles sont '
      'liés, et la phrase de la vue le dit',
      (tester) async {
        await vente();
        await monter(tester);

        // Un article lié au stock : la vue dit « Toutes les ventes ont
        // décrémenté » sous un `0` mesuré, plus jamais « Non consulté ».
        final carte = find.byKey(const Key('ventes-kpi-stock'));
        expect(
          find.descendant(of: carte, matching: find.text('0')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: carte,
            matching: find.text('Toutes les ventes ont décrémenté'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: carte, matching: find.text('Non consulté')),
          findsNothing,
        );
        expect(
          find.descendant(of: carte, matching: find.textContaining('PA-')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'une boisson SANS lien au stock : KPI chiffré, badge « stock ✕ » et '
      'encadré du détail',
      (tester) async {
        await (db.update(db.cartesBoissonLocal)
              ..where((b) => b.id.equals('bsn-33')))
            .write(const CartesBoissonLocalCompanion(articleId: Value('')));
        final p = await vente();
        await monter(tester);

        expect(
          find.descendant(
            of: find.byKey(const Key('ventes-kpi-stock')),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('ventes-kpi-stock')),
            matching: find.text('Articles sans lien au stock'),
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('vente-badge-stock')), findsOneWidget);

        await tester.tap(find.byKey(Key('vente-ligne-${p.id}')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('vente-detail-stock')), findsOneWidget);
      },
    );

    testWidgets(
      'le détail ANNULE la vente : motif obligatoire, puis « annulée » reste '
      'au journal',
      (tester) async {
        final p = await vente();
        await monter(tester, droits: const {'M5': 'C'});

        await tester.tap(find.byKey(Key('vente-ligne-${p.id}')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('vente-detail-annuler')),
        );
        await tester.tap(find.byKey(const Key('vente-detail-annuler')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('vente-detail-annulation-refus')),
          findsOneWidget,
          reason: 'sans motif, le refus est dit',
        );
        expect((await paniers.parId(p.id))!.statut, isNot(StatutPanier.annule));

        await tester.enterText(
          find.byKey(const Key('vente-detail-motif')),
          'erreur de saisie',
        );
        await tester.tap(find.byKey(const Key('vente-detail-annuler')));
        await tester.pumpAndSettle();

        final apres = (await paniers.parId(p.id))!;
        expect(apres.statut, StatutPanier.annule);
        expect(apres.motifAnnulation, 'erreur de saisie');
        expect(
          find.byKey(const Key('vente-detail-annulee-message')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'un règlement non renseigné est NOMMÉ sous le chiffre d’affaires',
      (tester) async {
        // Sans cette phrase, « Encaissé + Porté en note » serait inférieur au
        // chiffre d'affaires sans que rien ne l'explique, et l'écart passerait
        // pour une erreur de calcul.
        await vente(modePaiement: null);
        await monter(tester);

        expect(
          find.descendant(
            of: find.byKey(const Key('ventes-kpi-ca')),
            matching: find.textContaining('sans règlement renseigné'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('les indicateurs suivent le FILTRE, pas le journal entier', (
      tester,
    ) async {
      await vente();
      await vente(annulee: true);
      await monter(tester);

      final avant = tester.element(find.byType(EcranHistoriqueVentes));
      expect(
        ProviderScope.containerOf(
          avant,
        ).read(kpisJournalVentesProvider).annulees,
        1,
      );

      ProviderScope.containerOf(avant)
          .read(filtreVentesProvider.notifier)
          .definir(const FiltreVentes(statut: StatutVente.validee));
      await tester.pumpAndSettle();

      final apres = ProviderScope.containerOf(
        avant,
      ).read(kpisJournalVentesProvider);
      expect(
        apres.annulees,
        0,
        reason:
            'ce qu’on voit, ce qu’on compte et ce qu’on exporte doivent être '
            'la même chose : trois portées sur un écran feraient douter des '
            'trois',
      );
      expect(apres.ventes, 1);
    });
  });

  /* ================================================================== */
  group('Le tableau et sa ligne', () {
    testWidgets('chaque vente porte une clé ATTEIGNABLE', (tester) async {
      // Piège n° 10 : une `DataRow.key` n'atteint jamais l'arbre de widgets.
      // `TableauTatacora` la pose sur la première cellule — une clé
      // introuvable est une clé qui ment.
      final v = await vente();
      await monter(tester);

      expect(find.byKey(Key('vente-ligne-${v.id}')), findsOneWidget);
    });

    testWidgets('le numéro de facture n’apparaît QUE s’il y en a une', (
      tester,
    ) async {
      final sansFacture = await vente();
      final avecFacture = await vente(pointVente: 'Restaurant');
      final piece = await factures.emettre(
        BrouillonFacture(
          origine: OrigineFacture.posComptant,
          panierId: avecFacture.id,
          lignes: const [
            LigneBrouillon(
              module: ModuleFacturable.m5Bar,
              libelle: 'Béninoise 33cl',
              prixUnitaire: 1000,
              quantite: 1,
            ),
          ],
        ),
      );
      await monter(tester);

      expect(
        find.byKey(Key('vente-facture-${avecFacture.id}')),
        findsOneWidget,
      );
      expect(find.text(piece.numero), findsOneWidget);
      // Un emplacement toujours occupé — par un tiret, par « aucune » — ferait
      // lire l'absence de facture comme un manquement, alors que c'est le cas
      // normal.
      expect(find.byKey(Key('vente-facture-${sansFacture.id}')), findsNothing);
    });

    testWidgets('une liste vide affiche le message du maître', (tester) async {
      await monter(tester);
      expect(find.text(TableauVentes.messageVide), findsOneWidget);
    });

    testWidgets('les paniers OUVERTS sont comptés et affichés', (tester) async {
      final ouvert = await paniers.ouvrir(
        typeVente: TypeVente.comptant,
        pointVente: 'Bar principal',
      );
      await paniers.ajouterLigne(ouvert.id, biere);
      await monter(tester);

      expect(find.byKey(const Key('ventes-paniers-ouverts')), findsOneWidget);
    });
  });

  /* ================================================================== */
  group('La pagination (demande du PO du 13/10/2026)', () {
    Iterable<String> lignesRendues(WidgetTester tester) => tester
        .widgetList(
          find.byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith('vente-ligne-'),
          ),
        )
        .map((w) => (w.key! as ValueKey<String>).value);

    String texteDe(WidgetTester tester, String cle) =>
        tester.widget<Text>(find.byKey(Key(cle))).data!;

    String decompte(WidgetTester tester) => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(const Key('ventes-pagination-decompte')),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data!)
        .join();

    bool actif(WidgetTester tester, String cle) =>
        tester.widget<InkWell>(find.byKey(Key(cle))).onTap != null;

    testWidgets('liste vide : « Affichage de 0-0 sur 0 », « Page 1 / 1 », '
        'les deux liens désactivés — et le message du maître', (tester) async {
      await monter(tester);

      expect(decompte(tester), 'Affichage de 0-0 sur 0');
      expect(texteDe(tester, 'ventes-pagination-page'), 'Page 1 / 1');
      expect(actif(tester, 'ventes-pagination-precedent'), isFalse);
      expect(actif(tester, 'ventes-pagination-suivant'), isFalse);
      expect(find.text('← Précédent'), findsOneWidget);
      expect(find.text('Suivant →'), findsOneWidget);
      expect(find.text(TableauVentes.messageVide), findsOneWidget);
    });

    testWidgets('une seule page : les contrôles RESTENT rendus, désactivés', (
      tester,
    ) async {
      await vente();
      await vente();
      await monter(tester);

      expect(decompte(tester), 'Affichage de 1-2 sur 2');
      expect(texteDe(tester, 'ventes-pagination-page'), 'Page 1 / 1');
      expect(actif(tester, 'ventes-pagination-precedent'), isFalse);
      expect(actif(tester, 'ventes-pagination-suivant'), isFalse);
      expect(lignesRendues(tester), hasLength(2));
      // Désactivé = estompé à l'opacité du thème, jamais une valeur en dur.
      expect(
        tester
            .widget<Opacity>(
              find
                  .ancestor(
                    of: find.byKey(const Key('ventes-pagination-precedent')),
                    matching: find.byType(Opacity),
                  )
                  .first,
            )
            .opacity,
        AppColors.opaciteDesactive,
      );
    });

    testWidgets('12 ventes, page de 10 : chiffre d’affaires, encaissé et '
        'export portent sur les DOUZE, sur chaque page', (tester) async {
      // 12 × 1 000 F au comptant. La page 1 n'en montre que dix (10 000 F) ;
      // la page 2 n'en montre que deux (2 000 F). Un indicateur calculé sur
      // la page dirait l'un ou l'autre — jamais 12 000 F.
      for (var i = 0; i < 12; i++) {
        await vente();
      }
      await monter(tester, taille: const Size(1600, 2400));

      // Les textes d'une carte, chacun entier : la valeur est l'un d'eux.
      List<String> textesDe(String cle) => tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(Key(cle)),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data ?? '')
          .toList();

      final douzeMille = formaterFcfa(12000);
      for (final page in const ['Page 1 / 2', 'Page 2 / 2']) {
        expect(texteDe(tester, 'ventes-pagination-page'), page);
        expect(lignesRendues(tester), hasLength(page == 'Page 1 / 2' ? 10 : 2));
        expect(textesDe('ventes-kpi-ca'), contains(douzeMille), reason: page);
        expect(
          textesDe('ventes-kpi-encaisse'),
          contains(douzeMille),
          reason: page,
        );
        expect(textesDe('ventes-kpi-nombre'), contains('12'), reason: page);
        if (page == 'Page 1 / 2') {
          await tester.tap(find.byKey(const Key('ventes-pagination-suivant')));
          await tester.pumpAndSettle();
        }
      }

      // L'export, demandé depuis la page 2, emporte les DOUZE ventes et les
      // montants de la liste entière.
      await tester.tap(find.byKey(const Key('ventes-exporter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-format-excel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-generer')));
      await tester.pumpAndSettle();
      final etat = exportes.single;
      expect(etat.ventes, hasLength(12));
      expect(etat.kpis.chiffreAffaires, 12000);
      expect(etat.kpis.encaisse, 12000);
    });

    testWidgets('23 ventes : 10, 10, puis 3 — on avance et on revient, chaque '
        'vente sur UNE seule page', (tester) async {
      for (var i = 0; i < 23; i++) {
        await vente();
      }
      await monter(tester, taille: const Size(1600, 2400));

      final vues = <String>{};
      expect(decompte(tester), 'Affichage de 1-10 sur 23');
      expect(texteDe(tester, 'ventes-pagination-page'), 'Page 1 / 3');
      expect(actif(tester, 'ventes-pagination-precedent'), isFalse);
      expect(actif(tester, 'ventes-pagination-suivant'), isTrue);
      expect(lignesRendues(tester), hasLength(10));
      vues.addAll(lignesRendues(tester));

      await tester.tap(find.byKey(const Key('ventes-pagination-suivant')));
      await tester.pumpAndSettle();
      expect(decompte(tester), 'Affichage de 11-20 sur 23');
      expect(texteDe(tester, 'ventes-pagination-page'), 'Page 2 / 3');
      expect(lignesRendues(tester), hasLength(10));
      vues.addAll(lignesRendues(tester));

      await tester.tap(find.byKey(const Key('ventes-pagination-suivant')));
      await tester.pumpAndSettle();
      expect(decompte(tester), 'Affichage de 21-23 sur 23');
      expect(texteDe(tester, 'ventes-pagination-page'), 'Page 3 / 3');
      expect(actif(tester, 'ventes-pagination-suivant'), isFalse);
      expect(actif(tester, 'ventes-pagination-precedent'), isTrue);
      expect(lignesRendues(tester), hasLength(3));
      vues.addAll(lignesRendues(tester));

      expect(
        vues,
        hasLength(23),
        reason: 'aucune vente vue deux fois, aucune perdue entre deux pages',
      );

      await tester.tap(find.byKey(const Key('ventes-pagination-precedent')));
      await tester.pumpAndSettle();
      expect(texteDe(tester, 'ventes-pagination-page'), 'Page 2 / 3');
    });

    testWidgets('un filtre ramène à la page 1 ; indicateurs et export portent '
        'sur la liste FILTRÉE ENTIÈRE, jamais sur la seule page', (
      tester,
    ) async {
      for (var i = 0; i < 12; i++) {
        await vente();
      }
      for (var i = 0; i < 11; i++) {
        await vente(annulee: true);
      }
      await monter(tester, taille: const Size(1600, 2400));

      await tester.tap(find.byKey(const Key('ventes-pagination-suivant')));
      await tester.pumpAndSettle();
      expect(texteDe(tester, 'ventes-pagination-page'), 'Page 2 / 3');

      // Les indicateurs comptent les 12 validées, pas les 10 de la page.
      expect(
        tester
            .widgetList<Text>(
              find.descendant(
                of: find.byKey(const Key('ventes-kpi-nombre')),
                matching: find.byType(Text),
              ),
            )
            .map((t) => t.data)
            .toList(),
        containsAll(<String>['12', '11 annulée(s)']),
      );

      // L'export emporte les 23 lignes affichables, pas la page.
      await tester.tap(find.byKey(const Key('ventes-exporter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-format-excel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-generer')));
      await tester.pumpAndSettle();
      expect(exportes.single.ventes, hasLength(23));

      // Le filtre garde DEUX pages (11 annulées) : sans retour en page 1, on
      // resterait en page 2 sur une seule ligne.
      final conteneur = ProviderScope.containerOf(
        tester.element(find.byType(EcranHistoriqueVentes)),
      );
      conteneur
          .read(filtreVentesProvider.notifier)
          .definir(const FiltreVentes(statut: StatutVente.annulee));
      await tester.pumpAndSettle();

      expect(texteDe(tester, 'ventes-pagination-page'), 'Page 1 / 2');
      expect(decompte(tester), 'Affichage de 1-10 sur 11');
      expect(lignesRendues(tester), hasLength(10));
    });
  });

  /* ================================================================== */
  group('La modale « Détail »', () {
    testWidgets('le bouton l’ouvre, avec les lignes et le total', (
      tester,
    ) async {
      final v = await vente(articles: 3);
      await monter(tester);

      await tester.tap(find.byKey(Key('vente-detail-${v.id}')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('vente-detail-reference')), findsOneWidget);
      expect(
        find.textContaining('Béninoise 33cl', findRichText: true),
        findsWidgets,
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('vente-detail-total'))).data,
        '3 000 FCFA',
      );
      expect(
        find.textContaining('Total · Espèces', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('une note de chambre porte l’encadré du maître', (
      tester,
    ) async {
      final v = await vente(modePaiement: ModeReglement.noteChambre.code);
      await monter(tester);

      await tester.tap(find.byKey(Key('vente-detail-${v.id}')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('vente-detail-note')),
                matching: find.byType(Text),
              ),
            )
            .data,
        contains('ce montant n’est PAS dans le tiroir'),
      );
    });

    testWidgets('une vente sans facture n’affirme RIEN de fiscal', (
      tester,
    ) async {
      final v = await vente();
      await monter(tester);

      await tester.tap(find.byKey(Key('vente-detail-${v.id}')));
      await tester.pumpAndSettle();

      final piece = tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const Key('vente-detail-piece')),
              matching: find.byType(Text),
            ),
          )
          .data!;
      expect(piece, contains('Aucune facture'));
      expect(piece, isNot(contains('certifi')));
    });

    testWidgets(
      'une addition LONGUE laisse le pied et ses trois boutons atteignables',
      (tester) async {
        // Piège n° 7 : une borne ne se teste que sur un contenu plus grand
        // qu'elle. Écran court, addition de trente articles distincts : sans le
        // `Flexible` autour du corps défilant, le `Column` déborde et le pied
        // disparaît AVEC les trois boutons.
        //
        // La modale est montée SEULE, pas depuis le tableau : sur un écran de
        // 600 px, la colonne « Actions » du tableau sort du cadre et le clic
        // ne l'atteindrait pas — le cas mesurerait alors la largeur du
        // tableau, pas la hauteur de la modale.
        var p = await paniers.ouvrir(
          typeVente: TypeVente.comptant,
          pointVente: 'Bar principal',
        );
        for (var i = 0; i < 30; i++) {
          await db
              .into(db.cartesBoissonLocal)
              .insert(
                CartesBoissonLocalCompanion.insert(
                  id: 'bsn-$i',
                  articleId: 'art-$i',
                  libelle: 'Boisson $i',
                  categorie: 'locale',
                  prixVente: 500,
                ),
              );
          p = await paniers.ajouterLigne(
            p.id,
            ArticleVendable(
              reference: ReferenceCatalogue(
                module: ModuleVendable.m5Bar,
                code: 'bsn-$i',
              ),
              libelle: 'Boisson $i',
              prix: 500,
            ),
          );
        }
        await paniers.cloturer(
          p.id,
          modePaiement: 'especes',
          auteurId: caissierEssai,
        );

        final journal = composerJournal(paniers: await paniers.paniers());
        final longue = journal.ventes.single;
        expect(longue.lignes, hasLength(30));

        tester.view
          ..physicalSize = const Size(1000, 600)
          ..devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              baseLocaleProvider.overrideWithValue(db),
              imprimerVenteProvider.overrideWithValue((etat) async {}),
              exporterVenteProvider.overrideWithValue((etat) async => ''),
            ],
            child: MaterialApp(
              theme: AppTheme.clair,
              home: Scaffold(body: DialogueDetailVente(vente: longue)),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        for (final cle in const [
          'vente-detail-fermer',
          'vente-detail-imprimer',
          'vente-detail-telecharger',
        ]) {
          expect(
            find.byKey(Key(cle)).hitTestable(),
            findsOneWidget,
            reason: cle,
          );
        }
      },
    );

    testWidgets('« Télécharger » dit OÙ le document est enregistré', (
      tester,
    ) async {
      final v = await vente();
      await monter(tester);

      await tester.tap(find.byKey(Key('vente-detail-${v.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('vente-detail-telecharger')));
      await tester.pumpAndSettle();

      // Le toast commun dit le NOM du fichier enregistré — « enregistré »,
      // jamais « envoyé » ni « synchronisé ».
      final dit = tester
          .widget<Text>(find.byKey(const Key('vente-detail-chemin')))
          .data;
      expect(dit, 'Export enregistré : vente.pdf');
      expect(dit, isNot(matches(RegExp('envoy|synchronis'))));
    });
  });

  /* ================================================================== */
  group('Les exports portent sur ce qui est affiché', () {
    testWidgets('une liste vide est REFUSÉE, avec le mot du maître', (
      tester,
    ) async {
      await monter(tester);

      await tester.tap(find.byKey(const Key('ventes-exporter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-format-pdf')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-generer')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ventes-export-vide')), findsOneWidget);
      expect(find.text(messageExportVentesVide), findsOneWidget);
      expect(
        imprimes,
        isEmpty,
        reason:
            'une page blanche remise au Gérant se lit comme « aucune vente », '
            'alors qu’elle veut dire « le filtre n’a rien retenu »',
      );
    });

    testWidgets('le PDF (présélectionné) part par l’export PDF, pas par le '
        'tableur, avec la liste FILTRÉE ; le toast le dit', (tester) async {
      await vente();
      await vente(annulee: true);
      await monter(tester);

      ProviderScope.containerOf(
            tester.element(find.byType(EcranHistoriqueVentes)),
          )
          .read(filtreVentesProvider.notifier)
          .definir(const FiltreVentes(statut: StatutVente.annulee));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ventes-exporter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-generer')));
      await tester.pumpAndSettle();

      expect(exportes, isEmpty, reason: 'le PDF ne passe pas par le tableur');
      expect(imprimes, hasLength(1));
      expect(imprimes.single.ventes, hasLength(1));
      expect(imprimes.single.filtre, contains('Statut : Annulées'));
      expect(
        tester.widget<Text>(find.byKey(const Key('ventes-export-chemin'))).data,
        'Export enregistré : journal_ventes.pdf',
      );
    });

    testWidgets('l’export emporte la liste FILTRÉE et son filtre', (
      tester,
    ) async {
      await vente();
      await vente(annulee: true);
      await monter(tester);

      final conteneur = ProviderScope.containerOf(
        tester.element(find.byType(EcranHistoriqueVentes)),
      );
      conteneur
          .read(filtreVentesProvider.notifier)
          .definir(const FiltreVentes(statut: StatutVente.annulee));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ventes-exporter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-format-excel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-generer')));
      await tester.pumpAndSettle();

      expect(exportes, hasLength(1));
      expect(
        exportes.single.ventes,
        hasLength(1),
        reason:
            'exporter le journal entier ferait envoyer au comptable un '
            'document que l’utilisateur croit avoir vérifié',
      );
      expect(exportes.single.filtre, contains('Statut : Annulées'));
      // Le toast commun dit le NOM du fichier enregistré — « enregistré »,
      // jamais « envoyé » ni « synchronisé ».
      final dit = tester
          .widget<Text>(find.byKey(const Key('ventes-export-chemin')))
          .data;
      expect(dit, 'Export enregistré : journal_ventes.csv');
      expect(dit, isNot(matches(RegExp('envoy|synchronis'))));
    });
  });
}
