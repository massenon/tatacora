/// L'onglet « Pilotage consolidé » du tableau de bord — entités SERVEUR.
///
/// Maître : `tableau-de-bord.html` l.162-227 (panneau pilotage) et
/// `pages/m11-pilotage.js`, l'ancien écran `m11-pilotage.html` que le maître a
/// lui-même retiré du menu (« Page conservée pour compatibilité »).
///
/// ## Rien n'est recalculé ici, et rien n'est stocké
///
/// M11 est hors du périmètre de réplication (PA-120) : les montants viennent
/// du serveur en **chaînes** `bcmath` et le restent jusqu'à l'affichage. Le
/// client n'en additionne aucun — un total calculé ici ne viendrait d'aucun
/// calcul du serveur. Même règle que la bande d'indicateurs et que l'état de
/// stock (PA-129, PA-126).
///
/// ## Les sources ont chacune LEURS issues
///
/// Le maître lit sept moteurs et protège chaque lecture : « si un moteur n'est
/// pas chargé ou lève, la carte affiche “indisponible” — jamais 0 F, qui se
/// lit comme un vrai chiffre » (`m11-pilotage.js`, en-tête). Ici, chaque
/// source serveur porte son propre [SourcePilotage] : une coupure sur
/// l'analytique n'efface pas les KPI comptables, et réciproquement.
library;

/// Le sort d'une lecture serveur de cet onglet.
///
/// **Quatre issues, jamais trois** (PA-120, PA-155) : reçu, refusé,
/// injoignable — et [SourceAbsente], quand le serveur a répondu mais que la
/// donnée n'existe pas encore (aucun exercice comptable ouvert). Ce n'est ni
/// une panne, ni un droit manquant : Article 7, « — » quand la donnée
/// n'existe pas, jamais un zéro. La quatrième issue de PA-155 — un compte
/// local sans jumeau serveur — se lit à l'écran via `etatJetonApiProvider`,
/// pas ici : ce fichier ne connaît pas l'authentification.
sealed class SourcePilotage<T> {
  const SourcePilotage();
}

final class SourceRecue<T> extends SourcePilotage<T> {
  const SourceRecue(this.donnee);
  final T donnee;
}

/// Le serveur a répondu, et il refuse — droit manquant (403), session (401),
/// filtre inconnu (422).
final class SourceRefusee<T> extends SourcePilotage<T> {
  const SourceRefusee({required this.motif, this.codeHttp});
  final String motif;
  final int? codeHttp;
}

/// Le serveur n'a pas répondu. Au Gîte, la coupure est l'état normal une
/// partie de la journée — jamais une erreur de l'utilisateur.
final class SourceInjoignable<T> extends SourcePilotage<T> {
  const SourceInjoignable();
}

/// Le serveur a répondu : la donnée n'existe pas (encore).
///
/// Le cas concret : `GET /comptabilite/exercices` rend une liste vide sur une
/// base neuve. Le présenter comme un refus ferait chercher un droit manquant ;
/// comme une panne, un réseau qui marche.
final class SourceAbsente<T> extends SourcePilotage<T> {
  const SourceAbsente(this.raison);
  final String raison;
}

/// L'exercice comptable retenu pour l'onglet — le plus récent du référentiel.
///
/// `GET /comptabilite/exercices` rend la liste triée par année décroissante
/// (`ReferentielComptableController::exercices`, lu le 27/08/2026) : le
/// premier est l'exercice courant. Toutes les lectures M10 de l'onglet portent
/// sur lui — `ConsulterEtatComptableRequest` n'accepte qu'un `exercice_id` et
/// un filtre de statut, **aucune borne de dates** (vérifié le 27/08/2026).
final class ExercicePilotage {
  const ExercicePilotage({required this.id, required this.annee});

  final String id;
  final int annee;
}

