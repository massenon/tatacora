/// Les règles de gestion de la comptabilité, en FONCTIONS PURES : aucune base,
/// aucune horloge, aucun état. Réplique de ce que portent
/// `EcritureComptableService`, `PasserEcritureService` et
/// `ExerciceComptableService` du serveur, avec leurs refus exacts.
///
/// Le moteur (`MoteurComptable`) les appelle dans l'ordre du serveur ; les
/// tests les appellent seuls, sans Drift.
///
/// @see RG-11 Immutabilité et contre-passation
/// @see RG-12 Centre de coût obligatoire
/// @see EF-M10-02 Saisie des écritures comptables
library;

import 'entities/comptabilite.dart';
import 'messages_comptables.dart';
import 'montant_comptable.dart';
import 'refus_comptable.dart';

/// Une ligne telle que la règle d'équilibre la voit : deux montants, en
/// centimes.
typedef MontantsDeLigne = ({int debitCentimes, int creditCentimes});

/// Débit total = crédit total, en ENTIERS — jamais une égalité flottante.
///
/// Même ordre de refus que `EcritureComptableService::verifierEquilibre` :
/// d'abord l'écart (« déséquilibrée »), puis la pièce à zéro (équilibrée mais
/// qui ne veut rien dire). Une liste vide se refuse AVANT, par
/// [verifierPieceNonVide].
void verifierEquilibre(List<MontantsDeLigne> lignes) {
  var debit = 0;
  var credit = 0;
  for (final l in lignes) {
    debit += l.debitCentimes;
    credit += l.creditCentimes;
  }
  if (debit != credit) {
    throw RefusComptable.dit(
      MotifRefus.pieceDesequilibree,
      'comptabilite.piece_desequilibree',
      {
        'debit': chaineDepuisCentimes(debit),
        'credit': chaineDepuisCentimes(credit),
        'ecart': chaineDepuisCentimes(debit - credit),
      },
    );
  }
  if (debit == 0) {
    throw RefusComptable.dit(
      MotifRefus.pieceSansMontant,
      'comptabilite.piece_sans_montant',
    );
  }
}

/// Une pièce comporte au moins une ligne.
void verifierPieceNonVide(int nombreDeLignes) {
  if (nombreDeLignes == 0) {
    throw RefusComptable.dit(MotifRefus.pieceVide, 'comptabilite.piece_vide');
  }
}

/// Les contraintes de LIGNE que le serveur laisse à MySQL : un montant n'est
/// jamais négatif, et une ligne est débit OU crédit, jamais les deux.
///
/// Le serveur répond par une erreur SQL sans phrase ; le poste refuse au même
/// endroit du déroulement — APRÈS l'équilibre, au moment de l'écriture — avec
/// une phrase lisible (écart nommé, ticket D194).
void verifierContraintesDeLigne(MontantsDeLigne ligne) {
  if (ligne.debitCentimes < 0 || ligne.creditCentimes < 0) {
    throw const RefusComptable(
      MotifRefus.contrainteBase,
      PhrasesDuPoste.ligneNegative,
    );
  }
  if (ligne.debitCentimes > 0 && ligne.creditCentimes > 0) {
    throw const RefusComptable(
      MotifRefus.contrainteBase,
      PhrasesDuPoste.debitEtCredit,
    );
  }
}

/// Vrai pour une date `AAAA-MM-JJ` qui existe au calendrier (le 31 février
/// n'existe pas).
bool estDateIso(String valeur) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(valeur);
  if (m == null) return false;
  final a = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final j = int.parse(m.group(3)!);
  final d = DateTime.utc(a, mo, j);
  return d.year == a && d.month == mo && d.day == j;
}

/// L'exercice qui COUVRE la date, borne comprise (`date_debut <= date <=
/// date_fin`). `null` si aucun — y compris pour une chaîne qui n'est pas une
/// date, comme MySQL qui ne trouve alors aucun exercice.
ExerciceComptable? exerciceCouvrant(
  Iterable<ExerciceComptable> exercices,
  String date,
) {
  if (!estDateIso(date)) return null;
  for (final e in exercices) {
    if (e.dateDebut.compareTo(date) <= 0 && e.dateFin.compareTo(date) >= 0) {
      return e;
    }
  }
  return null;
}

