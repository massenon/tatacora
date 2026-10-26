/// La CLÔTURE ANNUELLE SYSCOHADA, en FONCTIONS PURES — 26/10/2026 (décision du
/// PO : « la clôture annuelle SYSCOHADA DOIT ÊTRE IMPLÉMENTÉE EN POSTE ET WEB »).
///
/// Réplique de ce que décident `ClotureExerciceService` (les lignes des deux
/// pièces) et `EtatClotureService` (la liste de contrôle) du serveur ; la
/// mécanique (transactions, statuts, contre-passations) est dans
/// `data/cloture_exercice_locale.dart`. Aucune base, aucune horloge ici : les
/// montants sont des CENTIMES entiers, et `cloture_contre_serveur_test.dart`
/// confronte ces fonctions au VRAI service PHP, au centime.
///
/// ## Le cycle d'un exercice (le même qu'au serveur)
///
///     ouvert ──démarrer──▶ en_cloture ──clôturer──▶ cloture
///       ▲                     │   ▲                     │
///       └──reprendre saisie───┘   └───────rouvrir───────┘ (comptable, motif)
library;

import 'etats_financiers.dart';

/// Les classes de GESTION soldées à la clôture, et celles de BILAN reportées à
/// nouveau (`ClotureExerciceService::CLASSES_GESTION` / `CLASSES_BILAN`).
const classesDeGestion = ['6', '7', '8'];
const classesDeBilan = ['1', '2', '3', '4', '5'];

/// Les journaux que SEULE la clôture écrit : une saisie manuelle y est refusée
/// (`ClotureExerciceService::JOURNAUX_RESERVES`).
const journalDeCloture = 'CL';
const journalANouveaux = 'AN';
const journauxReserves = [journalDeCloture, journalANouveaux];

/// Le centre qui porte les lignes de clôture et d'à-nouveaux
/// (`ClotureExerciceService::CENTRE_DE_CLOTURE`).
const centreDeCloture = 'Structure';

/// Le motif de réouverture : dix caractères au moins
/// (`ClotureExerciceService::MOTIF_LONGUEUR_MIN`).
const longueurMinMotifReouverture = 10;

/// Le rôle qui peut rouvrir (décision du PO du 20/10/2026 : « LE COMPTABLE »).
const roleReouverture = 'comptable';

/// Le solde d'un compte de GESTION, pour UN centre, sur les pièces validées
/// d'un exercice (somme des débits et des crédits).
typedef SoldeGestion = ({
  String numero,
  String centreId,
  int debitCentimes,
  int creditCentimes,
});

/// Le solde d'un compte de BILAN sur les pièces validées d'un exercice.
typedef SoldeBilan = ({
  String numero,
  String classe,
  int debitCentimes,
  int creditCentimes,
});

/// Une ligne de l'une des deux pièces de clôture : un compte, un centre, un
/// débit OU un crédit.
final class LignePieceCloture {
  const LignePieceCloture({
    required this.compte,
    required this.centreId,
    this.debitCentimes = 0,
    this.creditCentimes = 0,
  });

  final String compte;
  final String centreId;
  final int debitCentimes;
  final int creditCentimes;

  @override
  String toString() =>
      'LignePieceCloture($compte, $centreId, D$debitCentimes, C$creditCentimes)';
}

/// Les lignes qui soldent les comptes de gestion, centre par centre, et la
/// contrepartie en 131 (bénéfice) ou 139 (perte) — `lignesDeCloture` du
/// serveur.
///
/// Le solde est INVERSÉ : un compte débiteur (charge) est crédité, un compte
/// créditeur (produit) est débité. Un solde nul n'a pas de ligne. Le résultat
/// est les débits (produits soldés) moins les crédits (charges soldées) ; il
/// est signé (bénéfice positif) et sa contrepartie porte le centre
/// [centreStructureId].
({List<LignePieceCloture> lignes, int resultatCentimes}) lignesDeCloture(
  Iterable<SoldeGestion> soldes, {
  required String centreStructureId,
  required String compteBenefice,
  required String comptePerte,
}) {
  final tries = [...soldes]
    ..sort((a, b) {
      final c = a.numero.compareTo(b.numero);
      return c != 0 ? c : a.centreId.compareTo(b.centreId);
    });
  final lignes = <LignePieceCloture>[];
  var debits = 0;
  var credits = 0;
  for (final s in tries) {
    final net = s.debitCentimes - s.creditCentimes;
    if (net == 0) continue;
    final montant = net > 0 ? net : -net;
    lignes.add(
      LignePieceCloture(
        compte: s.numero,
        centreId: s.centreId,
        debitCentimes: net < 0 ? montant : 0,
        creditCentimes: net > 0 ? montant : 0,
      ),
    );
    if (net < 0) {
      debits += montant;
    } else {
      credits += montant;
    }
  }
  final resultat = debits - credits;
  if (resultat > 0) {
    lignes.add(
      LignePieceCloture(
        compte: compteBenefice,
        centreId: centreStructureId,
        creditCentimes: resultat,
      ),
    );
  } else if (resultat < 0) {
    lignes.add(
      LignePieceCloture(
        compte: comptePerte,
        centreId: centreStructureId,
        debitCentimes: -resultat,
      ),
    );
  }
  return (lignes: lignes, resultatCentimes: resultat);
}

