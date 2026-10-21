/// La fiche de stock d'un article sur une période — EF-M6-04.
///
/// ## Le seul document qui JUSTIFIE un solde
///
/// Le maître l'écrit en sous-titre : *« Stock initial, entrées, sorties et
/// stock théorique sur une période — le stock est calculé, jamais saisi. »*
/// C'est la pièce qu'on présente quand quelqu'un demande d'où vient un chiffre.
///
/// ## `coherent` n'est pas un détail d'affichage
///
/// Le calcul **vérifie** l'égalité entre le solde cumulé des lignes et le
/// stock théorique (calculé par un autre chemin), au lieu de la supposer.
/// À `false`, un mouvement a été écrit hors de `StocksDao` — donc sans le
/// contrôle de disponibilité — et **la fiche ne vaut pas justificatif**.
///
/// Le taire serait pire que de ne pas produire la fiche : on remettrait un
/// document qui a l'air d'un justificatif et n'en est pas un. Il est donc
/// affiché à l'écran **et imprimé sur le papier**.
library;

/// Une ligne de mouvement, avec le solde courant après elle.
final class LigneFiche {
  const LigneFiche({
    required this.date,
    required this.type,
    required this.motif,
    required this.entree,
    required this.sortie,
    required this.solde,
    this.par,
    this.ruptureForcee = false,
  });

  final String date;
  final String type;

  /// Le « pourquoi » du mouvement — la moitié de ce qu'une fiche justifie.
  final String motif;

  /// L'un des deux vaut `'0.00'` : une ligne est une entrée **ou** une sortie,
  /// jamais les deux. Elles sont séparées dès le calcul ; les fondre en un montant
  /// signé obligerait le lecteur à retrouver le sens.
  final String entree;
  final String sortie;

  /// Le solde **après** cette ligne. Cumulé UNE fois, par `calculerFiche` : le
  /// recalculer dans la vue donnerait une seconde arithmétique, et la fiche
  /// affichée cesserait de correspondre à la fiche imprimée.
  final String solde;

  /// Le « qui » (EF-M6-06), colonne « Par » du maître. `null` : un tiret,
  /// jamais un nom de remplacement.
  final String? par;

  /// RG-06 : sortie forcée alors que le disponible ne la couvrait pas. La
  /// fiche le dit — la confirmation promet qu'elle le fera.
  final bool ruptureForcee;
}

/// L'article auquel la fiche se rapporte.
final class ArticleFiche {
  const ArticleFiche({
    required this.id,
    required this.libelle,
    required this.unite,
    required this.cmp,
    this.stock,
  });

  final String id;
  final String libelle;
  final String unite;

  /// Coût moyen pondéré, en chaîne — comme partout (PA-134).
  final String cmp;

  /// Le stock CALCULÉ au point demandé, en chaîne — `null` quand aucun point
  /// n'a été demandé. Un stock tous points confondus présenté comme celui du bar
  /// annoncerait au comptoir des bouteilles qui dorment au magasin.
  final String? stock;
}

final class FicheStock {
  const FicheStock({
    required this.article,
    required this.debut,
    required this.fin,
    required this.stockInitial,
    required this.entrees,
    required this.sorties,
    required this.pertes,
    required this.regularisations,
    required this.stockTheorique,
    required this.valeurStockTheorique,
    required this.coherent,
    required this.pointId,
    required this.lignes,
  });

  final ArticleFiche article;
  final String debut;
  final String fin;

  final String stockInitial;
  final String entrees;
  final String sorties;
  final String pertes;

  /// Les régularisations d'inventaire, comptées à part des entrées et des
  /// sorties : elles ne viennent pas d'un flux mais d'un constat, et les
  /// mélanger ferait passer un écart d'inventaire pour un achat.
  final String regularisations;

  final String stockTheorique;
  final String valeurStockTheorique;

  /// **Vérifié, jamais supposé.** À `false`, la fiche ne vaut pas justificatif
  /// — voir l'en-tête de ce fichier.
  final bool coherent;

  /// Le point réellement appliqué, ou `null` pour tous points confondus.
  ///
  /// Une fiche restreinte à un point qui ne le dirait pas serait lue comme la
  /// fiche complète de l'article, et son solde final passerait pour le stock
  /// total (PA-119).
  final String? pointId;

