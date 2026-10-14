// Vue Blade maîtresse (PA-183) : pwa/achats/approvisionnement.blade.php
/// L'onglet « Dettes fournisseurs » et les deux cartes qui le résument —
/// FONCTIONS PURES, montants en centimes.
///
/// Réplique de `Approvisionnement::dettes()` et de ce que `render()` somme pour
/// « Fournisseurs à payer » et « Total dû ». Elles partent de la liste des
/// commandes DÉJÀ filtrée (statut, recherche) : le serveur lit la même liste
/// pour les trois (D262).
///
/// ## Trois définitions qui ne se recouvrent pas, répliquées telles quelles
///
/// 1. **La liste** (`dettes()`) écarte les commandes `receptionnee` et
///    `cloturee` (`estCloturee()`), groupe par fournisseur dans l'ordre de
///    première apparition, et garde TOUTES les autres — une commande soldée
///    comprise (sa ligne affiche alors « — » en Reste dû) ;
/// 2. **« Fournisseurs à payer »** compte les groupes de cette liste dont une
///    commande au moins a un reste dû positif ;
/// 3. **« Total dû »** somme le reste dû de TOUTES les commandes de la liste
///    filtrée, closes comprises : une commande réceptionnée et pas encore payée
///    pèse dans le total sans figurer dans l'onglet.
///
/// La troisième ne ressemble pas aux deux autres, et c'est le serveur qui la
/// pose. Elle est répliquée et consignée (D262), jamais corrigée ici.
library;

import '../../caisse/domain/montant_caisse.dart' show formaterCentimesEnFcfa;
import 'decimal_texte.dart';
import 'entities/commande_achat.dart';
import 'regles_reglement.dart';

/// Un fournisseur et ses commandes encore ouvertes (`dettes()`).
final class GroupeDettes {
  const GroupeDettes({
    required this.fournisseurId,
    required this.fournisseur,
    required this.commandes,
  });

  final String fournisseurId;

  /// Vide si la relation manque (`''` du serveur), jamais un nom inventé.
  final String fournisseur;
  final List<CommandeAchat> commandes;

  /// Le total du groupe : la somme du reste dû de ses commandes, en centimes.
  int get totalCentimes =>
      commandes.fold(0, (s, c) => s + (enCentiemes(c.resteDu) ?? 0));
}

/// `Approvisionnement::dettes()`.
List<GroupeDettes> composerDettes(List<CommandeAchat> commandes) {
  final groupes = <String, GroupeDettes>{};
  for (final c in commandes) {
    if (!figureAuxDettes(c.statut)) continue;
    final existant = groupes[c.fournisseurId];
    groupes[c.fournisseurId] = GroupeDettes(
      fournisseurId: c.fournisseurId,
      fournisseur: c.fournisseurRaisonSociale,
      commandes: [...?existant?.commandes, c],
    );
  }
  return groupes.values.toList(growable: false);
}

/// Les deux cartes : « Fournisseurs à payer » (un entier) et « Total dû » (en
/// centimes).
final class IndicateursDettes {
  const IndicateursDettes({
    required this.fournisseursAPayer,
    required this.totalDuCentimes,
  });

  final int fournisseursAPayer;
  final int totalDuCentimes;
}

IndicateursDettes composerIndicateursDettes(List<CommandeAchat> commandes) {
  final aPayer = composerDettes(
    commandes,
  ).where((g) => g.commandes.any((c) => (enCentiemes(c.resteDu) ?? 0) > 0));
  return IndicateursDettes(
    fournisseursAPayer: aPayer.length,
    totalDuCentimes: commandes.fold(
      0,
      (s, c) => s + (enCentiemes(c.resteDu) ?? 0),
    ),
  );
}

/// `(int) ($c->date_commande?->diffInDays(now()) ?? 0)` : le nombre de jours
/// entre le MINUIT de la commande et [maintenant], tronqué vers zéro.
///
/// Un bon daté du futur donne un nombre NÉGATIF que la vue affiche tel quel
/// (« -3 j ») : le serveur ne le planche pas, et le poste non plus.
int joursAnciennete(String dateCommande, DateTime maintenant) {
  final d = DateTime.tryParse(dateCommande);
  if (d == null) return 0;
  final minuit = DateTime(d.year, d.month, d.day);
  final secondes = maintenant.difference(minuit).inSeconds;
  return (secondes / 86400).truncate();
}

/// `MontantFcfa::formatOuTiret` : le montant en FCFA, ou « — » quand il vaut
/// zéro APRÈS arrondi à l'unité (la demi-unité s'éloigne de zéro). Un reste dû de
/// 0,40 F s'affiche donc « — », comme au serveur.
String montantFcfaOuTiret(int centimes) =>
    centimes.abs() < 50 ? '—' : formaterCentimesEnFcfa(centimes);
