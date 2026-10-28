/// La CAUSE d'un refus de la file d'envoi, et ce qu'on peut corriger — pur,
/// sans base.
///
/// Demande du PO (26/10/2026) : « pour les opérations rejetées ou bloquées de
/// la file, la CAUSE lisible, "Corriger" = modifier la charge utile quand c'est
/// possible (montant, libellé, date) via un formulaire généré du contrat de la
/// charge, puis "Relancer" ».
///
/// ## D'où vient la cause
///
/// Le serveur rend, pour un refus, `motif` (sa phrase), `code_motif` (un code
/// stable, registre FERMÉ relu du PHP par un test) et, pour une donnée
/// invalide, `erreurs` (ses phrases, champ par champ). Tout est consigné tel
/// quel dans `resultat_json` : rien de plus n'est demandé au serveur.
///
/// ## Le formulaire de correction
///
/// [champsEditables] lit la charge FIGÉE de l'opération et propose les champs
/// que ce registre connaît (libellés, noms, montants, dates, quantités) —
/// jamais un identifiant, un statut ou une ligne de document. [corrigerCharge]
/// valide chaque saisie contre le contrat (montant en francs entiers, décimal
/// à la précision d'origine, date `AAAA-MM-JJ`) ; le serveur, lui, rejuge à
/// l'envoi et ses phrases s'affichent à côté des champs.
library;

import 'dart:convert';

import 'operation_sync.dart';

/// Une phrase du serveur sur un champ.
typedef ErreurChamp = ({String cle, String libelle, List<String> messages});

/// La cause d'une opération à traiter.
final class CauseEnvoi {
  const CauseEnvoi({
    required this.titre,
    required this.motif,
    required this.conseil,
    this.code,
    this.erreurs = const [],
  });

  /// Le titre court de la cause (« Donnée refusée par le serveur »).
  final String titre;

  /// La phrase du serveur (ou celle du poste pour un blocage).
  final String motif;

  /// Comment s'en sortir.
  final String conseil;
  final String? code;
  final List<ErreurChamp> erreurs;
}

/// Les causes connues du serveur — le registre de `code_motif`. Un code
/// inconnu se lit comme `regle_metier`, jamais comme un code brut.
const Map<String, ({String titre, String conseil})> causesRefusServeur = {
  'donnees_invalides': (
    titre: 'Donnée refusée par le serveur',
    conseil:
        'Corrigez les champs signalés (bouton « Corriger »), puis renvoyez.',
  ),
  'chevauchement': (
    titre: 'Chevauchement avec un autre enregistrement',
    conseil:
        'Changez les dates ou l’unité en cause (champs de « Corriger » quand '
        'ils sont modifiables), ou annulez l’autre enregistrement, puis '
        'renvoyez.',
  ),
  'entite_inconnue': (
    titre: 'Élément absent du serveur',
    conseil:
        'La création de cet élément n’est pas arrivée ou a été refusée : '
        'traitez d’abord l’opération de création du même élément dans cette '
        'liste, puis renvoyez celle-ci.',
  ),
  'suppression_non_synchronisable': (
    titre: 'Suppression non admise',
    conseil:
        'Seules les unités d’hébergement et les véhicules archivés se '
        'purgent. Rien à renvoyer : l’élément reste sur le serveur.',
  ),
  'entite_existante': (
    titre: 'Identifiant déjà utilisé',
    conseil: 'Rien à corriger : le serveur détient déjà ce document.',
  ),
  'stock_insuffisant': (
    titre: 'Stock insuffisant au serveur',
    conseil:
        'Enregistrez d’abord l’approvisionnement manquant (il part avant), '
        'puis renvoyez.',
  ),
  'recette_manquante': (
    titre: 'Fiche technique manquante',
    conseil:
        'Composez la fiche technique du plat (elle part avec le catalogue), '
        'puis renvoyez.',
  ),
  'refus_caisse': (
    titre: 'Règle de caisse',
    conseil:
        'Vérifiez l’état de la caisse concernée (ouverte, clôturée) et les '
        'montants, puis renvoyez.',
  ),
  'piece_immuable': (
    titre: 'Pièce comptable validée',
    conseil:
        'Une pièce validée ne se modifie plus : faites passer une écriture '
        'corrective au serveur.',
  ),
  'droit_manquant': (
    titre: 'Droit manquant',
    conseil:
        'Le compte de ce poste n’a pas le droit d’écrire dans ce module au '
        'serveur : demandez-le à un administrateur, puis renvoyez.',
  ),
  'compte_inactif': (
    titre: 'Compte désactivé',
    conseil: 'Réactivez le compte au serveur, puis renvoyez.',
  ),
  'table_non_synchronisable': (
    titre: 'Document non pris en charge',
    conseil:
        'Le serveur n’accepte pas ce type de document : signalez-le à '
        'l’éditeur (Contactez l’éditeur).',
  ),
  'modification_non_synchronisable': (
    titre: 'Modification non admise hors connexion',
    conseil:
        'Cet enregistrement ne se modifie pas depuis un poste : faites la '
        'modification depuis l’écran en ligne.',
  ),
  'date_metier_invalide': (
    titre: 'Date du document invalide',
    conseil: 'Corrigez la date (bouton « Corriger »), puis renvoyez.',
  ),
  'regle_metier': (
    titre: 'Refusé par une règle de gestion',
    conseil:
        'Lisez le motif du serveur, corrigez ce qu’il demande (champs de '
        '« Corriger » quand ils sont modifiables), puis renvoyez.',
  ),
};

