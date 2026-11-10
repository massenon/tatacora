@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_api.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/calcul_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';
import 'package:tatacora_flutter/features/stocks/presentation/ecran_stocks.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import '../synchronisation/support/faux_transport.dart';

/// « Valeur d'achat », CMP et « Valeur stock » vus d'un SECOND poste (bug du PO du
/// 09/11/2026) : le barman (poste A) renseigne les prix d'articles importés SANS
/// prix, le gérant (poste B) descend le catalogue — il voyait les stocks et les
/// seuils mais « — » à la place des trois valeurs, parce que le COÛT des entrées ne
/// descendait pas et qu'un poste recalcule ces valeurs en rejouant les mouvements.
///
/// Rien n'est recopié : `tool/stocks/rejouer_valeurs_stock.php` fait tourner le
/// VRAI `MouvementStockService` (base privée, rollback), rend ce que le serveur
/// AFFICHE (`ConsultationStockService`, la source de l'écran web) et ce que la
/// DESCENTE livre à un gérant (`CatalogueDescendantService::page`). Le poste A rejoue
/// la même suite par ses écrans (`StocksApi`), le poste B reçoit la descente du
/// serveur par l'aligneur : trois valeurs égales, article par article.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  // Coût en dix-millièmes de franc ; `null` : entrée non valorisée (transfert).
  final etapes = <Map<String, Object?>>[
    {
      'article': 'Café double',
      'type': 'entree',
      'centiemes': 1500,
      'cout': 5000000,
    },
    {
      'article': 'Café double',
      'type': 'entree',
      'centiemes': 500,
      'cout': 6000000,
    },
    {'article': 'Café double', 'type': 'sortie', 'centiemes': 300},
    {'article': 'Café double', 'type': 'perte', 'centiemes': 100},
    // Dix en stock SANS coût, puis quatre à un coût fractionnaire : un CMP à décimales.
    {'article': 'Bière 65cl', 'type': 'entree', 'centiemes': 1000},
    {
      'article': 'Bière 65cl',
      'type': 'entree',
      'centiemes': 400,
      'cout': 3333333,
    },
  ];
  const articles = ['Café double', 'Bière 65cl', 'Thé sans prix'];

  late Map<String, dynamic> serveur;

  setUpAll(() async {
    serveur = await executerPhp(
      'rejouer_valeurs_stock.php',
      dossier: 'stocks',
      // Base privée : son verrou à elle (`tatacora_test_php` sinon, la queue commune).
      nomVerrou:
          Platform.environment['TATACORA_BASE_ESSAI'] ?? 'tatacora_test_php',
      entree: {'articles': articles, 'etapes': etapes},
    );
  });

  /// « 600.00 » et « 600.0000 » sont le même prix : on compare les valeurs.
  String? nombre(String? s) {
    if (s == null) return null;
    if (!s.contains('.')) return s;
    final epure = s
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
    return epure.isEmpty ? '0' : epure;
  }

  /// `articles.prix_achat` est un DECIMAL(15,2) : le serveur arrondit au centime ce que le
  /// poste garde à quatre décimales (écart nommé dans `dernierPrixAchatDe`) ; les deux
  /// s'affichent au franc. On compare au centime, moitié vers le haut.
  String? centime(String? s) {
    if (s == null) return null;
    final p = s.split('.');
    final dec = (p.length > 1 ? p[1] : '').padRight(4, '0');
    var c = int.parse(p[0]) * 100 + int.parse(dec.substring(0, 2));
    if (int.parse(dec.substring(2, 3)) >= 5) c++;
    return (c / 100).toStringAsFixed(2);
  }

  /// La valeur du serveur est un décimal au centime ; le poste l'arrondit au franc
  /// (écart nommé dans `valeurEnFrancs`) : on arrondit celle du serveur comme l'écran
  /// web la formate, moitié vers le haut.
  int francs(String decimal) {
    final parts = decimal.split('.');
    final entier = int.parse(parts[0]);
    final centimes = parts.length > 1
        ? int.parse(parts[1].padRight(2, '0').substring(0, 2))
        : 0;
    return entier + (centimes >= 50 ? 1 : 0);
  }

  Map<String, dynamic> duServeur(String libelle) =>
      (serveur['serveur'] as Map<String, dynamic>)[libelle]
          as Map<String, dynamic>;

  List<Map<String, Object?>> descente({bool sansCout = false}) => [
    for (final e in (serveur['descente'] as List<dynamic>))
      () {
        final element = Map<String, Object?>.from(e as Map<String, dynamic>);
        if (sansCout && element['table'] == 'mouvements_stock') {
          final donnees = Map<String, Object?>.from(element['donnees']! as Map)
            ..remove('cout_unitaire');
          element['donnees'] = donnees;
        }
        return element;
      }(),
  ];

  Future<void> descendreSur(
    BancSync b,
    List<Map<String, Object?>> elements,
  ) async {
    await DescenteCatalogueDao(b.db).effacerCurseur();
    final bilan = await b
        .descente(
          FauxTransport(
            (r) => r.methode == 'GET'
                ? FauxCatalogue(elements).repondre(r)
                : reponseLot(r),
          ),
        )
        .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
    expect(bilan.refuses, 0, reason: bilan.motifsRefus.join(' ; '));
    expect(bilan.enAttenteDeDependance, 0);
  }

  Future<Map<String, LigneStock>> lignesDe(AppDatabase db) async {
    final etat = await StocksDao(db).etat();
    return {for (final l in etat.lignes) l.libelle: l};
  }

  /// Le poste A : les mêmes gestes que le barman, par `StocksApi` (modale « Mouvement de stock »).
  Future<Map<String, LigneStock>> posteA() async {
    final db = AppDatabase.enMemoire();
    addTearDown(db.close);
    await db
        .into(db.utilisateursLocal)
        .insert(
          UtilisateursLocalCompanion.insert(
            id: 'u-barman',
            login: 'barman',
            nom: 'Barman',
            role: 'barman',
            droitsJson: '{}',
            sel: 's',
            empreinte: 'e',
            iterations: 1,
            dateCreation: DateTime(2026, 11, 1),
            dateMotDePasse: DateTime(2026, 11, 1),
          ),
        );
    var horloge = DateTime(2026, 11, 9, 8);
    final api = StocksApi(
      dao: StocksDao(
        db,
        maintenant: () => horloge = horloge.add(const Duration(minutes: 1)),
      ),
      peutLire: () => true,
      peutEcrire: () => true,
      auteurId: () => 'u-barman',
    );
    final point =
        ((await api.creerPoint(libelle: 'Bar', type: TypePoint.bar))
                as PointEnregistre)
            .point
            .id;
    final ids = <String, String>{};
    for (final libelle in articles) {
      ids[libelle] = 'a-${ids.length}';
      final r = await api.enregistrerArticle(
        SaisieArticle(
          id: ids[libelle]!,
          libelle: libelle,
          categorie: 'boisson',
          uniteMesure: 'unite',
          seuilAlerte: '5',
          suivi: SuiviArticle.permanent,
          pointStockageId: point,
        ),
      );
      expect(r, isA<ArticleEnregistre>(), reason: '$r');
    }
    for (final e in etapes) {
      final type = switch (e['type']) {
        'entree' => TypeMouvement.entree,
        'sortie' => TypeMouvement.sortie,
        _ => TypeMouvement.perte,
      };
      final r = await api.enregistrerMouvement(
        SaisieMouvement(
          articleId: ids[e['article']]!,
          pointId: point,
          type: type,
          quantite: ecrireCentiemes(e['centiemes']! as int),
          motif: 'Essai',
          coutUnitaire: e['cout'] == null
              ? null
              : ecrireCout(e['cout']! as int),
          validationRupture: type != TypeMouvement.entree,
        ),
      );
      expect(
        r,
        isA<MouvementEnregistre>(),
        reason: r is MouvementRefuse
            ? '${e['type']} ${e['article']} : ${r.motif} ${r.erreurs}'
            : '$r',
      );
    }
    return lignesDe(db);
  }

  void exigerEgalite(String qui, Map<String, LigneStock> poste) {
    for (final libelle in articles) {
      final l = poste[libelle];
      final s = duServeur(libelle);
      expect(l, isNotNull, reason: '$qui : « $libelle » absent');
      expect(l!.stock, s['stock'], reason: '$qui / $libelle : stock');
      expect(
        centime(l.prixAchat),
        centime(s['prix_achat'] as String?),
        reason: '$qui / $libelle : valeur d’achat',
      );
      expect(
        nombre(l.coutMoyenPondere),
        nombre(s['cmp'] as String?),
        reason: '$qui / $libelle : CMP',
      );
      expect(
        int.parse(l.valeurStock),
        francs(s['valeur'] as String),
        reason: '$qui / $libelle : valeur du stock',
      );
    }
  }

  test(
    'le serveur a bien des valeurs à montrer (le cas du PO, pas un cas vide)',
    () {
      expect(duServeur('Café double')['prix_achat'], '600.00');
      expect(duServeur('Café double')['cmp'], '525.0000');
      expect(duServeur('Café double')['stock'], '16.00');
      expect(
        duServeur('Bière 65cl')['cmp'],
        '95.2380',
        reason: 'un CMP à décimales',
      );
      expect(duServeur('Thé sans prix')['prix_achat'], isNull);
      // Le coût descend avec le mouvement : sans lui, un poste n'a rien à rejouer.
      final avecCout = (serveur['descente'] as List<dynamic>).where(
        (e) =>
            (e as Map)['table'] == 'mouvements_stock' &&
            (e['donnees'] as Map)['cout_unitaire'] != null,
      );
      expect(avecCout, hasLength(3));
    },
  );

  test(
    'poste A (barman) : ses écrans donnent les valeurs du serveur',
    () async {
      exigerEgalite('poste A', await posteA());
    },
  );

  test(
    'poste B (gérant) : la descente du serveur donne les MÊMES valeurs que le web',
    () async {
      final b = await BancSync.creer();
      addTearDown(b.fermer);
      await b.semerAuteur();
      await descendreSur(b, descente());
      exigerEgalite('poste B', await lignesDe(b.db));
    },
  );

  test(
    'A, B et le serveur affichent la même chose, article par article',
    () async {
      final a = await posteA();
      final b = await BancSync.creer();
      addTearDown(b.fermer);
      await b.semerAuteur();
      await descendreSur(b, descente());
      final lb = await lignesDe(b.db);
      for (final libelle in articles) {
        expect(
          [
            lb[libelle]!.stock,
            lb[libelle]!.prixAchat,
            lb[libelle]!.coutMoyenPondere,
            lb[libelle]!.valeurStock,
          ],
          [
            a[libelle]!.stock,
            a[libelle]!.prixAchat,
            a[libelle]!.coutMoyenPondere,
            a[libelle]!.valeurStock,
          ],
          reason: libelle,
        );
      }
    },
  );

  test(
    'REDESCENTE : des mouvements reçus SANS coût (curseur déjà passé) sont complétés',
    () async {
      final b = await BancSync.creer();
      addTearDown(b.fermer);
      await b.semerAuteur();

      // Ce que livrait le serveur avant : le bug du PO, reproduit sur le poste.
      await descendreSur(b, descente(sansCout: true));
      final avant = await lignesDe(b.db);
      expect(
        avant['Café double']!.stock,
        '16.00',
        reason: 'les stocks descendaient déjà',
      );
      expect(
        avant['Café double']!.prixAchat,
        isNull,
        reason: 'valeur d’achat « — »',
      );
      // v59 (10/11/2026) : sans coût de mouvement, le CMP du serveur tient lieu de référence —
      // jamais « — » là où le web affiche un chiffre (16 × 525 = 8 400).
      expect(avant['Café double']!.cmpDeReference, isTrue);
      expect(
        int.parse(avant['Café double']!.valeurStock),
        8400,
        reason: 'valeur du stock = celle du web, par la référence',
      );

      // La mise à jour oublie le curseur (migration v56) ; la descente complète les lignes.
      await descendreSur(b, descente());
      exigerEgalite('poste B redescendu', await lignesDe(b.db));
      final lignes = await b.db.select(b.db.mouvementsStockLocal).get();
      expect(lignes, hasLength(6), reason: 'aucune ligne en double');
    },
  );

  test('un coût déjà présent n’est jamais réécrit par la descente', () async {
    final b = await BancSync.creer();
    addTearDown(b.fermer);
    await b.semerAuteur();
    await descendreSur(b, descente());
    await b.db.customStatement(
      'UPDATE mouvements_stock_local SET cout_unitaire_dix_milliemes = 1 WHERE cout_unitaire_dix_milliemes IS NOT NULL',
    );
    await descendreSur(b, descente());
    final couts = await b.db
        .customSelect(
          'SELECT cout_unitaire_dix_milliemes AS c FROM mouvements_stock_local WHERE cout_unitaire_dix_milliemes IS NOT NULL',
        )
        .get();
    expect(couts.map((r) => r.data['c']), everyElement(1));
  });

  testWidgets(
    'le GÉRANT voit Valeur d’achat, CMP et Valeur stock (aucun masquage par rôle)',
    (tester) async {
      // Les E/S réelles (dossier temporaire, base) se font HORS de l'horloge simulée.
      final b = (await tester.runAsync(BancSync.creer))!;
      addTearDown(b.fermer);
      await tester.runAsync(() async {
        await b.semerAuteur();
        await descendreSur(b, descente());
      });

      tester.view
        ..physicalSize = const Size(1600, 1400)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final droits = GardeAcces({'M6': 'C'});
      final session = Session(
        utilisateurId: 'u-admin',
        login: 'gerant',
        nom: 'Gérant',
        role: 'gerant',
        droits: droits,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseLocaleProvider.overrideWithValue(b.db),
            droitsProvider.overrideWithValue(droits),
            sessionProvider.overrideWithBuild((ref, notifier) => session),
          ],
          child: MaterialApp(
            theme: AppTheme.clair,
            home: const Scaffold(body: EcranStocks()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Café double'), findsWidgets);
      expect(find.text('600 FCFA'), findsWidgets, reason: 'valeur d’achat');
      expect(find.textContaining('525'), findsWidgets, reason: 'CMP');
      expect(
        find.text('8 400 FCFA'),
        findsWidgets,
        reason: 'valeur du stock : 16 × 525',
      );
    },
  );
}
