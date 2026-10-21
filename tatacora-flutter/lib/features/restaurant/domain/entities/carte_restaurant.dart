/// Les entités de la **carte du restaurant** — `m4-restaurant-carte.html`.
///
/// Ce sont des entités de DOMAINE, jamais les corps JSON de l'API : un
/// `Repository` n'expose pas un DTO à `presentation/`, sans quoi renommer un
/// champ du serveur casserait un widget.
///
/// ## La règle qui gouverne tout ce fichier : `null` n'est pas `0`
///
/// Cinq champs peuvent valoir `null` ici, et **aucun** ne doit être replié sur
/// zéro à la lecture :
///
///  - [LigneCarteRestaurant.portionsVendables] — « on n'a pas compté » ;
///  - [LigneCarteRestaurant.coutMatiere] — « on ignore ce que ça coûte » ;
///  - [LigneCarteRestaurant.marge] — elle disparaît avec le coût ;
///  - [IndicateursCarte.tauxCouverture] — sur une carte vide ;
///  - [CouvertureCategorie.taux] — idem, par catégorie.
///
/// `DIRECTIVE_CONFORMITE_100.md` Article 7 : « — quand la donnée n'existe pas,
/// 0 quand elle vaut zéro. Les deux ne disent pas la même chose. » Sur l'écran
/// où l'on décide de retirer un plat de la carte ou d'en fixer le prix, un zéro
/// inventé est une décision prise à la place de quelqu'un.
library;

import '../../../pos/data/dto/catalogue_dto.dart' show IndisponibiliteDistante;

/// La catégorie d'un plat — **le type de son menu porteur**, jamais une
/// colonne de `plats`.
///
/// Le maître la pose sur le plat (`m4-restauration.html` l.138-147) ; le schéma
/// la porte sur `menus.type`, et `EnregistrerPlatRequest` la refuse
/// explicitement en saisie (« elle est celle de son menu »). Elle descend donc
/// **projetée** par `PlatResource`, en lecture seule.
///
/// Registre fermé : `Menu::TYPES` vaut `['local', 'europeen', 'special']`.
/// Un quatrième type ajouté demain n'obtiendra pas un libellé par omission —
/// il tombera dans [CategoriePlat.depuisCode] qui rend `null`, et l'écran
/// affichera le code brut plutôt qu'une traduction inventée.
enum CategoriePlat {
  /// `local` — libellé du maître : « Local » (`m4-restauration.html` l.71).
  local('local', 'Local'),

  /// `europeen` — libellé du maître : « Européen » (l.72).
  europeen('europeen', 'Européen'),

  /// `special` — libellé du maître : « Spécial » (l.73).
  special('special', 'Spécial');

  const CategoriePlat(this.code, this.libelle);

  /// Le code du serveur — `menus.type`, jamais traduit sur le fil.
  final String code;

  /// Le mot du maître, au caractère près. `MenuResource` le dit lui-même :
  /// « la traduction en libellés affichables appartient au client ».
  final String libelle;

  static CategoriePlat? depuisCode(String? code) {
    for (final c in CategoriePlat.values) {
      if (c.code == code) return c;
    }
    return null;
  }
}

/// Le filtre « état » de la carte — `m4-restaurant-carte.html` l.64-71.
///
/// ## Les SIX options de la vue sont ici, dont UNE que le serveur refuse
///
/// Elle est conservée parce que l'Article 1 (interdit 08) interdit de
/// supprimer un élément visible sans dérogation écrite. Elle est marquée
/// [servi] à `false`, et l'écran la rend **présente mais non sélectionnable,
/// avec sa raison** — le troisième comportement, celui qui dit la vérité :
/// la fonction manque, l'écran n'est pas cassé.
///
/// ⚠ Elles étaient DEUX jusqu'au 11/09/2026 (PA-185). « Prix provisoire » est
/// servi par le serveur depuis le 02/09/2026 — `provisoire` est sorti de
/// `CarteRestaurantService::ETATS_SANS_SCHEMA` — et ce client le refusait
/// encore pour un motif devenu faux (« aucune colonne ne porte le caractère
/// provisoire d'un prix »). La garde ci-dessous l'a vu : c'est pour cela que
/// la liste n'est pas recopiée (PA-144).
///
/// Les envoyer serait pire que de les retirer. `FiltrerCarteRequest` les
/// rejette en 422 avec un message dédié, et le serveur explique pourquoi : les
/// ignorer rendrait « la carte ENTIÈRE sous un intitulé qui promet le
/// contraire » (PA-119).
///
/// La liste des états refusés n'est PAS figée ici : elle est confrontée à la
/// constante PHP `CarteRestaurantService::ETATS_SANS_SCHEMA` par
/// `test/features/restaurant/conformite_restaurant_test.dart`. Une constante
/// recopiée ne vérifierait qu'elle-même et resterait verte le jour où la
/// colonne `disponible` entrerait au schéma.
enum EtatArticleCarte {
  /// L'option vide du maître (l.65) — aucun filtre.
  tous('', 'Tous les articles', servi: true),

