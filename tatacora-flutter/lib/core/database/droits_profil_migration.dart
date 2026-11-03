import 'dart:convert';

import 'package:drift/drift.dart';

/// v49 (03/11/2026) — pose les trois droits de « Mon profil » dans les matrices
/// DÉJÀ stockées : `roles_local.droits_json` et `utilisateurs_local.droits_json`.
///
/// ADDITIF et idempotent : une clé déjà présente n'est JAMAIS réécrite (un réglage
/// fait à l'écran « Rôles & Permissions » prime), une matrice illisible n'est pas
/// touchée (jamais un droit deviné). Valeurs par défaut (décision du PO) :
/// `PROFIL_NOM` et `PROFIL_TELEPHONE` pour TOUS les rôles, `PROFIL_INTITULE` pour
/// les rôles d'administration seulement. Mêmes valeurs que le serveur
/// (`RolePermissionSeeder`) et que `droitsProfilParDefaut` (le test de parité les
/// confronte) ; recopiées ICI parce que `core/` n'importe pas `features/`.
Future<void> poserDroitsProfil(DatabaseConnectionUser base) async {
  const administration = {'administrateur', 'super_admin'};
  Map<String, String> defauts(String role) => {
    'PROFIL_NOM': 'C',
    'PROFIL_TELEPHONE': 'C',
    'PROFIL_INTITULE': administration.contains(role) ? 'C' : '-',
  };

  final tables = {
    for (final t
        in await base
            .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
            .get())
      t.data['name'] as String,
  };

  Future<void> completer(String table, String colonneRole) async {
    if (!tables.contains(table)) return;
    final lignes = await base
        .customSelect(
          'SELECT id, $colonneRole AS role, droits_json FROM $table',
        )
        .get();
    for (final l in lignes) {
      Object? lu;
      try {
        lu = jsonDecode(l.data['droits_json'] as String);
      } on FormatException {
        continue;
      }
      if (lu is! Map) continue;
      final droits = {for (final e in lu.entries) e.key.toString(): e.value};
      var change = false;
      defauts(l.data['role'] as String).forEach((code, niveau) {
        if (!droits.containsKey(code)) {
          droits[code] = niveau;
          change = true;
        }
      });
      if (!change) continue;
      await base.customStatement(
        'UPDATE $table SET droits_json = ? WHERE id = ?',
        [jsonEncode(droits), l.data['id']],
      );
    }
  }

  await completer('roles_local', 'libelle');
  await completer('utilisateurs_local', 'role');
}
