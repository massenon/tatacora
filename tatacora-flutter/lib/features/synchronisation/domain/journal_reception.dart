/// Le JOURNAL DE RÉCEPTION du poste (schéma v37) — vocabulaire pur, sans base.
///
/// Demande du PO : « une partie de RÉCEPTION avec toutes les informations
/// reçues, les ÉCHECS, les RELANCES, les CORRECTIONS : identifier la CAUSE des
/// échecs, CORRIGER et RELANCER ».
///
/// ## Ce que le journal tient
///
/// UNE ligne par élément reçu du serveur (table + identifiant), mise à jour à
/// chaque nouvelle tentative d'alignement : sa DERNIÈRE issue, la cause, le
/// nombre de tentatives. Une nouvelle version du même élément (autre
/// `modifie_le`) repart à une tentative. Seul écrivain : `DescenteCatalogue`
/// par `JournalReceptionDao` (une sonde de test le garde) ; il n'enfile jamais.
///
/// ## La cause
///
/// L'aligneur rend une [IssueAlignement] et une phrase courte (`motif`). La
/// cause en est déduite ICI, par [analyserMotif] : un registre fermé
/// ([CauseReception]) plus, quand la phrase le nomme, le CHAMP fautif ou
/// l'élément lié qui manque. Une phrase que le registre ne reconnaît pas
/// tombe sur [CauseReception.regleDuPoste] avec la phrase de l'aligneur, mais
/// jamais sur un code : tout ce que l'écran dit est en français.
library;

import 'dart:convert';

import 'descente_catalogue.dart';

/// Ce qu'est devenu un élément reçu — l'issue de son DERNIER alignement.
enum IssueReception {
  aligne('aligne', 'Alignée'),
  conserve('conserve', 'Conservée localement'),
  enAttente('attente', 'En attente d’un élément lié'),
  refuse('refuse', 'Refusée par ce poste');

  const IssueReception(this.code, this.libelle);

  /// Le code rangé dans la base.
  final String code;
  final String libelle;

  /// Reste-t-il quelque chose à faire (relancer, corriger) ?
  bool get ouverte => this != aligne;

  static IssueReception? depuisCode(String? code) {
    for (final i in values) {
      if (i.code == code) return i;
    }
    return null;
  }

  static IssueReception depuis(IssueAlignement issue) => switch (issue) {
    Aligne() => aligne,
    ConserveLocalement() => conserve,
    EnAttenteDeDependance() => enAttente,
    RefuseParLePoste() => refuse,
  };
}

/// La cause identifiable d'un élément non aligné. Registre FERMÉ.
enum CauseReception {
  /// L'élément est aligné : pas de cause.
  aucune('aucune'),

  /// Il cite un élément que ce poste n'a pas encore reçu.
  dependanceManquante('dependance_manquante'),

  /// Une modification de ce poste sur le même élément n'est pas encore partie.
  conflitLocal('conflit_local'),

  /// Un élément du même nom, créé sur ce poste, n'est pas encore parti.
  homonymeLocal('homonyme_local'),

  /// Un champ est absent, illisible ou incomplet dans ce que le serveur a
  /// envoyé.
  donneeIllisible('donnee_illisible'),

  /// Un statut, un type ou un mode que ce logiciel ne connaît pas.
  valeurInconnue('valeur_inconnue'),

  /// Un montant ou une quantité à une précision que le poste ne tient pas.
  precisionNonTenue('precision_non_tenue'),

  /// Aucun compte actif sur ce poste pour porter l'écriture.
  sansCompteLocal('sans_compte_local'),

  /// L'écriture dans la base du poste a échoué.
  ecritureImpossible('ecriture_impossible'),

  /// Une règle de gestion du poste (dates incohérentes, arrivée pointée ici…).
  regleDuPoste('regle_du_poste');

  const CauseReception(this.code);
  final String code;

  static CauseReception depuisCode(String? code) {
    for (final c in values) {
      if (c.code == code) return c;
    }
    return regleDuPoste;
  }
}

