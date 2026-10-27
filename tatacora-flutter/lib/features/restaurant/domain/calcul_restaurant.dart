/// Les calculs de M4 Restaurant — des FONCTIONS PURES, des ENTIERS.
///
/// @see EF-M4-01 Gestion des menus et cartes
/// @see EF-M4-02 Fiches techniques (coût matière, ingrédients)
/// @see RG-05 Sortie de stock automatique — la fiche est ce qui la rend
///   possible ; ce poste ne la déclenche PAS (voir [MessagesRestaurant])
///
/// ## Rien de ce qui est calculé ici n'est stocké
///
/// Ni les portions vendables, ni le coût matière, ni la marge, ni le taux de
/// couverture ne sont des colonnes : ils se recalculent des fiches, des
/// mouvements de stock (M6) et du coût moyen pondéré. Une colonne les
/// porterait deux fois, et la seconde divergerait (`recettes.cout_matiere_
/// calcule` valait zéro pour tout le monde au serveur : PA-126).
///
/// ## Des entiers, confrontés au serveur par exécution de PHP
///
/// Quantité d'ingrédient en MILLIÈMES, stock en CENTIÈMES, coût moyen pondéré
/// en DIX-MILLIÈMES de franc, prix de vente en FRANCS. Les formules sont celles
/// de `CarteRestaurantService` et `CompositionRecetteService`, rejouées par le
/// VRAI code PHP sur les mêmes scénarios
/// (`test/features/restaurant/carte_contre_serveur_test.dart`) : une formule
/// recopiée ne vérifierait qu'elle-même.
///
///  * portions d'un ingrédient = `bcdiv(stock, quantité, 0)` — troncature ;
///  * coût d'une ligne = `bcmul(quantité, coût moyen pondéré, 2)` — TRONQUÉ au
///    centime, puis les lignes s'additionnent à deux décimales ;
///  * taux de couverture = `bcdiv(bcmul(n, 100, 3), total, 1)` — tronqué au
///    dixième.
///
/// ## Trois écarts avec le serveur, NOMMÉS (rejoués par PHP, jamais devinés)
///
///  1. **Un article en achat journalier ne borne aucune portion.** Le serveur
///     lit pour lui un solde de `0.00` (il n'a aucun mouvement) et rend `0`
///     portion, « rupture » et « sous seuil » : une fiche d'une seule salade
///     est en rupture en permanence, et toute fiche qui contient un oignon
///     aussi. Un zéro plausible n'est pas une mesure ([MotifSansStock.
///     compositionSansSuivi]). À remonter à l'Architecte.
///  2. **Le tri et la recherche ignorent les accents**, comme la collation du
///     serveur (`utf8mb4_unicode_ci`) — mais sont faits en Dart, parce que le
///     `LIKE` de SQLite ne replie la casse que sur l'ASCII.
///  3. **Plusieurs points de type cuisine** : le serveur prend « le premier »
///     sans `ORDER BY` pour l'API, et « par libellé » pour la vue. Ce poste
///     retient le premier par libellé, puis par identifiant : un choix
///     déterministe, jamais le hasard de l'ordre de la base.
library;

import '../../../core/format/cle_comparaison.dart';
import '../../stocks/domain/calcul_stock.dart' show ecrireCentiemes, ecrireCout;
import '../../stocks/domain/entities/etat_stock.dart' show SuiviArticle;
import '../../pos/data/dto/catalogue_dto.dart' show IndisponibiliteDistante;
import 'entities/carte_restaurant.dart';
import 'entities/plat.dart';
import 'messages_restaurant.dart';

/// 1 unité = 0,001 de l'unité de l'article (`DECIMAL(10,3)` du serveur).
const int echelleRecette = 1000;

/// Les types de menu — le registre FERMÉ du serveur (`Menu::TYPES`).
const List<String> typesDeMenu = ['local', 'europeen', 'special'];

/* ====================================================================== */
/* Lecture de ce qui est frappé                                            */
/* ====================================================================== */

final _formeQuantite = RegExp(r'^(\d+)(?:[.,](\d+))?$');

/// « 0,25 », « 1.5 » ou « 12 » -> des millièmes ; `null` si la forme n'est pas
/// un nombre positif ou nul. [trop] vaut `true` quand la forme est un nombre
/// mais porte PLUS de trois décimales non nulles : refusé, jamais tronqué.
({int? milliemes, bool trop}) lireMilliemes(String saisie) {
  final m = _formeQuantite.firstMatch(saisie.trim());
  if (m == null) return (milliemes: null, trop: false);

  final entiere = m.group(1)!;
  final decimale = m.group(2) ?? '';
  if (entiere.length > 10) return (milliemes: null, trop: false);

  // Des zéros de fin ne sont pas une précision : « 0,2500 » vaut « 0,250 ».
  var utile = decimale;
  while (utile.length > 3 && utile.endsWith('0')) {
    utile = utile.substring(0, utile.length - 1);
  }
  if (utile.length > 3) return (milliemes: null, trop: true);

  return (
    milliemes:
        int.parse(entiere) * echelleRecette + int.parse(utile.padRight(3, '0')),
    trop: false,
  );
}

