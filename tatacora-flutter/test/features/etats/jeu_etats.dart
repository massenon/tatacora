import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/achats/data/achats_dao.dart';
import 'package:tatacora_flutter/features/caisse/data/sessions_caisse_dao.dart';
import 'package:tatacora_flutter/features/caisse/domain/entities/session_caisse.dart'
    show pointDeCaisseDuComptoir;
import 'package:tatacora_flutter/features/achats/domain/entities/commande_achat.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/fournisseur.dart';
import 'package:tatacora_flutter/features/depenses/domain/categories_depense.dart';
import 'package:tatacora_flutter/features/depenses/domain/entities/depense.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_repository_local.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/article_vendable.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';
import 'package:tatacora_flutter/features/rh/data/employe_dao.dart';
import 'package:tatacora_flutter/features/rh/data/paie_dao.dart';
import 'package:tatacora_flutter/features/rh/domain/entities/bulletin_paie.dart';
import 'package:tatacora_flutter/features/rh/domain/entities/employe.dart';
import 'package:tatacora_flutter/features/rh/domain/services/bulletin_paie_service.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';
import 'package:tatacora_flutter/features/tourisme/data/tourisme_dao.dart';
import 'package:tatacora_flutter/features/vehicules/data/vehicule_dao.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/contrat_location.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/vehicule.dart';

import '../comptabilite/support/outils_comptabilite.dart'
    show baseInstalleeSur, moteurSur;
import '../depenses/support/outils_depenses.dart';
import '../facturation/support/outils_encaissement.dart'
    show caissierEssai, ouvrirLaCaisseDuComptoir;
import '../pos/support/outils_ventes.dart' show cloturerSansPiece;

/// Ce que le jeu a écrit, pour que les tests relisent les valeurs EXACTES
/// plutôt que de les recopier de mémoire.
final class JeuEtats {
  JeuEtats({
    required this.panierIds,
    required this.employes,
    required this.bulletinKora,
  });

  /// Les identifiants de paniers, par nom : l'identifiant abrégé est la
  /// colonne « N° » de l'état des ventes.
  final Map<String, String> panierIds;

  /// Les salariés par nom de famille.
  final Map<String, Employe> employes;

  /// Le seul bulletin établi, relu de la base.
  final BulletinPaie bulletinKora;
}

