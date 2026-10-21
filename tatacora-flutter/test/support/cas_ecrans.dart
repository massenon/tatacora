// Les CAS D'ÉCRAN partagés par les mesures de la Phase 1 : une vue Blade, le
// jeu de données que les deux côtés posent, les droits, les fournisseurs
// surchargés et l'écran Flutter qui la porte. Un seul registre : deux listes
// d'écrans écrites à deux endroits finiraient par diverger.
//
// Utilisé par `emplacement_blade_test.dart` (Phase 1A) et
// `geometrie_blade_test.dart` (Phase 1D).

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/achats/presentation/ecran_approvisionnement.dart';
import 'package:tatacora_flutter/features/achats/presentation/ecran_fournisseurs.dart';
import 'package:tatacora_flutter/features/auth/presentation/ecran_connexion.dart';
import 'package:tatacora_flutter/features/auth/presentation/ecran_demarrage.dart';
import 'package:tatacora_flutter/features/auth/presentation/formulaire_premier_compte.dart';
import 'package:tatacora_flutter/features/bar/presentation/ecran_carte_bar.dart';
import 'package:tatacora_flutter/features/bar/presentation/providers_bar.dart';
import 'package:tatacora_flutter/features/crm/data/client_dao.dart';
import 'package:tatacora_flutter/features/etats/presentation/ecran_etats.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_depot_local.dart';
import 'package:tatacora_flutter/features/parametres/presentation/ecran_parametres.dart';
import 'package:tatacora_flutter/features/restaurant/presentation/ecran_carte_restaurant.dart';
import 'package:tatacora_flutter/features/synchronisation/data/service_suivi_postes.dart';
import 'package:tatacora_flutter/features/synchronisation/data/transport_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/presentation/ecran_synchronisation_postes.dart';
import 'package:tatacora_flutter/features/crm/domain/entities/client.dart';
import 'package:tatacora_flutter/features/crm/presentation/ecran_clients.dart';
import 'package:tatacora_flutter/features/depenses/presentation/ecran_depenses.dart';
import 'package:tatacora_flutter/features/facturation/data/facture_dao.dart';
import 'package:tatacora_flutter/features/facturation/data/facture_repository_local.dart';
import 'package:tatacora_flutter/features/facturation/presentation/ecran_facturation.dart';
import 'package:tatacora_flutter/features/facturation/presentation/providers_facturation.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_repository_local.dart';
import 'package:tatacora_flutter/features/hebergement/presentation/providers_hebergement.dart';
import 'package:tatacora_flutter/features/notifications/presentation/ecran_notifications.dart';
import 'package:tatacora_flutter/features/pos/data/catalogue_dao.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/data/panier_repository_local.dart';
import 'package:tatacora_flutter/features/pos/presentation/ecran_pos_comptant.dart';
import 'package:tatacora_flutter/features/pos/presentation/ecran_pos_heberges.dart';
import 'package:tatacora_flutter/features/pos/presentation/providers_pos.dart';
import 'package:tatacora_flutter/features/pos/data/dto/catalogue_dto.dart';
import 'package:tatacora_flutter/features/restaurant/presentation/ecran_restauration.dart';
import 'package:tatacora_flutter/features/rh/presentation/ecran_paie.dart';
import 'package:tatacora_flutter/features/rh/presentation/providers_rh.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/presentation/ecran_tableau_de_bord.dart';
import 'package:tatacora_flutter/features/stocks/presentation/ecran_inventaires.dart';
import 'package:tatacora_flutter/features/stocks/presentation/ecran_stocks.dart';
import 'package:tatacora_flutter/features/tourisme/presentation/ecran_tourisme.dart';
import 'package:tatacora_flutter/features/rh/presentation/ecran_conges_plannings.dart';
import 'package:tatacora_flutter/features/vehicules/presentation/ecran_vehicules.dart';
import 'package:tatacora_flutter/features/ventes/presentation/ecran_historique_ventes.dart';
import 'package:tatacora_flutter/features/hebergement/presentation/ecran_hebergement.dart';
import 'package:tatacora_flutter/features/hebergement/presentation/ecran_reservations.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/ecran_comptabilite.dart';
import 'package:tatacora_flutter/features/transverse/presentation/ecran_aide_a_propos.dart';
import 'package:tatacora_flutter/features/transverse/presentation/ecran_contact_editeur.dart';
import 'package:tatacora_flutter/features/transverse/presentation/ecran_import_export.dart';
import 'package:tatacora_flutter/features/transverse/presentation/ecran_journal_audit.dart';
import 'package:tatacora_flutter/features/transverse/presentation/ecran_mon_profil.dart';
import 'package:tatacora_flutter/features/transverse/presentation/ecran_roles_permissions.dart';

