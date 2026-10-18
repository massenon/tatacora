import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../comptabilite/presentation/providers_comptabilite.dart';
import '../../../core/config/environnement.dart';
import '../../../core/di/providers.dart';
import '../../transverse/data/configuration_poste.dart';
import '../data/descente_catalogue.dart';
import '../data/descente_catalogue_dao.dart';
import '../data/operations_sync_dao.dart';
import '../data/service_appairage.dart';
import '../data/sync_manager.dart';
import '../data/transport_synchronisation.dart';
import '../domain/bilan_synchronisation.dart';
import '../domain/descente_catalogue.dart';
import '../domain/operation_sync.dart';
import '../domain/voyant_synchronisation.dart';

/// La file d'envoi du poste (lot F1, 15/10/2026).
final operationsSyncDaoProvider = Provider<OperationsSyncDao>(
  (ref) => OperationsSyncDao(ref.watch(baseLocaleProvider)),
);

/// Au DÉMARRAGE du poste : les opérations restées `en_cours` sous un bail
/// échu (le lot d'un processus tué pendant un envoi) redeviennent
/// `en_attente`. Lu par `main.dart` après la première image ; ne bloque rien
/// et n'atteint jamais l'interface — une base fermée pendant l'arrêt, par
/// exemple, sera traitée au démarrage suivant.
final liberationBauxSyncProvider = FutureProvider<int>((ref) async {
  try {
    return await ref.watch(operationsSyncDaoProvider).libererBauxExpires();
  } on Object {
    return 0;
  }
});

/* ==================================================================== */
/* Lot F2a — transport, appairage, moteur d'envoi, déclencheurs         */
/* ==================================================================== */

/// Le transport HTTP — un test le remplace (`MockClient` ou faux).
final transportSynchronisationProvider = Provider<TransportSynchronisation>(
  (ref) => TransportHttp(),
);

/// L'adresse de l'API du BUILD (`--dart-define=ENV=…`) ; `null` en
/// démonstration. Jamais une saisie.
final urlServeurSynchronisationProvider = Provider<String?>(
  (ref) => Environnement.actuel.baseUrl,
);

/// Le chemin de `poste.json` — un test pose le sien.
final cheminConfigurationPosteProvider = Provider<Future<String> Function()>(
  (ref) => cheminConfigurationPoste,
);

/// La démonstration ne se synchronise JAMAIS : flavor `demo`, ou base dont la
/// file est inactive (`AppDatabase.fileSynchronisationActive`).
final synchronisationInterditeProvider = Provider<bool>(
  (ref) =>
      Environnement.actuel.estHorsLigneIntegral ||
      !ref.watch(baseLocaleProvider).fileSynchronisationActive,
);

/// L'appairage du poste (Paramètres → Synchronisation).
final serviceAppairageProvider = Provider<ServiceAppairage>((ref) {
  final chemin = ref.watch(cheminConfigurationPosteProvider);
  return ServiceAppairage(
    transport: ref.watch(transportSynchronisationProvider),
    urlServeur: ref.watch(synchronisationInterditeProvider)
        ? null
        : ref.watch(urlServeurSynchronisationProvider),
    lecteur: LecteurConfigurationPoste(chemin: chemin),
    ecrivain: EcrivainConfigurationPoste(chemin: chemin),
  );
});

/// L'appairage actuel, relu du fichier à chaque lecture.
final appairageActuelProvider = FutureProvider.autoDispose<AppairagePoste?>(
  (ref) => ref.watch(serviceAppairageProvider).appairageActuel(),
);

/// Le DERNIER bilan de synchronisation de cette session du logiciel — `null`
/// tant qu'aucune n'a eu lieu. L'écran de synchronisation (F2b) le lira.
final dernierBilanSynchronisationProvider =
    NotifierProvider<DernierBilanSynchronisation, BilanSynchronisation?>(
      DernierBilanSynchronisation.new,
    );

final class DernierBilanSynchronisation
    extends Notifier<BilanSynchronisation?> {
  @override
  BilanSynchronisation? build() => null;

  void poser(BilanSynchronisation bilan) => state = bilan;
}

/// L'état de la descente du catalogue (lot F2b).
final descenteCatalogueDaoProvider = Provider<DescenteCatalogueDao>(
  (ref) => DescenteCatalogueDao(ref.watch(baseLocaleProvider)),
);

