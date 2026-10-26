/// La CORRESPONDANCE rôle -> compte comptable, modifiable (décision du PO du
/// 26/10/2026 : « on peut impérativement modifier les comptes sur poste et le
/// web »). RÉPLIQUE de `RolesCorrespondance` et de `CorrespondanceComptesService`
/// du serveur, et de `lang/fr/comptes_correspondance.php`.
///
/// ## Comment on sait que la copie ne diverge pas
///
/// `correspondance_comptes_contre_serveur_test.dart` EXÉCUTE PHP
/// (`tool/comptabilite/exporter_correspondance.php`) et exige, rôle par rôle,
/// le même groupe, le même libellé, la même aide, les mêmes préfixes de compte,
/// la même clé de paramètre et le même défaut ; chaque gabarit de langue est
/// confronté mot pour mot. `rejouer_correspondance.php` rejoue la VALIDATION
/// contre le vrai service : mêmes refus, mêmes phrases.
///
/// ## Ce qu'un rôle EST
///
/// Un nom (la constante de `ComptesSyscohada`), un compte par défaut, et ce que
/// la validation en dit : les PRÉFIXES de numéro admis (« classe cohérente avec
/// le rôle » : un produit est de classe 7, la TVA collectée de 443, une
/// trésorerie de classe 5…). Sa valeur choisie vit dans le paramètre
/// `compte_<rôle en minuscules>` (`parametres_systeme_local`), écrit par le seul
/// `EnregistrerParametres`, synchronisé comme les autres paramètres (dernier
/// écrit gagnant, clé par clé).
///
/// ## Les comptes de CHARGE n'y sont pas
///
/// Le compte d'une charge se choisit LIGNE PAR LIGNE à la saisie d'une dépense :
/// `ComptesSyscohada.achatsMarchandises` et consorts ne servent qu'à la
/// démonstration. Les déclarer modifiables serait offrir un réglage que aucune
/// pièce ne lit (PA-59/60/61).
///
/// @see RG-10 paramétrage sans déploiement
/// @see RG-11 une pièce déjà passée n'est jamais réécrite
library;

import 'comptes_syscohada.dart';
import 'entities/comptabilite.dart';
import 'messages_comptables.dart';
import 'regle_numero_compte.dart';

/// Un rôle comptable modifiable.
final class RoleCompte {
  const RoleCompte({
    required this.code,
    required this.groupe,
    required this.libelle,
    required this.aide,
    required this.prefixes,
  });

  /// Le nom de la constante de `ComptesSyscohada` : `PRODUIT_LOCATIONS`.
  final String code;
  final String groupe;
  final String libelle;
  final String aide;

  /// Les débuts de numéro admis pour ce rôle (`['443']`, `['7']`…).
  final List<String> prefixes;

  /// La clé du paramètre qui porte le compte choisi : `compte_produit_locations`.
  String get cle => RolesCorrespondance.cle(code);

  /// Le compte par défaut : la constante de `ComptesSyscohada`.
  String get defaut => ComptesSyscohada.tous[code]!;
}

abstract final class RolesCorrespondance {
  static const String prefixeCle = 'compte_';

  static const String groupeProduits = 'produits';
  static const String groupeTva = 'tva';
  static const String groupeTresorerie = 'tresorerie';
  static const String groupeTiers = 'tiers';
  static const String groupeResultat = 'resultat';

  /// L'ordre des groupes à l'écran (`RolesCorrespondance::GROUPES`).
  static const List<String> groupes = [
    groupeProduits,
    groupeTva,
    groupeTresorerie,
    groupeTiers,
    groupeResultat,
  ];