/// 300 -> « 0.300 ». Trois décimales toujours : la forme du serveur.
String ecrireMilliemes(int milliemes) {
  final signe = milliemes < 0 ? '-' : '';
  final absolu = milliemes.abs();
  return '$signe${absolu ~/ echelleRecette}.'
      '${(absolu % echelleRecette).toString().padLeft(3, '0')}';
}

/// Des centimes de franc en chaîne à deux décimales : 75000 -> « 750.00 ».
String ecrireCentimes(int centimes) => ecrireCentiemes(centimes);

/// Des francs entiers en `DECIMAL(15,2)` sérialisé : 4500 -> « 4500.00 ».
String ecrirePrix(int francs) => ecrireCentimes(francs * 100);

/// Le prix de vente frappé -> des FRANCS ENTIERS, ou la phrase du refus.
///
/// « 4 500 » et « 4500,00 » sont lus ; « 4500,50 » est REFUSÉ (le franc CFA n'a
/// pas de sous-unité en circulation, et le point de vente manipule des
/// entiers) ; « -5 » est refusé avec la phrase du serveur.
({int? francs, String? erreur}) lirePrix(String saisie) {
  final texte = saisie.replaceAll(RegExp(r'[\s  ]'), '').replaceAll(',', '.');
  if (texte.isEmpty) {
    return (francs: null, erreur: MessagesRestaurant.prixObligatoire);
  }

  final m = RegExp(r'^(-?)(\d+)(?:\.(\d*))?$').firstMatch(texte);
  if (m == null) {
    return (francs: null, erreur: MessagesRestaurant.prixIllisible);
  }

  final entiere = m.group(2)!;
  final decimale = m.group(3) ?? '';
  final nul =
      int.tryParse(entiere) == 0 && decimale.replaceAll('0', '').isEmpty;

  if (m.group(1) == '-' && !nul) {
    return (francs: null, erreur: MessagesRestaurant.prixNegatif);
  }
  if (entiere.length > 12) {
    return (francs: null, erreur: MessagesRestaurant.prixIllisible);
  }
  if (decimale.replaceAll('0', '').isNotEmpty) {
    return (francs: null, erreur: MessagesRestaurant.prixFractionDeFranc);
  }

  return (francs: int.parse(entiere), erreur: null);
}

/// Une date `AAAA-MM-JJ` qui existe au calendrier (le 30 février n'en est pas
/// une : `DateTime` le ramènerait au 2 mars sans rien dire).
bool estDateValide(String texte) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(texte);
  if (m == null) return false;
  final a = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final j = int.parse(m.group(3)!);
  final d = DateTime(a, mo, j);
  return d.year == a && d.month == mo && d.day == j;
}

/* ====================================================================== */
/* Vérification des saisies — sans toucher la base                         */
/* ====================================================================== */

/// Le résultat de la vérification d'une saisie : les valeurs normalisées si
/// tout passe, les phrases par champ sinon. Jamais les deux.
final class SaisieMenuLue {
  const SaisieMenuLue({
    this.libelle = '',
    this.type = '',
    this.dateDebut,
    this.dateFin,
    this.erreurs = const {},
  });

  final String libelle;
  final String type;
  final String? dateDebut;
  final String? dateFin;
  final Map<String, String> erreurs;
}

/// `EnregistrerMenuRequest` + `Restauration::enregistrerMenu` : libellé requis
/// (255 au plus), type du registre fermé, dates facultatives, la fin ne
/// précède pas le début. `after_or_equal` n'est posée que si un début existe :
/// appliquée à une chaîne vide, elle comparerait la fin à une date qui
/// n'existe pas.
SaisieMenuLue verifierMenu(SaisieMenu s) {
  final erreurs = <String, String>{};

  final libelle = s.libelle.trim();
  if (libelle.isEmpty) {
    erreurs['libelle'] = MessagesRestaurant.libelleObligatoire;
  } else if (libelle.length > 255) {
    erreurs['libelle'] = MessagesRestaurant.libelleTropLong;
  }

  if (!typesDeMenu.contains(s.type)) {
    erreurs['type'] = MessagesRestaurant.categorieInconnue;
  }

  final debut = s.dateDebut.trim();
  final fin = s.dateFin.trim();
  if (debut.isNotEmpty && !estDateValide(debut)) {
    erreurs['date_debut'] = MessagesRestaurant.dateIllisible;
  }
  if (fin.isNotEmpty && !estDateValide(fin)) {
    erreurs['date_fin'] = MessagesRestaurant.dateIllisible;
  }
  // Des dates `AAAA-MM-JJ` valides se comparent comme des chaînes.
  if (debut.isNotEmpty &&
      fin.isNotEmpty &&
      !erreurs.containsKey('date_debut') &&
      !erreurs.containsKey('date_fin') &&
      fin.compareTo(debut) < 0) {
    erreurs['date_fin'] = MessagesRestaurant.saisonInversee;
  }

  if (erreurs.isNotEmpty) return SaisieMenuLue(erreurs: erreurs);

  return SaisieMenuLue(
    libelle: libelle,
    type: s.type,
    dateDebut: debut.isEmpty ? null : debut,
    dateFin: fin.isEmpty ? null : fin,
  );
}