/// La descente du catalogue (lot F2b) — appelée par [SyncManager] après
/// l'envoi. L'auteur d'une création descendue : le compte connecté, à
/// défaut le plus ancien administrateur actif du poste.
final descenteCatalogueProvider = Provider<DescenteCatalogue>((ref) {
  final db = ref.watch(baseLocaleProvider);
  final dao = ref.watch(descenteCatalogueDaoProvider);
  return DescenteCatalogue(
    db: db,
    transport: ref.watch(transportSynchronisationProvider),
    auteur: () async {
      String? connecte;
      try {
        connecte = ref.read(sessionProvider)?.utilisateurId;
      } on Object {
        connecte = null;
      }
      return connecte ?? await dao.auteurParDefaut();
    },
    // Lot F6 : la contre-passation d'un document de CE poste annulé au
    // serveur passe par le moteur de production.
    moteur: () => ref.read(moteurComptableProvider.future),
  );
});

/// Le moteur d'envoi — UNE instance : c'est elle qui tient le « un seul
/// envoi à la fois » du processus. Depuis le lot F2b, il descend aussi le
/// catalogue après l'envoi.
final syncManagerProvider = Provider<SyncManager>((ref) {
  final chemin = ref.watch(cheminConfigurationPosteProvider);
  return SyncManager(
    dao: ref.watch(operationsSyncDaoProvider),
    transport: ref.watch(transportSynchronisationProvider),
    urlServeur: ref.watch(urlServeurSynchronisationProvider),
    demonstration: ref.watch(synchronisationInterditeProvider),
    lecteur: LecteurConfigurationPoste(chemin: chemin),
    ecrivain: EcrivainConfigurationPoste(chemin: chemin),
    surBilan: (bilan) =>
        ref.read(dernierBilanSynchronisationProvider.notifier).poser(bilan),
    descente: ref.watch(descenteCatalogueProvider),
  );
});

/* ==================================================================== */
/* Lot F2b — l'écran de synchronisation                                 */
/* ==================================================================== */

/// Une synchronisation lancée DEPUIS L'ÉCRAN est-elle en cours ? (Le bouton
/// se grise et une barre de progression s'affiche ; les autres écrans ne
/// sont jamais bloqués.)
final synchronisationEnCoursProvider =
    NotifierProvider<SynchronisationEnCours, bool>(SynchronisationEnCours.new);

final class SynchronisationEnCours extends Notifier<bool> {
  @override
  bool build() => false;

  void poser(bool valeur) => state = valeur;
}

/// « Synchroniser maintenant » de l'écran : lance la synchronisation et
/// tient [synchronisationEnCoursProvider] — au niveau du CONTENEUR, pas du
/// widget : quitter l'écran pendant l'envoi ne l'interrompt pas, et rien ne
/// touche un widget démonté. Ne lève jamais.
final synchroniserDepuisEcranProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    if (ref.read(synchronisationEnCoursProvider)) return;
    final enCours = ref.read(synchronisationEnCoursProvider.notifier);
    enCours.poser(true);
    try {
      await ref.read(syncManagerProvider).synchroniserMaintenant();
    } on Object {
      // Le moteur ne lève pas ; un moteur impossible à construire (base
      // fermée) ne remonte pas jusqu'à l'écran.
    } finally {
      enCours.poser(false);
      ref.invalidate(appairageActuelProvider);
    }
  },
);

/// Ce que l'écran de synchronisation lit de la base — relu après chaque
/// geste et chaque synchronisation.
final class EtatFileSynchronisation {
  const EtatFileSynchronisation({
    required this.comptes,
    required this.remplacees,
    required this.aTraiter,
    required this.anomalies,
    required this.derniereDescente,
  });

  final Map<StatutOperationSync, int> comptes;

  /// Opérations rejetées déjà renvoyées (historique de leur remplaçante).
  final int remplacees;
  final List<OperationATraiter> aTraiter;
  final List<OperationSync> anomalies;
  final BilanDescente? derniereDescente;
}

final etatFileSynchronisationProvider =
    FutureProvider.autoDispose<EtatFileSynchronisation>((ref) async {
      // Relu à chaque nouveau bilan.
      ref.watch(dernierBilanSynchronisationProvider);
      final dao = ref.watch(operationsSyncDaoProvider);
      return EtatFileSynchronisation(
        comptes: await dao.compteParStatut(),
        remplacees: (await dao.remplacees()).length,
        aTraiter: await dao.aTraiter(),
        anomalies: await dao.avecAnomalies(),
        derniereDescente: await ref
            .watch(descenteCatalogueDaoProvider)
            .derniereDescente(),
      );
    });

