/// Les règles de gestion de M6 — des FONCTIONS PURES, sans base ni widget.
///
/// @see EF-M6-01 Référentiel articles
/// @see EF-M6-03 Valorisation au coût moyen pondéré
/// @see EF-M6-04 Fiche de stock
/// @see EF-M6-05 Alerte de sous-stock
/// @see RG-06 Blocage au-delà du disponible, avec échappatoire contrôlée
/// @see RG-07 Alerte de seuil
///
/// ## Des entiers, partout
///
/// Une quantité est un entier de CENTIÈMES (`12,5` -> 1250), un coût unitaire
/// un entier de DIX-MILLIÈMES de franc (`833,3333` -> 8 333 333), un montant
/// un entier de francs. Aucun `double` n'entre dans un calcul : une somme de
/// flottants dérive, et l'écart d'inventaire qui en résulterait serait imputé à
/// tort à une perte physique (A1_MASTER_PROMPT §2.5).
///
/// Les échelles sont celles du serveur (`DECIMAL(10,2)` pour les quantités,
/// `DECIMAL(15,4)` pour le coût moyen pondéré) : le client rejoue le MÊME
/// calcul, et un test l'éprouve contre `ValorisationStockService` en exécutant
/// PHP — une formule recopiée à la main ne vérifierait qu'elle-même.
///
/// ## Le stock n'est jamais une donnée
///
/// Il est la somme signée des mouvements. Le coût moyen pondéré est REJOUÉ
/// depuis les entrées valorisées, dans l'ordre d'écriture — il n'est stocké
/// nulle part, donc il ne peut diverger de rien.
library;

import 'entities/etat_stock.dart';
import 'entities/fiche_stock.dart';
import 'entities/mouvement_stock.dart';

/// 1 unité = 0,01 de la quantité du référentiel.
const int echelleQuantite = 100;

/// 1 unité = 0,0001 franc.
const int echelleCout = 10000;

/* ====================================================================== */
/* Conversions texte <-> entiers                                           */
/* ====================================================================== */

final _formeDecimale = RegExp(r'^(\d+)(?:[.,](\d+))?$');

int? _lire(String saisie, int decimalesMax) {
  final m = _formeDecimale.firstMatch(saisie.trim());
  if (m == null) return null;
  final entiere = m.group(1)!;
  final decimale = m.group(2) ?? '';
  if (decimale.length > decimalesMax) return null;

  final complete = decimale.padRight(decimalesMax, '0');
  return int.parse(entiere) * _puissance10(decimalesMax) +
      (complete.isEmpty ? 0 : int.parse(complete));
}

