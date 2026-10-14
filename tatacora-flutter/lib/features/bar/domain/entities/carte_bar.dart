// Vue Blade maîtresse (PA-183) : pwa/bar/carte.blade.php
import '../../../pos/data/dto/catalogue_dto.dart';
import 'boisson.dart';

/// Une ligne de la **Carte du bar** — `prototype_v2/pages/m5-bar-carte.html`.
///
/// ## Deux sources, deux disponibilités
///
/// Le **libellé, la catégorie et le prix** viennent de la base locale : ils
/// sont répliqués (PA-129) et l'écran fonctionne donc hors connexion.
///
/// Le **stock**, lui, est calculé par le serveur sur des tables M6 que ce poste
/// ne détient pas. Il n'est **pas stocké** : figé localement, il deviendrait
/// faux à la première vente sans que rien ne le signale — même refus que le
/// solde client (PA-126). Hors connexion, il est simplement absent, et l'écran
/// le dit au lieu d'afficher un zéro.
final class LigneCarte {
  const LigneCarte({
    required this.id,
    required this.libelle,
    required this.categorie,
    required this.prix,
    required this.articleId,
    required this.stock,
    this.indisponibilite,
    this.disponibiliteConnue = false,
    this.reserve,
    this.sousSeuil = false,
    this.rupture,
    this.stockNonConsulte = false,
    this.pointDeVenteAbsent = false,
    this.prixProvisoire = false,
    this.prixCorrigeMain = false,
    this.lienLibelle,
    this.lienDetail,
  });

  /// « corrigé à la main » — la seconde marque sous le prix (PA-200).
  final bool prixCorrigeMain;

  /// « Article de stock » : libellé et conditionnement en clair, du serveur.
  final String? lienLibelle;
  final String? lienDetail;

  /// La réserve — le stock hors point de vente, en unités vendables — ou
  /// `null` : sans solde au point, elle ne se calcule pas (jamais un zéro).
  final double? reserve;

  /// Sous le seuil d'alerte de l'article, selon le serveur.
  final bool sousSeuil;

  /// La rupture selon le SERVEUR (`null` sans chiffre) — voir [enRupture].
  final bool? rupture;

  /// Lié au stock, mais sans chiffre : lecture impossible ou point de vente
  /// absent. Distinct d'une absence de lien, et jamais un zéro.
  final bool stockNonConsulte;

  /// Aucun point de stockage de type « bar » n'est déclaré au serveur.
  final bool pointDeVenteAbsent;

  /// PA-161 (b) — un tarif provisoire, à confronter à la carte.
  final bool prixProvisoire;

  final String id;
  final String libelle;
  final String categorie;

  /// En francs entiers : le XOF n'a pas de sous-unité en circulation.
  final int prix;

  /// Le lien vers l'article de stock (M6), ou `null` s'il n'y en a pas.
  ///
  /// Le maître distingue « lié au stock » de « sans lien » parce que la
  /// conséquence n'est pas la même : une boisson sans lien ne décrémente aucun
  /// casier, donc sa vente ne se rapproche de rien.
  final String? articleId;

  /// Stock disponible **tel que le serveur l'a calculé**, ou `null`.
  ///
  /// ⚠ `null` a **deux causes** que l'écran distingue : pas de lien de stock,
  /// ou serveur injoignable. Les confondre ferait passer une carte entière pour
  /// « sans lien » un jour de coupure.
  final double? stock;

  /// Le retrait de la carte du jour en cours, ou `null`.
  ///
  /// ⚠ `null` ne veut « à la carte » que si [disponibiliteConnue] : hors
  /// connexion, le poste ne sait pas si une boisson a été retirée ailleurs,
  /// et l'écran n'offre alors ni « Rendre indispo. » ni « Remettre » — le
  /// mauvais des deux serait proposé une fois sur deux.
  final IndisponibiliteDistante? indisponibilite;

  /// Le serveur a-t-il répondu pour cette ligne ?
  final bool disponibiliteConnue;

  bool get estRetiree => indisponibilite != null;

  bool get estLieAuStock => articleId != null && articleId!.isNotEmpty;

  /// Un prix à zéro n'est pas un prix : c'est une ligne qu'on négociera au
  /// comptoir. Le maître l'écarte de la fiche des prix **en le comptant**.
  bool get sansPrix => prix <= 0;

  /// Le drapeau du serveur quand il l'a rendu ; à défaut, le chiffre.
  bool get enRupture => rupture ?? (stock != null && stock! <= 0);
}