/// Une ligne de composition lue : l'article et ses millièmes.
final class LigneCompositionLue {
  const LigneCompositionLue({required this.articleId, required this.milliemes});

  final String articleId;
  final int milliemes;
}

final class SaisieFicheLue {
  const SaisieFicheLue({
    this.libelle = '',
    this.lignes = const [],
    this.erreurs = const {},
  });

  final String libelle;
  final List<LigneCompositionLue> lignes;

  /// Les phrases par champ : `libelle`, ou `lignes.<rang>.article_id` /
  /// `lignes.<rang>.quantite_unitaire` (le rang est celui de la ligne
  /// SAISIE, vides comprises, pour que l'écran désigne la bonne).
  final Map<String, String> erreurs;
}

/// `EnregistrerRecetteRequest` + `EnregistrerCompositionRequest` + les règles
/// de `Restauration::enregistrerRecette` : les lignes ENTIÈREMENT vides sont
/// retirées avant validation (un « ajouter un ingrédient » abandonné ne doit
/// pas refuser une fiche par ailleurs correcte) ; chaque ligne désigne un
/// article ; un article ne figure qu'une fois ; la quantité est strictement
/// positive. Une composition VIDE est acceptée : c'est le seul moyen de vider
/// une fiche erronée.
///
/// Écart : la quantité accepte au plus trois décimales et en REFUSE une
/// quatrième (le serveur arrondit à la précision de la colonne en silence) — la
/// fiche décrémenterait un autre chiffre que celui que l'écran vient de lire.
SaisieFicheLue verifierFiche(SaisieFiche s) {
  final erreurs = <String, String>{};

  final libelle = s.libelle.trim();
  if (libelle.isEmpty) {
    erreurs['libelle'] = MessagesRestaurant.libelleObligatoire;
  } else if (libelle.length > 255) {
    erreurs['libelle'] = MessagesRestaurant.libelleTropLong;
  }

  final lignes = <LigneCompositionLue>[];
  final vus = <String>{};

  for (var i = 0; i < s.lignes.length; i++) {
    final l = s.lignes[i];
    final article = l.articleId.trim();
    final quantite = l.quantite.trim();
    if (article.isEmpty && quantite.isEmpty) continue;

    if (article.isEmpty) {
      erreurs['lignes.$i.article_id'] = MessagesRestaurant.articleObligatoire;
    } else if (!vus.add(article)) {
      erreurs['lignes.$i.article_id'] = MessagesRestaurant.ingredientEnDouble;
    }

    if (quantite.isEmpty) {
      erreurs['lignes.$i.quantite_unitaire'] =
          MessagesRestaurant.quantiteRecetteObligatoire;
      continue;
    }
    final lue = lireMilliemes(quantite);
    if (lue.milliemes == null) {
      erreurs['lignes.$i.quantite_unitaire'] = lue.trop
          ? MessagesRestaurant.quantiteTropFine
          : MessagesRestaurant.quantiteIllisible;
    } else if (lue.milliemes! <= 0) {
      erreurs['lignes.$i.quantite_unitaire'] =
          MessagesRestaurant.quantiteRecettePositive;
    } else if (article.isNotEmpty &&
        !erreurs.containsKey('lignes.$i.article_id')) {
      lignes.add(
        LigneCompositionLue(articleId: article, milliemes: lue.milliemes!),
      );
    }
  }

  if (erreurs.isNotEmpty) return SaisieFicheLue(erreurs: erreurs);
  return SaisieFicheLue(libelle: libelle, lignes: lignes);
}

final class SaisiePlatLue {
  const SaisiePlatLue({
    this.libelle = '',
    this.prixFrancs = 0,
    this.erreurs = const {},
  });

  final String libelle;
  final int prixFrancs;
  final Map<String, String> erreurs;
}

