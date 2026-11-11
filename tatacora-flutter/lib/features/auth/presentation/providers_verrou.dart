import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../data/stockage_activite_verrou.dart';
import '../domain/verrou_session.dart';

/// L'horloge du verrou — injectable : un test avance le temps sans attendre
/// quinze minutes.
final horlogeVerrouProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Où l'instant de la dernière activité est rangé.
final stockageActiviteVerrouProvider = Provider<StockageActiviteVerrou>(
  (ref) => StockageActiviteCoffre(),
);

/// `deverrouiller()` : un SEUL objet par processus, parce qu'il tient le
/// compteur d'essais (le cache du serveur).
final deverrouillageSessionProvider = Provider<DeverrouillageSession>(
  (ref) => DeverrouillageSession(
    verifier: (login, motDePasse) =>
        ref.read(depotSessionProvider).verifierMotDePasse(login, motDePasse),
    limiteur: LimiteurTentatives(horloge: ref.read(horlogeVerrouProvider)),
  ),
);

/// L'état du voile.
final class EtatVerrou {
  const EtatVerrou({
    this.pret = false,
    this.verrouille = false,
    this.enCours = false,
    this.erreur,
  });

  /// L'horodatage persisté est lu : tant qu'il ne l'est pas, aucune activité
  /// n'est enregistrée (la vue contrôle l'inactivité AVANT d'enregistrer la
  /// première activité, sinon un redémarrage lèverait le verrou).
  final bool pret;

  /// Le voile est posé (`verrouille` d'Alpine).
  final bool verrouille;

  /// Un essai de déverrouillage est en cours (`wire:loading`).
  final bool enCours;

  /// Le message sous le champ (`@error('motDePasse')`).
  final String? erreur;

  EtatVerrou avec({
    bool? pret,
    bool? verrouille,
    bool? enCours,
    String? Function()? erreur,
  }) => EtatVerrou(
    pret: pret ?? this.pret,
    verrouille: verrouille ?? this.verrouille,
    enCours: enCours ?? this.enCours,
    erreur: erreur == null ? this.erreur : erreur(),
  );
}

/// Le minuteur d'inactivité (`x-data` de la vue) et le déverrouillage.
///
/// ## Quand le voile se pose
///
/// Seulement avec une session ouverte : sur l'écran de connexion il n'y a rien à
/// suspendre. Sans session, une activité LÈVE le verrou éventuel (l'horodatage
/// persisté d'un usage ancien ne doit pas verrouiller une connexion toute
/// fraîche — la saisie du mot de passe de connexion est une activité).
///
/// ## Un seul auteur de l'activité
///
/// [activite] est l'unique chemin qui rafraîchit l'horodatage ; l'écran la
/// demande à chaque événement de pointeur, de molette et de clavier
/// (`mousemove mousedown keydown scroll touchstart wheel`). Elle n'écrit au
/// coffre qu'au plus toutes les [espacementEcritureActivite].
final class VerrouSessionNotifier extends Notifier<EtatVerrou> {
  Timer? _minuteur;
  DateTime? _derniere;
  DateTime? _derniereEcriture;

  DateTime _maintenant() => ref.read(horlogeVerrouProvider)();

  @override
  EtatVerrou build() {
    ref.listen(sessionProvider, (avant, apres) {
      if (apres == null) {
        // Plus de session : ni voile ni erreur à garder.
        _derniere = _maintenant();
        state = state.avec(verrouille: false, erreur: () => null);
      } else if (avant != null && avant.login != apres.login) {
        _derniere = _maintenant();
        state = state.avec(verrouille: false, erreur: () => null);
      }
    });
    _minuteur = Timer.periodic(controleVerrou, (_) => controler());
    ref.onDispose(() => _minuteur?.cancel());
    unawaited(Future.microtask(_initialiser));
    return const EtatVerrou();
  }

  /// `init()` de la vue : l'inactivité est jugée sur l'horodatage rangé AVANT
  /// d'enregistrer la première activité.
  Future<void> _initialiser() async {
    final rangee = await ref.read(stockageActiviteVerrouProvider).lire();
    if (!ref.mounted) return;
    final maintenant = _maintenant();
    _derniere = rangee ?? _derniere;
    state = state.avec(
      pret: true,
      verrouille: inactifDepuisTropLongtemps(rangee, maintenant),
    );
    if (!state.verrouille) _enregistrer(maintenant);
  }

  void _enregistrer(DateTime instant) {
    _derniere = instant;
    final ecrite = _derniereEcriture;
    if (ecrite != null &&
        instant.difference(ecrite) < espacementEcritureActivite) {
      return;
    }
    _derniereEcriture = instant;
    unawaited(ref.read(stockageActiviteVerrouProvider).ecrire(instant));
  }

  /// Un événement d'activité (`enregistrerActivite()` hors verrou).
  void activite() {
    if (!state.pret) return;
    if (ref.read(sessionProvider) == null) {
      // Connexion en cours : une activité efface un verrou périmé.
      if (state.verrouille) state = state.avec(verrouille: false);
      _enregistrer(_maintenant());
      return;
    }
    if (state.verrouille) return;
    _enregistrer(_maintenant());
  }

  /// Le tour du `setInterval` de 5 secondes.
  void controler() {
    if (!state.pret || state.verrouille) return;
    if (ref.read(sessionProvider) == null) return;
    if (inactifDepuisTropLongtemps(_derniere, _maintenant())) {
      state = state.avec(verrouille: true, erreur: () => null);
    }
  }

  /// `VerrouSession::deverrouiller()`.
  Future<void> deverrouiller(String motDePasse) async {
    if (state.enCours) return;
    state = state.avec(enCours: true, erreur: () => null);
    final session = ref.read(sessionProvider);
    final issue = await ref
        .read(deverrouillageSessionProvider)
        .deverrouiller(
          utilisateurId: session?.utilisateurId,
          login: session?.login,
          motDePasse: motDePasse,
        );
    if (!ref.mounted) return;
    switch (issue) {
      case Deverrouille():
        // `session-deverrouillee` : le voile se lève et l'activité repart.
        final maintenant = _maintenant();
        _derniereEcriture = null;
        _enregistrer(maintenant);
        state = state.avec(
          enCours: false,
          verrouille: false,
          erreur: () => null,
        );
      case MotDePasseRefuse(:final message):
        state = state.avec(enCours: false, erreur: () => message);
      case TropDeTentatives(:final message):
        state = state.avec(enCours: false, erreur: () => message);
      case SessionAbsente():
        // Le serveur renvoie vers la connexion ; ici l'écran de connexion est
        // déjà celui d'une session absente : le voile n'a plus de raison d'être.
        state = state.avec(
          enCours: false,
          verrouille: false,
          erreur: () => null,
        );
    }
  }
}

final verrouSessionProvider =
    NotifierProvider<VerrouSessionNotifier, EtatVerrou>(
      VerrouSessionNotifier.new,
    );
