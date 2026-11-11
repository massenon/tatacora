import 'dart:convert';

import 'package:drift/drift.dart';

/// v54 (09/11/2026) — pose les trois droits TRANSVERSES `SYNCHRO`, `APPAIRAGE` et
/// `IMPORT_EXPORT` dans les matrices DÉJÀ stockées : `roles_local.droits_json` et
/// `utilisateurs_local.droits_json` (décision du PO : « Synchronisation », « Appairage
/// Postes » et « Import & Export » sont au menu de TOUS les rôles par défaut).
///
/// ADDITIF et idempotent, comme `poserDroitsProfil` : une clé déjà présente n'est JAMAIS
/// réécrite (un réglage fait à l'écran « Rôles & Permissions » prime), une matrice
/// illisible n'est pas touchée, aucun droit n'est retiré. Valeur : `L` pour tout rôle,
/// `C` pour les rôles d'administration (mêmes valeurs que `RolePermissionSeeder::MATRICE`
/// du serveur ; le test de parité les confronte). Recopiées ICI parce que `core/`
/// n'importe pas `features/`. AUCUNE table ni colonne : la version de schéma monte
/// seulement pour que `onUpgrade` pose ces clés sur un poste déjà en service.
Future<void> poserDroitsOuvertsATous(DatabaseConnectionUser base) async {
  const administration = {'administrateur', 'super_admin'};
  const codes = ['SYNCHRO', 'APPAIRAGE', 'IMPORT_EXPORT'];

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
      final niveau = administration.contains(l.data['role']) ? 'C' : 'L';
      var change = false;
      for (final code in codes) {
        if (!droits.containsKey(code)) {
          droits[code] = niveau;
          change = true;
        }
      }
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
