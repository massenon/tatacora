import '../../comptabilite/data/moteur_comptable.dart';
import '../../comptabilite/domain/comptes_syscohada.dart';
import '../../depenses/domain/categories_depense.dart';
import '../domain/entities/paiement_facture.dart';

/// La pièce comptable d'un encaissement — **fonction pure**, réplique des lignes
/// de `EncaissementFactureService::encaisser`.
///
/// * un DÉBIT de la trésorerie du mode (le compte et le journal font foi chez
///   `TresorerieDepense`, réplique de `DepenseService::TRESORERIES` — « carte »
///   entre en BANQUE : le TPE crédite le compte bancaire, jamais le tiroir) ;
/// * un CRÉDIT de `4111` Clients, au journal de cette trésorerie (CAI ou BQ).
///
/// Aucune TVA : un encaissement de créance ne touche pas les produits, la taxe a
/// été traitée (ou refusée) à l'émission de la facture. Aucun centre n'est passé :
/// c'est le défaut du compte qui joue (5711 -> Hébergement, 4111 -> Structure),
/// comme au serveur, où la pièce naît sans centre explicite.
///
/// @see RG-11 La pièce est VALIDÉE d'emblée, donc immuable
/// @see EF-M2-03 Encaissement des factures
DemandePiece pieceDeLEncaissement({
  required ModePaiementFacture mode,
  required String dateIso,
  required String libelle,
  required int montantCentimes,
}) {
  final tresorerie = TresorerieDepense.depuisCode(mode.tresorerie.code)!;
  return DemandePiece(
    journal: tresorerie.journal,
    date: dateIso,
    libelle: libelle,
    lignes: [
      LigneDemandee(compte: tresorerie.compte, debitCentimes: montantCentimes),
      LigneDemandee(
        compte: ComptesSyscohada.clients,
        creditCentimes: montantCentimes,
      ),
    ],
  );
}