  /// l.66 — **refusé** : aucune colonne ne porte la disponibilité du jour.
  retiresDuJour('indisponible', 'Retirés du jour', servi: false),

  /// l.67 — la recette porte au moins un ingrédient.
  liesAuStock('lie', 'Liés au stock', servi: true),

  /// l.68 — la recette est vide : la vente ne décrémente rien.
  sansLienDeStock('sans_lien', 'Sans lien de stock', servi: true),

  /// l.69 — zéro portion servable au point cuisine.
  enRuptureDeStock('rupture_stock', 'En rupture de stock', servi: true),

  /// Servi : `CarteRestaurantService::ETATS` le porte depuis le 02/09/2026
  /// (colonne `plats.prix_provisoire`). Refusé ici jusqu'au 11/09/2026 pour
  /// un motif devenu faux (PA-185).
  prixProvisoire('provisoire', 'Prix provisoire', servi: true);

  const EtatArticleCarte(this.code, this.libelle, {required this.servi});

  /// La valeur envoyée au serveur. Vide pour [tous] : le maître pose
  /// `value=""`, et un filtre vide ne part pas.
  final String code;

  /// Le libellé du maître, au caractère près.
  final String libelle;

  /// Faux quand le serveur refuse ce filtre faute de colonne au schéma.
  final bool servi;

  /// Ce qu'on envoie — `null` quand rien ne doit partir.
  String? get parametre => code.isEmpty ? null : code;
}

/// Pourquoi une ligne n'a **aucun** chiffre de portions.
///
/// Registre fermé, aligné sur `LignePlatCarte::MOTIF_*`. Un tiret qui ne dit
/// pas pourquoi renvoie chercher un bug là où il n'y en a pas.
enum MotifSansStock {
  /// `recette_sans_ingredient` — la fiche technique est vide. Le plat se vend
  /// sans rien décrémenter, et sa transmission en cuisine sera **refusée**
  /// (`RecetteManquanteException`). L'écran le montre avant le comptoir.
  recetteSansIngredient(
    'recette_sans_ingredient',
    'Fiche technique vide : la vente ne décrémente rien, et la transmission '
        'en cuisine sera refusée.',
  ),

  /// `point_cuisine_absent` — aucun point de stockage de type `cuisine`
  /// n'existe. On ne sait pas d'où sortiraient les denrées.
  pointCuisineAbsent(
    'point_cuisine_absent',
    'Aucun point de stockage « cuisine » n’existe : on ignore d’où sortiraient '
        'les denrées, donc combien il en reste.',
  ),

  /// `composition_sans_suivi` — **propre à ce poste** (09/10/2026), absent du
  /// registre du serveur.
  ///
  /// Tous les ingrédients de la fiche sont des articles en achat JOURNALIER :
  /// leur stock n'est pas tenu, aucun solde n'existe, donc aucune portion ne se
  /// compte. Le serveur (`CarteRestaurantService::portions`) ne distingue pas
  /// ce cas : il lit un solde de `0.00` pour l'article sans mouvement et rend
  /// `0` portion, `rupture` et `sous seuil` — c'est-à-dire qu'une salade
  /// (laitue, tomate, oignon, tous journaliers) apparaît « en rupture » en
  /// permanence. Rejoué par PHP le 09/10/2026 (`tool/restaurant/`). Un zéro
  /// plausible n'est pas une mesure : ce poste dit « non suivi » avec cette
  /// raison, que la vue nomme elle-même sur l'onglet des fiches (« composée »
  /// mais « sans suivi »). Écart à remonter au PO / à l'Architecte.
  compositionSansSuivi(
    'composition_sans_suivi',
    'Aucun ingrédient de la fiche n’est suivi en stock (tous sont en achat '
        'journalier) : le stock n’en est pas tenu, donc le nombre de portions '
        'restantes ne se calcule pas. Ce n’est pas une rupture.',
  ),

  /// Le serveur a nommé un motif que ce client ne connaît pas.
  ///
  /// Il existe pour que le cas ajouté demain n'obtienne pas un comportement
  /// **par omission** : sans lui, un code inconnu se lirait comme « aucun
  /// motif », c'est-à-dire comme un stock normalement compté.
  inconnu(
    '',
    'Le serveur a nommé un motif que cette version du client ne connaît pas.',
  );

  const MotifSansStock(this.code, this.explication);

  final String code;
  final String explication;

