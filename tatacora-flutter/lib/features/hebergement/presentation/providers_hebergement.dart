library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../comptabilite/presentation/providers_comptabilite.dart';
import '../../crm/data/client_dao.dart';
import '../../crm/domain/entities/client.dart';
import '../../facturation/data/facture_dao.dart';
import '../../parametres/data/parametres_dao.dart';
import '../../pos/data/panier_dao.dart';
import '../data/catalogue_services_dao.dart';
import '../data/parc_dao.dart';
import '../data/reservation_dao.dart';
import '../data/reservation_repository_local.dart';
import '../data/sejour_dao.dart';
import '../domain/annulation_reservation.dart';
import '../domain/entities/carte_reservation.dart';
import '../domain/entities/categorie_hebergement.dart';
import '../domain/entities/disponibilite.dart';
import '../domain/entities/etat_du_jour.dart';
import '../domain/entities/periode_sejour.dart';
import '../domain/entities/reservation.dart';
import '../domain/entities/unite_hebergement.dart';
import '../domain/entities/service_reservation.dart';
import '../impression/confirmation_reservation.dart';
import '../impression/etat_historique.dart';
import '../impression/etat_parc.dart';
import '../domain/repositories/catalogue_services.dart';
import '../domain/repositories/reservation_repository.dart';
import '../domain/usecases/annuler_reservation.dart';
import '../domain/usecases/consulter_disponibilites.dart';
import '../domain/usecases/creer_reservation.dart';
import '../domain/usecases/modifier_reservation.dart';

/// Providers du module M1 — Riverpod exclusivement.
///
/// Les écrans ne connaissent que les **cas d'usage** et le contrat de dépôt.
/// Aucun d'eux ne voit `ReservationDao` : c'est ce qui a rendu la bascule du
/// 14/09/2026 invisible à l'interface.
///
/// ## Zéro réseau — décision du Product Owner, 14/09/2026
///
/// `ReservationRepositoryComposite`, `ReservationApi`, `ParcApi`, `ClientApi`,
/// `FileSynchronisation` et `DeclencheurSynchronisation` ont été **supprimés**.
/// Le dépôt est désormais `ReservationRepositoryLocal` — et il l'était déjà
/// pour toutes les **lectures** : le composite les lui déléguait une par une,
/// le réseau ne servant qu'à rafraîchir la base. C'est pourquoi aucun écran de
/// consultation ne change d'une ligne.
///
/// ## RG-01 se tient désormais ENTIÈREMENT ici
///
/// Un seul poste utilise le logiciel (décision du PO) : le contrôle de
/// chevauchement de `ReservationRepositoryLocal` est le seul arbitre du
/// double-booking, et il n'a plus d'arbitre serveur au-dessus de lui. Les
/// questions qui ne se tranchaient qu'à deux postes — l'unicité du panier
/// ouvert, l'alignement descendant de PA-127 — n'ont plus d'objet. ⚠ Mais si
/// un second poste apparaissait, **plus rien ne les départagerait** : c'est la
/// contrepartie exacte de la décision, et elle est structurelle.

/// Le DAO des réservations, BRANCHÉ sur le moteur comptable : un acompte encaissé
/// et un remboursement d'annulation passent leur pièce dans la même transaction
/// que le geste (règle du PO du 31/08/2026). Le moteur arrive par un résolveur —
/// `moteurComptableProvider` attend l'installation du référentiel.
final reservationDaoProvider = Provider<ReservationDao>(
  (ref) => ReservationDao(
    ref.watch(baseLocaleProvider),
    moteur: () => ref.read(moteurComptableProvider.future),
  ),
);

/// L'horloge de la modale d'annulation (le délai avant l'arrivée en dépend).
/// Injectable : un test qui lit l'heure réelle échoue un jour sur mille.
final horlogeAnnulationProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Le taux d'annulation à PRÉ-REMPLIR dans le formulaire : le paramètre
/// `hebergement_taux_annulation_moins_24h`, ou 50 % à défaut — jamais imposé,
/// l'opérateur le modifie (EF-M1-06). Lu à chaque ouverture, sans cache : un
/// Administrateur qui change le paramètre le voit au geste suivant.
final tauxAnnulationParDefautProvider = FutureProvider.autoDispose<String>((
  ref,
) async {
  final valeurs = await ParametresDao(ref.watch(baseLocaleProvider)).lireTout();
  return tauxParDefaut(valeurs);
});

