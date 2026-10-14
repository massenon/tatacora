import '../entities/paiement_facture.dart';

/// Les encaissements de factures du poste.
///
/// Le contrat ne dit PAS d'où vient la donnée : c'est ce qui interdit les
/// branches « si connecté » dans les écrans. Le seul auteur de la table est
/// `PaiementsFactureDao`.
abstract interface class PaiementsFactureRepository {
  /// Tous les encaissements, du plus récent au plus ancien, ANNULÉS compris —
  /// comme `Paiement::query()->orderByDesc('date_paiement')` du serveur, qui ne
  /// filtre pas le statut (la table « Recouvrements encaissés » de la vue ne
  /// distingue pas un encaissement annulé : incohérence du serveur répliquée).
  Future<List<PaiementFacture>> paiements();

  Future<PaiementFacture?> parId(String id);

  /// `ClientsCreances::enregistrerRecouvrement` : le droit (M3 puis M2), la
  /// validation de la saisie, puis le service.
  ///
  /// [peutEncaisser] est le droit COMBINÉ sur les deux modules : le serveur exige
  /// M3 (l'écran) puis M2 (l'écriture d'un encaissement) et répond 403 au
  /// premier qui manque, avant toute validation.
  ///
  /// Lève `RefusEncaissement` (rien n'a été écrit) ou `RefusComptable` (la pièce
  /// a été refusée : ni paiement ni pièce n'existent).
  Future<PaiementFacture> recouvrer({
    required String? pieceId,
    required String? montantSaisi,
    required String? modeSaisi,
    required String auteurId,
    required bool peutEncaisser,
  });

  /// `EncaissementFactureService::encaisser` : le service seul, sans le droit ni
  /// la validation du composant. [montant] est la chaîne que le service reçoit
  /// (« 30000.00 »).
  Future<PaiementFacture> encaisser({
    required String pieceId,
    required String montant,
    required String mode,
    required String auteurId,
  });

  /// `EncaissementFactureService::annuler` : un ÉTAT tracé, jamais une
  /// suppression, et la contre-passation de la pièce ENTIÈRE dans la même
  /// transaction.
  ///
  /// ⚠ Comme au serveur, AUCUN écran ne l'appelle : le service existe, la vue
  /// `clients-creances` n'expose aucun geste d'annulation. Un test le garde.
  Future<PaiementFacture> annuler(
    String paiementId,
    String motif, {
    required String auteurId,
  });
}
