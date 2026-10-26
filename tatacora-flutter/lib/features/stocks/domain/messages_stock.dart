/// Les phrases de refus de M6 qui sont CELLES DU SERVEUR, mot pour mot.
///
/// `lang/fr/stocks.php` (clés `validation.*` et `cout_negatif`) et
/// `lang/fr/stocks_pwa.php` (`mouvement.refus_journalier`) disent déjà
/// pourquoi chaque saisie est refusée. Les réécrire ici ferait deux phrases
/// pour un même refus, et la seconde vieillirait. Un test les relit sur les
/// fichiers PHP (en exécutant PHP) et échoue au moindre écart : une phrase
/// recopiée à la main ne vérifierait qu'elle-même.
///
/// Les apostrophes sont DROITES, comme dans les fichiers de langue : c'est
/// aussi la sûre pour un PDF, dont les polices intégrées ne couvrent pas
/// U+2019.
///
/// Les phrases propres à CE poste (droit manquant, unité verrouillée, point
/// homonyme…) vivent à côté de leur règle, dans le DAO et l'API : le serveur
/// ne les connaît pas, et rien ne les confronte.
library;

abstract final class MessagesStock {
  // `lang/fr/stocks.php` -> `validation.*`
  static const typeInconnu =
      "Type de mouvement inconnu. Un écart d'inventaire ne se saisit pas ici : "
      "il naît de la clôture d'un comptage, qui seule le rend opposable.";
  static const quantitePositive =
      'La quantité doit être strictement positive : '
      "une saisie à zéro n'est pas un mouvement.";
  static const motifObligatoire =
      'Le motif est obligatoire : un mouvement sans raison identifiée '
      "rend l'historique de stock inopposable lors d'un inventaire.";
  static const articleInexistant = 'Article inconnu du référentiel.';
  static const pointInexistant =
      'Point de stockage inconnu : le mouvement ne peut pas être imputé.';
  static const coutReserveEntree =
      'Un coût unitaire ne se renseigne que sur une entrée : '
      'une sortie est valorisée au coût moyen pondéré du moment et ne le '
      'modifie pas.';
  static const ruptureSurSortie =
      'La validation de rupture ne concerne que les sorties et les pertes : '
      'une entrée de stock ne peut pas être en rupture.';
  static const identifiantDejaPris =
      'Cet identifiant est déjà utilisé par un autre article.';
  static const libelleObligatoire = "Le libellé de l'article est obligatoire.";
  static const uniteObligatoire =
      "L'unité de mesure est obligatoire : "
      'sans elle, une quantité ne veut rien dire.';
  static const seuilObligatoire =
      "Le seuil d'alerte est obligatoire : "
      'sans lui, aucune rupture ne sera signalée.';
  static const periodeInversee =
      'La date de fin ne peut pas précéder la date de début.';

  // `lang/fr/stocks.php` -> `cout_negatif`
  static const coutNegatif =
      "Un coût d'achat ne peut pas être négatif : il ferait baisser le coût "
      'moyen pondéré et sous-évaluerait le stock au bilan.';

  /// `lang/fr/stocks_pwa.php` -> `article.stock_ouverture_motif` : le motif du
  /// mouvement d'entrée que le stock d'ouverture produit. Il apparaît tel quel
  /// en fiche de stock, et c'est ce qui rend l'ouverture rapprochable.
  static const motifOuverture = "Stock d'ouverture";

  /// `lang/fr/stocks_pwa.php` -> `mouvement.refus_journalier`, `:article`
  /// remplacé.
  static String refusJournalier(String article) =>
      "« $article » est en suivi journalier : son stock n'est pas suivi.";

  /// `lang/fr/stocks_pwa.php` -> `article.entree_motif` : le motif du mouvement
  /// d'entrée posé depuis la fiche article (administrateur seulement). Il
  /// apparaît tel quel en fiche de stock.
  static const entreeMotif = 'Entrée depuis la fiche article';

  /// `article.entree_point_requis` (apostrophes typographiques, comme la vue).
  static const entreePointRequis =
      'Choisissez le point de stockage qui reçoit la marchandise : une '
      'quantité sans destination n’est pas une livraison.';

