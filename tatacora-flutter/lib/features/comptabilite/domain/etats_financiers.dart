/// Compte de résultat et bilan, calculés sur le poste depuis les écritures
/// VALIDÉES du serveur (`ecritures_serveur_local`, v34) — 21/10/2026.
///
/// Le serveur est le seul comptable (D246) : ce calcul n'écrit rien et ne lit
/// que le miroir. Il reprend, au centime, `BalanceGeneraleService`,
/// `CompteResultatService` et `BilanService` (PHP exécuté par
/// `etats_financiers_contre_serveur_test.dart`), sur le seul filtre
/// `validee` : le poste ne reçoit pas les brouillons.
///
/// Les montants sont des CENTIMES entiers ; le signe est celui de la cascade
/// du serveur : un produit est positif, une charge négative.
library;

import '../data/ecritures_serveur_dao.dart';
import 'entities/comptabilite.dart';

/// Un compte de la balance : ses totaux, jamais son solde (il se déduit).
final class LigneBalanceEtat {
  const LigneBalanceEtat({
    required this.numeroCompte,
    required this.libelle,
    required this.classe,
    required this.debitCentimes,
    required this.creditCentimes,
  });

  final String numeroCompte;
  final String libelle;
  final String classe;
  final int debitCentimes;
  final int creditCentimes;
}

/// Un compte du plan, pour nommer les comptes de résultat (131 / 139) que les
/// à-nouveaux provisoires font naître.
final class CompteDeReport {
  const CompteDeReport({required this.libelle, required this.classe});

  final String libelle;
  final String classe;
}

/// La balance d'un exercice, sans le journal de clôture `CL`.
final class BalanceEtat {
  const BalanceEtat({
    required this.lignes,
    required this.aNouveauxProvisoiresDe,
  });

  final List<LigneBalanceEtat> lignes;

  /// L'année dont les soldes ont été reportés PROVISOIREMENT (son exercice
  /// n'est pas clôturé), sinon `null`.
  final int? aNouveauxProvisoiresDe;
}

enum SensRubrique { produit, charge, solde }

/// Une rubrique de la cascade des soldes intermédiaires de gestion.
final class RubriqueCascade {
  const RubriqueCascade(
    this.code,
    this.libelle,
    this.sens, {
    this.prefixes = const [],
    this.composants = const [],
  });

  final String code;
  final String libelle;
  final SensRubrique sens;
  final List<String> prefixes;
  final List<String> composants;

  bool get estSolde => composants.isNotEmpty;
}

