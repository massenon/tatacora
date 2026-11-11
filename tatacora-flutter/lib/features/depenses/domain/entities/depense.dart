import '../categories_depense.dart';
import '../recu_depense.dart';

/// Une ligne d'achat — libellé, compte de charge, catégorie, prix.
///
/// Les trois classements sont des **chaînes figées**, pas des valeurs du
/// registre : ils ont été recopiés à l'enregistrement et disent ce qui a été
/// acheté ce jour-là. Le registre, lui, dit ce qu'on propose aujourd'hui.
final class LigneDepense {
  const LigneDepense({
    required this.id,
    required this.libelle,
    required this.compteCharge,
    required this.nature,
    required this.famille,
    required this.montant,
  });

  final String id;
  final String libelle;

  /// Le numéro SYSCOHADA, tel qu'il a été saisi.
  final String compteCharge;

  final String nature;
  final String famille;

  /// Prix en francs CFA — entier, toujours strictement positif : une ligne à
  /// zéro n'est jamais enregistrée (voir [RefusDepense]).
  final int montant;

  /// « 6011 · Achats de marchandises » — la forme de la vue dans la colonne
  /// « Charge (SYSCOHADA) ».
  ///
  /// Un compte absent du plan ET de l'ancien registre rend « — » après son
  /// numéro, jamais un libellé approché.
  String compteAffiche(LibellesDesComptes libelles) =>
      '$compteCharge · ${libelles.de(compteCharge) ?? tiretAbsence}';
}

/// Le tiret de l'Article 7 — « — » et « 0 » ne disent pas la même chose.
///
/// Un seul endroit pour tout M10 : deux écritures différentes du même « rien »
/// se liraient comme deux états.
const String tiretAbsence = '—';

/// Une dépense courante : une sortie d'argent, une ou plusieurs lignes d'achat.
final class Depense {
  const Depense({
    required this.id,
    required this.dateTransaction,
    required this.tresorerie,
    required this.libelle,
    required this.lignes,
    required this.saisieLe,
    this.ecritureId,
    this.numeroPiece,
    this.ecritureRefus,
    this.recueDuServeur = false,
    this.posteOrigine,
    this.recu,
  });

  /// Le reçu en image (lot L4), ou `null` : « sans reçu ». Son ÉTAT ne se dit
  /// que de ce que le serveur a accusé (voir [StatutRecu]).
  final RecuDepense? recu;

  final String id;
  final DateTime dateTransaction;

  /// Lot F4 (17/10/2026) : la dépense a été saisie sur un AUTRE poste (ou au
  /// serveur) et DESCENDUE ici. Sa pièce existe au serveur, pas sur ce poste
  /// (décision Q1 du PO) : elle ne se rattrape JAMAIS ici — elle serait
  /// comptée deux fois. Lu de `origines_documents_local`.
  final bool recueDuServeur;

  /// Le poste qui l'a saisie (`null` : saisie au serveur, ou sur ce poste).
  final String? posteOrigine;

  /// La pièce de cette dépense est tenue par le SERVEUR, pas par ce poste.
  bool get pieceAuServeur => recueDuServeur && ecritureId == null;

  /// `null` si la valeur stockée n'est plus au registre — jamais un repli sur
  /// « Caisse », qui gonflerait l'indicateur des espèces.
  final TresorerieDepense? tresorerie;

  final String libelle;
  final List<LigneDepense> lignes;
  final DateTime saisieLe;

  /// La ligne de TRESORERIE de la pièce comptable, `null` tant qu'aucune pièce
  /// n'existe (dépense saisie avant la v16, ou rattrapage refusé).
  final String? ecritureId;

  /// Le numéro de la pièce (`CAI-2026-00007`), LU de l'écriture — jamais
  /// recopié. `null` quand [ecritureId] l'est.
  final String? numeroPiece;

  /// La raison du dernier rattrapage refusé, pour l'infobulle de la pastille.
  /// Elle ne décide de rien : l'état se lit de [ecritureId].
  final String? ecritureRefus;

  /// Vrai si une pièce comptable existe réellement pour cette dépense.
  ///
  /// Lu de la CLÉ ÉTRANGÈRE, jamais d'un drapeau ni de [ecritureRefus] : une
  /// dépense antérieure à la v16 n'a ni l'un ni l'autre et se serait affichée
  /// comme comptabilisée (`Depense::estComptabilisee` du serveur).
  bool get estComptabilisee => ecritureId != null;

  /// **Le montant décaissé.** Il ne se saisit pas : c'est la somme des lignes.
  ///
  /// Calculé à chaque lecture plutôt que stocké — une colonne dénormalisée
  /// deviendrait fausse au premier correctif de ligne, et la règle n° 2 du
  /// dépôt veut que toute valeur calculable soit affichée, jamais saisie.
  ///
  /// Somme d'entiers : aucun flottant n'apparaît, à aucune étape.
  int get montantTotal =>
      lignes.fold<int>(0, (total, ligne) => total + ligne.montant);

