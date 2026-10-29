import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/rbac/garde_acces.dart';
import '../domain/mot_de_passe_perdu.dart';
import '../domain/session.dart';
import '../domain/session_repository.dart';
import 'verificateur_hors_ligne.dart';

/// Authentification **locale**, sans Laravel.
///
/// ## La décision, et ce qu'elle change
///
/// Product Owner, 21/08/2026 : *« je veux une connexion avec les RBAC et accès
/// sans l'API de Laravel, un login sans synchronisation avec Laravel ; on peut
/// faire la synchronisation des modules du système comme ventes, POS,
/// rapports, et non la synchronisation du login. »*
///
/// La distinction est structurante et vaut d'être énoncée : **le référentiel**
/// des utilisateurs est une donnée, qui pourra se synchroniser comme les
/// autres ; **l'authentification** est un geste local, qui ne le fera jamais.
///
/// Le repli qui existait avant ce jour ne suffisait pas : il exigeait une
/// **première** connexion en ligne, donc restait une dépendance au serveur,
/// simplement décalée dans le temps. Un poste neuf livré au Gîte un jour où le
/// lien est coupé n'aurait ouvert pour personne.
///
/// **Aucune méthode de ce fichier n'ouvre de socket.** C'est vérifiable en le
/// lisant : il n'importe ni `dio`, ni `http`.
///
/// ## Ce qui n'est jamais stocké
///
/// Le mot de passe. [VerificateurHorsLigne] porte un dérivé PBKDF2-HMAC-SHA256
/// — sel aléatoire, 120 000 tours, comparaison à temps constant.
///
/// ## Aucun message du serveur ne peut plus atteindre l'écran
///
/// L'implémentation précédente remontait le champ `message` de la réponse HTTP.
/// Un serveur mal routé répondait « The route api/v1/login could not be
/// found », **et cette phrase s'affichait au comptoir** : elle nomme le
/// préfixe d'API, la version, et révèle qu'aucun contrôle d'identifiants n'a
/// même été tenté. Ici les refus sont un **jeu fermé de trois messages**,
/// écrits localement.
final class SessionRepositoryLocal implements SessionRepository {
  SessionRepositoryLocal(
    this._base, {
    FlutterSecureStorage? coffre,
    DateTime Function()? horloge,
  }) : _coffre = coffre ?? const FlutterSecureStorage(),
       _horloge = horloge ?? DateTime.now;

  final AppDatabase _base;
  final FlutterSecureStorage _coffre;
  final DateTime Function() _horloge;

  static const _uuid = Uuid();
  static const String _cleSessionCourante = 'tatacora_session_courante';
  static const String _clePoste = 'tatacora_identifiant_poste';

  /// **Le seul message de refus d'identifiants.**
  ///
  /// Identique que le compte soit inconnu, désactivé, ou que le mot de passe
  /// soit faux. Les distinguer dirait à un attaquant quels identifiants
  /// existent — il lui suffirait alors d'essayer des logins jusqu'à ce que le
  /// message change.
  static const String refusIdentifiants =
      'Identifiant ou mot de passe incorrect.';

  /// Le cas du poste vierge, qui n'est pas un refus mais une consigne.
  static const String aucunCompte =
      'Aucun compte sur ce poste. Créez le compte administrateur pour '
      'commencer.';

  @override
  Future<Session> connecter(String identifiant, String motDePasse) async {
    final login = identifiant.trim().toLowerCase();

    final ligne = await (_base.select(
      _base.utilisateursLocal,
    )..where((u) => u.login.equals(login))).getSingleOrNull();

    // Un compte introuvable et un mot de passe faux rendent le MÊME refus, et
    // prennent volontairement un temps comparable : `correspond` est appelé
    // même quand la ligne existe mais que le compte est désactivé.
    if (ligne == null || !ligne.actif) {
      throw const EchecConnexion(refusIdentifiants);
    }

    final verificateur = VerificateurHorsLigne(
      login: ligne.login,
      sel: ligne.sel,
      empreinte: ligne.empreinte,
      iterations: ligne.iterations,
      derniereConnexionEnLigne: ligne.dateMotDePasse,
    );

    if (!verificateur.correspond(motDePasse)) {
      throw const EchecConnexion(refusIdentifiants);
    }

    // Mot de passe TEMPORAIRE posé par un administrateur (29/10/2026) : expiré
    // (24 h) il n'ouvre rien — le refus est prononcé APRÈS la vérification du mot
    // de passe, comme le compte désactivé du serveur, pour ne rien dire à qui ne
    // le connaît pas. Valide, il n'ouvre QUE l'écran de changement (la session
    // porte `changementObligatoire`, la garde du routeur fait le reste).
    if (_temporaireExpire(ligne, _horloge())) {
      throw const EchecConnexion(MessagesMotDePassePerdu.expire);
    }

    final session = _depuisLigne(ligne);
    await _memoriserSession(ligne);
    return session;
  }