/// `EnregistrerPlatRequest` : libellé requis (255 au plus), prix `>= 0` en
/// francs entiers. Le menu et la fiche, eux, se vérifient contre la base (leur
/// existence est une clé étrangère).
SaisiePlatLue verifierPlat(SaisiePlat s) {
  final erreurs = <String, String>{};

  final libelle = s.libelle.trim();
  if (libelle.isEmpty) {
    erreurs['libelle'] = MessagesRestaurant.libelleObligatoire;
  } else if (libelle.length > 255) {
    erreurs['libelle'] = MessagesRestaurant.libelleTropLong;
  }

  final prix = lirePrix(s.prixVente);
  if (prix.erreur != null) erreurs['prix_vente'] = prix.erreur!;

  if (s.menuId.trim().isEmpty) {
    erreurs['menu_id'] = MessagesRestaurant.menuObligatoire;
  }
  if (s.recetteId.trim().isEmpty) {
    erreurs['recette_id'] = MessagesRestaurant.recetteObligatoire;
  }

  // La catégorie (v41) : `null` = non soumise (importation, plat d'avant) ; une
  // clé soumise doit être l'une des dix de la carte, comme le serveur la juge.
  final categorie = s.categorie;
  if (categorie != null) {
    if (categorie.trim().isEmpty) {
      erreurs['categorie'] = MessagesRestaurant.categorieDuPlatObligatoire;
    } else if (CategorieCarte.depuisCode(categorie) == null) {
      erreurs['categorie'] = MessagesRestaurant.categorieDuPlatInvalide;
    }
  }

  if (erreurs.isNotEmpty) return SaisiePlatLue(erreurs: erreurs);
  return SaisiePlatLue(libelle: libelle, prixFrancs: prix.francs!);
}

/* ====================================================================== */
/* PA-161 (b) — les deux marques de prix                                   */
/* ====================================================================== */

/// « Corrigé à la main » est un FAIT, pas une case à cocher : changer au
/// clavier le prix d'un plat qui portait un tarif provisoire EST la correction
/// manuelle. La lui faire cocher en plus reviendrait à lui demander de déclarer
/// ce qu'il vient de faire, et il l'oublierait.
///
/// Même règle que `MarquesDePrix::completer` : la marque se pose quand le plat
/// portait un tarif provisoire (avant l'enregistrement) ET que le montant
/// change réellement ; elle ne se lève jamais d'elle-même.
bool prixCorrigeMainApres({
  required bool corrigeActuel,
  required bool provisoireActuel,
  required int prixActuelFrancs,
  required int prixSoumisFrancs,
}) =>
    corrigeActuel || (provisoireActuel && prixSoumisFrancs != prixActuelFrancs);

/* ====================================================================== */
/* La carte                                                                */
/* ====================================================================== */

/// Un ingrédient tel que les calculs le voient.
final class IngredientCalcule {
  const IngredientCalcule({
    required this.articleId,
    required this.libelle,
    required this.uniteMesure,
    required this.quantiteMilliemes,
    required this.suivi,
    required this.seuilCentiemes,
    required this.stockCentiemes,
    required this.cmpDixMilliemes,
  });

  final String articleId;
  final String libelle;
  final String uniteMesure;
  final int quantiteMilliemes;
  final SuiviArticle suivi;
  final int seuilCentiemes;

  /// Le stock AU POINT CUISINE, jamais tous points confondus : ce qui dort au
  /// magasin n'est pas servi en salle.
  final int stockCentiemes;

  /// Le coût moyen pondéré. `0` = jamais réceptionné : un article qui n'est pas
  /// gratuit mais NON VALORISÉ.
  final int cmpDixMilliemes;

  bool get estSuivi => suivi == SuiviArticle.permanent;
}

/// Un plat et ce que sa fiche engage.
final class PlatCalcule {
  const PlatCalcule({
    required this.id,
    required this.libelle,
    required this.menuId,
    required this.menuType,
    required this.recetteId,
    required this.prixFrancs,
    required this.composition,
    this.recetteLibelle,
    this.prixProvisoire = false,
    this.prixCorrigeMain = false,
    this.indisponibilite,
    this.lien,
  });

  /// Le lien direct au stock (v36), ou `null` : le plat se décrémente par sa
  /// fiche. Quand il existe, il l'emporte (`DeductionStockCuisineService`).
  final LienDirectCalcule? lien;

  final String id;
  final String libelle;
  final String menuId;

  /// Le retrait de la carte du jour en cours (v31), ou `null`.
  final IndisponibiliteDistante? indisponibilite;

  /// `menus.type` : la catégorie du plat (comme l'API).
  final String menuType;
  final String recetteId;

  /// Le libellé de la fiche, tel que la colonne « Article de stock » le nomme.
  final String? recetteLibelle;
  final int prixFrancs;
  final bool prixProvisoire;
  final bool prixCorrigeMain;

