import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/format/cle_comparaison.dart';
import '../../../core/rbac/garde_acces.dart';
import '../domain/roles_du_poste.dart';

/// Un refus d'écriture de la matrice — par CHAMP, comme les erreurs de
/// validation Livewire (`libelle`, `description`, `niveaux`), pour que la
/// modale les affiche sous le champ fautif ; plusieurs à la fois quand le
/// serveur en rendrait plusieurs (`$this->validate()` les collecte toutes).
final class RefusRoles implements Exception {
  const RefusRoles(this.erreurs);

  RefusRoles.message(String champ, String message) : erreurs = {champ: message};

  final Map<String, String> erreurs;

  String get message => erreurs.values.first;

  @override
  String toString() => message;
}

/// Les SEULS écrivains de `roles_local` — réplique de `RolePermissionService`
/// et du composant `RolesPermissions` du serveur (14/10/2026). Ils écrivent
/// aussi `utilisateurs_local.droitsJson` des comptes du rôle : au serveur, un
/// compte lit ses droits sur son rôle, sur ce poste il les PORTE — les
/// recopier est ce qui rend au geste l'effet immédiat du serveur.
///
/// @see RG-16 Contrôle d'accès basé sur les rôles
class RolesDao {
  RolesDao(this._base, {DateTime Function()? horloge})
    : _horloge = horloge ?? DateTime.now;

  final AppDatabase _base;
  final DateTime Function() _horloge;

  static const _uuid = Uuid();

  /// Les rôles et leurs comptes, dans l'ordre de `orderBy('libelle')`
  /// (collation sans casse ni accent).
  Future<List<RoleDuPoste>> roles() async {
    final lignes = await _base.select(_base.rolesLocal).get();
    final comptes = await _comptesParRole();
    final roles = [
      for (final l in lignes)
        RoleDuPoste(
          id: l.id,
          libelle: l.libelle,
          description: l.description,
          niveaux: _lire(l.droitsJson),
          comptes: comptes[l.libelle] ?? 0,
        ),
    ];
    roles.sort((a, b) {
      final c = cleDeComparaison(
        a.libelle,
      ).compareTo(cleDeComparaison(b.libelle));
      return c != 0 ? c : a.libelle.compareTo(b.libelle);
    });
    return roles;
  }

  /// `User::query()->count()` — TOUS les comptes, désactivés compris.
  Future<int> totalComptes() async {
    final ligne = await _base
        .customSelect('SELECT COUNT(*) AS n FROM utilisateurs_local')
        .getSingle();
    return ligne.data['n'] as int;
  }

  /// Pose les rôles du SOCLE qui manquent, et SEULEMENT eux —
  /// `RolePermissionSeeder::completerRolesNouveaux()` : un rôle présent n'est
  /// JAMAIS réécrit, ses ajustements d'écran priment. Idempotent : appelé à
  /// chaque lecture de l'écran, il couvre le poste neuf, la mise à jour depuis
  /// la v23 et le poste qui a sauté une livraison. Rend le nombre de rôles
  /// créés.
  Future<int> installerSocle() => _base.transaction(() async {
    final presents = {
      for (final r in await _base.select(_base.rolesLocal).get())
        cleDeComparaison(r.libelle),
    };
    var crees = 0;
    final maintenant = _horloge();
    for (final e in socleRbacCdcf.entries) {
      if (presents.contains(cleDeComparaison(e.key))) continue;
      await _base
          .into(_base.rolesLocal)
          .insert(
            RolesLocalCompanion.insert(
              id: _uuid.v4(),
              libelle: e.key,
              droitsJson: jsonEncode(e.value),
              dateCreation: maintenant,
              dateModification: maintenant,
            ),
          );
      crees++;
    }
    return crees;
  });

  /// « + Nouveau rôle » — `RolesPermissions::enregistrerRole()` puis
  /// `RolePermissionService::creerRole()`, refus dans leur ordre : droit,
  /// validation (toutes les erreurs à la fois), libellé vide après `trim`,
  /// doublon. Le rôle naît FERMÉ (`-` partout) : il n'obtient un droit que si
  /// quelqu'un le lui donne. Rend l'identifiant du rôle.
  Future<String> creerRole({
    required GardeAcces auteur,
    required String libelle,
    String? description,
  }) async {
    _exigerEcriture(auteur);

    // `validate()` : `required|string|max:100` et `nullable|string|max:255`,
    // sur la saisie BRUTE (`mb_strlen`, en caractères).
    final erreurs = <String, String>{};
    if (libelle.trim().isEmpty) {
      erreurs['libelle'] = MessagesRoles.libelleObligatoire;
    } else if (libelle.runes.length > 100) {
      erreurs['libelle'] = MessagesRoles.libelleTropLong;
    }
    if (description != null && description.runes.length > 255) {
      erreurs['description'] = MessagesRoles.descriptionTropLongue;
    }
    if (erreurs.isNotEmpty) throw RefusRoles(erreurs);

    final propre = libelle.trim();
    if (propre.isEmpty) {
      throw RefusRoles.message('libelle', MessagesRoles.libelleRequis);
    }
    final descriptionPropre =
        (description == null || description.trim().isEmpty)
        ? null
        : description.trim();

    return _base.transaction(() async {
      final cle = cleDeComparaison(propre);
      final existants = await _base.select(_base.rolesLocal).get();
      if (existants.any((r) => cleDeComparaison(r.libelle) == cle)) {
        throw RefusRoles.message(
          'libelle',
          MessagesRoles.roleDejaExistant(propre),
        );
      }
      final id = _uuid.v4();
      final maintenant = _horloge();
      await _base
          .into(_base.rolesLocal)
          .insert(
            RolesLocalCompanion.insert(
              id: id,
              libelle: propre,
              description: Value(descriptionPropre),
              droitsJson: jsonEncode({
                for (final code in codesModulesSocle)
                  code: NiveauAcces.aucun.code,
              }),
              dateCreation: maintenant,
              dateModification: maintenant,
            ),
          );
      return id;
    });
  }

