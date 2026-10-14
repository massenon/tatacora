/// La créance d'une facture — fonctions PURES, réplique de `Facture::SQL_RESTE_DU`
/// et de `SoldeClientService` du serveur (lot 5, 12/10/2026).
///
/// ## Une seule formule, écrite ICI et nulle part ailleurs
///
/// Le serveur l'a apprise à ses dépens (PA-121, PA-165) : deux formules pour la
/// même grandeur divergent au premier terme ajouté. Le solde d'un client, le
/// bouton « Recouvrement », le refus de sur-encaissement, les trois indicateurs
/// de M11 et l'état « créances clients » de M14 lisent TOUS ce fichier.
///
/// ```
/// reste dû = TTC − avoirs émis − paiements ACTIFS − acomptes liés
/// ```
///
/// * **TTC** : la somme des lignes de la pièce. Le poste n'applique aucune TVA
///   à l'émission (PA-62) : TTC = HT, comme `montant_ttc` d'une facture dont
///   `montant_tva` vaut zéro.
/// * **Avoirs émis** : les pièces du registre dont `avoirDe` désigne le numéro
///   de la facture, en valeur absolue (leurs lignes portent une quantité
///   négative). Le serveur les somme sans regarder leur statut.
/// * **Paiements actifs** : un encaissement ANNULÉ ne compte plus (sa pièce est
///   contre-passée).
/// * **Acomptes liés** : l'acompte de la réservation que la facture couvre, SI la
///   facture porte une ligne d'hébergement (`source_module = 'M1'`). Il n'existe
///   pas en paiement : il est versé à la RÉSERVATION, avant l'émission.
///
/// Le résultat n'est PAS plafonné à zéro : le prédicat « impayée » (`> 0`) et le
/// solde l'utilisent tel quel, et un négatif doit se VOIR comme l'anomalie qu'il
/// est. Le plancher n'est posé qu'à l'affichage et au contrôle de
/// sur-encaissement ([CreanceFacture.resteDuCentimes]).
///
/// ## Ce qui est une « facture » ici, et ce que le serveur ne connaît pas
///
/// Le registre local mêle trois choses que le serveur sépare : des factures, des
/// avoirs (table `avoirs`) et des tickets de vente au comptant (table `ventes`).
/// Seule la première est une créance. Voir [estUneCreance].
///
/// @see EF-M3-04 Suivi des soldes et créances
/// @see EF-M2-03 Encaissement des factures
library;

import '../../hebergement/domain/entities/reservation.dart';
import 'entities/paiement_facture.dart';
import 'entities/piece_facturation.dart';

/// La pièce est-elle une FACTURE au sens du serveur — une créance possible ?
///
/// * un avoir ne l'est pas (il VIENT en diminution d'une créance) ;
/// * un ticket de vente au comptant ne l'est pas : le panier a été encaissé à la
///   vente, dans une session de caisse (`session_encaissement_id`). Au serveur
///   cette vente est une ligne de `ventes`, jamais de `factures`. La traiter en
///   créance ferait réclamer une seconde fois l'argent déjà en caisse — ÉCART
///   DU POSTE, nommé (D228).
bool estUneCreance(PieceFacturation piece) =>
    !piece.estAvoir && piece.origine != OrigineFacture.posComptant;

/// Une facture et tout ce qui la solde.
final class CreanceFacture {
  const CreanceFacture({
    required this.piece,
    required this.ttcCentimes,
    required this.avoirsCentimes,
    required this.paiementsActifsCentimes,
    required this.acomptesCentimes,
  });

  final PieceFacturation piece;
  final int ttcCentimes;
  final int avoirsCentimes;
  final int paiementsActifsCentimes;
  final int acomptesCentimes;

  /// `Facture::SQL_RESTE_DU` — SANS plancher.
  int get resteDuBrutCentimes =>
      ttcCentimes - avoirsCentimes - paiementsActifsCentimes - acomptesCentimes;

  /// `Facture::resteDu()` — plancher à zéro : « rien à réclamer » se dit, un
  /// négatif se refuse en amont.
  int get resteDuCentimes => resteDuBrutCentimes < 0 ? 0 : resteDuBrutCentimes;

  /// `SoldeClientService::appliquerPredicatImpayee` : reste dû strictement
  /// positif. (Le prédicat « certifiée » du serveur est ici [estUneCreance] :
  /// toute facture du registre est figée dès son émission.)
  bool get estImpayee => resteDuBrutCentimes > 0;

