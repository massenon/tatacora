/// Les LIGNES DE VENTE d'un rayon (bar M5, restaurant M4), calculées sur les
/// paniers du poste — l'onglet « Ventes » des cartes, SANS serveur.
///
/// Réplique de `LignesVenteDuRayonService` (serveur, PA-197), sur les ventes
/// que ce poste détient : les siennes ET celles des autres postes que la
/// descente lui a rendues (elles s'écrivent dans les mêmes tables).
///
///  * le filtre de module est celui de la LIGNE, jamais de la vente : un même
///    ticket porte une bière (M5) et un poulet (M4) ;
///  * une vente annulée reste au registre, son montant n'est pas de l'argent ;
///  * bornes de date INCLUSES, les deux, sur le JOUR de la vente ;
///  * le total est celui du jeu filtré ENTIER, jamais de la page ;
///  * du plus récent au plus ancien, départagé par l'identifiant de la ligne.
///
/// Écarts nommés : le panier n'a ni numéro `V-` ni auteur de vente. Le numéro
/// est celui de la facture quand il y en a une, « — » sinon ; l'auteur est
/// « — » (jamais un « système » inventé).
library;

import '../../bar/domain/entities/ventes_bar.dart';
import '../../pos/domain/entities/panier.dart';
import '../../pos/domain/entities/reference_catalogue.dart';

/// Lignes par page — celle de l'onglet de la vue (`PAR_PAGE`).
const int lignesParPageDuRayon = 10;

String _decimal2(int francs) => '$francs.00';

/// Toutes les lignes du [rayon] qui passent [filtre] (sans pagination).
List<LigneVenteBar> lignesDuRayon(
  List<Panier> paniers,
  ModuleVendable rayon,
  FiltreVentesBar filtre, {
  Map<String, String> numeroFactureParPanier = const {},
}) {
  final terme = filtre.recherche.trim().toLowerCase();
  final du = filtre.du == null ? null : _jour(filtre.du!);
  final au = filtre.au == null ? null : _jour(filtre.au!);
  final lignes = <LigneVenteBar>[];
  final parLigne = <String, DateTime>{};

  for (final panier in paniers) {
    final annulee = switch (panier.statut) {
      StatutPanier.ouvert => null,
      StatutPanier.cloture => false,
      StatutPanier.annule => true,
    };
    if (annulee == null) continue;
    if (filtre.statut != null &&
        (filtre.statut == StatutVenteBar.annulee) != annulee) {
      continue;
    }
    final date = panier.clotureLe ?? panier.ouvertLe;
    final jour = _jour(date);
    if (du != null && jour.isBefore(du)) continue;
    if (au != null && jour.isAfter(au)) continue;
    final numero = numeroFactureParPanier[panier.id];

    for (final l in panier.lignes) {
      if (l.reference.module != rayon) continue;
      if (terme.isNotEmpty &&
          !l.libelle.toLowerCase().contains(terme) &&
          !(numero ?? '').toLowerCase().contains(terme)) {
        continue;
      }
      parLigne[l.id] = date;
      lignes.add(
        LigneVenteBar(
          id: l.id,
          code: l.reference.code,
          nom: l.libelle,
          numero: numero,
          date: date,
          prixUnitaire: _decimal2(l.prixUnitaire),
          quantite: l.quantite,
          montant: _decimal2(l.montant),
          annulee: annulee,
          motifAnnulation: annulee ? panier.motifAnnulation : null,
          utilisateur: null,
        ),
      );
    }
  }

  lignes.sort((a, b) {
    final parDate = parLigne[b.id]!.compareTo(parLigne[a.id]!);
    return parDate != 0 ? parDate : b.id.compareTo(a.id);
  });
  return lignes;
}

DateTime _jour(DateTime d) => DateTime(d.year, d.month, d.day);

/// Les compteurs du jeu filtré ENTIER : lignes, annulées, total des seules
/// lignes validées.
TotauxVentesBar totauxDuRayon(List<LigneVenteBar> lignes) => TotauxVentesBar(
  lignes: lignes.length,
  annulees: lignes.where((l) => l.annulee).length,
  totalValide: sommeDecimale([
    for (final l in lignes)
      if (!l.annulee) l.montant,
  ]),
);

/// Une page du jeu filtré (la dernière page est bornée, la première est 1).
PageVentesBar pageDuRayon(List<LigneVenteBar> lignes, FiltreVentesBar filtre) {
  final derniere = lignes.isEmpty
      ? 1
      : (lignes.length + lignesParPageDuRayon - 1) ~/ lignesParPageDuRayon;
  final page = filtre.page < 1
      ? 1
      : (filtre.page > derniere ? derniere : filtre.page);
  final debut = (page - 1) * lignesParPageDuRayon;
  final fin = debut + lignesParPageDuRayon > lignes.length
      ? lignes.length
      : debut + lignesParPageDuRayon;
  return PageVentesBar(
    lignes: lignes.sublist(debut, fin),
    totaux: totauxDuRayon(lignes),
    page: page,
    derniere: derniere,
    parPage: lignesParPageDuRayon,
  );
}
