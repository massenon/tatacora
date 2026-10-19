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
/// Aucun `statutSync` : depuis le lot 10e, l'envoi est enfilé par
/// `ParametresDepotLocal.ecrire`, et la descente passe par
/// [inscrireDescendue].
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

  /// Pose chaque valeur de [valeurs] dont la clé est ABSENTE, et seulement
  /// elle — `firstOrCreate` de `ParametresEtablissementSeeder` : une valeur
  /// déjà en base, corrigée à l'écran Paramètres, n'est JAMAIS réécrite. Sans
  /// auteur (`modifiePar` nul) : comme `utilisateur_creation_id` au serveur,
  /// la valeur vient du seeder, pas d'un compte. Rend les clés posées.
  ///
  /// Seul appelant : `ParametresDepotLocal.installerParametresInitiaux`.
  Future<List<String>> semerSiAbsentes(Map<String, String> valeurs) async {
    final posees = <String>[];
    await transaction(() async {
      for (final e in valeurs.entries) {
        final existant = await (select(
          parametresSystemeLocal,
        )..where((p) => p.cle.equals(e.key))).getSingleOrNull();
        if (existant != null) continue;
        await into(parametresSystemeLocal).insert(
          ParametresSystemeLocalCompanion.insert(
            cle: e.key,
            valeur: e.value,
            modifieLe: _maintenant(),
          ),
        );
        posees.add(e.key);
      }
    });
    return posees;
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

  /// Une valeur DESCENDUE du serveur (lot 10e) : posée sans auteur
  /// (`modifiePar` nul, comme `semerSiAbsentes` : elle ne vient d'aucun
  /// compte de ce poste) ; `null` vide la clé. Rend vrai si la ligne change.
  /// Seul appelant : `ParametresDepotLocal.inscrireDescendue`.
  Future<bool> inscrireDescendue(String cle, String? valeur) async {
    final existant = await (select(
      parametresSystemeLocal,
    )..where((p) => p.cle.equals(cle))).getSingleOrNull();
    if (valeur == null) {
      if (existant == null) return false;
      await (delete(
        parametresSystemeLocal,
      )..where((p) => p.cle.equals(cle))).go();
      return true;
    }
    if (existant?.valeur == valeur) return false;
    await into(parametresSystemeLocal).insertOnConflictUpdate(
      ParametresSystemeLocalCompanion.insert(
        cle: cle,
        valeur: valeur,
        modifieLe: _maintenant(),
        modifiePar: const Value(null),
      ),
    );
    return true;
  }
}