/// Le jeu de données des douze états : tous les modules sont écrits par leurs
/// VRAIS dépôts, jamais par une insertion de test dans une table de domaine.
///
/// ## Horloge
///
/// [aujourdhui] est le « maintenant » du poste : 10/10/2026 14:30.
///
/// ## Ce que le jeu contient, état par état
///
/// - **Réservations** : r1 (confirmée, 1→5/10), r2 (en attente, 10→13/10), r3
///   (annulée, exclue), r4 (confirmée, 8→12/10, acompte 20 000), r5 (reprise
///   d'avant le tarif figé : tarif 0, 1→3/09).
/// - **Stock** : Riz (10 sacs à 1 250,50 F), Sel (4 kg SANS coût), Huile (2 L
///   sous son seuil, 500 F), Farine (EN RUPTURE : entrée puis sortie de 3 kg),
///   Pain (achat JOURNALIER, non suivi).
/// - **Ventes** : cinq clôturées (dont une SANS mode de règlement et une
///   portée sur la note de chambre), une annulée, un panier encore ouvert.
/// - **Dépenses** : trois, dont une en août.
/// - **Parc** : quatre véhicules (un en entretien) ; **locations** : deux.
/// - **Tourisme** : trois réservations dont une annulée.
/// - **Achats** : deux commandes d'un même fournisseur.
/// - **Personnel** : cinq salariés de statuts différents (deux actifs, trois
///   qui ne le sont pas : l'écart est voulu, un compte symétrique ne
///   distinguerait pas « actif » de « non actif »), un bulletin.
Future<JeuEtats> semerJeuEtats(AppDatabase db, DateTime aujourdhui) async {
  // Une vente au comptant exige une caisse ouverte (lot 5, D221 option a) :
  // l'ouvrir AVANT de semer, comme le caissier du matin.
  await ouvrirLaCaisseDuComptoir(db);
  // Et une vente passe sa PIÈCE comptable dans la même transaction : le
  // référentiel est installé avant la première vente (idempotent, la suite le
  // réinstalle sans rien changer).
  await baseInstalleeSur(db, aujourdhui);
  await db
      .into(db.utilisateursLocal)
      .insert(
        UtilisateursLocalCompanion.insert(
          id: 'u-essai',
          login: 'essai',
          nom: 'Essai',
          role: 'administrateur',
          droitsJson: '{}',
          sel: 's',
          empreinte: 'e',
          iterations: 1,
          dateCreation: DateTime(2026, 10, 1),
          dateMotDePasse: DateTime(2026, 10, 1),
        ),
      );

  // --- Parc d'hébergement : 2 unités louables + 1 hors service ---------
  await db
      .into(db.categoriesHebergementLocal)
      .insert(
        CategoriesHebergementLocalCompanion.insert(
          id: 'cat-1',
          libelle: 'Bungalow',
          capaciteMax: 2,
          tarifBase: 28000,
        ),
      );
  for (final (id, numero, statut) in const [
    ('u-1', 'BNG-01', 'libre'),
    ('u-2', 'BNG-02', 'libre'),
    ('u-3', 'BNG-03', 'hors_service'),
  ]) {
    await db
        .into(db.unitesHebergementLocal)
        .insert(
          UnitesHebergementLocalCompanion.insert(
            id: id,
            categorieId: 'cat-1',
            numero: numero,
            statut: statut,
          ),
        );
  }
  for (final (id, nom, prenom) in const [
    ('cli-1', 'KORA', 'Jean'),
    ('cli-2', 'DOSSOU', 'Awa'),
  ]) {
    await db
        .into(db.clientsLocal)
        .insert(
          ClientsLocalCompanion.insert(
            id: id,
            nom: nom,
            prenom: Value(prenom),
            telephone: '+229 01 00 00 00 0${id.substring(4)}',
            typeClient: 'particulier',
          ),
        );
  }

  // --- Réservations -------------------------------------------------------
  final depot = ReservationRepositoryLocal(ReservationDao(db));
  Future<void> reserver(
    String id,
    String unite,
    StatutReservation statut,
    DateTime arrivee,
    DateTime depart,
    DateTime creeeLe, {
    String client = 'cli-1',
    String nom = 'KORA Jean',
    int tarif = 28000,
    int acompte = 0,
  }) => depot.enregistrer(
    Reservation(
      id: id,
      reference: 'LOC-$id',
      clientId: client,
      clientNom: nom,
      uniteId: unite,
      periode: PeriodeSejour(arrivee: arrivee, depart: depart),
      tarifNuit: tarif,
      statut: statut,
      statutSynchronisation: StatutSynchronisation.local,
      creeeLe: creeeLe,
      acompte: acompte,
    ),
  );
  await reserver(
    'r1',
    'u-1',
    StatutReservation.confirmee,
    DateTime(2026, 10, 1),
    DateTime(2026, 10, 5),
    DateTime(2026, 9, 25),
  );
  await reserver(
    'r2',
    'u-1',
    StatutReservation.enAttente,
    DateTime(2026, 10, 10),
    DateTime(2026, 10, 13),
    DateTime(2026, 10, 8),
  );
  await reserver(
    'r3',
    'u-1',
    StatutReservation.annulee,
    DateTime(2026, 10, 6),
    DateTime(2026, 10, 8),
    DateTime(2026, 10, 1),
  );
  await reserver(
    'r4',
    'u-2',
    StatutReservation.confirmee,
    DateTime(2026, 10, 8),
    DateTime(2026, 10, 12),
    DateTime(2026, 10, 2),
    acompte: 20000,
  );
  await reserver(
    'r5',
    'u-2',
    StatutReservation.confirmee,
    DateTime(2026, 9, 1),
    DateTime(2026, 9, 3),
    DateTime(2026, 8, 20),
    client: 'cli-2',
    nom: 'DOSSOU Awa',
    tarif: 0,
  );

  // --- Personnel : 2 actifs, 1 en congé, 1 parti ---------------------------
  final employes = EmployeDao(db, maintenant: () => aujourdhui);
  await employes.installerServices();
  final paie = PaieDao(db, maintenant: () => aujourdhui);
  await paie.installerReferentielConfirme();
  final service = (await employes.services()).first;
  Future<Employe> embaucher(String nom, StatutEmploye statut) => employes.creer(
    nom: nom,
    prenom: 'X',
    poste: 'Poste',
    serviceId: service.id,
    dateEmbauche: DateTime(2024, 1, 1),
    salaireBase: 150000,
    numeroCnss: 'BJ-$nom',
    typeContrat: TypeContrat.cdi,
    statut: statut,
  );
  final kora = await embaucher('KORA', StatutEmploye.actif);
  final dossou = await embaucher('DOSSOU', StatutEmploye.actif);
  final agbo = await embaucher('AGBO', StatutEmploye.conge);
  final mensah = await embaucher('MENSAH', StatutEmploye.suspendu);
  final zinsou = await embaucher('ZINSOU', StatutEmploye.parti);
  final bulletin = await BulletinPaieService(
    paie,
    employes,
  ).etablirBulletin(kora, '2026-10');

  // --- Stock ---------------------------------------------------------------
  final stocks = StocksDao(db);
  final point = await stocks.creerPoint(libelle: 'Magasin');
  Future<void> article(
    String id,
    String libelle,
    String unite,
    int seuil, {
    SuiviArticle suivi = SuiviArticle.permanent,
    ({int centiemes, int? coutDixMilliemes})? ouverture,
  }) => stocks.creerArticle(
    id: id,
    libelle: libelle,
    categorie: null,
    uniteMesure: unite,
    seuilCentiemes: seuil,
    suivi: suivi,
    pointStockageId: point.id,
    auteurId: 'u-essai',
    ouverture: ouverture,
  );
  // Riz : 10 sacs à 1 250,50 F = 12 505 F.
  await article(
    'riz',
    'Riz',
    'sac',
    500,
    ouverture: (centiemes: 1000, coutDixMilliemes: 12505000),
  );
  // Sel : 4 kg, JAMAIS valorisé -> sa valeur est INCONNUE, pas nulle.
  await article(
    'sel',
    'Sel',
    'sac',
    100,
    ouverture: (centiemes: 400, coutDixMilliemes: null),
  );
  // Huile : 2 L pour un seuil de 6 -> sous le seuil ; 2 x 500 F = 1 000 F.
  await article(
    'huile',
    'Huile',
    'L',
    600,
    ouverture: (centiemes: 200, coutDixMilliemes: 5000000),
  );
  // Farine : 3 kg entrés puis 3 kg sortis -> EN RUPTURE (stock 0), seuil 1.
  await article(
    'farine',
    'Farine',
    'kg',
    100,
    ouverture: (centiemes: 300, coutDixMilliemes: 8000000),
  );
  await stocks.ajouterMouvement(
    articleId: 'farine',
    pointId: point.id,
    type: TypeMouvement.sortie,
    centiemes: 300,
    motif: 'Cuisine',
    auteurId: 'u-essai',
  );
  // Pain : achat JOURNALIER, sans quantité suivie.
  await article('pain', 'Pain', 'unité', 0, suivi: SuiviArticle.journalier);

  // --- Ventes du bar -------------------------------------------------------
  await db
      .into(db.cartesBoissonLocal)
      .insert(
        CartesBoissonLocalCompanion.insert(
          id: 'bsn-33',
          articleId: 'art-bsn',
          libelle: 'Béninoise 33cl',
          categorie: 'locale',
          prixVente: 1000,
        ),
      );
  const biere = ArticleVendable(
    reference: ReferenceCatalogue(module: ModuleVendable.m5Bar, code: 'bsn-33'),
    libelle: 'Béninoise 33cl',
    prix: 1000,
    categorie: 'locale',
  );
  final paniersIds = <String, String>{};
  Future<void> vendre(
    String nom,
    DateTime quand,
    int bouteilles, {
    String? mode = 'especes',
    String? client,
    bool annuler = false,
    bool laisserOuvert = false,
  }) async {
    final paniers = PanierDao(
      db,
      maintenant: () => quand,
      moteur: () async => moteurSur(db, maintenant: () => quand),
    );
    var p = await paniers.ouvrir(
      typeVente: TypeVente.comptant,
      pointVente: 'Bar principal',
      clientNom: client,
    );
    for (var i = 0; i < bouteilles; i++) {
      p = await paniers.ajouterLigne(p.id, biere);
    }
    paniersIds[nom] = p.id;
    if (laisserOuvert) return;
    if (annuler) {
      await paniers.annuler(p.id, 'Service abandonné');
      return;
    }
    // Une vente D'AUJOURD'HUI passe sa pièce par la clôture. Un mode « non
    // renseigné » et une note de chambre au COMPTOIR, la clôture d'aujourd'hui
    // les refuse : ce sont des ventes HISTORIQUES (d'avant le lot 6), écrites
    // sans pièce — l'état doit pouvoir les montrer, c'est précisément son
    // objet.
    if (mode == null || mode == 'note_chambre') {
      final session = await SessionsCaisseDao(
        db,
      ).sessionOuverte(pointDeCaisseDuComptoir);
      await cloturerSansPiece(
        db,
        p.id,
        mode: mode,
        quand: quand,
        sessionId: session?.id,
      );
      return;
    }
    await paniers.cloturer(p.id, modePaiement: mode, auteurId: caissierEssai);
  }

  await vendre('v1', DateTime(2026, 10, 5, 19), 2);
  await vendre('v2', DateTime(2026, 10, 6, 20), 1);
  await vendre('v3', DateTime(2026, 8, 3, 20), 5);
  await vendre('v5', DateTime(2026, 10, 7, 21), 1, mode: null);
  await vendre(
    'v6',
    DateTime(2026, 10, 8, 20),
    2,
    mode: 'note_chambre',
    client: 'KORA Jean',
  );
  await vendre('v4', DateTime(2026, 10, 9, 18), 3, annuler: true);
  await vendre('v7', DateTime(2026, 10, 10, 12), 1, laisserOuvert: true);

  // --- Dépenses ------------------------------------------------------------
  final depenses = await depenseDaoPrepare(db, aujourdhui);
  final centreDepenses = await centreDe(db, 'Restaurant');
  Future<void> depenser(DateTime jour, NatureDepense nature, int montant) =>
      depenses.enregistrer(
        dateTransaction: jour,
        tresorerie: TresorerieDepense.caisse,
        libelle: nature.libelle,
        auteurId: auteurDepense,
        centreId: centreDepenses,
        lignes: [
          SaisieLigneDepense(
            libelle: nature.libelle,
            compteCharge: '6011',
            nature: nature,
            montant: montant,
          ),
        ],
      );
  await depenser(DateTime(2026, 10, 9), NatureDepense.riz, 5000);
  await depenser(DateTime(2026, 10, 10), NatureDepense.transport, 3000);
  await depenser(DateTime(2026, 8, 1), NatureDepense.riz, 99000);

  // --- Parc de véhicules et locations --------------------------------------
  final vehicules = VehiculeDao(db);
  final voiture = await vehicules.enregistrerVehicule(
    immatriculation: 'AB-123-BJ',
    categorie: CategorieVehicule.voiture,
    tarifJour: 35000,
  );
  await vehicules.enregistrerVehicule(
    immatriculation: 'CD-456-BJ',
    categorie: CategorieVehicule.quatreQuatre,
    tarifJour: 60000,
    statut: StatutVehicule.entretien,
  );
  final moto = await vehicules.enregistrerVehicule(
    immatriculation: 'EF-789-BJ',
    categorie: CategorieVehicule.moto,
    tarifJour: 15000,
  );
  await vehicules.enregistrerVehicule(
    immatriculation: 'GH-000-BJ',
    categorie: CategorieVehicule.velo,
    tarifJour: 5000,
  );
  await vehicules.creerContrat(
    SaisieContrat(
      vehiculeId: voiture.id,
      clientId: 'cli-1',
      debut: DateTime(2026, 10, 5),
      fin: DateTime(2026, 10, 8),
      pieceIdentite: 'CNI-1',
      permisConduire: 'PC-1',
    ),
  );
  await vehicules.creerContrat(
    SaisieContrat(
      vehiculeId: moto.id,
      clientId: 'cli-2',
      debut: DateTime(2026, 10, 1),
      fin: DateTime(2026, 10, 2),
      pieceIdentite: 'CNI-2',
      permisConduire: 'PC-2',
    ),
  );

  // --- Tourisme ------------------------------------------------------------
  final tourisme = TourismeDao(db);
  final cascades = await tourisme.enregistrerCircuit(
    nom: 'Cascades de Tanougou',
    theme: 'Nature',
    zone: 'Nord',
    prix: 15000,
    capaciteMax: 10,
  );
  final pendjari = await tourisme.enregistrerCircuit(
    nom: 'Pendjari',
    theme: 'Faune',
    zone: 'Nord',
    prix: 25000,
    capaciteMax: 8,
  );
  final guide = await tourisme.enregistrerGuide(nom: 'Koffi');
  await tourisme.reserver(
    circuitId: cascades.id,
    clientId: 'cli-1',
    guideId: guide.id,
    dateCircuit: DateTime(2026, 10, 12),
    nbParticipants: 4,
  );
  await tourisme.reserver(
    circuitId: pendjari.id,
    clientId: 'cli-2',
    guideId: guide.id,
    dateCircuit: DateTime(2026, 10, 20),
    nbParticipants: 2,
  );
  final annulee = await tourisme.reserver(
    circuitId: cascades.id,
    clientId: 'cli-1',
    guideId: guide.id,
    dateCircuit: DateTime(2026, 10, 25),
    nbParticipants: 3,
  );
  await tourisme.annulerReservation(annulee.id);

  // --- Achats --------------------------------------------------------------
  final achats = AchatsDao(db, stocks: stocks);
  await achats.creerFournisseur(
    const SaisieFournisseur(
      id: 'f-1',
      raisonSociale: 'SODIS',
      contact: null,
      categorie: null,
      conditionsPaiement: null,
      evaluationCode: null,
    ),
    auteurId: 'u-essai',
  );
  Future<void> commander(
    String date,
    StatutCommande statut,
    String quantite,
    String prix,
  ) => achats.creerCommande(
    SaisieCommande(
      fournisseurId: 'f-1',
      dateCommande: date,
      statut: statut,
      lignes: [
        LigneSaisieCommande(
          articleId: 'riz',
          libelle: 'Riz',
          uniteMesure: 'sac',
          quantite: quantite,
          prixUnitaire: prix,
        ),
      ],
    ),
    auteurId: 'u-essai',
  );
  await commander('2026-10-01', StatutCommande.brouillon, '10.00', '1000.00');
  await commander('2026-10-05', StatutCommande.envoyee, '2.00', '2500.50');

  return JeuEtats(
    panierIds: paniersIds,
    employes: {
      'KORA': kora,
      'DOSSOU': dossou,
      'AGBO': agbo,
      'MENSAH': mensah,
      'ZINSOU': zinsou,
    },
    bulletinKora: bulletin,
  );
}
