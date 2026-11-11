/// Le tableau des flux de trésorerie (TAFIRE) et les notes annexes, calculés
/// sur le poste — sans serveur. Fonctions PURES en centimes entiers, réplique de
/// `TafireService` et `NotesAnnexesService` (confrontées au serveur par
/// `tafire_notes_contre_serveur_test.dart`) : MÊMES rubriques, MÊMES signes.
///
/// DÉFINITION FINALE du TAFIRE (10/11/2026, avis de l'expert-comptable, miroir
/// exact de `TafireService`) : le résultat est celui de N SEUL
/// (`bilan.resultatExerciceCentimes`, jamais le 131/139 reporté de N-1), et tout
/// montant de bilan est une VARIATION (solde de clôture − solde d'ouverture,
/// `reportOuverture`).
///
///   CAFG = résultat de N + DOTATIONS (681, 687, 691, 697, 85)
///          − REPRISES (781, 787, 791, 797, 798, 86) + VNC cédées (81)
///          − produits des cessions (82) − quote-part des subventions
///          d'investissement virée au résultat (799, produit non encaissé)
///   Exploitation = CAFG − variation du BFR (le 465 n'y est pas)
///   Investissement = produits des cessions − acquisitions, acquisitions =
///          variation des immobilisations NETTES + dotations aux AMORTISSEMENTS
///          (681, 852) + VNC − reprises sur immobilisations (781, 787, 798, 862)
///   Financement = apports (101, 102, 103, 105, 106, 109 + subventions
///          d'investissement REÇUES : variation du 14 + quote-part 799)
///          + emprunts (16 et 17) + dettes liées à des participations (18, ligne
///          distincte) − dividendes versés, dividendes versés = −(variation des
///          capitaux propres hors résultat : compte de l'exploitant 104, 11, 12,
///          13 + variation des dividendes à payer 465)
///   Variation de trésorerie = les trois flux = variation constatée aux classes 5.
///
/// Le compte 19 (provision financière pour risques et charges) et le 15
/// (provisions réglementées) n'entrent dans AUCUN flux : leur variation passe par
/// les dotations et les reprises de la CAFG. L'affectation du résultat de N-1 et
/// les prélèvements de l'exploitant sont des mouvements de capitaux propres lus
/// PAR COMPTES (classe 1), pas du résultat de N.
library;

import 'etats_financiers.dart';
import 'grand_livre_analytique.dart';

/// `RubriquesTafire` du serveur — relus de `RubriquesTafire.php` par un test.
abstract final class RubriquesTafire {
  // Dotations (charges non décaissées réintégrées à la CAFG) et reprises
  // (produits non encaissés déduits).
  static const dotations = ['681', '687', '691', '697', '85'];
  static const reprises = ['781', '787', '791', '797', '798', '86'];
  // La part dont la contrepartie est un AMORTISSEMENT ou une immobilisation : seule
  // elle se compense dans les acquisitions (une dotation aux PROVISIONS n'a aucune
  // contrepartie d'actif).
  static const dotationsAmortissements = ['681', '852'];
  static const reprisesSurImmobilisations = ['781', '787', '798', '862'];
  // Quote-part des subventions d'investissement virée au résultat.
  static const quotePartSubventions = ['799'];
  static const valeurComptableCessions = ['81'];
  static const produitsCessions = ['82'];
  // Le 104 (compte de l'exploitant) n'est PAS un apport : voir
  // `autresCapitauxPropres`.
  static const apportsCapital = [
    '101',
    '102',
    '103',
    '105',
    '106',
    '109',
    '14',
  ];
  static const autresCapitauxPropres = ['104', '11', '12', '13'];
  // Les « emprunts » : 16 et 17 SEULS (le 19 est une provision).
  static const dettesFinancieres = ['16', '17'];
  static const dettesParticipations = ['18'];
  static const dividendesAPayer = ['465'];
}