/// Les codes que le serveur peut rendre.
Set<String> get codesRefusServeur => causesRefusServeur.keys.toSet();

Map<String, Object?>? _resultat(OperationSync o) {
  final brut = o.resultatJson;
  if (brut == null) return null;
  try {
    final r = jsonDecode(brut);
    return r is Map<String, Object?> ? r : null;
  } on FormatException {
    return null;
  }
}

/// Le code structuré du refus (`code_motif`), ou `null`.
String? codeMotifDe(OperationSync o) {
  final c = _resultat(o)?['code_motif'];
  return c is String && c.isNotEmpty ? c : null;
}

/// Les phrases du serveur, champ par champ (`erreurs`).
List<ErreurChamp> erreursChampsDe(OperationSync o) {
  final e = _resultat(o)?['erreurs'];
  if (e is! Map) return const [];
  final liste = <ErreurChamp>[];
  for (final entree in e.entries) {
    final cle = '${entree.key}';
    final v = entree.value;
    final messages = <String>[];
    if (v is List) {
      for (final m in v) {
        if (m is String && m.trim().isNotEmpty) messages.add(m.trim());
      }
    } else if (v is String && v.trim().isNotEmpty) {
      messages.add(v.trim());
    }
    if (messages.isNotEmpty) {
      liste.add((
        cle: cle,
        libelle: libelleChampServeur(cle),
        messages: messages,
      ));
    }
  }
  return liste;
}

/// Le nom français d'un champ de la charge (`date_arrivee` → « Date
/// d'arrivée »), y compris « lignes.0.montant » → « Ligne 1 : Montant ».
String libelleChampServeur(String cle) {
  final morceaux = cle.split('.');
  final sortie = <String>[];
  for (var i = 0; i < morceaux.length; i++) {
    final m = morceaux[i];
    final rang = int.tryParse(m);
    if (rang != null) {
      sortie.add('ligne ${rang + 1}');
      continue;
    }
    final connu = _registre[m];
    if (connu != null) {
      sortie.add(connu.libelle);
    } else if (m == 'lignes') {
      continue;
    } else {
      sortie.add(_humaniser(m));
    }
  }
  if (sortie.isEmpty) return _humaniser(cle);
  if (sortie.length == 1) return _majuscule(sortie.first);
  return '${_majuscule(sortie.first)} : ${sortie.skip(1).join(', ')}';
}

String _humaniser(String cle) =>
    _majuscule(cle.replaceAll('_id', '').replaceAll('_', ' ').trim());

