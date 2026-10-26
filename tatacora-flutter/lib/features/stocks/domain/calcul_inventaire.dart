/// L'INVENTAIRE physique tel que CE POSTE le calcule — EF-M6-05.
///
/// ## Théorique contre constaté
///
/// Le stock théorique est le cumul des mouvements du point ; le constaté est ce
/// qu'on trouve en rayon. L'écart (`constaté − théorique`) est la mesure de
/// fiabilité du stock : négatif = manquant, positif = excédent.
///
/// ## Le théorique est FIGÉ au comptage
///
/// Comme `InventaireService::compter` : le théorique d'une ligne est celui de
/// l'instant où l'article a été compté, jamais recalculé ensuite — le
/// recalculer ferait un écart faux dès qu'un mouvement survient pendant la
/// matinée. Un second comptage du même article ÉCRASE le premier (correction
/// d'une erreur de saisie) et refige le théorique.
///
/// ## Une ligne n'existe QUE si l'article a été compté
///
/// Un article oublié ne doit pas se confondre avec un article compté conforme
/// (écart zéro) : c'est exactement ce qu'un inventaire existe pour révéler. La
/// feuille porte donc, pour chaque article, un constaté `null` tant qu'il n'a
/// pas été compté.
///
/// ## Le brouillon n'est PAS en base
///
/// Le comptage en cours vit en mémoire ([InventaireEnCours]) ; l'inventaire, ses
/// lignes et ses mouvements de régularisation s'écrivent ensemble, à la
/// clôture, dans UNE transaction. Le schéma ne porte aucun statut d'inventaire
/// (PA-150) : une ligne écrite avant la clôture ne se distinguerait pas d'un
/// inventaire clos.
///
/// Tout est en entiers : quantités en CENTIÈMES, valeurs en francs.
library;

import 'calcul_stock.dart';

/// Ce que le comptage d'UN article a figé : le théorique à cet instant et ce
/// qui a été trouvé en rayon.
final class ComptageBrouillon {
  const ComptageBrouillon({
    required this.theoriqueCentiemes,
    required this.constateCentiemes,
  });

  final int theoriqueCentiemes;
  final int constateCentiemes;

  /// Négatif = manquant, positif = excédent.
  int get ecartCentiemes => constateCentiemes - theoriqueCentiemes;
}

/// L'inventaire OUVERT sur ce poste, pas encore clôturé.
final class InventaireEnCours {
  const InventaireEnCours({
    required this.pointId,
    required this.date,
    this.comptages = const {},
  });

  final String pointId;

  /// Le jour d'ouverture (`date_inventaire`).
  final DateTime date;

  /// Article -> ce qui a été figé à son comptage.
  final Map<String, ComptageBrouillon> comptages;

  InventaireEnCours avecComptage(String articleId, ComptageBrouillon c) =>
      InventaireEnCours(
        pointId: pointId,
        date: date,
        comptages: {...comptages, articleId: c},
      );
}

/// Une ligne de la feuille de comptage : un article, compté ou non.
final class LigneFeuille {
  const LigneFeuille({
    required this.articleId,
    required this.libelle,
    required this.unite,
    required this.theoriqueCentiemes,
    required this.constateCentiemes,
    required this.valoriseFrancs,
  });

  final String articleId;
  final String libelle;
  final String unite;

  /// Figé au comptage pour une ligne comptée, sinon le stock du point à cet
  /// instant.
  final int theoriqueCentiemes;

  /// `null` : pas encore compté — jamais zéro.
  final int? constateCentiemes;

  /// L'écart au coût moyen pondéré, en francs. `null` : pas compté, OU compté
  /// mais l'article n'a aucune entrée valorisée — son coût est INCONNU, pas
  /// nul (voir [LigneFeuille.sansCout]).
  final int? valoriseFrancs;

  bool get compte => constateCentiemes != null;

  int? get ecartCentiemes => constateCentiemes == null
      ? null
      : constateCentiemes! - theoriqueCentiemes;

  /// Comptée, en écart, mais sans coût connu : sa valeur est inconnue.
  bool get sansCout => compte && ecartCentiemes != 0 && valoriseFrancs == null;
}

/// La feuille de comptage et ses totaux.
final class FeuilleComptage {
  const FeuilleComptage({required this.lignes});

  final List<LigneFeuille> lignes;

  int get total => lignes.length;
  int get comptes => lignes.where((l) => l.compte).length;
  int get nonComptes => total - comptes;

  /// Les lignes comptées dont l'écart n'est pas nul.
  int get ecarts =>
      lignes.where((l) => l.compte && l.ecartCentiemes != 0).length;

  /// L'impact valorisé : la somme des écarts dont le coût est connu.
  int get impactFrancs =>
      lignes.fold(0, (somme, l) => somme + (l.valoriseFrancs ?? 0));

  /// Combien d'écarts n'ont pas pu être valorisés (aucun coût connu).
  int get ecartsSansCout => lignes.where((l) => l.sansCout).length;
}

