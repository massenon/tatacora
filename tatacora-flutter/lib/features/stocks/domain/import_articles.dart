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
///
/// ## Porteur de la vue (21/10/2026)
///
/// [TextesImportArticles] porte les mots de la modale « Importer des
/// articles » — une seule fois ; la modale les rend sans les recopier. Pour
/// que la mesure de conformité les retrouve dans le code qui PORTE la modale,
/// ce fichier cite la vue : pwa/stocks/stocks.blade.php
/// (`etatFormulaire === 'import'`).
library;

import '../../../core/fichiers/ecriture_xlsx.dart';
import '../../transverse/domain/import_referentiels.dart'
    show estLigneExemple, normaliserImport;
import 'calcul_stock.dart';
import 'entities/etat_stock.dart';
import 'entities/mouvement_stock.dart';

/// Les mots de la vue — `stocks_pwa.import`, au mot (apostrophes droites).
abstract final class TextesImportArticles {
  static const String titre = 'Importer des articles';
  // Un littéral sur UNE ligne : la mesure de conformité ne recolle pas un
  // double guillemet suivi d'un simple.
  static const String sousTitre =
      "Classeur Excel (.xlsx), une ligne par article. Le stock d'ouverture entre comme un mouvement d'entrée.";
  static const String fichier = 'Fichier Excel (.xlsx) ou CSV';
  static const String valider = 'Importer';
  static const String modele = 'Modèle';
  static const String fichierIllisible =
      "Le fichier n'a pas pu être lu : il est vide, ou ce n'est ni un classeur "
      '.xlsx ni un CSV.';
  static String enteteAbsente(List<String> absentes, List<String> trouvees) =>
      'Ligne 1 : colonne(s) obligatoire(s) absente(s) de l\'en-tête : '
      '${absentes.join(', ')}. Colonnes trouvées : '
      '${trouvees.where((t) => t.trim().isNotEmpty).join(' ; ')}. '
      'Téléchargez le modèle .xlsx et repartez de lui.';

