/// Les fixtures des huit importeurs du poste (onglet « Importer les données »
/// de l'écran Import & Export) — partagées par l'essai du moteur et celui de
/// l'écran.
///
/// Chaque module est décrit par ce qu'un UTILISATEUR écrirait dans son
/// tableur (en-tête du modèle, lignes valides, une ligne fautive) et par la
/// table que son DAO PROPRIÉTAIRE écrit : les essais relisent cette table en
/// SQL brut, jamais une liste rendue par l'importeur lui-même.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/hebergement/data/parc_dao.dart';
import 'package:tatacora_flutter/features/restaurant/data/restaurant_dao.dart';
import 'package:tatacora_flutter/features/restaurant/domain/entities/plat.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/synchronisation/presentation/providers_synchronisation.dart'
    show cheminConfigurationPosteProvider;

/// L'auteur de toutes les saisies d'essai.
const String auteurImport = 'u-import';

/// Un module importable, vu de l'extérieur.
final class CasImport {
  const CasImport({
    required this.cle,
    required this.code,
    required this.nom,
    required this.table,
    required this.colonne,
    required this.entete,
    required this.valides,
    required this.fautive,
    required this.colonneFautive,
    required this.debutMessageFautif,
  });

  /// La clé fermée du serveur (`m3-clients`…).
  final String cle;

  /// Le code RBAC du module source (`M3`…).
  final String code;

  /// Le nom du module à l'écran.
  final String nom;

  /// La table que le DAO propriétaire écrit, et la colonne de sa clé
  /// naturelle.
  final String table;
  final String colonne;

  /// L'en-tête du modèle, au point-virgule, sans BOM.
  final String entete;

  /// Deux lignes valides (point-virgule), et leur clé naturelle en tête.
  final List<String> valides;

  /// Une ligne refusée au CONTRÔLE, la colonne visée et le début du message.
  final String fautive;
  final String colonneFautive;
  final String debutMessageFautif;

  /// Les clés naturelles des lignes valides (premier champ).
  List<String> get cles => [for (final l in valides) l.split(';').first];

  /// Un fichier : l'en-tête puis [lignes], au séparateur [separateur], en
  /// fin de ligne `\r\n` (Excel), précédé du BOM si [bom].
  String fichier(
    List<String> lignes, {
    String separateur = ';',
    bool bom = false,
  }) {
    final corps = [
      entete,
      ...lignes,
    ].map((l) => l.replaceAll(';', separateur)).join('\r\n');
    return '${bom ? '\u{FEFF}' : ''}$corps\r\n';
  }
}

