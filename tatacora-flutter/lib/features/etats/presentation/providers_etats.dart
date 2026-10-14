import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../achats/presentation/providers_achats.dart';
import '../../depenses/presentation/providers_depenses.dart';
import '../../facturation/presentation/providers_paiements.dart';
import '../../hebergement/presentation/providers_hebergement.dart';
import '../../pos/presentation/providers_pos.dart';
import '../../rh/presentation/providers_rh.dart';
import '../../stocks/presentation/providers_stocks.dart';
import '../../tableau_de_bord/domain/entities/tableau_de_bord.dart';
import '../../tableau_de_bord/presentation/ecran_tableau_de_bord.dart'
    show tableauDeBordLocalProvider;
import '../../tourisme/presentation/providers_tourisme.dart';
import '../../vehicules/presentation/providers_vehicules.dart';
import '../../ventes/domain/journal_ventes.dart';
import '../data/etats_api.dart';
import '../domain/apercu_etat.dart';
import '../domain/entities/etat_catalogue.dart';

/// L'horloge de M14 : « maintenant » d'une photographie (« Arrêté au … ») et
/// mois courant de la paie. Injectable — un test qui lit l'horloge réelle
/// devient faux au changement de mois (D27).
final horlogeEtatsProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Les dépôts dont les états relisent les chiffres.
///
/// Chaque lecteur est celui de l'écran du module source, et **FRAIS** : aucun
/// n'emprunte un fournisseur qui garderait sa réponse (`journalVentesProvider`,
/// `depensesProvider`…). Un état édité après une vente doit contenir cette
/// vente ; la lecture conservée d'un autre écran, non (PA-120).
final sourcesEtatsProvider = Provider<SourcesEtats>(
  (ref) => SourcesEtats(
    stock: () => ref.read(stocksApiProvider).etat(),
    // La fenêtre de `EtatTableauDeBord` du serveur : « à date », défaut
    // `Periode::DEFAUT` (30 jours) — pas celle du sélecteur de l'écran M11.
    tableauDeBord: () => ref
        .read(tableauDeBordLocalProvider)
        .consulterADate(PeriodeADate.parDefaut),
    parcVehicules: () => ref.read(vehiculeDaoProvider).parc(),
    contrats: () => ref.read(vehiculeDaoProvider).contrats(),
    reservations: () => ref.read(depotReservationProvider).reservations(),
    unites: () => ref.read(depotReservationProvider).unites(),
    journalVentes: () async =>
        composerJournal(paniers: await ref.read(depotPanierProvider).paniers()),
    depenses: () => ref.read(depotDepensesProvider).depenses(),
    commandes: () async =>
        (await ref
                .read(achatsDaoProvider)
                .commandes(parPage: _toutesLesCommandes))
            .elements,
    tours: () => ref
        .read(tourismeDaoProvider)
        .reservationsSurFenetre(_debutDesTemps, _finDesTemps),
    employes: () => ref.read(employeDaoProvider).employes(),
    totauxPaie: (periode) =>
        ref.read(livreDePaieServiceProvider).totaux(periode),
    clients: () => ref.read(clientDaoProvider).clients(),
    creances: () => lireCreances(ref.read),
    maintenant: ref.watch(horlogeEtatsProvider),
  ),
);

/// Aucune pagination : un état est la liste ENTIÈRE. 200 par page (le défaut du
/// dépôt) tronquerait silencieusement un registre plus long.
const int _toutesLesCommandes = 1 << 30;

/// « Toutes dates » : `calculer([])` ne pose aucune borne. Le lecteur des
/// réservations de circuits n'a qu'une fenêtre ; on lui en donne une qui
/// couvre tout ce qu'un poste peut contenir.
final DateTime _debutDesTemps = DateTime(1970);
final DateTime _finDesTemps = DateTime(9000);

final etatsApiProvider = Provider<EtatsApi>(
  (ref) => EtatsApi(
    droits: ref.watch(droitsProvider),
    sources: ref.watch(sourcesEtatsProvider),
  ),
);

/// Le catalogue — **recalculé, jamais mis en cache**.
///
/// Il dépend des droits de la session : un changement de rôle recompose la
/// liste, et une liste gardée d'hier proposerait des états que l'utilisateur
/// n'a plus le droit d'éditer.
final catalogueEtatsProvider = FutureProvider<List<EtatCatalogue>>(
  (ref) async => ref.watch(etatsApiProvider).catalogue(),
);

/// Le terme de recherche du catalogue — `#rech` du maître.
final rechercheEtatsProvider = NotifierProvider<_RechercheNotifier, String>(
  _RechercheNotifier.new,
);

class _RechercheNotifier extends Notifier<String> {
  @override
  String build() => '';

  void definir(String valeur) => state = valeur;
}

/// Le filtre de module — `#filtres-module`. `null` = « Tous ».
final moduleFiltreEtatsProvider = NotifierProvider<_ModuleNotifier, String?>(
  _ModuleNotifier.new,
);

class _ModuleNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void definir(String? code) => state = code;
}

/// Le code de l'état sélectionné, ou `null` — l'écran d'accueil du maître.
final etatSelectionneProvider = NotifierProvider<_SelectionNotifier, String?>(
  _SelectionNotifier.new,
);

class _SelectionNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void definir(String? code) => state = code;
}

/// Le catalogue **filtré**, tel que la colonne de gauche le rend.
///
/// Le filtrage est fait ici, pas dans le widget : « aucune règle métier dans
/// un widget » (Article 10).
final catalogueFiltreProvider = Provider<AsyncValue<List<EtatCatalogue>>>((
  ref,
) {
  final brut = ref.watch(catalogueEtatsProvider);
  final terme = ref.watch(rechercheEtatsProvider);
  final module = ref.watch(moduleFiltreEtatsProvider);

  return brut.whenData(
    (etats) => filtrerCatalogue(etats, terme: terme, module: module),
  );
});

/// L'aperçu d'un état — **recalculé à chaque sélection**, jamais gardé.
///
/// `autoDispose` : quitter l'état oublie la réponse. La garder montrerait,
/// au retour, des chiffres qui datent de la visite précédente sans que rien
/// ne le dise (PA-59/60/61).
final apercuEtatProvider = FutureProvider.autoDispose
    .family<ResultatApercu, String>(
      (ref, code) => ref.watch(etatsApiProvider).apercu(code),
    );