  /// Le mot de passe temporaire de [ligne] est-il expiré à [maintenant] ?
  static bool _temporaireExpire(UtilisateurLocal ligne, DateTime maintenant) =>
      ligne.changementObligatoire &&
      ligne.mdpTemporaireExpireLe != null &&
      !maintenant.isBefore(ligne.mdpTemporaireExpireLe!);

  /// Définit le mot de passe CHOISI par le titulaire après une réinitialisation
  /// par un administrateur (29/10/2026, option A du PO) — la SEULE sortie de
  /// « changement obligatoire ».
  ///
  /// Règles : celles de « Mon profil » (8 caractères au moins), PLUS :
  /// différent du mot de passe temporaire et différent de l'ancien. Un temporaire
  /// expiré (24 h) n'autorise plus rien. Le nouveau est dérivé par le MÊME
  /// [VerificateurHorsLigne.creer] que partout ; l'indicateur, l'échéance et le
  /// dérivé de l'ancien mot de passe sont effacés. La session n'est pas fermée ICI
  /// (le notificateur de session la ferme : on se reconnecte avec le nouveau mot
  /// de passe, comme au web).
  ///
  /// La confirmation (« les deux saisies correspondent ») est un contrôle de
  /// SAISIE : elle reste au formulaire.
  Future<void> definirNouveauMotDePasse({
    required String login,
    required String nouveau,
  }) async {
    if (nouveau.length < ReglesMotDePassePerdu.longueurMin) {
      throw const RefusMotDePassePerdu(MessagesMotDePassePerdu.tropCourt);
    }
    final ligne =
        await (_base.select(_base.utilisateursLocal)
              ..where((u) => u.login.equals(login.trim().toLowerCase())))
            .getSingleOrNull();
    if (ligne == null || !ligne.actif || !ligne.changementObligatoire) {
      // Un compte qui n'a rien à changer n'a rien à faire ici.
      throw const RefusMotDePassePerdu(refusIdentifiants);
    }
    final maintenant = _horloge();
    if (_temporaireExpire(ligne, maintenant)) {
      throw const RefusMotDePassePerdu(MessagesMotDePassePerdu.expire);
    }

    final temporaire = VerificateurHorsLigne(
      login: ligne.login,
      sel: ligne.sel,
      empreinte: ligne.empreinte,
      iterations: ligne.iterations,
      derniereConnexionEnLigne: ligne.dateMotDePasse,
    );
    if (temporaire.correspond(nouveau)) {
      throw const RefusMotDePassePerdu(
        MessagesMotDePassePerdu.identiqueTemporaire,
      );
    }
    if (ligne.selPrecedent != null && ligne.empreintePrecedente != null) {
      final ancien = VerificateurHorsLigne(
        login: ligne.login,
        sel: ligne.selPrecedent!,
        empreinte: ligne.empreintePrecedente!,
        iterations: ligne.iterationsPrecedentes ?? 1,
        derniereConnexionEnLigne: ligne.dateMotDePasse,
      );
      if (ancien.correspond(nouveau)) {
        throw const RefusMotDePassePerdu(
          MessagesMotDePassePerdu.identiqueAncien,
        );
      }
    }

    final v = VerificateurHorsLigne.creer(
      login: ligne.login,
      motDePasse: nouveau,
      maintenant: maintenant,
    );
    await (_base.update(
      _base.utilisateursLocal,
    )..where((u) => u.id.equals(ligne.id))).write(
      UtilisateursLocalCompanion(
        sel: Value(v.sel),
        empreinte: Value(v.empreinte),
        iterations: Value(v.iterations),
        dateMotDePasse: Value(maintenant),
        changementObligatoire: const Value(false),
        mdpTemporaireExpireLe: const Value(null),
        selPrecedent: const Value(null),
        empreintePrecedente: const Value(null),
        iterationsPrecedentes: const Value(null),
      ),
    );
  }

