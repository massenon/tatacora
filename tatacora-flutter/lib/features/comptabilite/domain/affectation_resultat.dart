/// L'AFFECTATION DU RÉSULTAT d'un exercice clôturé, en FONCTIONS PURES —
/// 09/11/2026 (demande du PO : « ajoute l'affectation du résultat »).
///
/// Réplique de ce que décide `AffectationResultatService` du serveur : les
/// lignes de la pièce, les contrôles de la ventilation, la réserve légale
/// proposée. La mécanique (transaction, pièce par le moteur, demande de
/// contre-passation) est dans `data/affectation_resultat_locale.dart`. Aucune
/// base, aucune horloge ici : les montants sont des CENTIMES entiers, et
/// `affectation_contre_serveur_test.dart` confronte ces fonctions au VRAI
/// service PHP, au centime.
///
/// ## La pièce
///
/// Journal OD, datée de l'approbation des comptes DANS l'exercice N (celui qui
/// suit l'exercice clôturé), validée donc immuable (RG-11) :
///
///  - bénéfice : DÉBIT 131 du résultat ; CRÉDIT réserve légale (111), autres
///    réserves (118x), dividendes à payer (465), report à nouveau créditeur (121) ;
///  - perte : CRÉDIT 139 du résultat ; DÉBIT report à nouveau débiteur (129x),
///    ou imputation sur les autres réserves (118x) / le report à nouveau
///    créditeur (121).
///
/// Les numéros de compte sont ceux de la CORRESPONDANCE paramétrable (jamais en
/// dur) ; le centre de coût est celui de la clôture (« Structure »).
///
/// ## Les règles PAR FORME JURIDIQUE (09/11/2026, décision du PO : « le Gîte est
/// ## une entreprise individuelle »)
///
///  - ENTREPRISE INDIVIDUELLE : ni réserve légale, ni dividendes (ni la ligne ni le
///    compte 465), pas de procès-verbal d'assemblée. Le bénéfice se ventile entre le
///    compte de l'exploitant (1041), le report à nouveau créditeur (121) et les
///    autres réserves (1181) ; le RESTE va au compte de l'exploitant. Une perte se
///    débite au compte de l'exploitant (défaut), au report à nouveau débiteur (1291)
///    ou s'impute sur 121 / 1181 dans la limite de leur solde ;
///  - SARL / SA : RÉSERVE LÉGALE OBLIGATOIRE (au moins 10 % de bénéfice − pertes
///    antérieures tant que la réserve légale est sous 20 % du capital : refus
///    bloquant ; capital non déterminable : un avertissement), dividendes refusés
///    s'ils font passer les capitaux propres sous le capital et les réserves non
///    distribuables, ALERTE (non bloquante) sous la moitié du capital après une perte ;
///  - ORDRE D'IMPUTATION d'une perte (modifiable) : 121, puis 1181, puis le reste en
///    1291 ; une entreprise individuelle propose le compte de l'exploitant.
///
/// Jamais la réserve légale pour une perte. `AffectationResultatService` du serveur
/// est la source ; `affectation_contre_serveur_test.dart` la confronte au centime.
library;

import 'cloture_exercice.dart';
import 'forme_juridique.dart';
import 'messages_affectation.dart';
import 'refus_comptable.dart';

/// Une affectation est une opération diverse : aucun journal propre
/// (`AffectationResultatService::JOURNAL`).
const journalAffectation = 'OD';

/// Même droit que la réouverture : le comptable seul.
const roleAffectation = roleReouverture;

/// Le motif de la contre-passation : dix caractères au moins.
const longueurMinMotifAffectation = 10;

/// Les postes de ventilation (`AffectationResultatService::POSTES`), dans
/// l'ordre de l'écran.
const postesAffectation = [
  'reserve_legale',
  'autres_reserves',
  'dividendes',
  'report_a_nouveau',
  'imputation_report_crediteur',
  'compte_exploitant',
];

/// Ceux d'un bénéfice et ceux d'une perte pour une SOCIÉTÉ (`POSTES_BENEFICE` /
/// `POSTES_PERTE`).
const postesBenefice = [
  'reserve_legale',
  'autres_reserves',
  'dividendes',
  'report_a_nouveau',
];
const postesPerte = [
  'autres_reserves',
  'imputation_report_crediteur',
  'report_a_nouveau',
];

