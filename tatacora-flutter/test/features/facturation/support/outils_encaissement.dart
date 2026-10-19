import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/providers_comptabilite.dart';
import 'package:tatacora_flutter/features/caisse/data/sessions_caisse_dao.dart';
import 'package:tatacora_flutter/features/caisse/domain/entities/session_caisse.dart';
import 'package:tatacora_flutter/features/crm/data/client_dao.dart';
import 'package:tatacora_flutter/features/crm/domain/entities/client.dart';
import 'package:tatacora_flutter/features/facturation/data/facture_dao.dart';
import 'package:tatacora_flutter/features/facturation/data/paiements_facture_dao.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/piece_facturation.dart';
import 'package:tatacora_flutter/features/facturation/domain/repositories/facture_repository.dart';
import 'package:tatacora_flutter/features/facturation/presentation/providers_facturation.dart';
import 'package:tatacora_flutter/features/facturation/presentation/providers_paiements.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/article_vendable.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/fiche_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/service_reservation.dart';

import '../../caisse/support/outils_caisse.dart' show compterLignes;
import '../../comptabilite/support/outils_comptabilite.dart';

export '../../caisse/support/outils_caisse.dart' show compterLignes;

/// Le jour de référence des essais d'encaissement : 12/10/2026 à 10:00. L'exercice
/// 2026 est celui que l'installation ouvre ; aucun essai ne dépend de l'horloge.
final DateTime jourEncaissement = DateTime(2026, 10, 12, 10);

/// L'auteur des encaissements d'essai (clé étrangère RG-15).
const String caissierEssai = auteurEssai;

/// Une base EN MÉMOIRE portant le référentiel comptable installé par la vraie
/// fonction à [maintenant] (l'exercice de l'année est ouvert) et un auteur.
Future<AppDatabase> baseEncaissement({DateTime? maintenant}) =>
    baseInstallee(maintenant: maintenant ?? jourEncaissement);

FactureDao factureDaoSur(AppDatabase db, {DateTime? horloge}) {
  final h = horloge ?? jourEncaissement;
  return FactureDao(db, maintenant: () => h);
}

/// Le DAO des encaissements BRANCHÉ sur le moteur comptable réel de [db] : c'est
/// le chemin de production, pas un dépôt bouché. [sansMoteur] pour éprouver le
/// refus d'écrire sans pièce.
PaiementsFactureDao paiementsDaoSur(
  AppDatabase db, {
  DateTime? horloge,
  bool sansMoteur = false,
}) {
  final h = horloge ?? jourEncaissement;
  return PaiementsFactureDao(
    db,
    maintenant: () => h,
    moteur: sansMoteur ? null : () async => moteurSur(db, maintenant: () => h),
  );
}

/// Ouvre une session de caisse au [point] avec [fond] francs.
Future<SessionCaisse> ouvrirCaissePour(
  AppDatabase db, {
  PointDeVenteCaisse point = PointDeVenteCaisse.bar,
  String fond = '10000',
  DateTime? horloge,
}) {
  final h = horloge ?? jourEncaissement;
  return SessionsCaisseDao(db, maintenant: () => h).ouvrir(
    point: point,
    fondSaisi: fond,
    auteurId: caissierEssai,
    peutEcrire: true,
  );
}

Future<Client> creerClient(
  AppDatabase db, {
  String nom = 'KORA',
  String telephone = '97111111',
}) => ClientDao(db).creer(
  nom: nom,
  telephone: telephone,
  type: TypeClientReferentiel.particulier,
);

/// Émet une facture de [montant] francs (une ligne) par le chemin de production.
///
/// [origine] : une facture directe par défaut ; `posComptant` pour un ticket de
/// vente au comptant, que ce poste n'encaisse pas une seconde fois.
Future<PieceFacturation> emettreFacture(
  AppDatabase db, {
  int montant = 50000,
  String? clientId,
  String clientNom = 'KORA',
  OrigineFacture origine = OrigineFacture.factureDirecte,
  ModuleFacturable module = ModuleFacturable.m5Bar,
  String? reservationId,
  DateTime? horloge,
}) => factureDaoSur(db, horloge: horloge).emettre(
  BrouillonFacture(
    origine: origine,
    clientNom: clientNom,
    clientId: clientId,
    reservationId: reservationId,
    lignes: [
      LigneBrouillon(
        module: module,
        libelle: 'Prestation',
        prixUnitaire: montant,
        quantite: 1,
      ),
    ],
  ),
);

/// Sème le parc minimal (`reservations_local.unite_id` est une vraie clé
/// étrangère) puis une réservation à [acompte] francs.
Future<void> semerReservation(
  AppDatabase db, {
  required String id,
  required String clientId,
  int acompte = 0,
  int total = 50000,
}) async {
  final categories = await db.select(db.categoriesHebergementLocal).get();
  if (categories.isEmpty) {
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
    await db
        .into(db.unitesHebergementLocal)
        .insert(
          UnitesHebergementLocalCompanion.insert(
            id: 'u-1',
            categorieId: 'cat-1',
            numero: 'BNG-01',
            statut: 'libre',
          ),
        );
  }
  await ReservationDao(db).enregistrer(
    Reservation(
      id: id,
      reference: 'LOC-$id',
      clientId: clientId,
      clientNom: 'Client',
      uniteId: 'u-1',
      periode: PeriodeSejour(
        arrivee: DateTime(2026, 10, 20),
        depart: DateTime(2026, 10, 22),
      ),
      tarifNuit: 0,
      statut: StatutReservation.confirmee,
      statutSynchronisation: StatutSynchronisation.local,
      creeeLe: DateTime(2026, 10, 1),
      acompte: acompte,
      typeClient: TypeClient.particulier,
      canal: CanalReservation.physique,
      lignes: [
        LigneService(
          id: 'l-$id',
          service: ServiceReservation.hebergement,
          itemId: 'u-1',
          libelle: 'Chambre',
          prixUnitaire: total,
          quantite: 1,
        ),
      ],
    ),
  );
}

