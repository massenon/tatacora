import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/providers_comptabilite.dart';
import 'package:tatacora_flutter/features/depenses/data/depense_dao.dart';

import '../../comptabilite/support/outils_comptabilite.dart';

/// Le jour de référence des essais : l'exercice 2026 est celui que
/// l'installation ouvre, et aucune dépense d'essai ne dépend de l'horloge réelle
/// (un test daté « aujourd'hui » échouerait le jour où l'exercice de l'année
/// courante ne serait pas celui qu'il suppose).
final DateTime jourDeReference = DateTime(2026, 10, 10, 10);

/// Le même identifiant que l'auteur des pièces de la comptabilité d'essai.
const String auteurDepense = auteurEssai;

/// Une base EN MÉMOIRE portant le référentiel comptable installé par la vraie
/// fonction à [maintenant] (l'exercice de cette année est ouvert) et un auteur.
Future<AppDatabase> baseDepenses({DateTime? maintenant}) =>
    baseInstallee(maintenant: maintenant ?? jourDeReference);

/// Prépare une base qui ne cherche pas à éprouver la comptabilité mais a besoin
/// de dépenses VRAIES (états, tableau de bord) : référentiel installé à
/// [maintenant] (idempotent), auteur semé s'il manque, DAO branché sur le
/// moteur réel. Une dépense y est enregistrée par le chemin de production, pièce
/// comprise.
Future<DepenseDao> depenseDaoPrepare(
  AppDatabase db,
  DateTime maintenant,
) async {
  await db.customStatement('SELECT 1');
  final auteurs = await (db.select(
    db.utilisateursLocal,
  )..where((u) => u.id.equals(auteurDepense))).get();
  if (auteurs.isEmpty) await semerAuteur(db);
  await baseInstalleeSur(db, maintenant);
  return depenseDaoSur(db, horloge: maintenant);
}

/// Le DAO des dépenses BRANCHÉ sur le moteur comptable réel de [db], à
/// l'horloge [horloge] : c'est le chemin de production, pas un dépôt bouché.
DepenseDao depenseDaoSur(AppDatabase db, {DateTime? horloge}) {
  final h = horloge ?? jourDeReference;
  return DepenseDao(
    db,
    maintenant: () => h,
    moteur: () async => moteurSur(db, maintenant: () => h),
  );
}

/// L'identifiant d'un centre de coût du moteur, par son libellé.
Future<String> centreDe(AppDatabase db, String libelle) async {
  final centre = await ComptabiliteDao(db).centreParLibelle(libelle);
  return centre!.id;
}

/// Le nombre de lignes d'une table, par SQL brut : ce qu'un refus ne doit pas
/// avoir fait bouger.
Future<int> compter(AppDatabase db, String table) async {
  final r = await db
      .customSelect('SELECT COUNT(*) AS n FROM $table')
      .getSingle();
  return r.data['n'] as int;
}

/// Une dépense d'AVANT la comptabilité, écrite DIRECTEMENT en base : sans
/// pièce, et avec le [compte] voulu même s'il n'est plus au plan (l'ancien
/// registre à six chiffres). C'est l'état d'un poste migré depuis la v15.
Future<void> semerDepenseAncienne(
  AppDatabase db, {
  String compte = '6052',
  String id = 'dep-ancienne',
}) async {
  await db
      .into(db.depensesLocal)
      .insert(
        DepensesLocalCompanion.insert(
          id: id,
          dateTransaction: DateTime(2026, 8, 20),
          tresorerie: 'caisse',
          libelle: 'Dépannage plomberie',
          saisieLe: Value(DateTime(2026, 8, 20, 9)),
        ),
      );
  await db
      .into(db.lignesDepenseLocal)
      .insert(
        LignesDepenseLocalCompanion.insert(
          id: '$id-l1',
          depenseId: id,
          libelle: 'Robinet',
          compteCharge: compte,
          nature: 'Entretien et réparations',
          famille: 'Services',
          montant: 12000,
        ),
      );
}

/// Pose un centre de coût PAR DÉFAUT sur un compte du plan — le geste que
/// l'Administrateur fait au serveur (aucun compte de charge n'en porte à
/// l'installation).
Future<void> donnerCentreParDefaut(
  AppDatabase db,
  String numero,
  String centre,
) async {
  final id = await centreDe(db, centre);
  await db.customStatement(
    'UPDATE plan_comptable_local SET centre_cout_defaut_id = ? '
    'WHERE numero_compte = ?',
    [id, numero],
  );
}

/// Les surcharges d'un écran monté sur [db] : la base, le moteur à l'horloge de
/// référence (sans quoi `moteurComptableProvider` lirait l'asset et l'heure
/// réelle), une session qui porte [droits] et un utilisateur réel.
List<Override> surchargesDepenses(
  AppDatabase db, {
  Map<String, String> droits = const {'M10': 'C'},
  DateTime? horloge,
}) {
  final h = horloge ?? jourDeReference;
  final garde = GardeAcces.depuisJson(droits);
  return [
    baseLocaleProvider.overrideWithValue(db),
    moteurComptableProvider.overrideWith(
      (ref) async => moteurSur(db, maintenant: () => h),
    ),
    droitsProvider.overrideWithValue(garde),
    sessionProvider.overrideWithBuild(
      (ref, notifier) => Session(
        utilisateurId: auteurDepense,
        login: 'compta-$auteurDepense',
        nom: 'Comptable',
        role: 'comptable',
        droits: garde,
      ),
    ),
  ];
}
