/// Les IMPORTEURS du poste — onglet « Importer les données » de l'écran
/// Import & Export (demande du PO du 14/10/2026).
///
/// Le serveur déclare huit modules importables (`ReferentielsImport`) ; chacun
/// est porté ici parce que le poste détient sa table ET un chemin d'écriture
/// à règles claires — le DAO que l'écran du module emploie déjà. Chaque ligne
/// passe par CE chemin, jamais par une insertion directe :
///
/// | Module | Clé naturelle | Écrivain |
/// |---|---|---|
/// | M6 Articles de stock | `nom` | `StocksApi.enregistrerArticle` (moteur partagé avec l'écran Stocks) |
/// | M3 Clients | `nom` | `ClientDao.creer` |
/// | M1 Unités d'hébergement | `numero` | `ParcDao.creerUnite` |
/// | M5 Carte du bar | `libelle` | `BoissonsApi.enregistrer` |
/// | M4 Carte du restaurant | `libelle` | `RestaurantDao.enregistrerPlat` |
/// | M7 Fournisseurs | `raison_sociale` | `AchatsDao.creerFournisseur` |
/// | M8 Parc de véhicules | `immatriculation` | `VehiculeDao.enregistrerVehicule` |
/// | M9 Circuits touristiques | `nom` | `TourismeDao.enregistrerCircuit` |
///
/// ## Les colonnes suivent le SCHÉMA DU POSTE (écarts nommés)
///
///  - **M6** : le modèle est celui de l'écran Stocks (`colonnesImportArticles`,
///    huit colonnes, stock d'ouverture compris) — c'est le moteur du poste,
///    partagé, pas la déclaration à cinq colonnes du serveur.
///  - **M4** : pas de colonne « Catégorie » — sur ce poste la catégorie d'un
///    plat est le type de son menu (D148), aucune colonne ne la porte.
///  - **M8** : ni « Année », ni « Nombre de places », ni « Transmission » —
///    `vehicules_local` n'a pas ces colonnes ; les importer serait les jeter.
///  - **M9** : « Thème » est un texte libre, comme la modale « Prestation » du
///    poste — l'énumération vit dans un schéma MySQL que le poste ne détient
///    pas.
///
/// ## Aucun import partiel
///
/// [MoteurImportLocal.controler] SIMULE l'écriture dans une transaction
/// annulée : le rapport dit d'avance ce que les DAO refuseraient.
/// [MoteurImportLocal.appliquer] recontrôle, puis écrit TOUT dans UNE
/// transaction : une ligne refusée, et rien n'entre en base.
library;

import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../achats/data/achats_dao.dart';
import '../../achats/domain/entities/fournisseur.dart';
import '../../bar/data/boissons_api.dart';
import '../../bar/domain/entities/boisson.dart';
import '../../crm/data/client_dao.dart';
import '../../crm/domain/entities/client.dart';
import '../../hebergement/data/parc_dao.dart';
import '../../hebergement/domain/refus_parc.dart';
import '../../restaurant/data/restaurant_dao.dart';
import '../../restaurant/domain/entities/plat.dart';
import '../../stocks/data/service_import_articles.dart';
import '../../stocks/data/stocks_api.dart';
import '../../stocks/data/stocks_dao.dart';
import '../../stocks/domain/import_articles.dart';
import '../../tourisme/data/tourisme_dao.dart';
import '../../tourisme/domain/departs.dart';
import '../../vehicules/data/vehicule_dao.dart';
import '../../vehicules/domain/entities/vehicule.dart';
import '../../vehicules/domain/regles_vehicules.dart';
import '../domain/import_referentiels.dart';

/// Le refus d'UNE ligne par le module qui l'écrit.
final class RefusLigneImport implements Exception {
  const RefusLigneImport(this.message);

  final String message;

  @override
  String toString() => message;
}

/// La phrase d'un refus levé par un DAO — chaque module a la sienne.
String motifRefusImport(Object e) => switch (e) {
  RefusLigneImport(:final message) => message,
  RefusStock(:final motif) => motif,
  RefusAchats(:final motif) => motif,
  RefusRestaurant(:final motif) => motif,
  RefusParc(:final message) => message,
  RefusVehicule(:final message) => message,
  RefusTourisme(:final message) => message,
  _ => '$e',
};