/// `SoldesIntermediairesGestion::CASCADE`, dans l'ordre. Relue du serveur par
/// un test : une rubrique ajoutée là-bas fait rougir ici.
const cascadeResultat = <RubriqueCascade>[
  RubriqueCascade(
    'TA',
    'Ventes de marchandises',
    SensRubrique.produit,
    prefixes: ['701'],
  ),
  RubriqueCascade(
    'RA',
    'Achats de marchandises',
    SensRubrique.charge,
    prefixes: ['601'],
  ),
  RubriqueCascade(
    'RB',
    'Variation de stocks de marchandises',
    SensRubrique.charge,
    prefixes: ['6031'],
  ),
  RubriqueCascade(
    'XA',
    'MARGE COMMERCIALE',
    SensRubrique.solde,
    composants: ['TA', 'RA', 'RB'],
  ),
  RubriqueCascade(
    'TB',
    'Ventes de produits fabriqués',
    SensRubrique.produit,
    prefixes: ['702'],
  ),
  RubriqueCascade(
    'TC',
    'Travaux et services vendus',
    SensRubrique.produit,
    prefixes: ['705', '706'],
  ),
  RubriqueCascade(
    'TD',
    'Produits accessoires',
    SensRubrique.produit,
    prefixes: ['707'],
  ),
  RubriqueCascade(
    'XB',
    "CHIFFRE D'AFFAIRES",
    SensRubrique.solde,
    composants: ['TA', 'TB', 'TC', 'TD'],
  ),
  RubriqueCascade(
    'TE',
    'Production stockée (ou déstockage)',
    SensRubrique.produit,
    prefixes: ['73'],
  ),
  RubriqueCascade(
    'TF',
    'Production immobilisée',
    SensRubrique.produit,
    prefixes: ['72'],
  ),
  RubriqueCascade(
    'TG',
    "Subventions d'exploitation",
    SensRubrique.produit,
    prefixes: ['71'],
  ),
  RubriqueCascade(
    'TH',
    'Autres produits',
    SensRubrique.produit,
    prefixes: ['75'],
  ),
  RubriqueCascade(
    'TI',
    "Transferts de charges d'exploitation",
    SensRubrique.produit,
    prefixes: ['781'],
  ),
  RubriqueCascade(
    'RC',
    'Achats de matières premières et fournitures liées',
    SensRubrique.charge,
    prefixes: ['602'],
  ),
  RubriqueCascade(
    'RD',
    'Variation de stocks de matières premières',
    SensRubrique.charge,
    prefixes: ['6032'],
  ),
  RubriqueCascade(
    'RE',
    'Autres achats',
    SensRubrique.charge,
    prefixes: ['604', '605', '608'],
  ),
  RubriqueCascade(
    'RF',
    "Variation de stocks d'autres approvisionnements",
    SensRubrique.charge,
    prefixes: ['6033'],
  ),
  RubriqueCascade('RG', 'Transports', SensRubrique.charge, prefixes: ['61']),
  RubriqueCascade(
    'RH',
    'Services extérieurs',
    SensRubrique.charge,
    prefixes: ['62', '63'],
  ),
  RubriqueCascade(
    'RI',
    'Impôts et taxes',
    SensRubrique.charge,
    prefixes: ['64'],
  ),
  RubriqueCascade(
    'RJ',
    'Autres charges',
    SensRubrique.charge,
    prefixes: ['65'],
  ),
  RubriqueCascade(
    'XC',
    'VALEUR AJOUTÉE',
    SensRubrique.solde,
    composants: [
      'XB', 'TE', 'TF', 'TG', 'TH', 'TI', //
      'RA', 'RB', 'RC', 'RD', 'RE', 'RF', 'RG', 'RH', 'RI', 'RJ',
    ],
  ),
  RubriqueCascade(
    'RK',
    'Charges de personnel',
    SensRubrique.charge,
    prefixes: ['66'],
  ),
  RubriqueCascade(
    'XD',
    "EXCÉDENT BRUT D'EXPLOITATION",
    SensRubrique.solde,
    composants: ['XC', 'RK'],
  ),
  RubriqueCascade(
    'TJ',
    "Reprises d'amortissements, provisions et dépréciations",
    SensRubrique.produit,
    prefixes: ['791', '798'],
  ),
  RubriqueCascade(
    'RL',
    'Dotations aux amortissements, provisions et dépréciations',
    SensRubrique.charge,
    prefixes: ['681', '691'],
  ),
  RubriqueCascade(
    'XE',
    "RÉSULTAT D'EXPLOITATION",
    SensRubrique.solde,
    composants: ['XD', 'TJ', 'RL'],
  ),
  RubriqueCascade(
    'TK',
    'Revenus financiers et assimilés',
    SensRubrique.produit,
    prefixes: ['77'],
  ),
  RubriqueCascade(
    'TM',
    'Transferts de charges financières',
    SensRubrique.produit,
    prefixes: ['787'],
  ),
  RubriqueCascade(
    'RM',
    'Frais financiers et charges assimilées',
    SensRubrique.charge,
    prefixes: ['67'],
  ),
  RubriqueCascade(
    'RN',
    'Dotations aux provisions et dépréciations financières',
    SensRubrique.charge,
    prefixes: ['697'],
  ),
  RubriqueCascade(
    'XF',
    'RÉSULTAT FINANCIER',
    SensRubrique.solde,
    composants: ['TK', 'TM', 'RM', 'RN'],
  ),
  RubriqueCascade(
    'XG',
    'RÉSULTAT DES ACTIVITÉS ORDINAIRES',
    SensRubrique.solde,
    composants: ['XE', 'XF'],
  ),
  RubriqueCascade(
    'TN',
    "Produits des cessions d'immobilisations",
    SensRubrique.produit,
    prefixes: ['82'],
  ),
  RubriqueCascade(
    'TO',
    'Autres produits HAO',
    SensRubrique.produit,
    prefixes: ['84', '86', '88'],
  ),
  RubriqueCascade(
    'RO',
    "Valeurs comptables des cessions d'immobilisations",
    SensRubrique.charge,
    prefixes: ['81'],
  ),
  RubriqueCascade(
    'RP',
    'Autres charges HAO',
    SensRubrique.charge,
    prefixes: ['83', '85'],
  ),
  RubriqueCascade(
    'XH',
    'RÉSULTAT HORS ACTIVITÉS ORDINAIRES',
    SensRubrique.solde,
    composants: ['TN', 'TO', 'RO', 'RP'],
  ),
  RubriqueCascade(
    'RQ',
    'Participation des travailleurs',
    SensRubrique.charge,
    prefixes: ['87'],
  ),
  RubriqueCascade(
    'RS',
    'Impôts sur le résultat',
    SensRubrique.charge,
    prefixes: ['89'],
  ),
  RubriqueCascade(
    'XI',
    'RÉSULTAT NET',
    SensRubrique.solde,
    composants: ['XG', 'XH', 'RQ', 'RS'],
  ),
];