/// Ceux d'une ENTREPRISE INDIVIDUELLE : ni réserve légale ni dividendes
/// (`POSTES_BENEFICE_EI` / `POSTES_PERTE_EI`).
const postesBeneficeEi = [
  'compte_exploitant',
  'autres_reserves',
  'report_a_nouveau',
];
const postesPerteEi = [
  'compte_exploitant',
  'autres_reserves',
  'imputation_report_crediteur',
  'report_a_nouveau',
];

/// Les postes OFFERTS pour [forme] et le sens du résultat
/// (`AffectationResultatService::postes`).
List<String> postesOfferts(FormeJuridique forme, {required bool benefice}) {
  if (forme.estSociete) return benefice ? postesBenefice : postesPerte;
  return benefice ? postesBeneficeEi : postesPerteEi;
}

/// Le poste qui reçoit LE RESTE : le compte de l'exploitant (entreprise
/// individuelle), le report à nouveau (société) — `AffectationResultatService::posteDuReste`.
String posteDuResteDe(FormeJuridique forme) =>
    forme.estSociete ? 'report_a_nouveau' : 'compte_exploitant';

/// Le capital SOCIAL se lit au 101 seul (`PREFIXES_CAPITAL_SOCIAL`) : le groupe 104
/// est le compte de l'exploitant, jamais un capital.
const prefixesCapital = ['101'];

/// Les capitaux propres (`PREFIXES_CAPITAUX_PROPRES`) : le capital compte par compte
/// (le plan n'a pas de compte `10`), les réserves, le report à nouveau, le résultat, les
/// subventions et les provisions réglementées.
const prefixesCapitauxPropres = [
  '101',
  '102',
  '103',
  '104',
  '105',
  '106',
  '109',
  '11',
  '12',
  '13',
  '14',
  '15',
];

/// Les pertes antérieures : le report à nouveau débiteur (`PREFIXES_PERTES_ANTERIEURES`).
const prefixesPertesAnterieures = ['129'];

/// Les réserves non distribuables autres que la légale
/// (`PREFIXES_RESERVES_NON_DISTRIBUABLES`) : statutaires (112), réglementées (113).
const prefixesReservesNonDistribuables = ['112', '113'];

/// Longueur maximale de la référence de la décision (`REFERENCE_LONGUEUR_MAX`).
const longueurMaxReferenceDecision = 255;

/// Taux de la réserve légale (10 % du bénéfice net) et plafond (20 % du capital).
const tauxReserveLegaleDixiemes =
    10; // `TAUX_RESERVE_LEGALE` = 0.10 : un dixième
const plafondReserveLegaleCinquiemes =
    5; // `PLAFOND_RESERVE_LEGALE` = 0.20 : un cinquième

/// Le libellé de chaque poste (`comptabilite.affectation_poste_*`).
String libellePoste(String poste) =>
    MessagesAffectation.dire('comptabilite.affectation_poste_$poste');

/// Le libellé de la pièce d'affectation de l'exercice [annee] — c'est aussi ce
/// qui la RECONNAÎT au poste (`comptabilite.libelle_affectation_resultat`).
String libellePieceAffectation(int annee) => MessagesAffectation.dire(
  'comptabilite.libelle_affectation_resultat',
  {'annee': '$annee'},
);

/// Les comptes lus à la correspondance, par poste de ventilation, au moment de
/// passer la pièce.
typedef ComptesAffectation = ({
  String benefice,
  String perte,
  String reserveLegale,
  String autresReserves,
  String dividendes,
  String reportCrediteur,
  String reportDebiteur,
  String exploitant,
});

/// Une ligne de la pièce : un compte, un débit OU un crédit (centimes).
typedef LigneAffectation = ({String compte, int debit, int credit});

/// La SITUATION de N lue sur ses écritures validées (à-nouveaux écrits compris),
/// en CENTIMES : capital social (101x), réserve légale, réserves non distribuables
/// (112, 113), pertes antérieures (report à nouveau débiteur, positif) et capitaux
/// propres (classes 10 à 15) — `AffectationResultatService::situation`.
typedef SituationCapitaux = ({
  int capital,
  int reserveLegale,
  int reservesNonDistribuables,
  int pertesAnterieures,
  int capitauxPropres,
});