  /// Vérifie le mot de passe de [login] SANS ouvrir de session : l'équivalent
  /// de `Auth::validate()` que `VerrouSession::deverrouiller()` emploie au web
  /// (jamais `Auth::attempt()`, qui régénérerait la session). Ne touche ni au
  /// coffre ni à l'état de la session ; un compte inconnu ou désactivé rend
  /// `false`, comme un mot de passe faux (même refus, PA-103).
  Future<bool> verifierMotDePasse(String login, String motDePasse) async {
    final ligne =
        await (_base.select(_base.utilisateursLocal)
              ..where((u) => u.login.equals(login.trim().toLowerCase())))
            .getSingleOrNull();
    if (ligne == null || !ligne.actif) return false;
    return VerificateurHorsLigne(
      login: ligne.login,
      sel: ligne.sel,
      empreinte: ligne.empreinte,
      iterations: ligne.iterations,
      derniereConnexionEnLigne: ligne.dateMotDePasse,
    ).correspond(motDePasse);
  }

  /// Y a-t-il au moins un compte sur ce poste ?
  ///
  /// Commande l'écran de premier démarrage. Un poste vierge ne doit pas
  /// afficher un formulaire qui refusera tout ce qu'on y saisit.
  Future<bool> aucunCompteExiste() async {
    final compte = await _base
        .customSelect('SELECT COUNT(*) AS n FROM utilisateurs_local')
        .getSingle();
    return (compte.data['n'] as int) == 0;
  }

  /// Crée un compte.
  ///
  /// **Aucun mot de passe par défaut n'existe nulle part dans ce dépôt.** Un
  /// mot de passe posé par une migration ou un seeder serait connu de
  /// quiconque lit le code, et personne ne le changerait jamais : c'est le
  /// mode d'entrée le plus courant sur un logiciel de gestion.
  Future<void> creerCompte({
    required String login,
    required String nom,
    required String motDePasse,
    required String role,
    required Map<String, String> droits,
  }) async {
    final normalise = login.trim().toLowerCase();
    if (normalise.isEmpty) {
      throw const EchecConnexion('L’identifiant ne peut pas être vide.');
    }
    if (motDePasse.length < 8) {
      // Le seul contrôle de robustesse posé ici, et le plus élémentaire.
      // Une politique complète (longueur, classes de caractères, historique)
      // est une décision qui appartient au Product Owner.
      throw const EchecConnexion(
        'Le mot de passe doit compter au moins 8 caractères.',
      );
    }

    final maintenant = DateTime.now();
    final v = VerificateurHorsLigne.creer(
      login: normalise,
      motDePasse: motDePasse,
      maintenant: maintenant,
    );

    await _base
        .into(_base.utilisateursLocal)
        .insert(
          UtilisateursLocalCompanion.insert(
            id: _uuid.v4(),
            login: normalise,
            nom: nom.trim().isEmpty ? normalise : nom.trim(),
            role: role,
            droitsJson: jsonEncode(droits),
            sel: v.sel,
            empreinte: v.empreinte,
            iterations: v.iterations,
            dateCreation: maintenant,
            dateMotDePasse: maintenant,
          ),
        );
  }

  /// Change le mot de passe de [login] — écran « Mon profil » (demande du PO
  /// du 14/10/2026), réplique LOCALE de `MonProfil::changerMotDePasse()`.
  ///
  /// Mêmes règles, même ordre que le serveur : 8 caractères au moins (la
  /// règle de [creerCompte]), nouveau différent de l'ancien, ancien VÉRIFIÉ
  /// contre le dérivé stocké. Le nouveau est dérivé par le MÊME
  /// [VerificateurHorsLigne.creer] que la création du compte — sel neuf,
  /// PBKDF2 — et seul ce dérivé est écrit. La session n'est pas fermée.
  ///
  /// La confirmation (« les deux saisies correspondent ») est un contrôle de
  /// SAISIE : elle reste au formulaire, comme au serveur.
  Future<void> changerMotDePasse({
    required String login,
    required String ancien,
    required String nouveau,
    DateTime? maintenant,
  }) async {
    if (nouveau.length < 8) {
      throw const EchecConnexion(
        'Le mot de passe doit compter au moins 8 caractères.',
      );
    }
    if (nouveau == ancien) {
      throw const EchecConnexion(
        "Le nouveau mot de passe est identique à l'ancien.",
      );
    }

    final ligne = await (_base.select(
      _base.utilisateursLocal,
    )..where((u) => u.login.equals(login))).getSingleOrNull();
    if (ligne == null || !ligne.actif) {
      throw const EchecConnexion("L'ancien mot de passe est incorrect.");
    }
    final verificateur = VerificateurHorsLigne(
      login: ligne.login,
      sel: ligne.sel,
      empreinte: ligne.empreinte,
      iterations: ligne.iterations,
      derniereConnexionEnLigne: ligne.dateMotDePasse,
    );
    if (!verificateur.correspond(ancien)) {
      throw const EchecConnexion("L'ancien mot de passe est incorrect.");
    }

    final date = maintenant ?? DateTime.now();
    final v = VerificateurHorsLigne.creer(
      login: ligne.login,
      motDePasse: nouveau,
      maintenant: date,
    );
    await (_base.update(
      _base.utilisateursLocal,
    )..where((u) => u.id.equals(ligne.id))).write(
      UtilisateursLocalCompanion(
        sel: Value(v.sel),
        empreinte: Value(v.empreinte),
        iterations: Value(v.iterations),
        dateMotDePasse: Value(date),
      ),
    );
  }

