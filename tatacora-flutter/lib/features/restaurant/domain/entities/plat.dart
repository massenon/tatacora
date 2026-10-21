/// Les entités du **catalogue de plats** — `m4-restauration.html`.
///
/// Le maître y rend un écran CRUD générique (`crud-ui.js` + `crud-engine.js`) :
/// barre d'outils, tableau paginé, cinq modales. Ce fichier porte ce que ces
/// écrans manipulent, et **seulement des entités de domaine**.
library;

import 'carte_restaurant.dart';

/// Un plat du catalogue — `PlatResource`.
///
/// ## Ni stock, ni coût matière ici, et c'est le serveur qui le dit
///
/// « Ce sont des calculs, et ils vivent sur `GET /restaurant/carte`. Les
/// dupliquer ici en ferait deux chemins de calcul pour le même chiffre »
/// (PA-121). L'écran de catalogue n'en affiche donc aucun — et le maître n'en
/// demande aucun.
final class Plat {
  const Plat({
    required this.id,
    required this.libelle,
    required this.prixVente,
    required this.menuId,
    required this.recetteId,
    this.menuLibelle,
    this.categorieBrute,
    this.recetteLibelle,
    this.prixProvisoire = false,
    this.prixCorrigeMain = false,
  });

  final String id;

  /// Le champ « Nom du plat » du maître (l.131-135).
  final String libelle;

  /// PA-161 (b) — le tarif a été POSÉ faute de relevé. Une décision, cochée à la
  /// saisie.
  final bool prixProvisoire;

  /// PA-161 (b) — le tarif imprimé a été corrigé à la main. Un FAIT : déduit à
  /// l'enregistrement, jamais coché.
  final bool prixCorrigeMain;

  /// `DECIMAL(15,2)` sérialisé — chaîne, jamais `double`.
  final String prixVente;

  final String menuId;
  final String? menuLibelle;

  /// `menus.type`, projeté par le serveur. `null` si la relation manque.
  final String? categorieBrute;

  final String recetteId;
  final String? recetteLibelle;

  CategoriePlat? get categorie => CategoriePlat.depuisCode(categorieBrute);

  /// Le libellé affichable — le code brut si le registre ne le connaît pas.
  /// `null` seulement quand le serveur n'a rendu aucune catégorie.
  String? get categorieLibelle => categorie?.libelle ?? categorieBrute;
}

/// Un menu — `MenuResource`. C'est lui qui porte la **catégorie** et la
/// période de validité.
///
/// `plats.menu_id` est NOT NULL : sans menu, aucun plat ne peut être créé.
/// C'est le cas PA-128 appliqué à M4, et c'est pourquoi le formulaire de plat
/// refuse de s'ouvrir sur un référentiel vide plutôt que d'échouer à l'envoi.
final class MenuRestaurant {
  const MenuRestaurant({
    required this.id,
    required this.libelle,
    required this.typeBrut,
    this.dateDebut,
    this.dateFin,
    this.nbPlats,
  });

  /// Le nombre de plats rattachés, COMPTÉ des plats (jamais une colonne).
  /// `null` = non compté : « 0 » s'y lirait « menu vide ».
  final int? nbPlats;

  final String id;
  final String libelle;
  final String typeBrut;

  /// `null` sur un menu permanent, et le rester : y substituer des bornes
  /// arbitraires ferait expirer une carte que personne n'a datée.
  final String? dateDebut;
  final String? dateFin;

  CategoriePlat? get type => CategoriePlat.depuisCode(typeBrut);
  String get typeLibelle => type?.libelle ?? typeBrut;
}