/// Les huit modules, dans l'ordre du registre du serveur
/// (`ReferentielsImport::definitions()`).
const List<CasImport> casImport = [
  CasImport(
    cle: 'm3-clients',
    code: 'M3',
    nom: 'Clients',
    table: 'clients_local',
    colonne: 'nom',
    entete: 'Nom / Raison sociale;Prénom;Type de client;Téléphone;Email',
    valides: [
      'Agence Bénin Tour;;agence;+229 01 97 00 00 00;contact@exemple.bj',
      'KORA;Jean;particulier;+229 01 00 00 00 01;',
    ],
    fautive: 'Martien;;extraterrestre;+229 01 00 00 00 09;',
    colonneFautive: 'Type de client',
    debutMessageFautif: 'valeur « extraterrestre » hors liste',
  ),
  CasImport(
    cle: 'm1-hebergement',
    code: 'M1',
    nom: "Unités d'hébergement",
    table: 'unites_hebergement_local',
    colonne: 'numero',
    entete: "Numéro d'unité;Catégorie",
    valides: ['BNG-03;Bungalow', 'BNG-04;Bungalow'],
    fautive: 'CHT-01;Château',
    colonneFautive: 'Catégorie',
    debutMessageFautif: 'aucun enregistrement « Château »',
  ),
  CasImport(
    cle: 'm5-bar',
    code: 'M5',
    nom: 'Carte du bar',
    table: 'cartes_boisson_local',
    colonne: 'libelle',
    entete:
        'Nom de la boisson;Catégorie;Prix de vente (FCFA);Article de stock lié',
    valides: [
      'Bière Béninoise 66 cl;locale;1200;Béninoise 66 cl',
      'Béninoise bien fraîche;maison;1300;Béninoise 66 cl',
    ],
    fautive: 'Sucrerie;locale;douze cents;Béninoise 66 cl',
    colonneFautive: 'Prix de vente (FCFA)',
    debutMessageFautif: 'valeur « douze cents » n',
  ),
  CasImport(
    cle: 'm4-restaurant',
    code: 'M4',
    nom: 'Carte du restaurant',
    table: 'plats_local',
    colonne: 'libelle',
    entete: 'Nom du plat;Catégorie;Prix de vente (FCFA);Menu;Fiche recette',
    valides: [
      'Poulet DG;plats;4500;Menu local;Poulet DG',
      'Poulet braisé;plats;4000;Menu local;Poulet DG',
    ],
    fautive: 'Pâte rouge;plats;3000;Menu inconnu;Poulet DG',
    colonneFautive: 'Menu',
    debutMessageFautif: 'aucun enregistrement « Menu inconnu »',
  ),
  CasImport(
    cle: 'm6-stocks',
    code: 'M6',
    nom: 'Articles de stock',
    table: 'articles_local',
    colonne: 'libelle',
    entete:
        'nom;categorie;unite_mesure;prix_achat;seuil_alerte;point_stockage;'
        'suivi;stock_initial',
    valides: [
      'Riz local (sac 50 kg);Denrées;sac;18500;5;;permanent;',
      'Huile de palme;Denrées;bidon;;2;;permanent;',
    ],
    fautive: 'Sel fin;Denrées;;;;;;',
    colonneFautive: 'unite_mesure',
    debutMessageFautif: 'valeur obligatoire absente',
  ),
  CasImport(
    cle: 'm7-achats',
    code: 'M7',
    nom: 'Fournisseurs',
    table: 'fournisseurs_local',
    colonne: 'raison_sociale',
    entete:
        'Raison sociale;Contact;Catégorie;Conditions de paiement;Évaluation',
    valides: [
      'Bénin Boissons Distribution;+229 01 21 30 40 50;Boissons;30 jours;bon',
      'SOBEBRA;;Boissons;;',
    ],
    fautive: 'Fournisseur X;;;;excellentissime',
    colonneFautive: 'Évaluation',
    debutMessageFautif: 'valeur « excellentissime » hors liste',
  ),
  CasImport(
    cle: 'm8-vehicules',
    code: 'M8',
    nom: 'Parc de véhicules',
    table: 'vehicules_local',
    colonne: 'immatriculation',
    entete:
        'Immatriculation;Catégorie;Année;Nombre de places;Transmission;'
        'Tarif journalier (FCFA)',
    valides: [
      'AB 1234 RB;4x4;2022;5;Manuelle;45000',
      'AC 5678 RB;moto;2020;;;8000',
    ],
    fautive: 'AD 0000 RB;4x4;2022;5;Manuelle;-5',
    colonneFautive: 'Tarif journalier (FCFA)',
    debutMessageFautif: 'montant négatif (-5)',
  ),
  CasImport(
    cle: 'm9-tourisme',
    code: 'M9',
    nom: 'Circuits touristiques',
    table: 'circuits_local',
    colonne: 'nom',
    entete:
        'Nom du circuit;Thème;Zone;Durée;Prix par participant (FCFA);'
        'Capacité maximale',
    valides: [
      'Circuit Pendjari;nature;Atacora;2 jours;125000;12',
      'Tata Somba;culture;Atacora;1 jour;30000;8',
    ],
    fautive: 'Chutes de Kota;nature;Atacora;1 jour;20000;douze',
    colonneFautive: 'Capacité maximale',
    debutMessageFautif: 'valeur « douze » n',
  ),
];

/// Les droits d'écriture sur les huit modules et sur l'écran Import & Export.
const Map<String, String> droitsImportComplets = {
  'PARAM': 'C',
  'M1': 'C',
  'M3': 'C',
  'M4': 'C',
  'M5': 'C',
  'M6': 'C',
  'M7': 'C',
  'M8': 'C',
  'M9': 'C',
};

