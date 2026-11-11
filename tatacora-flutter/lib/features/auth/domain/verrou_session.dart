/// Le VERROU DE SESSION du poste — réplique de `App\Pwa\Livewire\Transverse\
/// VerrouSession` (demande du Product Owner du 01/09/2026) et de son voile
/// (`pwa/livewire/verrou-session.blade.php`, monté par `layouts/pwa`).
///
/// ## Ce que « suspendue, pas fermée » veut dire, ici aussi
///
/// Le verrou ne ferme RIEN : il pose un voile par-dessus l'application (un
/// panier ouvert au comptoir, une modale à moitié remplie restent exactement
/// où ils étaient) et ne fait qu'UNE chose — vérifier le mot de passe du compte
/// connecté, sans ouvrir de session ([DeverrouillageSession]).
///
/// ## Ce qui est répliqué, et d'où cela vient
///
/// * le seuil (`INACTIVITE_SECONDES`, 15 minutes) et les mots (`pwa.verrou.*`)
///   sont RELUS du serveur par `verrou_session_contre_serveur_test.dart` ;
/// * la limitation de cadence est celle de `deverrouiller()` : cinq essais par
///   fenêtre de 60 secondes, clé `verrou-session|<utilisateur>`, relue par PHP
///   exécuté (le vrai composant) ;
/// * le contrôle d'inactivité tourne toutes les 5 secondes (`setInterval(…,
///   5000)` de la vue).
///
/// ## Écarts nommés (le poste n'est pas un navigateur)
///
/// * Le compteur d'essais vit en MÉMOIRE (le serveur : dans le cache). Fermer
///   l'application le remet à zéro, mais l'écran de connexion n'est pas limité
///   non plus sur ce poste.
/// * L'horodatage de la dernière activité est rangé au coffre sécurisé du poste
///   (le serveur : `localStorage`), au plus toutes les 20 secondes : le verrou
///   tient donc à travers un redémarrage de l'application, comme à travers un F5.
library;

/// `VerrouSession::INACTIVITE_SECONDES` — 15 minutes.
const Duration inactiviteVerrou = Duration(minutes: 15);

/// Le rythme du contrôle d'inactivité — `setInterval(…, 5000)` de la vue.
const Duration controleVerrou = Duration(seconds: 5);

/// `RateLimiter::tooManyAttempts($cle, 5)`.
const int essaisMaxVerrou = 5;

/// `RateLimiter::hit($cle, 60)` — la fenêtre, en secondes.
const Duration fenetreEssaisVerrou = Duration(seconds: 60);

/// L'écriture de l'horodatage d'activité est espacée : un mouvement de souris
/// ne doit pas écrire au coffre à chaque pixel.
const Duration espacementEcritureActivite = Duration(seconds: 20);

/// La clé de limitation de `deverrouiller()` : `'verrou-session|' . $utilisateur->id`.
String cleLimiteurVerrou(String utilisateurId) =>
    'verrou-session|$utilisateurId';

/// `localStorage` du serveur : `tatacora_derniere_activite`.
const String cleActiviteVerrou = 'tatacora_derniere_activite';

/// Les mots du voile — `lang/fr/pwa.php`, groupe `verrou`, et deux libellés de
/// `pwa.connexion` (l'œil du champ).
abstract final class TextesVerrou {
  /// `pwa.verrou.titre`.
  static const String titre = 'Session verrouillée';

  /// `pwa.verrou.message` — la phrase que le Product Owner a demandée.
  static const String message = 'Votre session est suspendue, pas fermée.';

  /// `pwa.verrou.sous_message`.
  static const String sousMessage =
      'Ressaisissez votre mot de passe pour reprendre exactement où vous en étiez.';

  /// `pwa.verrou.mot_de_passe`.
  static const String motDePasse = 'Mot de passe';

  /// `pwa.verrou.deverrouiller`.
  static const String deverrouiller = 'Déverrouiller';

  /// `pwa.verrou.erreur`.
  static const String erreur = 'Mot de passe incorrect.';

  /// `pwa.verrou.trop_de_tentatives`.
  static String tropDeTentatives(int secondes) =>
      'Trop de tentatives. Réessayez dans $secondes seconde(s).';

  /// `pwa.connexion.afficher_mot_de_passe`.
  static const String afficherMotDePasse = 'Afficher le mot de passe';

  /// `pwa.connexion.masquer_mot_de_passe`.
  static const String masquerMotDePasse = 'Masquer le mot de passe';
}

