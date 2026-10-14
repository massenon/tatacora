/// Les règles de calcul de M7 — fonctions PURES, en entiers.
///
/// ## Aucune règle ne vit dans un écran ni dans un DAO
///
/// Le DAO lit et écrit ; ce fichier décide. Chaque formule reprend celle du
/// serveur (`ReceptionService`, `LigneCommandeAchat`, `ControleTroisVoiesService`)
/// et **est confrontée à elle par exécution de PHP**
/// (`tool/achats/exporter_calculs.php`, `calcul_achats_contre_serveur_test.dart`) :
/// une copie recopiée à la main ne vérifierait qu'elle-même.
///
/// ## Des entiers, jamais un flottant
///
///  * quantités : CENTIÈMES entiers (`12,50` -> 1250) ;
///  * prix unitaires : CENTIÈMES de franc entiers (la précision
///    `DECIMAL(15,2)` du serveur) ;
///  * montants : CENTIÈMES de franc entiers, produit TRONQUÉ comme `bcmul`
///    (`LigneCommandeAchat::montant`) — arrondir au plus proche ferait
///    diverger l'écran du bon de commande remis au fournisseur ;
///  * pourcentages : CENTIÈMES de pour cent (`2,50 %` -> 250), quotient tronqué
///    vers zéro comme `bcdiv`.
///
/// Un `int` Dart est exact jusqu'à 2^63 : un bon de commande de plusieurs
/// milliards de francs reste exact, là où un `double` perdrait le centime.
library;

import 'decimal_texte.dart';
import 'entities/bon_reception.dart';
import 'entities/commande_achat.dart';

/// Écart conventionnel quand la quantité commandée est nulle : `'99999.99'` du
/// serveur (`ReceptionService::ECART_INCALCULABLE`), en centièmes de pour cent.
const int ecartIncalculableCentiemes = 9999999;

/// `quantité × prix`, ramené aux centièmes de franc par TRONCATURE —
/// `bcmul($q, $p, 2)`.
///
/// Les deux opérandes ont deux décimales : leur produit en entiers est exprimé
/// en dix-millièmes, et diviser par cent le ramène aux centièmes.
int montantLigneCentimes({
  required int quantiteCentiemes,
  required int prixUnitaireCentimes,
}) => (quantiteCentiemes * prixUnitaireCentimes) ~/ 100;

/// La somme des montants de lignes — `CommandeAchat::montantTotal`.
///
/// Somme des montants DÉJÀ tronqués ligne à ligne, comme `bcadd` : jamais le
/// produit de totaux, qui arrondirait autrement.
int montantTotalCentimes(
  Iterable<({int quantiteCentiemes, int prixUnitaireCentimes})> lignes,
) => lignes.fold(
  0,
  (somme, l) =>
      somme +
      montantLigneCentimes(
        quantiteCentiemes: l.quantiteCentiemes,
        prixUnitaireCentimes: l.prixUnitaireCentimes,
      ),
);

/// Écart reçu / commandé, en centièmes de pour cent de la quantité commandée.
/// Négatif = manquant, positif = excédent — `ReceptionService::ecartPourcentage`.
///
/// Quantité commandée nulle : aucun pourcentage n'a de sens (division par
/// zéro). Tout reçu non nul en face est un excédent infini
/// ([ecartIncalculableCentiemes]) ; zéro reçu pour zéro commandé est un écart
/// nul.
int ecartPourcentageCentiemes({
  required int recueCentiemes,
  required int commandeeCentiemes,
}) {
  if (commandeeCentiemes == 0) {
    return recueCentiemes == 0 ? 0 : ecartIncalculableCentiemes;
  }
  // ((r - c) / 100) * 100 / (c / 100), exprimé en centièmes de pour cent, soit
  // (r - c) * 10 000 / c. `~/` tronque vers zéro, comme `bcdiv`.
  return ((recueCentiemes - commandeeCentiemes) * 10000) ~/ commandeeCentiemes;
}

/// Le verdict RG-10 pour UNE ligne — `ReceptionService::conformiteLigne`.
///
/// Au-delà de la tolérance en excédent : `non_conforme` (recevoir plus que
/// commandé est une facture plus élevée que prévu, pas une bonne nouvelle).
/// En deçà de l'opposé de la tolérance : `partielle` (livraison incomplète,
/// créance sur le fournisseur). Pile sur la tolérance : `totale`.
ConformiteReception conformiteLigne({
  required int recueCentiemes,
  required int commandeeCentiemes,
  required int toleranceCentiemes,
}) {
  final ecart = ecartPourcentageCentiemes(
    recueCentiemes: recueCentiemes,
    commandeeCentiemes: commandeeCentiemes,
  );
  if (ecart > toleranceCentiemes) return ConformiteReception.nonConforme;
  if (ecart < -toleranceCentiemes) return ConformiteReception.partielle;
  return ConformiteReception.totale;
}

