import '../../comptabilite/data/moteur_comptable.dart';
import '../../depenses/domain/categories_depense.dart';

/// La pièce comptable d'un règlement fournisseur — **fonction pure**, réplique
/// des lignes de `ReglementFournisseurService::regler`.
///
/// * un DÉBIT du rôle `FOURNISSEURS` (4011 par défaut ; la dette diminue) ;
/// * un CRÉDIT de la trésorerie qui décaisse, au journal de cette trésorerie
///   (CAI pour la caisse, BQ pour le mobile money et la banque : le compte et le
///   journal font foi chez `TresorerieDepense`, réplique de
///   `DepenseService::TRESORERIES`).
///
/// Aucune TVA : un règlement de dette ne touche pas les charges, la taxe a été
/// traitée (ou refusée) à la commande. Aucun centre n'est passé : c'est le défaut
/// du compte qui joue (4011 -> Structure, 5711 -> Hébergement), comme au serveur,
/// où la pièce naît sans centre explicite.
///
/// @see RG-11 La pièce est VALIDÉE d'emblée, donc immuable
/// @see EF-M7-04 Dettes fournisseurs
DemandePiece pieceDuReglement({
  required TresorerieDepense tresorerie,
  required String dateIso,
  required String libelle,
  required int montantCentimes,
}) {
  return DemandePiece(
    journal: tresorerie.journal,
    date: dateIso,
    libelle: libelle,
    lignes: [
      LigneDemandee(role: 'FOURNISSEURS', debitCentimes: montantCentimes),
      LigneDemandee(role: tresorerie.role, creditCentimes: montantCentimes),
    ],
  );
}