/// Le jeu de données commun à la vue Blade et au Flutter.
enum JeuEcran { clients, parc, vide }

class CasEcran {
  const CasEcran({
    required this.vue,
    required this.jeu,
    required this.droits,
    required this.ecran,
    this.activations = const {},
    this.surcharges = _aucune,
    this.parRouteur = false,
  });

  final String vue;
  final JeuEcran jeu;
  final Map<String, String> droits;
  final Widget Function() ecran;

  /// Les fournisseurs que l'écran exige et que le test construit lui-même
  /// (dépôts locaux), comme le font ses propres tests de widget.
  final List<Override> Function(AppDatabase db) surcharges;

  /// L'écran aiguille par `context.go` (démarrage) : il lui faut un vrai
  /// routeur, et il ne « se calme » jamais (minuteur périodique), donc le
  /// test n'attend pas la fin des animations.
  final bool parRouteur;

  /// Variantes sans bouton d'onglet dans la vue (`?vue=historique`) : clé ->
  /// libellé du contrôle qui l'ouvre.
  final Map<String, String> activations;
}

List<Override> _aucune(AppDatabase db) => const [];

/// M7 est mesuré sur sa SOURCE LOCALE réelle (09/10/2026) : `achatsApiProvider`
/// lit la base du test, vide — aucun fournisseur, aucune commande, aucune
/// réception, donc la structure d'un poste neuf, ATTEIGNABLE en production.
/// Jusqu'à cette date le test surchargeait six providers avec des réponses
/// « reçues, vides » que la production n'atteignait pas (le client ne rendait
/// que des refus) : la mesure portait sur un état irréalisable.
///
/// M6 est mesuré sur sa SOURCE LOCALE réelle (09/10/2026) : `stocksApiProvider`
/// lit la base du test, vide — aucun article, aucun point, aucun mouvement,
/// donc la structure d'un poste neuf. Jusqu'à cette date le test surchargeait
/// `etatStockProvider` avec une réponse « reçue, vide » que la production
/// n'atteignait pas (le client d'API ne rendait que des refus) : la mesure
/// portait sur un état irréalisable. L'état vide d'aujourd'hui, lui, est
/// exactement ce que voit un poste neuf. Rien à surcharger : la chaîne réelle
/// (API -> DAO -> base) est empruntée.
List<Override> _sourceLocaleStocks(AppDatabase db) => const [];

/// L'écran Paramètres est mesuré sur sa SOURCE LOCALE réelle (09/10/2026) : le
/// dépôt de la base du test, vide — aucune valeur saisie, donc chaque champ
/// affiche « — », ce que fait un poste neuf. Jusqu'à cette date, le test
/// surchargeait `parametresProvider` avec la réponse du serveur relevée dans
/// `reponse-serveur__parametres.json` : la mesure portait sur un état que la
/// production n'atteignait pas (aucun client d'API), ce qui est un gain de
/// MESURE sans gain réel. Désormais la chaîne entière (dépôt, registre, états
/// dérivés) est empruntée.
List<Override> _sourceLocaleParametres(AppDatabase db) => [
  stockageParametresProvider.overrideWithValue(ParametresDepotLocal(db)),
];

