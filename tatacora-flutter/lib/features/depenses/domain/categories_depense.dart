/// Les trois registres FERMÉS de la dépense courante : trésoreries, catégories
/// de dépenses, catégories de charges SYSCOHADA.
///
/// Un registre fermé plutôt qu'une chaîne libre — une valeur ajoutée demain ne
/// doit pas obtenir un comportement par omission. Les trois sont **relevés dans
/// le serveur**, pas écrits de mémoire, et chacun dit où :
///
/// | Registre | Source |
/// |---|---|
/// | Trésoreries | `DepenseService::TRESORERIES` (clés) et le composant (libellés) |
/// | Natures | `Depenses::NATURES` — deux familles, douze natures |
/// | Comptes de charge | le plan du PO installé en base (`plan_comptable_local`), classe 6, 4 chiffres |
///
/// ⚠ **Les numéros de compte ne s'écrivent pas de mémoire.** Le composant PWA
/// en a porté sept — `601`, `614`, `6051`, `6052`, `628`, `5711`, `5311` — qui
/// n'existent dans aucun plan comptable du dépôt. Aucune écriture n'ayant
/// jamais été tentée, la divergence n'a eu aucune occasion de se voir. Depuis la
/// v16 la liste des comptes de charge n'est plus écrite ici : elle est LUE du
/// plan (`MoteurComptable.comptesDeCharge`).
library;

import '../../comptabilite/domain/comptes_syscohada.dart';

/// Les trois comptes de trésorerie du maître — « d'où l'argent est sorti ».
///
/// Le [code] est la clé de `DepenseService::TRESORERIES`, le [libelle] le mot
/// affiché. Les deux sont distincts et le restent : un test serveur les fige, et
/// stocker le libellé casserait le jour où la dépense monterait.
///
/// ## Le compte et le journal sont ceux du serveur, confrontés par PHP
///
/// [compte] et [journal] sont `DepenseService::TRESORERIES` : caisse -> 5711
/// (journal CAI), mobile money -> 552 (journal BQ), banque -> 5211 (journal BQ).
/// Le rattachement du mobile money au journal de banque est un choix
/// d'organisation signalé au Comptable côté serveur, répliqué tel quel ici ; les
/// numéros viennent de `ComptesSyscohada` (« à valider par le comptable »), pas
/// d'une seconde liste. `depenses_contre_serveur_test.dart` EXÉCUTE PHP et
/// exige l'égalité des trois couples.
enum TresorerieDepense {
  caisse('caisse', 'Caisse', ComptesSyscohada.caisse, 'CAI'),
  momo('momo', 'Mobile Money', ComptesSyscohada.mobileMoney, 'BQ'),
  banque('banque', 'Compte bancaire', ComptesSyscohada.banque, 'BQ');

  const TresorerieDepense(this.code, this.libelle, this.compte, this.journal);

  final String code;
  final String libelle;

  /// Le compte de contrepartie de la pièce (crédité par la dépense).
  final String compte;

  /// Le code du journal où la pièce est passée.
  final String journal;

  /// `null` sur un code inconnu — jamais un repli sur « Caisse ».
  ///
  /// Ranger au hasard une dépense dans la caisse fausserait l'indicateur
  /// « Caisse » du maître, qui ne compte que les espèces.
  static TresorerieDepense? depuisCode(String code) {
    for (final t in values) {
      if (t.code == code) return t;
    }
    return null;
  }
}

/// Les deux familles du maître, dans son ordre.
///
/// Elles ne sont pas décoratives : ce sont les deux indicateurs « Marché » et
/// « Services » de la bande, et leur [detail] est le second libellé de la carte.
enum FamilleDepense {
  services('Services', 'charges externes'),
  marche('Marché', 'denrées');

  const FamilleDepense(this.libelle, this.detail);

  final String libelle;

  /// Le sous-titre de la carte d'indicateur — « denrées », « charges externes ».
  final String detail;

  static FamilleDepense? depuisLibelle(String libelle) {
    for (final f in values) {
      if (f.libelle == libelle) return f;
    }
    return null;
  }
}

/// Les douze natures du maître — `Depenses::NATURES`, dans son ordre.
///
/// Ce sont des libellés d'écran, pas une donnée réglementaire : ils classent
/// une dépense en denrées ou en charges externes pour les deux indicateurs.
/// Aucune table de natures n'existe au schéma, côté serveur comme ici.
enum NatureDepense {
  transport('Transport', FamilleDepense.services),
  electriciteEau('Électricité / eau', FamilleDepense.services),
  entretien('Entretien et réparations', FamilleDepense.services),
  communication('Communication', FamilleDepense.services),
  blanchisserie('Blanchisserie', FamilleDepense.services),
  oignon('Oignon', FamilleDepense.marche),
  tomate('Tomate', FamilleDepense.marche),
  piment('Piment', FamilleDepense.marche),
  viande('Viande', FamilleDepense.marche),
  poisson('Poisson', FamilleDepense.marche),
  igname('Igname', FamilleDepense.marche),
  riz('Riz', FamilleDepense.marche);

