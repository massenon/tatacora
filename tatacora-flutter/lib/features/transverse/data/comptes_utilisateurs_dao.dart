import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/format/adresse_email_facultative.dart';
import '../../../core/rbac/regle_archivage.dart';
import '../../auth/data/verificateur_hors_ligne.dart';
import '../domain/comptes_utilisateurs.dart';

/// Les gestes d'administration des comptes du poste — Lot J2 (14/10/2026).
///
/// ## Qui écrit `utilisateurs_local`, désormais
///
/// | Auteur | Colonnes |
/// |---|---|
/// | `SessionRepositoryLocal.creerCompte` | le PREMIER compte (poste vierge) |
/// | `SessionRepositoryLocal.changerMotDePasse` | le mot de passe de la session (« Mon profil ») |
/// | `RolesDao` | `droitsJson` des comptes d'un rôle modifié |
/// | **ce DAO** | création d'un compte, `actif`, mot de passe réinitialisé, `email` (v45 : à la création, et par son titulaire depuis « Mon profil ») |
///
/// ## Le même dérivé que partout
///
/// Tout mot de passe passe par [VerificateurHorsLigne.creer] — sel neuf,
/// PBKDF2-HMAC-SHA256, 120 000 tours — le chemin du compte administrateur et
/// de « Mon profil ». Seul le dérivé est écrit ; le mot de passe n'est ni
/// stocké ni journalisé.
///
/// ## Le droit est RELU au geste
///
/// L'auteur est relu en base par son identifiant à chaque geste : actif, et
/// d'un des deux rôles d'administration (par leur CODE). Une session ouverte
/// avant qu'on lui retire ce rôle n'administre plus rien.
///
/// Aucune suppression n'est exposée (RG-15), et rien ne part nulle part : le
/// poste est zéro réseau.
///
/// @see RG-15 Traçabilité — un compte désactivé reste en base
/// @see RG-16 Contrôle d'accès basé sur les rôles
class ComptesUtilisateursDao {
  ComptesUtilisateursDao(this._base, {DateTime Function()? horloge})
    : _horloge = horloge ?? DateTime.now;

  final AppDatabase _base;
  final DateTime Function() _horloge;

  static const _uuid = Uuid();

  /// Tous les comptes, désactivés compris, par nom puis identifiant. Ne lit
  /// JAMAIS le sel ni l'empreinte.
  Future<List<CompteUtilisateur>> comptes() async {
    final t = _base.utilisateursLocal;
    final lignes =
        await (_base.selectOnly(t)..addColumns([
              t.id,
              t.login,
              t.nom,
              t.role,
              t.actif,
              t.dateCreation,
              t.dateMotDePasse,
              t.email,
            ]))
            .get();
    final comptes = [
      for (final l in lignes)
        CompteUtilisateur(
          id: l.read(t.id)!,
          identifiant: l.read(t.login)!,
          nom: l.read(t.nom)!,
          role: l.read(t.role)!,
          actif: l.read(t.actif) ?? false,
          dateCreation: l.read(t.dateCreation)!,
          dateMotDePasse: l.read(t.dateMotDePasse)!,
          email: l.read(t.email),
        ),
    ];
    comptes.sort((a, b) {
      final c = a.nom.toLowerCase().compareTo(b.nom.toLowerCase());
      return c != 0 ? c : a.identifiant.compareTo(b.identifiant);
    });
    return comptes;
  }