/// Le filtre « état » de la vue (`pwa/carte/corps.blade.php` l.246-254), ses
/// six entrées dans son ordre et avec ses mots (`carte_pwa.commun.etat_*`).
///
/// « Retirés du jour » et « Prix provisoire » manquaient jusqu'au 11/09/2026 :
/// le retrait est rendu par l'API depuis PA-191, `prix_provisoire` depuis
/// PA-199. Portés en PA-200.
enum EtatCarte {
  tous('', 'Tous les articles'),
  indisponible('indisponible', 'Retirés du jour'),
  lie('lie', 'Liés au stock'),
  sansLien('sans_lien', 'Sans lien de stock'),
  ruptureStock('rupture_stock', 'En rupture de stock'),
  provisoire('provisoire', 'Prix provisoire');

  const EtatCarte(this.code, this.libelle);

  final String code;
  final String libelle;
}

/// Compose la carte à partir du catalogue **local**, enrichi du stock **distant**
/// quand il est disponible.
List<LigneCarte> composerCarte({
  required List<LigneCarte> local,
  List<BoissonDistante>? distantes,
}) {
  if (distantes == null) return local;

  final parId = {for (final b in distantes) b.id: b};

  return local
      .map((l) {
        final b = parId[l.id];
        return LigneCarte(
          id: l.id,
          libelle: l.libelle,
          categorie: l.categorie,
          prix: l.prix,
          // Le lien de stock du serveur fait foi : la copie locale peut dater
          // d'avant un rattachement fait au bureau.
          articleId: b == null ? l.articleId : b.articleId,
          // ⚠ Le stock VENDABLE (bouteilles), jamais `stockDisponible`
          // (casiers) : c'est le chiffre de la carte PWA (PA-199). Jusqu'au
          // 11/09/2026, cet écran lisait les casiers — « 2 » là où la PWA
          // disait « 48 » pour un casier de 24.
          stock: b?.stockVendable,
          indisponibilite: b?.indisponibilite,
          // Une boisson absente de la réponse — créée ailleurs depuis, ou hors
          // de la page servie — n'a pas d'état connu : aucune supposition.
          disponibiliteConnue: b != null,
          reserve: b?.reserve,
          sousSeuil: b?.sousSeuil ?? false,
          rupture: b?.rupture,
          stockNonConsulte: b?.stockNonConsulte ?? false,
          pointDeVenteAbsent: b?.pointDeVenteAbsent ?? false,
          prixProvisoire: b?.prixProvisoire ?? false,
          prixCorrigeMain: b?.prixCorrigeMain ?? false,
          lienLibelle: b?.lienLibelle,
          lienDetail: b?.lienDetail,
        );
      })
      .toList(growable: false);
}

List<LigneCarte> filtrerCarte(
  List<LigneCarte> lignes, {
  String terme = '',
  String? categorie,
  EtatCarte etat = EtatCarte.tous,
}) {
  final recherche = terme.trim().toLowerCase();

  return lignes
      .where((l) {
        if (recherche.isNotEmpty &&
            !l.libelle.toLowerCase().contains(recherche)) {
          return false;
        }
        if (categorie != null && l.categorie != categorie) return false;

        return switch (etat) {
          EtatCarte.tous => true,
          EtatCarte.lie => l.estLieAuStock,
          EtatCarte.sansLien => !l.estLieAuStock,
          EtatCarte.ruptureStock => l.enRupture,
          EtatCarte.indisponible => l.estRetiree,
          EtatCarte.provisoire => l.prixProvisoire,
        };
      })
      .toList(growable: false);
}