  @override
  Future<Session?> sessionCourante() async {
    final brut = await _coffre.read(key: _cleSessionCourante);
    if (brut == null) return null;

    final String login;
    try {
      login = (jsonDecode(brut) as Map<String, dynamic>)['login'] as String;
    } on Object {
      return null;
    }

    // On relit la ligne plutôt que de restaurer un profil figé : un compte
    // désactivé, ou dont les droits ont changé depuis, ne doit pas rouvrir
    // avec ses anciens droits au seul motif qu'une session traînait.
    final ligne = await (_base.select(
      _base.utilisateursLocal,
    )..where((u) => u.login.equals(login))).getSingleOrNull();

    if (ligne == null || !ligne.actif || _temporaireExpire(ligne, _horloge())) {
      await _coffre.delete(key: _cleSessionCourante);
      return null;
    }
    return _depuisLigne(ligne);
  }

  /// Relit la session de [login] depuis la base, sans toucher au coffre —
  /// `null` si le compte n'existe plus ou est désactivé.
  ///
  /// Appelée après un geste de l'écran Rôles & Permissions (14/10/2026) : au
  /// serveur, un compte relit ses droits sur son rôle à chaque requête ; sur ce
  /// poste, la session porte les droits lus à la connexion, et sans cette
  /// relecture un droit retiré resterait actif jusqu'à la déconnexion.
  Future<Session?> relire(String login) async {
    final ligne = await (_base.select(
      _base.utilisateursLocal,
    )..where((u) => u.login.equals(login))).getSingleOrNull();
    if (ligne == null || !ligne.actif) return null;
    return _depuisLigne(ligne);
  }

  @override
  Future<void> deconnecter() async {
    await _coffre.delete(key: _cleSessionCourante);
  }

  /// Identifiant stable de ce poste.
  ///
  /// Il ne sert PAS à la connexion — il sert à la **synchronisation des
  /// modules**, qui doit envoyer toujours le même (PA-66 : le `poste_id` d'un
  /// lot est opposable au jeton). Conservé ici parce que c'est le seul endroit
  /// qui possède déjà le coffre.
  Future<String> identifiantPoste() async {
    final existant = await _coffre.read(key: _clePoste);
    if (existant != null && existant.isNotEmpty) return existant;
    final nouveau = 'poste-${_uuid.v4().substring(0, 8)}';
    await _coffre.write(key: _clePoste, value: nouveau);
    return nouveau;
  }

  Future<void> _memoriserSession(UtilisateurLocal ligne) => _coffre.write(
    key: _cleSessionCourante,
    value: jsonEncode({'login': ligne.login}),
  );

  Session _depuisLigne(UtilisateurLocal ligne) {
    final brut = jsonDecode(ligne.droitsJson);
    final droits = <String, dynamic>{
      if (brut is Map)
        for (final e in brut.entries) e.key.toString(): e.value,
    };

    return Session(
      utilisateurId: ligne.id,
      login: ligne.login,
      nom: ligne.nom,
      role: ligne.role,
      // MEME fabrique que la voie serveur : une seconde lecture de la matrice
      // divergerait de la premiere, et c'est le RBAC qui en paierait le prix.
      droits: GardeAcces.depuisJson(droits),
      changementObligatoire: ligne.changementObligatoire,
    );
  }
}
