import '../../comptabilite/data/moteur_comptable.dart';
import '../../comptabilite/domain/comptes_syscohada.dart';
import '../../depenses/domain/categories_depense.dart';
import '../domain/entities/fiche_reservation.dart';
import '../domain/messages_annulation.dart';

/// La trésorerie qui ENCAISSE l'acompte selon le mode de la fiche —
/// `ReservationService::TRESORERIE_ACOMPTE_PAR_MODE`, et rien d'autre.
///
/// « Crédit » n'y figure pas : à crédit, l'acompte est PROMIS, pas reçu —
/// aucune trésorerie ne bouge, et la créance vit sur le reste à payer. Un mode
/// ABSENT n'y figure pas non plus : la trésorerie d'entrée est inconnaissable, et
/// imputer la caisse par défaut fausserait le tiroir du montant d'un Mobile
/// Money. Le flux reste celui que le serveur nomme (PA-162/PA-166) : sans
/// pièce, jamais deviné.
TresorerieDepense? tresorerieDeLAcompte(ModePaiementReservation? mode) =>
    switch (mode) {
      ModePaiementReservation.especes => TresorerieDepense.caisse,
      ModePaiementReservation.mobileMoney => TresorerieDepense.momo,
      ModePaiementReservation.virement => TresorerieDepense.banque,
      ModePaiementReservation.cheque => TresorerieDepense.banque,
      ModePaiementReservation.credit => null,
      null => null,
    };

/// La pièce de l'ACOMPTE reçu — **fonction pure**, réplique de
/// `ReservationService::comptabiliserAcompte` :
///
/// * un DÉBIT de la trésorerie du mode (compte et journal font foi chez
///   `TresorerieDepense`, réplique de `DepenseService::TRESORERIES`) ;
/// * un CRÉDIT de `4191` « Clients — avances et acomptes reçus ».
///
/// `null` dans les trois cas SANS pièce, et chacun est un fait, pas un oubli :
/// acompte nul (aucun argent), mode « crédit » (promis, pas reçu), mode absent
/// (trésorerie inconnaissable).
///
/// Aucun centre n'est passé : c'est le défaut du compte qui joue (5711 et 4191 ->
/// Hébergement, 552 et 5211 -> Structure), comme au serveur.
///
/// @see RG-11 La pièce est VALIDÉE d'emblée, donc immuable
DemandePiece? pieceDeLAcompte({
  required String reservationId,
  required ModePaiementReservation? mode,
  required int acompteCentimes,
  required String dateIso,
}) {
  if (acompteCentimes <= 0) return null;
  final tresorerie = tresorerieDeLAcompte(mode);
  if (tresorerie == null) return null;

  return DemandePiece(
    journal: tresorerie.journal,
    date: dateIso,
    libelle: MessagesAnnulation.libelleDeLAcompte(reservationId),
    lignes: [
      LigneDemandee(compte: tresorerie.compte, debitCentimes: acompteCentimes),
      LigneDemandee(
        compte: ComptesSyscohada.avancesClients,
        creditCentimes: acompteCentimes,
      ),
    ],
  );
}

/// La pièce du REMBOURSEMENT d'une annulation — **fonction pure**, réplique de
/// `AnnulationReservationService::passerEcritureRemboursement` :
///
/// * un DÉBIT de `4191` (la dette envers le client s'éteint) — c'est CETTE ligne
///   que la réservation désigne (`ecriture_remboursement_id`) ;
/// * un CRÉDIT de `5711` Caisse (l'argent sort réellement du tiroir).
///
/// La trésorerie est TOUJOURS la caisse : le compte rendu client et
/// l'instruction du PO ne parlent que d'argent qui « sort réellement de la
/// caisse », jamais d'un virement ni d'un Mobile Money. [client] est le nom
/// complet à la manière du serveur (`trim(prenom . ' ' . nom)`), repli sur
/// l'identifiant de la réservation.
DemandePiece pieceDuRemboursement({
  required String client,
  required int rembourseCentimes,
  required String dateIso,
}) {
  final caisse = TresorerieDepense.caisse;
  return DemandePiece(
    journal: caisse.journal,
    date: dateIso,
    libelle: MessagesAnnulation.libelleDeLaPiece(client),
    lignes: [
      LigneDemandee(
        compte: ComptesSyscohada.avancesClients,
        debitCentimes: rembourseCentimes,
      ),
      LigneDemandee(compte: caisse.compte, creditCentimes: rembourseCentimes),
    ],
  );
}