/// Une ligne de l'onglet **« Couverture du stock »** : une CATÉGORIE.
///
/// ## Deux champs seulement, et c'est le fait qui commande tout cet onglet
///
/// Le maître groupe par catégorie et compte quatre choses — total, liés au
/// stock, indisponibles, prix provisoires (`carte-module.js` l.152-159). Une
/// seule est mesurable ici : le total.
///
/// **Le lien au stock est OBLIGATOIRE des deux côtés.** Au serveur,
/// `cartes_boisson.article_id` est un `foreignUuid(...)->constrained('articles')`
/// donc NOT NULL (`2026_08_01_000500_create_stocks.php` l.78-85) ; au poste,
/// `CartesBoissonLocal.articleId` est un `text()()` NOT NULL
/// (`bar_tables.dart` l.11). Le modèle local sait pourtant représenter une
/// absence — `catalogue_dao.dart` l.92-94 écrit la chaîne vide quand le serveur
/// rend `null` — mais **le serveur ne peut jamais rendre `null`**, la colonne le
/// lui interdit. Ce repli est donc inatteignable.
///
/// Conséquence : « liés au stock » vaudrait toujours le total, « sans lien »
/// toujours zéro, « couverture » toujours 100 %. Un chiffre qui ne peut prendre
/// qu'une valeur ne mesure rien — et l'afficher affirmerait le résultat d'un
/// rapprochement que personne n'effectue (PA-59/60/61). Les trois colonnes sont
/// **rendues à leur place et nommées vides**, jamais remplies.
///
/// C'est pourquoi cette entité ne porte ni `lies`, ni `sansLien`, ni `taux` : un
/// champ toujours égal à un autre finirait par être lu comme une mesure.
///
/// ⚠ Ce qui précède décrit l'état antérieur au 11/09/2026. Depuis PA-200,
/// l'onglet mesure les cinq colonnes, comme la vue (l.476-507) : le lien est
/// constant au bar, mais la vue l'affiche, et le client Flutter suit la vue
/// (PA-182) ; retraits et prix provisoires sont rendus par l'API.
final class CouvertureCategorieBar {
  const CouvertureCategorieBar({
    required this.categorie,
    required this.articles,
    this.lies = 0,
    this.indisponibles = 0,
    this.provisoires = 0,
  });

  final int lies;
  final int indisponibles;
  final int provisoires;

  int get sansLien => articles - lies;

  /// Arrondi au dixième comme `round(…, 1)` de la PWA.
  double get taux => tauxAuDixieme(lies, articles);

  String get tauxLisible => tauxLisibleDe(taux);

  /// La ligne TOTAL — la somme des catégories (vue l.499-507).
  static CouvertureCategorieBar total(List<CouvertureCategorieBar> lignes) =>
      CouvertureCategorieBar(
        categorie: 'TOTAL',
        articles: lignes.fold(0, (s, c) => s + c.articles),
        lies: lignes.fold(0, (s, c) => s + c.lies),
        indisponibles: lignes.fold(0, (s, c) => s + c.indisponibles),
        provisoires: lignes.fold(0, (s, c) => s + c.provisoires),
      );

  /// Le code brut du maître — `locale`, `maison`, `importee`
  /// (`bar_tables.dart` l.17). Aucune table de libellés n'existe dans ce dépôt,
  /// et l'onglet « Carte du jour » rend déjà le code tel quel
  /// (`table_carte.dart`) : en inventer un ici ferait dire deux mots différents
  /// à la même donnée sur le même écran.
  final String categorie;

  final int articles;

  /// Ce que la cellule affiche. Une catégorie vide n'est pas une catégorie
  /// nommée « » : le tiret de l'Article 7 dit qu'elle manque.
  String get libelle =>
      CategorieBoisson.depuisCode(categorie)?.libelle ??
      (categorie.isEmpty ? '—' : categorie);
}

/// Groupe la carte **locale** par catégorie — `vueCouverture()` l.150-159.
///
/// L'ordre est celui du **registre** des catégories (`CarteBoisson::CATEGORIES`,
/// repris par [CategorieBoisson]), puis celui de la première rencontre pour
/// une catégorie hors registre. Le maître, lui, itérait sur ce qu'il
/// rencontrait (`Object.keys(parCat)`) : la vue Blade, seule maîtresse depuis
/// PA-182, parcourt le registre.
///
/// ⚠ Cette fonction ne prend **jamais** la carte filtrée : le maître appelle
/// `C.articles({ module })` sans filtre à l.150, là où l'onglet « Carte du
/// jour » appelle `C.articles(filtres())`. Filtrer ferait tomber le total dès
/// qu'on cherche à mesurer un trou — c'est-à-dire précisément quand il compte.
List<CouvertureCategorieBar> couvertureParCategorie(List<LigneCarte> lignes) {
  // Le REGISTRE d'abord, comme `EcranDeCarte::couverture()` (l.882-893) :
  // une catégorie sans article est une ligne à zéro, pas une ligne absente.
  // Une carte vide rend donc les trois catégories, et c'est ce que la vue
  // montre. Une catégorie hors registre est RENDUE, après : la taire ferait
  // un total qui ne correspond pas à la somme des lignes.
  final ordre = <String>[for (final c in CategorieBoisson.values) c.code];
  final articles = <String, int>{for (final c in ordre) c: 0};
  final lies = <String, int>{};
  final retires = <String, int>{};
  final provisoires = <String, int>{};
  int plus(Map<String, int> m, String c) => m[c] = (m[c] ?? 0) + 1;

  for (final l in lignes) {
    if (!articles.containsKey(l.categorie)) {
      ordre.add(l.categorie);
      articles[l.categorie] = 0;
    }
    plus(articles, l.categorie);
    if (l.estLieAuStock) plus(lies, l.categorie);
    if (l.estRetiree) plus(retires, l.categorie);
    if (l.prixProvisoire) plus(provisoires, l.categorie);
  }

  return [
    for (final c in ordre)
      CouvertureCategorieBar(
        categorie: c,
        articles: articles[c]!,
        lies: lies[c] ?? 0,
        indisponibles: retires[c] ?? 0,
        provisoires: provisoires[c] ?? 0,
      ),
  ];
}