/// Le TAFIRE d'un exercice.
final class TafireEtat {
  const TafireEtat({
    required this.resultatExerciceCentimes,
    required this.dotationsCentimes,
    required this.reprisesCentimes,
    required this.valeurComptableCessionsCentimes,
    required this.quotePartSubventionsCentimes,
    required this.cafgCentimes,
    required this.produitsCessionsCentimes,
    required this.augmentationCapitalCentimes,
    required this.variationEmpruntsCentimes,
    required this.variationDettesParticipationsCentimes,
    required this.totalRessourcesCentimes,
    required this.acquisitionsCentimes,
    required this.variationAutresCapitauxPropresCentimes,
    required this.variationDividendesAPayerCentimes,
    required this.dividendesVersesCentimes,
    required this.totalEmploisCentimes,
    required this.fluxExploitationCentimes,
    required this.fluxInvestissementCentimes,
    required this.fluxFinancementCentimes,
    required this.variationStocksCentimes,
    required this.variationCreancesCentimes,
    required this.variationDettesCentimes,
    required this.variationBfrCentimes,
    required this.variationCalculeeCentimes,
    required this.variationReelleCentimes,
  });

  final int resultatExerciceCentimes;
  final int dotationsCentimes;
  final int reprisesCentimes;
  final int valeurComptableCessionsCentimes;
  final int quotePartSubventionsCentimes;
  final int cafgCentimes;
  final int produitsCessionsCentimes;
  final int augmentationCapitalCentimes;
  final int variationEmpruntsCentimes;
  final int variationDettesParticipationsCentimes;
  final int totalRessourcesCentimes;
  final int acquisitionsCentimes;
  final int variationAutresCapitauxPropresCentimes;
  final int variationDividendesAPayerCentimes;
  final int dividendesVersesCentimes;
  final int totalEmploisCentimes;
  final int fluxExploitationCentimes;
  final int fluxInvestissementCentimes;
  final int fluxFinancementCentimes;
  final int variationStocksCentimes;
  final int variationCreancesCentimes;
  final int variationDettesCentimes;
  final int variationBfrCentimes;
  final int variationCalculeeCentimes;
  final int variationReelleCentimes;

  int get ecartCentimes => variationCalculeeCentimes - variationReelleCentimes;

  /// Le contrôle de cohérence : variation calculée = variation réelle.
  bool get coherent => ecartCentimes == 0;
}

bool _releve(String numero, List<String> prefixes) =>
    prefixes.any(numero.startsWith);

int _debitrice(List<LigneBalanceEtat> lignes, List<String> prefixes) => lignes
    .where((l) => _releve(l.numeroCompte, prefixes))
    .fold(0, (t, l) => t + l.debitCentimes - l.creditCentimes);

int _crediteur(List<LigneBalanceEtat> lignes, List<String> prefixes) =>
    -_debitrice(lignes, prefixes);