  /// Les natures distinctes, pour la colonne « Nature ».
  ///
  /// Le maître n'affiche qu'une nature par ligne de tableau parce que sa
  /// maquette n'en produisait qu'une. Une dépense qui en porte plusieurs rend
  /// ses valeurs distinctes dans la même cellule, plutôt que d'en taire
  /// silencieusement toutes sauf une.
  String get naturesAffichees => _distinctes(lignes.map((l) => l.nature));

  /// Les familles distinctes de la pièce — « Marché », « Services », ou les
  /// deux : un marché du matin peut mêler des tomates et un transport.
  Set<String> get familles => lignes.map((l) => l.famille).toSet();

  /// Le total des lignes d'une famille. C'est ce que somment les deux
  /// indicateurs du maître : chaque ligne compte dans SA famille, jamais la
  /// pièce entière dans celle de sa première ligne.
  int totalDeLaFamille(FamilleDepense famille) => lignes
      .where((l) => l.famille == famille.libelle)
      .fold<int>(0, (total, ligne) => total + ligne.montant);

  static String _distinctes(Iterable<String> valeurs) {
    final vues = <String>[];
    for (final v in valeurs) {
      if (v.trim().isEmpty || vues.contains(v)) continue;
      vues.add(v);
    }
    return vues.isEmpty ? tiretAbsence : vues.join(', ');
  }
}

/// Ce qu'une ligne vaut **avant** enregistrement — la saisie, pas la donnée.
///
/// Distincte de [LigneDepense] : celle-ci n'a pas encore d'identifiant, et sa
/// nature est une valeur du registre. C'est à l'enregistrement que la nature et
/// sa famille deviennent des chaînes figées.
final class SaisieLigneDepense {
  const SaisieLigneDepense({
    required this.libelle,
    required this.compteCharge,
    required this.nature,
    required this.montant,
  });

  final String libelle;
  final String compteCharge;
  final NatureDepense nature;

  /// En francs CFA. Une valeur nulle ou négative est **refusée**, jamais
  /// ramenée à autre chose : elle produirait une imputation qui affirme un
  /// achat sans argent.
  final int montant;
}

/// Le refus d'une saisie, dit en français à l'opérateur.
///
/// Registre **fermé** de causes : chacune est locale et corrigible à l'écran.
/// Aucune ne vient d'un serveur — il n'y en a pas — et aucun message technique
/// n'atteint l'utilisateur.
final class RefusDepense implements Exception {
  const RefusDepense(this.message);

  /// Une dépense sans ligne n'existe pas.
  const RefusDepense.sansLigne()
    : message = 'Une dépense porte au moins une ligne.';

  /// Le rang est **humain** : la première ligne est « Ligne 1 », jamais
  /// « lignes.0 », qui ne désigne rien pour un opérateur.
  RefusDepense.libelleLigne(int rang)
    : message = 'Ligne $rang : le libellé de l\'achat est obligatoire.';

  RefusDepense.compteLigne(int rang)
    : message = 'Ligne $rang : choisissez la catégorie de charges.';

  RefusDepense.compteInconnu(int rang)
    : message = 'Ligne $rang : ce compte n\'existe pas au plan comptable.';

  /// La « Catégorie de dépenses » de la ligne — distincte de la catégorie des
  /// charges, qui est un compte SYSCOHADA. Les deux listes sont côte à côte
  /// dans la modale : le refus doit dire laquelle manque.
  RefusDepense.natureLigne(int rang)
    : message = 'Ligne $rang : choisissez la catégorie de dépenses.';

  RefusDepense.montantLigne(int rang)
    : message = 'Ligne $rang : le prix est obligatoire.';

  RefusDepense.montantNul(int rang)
    : message =
          'Ligne $rang : un prix à zéro ne s\'enregistre pas. Retirez la '
          'ligne, ou saisissez son montant.';

  /// Le rattrapage cible une dépense qui n'est plus sur ce poste.
  /// Lot F4 : une dépense descendue d'un autre poste ne se rattrape pas ici.
  const RefusDepense.recueDuServeur()
    : message =
          'Cette dépense vient d\'un autre poste : sa pièce est passée au '
          'serveur. La comptabiliser ici la compterait deux fois.';

  const RefusDepense.introuvable()
    : message = 'Cette dépense n\'existe plus sur ce poste.';

  /// Une trésorerie hors registre : on ne devine pas le compte à créditer
  /// (`depenses.tresorerie_inconnue` du serveur : « caisse », « momo » et
  /// « banque » sont les seules admises).
  const RefusDepense.tresorerieInconnue()
    : message =
          'Trésorerie inconnue. Les trésoreries admises sont « caisse », '
          '« momo » et « banque ».';

  const RefusDepense.libelleManquant()
    : message = 'Le libellé de la dépense est obligatoire.';

  /// « D'où l'argent est sorti » — sans elle, la dépense ne dit pas quelle
  /// caisse a été vidée, et l'indicateur « Caisse » ne veut plus rien dire.
  const RefusDepense.tresorerieManquante()
    : message = 'Choisissez le compte de trésorerie.';

  final String message;

  @override
  String toString() => message;
}
