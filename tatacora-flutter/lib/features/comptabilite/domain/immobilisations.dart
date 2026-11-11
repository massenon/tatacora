/// Les IMMOBILISATIONS du poste et leur plan d'amortissement linéaire — le
/// calcul de `ImmobilisationService::planAmortissement()` et
/// `tableauPourExercice()` du serveur, en CENTIMES entiers (21/10/2026).
///
/// Vue Blade maîtresse (PA-183) : pwa/comptabilite/onglets/immo.blade.php
///
/// ## Le plan est CALCULÉ, jamais stocké
///
/// Comme au serveur : aucune annuité n'est écrite nulle part, le plan se
/// recalcule depuis la valeur d'origine, la durée et la date de mise en
/// service. Une VNC affichée aujourd'hui et demain sort donc de la MÊME formule.
///
/// ## La formule, au pas de bcmath près
///
/// - **annuité théorique** = valeur ÷ durée, TRONQUÉE à dix décimales de franc
///   (`bcdiv(.., 10)`) ;
/// - **première annuité** = annuité théorique × `13 − mois de mise en service`
///   ÷ 12 (prorata temporis en MOIS ENTAMÉS : une mise en service le 20 mars
///   compte mars en entier), tronquée à dix décimales, puis ARRONDIE au centime
///   (moitié vers le haut : `+0,005` puis troncature à deux décimales) ;
/// - **annuités intermédiaires** = annuité théorique arrondie au centime ;
/// - **dernière annuité** (rang = durée) = le SOLDE EXACT (valeur − cumul) : elle
///   absorbe l'arrondi, sans quoi la VNC finale ne tomberait pas à zéro ;
/// - une annuité nulle est SAUTÉE ; une annuité qui dépasserait la valeur est
///   ramenée au solde ; le plan s'arrête quand le cumul atteint la valeur.
///
/// Les dix décimales sont tenues par des [BigInt] (valeur × 10⁸ centimes-dixièmes) :
/// un entier de 64 bits déborderait dès 92 millions de francs. Un test
/// (`plan_amortissement_contre_serveur_test.dart`) confronte ce calcul au VRAI
/// service du serveur, exécuté.
library;

/// Une immobilisation : un bien, sa valeur d'origine, sa durée d'utilité.
final class Immobilisation {
  const Immobilisation({
    required this.id,
    required this.code,
    required this.libelle,
    required this.compteImmobilisation,
    required this.valeurOrigineCentimes,
    required this.dateMiseService,
    required this.dureeAnnees,
  });

  final String id;

  /// `IMMO-AAAA-NNNNN` — provisoire sur le poste tant que le serveur n'a pas
  /// rendu le sien.
  final String code;
  final String libelle;

  /// Le numéro de compte d'immobilisation (231, 244…), facultatif.
  final String? compteImmobilisation;
  final int valeurOrigineCentimes;

  /// `AAAA-MM-JJ`.
  final String dateMiseService;

  /// 1 et plus : la durée d'utilité est une estimation de l'entité, jamais un
  /// défaut.
  final int dureeAnnees;

  int get anneeMiseService => int.parse(dateMiseService.substring(0, 4));

  int get moisMiseService => int.parse(dateMiseService.substring(5, 7));

  /// `d/m/Y` de la vue (`->format('d/m/Y')`).
  String get dateMiseServiceCourte =>
      '${dateMiseService.substring(8, 10)}/${dateMiseService.substring(5, 7)}/'
      '${dateMiseService.substring(0, 4)}';
}

/// Une annuité du plan (`LigneAmortissement` du serveur).
final class LigneAmortissement {
  const LigneAmortissement({
    required this.annee,
    required this.baseCentimes,
    required this.dotationCentimes,
    required this.cumulCentimes,
    required this.vncCentimes,
    this.prorata,
  });

  final int annee;
  final int baseCentimes;
  final int dotationCentimes;
  final int cumulCentimes;
  final int vncCentimes;

  /// `7/12` sur la première annuité, `null` ailleurs.
  final String? prorata;
}

/// Le plan complet d'une immobilisation (`PlanAmortissement` du serveur).
final class PlanAmortissement {
  const PlanAmortissement({
    required this.immobilisation,
    required this.lignes,
    required this.totalCentimes,
  });

  final Immobilisation immobilisation;
  final List<LigneAmortissement> lignes;

  /// Le cumul final ; il égale la valeur d'origine (la dernière annuité
  /// absorbe l'arrondi).
  final int totalCentimes;
}

/// Une ligne du tableau d'un exercice.
final class LigneTableauImmobilisations {
  const LigneTableauImmobilisations({
    required this.immobilisation,
    required this.brutCentimes,
    required this.dotationCentimes,
    required this.cumulCentimes,
    required this.vncCentimes,
  });

  final Immobilisation immobilisation;
  final int brutCentimes;

  /// La dotation DE l'exercice.
  final int dotationCentimes;

  /// Le cumul JUSQU'À l'exercice.
  final int cumulCentimes;
  final int vncCentimes;
}

/// Le tableau des immobilisations d'un exercice, avec les totaux du pied.
final class TableauImmobilisations {
  const TableauImmobilisations({
    required this.annee,
    required this.lignes,
    required this.totalBrutCentimes,
    required this.totalDotationCentimes,
    required this.totalCumulCentimes,
    required this.totalVncCentimes,
  });

  final int annee;
  final List<LigneTableauImmobilisations> lignes;
  final int totalBrutCentimes;
  final int totalDotationCentimes;
  final int totalCumulCentimes;
  final int totalVncCentimes;
}