/// `TafireService::genererPourExercice` : voir la définition en tête de fichier.
TafireEtat tafireDe(int annee, DonneesEtats d) {
  final lignes = balanceDe(annee, d).lignes;
  final bilan = bilanDe(annee, d);
  // Les à-nouveaux (AN ou provisoires) sont déjà dans la balance : on ne
  // retient que les VARIATIONS. Le poste ne lit que des écritures validées.
  final ouverture = reportOuverture(annee, d).soldes;

  int variationDebitrice(List<String> prefixes) {
    var total = _debitrice(lignes, prefixes);
    for (final e in ouverture.entries) {
      if (_releve(e.key, prefixes)) total -= e.value;
    }
    return total;
  }

  int variationCrediteur(List<String> prefixes) =>
      -variationDebitrice(prefixes);

  // Le résultat de N SEUL, jamais le 131/139 reporté de N-1.
  final resultat = bilan.resultatExerciceCentimes;
  final dotations = _debitrice(lignes, RubriquesTafire.dotations);
  final reprises = _crediteur(lignes, RubriquesTafire.reprises);
  final dotationsAmortissements = _debitrice(
    lignes,
    RubriquesTafire.dotationsAmortissements,
  );
  final reprisesSurImmobilisations = _crediteur(
    lignes,
    RubriquesTafire.reprisesSurImmobilisations,
  );
  final vnc = _debitrice(lignes, RubriquesTafire.valeurComptableCessions);
  final cessions = _crediteur(lignes, RubriquesTafire.produitsCessions);
  final quotePart = _crediteur(lignes, RubriquesTafire.quotePartSubventions);
  final cafg = resultat + dotations - reprises + vnc - cessions - quotePart;
  // Apports : capital et subventions d'investissement REÇUES (variation du 14 +
  // quote-part virée, qui l'a diminué sans trésorerie).
  final capital =
      variationCrediteur(RubriquesTafire.apportsCapital) + quotePart;
  // Emprunts : 16 et 17 seuls. Le 19 est une provision : aucun flux.
  final emprunts = variationCrediteur(RubriquesTafire.dettesFinancieres);
  final participations = variationCrediteur(
    RubriquesTafire.dettesParticipations,
  );
  final ressources = cafg + cessions + capital + emprunts + participations;
  final variationBrut = variationDebitrice(
    RubriquesBilan.immobilisationsBrutes,
  );
  final variationAmort = variationCrediteur(RubriquesBilan.amortissements);
  final acquisitions =
      variationBrut -
      variationAmort +
      dotationsAmortissements +
      vnc -
      reprisesSurImmobilisations;
  final autres = variationCrediteur(RubriquesTafire.autresCapitauxPropres);
  final dividendesAPayer = variationCrediteur(RubriquesTafire.dividendesAPayer);
  final dividendesVerses = -(autres + dividendesAPayer);
  final emplois = acquisitions + dividendesVerses;
  final stocks = variationDebitrice(RubriquesBilan.stocks);
  final creances = variationDebitrice(RubriquesBilan.creances);
  final dettes = variationCrediteur(RubriquesBilan.dettesCirculantes);
  final bfr = stocks + creances - dettes;
  final calculee = ressources - emplois - bfr;
  final reelle =
      variationDebitrice(RubriquesBilan.tresorerieActif) -
      variationCrediteur(RubriquesBilan.tresoreriePassif);
  return TafireEtat(
    resultatExerciceCentimes: resultat,
    dotationsCentimes: dotations,
    reprisesCentimes: reprises,
    valeurComptableCessionsCentimes: vnc,
    quotePartSubventionsCentimes: quotePart,
    cafgCentimes: cafg,
    produitsCessionsCentimes: cessions,
    augmentationCapitalCentimes: capital,
    variationEmpruntsCentimes: emprunts,
    variationDettesParticipationsCentimes: participations,
    totalRessourcesCentimes: ressources,
    acquisitionsCentimes: acquisitions,
    variationAutresCapitauxPropresCentimes: autres,
    variationDividendesAPayerCentimes: dividendesAPayer,
    dividendesVersesCentimes: dividendesVerses,
    totalEmploisCentimes: emplois,
    fluxExploitationCentimes: cafg - bfr,
    fluxInvestissementCentimes: cessions - acquisitions,
    fluxFinancementCentimes:
        capital + emprunts + participations - dividendesVerses,
    variationStocksCentimes: stocks,
    variationCreancesCentimes: creances,
    variationDettesCentimes: dettes,
    variationBfrCentimes: bfr,
    variationCalculeeCentimes: calculee,
    variationReelleCentimes: reelle,
  );
}

/// L'état d'une note — `NotesAnnexes::ETAT_*`.
enum EtatNote { disponible, indisponible, nonSaisie }

/// Un poste d'une note : un compte mouvementé, son montant, et — quand le
/// report à nouveau est connu — son ouverture et la variation de l'exercice.
final class PosteNote {
  const PosteNote({
    required this.libelle,
    required this.montantCentimes,
    this.ouvertureCentimes,
    this.variationCentimes,
  });

  final String libelle;
  final int montantCentimes;
  final int? ouvertureCentimes;
  final int? variationCentimes;
}

/// Une note annexe.
final class NoteAnnexe {
  const NoteAnnexe({
    required this.numero,
    required this.titre,
    required this.etat,
    this.texte,
    this.postes = const [],
    this.motif,
  });

  final int numero;
  final String titre;
  final EtatNote etat;
  final String? texte;
  final List<PosteNote> postes;

  /// Le code fermé du serveur (`NotesAnnexesService::MOTIF_*`).
  final String? motif;
}

/// `comptabilite.notes.regles_et_methodes`.
const String texteReglesEtMethodes =
    'Comptabilité tenue conformément au référentiel SYSCOHADA révisé, Système '
    'Normal. Évaluation des stocks au coût moyen pondéré. Amortissement '
    "linéaire sur la durée d'usage estimée de chaque catégorie "
    "d'immobilisation.";