  /// Triée par identifiant d'article, comme le serveur (`orderBy('article_id')`).
  final List<IngredientCalcule> composition;
}

/// Le lien direct d'un plat à un article de stock, valorisé au point cuisine.
final class LienDirectCalcule {
  const LienDirectCalcule({
    required this.articleId,
    required this.libelle,
    required this.uniteMesure,
    required this.suivi,
    required this.unitesVendables,
    required this.unitesDixMilliemes,
    required this.stockCentiemes,
    required this.seuilCentiemes,
  });

  final String articleId;
  final String libelle;
  final String uniteMesure;
  final SuiviArticle suivi;

  /// Le texte décimal enregistré (« 24.0000 »).
  final String unitesVendables;

  /// Le même nombre en dix-millièmes (240000), pour le calcul en entiers.
  final int unitesDixMilliemes;

  /// Le solde de l'article au point cuisine, en centièmes.
  final int stockCentiemes;
  final int seuilCentiemes;

  /// `bcmul(solde, conversion, 0)` : « il reste 120 bouteilles », tronqué.
  /// Jamais négatif (une rupture forcée se lit zéro).
  int get portions => stockCentiemes <= 0
      ? 0
      : (stockCentiemes * unitesDixMilliemes) ~/ 1000000;
}

/// « 24 », « 0,5 » ou « 12.25 » -> des dix-millièmes (`DECIMAL(…,4)`), tronqués
/// au quatrième décimal comme `bcmath` ; `null` si la forme n'est pas un nombre
/// positif ou nul.
int? lireDixMilliemes(String saisie) {
  final m = RegExp(r'^(\d+)(?:[.,](\d*))?$').firstMatch(saisie.trim());
  if (m == null) return null;
  final entiere = m.group(1)!;
  if (entiere.length > 9) return null;
  var fraction = m.group(2) ?? '';
  if (fraction.length > 4) fraction = fraction.substring(0, 4);
  return int.parse(entiere) * 10000 + int.parse(fraction.padRight(4, '0'));
}

/// 240000 -> « 24.0000 » : la forme du serveur.
String ecrireDixMilliemes(int v) =>
    '${v ~/ 10000}.${(v % 10000).toString().padLeft(4, '0')}';