/// M14 est mesuré sur sa SOURCE LOCALE réelle (10/10/2026) : le catalogue est
/// composé par `EtatsApi.catalogue` depuis les droits de la session — ceux d'un
/// Administrateur, comme la capture du navigateur (`capture.admin`) — et rien
/// n'est surchargé. Jusqu'à cette date le test rejouait la réponse du serveur
/// relevée dans `reponse-serveur__etats.json` : la mesure portait sur un état
/// que la production n'atteignait pas (le client rendait un refus). Les douze
/// états s'y retrouvent dans l'ordre du registre serveur, et un test confronte
/// les deux listes.
List<Override> _sourceLocaleEtats(AppDatabase db) => const [];

/// M4 est mesuré sur sa SOURCE LOCALE réelle (09/10/2026) : `restaurantApiProvider`
/// lit la base du test, vide — aucun menu, aucune fiche, aucun plat, aucun point
/// de stockage —, donc la structure d'un poste neuf, ATTEIGNABLE en production.
/// Jusqu'à cette date le test surchargeait `carteRestaurantProvider` et
/// `platsProvider` avec des réponses « reçues, vides » que la production
/// n'atteignait pas (le client ne rendait que des refus) : la mesure portait sur
/// un état irréalisable. Rien à surcharger : la chaîne réelle (API -> DAO ->
/// base) est empruntée, pour la carte comme pour le catalogue.
List<Override> _sourceLocaleRestaurant(AppDatabase db) => const [];

/// La carte du bar : la base locale (vide) suffit ; le stock du serveur est
/// simulé comme reçu et vide, sans quoi l'écran ouvrirait une vraie connexion.
List<Override> _reseauBar(AppDatabase db) => [
  stockBarProvider.overrideWith((ref) async => <BoissonDistante>[]),
];

List<Override> _compteExistant(AppDatabase db) => [
  aucunCompteProvider.overrideWith((ref) async => false),
];

/// Les trois dépôts du point de vente, du panier et de la facture.
List<Override> _depotsVente(AppDatabase db) => [
  depotPanierProvider.overrideWithValue(PanierRepositoryLocal(PanierDao(db))),
  catalogueProvider.overrideWithValue(CatalogueDao(db)),
  depotReservationProvider.overrideWithValue(
    ReservationRepositoryLocal(ReservationDao(db)),
  ),
  depotFactureProvider.overrideWithValue(
    FactureRepositoryLocal(FactureDao(db)),
  ),
];