/// Le dépôt réellement utilisé par l'application — **local, et seul**.
///
/// Exposé sous le type du **contrat**, comme avant : un écran ne doit pas
/// pouvoir appeler autre chose que les lectures et les écritures du contrat.
final depotReservationProvider = Provider<ReservationRepository>(
  (ref) => ReservationRepositoryLocal(ref.watch(reservationDaoProvider)),
);

/// Le référentiel client du poste (M3).
final clientDaoProvider = Provider<ClientDao>(
  (ref) => ClientDao(ref.watch(baseLocaleProvider)),
);

/// Les clients enregistrés sur ce poste.
///
/// Alimente la liste du formulaire de réservation. **Ce n'est pas un champ
/// libre** : la règle du projet veut qu'un champ relationnel soit une vraie clé
/// étrangère. Le maître emploie un `<input>` texte — anti-pattern de
/// démonstration nommé comme tel — mais pose à côté le bouton « Ajouter
/// client », qui dit ce que le formulaire veut vraiment.
final clientsProvider = FutureProvider<List<Client>>(
  (ref) => ref.watch(clientDaoProvider).clients(),
);

/// Le catalogue des cinq services, lu dans la base locale.
final catalogueServicesProvider = Provider<CatalogueServices>(
  (ref) => CatalogueServicesDao(ref.watch(baseLocaleProvider)),
);

/// Les rayons proposables pour une période donnée.
///
/// La période est la **clé** du provider, et non une lecture d'un autre
/// provider : la disponibilité d'une chambre dépend des dates, et un cache
/// commun à toutes les périodes proposerait une chambre libre en juillet à un
/// séjour d'août. Le tuple porte l'égalité structurelle qui sert de clé.
final rayonsServicesProvider = FutureProvider.autoDispose
    .family<
      List<RayonService>,
      ({DateTime? arrivee, DateTime? depart, String? exclure})
    >(
      (ref, cle) => ref
          .watch(catalogueServicesProvider)
          .rayons(
            arrivee: cle.arrivee,
            depart: cle.depart,
            // En modification, la réservation rouverte est écartée du calcul
            // d'occupation : sa propre chambre doit rester proposable.
            exclureReservationId: cle.exclure,
          ),
    );

/// L'édition d'un état, exposée comme une **action injectable**.
///
/// Deux raisons, et la seconde est la vraie. Un test de widget n'a pas de
/// greffon natif : appeler `Printing` ou écrire un fichier y lèverait, et le
/// panneau deviendrait intestable. Surtout, **il doit exister un endroit unique
/// où l'impression est déclenchée** — un `Printing.layoutPdf` recopié dans
/// chaque écran serait un chemin de plus à ne jamais exécuter (PA-63).
final imprimerEtatHistoriqueProvider =
    Provider<Future<void> Function(EtatHistorique)>(
      (ref) => (etat) async {
        await Printing.layoutPdf(
          onLayout: (_) => etat.pdf(),
          name: EtatHistorique.titre,
          format: PdfPageFormat.a4.landscape,
        );
      },
    );

/// L'impression de la **confirmation de réservation**, exposée comme action.
///
/// ⚠ Ce document n'est PAS une facture : il n'a ni numéro ni cachet fiscal, et
/// rien n'est écrit au registre. Voir l'en-tête de
/// `impression/confirmation_reservation.dart` — c'est l'écart le plus important
/// du module, et il est délibéré.
final imprimerConfirmationReservationProvider =
    Provider<Future<void> Function(ConfirmationReservation)>(
      (ref) => (document) async {
        await Printing.layoutPdf(
          onLayout: (_) => document.pdf(),
          name: 'Confirmation ${document.reservation.reference}',
          format: PdfPageFormat.a4,
        );
      },
    );