  final List<LigneFiche> lignes;

  bool get estVide => lignes.isEmpty;
}

/// Une ligne de la fiche CONSOLIDÉE : celle de la fiche d'UN article, plus
/// l'article et son unité — le solde reste celui de SON article.
final class LigneFicheConsolidee {
  const LigneFicheConsolidee({
    required this.article,
    required this.unite,
    required this.ligne,
  });

  final String article;
  final String unite;
  final LigneFiche ligne;
}

/// La fiche de TOUS les articles sur une période
/// (`FicheStockService::pourTousLesArticles`, demande du PO du 06/09/2026).
///
/// ## Ce qui est totalisé, et ce qui ne l'est pas
///
/// Seule la VALEUR (en francs, unité commune) se totalise. Additionner 3 kg de
/// riz, 2 casiers de bière et 12 portions donnerait « 17 » de rien du tout : un
/// chiffre faux mais plausible. Chaque ligne garde donc SON article, SON unité
/// et le solde de SA fiche.
final class FicheConsolidee {
  const FicheConsolidee({
    required this.debut,
    required this.fin,
    required this.pointId,
    required this.articles,
    required this.articlesAvecMouvement,
    required this.valeurStockTheorique,
    required this.incoherents,
    required this.lignes,
  });

  final String debut;
  final String fin;
  final String? pointId;

  /// Les articles du référentiel, mouvementés ou non : un article dormant a
  /// bien une valeur en magasin.
  final int articles;
  final int articlesAvecMouvement;

  /// Francs entiers, en chaîne (comme `FicheStock.valeurStockTheorique`).
  final String valeurStockTheorique;

  /// Les libellés des articles dont la fiche est INCOHÉRENTE (un mouvement
  /// écrit hors de `StocksDao`) : nommés, pas noyés dans un compteur.
  final List<String> incoherents;

  /// Triées chronologiquement, tous articles confondus : la question que pose
  /// « tous les articles » est « que s'est-il passé ce jour-là ? ».
  final List<LigneFicheConsolidee> lignes;

  int get mouvements => lignes.length;
}

/// Les quatre raccourcis de période du maître (`m6-inventaires.html` l.73-76).
///
/// Ils **calculent** des bornes, ils n'en stockent pas : une période figée
/// vieillirait, et « 30 jours » finirait par désigner un mois révolu.
enum RaccourciPeriode {
  septJours('7 jours', 7),
  trenteJours('30 jours', 30),
  quatreVingtDixJours('90 jours', 90),

  /// « Ce mois » commence au premier du mois courant — pas trente jours en
  /// arrière. Un rapprochement de stock se fait sur un mois calendaire, celui
  /// qu'on déclare.
  ceMois('Ce mois', null);

  const RaccourciPeriode(this.libelle, this.jours);

  final String libelle;
  final int? jours;

  /// Les bornes, calculées depuis [aujourdhui] — injecté, jamais lu de
  /// l'horloge ici : une fonction qui lit l'heure ne se teste pas deux fois de
  /// la même façon.
  (DateTime debut, DateTime fin) bornes(DateTime aujourdhui) {
    final fin = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day);

    if (jours == null) {
      return (DateTime(aujourdhui.year, aujourdhui.month), fin);
    }

    // `jours - 1` : « 7 jours » inclut aujourd'hui, sinon la période en
    // couvrirait huit et le cumul ne correspondrait pas au libellé.
    return (fin.subtract(Duration(days: jours! - 1)), fin);
  }
}

/// « 2026-10-09 14:03:22 » -> « 09/10/2026 14:03 » : la date d'une ligne de
/// fiche telle que la vue l'écrit (`format('d/m/Y H:i')`). Une chaîne qui n'a
/// pas la forme attendue est rendue telle quelle : jamais une date inventée.
String dateHeureDeLaVue(String iso) {
  final m = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})',
  ).firstMatch(iso);
  if (m == null) return iso;
  return '${m[3]}/${m[2]}/${m[1]} ${m[4]}:${m[5]}';
}

/// Format des dates d'une fiche : `AAAA-MM-JJ` (celui du serveur, `date_format:Y-m-d`).
String formatIso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