final casEcrans = <CasEcran>[
  CasEcran(
    vue: 'crm/clients-creances',
    jeu: JeuEcran.clients,
    droits: const {'M3': 'C'},
    ecran: () => const EcranClients(),
  ),
  CasEcran(
    vue: 'hebergement/hebergement',
    jeu: JeuEcran.parc,
    droits: const {'M1': 'C'},
    ecran: () => const EcranHebergement(),
  ),
  CasEcran(
    vue: 'hebergement/reservations',
    jeu: JeuEcran.parc,
    droits: const {'M1': 'C', 'M3': 'C'},
    ecran: () => const EcranReservations(),
    activations: const {'historique': 'Historique'},
  ),
  // ---- Lot 6 : l'accueil. Les onglets de la vue sont portés par `?panel=`
  // et par des boutons Alpine (pas de `wire:click`) : on nomme donc les
  // libellés à cliquer. L'écran est mesuré dans l'ÉTAT RÉEL du poste (clients
  // d'API en coquille, « donnée non disponible ») : simuler un tableau de
  // bord reçu exigerait une dizaine de fournisseurs de données et ne
  // décrirait rien que l'utilisateur puisse voir aujourd'hui. ----
  CasEcran(
    vue: 'livewire/accueil',
    jeu: JeuEcran.vide,
    droits: const {'M11': 'C', 'M1': 'C', 'M6': 'C', 'M10': 'C'},
    ecran: () => const EcranTableauDeBord(),
    activations: const {
      'pilotage': 'Pilotage consolidé',
      'croise': 'Tableau croisé dynamique',
    },
  ),
  // ---- Lot 5b : carte du restaurant, studio d'états, paramètres ----
  CasEcran(
    vue: 'restaurant/carte',
    jeu: JeuEcran.vide,
    droits: const {'M4': 'C', 'M6': 'C'},
    ecran: () => const EcranCarteRestaurant(),
    surcharges: _sourceLocaleRestaurant,
  ),
  CasEcran(
    vue: 'etats/studio',
    jeu: JeuEcran.vide,
    droits: const {
      'M1': 'C',
      'M2': 'C',
      'M3': 'C',
      'M4': 'C',
      'M5': 'C',
      'M6': 'C',
      'M7': 'C',
      'M8': 'C',
      'M9': 'C',
      'M10': 'C',
      'M11': 'C',
      'M12': 'C',
      'M13': 'C',
      'M14': 'C',
    },
    ecran: () => const EcranEtats(),
    surcharges: _sourceLocaleEtats,
  ),
  CasEcran(
    vue: 'transverse/parametres',
    jeu: JeuEcran.vide,
    droits: const {'PARAM': 'C'},
    ecran: () => const EcranParametres(),
    surcharges: _sourceLocaleParametres,
  ),
  // ---- Lot 5a : stocks, restauration, carte du bar ----
  CasEcran(
    vue: 'stocks/stocks',
    jeu: JeuEcran.vide,
    droits: const {'M6': 'C'},
    ecran: () => const EcranStocks(),
    surcharges: _sourceLocaleStocks,
  ),
  CasEcran(
    vue: 'stocks/inventaires',
    jeu: JeuEcran.vide,
    droits: const {'M6': 'C'},
    ecran: () => const EcranInventaires(),
    surcharges: _sourceLocaleStocks,
  ),
  CasEcran(
    vue: 'restaurant/restauration',
    jeu: JeuEcran.vide,
    droits: const {'M4': 'C'},
    ecran: () => const EcranRestauration(),
    surcharges: _sourceLocaleRestaurant,
  ),
  CasEcran(
    vue: 'bar/carte',
    jeu: JeuEcran.vide,
    droits: const {'M5': 'C', 'M6': 'C'},
    ecran: () => const EcranCarteBar(),
    surcharges: _reseauBar,
  ),
  // ---- Lot 4 : les écrans d'API (locations, tourisme, achats) ----
  CasEcran(
    vue: 'vehicules/locations',
    jeu: JeuEcran.vide,
    droits: const {'M8': 'C', 'M3': 'C'},
    ecran: () => const EcranVehicules(),
  ),
  CasEcran(
    vue: 'rh/conges-plannings',
    jeu: JeuEcran.vide,
    droits: const {'M13': 'C'},
    ecran: () => const EcranCongesPlannings(),
  ),
  CasEcran(
    vue: 'tourisme/departs',
    jeu: JeuEcran.vide,
    droits: const {'M9': 'C', 'M3': 'C'},
    ecran: () => const EcranTourisme(),
  ),
  CasEcran(
    vue: 'achats/achats',
    jeu: JeuEcran.vide,
    droits: const {'M7': 'C'},
    ecran: () => const EcranFournisseurs(),
  ),
  CasEcran(
    vue: 'achats/approvisionnement',
    jeu: JeuEcran.vide,
    droits: const {'M7': 'C', 'M6': 'C'},
    ecran: () => const EcranApprovisionnement(),
  ),
  // ---- Lot 3 : les écrans d'accueil, sans barre ni session ----
  CasEcran(
    vue: 'livewire/connexion',
    jeu: JeuEcran.vide,
    droits: const {},
    ecran: () => const EcranConnexion(),
    // Le poste porte déjà un compte : sans cela l'écran cède la place à la
    // création du premier compte (PA-103), un autre formulaire.
    surcharges: _compteExistant,
  ),
  CasEcran(
    vue: 'demarrage',
    jeu: JeuEcran.vide,
    droits: const {},
    ecran: () => const EcranDemarrage(),
    parRouteur: true,
  ),
  // ---- Lot 2 : les écrans à données locales (jeu vide des deux côtés) ----
  CasEcran(
    vue: 'pos/comptant',
    jeu: JeuEcran.vide,
    droits: const {'M5': 'C', 'M1': 'C', 'M4': 'C'},
    ecran: () => const EcranPosComptant(),
    surcharges: _depotsVente,
  ),
  CasEcran(
    vue: 'pos/heberges',
    jeu: JeuEcran.vide,
    droits: const {'M5': 'C', 'M1': 'C', 'M4': 'C'},
    ecran: () => const EcranPosHeberges(),
    surcharges: _depotsVente,
  ),
  CasEcran(
    vue: 'pos/historique-ventes',
    jeu: JeuEcran.vide,
    droits: const {'M5': 'C', 'M4': 'C'},
    ecran: () => const EcranHistoriqueVentes(),
  ),
  CasEcran(
    vue: 'facturation/facturation',
    jeu: JeuEcran.vide,
    droits: const {'M2': 'C'},
    ecran: () => const EcranFacturation(),
    surcharges: _depotsVente,
  ),
  CasEcran(
    vue: 'depenses/depenses',
    jeu: JeuEcran.vide,
    droits: const {'M10': 'C'},
    ecran: () => const EcranDepenses(),
  ),
  CasEcran(
    vue: 'notifications/hub',
    jeu: JeuEcran.vide,
    droits: const {'M12': 'C'},
    ecran: () => const EcranNotifications(),
  ),
  CasEcran(
    vue: 'rh/paie',
    jeu: JeuEcran.vide,
    droits: const {'M13': 'C'},
    ecran: () => const EcranPaie(),
    surcharges: _baseDePaieVierge,
  ),
  // ---- Lot D (14/10/2026, D417–D424), mesurés depuis le 15/10/2026 : la vue
  // est relevée pour `compte.structure`, administrateur — mêmes droits et
  // même rôle ici. ----
  CasEcran(
    vue: 'comptabilite/hub',
    jeu: JeuEcran.parc,
    droits: _droitsAdministrateur,
    ecran: () => const EcranComptabilite(),
    surcharges: _sessionAdministrateur,
  ),
  CasEcran(
    vue: 'transverse/aide-a-propos',
    jeu: JeuEcran.parc,
    droits: _droitsAdministrateur,
    ecran: () => const EcranAideAPropos(),
    surcharges: _sessionAdministrateur,
  ),
  CasEcran(
    vue: 'transverse/contact-editeur',
    jeu: JeuEcran.parc,
    droits: _droitsAdministrateur,
    ecran: () => const EcranContactEditeur(),
    surcharges: _sessionAdministrateur,
  ),
  CasEcran(
    vue: 'transverse/import-export',
    jeu: JeuEcran.parc,
    droits: _droitsAdministrateur,
    ecran: () => const EcranImportExport(),
    surcharges: _sessionAdministrateur,
  ),
  CasEcran(
    vue: 'transverse/journal-audit',
    jeu: JeuEcran.parc,
    droits: _droitsAdministrateur,
    ecran: () => const EcranJournalAudit(),
    surcharges: _sessionAdministrateur,
  ),
  // Décision PO du 18/10/2026 : aucun poste encore connu du serveur, aucune
  // demande — l'état que la vue rend sur le jeu `parc`.
  CasEcran(
    vue: 'transverse/synchronisation-postes',
    jeu: JeuEcran.parc,
    droits: _droitsAdministrateur,
    ecran: () => const EcranSynchronisationPostes(),
    surcharges: (db) => [
      ..._sessionAdministrateur(db),
      serviceSuiviPostesProvider.overrideWithValue(_SuiviPostesVierge()),
    ],
  ),
  CasEcran(
    vue: 'transverse/mon-profil',
    jeu: JeuEcran.parc,
    droits: _droitsAdministrateur,
    ecran: () => const EcranMonProfil(),
    surcharges: _sessionAdministrateur,
  ),
  CasEcran(
    vue: 'transverse/roles-permissions',
    jeu: JeuEcran.parc,
    droits: _droitsAdministrateur,
    ecran: () => const EcranRolesPermissions(),
    surcharges: _sessionAdministrateur,
  ),
];