  /// « + Nouveau compte ». Refus dans cet ordre : droit, validation (toutes
  /// les erreurs de saisie à la fois), identifiant déjà pris, rôle inconnu.
  /// Le compte reçoit les droits de son rôle (`roles_local.droitsJson`),
  /// RECOPIÉS comme le fait `RolesDao` : sur ce poste, un compte PORTE ses
  /// droits. Rend l'identifiant du compte créé.
  Future<String> creerCompte({
    required String auteurId,
    required String nom,
    required String identifiant,
    required String? role,
    required String motDePasse,
    required String confirmation,
    String? email,
  }) async {
    await _exigerAdministration(auteurId);

    final login = ReglesComptes.normaliserIdentifiant(identifiant);
    final nomPropre = nom.trim();
    final erreurs = <String, String>{};
    if (nomPropre.isEmpty) {
      erreurs['nom'] = MessagesComptes.nomObligatoire;
    } else if (nomPropre.runes.length > ReglesComptes.longueurMaxNom) {
      erreurs['nom'] = MessagesComptes.nomTropLong;
    }
    final erreurIdentifiant = _validerIdentifiant(login);
    if (erreurIdentifiant != null) erreurs['identifiant'] = erreurIdentifiant;
    if (role == null || role.trim().isEmpty) {
      erreurs['role'] = MessagesComptes.roleObligatoire;
    }
    // E-mail FACULTATIF (v45) : normalisé, validé comme le serveur ; vide : rien.
    if (AdresseEmailFacultative.erreur(email) != null) {
      erreurs['email'] = MessagesComptes.emailInvalide;
    }
    erreurs.addAll(_validerMotDePasse(motDePasse, confirmation));
    if (erreurs.isNotEmpty) throw RefusComptes(erreurs);

    // Le dérivé est calculé HORS de la transaction : 120 000 tours de PBKDF2
    // n'ont pas à tenir la base verrouillée.
    final maintenant = _horloge();
    final v = VerificateurHorsLigne.creer(
      login: login,
      motDePasse: motDePasse,
      maintenant: maintenant,
    );

    return _base.transaction(() async {
      final existant = await (_base.select(
        _base.utilisateursLocal,
      )..where((u) => u.login.equals(login))).getSingleOrNull();
      if (existant != null) {
        throw RefusComptes.message(
          'identifiant',
          MessagesComptes.identifiantPris(login),
        );
      }
      final ligneRole = await (_base.select(
        _base.rolesLocal,
      )..where((r) => r.libelle.equals(role!))).getSingleOrNull();
      if (ligneRole == null) {
        throw RefusComptes.message('role', MessagesComptes.roleInconnu);
      }
      final id = _uuid.v4();
      await _base
          .into(_base.utilisateursLocal)
          .insert(
            UtilisateursLocalCompanion.insert(
              id: id,
              login: login,
              nom: nomPropre,
              email: Value(AdresseEmailFacultative.normaliser(email)),
              role: ligneRole.libelle,
              droitsJson: ligneRole.droitsJson,
              sel: v.sel,
              empreinte: v.empreinte,
              iterations: v.iterations,
              dateCreation: maintenant,
              dateMotDePasse: maintenant,
            ),
          );
      return id;
    });
  }

  /// « Désactiver » / « Réactiver ». Un administrateur ne se désactive pas
  /// lui-même, et le dernier compte d'administration ACTIF ne se désactive
  /// pas : le poste n'aurait plus personne pour rouvrir les comptes.
  Future<void> definirActif({
    required String auteurId,
    required String compteId,
    required bool actif,
  }) async {
    await _exigerAdministration(auteurId);
    await _base.transaction(() async {
      final compte = await _compte(compteId);
      if (compte.actif == actif) return;
      if (!actif) {
        if (compte.id == auteurId) {
          throw RefusComptes.message(
            'compte',
            MessagesComptes.desactiverSoiMeme,
          );
        }
        if (rolesAdministration.contains(roleNormalise(compte.role))) {
          final actifs = await (_base.select(
            _base.utilisateursLocal,
          )..where((u) => u.actif.equals(true))).get();
          final autres = actifs.where(
            (u) =>
                u.id != compte.id &&
                rolesAdministration.contains(roleNormalise(u.role)),
          );
          if (autres.isEmpty) {
            throw RefusComptes.message(
              'compte',
              MessagesComptes.dernierAdministrateur,
            );
          }
        }
      }
      await (_base.update(_base.utilisateursLocal)
            ..where((u) => u.id.equals(compte.id)))
          .write(UtilisateursLocalCompanion(actif: Value(actif)));
    });
  }