/// Ce que l'écran propose pour corriger — registre FERMÉ.
enum ActionCorrection {
  /// Rien à faire que relancer (ou attendre).
  aucune,

  /// Voir les éléments de la table liée (ceux qui sont arrivés, ceux qui ont
  /// été refusés).
  voirElementsLies,

  /// Ouvrir l'écran où l'on crée ce qui manque (compte, client, stock…).
  ouvrirEcran,

  /// Voir l'opération de ce poste qui attend dans la file d'envoi.
  voirFileEnvoi,
}

/// L'analyse d'un motif : cause, champ fautif, élément lié manquant.
typedef AnalyseReception = ({
  CauseReception cause,

  /// Le champ fautif, en français (« Libellé », « Dates de séjour »), ou `null`.
  String? champ,

  /// La valeur reçue que le poste ne connaît pas (`« promo »`), ou `null`.
  String? valeur,

  /// Le nom serveur de la table de l'élément lié qui manque, ou `null`.
  String? dependance,
});

/// Ce que l'écran dit d'un élément non aligné.
final class ExplicationReception {
  const ExplicationReception({
    required this.cause,
    required this.titre,
    required this.phrase,
    required this.correction,
    this.action = ActionCorrection.aucune,
    this.route,
    this.libelleRoute,
    this.dependance,
    this.champ,
  });

  final CauseReception cause;

  /// Le titre court de la cause (« Élément lié manquant »).
  final String titre;

  /// La cause, en une ou deux phrases.
  final String phrase;

  /// Comment la corriger, précisément.
  final String correction;
  final ActionCorrection action;

  /// L'écran à ouvrir ([ActionCorrection.ouvrirEcran]) et son libellé.
  final String? route;
  final String? libelleRoute;

  /// La table (nom serveur) de l'élément lié qui manque.
  final String? dependance;
  final String? champ;
}

String _majuscule(String t) =>
    t.isEmpty ? t : '${t[0].toUpperCase()}${t.substring(1)}';

/// Les noms (tels que l'aligneur les écrit) des éléments liés → leur table.
/// L'ordre compte : « unité d'hébergement » avant « service ».
const List<(String, String)> _liens = [
  ('unité', 'unites_hebergement'),
  ('catégorie', 'categories_hebergement'),
  ('point de stockage', 'points_stockage'),
  ('article', 'articles'),
  ('boisson', 'cartes_boisson'),
  ('plat', 'plats'),
  ('menu', 'menus'),
  ('fiche technique', 'recettes'),
  ('client', 'clients'),
  ('réservation', 'reservations'),
  ('employé', 'employes'),
  ('fournisseur', 'fournisseurs'),
  ('commande', 'commandes_achat'),
  ('facture', 'factures'),
  ('session de caisse', 'sessions_caisse'),
  ('caisse', 'sessions_caisse'),
  ('véhicule', 'vehicules'),
  ('service', 'services'),
  ('table', 'tables_salle'),
];

/// Les éléments liés que [motif] dit absents (« circuit, client ou guide »),
/// ou `null`.
String? nomsDeDependance(String motif) {
  final i = motif.indexOf(' pas encore');
  return i <= 0 ? null : motif.substring(0, i).trim();
}

/// La table de l'élément lié que [motif] dit absent, ou `null` — aussi quand
/// le motif en nomme PLUSIEURS possibles (« client ou guide ») : le poste ne
/// sait pas lequel manque, il ne devine pas.
String? dependanceDeMotif(String motif) {
  final m = (nomsDeDependance(motif) ?? motif).toLowerCase();
  if (m.contains(' ou ') || m.contains(',')) return null;
  for (final (mot, table) in _liens) {
    if (m.contains(mot)) return table;
  }
  return null;
}

