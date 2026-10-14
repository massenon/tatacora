/// Les providers des sessions de caisse.
///
/// ## Tout vient de la base LOCALE, et rien ne part
///
/// Aucun `Dio`, aucun client d'API. Comme `providers_depenses.dart` : la session
/// de caisse EST sur le poste et y reste (zéro réseau).
///
/// ## Aucun `autoDispose`, et un `invalidate` APRÈS chaque geste
///
/// La barre de session lit la base ; elle ne se rafraîchit que si on le lui dit.
/// Le geste (ouvrir, clôturer) invalide [sessionDuBarProvider] juste après
/// l'écriture — sans quoi la barre dirait « Aucune caisse ouverte » sous un
/// message qui vient d'annoncer l'inverse.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/rbac/garde_acces.dart';
import '../data/sessions_caisse_dao.dart';
import '../../pos/domain/entities/panier.dart';
import '../../pos/presentation/providers_pos.dart';
import '../domain/entities/session_caisse.dart';
import '../domain/especes_de_la_session.dart';
import '../domain/indicateur_caisse.dart';
import '../domain/regles_caisse.dart';
import '../domain/repositories/sessions_caisse_repository.dart';

// Le point de vente de l'écran POS comptant (`PosComptant::POINT_CAISSE`) vit au
// domaine depuis le lot 5 : `PanierDao.cloturer` en a besoin. Ré-exporté ici
// pour que les écrans de la caisse n'aient rien à changer.
export '../domain/entities/session_caisse.dart' show pointDeCaisseDuComptoir;

/// Le dépôt des sessions — **l'interface**, jamais le DAO.
final depotSessionsCaisseProvider = Provider<SessionsCaisseRepository>(
  (ref) => SessionsCaisseDao(ref.watch(baseLocaleProvider)),
);

/// L'horloge de la barre de session (« · 12 min »). Injectable : un test qui
/// lit l'heure réelle échoue un jour sur mille.
final horlogeCaisseProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// La session OUVERTE du point de vente de l'écran — `null` : « Aucune caisse
/// ouverte ».
final sessionDuBarProvider = FutureProvider<SessionCaisse?>(
  (ref) => ref
      .watch(depotSessionsCaisseProvider)
      .sessionOuverte(pointDeCaisseDuComptoir),
);

/// L'indicateur de caisse de la barre supérieure — `IndicateurCaisse::pour()`
/// (12/10/2026, lot 1 « coquille »).
///
/// Il lit la session ouverte LA PLUS RÉCENTE, tous points confondus, comme le
/// serveur — pas celle du comptoir. Il SURVEILLE [sessionDuBarProvider] : les
/// deux gestes de caisse ([ouvrirLaCaisse], [cloturerLaCaisse]) l'invalident
/// après l'écriture, et l'indicateur se relit avec lui. Sans ce lien, la barre
/// supérieure dirait « Caisse fermée » au-dessus d'une barre de session qui
/// vient d'annoncer l'ouverture.
///
/// L'état « tardive » est calculé à la LECTURE, comme au serveur :
/// `IndicateurCaisse::pour()` est rappelé à CHAQUE rendu de page, donc à
/// chaque navigation. Ce provider n'est pas `autoDispose` et rien ne le réveille
/// de lui-même : c'est la coquille qui le relit à chaque montage et à chaque
/// changement de route (`_IndicateurCaisse`, `coquille_application.dart`), avec
/// l'heure de [horlogeCaisseProvider] — jamais `DateTime.now()` en dur.
///
/// ⚠ Corrigé le 12/10/2026 (contrôle B-1, bloquant) : ce commentaire disait
/// « passe au rouge à la prochaine relecture » alors qu'AUCUNE relecture
/// n'avait lieu hors ouvrir/clôturer — un poste resté allumé ne voyait jamais
/// la pastille rouge. Un poste laissé sur le MÊME écran passe au rouge à sa
/// prochaine navigation, comme la vue, pas à la minute exacte.
final indicateurCaisseProvider = FutureProvider<IndicateurCaisse>((ref) async {
  await ref.watch(sessionDuBarProvider.future);
  final session = await ref
      .watch(depotSessionsCaisseProvider)
      .sessionOuverteLaPlusRecente();
  return indicateurCaisse(session, ref.watch(horlogeCaisseProvider)());
});

