// Vue Blade maîtresse (PA-183) : pwa/restaurant/restauration.blade.php
// (ces phrases sont celles de ses modales : un fichier de messages qui porte les
// mots d'une modale doit citer la vue, et chaque phrase tient en UN littéral).
/// Les phrases de refus de M4 qui sont CELLES DU SERVEUR, mot pour mot.
///
/// `lang/fr/restaurant.php` (clés `validation.*`) dit déjà pourquoi chaque
/// saisie est refusée. Les réécrire ici ferait deux phrases pour un même refus,
/// et la seconde vieillirait. Un test les relit sur le fichier PHP (en
/// exécutant PHP) et échoue au moindre écart : une phrase recopiée à la main
/// ne vérifierait qu'elle-même.
///
/// Les apostrophes sont DROITES, comme dans les fichiers de langue : c'est
/// aussi la sûre pour un PDF, dont les polices intégrées ne couvrent pas
/// U+2019.
///
/// Les phrases propres à CE poste (droit manquant, prix à fraction de franc,
/// quantité à quatre décimales…) vivent ici aussi, SOUS la ligne de séparation
/// : le serveur ne les connaît pas, et rien ne les confronte. Elles disent ce
/// que ce poste fait de différent, pas ce que le serveur refuse.
library;

abstract final class MessagesRestaurant {
  // `lang/fr/restaurant.php` -> `validation.*`
  static const libelleObligatoire = 'Le libellé est obligatoire.';
  static const categorieInconnue =
      'Catégorie inconnue. Le registre est fermé : local, europeen, special. '
      "Un filtre incompris serait ignoré, et la carte entière s'afficherait "
      'sous un intitulé qui promet le contraire.';
  static const menuObligatoire =
      "Un plat appartient obligatoirement à un menu : c'est le menu qui porte "
      'sa catégorie et sa période de validité.';
  static const menuInexistant =
      'Menu inconnu. Un menu se choisit dans la liste, il ne se saisit pas en '
      'texte libre.';
  static const recetteObligatoire =
      'Un plat porte obligatoirement une fiche technique : sans elle, sa vente '
      'ne décrémenterait aucun stock.';
  static const recetteInexistante = 'Fiche technique inconnue du référentiel.';
  static const prixObligatoire = 'Le prix de vente est obligatoire.';
  static const prixNegatif = 'Le prix de vente ne peut pas être négatif.';
  static const saisonInversee =
      'La fin de validité précède son début : ce menu ne rendrait jamais aucun '
      "plat, et la carte s'afficherait vide sans dire pourquoi.";
  static const articleObligatoire =
      'Chaque ligne de composition désigne un article du référentiel.';
  static const articleInexistant =
      'Article inconnu du référentiel. Un ingrédient se choisit dans la liste, '
      'il ne se saisit pas en texte libre : la déduction de stock suppose une '
      'relation exacte.';
  static const ingredientEnDouble =
      'Cet article figure deux fois dans la composition. Les quantités sont '
      'relues article par article : la seconde ligne écraserait la première, '
      "et le plat consommerait moins que sa fiche ne l'indique.";
  static const quantiteRecetteObligatoire =
      'La quantité unitaire est obligatoire.';
  static const quantiteRecettePositive =
      'La quantité unitaire doit être strictement positive : un ingrédient à '
      "zéro n'est pas un ingrédient, c'est une ligne à retirer.";

  // ----------------------------------------------------------------------
  // Propres à ce poste — le serveur ne les connaît pas.
  // ----------------------------------------------------------------------

  /// La disponibilité du jour (un plat retiré de la carte, et son motif) n'a
  /// AUCUNE colonne sur ce poste : le geste est refusé avec sa raison (D15).
  /// « — » veut dire « on ne sait pas », jamais « tout est disponible ».
  static const disponibiliteAbsente =
      "La disponibilité du jour n'est portée par aucune table de ce poste : "
      'ni un plat retiré de la carte, ni son motif ne peuvent y être '
      "enregistrés. Aucun chiffre n'est produit d'ici là.";

  static const platIntrouvable =
      'Ce plat ne figure pas au catalogue de ce poste. Il a peut-être été '
      'enregistré sur un autre poste : les catalogues ne se synchronisent '
      'plus, chacun tient le sien.';

  /// Ce que la phrase de la vue sur les fiches vides promet (« le point de vente
  /// REFUSE la vente du plat ») n'est PAS vrai sur ce poste : le point de vente
  /// ne retire encore rien du stock, et la vente d'un plat à fiche vide n'est
  /// pas refusée. Le dire, plutôt que laisser croire à un refus qui n'a pas lieu.
  static const venteSansSortieDeStock =
      'Sur ce poste, le point de vente ne retire encore rien du stock : la vente '
      "d'un plat à fiche vide n'y est pas refusée, et celle d'un plat à fiche "
      'composée ne décrémente rien non plus.';

  static const droitLectureRefuse =
      "Vous n'avez pas le droit de consulter le restaurant.";

  static const droitEcritureRefuse =
      "Vous n'avez pas le droit de modifier le restaurant. Rien n'a été "
      'enregistré.';

  static const auteurInconnu =
      "L'auteur est inconnu : aucune session n'est ouverte, et une écriture "
      'sans « qui » ne peut pas être opposée à un inventaire.';