  static MotifSansStock? depuisCode(String? code) {
    if (code == null || code.isEmpty) return null;
    for (final m in MotifSansStock.values) {
      if (m.code == code && m != MotifSansStock.inconnu) return m;
    }
    return MotifSansStock.inconnu;
  }
}

/// L'ingrédient qui **borne** le nombre de portions.
///
/// Le maillon faible commande : dix kilos de riz ne servent à rien s'il ne
/// reste pas de poulet. « 4 portions » sans dire ce qui manque n'indique pas
/// quoi racheter.
final class IngredientLimitant {
  const IngredientLimitant({
    required this.id,
    required this.libelle,
    required this.uniteMesure,
  });

  final String id;
  final String libelle;
  final String? uniteMesure;
}

/// Un plat de la carte, avec sa couverture de stock.
final class LigneCarteRestaurant {
  const LigneCarteRestaurant({
    required this.id,
    required this.libelle,
    required this.categorieBrute,
    required this.prixVente,
    required this.lieAuStock,
    required this.nbIngredients,
    this.menuId,
    this.recetteId,
    this.motifSansStock,
    this.portionsVendables,
    this.ingredientLimitant,
    this.rupture = false,
    this.sousSeuil = false,
    this.coutMatiere,
    this.coutMatiereIncomplet = false,
    this.articlesSansCout = const [],
    this.marge,
    this.prixProvisoire = false,
    this.prixCorrigeMain = false,
    this.recetteLibelle,
    this.indisponibilite,
  });

  final String id;
  final String libelle;

  /// Le retrait de la carte du jour EN COURS (table `indisponibilites_carte_local`,
  /// v31), ou `null` : le plat est à la carte.
  final IndisponibiliteDistante? indisponibilite;

  bool get estRetire => indisponibilite != null;

  /// Le libellé de la fiche technique du plat — ce que la colonne « Article de
  /// stock » de la vue nomme, en vert, au-dessus du nombre d'ingrédients.
  /// `null` = non lu.
  final String? recetteLibelle;

  /// Le code brut du serveur. Conservé **en plus** de [categorie] : un type
  /// inconnu doit rester affichable tel quel plutôt que disparaître.
  final String categorieBrute;

  final String? menuId;
  final String? recetteId;

  /// `DECIMAL(15,2)` sérialisé — une **chaîne**, jamais un `double`. Réarrondi,
  /// le prix affiché divergerait de celui que le serveur facture.
  final String prixVente;

  /// La recette porte au moins un ingrédient.
  final bool lieAuStock;

  final int nbIngredients;

  /// Non nul **exactement quand** [portionsVendables] est nul.
  final MotifSansStock? motifSansStock;

  /// `null` = personne n'a compté. `0` = il n'en reste plus.
  final int? portionsVendables;

  final IngredientLimitant? ingredientLimitant;

  /// Zéro portion, et le chiffre existe. Jamais vrai quand le chiffre manque.
  final bool rupture;

  /// Au moins un ingrédient sous son seuil d'alerte.
  final bool sousSeuil;

  /// `null` quand au moins un ingrédient n'a jamais été réceptionné : son coût
  /// moyen pondéré vaut zéro, ce qui n'est pas un prix.
  final String? coutMatiere;

  final bool coutMatiereIncomplet;

  /// Les articles dont le coût est inconnu, **nommés** : sans eux, la
  /// correction est impossible.
  final List<String> articlesSansCout;

  /// `null` avec [coutMatiere]. Prix de vente moins coût inconnu n'est pas une
  /// marge, c'est le prix de vente.
  final String? marge;

  /// PA-161 (b) — le tarif a été POSÉ faute de relevé : une décision, cochée à
  /// la saisie du plat. Rendu SOUS le prix, comme la vue.
  final bool prixProvisoire;

  /// PA-161 (b) — le tarif imprimé a été corrigé à la main : un FAIT, déduit à
  /// l'enregistrement quand le prix d'un plat provisoire change (jamais coché).
  final bool prixCorrigeMain;

  CategoriePlat? get categorie => CategoriePlat.depuisCode(categorieBrute);

  /// Le libellé affichable de la catégorie — le code brut si le registre ne le
  /// connaît pas, jamais une traduction inventée.
  String get categorieLibelle => categorie?.libelle ?? categorieBrute;
}

/// La bande de six cartes du maître (`carte-module.js` l.379-397).
///
/// ## Trois des six chiffres du maître N'EXISTENT PAS, et sont NOMMÉS
///
/// [absents] porte la raison que le serveur donne, clé par clé
/// (`indicateurs_absents` de `CarteRestaurantResource`). Elle vient de
/// `lang/fr/restaurant.php`, pas d'une phrase réécrite ici : deux textes
/// décrivant le même refus finiraient par diverger.
///
/// Les cartes correspondantes affichent « — » **et la raison**, jamais `0`.
final class IndicateursCarte {
  const IndicateursCarte({
    required this.plats,
    required this.lies,
    required this.sansLien,
    required this.enRupture,
    required this.sousSeuil,
    required this.coutMatiereInconnu,
    this.tauxCouverture,
    this.absents = const {},
    this.prixProvisoires,
    this.disponibles,
    this.indisponibles,
  });