/// 240000 -> « 24 », 4167 -> « 0.4167 » : sans zéros de fin, pour l'écran.
String lisibleDixMilliemes(int v) {
  final texte = ecrireDixMilliemes(v);
  return texte
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

/// Ce que le calcul des portions conclut.
final class PortionsCalculees {
  const PortionsCalculees({
    this.portions,
    this.limitant,
    this.sousSeuil = false,
    this.motif,
  });

  /// `null` = aucun chiffre ([motif] dit pourquoi). `0` = il n'en reste plus.
  final int? portions;
  final IngredientCalcule? limitant;
  final bool sousSeuil;
  final MotifSansStock? motif;
}

/// Combien de portions le stock cuisine permet encore de servir : le MINIMUM
/// sur les ingrédients suivis. Le maillon faible commande — dix kilos de riz ne
/// servent à rien s'il ne reste pas de poulet — et l'ingrédient limitant est
/// remonté avec le chiffre : « 4 portions » sans dire ce qui manque n'indique
/// pas quoi racheter.
///
/// Le premier ingrédient atteignant le minimum garde la place (`<` strict) : à
/// égalité, c'est celui de plus petit identifiant.
PortionsCalculees calculerPortions(
  List<IngredientCalcule> composition, {
  required bool pointCuisine,
}) {
  if (composition.isEmpty) {
    return const PortionsCalculees(motif: MotifSansStock.recetteSansIngredient);
  }
  if (!pointCuisine) {
    return const PortionsCalculees(motif: MotifSansStock.pointCuisineAbsent);
  }

  int? minimum;
  IngredientCalcule? limitant;
  var sousSeuil = false;
  var suivis = 0;

  for (final i in composition) {
    // Écart 1 (voir l'en-tête) : un article journalier n'a aucun stock tenu.
    if (!i.estSuivi) continue;
    suivis++;

    if (i.stockCentiemes <= i.seuilCentiemes) sousSeuil = true;

    // Une quantité nulle ne consomme rien : elle ne borne aucune portion.
    if (i.quantiteMilliemes <= 0) continue;

    // Stock négatif — une rupture forcée l'autorise (RG-06) : zéro portion,
    // jamais un nombre négatif de plats. `stock / quantité` en entiers : le
    // stock est en centièmes et la quantité en millièmes, d'où le facteur 10.
    final p = i.stockCentiemes <= 0
        ? 0
        : (i.stockCentiemes * 10) ~/ i.quantiteMilliemes;

    if (minimum == null || p < minimum) {
      minimum = p;
      limitant = i;
    }
  }

  if (suivis == 0) {
    return const PortionsCalculees(motif: MotifSansStock.compositionSansSuivi);
  }
  return PortionsCalculees(
    portions: minimum ?? 0,
    limitant: limitant,
    sousSeuil: sousSeuil,
  );
}

/// Le coût matière d'une fiche — TROIS états, jamais deux.
///
///  * un montant : tous les ingrédients sont valorisés ;
///  * « incomplet » : au moins un ingrédient n'a jamais été réceptionné, son
///    coût moyen pondéré vaut zéro, ce qui n'est pas un prix ;
///  * « vide » : la fiche n'a aucune ligne.
///
/// Rendre `0` dans les deux derniers cas afficherait « coût matière : 0 F »,
/// donc « marge = prix de vente entier », sur l'écran où l'on fixe un prix.
final class CoutMatiereCalcule {
  const CoutMatiereCalcule._({
    this.centimes,
    this.incomplet = false,
    this.vide = false,
    this.articlesSansCout = const [],
  });

  const CoutMatiereCalcule.vide() : this._(vide: true);

  const CoutMatiereCalcule.incomplet(List<String> articles)
    : this._(incomplet: true, articlesSansCout: articles);

  const CoutMatiereCalcule.connu(int centimes) : this._(centimes: centimes);

  /// En centimes de franc. `null` quand le coût est inconnu ou la fiche vide.
  final int? centimes;
  final bool incomplet;
  final bool vide;
  final List<String> articlesSansCout;

  /// « 750.00 », ou `null`.
  String? get montant => centimes == null ? null : ecrireCentimes(centimes!);

  /// Prix de vente moins coût — `null` si le coût est inconnu : un prix moins un
  /// coût inconnu n'est pas une marge, c'est le prix de vente. Elle peut être
  /// NÉGATIVE (vendu à perte) : « -120.50 ».
  String? marge(int prixFrancs) =>
      centimes == null ? null : ecrireCentimes(prixFrancs * 100 - centimes!);
}

CoutMatiereCalcule calculerCoutMatiere(List<IngredientCalcule> composition) {
  if (composition.isEmpty) return const CoutMatiereCalcule.vide();

  var total = 0;
  final sansCout = <String>[];

  for (final i in composition) {
    if (i.cmpDixMilliemes <= 0) {
      if (!sansCout.contains(i.libelle)) sansCout.add(i.libelle);
      continue;
    }
    // millièmes × dix-millièmes = dix-millionièmes de franc ; au centime, on
    // divise par 10^5 en TRONQUANT, ligne par ligne, comme `bcmul(…, 2)`.
    total += (i.quantiteMilliemes * i.cmpDixMilliemes) ~/ 100000;
  }

  // Le trou l'emporte sur le sous-total : un coût partiel présenté comme
  // complet est plus dangereux qu'un coût absent, parce qu'il se compare.
  return sansCout.isEmpty
      ? CoutMatiereCalcule.connu(total)
      : CoutMatiereCalcule.incomplet(sansCout);
}

/// Le taux de couverture, en pourcentage tronqué au dixième — « 66.6 » — ou
/// `null` sur un ensemble vide : `0.0` se lirait « aucun plat n'est rattaché »,
/// donc comme un défaut à corriger, alors qu'il n'y a rien à rattacher.
String? tauxCouverture(int numerateur, int total) {
  if (total == 0) return null;
  final dixiemes = (numerateur * 1000) ~/ total;
  return '${dixiemes ~/ 10}.${dixiemes % 10}';
}

/// Le premier point de type cuisine, par libellé puis par identifiant — le choix
/// est DÉTERMINISTE (écart 3 de l'en-tête).
String? choisirPointCuisine(
  List<({String id, String libelle, String? type})> points,
) {
  final cuisines =
      [
        for (final p in points)
          if (p.type == 'cuisine') p,
      ]..sort((a, b) {
        final c = cleDeComparaison(
          a.libelle,
        ).compareTo(cleDeComparaison(b.libelle));
        return c != 0 ? c : a.id.compareTo(b.id);
      });
  return cuisines.isEmpty ? null : cuisines.first.id;
}

/// La carte entière : lignes filtrées, indicateurs et couverture sur le TOUT.
///
/// Les indicateurs et la couverture portent sur la carte ENTIÈRE, les lignes sur
/// les filtres : c'est ce que fait la VUE (`EcranDeCarte::indicateurs` est
/// appelée sur toutes les lignes, avant `lignesFiltrees`). Filtrer les
/// compteurs ferait tomber « ne décrémentent rien » à zéro dès qu'on filtre sur
/// « liés au stock » — c'est-à-dire précisément quand on cherche à mesurer le
/// trou.
///
/// Écart avec l'API du serveur (`CarteRestaurantService::carte`), rejoué par
/// PHP : elle applique la recherche et la catégorie AVANT de compter, et ne
/// laisse que le filtre d'état en dehors. La vue gagne (PA-182), et la
/// confrontation compare les indicateurs de chaque requête à ceux de la requête
/// SANS filtre.
CarteRestaurant calculerCarte({
  required List<PlatCalcule> plats,
  required String? pointCuisineId,
  required String arreteAu,
  String? recherche,
  String? categorie,
  EtatArticleCarte etat = EtatArticleCarte.tous,
}) {
  final terme = cleDeComparaison((recherche ?? '').trim());

  final tries = [...plats]
    ..sort((a, b) {
      final c = cleDeComparaison(
        a.libelle,
      ).compareTo(cleDeComparaison(b.libelle));
      return c != 0 ? c : a.id.compareTo(b.id);
    });

  final toutes = [
    for (final p in tries) _ligne(p, pointCuisine: pointCuisineId != null),
  ];

  final filtrees = [
    for (final l in toutes)
      if ((categorie == null ||
              categorie.isEmpty ||
              l.categorieBrute == categorie) &&
          (terme.isEmpty || cleDeComparaison(l.libelle).contains(terme)) &&
          switch (etat) {
            EtatArticleCarte.liesAuStock => l.lieAuStock,
            EtatArticleCarte.sansLienDeStock => !l.lieAuStock,
            EtatArticleCarte.enRuptureDeStock => l.rupture,
            EtatArticleCarte.prixProvisoire => l.prixProvisoire,
            // `tous`, et « retirés du jour » que le serveur refuse faute de
            // colonne : jamais appliqué ici, l'écran ne le propose pas.
            _ => true,
          })
        l,
  ];

  return CarteRestaurant(
    lignes: filtrees,
    indicateurs: _indicateurs(toutes),
    couverture: _couverture(toutes),
    filtresAppliques: {
      if ((recherche ?? '').isNotEmpty) 'recherche': recherche!,
      if ((categorie ?? '').isNotEmpty) 'categorie': categorie!,
      if (etat.parametre != null) 'etat': etat.parametre!,
    },
    arreteAu: arreteAu,
    pointCuisineId: pointCuisineId,
  );
}

LigneCarteRestaurant _ligne(PlatCalcule p, {required bool pointCuisine}) {
  final lien = p.lien;
  // Le lien direct l'emporte sur la fiche : un article unique n'a pas de
  // nomenclature à traverser (`DeductionStockCuisineService`).
  final portions = lien == null
      ? calculerPortions(p.composition, pointCuisine: pointCuisine)
      : !pointCuisine
      ? const PortionsCalculees(motif: MotifSansStock.pointCuisineAbsent)
      : lien.suivi != SuiviArticle.permanent
      ? const PortionsCalculees(motif: MotifSansStock.compositionSansSuivi)
      : PortionsCalculees(
          portions: lien.portions,
          sousSeuil: lien.stockCentiemes <= lien.seuilCentiemes,
          limitant: IngredientCalcule(
            articleId: lien.articleId,
            libelle: lien.libelle,
            uniteMesure: lien.uniteMesure,
            quantiteMilliemes: 0,
            suivi: lien.suivi,
            seuilCentiemes: lien.seuilCentiemes,
            stockCentiemes: lien.stockCentiemes,
            cmpDixMilliemes: 0,
          ),
        );
  final cout = calculerCoutMatiere(p.composition);

  return LigneCarteRestaurant(
    id: p.id,
    libelle: p.libelle,
    categorieBrute: p.menuType,
    menuId: p.menuId,
    recetteId: p.recetteId,
    recetteLibelle: p.recetteLibelle,
    prixVente: ecrirePrix(p.prixFrancs),
    lieAuStock: lien != null || p.composition.isNotEmpty,
    articleStockId: lien?.articleId,
    articleStockLibelle: lien?.libelle,
    articleStockUnite: lien?.uniteMesure,
    unitesVendables: lien == null
        ? null
        : lisibleDixMilliemes(lien.unitesDixMilliemes),
    nbIngredients: p.composition.length,
    motifSansStock: portions.motif,
    portionsVendables: portions.portions,
    ingredientLimitant: portions.limitant == null
        ? null
        : IngredientLimitant(
            id: portions.limitant!.articleId,
            libelle: portions.limitant!.libelle,
            uniteMesure: portions.limitant!.uniteMesure,
          ),
    // Une rupture ne se déclare que si le chiffre existe : sans point cuisine,
    // « 0 » se lirait « plus rien en réserve » alors que personne n'a rien
    // consulté.
    rupture: portions.portions != null && portions.portions == 0,
    sousSeuil: portions.sousSeuil,
    coutMatiere: cout.montant,
    coutMatiereIncomplet: cout.incomplet,
    articlesSansCout: cout.articlesSansCout,
    marge: cout.marge(p.prixFrancs),
    prixProvisoire: p.prixProvisoire,
    prixCorrigeMain: p.prixCorrigeMain,
    indisponibilite: p.indisponibilite,
  );
}

IndicateursCarte _indicateurs(List<LigneCarteRestaurant> lignes) {
  var lies = 0;
  var rupture = 0;
  var sousSeuil = 0;
  var coutInconnu = 0;
  var provisoires = 0;
  var retires = 0;

  for (final l in lignes) {
    if (l.estRetire) retires++;
    if (l.lieAuStock) lies++;
    if (l.rupture) rupture++;
    if (l.sousSeuil) sousSeuil++;
    if (l.coutMatiere == null) coutInconnu++;
    if (l.prixProvisoire) provisoires++;
  }

  return IndicateursCarte(
    plats: lignes.length,
    lies: lies,
    sansLien: lignes.length - lies,
    tauxCouverture: tauxCouverture(lies, lignes.length),
    enRupture: rupture,
    sousSeuil: sousSeuil,
    coutMatiereInconnu: coutInconnu,
    prixProvisoires: provisoires,
    // Depuis la v31 (21/10/2026) la disponibilité du jour a sa table : les
    // deux sont COMPTÉS, donc plus rien n'est « absent ». Le serveur, lui, les
    // déclare encore absents de son API (`CarteRestaurantService`) : les
    // cartes continuent d'interroger `raisonAbsence`.
    disponibles: lignes.length - retires,
    indisponibles: retires,
  );
}

List<CouvertureCategorie> _couverture(List<LigneCarteRestaurant> lignes) {
  final plats = <String, int>{};
  final lies = <String, int>{};

  for (final l in lignes) {
    plats[l.categorieBrute] = (plats[l.categorieBrute] ?? 0) + 1;
    lies[l.categorieBrute] =
        (lies[l.categorieBrute] ?? 0) + (l.lieAuStock ? 1 : 0);
  }

  // `ksort` : l'ordre des clés (octets), pas celui des libellés.
  final cles = plats.keys.toList()..sort();

  return [
    for (final c in cles)
      CouvertureCategorie(
        categorieBrute: c,
        plats: plats[c]!,
        lies: lies[c]!,
        sansLien: plats[c]! - lies[c]!,
        taux: tauxCouverture(lies[c]!, plats[c]!),
      ),
  ];
}

/* ====================================================================== */
/* Les fiches techniques — l'onglet des fiches et la modale de détail      */
/* ====================================================================== */

/// Une fiche et ses plats, prête à être transformée en entités.
final class FicheCalculee {
  const FicheCalculee({
    required this.id,
    required this.libelle,
    required this.composition,
    required this.platsServis,
    this.compositionProvisoire = false,
  });

  final String id;
  final String libelle;
  final List<IngredientCalcule> composition;
  final List<String> platsServis;

  /// La marque « composition provisoire » (`recettes.composition_provisoire`) :
  /// les quantités ont été posées, jamais pesées.
  final bool compositionProvisoire;
}

/// La fiche technique et son coût, dans ses trois états.
Recette versRecette(FicheCalculee f) {
  final cout = calculerCoutMatiere(f.composition);
  return Recette(
    id: f.id,
    libelle: f.libelle,
    coutMatiere: cout.montant,
    coutMatiereIncomplet: cout.incomplet,
    compositionVide: cout.vide,
    articlesSansCout: cout.articlesSansCout,
    nbIngredients: f.composition.length,
    platsServis: f.platsServis,
    // `Recette::decrementeUnStockSuivi` : au moins un ingrédient suivi.
    decrementeUnStockSuivi: f.composition.any((i) => i.estSuivi),
    compositionProvisoire: f.compositionProvisoire,
  );
}

/// La composition ligne à ligne : quantité, unité, coût de l'unité et de la
/// ligne. Un coût d'ingrédient INCONNU est `null`, pas `0.0000`.
List<LigneComposition> versLignes(List<IngredientCalcule> composition) => [
  for (final i in composition)
    LigneComposition(
      articleId: i.articleId,
      articleLibelle: i.libelle,
      uniteMesure: i.uniteMesure,
      quantiteUnitaire: ecrireMilliemes(i.quantiteMilliemes),
      coutUnitaire: i.cmpDixMilliemes <= 0
          ? null
          : ecrireCout(i.cmpDixMilliemes),
      coutLigne: i.cmpDixMilliemes <= 0
          ? null
          : ecrireCentimes((i.quantiteMilliemes * i.cmpDixMilliemes) ~/ 100000),
    ),
];