/// `inactifDepuisTropLongtemps()` : vrai quand la dernière activité date de
/// [inactiviteVerrou] ou plus. Sans horodatage (`derniere == null`), jamais
/// inactif — la vue : `if (!derniere) return false`.
bool inactifDepuisTropLongtemps(DateTime? derniere, DateTime maintenant) {
  if (derniere == null) return false;
  return maintenant.difference(derniere) >= inactiviteVerrou;
}

/// `Illuminate\Cache\RateLimiter` pour la seule clé du verrou : `hit()` ouvre
/// la fenêtre au PREMIER essai et ne la prolonge pas, `tooManyAttempts()` ne dit
/// oui que tant que la fenêtre court, `availableIn()` compte en secondes
/// entières, `clear()` oublie tout.
final class LimiteurTentatives {
  LimiteurTentatives({DateTime Function()? horloge})
    : _horloge = horloge ?? DateTime.now;

  final DateTime Function() _horloge;
  final Map<String, ({int essais, int expireSecondes})> _compteurs = {};

  int _secondes() => _horloge().millisecondsSinceEpoch ~/ 1000;

  bool tropDEssais(String cle, int max) {
    final c = _compteurs[cle];
    if (c == null) return false;
    if (c.expireSecondes <= _secondes()) {
      // La fenêtre est close : Laravel remet les essais à zéro.
      _compteurs.remove(cle);
      return false;
    }
    return c.essais >= max;
  }

  /// `RateLimiter::hit($cle, $fenetre)`.
  void toucher(String cle, Duration fenetre) {
    final maintenant = _secondes();
    final c = _compteurs[cle];
    if (c == null || c.expireSecondes <= maintenant) {
      _compteurs[cle] = (
        essais: 1,
        expireSecondes: maintenant + fenetre.inSeconds,
      );
    } else {
      _compteurs[cle] = (
        essais: c.essais + 1,
        expireSecondes: c.expireSecondes,
      );
    }
  }

  /// `RateLimiter::availableIn($cle)`.
  int disponibleDans(String cle) {
    final c = _compteurs[cle];
    if (c == null) return 0;
    final reste = c.expireSecondes - _secondes();
    return reste < 0 ? 0 : reste;
  }

  /// `RateLimiter::clear($cle)`.
  void effacer(String cle) => _compteurs.remove(cle);
}

/// L'issue d'un essai de déverrouillage.
sealed class ResultatDeverrouillage {
  const ResultatDeverrouillage();
}

/// Le bon mot de passe : le voile se lève (`session-deverrouillee`).
final class Deverrouille extends ResultatDeverrouillage {
  const Deverrouille();
}

/// Mot de passe incorrect : `pwa.verrou.erreur`.
final class MotDePasseRefuse extends ResultatDeverrouillage {
  const MotDePasseRefuse();
  String get message => TextesVerrou.erreur;
}

/// Cinq essais ratés dans la minute : `pwa.verrou.trop_de_tentatives`.
final class TropDeTentatives extends ResultatDeverrouillage {
  const TropDeTentatives(this.secondes);
  final int secondes;
  String get message => TextesVerrou.tropDeTentatives(secondes);
}

/// Aucune session ouverte : il n'y a rien à déverrouiller. Au serveur c'est le
/// renvoi vers la connexion (`redirectRoute('pwa.connexion')`).
final class SessionAbsente extends ResultatDeverrouillage {
  const SessionAbsente();
}

/// `VerrouSession::deverrouiller()` — vérifier le mot de passe de l'utilisateur
/// COURANT, dans le même ordre que le composant : session absente, trop
/// d'essais (le bon mot de passe n'y change rien), vérification, puis
/// `hit` sur échec ou `clear` sur succès.
final class DeverrouillageSession {
  DeverrouillageSession({required this.verifier, LimiteurTentatives? limiteur})
    : _limiteur = limiteur ?? LimiteurTentatives();

  /// Vérifie le mot de passe d'un compte SANS ouvrir de session
  /// (`Auth::validate()`).
  final Future<bool> Function(String login, String motDePasse) verifier;
  final LimiteurTentatives _limiteur;

  Future<ResultatDeverrouillage> deverrouiller({
    required String? utilisateurId,
    required String? login,
    required String motDePasse,
  }) async {
    if (utilisateurId == null || login == null) return const SessionAbsente();

    final cle = cleLimiteurVerrou(utilisateurId);

    if (_limiteur.tropDEssais(cle, essaisMaxVerrou)) {
      return TropDeTentatives(_limiteur.disponibleDans(cle));
    }

    final valide = await verifier(login, motDePasse);
    if (!valide) {
      _limiteur.toucher(cle, fenetreEssaisVerrou);
      return const MotDePasseRefuse();
    }

    _limiteur.effacer(cle);
    return const Deverrouille();
  }
}
