/// Les providers de « Contactez l'éditeur » — la boîte d'envoi (schéma v25)
/// et sa relance périodique (Lot J2 partie 2, 14/10/2026).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../parametres/data/parametres_dao.dart';
import '../data/envoi_messages_editeur.dart';
import '../data/messages_editeur_dao.dart';
import '../domain/messages_editeur.dart';

/// Le seul écrivain de `messages_editeur_local`.
final messagesEditeurDaoProvider = Provider<MessagesEditeurDao>(
  (ref) => MessagesEditeurDao(ref.watch(baseLocaleProvider)),
);

/// L'unique expéditeur — UNE instance pour le geste de l'écran et la
/// relance : c'est elle qui empêche un double envoi.
final serviceMessagesEditeurProvider = Provider<ServiceMessagesEditeur>(
  (ref) => ServiceMessagesEditeur(
    dao: ref.watch(messagesEditeurDaoProvider),
    parametres: ParametresDao(ref.watch(baseLocaleProvider)),
  ),
);

/// Un compteur qui avance à chaque écriture de la boîte (geste, relance) :
/// les deux lectures de l'écran le surveillent et se relisent.
final revisionBoiteEditeurProvider = NotifierProvider<_RevisionBoite, int>(
  _RevisionBoite.new,
);

final class _RevisionBoite extends Notifier<int> {
  @override
  int build() => 0;

  void avancer() => state++;
}

/// « Vos envois » — les 50 derniers envois du compte de la session.
final envoisDuCompteProvider = FutureProvider.autoDispose<List<MessageEditeur>>(
  (ref) {
    ref.watch(revisionBoiteEditeurProvider);
    final session = ref.watch(sessionProvider);
    if (session == null) return Future.value(const []);
    return ref
        .watch(messagesEditeurDaoProvider)
        .envoisDuCompte(session.utilisateurId);
  },
);

/// « Messages en attente d'envoi » — tout le poste.
final etatFileEditeurProvider = FutureProvider.autoDispose<EtatFileEditeur>((
  ref,
) {
  ref.watch(revisionBoiteEditeurProvider);
  return ref.watch(messagesEditeurDaoProvider).etatFile();
});

/// La RELANCE des messages en attente : une première fois au démarrage du
/// poste, puis toutes les `PolitiqueRelanceEditeur.periode` tant que
/// l'application tourne. Démarrée par `main.dart` (PAS par `main_demo.dart` :
/// la démonstration n'émet rien — et le service le refuserait de toute façon).
///
/// Aucune sonde de connectivité : la tentative est l'autorité (au Gîte, un
/// routeur allumé au lien amont coupé se dit « connecté »). Une relance qui
/// échoue ne lève rien : elle note la raison et attend la suivante.
final relanceMessagesEditeurProvider = Provider<void>((ref) {
  final service = ref.watch(serviceMessagesEditeurProvider);

  Future<void> relancer() async {
    try {
      final bilan = await service.relancer();
      if (bilan != null && (bilan.envoyes > 0 || bilan.restants > 0)) {
        ref.read(revisionBoiteEditeurProvider.notifier).avancer();
      }
    } on Object {
      // Une base fermée pendant l'arrêt, par exemple : la relance suivante
      // recommencera. Rien ne doit remonter jusqu'à l'interface.
    }
  }

  unawaited(relancer());
  final minuteur = Timer.periodic(
    PolitiqueRelanceEditeur.periode,
    (_) => unawaited(relancer()),
  );
  ref.onDispose(minuteur.cancel);
});