/// L'unité des dix décimales de franc, en centimes : 10⁸.
final BigInt _echelle = BigInt.from(100000000);

/// `0,005` franc en dix-milliardièmes de franc : 5 × 10⁷.
final BigInt _demiCentime = BigInt.from(50000000);

/// Arrondi au centime, moitié vers le haut (`arrondir()` du serveur).
int _arrondir(BigInt dixDecimales) =>
    ((dixDecimales + _demiCentime) ~/ _echelle).toInt();

/// Le plan d'amortissement linéaire de [immobilisation].
PlanAmortissement planAmortissement(Immobilisation immobilisation) {
  final valeur = immobilisation.valeurOrigineCentimes;
  final duree = immobilisation.dureeAnnees;
  final anneeDebut = immobilisation.anneeMiseService;
  // Mois entamés, mise en service comprise : janvier laisse 12 douzièmes,
  // décembre un seul.
  final moisRestants = 13 - immobilisation.moisMiseService;

  // valeur ÷ durée, tronquée à dix décimales de franc.
  final annuite = (BigInt.from(valeur) * _echelle) ~/ BigInt.from(duree);

  final lignes = <LigneAmortissement>[];
  var cumul = 0;

  for (var i = 0; i <= duree; i++) {
    var dotation = i == 0
        ? _arrondir((annuite * BigInt.from(moisRestants)) ~/ BigInt.from(12))
        : i == duree
        ? valeur - cumul
        : _arrondir(annuite);

    if (dotation <= 0) continue;
    if (cumul + dotation > valeur) dotation = valeur - cumul;

    cumul += dotation;
    lignes.add(
      LigneAmortissement(
        annee: anneeDebut + i,
        baseCentimes: valeur,
        dotationCentimes: dotation,
        cumulCentimes: cumul,
        vncCentimes: valeur - cumul,
        prorata: i == 0 ? '$moisRestants/12' : null,
      ),
    );

    if (cumul >= valeur) break;
  }

  return PlanAmortissement(
    immobilisation: immobilisation,
    lignes: lignes,
    totalCentimes: cumul,
  );
}

/// Le tableau de l'exercice [annee] (`tableauPourExercice()` du serveur) :
/// brut, dotation DE l'exercice, cumul JUSQU'À l'exercice, VNC ; les lignes
/// sont triées par code. [recherche] filtre sur le code OU le libellé (sans
/// égard à la casse) ; les totaux du pied somment les lignes affichées.
TableauImmobilisations tableauPourExercice(
  List<Immobilisation> immobilisations,
  int annee, {
  String recherche = '',
}) {
  final q = recherche.toLowerCase();
  final retenues = [
    for (final i in immobilisations)
      if (q.isEmpty ||
          i.code.toLowerCase().contains(q) ||
          i.libelle.toLowerCase().contains(q))
        i,
  ]..sort((a, b) => a.code.compareTo(b.code));

  final lignes = <LigneTableauImmobilisations>[];
  var totalBrut = 0;
  var totalDotation = 0;
  var totalCumul = 0;
  var totalVnc = 0;

  for (final i in retenues) {
    var cumul = 0;
    var dotationDeLAnnee = 0;
    for (final l in planAmortissement(i).lignes) {
      if (l.annee <= annee) cumul = l.cumulCentimes;
      if (l.annee == annee) dotationDeLAnnee = l.dotationCentimes;
    }
    final brut = i.valeurOrigineCentimes;
    final vnc = brut - cumul;
    lignes.add(
      LigneTableauImmobilisations(
        immobilisation: i,
        brutCentimes: brut,
        dotationCentimes: dotationDeLAnnee,
        cumulCentimes: cumul,
        vncCentimes: vnc,
      ),
    );
    totalBrut += brut;
    totalDotation += dotationDeLAnnee;
    totalCumul += cumul;
    totalVnc += vnc;
  }

  return TableauImmobilisations(
    annee: annee,
    lignes: lignes,
    totalBrutCentimes: totalBrut,
    totalDotationCentimes: totalDotation,
    totalCumulCentimes: totalCumul,
    totalVncCentimes: totalVnc,
  );
}

/* ====================================================================== */
/* Messages et refus                                                       */
/* ====================================================================== */

/// Les phrases de refus de la création, **reprises au mot de
/// `tatacora-api/lang/fr/comptabilite.php`** (`immobilisation_*`,
/// `compte_inconnu`), apostrophe DROITE comprise. Un test les relit par PHP.
abstract final class MessagesImmobilisations {
  static const String libelleRequis =
      "Le libellé de l'immobilisation est obligatoire.";
  static const String valeurInvalide =
      "La valeur d'origine doit être strictement positive.";
  static const String dureeRequise =
      "La durée d'utilité (en années) est obligatoire : c'est une estimation "
      "propre à l'entité (AUDCIF art. 45), jamais un barème déduit du type de "
      'bien.';
  static const String dateInvalide =
      'La date de mise en service est obligatoire et doit être une date '
      'valide.';
  static String compteInconnu(String numero) =>
      'Compte comptable inconnu : $numero. Le plan comptable ne le contient '
      'pas.';
}

/// Un refus de la création d'une immobilisation — la phrase est celle du
/// serveur.
final class RefusImmobilisation implements Exception {
  const RefusImmobilisation(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Une valeur d'origine saisie en francs entiers -> centimes, ou `null` si la
/// saisie n'est pas un entier de francs.
int? centimesDepuisFrancsSaisis(String saisie) {
  final propre = saisie.trim();
  if (!RegExp(r'^\d+$').hasMatch(propre)) return null;
  final francs = int.tryParse(propre);
  return francs == null ? null : francs * 100;
}
