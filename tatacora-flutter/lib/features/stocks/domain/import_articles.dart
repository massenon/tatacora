/// L'IMPORT D'ARTICLES par fichier CSV — réplique, sur ce poste, de
/// `Stocks::lancerImport()` et `Stocks::telechargerModeleCsv()` du serveur
/// (`app/Pwa/Livewire/Stocks/Stocks.php`, lus le 14/10/2026), et des mots de
/// `lang/fr/stocks_pwa.php` (`import`).
///
/// ## Les règles du serveur, une par une
///
/// | Règle | Serveur | Ici |
/// |---|---|---|
/// | En-tête | 1re ligne, au moins 8 colonnes, sinon `entete_absente` | idem |
/// | Séparateur | `fgetcsv(…, ';')`, guillemets doublés | idem, BOM UTF-8 retiré |
/// | Ligne blanche | sautée, ce n'est pas une erreur | idem |
/// | Numéro de ligne | l'en-tête est la ligne 1 | idem |
/// | Point | correspondance EXACTE du libellé, sinon aucun point | idem |
/// | Suivi | hors registre → `permanent` | idem |
/// | Seuil | `journalier` → 0 ; colonne absente → 0 | idem |
/// | Stock d'ouverture | ENTRÉE si permanent, point connu, `is_numeric` et > 0 | idem — jamais une colonne |
/// | Coût de l'entrée | `prix_achat` s'il est `is_numeric`, sinon aucun | idem |
/// | Ligne fautive | NOMMÉE, l'import continue | idem |
/// | Bilan | `bilan` ou `bilan_partiel` | idem |
///
/// ## Deux écarts, nommés
///
///  * **Une ligne = UNE transaction** (article ET entrée d'ouverture,
///    `StocksDao.creerArticle`). Le serveur écrit l'article puis l'entrée hors
///    transaction : une entrée refusée laisse chez lui un article créé SANS son
///    stock, compté refusé. Ici, rien n'est écrit pour une ligne refusée.
///  * **Le stock d'ouverture IGNORÉ est DIT.** Quand le point est inconnu ou la
///    quantité illisible, le serveur crée l'article et laisse tomber l'entrée
///    sans un mot — un stock faux que rien ne signale. Le poste fait la même
///    chose (l'article est créé, comme au serveur) mais l'écrit au compte rendu.
///    Défaut du serveur à remonter à l'Architecte (14/10/2026).
///
/// Les refus d'une ligne sont ceux de `StocksApi.enregistrerArticle` — les
/// mêmes que la modale « Nouvel article » : un libellé ou une unité vide, un
/// seuil illisible sont refusés là où le serveur laisse MySQL lever (message
/// technique). Même issue (ligne refusée), message lisible.
library;

import 'dart:convert';

import 'calcul_stock.dart';
import 'entities/etat_stock.dart';
import 'entities/mouvement_stock.dart';

/// Les mots de la vue — `stocks_pwa.import`, au mot (apostrophes droites).
abstract final class TextesImportArticles {
  static const String titre = 'Importer des articles';
  static const String sousTitre =
      "Fichier CSV, une ligne par article. Le stock d'ouverture entre comme un "
      'mouvement, jamais comme une colonne.';
  static const String fichier = 'Fichier CSV';
  static const String valider = 'Importer';
  static const String modele = 'Modèle';
  static const String fichierIllisible =
      "Le fichier n'a pas pu être lu : il est vide, ou ce n'est pas un CSV.";
  static const String enteteAbsente =
      "La première ligne doit être l'en-tête du modèle. Téléchargez le modèle "
      'et repartez de lui.';

  /// `colonnes` : « Colonnes attendues, dans cet ordre : :colonnes », les
  /// colonnes jointes par « ; » (`implode(' ; ', COLONNES_IMPORT)`).
  static final String colonnes =
      'Colonnes attendues, dans cet ordre : ${colonnesImportArticles.join(' ; ')}';

  static String bilan(int crees) => '$crees article(s) importé(s).';
  static String bilanPartiel(int crees, int refuses) =>
      '$crees importé(s), $refuses refusé(s).';
  static String ligneRefusee(int numero, String nom, String raison) =>
      'ligne $numero — ${nom.isEmpty ? '?' : nom} : $raison';