/// Compose la feuille d'un inventaire sur [pointId] : TOUS les articles du
/// référentiel, comme `Inventaires::feuilleDeComptage` (le serveur ne retire ni
/// les archivés ni les articles journaliers), triés par libellé.
FeuilleComptage composerFeuille({
  required List<ArticleCalcul> articles,
  required List<MouvementCalcul> mouvements,
  required String pointId,
  required Map<String, ComptageBrouillon> comptages,
}) {
  final parArticle = <String, List<MouvementCalcul>>{};
  for (final m in mouvements) {
    parArticle.putIfAbsent(m.articleId, () => []).add(m);
  }

  final ordonnes = [...articles]
    ..sort((a, b) {
      final c = a.libelle.toLowerCase().compareTo(b.libelle.toLowerCase());
      return c != 0 ? c : a.id.compareTo(b.id);
    });

  return FeuilleComptage(
    lignes: [
      for (final a in ordonnes)
        _ligne(
          a,
          siens: parArticle[a.id] ?? const <MouvementCalcul>[],
          pointId: pointId,
          comptage: comptages[a.id],
        ),
    ],
  );
}

LigneFeuille _ligne(
  ArticleCalcul a, {
  required List<MouvementCalcul> siens,
  required String pointId,
  required ComptageBrouillon? comptage,
}) {
  final theorique =
      comptage?.theoriqueCentiemes ?? stockDe(siens, pointId: pointId);
  return LigneFeuille(
    articleId: a.id,
    libelle: a.libelle,
    unite: a.uniteMesure,
    theoriqueCentiemes: theorique,
    constateCentiemes: comptage?.constateCentiemes,
    valoriseFrancs: comptage == null
        ? null
        : valoriserEcart(siens, comptage.ecartCentiemes),
  );
}

/// L'écart au coût moyen pondéré courant de l'article ; `null` si aucune entrée
/// n'a été valorisée (coût INCONNU, pas nul — comme la colonne « Valeur stock »
/// de l'écran Stocks). Un écart nul vaut zéro franc, quel que soit le coût.
int? valoriserEcart(
  List<MouvementCalcul> mouvementsArticle,
  int ecartCentiemes,
) {
  if (ecartCentiemes == 0) return 0;
  if (dernierPrixAchatDe(mouvementsArticle) == null) return null;
  return valeurEnFrancs(ecartCentiemes, coutMoyenPondereDe(mouvementsArticle));
}

/// Un mouvement de régularisation à écrire pour une ligne en écart.
///
/// Comme `InventaireService::cloturer` : l'EXCÉDENT est une entrée `inventaire`
/// NON valorisée (aucun achat n'a eu lieu, recalculer le coût moyen créerait de
/// la valeur ex nihilo) ; le MANQUANT est une `perte`, pas une sortie (une
/// sortie suppose une consommation identifiée, ce qui n'est justement pas le
/// cas ici).
final class RegularisationPrevue {
  const RegularisationPrevue({
    required this.articleId,
    required this.type,
    required this.centiemes,
    required this.ecartCentiemes,
  });

  final String articleId;

  /// `inventaire` (excédent) ou `perte` (manquant).
  final TypeMouvementRegularisation type;

  /// Toujours POSITIF : la quantité du mouvement.
  final int centiemes;

  /// L'écart SIGNÉ de la ligne, pour le motif.
  final int ecartCentiemes;
}

enum TypeMouvementRegularisation { excedent, manquant }

/// Les régularisations d'une liste de lignes comptées, dans l'ordre donné ; une
/// ligne sans écart n'en produit aucune.
List<RegularisationPrevue> regularisationsDe(
  Iterable<({String articleId, int ecartCentiemes})> lignes,
) => [
  for (final l in lignes)
    if (l.ecartCentiemes != 0)
      RegularisationPrevue(
        articleId: l.articleId,
        type: l.ecartCentiemes > 0
            ? TypeMouvementRegularisation.excedent
            : TypeMouvementRegularisation.manquant,
        centiemes: l.ecartCentiemes.abs(),
        ecartCentiemes: l.ecartCentiemes,
      ),
];

/// Ce que la clôture d'un inventaire rend — `InventaireService::cloturer`.
final class BilanCloture {
  const BilanCloture({
    required this.inventaireId,
    required this.regularisations,
    required this.manquantsFrancs,
    required this.excedentsFrancs,
    required this.ecartsSansCout,
  });

  final String inventaireId;

  /// Combien de lignes en écart ont produit un mouvement.
  final int regularisations;

  /// Négatif : la valeur des manquants au coût moyen pondéré.
  final int manquantsFrancs;

  /// Positif : la valeur des excédents.
  final int excedentsFrancs;

  /// Les écarts dont le coût est inconnu : régularisés en quantité, mais NON
  /// valorisés (un zéro franc se lirait « sans conséquence »).
  final int ecartsSansCout;

  /// `ecart_valorise` du serveur : manquants (négatifs) + excédents.
  int get ecartValoriseFrancs => manquantsFrancs + excedentsFrancs;
}

/// Un inventaire clôturé, tel que l'historique le liste.
final class InventaireClos {
  const InventaireClos({
    required this.id,
    required this.date,
    required this.pointId,
    required this.pointLibelle,
    required this.articles,
    required this.regularises,
    required this.par,
  });

  final String id;

  /// `AAAA-MM-JJ`.
  final String date;
  final String pointId;

  /// `null` : le point n'est pas (ou plus) connu de ce poste.
  final String? pointLibelle;

  /// Le nombre de lignes comptées.
  final int articles;

  /// Les lignes dont l'écart n'est pas nul.
  final int regularises;

  /// Le login de qui a clôturé ; `null` pour un inventaire descendu d'un autre
  /// poste (le serveur ne descend pas ses comptes) — l'écran rend « — ».
  final String? par;
}