  /// Les rôles, dans l'ordre de `RolesCorrespondance::ROLES` du serveur.
  static const List<RoleCompte> roles = [
    RoleCompte(
      code: 'PRODUIT_PRESTATIONS',
      groupe: groupeProduits,
      libelle: 'Produits du restaurant',
      aide: 'Crédité par une vente du restaurant au comptoir.',
      prefixes: ['7'],
    ),
    RoleCompte(
      code: 'PRODUIT_MARCHANDISES',
      groupe: groupeProduits,
      libelle: 'Produits du bar',
      aide: 'Crédité par une vente de boissons au comptoir.',
      prefixes: ['7'],
    ),
    RoleCompte(
      code: 'PRODUIT_LOCATIONS',
      groupe: groupeProduits,
      libelle: 'Produits de la location de véhicules',
      aide: 'Crédité par une location encaissée au comptoir.',
      prefixes: ['7'],
    ),
    RoleCompte(
      code: 'PRODUIT_CIRCUITS',
      groupe: groupeProduits,
      libelle: 'Produits du tourisme, circuits',
      aide: 'Crédité par un circuit encaissé au comptoir.',
      prefixes: ['7'],
    ),
    RoleCompte(
      code: 'TVA_FACTUREE_BIENS',
      groupe: groupeTva,
      libelle: 'TVA facturée sur les ventes de biens (bar)',
      aide:
          'Crédité par la part de TVA d’une vente de boissons ; lu par la déclaration de TVA.',
      prefixes: ['443'],
    ),
    RoleCompte(
      code: 'TVA_FACTUREE_PRESTATIONS',
      groupe: groupeTva,
      libelle:
          'TVA facturée sur les prestations (restaurant, location, tourisme)',
      aide:
          'Crédité par la part de TVA d’une prestation de services ; lu par la déclaration de TVA.',
      prefixes: ['443'],
    ),
    RoleCompte(
      code: 'TVA_RECUPERABLE_ACHATS',
      groupe: groupeTva,
      libelle: 'TVA récupérable sur les achats',
      aide: 'Lu par la déclaration de TVA, au titre de la TVA déductible.',
      prefixes: ['445'],
    ),
    RoleCompte(
      code: 'CAISSE',
      groupe: groupeTresorerie,
      libelle: 'Caisse',
      aide: 'Trésorerie des règlements en espèces.',
      prefixes: ['5'],
    ),
    RoleCompte(
      code: 'BANQUE',
      groupe: groupeTresorerie,
      libelle: 'Banque',
      aide: 'Trésorerie des règlements par carte, virement ou chèque.',
      prefixes: ['5'],
    ),
    RoleCompte(
      code: 'MOBILE_MONEY',
      groupe: groupeTresorerie,
      libelle: 'Mobile Money',
      aide: 'Trésorerie des règlements par Mobile Money.',
      prefixes: ['5'],
    ),
    RoleCompte(
      code: 'CLIENTS',
      groupe: groupeTiers,
      libelle: 'Clients',
      aide:
          'Débité par une vente portée sur la note de chambre, crédité par l’encaissement d’une facture.',
      prefixes: ['411'],
    ),
    RoleCompte(
      code: 'FOURNISSEURS',
      groupe: groupeTiers,
      libelle: 'Fournisseurs',
      aide: 'Débité par le règlement d’une commande fournisseur.',
      prefixes: ['401'],
    ),
    RoleCompte(
      code: 'AVANCES_CLIENTS',
      groupe: groupeTiers,
      libelle: 'Avances et acomptes clients',
      aide:
          'Crédité par l’acompte d’une réservation, débité par son remboursement.',
      prefixes: ['419'],
    ),
    RoleCompte(
      code: 'RESULTAT_BENEFICE',
      groupe: groupeResultat,
      libelle: 'Résultat net : bénéfice',
      aide: 'Crédité par la clôture d’un exercice qui dégage un bénéfice.',
      prefixes: ['13'],
    ),
    RoleCompte(
      code: 'RESULTAT_PERTE',
      groupe: groupeResultat,
      libelle: 'Résultat net : perte',
      aide: 'Débité par la clôture d’un exercice qui dégage une perte.',
      prefixes: ['13'],
    ),
  ];

  /// La clé du paramètre d'un rôle : `compte_produit_locations`.
  static String cle(String code) => '$prefixeCle${code.toLowerCase()}';

  static RoleCompte? parCode(String code) {
    for (final r in roles) {
      if (r.code == code) return r;
    }
    return null;
  }

  /// Le rôle d'une clé de paramètre, ou `null` si ce n'est pas une clé de rôle
  /// (jamais un rôle deviné).
  static RoleCompte? parCle(String cle) {
    for (final r in roles) {
      if (r.cle == cle) return r;
    }
    return null;
  }

  static bool estCleDeRole(String cle) => parCle(cle) != null;

  /// Ce qu'un rôle attend, en mots : « est de la classe 7 » ou « commence par
  /// 443 » (`CorrespondanceComptesService::attendu`).
  static String attendu(List<String> prefixes) => prefixes
      .map(
        (p) => p.length == 1
            ? MessagesCorrespondance.dire('attendu_classe', {'classe': p})
            : MessagesCorrespondance.dire('attendu_prefixe', {'prefixe': p}),
      )
      .join(MessagesCorrespondance.dire('attendu_ou'));
}

