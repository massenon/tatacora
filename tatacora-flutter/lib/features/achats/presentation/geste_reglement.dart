// Vue Blade maîtresse (PA-183) : pwa/achats/approvisionnement.blade.php
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/achats_api.dart';
import '../domain/messages_reglement.dart';
import 'providers_achats.dart';
import 'widgets/modale_reglement.dart';

/// Le geste « Régler » d'une ligne de commande — `ouvrirFormulaireReglement`
/// puis `enregistrerReglement` du composant.
///
/// Un seul auteur pour les DEUX onglets qui offrent le bouton (Commandes et
/// Dettes) : deux copies du geste finiraient par diverger sur le message ou sur
/// ce qu'elles rafraîchissent.
///
/// * L'ouverture refusée (commande introuvable, déjà soldée, droit manquant)
///   pose l'erreur `selection` en bandeau de la page ; la modale ne s'ouvre pas.
/// * L'enregistrement réussi pose le bandeau vert, puis relit les commandes, les
///   cartes et les dettes : « Réglé » et « Reste dû » se lisent des règlements,
///   et une liste qu'on ne relit pas dirait encore l'ancien reste dû.
Future<void> reglerUneCommande(
  BuildContext context,
  WidgetRef ref,
  String commandeId,
) async {
  final bandeau = ref.read(bandeauApproProvider.notifier)..effacer();

  final ouverture = await ref
      .read(achatsApiProvider)
      .ouvrirReglement(commandeId);
  if (!context.mounted) return;

  switch (ouverture) {
    case AchatsRefuse(:final motif):
      bandeau.erreurSelection(motif);
    case AchatsInjoignable():
      // Jamais produite (la base est locale) ; le type la garde.
      bandeau.erreurSelection(
        'La base du poste n’a pas répondu : aucun règlement n’est ouvert.',
      );
    case AchatsRecu(:final donnees):
      final saisi = await ouvrirModaleReglement(
        context,
        commandeId: commandeId,
        ouverture: donnees,
      );
      if (saisi == null) return;

      bandeau.succes(
        MessagesReglement.enregistre(saisi.montantSaisi, saisi.fournisseurNom),
      );
      ref
        ..invalidate(commandesProvider(null))
        ..invalidate(kpisApprovisionnementProvider)
        ..invalidate(commandesAchatsProvider(null));
  }
}