/// La matrice d'un administrateur : tous les modules en création.
const _droitsAdministrateur = {
  'M1': 'C', 'M2': 'C', 'M3': 'C', 'M4': 'C', 'M5': 'C', 'M6': 'C', //
  'M7': 'C', 'M8': 'C', 'M9': 'C', 'M10': 'C', 'M11': 'C', 'M12': 'C',
  'M13': 'C', 'M14': 'C', 'ROLES': 'C', 'PARAM': 'C',
};

/// La session du relevé Blade : `compte.structure`, administrateur
/// (`ExtraireStructureBladeTest::administrateur`).
/// Le serveur tel que la vue le rend sur le jeu `parc` : aucun poste, aucune
/// demande.
final class _SuiviPostesVierge extends ServiceSuiviPostes {
  _SuiviPostesVierge() : super(transport: TransportHttp(), urlServeur: null);

  @override
  Future<IssueSuiviPostes> lire() async =>
      const SuiviPostesLu(demandeeLe: null, postes: []);
}

List<Override> _sessionAdministrateur(AppDatabase db) => [
  sessionProvider.overrideWithBuild(
    (ref, notifier) => Session(
      utilisateurId: 'u-structure',
      login: 'compte.structure',
      nom: 'compte.structure',
      role: 'administrateur',
      droits: GardeAcces.depuisJson(_droitsAdministrateur),
    ),
  ),
];