/// Les phrases de l'écran « Correspondance des comptes » et de ses refus —
/// RECOPIÉES MOT POUR MOT de `lang/fr/comptes_correspondance.php` du serveur.
/// Le test les relit de ce fichier par PHP et exige l'égalité, des deux côtés.
abstract final class MessagesCorrespondance {
  static const gabarits = <String, String>{
    'compte_absent':
        'Le compte :numero n’existe pas au plan comptable. Choisissez un compte du plan : un numéro saisi de mémoire imputerait les pièces futures sur un compte que le plan ne connaît pas.',
    'compte_incoherent':
        'Le compte :numero ne convient pas au rôle « :role » : le numéro attendu :attendu.',
    'attendu_classe': 'est de la classe :classe',
    'attendu_prefixe': 'commence par :prefixe',
    'attendu_ou': ' ou ',
    'titre': 'Correspondance des comptes',
    'titre_page': 'Correspondance des comptes — TATACORA AFRIQUE',
    'sous_titre':
        'Le compte que chaque pièce automatique utilise pour chaque rôle',
    'avertissement':
        'Un changement vaut pour les pièces futures. Une pièce déjà passée n’est jamais réécrite : elle reste sur le compte où elle a été passée.',
    'colonne_role': 'Rôle',
    'colonne_compte': 'Compte actuel',
    'colonne_defaut': 'Par défaut',
    'colonne_action': 'Action',
    'groupe_produits': 'Produits des ventes',
    'groupe_tva': 'TVA',
    'groupe_tresorerie': 'Trésoreries',
    'groupe_tiers': 'Tiers',
    'groupe_resultat': 'Résultat de l’exercice',
    'modifier': 'Modifier',
    'etat_defaut': 'Défaut',
    'etat_modifie': 'Modifié',
    'libelle_inconnu': 'Compte absent du plan',
    'modale_titre': 'Modifier le compte du rôle',
    'champ_compte': 'Numéro de compte',
    'champ_compte_requis':
        'Saisissez un numéro de compte, ou rétablissez le défaut.',
    'champ_compte_aide':
        'De deux à quatre chiffres, un compte du plan comptable.',
    'role_attendu': 'Numéro attendu : :attendu.',
    'defaut_rappel': 'Compte par défaut : :defaut.',
    'retablir': 'Rétablir le défaut',
    'enregistrer': 'Enregistrer',
    'annuler': 'Annuler',
    'enregistre':
        'Correspondance enregistrée : les pièces futures utiliseront le compte :numero.',
    'retabli':
        'Défaut rétabli : les pièces futures utiliseront le compte :numero.',
    'aucun_changement': 'Aucune valeur modifiée.',
    'lecture_seule':
        'Vous pouvez consulter cette correspondance, pas la modifier.',
    'lien_hub': 'Correspondance des comptes',
  };

  /// La phrase de la clé [cle], variables remplacées comme Laravel le fait
  /// (`MessagesComptables.remplacer`). Une clé inconnue LÈVE : rendre la clé
  /// brute à l'écran serait un message plausible et faux.
  static String dire(String cle, [Map<String, String> variables = const {}]) {
    final gabarit = gabarits[cle];
    if (gabarit == null) {
      throw ArgumentError.value(cle, 'cle', 'Clé de langue inconnue.');
    }
    return MessagesComptables.remplacer(gabarit, variables);
  }
}

/// Les QUATRE refus de la correspondance, dans l'ordre du serveur
/// (`CorrespondanceComptesService::verifier`) : le format du numéro (la règle
/// unique `RegleNumeroCompte`), l'existence au plan, la classe cohérente avec
/// le rôle, puis un compte imputable (une division ne reçoit aucun mouvement).
///
/// Fonction PURE : [compte] est le compte du plan portant [numero] (`null` si
/// absent) et [aDesSousComptes] dit s'il a des sous-comptes — l'appelant lit la
/// base, la règle se teste sans elle. Rend la phrase du refus, ou `null`.
String? verifierCompteDuRoleSurPlan({
  required RoleCompte role,
  required String numero,
  required CompteDuPlan? compte,
  required bool aDesSousComptes,
}) {
  if (!RegleNumeroCompte.format.hasMatch(numero)) {
    return MessagesComptables.dire('comptabilite.compte_numero_invalide', {
      'numero': numero,
    });
  }
  if (compte == null) {
    return MessagesCorrespondance.dire('compte_absent', {'numero': numero});
  }
  if (!role.prefixes.any(numero.startsWith)) {
    return MessagesCorrespondance.dire('compte_incoherent', {
      'numero': numero,
      'role': role.libelle,
      'attendu': RolesCorrespondance.attendu(role.prefixes),
    });
  }
  if (numero.length < 4 && aDesSousComptes) {
    return MessagesComptables.dire('comptabilite.compte_division', {
      'numero': numero,
    });
  }
  return null;
}