/// Déduit la cause du [motif] de l'aligneur.
AnalyseReception analyserMotif(IssueReception issue, String motif) {
  const rien = (
    cause: CauseReception.aucune,
    champ: null,
    valeur: null,
    dependance: null,
  );
  final m = motif.trim();
  switch (issue) {
    case IssueReception.aligne:
      return rien;
    case IssueReception.enAttente:
      if (m.contains('compte local')) {
        return (
          cause: CauseReception.sansCompteLocal,
          champ: null,
          valeur: null,
          dependance: null,
        );
      }
      final lie = dependanceDeMotif(m);
      return (
        cause: CauseReception.dependanceManquante,
        champ: lie == null ? nomsDeDependance(m) : null,
        valeur: null,
        dependance: lie,
      );
    case IssueReception.conserve:
      return (
        cause: m.contains('même nom')
            ? CauseReception.homonymeLocal
            : CauseReception.conflitLocal,
        champ: null,
        valeur: null,
        dependance: null,
      );
    case IssueReception.refuse:
      break;
  }
  if (m.startsWith('écriture impossible')) {
    return (
      cause: CauseReception.ecritureImpossible,
      champ: null,
      valeur: null,
      dependance: null,
    );
  }
  final inconnu = RegExp(r'^(.+?) inconnue?\b(?: « ?(.*?) ?»)?').firstMatch(m);
  if (inconnu != null) {
    return (
      cause: CauseReception.valeurInconnue,
      champ: _majuscule(inconnu.group(1)!),
      valeur: inconnu.group(2),
      dependance: null,
    );
  }
  if (m.contains('fraction de franc') || m.contains('décimales')) {
    return (
      cause: CauseReception.precisionNonTenue,
      champ: null,
      valeur: null,
      dependance: null,
    );
  }
  final defaut = RegExp(
    r'^(.+?) (absents?|absentes?|illisibles?|incomplets?|incomplètes?|invalides?)\b',
  ).firstMatch(m);
  if (defaut != null) {
    final champ = _champPropre(defaut.group(1)!);
    if (champ != null) {
      return (
        cause: CauseReception.donneeIllisible,
        champ: champ,
        valeur: null,
        dependance: null,
      );
    }
  }
  final sans = RegExp(r'^(.+?) sans (.+)$').firstMatch(m);
  if (sans != null) {
    final champ = _champPropre(sans.group(2)!.replaceAll(' ni ', ' ou '));
    if (champ != null) {
      return (
        cause: CauseReception.donneeIllisible,
        champ: champ,
        valeur: null,
        dependance: null,
      );
    }
  }
  return (
    cause: CauseReception.regleDuPoste,
    champ: null,
    valeur: null,
    dependance: null,
  );
}

/// Le nom d'un champ tiré d'un motif : sans la valeur citée (« capacité « 7 »
/// » → « Capacité »), ou `null` si le morceau n'est pas un nom de champ (une
/// phrase entière, une mention du serveur).
String? _champPropre(String brut) {
  final t = brut.replaceAll(RegExp(r'\s*«.*?»'), '').trim();
  if (t.isEmpty ||
      t.contains(':') ||
      t.contains('serveur') ||
      t.contains(' sans ') ||
      t.length > 48) {
    return null;
  }
  return _majuscule(t);
}

/// L'écran où l'on crée ce qui manque pour la table [table] (nom serveur), ou
/// `null`. Ce sont des routes du poste ; l'accès reste jugé par le routeur.
({String route, String libelle})? ecranDeCreation(String table) =>
    switch (table) {
      'clients' || 'relances_clients' => (route: '/crm', libelle: 'Clients'),
      'fournisseurs' => (route: '/fournisseurs', libelle: 'Fournisseurs'),
      'articles' || 'points_stockage' => (route: '/stocks', libelle: 'Stocks'),
      'cartes_boisson' => (route: '/bar/boissons', libelle: 'Boissons du bar'),
      'plats' || 'menus' || 'recettes' => (
        route: '/restaurant/plats',
        libelle: 'Plats du restaurant',
      ),
      'tables_salle' => (route: '/restaurant', libelle: 'Restaurant'),
      'unites_hebergement' ||
      'categories_hebergement' ||
      'reservations' => (route: '/hebergement', libelle: 'Hébergement'),
      'employes' || 'services' => (route: '/paie', libelle: 'Paie et employés'),
      'vehicules' => (route: '/vehicules', libelle: 'Véhicules'),
      'factures' => (route: '/facturation', libelle: 'Facturation'),
      'sessions_caisse' => (route: '/pos', libelle: 'Point de vente'),
      _ => null,
    };