/// L'export tableur — rend le **chemin** du fichier écrit.
///
/// Le chemin est rendu pour être **affiché**. Un export silencieux est un
/// export que personne ne retrouve : l'utilisateur clique, rien ne se passe à
/// l'écran, et il recommence.
///
/// ⚠ Fichier **CSV**, pas XLSX : l'écart avec le maître est expliqué en tête
/// de `impression/etat_historique.dart`.
final exporterEtatHistoriqueProvider =
    Provider<Future<String> Function(EtatHistorique)>(
      (ref) => (etat) async {
        final dossier = await getApplicationDocumentsDirectory();
        // Un horodatage dans le nom : deux exports du même jour ne doivent pas
        // s'écraser l'un l'autre, surtout quand ils portent des filtres
        // différents.
        final maintenant = DateTime.now();
        final horodatage =
            '${maintenant.year}'
            '${maintenant.month.toString().padLeft(2, '0')}'
            '${maintenant.day.toString().padLeft(2, '0')}-'
            '${maintenant.hour.toString().padLeft(2, '0')}'
            '${maintenant.minute.toString().padLeft(2, '0')}'
            '${maintenant.second.toString().padLeft(2, '0')}';
        final fichier = File(
          p.join(dossier.path, 'historique-reservations-$horodatage.csv'),
        );
        await fichier.writeAsBytes(etat.csvOctets());
        return fichier.path;
      },
    );

final consulterDisponibilitesProvider = Provider<ConsulterDisponibilites>(
  (ref) => ConsulterDisponibilites(ref.watch(depotReservationProvider)),
);

final creerReservationProvider = Provider<CreerReservation>(
  (ref) => CreerReservation(ref.watch(depotReservationProvider)),
);

final modifierReservationProvider = Provider<ModifierReservation>(
  (ref) => ModifierReservation(ref.watch(depotReservationProvider)),
);

/// Une réservation, relue EN BASE.
///
/// L'écran d'édition part de là, jamais d'un objet que la grille garde en
/// mémoire depuis son dernier rendu : entre-temps, elle a pu être annulée
/// depuis un autre écran, et on rouvrirait une version périmée pour la
/// réécrire.
final reservationParIdProvider = FutureProvider.autoDispose
    .family<Reservation?, String>(
      (ref, id) => ref.watch(depotReservationProvider).parId(id),
    );

final annulerReservationProvider = Provider<AnnulerReservation>(
  (ref) => AnnulerReservation(ref.watch(depotReservationProvider)),
);

/* ====================================================================== */
/* Période consultée                                                       */
/* ====================================================================== */

/// Plage de dates cherchée dans l'onglet Disponibilités, que la fiche de
/// réservation reprend comme période initiale.
///
/// Par défaut : cette nuit (pour la fiche ouverte depuis le plan ; l'onglet,
/// lui, part VIDE et ne la montre qu'une fois deux dates choisies). C'est la demande la plus fréquente au comptoir —
/// un client qui se présente sans réservation.
final periodeConsulteeProvider =
    NotifierProvider<PeriodeConsulteeNotifier, PeriodeSejour>(
      PeriodeConsulteeNotifier.new,
    );

final class PeriodeConsulteeNotifier extends Notifier<PeriodeSejour> {
  @override
  PeriodeSejour build() {
    final auj = DateTime.now();
    return PeriodeSejour(
      arrivee: auj,
      depart: auj.add(const Duration(days: 1)),
    );
  }

  /// Change la plage.
  ///
  /// Refuse en silence une période invalide plutôt que de lever : l'appelant
  /// est un sélecteur de dates, et une exception y afficherait un écran rouge
  /// pour un choix que l'utilisateur est en train de faire.
  void definir({DateTime? arrivee, DateTime? depart}) {
    final a = arrivee ?? state.arrivee;
    var d = depart ?? state.depart;

    // Une arrivée déplacée au-delà du départ pousse le départ, au lieu de
    // rejeter la saisie : c'est ce que l'utilisateur veut dire.
    if (!d.isAfter(a)) d = a.add(const Duration(days: 1));

    state = PeriodeSejour(arrivee: a, depart: d);
  }
}

/* ====================================================================== */
/* Données affichées                                                       */
/* ====================================================================== */

/// Disponibilités sur la période courante.
///
/// `FutureProvider` et non `Future` appelé dans un `build` : le recalcul suit
/// le changement de période, et l'écran n'a aucun cycle de vie à gérer.
final disponibilitesProvider = FutureProvider<List<Disponibilite>>((ref) {
  final periode = ref.watch(periodeConsulteeProvider);
  return ref.watch(consulterDisponibilitesProvider)(periode);
});

