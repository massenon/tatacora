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
/// ## La réserve légale est une PROPOSITION
///
/// 10 % du bénéfice tant que la réserve légale n'atteint pas 20 % du capital ;
/// modifiable, jamais bloquante ; capital non déterminable : rien n'est proposé.
library;

import 'cloture_exercice.dart';
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
];

/// Ceux d'un bénéfice et ceux d'une perte (`POSTES_BENEFICE` / `POSTES_PERTE`).
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

/// Le préfixe du capital lu au plan (`RubriquesSyscohada::CAPITAL`).
const prefixesCapital = ['101'];

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
});

/// Une ligne de la pièce : un compte, un débit OU un crédit (centimes).
typedef LigneAffectation = ({String compte, int debit, int credit});

/// La ventilation PROPOSÉE : bénéfice → réserve légale à 10 % tant qu'elle
/// n'atteint pas 20 % du capital, le reste en report à nouveau ; perte → tout en
/// report à nouveau débiteur (`AffectationResultatService::proposer`).
///
/// [capitalCentimes] et [reserveLegaleCentimes] sont des SOLDES CRÉDITEURS de N
/// (capital 101x, compte de la réserve légale) ; un capital nul ou négatif
/// n'est pas « déterminable » : aucune réserve légale n'est proposée.
({Map<String, int> ventilation, bool reserveLegalePropose, bool plafondAtteint})
proposerVentilation({
  required int resultatCentimes,
  required int capitalCentimes,
  required int reserveLegaleCentimes,
}) {
  final ventilation = {for (final p in postesAffectation) p: 0};
  if (resultatCentimes <= 0) {
    ventilation['report_a_nouveau'] = -resultatCentimes;
    return (
      ventilation: ventilation,
      reserveLegalePropose: false,
      plafondAtteint: false,
    );
  }
  var reserve = 0;
  var propose = false;
  var plafondAtteint = false;
  if (capitalCentimes > 0) {
    propose = true;
    // `bcmul(.., '0.20', 2)` et `bcmul(.., '0.10', 2)` TRONQUENT à deux
    // décimales : en centimes, une division entière.
    final plafond = capitalCentimes ~/ 5;
    final place = plafond - reserveLegaleCentimes;
    if (place <= 0) {
      plafondAtteint = true;
    } else {
      final dix = resultatCentimes ~/ 10;
      reserve = dix <= place ? dix : place;
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
/// négatif, postes admis (dividende / réserve légale refusés sur une perte),
/// SOMME EXACTE, imputation dans la limite du solde. Rend les montants de tous
/// les postes ; LÈVE [RefusComptable] à la phrase du serveur.
///
/// [soldesImputables] : solde créditeur (centimes) des comptes que l'imputation
/// d'une perte débite — `autres_reserves` et `imputation_report_crediteur`.
Map<String, int> controlerVentilation({
  required Map<String, int> ventilation,
  required int resultatCentimes,
  required Map<String, int> soldesImputables,
}) {
  final beneficiaire = resultatCentimes > 0;
  final absolu = beneficiaire ? resultatCentimes : -resultatCentimes;
  final montants = {for (final p in postesAffectation) p: 0};

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
  return montants;
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
        }
      : {
          'autres_reserves': comptes.autresReserves,
          'imputation_report_crediteur': comptes.reportCrediteur,
          'report_a_nouveau': comptes.reportDebiteur,
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
