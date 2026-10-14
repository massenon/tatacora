/// L'état de stock tel que CE POSTE le calcule — M6.
///
/// ## Le stock n'est jamais stocké
///
/// Le stock, le coût moyen pondéré et la valorisation sont dérivés des
/// mouvements par `calculerEtat` (`domain/calcul_stock.dart`), en entiers.
/// Aucune colonne ne les porte : figés, ils deviendraient faux au premier
/// mouvement (même refus que le solde client, PA-126).
///
/// ⚠ Ce stock ne compte QUE les mouvements écrits sur ce poste, par l'écran
/// Stocks. Les ventes du bar et du restaurant ne décrémentent rien (aucune
/// sortie automatique n'est écrite) : l'écran le dit.
///
/// Les valeurs restent des **chaînes** jusqu'à l'affichage : « 12.50 » pour une
/// quantité, « 833.3333 » pour un coût unitaire, « 10417 » pour un montant en
/// francs entiers.
library;

/// Un article et son stock, tels que `calculerEtat` les projette.
final class LigneStock {
  const LigneStock({
    required this.id,
    required this.libelle,
    required this.categorie,
    required this.uniteMesure,
    required this.seuilAlerte,
    required this.coutMoyenPondere,
    required this.stock,
    required this.valeurStock,
    required this.portee,
    required this.suivi,
    required this.pointStockageId,
    required this.pointLibelle,
    required this.prixAchat,
    required this.deriveCmp,
  });

  final String id;
  final String libelle;

  /// `null` au schéma serveur : une catégorie absente n'est pas une chaîne
  /// vide, et l'écran ne doit pas la présenter comme une catégorie nommée.
  final String? categorie;

  final String uniteMesure;
  final String seuilAlerte;

  final String coutMoyenPondere;

  /// Calculé depuis les mouvements. **Jamais saisi** — le sous-titre du maître
  /// l'écrit en toutes lettres. Pour un article JOURNALIER, `0.00` n'est pas un
  /// stock : voir [suivi].
  final String stock;

  final String valeurStock;

  /// Sur quel périmètre le stock a été calculé : un point précis, ou tous
  /// points confondus.
  ///
  /// Dite parce qu'un chiffre de stock ne veut rien dire tant qu'on ignore s'il
  /// porte sur le bar ou sur l'établissement entier. Un écran qui l'ignorerait
  /// servirait au comptoir une bouteille qui est en réserve.
  final String portee;

  /// Le mode de suivi. Un article JOURNALIER n'a pas de stock tenu : il n'est
  /// ni en rupture ni sous seuil, et son stock s'affiche « non suivi », pas
  /// « 0 » — qui se lirait comme une rupture sur une marchandise dont personne
  /// ne tient le compte.
  final SuiviArticle suivi;

  /// Le point de RATTACHEMENT (clé étrangère) et son libellé, `null` si
  /// l'article n'en a pas. Ce n'est jamais la portée de son stock.
  final String? pointStockageId;
  final String? pointLibelle;

  /// Le DERNIER prix d'achat connu (le coût de la dernière entrée valorisée),
  /// `null` si l'article n'a jamais été réceptionné. Ce n'est pas le coût
  /// moyen pondéré.
  final String? prixAchat;

  /// La dérive du coût moyen pondéré contre [prixAchat], en pourcentage
  /// entier. `null` quand elle n'est pas mesurable — jamais zéro.
  final int? deriveCmp;

  bool get estJournalier => suivi == SuiviArticle.journalier;

  /// Aucune entrée valorisée : le coût moyen pondéré n'est pas « 0 », il est
  /// INCONNU (le 0 n'est que la valeur de départ du calcul). Il s'affiche « — ».
  bool get cmpInconnu => prixAchat == null;

  /// Du stock (positif ou négatif) mais AUCUNE entrée valorisée : le coût est
  /// inconnu, donc la valeur l'est aussi. Elle s'affiche « — », jamais « 0 » —
  /// un zéro se somme, et le total du stock passerait pour exhaustif.
  bool get valeurInconnue =>
      !estJournalier && prixAchat == null && _stockCentiemes != 0;

  // Les seuils et le stock sont des chaînes de CENTIÈMES exacts (« 12.50 ») que
  // `calculerEtat` vient d'écrire : on les compare par leurs chiffres, jamais
  // par un `double`.
  int get _stockCentiemes => _entier(stock);
  int get _seuilCentiemes => _entier(seuilAlerte);

  bool get enRupture => !estJournalier && _stockCentiemes <= 0;

  /// Sous le seuil **sans être en rupture** : les deux états appellent des
  /// gestes différents — réapprovisionner, ou cesser de vendre.
  bool get sousSeuil =>
      !estJournalier && !enRupture && _stockCentiemes <= _seuilCentiemes;

  /// Le solde est AU seuil ou dessous, QUEL QUE SOIT le mode de suivi — la
  /// règle de `Accueil::articlesCritiques()` du serveur (`EXPRESSION_SOLDE <=
  /// seuil_alerte`, sans filtre de suivi), qui alimente l'alerte « À traiter »
  /// du tableau de bord. Ce n'est PAS [sousSeuil] (écran Stocks), qui écarte
  /// les journaliers et la rupture : un journalier, de seuil zéro et de solde
  /// zéro, y est donc compté. Écart du serveur entre ses deux écrans, répliqué
  /// et noté (D298).
  bool get auSeuilOuDessous => _stockCentiemes <= _seuilCentiemes;
}

/// « -12.50 » -> -1250. Les chaînes qui arrivent ici viennent de
/// `ecrireCentiemes` : deux décimales, toujours.
int _entier(String centiemes) {
  final neg = centiemes.startsWith('-');
  final chiffres = centiemes.replaceAll('-', '').replaceAll('.', '');
  final n = int.tryParse(chiffres) ?? 0;
  return neg ? -n : n;
}