/// Un taux au DIXIÈME, en entiers — `round(($lies / $total) * 100, 1)` de la
/// PWA : 2/3 vaut 66,7, jamais 66,66666. Auteur unique de la bande et de
/// l'onglet Couverture.
double tauxAuDixieme(int lies, int total) =>
    total == 0 ? 0 : (lies * 1000 / total).round() / 10;

/// Le taux tel que la PWA l'imprime : « 100 », « 66.7 ».
String tauxLisibleDe(double taux) =>
    taux == taux.truncateToDouble() ? taux.toInt().toString() : taux.toString();

/// Les SIX indicateurs de la bande de la vue — `pwa/carte/corps.blade.php`
/// l.170-208, calculés comme `EcranDeCarte::indicateurs()` (PA-199).
///
/// ⚠ Cette entité en écartait trois jusqu'au 11/09/2026 : « disponibles /
/// retirés » et « prix provisoires » faute de donnée — les deux sont rendus
/// par l'API depuis (retrait, `prix_provisoire`) —, et « liés / sans lien /
/// couverture » parce que le lien est obligatoire, donc constant. La vue les
/// affiche néanmoins, et le client Flutter suit la vue (PA-182) : ils sont
/// rendus. Un chiffre constant reste vrai.
///
/// La rupture et le sous-seuil ne comptent que les lignes dont le serveur a
/// rendu un CHIFFRE, comme la PWA ; [stockConnu] dit s'il en a rendu un seul —
/// sans quoi « 0 en rupture » se lirait comme une bonne nouvelle.
final class KpisCarte {
  const KpisCarte({
    required this.articles,
    required this.indisponibles,
    required this.lies,
    required this.enRupture,
    required this.sousSeuil,
    required this.prixProvisoires,
    required this.stockConnu,
  });

  factory KpisCarte.calculer(List<LigneCarte> lignes) {
    var indisponibles = 0;
    var lies = 0;
    var rupture = 0;
    var sousSeuil = 0;
    var provisoires = 0;
    var stockConnu = false;

    for (final l in lignes) {
      if (l.estRetiree) indisponibles++;
      if (l.prixProvisoire) provisoires++;
      if (l.estLieAuStock) lies++;
      if (l.stock != null) {
        stockConnu = true;
        // `rupture` PUIS `sous_seuil`, jamais les deux : une ligne en
        // rupture est aussi sous son seuil, et la compter deux fois ferait
        // un total qui ne correspond à rien (`indicateurs()`, même ordre).
        if (l.enRupture) {
          rupture++;
        } else if (l.sousSeuil) {
          sousSeuil++;
        }
      }
    }

    return KpisCarte(
      articles: lignes.length,
      indisponibles: indisponibles,
      lies: lies,
      enRupture: rupture,
      sousSeuil: sousSeuil,
      prixProvisoires: provisoires,
      stockConnu: stockConnu,
    );
  }

  final int articles;
  final int indisponibles;
  final int lies;
  final int enRupture;
  final int sousSeuil;
  final int prixProvisoires;
  final bool stockConnu;

  int get disponibles => articles - indisponibles;
  int get sansLien => articles - lies;

  /// Le taux de couverture, arrondi au DIXIÈME comme `round(…, 1)` de la PWA,
  /// calculé en entiers : 2/3 vaut 66,7, jamais 66,66666.
  double get tauxCouverture => tauxAuDixieme(lies, articles);

  /// Le taux tel que la PWA l'imprime : « 100 », « 66.7 ».
  String get tauxLisible => tauxLisibleDe(tauxCouverture);
}