/// Un module importable sur ce poste.
abstract base class ImporteurLocal {
  ImporteurLocal(this.base);

  final AppDatabase base;

  /// La clé fermée du serveur (`m6-stocks`…).
  String get cle;

  /// Le module RBAC source — l'import exige son droit d'écriture.
  ModuleTatacora get module;
  String get nom;
  String get description;

  /// Le champ de la clé naturelle (doublons, idempotence).
  String get identifiant;
  List<ColonneImport> get colonnes;

  /// Le nom proposé par « Enregistrer sous » (celui du serveur).
  String get nomModele => 'modele_import_$cle.csv';

  /// Le modèle : BOM UTF-8, en-tête au point-virgule, AUCUNE ligne de
  /// données — décision du PO du 14/10/2026 pour l'import d'articles, étendue
  /// ici : une ligne d'exemple oubliée serait importée comme une vraie fiche.
  /// Les exemples sont dans la fiche « Colonnes attendues ».
  List<int> modeleOctets() =>
      utf8.encode('\u{FEFF}${colonnes.map((c) => c.libelle).join(';')}\r\n');

  /// Les identifiants déjà en base, NORMALISÉS.
  Future<Set<String>> existants();

  /// Par champ `reference` : libellé exact → identifiant.
  Future<Map<String, Map<String, String>>> references() async => const {};

  /// Lu avant chaque contrôle et chaque import (référentiels du moment).
  Future<void> preparer() async {}

  /// Écrit UNE ligne contrôlée par le chemin du module. LÈVE pour refuser ;
  /// rend une réserve à dire (ligne écrite, mais avec un manque), ou `null`.
  Future<String?> ecrire(LigneImport ligne);

  static Set<String> normaliser(Iterable<String> valeurs) => {
    for (final v in valeurs) normaliserImport(v),
  };

  /// Un montant en francs ENTIERS (le XOF n'a pas de sous-unité).
  static int francs(String valeur) {
    final lu = num.tryParse(valeur);
    if (lu == null || lu != lu.truncate()) {
      throw RefusLigneImport(
        'montant « $valeur » : un nombre entier de francs est attendu',
      );
    }
    return lu.toInt();
  }
}

/* ====================================================================== */
/* M6 — Articles de stock : le moteur de l'écran Stocks, partagé           */
/* ====================================================================== */

final class ImporteurArticles extends ImporteurLocal {
  ImporteurArticles(super.base, {required this.api});

  final StocksApi api;
  Map<String, String> _points = const {};
  static const _uuid = Uuid();

  @override
  String get cle => 'm6-stocks';
  @override
  ModuleTatacora get module => ModuleTatacora.m6Stocks;
  @override
  String get nom => 'Articles de stock';
  @override
  String get description => TextesImportArticles.sousTitre;
  @override
  String get identifiant => 'nom';
  @override
  String get nomModele => TextesImportArticles.nomModele;
  @override
  List<int> modeleOctets() => modeleImportArticlesOctets();

  /// Les huit colonnes de `colonnesImportArticles`, dans leur ordre. Seules
  /// `nom` et `unite_mesure` sont obligatoires ; les autres suivent les règles
  /// du moteur (`lireLigneArticle`), qui les DIT au rapport.
  @override
  List<ColonneImport> get colonnes => const [
    ColonneImport(
      champ: 'nom',
      libelle: 'nom',
      requis: true,
      exemple: 'Riz local (sac 50 kg)',
    ),
    ColonneImport(
      champ: 'categorie',
      libelle: 'categorie',
      requis: false,
      exemple: 'Denrées',
    ),
    ColonneImport(
      champ: 'unite_mesure',
      libelle: 'unite_mesure',
      requis: true,
      exemple: 'sac',
    ),
    ColonneImport(
      champ: 'prix_achat',
      libelle: 'prix_achat',
      requis: false,
      exemple: '18500',
    ),
    ColonneImport(
      champ: 'seuil_alerte',
      libelle: 'seuil_alerte',
      requis: false,
      exemple: '5',
    ),
    ColonneImport(
      champ: 'point_stockage',
      libelle: 'point_stockage',
      requis: false,
      exemple: 'Magasin général',
    ),
    ColonneImport(
      champ: 'suivi',
      libelle: 'suivi',
      requis: false,
      exemple: 'permanent',
    ),
    ColonneImport(
      champ: 'stock_initial',
      libelle: 'stock_initial',
      requis: false,
      exemple: '10',
    ),
  ];