String _majuscule(String t) =>
    t.isEmpty ? t : '${t[0].toUpperCase()}${t.substring(1)}';

/// La cause à afficher pour une opération rejetée, en conflit ou bloquée.
CauseEnvoi causeDe(OperationSync o, {required String motif}) {
  if (o.statut == StatutOperationSync.conflit) {
    return CauseEnvoi(
      titre: 'Conflit financier',
      motif: motif,
      conseil:
          'Un responsable tranche au serveur : aucune action possible sur ce '
          'poste.',
    );
  }
  if (o.statut == StatutOperationSync.bloque) {
    return CauseEnvoi(
      titre: 'Bloquée derrière une opération refusée',
      motif: motif,
      conseil:
          'Traitez d’abord l’opération refusée du même élément (« Corriger » '
          'puis renvoyer) ; celle-ci pourra repartir ensuite (« Débloquer »).',
    );
  }
  final code = codeMotifDe(o);
  final connue =
      causesRefusServeur[code] ?? causesRefusServeur['regle_metier']!;
  return CauseEnvoi(
    titre: connue.titre,
    motif: motif,
    conseil: connue.conseil,
    code: code,
    erreurs: erreursChampsDe(o),
  );
}

/* ==================================================================== */
/* Le formulaire généré du contrat de la charge                          */
/* ==================================================================== */

/// Le genre d'un champ modifiable.
enum GenreChamp {
  texte,

  /// Francs entiers (ou entier d'une autre unité du contrat).
  entier,

  /// Chaîne décimale exacte du contrat (`"15000.00"`).
  decimal,

  /// `AAAA-MM-JJ`.
  date,

  /// `AAAA-MM-JJ HH:MM:SS`, heure locale du poste.
  instant,
}

/// Un champ proposé à la correction.
final class ChampEditable {
  const ChampEditable({
    required this.cle,
    required this.libelle,
    required this.genre,
    required this.valeur,
    this.decimales = 0,
    this.obligatoire = true,
    this.aide,
  });

  final String cle;
  final String libelle;
  final GenreChamp genre;

  /// La valeur actuelle, en texte de saisie.
  final String valeur;

  /// Pour un décimal : le nombre de décimales du contrat.
  final int decimales;
  final bool obligatoire;
  final String? aide;
}

typedef _Def = ({String libelle, int max});

