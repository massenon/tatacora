import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../achats/presentation/providers_achats.dart';
import '../../bar/presentation/providers_bar.dart';
import '../../bar/presentation/providers_catalogue_boissons.dart';
import '../../hebergement/presentation/providers_hebergement.dart';
import '../../restaurant/presentation/providers_restaurant.dart';
import '../../stocks/presentation/providers_stocks.dart';
import '../../tourisme/presentation/providers_tourisme.dart';
import '../../vehicules/presentation/providers_vehicules.dart';
import '../../synchronisation/presentation/providers_synchronisation.dart'
    show cheminConfigurationPosteProvider;
import '../data/importeurs_locaux.dart';
import '../data/sauvegarde_locale.dart';
import '../data/sauvegardes_poste.dart';

/// Les importeurs du poste, dans l'ordre du registre du serveur
/// (`ReferentielsImport::definitions()`). Chaque écrivain est celui que
/// l'écran du module emploie déjà — mêmes droits, même auteur.
final importeursLocauxProvider = Provider<List<ImporteurLocal>>((ref) {
  final base = ref.watch(baseLocaleProvider);
  String? auteur() => ref.read(sessionProvider)?.utilisateurId;
  return [
    ImporteurClients(base, dao: ref.watch(clientDaoProvider)),
    ImporteurUnites(base, dao: ref.watch(parcDaoProvider)),
    ImporteurCarteBar(base, api: ref.watch(boissonsApiProvider)),
    ImporteurCarteRestaurant(
      base,
      dao: ref.watch(restaurantDaoProvider),
      auteurId: auteur,
    ),
    ImporteurArticles(base, api: ref.watch(stocksApiProvider)),
    ImporteurFournisseurs(
      base,
      dao: ref.watch(achatsDaoProvider),
      auteurId: auteur,
    ),
    ImporteurVehicules(base, dao: ref.watch(vehiculeDaoProvider)),
    ImporteurCircuits(base, dao: ref.watch(tourismeDaoProvider)),
  ];
});

final moteurImportProvider = Provider<MoteurImportLocal>(
  (ref) => MoteurImportLocal(ref.watch(baseLocaleProvider)),
);

final sauvegardeLocaleProvider = Provider<SauvegardeLocale>(
  (ref) => SauvegardeLocale(ref.watch(baseLocaleProvider)),
);

/// Les sauvegardes CONSERVÉES sur ce poste (dossier `sauvegardes/` à côté de
/// `poste.json`) — l'onglet « Sauvegardes de la base » et le filet d'avant
/// « Réinitialiser comme neuf ».
final sauvegardesPosteProvider = Provider<SauvegardesPoste>(
  (ref) => SauvegardesPoste(
    ref.watch(baseLocaleProvider),
    cheminConfiguration: ref.watch(cheminConfigurationPosteProvider),
  ),
);

/// La liste des sauvegardes rangées — relue après chaque geste (on invalide).
final fichiersSauvegardeProvider =
    FutureProvider.autoDispose<List<FichierSauvegarde>>(
      (ref) => ref.watch(sauvegardesPosteProvider).fichiers(),
    );

/// Une entrée de « Historique des imports ».
final class EntreeHistoriqueImport {
  const EntreeHistoriqueImport({
    required this.module,
    required this.lignes,
    required this.le,
    required this.par,
  });

  final String module;
  final int lignes;
  final DateTime le;
  final String? par;
}

/// L'historique des imports de CETTE SESSION de l'application — le poste ne
/// tient pas de table `journal_imports` (aucune migration pour un journal) ;
/// l'écran le dit, plutôt que de laisser croire à un historique complet.
final class HistoriqueImports extends Notifier<List<EntreeHistoriqueImport>> {
  @override
  List<EntreeHistoriqueImport> build() => const [];

  void ajouter(EntreeHistoriqueImport entree) => state = [entree, ...state];
}

final historiqueImportsProvider =
    NotifierProvider<HistoriqueImports, List<EntreeHistoriqueImport>>(
      HistoriqueImports.new,
    );

/// Les lectures du module à relire après un import — celles qui ne se
/// relisent pas d'elles-mêmes (non `autoDispose`).
void relireApresImport(WidgetRef ref, String cle) {
  switch (cle) {
    case 'm3-clients':
      ref
        ..invalidate(clientsProvider)
        ..invalidate(clientsTourismeProvider);
    case 'm1-hebergement':
      ref.invalidate(unitesProvider);
    case 'm5-bar':
      ref
        ..invalidate(carteLocaleProvider)
        ..invalidate(carteBarProvider);
    case 'm8-vehicules':
      ref.invalidate(parcProvider);
    case 'm9-tourisme':
      ref.invalidate(circuitsProvider);
    case 'm6-stocks':
      ref.invalidate(etatStockProvider);
  }
}
