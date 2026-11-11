/// Les mouvements de stock et les deux saisies de M6 — EF-M6-01, EF-M6-02,
/// EF-M6-06.
///
/// ## Rien n'est converti, ici non plus
///
/// Quantités et coûts restent des **chaînes** de bout en bout : de la frappe au
/// corps de la requête, puis de la réponse à l'écran. Un `double` intermédiaire
/// réarrondirait, et le journal afficherait un autre chiffre que celui que le
/// serveur a écrit dans `mouvements_stock` — c'est ce même chiffre qui sert
/// ensuite à justifier un écart d'inventaire.
///
/// ## Deux registres, pas un
///
/// On **consulte** quatre types de mouvement, on n'en **saisit** que trois :
/// `inventaire` naît d'une clôture de comptage (`InventaireService`), jamais
/// d'un formulaire. Les confondre en un seul registre ouvrirait la saisie libre
/// d'un écart d'inventaire — c'est-à-dire permettrait de réécrire n'importe
/// quel solde sans qu'aucun comptage n'ait eu lieu, et rendrait l'inventaire
/// inopposable.
///
/// ## Porteur de la vue (21/10/2026)
///
/// Les trois libellés longs du sélecteur de type de la modale « Mouvement de
/// stock » vivent ICI, une seule fois ([TypeMouvement.libelleSaisie]) ; la
/// modale les rend sans les recopier. Pour que la mesure de conformité les
/// retrouve dans le code qui PORTE la modale, ce fichier cite la vue :
/// pwa/stocks/stocks.blade.php (`etatFormulaire === 'mouvement'`).
library;

import 'etat_stock.dart' show SuiviArticle;

/// Le registre **fermé** des types de mouvement, celui du schéma serveur
/// (`enum('entree','sortie','perte','inventaire')`).
///
/// [saisissable] est une **donnée portée par chaque cas**, pas un prédicat
/// dérivé d'un autre champ : un test qui comparerait `saisissable` à une
/// propriété calculée depuis lui-même ne pourrait jamais échouer (piège 12).
/// Il est confronté au registre du serveur — `EnregistrerMouvementRequest::
/// TYPES_SAISISSABLES`, relu dans son code source par
/// `test/features/stocks/saisie_stocks_test.dart`.
enum TypeMouvement {
  /// Libellés de saisie repris **au mot** du maître, `m6-stocks.html` l.392.
  entree('entree', 'Entrée', 'Entrée (réception, retour)', true),

  /// `m6-stocks.html` l.393.
  sortie('sortie', 'Sortie', 'Sortie (consommation, vente)', true),

  /// `m6-stocks.html` l.394.
  perte('perte', 'Perte', 'Perte (casse, péremption, vol)', true),

  /// Consultable, **jamais saisissable**. Le libellé court est celui du maître
  /// (`m6-inventaires.html` l.136, `LIBELLE_TYPE`).
  inventaire('inventaire', 'Régularisation', null, false);

  const TypeMouvement(
    this.code,
    this.libelle,
    this.libelleSaisie,
    this.saisissable,
  );

  /// Le code tel que le serveur l'attend et le renvoie. Il part et revient tel
  /// quel : une seconde table de correspondance finirait par envoyer un code
  /// refusé en 422, sur un écran qui semblait fonctionner.
  final String code;

  /// Le libellé court, pour le journal.
  final String libelle;

  /// Le libellé long du sélecteur de saisie, `null` quand le type ne se
  /// saisit pas.
  final String? libelleSaisie;

  /// Vrai pour les trois types qu'un formulaire peut saisir.
  final bool saisissable;

  /// Vrai quand le mouvement AJOUTE au stock (`entree` et `inventaire`), faux
  /// quand il en retranche. C'est la convention de signe du serveur
  /// (`StockTheoriqueService::TYPES_ENTRANTS`), écrite ici UNE fois : la
  /// recopier dans un second endroit ferait afficher deux stocks différents
  /// pour le même article le jour où elle change.
  bool get ajouteAuStock =>
      this == TypeMouvement.entree || this == TypeMouvement.inventaire;

  /// Les trois types offerts au formulaire, dans l'ordre du maître.
  static List<TypeMouvement> get saisissables =>
      values.where((t) => t.saisissable).toList(growable: false);

  /// `null` sur un code inconnu — **jamais un repli sur un cas plausible**.
  ///
  /// Un type ajouté au schéma demain ne doit pas hériter du comportement de
  /// `entree` par omission : le journal affiche alors le code brut, ce qui se
  /// voit, plutôt qu'un libellé faux, qui ne se voit pas. Même règle que les
  /// types de champ inconnus de l'écran Paramètres (PA-125).
  static TypeMouvement? depuisCode(String code) {
    for (final t in values) {
      if (t.code == code) return t;
    }
    return null;
  }
}