/// Les motifs, traduits comme `pwa.comptabilite.motifs.*`.
const Map<String, String> motifsNotes = {
  'report_a_nouveau_absent': "Aucun mécanisme de report à nouveau n'existe.",
  'detail_physique_hors_domaine_m10':
      'Le détail physique relève des stocks, hors de la comptabilité.',
  'effectif_hors_domaine_m10':
      "L'effectif relève des ressources humaines, hors de la comptabilité.",
  'non_saisi_par_le_comptable':
      "Rubrique en texte libre : rien n'a encore été saisi.",
  'lettrage_par_anciennete_non_arbitre':
      "Le lettrage par ancienneté (30/60/90 jours) n'est pas vérifié.",
};

/// `NotesAnnexesService::genererPourExercice` : sept notes, dont les notes 2 à
/// 5 détaillent par compte ce que le bilan agrège. Les notes 6 (effectif,
/// donnée des ressources humaines) et 7 (texte libre du comptable, non saisi
/// sur ce poste) sont rendues INDISPONIBLES avec leur motif, comme le serveur :
/// jamais omises (ce sont des notes obligatoires).
List<NoteAnnexe> notesDe(int annee, DonneesEtats d) {
  final lignes = balanceDe(annee, d).lignes;
  final report = reportOuverture(annee, d);
  final ouverture = report.connu ? report.soldes : null;
  final motifReport = report.connu ? null : 'report_a_nouveau_absent';

  List<PosteNote> postes(
    List<String> prefixes, {
    required bool debitrice,
    Map<String, int>? ouverture,
  }) {
    final r = <PosteNote>[];
    for (final l in lignes) {
      if (!_releve(l.numeroCompte, prefixes)) continue;
      final brut = l.debitCentimes - l.creditCentimes;
      final montant = debitrice ? brut : -brut;
      int? depart;
      int? variation;
      if (ouverture != null) {
        final net = ouverture[l.numeroCompte] ?? 0;
        depart = debitrice ? net : -net;
        variation = montant - depart;
      }
      r.add(
        PosteNote(
          libelle: '${l.libelle} (${l.numeroCompte})',
          montantCentimes: montant,
          ouvertureCentimes: depart,
          variationCentimes: variation,
        ),
      );
    }
    return r;
  }

  return [
    const NoteAnnexe(
      numero: 1,
      titre: 'Règles et méthodes comptables',
      etat: EtatNote.disponible,
      texte: texteReglesEtMethodes,
    ),
    NoteAnnexe(
      numero: 2,
      titre: 'Tableau des immobilisations',
      etat: EtatNote.disponible,
      postes: postes(
        RubriquesBilan.immobilisationsBrutes,
        debitrice: true,
        ouverture: ouverture,
      ),
      motif: motifReport,
    ),
    NoteAnnexe(
      numero: 3,
      titre: 'Tableau des amortissements',
      etat: EtatNote.disponible,
      postes: postes(
        RubriquesBilan.amortissements,
        debitrice: false,
        ouverture: ouverture,
      ),
      motif: motifReport,
    ),
    NoteAnnexe(
      numero: 4,
      titre: 'État des créances et dettes',
      etat: EtatNote.disponible,
      postes: [
        ...postes(RubriquesBilan.creances, debitrice: true),
        // Les dettes de la note sont celles du Bilan, 465 (dividendes à payer)
        // compris : miroir de `NotesAnnexesService` (10/11/2026).
        ...postes([
          ...RubriquesBilan.dettesCirculantes,
          ...RubriquesBilan.dettesAssocies,
        ], debitrice: false),
      ],
      motif: 'lettrage_par_anciennete_non_arbitre',
    ),
    NoteAnnexe(
      numero: 5,
      titre: 'État des stocks',
      etat: EtatNote.disponible,
      postes: postes(RubriquesBilan.stocks, debitrice: true),
      motif: 'detail_physique_hors_domaine_m10',
    ),
    const NoteAnnexe(
      numero: 6,
      titre: 'Effectif du personnel',
      etat: EtatNote.indisponible,
      motif: 'effectif_hors_domaine_m10',
    ),
    const NoteAnnexe(
      numero: 7,
      titre: 'Événements postérieurs à la clôture',
      etat: EtatNote.nonSaisie,
      motif: 'non_saisi_par_le_comptable',
    ),
  ];
}
