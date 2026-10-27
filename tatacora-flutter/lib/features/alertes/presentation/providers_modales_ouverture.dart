import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/format/formats.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../crm/domain/messages_relance.dart' show RefusRelance;
import '../../facturation/presentation/providers_paiements.dart';
import '../../hebergement/domain/messages_sejour.dart' show RefusSejour;
import '../../hebergement/presentation/providers_hebergement.dart'
    show sejourDaoProvider;
import '../../crm/presentation/providers_crm.dart'
    show relancesClientsDaoProvider;
import '../../parametres/data/parametres_dao.dart';
import '../../stocks/presentation/providers_stocks.dart';
import '../domain/modales_ouverture.dart';
import 'providers_alertes.dart';

/// Les lignes des trois blocs, lues dans la base locale à l'instant [maintenant].
///
/// Un bloc dont le module n'est pas LISIBLE par le compte n'est pas lu du tout
/// (`MenuLateral::moduleAccessible` du serveur : masqué sur `-` seulement).
Future<({
  List<LigneStockOuverture>? stock,
  List<LigneDepartOuverture>? departs,
  List<LigneCreanceOuverture>? creances,
})>
lireLignesOuverture(
  Ref ref, {
  required GardeAcces droits,
  required DateTime maintenant,
}) async {
  List<LigneStockOuverture>? stock;
  if (droits.peutLire(ModuleTatacora.m6Stocks)) {
    final stocks = ref.read(stocksDaoProvider);
    stock = stockCritiqueModale(
      articles: await stocks.articles(),
      mouvements: await stocks.mouvementsCalcul(),
    );
  }

  List<LigneDepartOuverture>? departs;
  if (droits.peutLire(ModuleTatacora.m1Hebergement)) {
    departs = departsAEcheance(
      departs: await ref.read(sejourDaoProvider).departsAEcheance(maintenant),
      maintenant: maintenant,
    );
  }

  List<LigneCreanceOuverture>? creances;
  if (droits.peutLire(ModuleTatacora.m3Crm)) {
    final relances = await ref.read(relancesClientsDaoProvider).toutes();
    final derniere = <String, DateTime>{};
    for (final r in relances) {
      final avant = derniere[r.clientId];
      if (avant == null || r.dateRelance.isAfter(avant)) {
        derniere[r.clientId] = r.dateRelance;
      }
    }
    creances = creancesModale(
      creances: await lireCreances(ref.read),
      derniereRelance: derniere,
      maintenant: maintenant,
      formaterFcfa: formaterFcfa,
    );
  }
  return (stock: stock, departs: departs, creances: creances);
}

/// Les étapes de la séquence d'ouverture — `AlertesOuvertureModales::etapes()`.
///
/// Vide quand personne n'est connecté ou quand la bascule « Alertes à
/// l'ouverture de session » est fermée (la même qui gouverne la cloche) :
/// `doitAfficher()` du composant.
final etapesOuvertureProvider =
    FutureProvider.autoDispose<List<EtapeOuverture>>((ref) async {
      if (ref.watch(sessionProvider) == null) return const [];
      final base = ref.watch(baseLocaleProvider);
      if (!await lireAlertesOuvertureActives(ParametresDao(base))) {
        return const [];
      }
      final lignes = await lireLignesOuverture(
        ref,
        droits: ref.watch(droitsProvider),
        maintenant: ref.watch(horlogeAlertesProvider)(),
      );
      return etapesOuverture(
        stock: lignes.stock,
        departs: lignes.departs,
        creances: lignes.creances,
      );
    });

/// L'état des modales : ce qui a déjà été traité et l'erreur de la dernière
/// action (`$traites` et `alerte_ouverture` du composant).
final class EtatModalesOuverture {
  const EtatModalesOuverture({
    this.traites = const {},
    this.erreur,
    this.canalRelance = 'telephone',
  });

  /// `sejour:<id>` et `client:<id>`.
  final Set<String> traites;
  final String? erreur;
  final String canalRelance;

  EtatModalesOuverture avec({
    Set<String>? traites,
    String? Function()? erreur,
    String? canalRelance,
  }) => EtatModalesOuverture(
    traites: traites ?? this.traites,
    erreur: erreur == null ? this.erreur : erreur(),
    canalRelance: canalRelance ?? this.canalRelance,
  );
}

/// `effectuerCheckOutOuverture` et `tracerRelanceOuverture` : les DEUX seuls
/// gestes des modales. Chacun exige le niveau `C` de SON module (M1, M3), relu
/// à l'instant du geste ; un refus, une absence ou un échec se DIT dans la
/// bande rouge de la modale (`alerte_ouverture`), jamais en silence.
final class ModalesOuvertureNotifier extends Notifier<EtatModalesOuverture> {
  @override
  EtatModalesOuverture build() => const EtatModalesOuverture();

  void choisirCanal(String canal) => state = state.avec(canalRelance: canal);

  void remettreAZero() => state = const EtatModalesOuverture();

  /// Check-out inline — même geste que l'écran Hébergement : l'unité passe en
  /// NETTOYAGE, jamais directement libre (EF-M1-04).
  Future<void> effectuerCheckOut(LigneDepartOuverture ligne) async {
    state = state.avec(erreur: () => null);
    if (!ref.read(droitsProvider).peutEcrire(ModuleTatacora.m1Hebergement)) {
      state = state.avec(erreur: () => TextesOuverture.droitManquant);
      return;
    }
    try {
      await ref.read(sejourDaoProvider).checkoutDuSejour(ligne.sejourId);
      state = state.avec(traites: {...state.traites, 'sejour:${ligne.sejourId}'});
    } on RefusSejour catch (refus) {
      state = state.avec(erreur: () => refus.message);
    }
  }

  /// Relance TRACÉE — aucune promesse d'envoi. Le montant réclamé est le reste
  /// dû RÉEL du client, relu à l'instant du geste, jamais une saisie ; une
  /// créance qui n'appelle pas (ou plus) de relance est refusée.
  Future<void> tracerRelance(LigneCreanceOuverture ligne) async {
    state = state.avec(erreur: () => null);
    if (!ref.read(droitsProvider).peutEcrire(ModuleTatacora.m3Crm)) {
      state = state.avec(erreur: () => TextesOuverture.droitManquant);
      return;
    }
    final session = ref.read(sessionProvider);
    final lignes = await lireLignesOuverture(
      ref,
      droits: ref.read(droitsProvider),
      maintenant: ref.read(horlogeAlertesProvider)(),
    );
    final fraiche = (lignes.creances ?? const <LigneCreanceOuverture>[])
        .where((c) => c.clientId != null && c.clientId == ligne.clientId)
        .firstOrNull;
    if (fraiche == null || !fraiche.relanceRequise) {
      state = state.avec(erreur: () => TextesOuverture.relanceIndisponible);
      return;
    }
    try {
      await ref
          .read(relancesClientsDaoProvider)
          .enregistrer(
            clientId: fraiche.clientId!,
            canal: state.canalRelance,
            montantReclameCentimes: fraiche.resteCentimes,
            commentaire: TextesOuverture.relanceCommentaire,
            auteurLogin: session?.login,
          );
      state = state.avec(traites: {...state.traites, fraiche.cleTraitee});
    } on RefusRelance catch (refus) {
      state = state.avec(erreur: () => refus.message);
    }
  }
}

final modalesOuvertureProvider =
    NotifierProvider<ModalesOuvertureNotifier, EtatModalesOuverture>(
      ModalesOuvertureNotifier.new,
    );