  /// `Facture::estSoldee()` : le reste dû plafonné vaut zéro.
  bool get estSoldee => resteDuCentimes == 0;
}

/// Les créances du poste : une entrée par FACTURE du registre, impayée ou non.
///
/// [acomptesParReservation] : l'acompte (en FRANCS) de chaque réservation, par
/// identifiant — la seule lecture que cette fonction demande à M1. Fonction
/// pure : elle ne lit ni base ni réseau, c'est ce qui permet de la confronter au
/// serveur sans monter d'écran.
List<CreanceFacture> composerCreances({
  required List<PieceFacturation> pieces,
  required List<PaiementFacture> paiements,
  required Map<String, int> acomptesParReservation,
}) {
  final avoirsParNumero = <String, int>{};
  for (final p in pieces) {
    final cible = p.avoirDe;
    if (cible == null) continue;
    // Les lignes d'un avoir ont une quantité négative : son montant est la
    // valeur absolue de leur somme.
    avoirsParNumero[cible] = (avoirsParNumero[cible] ?? 0) + (-p.montantTotal);
  }

  final paiementsParPiece = <String, int>{};
  for (final pa in paiements) {
    if (!pa.estActif) continue;
    paiementsParPiece[pa.pieceId] =
        (paiementsParPiece[pa.pieceId] ?? 0) + pa.montantCentimes;
  }

  return [
    for (final piece in pieces)
      if (estUneCreance(piece))
        CreanceFacture(
          piece: piece,
          ttcCentimes: piece.montantTotal * 100,
          avoirsCentimes: (avoirsParNumero[piece.numero] ?? 0) * 100,
          paiementsActifsCentimes: paiementsParPiece[piece.id] ?? 0,
          acomptesCentimes: _acompteLie(piece, acomptesParReservation),
        ),
  ];
}

/// `SQL_ACOMPTES_LIES` : l'acompte de la réservation que la facture couvre, si
/// elle porte une ligne d'hébergement.
///
/// Le serveur ne regarde ni le statut de la réservation ni les AUTRES factures
/// qui la couvrent : deux factures d'une même réservation déduiraient chacune
/// son acompte en entier. Incohérence du serveur répliquée (D228), pas corrigée.
int _acompteLie(PieceFacturation piece, Map<String, int> acomptes) {
  final reservation = piece.reservationId;
  if (reservation == null) return 0;
  final porteLHebergement = piece.lignes.any(
    (l) => l.module == ModuleFacturable.m1Hebergement,
  );
  if (!porteLHebergement) return 0;
  return (acomptes[reservation] ?? 0) * 100;
}

/// Les acomptes (en francs) des réservations, par identifiant.
Map<String, int> acomptesDesReservations(List<Reservation> reservations) => {
  for (final r in reservations) r.id: r.acompte,
};

/// Le solde d'un client, tel que le registre le porte.
final class SoldeClient {
  const SoldeClient({
    required this.clientId,
    required this.soldeCentimes,
    required this.nbPieces,
    this.plusAncienne,
  });

  final String clientId;

  /// `SUM(reste dû)` des factures impayées du client (SANS plancher par facture,
  /// comme `SoldeClientService::registre`).
  final int soldeCentimes;

  /// Le nombre de factures impayées.
  final int nbPieces;

  /// La date d'émission de la plus ancienne facture impayée, ou `null`.
  final DateTime? plusAncienne;
}

/// `SoldeClientService::registre()`, restreint aux clients qui ont une dette :
/// le client sans facture impayée est ABSENT (l'appelant le rend à zéro, ce que
/// fait le `COALESCE` du serveur).
Map<String, SoldeClient> soldesParClient(List<CreanceFacture> creances) {
  final parClient = <String, List<CreanceFacture>>{};
  for (final c in creances) {
    final client = c.piece.clientId;
    if (client == null || !c.estImpayee) continue;
    parClient.putIfAbsent(client, () => []).add(c);
  }
  return {
    for (final e in parClient.entries)
      e.key: SoldeClient(
        clientId: e.key,
        soldeCentimes: e.value.fold(0, (t, c) => t + c.resteDuBrutCentimes),
        nbPieces: e.value.length,
        plusAncienne: e.value
            .map((c) => c.piece.dateEmission)
            .reduce((a, b) => a.isBefore(b) ? a : b),
      ),
  };
}

