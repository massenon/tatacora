/// Les providers de l'encaissement de facture (lot 5, 12/10/2026).
///
/// ## Tout vient de la base LOCALE, et rien ne part
///
/// Aucun `Dio`, aucun client d'API. Comme `providers_depenses.dart` : l'argent
/// encaissé EST sur le poste et y reste (zéro réseau).
///
/// ## Le moteur arrive par un résolveur
///
/// `moteurComptableProvider` attend l'installation du référentiel comptable ; le
/// DAO l'appelle à chaque écriture, jamais à la construction. Sans cela, une
/// instance construite trop tôt servirait un plan vide.
///
/// ## Une seule lecture des créances
///
/// [creancesProvider] est LA lecture que le solde des clients, le bouton
/// « Recouvrement », les trois indicateurs de M11 et l'état « créances clients »
/// de M14 partagent : la formule vit dans `creances.dart`, jamais réécrite.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../../core/di/providers.dart';
import '../../comptabilite/presentation/providers_comptabilite.dart';
import '../../hebergement/presentation/providers_hebergement.dart';
import '../data/paiements_facture_dao.dart';
import '../domain/creances.dart';
import '../domain/entities/paiement_facture.dart';
import '../domain/regles_encaissement.dart';
import '../domain/repositories/paiements_facture_repository.dart';
import 'providers_facturation.dart';

/// Le DAO des encaissements, branché sur le moteur comptable réel.
final paiementsFactureDaoProvider = Provider<PaiementsFactureDao>(
  (ref) => PaiementsFactureDao(
    ref.watch(baseLocaleProvider),
    moteur: () => ref.read(moteurComptableProvider.future),
  ),
);

/// Le dépôt — **l'interface**, jamais le DAO.
final depotPaiementsFactureProvider = Provider<PaiementsFactureRepository>(
  (ref) => ref.watch(paiementsFactureDaoProvider),
);

/// Les encaissements, du plus récent au plus ancien, annulés compris (comme le
/// serveur).
final paiementsFactureProvider =
    FutureProvider.autoDispose<List<PaiementFacture>>(
      (ref) => ref.watch(depotPaiementsFactureProvider).paiements(),
    );

/// `ref.read` d'un `Ref` OU d'un `WidgetRef` : les deux se passent tels quels.
typedef LecteurDeFournisseur = T Function<T>(ProviderListenable<T> fournisseur);

/// Lit les créances du poste — pièces, encaissements, acomptes — FRAÎCHES.
///
/// Une fonction et non un fournisseur, pour les lecteurs qui ne sont pas des
/// widgets (le tableau de bord, l'état M14, le geste « Recouvrement ») : lire un
/// `FutureProvider.autoDispose` depuis un `Provider` sans écouteur le fait
/// disposer EN COURS de calcul (« Cannot use the Ref … after it has been
/// disposed », rencontré au premier branchement de M11). Chacun appelle donc
/// cette lecture directement, et [creancesProvider] n'est que l'enveloppe des
/// écrans qui veulent se rafraîchir.
Future<List<CreanceFacture>> lireCreances(LecteurDeFournisseur lire) async {
  final pieces = await lire(depotFactureProvider).pieces();
  final paiements = await lire(depotPaiementsFactureProvider).paiements();
  final reservations = await lire(depotReservationProvider).reservations();

  return composerCreances(
    pieces: pieces,
    paiements: paiements,
    acomptesParReservation: acomptesDesReservations(reservations),
  );
}

/// Les créances : une entrée par facture du registre, impayée ou non.
final creancesProvider = FutureProvider.autoDispose<List<CreanceFacture>>(
  (ref) => lireCreances(ref.read),
);

/// Relit tout ce qu'un encaissement fait bouger. À appeler APRÈS le geste, qu'il
/// ait réussi ou non : un refus de pièce comptable ne laisse rien, mais la
/// lecture ne doit pas dépendre de cette garantie.
void rafraichirEncaissements(WidgetRef ref) {
  ref
    ..invalidate(paiementsFactureProvider)
    ..invalidate(creancesProvider);
}

/// Qui encaisse : l'identifiant du compte connecté (RG-15), vide s'il n'y en a pas.
String _auteur(WidgetRef ref) => ref.read(sessionProvider)?.utilisateurId ?? '';

/// `ClientsCreances::enregistrerRecouvrement`. Rend le message de succès ; lève
/// `RefusEncaissement` ou `RefusComptable` — dans les deux cas rien n'est écrit.
Future<String> recouvrerLaFacture(
  WidgetRef ref, {
  required String? pieceId,
  required String? montantSaisi,
  required String? modeSaisi,
  required String clientNom,
}) async {
  try {
    final paiement = await ref
        .read(depotPaiementsFactureProvider)
        .recouvrer(
          pieceId: pieceId,
          montantSaisi: montantSaisi,
          modeSaisi: modeSaisi,
          auteurId: _auteur(ref),
          peutEncaisser: peutEncaisserUneFacture(ref.read(droitsProvider)),
        );
    return messageDeRecouvrement(paiement, clientNom);
  } finally {
    // La lecture relit la base, que le geste ait réussi ou non.
    rafraichirEncaissements(ref);
  }
}

/// L'horloge de l'écran Clients & Créances (« Encaissé sur 30 j », ancienneté des
/// factures). Injectable : un test qui lit l'heure réelle change de résultat
/// tous les jours.
final horlogeCreancesProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);