/// La bande d'indicateurs du maître (`m6-stocks.html` l.40).
///
/// ⚠ **`references` compte les lignes AFFICHÉES ; `sousSeuil` et `rupture`
/// comptent tout le référentiel de la portée.** L'écart est voulu (c'est la
/// règle du serveur, reprise telle quelle) : masquer les articles sains ne
/// change pas le nombre d'articles à réapprovisionner. Les uniformiser ferait
/// tomber l'alarme à zéro dès qu'on filtre.
final class KpisStock {
  const KpisStock({
    required this.references,
    required this.sousSeuil,
    required this.rupture,
    required this.valeurStock,
    required this.mouvements30Jours,
    required this.permanents,
    required this.journaliers,
    required this.sansValorisation,
  });

  final int references;
  final int sousSeuil;
  final int rupture;
  final String valeurStock;
  final int mouvements30Jours;

  /// La répartition du référentiel entre suivi permanent et achat journalier
  /// (maître l.170 et l.174). Comme les alarmes, elle porte sur TOUT le
  /// référentiel de la portée : masquer des articles sains ne change pas la
  /// répartition du parc.
  final int permanents;
  final int journaliers;

  /// Combien d'articles suivis ont du stock (positif OU négatif) mais AUCUNE
  /// entrée valorisée : leur coût n'est pas connu, leur valeur compte pour
  /// zéro franc dans [valeurStock], et ce zéro n'est pas une mesure. Le dire
  /// est la seule façon de ne pas laisser une valeur sous-estimée passer pour
  /// exacte.
  final int sansValorisation;
}

/// Le registre FERMÉ des modes de suivi — celui du serveur
/// (`Article::SUIVIS`). Une chaîne libre ferait disparaître un article de tous
/// les filtres sans qu'aucun message ne l'annonce.
enum SuiviArticle {
  permanent('permanent', 'Permanent'),
  journalier('journalier', 'Journalier');

  const SuiviArticle(this.code, this.libelle);

  final String code;
  final String libelle;

  /// `null` sur un code inconnu : jamais un repli sur `permanent`, qui ferait
  /// compter dans les alarmes un article dont personne ne tient le stock.
  static SuiviArticle? depuisCode(String? code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

/// Le registre FERMÉ des types de point de stockage. Ce sont les quatre points
/// du Gîte (`StocksSeeder`) ; RG-05 retrouve un point par son type.
enum TypePoint {
  magasin('magasin', 'Magasin'),
  cuisine('cuisine', 'Cuisine'),
  bar('bar', 'Bar'),
  garage('garage', 'Garage');

  const TypePoint(this.code, this.libelle);

  final String code;
  final String libelle;

  static TypePoint? depuisCode(String? code) {
    for (final t in values) {
      if (t.code == code) return t;
    }
    return null;
  }
}

/// Le filtre « état » du maître (l.57-61), **réduit au registre fermé du
/// serveur** : `ConsultationStockService::ETATS` ne connaît que `rupture` et
/// `sous_seuil`. Un filtre incompris serait ignoré, et la liste entière
/// s'afficherait sous un intitulé qui promet le contraire.
enum EtatStockFiltre {
  tous('', 'Tous les états'),
  sousSeuil('sous_seuil', 'Sous seuil'),
  rupture('rupture', 'En rupture');

  const EtatStockFiltre(this.code, this.libelle);

  final String code;
  final String libelle;
}

/// Un point de stockage — remplit le sélecteur du maître (l.55).
final class PointStockage {
  const PointStockage({
    required this.id,
    required this.libelle,
    required this.type,
  });

  final String id;
  final String libelle;

  /// `null` : un point sans type reste un point valide (comme au serveur).
  final String? type;
}

/// La réponse complète de `GET /stocks/etat`.
final class EtatStock {
  const EtatStock({
    required this.kpis,
    required this.lignes,
    required this.arreteAu,
  });

  final KpisStock kpis;
  final List<LigneStock> lignes;

  /// L'instant auquel ce poste a arrêté ses comptes.
  ///
  /// Affiché, et pas seulement transporté : un état de stock sans date ne se
  /// rapproche de rien, et deux écrans ouverts à dix minutes d'intervalle
  /// donneraient deux chiffres sans qu'on sache lequel est le plus récent.
  final String arreteAu;
}

/// Les catégories proposées à la saisie — `m6-stocks.html` l.85 (`CATEGORIES`).
///
/// ## Une liste du maître, pas un référentiel
///
/// `articles.categorie` est une chaîne libre au schéma, et **aucun
/// référentiel de catégories n'existe**. Le maître ferme la liste à quatre
/// valeurs ; on s'y tient, parce qu'un champ libre ferait cohabiter
/// « Boissons » et « boisson » dans le filtre de l'écran, qui les compte comme
/// deux catégories.
///
/// La modale y ajoute celles **réellement présentes** dans les articles saisis :
/// une catégorie créée au bureau doit rester sélectionnable, sinon rouvrir la
/// fiche d'un article la remplacerait en silence.
const categoriesMaitre = <String>[
  'Denrées',
  'Boissons',
  'Fournitures',
  'Pièces véhicules',
];

/// Les unités de mesure proposées à la saisie — `m6-stocks.html` l.87
/// (`UNITES`).
///
/// Fermée pour la même raison, et une de plus : `unite_mesure` est obligatoire
/// au serveur parce que sans elle une quantité ne veut rien dire. « L » et
/// « litre » saisis au hasard rendraient deux articles incomparables.
const unitesMaitre = <String>[
  'kg',
  'L',
  'unité',
  'sac',
  'carton',
  'casier',
  'pack',
  'bidon',
  'bouteille',
];