/// `SoldeClientService::totaux()` : le total dû, le nombre de factures impayées
/// et le nombre de clients DISTINCTS qui les portent.
///
/// ⚠ Comme au serveur, `COUNT(DISTINCT factures.client_id)` ne compte pas une
/// facture sans client (un `NULL` n'est pas distinct) ; le total et le nombre de
/// pièces, eux, l'incluent. Au serveur `client_id` est NOT NULL ; le registre
/// local peut porter une facture directe sans client — écart nommé (D228).
({int totalDuCentimes, int nbPieces, int nbClients}) totauxCreances(
  List<CreanceFacture> creances,
) {
  final impayees = creances.where((c) => c.estImpayee).toList();
  return (
    totalDuCentimes: impayees.fold(0, (t, c) => t + c.resteDuBrutCentimes),
    nbPieces: impayees.length,
    nbClients: impayees
        .map((c) => c.piece.clientId)
        .whereType<String>()
        .toSet()
        .length,
  );
}

/// Le libellé d'une facture dans le sélecteur de la modale :
/// `numero_mecef ?? id` au serveur. Le poste n'a pas de numéro MECeF (jamais
/// certifié) : le numéro de pièce `F-AAAA-NNNNN` tient le même rôle.
String libelleDeLaFacture(PieceFacturation piece) => piece.numero;

/// `now()->subDays(30)` de Carbon : 30 jours CALENDAIRES en arrière, à la même
/// heure — pas 720 heures. (Le Bénin n'a pas d'heure d'été, les deux
/// coïncident ; l'écriture suit pourtant le serveur, qui ne dépend pas de ce
/// fait.)
DateTime ilYa30Jours(DateTime maintenant) => DateTime(
  maintenant.year,
  maintenant.month,
  maintenant.day - 30,
  maintenant.hour,
  maintenant.minute,
  maintenant.second,
  maintenant.millisecond,
);

/// `SoldeClientService::encaisseDepuis` : la somme des paiements ACTIFS dont la
/// date est postérieure ou égale à [depuis].
///
/// Le serveur a corrigé sa version d'écran, qui comptait les paiements ANNULÉS
/// (PA-168) : un encaissement annulé n'est pas un encaissement. Cette fonction
/// est la version corrigée, et c'est la seule du poste.
int encaisseDepuisCentimes(List<PaiementFacture> paiements, DateTime depuis) {
  var total = 0;
  for (final p in paiements) {
    if (!p.estActif) continue;
    if (p.datePaiement.isBefore(depuis)) continue;
    total += p.montantCentimes;
  }
  return total;
}

/// Les factures IMPAYÉES d'un client, de la plus ancienne à la plus récente —
/// `ClientsCreances::facturesImpayeesDuClient` :
/// `appliquerPredicatImpayee(...)->where('client_id', ...)->orderBy('date_emission')`.
///
/// C'est la liste du sélecteur « Pièce réglée » de la modale. Le serveur ne
/// départage pas deux factures du même jour ; le poste le fait par numéro, pour
/// qu'elles ne changent pas d'ordre d'une ouverture à l'autre.
List<CreanceFacture> facturesImpayeesDuClient(
  List<CreanceFacture> creances,
  String clientId,
) =>
    [
      for (final c in creances)
        if (c.piece.clientId == clientId && c.estImpayee) c,
    ]..sort((a, b) {
      final parDate = a.piece.dateEmission.compareTo(b.piece.dateEmission);
      return parDate != 0 ? parDate : a.piece.numero.compareTo(b.piece.numero);
    });

/* ====================================================================== */
/* La balance âgée                                                         */
/* ====================================================================== */

/// Les quatre tranches de la balance âgée — `ClientsCreances::TRANCHES`, reprises
/// du référentiel du maître (`creances-engine.js`, `TRANCHES`).
///
/// ⚠ L'ancienneté se compte depuis la DATE D'ÉMISSION de la facture, un fait ;
/// jamais depuis une date d'échéance que personne n'a décidée. L'ancien motif de
/// refus (« PA-20 : la balance âgée suppose une date d'échéance ») n'était plus
/// celui du serveur à la date de ce lot (12/10/2026).
enum TrancheAge {
  jusqua30('0_30', '0 à 30 jours', 0, 30),
  de31a60('31_60', '31 à 60 jours', 31, 60),
  de61a90('61_90', '61 à 90 jours', 61, 90),
  plus90('plus_90', 'Plus de 90 jours', 91, null);