/// Le parc, indépendamment de toute période.
///
/// Sert au calendrier d'occupation : le taux se calcule sur le **nombre
/// d'unités**, pas sur celles qui seraient libres à un instant donné.
final unitesProvider = FutureProvider<List<UniteHebergement>>(
  (ref) => ref.watch(depotReservationProvider).unites(),
);

/* ====================================================================== */
/* Le PARC — saisi sur ce poste depuis le 14/09/2026                       */
/* ====================================================================== */

/// L'auteur du parc **saisi au comptoir**.
///
/// Le parc descendait du serveur (PA-128) ; le poste est zéro réseau, et plus
/// rien ne l'alimentait — un poste neuf ne pouvait prendre aucune réservation.
/// Décision du Product Owner du 14/09/2026 : il se saisit ici.
final parcDaoProvider = Provider<ParcDao>(
  (ref) => ParcDao(ref.watch(baseLocaleProvider)),
);

/// Le SEUL auteur de `sejours_local` (check-in, check-out) — réplique de
/// `SejourService` (lot C, 14/10/2026, D408).
final sejourDaoProvider = Provider<SejourDao>(
  (ref) => SejourDao(ref.watch(baseLocaleProvider)),
);

/// Les réservations dont le séjour est OUVERT (`Accueil::sejoursEnCours()`) —
/// le bouton « Check-out » plutôt que « Check-in » de l'accueil. Sans cache :
/// relu à chaque visite.
final reservationsAuSejourOuvertProvider =
    FutureProvider.autoDispose<Set<String>>(
      (ref) => ref.watch(sejourDaoProvider).reservationsAuSejourOuvert(),
    );

/// Le référentiel des catégories — le tarif et la capacité y vivent.
final categoriesParcProvider = FutureProvider<List<CategorieHebergement>>(
  (ref) => ref.watch(parcDaoProvider).categories(),
);

/// L'écriture est-elle permise sur M1 ?
///
/// Premier des trois niveaux de RBAC seulement : il évite de proposer ce qui
/// serait refusé, il ne protège rien. Ici il n'y a pas de second niveau à
/// invoquer — le module est local — et c'est écrit plutôt que sous-entendu.
final peutEcrireHebergementProvider = Provider<bool>(
  (ref) => ref.watch(droitsProvider).peutEcrire(ModuleTatacora.m1Hebergement),
);

/// Le terme de recherche de la barre d'outils du plan.
final rechercheParcProvider = NotifierProvider<_RechercheParcNotifier, String>(
  _RechercheParcNotifier.new,
);

final class _RechercheParcNotifier extends Notifier<String> {
  @override
  String build() => '';

  void definir(String terme) => state = terme;
}

/// La catégorie retenue au filtre — `null` vaut « Toutes les catégories ».
final filtreCategorieParcProvider =
    NotifierProvider<_FiltreCategorieNotifier, String?>(
      _FiltreCategorieNotifier.new,
    );

final class _FiltreCategorieNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void definir(String? categorieId) => state = categorieId;
}

/// La page affichée de la grille du parc.
final pageParcProvider = NotifierProvider<_PageParcNotifier, int>(
  _PageParcNotifier.new,
);

final class _PageParcNotifier extends Notifier<int> {
  @override
  int build() => 1;

  void definir(int page) => state = page < 1 ? 1 : page;
}

/// Lignes par page — la valeur de la vue (10).
const int lignesParPageParc = 10;

/// L'horloge de l'écran Hébergement : « maintenant ».
///
/// Un seul endroit où l'écran lit l'heure — l'état du jour des cartes, l'état
/// des séjours de « Réservations en cours », le mois du calendrier, les bornes
/// du sélecteur de dates de « Disponibilités ». Un test fixe la date ICI : un
/// test qui lit l'horloge réelle devient faux le jour où le mois change.
final horlogeHebergementProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// L'ÉTAT DU JOUR de chaque unité, dérivé des réservations (RG-02).
///
/// Il n'est jamais lu de `unites_hebergement_local.statut` seul : la colonne ne
/// connaît ni date ni période. Voir l'en-tête de `etat_du_jour.dart`.
final etatsDuJourProvider = FutureProvider<Map<String, EtatDuJour>>((
  ref,
) async {
  final parc = await ref.watch(unitesProvider.future);
  final reservations = await ref.watch(reservationsProvider.future);

  return etatsDuJour(
    parc,
    reservations: reservations,
    aujourdHui: ref.watch(horlogeHebergementProvider)(),
  );
});