/// Les six chiffres comptables du bandeau `GET /comptabilite/indicateurs` —
/// chacun **lu** d'un état déjà calculé (Compte de Résultat, Bilan, Balance),
/// jamais recalculé par une agrégation parallèle (PA-121).
final class ComptaPilotage {
  const ComptaPilotage({
    required this.annee,
    required this.chiffreAffaires,
    required this.valeurAjoutee,
    required this.excedentBrut,
    required this.resultatNet,
    required this.tresorerie,
    required this.totalBilan,
    required this.equilibre,
    required this.impotNonComptabilise,
    required this.brouillons,
    required this.validees,
  });

  final int annee;

  // Chaînes `bcmath` du serveur — converties pour la mise en forme seulement.
  final String chiffreAffaires;
  final String valeurAjoutee;
  final String excedentBrut;
  final String resultatNet;
  final String tresorerie;
  final String totalBilan;

  /// ⚠ Un SEUL commutateur pour DEUX états. Le serveur combine « balance
  /// équilibrée » et « bilan équilibré » (`IndicateursComptablesResource`,
  /// lu le 27/08/2026 : « ne vérifier que la balance laisserait passer une
  /// erreur de classification de compte »). La vue en tire UNE alerte,
  /// « Comptabilité déséquilibrée » (`accueil_pwa.alertes`), et ce poste aussi
  /// (12/10/2026 ; les deux alertes de l'ancien prototype ne font plus foi).
  final bool equilibre;

  /// `true` tant que rien n'est comptabilisé en classe 89 : le résultat rendu
  /// est un résultat AVANT impôt, et l'écran le dit (PA-49 : l'intitulé dit ce
  /// qui est réellement calculé).
  final bool impotNonComptabilise;

  /// Décomptes de `repartition_statuts` — « ils disent ce qui existe, pas ce
  /// qui a été retenu » (commentaire du serveur).
  final int brouillons;
  final int validees;

  /// « Pièces saisies » de la carte M10 du maître.
  ///
  /// Somme de deux **compteurs** — pas de montants — et le registre des
  /// statuts d'écriture est fermé à deux valeurs par le schéma
  /// (`brouillon`/`validee`, RG-11) : la somme est le total par construction.
  int get pieces => brouillons + validees;

  bool get resultatNegatif => (double.tryParse(resultatNet) ?? 0) < 0;
  bool get tresorerieNegative => (double.tryParse(tresorerie) ?? 0) < 0;
  bool get excedentBrutNegatif => (double.tryParse(excedentBrut) ?? 0) < 0;
}

/// Un centre d'analyse et sa marge sur coûts directs —
/// `GET /comptabilite/analytique`.
final class CentreAnalytique {
  const CentreAnalytique({
    required this.libelle,
    required this.resultat,
    required this.nombreLignes,
  });

  final String libelle;

  /// Marge sur coûts directs, chaîne `bcmath` du serveur.
  final String resultat;

  final int nombreLignes;

  /// Pour le TRACÉ seulement : `fl_chart` exige un nombre. Aucun montant
  /// n'est réaffiché depuis cette conversion.
  double get resultatTrace => double.tryParse(resultat) ?? 0;

  /// « Le rouge n'est pas décoratif : un centre déficitaire doit se voir sans
  /// avoir à lire l'axe » (`m11-pilotage.js`, `rendreGraphes`).
  bool get deficitaire => resultatTrace < 0;
}

/// L'analytique de l'exercice — marges par centre et réserve de méthode.
final class AnalytiquePilotage {
  const AnalytiquePilotage({
    required this.repartitionStructureEffectuee,
    required this.centres,
  });

  /// `false` tant qu'aucune clé de répartition des charges de structure
  /// n'existe : les montants sont des MARGES, pas des résultats nets par
  /// filière. C'est la réserve « Charges de structure non réparties ».
  final bool repartitionStructureEffectuee;

  final List<CentreAnalytique> centres;

  /// Le maître ne trace que les centres mouvementés
  /// (`centres.filter((c) => c.nb_lignes > 0)`).
  List<CentreAnalytique> get centresActifs =>
      centres.where((c) => c.nombreLignes > 0).toList(growable: false);
}