/// Les lignes d'à-nouveaux : le solde de chaque compte de BILAN (classes 1 à 5,
/// résultat compris) APRÈS la pièce de clôture — `lignesANouveaux` du serveur.
/// Un solde débiteur est reporté au débit, un solde créditeur au crédit, tous
/// sur le centre [centreStructureId].
List<LignePieceCloture> lignesANouveaux(
  Iterable<SoldeBilan> soldes, {
  required String centreStructureId,
}) {
  final tries = [...soldes]..sort((a, b) => a.numero.compareTo(b.numero));
  final lignes = <LignePieceCloture>[];
  for (final s in tries) {
    if (!classesDeBilan.contains(s.classe)) continue;
    final net = s.debitCentimes - s.creditCentimes;
    if (net == 0) continue;
    lignes.add(
      LignePieceCloture(
        compte: s.numero,
        centreId: centreStructureId,
        debitCentimes: net > 0 ? net : 0,
        creditCentimes: net < 0 ? -net : 0,
      ),
    );
  }
  return lignes;
}

/// Ce qui BLOQUE une clôture (`EtatClotureService::BLOCAGE_*`) : le code est
/// celui du serveur, la phrase est celle de `pwa.comptabilite.motifs.<code>`.
enum BlocageCloture {
  journalANouveauxAbsent('journal_a_nouveaux_absent'),
  comptesDeResultatAbsents('comptes_de_resultat_absents'),
  centreDeClotureAbsent('centre_de_cloture_absent'),
  ecrituresEnBrouillon('ecritures_en_brouillon'),
  balanceDesequilibree('balance_desequilibree'),
  bilanDesequilibre('bilan_desequilibre');

  const BlocageCloture(this.code);

  /// Le code du serveur.
  final String code;

  /// Vrai pour un blocage de RÉFÉRENTIEL (`blocagesStructurels` du serveur) :
  /// il disparaît seul le jour où l'élément manquant existe.
  bool get structurel => index <= centreDeClotureAbsent.index;
}

/// Ce qui AVERTIT sans bloquer (`EtatClotureService::AVERTISSEMENT_*`).
///
/// Écart nommé : le serveur en porte un second, `releves_bancaires_non_rapproches`
/// — ce poste n'a aucun relevé bancaire à rapprocher (la table du serveur n'a pas
/// de pendant ici) ; il ne peut donc pas être levé sur ce poste.
enum AvertissementCloture {
  impotNonComptabilise('impot_non_comptabilise');

  const AvertissementCloture(this.code);

  final String code;
}

/// L'état de la procédure de clôture d'UN exercice, calculé sur les pièces de ce
/// poste — `EtatCloture` du serveur, les trois chiffres de l'onglet
/// « Clôtures » : résultat à reporter, blocages, avertissements.
final class EtatClotureLocal {
  const EtatClotureLocal({
    required this.annee,
    required this.statut,
    required this.blocages,
    required this.avertissements,
    required this.resultatAReporterCentimes,
    required this.compteDeDestination,
  });

  final int annee;

  /// `ouvert`, `en_cloture` ou `cloture`.
  final String statut;

  /// Structurels d'abord, puis de données (l'ordre du serveur).
  final List<BlocageCloture> blocages;
  final List<AvertissementCloture> avertissements;

  /// Le résultat de l'exercice, signé, en centimes (`bilan->resultatExercice`).
  final int resultatAReporterCentimes;

  /// 131 (bénéfice, zéro compris) ou 139 (perte).
  final String compteDeDestination;

  /// Les conditions constatables sont-elles réunies ?
  /// (`conditionsVerifiablesReunies` du serveur.)
  bool get conditionsReunies => blocages.isEmpty;
}

/// Les faits du référentiel que la liste de contrôle vérifie : journaux CL et AN
/// présents, comptes de résultat (bénéfice ET perte) au plan, centre de clôture.
typedef ReferentielDeCloture = ({
  bool journauxPresents,
  bool comptesDeResultatPresents,
  bool centreDeClotureEtPresent,
});