  /// Propre au poste (voir l'écart n° 2 de l'en-tête).
  static String ouvertureIgnoree(int numero, String nom, String raison) =>
      'ligne $numero — ${nom.isEmpty ? '?' : nom} : créé sans stock '
      "d'ouverture ($raison).";

  /// Le nom proposé par la fenêtre « Enregistrer sous » — celui du serveur.
  static const String nomModele = 'modele_import_articles.csv';
}

/// `Stocks::COLONNES_IMPORT` — l'en-tête du modèle, dans l'ordre.
const List<String> colonnesImportArticles = [
  'nom',
  'categorie',
  'unite_mesure',
  'prix_achat',
  'seuil_alerte',
  'point_stockage',
  'suivi',
  'stock_initial',
];

/// Le modèle d'import : BOM UTF-8, en-tête au point-virgule, AUCUNE ligne.
///
/// ÉCART au serveur, demandé par le PO le 14/10/2026 (« le CSV vide aux
/// colonnes attendues ») : `telechargerModeleCsv()` ajoute une ligne
/// d'exemple (« Riz local (sac 50 kg) ») qui serait importée comme un vrai
/// article si l'utilisateur oubliait de l'effacer.
List<int> modeleImportArticlesOctets() =>
    utf8.encode('\u{FEFF}${colonnesImportArticles.join(';')}\r\n');

/// Le compte rendu d'un import.
final class BilanImportArticles {
  const BilanImportArticles({
    this.crees = 0,
    this.refusees = const [],
    this.reserves = const [],
    this.erreurFichier,
  });

  final int crees;

  /// Une phrase par ligne refusée (`ligne_refusee`).
  final List<String> refusees;

  /// Les lignes CRÉÉES dont le stock d'ouverture a été ignoré (écart n° 2).
  final List<String> reserves;

  /// Le fichier entier refusé (`fichier_illisible`, `entete_absente`).
  final String? erreurFichier;

  bool get complet => erreurFichier == null && refusees.isEmpty;

  /// `bilan` ou `bilan_partiel`, au mot du serveur.
  String get phrase =>
      erreurFichier ??
      (refusees.isEmpty
          ? TextesImportArticles.bilan(crees)
          : TextesImportArticles.bilanPartiel(crees, refusees.length));
}

/// Lit un CSV au point-virgule comme `fgetcsv` : guillemets, guillemets
/// doublés, séparateur et saut de ligne protégés entre guillemets. Le BOM
/// UTF-8 de tête est retiré (les CSV du poste en portent un).
List<List<String>> lireCsvPointVirgule(String contenu) {
  var texte = contenu;
  if (texte.startsWith('\u{FEFF}')) texte = texte.substring(1);

  final lignes = <List<String>>[];
  var champs = <String>[];
  final champ = StringBuffer();
  var entreGuillemets = false;
  var i = 0;

  void finirChamp() {
    champs.add(champ.toString());
    champ.clear();
  }

  void finirLigne() {
    finirChamp();
    lignes.add(champs);
    champs = <String>[];
  }

  while (i < texte.length) {
    final c = texte[i];
    if (entreGuillemets) {
      if (c == '"') {
        if (i + 1 < texte.length && texte[i + 1] == '"') {
          champ.write('"');
          i++;
        } else {
          entreGuillemets = false;
        }
      } else {
        champ.write(c);
      }
    } else if (c == '"') {
      entreGuillemets = true;
    } else if (c == ';') {
      finirChamp();
    } else if (c == '\r') {
      // `\r\n` : le `\n` qui suit ferme la ligne.
      if (!(i + 1 < texte.length && texte[i + 1] == '\n')) finirLigne();
    } else if (c == '\n') {
      finirLigne();
    } else {
      champ.write(c);
    }
    i++;
  }
  if (champ.isNotEmpty || champs.isNotEmpty) finirLigne();
  return lignes;
}

/// `is_numeric` de PHP sur une chaîne déjà rognée : entier ou décimal à point,
/// signe et exposant admis. « 12,5 » n'est PAS numérique pour le serveur.
bool estNumeriquePhp(String valeur) =>
    RegExp(r'^[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?$').hasMatch(valeur);