/// Une base en mémoire portant les référentiels que les imports VISENT
/// (catégorie d'hébergement, article lié d'une boisson, menu et fiche
/// recette d'un plat) — chacun écrit par le DAO de son module.
Future<AppDatabase> baseImport() async {
  final db = AppDatabase.enMemoire();
  await db.customStatement('SELECT 1');
  await db
      .into(db.utilisateursLocal)
      .insert(
        UtilisateursLocalCompanion.insert(
          id: auteurImport,
          login: 'import',
          nom: 'Responsable import',
          role: 'administrateur',
          droitsJson: '{}',
          sel: 's',
          empreinte: 'e',
          iterations: 1,
          dateCreation: DateTime(2026, 10, 1),
          dateMotDePasse: DateTime(2026, 10, 1),
        ),
      );
  await ParcDao(
    db,
  ).creerCategorie(libelle: 'Bungalow', capaciteMax: 2, tarifBase: 28000);
  final stocks = StocksDao(db);
  await stocks.creerArticle(
    id: 'art-beninoise',
    libelle: 'Béninoise 66 cl',
    categorie: 'Boissons',
    uniteMesure: 'bouteille',
    seuilCentiemes: 0,
    suivi: SuiviArticle.permanent,
    pointStockageId: null,
  );
  await stocks.creerArticle(
    id: 'art-poulet',
    libelle: 'Poulet entier',
    categorie: 'Viandes',
    uniteMesure: 'kg',
    seuilCentiemes: 0,
    suivi: SuiviArticle.permanent,
    pointStockageId: null,
  );
  final restaurant = RestaurantDao(db, stocks: stocks);
  await restaurant.enregistrerMenu(
    const SaisieMenu(libelle: 'Menu local', type: 'local'),
    auteurId: auteurImport,
  );
  await restaurant.enregistrerRecette(
    const SaisieFiche(
      libelle: 'Poulet DG',
      lignes: [
        LigneSaisieComposition(articleId: 'art-poulet', quantite: '0.5'),
      ],
    ),
    auteurId: auteurImport,
  );
  return db;
}

/// Les surcharges d'un conteneur (ou d'un écran) monté sur [db], avec une
/// session qui porte [droits].
///
/// [cheminPoste] : le `poste.json` fictif dont le dossier héberge `sauvegardes/`
/// (les sauvegardes conservées du poste). Absent, un dossier SANS entrée-sortie
/// asynchrone : le temps d'un test de widget est simulé.
List<Override> surchargesImport(
  AppDatabase db, {
  Map<String, String> droits = droitsImportComplets,
  String cheminPoste = '/inexistant/poste.json',
}) {
  final garde = GardeAcces.depuisJson(droits);
  return [
    cheminConfigurationPosteProvider.overrideWithValue(() async => cheminPoste),
    baseLocaleProvider.overrideWithValue(db),
    droitsProvider.overrideWithValue(garde),
    sessionProvider.overrideWithBuild(
      (ref, notifier) => Session(
        utilisateurId: auteurImport,
        login: 'import',
        nom: 'Responsable import',
        role: 'administrateur',
        droits: garde,
      ),
    ),
  ];
}

/// Le nombre de lignes d'une table, en SQL brut.
Future<int> compterLignes(AppDatabase db, String table) async {
  final r = await db
      .customSelect('SELECT COUNT(*) AS n FROM "$table"')
      .getSingle();
  return r.data['n'] as int;
}

/// Les valeurs de [colonne] dans [table], en SQL brut.
Future<Set<String>> valeursDe(
  AppDatabase db,
  String table,
  String colonne,
) async {
  final r = await db.customSelect('SELECT "$colonne" AS v FROM "$table"').get();
  return {for (final l in r) l.data['v'] as String};
}

/// Un conteneur Riverpod de production (importeurs câblés par
/// `importeursLocauxProvider`) sur [db].
ProviderContainer conteneurImport(AppDatabase db) =>
    ProviderContainer(overrides: surchargesImport(db));