/// Le parc tel qu'il est FILTRÉ — c'est lui que la grille pagine.
///
/// ⚠ La recherche porte sur le **numéro seul**, et c'est la vue qui en décide
/// (`where('numero', 'like', ...)`). Son invite dit pourtant « Rechercher
/// bungalow, chambre ou tente... », c'est-à-dire des noms de CATÉGORIE : taper
/// « bungalow » n'y trouve donc rien. L'incohérence est celle de la vue, elle
/// n'est pas lissée ici — « harmoniser silencieusement une incohérence » est
/// l'interdit n° 10 de l'Article 1. Le jour où la vue cherchera aussi la
/// catégorie, c'est ici que le prédicat s'élargira.
final parcFiltreProvider = FutureProvider<List<UniteHebergement>>((ref) async {
  final parc = await ref.watch(unitesProvider.future);
  final terme = ref.watch(rechercheParcProvider).trim().toLowerCase();
  final categorieId = ref.watch(filtreCategorieParcProvider);

  final retenues = parc.where((unite) {
    if (categorieId != null && unite.categorieId != categorieId) {
      return false;
    }
    if (terme.isEmpty) return true;
    return unite.numero.toLowerCase().contains(terme);
  }).toList();

  // L'ordre de la vue (`orderBy('numero')`). Sans tri, SQLite est libre de
  // rendre les unités dans l'ordre qu'il veut, et la grille « bouge » d'un
  // rafraîchissement au suivant sans qu'aucune donnée n'ait changé.
  retenues.sort((a, b) => a.numero.compareTo(b.numero));
  return retenues;
});

/// La page courante du parc, et de quoi rendre la pagination de la vue.
///
/// ⚠ La page est **clampée ici, par dérivation** — jamais en réécrivant
/// [pageParcProvider] pendant un rendu. Un filtre qui réduit le résultat sous
/// la page courante ne peut donc pas rendre une grille vide sans raison, et
/// aucun état n'est modifié au milieu d'un `build` (piège 6).
final parcPagineProvider =
    FutureProvider<
      ({List<UniteHebergement> unites, int page, int total, int totalPages})
    >((ref) async {
      final filtre = await ref.watch(parcFiltreProvider.future);
      final total = filtre.length;
      final totalPages = total == 0
          ? 1
          : ((total - 1) ~/ lignesParPageParc) + 1;

      final demandee = ref.watch(pageParcProvider);
      final page = demandee > totalPages ? totalPages : demandee;
      final debut = (page - 1) * lignesParPageParc;

      return (
        unites: filtre.skip(debut).take(lignesParPageParc).toList(),
        page: page,
        total: total,
        totalPages: totalPages,
      );
    });

/// L'export tableur du parc — rend le **chemin** du fichier écrit.
///
/// Action injectable, comme `exporterDepensesProvider` : un test de widget n'a
/// pas de greffon natif, et il doit exister un seul endroit où ce fichier est
/// écrit. Un export silencieux est un export que personne ne retrouve — l'écran
/// affiche le chemin rendu ici.
final exporterParcProvider = Provider<Future<String> Function(EtatParc)>(
  (ref) => (etat) async {
    final dossier = await getApplicationDocumentsDirectory();
    final m = DateTime.now();
    final horodatage =
        '${m.year}'
        '${m.month.toString().padLeft(2, '0')}'
        '${m.day.toString().padLeft(2, '0')}-'
        '${m.hour.toString().padLeft(2, '0')}'
        '${m.minute.toString().padLeft(2, '0')}'
        '${m.second.toString().padLeft(2, '0')}';
    final fichier = File(
      p.join(dossier.path, '${EtatParc.prefixeFichier}-$horodatage.csv'),
    );
    await fichier.writeAsBytes(etat.csvOctets());
    return fichier.path;
  },
);