  /// `colonnes` : « Colonnes attendues, dans cet ordre : :colonnes », les
  /// colonnes jointes par « ; » (`implode(' ; ', COLONNES_IMPORT)`).
  static final String colonnes =
      "Colonnes attendues (repérées par leur nom, dans n'importe quel ordre) : ${colonnesImportArticles.join(' ; ')}";

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
  static const String nomModele = 'modele_import_articles.xlsx';
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

/// Les colonnes du modèle (`Stocks::colonnesImport` du serveur) — la
/// déclaration dont découlent le classeur `.xlsx` ET la lecture par nom.
const List<ColonneTableur> colonnesTableurArticles = [
  ColonneTableur(
    libelle: 'nom',
    requis: true,
    format: 'Texte libre',
    exemple: 'Riz local (sac 50 kg)',
  ),
  ColonneTableur(
    libelle: 'categorie',
    requis: false,
    format: 'Une valeur de la liste',
    valeurs: ['Denrées', 'Boissons', 'Fournitures', 'Pièces véhicules'],
    exemple: 'Denrées',
  ),
  ColonneTableur(
    libelle: 'unite_mesure',
    requis: true,
    format: 'Une valeur de la liste',
    valeurs: [
      'kg',
      'L',
      'unité',
      'sac',
      'carton',
      'casier',
      'pack',
      'bidon',
      'bouteille',
    ],
    exemple: 'sac',
  ),
  ColonneTableur(
    libelle: 'prix_achat',
    requis: false,
    format: 'Nombre',
    numerique: true,
    exemple: '32000',
  ),
  ColonneTableur(
    libelle: 'seuil_alerte',
    requis: false,
    format: 'Nombre',
    numerique: true,
    exemple: '4',
  ),
  ColonneTableur(
    libelle: 'point_stockage',
    requis: false,
    format: "Libellé exact d'une fiche existante",
    exemple: 'Magasin général',
  ),
  ColonneTableur(
    libelle: 'suivi',
    requis: false,
    format: 'Une valeur de la liste',
    valeurs: ['permanent', 'journalier'],
    exemple: 'permanent',
  ),
  ColonneTableur(
    libelle: 'stock_initial',
    requis: false,
    format: 'Nombre',
    numerique: true,
    exemple: '10',
  ),
];

/// Le modèle d'import : un VRAI classeur `.xlsx` (PO, 30/10/2026), feuilles
/// « Modèle » (en-têtes en gras, une ligne d'exemple, ignorée si elle reste
/// telle quelle) et « Aide ». Le CSV au point-virgule qui le précédait
/// s'ouvrait en UNE seule colonne dans un Excel réglé sur la virgule.
List<int> modeleImportArticlesOctets() => ecrireClasseurXlsx(
  nomModule: TextesImportArticles.titre,
  description: TextesImportArticles.sousTitre,
  colonnes: colonnesTableurArticles,
);

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

/// `is_numeric` de PHP sur une chaîne déjà rognée : entier ou décimal à point,
/// signe et exposant admis. « 12,5 » n'est PAS numérique pour le serveur.
bool estNumeriquePhp(String valeur) =>
    RegExp(r'^[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?$').hasMatch(valeur);

/// Une ligne du CSV d'articles, lue — la saisie à enregistrer et, quand le
/// stock d'ouverture est ignoré, sa RAISON (écart n° 2 de l'en-tête).
typedef LigneArticleLue = ({SaisieArticle saisie, String? reserve});

/// Lit UNE ligne du CSV d'articles ([colonnes] dans l'ordre de
/// [colonnesImportArticles]) — les règles du serveur, une par une (voir
/// l'en-tête). Partagée par l'import de l'écran Stocks ([importerArticles]) et
/// par l'onglet « Importer les données » de l'écran Import & Export : les deux
/// portes d'entrée lisent une ligne de la MÊME façon.
LigneArticleLue lireLigneArticle(
  List<String> colonnes, {
  required Map<String, String> pointsParLibelle,
  required String Function() nouvelId,
}) {
  String? colonne(int i) => i < colonnes.length ? colonnes[i] : null;

  final nom = (colonne(0) ?? '').trim();
  final pointLibelle = (colonne(5) ?? '').trim();
  final pointId = pointsParLibelle[pointLibelle];
  final suivi =
      SuiviArticle.depuisCode((colonne(6) ?? '').trim()) ??
      SuiviArticle.permanent;
  final journalier = suivi == SuiviArticle.journalier;
  final seuil = journalier ? '0' : (colonne(4) ?? '0').trim();
  final ouverture = (colonne(7) ?? '0').trim();
  final prix = (colonne(3) ?? '').trim();
  final categorie = (colonne(1) ?? '').trim();

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

  return (
    saisie: SaisieArticle(
      id: nouvelId(),
      libelle: nom,
      categorie: categorie.isEmpty ? null : categorie,
      uniteMesure: (colonne(2) ?? '').trim(),
      seuilAlerte: seuil,
      suivi: suivi,
      pointStockageId: pointId,
      stockOuverture: ouvertureEcrite ? ouverture : '',
      valeurAchat: ouvertureEcrite && estNumeriquePhp(prix) ? prix : '',
    ),
    reserve: reserve,
  );
}

/// Importe [tableau] (première ligne = en-tête, lue PAR NOM : une colonne
/// déplacée ou ajoutée ne décale rien) : une ligne = un appel à [enregistrer]
/// (validation et transaction de `StocksApi.enregistrerArticle`). [nouvelId]
/// fournit l'UUID de chaque article — né côté client, comme pour la modale.
Future<BilanImportArticles> importerArticles({
  required List<List<String>> tableau,
  required List<PointStockage> points,
  required Future<ResultatImportLigne> Function(SaisieArticle saisie)
  enregistrer,
  required String Function() nouvelId,
}) async {
  // champ → index de colonne, par nom d'en-tête.
  final index = <int, int>{};
  if (tableau.isNotEmpty) {
    for (final (i, e) in tableau.first.indexed) {
      final n = normaliserImport(e);
      final k = colonnesImportArticles.indexWhere(
        (c) => normaliserImport(c) == n,
      );
      if (k >= 0 && !index.containsKey(k)) index[k] = i;
    }
  }
  final absentes = [
    for (final (k, c) in colonnesImportArticles.indexed)
      if ((c == 'nom' || c == 'unite_mesure') && !index.containsKey(k)) c,
  ];
  if (absentes.isNotEmpty) {
    return BilanImportArticles(
      erreurFichier: TextesImportArticles.enteteAbsente(
        absentes,
        tableau.isEmpty ? const [] : tableau.first,
      ),
    );
  }

  final pointsParLibelle = {for (final p in points) p.libelle: p.id};
  var crees = 0;
  final refusees = <String>[];
  final reserves = <String>[];
  var numero = 1;

  for (final brute in tableau.skip(1)) {
    numero++;
    if (brute.every((v) => v.trim().isEmpty)) continue;

    // Remis dans l'ordre canonique de `colonnesImportArticles`.
    final colonnes = [
      for (var k = 0; k < colonnesImportArticles.length; k++)
        index.containsKey(k)
            ? (index[k]! < brute.length ? brute[index[k]!] : '')
            // Colonne ABSENTE du fichier : le défaut du serveur (`?? '0'`).
            : (k == 4 || k == 7 ? '0' : ''),
    ];
    // La ligne d'exemple du modèle (« (exemple) … ») n'est pas une donnée.
    if (estLigneExemple(brute)) continue;

    final lue = lireLigneArticle(
      colonnes,
      pointsParLibelle: pointsParLibelle,
      nouvelId: nouvelId,
    );
    final nom = lue.saisie.libelle;
    final reserve = lue.reserve;
    final resultat = await enregistrer(lue.saisie);

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
