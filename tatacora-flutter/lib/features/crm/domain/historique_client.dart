// Vue Blade maîtresse (PA-183) : pwa/crm/clients-creances.blade.php
import '../../facturation/domain/creances.dart';
import '../../facturation/domain/entities/paiement_facture.dart';
import 'entities/relance.dart';

/// Un mouvement de la modale « Historique d'un client » — une ligne de ses
/// cinq colonnes (`Date · Type · Libellé · Détail · Montant`).
final class MouvementClient {
  const MouvementClient({
    required this.date,
    required this.type,
    required this.libelle,
    required this.detail,
    required this.montantCentimes,
  });

  final DateTime date;

  /// `pwa.clients.historique_type_encaissement`.
  final String type;

  /// Le numéro de la pièce réglée. La vue rend le numéro MECeF de la facture
  /// (ou un tiret tant qu'elle n'est pas certifiée) ; ce poste n'a pas de
  /// numéro MECeF, et son numéro de pièce est la donnée réelle la plus proche.
  final String libelle;

  /// Le mode de règlement (`pwa.clients.mode_*`).
  final String detail;

  final int montantCentimes;
}

/// Le type d'un encaissement (`pwa.clients.historique_type_encaissement`).
const String typeEncaissement = 'Encaissement';

/// Le type d'une relance (`pwa.clients.historique_type_relance`) — aussi son
/// libellé dans la colonne « Libellé » (maître, l.360).
const String typeRelance = 'Relance';

/// `ClientsCreances::historiqueClient()` — les encaissements des factures du
/// client, du plus récent au plus ancien, ANNULÉS COMPRIS (aucun filtre de
/// statut au serveur : incohérence répliquée, D233), PUIS ses relances, du plus
/// récent au plus ancien (la vue boucle les paiements, puis les relances —
/// aucun tri commun).
///
/// Une relance se lit : date, type « Relance », libellé « Relance », le canal en
/// détail, le montant RÉCLAMÉ ce jour-là (figé).
List<MouvementClient> composerHistoriqueClient({
  required String clientId,
  required List<PaiementFacture> paiements,
  required List<CreanceFacture> creances,
  List<Relance> relances = const [],
}) {
  final pieces = {for (final c in creances) c.piece.id: c.piece};

  final encaissements = <MouvementClient>[
    for (final p in paiements)
      if (pieces[p.pieceId]?.clientId == clientId)
        MouvementClient(
          date: p.datePaiement,
          type: typeEncaissement,
          libelle: pieces[p.pieceId]!.numero,
          detail: p.mode.libelle,
          montantCentimes: p.montantCentimes,
        ),
  ]..sort((a, b) => b.date.compareTo(a.date));

  final lesRelances = <MouvementClient>[
    for (final r in relances)
      if (r.clientId == clientId)
        MouvementClient(
          date: r.dateRelance,
          type: typeRelance,
          libelle: typeRelance,
          detail: CanalRelance.libelleDe(r.canal),
          montantCentimes: r.montantReclameCentimes,
        ),
  ]..sort((a, b) => b.date.compareTo(a.date));

  return [...encaissements, ...lesRelances];
}