/// La réserve légale OBLIGATOIRE d'un bénéfice de société : 10 % de (bénéfice −
/// pertes antérieures), plafonnée à ce qui reste avant 20 % du capital. `null`
/// quand le plafond est atteint (rien n'est dû). Le capital doit être déterminable
/// (`AffectationResultatService::reserveLegaleMinimum`).
///
/// `bcmul(.., '0.20', 2)` et `bcmul(.., '0.10', 2)` TRONQUENT à deux décimales :
/// en centimes, une division entière.
int? reserveLegaleMinimum(SituationCapitaux situation, int resultatCentimes) {
  final plafond = situation.capital ~/ plafondReserveLegaleCinquiemes;
  final place = plafond - situation.reserveLegale;
  if (place <= 0) return null;
  final base = resultatCentimes - situation.pertesAnterieures;
  if (base <= 0) return 0;
  final dix = base ~/ tauxReserveLegaleDixiemes;
  return dix <= place ? dix : place;
}

/// L'ALERTE de l'article 664 : une PERTE de société dont les capitaux propres
/// tombent sous la moitié du capital. Non bloquante ; `null` sinon (bénéfice,
/// capital non déterminable, capitaux propres suffisants)
/// (`AffectationResultatService::alerteMoitieCapital`).
String? alerteMoitieCapital(SituationCapitaux situation, int resultatCentimes) {
  if (resultatCentimes >= 0 || situation.capital <= 0) return null;
  // `bcdiv(.., '2', 2)` tronque : une division entière en centimes.
  if (situation.capitauxPropres >= situation.capital ~/ 2) return null;
  return MessagesAffectation.dire(
    'comptabilite.affectation_alerte_moitie_capital',
    {
      'propres': _decimal(situation.capitauxPropres),
      'capital': _decimal(situation.capital),
    },
  );
}

/// La ventilation PROPOSÉE (`AffectationResultatService::proposer`) :
///
///  - entreprise individuelle : tout au compte de l'exploitant, bénéfice comme perte ;
///  - société, bénéfice : la réserve légale OBLIGATOIRE (10 % du bénéfice net des
///    pertes antérieures, plafonnée à 20 % du capital), le reste en report à nouveau ;
///    capital non déterminable : aucune réserve légale proposée ;
///  - société, perte : report à nouveau créditeur (121) d'abord, puis réserves
///    facultatives (1181), puis le reste en report à nouveau débiteur (1291) — jamais
///    au-delà du solde, jamais la réserve légale.
///
/// [situation] est celle de N (`null` si N n'existe pas encore) ;
/// [soldeReportCrediteur] et [soldeAutresReserves] sont les soldes créditeurs (centimes)
/// des comptes que l'imputation d'une perte débite.
({Map<String, int> ventilation, bool reserveLegalePropose, bool plafondAtteint})
proposerVentilation({
  required FormeJuridique forme,
  required int resultatCentimes,
  SituationCapitaux? situation,
  int soldeReportCrediteur = 0,
  int soldeAutresReserves = 0,
}) {
  final ventilation = {for (final p in postesAffectation) p: 0};
  final absolu = resultatCentimes > 0 ? resultatCentimes : -resultatCentimes;
  if (!forme.estSociete) {
    ventilation['compte_exploitant'] = absolu;
    return (
      ventilation: ventilation,
      reserveLegalePropose: false,
      plafondAtteint: false,
    );
  }
  if (resultatCentimes <= 0) {
    var reste = absolu;
    for (final e in {
      'imputation_report_crediteur': soldeReportCrediteur,
      'autres_reserves': soldeAutresReserves,
    }.entries) {
      final impute = e.value <= 0 ? 0 : (reste <= e.value ? reste : e.value);
      ventilation[e.key] = impute;
      reste -= impute;
    }
    ventilation['report_a_nouveau'] = reste;
    return (
      ventilation: ventilation,
      reserveLegalePropose: false,
      plafondAtteint: false,
    );
  }
  var reserve = 0;
  var propose = false;
  var plafondAtteint = false;
  // Capital non déterminable : aucune proposition, jamais un taux deviné.
  if (situation != null && situation.capital > 0) {
    propose = true;
    final minimum = reserveLegaleMinimum(situation, resultatCentimes);
    if (minimum == null) {
      plafondAtteint = true;
    } else {
      reserve = minimum;
    }
  }
  ventilation['reserve_legale'] = reserve;
  ventilation['report_a_nouveau'] = resultatCentimes - reserve;
  return (
    ventilation: ventilation,
    reserveLegalePropose: propose,
    plafondAtteint: plafondAtteint,
  );
}

