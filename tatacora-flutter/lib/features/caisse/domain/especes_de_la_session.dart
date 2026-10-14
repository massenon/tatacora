/// Les espèces encaissées d'une session — la SOURCE du théorique de caisse.
///
/// Réplique de `PosComptant::especesDeLaSession` :
///
/// ```php
/// Vente::query()
///     ->where('session_id', $sessionId)
///     ->where('statut', 'validee')
///     ->where('mode_paiement', 'especes')
///     ->sum('montant_total');
/// ```
///
/// Ici la « vente » est un panier au COMPTANT clôturé, rattaché à sa session par
/// `session_encaissement_id` (D221, option a). Mobile Money, carte, virement et
/// note de chambre n'entrent pas dans un tiroir ; un panier annulé n'est pas une
/// vente (le serveur annule une vente par un statut, le poste n'annule que des
/// paniers OUVERTS : une vente clôturée se corrige par un avoir).
///
/// ## Ce que cette somme ne contient PAS — et que le serveur ignore aussi
///
/// Les ENCAISSEMENTS DE FACTURE en espèces rattachés à la même session. Le
/// serveur écrit `paiements.session_id` mais son théorique ne lit que `ventes` :
/// un recouvrement en espèces entre dans le tiroir sans entrer dans le théorique,
/// et la clôture annonce un écart POSITIF qui n'en est pas un. Incohérence du
/// SERVEUR répliquée à l'identique (D230), pas corrigée ici — à remonter à
/// l'Architecte. Inversement, l'indicateur « Trésorerie de caisse » de M11 lit le
/// fond et les paiements mais ignore les ventes : deux définitions du tiroir.
///
/// @see EF-M5-06 Vente au comptoir du bar
library;

import '../../pos/domain/entities/mode_reglement.dart';
import '../../pos/domain/entities/panier.dart';

/// Les espèces d'une session, en CENTIMES : la somme des montants figés des
/// paniers au comptant clôturés et réglés en `especes` dans [sessionId].
///
/// Le montant d'un panier est en FRANCS entiers (`montantCloture`) : le XOF n'a
/// pas de sous-unité en circulation. Un panier sans montant figé (clôturé avant
/// qu'on le fige — impossible depuis la v3) compterait zéro, jamais une valeur
/// recalculée depuis ses lignes.
int especesEncaisseesCentimes(Iterable<Panier> paniers, String sessionId) {
  var total = 0;
  for (final p in paniers) {
    if (p.sessionEncaissementId != sessionId) continue;
    if (p.statut != StatutPanier.cloture) continue;
    if (p.modePaiement != ModeReglement.especes.code) continue;
    total += (p.montantCloture ?? 0) * 100;
  }
  return total;
}

/// Les ventes en espèces de la période qui ne sont rattachées à AUCUNE session.
///
/// ## Pourquoi le poste doit le DIRE (réserve R2 du contrôle, 12/10/2026)
///
/// Avant la v18, un panier clôturé n'écrivait pas la session qui l'avait
/// encaissé. Une session ouverte AVANT la mise à jour voit donc un théorique
/// sans les ventes antérieures : le chiffre est exact au sens de la formule
/// (`fond + espèces rattachées`), et FAUX au sens du tiroir. Le serveur n'a pas
/// ce cas (`ventes.session_id` y est écrit depuis toujours) ; le poste, lui, l'a
/// hérité de son histoire, et ne doit pas présenter ce théorique comme un fait.
///
/// ## Ce que la fonction mesure — et ce qu'elle ne devine pas
///
/// Les paniers au COMPTANT, clôturés, réglés en espèces, clôturés à
/// [ouvertureSession] ou après, et dont `sessionEncaissementId` est vide. Depuis
/// la v18, `PanierDao.cloturer` refuse un panier au comptant sans caisse ouverte :
/// un panier de cette espèce est donc une vente d'AVANT la mise à jour (ou une
/// ligne écrite hors du chemin de production). La fonction ne dit PAS que
/// l'argent est dans le tiroir — seulement que le théorique ne le compte pas.
///
/// Un panier de séjour (note de chambre) n'est pas une vente en espèces ; un mode
/// « non renseigné » non plus : on ne range pas au hasard un argent dont on
/// ignore la forme. Les montants sont des FRANCS entiers (`montantCloture`).
({int nombre, int montant}) ventesEnEspecesSansSession(
  Iterable<Panier> paniers,
  DateTime ouvertureSession,
) {
  var nombre = 0;
  var montant = 0;
  for (final p in paniers) {
    if (p.sessionEncaissementId != null) continue;
    if (p.statut != StatutPanier.cloture) continue;
    if (p.typeVente != TypeVente.comptant) continue;
    if (p.modePaiement != ModeReglement.especes.code) continue;
    final cloture = p.clotureLe;
    if (cloture == null || cloture.isBefore(ouvertureSession)) continue;
    nombre++;
    montant += p.montantCloture ?? 0;
  }
  return (nombre: nombre, montant: montant);
}