/// Une ligne du journal, telle que `MouvementStockResource` la rend.
final class MouvementStock {
  const MouvementStock({
    required this.id,
    required this.articleId,
    required this.articleLibelle,
    required this.uniteMesure,
    required this.pointId,
    required this.pointLibelle,
    required this.typeCode,
    required this.quantite,
    required this.sens,
    required this.motif,
    required this.utilisateur,
    required this.dateMouvement,
    this.ruptureForcee = false,
    this.coutUnitaire,
  });

  final String id;
  final String articleId;

  /// Chargé par le serveur (`with(['article:id,libelle,unite_mesure'])`).
  /// Vide si la relation n'a pas été jointe — on affiche alors l'identifiant
  /// plutôt qu'un libellé inventé.
  final String articleLibelle;
  final String uniteMesure;

  final String pointId;
  final String pointLibelle;

  /// Le code brut du serveur, **conservé même s'il est inconnu** : c'est lui
  /// qu'on affiche quand [type] rend `null`.
  final String typeCode;

  /// Toujours positive au schéma — c'est [sens] qui dit si elle ajoute ou
  /// retranche. Chaîne, jamais un nombre.
  final String quantite;

  /// `'entree'` ou `'sortie'`, **dérivé par le serveur** depuis
  /// `StockTheoriqueService::TYPES_ENTRANTS`. Il n'est pas recalculé ici : une
  /// convention de signe écrite à deux endroits finit par diverger, et le
  /// journal montrerait alors l'inverse de ce que le stock vaut.
  final String sens;

  /// Le « pourquoi » — obligatoire au schéma (EF-M6-06).
  final String motif;

  /// Le « qui ». `null` quand le serveur n'a pas joint la relation ou que le
  /// mouvement n'a pas d'auteur (import, tâche planifiée) : on affiche alors
  /// un tiret, jamais un nom de remplacement.
  final String? utilisateur;

  /// L'horodatage ISO 8601, **conservé tel quel**.
  final String dateMouvement;

  /// RG-06 : la sortie a été forcée alors que le disponible ne la couvrait pas.
  /// C'est la trace de la décision — avec [utilisateur] et [dateMouvement].
  final bool ruptureForcee;

  /// Le coût d'achat unitaire de cette entrée (« 1250.0000 »), `null` si elle
  /// n'en porte pas (sortie, perte, transfert entre points).
  final String? coutUnitaire;

  TypeMouvement? get type => TypeMouvement.depuisCode(typeCode);

  /// Le libellé à afficher : celui du registre, ou le **code brut** si le
  /// serveur a renvoyé un type que ce client ne connaît pas.
  String get libelleType => type?.libelle ?? typeCode;

  /// Le libellé du journal : celui du type, plus la mention de la décision
  /// quand la sortie a été forcée. La mention est ce qui rend vraie la phrase
  /// de la confirmation (« tracé comme rupture forcée »).
  String get libelleJournal =>
      ruptureForcee ? '$libelleType — rupture forcée' : libelleType;

  bool get estEntrante => sens == 'entree';

  /// L'horodatage réduit à « AAAA-MM-JJ HH:MM » pour l'affichage.
  ///
  /// Une **troncature de présentation**, pas une conversion : la valeur portée
  /// par [dateMouvement] n'est pas touchée, et rien n'est reformaté selon un
  /// fuseau. Un `DateTime.parse` suivi d'un rendu local décalerait l'heure
  /// affichée de celle que porte le journal du serveur, sur un document qui
  /// sert à situer un mouvement dans une journée de comptoir.
  String get dateCourte {
    final brut = dateMouvement.replaceFirst('T', ' ');
    return brut.length >= 16 ? brut.substring(0, 16) : brut;
  }
}

/// Ce que le formulaire « Nouvel article » / « Modifier l'article » soumet —
/// `m6-stocks.html` l.296-374.
///
/// ## Aucun champ calculé n'y figure, et il ne faut jamais en ajouter
///
/// `EnregistrerArticleRequest::CHAMPS_CALCULES` refuse `stock`,
/// `stock_initial`, `stock_disponible`, `quantite_stock`, `cout_moyen_pondere`
/// et `valeur_stock` — **refuse**, pas « ignore » (PA-24). La différence
/// compte : un champ ignoré laisse le magasinier croire qu'il a compté, et
/// l'écart ne se voit qu'à l'inventaire suivant.
///
/// Le maître propose pourtant deux d'entre eux — « Stock d'ouverture » (l.331)
/// et « Valeur d'achat unitaire » (l.307). Ils ne sont **pas rendus**, et la
/// modale dit pourquoi à l'écran plutôt que de les taire.
final class SaisieArticle {
  const SaisieArticle({
    required this.id,
    required this.libelle,
    required this.categorie,
    required this.uniteMesure,
    required this.seuilAlerte,
    this.suivi = SuiviArticle.permanent,
    this.pointStockageId,
    this.stockOuverture = '',
    this.valeurAchat = '',
  });