  /// « Réinitialiser le mot de passe » — l'administrateur pose le nouveau.
  /// Règles de `changerMotDePasse` : 8 caractères au moins, différent de
  /// l'actuel (vérifié contre le dérivé stocké, l'ancien n'étant pas saisi).
  /// La confirmation est rejouée ici aussi.
  Future<void> reinitialiserMotDePasse({
    required String auteurId,
    required String compteId,
    required String nouveau,
    required String confirmation,
  }) async {
    await _exigerAdministration(auteurId);
    final erreurs = _validerMotDePasse(nouveau, confirmation);
    if (erreurs.isNotEmpty) throw RefusComptes(erreurs);

    final compte = await _compte(compteId);
    final actuel = VerificateurHorsLigne(
      login: compte.login,
      sel: compte.sel,
      empreinte: compte.empreinte,
      iterations: compte.iterations,
      derniereConnexionEnLigne: compte.dateMotDePasse,
    );
    if (actuel.correspond(nouveau)) {
      throw RefusComptes.message(
        'motDePasse',
        MessagesComptes.motDePasseIdentique,
      );
    }
    final date = _horloge();
    final v = VerificateurHorsLigne.creer(
      login: compte.login,
      motDePasse: nouveau,
      maintenant: date,
    );
    await (_base.update(
      _base.utilisateursLocal,
    )..where((u) => u.id.equals(compte.id))).write(
      UtilisateursLocalCompanion(
        sel: Value(v.sel),
        empreinte: Value(v.empreinte),
        iterations: Value(v.iterations),
        dateMotDePasse: Value(date),
      ),
    );
  }

  /// « Enregistrer les informations » de « Mon profil » : l'e-mail FACULTATIF du
  /// compte [utilisateurId] — celui de la SESSION, jamais celui d'un tiers (le
  /// geste ne prend pas d'auteur distinct : un compte n'écrit que le sien, sans
  /// droit d'administration, comme le changement de mot de passe). Vide efface ;
  /// normalisé (trim, minuscules) ; mal formé : [RefusComptes] sur `email`, rien
  /// n'est écrit. Aucune unicité. Rend l'adresse enregistrée (`null` : effacée).
  Future<String?> enregistrerEmail({
    required String utilisateurId,
    required String? email,
  }) async {
    if (AdresseEmailFacultative.erreur(email) != null) {
      throw RefusComptes.message('email', MessagesComptes.emailInvalide);
    }
    final adresse = AdresseEmailFacultative.normaliser(email);
    final compte = await _compte(utilisateurId);
    await (_base.update(_base.utilisateursLocal)
          ..where((u) => u.id.equals(compte.id)))
        .write(UtilisateursLocalCompanion(email: Value(adresse)));
    return adresse;
  }

  /// L'e-mail du compte [utilisateurId] (`null` : non renseigné ou compte inconnu).
  Future<String?> emailDuCompte(String utilisateurId) async {
    final t = _base.utilisateursLocal;
    final ligne =
        await (_base.selectOnly(t)
              ..addColumns([t.email])
              ..where(t.id.equals(utilisateurId)))
            .getSingleOrNull();
    return ligne?.read(t.email);
  }

  /// L'auteur, relu en base : actif ET d'un rôle d'administration.
  Future<void> _exigerAdministration(String auteurId) async {
    final auteur = await (_base.select(
      _base.utilisateursLocal,
    )..where((u) => u.id.equals(auteurId))).getSingleOrNull();
    if (auteur == null ||
        !auteur.actif ||
        !peutAdministrerComptes(auteur.role)) {
      throw RefusComptes.message('droit', MessagesComptes.refusDroit);
    }
  }

  Future<UtilisateurLocal> _compte(String compteId) async {
    final compte = await (_base.select(
      _base.utilisateursLocal,
    )..where((u) => u.id.equals(compteId))).getSingleOrNull();
    if (compte == null) {
      throw RefusComptes.message('compte', MessagesComptes.compteIntrouvable);
    }
    return compte;
  }

  static String? _validerIdentifiant(String login) {
    if (login.isEmpty) return MessagesComptes.identifiantObligatoire;
    final n = login.runes.length;
    if (n < ReglesComptes.longueurMinIdentifiant ||
        n > ReglesComptes.longueurMaxIdentifiant) {
      return MessagesComptes.identifiantLongueur;
    }
    if (!ReglesComptes.formatIdentifiant.hasMatch(login)) {
      return MessagesComptes.identifiantFormat;
    }
    return null;
  }

  static Map<String, String> _validerMotDePasse(
    String motDePasse,
    String confirmation,
  ) {
    final erreurs = <String, String>{};
    if (motDePasse.length < ReglesComptes.longueurMinMotDePasse) {
      erreurs['motDePasse'] = MessagesComptes.motDePasseCourt;
    }
    if (confirmation != motDePasse) {
      erreurs['confirmation'] = MessagesComptes.confirmationDifferente;
    }
    return erreurs;
  }
}
