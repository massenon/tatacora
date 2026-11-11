import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../domain/comptes_syscohada.dart';
import '../domain/plan_comptable_fichier.dart';

/// Le chemin de l'asset : la COPIE OCTET POUR OCTET du fichier du PO que le
/// serveur importe (`tatacora-api/database/data/plan-comptable-syscohada-revise.csv`).
const cheminAssetPlanComptable =
    'assets/data/plan-comptable-syscohada-revise.csv';

/// Ce que l'installation a changé. Une seconde exécution rend des zéros : c'est
/// la preuve de l'idempotence, et un appelant peut la lire.
final class BilanInstallation {
  const BilanInstallation({
    required this.centresCrees,
    required this.journauxCrees,
    required this.comptesCrees,
    required this.comptesAlignes,
    required this.exerciceSeme,
  });

  final int centresCrees;
  final int journauxCrees;
  final int comptesCrees;
  final int comptesAlignes;

  /// L'année de l'exercice OUVERT par cette installation, `null` s'il existait
  /// déjà.
  final int? exerciceSeme;

  bool get aRienChange =>
      centresCrees == 0 &&
      journauxCrees == 0 &&
      comptesCrees == 0 &&
      comptesAlignes == 0 &&
      exerciceSeme == null;
}

/// Installe le référentiel comptable du serveur sur ce poste : les sept centres
/// de coût, les journaux (les cinq du seeder et les deux de la clôture), le plan comptable du PO (importé de
/// [contenuPlan] par `lirePlanComptable`, UNE fonction) et l'exercice de
/// l'année. Réplique de `ComptabiliteReferentielSeeder`.
///
/// ## Idempotent, additif, jamais destructif
///
/// Crée ce qui manque ; aligne le libellé et la classe d'un compte présent sur
/// le fichier ; ne supprime JAMAIS un compte (un compte peut porter des
/// écritures). Une `nature` ou un centre par défaut déjà posés ne sont jamais
/// écrasés. `nature` n'est dérivée que là où une règle écrite la donne
/// (6 = charge, 7 = produit) : les classes 1, 4 et 5 mêlent actif et passif, et
/// deviner ferait une nature fausse sur un état financier.
///
/// ## L'exercice de l'ANNÉE COURANTE s'ouvre tout seul, à chaque démarrage
///
/// Décision du lead (ticket D197, option (b), mise en œuvre le 10/10/2026) :
/// si le poste ne porte aucun exercice pour l'année de [maintenant], il
/// l'ouvre — du 1er janvier au 31 décembre, rien d'autre (aucun à-nouveau,
/// aucune reprise de solde). **ÉCART ASSUMÉ avec le serveur**, qui n'ouvre
/// jamais un exercice tout seul (« les exercices suivants sont ouverts par le
/// geste de clôture, jamais par un seeder ») : sans cet écart, un poste installé
/// en 2026 refuserait toute dépense le 01/01/2027
/// (`depenses.exercice_absent`) tant qu'aucun écran n'appellerait
/// `MoteurComptable.ouvrirExercice(2027)` — et aucun n'existe.
///
/// Idempotent : un exercice de l'année, ouvert ou CLÔTURÉ, n'est jamais recréé
/// ni rouvert. Les années passées ne sont pas comblées : ouvrir 2025 sur un poste
/// éteint depuis 2024 serait un choix comptable, pas un démarrage.
///
/// (Limite levée le 20/10/2026 : un poste allumé le 31/12 et laissé ouvert
/// jusqu'au 01/01 ouvre l'exercice à sa première pièce de l'année —
/// `MoteurComptable`, règle `ouvertureAutomatiquePermise`.)
///
/// ## Qui l'appelle
///
/// `referentielComptableProvider`, lu au démarrage de l'application
/// (`main.dart`). Une migration ne lit pas un asset : la v15 crée les tables
/// VIDES, et ce démarrage les remplit.
///
/// @see EF-M10-01 Plan comptable conforme SYSCOHADA révisé
Future<BilanInstallation> installerReferentielComptable(
  AppDatabase db, {
  required String contenuPlan,
  required DateTime maintenant,
  Uuid? uuid,
}) {
  final ids = uuid ?? const Uuid();
  // Le fichier est lu AVANT d'ouvrir la transaction : un fichier invalide ne
  // doit rien laisser derrière lui.
  final plan = lirePlanComptable(contenuPlan);

  return db.transaction(() async {
    // --- Centres de coût : firstOrCreate par libellé ---------------------
    final centresExistants = {
      for (final c in await db.select(db.centresCoutLocal).get())
        c.libelle: c.id,
    };
    var centresCrees = 0;
    for (final e in ComptesSyscohada.centres.entries) {
      if (centresExistants.containsKey(e.key)) continue;
      final id = ids.v4();
      await db
          .into(db.centresCoutLocal)
          .insert(
            CentresCoutLocalCompanion.insert(
              id: id,
              libelle: e.key,
              type: Value(e.value),
            ),
          );
      centresExistants[e.key] = id;
      centresCrees++;
    }

    // --- Journaux : firstOrCreate par code --------------------------------
    final journauxExistants = {
      for (final j in await db.select(db.journauxLocal).get()) j.code,
    };
    var journauxCrees = 0;
    // Les cinq journaux du seeder, puis les deux de la CLÔTURE (CL, AN) : le
    // serveur les porte depuis la migration de la clôture annuelle.
    for (final e in [
      ...ComptesSyscohada.journaux.entries,
      ...ComptesSyscohada.journauxDeCloture.entries,
    ]) {
      if (journauxExistants.contains(e.key)) continue;
      await db
          .into(db.journauxLocal)
          .insert(
            JournauxLocalCompanion.insert(
              id: ids.v4(),
              code: e.key,
              libelle: e.value,
            ),
          );
      journauxCrees++;
    }

    // --- Plan comptable : import du fichier du PO --------------------------
    final existants = {
      for (final c in await db.select(db.planComptableLocal).get())
        c.numeroCompte: c,
    };
    final aInserer = <PlanComptableLocalCompanion>[];
    var comptesAlignes = 0;

    for (final ligne in plan) {
      final classe = ligne.numero.substring(0, 1);
      final centreLibelle = ComptesSyscohada.centreParDefaut[ligne.numero];
      final centre = centreLibelle == null
          ? null
          : centresExistants[centreLibelle];
      final nature = switch (classe) {
        '6' => 'charge',
        '7' => 'produit',
        _ => null,
      };

      final compte = existants[ligne.numero];
      if (compte == null) {
        aInserer.add(
          PlanComptableLocalCompanion.insert(
            id: ids.v4(),
            numeroCompte: ligne.numero,
            libelle: ligne.libelle,
            classe: classe,
            nature: Value(nature),
            centreCoutDefautId: Value(centre),
          ),
        );
        continue;
      }

      final nouvelleNature = compte.nature ?? nature;
      final nouveauCentre = compte.centreCoutDefautId ?? centre;
      if (compte.libelle != ligne.libelle ||
          compte.classe != classe ||
          compte.nature != nouvelleNature ||
          compte.centreCoutDefautId != nouveauCentre) {
        await (db.update(
          db.planComptableLocal,
        )..where((c) => c.id.equals(compte.id))).write(
          PlanComptableLocalCompanion(
            libelle: Value(ligne.libelle),
            classe: Value(classe),
            nature: Value(nouvelleNature),
            centreCoutDefautId: Value(nouveauCentre),
          ),
        );
        comptesAlignes++;
      }
    }

    if (aInserer.isNotEmpty) {
      await db.batch((b) => b.insertAll(db.planComptableLocal, aInserer));
    }

    // --- Exercice de l'année courante : ouvert s'il manque ------------------
    final annee = maintenant.year;
    final exerciceDeLAnnee =
        await (db.select(db.exercicesLocal)
              ..where((e) => e.annee.equals(annee))
              ..limit(1))
            .getSingleOrNull();
    int? exerciceSeme;
    if (exerciceDeLAnnee == null) {
      await db
          .into(db.exercicesLocal)
          .insert(
            ExercicesLocalCompanion.insert(
              id: ids.v4(),
              annee: annee,
              dateDebut: '$annee-01-01',
              dateFin: '$annee-12-31',
            ),
          );
      exerciceSeme = annee;
    }

    return BilanInstallation(
      centresCrees: centresCrees,
      journauxCrees: journauxCrees,
      comptesCrees: aInserer.length,
      comptesAlignes: comptesAlignes,
      exerciceSeme: exerciceSeme,
    );
  });
}