  @override
  Future<void> preparer() async {
    _points = {for (final p in await api.points()) p.libelle: p.id};
  }

  @override
  Future<Set<String>> existants() async => ImporteurLocal.normaliser(
    (await base.select(base.articlesLocal).get()).map((a) => a.libelle),
  );

  @override
  Future<String?> ecrire(LigneImport ligne) async {
    final lue = lireLigneArticle(
      [for (final c in colonnesImportArticles) ligne[c] ?? ''],
      pointsParLibelle: _points,
      nouvelId: _uuid.v4,
    );
    final r = await enregistrerArticleImporte(api, lue.saisie);
    if (r is LigneRefusee) throw RefusLigneImport(r.motif);
    final reserve = lue.reserve;
    return reserve == null ? null : "créé sans stock d'ouverture ($reserve)";
  }
}

/* ====================================================================== */
/* M3 — Clients                                                            */
/* ====================================================================== */

final class ImporteurClients extends ImporteurLocal {
  ImporteurClients(super.base, {required this.dao});

  final ClientDao dao;

  @override
  String get cle => 'm3-clients';
  @override
  ModuleTatacora get module => ModuleTatacora.m3Crm;
  @override
  String get nom => 'Clients';
  @override
  String get description =>
      'Fiches clients : particuliers, groupes, agences et structures.';
  @override
  String get identifiant => 'nom';
  @override
  List<ColonneImport> get colonnes => [
    const ColonneImport(
      champ: 'nom',
      libelle: 'Nom / Raison sociale',
      requis: true,
      exemple: 'Agence Bénin Tour',
    ),
    const ColonneImport(
      champ: 'prenom',
      libelle: 'Prénom',
      requis: false,
      exemple: 'Pascaline',
    ),
    ColonneImport(
      champ: 'type_client',
      libelle: 'Type de client',
      requis: true,
      type: TypeColonneImport.liste,
      valeurs: [for (final t in TypeClientReferentiel.values) t.code],
      exemple: 'agence',
    ),
    const ColonneImport(
      champ: 'telephone',
      libelle: 'Téléphone',
      requis: true,
      exemple: '+229 01 97 00 00 00',
    ),
    const ColonneImport(
      champ: 'email',
      libelle: 'Email',
      requis: false,
      exemple: 'contact@exemple.bj',
    ),
  ];

  @override
  Future<Set<String>> existants() async => ImporteurLocal.normaliser(
    (await base.select(base.clientsLocal).get()).map((c) => c.nom),
  );

  @override
  Future<String?> ecrire(LigneImport ligne) async {
    await dao.creer(
      nom: ligne.exiger('nom'),
      prenom: ligne['prenom'],
      telephone: ligne.exiger('telephone'),
      email: ligne['email'],
      type: TypeClientReferentiel.parCode(ligne['type_client']),
    );
    return null;
  }
}

/* ====================================================================== */
/* M1 — Unités d'hébergement                                               */
/* ====================================================================== */

final class ImporteurUnites extends ImporteurLocal {
  ImporteurUnites(super.base, {required this.dao});

  final ParcDao dao;

  @override
  String get cle => 'm1-hebergement';
  @override
  ModuleTatacora get module => ModuleTatacora.m1Hebergement;
  @override
  String get nom => "Unités d'hébergement";
  @override
  String get description =>
      'Bungalows, chambres et tentes du gîte. Chaque unité rejoint une '
      'catégorie existante, qui porte le tarif ; une unité importée entre au '
      'parc libre.';
  @override
  String get identifiant => 'numero';
  @override
  List<ColonneImport> get colonnes => const [
    ColonneImport(
      champ: 'numero',
      libelle: "Numéro d'unité",
      requis: true,
      exemple: 'BNG-03',
    ),
    ColonneImport(
      champ: 'categorie',
      libelle: 'Catégorie',
      requis: true,
      type: TypeColonneImport.reference,
      exemple: 'Bungalow',
    ),
  ];