/// Toutes les réservations, de la plus récente à la plus ancienne.
final reservationsProvider = FutureProvider<List<Reservation>>(
  (ref) => ref.watch(depotReservationProvider).reservations(),
);

/// Le terme de recherche de la page Réservations.
///
/// Le maître cherche **dans le nom du client** seulement (`rendreListe`) — et
/// non dans le canal ou la référence, contrairement au panneau Historique. La
/// différence est voulue : la grille répond à « où en est ce client ? », le
/// panneau à « retrouve-moi cette réservation ».
final rechercheReservationProvider =
    NotifierProvider<_RechercheNotifier, String>(_RechercheNotifier.new);

final class _RechercheNotifier extends Notifier<String> {
  @override
  String build() => '';

  void definir(String terme) => state = terme;
}

/// Les cartes de la grille — la réservation, ses consommations et sa facture.
///
/// ## Pourquoi ce provider appelle deux DAO une fois par réservation
///
/// `PanierDao.panierOuvertPour` et `FactureDao.facturePourReservation`
/// portent chacun une règle qui ne se recopie pas sans risque : le premier est
/// aussi le garde-fou d'unicité du panier ouvert (Q2), le second sait qu'un
/// **avoir porte le même `reservationId`** et doit être écarté. Les remplacer
/// par deux requêtes groupées écrites ici ferait vivre ces règles à deux
/// endroits — et c'est la copie qui finirait par diverger, silencieusement.
///
/// Le coût est assumé et borné : la base d'un poste porte des dizaines de
/// réservations, pas des dizaines de milliers, et tout est local.
final cartesReservationProvider = FutureProvider<List<CarteReservation>>((
  ref,
) async {
  final depot = ref.watch(depotReservationProvider);
  final reservations = await depot.reservations();
  // L'unité de chaque carte, pour la ligne « Unité : BNG-01 — Bungalow » de la
  // vue (PA-185) — lue du parc local, une fois pour toute la grille.
  final unites = {for (final u in await depot.unites()) u.id: u};
  final base = ref.watch(baseLocaleProvider);
  final paniers = PanierDao(base);
  final factures = FactureDao(base);

  final terme = ref.watch(rechercheReservationProvider).trim().toLowerCase();

  final cartes = <CarteReservation>[];
  for (final r in reservations) {
    if (terme.isNotEmpty && !r.clientNom.toLowerCase().contains(terme)) {
      continue;
    }

    final panier = await paniers.panierOuvertPour(r.id);
    final facture = await factures.facturePourReservation(r.id);

    cartes.add(
      CarteReservation(
        reservation: r,
        consommations: panier?.total ?? 0,
        unite: unites[r.uniteId],
        factureId: facture?.id,
        factureNumero: facture?.numero,
      ),
    );
  }
  return cartes;
});

/// Recharge les listes après une écriture.
///
/// **Purement local** — comme tout le reste depuis le 14/09/2026.
///
/// Une seule fonction plutôt qu'un `invalidate` recopié dans chaque écran :
/// oublier d'invalider une liste laisse une réservation absente de l'affichage
/// alors qu'elle est en base, et l'utilisateur la ressaisit.
void rafraichirListes(WidgetRef ref) {
  ref
    ..invalidate(clientsProvider)
    ..invalidate(disponibilitesProvider)
    ..invalidate(reservationsProvider)
    // Le PARC et son état du jour. `unitesProvider` n'était invalidé nulle
    // part : tant que le parc descendait du serveur, il ne changeait jamais en
    // cours de session. Il se saisit désormais sur le poste (14/09/2026), et
    // sans cette ligne une unité créée resterait absente de la grille et du
    // calendrier jusqu'au prochain démarrage — l'utilisateur la ressaisirait.
    ..invalidate(unitesProvider)
    ..invalidate(categoriesParcProvider)
    ..invalidate(parcFiltreProvider)
    ..invalidate(parcPagineProvider)
    ..invalidate(etatsDuJourProvider)
    // La grille porte les consommations du panier ouvert : sans cette ligne,
    // une carte garderait un montant périmé jusqu'au prochain redémarrage —
    // un chiffre faux affiché à côté d'un nom de client, ce que le maître
    // corrige par un réabonnement à `tatacora:panier-modifie`.
    ..invalidate(cartesReservationProvider);
}