/// Le verdict d'une réception — `ReceptionService::evaluerConformite`.
///
/// 1. un article reçu qui ne figure pas à la commande : `non_conforme` ;
/// 2. puis chaque ligne COMMANDÉE, dans l'ordre : le premier `non_conforme`
///    l'emporte, une `partielle` dégrade `totale`.
///
/// ⚠ Comme au serveur, le verdict porte sur les quantités de CETTE réception,
/// pas sur le cumul des réceptions précédentes. Une réception complémentaire
/// qui ne livre que le reste est donc `partielle`. C'est le comportement du
/// serveur, reproduit à l'identique et signalé à l'Architecte (D133) : le
/// corriger ici ferait deux verdicts pour la même livraison.
ConformiteReception evaluerConformite({
  required Map<String, int> commandees,
  required Map<String, int> recues,
  required int toleranceCentiemes,
}) {
  for (final article in recues.keys) {
    if (!commandees.containsKey(article)) {
      return ConformiteReception.nonConforme;
    }
  }

  var conformite = ConformiteReception.totale;
  for (final e in commandees.entries) {
    final verdict = conformiteLigne(
      recueCentiemes: recues[e.key] ?? 0,
      commandeeCentiemes: e.value,
      toleranceCentiemes: toleranceCentiemes,
    );
    if (verdict == ConformiteReception.nonConforme) return verdict;
    if (verdict == ConformiteReception.partielle) {
      conformite = ConformiteReception.partielle;
    }
  }
  return conformite;
}

/// Le statut que la réception POSE sur la commande —
/// `ReceptionService::receptionner` : `totale` -> `receptionnee`, tout le
/// reste -> `receptionnee_partiellement`.
StatutCommande statutApresReception(ConformiteReception conformite) =>
    conformite == ConformiteReception.totale
    ? StatutCommande.receptionnee
    : StatutCommande.receptionneePartiellement;

/// « Une commande est CLÔTURÉE-OU-REÇUE » — `CommandeAchat::estCloturee`.
///
/// Le nom du serveur est trompeur : `receptionnee` y compte. Une commande
/// intégralement reçue ne se réceptionne plus (elle se clôture), une commande
/// partiellement reçue se réceptionne encore.
bool estCloturee(StatutCommande? statut) =>
    statut == StatutCommande.receptionnee || statut == StatutCommande.cloturee;

/// Le bouton « Réceptionner » : `! estCloturee()`. Un statut INCONNU n'est pas
/// réceptionnable — on ne devine pas.
bool receptionnable(StatutCommande? statut) =>
    statut != null && !estCloturee(statut);

/// Le bouton « Clôturer » : `statut === 'receptionnee'` seulement.
bool cloturable(StatutCommande? statut) =>
    statut == StatutCommande.receptionnee;

/// La concordance d'une ligne du rapprochement —
/// `ControleTroisVoiesService::rapprocher`.
String concordanceLigne({
  required int recueCentiemes,
  required int commandeeCentiemes,
}) {
  final ecart = recueCentiemes - commandeeCentiemes;
  if (ecart == 0) return 'conforme';
  return ecart < 0 ? 'manquant' : 'excedent';
}

/// Le reste à recevoir d'une ligne, planché à zéro —
/// `CommandeAchatDetailResource` : un excédent ne devient pas un reste négatif.
int resteARecevoirCentiemes({
  required int commandeeCentiemes,
  required int recueCentiemes,
}) {
  final reste = commandeeCentiemes - recueCentiemes;
  return reste < 0 ? 0 : reste;
}

/// Lit une tolérance de réception saisie en Paramètres (`tolerance_reception_pct`).
///
/// Trois issues distinctes, et elles ne se confondent pas :
///  * `null` — le paramètre n'est pas renseigné : aucune conformité ne peut
///    être évaluée (une tolérance devinée ferait accepter ou refuser des
///    livraisons sur un critère arbitraire, PA-19) ;
///  * `illisible` — renseigné mais pas en centièmes : refusé plutôt
///    que tronqué (le serveur tronquerait à deux décimales ; ici on ne tronque
///    pas en silence une règle de gestion) ;
///  * un entier — centièmes de pour cent.
({int? centiemes, bool illisible}) lireTolerance(String? brut) {
  if (brut == null || brut.trim().isEmpty) {
    return (centiemes: null, illisible: false);
  }
  final c = enCentiemes(brut);
  if (c == null || c < 0) return (centiemes: null, illisible: true);
  return (centiemes: c, illisible: false);
}
