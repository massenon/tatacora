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
}
