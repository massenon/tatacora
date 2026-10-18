/// Ce que l'écran de synchronisation DIT de la file (lot F2b, 15/10/2026) :
/// statuts, motifs, documents, anomalies — en français, et seulement ce qui
/// est vrai (piège 1).
///
/// ## La règle de vocabulaire
///
/// « Synchronisé » ne se dit QUE d'une opération que le serveur a acceptée
/// (statut `synchronise`, posé par `OperationsSyncDao.marquerResultat` sur
/// la réponse du serveur). Une opération en attente « attend d'être
/// envoyée », une opération en cours « est en cours d'envoi » — jamais
/// « synchronisée ». Un test balaie ces phrases.
library;

import 'dart:convert';

import 'descente_catalogue.dart';
import 'operation_sync.dart';

/// Le libellé d'un statut de la file — pluriel : il nomme un COMPTEUR.
String libelleStatutFile(StatutOperationSync s) => switch (s) {
  StatutOperationSync.enAttente => 'En attente d\'envoi',
  StatutOperationSync.enCours => 'En cours d\'envoi',
  StatutOperationSync.synchronise =>
    'Synchronisées (confirmées par le serveur)',
  StatutOperationSync.rejete => 'Rejetées par le serveur',
  StatutOperationSync.conflit => 'En conflit (arbitrage au serveur)',
  StatutOperationSync.bloque => 'Bloquées',
};

/// Le libellé d'UNE opération à traiter — singulier : il qualifie une ligne.
String libelleStatutOperation(StatutOperationSync s) => switch (s) {
  StatutOperationSync.enAttente => 'En attente d\'envoi',
  StatutOperationSync.enCours => 'En cours d\'envoi',
  StatutOperationSync.synchronise => 'Synchronisée',
  StatutOperationSync.rejete => 'Rejetée',
  StatutOperationSync.conflit => 'Conflit',
  StatutOperationSync.bloque => 'Bloquée',
};

/// Ce que l'écran dit d'une opération en CONFLIT : aucune action locale.
const String texteConflitArbitrage =
    'En attente d\'arbitrage sur le serveur : aucune action sur ce poste.';

/// Le MOTIF d'une opération à traiter : la phrase du serveur (rejet), celle
/// du blocage, ou l'arbitrage (conflit). Jamais un corps de réponse brut.
String motifOperation(OperationSync o) {
  if (o.statut == StatutOperationSync.conflit) return texteConflitArbitrage;
  final erreur = o.derniereErreur;
  if (erreur != null && erreur.trim().isNotEmpty) return erreur;
  final r = _resultat(o);
  final motif = r?['motif'];
  if (motif is String && motif.trim().isNotEmpty) return motif;
  return switch (o.statut) {
    StatutOperationSync.bloque =>
      'Bloquée : une opération antérieure sur le même élément a été refusée '
          'par le serveur.',
    StatutOperationSync.rejete => 'Refusée par le serveur (motif non fourni).',
    _ => '',
  };
}

/// Le DOCUMENT que l'opération porte, en clair — lu du payload figé. `null`
/// quand le payload ne le dit pas (une modification partielle ne porte que
/// ses champs changés).
String? libelleDocument(OperationSync o) {
  final Object? brut;
  try {
    brut = jsonDecode(o.payload);
  } on FormatException {
    return null;
  }
  if (brut is! Map) return null;
  final champs = brut;
  String? t(String c) {
    final v = champs[c];
    return v is String && v.trim().isNotEmpty ? v.trim() : null;
  }

  return switch (o.table) {
    TableSynchronisee.fournisseurs => t('raison_sociale'),
    TableSynchronisee.unitesHebergement => switch (t('numero')) {
      final n? => 'Unité $n',
      null => null,
    },
    TableSynchronisee.clients => switch ((t('nom'), t('prenom'))) {
      (final n?, final p?) => '$n $p',
      (final n?, null) => n,
      _ => null,
    },
    TableSynchronisee.reservations => switch ((
      t('date_arrivee'),
      t('date_depart'),
    )) {
      (final a?, final d?) => 'Séjour du $a au $d',
      _ => null,
    },
    TableSynchronisee.commandesAchat => switch (t('date_commande')) {
      final d? => 'Commande du $d',
      null => null,
    },
    TableSynchronisee.bonsReception => switch (t('date_reception')) {
      final d? => 'Réception du $d',
      null => null,
    },
    TableSynchronisee.sessionsCaisse => switch (t('point_vente')) {
      final p? =>
        o.type == TypeOperationSync.creation
            ? 'Ouverture de caisse ($p)'
            : 'Clôture de caisse ($p)',
      null => null,
    },
    TableSynchronisee.ventes => switch (t('cloture_le')) {
      final d? => 'Vente du $d',
      null => null,
    },
    _ => t('libelle'),
  };
}

/// Les ANOMALIES que le serveur a signalées en acceptant un document
/// (`anomalies` du résultat ; la clôture d'une caisse qu'il ne connaît pas
/// porte son propre statut). Registre FERMÉ relu de
/// `AnomalieSynchronisation` au serveur par un test.
const Map<String, String> libellesAnomalies = {
  'ecart_prix': 'Écart de prix avec le catalogue du serveur',
  'vente_en_rupture':
      'Vente enregistrée alors que le stock du serveur était épuisé',
  'vente_session_inconnue':
      'Vente rattachée à une caisse que le serveur ne connaît pas',
  'vente_session_cloturee':
      'Vente rattachée à une caisse déjà clôturée au serveur',
  'ecart_theorique_caisse':
      'Écart entre le théorique de caisse du poste et celui du serveur',
  'ecart_conformite_reception':
      'Conformité de la réception jugée autrement par le serveur',
  'plat_sans_composition':
      'Plat vendu sans composition : aucune sortie de stock au serveur',
  'cloture_session_inconnue':
      'Clôture d\'une caisse que le serveur ne connaît pas : enregistrée avec '
      'les chiffres du poste',
  'guide_sans_tarif':
      'Guide créé sur ce poste sans tarif journalier : enregistré à 0 au '
      'serveur, tarif à saisir',
  'vehicule_sans_annee':
      'Véhicule créé sur ce poste sans année ni capacité : enregistré avec '
      'l\'année 0 au serveur, à compléter',
  'paiement_facture_non_certifiee':
      'Encaissement d\'une facture non certifiée au serveur : enregistré, la '
      'certification MECeF n\'est pas lancée',
  'paiement_session_inconnue':
      'Encaissement d\'une caisse que le serveur ne connaît pas : rattaché à '
      'la caisse ouverte du serveur',
};

/// Le libellé d'une anomalie ; une anomalie inconnue est rendue par son
/// code, jamais devinée.
String libelleAnomalie(String code) => libellesAnomalies[code] ?? code;

/// Les codes d'anomalie d'une opération ACCEPTÉE, sans doublon.
List<String> anomaliesDe(OperationSync o) {
  final r = _resultat(o);
  if (r == null) return const [];
  final codes = <String>{
    for (final a in (r['anomalies'] is List ? r['anomalies']! as List : []))
      if (a is String) a,
  };
  if (r['statut'] == 'cloture_sans_session_serveur') {
    codes.add('cloture_session_inconnue');
  }
  return codes.toList();
}

/// Le libellé de la table d'une opération.
String libelleTableOperation(OperationSync o) =>
    libelleTableServeur(o.table.nomServeur);

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
