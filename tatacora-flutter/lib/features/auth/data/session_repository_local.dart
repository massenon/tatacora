import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/rbac/garde_acces.dart';
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
  SessionRepositoryLocal(this._base, {FlutterSecureStorage? coffre})
    : _coffre = coffre ?? const FlutterSecureStorage();

  final AppDatabase _base;
  final FlutterSecureStorage _coffre;

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

    final session = _depuisLigne(ligne);
    await _memoriserSession(ligne);
    return session;
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

    if (ligne == null || !ligne.actif) {
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
    );
  }
}