  @override
  Future<Set<String>> existants() async => ImporteurLocal.normaliser(
    (await base.select(base.unitesHebergementLocal).get()).map((u) => u.numero),
  );

  @override
  Future<Map<String, Map<String, String>>> references() async => {
    'categorie': {
      for (final c in await base.select(base.categoriesHebergementLocal).get())
        c.libelle: c.id,
    },
  };

  @override
  Future<String?> ecrire(LigneImport ligne) async {
    await dao.creerUnite(
      numero: ligne.exiger('numero'),
      categorieId: ligne.exiger('categorie'),
    );
    return null;
  }
}

/* ====================================================================== */
/* M5 — Carte du bar                                                       */
/* ====================================================================== */

final class ImporteurCarteBar extends ImporteurLocal {
  ImporteurCarteBar(super.base, {required this.api});

  final BoissonsApi api;

  @override
  String get cle => 'm5-bar';
  @override
  ModuleTatacora get module => ModuleTatacora.m5Bar;
  @override
  String get nom => 'Carte du bar';
  @override
  String get description =>
      'Boissons proposées au bar et au point de vente. Chaque boisson se '
      'rattache à un article de stock existant.';
  @override
  String get identifiant => 'libelle';
  @override
  List<ColonneImport> get colonnes => [
    const ColonneImport(
      champ: 'libelle',
      libelle: 'Nom de la boisson',
      requis: true,
      exemple: 'Bière Béninoise 66 cl',
    ),
    ColonneImport(
      champ: 'categorie',
      libelle: 'Catégorie',
      requis: true,
      type: TypeColonneImport.liste,
      valeurs: [for (final c in CategorieBoisson.values) c.code],
      exemple: 'locale',
    ),
    const ColonneImport(
      champ: 'prix_vente',
      libelle: 'Prix de vente (FCFA)',
      requis: true,
      type: TypeColonneImport.montant,
      exemple: '1200',
    ),
    const ColonneImport(
      champ: 'article',
      libelle: 'Article de stock lié',
      requis: true,
      type: TypeColonneImport.reference,
      exemple: 'Béninoise 66 cl',
    ),
  ];

  @override
  Future<Set<String>> existants() async => ImporteurLocal.normaliser(
    (await base.select(base.cartesBoissonLocal).get()).map((b) => b.libelle),
  );

  @override
  Future<Map<String, Map<String, String>>> references() async => {
    'article': {
      for (final a in await base.select(base.articlesLocal).get())
        a.libelle: a.id,
    },
  };

  @override
  Future<String?> ecrire(LigneImport ligne) async {
    final r = await api.enregistrer(
      SaisieBoisson(
        libelle: ligne.exiger('libelle'),
        categorie: CategorieBoisson.depuisCode(ligne['categorie'])!,
        prixVente: '${ImporteurLocal.francs(ligne.exiger('prix_vente'))}',
        articleId: ligne.exiger('article'),
      ),
    );
    switch (r) {
      case BarRecu():
        return null;
      case BarRefuse(:final motif, :final erreurs):
        throw RefusLigneImport(erreurs.isEmpty ? motif : erreurs.values.first);
      case BarInjoignable():
        throw const RefusLigneImport(
          "La boisson n'a pas pu être écrite sur ce poste.",
        );
    }
  }
}

/* ====================================================================== */
/* M4 — Carte du restaurant                                                */
/* ====================================================================== */

final class ImporteurCarteRestaurant extends ImporteurLocal {
  ImporteurCarteRestaurant(
    super.base, {
    required this.dao,
    required this.auteurId,
  });

  final RestaurantDao dao;
  final String? Function() auteurId;