  const TrancheAge(this.code, this.libelle, this.min, this.max);

  final String code;
  final String libelle;
  final int min;

  /// `null` : sans borne haute.
  final int? max;

  /// `trancheDe()` du serveur : la première tranche qui contient [jours], et
  /// « plus de 90 jours » pour tout le reste — **un nombre de jours NÉGATIF
  /// (facture datée du futur) y tombe aussi**, faute de tranche qui le contienne.
  /// Défaut du serveur répliqué (D233), pas corrigé : une facture datée de demain
  /// se lirait « douteuse ».
  static TrancheAge pour(int jours) {
    for (final t in values) {
      if (jours >= t.min && (t.max == null || jours <= t.max!)) return t;
    }
    return TrancheAge.plus90;
  }
}

/// Une ligne de la balance âgée : un client, son reste dû par tranche, son total.
final class LigneDetteAgee {
  const LigneDetteAgee({
    required this.clientId,
    required this.nom,
    required this.tranchesCentimes,
    required this.totalCentimes,
  });

  final String clientId;
  final String nom;
  final Map<TrancheAge, int> tranchesCentimes;
  final int totalCentimes;
}

/// `detteAgeeParClient()` du serveur — l'onglet « Suivi des dettes ».
///
/// Les factures IMPAYÉES (le prédicat du solde), groupées par client, rangées en
/// tranches par le nombre de jours entiers entre leur date d'émission et
/// [aujourdhui] (`Carbon::today()`). Le reste dû de chaque facture entre SANS
/// plancher, comme dans le solde. Un client absent du référentiel n'a pas de
/// ligne (jointure interne du serveur) ; [terme] filtre sur le nom ET le prénom
/// (`like %terme%`, sans le téléphone, à la différence de la liste).
///
/// Tri : total décroissant, puis le nom comparé octet à octet (`strcmp`).
List<LigneDetteAgee> detteAgeeParClient(
  List<CreanceFacture> creances,
  Map<String, ({String nom, String? prenom})> clients,
  DateTime aujourdhui, {
  String? terme,
}) {
  final recherche = terme?.toLowerCase();
  final parClient = <String, Map<TrancheAge, int>>{};
  final aujourdhuiUtc = DateTime.utc(
    aujourdhui.year,
    aujourdhui.month,
    aujourdhui.day,
  );

  for (final c in creances) {
    if (!c.estImpayee) continue;
    final client = c.piece.clientId == null ? null : clients[c.piece.clientId];
    if (client == null) continue;
    if (recherche != null &&
        !client.nom.toLowerCase().contains(recherche) &&
        !(client.prenom ?? '').toLowerCase().contains(recherche)) {
      continue;
    }
    final e = c.piece.dateEmission;
    final jours = aujourdhuiUtc
        .difference(DateTime.utc(e.year, e.month, e.day))
        .inDays;
    final tranches = parClient.putIfAbsent(
      c.piece.clientId!,
      () => {for (final t in TrancheAge.values) t: 0},
    );
    tranches[TrancheAge.pour(jours)] =
        tranches[TrancheAge.pour(jours)]! + c.resteDuBrutCentimes;
  }

  final lignes = [
    for (final e in parClient.entries)
      LigneDetteAgee(
        clientId: e.key,
        nom: [
          clients[e.key]!.nom,
          clients[e.key]!.prenom ?? '',
        ].join(' ').trim(),
        tranchesCentimes: e.value,
        totalCentimes: e.value.values.fold(0, (t, v) => t + v),
      ),
  ];
  lignes.sort((a, b) {
    final parTotal = b.totalCentimes.compareTo(a.totalCentimes);
    return parTotal != 0 ? parTotal : a.nom.compareTo(b.nom);
  });
  return lignes;
}

/// `kpiParTranche()` : le total d'UNE tranche sur la balance COMPLÈTE (jamais
/// filtrée par la recherche — la carte surplombe le tableau).
int totalDeLaTranche(List<LigneDetteAgee> lignes, TrancheAge tranche) =>
    lignes.fold(0, (t, l) => t + l.tranchesCentimes[tranche]!);