/// Les montants SAISIS (chaînes décimales, un champ par poste) en centimes,
/// comme `AffectationResultatService::controlerVentilation` les lit : un champ
/// vide vaut zéro, un nombre à deux décimales au plus, sinon le refus
/// « montant illisible » (la phrase du serveur). Un poste absent vaut zéro.
Map<String, int> ventilationDepuisSaisie(Map<String, String> saisie) {
  final centimes = <String, int>{};
  for (final poste in postesAffectation) {
    final brut = (saisie[poste] ?? '').isEmpty ? '0' : saisie[poste]!;
    if (!RegExp(r'^-?\d+(\.\d{1,2})?$').hasMatch(brut)) {
      throw RefusComptable(
        MotifRefus.affectationVentilation,
        MessagesAffectation.dire('comptabilite.affectation_montant_illisible', {
          'poste': libellePoste(poste),
          'valeur': brut,
        }),
      );
    }
    final negatif = brut.startsWith('-');
    final sansSigne = negatif ? brut.substring(1) : brut;
    final parties = sansSigne.split('.');
    final deux = (parties.length > 1 ? parties[1] : '').padRight(2, '0');
    final valeur = int.parse(parties[0]) * 100 + int.parse(deux);
    centimes[poste] = negatif ? -valeur : valeur;
  }
  return centimes;
}

/// Les contrôles de la ventilation, dans l'ordre du serveur : montant non
/// négatif, postes admis POUR LA FORME JURIDIQUE (ni réserve légale ni dividende
/// pour une entreprise individuelle, pas de compte de l'exploitant pour une société ;
/// ni dividende ni réserve légale sur une perte), SOMME EXACTE, imputation dans la
/// limite du solde, puis — société, bénéfice — la RÉSERVE LÉGALE OBLIGATOIRE et le
/// plancher des capitaux propres sous les dividendes. Rend les montants de tous les
/// postes et les avertissements non bloquants ; LÈVE [RefusComptable] à la phrase du
/// serveur.
///
/// [soldesImputables] : solde créditeur (centimes) des comptes que l'imputation
/// d'une perte débite — `autres_reserves` et `imputation_report_crediteur`.
/// [situation] : celle de N, lue seulement pour une société qui affecte un bénéfice.
({Map<String, int> montants, List<String> avertissements})
controlerVentilation({
  required FormeJuridique forme,
  required Map<String, int> ventilation,
  required int resultatCentimes,
  required Map<String, int> soldesImputables,
  SituationCapitaux? situation,
}) {
  final beneficiaire = resultatCentimes > 0;
  final absolu = beneficiaire ? resultatCentimes : -resultatCentimes;
  final montants = {for (final p in postesAffectation) p: 0};
  final avertissements = <String>[];

  RefusComptable refus(
    MotifRefus motif,
    String cle, [
    Map<String, String>? v,
  ]) => RefusComptable(
    motif,
    MessagesAffectation.dire('comptabilite.$cle', v ?? const {}),
  );

  for (final poste in postesAffectation) {
    final montant = ventilation[poste] ?? 0;
    if (montant < 0) {
      throw refus(
        MotifRefus.affectationVentilation,
        'affectation_montant_negatif',
        {'poste': libellePoste(poste)},
      );
    }
    montants[poste] = montant;
  }

  // La forme juridique : une entreprise individuelle n'a ni réserve légale ni
  // dividende ; une société n'a pas de compte de l'exploitant.
  if (!forme.estSociete) {
    if (montants['reserve_legale']! > 0) {
      throw refus(
        MotifRefus.affectationVentilation,
        'affectation_ei_reserve_legale',
      );
    }
    if (montants['dividendes']! > 0) {
      throw refus(
        MotifRefus.affectationVentilation,
        'affectation_ei_dividende',
      );
    }
  } else if (montants['compte_exploitant']! > 0) {
    throw refus(
      MotifRefus.affectationVentilation,
      'affectation_societe_compte_exploitant',
      {'forme': forme.libelle},
    );
  }

  if (!beneficiaire) {
    if (montants['dividendes']! > 0) {
      throw refus(
        MotifRefus.affectationVentilation,
        'affectation_dividende_sur_perte',
      );
    }
    if (montants['reserve_legale']! > 0) {
      throw refus(
        MotifRefus.affectationVentilation,
        'affectation_reserve_legale_sur_perte',
      );
    }
  } else if (montants['imputation_report_crediteur']! > 0) {
    throw refus(
      MotifRefus.affectationVentilation,
      'affectation_imputation_sur_benefice',
    );
  }

  final somme = montants.values.fold<int>(0, (t, m) => t + m);
  if (somme != absolu) {
    throw refus(
      MotifRefus.affectationVentilation,
      'affectation_somme_differente',
      {
        'somme': _decimal(somme),
        'resultat': _decimal(absolu),
        'ecart': _decimal(absolu - somme),
      },
    );
  }

  if (!beneficiaire) {
    for (final poste in const [
      'autres_reserves',
      'imputation_report_crediteur',
    ]) {
      final solde = soldesImputables[poste] ?? 0;
      if (montants[poste]! > solde) {
        throw refus(
          MotifRefus.affectationVentilation,
          'affectation_imputation_excessive',
          {
            'poste': libellePoste(poste),
            'montant': _decimal(montants[poste]!),
            'solde': _decimal(solde > 0 ? solde : 0),
          },
        );
      }
    }
  }

  if (forme.estSociete && beneficiaire && situation != null) {
    // La réserve légale est OBLIGATOIRE tant qu'elle n'atteint pas 20 % du capital.
    if (situation.capital <= 0) {
      avertissements.add(
        MessagesAffectation.dire(
          'comptabilite.affectation_avertissement_capital_indetermine',
        ),
      );
    } else {
      final minimum = reserveLegaleMinimum(situation, resultatCentimes);
      if (minimum != null && montants['reserve_legale']! < minimum) {
        throw refus(
          MotifRefus.affectationVentilation,
          'affectation_reserve_legale_insuffisante',
          {
            'minimum': _decimal(minimum),
            'base': _decimal(resultatCentimes - situation.pertesAnterieures),
            'pertes': _decimal(situation.pertesAnterieures),
            'capital': _decimal(situation.capital),
            'saisi': _decimal(montants['reserve_legale']!),
          },
        );
      }
    }

    // Un dividende ne peut pas entamer le capital ni les réserves non distribuables.
    if (montants['dividendes']! > 0) {
      final apres = situation.capitauxPropres - montants['dividendes']!;
      final plancher =
          situation.capital +
          situation.reserveLegale +
          montants['reserve_legale']! +
          situation.reservesNonDistribuables;
      if (apres < plancher) {
        throw refus(
          MotifRefus.affectationVentilation,
          'affectation_dividende_capitaux_propres',
          {
            'dividendes': _decimal(montants['dividendes']!),
            'apres': _decimal(apres),
            'plancher': _decimal(plancher),
          },
        );
      }
    }
  }
  return (montants: montants, avertissements: avertissements);
}