/// `RubriquesSyscohada` : les préfixes du bilan. Relus du serveur par un test.
abstract final class RubriquesBilan {
  static const immobilisationsBrutes = ['231', '234', '244', '245'];
  static const amortissements = ['28'];
  static const stocks = ['31', '32'];
  static const creances = ['411'];
  static const tresorerieActif = ['521', '522', '55', '571', '572', '573'];
  static const capital = ['101'];
  static const resultatReporte = ['131', '139'];
  static const dettesCirculantes = ['401', '4191', '421', '422', '431', '447'];
  static const tresoreriePassif = ['561', '564', '565', '566'];

  static List<String> get tous => [
    ...immobilisationsBrutes,
    ...amortissements,
    ...stocks,
    ...creances,
    ...tresorerieActif,
    ...capital,
    ...resultatReporte,
    ...dettesCirculantes,
    ...tresoreriePassif,
  ];
}

/// Le code de l'impôt, du résultat avant impôt et du résultat net.
const codeImpot = 'RS';
const codeResultatNet = 'XI';

bool _releveDe(String numeroCompte, List<String> prefixes) =>
    prefixes.any(numeroCompte.startsWith);

/// Une ligne du compte de résultat.
final class LigneResultatEtat {
  const LigneResultatEtat({
    required this.rubrique,
    required this.montantCentimes,
  });

  final RubriqueCascade rubrique;

  /// Signé : positif pour un produit, négatif pour une charge.
  final int montantCentimes;
}

final class CompteResultatEtat {
  const CompteResultatEtat({
    required this.lignes,
    required this.resultatAvantImpotCentimes,
    required this.impotCentimes,
    required this.resultatNetCentimes,
    required this.aNouveauxProvisoiresDe,
  });

  final List<LigneResultatEtat> lignes;
  final int resultatAvantImpotCentimes;
  final int impotCentimes;
  final int resultatNetCentimes;
  final int? aNouveauxProvisoiresDe;

  /// Aucun impôt en classe 89 : le « résultat net » est AVANT impôt.
  bool get impotNonComptabilise => impotCentimes == 0;

  int? montant(String code) {
    for (final l in lignes) {
      if (l.rubrique.code == code) return l.montantCentimes;
    }
    return null;
  }
}

enum SectionBilan { actif, passif }

final class PosteBilanEtat {
  const PosteBilanEtat({
    required this.section,
    required this.code,
    required this.libelle,
    required this.brutCentimes,
    required this.amortissementCentimes,
    required this.prefixes,
  });

  final SectionBilan section;
  final String code;
  final String libelle;
  final int brutCentimes;
  final int amortissementCentimes;
  final List<String> prefixes;

  int get netCentimes => brutCentimes - amortissementCentimes;
}

final class CompteHorsRubrique {
  const CompteHorsRubrique({
    required this.numeroCompte,
    required this.libelle,
    required this.soldeCentimes,
  });

  final String numeroCompte;
  final String libelle;
  final int soldeCentimes;
}

final class BilanEtat {
  const BilanEtat({
    required this.actif,
    required this.passif,
    required this.comptesHorsRubrique,
    required this.resultatExerciceCentimes,
    required this.impotNonComptabilise,
    required this.aNouveauxProvisoiresDe,
  });

  final List<PosteBilanEtat> actif;
  final List<PosteBilanEtat> passif;
  final List<CompteHorsRubrique> comptesHorsRubrique;
  final int resultatExerciceCentimes;
  final bool impotNonComptabilise;
  final int? aNouveauxProvisoiresDe;