  @override
  String get cle => 'm4-restaurant';
  @override
  ModuleTatacora get module => ModuleTatacora.m4Restaurant;
  @override
  String get nom => 'Carte du restaurant';
  @override
  String get description =>
      'Plats proposés au restaurant. Chaque plat se rattache à un menu et à '
      'une fiche recette existants. La catégorie du plat est celle de son menu.';
  @override
  String get identifiant => 'libelle';
  @override
  List<ColonneImport> get colonnes => const [
    ColonneImport(
      champ: 'libelle',
      libelle: 'Nom du plat',
      requis: true,
      exemple: 'Poulet DG',
    ),
    ColonneImport(
      champ: 'prix_vente',
      libelle: 'Prix de vente (FCFA)',
      requis: true,
      type: TypeColonneImport.montant,
      exemple: '4500',
    ),
    ColonneImport(
      champ: 'menu',
      libelle: 'Menu',
      requis: true,
      type: TypeColonneImport.reference,
      exemple: 'Menu local',
    ),
    ColonneImport(
      champ: 'recette',
      libelle: 'Fiche recette',
      requis: true,
      type: TypeColonneImport.reference,
      exemple: 'Poulet DG',
    ),
  ];

  @override
  Future<Set<String>> existants() async => ImporteurLocal.normaliser(
    (await base.select(base.platsLocal).get()).map((p) => p.libelle),
  );

  @override
  Future<Map<String, Map<String, String>>> references() async => {
    'menu': {
      for (final m in await base.select(base.menusLocal).get()) m.libelle: m.id,
    },
    'recette': {
      for (final r in await base.select(base.recettesLocal).get())
        r.libelle: r.id,
    },
  };

  @override
  Future<String?> ecrire(LigneImport ligne) async {
    await dao.enregistrerPlat(
      SaisiePlat(
        libelle: ligne.exiger('libelle'),
        menuId: ligne.exiger('menu'),
        recetteId: ligne.exiger('recette'),
        prixVente: '${ImporteurLocal.francs(ligne.exiger('prix_vente'))}',
      ),
      modification: false,
      auteurId: auteurId(),
    );
    return null;
  }
}

/* ====================================================================== */
/* M7 — Fournisseurs                                                       */
/* ====================================================================== */

final class ImporteurFournisseurs extends ImporteurLocal {
  ImporteurFournisseurs(
    super.base, {
    required this.dao,
    required this.auteurId,
  });

  final AchatsDao dao;
  final String? Function() auteurId;
  static const _uuid = Uuid();

  @override
  String get cle => 'm7-achats';
  @override
  ModuleTatacora get module => ModuleTatacora.m7Achats;
  @override
  String get nom => 'Fournisseurs';
  @override
  String get description => 'Fournisseurs référencés pour les commandes.';
  @override
  String get identifiant => 'raison_sociale';
  @override
  List<ColonneImport> get colonnes => [
    const ColonneImport(
      champ: 'raison_sociale',
      libelle: 'Raison sociale',
      requis: true,
      exemple: 'Bénin Boissons Distribution',
    ),
    const ColonneImport(
      champ: 'contact',
      libelle: 'Contact',
      requis: false,
      exemple: '+229 01 21 30 40 50',
    ),
    const ColonneImport(
      champ: 'categorie',
      libelle: 'Catégorie',
      requis: false,
      exemple: 'Boissons',
    ),
    const ColonneImport(
      champ: 'conditions_paiement',
      libelle: 'Conditions de paiement',
      requis: false,
      exemple: '30 jours',
    ),
    ColonneImport(
      champ: 'evaluation',
      libelle: 'Évaluation',
      requis: false,
      type: TypeColonneImport.liste,
      valeurs: [for (final e in EvaluationFournisseur.values) e.code],
      exemple: 'bon',
    ),
  ];

  @override
  Future<Set<String>> existants() async => ImporteurLocal.normaliser(
    (await base.select(base.fournisseursLocal).get()).map(
      (f) => f.raisonSociale,
    ),
  );

  @override
  Future<String?> ecrire(LigneImport ligne) async {
    await dao.creerFournisseur(
      SaisieFournisseur(
        id: _uuid.v4(),
        raisonSociale: ligne.exiger('raison_sociale'),
        contact: ligne['contact'],
        categorie: ligne['categorie'],
        conditionsPaiement: ligne['conditions_paiement'],
        evaluationCode: ligne['evaluation'],
      ),
      auteurId: auteurId(),
    );
    return null;
  }
}

/* ====================================================================== */
/* M8 — Parc de véhicules                                                  */
/* ====================================================================== */

final class ImporteurVehicules extends ImporteurLocal {
  ImporteurVehicules(super.base, {required this.dao});

