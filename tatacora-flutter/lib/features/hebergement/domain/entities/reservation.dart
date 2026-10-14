import 'annulation_enregistree.dart';
import 'fiche_reservation.dart';
import 'periode_sejour.dart';
import 'service_reservation.dart';

/// Cycle de vie métier d'une réservation.
///
/// Les cinq valeurs sont celles de l'enum MySQL `reservations.statut`. La liste
/// doit rester alignée : `en_attente` manquait au client jusqu'au 18/08/2026,
/// et une réservation que le serveur tenait pour **en attente** s'affichait
/// donc « confirmée » au comptoir — on annonçait au client une chambre qui ne
/// lui était pas garantie.
enum StatutReservation {
  /// Défaut du serveur à la création : `CreerReservationRequest` n'accepte pas
  /// `statut`, le client ne peut donc jamais confirmer lui-même.
  enAttente('en_attente'),
  confirmee('confirmee'),
  enCours('en_cours'),
  terminee('terminee'),
  annulee('annulee');

  const StatutReservation(this.code);
  final String code;

  /// Un code inconnu vaut `enAttente` — la lecture prudente. `confirmee` par
  /// défaut promettrait une chambre sur la foi d'une valeur incomprise.
  static StatutReservation depuisCode(String? code) => values.firstWhere(
    (s) => s.code == code,
    orElse: () => StatutReservation.enAttente,
  );
}

/// Où en est cette réservation vis-à-vis du serveur.
///
/// C'est une information **de premier plan**, pas un détail technique : un
/// réceptionniste qui ignore qu'une saisie n'est pas partie la ressaisira, et
/// le doublon apparaîtra ailleurs.
enum StatutSynchronisation {
  /// Créée hors connexion, pas encore poussée dans la file.
  local('local'),

  /// Dans la file, en attente de réseau ou de réponse.
  enAttente('en_attente'),

  /// Acceptée par le serveur.
  synchronise('synchronise'),

  /// **Refusée** par le serveur — chevauchement RG-01, le plus souvent.
  /// La réservation est conservée localement avec son motif : elle n'est
  /// jamais supprimée en silence.
  rejete('rejete');

  const StatutSynchronisation(this.code);
  final String code;

  static StatutSynchronisation depuisCode(String? code) => values.firstWhere(
    (s) => s.code == code,
    orElse: () => StatutSynchronisation.local,
  );

  /// Vrai tant que le serveur n'a pas tranché.
  bool get estEnSuspens =>
      this == StatutSynchronisation.local ||
      this == StatutSynchronisation.enAttente;
}

/// Une réservation d'hébergement.
///
/// ## Le montant n'est pas un champ saisi
///
/// `montantTotal` est **calculé** depuis le tarif de l'unité et le nombre de
/// nuits. Un total modifiable finit toujours par contredire les dates, et
/// c'est la saisie qui l'emporte — on ne sait alors plus quel chiffre est le
/// bon. Pour changer le total, on change ce qui le produit.
///
/// ## L'identifiant vient du client, pas du serveur
///
/// UUID v4 posé **à la création de l'objet**, jamais à l'envoi. C'est lui qui
/// rend l'opération idempotente : si le réseau coupe après traitement mais
/// avant la réponse, le rejeu porte le même identifiant et le serveur n'en
/// applique qu'un.
final class Reservation {
  const Reservation({
    required this.id,
    required this.reference,
    required this.clientId,
    required this.clientNom,
    required this.uniteId,
    required this.periode,
    required this.tarifNuit,
    required this.statut,
    required this.statutSynchronisation,
    required this.creeeLe,
    this.acompte = 0,
    this.typeClient,
    this.canal,
    this.modePaiement,
    this.remiseType,
    this.remiseValeur,
    this.motifRejet,
    this.motifAnnulation,
    this.annulation,
    this.lignes = const [],
  });

  final String id;

  /// Référence lisible. Provisoire tant que le serveur n'a pas répondu :
  /// c'est lui qui détient la numérotation continue exigée par la
  /// facturation.
  final String reference;

  final String clientId;
  final String clientNom;
  final String uniteId;
  final PeriodeSejour periode;

  /// Tarif figé **au moment de la réservation**.
  ///
  /// Reprendre le tarif courant de l'unité ferait varier le montant d'une
  /// réservation passée à chaque changement de grille tarifaire.
  final int tarifNuit;

  final StatutReservation statut;
  final StatutSynchronisation statutSynchronisation;
  final DateTime creeeLe;
  final int acompte;

  /// La FICHE du maitre — quatre attributs de `reservations.html`.
  ///
  /// Tous nullables : les reservations anterieures au schema v7 n'en portent
  /// pas, et leur inventer une valeur affirmerait un canal ou un mode de
  /// paiement que personne n'a choisi.
  final TypeClient? typeClient;
  final CanalReservation? canal;
  final ModePaiementReservation? modePaiement;
  final TypeRemise? remiseType;

