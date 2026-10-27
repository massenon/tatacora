/// Racine des providers partages.
///
/// Riverpod **exclusivement** (`00_MASTER_INSTRUCTIONS.md` ADR-000). Melanger
/// Provider, Bloc et `setState` produit trois facons de faire la meme chose,
/// et plus personne ne sait laquelle fait autorite.
///
/// Les providers sont declares a la main plutot que generes : `riverpod_generator`
/// est incompatible avec `drift_dev` sur ce SDK (analyzer 12 contre 13). Voir
/// la note de divergence du resume de Sprint 0.
///
/// ## Ce fichier ne construit AUCUN client HTTP — decision du PO, 14/09/2026
///
/// Le poste est **zero reseau**. `dioProvider`, `dioEnLigneProvider`,
/// `depotJetonApiProvider` et `etatJetonApiProvider` ont ete retires, avec la
/// couche `core/network/` et `core/sync/` entiere.
///
/// C'est la garantie la plus simple a verifier de tout le fichier, et elle
/// vaut mieux qu'une consigne : **un fichier qui n'importe aucun client HTTP
/// ne peut pas appeler un serveur**, ni aujourd'hui ni par inadvertance dans
/// six mois. La meme garde existait deja pour `SessionRepositoryLocal`
/// (PA-103) ; elle couvre desormais la racine.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/session_repository_local.dart';
import '../../features/auth/domain/session.dart';
import '../../features/auth/domain/session_repository.dart';
import '../database/app_database.dart';
import '../database/auteur_ecriture.dart';
import '../rbac/garde_acces.dart';

final baseLocaleProvider = Provider<AppDatabase>((ref) {
  final base = AppDatabase();
  // QUI écrit, depuis quel poste (v38) : le compte CONNECTÉ à l'instant de
  // l'écriture — relu à chaque fois, jamais capturé ici (une session qui change
  // entre deux gestes ne doit pas écrire sous l'identité de la précédente,
  // RG-15) — et le nom de la machine. Voir `auteur_ecriture.dart`.
  base.auteurEcriture = () =>
      (login: ref.read(sessionProvider)?.login, poste: nomDuPosteLocal());
  ref.onDispose(base.close);
  return base;
});

/// Le depot d'authentification — **LOCAL**, et il n'y en a plus qu'un.
///
/// Decision du Product Owner du 21/08/2026 (PA-103) : la connexion ne passe
/// pas par l'API. Le 14/09/2026 a supprime la seconde voie — `SessionRepositoryImpl`,
/// qui obtenait un jeton Sanctum pour la synchronisation — puisqu'il n'y a plus
/// ni synchronisation ni serveur a joindre.
///
/// Rien ne change pour l'utilisateur : c'est deja ce depot, et lui seul, qui
/// decidait qui entre.
final depotSessionProvider = Provider<SessionRepositoryLocal>((ref) {
  return SessionRepositoryLocal(ref.watch(baseLocaleProvider));
});

/// Session active, `null` si personne n'est connecte.
final sessionProvider = NotifierProvider<SessionNotifier, Session?>(
  SessionNotifier.new,
);

final class SessionNotifier extends Notifier<Session?> {
  @override
  Session? build() => null;

  SessionRepository get _depot => ref.read(depotSessionProvider);

  Future<void> restaurer() async {
    state = await _depot.sessionCourante();
  }

  /// Ouvre la session — **localement**, et rien d'autre ne peut l'empecher.
  ///
  /// ⚠ Jusqu'au 14/09/2026, cette methode tentait EN PLUS d'obtenir un jeton
  /// d'API (PA-154, voie (a)). L'acquisition a disparu avec le reseau. Ne la
  /// retablissez pas : elle faisait voyager le mot de passe vers un serveur,
  /// et la regle de PA-103 — un compte inconnu rend le meme message qu'un mot
  /// de passe faux — n'a jamais tenu que parce qu'aucun message du serveur
  /// n'atteignait cet ecran.
  Future<void> connecter(String identifiant, String motDePasse) async {
    state = await _depot.connecter(identifiant, motDePasse);
    // `Connexion::seConnecter()` pose le drapeau des modales d'ouverture de
    // session : une CONNEXION les déclenche, une session restaurée au
    // démarrage ne le fait pas.
    ref.read(ouvertureEnAttenteProvider.notifier).poser();
  }

  Future<void> deconnecter() async {
    await _depot.deconnecter();
    state = null;
  }

  /// Relit les droits de la session ouverte depuis la base (14/10/2026,
  /// écran Rôles & Permissions) : un droit modifié sur le rôle de la session
  /// prend effet tout de suite, comme au serveur qui le relit à chaque
  /// requête. Un compte devenu introuvable ou désactivé ferme la session,
  /// comme `restaurer()`.
  Future<void> relireDroits() async {
    final courante = state;
    if (courante == null) return;
    state = await ref.read(depotSessionProvider).relire(courante.login);
  }
}

/// Le drapeau « modales d'ouverture de session en attente » — le
/// `alertes_ouverture_en_attente` que `Connexion::seConnecter()` met en session
/// et qu'`AlertesOuvertureModales` consomme : vrai de la connexion jusqu'au
/// moment où les modales ont été montrées (ou jugées inutiles). Jamais posé par
/// la restauration d'une session au démarrage.
final ouvertureEnAttenteProvider =
    NotifierProvider<OuvertureEnAttenteNotifier, bool>(
      OuvertureEnAttenteNotifier.new,
    );

final class OuvertureEnAttenteNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void poser() => state = true;

  void consommer() => state = false;
}

/// Droits de la session — jamais `null`, pour eviter un `?.` a chaque usage.
///
/// Une session absente donne des droits vides, ce qui masque tout. C'est le
/// comportement sur : un droit ne s'obtient jamais par omission.
final droitsProvider = Provider<GardeAcces>((ref) {
  final session = ref.watch(sessionProvider);
  return session?.droits ?? const GardeAcces.deconnecte();
});
