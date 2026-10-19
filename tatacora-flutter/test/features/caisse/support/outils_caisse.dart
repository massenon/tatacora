import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/features/caisse/data/sessions_caisse_dao.dart';
import 'package:tatacora_flutter/features/caisse/presentation/providers_caisse.dart';

import '../../comptabilite/support/outils_comptabilite.dart';

/// Le jour de référence des essais de caisse : 12/10/2026 à 07:00, l'heure à
/// laquelle le Gîte ouvre son tiroir. Aucun essai ne dépend de l'horloge réelle.
final DateTime ouvertureDeReference = DateTime(2026, 10, 12, 7);

/// L'auteur des ouvertures de caisse d'essai (clé étrangère RG-15).
const String ouvreurEssai = auteurEssai;

/// Une base EN MÉMOIRE portant un utilisateur — le minimum pour ouvrir une
/// caisse (la clé étrangère `utilisateur_ouverture_id` est réelle).
Future<AppDatabase> baseCaisse() async {
  final db = AppDatabase.enMemoire();
  await db.customStatement('SELECT 1');
  await semerAuteur(db);
  return db;
}

/// Le DAO des sessions à l'horloge [horloge] — le chemin de production, sans
/// dépôt bouché.
SessionsCaisseDao daoCaisseSur(AppDatabase db, {DateTime? horloge}) {
  final h = horloge ?? ouvertureDeReference;
  return SessionsCaisseDao(db, maintenant: () => h);
}

/// Les surcharges qui branchent l'écran sur [db] et fixent l'horloge de la
/// barre de session (« depuis 07:00 », « · 12 min »).
List<Override> surchargesCaisse(AppDatabase db, {DateTime? horloge}) {
  final h = horloge ?? ouvertureDeReference;
  return [
    baseLocaleProvider.overrideWithValue(db),
    depotSessionsCaisseProvider.overrideWithValue(daoCaisseSur(db, horloge: h)),
    horlogeCaisseProvider.overrideWithValue(() => h),
  ];
}

/// Le nombre de lignes d'une table, par SQL brut.
Future<int> compterLignes(AppDatabase db, String table) async {
  final r = await db
      .customSelect('SELECT COUNT(*) AS n FROM $table')
      .getSingle();
  return r.data['n'] as int;
}
