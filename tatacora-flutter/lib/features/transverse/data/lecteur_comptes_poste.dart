import 'dart:convert';

import '../../../core/database/app_database.dart';
import '../../../core/rbac/garde_acces.dart';
import '../domain/roles_du_poste.dart';

/// LECTURE des comptes du poste pour Mon profil (lot D, 14/10/2026). N'écrit
/// rien : `SessionRepositoryLocal` crée les comptes, et `RolesDao` réécrit
/// leurs droits (`droitsJson`) quand les droits de leur rôle changent.
///
/// Ne lit JAMAIS le sel ni l'empreinte : seules les colonnes du rôle, des
/// droits et de l'état sont demandées. Les droits passent par
/// `GardeAcces.depuisJson`, la même fabrique que la session.
class LecteurComptesPoste {
  LecteurComptesPoste(this._base);

  final AppDatabase _base;

  /// Tous les comptes du poste, désactivés compris (RG-15 : un compte
  /// désactivé reste en base).
  Future<List<CompteDuPoste>> comptes() async {
    final t = _base.utilisateursLocal;
    final lignes = await (_base.selectOnly(
      t,
    )..addColumns([t.role, t.droitsJson, t.actif])).get();
    return [
      for (final l in lignes)
        CompteDuPoste(
          role: l.read(t.role) ?? '',
          droits: _droits(l.read(t.droitsJson)),
          actif: l.read(t.actif) ?? false,
        ),
    ];
  }

  /// L'état du compte [utilisateurId] : `true` actif, `false` désactivé,
  /// `null` inconnu (compte absent de la base).
  Future<bool?> estActif(String utilisateurId) async {
    final t = _base.utilisateursLocal;
    final ligne =
        await (_base.selectOnly(t)
              ..addColumns([t.actif])
              ..where(t.id.equals(utilisateurId)))
            .getSingleOrNull();
    return ligne?.read(t.actif);
  }

  /// Un JSON illisible rend une garde VIDE (aucun droit), jamais un droit
  /// deviné.
  static GardeAcces _droits(String? json) {
    if (json == null) return GardeAcces.depuisJson(const {});
    try {
      final lu = jsonDecode(json);
      return lu is Map<String, dynamic>
          ? GardeAcces.depuisJson(lu)
          : GardeAcces.depuisJson(const {});
    } on FormatException {
      return GardeAcces.depuisJson(const {});
    }
  }
}