/// L'année d'une pièce qui peut ouvrir son exercice D'ELLE-MÊME (passage
/// d'année, 20/10/2026) — la même règle que le serveur
/// (`ExerciceComptableService::ouvertureAutomatiquePermise`) : l'année en
/// cours, et la suivante en décembre seulement. Une date mal saisie
/// (« 2062 ») ou une année passée manquante n'ouvre rien.
bool ouvertureAutomatiquePermise(int annee, DateTime maintenant) =>
    annee == maintenant.year ||
    (annee == maintenant.year + 1 && maintenant.month == 12);

/// L'exercice qui couvre la date ET qui est encore ouvert.
///
/// Deux refus distincts, et l'écart compte : « aucun exercice » se corrige en
/// créant l'exercice, « exercice clos » se corrige en rouvrant ou en datant la
/// pièce autrement. `en_cloture` est refusé aussi (seul `ouvert` reçoit une
/// saisie), avec son statut brut dans la phrase.
ExerciceComptable exerciceOuvertPour(
  Iterable<ExerciceComptable> exercices,
  String date,
) => exerciceAdmisPour(exercices, date, const {StatutExercice.ouvert});

/// L'exercice qui couvre la date ET dont le statut est ADMIS (26/10/2026) —
/// `PasserEcritureService::exerciceOuvert($date, $statutsAdmis)`. Les modules ne
/// passent que dans un exercice `ouvert` ; la clôture et l'écriture d'inventaire
/// du comptable admettent aussi `en_cloture`. Un exercice `cloture` n'est jamais
/// admis par un geste de saisie : seule la réouverture le rend écrivable.
ExerciceComptable exerciceAdmisPour(
  Iterable<ExerciceComptable> exercices,
  String date,
  Set<StatutExercice> admis,
) {
  final exercice = exerciceCouvrant(exercices, date);
  if (exercice == null) {
    throw RefusComptable.dit(
      MotifRefus.exerciceAbsent,
      'depenses.exercice_absent',
      {'date': date},
    );
  }
  if (!admis.contains(exercice.statut)) {
    throw RefusComptable.dit(
      MotifRefus.exerciceNonOuvert,
      'depenses.exercice_clos',
      {'annee': '${exercice.annee}', 'statut': exercice.statut.valeur},
    );
  }
  return exercice;
}

/// Un compte de DIVISION (le plan en porte des sous-comptes) ne reçoit aucun
/// mouvement : seuls les comptes de détail s'imputent. En pratique les comptes
/// à 4 chiffres ; les comptes plus courts SANS sous-compte au plan (552, 131,
/// 139…) sont des feuilles et restent imputables.
bool estDivision(String numero, Iterable<String> numerosDuPlan) {
  if (numero.length >= 4) return false;
  return numerosDuPlan.any((n) => n != numero && n.startsWith(numero));
}

/// Le centre d'une ligne : celui qu'elle nomme, sinon le défaut du compte,
/// sinon REFUS (RG-12). Jamais un centre « par défaut » global : imputer les
/// achats du bar à la Structure fausserait toute la comptabilité analytique
/// sans qu'aucun total ne bouge.
String centrePour({
  required String? centreExplicite,
  required CompteDuPlan compte,
}) {
  final centre = centreExplicite ?? compte.centreCoutDefautId;
  if (centre == null || centre.isEmpty) {
    throw RefusComptable.dit(
      MotifRefus.centreAbsent,
      'depenses.centre_absent',
      {'numero': compte.numero},
    );
  }
  return centre;
}

/// `CODE-AAAA-NNNNN` — le numéro d'une pièce (`SequenceDocumentService`).
String formaterNumeroPiece(String codeJournal, int annee, int rang) =>
    '$codeJournal-$annee-${rang.toString().padLeft(5, '0')}';

/// Le libellé d'une contre-passation sans motif : « Contre-passation — X ».
String libelleContrepassation(String libelleOrigine) => MessagesComptables.dire(
  'comptabilite.libelle_contrepassation',
  {'libelle': libelleOrigine},
);