  /// La valeur SAISIE — pourcentage ou francs selon [remiseType]. Le montant
  /// de la remise se CALCULE (`RecapitulatifReservation`), il ne se stocke
  /// pas : deux verites divergeraient au premier changement de tarif.
  final num? remiseValeur;

  /// Message du serveur en cas de rejet. Affiché tel quel : c'est lui qui
  /// explique au réceptionniste pourquoi sa saisie n'a pas pris.
  final String? motifRejet;

  final String? motifAnnulation;

  /// Ce que l'annulation a FIXÉ (taux, commission, remboursement, auteur) —
  /// `null` pour une réservation jamais annulée, et pour une annulation
  /// d'AVANT la v19, qui n'avait rien de tout cela.
  final AnnulationEnregistree? annulation;

  /// Les services inclus dans cette réservation (schéma v8).
  ///
  /// Vide pour les réservations antérieures à la v8 : elles n'en portent pas,
  /// et leur en fabriquer une à partir du `tarifNuit` inventerait des lignes —
  /// à zéro franc pour celles reprises de la v1, dont le tarif n'existe nulle
  /// part. Voir la branche `from < 8` de la migration.
  final List<LigneService> lignes;

  int get nuits => periode.nuits;

  /// Somme des lignes de service, en francs CFA.
  int get sousTotalServices =>
      lignes.fold(0, (somme, ligne) => somme + ligne.sousTotal);

  /// Montant total, en francs CFA. Dérivé, jamais stocké en entrée.
  ///
  /// **Deux dérivations, et la bonne dépend de l'âge de la réservation.** Une
  /// réservation portant des lignes vaut la somme de ses lignes — c'est le
  /// récapitulatif du maître. Une réservation antérieure à la v8 n'en a
  /// aucune : son montant reste `tarifNuit × nuits`, la seule information
  /// qu'elle porte. Rendre zéro dans ce cas ferait disparaître le montant de
  /// tout l'historique le jour de la mise à jour.
  int get montantTotal =>
      lignes.isEmpty ? tarifNuit * nuits : sousTotalServices;

  /// Le récapitulatif financier — **la même formule que la fiche de saisie**.
  ///
  /// Une seconde formule finirait par diverger de la première, et c'est le
  /// total affiché au client qui trancherait.
  RecapitulatifReservation get recapitulatif =>
      RecapitulatifReservation.calculer(
        sousTotal: montantTotal,
        typeRemise: remiseType ?? TypeRemise.aucune,
        valeurRemise: remiseValeur ?? 0,
        acompte: acompte,
      );

  /// Ce que le client doit encore, **remise comprise**.
  ///
  /// Jusqu'au 25/08/2026 : `montantTotal - acompte`, qui ignorait purement et
  /// simplement la remise. Une réservation remisée affichait donc un reste dû
  /// supérieur à la réalité — on aurait réclamé au client de l'argent qu'on
  /// venait de lui accorder.
  int get resteAPayer => recapitulatif.reste;

  bool get estActive => statut != StatutReservation.annulee;

  /// Engage l'unité tant que le séjour n'est pas terminé.
  ///
  /// Sert au calcul de disponibilité : une réservation annulée ou dont la
  /// date de départ est passée ne bloque plus rien.
  bool engageLUnite(DateTime maintenant) =>
      estActive &&
      periode.depart.isAfter(
        DateTime.utc(maintenant.year, maintenant.month, maintenant.day),
      );

  Reservation copyWith({
    String? reference,
    StatutReservation? statut,
    StatutSynchronisation? statutSynchronisation,
    int? acompte,
    String? motifRejet,
    String? motifAnnulation,
    AnnulationEnregistree? annulation,
  }) => Reservation(
    id: id,
    reference: reference ?? this.reference,
    clientId: clientId,
    clientNom: clientNom,
    uniteId: uniteId,
    periode: periode,
    tarifNuit: tarifNuit,
    statut: statut ?? this.statut,
    statutSynchronisation: statutSynchronisation ?? this.statutSynchronisation,
    creeeLe: creeeLe,
    acompte: acompte ?? this.acompte,
    lignes: lignes,
    // La fiche est REPORTEE, toujours. Aucun parametre ne la modifie : les
    // seuls appelants de `copyWith` sont la synchronisation et l'annulation,
    // qui n'ont aucune raison de toucher au canal ni au mode de paiement. Les
    // omettre ici les aurait effaces au premier retour du serveur — une saisie
    // qui disparait apres coup, sans erreur ni trace.
    typeClient: typeClient,
    canal: canal,
    modePaiement: modePaiement,
    remiseType: remiseType,
    remiseValeur: remiseValeur,
    motifRejet: motifRejet ?? this.motifRejet,
    motifAnnulation: motifAnnulation ?? this.motifAnnulation,
    annulation: annulation ?? this.annulation,
  );

  @override
  bool operator ==(Object other) => other is Reservation && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'Reservation($reference, $clientNom, ${periode.nuits} nuit(s), ${statutSynchronisation.code})';
}
