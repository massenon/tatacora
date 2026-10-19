import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/achats/data/achats_api.dart';
import 'package:tatacora_flutter/features/achats/data/achats_dao.dart';
import 'package:tatacora_flutter/features/achats/data/reglements_fournisseur_dao.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/commande_achat.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/fournisseur.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';

import '../../comptabilite/support/outils_comptabilite.dart';

/// Le jour où se jouent les essais de règlement : fixé, jamais l'horloge réelle.
final DateTime jourReglement = DateTime(2026, 10, 13, 10);

/// Le DAO des règlements sur [db], branché sur le VRAI moteur comptable (même
/// base, même horloge) : le règlement et sa pièce s'écrivent dans la même
/// transaction, comme en production.
ReglementsFournisseurDao reglementsDaoSur(
  AppDatabase db, {
  DateTime? maintenant,
}) {
  final quand = maintenant ?? jourReglement;
  return ReglementsFournisseurDao(
    db,
    maintenant: () => quand,
    moteur: () async => moteurSur(db, maintenant: () => quand),
  );
}

AchatsDao achatsDaoSur(AppDatabase db, {DateTime? maintenant}) {
  final quand = maintenant ?? jourReglement;
  return AchatsDao(
    db,
    stocks: StocksDao(db, maintenant: () => quand),
    maintenant: () => quand,
  );
}

/// Un fournisseur, un article et une commande de [quantite] × [prix], par les
/// DAO de production. Rend l'identifiant de la commande.
///
/// [statut] autre que `brouillon` / `envoyee` est POSÉ par SQL après la
/// création — comme le fait le script PHP : ces statuts sont produits par une
/// réception, que ces essais n'ont pas besoin de rejouer.
Future<String> semerCommande(
  AppDatabase db, {
  String fournisseurId = 'f-1',
  String fournisseur = 'Grand Marche SARL',
  String articleId = 'a-1',
  String quantite = '4',
  String prix = '1000',
  String date = '2026-10-01',
  String statut = 'envoyee',
  String auteurId = auteurEssai,
  DateTime? maintenant,
}) async {
  final achats = achatsDaoSur(db, maintenant: maintenant);
  final stocks = StocksDao(db, maintenant: () => maintenant ?? jourReglement);

  // Lu en base, pas par `tousLesFournisseurs()` : celui-ci n'offre que les
  // ACTIFS, et un fournisseur archivé existe quand même.
  final deja = await (db.select(
    db.fournisseursLocal,
  )..where((f) => f.id.equals(fournisseurId))).getSingleOrNull();
  if (deja == null) {
    await achats.creerFournisseur(
      SaisieFournisseur(
        id: fournisseurId,
        raisonSociale: fournisseur,
        contact: null,
        categorie: null,
        conditionsPaiement: null,
        evaluationCode: null,
      ),
      auteurId: auteurId,
    );
  }
  final existant = await (db.select(
    db.articlesLocal,
  )..where((a) => a.id.equals(articleId))).getSingleOrNull();
  if (existant == null) {
    await stocks.creerArticle(
      id: articleId,
      libelle: 'Sucre $articleId',
      categorie: 'Denrées',
      uniteMesure: 'kg',
      seuilCentiemes: 400,
      suivi: SuiviArticle.permanent,
      pointStockageId: null,
    );
  }

  final saisissable = StatutCommande.depuisCode(statut)?.saisissable ?? false;
  final detail = await achats.creerCommande(
    SaisieCommande(
      fournisseurId: fournisseurId,
      dateCommande: date,
      statut: saisissable
          ? StatutCommande.depuisCode(statut)!
          : StatutCommande.envoyee,
      lignes: [
        LigneSaisieCommande(
          articleId: articleId,
          libelle: 'ignoré',
          uniteMesure: 'ignorée',
          quantite: quantite,
          prixUnitaire: prix,
        ),
      ],
    ),
    auteurId: auteurId,
  );
  if (!saisissable) {
    await poserStatut(db, detail.commande.id, statut);
  }
  return detail.commande.id;
}

/// Pose un statut de commande par SQL (voir [semerCommande]).
Future<void> poserStatut(AppDatabase db, String commandeId, String statut) =>
    db.customStatement(
      'UPDATE commandes_achat_local SET statut = ? WHERE id = ?',
      [statut, commandeId],
    );

/// Le nombre de lignes d'une table.
Future<int> compterReglements(AppDatabase db) async {
  final r = await db
      .customSelect('SELECT COUNT(*) AS n FROM reglements_fournisseur_local')
      .getSingle();
  return r.data['n'] as int;
}

/// L'API de M7 sur [db], avec droits réglables — le chemin que l'écran emprunte.
AchatsApi apiAchatsSur(
  AppDatabase db, {
  bool peutLire = true,
  bool peutEcrire = true,
  String? auteur = auteurEssai,
  DateTime? maintenant,
}) => AchatsApi(
  dao: achatsDaoSur(db, maintenant: maintenant),
  reglements: reglementsDaoSur(db, maintenant: maintenant),
  peutLire: () => peutLire,
  peutEcrire: () => peutEcrire,
  auteurId: () => auteur,
);

/// Une aide pour les assertions sur un résultat d'API.
T recu<T>(ResultatAchats<T> r) {
  expect(r, isA<AchatsRecu<T>>(), reason: '$r');
  return (r as AchatsRecu<T>).donnees;
}