  final VehiculeDao dao;

  @override
  String get cle => 'm8-vehicules';
  @override
  ModuleTatacora get module => ModuleTatacora.m8Vehicules;
  @override
  String get nom => 'Parc de véhicules';
  @override
  String get description =>
      'Véhicules du parc proposés à la location. Un véhicule importé entre au '
      'parc disponible.';
  @override
  String get identifiant => 'immatriculation';
  @override
  List<ColonneImport> get colonnes => [
    const ColonneImport(
      champ: 'immatriculation',
      libelle: 'Immatriculation',
      requis: true,
      exemple: 'AB 1234 RB',
    ),
    ColonneImport(
      champ: 'categorie',
      libelle: 'Catégorie',
      requis: true,
      type: TypeColonneImport.liste,
      valeurs: [for (final c in CategorieVehicule.values) c.code],
      exemple: '4x4',
    ),
    const ColonneImport(
      champ: 'tarif_jour',
      libelle: 'Tarif journalier (FCFA)',
      requis: true,
      type: TypeColonneImport.montant,
      exemple: '45000',
    ),
  ];

  @override
  Future<Set<String>> existants() async => ImporteurLocal.normaliser(
    (await base.select(base.vehiculesLocal).get()).map(
      (v) => v.immatriculation,
    ),
  );

  @override
  Future<String?> ecrire(LigneImport ligne) async {
    await dao.enregistrerVehicule(
      immatriculation: ligne.exiger('immatriculation'),
      categorie: CategorieVehicule.depuisCode(ligne['categorie'])!,
      tarifJour: ImporteurLocal.francs(ligne.exiger('tarif_jour')),
    );
    return null;
  }
}

/* ====================================================================== */
/* M9 — Circuits touristiques                                              */
/* ====================================================================== */

final class ImporteurCircuits extends ImporteurLocal {
  ImporteurCircuits(super.base, {required this.dao});

  final TourismeDao dao;

  @override
  String get cle => 'm9-tourisme';
  @override
  ModuleTatacora get module => ModuleTatacora.m9Tourisme;
  @override
  String get nom => 'Circuits touristiques';
  @override
  String get description => 'Circuits et excursions proposés aux clients.';
  @override
  String get identifiant => 'nom';
  @override
  List<ColonneImport> get colonnes => const [
    ColonneImport(
      champ: 'nom',
      libelle: 'Nom du circuit',
      requis: true,
      exemple: 'Circuit Parc National de la Pendjari',
    ),
    ColonneImport(
      champ: 'theme',
      libelle: 'Thème',
      requis: true,
      exemple: 'nature',
    ),
    ColonneImport(
      champ: 'zone',
      libelle: 'Zone',
      requis: true,
      exemple: 'Atacora',
    ),
    ColonneImport(
      champ: 'duree',
      libelle: 'Durée',
      requis: true,
      exemple: '2 jours',
    ),
    ColonneImport(
      champ: 'prix',
      libelle: 'Prix par participant (FCFA)',
      requis: true,
      type: TypeColonneImport.montant,
      exemple: '125000',
    ),
    ColonneImport(
      champ: 'capacite_max',
      libelle: 'Capacité maximale',
      requis: true,
      type: TypeColonneImport.nombre,
      exemple: '12',
    ),
  ];

  @override
  Future<Set<String>> existants() async => ImporteurLocal.normaliser(
    (await base.select(base.circuitsLocal).get()).map((c) => c.nom),
  );

  @override
  Future<String?> ecrire(LigneImport ligne) async {
    final capacite = int.tryParse(ligne.exiger('capacite_max'));
    if (capacite == null) {
      throw RefusLigneImport(
        'capacité « ${ligne.exiger('capacite_max')} » : un nombre entier est '
        'attendu',
      );
    }
    await dao.enregistrerCircuit(
      nom: ligne.exiger('nom'),
      theme: ligne.exiger('theme'),
      zone: ligne.exiger('zone'),
      duree: ligne['duree'],
      prix: ImporteurLocal.francs(ligne.exiger('prix')),
      capaciteMax: capacite,
    );
    return null;
  }
}

/* ====================================================================== */
/* Le moteur : contrôle (simulé) puis import (une transaction)             */
/* ====================================================================== */