/// L'explication complète d'un élément non aligné de la table [tableServeur].
ExplicationReception expliquer({
  required String tableServeur,
  required IssueReception issue,
  required String motif,
}) {
  final a = analyserMotif(issue, motif);
  final table = libelleTableServeur(tableServeur);
  switch (a.cause) {
    case CauseReception.aucune:
      return const ExplicationReception(
        cause: CauseReception.aucune,
        titre: 'Aligné',
        phrase: 'Cet élément est à jour sur ce poste.',
        correction: 'Rien à corriger.',
      );
    case CauseReception.dependanceManquante:
      final lie = a.dependance;
      final nomLie = lie == null ? null : libelleTableServeur(lie);
      final noms = a.champ;
      final ecran = lie == null ? null : ecranDeCreation(lie);
      return ExplicationReception(
        cause: a.cause,
        titre: 'Élément lié manquant',
        phrase: nomLie == null
            ? (noms == null
                  ? 'Cet élément en cite un autre que ce poste n’a pas encore '
                        'reçu.'
                  : 'Cet élément cite un élément ($noms) que ce poste n’a '
                        'pas encore reçu.')
            : 'Cet élément cite un élément de « $nomLie » que ce poste n’a '
                  'pas encore reçu.',
        correction: nomLie == null
            ? 'Relancez la réception : les éléments liés arrivent d’abord. '
                  'Si le blocage persiste, vérifiez que l’élément lié n’a pas '
                  'été refusé.'
            : 'Relancez la réception : « $nomLie » arrive avant cet élément. '
                  'Si le blocage persiste, regardez dans « $nomLie » s’il '
                  'a été refusé : corrigez-le d’abord, puis relancez celui-ci.',
        action: ecran == null
            ? ActionCorrection.voirElementsLies
            : ActionCorrection.ouvrirEcran,
        route: ecran?.route,
        libelleRoute: ecran?.libelle,
        dependance: lie,
      );
    case CauseReception.sansCompteLocal:
      return const ExplicationReception(
        cause: CauseReception.sansCompteLocal,
        titre: 'Aucun compte sur ce poste',
        phrase:
            'Ce poste n’a aucun compte actif pour porter l’écriture de '
            'cet élément reçu.',
        correction:
            'Créez un compte actif (Comptes utilisateurs), puis relancez '
            'la réception.',
        action: ActionCorrection.ouvrirEcran,
        route: '/comptes-utilisateurs',
        libelleRoute: 'Comptes utilisateurs',
      );
    case CauseReception.conflitLocal:
      return ExplicationReception(
        cause: a.cause,
        titre: 'Modification locale en attente',
        phrase:
            'Une modification de ce poste sur cet élément n’est pas encore '
            'partie : la version du serveur ne l’écrase pas.',
        correction:
            'Envoyez-la (« Synchroniser maintenant »). Le serveur gardera '
            'la saisie la plus récente, puis sa version redescendra. Si '
            'l’opération est rejetée ou bloquée, corrigez-la dans la partie '
            'Envoi.',
        action: ActionCorrection.voirFileEnvoi,
      );
    case CauseReception.homonymeLocal:
      return ExplicationReception(
        cause: a.cause,
        titre: 'Même nom créé sur ce poste',
        phrase:
            'Un élément du même nom, créé sur ce poste, n’est pas encore '
            'parti : le recevoir maintenant ferait un doublon.',
        correction:
            'Envoyez d’abord l’élément de ce poste ; le serveur les fusionnera '
            'et la réception reprendra seule.',
        action: ActionCorrection.voirFileEnvoi,
      );
    case CauseReception.donneeIllisible:
      final champ = a.champ ?? 'une donnée';
      return ExplicationReception(
        cause: a.cause,
        titre: 'Donnée illisible',
        phrase:
            '« $table » : le champ « $champ » est absent, illisible ou '
            'incomplet dans ce que le serveur a envoyé.',
        correction:
            'Cela se corrige à la source : ouvrez cet élément sur le serveur '
            '(ou sur le poste qui l’a saisi), renseignez correctement '
            '« $champ », puis utilisez « Relancer tout » pour recevoir la '
            'version corrigée. Le poste ne devine jamais une donnée.',
        champ: a.champ,
      );
    case CauseReception.valeurInconnue:
      final champ = a.champ ?? 'une valeur';
      final valeur = a.valeur == null
          ? ' une valeur'
          : ' la valeur « ${a.valeur} »';
      return ExplicationReception(
        cause: a.cause,
        titre: 'Valeur inconnue de ce poste',
        phrase:
            'Le champ « $champ » porte$valeur, que cette version du '
            'logiciel ne connaît pas.',
        correction:
            'Mettez le logiciel du poste à jour (la valeur existe peut-être '
            'dans une version plus récente) ou corrigez la valeur à la '
            'source, puis utilisez « Relancer tout » pour recevoir la version '
            'corrigée.',
        champ: a.champ,
      );
    case CauseReception.precisionNonTenue:
      return ExplicationReception(
        cause: a.cause,
        titre: 'Précision non tenue',
        phrase:
            'Un montant ou une quantité de « $table » a une précision que ce '
            'poste ne sait pas tenir (fraction de franc, décimales en trop). '
            'Il n’est jamais arrondi.',
        correction:
            'Corrigez le montant à la source (francs entiers, quantités à '
            'deux ou trois décimales selon le cas), puis utilisez « Relancer '
            'tout » pour recevoir la version corrigée.',
      );
    case CauseReception.ecritureImpossible:
      return ExplicationReception(
        cause: a.cause,
        titre: 'Écriture impossible sur ce poste',
        phrase:
            'L’écriture de cet élément dans la base de ce poste a échoué '
            '(une règle de la base s’y est opposée).',
        correction:
            'Relancez l’élément. Si l’échec persiste, signalez-le à '
            'l’éditeur (Contactez l’éditeur) en joignant la table et la date '
            'de réception.',
        action: ActionCorrection.ouvrirEcran,
        route: '/contact-editeur',
        libelleRoute: 'Contactez l’éditeur',
      );
    case CauseReception.regleDuPoste:
      return ExplicationReception(
        cause: a.cause,
        titre: 'Refusé par une règle du poste',
        phrase: motif.trim().isEmpty
            ? 'Ce poste a refusé cet élément.'
            : '${_majuscule(motif.trim())}.',
        correction:
            'Corrigez l’élément à la source si la donnée est fausse, puis '
            'utilisez « Relancer tout » pour recevoir la version corrigée. '
            'Sinon, la décision du serveur fait foi : rien à faire ici.',
      );
  }
}