/// Une fiche technique — `RecetteResource`, EF-M4-02.
///
/// ## Le coût matière a TROIS états, pas deux
///
///  - un montant : tous les ingrédients sont valorisés ;
///  - `null` + [compositionVide] : la recette n'a aucune ligne ;
///  - `null` + [coutMatiereIncomplet] : au moins un ingrédient n'a jamais été
///    réceptionné, donc son coût moyen pondéré vaut zéro — ce qui n'est pas un
///    prix. [articlesSansCout] les nomme.
///
/// Rendre `0` dans les deux derniers cas afficherait « coût matière : 0 F »,
/// donc « marge = prix de vente entier », **sur l'écran où l'on fixe un prix**.
/// C'est la forme exacte de PA-126.
final class Recette {
  const Recette({
    required this.id,
    required this.libelle,
    this.coutMatiere,
    this.coutMatiereIncomplet = false,
    this.compositionVide = false,
    this.articlesSansCout = const [],
    this.nbIngredients,
    this.platsServis = const [],
    this.decrementeUnStockSuivi,
    this.compositionProvisoire = false,
  });

  /// La marque « composition provisoire » (`recettes.composition_provisoire`) :
  /// les quantités ont été POSÉES pour débloquer le service, jamais pesées.
  ///
  /// ⚠ **Sur ce poste, la valeur ne vient d'AUCUNE colonne** : `recettes_local`
  /// n'en porte pas (le schéma v14 ne la crée pas, et la descente du catalogue
  /// ne la reçoit pas), si bien que le DAO ne la renseigne jamais et qu'elle
  /// vaut `false` partout. L'écran sait RENDRE la marque (pastille, bandeau de
  /// la modale, infobulle) ; elle ne s'allumera que le jour où la colonne
  /// existera — changement de schéma décrit au rapport de lot du 21/10/2026.
  final bool compositionProvisoire;

  /// Le nombre d'ingrédients de la composition. `null` = non compté.
  final int? nbIngredients;

  /// Les libellés des plats qui se préparent d'après cette fiche : « Recette à
  /// écrire » ne dit rien, « Recette à écrire — Salade nue » dit quelle vente
  /// est concernée. Vide = aucun plat n'utilise la fiche.
  final List<String> platsServis;

  /// Vrai quand au moins un ingrédient est en suivi PERMANENT (donc que la
  /// vente fait réellement bouger un stock). Faux sur une fiche composée de
  /// seuls articles journaliers : « composée », mais elle ne décrémente rien.
  /// `null` = non évalué.
  final bool? decrementeUnStockSuivi;

  /// Les TROIS états de la fiche, jamais deux.
  EtatFiche? get etat {
    final n = nbIngredients;
    if (n == null) return null;
    if (n == 0) return EtatFiche.vide;
    return decrementeUnStockSuivi == false
        ? EtatFiche.sansSuivi
        : EtatFiche.composee;
  }

  final String id;
  final String libelle;
  final String? coutMatiere;
  final bool coutMatiereIncomplet;
  final bool compositionVide;
  final List<String> articlesSansCout;
}

/// Les trois états d'une fiche technique (onglet des fiches de la vue).
///
/// Une fiche composée de seuls articles JOURNALIERS (laitue, tomate, oignon) est
/// bel et bien composée, et ne décrémente RIEN : la vente passe, aucun stock ne
/// bouge. La rendre « composée » sans plus se lirait comme une fiche qui
/// décrémente.
enum EtatFiche { vide, sansSuivi, composee }

/// Une ligne de composition — `RecetteDetailResource`.
final class LigneComposition {
  const LigneComposition({
    required this.articleId,
    required this.quantiteUnitaire,
    this.articleLibelle,
    this.uniteMesure,
    this.coutUnitaire,
    this.coutLigne,
  });

  final String articleId;

  /// Le libellé de l'article, ou `null` si la relation manque. **Jamais
  /// remplacé par l'identifiant** : un UUID affiché à la place d'un nom
  /// d'ingrédient ne se lit pas.
  final String? articleLibelle;

  final String? uniteMesure;
  final String quantiteUnitaire;

  /// `null` = article jamais réceptionné. Le coût moyen pondéré d'un article
  /// jamais reçu vaut zéro ; ce n'est pas un prix, c'est une absence de prix.
  final String? coutUnitaire;