  final int plats;
  final int lies;
  final int sansLien;

  /// `null` sur une carte vide : `0 %` s'y lirait comme « aucun plat n'est
  /// rattaché », donc comme un défaut à corriger, alors qu'il n'y a rien à
  /// rattacher.
  final String? tauxCouverture;

  final int enRupture;
  final int sousSeuil;

  /// Le nombre de plats dont on ignore le coût matière.
  ///
  /// **Servi par l'API, sans emplacement au maître** : les six cartes de
  /// `carte-module.js` n'en comptent aucune. Il n'est donc pas rendu — ajouter
  /// un indicateur non maquetté est l'interdit 07 de l'Article 1. Le champ est
  /// conservé pour que la question reste visible dans le code, et il est
  /// remonté au rapport.
  final int coutMatiereInconnu;

  /// Le nombre de plats dont le tarif est marqué provisoire. `null` = personne
  /// n'a compté (un client qui ne détient pas la colonne) : l'écran rend alors
  /// « — » avec la raison de [absents], jamais « 0 » (qui se lirait « tous les
  /// prix ont été confrontés à la carte »). Sur ce poste la colonne existe et le
  /// compte est toujours fait : un zéro y est une mesure.
  final int? prixProvisoires;

  /// Les plats à la carte / retirés du jour (21/10/2026, v31). `null` = non
  /// compté (le serveur, lui, ne les sert pas) : l'écran rend alors « — » et la
  /// raison de [absents].
  final int? disponibles;
  final int? indisponibles;

  /// Les indicateurs du maître qu'aucune colonne ne permet de produire, avec
  /// la raison donnée. Clés : `disponibles`, `indisponibles` et, pour un client
  /// qui ne compte pas les prix provisoires, `prix_provisoires`.
  final Map<String, String> absents;

  /// La raison d'absence d'un indicateur, ou `null` s'il est servi.
  String? raisonAbsence(String cle) => absents[cle];
}

/// Une ligne de l'onglet « Couverture du stock ».
final class CouvertureCategorie {
  const CouvertureCategorie({
    required this.categorieBrute,
    required this.plats,
    required this.lies,
    required this.sansLien,
    this.taux,
  });

  final String categorieBrute;
  final int plats;
  final int lies;
  final int sansLien;

  /// `null` sur une catégorie vide — même arbitrage que
  /// [IndicateursCarte.tauxCouverture].
  final String? taux;

  CategoriePlat? get categorie => CategoriePlat.depuisCode(categorieBrute);
  String get categorieLibelle => categorie?.libelle ?? categorieBrute;

  /// Le taux en nombre, pour la barre de progression. `null` quand il manque :
  /// une barre à zéro affirmerait une couverture nulle qui n'a pas été mesurée.
  double? get tauxNumerique => taux == null ? null : double.tryParse(taux!);
}

/// L'écran entier, d'un seul parcours du serveur.
///
/// ## Les indicateurs portent sur la carte ENTIÈRE, les lignes sur le filtre
///
/// Ce n'est pas une incohérence, c'est ce que fait le maître : `carte-module.js`
/// appelle `C.kpis(MODULE)` sans filtre pour la bande et pour l'onglet
/// Couverture, et `C.articles(filtres())` pour le tableau. Filtrer les
/// compteurs ferait tomber « Ne décrémentent rien » à zéro dès qu'on filtre sur
/// « Liés au stock » — c'est-à-dire précisément quand on cherche à mesurer le
/// trou.
final class CarteRestaurant {
  const CarteRestaurant({
    required this.lignes,
    required this.indicateurs,
    required this.couverture,
    required this.filtresAppliques,
    required this.arreteAu,
    this.pointCuisineId,
  });

  final List<LigneCarteRestaurant> lignes;
  final IndicateursCarte indicateurs;
  final List<CouvertureCategorie> couverture;

  /// Ce que le serveur a réellement appliqué. Un export DIT son filtre
  /// (PA-119) : sans cela, un état partiel passe pour un état complet.
  final Map<String, String> filtresAppliques;

  /// `null` = aucun point de stockage de type `cuisine` n'existe. Aucune
  /// portion n'est alors calculable, et l'écran doit le DIRE plutôt que
  /// d'afficher une carte sans stock qui passerait pour une carte en rupture.
  final String? pointCuisineId;

  /// L'horodatage du serveur, tel quel.
  final String arreteAu;

  bool get sansPointCuisine => pointCuisineId == null;
}
