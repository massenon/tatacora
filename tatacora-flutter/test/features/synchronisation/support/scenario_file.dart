import 'dart:convert';

import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/achats/data/achats_dao.dart';
import 'package:tatacora_flutter/features/achats/data/reglements_fournisseur_dao.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/bon_reception.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/commande_achat.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/fournisseur.dart';
import 'package:tatacora_flutter/features/caisse/data/sessions_caisse_dao.dart';
import 'package:tatacora_flutter/features/caisse/domain/entities/session_caisse.dart';
import 'package:tatacora_flutter/features/crm/data/client_dao.dart';
import 'package:tatacora_flutter/features/crm/domain/entities/client.dart';
import 'package:tatacora_flutter/features/depenses/domain/categories_depense.dart';
import 'package:tatacora_flutter/features/facturation/data/facture_dao.dart';
import 'package:tatacora_flutter/features/facturation/data/paiements_facture_dao.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/piece_facturation.dart';
import 'package:tatacora_flutter/features/facturation/domain/repositories/facture_repository.dart';
import 'package:tatacora_flutter/features/depenses/domain/entities/depense.dart';
import 'package:tatacora_flutter/features/hebergement/data/parc_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_repository_local.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/fiche_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/data/sejour_dao.dart';
import 'package:tatacora_flutter/features/hebergement/domain/usecases/creer_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/usecases/modifier_reservation.dart';
import 'package:tatacora_flutter/features/pos/data/catalogue_dao.dart';
import 'package:tatacora_flutter/features/pos/data/tables_pos_dao.dart';
import 'package:tatacora_flutter/features/pos/data/dto/catalogue_dto.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/article_vendable.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';
import 'package:tatacora_flutter/features/restaurant/data/restaurant_dao.dart';
import 'package:tatacora_flutter/features/restaurant/domain/entities/plat.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/tourisme/data/tourisme_dao.dart';
import 'package:tatacora_flutter/features/vehicules/data/vehicule_dao.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/contrat_location.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/vehicule.dart';
import 'package:uuid/uuid.dart';

import '../../comptabilite/support/outils_comptabilite.dart';
import '../../depenses/support/outils_depenses.dart';
import '../../pos/support/outils_ventes.dart';

/// Le jour du scénario : la comptabilité du poste est installée à cette date,
/// et l'exercice 2026 est ouvert des deux côtés.
final DateTime jourScenario = DateTime(2026, 10, 12, 10);

/// Les identifiants posés par le scénario, pour les assertions.
final class ScenarioFile {
  ScenarioFile();

  late String point;
  late String article;
  late String riz;
  late String boisson;
  late String menu;
  late String recette;
  late String plat;
  late String categorie;
  late String unite;
  late String client;
  late String reservation;
  late String fournisseur;
  late String commande;
  late String bon;
  late String session;
  late String vente;
  late String depense;
  late String circuit;
  late String guide;
  late String reservationTour;
  late String sejour;
  late String reservationAnnulee;
  late String tableR2;
  late String reglement;
  late String vehicule;
  late String contrat;
  late String venteSejour;
  late String facture;
  late String paiement;
  late String sessionDepart;
}

