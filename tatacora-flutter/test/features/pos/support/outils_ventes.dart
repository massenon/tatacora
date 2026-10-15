import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';

import '../../comptabilite/support/outils_comptabilite.dart';

/// Le jour de référence des essais de vente : 12/10/2026 à 10:00. L'exercice 2026
/// est celui que l'installation ouvre ; aucun essai ne dépend de l'horloge réelle.
final DateTime jourDeVente = DateTime(2026, 10, 12, 10);

/// L'auteur des ventes d'essai (clé étrangère RG-15, `ecritures_local.cree_par`).
const String caissierDeVente = auteurEssai;

/// Le DAO des paniers BRANCHÉ sur le moteur comptable réel de [db], à l'horloge
/// [horloge] : c'est le chemin de production, pas un dépôt bouché. Il faut que
/// [db] porte le référentiel comptable (`baseInstallee`, `baseInstalleeSur`) et
/// un auteur (`semerAuteur`), sans quoi toute clôture est refusée — comme en
/// production sur un poste sans plan.
///
/// [sansMoteur] pour éprouver le refus de clôturer sans pièce.
PanierDao panierDaoSur(
  AppDatabase db, {
  DateTime? horloge,
  DateTime Function()? lireHorloge,
  bool sansMoteur = false,
}) {
  final h = horloge ?? jourDeVente;
  DateTime maintenant() => lireHorloge?.call() ?? h;
  return PanierDao(
    db,
    maintenant: maintenant,
    moteur: sansMoteur
        ? null
        : () async => moteurSur(db, maintenant: maintenant),
  );
}

/// Prépare une base qui n'éprouve pas la comptabilité mais DOIT pouvoir clôturer
/// un panier : auteur semé s'il manque, référentiel installé à [maintenant]
/// (idempotent). Rend [db].
Future<AppDatabase> avecComptabilite(
  AppDatabase db, {
  DateTime? maintenant,
}) async {
  await db.customStatement('SELECT 1');
  final auteurs = await (db.select(
    db.utilisateursLocal,
  )..where((u) => u.id.equals(caissierDeVente))).get();
  if (auteurs.isEmpty) await semerAuteur(db);
  await baseInstalleeSur(db, maintenant ?? jourDeVente);
  return db;
}

/// Clôture un panier comme le faisait le poste AVANT le lot 6 : le statut, la
/// date, le mode, le montant figé et la session — et AUCUNE pièce comptable.
///
/// C'est la fabrique des ventes HISTORIQUES : celles qu'un poste a enregistrées
/// avant que la clôture ne passe sa pièce (rien n'est fabriqué rétroactivement,
/// voir `app_database.dart` v19), et celles que la clôture d'aujourd'hui ne
/// produirait plus jamais (un mode « non renseigné », une note de chambre au
/// comptoir). Une fixture qui voudrait la vente d'aujourd'hui passe par
/// `PanierDao.cloturer`, jamais par ici.
Future<void> cloturerSansPiece(
  AppDatabase db,
  String panierId, {
  String? mode,
  DateTime? quand,
  String? sessionId,
}) async {
  final lignes = await (db.select(
    db.lignesPanierLocal,
  )..where((l) => l.panierId.equals(panierId))).get();
  final total = lignes.fold<int>(0, (t, l) => t + l.prixUnitaire * l.quantite);
  await db.customStatement(
    'UPDATE paniers_local SET statut = ?, cloture_le = ?, mode_paiement = ?, '
    'montant_cloture = ?, session_encaissement_id = ? WHERE id = ?',
    [
      'cloture',
      (quand ?? jourDeVente).millisecondsSinceEpoch ~/ 1000,
      mode,
      total,
      sessionId,
      panierId,
    ],
  );
}
