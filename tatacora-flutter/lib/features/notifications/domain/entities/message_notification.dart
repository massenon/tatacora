/// Un message COMPOSÉ — et le registre fermé de ses quatre sorts possibles.
library;

import 'canal_notification.dart';
import 'declencheur_notification.dart';

/// Ce qu'il est advenu d'un message — REGISTRE FERMÉ.
///
/// ## Le quatrième cas n'est atteignable par AUCUN geste de ce poste
///
/// [envoyeParLeSysteme] existe au registre du serveur et **reste ici**, pour
/// deux raisons :
///
/// 1. le compteur « Réellement envoyés » se dérive de lui, sur la table réelle.
///    Le retirer forcerait à poser un `0` en dur, soit exactement PA-61 — un
///    chiffre juste aujourd'hui, faux le jour où il compterait ;
/// 2. le jour où un transport existera, c'est LUI qui écrira ce statut, et rien
///    d'autre. « Transmis à la main » ne doit jamais l'emprunter : ce n'est pas
///    le logiciel qui a fait partir le message, et la distinction doit rester
///    lisible à l'audit.
///
/// `notifications_dao_test.dart` énumère les gestes du DAO et exige qu'aucun ne
/// produise ce statut.
enum StatutMessageNotification {
  enAttente('en_attente', 'En file'),
  transmisALaMain('traite_manuellement', 'Transmis à la main'),
  abandonne('abandonne', 'Abandonné'),
  envoyeParLeSysteme('envoye', 'Envoyé par le système');

  const StatutMessageNotification(this.code, this.libelle);

  final String code;
  final String libelle;

  /// Un code inconnu vaut [enAttente] — la lecture PRUDENTE.
  ///
  /// Le défaut inverse serait grave : retomber sur [envoyeParLeSysteme]
  /// afficherait « envoyé » sur un message dont on n'a pas compris l'état.
  /// Rester en file ne fait, au pire, que proposer un geste déjà accompli — et
  /// ce geste est refusé par le DAO si le statut réel l'interdit.
  static StatutMessageNotification depuisCode(String? code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return StatutMessageNotification.enAttente;
  }

  /// La colonne « Envoi système » du maître — « oui » / « non ».
  ///
  /// Un geste manuel rend TOUJOURS « non ». C'est la seule colonne du journal
  /// qui dise au Gérant si le logiciel a délivré quoi que ce soit.
  bool get estUnEnvoiDuSysteme =>
      this == StatutMessageNotification.envoyeParLeSysteme;
}

/// Un message composé, en file ou au journal.
final class MessageNotification {
  const MessageNotification({
    required this.id,
    required this.modeleId,
    required this.declencheur,
    required this.canal,
    required this.reference,
    required this.destinataire,
    required this.contenu,
    required this.longueur,
    required this.statut,
    required this.composeLe,
    this.objet,
    this.commentaire,
    this.motifAbandon,
    this.traitePar,
    this.traiteLe,
  });

  final String id;
  final String modeleId;

  /// `null` si le modèle porte un événement HORS registre.
  ///
  /// Rendre `null` plutôt qu'un déclencheur de repli est délibéré : l'anomalie
  /// doit se voir à l'écran, pas se fondre derrière un libellé fabriqué.
  final DeclencheurNotification? declencheur;

  /// `null` si le canal stocké est hors registre — même raisonnement.
  final CanalNotification? canal;

  final String reference;
  final String destinataire;
  final String? objet;
  final String contenu;
  final int longueur;
  final StatutMessageNotification statut;
  final DateTime composeLe;
  final String? commentaire;
  final String? motifAbandon;
  final String? traitePar;
  final DateTime? traiteLe;

  bool get estEnAttente => statut == StatutMessageNotification.enAttente;

  /// Vrai pour tout message sorti de la file — la moitié « traitement » du
  /// journal du maître.
  bool get estAuJournal => !estEnAttente;

  /// Ce que le journal affiche en colonne « Commentaire » : le commentaire de
  /// transmission, ou le motif d'abandon, ou un tiret.
  ///
  /// Le tiret est celui de l'Article 7 : une case vide laisserait croire à un
  /// défaut d'affichage.
  String get commentaireAffiche => commentaire ?? motifAbandon ?? '—';

  /// L'auteur du geste, ou un tiret. Jamais « système » : aucun système n'a
  /// rien fait.
  String get auteurAffiche => traitePar ?? '—';

  /// Le dépassement de la limite du canal, s'il y en a une et si elle est
  /// franchie.
  ///
  /// `null` quand le canal n'impose aucune limite (e-mail) ou qu'elle est
  /// respectée — distinct de `0`, qui se lirait comme « pile à la limite ».
  int? get depassement {
    final limite = canal?.limite;
    if (limite == null || longueur <= limite) return null;
    return longueur - limite;
  }
}