/// Une journée complète du poste, PAR SES VRAIS ÉCRIVAINS — chacun dépose son
/// document dans la file d'envoi. Rien n'est écrit à la main dans la file.
///
/// Les identifiants sont des UUID : le serveur valide `entite_id` et chaque
/// clé citée comme `uuid`.
Future<ScenarioFile> jouerJourneeComplete(AppDatabase db) async {
  final s = ScenarioFile();
  final h = jourScenario;
  DateTime horloge() => h;
  const uuid = Uuid();
  await avecComptabilite(db, maintenant: h);

  // M6 : un point, deux articles ; le premier est MODIFIÉ (seuil, catégorie).
  final stocks = StocksDao(db, maintenant: horloge);
  s.point = (await stocks.creerPoint(
    libelle: 'Bar F1',
    type: TypePoint.bar,
    id: uuid.v4(),
  )).id;
  // La cuisine : le serveur impute la sortie de stock d'un plat vendu au
  // point de type « cuisine », et REFUSE la vente sans lui.
  await stocks.creerPoint(
    libelle: 'Cuisine F1',
    type: TypePoint.cuisine,
    id: uuid.v4(),
  );
  s.article = uuid.v4();
  await stocks.creerArticle(
    id: s.article,
    libelle: 'Bière F1 65cl',
    categorie: null,
    uniteMesure: 'bouteille',
    seuilCentiemes: 500,
    suivi: SuiviArticle.permanent,
    pointStockageId: s.point,
    auteurId: auteurEssai,
  );
  await stocks.modifierArticle(
    id: s.article,
    libelle: 'Bière F1 65cl',
    categorie: 'Boissons',
    uniteMesure: 'bouteille',
    seuilCentiemes: 1250,
    suivi: SuiviArticle.permanent,
    pointStockageId: s.point,
  );
  s.riz = uuid.v4();
  await stocks.creerArticle(
    id: s.riz,
    libelle: 'Riz F1',
    // Sans catégorie : le poste l'admet, le serveur l'exige — la valeur
    // documentée `categorieArticleNonRenseignee` part à sa place.
    categorie: null,
    uniteMesure: 'kg',
    seuilCentiemes: 200,
    suivi: SuiviArticle.permanent,
    pointStockageId: s.point,
    auteurId: auteurEssai,
  );

  // M5 : une boisson, puis son prix modifié.
  final catalogue = CatalogueDao(db);
  s.boisson = uuid.v4();
  BoissonDistante boisson(double prix) => BoissonDistante(
    id: s.boisson,
    articleId: s.article,
    libelle: 'Bière F1 65cl',
    categorie: 'locale',
    prixVente: prix,
    stockDisponible: null,
  );
  await catalogue.enregistrerBoisson(boisson(1000));
  await catalogue.enregistrerBoisson(boisson(1100));

  // M4 : menu, fiche (composition en millièmes), plat, puis son prix modifié.
  final resto = RestaurantDao(db, stocks: stocks, maintenant: horloge);
  s.menu = (await resto.enregistrerMenu(
    const SaisieMenu(libelle: 'Carte F1', type: 'local'),
    auteurId: auteurEssai,
  )).id;
  s.recette = (await resto.enregistrerRecette(
    SaisieFiche(
      libelle: 'Riz sauce F1',
      lignes: [LigneSaisieComposition(articleId: s.riz, quantite: '0,25')],
    ),
    auteurId: auteurEssai,
  )).id;
  s.plat = (await resto.enregistrerPlat(
    SaisiePlat(
      libelle: 'Riz sauce F1',
      menuId: s.menu,
      recetteId: s.recette,
      prixVente: '2500',
    ),
    modification: false,
    auteurId: auteurEssai,
  )).id;
  await resto.enregistrerPlat(
    SaisiePlat(
      id: s.plat,
      libelle: 'Riz sauce F1',
      menuId: s.menu,
      recetteId: s.recette,
      prixVente: '2700',
    ),
    modification: true,
    auteurId: auteurEssai,
  );

  // M1 : catégorie, unité modifiée, archivée puis réintégrée.
  final parc = ParcDao(db, maintenant: horloge);
  s.categorie = (await parc.creerCategorie(
    libelle: 'Bungalow F1',
    capaciteMax: 2,
    tarifBase: 28000,
  )).id;
  s.unite = await parc.creerUnite(numero: 'BNG-F1', categorieId: s.categorie);
  await parc.modifierUnite(
    s.unite,
    numero: 'BNG-F1A',
    categorieId: s.categorie,
  );
  await parc.archiver(s.unite);
  await parc.restaurer(s.unite);

  // M3 puis M1 : le client, et sa réservation avec acompte en espèces.
  s.client = (await ClientDao(db).creer(
    nom: 'KORA F1',
    telephone: '97000001',
    type: TypeClientReferentiel.particulier,
  )).id;
  final depot = ReservationRepositoryLocal(
    ReservationDao(
      db,
      maintenant: horloge,
      moteur: () async => moteurSur(db, maintenant: horloge),
    ),
  );
  final unite = (await depot.unites()).firstWhere((u) => u.id == s.unite);
  s.reservation = (await CreerReservation(depot, maintenant: horloge)(
    unite: unite,
    clientId: s.client,
    clientNom: 'KORA F1',
    periode: PeriodeSejour(
      arrivee: DateTime(2026, 10, 20),
      depart: DateTime(2026, 10, 22),
    ),
    acompte: 10000,
    modePaiement: ModePaiementReservation.especes,
    auteurId: auteurEssai,
  )).id;

  // Lot F6 : une seconde réservation, DÉPLACÉE de deux jours, puis ANNULÉE
  // avec ses conditions (taux 20 %, la moitié de l'acompte rendue).
  final seconde = await CreerReservation(depot, maintenant: horloge)(
    unite: unite,
    clientId: s.client,
    clientNom: 'KORA F1',
    periode: PeriodeSejour(
      arrivee: DateTime(2026, 10, 25),
      depart: DateTime(2026, 10, 27),
    ),
    acompte: 8000,
    modePaiement: ModePaiementReservation.especes,
    auteurId: auteurEssai,
  );
  s.reservationAnnulee = seconde.id;
  await ModifierReservation(depot)(
    existante: (await depot.parId(seconde.id))!,
    unite: unite,
    clientNom: 'KORA F1',
    periode: PeriodeSejour(
      arrivee: DateTime(2026, 10, 27),
      depart: DateTime(2026, 10, 29),
    ),
    acompte: 8000,
    modePaiement: ModePaiementReservation.especes,
  );
  await ReservationDao(
    db,
    maintenant: horloge,
    moteur: () async => moteurSur(db, maintenant: horloge),
  ).annulerAvecConditions(
    seconde.id,
    tauxSaisi: '20',
    modeRemboursement: 'pourcentage',
    valeurRemboursement: '50',
    auteurId: auteurEssai,
  );

  // M7 : fournisseur modifié, commande envoyée, réception totale.
  await db
      .into(db.parametresSystemeLocal)
      .insertOnConflictUpdate(
        ParametresSystemeLocalCompanion.insert(
          cle: AchatsDao.cleTolerance,
          valeur: '5',
          modifieLe: h,
        ),
      );
  final achats = AchatsDao(db, stocks: stocks, maintenant: horloge);
  s.fournisseur = uuid.v4();
  SaisieFournisseur fiche(String? contact) => SaisieFournisseur(
    id: s.fournisseur,
    raisonSociale: 'Brasserie F1',
    contact: contact,
    categorie: 'Boissons',
    conditionsPaiement: '30 jours',
    evaluationCode: 'bon',
  );
  await achats.creerFournisseur(fiche(null), auteurId: auteurEssai);
  await achats.modifierFournisseur(fiche('97000002'), auteurId: auteurEssai);
  s.commande = (await achats.creerCommande(
    SaisieCommande(
      fournisseurId: s.fournisseur,
      dateCommande: '2026-10-12',
      statut: StatutCommande.envoyee,
      lignes: [
        LigneSaisieCommande(
          articleId: s.article,
          libelle: 'Bière F1 65cl',
          uniteMesure: 'bouteille',
          quantite: '24',
          prixUnitaire: '650,50',
        ),
      ],
    ),
    auteurId: auteurEssai,
  )).commande.id;
  s.bon = (await achats.enregistrerReception(
    SaisieReception(
      commandeId: s.commande,
      pointStockageId: s.point,
      dateReception: '2026-10-12',
      lignes: [
        LigneSaisieReception(
          articleId: s.article,
          libelle: 'Bière F1 65cl',
          uniteMesure: 'bouteille',
          quantiteCommandee: '24',
          quantiteDejaRecue: '0',
          quantiteRecue: '24',
        ),
      ],
    ),
    auteurId: auteurEssai,
  )).id;

  // Audit de couverture : un acompte versé au fournisseur, depuis la caisse.
  s.reglement =
      (await ReglementsFournisseurDao(
            db,
            maintenant: horloge,
            moteur: () async => moteurSur(db, maintenant: horloge),
          ).reglerParLeService(
            commandeId: s.commande,
            montant: '5000',
            tresorerie: 'caisse',
            auteurId: auteurEssai,
          ))
          .id;

  // M5 : la caisse s'ouvre, une vente au comptant (bière + plat), la caisse
  // se ferme le soir.
  s.session = (await SessionsCaisseDao(db, maintenant: horloge).ouvrir(
    point: PointDeVenteCaisse.bar,
    fondSaisi: '10000',
    auteurId: auteurEssai,
    peutEcrire: true,
  )).id;
  final paniers = panierDaoSur(db, horloge: h.add(const Duration(hours: 2)));
  // Lot F6 : l'addition est servie à la table R2 — la table et son
  // occupation partent, arbitrées au serveur.
  s.tableR2 = (await TablesPosDao(
    db,
  ).toutes()).firstWhere((t) => t.libelle == 'R2').id;
  var panier = await paniers.ouvrir(
    typeVente: TypeVente.comptant,
    pointVente: 'Bar',
    tableId: s.tableR2,
    espace: 'restaurant',
  );
  panier = await paniers.ajouterLigne(
    panier.id,
    ArticleVendable(
      reference: ReferenceCatalogue(
        module: ModuleVendable.m5Bar,
        code: s.boisson,
      ),
      libelle: 'Bière F1 65cl',
      prix: 1100,
    ),
    quantite: 3,
  );
  panier = await paniers.ajouterLigne(
    panier.id,
    ArticleVendable(
      reference: ReferenceCatalogue(
        module: ModuleVendable.m4Restaurant,
        code: s.plat,
      ),
      libelle: 'Riz sauce F1',
      prix: 2700,
    ),
    quantite: 1,
  );
  s.vente = (await paniers.cloturer(
    panier.id,
    modePaiement: 'especes',
    auteurId: auteurEssai,
  )).id;
  await SessionsCaisseDao(
    db,
    maintenant: () => h.add(const Duration(hours: 9)),
  ).cloturer(
    point: PointDeVenteCaisse.bar,
    constateSaisi: '16000',
    peutEcrire: true,
    especesEncaisseesCentimes: 6000 * 100,
  );

  // M10 : une dépense imputée au centre Restaurant.
  s.depense = (await depenseDaoSur(db, horloge: h).enregistrer(
    dateTransaction: DateTime(2026, 10, 12),
    tresorerie: TresorerieDepense.caisse,
    libelle: 'Marché F1',
    lignes: const [
      SaisieLigneDepense(
        libelle: 'Tomates',
        compteCharge: '6011',
        nature: NatureDepense.tomate,
        montant: 12500,
      ),
    ],
    auteurId: auteurEssai,
    centreId: await centreDe(db, 'Restaurant'),
  )).id;

  // M9 (lot F4) : un circuit sans durée, un guide, une réservation du client
  // de la journée, puis son annulation.
  final tourisme = TourismeDao(db);
  s.circuit = (await tourisme.enregistrerCircuit(
    nom: 'Chutes de Kota F4',
    theme: 'nature',
    zone: 'Atacora',
    prix: 15000,
    capaciteMax: 8,
  )).id;
  s.guide = (await tourisme.enregistrerGuide(
    nom: 'Moussa F4',
    zoneCompetence: 'Atacora',
  )).id;
  s.reservationTour = (await tourisme.reserver(
    circuitId: s.circuit,
    clientId: s.client,
    guideId: s.guide,
    dateCircuit: DateTime(2026, 10, 20),
    nbParticipants: 3,
  )).id;
  await tourisme.annulerReservation(s.reservationTour);

  // M8 (audit de couverture) : un 4x4 entre au parc, puis il est loué au
  // client de la journée trois jours.
  final flotte = VehiculeDao(db);
  s.vehicule = (await flotte.enregistrerVehicule(
    immatriculation: 'BJ-F1-4X4',
    categorie: CategorieVehicule.quatreQuatre,
    tarifJour: 30000,
  )).id;
  s.contrat = (await flotte.creerContrat(
    SaisieContrat(
      vehiculeId: s.vehicule,
      clientId: s.client,
      debut: DateTime(2026, 10, 24),
      fin: DateTime(2026, 10, 27),
      pieceIdentite: 'CNI-F1-001',
      permisConduire: 'P-F1-001',
    ),
  )).id;

  // M1 + POS hébergés (lot F5) : le client arrive, dîne sur la note de
  // chambre, et part.
  await SejourDao(
    db,
    maintenant: () => DateTime(2026, 10, 20, 14),
  ).checkin(s.reservation);
  s.sejour = (await db.select(db.sejoursLocal).getSingle()).id;
  final paniersSejour = panierDaoSur(db, horloge: DateTime(2026, 10, 22, 9));
  var note = await paniersSejour.ouvrir(
    typeVente: TypeVente.surSejour,
    pointVente: 'Restaurant',
    reservationId: s.reservation,
    dateDepartPrevue: DateTime(2026, 10, 22),
  );
  note = await paniersSejour.ajouterLigne(
    note.id,
    ArticleVendable(
      reference: ReferenceCatalogue(
        module: ModuleVendable.m4Restaurant,
        code: s.plat,
      ),
      libelle: 'Riz sauce F1',
      prix: 2700,
    ),
    quantite: 2,
  );
  s.venteSejour = (await paniersSejour.cloturer(
    note.id,
    modePaiement: 'note_chambre',
    auteurId: auteurEssai,
  )).id;
  await SejourDao(
    db,
    maintenant: () => DateTime(2026, 10, 22, 9, 30),
  ).checkout(s.reservation);

  // M2 (lots F5c, F5d) : la facture du séjour, PROVISOIRE, puis un acompte
  // encaissé dans la caisse rouverte le matin du départ.
  final depart = DateTime(2026, 10, 22, 9, 45);
  s.facture = (await FactureDao(db, maintenant: () => depart).emettre(
    BrouillonFacture(
      origine: OrigineFacture.posSejour,
      clientNom: 'KORA F1',
      clientId: s.client,
      reservationId: s.reservation,
      panierId: s.venteSejour,
      lignes: const [
        LigneBrouillon(
          module: ModuleFacturable.m1Hebergement,
          libelle: 'Hébergement — 2 nuit(s)',
          prixUnitaire: 25000,
          quantite: 2,
        ),
        LigneBrouillon(
          module: ModuleFacturable.m4Restaurant,
          libelle: 'Riz sauce F1',
          prixUnitaire: 2700,
          quantite: 2,
        ),
      ],
    ),
  )).id;
  final matin = DateTime(2026, 10, 22, 10);
  s.sessionDepart =
      (await SessionsCaisseDao(db, maintenant: () => matin).ouvrir(
        point: PointDeVenteCaisse.bar,
        fondSaisi: '5000',
        auteurId: auteurEssai,
        peutEcrire: true,
      )).id;
  s.paiement =
      (await PaiementsFactureDao(
            db,
            maintenant: () => matin,
            moteur: () async => moteurSur(db, maintenant: () => matin),
          ).encaisser(
            pieceId: s.facture,
            montant: '20000',
            mode: 'especes',
            auteurId: auteurEssai,
          ))
          .id;

  return s;
}

/// La file du poste au format du protocole `/api/v1/sync` — ce que le moteur
/// d'envoi (F2) poussera, opération par opération, dans l'ordre de `seq`.
Future<List<Map<String, Object?>>> fileAuProtocole(AppDatabase db) async => [
  for (final o in await OperationsSyncDao(db).operations())
    {
      'uuid_operation': o.uuidOperation,
      'table': o.table.nomServeur,
      'type': o.type.code,
      'entite_id': o.entiteId,
      'payload': jsonDecode(o.payload),
      'horodatage_client': o.horodatageClient,
    },
];