  final String? coutLigne;

  bool get coutInconnu => coutUnitaire == null;
}

/// La fiche technique et sa composition ligne à ligne.
final class RecetteDetail {
  const RecetteDetail({required this.recette, required this.composition});

  final Recette recette;
  final List<LigneComposition> composition;
}

/// Ce qu'on envoie pour créer ou modifier un plat — `EnregistrerPlatRequest`.
///
/// ## Trois champs du formulaire du maître N'ENTRENT PAS ici
///
/// `EnregistrerPlatRequest::CHAMPS_REFUSES` les déclare `prohibited`, et le
/// serveur explique chacun :
///
///  - **`categorie`** — elle est celle du menu. La porter aussi sur le plat
///    créerait une seconde vérité, qui divergerait au premier reclassement.
///  - **`disponible`** — aucune colonne du schéma ne la porte. L'accepter sans
///    la stocker laisserait croire qu'elle a été enregistrée.
///  - **`ingredients_principaux`** — une chaîne de caractères ne se rattache à
///    aucun article, donc ne décrémente aucun stock (PA-23).
///
/// Ils ne sont donc **pas envoyés**. Les envoyer ferait échouer l'écriture en
/// 422 à tous les coups — un formulaire qui ne peut jamais aboutir est
/// exactement ce que l'Article 6 refuse de porter.
final class SaisiePlat {
  const SaisiePlat({
    required this.libelle,
    required this.menuId,
    required this.recetteId,
    required this.prixVente,
    this.id,
    this.prixProvisoire = false,
  });

  /// PA-161 (b) — la marque « prix provisoire », une DÉCISION qui se coche.
  /// « Corrigé à la main » n'est pas ici : c'est un fait, déduit par le DAO.
  final bool prixProvisoire;

  /// `null` à la création. Le serveur accepte un UUID fourni par le client
  /// (`'id' => ['sometimes', 'uuid', unique]`) et l'**interdit** en
  /// modification.
  final String? id;

  final String libelle;
  final String menuId;
  final String recetteId;

  /// Saisi par l'utilisateur, envoyé **tel quel**. Le serveur valide
  /// `numeric|min:0` — le maître autorise 0 (`"min": 0`), et un plat offert
  /// existe réellement.
  final String prixVente;

  /// Le corps de la requête. [modification] retire `id`, que le serveur
  /// refuse en `PUT`.
  Map<String, Object?> versJson({required bool modification}) => {
    'libelle': libelle,
    'menu_id': menuId,
    'recette_id': recetteId,
    'prix_vente': prixVente,
    'prix_provisoire': prixProvisoire,
    if (!modification && id != null) 'id': id,
  };
}

/// Ce qu'on saisit pour créer ou modifier un menu — `EnregistrerMenuRequest`.
final class SaisieMenu {
  const SaisieMenu({
    required this.libelle,
    required this.type,
    this.dateDebut = '',
    this.dateFin = '',
    this.id,
  });

  /// `null` = création.
  final String? id;
  final String libelle;

  /// Le code du registre fermé (`local`, `europeen`, `special`).
  final String type;

  /// `AAAA-MM-JJ`, ou vide : un menu permanent n'a pas de saison.
  final String dateDebut;
  final String dateFin;
}

/// Une ligne de composition en cours de saisie : un article du référentiel et
/// une quantité par portion, TELLE QUE FRAPPÉE (jamais convertie avant la
/// validation : la troisième décimale se refuse, elle ne se tronque pas).
final class LigneSaisieComposition {
  const LigneSaisieComposition({
    required this.articleId,
    required this.quantite,
  });

  final String articleId;
  final String quantite;
}

/// Ce qu'on saisit pour créer ou composer une fiche technique.
final class SaisieFiche {
  const SaisieFiche({required this.libelle, required this.lignes, this.id});

  /// `null` = création.
  final String? id;
  final String libelle;
  final List<LigneSaisieComposition> lignes;
}