/// Les lignes de la pièce : le compte du résultat en tête (débité pour un
/// bénéfice, crédité pour une perte), puis chaque poste non nul
/// (`AffectationResultatService::lignes`).
List<LigneAffectation> lignesAffectation({
  required int resultatCentimes,
  required Map<String, int> montants,
  required ComptesAffectation comptes,
}) {
  final beneficiaire = resultatCentimes > 0;
  final absolu = beneficiaire ? resultatCentimes : -resultatCentimes;
  final lignes = <LigneAffectation>[
    (
      compte: beneficiaire ? comptes.benefice : comptes.perte,
      debit: beneficiaire ? absolu : 0,
      credit: beneficiaire ? 0 : absolu,
    ),
  ];
  final roles = beneficiaire
      ? {
          'reserve_legale': comptes.reserveLegale,
          'autres_reserves': comptes.autresReserves,
          'dividendes': comptes.dividendes,
          'report_a_nouveau': comptes.reportCrediteur,
          'compte_exploitant': comptes.exploitant,
        }
      : {
          'autres_reserves': comptes.autresReserves,
          'imputation_report_crediteur': comptes.reportCrediteur,
          'report_a_nouveau': comptes.reportDebiteur,
          'compte_exploitant': comptes.exploitant,
        };
  for (final e in roles.entries) {
    final montant = montants[e.key] ?? 0;
    if (montant <= 0) continue;
    lignes.add((
      compte: e.value,
      debit: beneficiaire ? 0 : montant,
      credit: beneficiaire ? montant : 0,
    ));
  }
  return lignes;
}

/// Les centimes en décimal à deux chiffres, comme `bcadd(.., '0', 2)`
/// (« 70000.00 »).
String _decimal(int centimes) {
  final negatif = centimes < 0;
  final abs = negatif ? -centimes : centimes;
  final entier = abs ~/ 100;
  final reste = (abs % 100).toString().padLeft(2, '0');
  return '${negatif ? '-' : ''}$entier.$reste';
}