int _puissance10(int n) {
  var r = 1;
  for (var i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}

/// « 12 », « 12,5 » ou « 12.50 » -> 1250 ; `null` si la forme n'est pas un
/// nombre positif d'au plus DEUX décimales. Jamais d'arrondi : une troisième
/// décimale est refusée, pas tronquée — l'écran dirait un autre chiffre que
/// celui qui est écrit.
int? lireCentiemes(String saisie) => _lire(saisie, 2);

/// Même chose pour un coût : au plus QUATRE décimales.
int? lireCout(String saisie) => _lire(saisie, 4);

String _ecrire(int valeur, int decimales) {
  final signe = valeur < 0 ? '-' : '';
  final absolu = valeur.abs();
  final base = _puissance10(decimales);
  final entiere = absolu ~/ base;
  final reste = (absolu % base).toString().padLeft(decimales, '0');
  return '$signe$entiere.$reste';
}

/// 1250 -> « 12.50 ». Deux décimales toujours : c'est la forme du serveur, et
/// une colonne de quantités doit s'aligner.
String ecrireCentiemes(int centiemes) => _ecrire(centiemes, 2);

/// 8 333 333 -> « 833.3333 ».
String ecrireCout(int dixMilliemes) => _ecrire(dixMilliemes, 4);

/// Un montant entier de francs, en chaîne (« 10417 »).
String ecrireFrancs(int francs) => '$francs';

/// `quantité × coût`, arrondi au franc entier le plus proche (moitié
/// éloignée de zéro). [centiemes] × [coutDixMilliemes] est exprimé en
/// millionièmes de franc.
///
/// Arrondi PAR LIGNE : la valeur totale du stock est la somme des valeurs
/// affichées, de sorte qu'un lecteur qui additionne la colonne retrouve le
/// total. (Le serveur, lui, tronque au centime : l'écart est de quelques
/// francs sur un stock entier, et il est dit ici plutôt que découvert.)
int valeurEnFrancs(int centiemes, int coutDixMilliemes) {
  final produit = centiemes * coutDixMilliemes;
  final signe = produit < 0 ? -1 : 1;
  return signe * ((produit.abs() + 500000) ~/ 1000000);
}

/* ====================================================================== */
/* Mouvements et soldes                                                    */
/* ====================================================================== */

/// Un mouvement tel que les calculs le voient : des entiers, aucune ligne
/// de base.
final class MouvementCalcul {
  const MouvementCalcul({
    required this.id,
    required this.articleId,
    required this.pointId,
    required this.type,
    required this.centiemes,
    required this.ordre,
    required this.date,
    this.motif = '',
    this.auteur,
    this.coutDixMilliemes,
    this.ruptureForcee = false,
  });

  final String id;
  final String articleId;
  final String pointId;
  final TypeMouvement type;

  /// Positive pour `entree` / `sortie` / `perte`, SIGNÉE pour `inventaire`.
  final int centiemes;

  /// Le rang d'écriture. C'est lui — pas la date — qui ordonne le rejeu.
  final int ordre;
  final DateTime date;

  /// Le « pourquoi » (EF-M6-06) — obligatoire à l'écriture.
  final String motif;

  /// Le « qui », tel qu'il s'affiche. `null` si l'auteur n'est plus lisible :
  /// un tiret, jamais un nom de remplacement.
  final String? auteur;

  /// Le coût d'achat unitaire de cette entrée, `null` si elle n'en porte pas.
  final int? coutDixMilliemes;
  final bool ruptureForcee;
}

/// Ce que le mouvement ajoute (+) ou retranche (−) au stock.
///
/// La convention de signe du serveur (`StockTheoriqueService::EXPRESSION_SOLDE`)
/// : `entree` et `inventaire` ajoutent, `sortie` et `perte` retranchent.
int variation(TypeMouvement type, int centiemes) =>
    type.ajouteAuStock ? centiemes : -centiemes;

/// Le stock d'un article : la somme signée de ses mouvements, restreinte à un
/// point si [pointId] est donné. Tous points confondus sinon.
int stockDe(Iterable<MouvementCalcul> mouvements, {String? pointId}) {
  var total = 0;
  for (final m in mouvements) {
    if (pointId != null && m.pointId != pointId) continue;
    total += variation(m.type, m.centiemes);
  }
  return total;
}

/// Le coût moyen pondéré APRÈS une entrée valorisée — la formule exacte de
/// `ValorisationStockService::moyennePonderee`, en entiers.
///
///     CMP = (stock avant × CMP avant + entrée × coût) / (stock avant + entrée)
///
/// Un stock de départ nul ou NÉGATIF (rupture forcée, premier achat) fait
/// retomber le CMP sur le seul coût de l'entrée : pondérer par une quantité
/// négative inverserait le résultat. La division TRONQUE, comme `bcdiv`.
int moyennePonderee({
  required int quantiteAvant,
  required int cmpAvant,
  required int quantiteEntree,
  required int coutEntree,
}) {
  if (quantiteAvant <= 0) return coutEntree;

  final total = quantiteAvant + quantiteEntree;
  if (total == 0) return cmpAvant;

  return (quantiteAvant * cmpAvant + quantiteEntree * coutEntree) ~/ total;
}

/// Les mouvements d'UN article, dans l'ordre d'écriture.
List<MouvementCalcul> _dansLOrdre(Iterable<MouvementCalcul> mouvements) =>
    mouvements.toList()..sort((a, b) => a.ordre.compareTo(b.ordre));

/// Le coût moyen pondéré courant d'un article, REJOUÉ depuis ses mouvements.
///
/// Seules les entrées qui portent un coût le modifient : un transfert entre
/// points (entrée sans coût) ne revalorise rien, et une sortie est valorisée
/// au CMP du moment sans le changer. Le stock « avant » est celui de TOUS les
/// points, comme `ValorisationStockService`.
int coutMoyenPondereDe(Iterable<MouvementCalcul> mouvements) {
  var stock = 0;
  var cmp = 0;
  for (final m in _dansLOrdre(mouvements)) {
    final cout = m.coutDixMilliemes;
    if (m.type == TypeMouvement.entree && cout != null && m.centiemes > 0) {
      cmp = moyennePonderee(
        quantiteAvant: stock,
        cmpAvant: cmp,
        quantiteEntree: m.centiemes,
        coutEntree: cout,
      );
    }
    stock += variation(m.type, m.centiemes);
  }
  return cmp;
}

/// Le DERNIER prix d'achat connu : le coût de la dernière entrée valorisée.
/// `null` si l'article n'a jamais été réceptionné — pas zéro, qui se lirait
/// « reçu gratuitement ».
///
/// ⚠ Ce n'est PAS le coût moyen pondéré. L'écart entre les deux est ce que la
/// colonne « Valeur d'achat » montre (la dérive) : y recopier le CMP la
/// rendrait nulle par construction.
///
/// Écart nommé avec le serveur : sa colonne `prix_achat` est un
/// `DECIMAL(15,2)` et arrondit au centime le coût saisi à quatre décimales. Ce
/// poste garde le coût EXACT de l'entrée — il n'y a pas de colonne à arrondir —,
/// donc la dérive peut différer d'un point sur un prix à fraction de centime.
int? dernierPrixAchatDe(Iterable<MouvementCalcul> mouvements) {
  int? prix;
  for (final m in _dansLOrdre(mouvements)) {
    final cout = m.coutDixMilliemes;
    if (m.type == TypeMouvement.entree && cout != null) prix = cout;
  }
  return prix;
}

/// La dérive du CMP contre le dernier prix d'achat, en pourcentage ENTIER —
/// `null` quand elle n'est pas mesurable, jamais zéro.
///
/// Même formule que `Article::deriveCoutMoyenPondere` : le quotient est tronqué
/// à six décimales, puis le pourcentage arrondi (moitié éloignée de zéro).
int? deriveCoutMoyenPondere({required int cmp, required int? prixAchat}) {
  if (prixAchat == null || prixAchat <= 0) return null;

  final ratio6 = ((cmp - prixAchat) * 1000000) ~/ prixAchat;
  final signe = ratio6 < 0 ? -1 : 1;
  return signe * ((ratio6.abs() + 5000) ~/ 10000);
}

/* ====================================================================== */
/* RG-06 — le contrôle de disponibilité                                    */
/* ====================================================================== */

/// Ce que le contrôle de disponibilité conclut pour une sortie ou une perte.
enum IssueSortie {
  /// Le disponible couvre la demande.
  couverte,

  /// Il ne la couvre pas : une confirmation explicite est requise (RG-06).
  ruptureAConfirmer,

  /// Il ne la couvre pas et l'utilisateur a assumé le forçage.
  ruptureForcee,
}

/// RG-06 : une sortie qui dépasse le DISPONIBLE DU POINT est une demande de
/// confirmation, jamais une erreur définitive. La refuser sèchement
/// empêcherait de servir un client au comptoir en attendant une
/// régularisation ; l'accepter sans demander produirait des stocks négatifs
/// que personne n'a décidés.
IssueSortie controlerSortie({
  required int disponible,
  required int demande,
  required bool forcage,
}) {
  if (disponible >= demande) return IssueSortie.couverte;
  return forcage ? IssueSortie.ruptureForcee : IssueSortie.ruptureAConfirmer;
}

/// La phrase de RG-06, mot pour mot celle de `lang/fr/stocks.php`
/// (`stocks.rupture`) : un test la relit sur le fichier PHP. Les deux chiffres
/// sont ceux que le contrôle a réellement comparés.
String messageRupture({required String disponible, required String demande}) =>
    'Stock insuffisant : $disponible disponible, $demande demandé. '
    'Une validation explicite est requise pour forcer la sortie.';

/* ====================================================================== */
/* L'état — la projection de lecture                                       */
/* ====================================================================== */

/// Un article tel que les calculs le voient.
final class ArticleCalcul {
  const ArticleCalcul({
    required this.id,
    required this.libelle,
    required this.categorie,
    required this.uniteMesure,
    required this.seuilCentiemes,
    required this.suivi,
    this.pointStockageId,
  });

  final String id;
  final String libelle;

  /// `null` = non renseignée (jamais la chaîne vide).
  final String? categorie;
  final String uniteMesure;
  final int seuilCentiemes;
  final SuiviArticle suivi;
  final String? pointStockageId;

  bool get estSuiviEnStock => suivi == SuiviArticle.permanent;
}

/// La fenêtre du compteur de mouvements récents, en jours (`FENETRE_MOUVEMENTS`).
const int fenetreMouvementsJours = 30;

/// L'état consolidé — mêmes filtres et mêmes compteurs que
/// `ConsultationStockService::etatConsolide`.
///
/// Trois règles qui viennent du serveur et que le client reprend telles
/// quelles, parce que chacune a une raison :
///
///  * les compteurs d'alarme (`sousSeuil`, `rupture`) sont relevés AVANT le
///    filtre d'affichage : masquer les articles sains ne change pas le nombre
///    d'articles à réapprovisionner ;
///  * un article JOURNALIER n'entre dans aucune alarme : son stock n'est pas
///    tenu, son solde vaut zéro, et il serait compté en rupture à perpétuité ;
///  * le seuil est franchi quand le stock lui est inférieur OU ÉGAL — alerter
///    seulement en dessous laisserait passer le moment exact où il est atteint.
EtatStock calculerEtat({
  required List<ArticleCalcul> articles,
  required List<MouvementCalcul> mouvements,
  required DateTime maintenant,
  required Map<String, String> libellesPoints,
  String? pointId,
  EtatStockFiltre filtre = EtatStockFiltre.tous,
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

  final lignes = <LigneStock>[];
  var valeurTotale = 0;
  var sousSeuil = 0;
  var rupture = 0;
  var permanents = 0;
  var journaliers = 0;
  var sansValorisation = 0;

  for (final a in ordonnes) {
    final siens = parArticle[a.id] ?? const <MouvementCalcul>[];
    final stock = stockDe(siens, pointId: pointId);
    final cmp = coutMoyenPondereDe(siens);
    final prix = dernierPrixAchatDe(siens);
    final valeur = a.estSuiviEnStock ? valeurEnFrancs(stock, cmp) : 0;

    if (a.estSuiviEnStock) {
      permanents++;
    } else {
      journaliers++;
    }

    final estSousSeuil = a.estSuiviEnStock && stock <= a.seuilCentiemes;
    final estRupture = a.estSuiviEnStock && stock <= 0;
    if (estSousSeuil) sousSeuil++;
    if (estRupture) rupture++;
    // Du stock, mais jamais un coût : sa valeur n'est pas zéro, elle est
    // INCONNUE. (Compté sur tout le référentiel de la portée, comme les
    // alarmes : filtrer l'affichage ne rend pas le coût connu.)
    if (a.estSuiviEnStock && stock != 0 && prix == null) sansValorisation++;

    if (filtre == EtatStockFiltre.sousSeuil && !estSousSeuil) continue;

    final rattache = a.pointStockageId;
    lignes.add(
      LigneStock(
        id: a.id,
        libelle: a.libelle,
        categorie: a.categorie,
        uniteMesure: a.uniteMesure,
        seuilAlerte: ecrireCentiemes(a.seuilCentiemes),
        coutMoyenPondere: ecrireCout(cmp),
        stock: ecrireCentiemes(stock),
        valeurStock: ecrireFrancs(valeur),
        portee: pointId == null
            ? 'tous points'
            : (libellesPoints[pointId] ?? pointId),
        suivi: a.suivi,
        pointStockageId: rattache,
        pointLibelle: rattache == null
            ? null
            : (libellesPoints[rattache] ?? rattache),
        prixAchat: prix == null ? null : ecrireCout(prix),
        deriveCmp: deriveCoutMoyenPondere(cmp: cmp, prixAchat: prix),
      ),
    );
    valeurTotale += valeur;
  }

  final debutFenetre = maintenant.subtract(
    const Duration(days: fenetreMouvementsJours),
  );
  final recents = mouvements.where(
    (m) =>
        (pointId == null || m.pointId == pointId) &&
        !m.date.isBefore(debutFenetre),
  );

  return EtatStock(
    kpis: KpisStock(
      references: lignes.length,
      sousSeuil: sousSeuil,
      rupture: rupture,
      valeurStock: ecrireFrancs(valeurTotale),
      mouvements30Jours: recents.length,
      permanents: permanents,
      journaliers: journaliers,
      sansValorisation: sansValorisation,
    ),
    lignes: lignes,
    arreteAu: formaterInstant(maintenant),
  );
}

/// « 09/10/2026 14:03 » — l'instant où ce poste a arrêté ses comptes.
String formaterInstant(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/${d.year} '
    '${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}';

/* ====================================================================== */
/* La fiche de stock                                                       */
/* ====================================================================== */

DateTime _jour(DateTime d) => DateTime(d.year, d.month, d.day);

/// Le solde à la veille de [date] — le stock initial d'une période.
int soldeAvant(
  Iterable<MouvementCalcul> mouvements,
  DateTime date, {
  String? pointId,
}) {
  final borne = _jour(date);
  return stockDe(
    mouvements.where((m) => m.date.isBefore(borne)),
    pointId: pointId,
  );
}

/// La fiche d'un article sur une période — EF-M6-04.
///
///     Stock initial (à la veille du début)
///   + Entrées + Régularisations − Sorties − Pertes
///   = Stock théorique en fin de période
///
/// ⚠ `coherent` n'est PAS supposé : le solde cumulé des lignes est comparé au
/// stock théorique calculé par un AUTRE chemin (`soldeAvant` le lendemain de la
/// fin). Un prédicat dérivé du champ qu'il vérifie ne vérifierait rien
/// (piège 12) ; ici les deux chemins ne partagent que les mouvements.
FicheStock calculerFiche({
  required ArticleFiche article,
  required int cmp,
  required List<MouvementCalcul> mouvements,
  required DateTime debut,
  required DateTime fin,
  String? pointId,
}) {
  final portee = pointId == null
      ? mouvements
      : mouvements.where((m) => m.pointId == pointId).toList();

  final initial = soldeAvant(portee, debut);
  final debutJ = _jour(debut);
  final lendemain = _jour(fin).add(const Duration(days: 1));

  final dansLaPeriode =
      portee
          .where((m) => !m.date.isBefore(debutJ) && m.date.isBefore(lendemain))
          .toList()
        ..sort((a, b) => a.ordre.compareTo(b.ordre));

  var solde = initial;
  var entrees = 0;
  var sorties = 0;
  var pertes = 0;
  var regularisations = 0;
  final lignes = <LigneFiche>[];

  for (final m in dansLaPeriode) {
    switch (m.type) {
      case TypeMouvement.entree:
        entrees += m.centiemes;
      case TypeMouvement.sortie:
        sorties += m.centiemes;
      case TypeMouvement.perte:
        pertes += m.centiemes;
      case TypeMouvement.inventaire:
        regularisations += m.centiemes;
    }
    final delta = variation(m.type, m.centiemes);
    solde += delta;

    lignes.add(
      LigneFiche(
        date: formaterInstantIso(m.date),
        type: m.type.libelle,
        motif: m.motif,
        entree: ecrireCentiemes(m.type.ajouteAuStock ? m.centiemes : 0),
        sortie: ecrireCentiemes(m.type.ajouteAuStock ? 0 : m.centiemes),
        solde: ecrireCentiemes(solde),
        par: m.auteur,
        ruptureForcee: m.ruptureForcee,
      ),
    );
  }

  final theorique = soldeAvant(portee, lendemain);

  return FicheStock(
    article: ArticleFiche(
      id: article.id,
      libelle: article.libelle,
      unite: article.unite,
      cmp: ecrireCout(cmp),
      stock: pointId == null ? null : ecrireCentiemes(stockDe(portee)),
    ),
    debut: formatIso(debut),
    fin: formatIso(fin),
    stockInitial: ecrireCentiemes(initial),
    entrees: ecrireCentiemes(entrees),
    sorties: ecrireCentiemes(sorties),
    pertes: ecrireCentiemes(pertes),
    regularisations: ecrireCentiemes(regularisations),
    stockTheorique: ecrireCentiemes(theorique),
    valeurStockTheorique: ecrireFrancs(valeurEnFrancs(theorique, cmp)),
    coherent: solde == theorique,
    pointId: pointId,
    lignes: lignes,
  );
}

/// « 2026-10-09 14:03:22 » — la date d'une ligne de fiche.
String formaterInstantIso(DateTime d) =>
    '${formatIso(d)} '
    '${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}:'
    '${d.second.toString().padLeft(2, '0')}';
