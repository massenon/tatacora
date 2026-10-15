import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_api.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/import_articles.dart';

/// L'import d'articles (D436, 14/10/2026) éprouvé sur une VRAIE base locale,
/// par le même chemin que la modale : `importerArticles` → `StocksApi` →
/// `StocksDao`. Les règles sont celles de `Stocks::lancerImport` du serveur,
/// une par ligne du fichier d'essai.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late StocksApi api;
  late List<PointStockage> points;
  var compteur = 0;

  setUp(() async {
    db = AppDatabase.enMemoire();
    compteur = 0;
    await db
        .into(db.utilisateursLocal)
        .insert(
          UtilisateursLocalCompanion.insert(
            id: 'u-essai',
            login: 'essai',
            nom: 'Essai',
            role: 'magasinier',
            droitsJson: '{}',
            sel: 's',
            empreinte: 'e',
            iterations: 1,
            dateCreation: DateTime(2026, 10, 1),
            dateMotDePasse: DateTime(2026, 10, 1),
          ),
        );
    api = StocksApi(
      dao: StocksDao(db),
      peutLire: () => true,
      peutEcrire: () => true,
      auteurId: () => 'u-essai',
    );
    await api.creerPoint(libelle: 'Magasin');
    points = await api.points();
  });

  tearDown(() => db.close());

  Future<BilanImportArticles> importer(String contenu) => importerArticles(
    contenu: contenu,
    points: points,
    nouvelId: () => 'art-${++compteur}',
    enregistrer: (saisie) async {
      final r = await api.enregistrerArticle(saisie);
      return switch (r) {
        ArticleEnregistre() => const LigneImportee(),
        ArticleRefuse(:final motif) => LigneRefusee(motif),
        ArticleInjoignable() => const LigneRefusee('injoignable'),
      };
    },
  );

  final entete = colonnesImportArticles.join(';');

  test('un en-tête de moins de huit colonnes refuse le FICHIER, rien n’est '
      'écrit', () async {
    final bilan = await importer('nom;categorie\nRiz;Denrées\n');
    expect(bilan.erreurFichier, TextesImportArticles.enteteAbsente);
    expect(bilan.phrase, TextesImportArticles.enteteAbsente);
    expect(await StocksDao(db).articles(), isEmpty);
  });

  test('les règles du serveur, ligne par ligne, et le compte rendu', () async {
    final bilan = await importer(
      '\u{FEFF}$entete\r\n'
      // ligne 2 : permanent, point connu, ouverture 10 à 1250 → ENTRÉE.
      'Riz local;Denrées;sac;1250;5;Magasin;permanent;10\r\n'
      // ligne 3 : blanche, sautée sans erreur.
      ';;;;;;;\r\n'
      // ligne 4 : libellé vide → refusée, NOMMÉE, l'import continue.
      ';Denrées;sac;;;;permanent;\r\n'
      // ligne 5 : journalier → seuil 0, aucune entrée d'ouverture.
      'Pain;Boulangerie;pièce;;7;Magasin;journalier;5\r\n'
      // ligne 6 : point inconnu → créé SANS stock, et c'est DIT.
      'Sucre;Denrées;kg;;2;Cave;permanent;3\r\n'
      // ligne 7 : suivi hors registre → permanent.
      'Sel;Denrées;kg;;1;;inconnu;\r\n',
    );

    expect(bilan.crees, 4);
    expect(bilan.refusees, hasLength(1));
    expect(bilan.refusees.single, startsWith('ligne 4 — ? : '));
    expect(bilan.reserves, [
      TextesImportArticles.ouvertureIgnoree(
        6,
        'Sucre',
        'point de stockage « Cave » inconnu',
      ),
    ]);
    expect(bilan.phrase, TextesImportArticles.bilanPartiel(4, 1));
    expect(bilan.complet, isFalse);

    final dao = StocksDao(db);
    final articles = {for (final a in await dao.articles()) a.libelle: a};
    expect(articles.keys, containsAll(['Riz local', 'Pain', 'Sucre', 'Sel']));
    expect(articles['Pain']!.suivi, SuiviArticle.journalier);
    expect(articles['Pain']!.seuilCentiemes, 0);
    expect(articles['Sel']!.suivi, SuiviArticle.permanent);

    // Le stock d'ouverture est un MOUVEMENT d'entrée, jamais une colonne.
    final riz = await dao.mouvementsCalcul(
      articleId: articles['Riz local']!.id,
    );
    expect(riz, hasLength(1));
    expect(riz.single.type, TypeMouvement.entree);
    expect(riz.single.centiemes, 1000);
    expect(riz.single.coutDixMilliemes, isNotNull);
    for (final libelle in ['Pain', 'Sucre', 'Sel']) {
      expect(
        await dao.mouvementsCalcul(articleId: articles[libelle]!.id),
        isEmpty,
        reason: libelle,
      );
    }
  });

  test('un import complet rend la phrase « bilan » du serveur', () async {
    final bilan = await importer('$entete\nHuile;Denrées;litre;;2;;;\n');
    expect(bilan.complet, isTrue);
    expect(bilan.phrase, TextesImportArticles.bilan(1));
  });

  test('le modèle : BOM, en-tête au point-virgule, AUCUNE ligne', () {
    expect(
      String.fromCharCodes(modeleImportArticlesOctets()),
      isNot(contains('Riz')),
    );
    expect(
      lireCsvPointVirgule(
        String.fromCharCodes(modeleImportArticlesOctets().skip(3)),
      ),
      [colonnesImportArticles],
    );
  });
}