/// L'issue d'un import.
sealed class ResultatImport {
  const ResultatImport();
}

/// Tout le lot est écrit.
final class ImportFait extends ResultatImport {
  const ImportFait({required this.importees, required this.ignorees});

  final int importees;
  final int ignorees;
}

/// Le fichier n'est plus conforme (la base a pu bouger depuis le contrôle) :
/// le rapport frais remplace l'ancien, rien n'est écrit.
final class ImportNonConforme extends ResultatImport {
  const ImportNonConforme(this.rapport);

  final RapportImport rapport;
}

/// Un module a refusé une ligne pendant l'écriture : TOUT est annulé.
final class ImportAnnule extends ResultatImport {
  const ImportAnnule(this.message);

  final String message;
}

/// L'annulation volontaire de la transaction de simulation.
final class _Simulation implements Exception {
  const _Simulation();
}

final class MoteurImportLocal {
  const MoteurImportLocal(this.base);

  final AppDatabase base;

  /// Lit [octets] (UTF-8) et contrôle le fichier, puis SIMULE l'écriture des
  /// lignes valides dans une transaction ANNULÉE : rien n'est écrit, mais les
  /// refus des DAO figurent au rapport — « Rien n'est importé à ce stade ».
  Future<RapportImport> controler(
    ImporteurLocal importeur,
    List<int> octets,
  ) async {
    final String contenu;
    try {
      contenu = utf8.decode(octets);
    } on FormatException {
      return RapportImport.refusGlobal(TextesControleImport.fichierIllisible);
    }

    await importeur.preparer();
    final rapport = controlerImport(
      colonnes: importeur.colonnes,
      identifiant: importeur.identifiant,
      tableau: analyserCsvImport(contenu),
      existants: await importeur.existants(),
      references: await importeur.references(),
    );
    if (!rapport.ok || rapport.lignes.isEmpty) return rapport;

    final libelleCle = importeur.colonnes
        .firstWhere((c) => c.champ == importeur.identifiant)
        .libelle;
    final refus = <AnomalieImport>[];
    final reserves = <AnomalieImport>[];
    try {
      await base.transaction(() async {
        for (final ligne in rapport.lignes) {
          try {
            final reserve = await importeur.ecrire(ligne);
            if (reserve != null) {
              reserves.add(
                AnomalieImport(
                  ligne: ligne.numero,
                  colonne: libelleCle,
                  message: reserve,
                ),
              );
            }
          } on Object catch (e) {
            refus.add(
              AnomalieImport(
                ligne: ligne.numero,
                colonne: libelleCle,
                message: TextesControleImport.refusModule(motifRefusImport(e)),
              ),
            );
          }
        }
        // Rien de la simulation ne doit survivre : la transaction est
        // ANNULÉE, toujours.
        throw const _Simulation();
      });
    } on _Simulation {
      // Attendu.
    }
    return rapport.avecSimulation(refus: refus, reserves: reserves);
  }

  /// RECONTRÔLE le fichier, puis écrit toutes ses lignes dans UNE
  /// transaction — une ligne refusée, et rien n'entre en base.
  Future<ResultatImport> appliquer(
    ImporteurLocal importeur,
    List<int> octets,
  ) async {
    final rapport = await controler(importeur, octets);
    if (!rapport.ok) return ImportNonConforme(rapport);
    if (rapport.lignes.isEmpty) {
      return rapport.ignorees > 0
          ? ImportFait(importees: 0, ignorees: rapport.ignorees)
          : const ImportAnnule(TextesControleImport.aucuneLigne);
    }

    try {
      await base.transaction(() async {
        for (final ligne in rapport.lignes) {
          try {
            await importeur.ecrire(ligne);
          } on Object catch (e) {
            throw RefusLigneImport(
              TextesControleImport.refusService(
                ligne.numero,
                ligne[importeur.identifiant] ?? '?',
                motifRefusImport(e),
              ),
            );
          }
        }
      });
    } on RefusLigneImport catch (e) {
      return ImportAnnule(e.message);
    }
    return ImportFait(
      importees: rapport.lignes.length,
      ignorees: rapport.ignorees,
    );
  }
}
