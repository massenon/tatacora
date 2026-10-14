/// Les providers de la cloche de la barre supérieure (14/10/2026, lot B).
///
/// ## Tout vient de la base LOCALE
///
/// Les quatre familles dérivées lisent les mêmes sources que les écrans qui les
/// détaillent : les mouvements de stock (`StocksDao`), les sessions de caisse
/// (`SessionsCaisseRepository`), les arrivées sans check-in (`SejourDao`,
/// depuis le 14/10/2026), les créances (`lireCreances`, la seule formule du
/// poste). Aucune seconde formule, aucun cache : la cloche est relue à
/// chaque navigation, comme la vue rend la sienne à chaque page.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/format/formats.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../caisse/presentation/providers_caisse.dart';
import '../../facturation/presentation/providers_paiements.dart';
import '../../hebergement/presentation/providers_hebergement.dart'
    show sejourDaoProvider;
import '../../parametres/data/parametres_dao.dart';
import '../../parametres/domain/options_systeme.dart';
import '../../stocks/presentation/providers_stocks.dart';
import '../data/alertes_vues_dao.dart';
import '../domain/alertes_ouverture.dart';

/// Le SEUL écrivain de `alertes_vues_local`.
final alertesVuesDaoProvider = Provider<AlertesVuesDao>(
  (ref) => AlertesVuesDao(ref.watch(baseLocaleProvider)),
);

/// L'horloge de la cloche (« ouverte avant aujourd'hui », « émise il y a 30
/// jours »). Injectable : un test qui lit l'heure réelle change de résultat
/// tous les jours.
final horlogeAlertesProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// La bascule « Alertes à l'ouverture de session » — LE lecteur de
/// `activation_alertes_ouverture` sur ce poste (déclaré au registre des
/// paramètres). Ouverte par défaut, comme au serveur (`OptionsSysteme`) ;
/// fermée, la cloche ne dérive plus aucune alerte, pour TOUS les profils.
Future<bool> lireAlertesOuvertureActives(ParametresDao dao) async {
  final valeurs = await dao.lireTout();
  return OptionsSysteme.actif(
    OptionsSysteme.cleAlertesOuverture,
    valeurs[OptionsSysteme.cleAlertesOuverture],
  );
}

/// Les alertes de la cloche pour le compte connecté — `AlertesOuverture::pour()`.
///
/// Une famille dont le module est REFUSÉ au compte n'est pas lue du tout : le
/// résultat est celui du serveur (qui dérive tout puis filtre), sans lire ce
/// que le compte n'a pas le droit de voir.
final alertesClocheProvider = FutureProvider.autoDispose<List<AlerteOuverture>>(
  (ref) async {
    final session = ref.watch(sessionProvider);
    if (session == null) return const [];

    final base = ref.watch(baseLocaleProvider);
    if (!await lireAlertesOuvertureActives(ParametresDao(base))) {
      return const [];
    }

    final droits = ref.watch(droitsProvider);
    final maintenant = ref.watch(horlogeAlertesProvider)();
    final toutes = <AlerteOuverture>[];

    if (droits.peutLire(ModuleTatacora.m6Stocks)) {
      final stocks = ref.read(stocksDaoProvider);
      toutes.addAll(
        alertesStock(
          articles: await stocks.articles(),
          mouvements: await stocks.mouvementsCalcul(),
        ),
      );
    }
    if (droits.peutLire(ModuleTatacora.m5Bar)) {
      toutes.addAll(
        alertesCaisse(
          sessions: await ref.read(depotSessionsCaisseProvider).sessions(),
          maintenant: maintenant,
        ),
      );
    }
    // Famille « réservations » (M1) — dérivée depuis le 14/10/2026 (lot C) :
    // les séjours sont tenus sur ce poste (`sejours_local`, v23).
    if (droits.peutLire(ModuleTatacora.m1Hebergement)) {
      final arrivees = await ref
          .read(sejourDaoProvider)
          .arriveesSansCheckIn(maintenant, plafond: plafondParFamille);
      toutes.addAll(
        alertesArrivees(
          arrivees: [for (final a in arrivees) (a.reservationId, a.client)],
          maintenant: maintenant,
        ),
      );
    }
    if (droits.peutLire(ModuleTatacora.m3Crm)) {
      toutes.addAll(
        alertesCreances(
          creances: await lireCreances(ref.read),
          maintenant: maintenant,
          formaterFcfa: formaterFcfa,
        ),
      );
    }

    final vues = await ref
        .read(alertesVuesDaoProvider)
        .clesVues(session.utilisateurId);
    return alertesVisibles(droits: droits, toutes: toutes, vues: vues);
  },
);

/// `ClocheNotifications::marquerToutLu` — les alertes NON vues de [alertes]
/// (la liste que le compte vient de voir dérivée), puis relecture.
Future<void> marquerToutesLesAlertesVues(
  WidgetRef ref,
  List<AlerteOuverture> alertes,
) async {
  final session = ref.read(sessionProvider);
  if (session == null) return;
  final cles = [
    for (final a in alertes)
      if (!a.vue) a.cle,
  ];
  if (cles.isEmpty) return;
  await ref
      .read(alertesVuesDaoProvider)
      .marquerVues(session.utilisateurId, cles);
  ref.invalidate(alertesClocheProvider);
}

/// `ClocheNotifications::marquerLu` — UNE alerte. La garde du serveur (la clé
/// doit désigner une alerte réellement dérivée pour ce compte) est tenue ici :
/// seule une alerte de la liste dérivée est acceptée.
Future<void> marquerAlerteVue(
  WidgetRef ref,
  AlerteOuverture alerte,
  List<AlerteOuverture> derivees,
) async {
  final session = ref.read(sessionProvider);
  if (session == null || alerte.vue) return;
  if (!derivees.any((a) => a.cle == alerte.cle)) return;
  await ref.read(alertesVuesDaoProvider).marquerVues(session.utilisateurId, [
    alerte.cle,
  ]);
  ref.invalidate(alertesClocheProvider);
}