  /// L'UUID est **fourni par le client**, y compris ici où rien ne se rejoue.
  ///
  /// Il ne rend pas la création idempotente — `EnregistrerArticleRequest` pose
  /// `unique`, donc un second envoi rend 422 et non 200. C'est précisément ce
  /// qu'on veut : sans identifiant, un `POST` dont la réponse se perd sur une
  /// liaison qui tombe — le cas normal au Gîte — créerait un **doublon** au
  /// référentiel au moment où l'on réessaie. Avec lui, le second envoi est
  /// refusé et le dit.
  final String id;

  final String libelle;

  /// `null` au schéma serveur : une catégorie non renseignée n'est pas la
  /// chaîne vide.
  final String? categorie;

  final String uniteMesure;

  /// Un **paramètre**, pas un état : il commande l'alerte RG-07, il ne décrit
  /// pas le stock. C'est la seule valeur numérique de ce formulaire, et la
  /// seule que le serveur accepte.
  final String seuilAlerte;

  /// Le mode de suivi (registre fermé). En `journalier` le seuil ne se saisit
  /// pas : il n'y a pas de stock à lui comparer, et il retombe à zéro (maître
  /// l.358).
  final SuiviArticle suivi;

  /// Le point de RATTACHEMENT — jamais la portée du stock. `null` : aucun, et
  /// lui en poser un par défaut affirmerait un lieu que personne n'a décidé.
  final String? pointStockageId;

  /// Le stock d'OUVERTURE, à la création seulement — vide : aucun.
  ///
  /// Ce n'est pas un champ « stock » : il est enregistré comme un MOUVEMENT
  /// d'entrée, daté, motivé et imputable, dans la même transaction que
  /// l'article (maître l.331-333). Il n'est JAMAIS écrit en colonne, et il
  /// n'existe pas en modification — le stock se corrige par un mouvement.
  /// Ignoré pour un article journalier, dont le stock n'est pas tenu.
  final String stockOuverture;

  /// Le coût d'achat unitaire de l'entrée d'ouverture, FCFA. Vide : l'entrée ne
  /// valorise rien (un zéro se lirait « reçu gratuitement »). Il traverse le
  /// coût moyen pondéré, il ne l'écrit pas.
  final String valeurAchat;

  /// Le corps de `POST /stocks/articles`.
  ///
  /// `id` est omis en modification : `EnregistrerArticleRequest` le pose
  /// `prohibited` sur cette route — l'identifiant d'un article ne se modifie
  /// pas.
  Map<String, dynamic> versJson({required bool modification}) => {
    if (!modification) 'id': id,
    'libelle': libelle,
    'categorie': categorie,
    'unite_mesure': uniteMesure,
    'seuil_alerte': seuilAlerte,
    'suivi': suivi.code,
    'point_stockage_id': pointStockageId,
  };
}

/// Ce que la modale « Mouvement de stock » soumet — `m6-stocks.html`
/// l.376-446.
final class SaisieMouvement {
  const SaisieMouvement({
    required this.articleId,
    required this.pointId,
    required this.type,
    required this.quantite,
    required this.motif,
    this.coutUnitaire,
    this.validationRupture = false,
  });

  final String articleId;

  /// Une vraie clé étrangère, jamais le libellé du point. Le maître envoie
  /// `point_stockage: 'Bar'` (l.414) parce que son moteur travaille en
  /// `localStorage` ; ici un libellé serait rejeté par `exists:points_stockage,id`.
  final String pointId;

  final TypeMouvement type;

  /// Chaîne, telle que frappée. `gt:0` côté serveur : une quantité à zéro
  /// n'est pas un mouvement, c'est une saisie inachevée.
  final String quantite;

  final String motif;

  /// Réservé aux **entrées** (`prohibited_unless:type_mouvement,entree`) : une
  /// sortie est valorisée au coût moyen pondéré du moment et ne le modifie
  /// pas. `null` sur un simple transfert entre points, qui ne revalorise rien.
  final String? coutUnitaire;

  /// RG-06 — le forçage de rupture est une décision explicite, jamais un
  /// défaut. Il n'est envoyé que **vrai** : le serveur refuse `true` sur une
  /// entrée, et envoyer `false` systématiquement transformerait un non-geste
  /// en champ soumis.
  final bool validationRupture;

  SaisieMouvement forcee() => SaisieMouvement(
    articleId: articleId,
    pointId: pointId,
    type: type,
    quantite: quantite,
    motif: motif,
    coutUnitaire: coutUnitaire,
    validationRupture: true,
  );

  /// Le corps de `POST /stocks/mouvements`.
  ///
  /// Aucun `id` : `EnregistrerMouvementRequest` le pose `prohibited`, et le
  /// motif est écrit dans son en-tête — aucun mécanisme de rejeu n'existe pour
  /// `mouvements_stock`, et en accepter un laisserait croire à une idempotence
  /// qui n'a pas lieu.
  Map<String, dynamic> versJson() => {
    'article_id': articleId,
    'point_id': pointId,
    'type_mouvement': type.code,
    'quantite': quantite,
    'motif': motif,
    if (coutUnitaire != null && coutUnitaire!.isNotEmpty)
      'cout_unitaire': coutUnitaire,
    if (validationRupture) 'validation_rupture': true,
  };
}