/// Assemble l'état de clôture de l'exercice [annee] depuis [donnees] (les
/// pièces VALIDÉES de ce poste) — `EtatClotureService::genererPourExercice`.
///
/// [brouillons] : le nombre d'écritures encore en brouillon dans l'exercice.
/// Comme le serveur, [donnees] porte pour l'exercice jugé ses brouillons ET ses
/// validées (`ecrituresValideesParAnnee(anneeAvecBrouillons:)`) : le résultat à
/// reporter d'un exercice qui a des brouillons les compte, et la liste de
/// contrôle les dit bloquants.
EtatClotureLocal etatDeCloture({
  required int annee,
  required String statut,
  required DonneesEtats donnees,
  required int brouillons,
  required ReferentielDeCloture referentiel,
  required String compteBenefice,
  required String comptePerte,
}) {
  final bilan = bilanDe(annee, donnees);
  final blocages = <BlocageCloture>[
    if (!referentiel.journauxPresents) BlocageCloture.journalANouveauxAbsent,
    if (!referentiel.comptesDeResultatPresents)
      BlocageCloture.comptesDeResultatAbsents,
    if (!referentiel.centreDeClotureEtPresent)
      BlocageCloture.centreDeClotureAbsent,
    if (brouillons > 0) BlocageCloture.ecrituresEnBrouillon,
    if (!_balanceEquilibree(annee, donnees))
      BlocageCloture.balanceDesequilibree,
    if (!bilan.equilibre) BlocageCloture.bilanDesequilibre,
  ];
  return EtatClotureLocal(
    annee: annee,
    statut: statut,
    blocages: blocages,
    avertissements: [
      if (bilan.impotNonComptabilise) AvertissementCloture.impotNonComptabilise,
    ],
    resultatAReporterCentimes: bilan.resultatExerciceCentimes,
    compteDeDestination: bilan.resultatExerciceCentimes >= 0
        ? compteBenefice
        : comptePerte,
  );
}

/// Les DEUX égalités de la balance générale (§4 du serveur) : totaux des
/// mouvements ET totaux des soldes. Distincte de `comptabiliteEquilibree`, qui y
/// ajoute le bilan — la liste de contrôle les nomme séparément.
bool _balanceEquilibree(int annee, DonneesEtats d) {
  var debit = 0;
  var credit = 0;
  var soldesDebiteurs = 0;
  var soldesCrediteurs = 0;
  for (final l in balanceDe(annee, d).lignes) {
    debit += l.debitCentimes;
    credit += l.creditCentimes;
    final net = l.debitCentimes - l.creditCentimes;
    if (net > 0) soldesDebiteurs += net;
    if (net < 0) soldesCrediteurs -= net;
  }
  return debit == credit && soldesDebiteurs == soldesCrediteurs;
}

/// Le motif de réouverture vaut-il ? Dix CARACTÈRES au moins, après `trim`
/// (`mb_strlen` : des caractères, pas des octets).
bool motifReouvertureValide(String motif) =>
    motif.trim().runes.length >= longueurMinMotifReouverture;

/// Une clôture d'exercice passée SUR CE POSTE — `ClotureExercice` du serveur.
/// ACTIVE tant qu'elle n'a pas été rouverte ; une clôture rouverte reste en
/// historique (rien ne s'efface).
final class ClotureExercice {
  const ClotureExercice({
    required this.id,
    required this.exerciceId,
    required this.pieceCloture,
    required this.pieceANouveaux,
    required this.resultatCentimes,
    required this.clotureePar,
    required this.clotureeLe,
    required this.archiveChemin,
    required this.archiveEmpreinte,
    required this.rouvertePar,
    required this.rouverteLe,
    required this.motifReouverture,
  });

  final String id;
  final String exerciceId;

  /// `CL-2026-00001` — `null` si aucun compte de gestion n'avait de solde.
  final String? pieceCloture;

  /// `AN-2027-00001` — `null` si aucun compte de bilan n'avait de solde.
  final String? pieceANouveaux;

  /// Le résultat, signé (bénéfice positif), en centimes.
  final int resultatCentimes;
  final String clotureePar;
  final DateTime clotureeLe;

  /// Le dossier de l'archive légale et son empreinte (SHA-256 du manifeste),
  /// `null` tant que l'archive n'est pas générée.
  final String? archiveChemin;
  final String? archiveEmpreinte;
  final String? rouvertePar;
  final DateTime? rouverteLe;
  final String? motifReouverture;

  bool get estActive => rouverteLe == null;
}