  static const libelleTropLong =
      'Le libellé ne peut pas dépasser 255 caractères.';

  /// Le serveur accepte `numeric` à deux décimales ; ce poste vend en francs
  /// entiers (le franc CFA n'a pas de sous-unité en circulation, et le point de
  /// vente manipule des entiers).
  static const prixIllisible =
      'Le prix de vente doit être un nombre positif ou nul, en francs entiers.';
  static const prixFractionDeFranc =
      "Le franc CFA n'a pas de sous-unité en circulation : le prix de vente se "
      'saisit en francs entiers. Un prix à fraction de franc est refusé plutôt '
      'qu\'arrondi — le client paierait un autre montant que celui de la carte.';

  static const quantiteIllisible =
      'La quantité unitaire doit être un nombre, par exemple 0,25 ou 1,5.';
  static const quantiteTropFine =
      "La quantité unitaire s'exprime avec au plus trois décimales (le "
      "millième de l'unité de l'article) : une quatrième est refusée plutôt "
      'que tronquée, car la fiche décrémenterait un autre chiffre que celui '
      'que vous avez saisi.';

  static const dateIllisible =
      'La date doit avoir la forme AAAA-MM-JJ (par exemple 2026-12-31).';

  static const compositionVideAcceptee = 'Fiche enregistrée sans ingrédient.';

  /// Une fiche ne peut pas être composée d'un article que ce poste ne connaît
  /// pas : il se choisit dans la liste. Le serveur en dit autant
  /// ([articleInexistant]) ; cette phrase-ci n'est que l'écran vide du sélecteur.
  static const aucunArticleDisponible =
      "Aucun article de stock n'existe sur ce poste : une fiche technique "
      'se compose d\'articles du référentiel du stock (jamais de texte libre). '
      "Créez d'abord les articles dans l'écran des stocks.";

  /// Ce que la carte dit du stock vendable : le calcul lit des mouvements qui
  /// ne tiennent pas compte des ventes de ce poste.
  static const stockSansLesVentes =
      'Le stock vendable est celui des mouvements enregistrés : les ventes de '
      "ce poste n'en retirent encore rien. Il peut dépasser le stock réel "
      "d'autant.";

  // ----------------------------------------------------------------------
  // Les phrases de la VUE (`carte_pwa.restauration.*`), reprises au mot.
  // Un test les relit en exécutant PHP.
  // ----------------------------------------------------------------------

  static const aucunMenu =
      "Aucun menu n'existe encore : un plat ne peut pas être créé sans lui. Créez d'abord un menu — vous reviendrez ici avec votre saisie.";
  static const aucuneFiche =
      "Aucune fiche technique n'existe encore : un plat ne peut pas être créé sans elle. Créez d'abord la fiche — vous reviendrez ici avec votre saisie.";
  static const recetteSansIngredient =
      "Sans ingrédient, cette fiche ne décrémente aucun stock : le point de vente REFUSERA la vente du plat qui l'utilise. Ajoutez au moins un article de stock, ou revenez la composer depuis l'onglet « Fiches techniques ».";
  static const recetteAucunArticle =
      "Aucun article de stock ne correspond. Élargissez la recherche, ou créez l'article depuis l'écran Stocks (M6).";

  /// `restauration.cree` / `restauration.modifie`.
  static String platEnregistre(String libelle, {required bool creation}) =>
      creation
      ? 'Le plat « $libelle » est au catalogue.'
      : 'Le plat « $libelle » est à jour.';

  /// `restauration.menu_cree` / `restauration.menu_modifie`.
  static String menuEnregistre(String libelle, {required bool creation}) =>
      creation
      ? 'Le menu « $libelle » est créé.'
      : 'Le menu « $libelle » est à jour.';

  /// Les six phrases de `restauration.recette_creee*` et `recette_modifiee*` :
  /// le coût matière est dit dans ses TROIS états, jamais « 0 F ».
  static String ficheEnregistree({
    required String libelle,
    required bool creation,
    required bool vide,
    required bool incomplet,
    required List<String> articlesSansCout,
    String? cout,
  }) {
    if (vide) {
      return creation
          ? 'La fiche « $libelle » est créée, sans ingrédient : elle ne '
                'décrémentera aucun stock tant que sa composition est vide.'
          : 'La fiche « $libelle » est enregistrée SANS ingrédient : elle ne '
                "décrémente aucun stock, et toute vente du plat qui l'utilise "
                'sera refusée au comptoir.';
    }
    if (incomplet) {
      final articles = articlesSansCout.join(', ');
      return creation
          ? 'La fiche « $libelle » est créée. Son coût matière reste INCONNU '
                ": $articles n'ont pas de coût moyen pondéré (jamais "
                'réceptionnés en M6).'
          : 'La fiche « $libelle » est à jour. Son coût matière reste '
                "INCONNU : $articles n'ont pas de coût moyen pondéré (jamais "
                'réceptionnés en M6).';
    }
    return creation
        ? 'La fiche « $libelle » est créée. Coût matière calculé : $cout.'
        : 'La fiche « $libelle » est à jour. Coût matière calculé : $cout.';
  }
}
