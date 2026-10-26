/// Le tableau des flux de trésorerie (TAFIRE) et les notes annexes, calculés
/// sur le poste — sans serveur. Fonctions PURES en centimes entiers, réplique de
/// `TafireService` et `NotesAnnexesService` (confrontées au serveur par
/// `tafire_notes_contre_serveur_test.dart`) : MÊMES rubriques, MÊMES signes.
///
/// Ils lisent la balance de l'exercice (`balanceDe`) et le bilan — jamais une
/// seconde agrégation (PA-121) : le résultat qui ouvre la CAFG est celui qui
/// équilibre le bilan.
library;

import 'etats_financiers.dart';
import 'grand_livre_analytique.dart';

/// `RubriquesSyscohada::DOTATIONS_AMORTISSEMENTS` — relu du serveur par un test.
const List<String> rubriqueDotations = ['681'];

/// Le TAFIRE d'un exercice.
final class TafireEtat {
  const TafireEtat({
    required this.resultatExerciceCentimes,
    required this.dotationsCentimes,
    required this.cafgCentimes,
    required this.augmentationCapitalCentimes,
    required this.totalRessourcesCentimes,
    required this.acquisitionsCentimes,
    required this.totalEmploisCentimes,
    required this.variationStocksCentimes,
    required this.variationCreancesCentimes,
    required this.variationDettesCentimes,
    required this.variationBfrCentimes,
    required this.variationCalculeeCentimes,
    required this.variationReelleCentimes,
  });

  final int resultatExerciceCentimes;
  final int dotationsCentimes;
  final int cafgCentimes;
  final int augmentationCapitalCentimes;
  final int totalRessourcesCentimes;
  final int acquisitionsCentimes;
  final int totalEmploisCentimes;
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

/// `TafireService::genererPourExercice` : ressources (CAFG, augmentation de
/// capital), emplois (acquisitions), variation du BFR (stocks + créances −
/// dettes circulantes) et variation de trésorerie, calculée puis comparée à la
/// variation réelle des comptes de trésorerie NETTE (actif moins passif).
TafireEtat tafireDe(int annee, DonneesEtats d) {
  final lignes = balanceDe(annee, d).lignes;
  final bilan = bilanDe(annee, d);
  final resultat = bilan.resultatExerciceCentimes;
  final dotations = _debitrice(lignes, rubriqueDotations);
  final cafg = resultat + dotations;
  final capital = _crediteur(lignes, RubriquesBilan.capital);
  final ressources = cafg + capital;
  final acquisitions = _debitrice(lignes, RubriquesBilan.immobilisationsBrutes);
  final stocks = _debitrice(lignes, RubriquesBilan.stocks);
  final creances = _debitrice(lignes, RubriquesBilan.creances);
  final dettes = _crediteur(lignes, RubriquesBilan.dettesCirculantes);
  final bfr = stocks + creances - dettes;
  final calculee = ressources - acquisitions - bfr;
  final reelle =
      _debitrice(lignes, RubriquesBilan.tresorerieActif) -
      _crediteur(lignes, RubriquesBilan.tresoreriePassif);
  return TafireEtat(
    resultatExerciceCentimes: resultat,
    dotationsCentimes: dotations,
    cafgCentimes: cafg,
    augmentationCapitalCentimes: capital,
    totalRessourcesCentimes: ressources,
    acquisitionsCentimes: acquisitions,
    totalEmploisCentimes: acquisitions,
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
        ...postes(RubriquesBilan.dettesCirculantes, debitrice: false),
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
