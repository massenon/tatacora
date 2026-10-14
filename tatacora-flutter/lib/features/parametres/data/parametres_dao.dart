import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
// Les classes de tables doivent être dans la portée du fichier : sans cet
// import, le mixin généré est VIDE, sans erreur de génération (leçon
// `employe_dao.dart`).
import '../../../core/database/tables/parametres_tables.dart';

part 'parametres_dao.g.dart';

/// Accès Drift aux paramètres saisis — **unique point d'écriture** sur
/// `parametres_systeme_local`.
///
/// Ce DAO ne connaît ni le registre ni les règles : il lit et écrit des
/// couples clé/valeur déjà normalisés. Ce qu'une clé a le droit de valoir se
/// juge avant l'appel (`regles_parametres.dart`), là où ça se teste sans base.
///
/// Aucune file de synchronisation, aucun `statutSync` : la table ne part nulle
/// part (zéro réseau).
@DriftAccessor(tables: [ParametresSystemeLocal])
class ParametresDao extends DatabaseAccessor<AppDatabase>
    with _$ParametresDaoMixin {
  ParametresDao(super.db, {DateTime Function()? maintenant})
    : _maintenant = maintenant ?? DateTime.now;

  final DateTime Function() _maintenant;

  /// Toutes les valeurs renseignées, clé -> valeur.
  Future<Map<String, String>> lireTout() async {
    final lignes = await select(parametresSystemeLocal).get();
    return {for (final l in lignes) l.cle: l.valeur};
  }

  /// Écrit [valeurs] (`null` = vider la clé) et rend les clés dont la valeur a
  /// réellement changé. Une clé inchangée n'est PAS réécrite : son horodatage
  /// et son auteur restent ceux de la dernière vraie modification.
  Future<List<String>> ecrire(
    Map<String, String?> valeurs, {
    required String? auteurId,
  }) async {
    final modifiees = <String>[];
    await transaction(() async {
      for (final e in valeurs.entries) {
        final existant = await (select(
          parametresSystemeLocal,
        )..where((p) => p.cle.equals(e.key))).getSingleOrNull();

        final valeur = e.value;
        if (valeur == null) {
          if (existant == null) continue;
          await (delete(
            parametresSystemeLocal,
          )..where((p) => p.cle.equals(e.key))).go();
          modifiees.add(e.key);
          continue;
        }

        if (existant?.valeur == valeur) continue;

        await into(parametresSystemeLocal).insertOnConflictUpdate(
          ParametresSystemeLocalCompanion.insert(
            cle: e.key,
            valeur: valeur,
            modifieLe: _maintenant(),
            modifiePar: Value(auteurId),
          ),
        );
        modifiees.add(e.key);
      }
    });
    return modifiees;
  }
}