  int get totalActifBrutCentimes => _somme(actif, (p) => p.brutCentimes);
  int get totalActifAmortissementCentimes =>
      _somme(actif, (p) => p.amortissementCentimes);
  int get totalActifCentimes => _somme(actif, (p) => p.netCentimes);
  int get totalPassifCentimes => _somme(passif, (p) => p.netCentimes);
  int get ecartCentimes => totalActifCentimes - totalPassifCentimes;
  bool get equilibre => ecartCentimes == 0;

  static int _somme(
    List<PosteBilanEtat> postes,
    int Function(PosteBilanEtat) champ,
  ) => postes.fold(0, (t, p) => t + champ(p));
}

/// Les écritures validées reçues, par année d'exercice, et le statut de
/// chaque exercice connu du poste.
final class DonneesEtats {
  const DonneesEtats({
    required this.ecrituresParAnnee,
    required this.statutParAnnee,
    required this.plan,
  });

  final Map<int, List<EcritureServeur>> ecrituresParAnnee;

  /// Un exercice absent de cette table n'existe pas : pas de N-1 pour lui, pas
  /// de report provisoire.
  final Map<int, StatutExercice> statutParAnnee;

  /// Pour nommer 131 / 139 quand un report provisoire en a besoin.
  final Map<String, CompteDeReport> plan;

  bool existe(int annee) => statutParAnnee.containsKey(annee);
}

/// `BalanceGeneraleService` sur le filtre `validee`.
BalanceEtat balanceDe(int annee, DonneesEtats d) {
  final comptes =
      <String, ({String libelle, String classe, int debit, int credit})>{};
  for (final e in d.ecrituresParAnnee[annee] ?? const <EcritureServeur>[]) {
    // Le journal de clôture se lit APRÈS clôture, jamais dans la balance
    // courante : il ramène les comptes de gestion à zéro.
    if (e.codeJournal == 'CL') continue;
    final c = comptes[e.numeroCompte];
    comptes[e.numeroCompte] = (
      libelle: c?.libelle ?? e.libelleCompte,
      classe: c?.classe ?? e.classe,
      debit: (c?.debit ?? 0) + e.debitCentimes,
      credit: (c?.credit ?? 0) + e.creditCentimes,
    );
  }

  int? provisoireDe;
  final precedent = annee - 1;
  if (d.existe(precedent) &&
      d.statutParAnnee[precedent] != StatutExercice.cloture) {
    provisoireDe = precedent;
    var resultat = 0;
    final ajouts = <(String, String, String, int)>[];
    for (final l in balanceDe(precedent, d).lignes) {
      final net = l.debitCentimes - l.creditCentimes;
      if (const ['6', '7', '8'].contains(l.classe)) {
        resultat -= net;
        continue;
      }
      ajouts.add((l.numeroCompte, l.libelle, l.classe, net));
    }
    if (resultat != 0) {
      final numero = resultat > 0 ? '131' : '139';
      final compte = d.plan[numero];
      if (compte != null) {
        ajouts.add((numero, compte.libelle, compte.classe, -resultat));
      }
    }
    for (final (numero, libelle, classe, net) in ajouts) {
      if (net == 0) continue;
      final c = comptes[numero];
      comptes[numero] = (
        libelle: c?.libelle ?? libelle,
        classe: c?.classe ?? classe,
        debit: (c?.debit ?? 0) + (net > 0 ? net : 0),
        credit: (c?.credit ?? 0) + (net < 0 ? -net : 0),
      );
    }
  }

  final numeros = comptes.keys.toList()..sort();
  return BalanceEtat(
    lignes: [
      for (final n in numeros)
        LigneBalanceEtat(
          numeroCompte: n,
          libelle: comptes[n]!.libelle,
          classe: comptes[n]!.classe,
          debitCentimes: comptes[n]!.debit,
          creditCentimes: comptes[n]!.credit,
        ),
    ],
    aNouveauxProvisoiresDe: provisoireDe,
  );
}

int _sommeCreditrice(List<LigneBalanceEtat> lignes, List<String> prefixes) {
  var total = 0;
  for (final l in lignes) {
    if (_releveDe(l.numeroCompte, prefixes)) {
      total += l.creditCentimes - l.debitCentimes;
    }
  }
  return total;
}

int _sommeDebitrice(List<LigneBalanceEtat> lignes, List<String> prefixes) =>
    -_sommeCreditrice(lignes, prefixes);