/// La période du réveil automatique.
const Duration periodeSynchronisation = Duration(minutes: 5);

/// La période du PASSAGE COURT (décision PO du 18/10/2026) : la lecture de
/// la demande « Synchroniser » faite au serveur — une requête légère, rien
/// n'est téléchargé tant qu'aucune demande nouvelle n'est lue.
const Duration periodeDemandeServeur = Duration(seconds: 30);

/// Lance une synchronisation SANS l'attendre et sans rien laisser remonter :
/// ni exception synchrone, ni erreur asynchrone. C'est la forme de TOUT
/// déclencheur automatique — un geste (la clôture de caisse d'abord) ne
/// dépend jamais du réseau.
void lancerSynchronisationSansAttendre(SyncManager Function() manager) {
  try {
    unawaited(
      manager().synchroniserMaintenant().then<void>((_) {}, onError: (_) {}),
    );
  } on Object {
    // Un moteur impossible à construire (base fermée) : rien ne remonte.
  }
}

/// Le déclencheur « après un geste » : appelé par `cloturerLaCaisse` une fois
/// la clôture ÉCRITE. Rend immédiatement.
final declencheurSynchronisationProvider = Provider<void Function()>(
  (ref) =>
      () => lancerSynchronisationSansAttendre(
        () => ref.read(syncManagerProvider),
      ),
);

/// Le réveil AUTOMATIQUE : une synchronisation au démarrage, puis toutes les
/// [periodeSynchronisation] tant que l'application tourne — sans requête
/// quand aucune opération n'est échue (le moteur s'arrête sur une file vide
/// ou en repli). Démarré par `main.dart` après la première image, PAS par
/// `main_demo.dart` (et le moteur refuserait la démonstration de toute
/// façon). Aucune sonde de connectivité : la tentative est l'autorité.
final synchronisationAutomatiqueProvider = Provider<void>((ref) {
  final manager = ref.watch(syncManagerProvider);
  lancerSynchronisationSansAttendre(() => manager);
  final minuteur = Timer.periodic(
    periodeSynchronisation,
    (_) => lancerSynchronisationSansAttendre(() => manager),
  );
  // Le bouton « Synchroniser » du serveur : sa demande est suivie dans les
  // 30 s, sans attendre le réveil de 5 minutes.
  final passageCourt = Timer.periodic(
    periodeDemandeServeur,
    (_) => unawaited(manager.suivreDemandeDuServeur()),
  );
  ref.onDispose(() {
    minuteur.cancel();
    passageCourt.cancel();
  });
});

/* ==================================================================== */
/* Lot F3 — le voyant de la barre supérieure                             */
/* ==================================================================== */

/// Les comptes de la file, RELUS à chaque écriture de la file (signal de
/// tables de Drift) : le badge suit une vente enfilée sans attendre le
/// passage suivant du moteur.
final comptesFileSynchronisationProvider =
    FutureProvider.autoDispose<Map<StatutOperationSync, int>>((ref) async {
      final dao = ref.watch(operationsSyncDaoProvider);
      final abonnement = dao.surveillerFile().listen(
        (_) => ref.invalidateSelf(),
      );
      ref.onDispose(abonnement.cancel);
      return dao.compteParStatut();
    });

/// Le voyant du bouton de la barre supérieure, ou `null` tant que la file
/// ou l'appairage ne sont pas lus (aucune couleur n'est affirmée avant).
final voyantSynchronisationProvider =
    Provider.autoDispose<VoyantSynchronisation?>((ref) {
      final interdite =
          ref.watch(synchronisationInterditeProvider) ||
          ref.watch(urlServeurSynchronisationProvider) == null;
      final comptes = ref.watch(comptesFileSynchronisationProvider);
      final appairage = ref.watch(appairageActuelProvider);
      if (!interdite && (!comptes.hasValue || !appairage.hasValue)) {
        return null;
      }
      return voyantDe(
        interdite: interdite,
        appaire: appairage.value != null,
        refusJeton: appairage.value?.refus != null,
        comptes: comptes.value ?? const {},
        bilan: ref.watch(dernierBilanSynchronisationProvider),
        enCours: ref.watch(synchronisationEnCoursProvider),
      );
    });