/// Les espèces encaissées d'une session, en CENTIMES — la SOURCE du théorique.
///
/// Le serveur les somme sur `ventes` (statut `validee`, mode `especes`,
/// `session_id` de la session). Depuis le lot 5 (12/10/2026, D221 option a) le
/// poste écrit la même chose : un panier au comptant porte la session qui l'a
/// ENCAISSÉ (`session_encaissement_id`), et la somme est celle de
/// [especesEncaisseesCentimes]. Le théorique et l'écart sont donc calculés comme
/// au serveur — y compris ses incohérences, qui sont nommées dans cette fonction.
///
/// C'est ICI qu'est branchée la somme : un seul point d'injection, pas de
/// condition éparpillée dans l'écran.
final especesDeLaSessionProvider =
    Provider<Future<int> Function(SessionCaisse)>(
      (ref) =>
          (session) async => especesEncaisseesCentimes(
            await ref
                .read(depotPanierProvider)
                .paniers(statut: StatutPanier.cloture),
            session.id,
          ),
    );

/// Les ventes en espèces de la période qui ne sont rattachées à AUCUNE session —
/// ce que le théorique de la clôture ne peut PAS compter (réserve R2 du
/// contrôle du 12/10/2026).
///
/// Une session ouverte avant la v18 voit un théorique sans les ventes
/// antérieures : la formule est exacte, le tiroir ne l'est pas. La modale de
/// clôture le DIT au lieu de présenter le théorique comme un fait. Une LECTURE,
/// comme [especesDeLaSessionProvider] : rien n'est écrit, rien n'est déduit.
final ventesSansSessionProvider =
    Provider<Future<({int nombre, int montant})> Function(SessionCaisse)>(
      (ref) =>
          (session) async => ventesEnEspecesSansSession(
            await ref
                .read(depotPanierProvider)
                .paniers(statut: StatutPanier.cloture),
            session.dateOuverture,
          ),
    );

/// Qui ouvre : l'identifiant du compte connecté (RG-15), vide s'il n'y en a pas.
String _auteur(WidgetRef ref) => ref.read(sessionProvider)?.utilisateurId ?? '';

bool _peutEcrire(WidgetRef ref) =>
    ref.read(droitsProvider).peutEcrire(ModuleTatacora.m5Bar);

/// `PosComptant::ouvrirCaisse`. Rend le message de succès ; lève `RefusCaisse`.
Future<String> ouvrirLaCaisse(WidgetRef ref, String? fondSaisi) async {
  try {
    final session = await ref
        .read(depotSessionsCaisseProvider)
        .ouvrir(
          point: pointDeCaisseDuComptoir,
          fondSaisi: fondSaisi,
          auteurId: _auteur(ref),
          peutEcrire: _peutEcrire(ref),
        );
    return messageOuverture(session.point);
  } finally {
    // La barre relit la base, que le geste ait réussi ou non.
    ref.invalidate(sessionDuBarProvider);
  }
}

/// `PosComptant::cloturerCaisse`. Rend le message d'issue ; lève `RefusCaisse`.
Future<String> cloturerLaCaisse(WidgetRef ref, String? constateSaisi) async {
  try {
    final depot = ref.read(depotSessionsCaisseProvider);
    final session = await depot.sessionOuverte(pointDeCaisseDuComptoir);
    // Sans session ouverte, le DAO refuse AVANT de lire les espèces : `null`
    // n'est jamais consulté, ce n'est pas un zéro.
    final especes = session == null
        ? null
        : await ref.read(especesDeLaSessionProvider)(session);
    final cloture = await depot.cloturer(
      point: pointDeCaisseDuComptoir,
      constateSaisi: constateSaisi,
      peutEcrire: _peutEcrire(ref),
      especesEncaisseesCentimes: especes,
    );
    return messageCloture(cloture.session.point, cloture.ecartCentimes);
  } finally {
    ref.invalidate(sessionDuBarProvider);
  }
}