  /// « Modifier les droits » — `RolesPermissions::enregistrerDroits()` puis
  /// `RolePermissionService::definirNiveau()` sur chaque module de l'écran.
  /// Les modules hors écran (`ANNULATIONS`) gardent leur niveau, comme au
  /// serveur qui ne synchronise que les seize modules de la modale. Les droits
  /// du rôle sont recopiés sur ses comptes dans la même transaction.
  ///
  /// ÉCART DÉLIBÉRÉ (14/10/2026) — le serveur appelle `definirNiveau()`
  /// module par module SANS transaction englobante : un refus sur `ROLES`
  /// laisserait écrits les quatorze modules qui le précèdent. Le poste refuse
  /// AVANT toute écriture. Le cas est inatteignable par l'écran (la case
  /// administrateur/ROLES est verrouillée à `C`), mais une écriture à moitié
  /// faite sur la matrice des droits ne se réplique pas.
  Future<void> definirDroits({
    required GardeAcces auteur,
    required String roleId,
    required Map<ModuleTatacora, NiveauAcces> niveaux,
  }) async {
    _exigerEcriture(auteur);
    await _base.transaction(() async {
      final role = await (_base.select(
        _base.rolesLocal,
      )..where((r) => r.id.equals(roleId))).getSingleOrNull();
      if (role == null) {
        throw RefusRoles.message('niveaux', MessagesRoles.roleIntrouvable);
      }
      if (role.libelle == 'administrateur' &&
          (niveaux[ModuleTatacora.roles] ?? NiveauAcces.aucun) !=
              NiveauAcces.complet) {
        throw RefusRoles.message(
          'niveaux',
          MessagesRoles.verrouillageAdministrateur,
        );
      }
      final droits = {
        ..._lire(role.droitsJson),
        for (final m in libellesModulesMatrice.keys)
          m.code: (niveaux[m] ?? NiveauAcces.aucun).code,
      };
      await _ecrire(role, droits);
    });
  }

  /// « Rétablir le socle du CdCF » — `RolePermissionService::retablirSocle()` :
  /// chaque rôle du socle PRÉSENT retrouve exactement sa matrice ; un rôle
  /// créé depuis l'écran n'est pas touché. Les comptes de chaque rôle rétabli
  /// sont réalignés dans la même transaction. Rend le nombre de rôles
  /// rétablis.
  Future<int> retablirSocle({required GardeAcces auteur}) async {
    _exigerEcriture(auteur);
    return _base.transaction(() async {
      final presents = await _base.select(_base.rolesLocal).get();
      var restaures = 0;
      for (final e in socleRbacCdcf.entries) {
        final cle = cleDeComparaison(e.key);
        final role = presents
            .where((r) => cleDeComparaison(r.libelle) == cle)
            .firstOrNull;
        // Le socle décrit douze rôles ; un rôle absent n'a rien à rétablir.
        if (role == null) continue;
        await _ecrire(role, {..._lire(role.droitsJson), ...e.value});
        restaures++;
      }
      return restaures;
    });
  }

  /// `exigerEcriture('ROLES')` — relu à chaque geste.
  static void _exigerEcriture(GardeAcces auteur) {
    if (!auteur.peutEcrire(ModuleTatacora.roles)) {
      throw RefusRoles.message('droit', MessagesRoles.refusDroit);
    }
  }

  Future<void> _ecrire(RoleLocal role, Map<String, String> droits) async {
    final json = jsonEncode(droits);
    await (_base.update(
      _base.rolesLocal,
    )..where((r) => r.id.equals(role.id))).write(
      RolesLocalCompanion(
        droitsJson: Value(json),
        dateModification: Value(_horloge()),
      ),
    );
    // Les comptes du rôle portent désormais SES droits — l'équivalent du
    // `role_id` du serveur, où le compte les lit sur le rôle à chaque requête.
    await (_base.update(_base.utilisateursLocal)
          ..where((u) => u.role.equals(role.libelle)))
        .write(UtilisateursLocalCompanion(droitsJson: Value(json)));
  }

  Future<Map<String, int>> _comptesParRole() async {
    final lignes = await _base
        .customSelect(
          'SELECT role, COUNT(*) AS n FROM utilisateurs_local GROUP BY role',
        )
        .get();
    return {
      for (final l in lignes) l.data['role'] as String: l.data['n'] as int,
    };
  }

  /// Un JSON illisible rend une matrice VIDE (aucun droit), jamais un droit
  /// deviné.
  static Map<String, String> _lire(String json) {
    try {
      final lu = jsonDecode(json);
      if (lu is! Map) return {};
      return {
        for (final e in lu.entries)
          if (e.value is String) e.key.toString(): e.value as String,
      };
    } on FormatException {
      return {};
    }
  }
}