/// Importe [contenu] : une ligne = un appel à [enregistrer] (validation et
/// transaction de `StocksApi.enregistrerArticle`). [nouvelId] fournit l'UUID
/// de chaque article — né côté client, comme pour la modale.
Future<BilanImportArticles> importerArticles({
  required String contenu,
  required List<PointStockage> points,
  required Future<ResultatImportLigne> Function(SaisieArticle saisie)
  enregistrer,
  required String Function() nouvelId,
}) async {
  final lignes = lireCsvPointVirgule(contenu);
  if (lignes.isEmpty || lignes.first.length < colonnesImportArticles.length) {
    return const BilanImportArticles(
      erreurFichier: TextesImportArticles.enteteAbsente,
    );
  }

  final pointsParLibelle = {for (final p in points) p.libelle: p.id};
  var crees = 0;
  final refusees = <String>[];
  final reserves = <String>[];
  var numero = 1;

  String? colonne(List<String> c, int i) => i < c.length ? c[i] : null;

  for (final colonnes in lignes.skip(1)) {
    numero++;
    if (colonnes.every((v) => v.trim().isEmpty)) continue;

    final nom = (colonne(colonnes, 0) ?? '').trim();
    final pointLibelle = (colonne(colonnes, 5) ?? '').trim();
    final pointId = pointsParLibelle[pointLibelle];
    final suivi =
        SuiviArticle.depuisCode((colonne(colonnes, 6) ?? '').trim()) ??
        SuiviArticle.permanent;
    final journalier = suivi == SuiviArticle.journalier;
    final seuil = journalier ? '0' : (colonne(colonnes, 4) ?? '0').trim();
    final ouverture = (colonne(colonnes, 7) ?? '0').trim();
    final prix = (colonne(colonnes, 3) ?? '').trim();
    final categorie = (colonne(colonnes, 1) ?? '').trim();

    // La condition EXACTE du serveur pour écrire l'entrée d'ouverture.
    final ouvertureEcrite =
        !journalier &&
        pointId != null &&
        estNumeriquePhp(ouverture) &&
        (lireCentiemes(ouverture) ?? 0) > 0;

    String? reserve;
    if (!journalier && !ouvertureEcrite && ouverture.isNotEmpty) {
      final quantite = estNumeriquePhp(ouverture)
          ? (lireCentiemes(ouverture) ?? 0)
          : null;
      if (quantite == null) {
        reserve = 'quantité « $ouverture » illisible';
      } else if (quantite > 0 && pointId == null) {
        reserve = pointLibelle.isEmpty
            ? 'aucun point de stockage'
            : 'point de stockage « $pointLibelle » inconnu';
      }
    }

    final resultat = await enregistrer(
      SaisieArticle(
        id: nouvelId(),
        libelle: nom,
        categorie: categorie.isEmpty ? null : categorie,
        uniteMesure: (colonne(colonnes, 2) ?? '').trim(),
        seuilAlerte: seuil,
        suivi: suivi,
        pointStockageId: pointId,
        stockOuverture: ouvertureEcrite ? ouverture : '',
        valeurAchat: ouvertureEcrite && estNumeriquePhp(prix) ? prix : '',
      ),
    );

    switch (resultat) {
      case LigneImportee():
        crees++;
        if (reserve != null) {
          reserves.add(
            TextesImportArticles.ouvertureIgnoree(numero, nom, reserve),
          );
        }
      case LigneRefusee(:final motif):
        refusees.add(TextesImportArticles.ligneRefusee(numero, nom, motif));
    }
  }

  return BilanImportArticles(
    crees: crees,
    refusees: refusees,
    reserves: reserves,
  );
}

/// L'issue d'UNE ligne — indépendante du type de résultat de l'API, pour que
/// ce fichier de domaine ne dépende pas de la couche `data`.
sealed class ResultatImportLigne {
  const ResultatImportLigne();
}

final class LigneImportee extends ResultatImportLigne {
  const LigneImportee();
}

final class LigneRefusee extends ResultatImportLigne {
  const LigneRefusee(this.motif);
  final String motif;
}