/// La suite lisible d'un élément pour la liste : libellé, nom, raison sociale…
String? etiquetteElement(Map<String, Object?> donnees) {
  String? t(String c) {
    final v = donnees[c];
    return v is String && v.trim().isNotEmpty ? v.trim() : null;
  }

  final nom = t('nom');
  final prenom = t('prenom');
  final choix =
      t('libelle') ??
      t('raison_sociale') ??
      (nom == null ? null : (prenom == null ? nom : '$nom $prenom')) ??
      (t('numero') == null ? null : 'N° ${t('numero')}') ??
      t('reference') ??
      t('code') ??
      t('matricule') ??
      t('immatriculation') ??
      t('date_arrivee') ??
      t('date_commande') ??
      t('date_reception') ??
      t('date');
  if (choix == null) return null;
  return choix.length > 60 ? '${choix.substring(0, 57)}…' : choix;
}

/// Une ligne du journal, telle que l'écran la lit.
final class EntreeJournalReception {
  const EntreeJournalReception({
    required this.tableServeur,
    required this.elementId,
    required this.issue,
    required this.cause,
    required this.motif,
    required this.tentatives,
    required this.recuLe,
    required this.derniereTentativeLe,
    this.champ,
    this.dependance,
    this.etiquette,
    this.posteOrigine,
    this.modifieLeServeur = '',
    this.elementJson,
  });