/// `CompteResultatService` : la cascade, sans taux d'impôt (PA-19).
CompteResultatEtat compteResultatDe(int annee, DonneesEtats d) {
  final balance = balanceDe(annee, d);
  final valeurs = <String, int>{};
  final lignes = <LigneResultatEtat>[];
  for (final r in cascadeResultat) {
    final montant = r.estSolde
        ? r.composants.fold<int>(0, (t, c) {
            final v = valeurs[c];
            if (v == null) {
              throw StateError(
                'Cascade SIG mal ordonnée : ${r.code} cite $c, non calculé.',
              );
            }
            return t + v;
          })
        : _sommeCreditrice(balance.lignes, r.prefixes);
    valeurs[r.code] = montant;
    lignes.add(LigneResultatEtat(rubrique: r, montantCentimes: montant));
  }
  final impot = valeurs[codeImpot]!;
  return CompteResultatEtat(
    lignes: lignes,
    resultatAvantImpotCentimes: valeurs['XG']! + valeurs['XH']!,
    impotCentimes: impot,
    resultatNetCentimes: valeurs[codeResultatNet]!,
    aNouveauxProvisoiresDe: balance.aNouveauxProvisoiresDe,
  );
}

/// `BilanService` : trois postes d'actif, trois de passif, par préfixe.
BilanEtat bilanDe(int annee, DonneesEtats d) {
  final balance = balanceDe(annee, d);
  final resultat = compteResultatDe(annee, d);
  final lignes = balance.lignes;

  PosteBilanEtat sans(
    SectionBilan section,
    String code,
    String libelle,
    int montant,
    List<String> prefixes,
  ) => PosteBilanEtat(
    section: section,
    code: code,
    libelle: libelle,
    brutCentimes: montant,
    amortissementCentimes: 0,
    prefixes: prefixes,
  );

  final prefixesCirculant = [
    ...RubriquesBilan.stocks,
    ...RubriquesBilan.creances,
  ];
  final actif = [
    PosteBilanEtat(
      section: SectionBilan.actif,
      code: 'actif_immobilise',
      libelle: 'Actif immobilisé',
      brutCentimes: _sommeDebitrice(
        lignes,
        RubriquesBilan.immobilisationsBrutes,
      ),
      amortissementCentimes: _sommeCreditrice(
        lignes,
        RubriquesBilan.amortissements,
      ),
      prefixes: [
        ...RubriquesBilan.immobilisationsBrutes,
        ...RubriquesBilan.amortissements,
      ],
    ),
    sans(
      SectionBilan.actif,
      'actif_circulant',
      'Actif circulant',
      _sommeDebitrice(lignes, prefixesCirculant),
      prefixesCirculant,
    ),
    sans(
      SectionBilan.actif,
      'tresorerie_actif',
      'Trésorerie-Actif',
      _sommeDebitrice(lignes, RubriquesBilan.tresorerieActif),
      RubriquesBilan.tresorerieActif,
    ),
  ];

  final capital = _sommeCreditrice(lignes, RubriquesBilan.capital);
  final reporte = _sommeCreditrice(lignes, RubriquesBilan.resultatReporte);
  final resultatExercice = reporte + resultat.resultatNetCentimes;
  final passif = [
    sans(
      SectionBilan.passif,
      'capitaux_propres',
      'Capitaux propres',
      capital + resultatExercice,
      [...RubriquesBilan.capital, ...RubriquesBilan.resultatReporte],
    ),
    sans(
      SectionBilan.passif,
      'passif_circulant',
      'Passif circulant',
      _sommeCreditrice(lignes, RubriquesBilan.dettesCirculantes),
      RubriquesBilan.dettesCirculantes,
    ),
    sans(
      SectionBilan.passif,
      'tresorerie_passif',
      'Trésorerie-Passif',
      _sommeCreditrice(lignes, RubriquesBilan.tresoreriePassif),
      RubriquesBilan.tresoreriePassif,
    ),
  ];

  final connus = [
    ...RubriquesBilan.tous,
    for (final r in cascadeResultat) ...r.prefixes,
  ];
  return BilanEtat(
    actif: actif,
    passif: passif,
    comptesHorsRubrique: [
      for (final l in lignes)
        if (!_releveDe(l.numeroCompte, connus))
          CompteHorsRubrique(
            numeroCompte: l.numeroCompte,
            libelle: l.libelle,
            soldeCentimes: l.debitCentimes - l.creditCentimes,
          ),
    ],
    resultatExerciceCentimes: resultatExercice,
    impotNonComptabilise: resultat.impotNonComptabilise,
    aNouveauxProvisoiresDe: balance.aNouveauxProvisoiresDe,
  );
}