/// Le registre FERMÉ des champs qu'une correction peut toucher. Un champ qui
/// n'y est pas (identifiant, statut, type, ligne de document…) n'est jamais
/// proposé.
const Map<String, _Def> _registre = {
  'libelle': (libelle: 'Libellé', max: 255),
  'nom': (libelle: 'Nom', max: 255),
  'prenom': (libelle: 'Prénom', max: 255),
  'raison_sociale': (libelle: 'Raison sociale', max: 255),
  'client_nom': (libelle: 'Nom du client', max: 255),
  'article_libelle': (libelle: 'Libellé de l’article', max: 255),
  'telephone': (libelle: 'Téléphone', max: 30),
  'email': (libelle: 'Adresse e-mail', max: 255),
  'contact': (libelle: 'Contact', max: 255),
  'motif': (libelle: 'Motif', max: 1000),
  'commentaire': (libelle: 'Commentaire', max: 1000),
  'description': (libelle: 'Description', max: 1000),
  'objet': (libelle: 'Objet', max: 255),
  'categorie': (libelle: 'Catégorie', max: 255),
  'zone': (libelle: 'Zone', max: 255),
  'immatriculation': (libelle: 'Immatriculation', max: 50),
  'numero_cnss': (libelle: 'Numéro CNSS', max: 50),
  'montant': (libelle: 'Montant', max: 0),
  'montant_reclame': (libelle: 'Montant réclamé', max: 0),
  'prix_vente': (libelle: 'Prix de vente', max: 0),
  'prix': (libelle: 'Prix', max: 0),
  'cout': (libelle: 'Coût', max: 0),
  'tarif_jour': (libelle: 'Tarif journalier', max: 0),
  'tarif_nuit': (libelle: 'Tarif de la nuit', max: 0),
  'tarif_base': (libelle: 'Tarif de base', max: 0),
  'acompte': (libelle: 'Acompte', max: 0),
  'salaire_base': (libelle: 'Salaire de base', max: 0),
  'valeur_origine': (libelle: 'Valeur d’origine', max: 0),
  'remise_valeur': (libelle: 'Valeur de la remise', max: 0),
  'seuil_alerte': (libelle: 'Seuil d’alerte', max: 0),
  'quantite': (libelle: 'Quantité', max: 0),
  'capacite_max': (libelle: 'Capacité maximale', max: 0),
  'nb_participants': (libelle: 'Nombre de participants', max: 0),
  'occupants': (libelle: 'Occupants', max: 0),
  'duree_annees': (libelle: 'Durée en années', max: 0),
  'date': (libelle: 'Date', max: 0),
  'date_arrivee': (libelle: 'Date d’arrivée', max: 0),
  'date_depart': (libelle: 'Date de départ', max: 0),
  'date_debut': (libelle: 'Date de début', max: 0),
  'date_fin': (libelle: 'Date de fin', max: 0),
  'date_commande': (libelle: 'Date de la commande', max: 0),
  'date_reception': (libelle: 'Date de réception', max: 0),
  'date_emission': (libelle: 'Date d’émission', max: 0),
  'date_paiement': (libelle: 'Date du paiement', max: 0),
  'date_reglement': (libelle: 'Date du règlement', max: 0),
  'date_transaction': (libelle: 'Date de l’opération', max: 0),
  'date_mouvement': (libelle: 'Date du mouvement', max: 0),
  'date_mise_service': (libelle: 'Date de mise en service', max: 0),
  'date_embauche': (libelle: 'Date d’embauche', max: 0),
  'date_inventaire': (libelle: 'Date de l’inventaire', max: 0),
  'date_circuit': (libelle: 'Date du circuit', max: 0),
  'date_relance': (libelle: 'Date de la relance', max: 0),
  'date_indisponibilite': (libelle: 'Date du retrait', max: 0),
  'date_ouverture': (libelle: 'Ouverture', max: 0),
  'date_cloture': (libelle: 'Clôture', max: 0),
  'cloture_le': (libelle: 'Clôture', max: 0),
};

final RegExp _entier = RegExp(r'^\d+$');
final RegExp _jour = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final RegExp _instant = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$',
);

bool _jourReel(String t) {
  final m = _jour.firstMatch(t);
  if (m == null) return false;
  final a = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final j = int.parse(m.group(3)!);
  final d = DateTime(a, mo, j);
  return d.year == a && d.month == mo && d.day == j;
}

bool _instantReel(String t) {
  final m = _instant.firstMatch(t);
  if (m == null) return false;
  if (!_jourReel('${m.group(1)}-${m.group(2)}-${m.group(3)}')) return false;
  return int.parse(m.group(4)!) < 24 &&
      int.parse(m.group(5)!) < 60 &&
      int.parse(m.group(6)!) < 60;
}

