/// La REMISE d'un panier — le motif de la fiche de réservation (directive du
/// Product Owner du 02/09/2026) : le TYPE (`aucune`, `pourcentage`, `montant`)
/// et la VALEUR saisis, jamais un montant pré-calculé — un montant figé
/// deviendrait faux au premier article ajouté. Le montant se DÉRIVE ici, par
/// une réplique de `Panier::remiseSur()` du serveur (auteur unique de la règle),
/// en centimes entiers : `bcmath` tronque, le poste aussi.
///
/// ## Les bornes (celles du serveur)
///
/// * une valeur NÉGATIVE est refusée ;
/// * un pourcentage vit entre 0 et 100 ;
/// * un montant en francs ne dépasse pas le total des lignes ;
/// * un net négatif ne doit jamais exister, ni à l'écran ni sur la pièce.
///
/// La borne est jugée ICI, à la saisie ET à l'encaissement : une remise en
/// francs devenue supérieure au total (une ligne retirée après coup) fait
/// refuser l'encaissement, jamais produire un encaissement négatif plausible.
///
/// @see ventes.remise_* du serveur (relues par PHP dans
///      `ventes_contre_serveur_test.dart`)
library;

import '../../hebergement/domain/entities/fiche_reservation.dart'
    show TypeRemise;
import 'messages_ventes.dart';

/// Le montant de la remise, en CENTIMES, sur un total en FRANCS entiers.
///
/// [valeurCentiemes] est la valeur saisie en centièmes (12,5 % = 1250 ;
/// 500 F = 50000). Lève [RefusVente] hors bornes, avec la phrase du serveur.
///
/// Pourcentage : `bcdiv(bcmul(total, valeur, 4), '100', 2)` — soit, en centimes,
/// `⌊total_c × valeur_c / 10 000⌋` (les deux opérandes ont deux décimales, le
/// produit est exact à quatre, la division tronque à deux).
int montantRemiseCentimes({
  required int totalFrancs,
  required TypeRemise type,
  required int valeurCentiemes,
}) {
  if (type == TypeRemise.aucune) return 0;
  if (valeurCentiemes < 0) {
    throw const RefusVente(MessagesVentes.remiseValeurInvalide);
  }
  final totalCentimes = totalFrancs * 100;
  if (type == TypeRemise.pourcentage) {
    if (valeurCentiemes > 10000) {
      throw const RefusVente(MessagesVentes.remisePourcentageHorsBornes);
    }
    return (totalCentimes * valeurCentiemes) ~/ 10000;
  }
  // Un montant en francs : sa valeur en centièmes EST des centimes.
  if (valeurCentiemes > totalCentimes) {
    throw const RefusVente(MessagesVentes.remiseSuperieureAuTotal);
  }
  return valeurCentiemes;
}

/// La valeur saisie (« 10 », « 12,5 », « 500 ») en centièmes, ou `null` si ce
/// n'est pas un nombre. Deux décimales au plus (`remise_valeur` est un
/// `DECIMAL(15,2)` au serveur) ; la virgule est acceptée, c'est celle qu'on
/// tape au Bénin ; un signe est refusé par l'appelant (valeur négative).
int? centiemesDepuisSaisie(String brut) {
  final texte = brut.trim().replaceAll(',', '.').replaceAll(' ', '');
  final m = RegExp(r'^(-?)(\d+)(?:\.(\d{1,2}))?$').firstMatch(texte);
  if (m == null) return null;
  final entier = int.parse(m.group(2)!);
  final decimales = (m.group(3) ?? '').padRight(2, '0');
  final valeur = entier * 100 + int.parse(decimales.isEmpty ? '0' : decimales);
  return m.group(1) == '-' ? -valeur : valeur;
}

/// Ramène la ventilation brute par module (centimes) au NET encaissé —
/// réplique de `VenteService::ventilerAuNet()`.
///
/// Chaque module cède sa quote-part de remise au prorata de son montant
/// (`⌊montant × net / brut⌋`) ; le DERNIER module, dans l'ordre reçu, prend
/// l'écart d'arrondi : la somme des crédits égale le débit de contrepartie
/// centime pour centime. Sans remise (`net == brut`), rien ne change.
///
/// L'ordre de [brut] est celui du serveur (`ventilerParModule` : les modules
/// encaissables d'abord, dans leur ordre) — c'est lui qui désigne le dernier.
Map<String, int> ventilerAuNet(Map<String, int> brut, int net) {
  var total = 0;
  for (final m in brut.values) {
    total += m;
  }
  if (brut.isEmpty || total == net || total <= 0) return brut;

  final nette = <String, int>{};
  var reste = net;
  final modules = brut.keys.toList();
  for (final module in modules) {
    if (module == modules.last) {
      nette[module] = reste;
      continue;
    }
    final part = (brut[module]! * net) ~/ total;
    nette[module] = part;
    reste -= part;
  }
  return nette;
}