  final String tableServeur;
  final String elementId;
  final IssueReception issue;
  final CauseReception cause;

  /// La phrase de l'aligneur (vide pour un élément aligné).
  final String motif;
  final String? champ;
  final String? dependance;
  final String? etiquette;
  final String? posteOrigine;
  final String modifieLeServeur;
  final int tentatives;
  final DateTime recuLe;
  final DateTime derniereTentativeLe;

  /// L'élément reçu, gardé tant qu'il reste à traiter (relance) ; `null` pour
  /// un élément aligné.
  final String? elementJson;

  String get libelleTable => libelleTableServeur(tableServeur);

  /// L'élément gardé, relu, ou `null` s'il n'est plus là ou est illisible.
  ElementCatalogue? element() {
    final brut = elementJson;
    if (brut == null) return null;
    try {
      return ElementCatalogue.depuisJson(jsonDecode(brut));
    } on FormatException {
      return null;
    }
  }

  ExplicationReception get explication =>
      expliquer(tableServeur: tableServeur, issue: issue, motif: motif);
}

/// Un élément illisible du serveur : de quoi le consigner sans rien deviner.
({String table, String id, String motif}) diagnosticIllisible(
  Object? brut,
  int rang,
) {
  if (brut is! Map) {
    return (
      table: 'inconnue',
      id: 'illisible-$rang',
      motif: 'élément illisible du serveur (ni table ni identifiant)',
    );
  }
  final table = brut['table'];
  final id = brut['id'];
  final donnees = brut['donnees'];
  final tableTexte = table is String && table.isNotEmpty ? table : 'inconnue';
  final idTexte = id is String && id.isNotEmpty ? id : 'illisible-$rang';
  final String motif;
  if (table is! String || TableDescendue.depuisNom(table) == null) {
    motif = 'table de l’élément illisible (inconnue de ce poste)';
  } else if (id is! String || id.isEmpty) {
    motif = 'identifiant de l’élément absent';
  } else if (donnees is! Map) {
    motif = 'données de l’élément absentes ou illisibles';
  } else {
    motif = 'élément illisible du serveur';
  }
  return (table: tableTexte, id: idTexte, motif: motif);
}

/// Ce qu'a donné « Relancer » sur un élément.
final class ResultatRelance {
  const ResultatRelance(this.issue);

  /// Le nouvel état de l'élément ; `null` : rien n'a pu être rejoué.
  final IssueReception? issue;

  /// L'élément n'est plus gardé sur ce poste.
  static const ResultatRelance introuvable = _Introuvable();

  /// La base du poste n'a pas pu rejouer l'élément.
  static const ResultatRelance impossible = _Impossible();

  bool get reussi => issue == IssueReception.aligne;

  /// La phrase de l'écran.
  String get phrase => switch (issue) {
    IssueReception.aligne => 'Élément aligné : il est à jour sur ce poste.',
    IssueReception.conserve =>
      'Toujours conservé localement : une modification de ce poste attend '
          'encore de partir.',
    IssueReception.enAttente =>
      'Toujours en attente : l’élément lié n’est pas encore arrivé.',
    IssueReception.refuse =>
      'Toujours refusé par ce poste : voyez la cause et corrigez-la.',
    null => 'Relance impossible sur ce poste.',
  };
}

final class _Introuvable extends ResultatRelance {
  const _Introuvable() : super(null);

  @override
  String get phrase =>
      'Cet élément n’est plus gardé sur ce poste : il sera reçu de nouveau à '
      'sa prochaine modification au serveur.';
}

final class _Impossible extends ResultatRelance {
  const _Impossible() : super(null);
}
