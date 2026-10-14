/// Le catalogue des boissons — `prototype_v2/pages/m5-bar.html`.
///
/// Une ligne de `cartes_boisson`, telle que `BoissonResource` la rend.
///
/// ## Les montants restent des CHAÎNES jusqu'à l'affichage
///
/// `prix_vente` et `stock_disponible` sortent du serveur en `decimal:2`,
/// c'est-à-dire en chaîne. Les convertir en `double` ici les ferait passer par
/// un flottant pour n'être que ré-affichés : la règle projet interdit
/// l'égalité flottante sur un montant, et ce client n'en calcule aucun.
library;

/// Les trois catégories du maître — `m5-bar.html` l.83-87 pour le filtre,
/// l.140-146 pour le formulaire.
///
/// ## Le maître écrit la CAPITALE, le serveur écrit la minuscule
///
/// L'enum `cartes_boisson.categorie` vaut `locale`, `maison`, `importee` —
/// sans accent, en minuscules (migration `create_stocks.php` l.82), et
/// `EnregistrerBoissonRequest` pose `Rule::in(['locale','maison','importee'])`.
/// Le maître, lui, affiche « Locale », « Maison », « Importée ».
///
/// Les deux registres cohabitent donc, et ce fichier est le **seul** endroit où
/// ils se rencontrent : [code] part au serveur, [libelle] va à l'écran. Deux
/// tables de correspondance écrites à deux endroits divergeraient — c'est le
/// piège nommé à propos des types de client (PA-116), où « Entreprise » à
/// l'écran et `structure` au schéma cassent la synchronisation quand on les
/// confond.
enum CategorieBoisson {
  locale('locale', 'Locale'),
  maison('maison', 'Maison'),
  importee('importee', 'Importée');

  const CategorieBoisson(this.code, this.libelle);

  /// Ce qui part au serveur.
  final String code;

  /// Ce que le maître affiche, à la capitale près.
  final String libelle;

  /// La catégorie du code serveur, ou `null` si le serveur en rend un que ce
  /// client ne connaît pas.
  ///
  /// `null` plutôt qu'un repli sur `locale` : une valeur ajoutée à l'enum
  /// demain se verrait, au lieu d'être rangée en silence dans la mauvaise
  /// case. Le tableau affiche alors la pastille de repli du moteur CRUD.
  static CategorieBoisson? depuisCode(String? code) {
    for (final c in CategorieBoisson.values) {
      if (c.code == code) return c;
    }
    return null;
  }
}

/// Une boisson de la carte, telle que le serveur la rend.
final class Boisson {
  const Boisson({
    required this.id,
    required this.libelle,
    required this.categorie,
    required this.categorieBrute,
    required this.prixVente,
    required this.articleId,
    required this.stockDisponible,
    required this.stockLectureSeule,
    this.unitesVendablesParUniteStock,
  });

  final String id;

  /// Le maître appelle ce champ « Nom de la boisson » ; le schéma l'appelle
  /// `libelle`. Le nom du champ suit le schéma, le libellé suit le maître.
  final String libelle;

  /// `null` quand le serveur rend un code hors du registre fermé.
  final CategorieBoisson? categorie;

  /// Ce que le serveur a réellement envoyé, conservé pour l'afficher tel quel
  /// quand [categorie] est `null`. Sans lui, une valeur inconnue disparaîtrait
  /// de l'écran au lieu de s'y voir.
  final String? categorieBrute;

  /// `DECIMAL(15,2)`, en chaîne.
  final String prixVente;

  /// Le lien vers l'article de stock (M6). **NOT NULL au schéma**, et
  /// `required` à `EnregistrerBoissonRequest` : une boisson sans article ne
  /// décrémenterait aucun casier à la vente (RG-05).
  final String articleId;

  /// Stock **calculé par le serveur** (`StockTheoriqueService`), en chaîne.
  ///
  /// ⚠ `null` ne veut PAS dire zéro. `BoissonResource::stockDisponible()` rend
  /// `null` quand aucun `PointStockage` de type `bar` n'existe — « un zéro se
  /// lirait "rupture", alors que la réalité est "on ne sait pas" », écrit le
  /// commentaire du serveur. L'écran distingue les deux (Article 7).
  final String? stockDisponible;

  /// Le drapeau que le serveur pose à `true` en dur : ce champ ne se saisit
  /// jamais (PA-24).
  ///
  /// Il est lu, et non supposé : le jour où le serveur cesserait de l'affirmer,
  /// l'écran ne s'en apercevrait pas si ce client codait `true` de son côté.
  final bool stockLectureSeule;

  /// Le conditionnement du lien — unités VENDABLES par unité de stock (24 pour
  /// un casier de 24), en chaîne `decimal:4`. `null` quand le serveur ne l'a
  /// pas rendu : un serveur antérieur au 11/09/2026 ne l'exposait pas, et
  /// « Lier au stock » refuse alors de proposer une valeur plutôt que de
  /// repartir de 1 (`EcranDeCarte::ouvrirLienAuStock()`).
  final String? unitesVendablesParUniteStock;

  /// Le libellé de catégorie à afficher — celui du maître quand le code est
  /// connu, le code brut sinon.
  String? get categorieLibelle => categorie?.libelle ?? categorieBrute;
}