/// L'état de la base que la vue Blade a RENDU pour la paie : fraîchement
/// semée, **sans aucun taux** ni aucun salarié. La vue affiche alors le
/// bandeau « Les taux de paie ne sont pas paramétrés » et l'état vide de
/// chaque tableau.
///
/// Sur ce poste, l'écran installe le référentiel confirmé à son ouverture
/// (`referentielPaieProvider`) ; pour reproduire l'état de la vue, ce
/// fournisseur est remplacé par la lecture de l'état SANS installation. C'est
/// la seule surcharge : la lecture elle-même (`etatReferentiel`) est réelle.
List<Override> _baseDePaieVierge(AppDatabase db) => [
  referentielPaieProvider.overrideWith(
    (ref) => ref.watch(bulletinPaieServiceProvider).etatReferentiel(),
  ),
];

/// Les deux clients que la vue Blade a rendus, dans le même ordre.
Future<void> semerClients(AppDatabase db) async {
  final dao = ClientDao(db);
  await dao.creer(
    nom: 'KORA',
    telephone: '97111111',
    type: TypeClientReferentiel.particulier,
  );
  await dao.creer(
    nom: 'KORA',
    prenom: 'Jean',
    telephone: '+229 01 00 00 00 01',
    type: TypeClientReferentiel.particulier,
  );
}

/// Le parc de la vue Blade : un bungalow, deux unités.
Future<void> semerParc(AppDatabase db) async {
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
  for (final numero in const ['BNG-01', 'BNG-02']) {
    await db
        .into(db.unitesHebergementLocal)
        .insert(
          UnitesHebergementLocalCompanion.insert(
            id: 'u-$numero',
            categorieId: 'cat-1',
            numero: numero,
            statut: 'libre',
          ),
        );
  }
  await db
      .into(db.clientsLocal)
      .insert(
        ClientsLocalCompanion.insert(
          id: 'cli-1',
          nom: 'KORA',
          prenom: const Value('Jean'),
          telephone: '+229 01 00 00 00 01',
          typeClient: 'particulier',
        ),
      );
}