  const NatureDepense(this.libelle, this.famille);

  final String libelle;

  /// La famille dont cette nature relève. Elle est **recopiée** sur la ligne à
  /// l'enregistrement : déplacer demain une nature d'une famille à l'autre ne
  /// doit pas réécrire les dépenses déjà saisies.
  final FamilleDepense famille;

  static NatureDepense? depuisLibelle(String libelle) {
    for (final n in values) {
      if (n.libelle == libelle) return n;
    }
    return null;
  }

  /// Les natures d'une famille, dans l'ordre du maître — c'est ce qui compose
  /// les groupes de la liste déroulante.
  static List<NatureDepense> deLaFamille(FamilleDepense famille) =>
      values.where((n) => n.famille == famille).toList(growable: false);
}

/// Un compte de charge proposé à la saisie — « Catégorie des charges
/// (SYSCOHADA) ».
///
/// Construit depuis le PLAN installé en base (`CompteDuPlan`), jamais écrit ici.
final class CompteDeCharge {
  const CompteDeCharge(this.numero, this.libelle);

  /// De deux à quatre chiffres au plan du PO ; la **classe** est le premier : elle
  /// vaut toujours 6 ici. Seuls les comptes à quatre chiffres sont proposés
  /// (une division n'est pas imputable).
  final String numero;

  final String libelle;

  /// La forme affichée par la vue dans sa liste : « 6011 — Achats… »
  /// (`depenses.blade.php` l.401, `numero — libelle`).
  String get affichage => '$numero — $libelle';
}

/// Les comptes de l'ANCIEN registre à six chiffres (`601100`…), que les
/// dépenses saisies AVANT la v16 portent encore.
///
/// ## Pourquoi ils sont gardés, et à quoi ils ne servent JAMAIS
///
/// Ils ne servent qu'à NOMMER, à l'affichage, ce qu'une ligne déjà enregistrée
/// a imputé : sans eux, une dépense de l'an dernier s'afficherait « 601100 · — »
/// alors que la ligne a été saisie avec ce libellé. Ils ne sont **jamais
/// proposés** à la saisie, jamais acceptés à l'écriture et jamais convertis en
/// comptes du plan : la correspondance ancien -> nouveau plan n'est pas une
/// décision technique, et la deviner imputerait une charge au mauvais poste sur
/// une pièce validée, donc immuable. Une dépense qui les porte reste « sans
/// pièce comptable » ; son rattrapage est refusé en nommant le compte
/// (`depenses.compte_inconnu`), comme le serveur.
const Map<String, String> comptesDeChargeHistoriques = {
  '601100': 'Achats denrées alimentaires (cuisine)',
  '601200': 'Achats boissons',
  '602100': "Fournitures d'entretien et petit équipement",
  '604000': 'Achats de matériel et fournitures non stockables',
  '605100': 'Carburants et lubrifiants',
  '605200': 'Pièces détachées et fournitures véhicules',
  '611000': 'Transports sur achats',
  '622100': 'Locations diverses',
  '624100': 'Entretien et réparations — bâtiments/équipements',
  '624500': 'Entretien et réparations — véhicules',
  '625000': "Primes d'assurances",
  '627000': 'Publicité, communication, relations publiques',
  '628100': 'Télécommunications (téléphone, Internet)',
  '631000': 'Frais bancaires et assimilés',
  '632000': 'Frais MECeF / plateforme de gestion',
  '641000': 'Impôts et taxes directs (hors personnel)',
  '645100': 'Charges sociales CNSS — part employeur',
  '661000': 'Rémunérations directes du personnel',
  '664000': 'Autres charges sociales',
  '681000': 'Dotations aux amortissements des immobilisations',
};

/// Les libellés des comptes, pour la colonne « Charge (SYSCOHADA) » et l'export.
///
/// Le PLAN d'abord ; à défaut, l'ancien registre à six chiffres
/// ([comptesDeChargeHistoriques]) pour NOMMER une ligne déjà saisie ; à défaut,
/// `null` — l'appelant montre « — », jamais un libellé approché d'un compte
/// voisin.
final class LibellesDesComptes {
  const LibellesDesComptes([this._plan = const {}]);

  final Map<String, String> _plan;

  String? de(String numero) =>
      _plan[numero] ?? comptesDeChargeHistoriques[numero];
}