/// Les surcharges qui branchent un écran sur [db] avec le moteur comptable réel
/// et l'horloge [horloge] — le chemin de production d'un recouvrement.
List<Override> surchargesEncaissement(
  AppDatabase db, {
  DateTime? horloge,
  Map<String, String> droits = const {'M3': 'C', 'M2': 'C'},
}) {
  final h = horloge ?? jourEncaissement;
  final garde = GardeAcces.depuisJson(droits);
  return [
    baseLocaleProvider.overrideWithValue(db),
    factureDaoProvider.overrideWithValue(factureDaoSur(db, horloge: h)),
    paiementsFactureDaoProvider.overrideWithValue(
      paiementsDaoSur(db, horloge: h),
    ),
    moteurComptableProvider.overrideWith(
      (ref) async => moteurSur(db, maintenant: () => h),
    ),
    horlogeCreancesProvider.overrideWithValue(() => h),
    droitsProvider.overrideWithValue(garde),
    sessionProvider.overrideWithBuild(
      (ref, notifier) => Session(
        utilisateurId: caissierEssai,
        login: 'compta-$caissierEssai',
        nom: 'Caissier',
        role: 'gerant',
        droits: garde,
      ),
    ),
  ];
}

/// Le nombre de lignes de comptabilité, de paiements et de pièces : ce qu'un
/// refus ne doit pas avoir fait bouger.
Future<({int paiements, int ecritures, int sequences})> empreinte(
  AppDatabase db,
) async => (
  paiements: await compterLignes(db, 'paiements_facture_local'),
  ecritures: await compterLignes(db, 'ecritures_local'),
  sequences: await db
      .customSelect(
        'SELECT COALESCE(SUM(dernier_rang), 0) AS n FROM sequences_piece_local',
      )
      .getSingle()
      .then((r) => r.data['n'] as int),
);

/// Une boisson au catalogue du comptoir (`cartes_boisson_local`).
Future<void> semerBoisson(
  AppDatabase db, {
  String id = 'bsn-33',
  int prix = 1000,
}) => db
    .into(db.cartesBoissonLocal)
    .insert(
      CartesBoissonLocalCompanion.insert(
        id: id,
        articleId: 'art-$id',
        libelle: 'Béninoise 33cl',
        categorie: 'locale',
        prixVente: prix.toDouble(),
      ),
    );

/// Une vente au comptant par le chemin de production : ouvrir un panier, y
/// ajouter [quantite] boissons, le clôturer en [mode]. La session ouverte du
/// bar l'encaisse, ou la clôture est refusée (`RefusCaisse`).
Future<Panier> vendreAuComptant(
  AppDatabase db, {
  String mode = 'especes',
  int quantite = 1,
  String boisson = 'bsn-33',
  int prix = 1000,
  DateTime? horloge,
}) async {
  final h = horloge ?? jourEncaissement;
  // La vente passe sa pièce comptable : le référentiel doit être installé
  // (idempotent — un appelant qui l'a déjà fait n'y perd rien).
  await baseInstalleeSur(db, h);
  final dao = PanierDao(
    db,
    maintenant: () => h,
    // La vente passe sa pièce comptable : le chemin de production, pas un DAO
    // bouché (la base doit porter le référentiel : `baseEncaissement`).
    moteur: () async => moteurSur(db, maintenant: () => h),
  );
  final panier = await dao.ouvrir(
    typeVente: TypeVente.comptant,
    pointVente: 'Comptoir',
  );
  await dao.ajouterLigne(
    panier.id,
    ArticleVendable(
      reference: ReferenceCatalogue(
        module: ModuleVendable.m5Bar,
        code: boisson,
      ),
      libelle: 'Béninoise 33cl',
      prix: prix,
    ),
    quantite: quantite,
  );
  return dao.cloturer(panier.id, modePaiement: mode, auteurId: caissierEssai);
}

/// Ouvre la caisse du BAR — le prérequis d'une vente au comptant depuis le
/// lot 5 (12/10/2026, D221 option a) : le serveur refuse d'encaisser sans elle
/// et le poste fait de même. Sème l'auteur s'il manque (les tests de panier
/// partent d'une base nue).
Future<SessionCaisse> ouvrirLaCaisseDuComptoir(
  AppDatabase db, {
  String fond = '1000',
}) async {
  await db.customStatement('SELECT 1');
  final auteurs = await (db.select(
    db.utilisateursLocal,
  )..where((u) => u.id.equals(caissierEssai))).get();
  if (auteurs.isEmpty) await semerAuteur(db);
  return ouvrirCaissePour(db, fond: fond);
}