/// Les champs que la charge de [o] permet de corriger, dans l'ordre de la
/// charge. Une charge illisible n'en propose aucun.
List<ChampEditable> champsEditables(OperationSync o) {
  final Object? brut;
  try {
    brut = jsonDecode(o.payload);
  } on FormatException {
    return const [];
  }
  if (brut is! Map) return const [];
  final champs = <ChampEditable>[];
  for (final e in brut.entries) {
    final cle = '${e.key}';
    final def = _registre[cle];
    final v = e.value;
    if (def == null || v == null) continue;
    if (v is bool || v is Map || v is List) continue;
    if (v is int) {
      champs.add(
        ChampEditable(
          cle: cle,
          libelle: def.libelle,
          genre: GenreChamp.entier,
          valeur: '$v',
        ),
      );
    } else if (v is String) {
      if (_jour.hasMatch(v)) {
        champs.add(
          ChampEditable(
            cle: cle,
            libelle: def.libelle,
            genre: GenreChamp.date,
            valeur: v,
            aide: 'Format AAAA-MM-JJ.',
          ),
        );
      } else if (_instant.hasMatch(v)) {
        champs.add(
          ChampEditable(
            cle: cle,
            libelle: def.libelle,
            genre: GenreChamp.instant,
            valeur: v,
            aide: 'Format AAAA-MM-JJ HH:MM:SS.',
          ),
        );
      } else if (RegExp(r'^-?\d+\.\d+$').hasMatch(v)) {
        champs.add(
          ChampEditable(
            cle: cle,
            libelle: def.libelle,
            genre: GenreChamp.decimal,
            valeur: v,
            decimales: v.split('.').last.length,
            aide: 'Nombre avec ${v.split('.').last.length} décimale(s).',
          ),
        );
      } else if (def.max > 0) {
        champs.add(
          ChampEditable(
            cle: cle,
            libelle: def.libelle,
            genre: GenreChamp.texte,
            valeur: v,
            obligatoire: v.trim().isNotEmpty,
          ),
        );
      }
    }
  }
  return champs;
}

/// Le résultat d'une validation de saisies.
typedef CorrectionValidee = ({
  Map<String, Object?>? charge,
  Map<String, String> erreurs,
});

/// Valide les [saisies] (clé → texte) contre le contrat de la charge de [o].
/// `charge` est la charge corrigée (les autres champs inchangés), ou `null`
/// quand une saisie est refusée ; [erreurs] dit laquelle, en français.
CorrectionValidee corrigerCharge(OperationSync o, Map<String, String> saisies) {
  final Object? brut;
  try {
    brut = jsonDecode(o.payload);
  } on FormatException {
    return (charge: null, erreurs: {'charge': 'La charge est illisible.'});
  }
  if (brut is! Map) {
    return (charge: null, erreurs: {'charge': 'La charge est illisible.'});
  }
  final charge = Map<String, Object?>.from(brut);
  final erreurs = <String, String>{};
  for (final champ in champsEditables(o)) {
    final saisie = saisies[champ.cle];
    if (saisie == null) continue;
    final t = saisie.trim();
    if (t.isEmpty && champ.obligatoire) {
      erreurs[champ.cle] = '${champ.libelle} est obligatoire.';
      continue;
    }
    switch (champ.genre) {
      case GenreChamp.texte:
        final max = _registre[champ.cle]?.max ?? 255;
        if (t.length > max) {
          erreurs[champ.cle] =
              '${champ.libelle} ne peut pas dépasser $max caractères.';
        } else {
          charge[champ.cle] = t;
        }
      case GenreChamp.entier:
        if (!_entier.hasMatch(t)) {
          erreurs[champ.cle] =
              '${champ.libelle} doit être un nombre entier positif ou nul.';
        } else {
          charge[champ.cle] = int.parse(t);
        }
      case GenreChamp.decimal:
        final m = RegExp(r'^(\d+)(?:[.,](\d+))?$').firstMatch(t);
        if (m == null || (m.group(2) ?? '').length > champ.decimales) {
          erreurs[champ.cle] =
              '${champ.libelle} doit être un nombre positif avec au plus '
              '${champ.decimales} décimale(s).';
        } else {
          charge[champ.cle] =
              '${m.group(1)}.${(m.group(2) ?? '').padRight(champ.decimales, '0')}';
        }
      case GenreChamp.date:
        if (!_jourReel(t)) {
          erreurs[champ.cle] =
              '${champ.libelle} doit être une date valide (AAAA-MM-JJ).';
        } else {
          charge[champ.cle] = t;
        }
      case GenreChamp.instant:
        if (!_instantReel(t)) {
          erreurs[champ.cle] =
              '${champ.libelle} doit être une date et une heure valides '
              '(AAAA-MM-JJ HH:MM:SS).';
        } else {
          charge[champ.cle] = t;
        }
    }
  }
  return (charge: erreurs.isEmpty ? charge : null, erreurs: erreurs);
}