  /// `article.entree_refus_role` (apostrophes typographiques, comme la vue).
  static const entreeRefusRole =
      'Faire entrer du stock depuis la fiche article est réservé à '
      'l’administrateur : l’entrée valorise la marchandise et déplace le coût '
      'moyen pondéré, qui alimente le bilan. Le bouton « Mouvement » de la '
      'ligne reste ouvert.';

  /// `article.entree_enregistree`, `:quantite :unite :libelle` remplacés.
  static String entreeEnregistree({
    required String quantite,
    required String unite,
    required String libelle,
  }) => 'Entrée enregistrée : $quantite $unite sur « $libelle ».';

  /* ================================================================ */
  /* L'ARCHIVAGE d'un article — `lang/fr/stocks_pwa.php`, `archivage.*`  */
  /* ================================================================ */

  /// `archivage.verrou_stock` : du stock reste (tous points confondus).
  /// [quantite] est le solde à deux décimales (« 12.50 »), comme le serveur.
  static String verrouStock(String quantite) =>
      "Il reste $quantite en stock : archiver l'article rendrait ces unités "
      'invisibles à l\'inventaire.';

  /// `archivage.verrou_commande` : [nombre] lignes de commande d'achat en cours.
  static String verrouCommande(int nombre) =>
      "Il figure sur $nombre commande(s) d'achat en cours : la réception à "
      'venir a besoin de cet article au sélecteur.';

  /// `archivage.verrou_carte` : [nombre] entrées de carte (bar + restaurant).
  static String verrouCarte(int nombre) =>
      'Il est vendu à la carte ($nombre entrée(s)) : le comptoir continuerait '
      'de le vendre et de décrémenter son stock. Retirez-le d\'abord de la '
      'carte.';

  /// `archivage.verrou_recette` : [nombre] compositions de recette.
  static String verrouRecette(int nombre) =>
      'Il entre dans $nombre recette(s) : la déduction de stock cuisine le '
      'cherche par cette composition.';

  /// `archivage.succes` (`trans_choice`) : un article, ou [nombre].
  static String archivesSucces(int nombre) => nombre == 1
      ? 'Article archivé — il reste restaurable.'
      : '$nombre articles archivés — ils restent restaurables.';

  /// `archivage.restaure`, `:libelle` remplacé.
  static String restaure(String libelle) => 'Article « $libelle » restauré.';

  /* ================================================================ */
  /* L'INVENTAIRE physique — `lang/fr/stocks.php` et `stocks_pwa.php`    */
  /* ================================================================ */

  /// `stocks.quantite_negative` : un comptage négatif n'existe pas.
  static const quantiteNegative = 'Une quantité ne peut pas être négative.';

  /// `stocks.inventaire_incomplet`, `:nombre` remplacé.
  static String inventaireIncomplet(int nombre) =>
      "$nombre article(s) n'ont pas été comptés. Clôturer maintenant régulariserait une partie du stock en laissant le reste inchangé, sans que rien ne le signale.";

  /// `stocks.motif_regularisation` : le motif de chaque mouvement de
  /// régularisation. [inventaire] est l'identifiant de l'inventaire, [ecart]
  /// l'écart SIGNÉ à deux décimales (« 2.00 », « -1.00 »), comme le serveur.
  static String motifRegularisation({
    required String inventaire,
    required String ecart,
  }) => 'Régularisation inventaire $inventaire — écart de $ecart';

  /// `inventaires.lance`, `:nombre` remplacé.
  static String inventaireOuvert(int nombre) =>
      'Inventaire ouvert — $nombre article(s) à compter.';

  /// `inventaires.comptage_enregistre`, `:article` remplacé.
  static String comptageEnregistre(String article) =>
      'Comptage de « $article » enregistré.';

  /// `inventaires.cloture`, `:nombre` et `:impact` remplacés.
  static String inventaireCloture({
    required int nombre,
    required String impact,
  }) => 'Inventaire clôturé — $nombre régularisation(s), impact $impact.';

  /// `inventaires.aucun_point_defini`.
  static const aucunPointDefini =
      "Aucun point de stockage n'est défini : un inventaire porte sur un point, il ne peut pas être ouvert sans lui.";
}
