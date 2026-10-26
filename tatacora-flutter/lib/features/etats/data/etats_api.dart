import '../../../core/rbac/garde_acces.dart';
import '../../achats/domain/entities/commande_achat.dart';
import '../../comptabilite/domain/etats_financiers.dart' show DonneesEtats;
import '../../crm/domain/entities/client.dart';
import '../../crm/domain/entities/registre_clients.dart';
import '../../depenses/domain/entities/depense.dart';
import '../../facturation/domain/creances.dart';
import '../../hebergement/domain/entities/reservation.dart';
import '../../hebergement/domain/entities/unite_hebergement.dart';
import '../../rh/domain/entities/employe.dart';
import '../../rh/domain/services/livre_de_paie_service.dart';
import '../../stocks/data/stocks_api.dart';
import '../../tableau_de_bord/data/tableau_de_bord_local.dart';
import '../../tourisme/domain/entities/reservation_tour.dart';
import '../../vehicules/domain/entities/contrat_location.dart';
import '../../vehicules/domain/entities/vehicule.dart';
import '../../ventes/domain/journal_ventes.dart';
import '../domain/apercu_etat.dart';
import '../domain/apercus_etats.dart';
import '../domain/entities/etat_catalogue.dart';
import '../domain/registre_etats.dart';

/// Les dépôts dont M14 relit les chiffres — UN lecteur par module source.
///
/// @see EF-M14-02 Bibliothèque d'états standards par module
///
/// M14 ne possède AUCUNE donnée : un état est une lecture des modules qui
/// l'alimentent, comme le tableau de bord. Les lecteurs sont INJECTÉS (les
/// écrans les câblent aux dépôts de chaque module ; un test les appelle avec
/// des listes construites à la main, ou avec la base en mémoire), et chacun est
/// celui de l'écran du module source : jamais une seconde requête, jamais une
/// seconde formule.
final class SourcesEtats {
  const SourcesEtats({
    required this.stock,
    required this.tableauDeBord,
    required this.parcVehicules,
    required this.contrats,
    required this.reservations,
    required this.unites,
    required this.journalVentes,
    required this.depenses,
    required this.commandes,
    required this.tours,
    required this.employes,
    required this.totauxPaie,
    required this.clients,
    required this.creances,
    required this.maintenant,
    this.donneesComptables,
  });

  /// Les écritures validées d'où se calcule la balance générale (pièces de ce
  /// poste ou écritures reçues du serveur, selon la synchronisation). `null` :
  /// l'état se refuse, sans source.
  final Future<DonneesEtats> Function()? donneesComptables;

  /// Passe par `StocksApi.etat()` : le droit de lecture de M6 y est respecté.
  final Future<ResultatStock> Function() stock;

  /// La fenêtre PAR DÉFAUT du serveur (`Periode::DEFAUT`) : `calculer([])`.
  final Future<ResultatTableauDeBord> Function() tableauDeBord;

  final Future<List<Vehicule>> Function() parcVehicules;
  final Future<List<ContratLocation>> Function() contrats;
  final Future<List<Reservation>> Function() reservations;
  final Future<List<UniteHebergement>> Function() unites;
  final Future<JournalVentes> Function() journalVentes;
  final Future<List<Depense>> Function() depenses;
  final Future<List<CommandeAchat>> Function() commandes;
  final Future<({List<ReservationTour> reservations, int illisibles})>
  Function()
  tours;
  final Future<List<Employe>> Function() employes;

  /// Les clients et leurs créances : de quoi composer le MÊME registre que
  /// l'écran Clients & Créances (`composerRegistre`), jamais une seconde formule.
  final Future<List<Client>> Function() clients;
  final Future<List<CreanceFacture>> Function() creances;

  /// Les totaux du livre de paie d'un mois `AAAA-MM`.
  final Future<TotauxLivre> Function(String periode) totauxPaie;

  final DateTime Function() maintenant;
}

/// La source du hub États & Rapports — M14, LOCAL depuis le 10/10/2026.
///
/// @see EF-M14-02 Bibliothèque d'états standards par module
/// @see EF-M14-03 Génération à la demande
///
/// ## Ce que ce poste produit, et ce qu'il ne produit pas
///
/// Le poste est zéro réseau (PO, 14/09/2026) et M14 a servi un refus jusqu'au
/// 10/10/2026. Il calcule maintenant l'APERÇU de chaque état dont TOUTES les
/// sources sont détenues ET écrites ici — onze des douze (les créances clients
/// depuis le 12/10/2026 : les encaissements ont un écrivain), voir
/// [EtatLocal.raisonRefus] pour les deux autres, listés et refusés avec leur
/// raison datée. Ce qu'il ne fait pas :
///
///  - aucun export, aucun archivage : la vue n'en offre pas (directive du PO du
///    31/08/2026) et le PDF A4 est l'arbitrage PA-192, non tranché ;
///  - aucun document : `GenerateurEtatService` (en-tête normalisée, archivage
///    EF-M14-06) reste au serveur. Une table d'archive locale n'aurait aucun
///    écrivain — personne ne génère rien ici — donc aucune table, aucune
///    migration (schéma inchangé).
///
/// ## Le droit est celui du MODULE SOURCE
///
/// Éditer l'état des stocks exige un droit sur M6, pas sur M14 : le catalogue
/// ne liste que les états dont le module source est lisible, et [apercu] le
/// revérifie (un code tapé à la main ne contourne rien — le 2ᵉ niveau, sur la
/// donnée et non sur l'affichage).
///
/// ## Aucun cache
///
/// Chaque appel relit les modules : garder la dernière réponse montrerait les
/// chiffres d'hier sous un état qui ne dit pas qu'ils datent (PA-120).
final class EtatsApi {
  const EtatsApi({required this.droits, required this.sources});

  final GardeAcces droits;
  final SourcesEtats sources;

  /// Le motif quand le lecteur n'a pas le droit de lire le module source.
  static const String refusModuleSource =
      'Votre rôle n\'a pas accès à cet état.';

  /// Le motif d'un code qui n'est pas au registre fermé.
  static const String refusCodeInconnu =
      'Cet état n\'est pas au registre : aucun aperçu n\'est composé pour un '
      'code inconnu.';

  /// Le catalogue : le registre fermé, filtré par le droit sur le module SOURCE
  /// de chaque état. Un état dont le niveau est `-` est absent, pas grisé.
  List<EtatCatalogue> catalogue() => [
    for (final e in EtatLocal.values)
      if (droits.peutLire(e.module))
        EtatCatalogue(
          code: e.code,
          module: e.module.code,
          libelle: e.libelle,
          niveau: droits.niveau(e.module),
        ),
  ];

  Future<ResultatApercu> apercu(String code) async {
    final etat = EtatLocal.depuisCode(code);
    if (etat == null) return const ApercuRefuse(motif: refusCodeInconnu);

    ApercuRefuse refus(String motif) => ApercuRefuse(
      motif: motif,
      titre: etat.libelle,
      moduleSource: etat.module.code,
    );

    if (!droits.peutLire(etat.module)) return refus(refusModuleSource);

    // Un état dont une source n'existe pas ici est LISTÉ et refusé, quelles que
    // soient les données : un tableau vide se lirait « rien à signaler ».
    final raison = etat.raisonRefus;
    if (raison != null) return refus(raison);

    final maintenant = sources.maintenant();

    switch (etat) {
      case EtatLocal.stocks:
        return switch (await sources.stock()) {
          StockRecu(:final etat) => ApercuRecu(
            apercuStocks(etat, maintenant: maintenant),
          ),
          StockRefuse(:final motif) => refus(motif),
          StockInjoignable() => refus('Le stock n\'a pas pu être lu.'),
        };
      case EtatLocal.tableauDeBord:
        return switch (await sources.tableauDeBord()) {
          TableauDeBordRecu(:final tableau) => ApercuRecu(
            apercuTableauDeBord(tableau),
          ),
          TableauDeBordRefuse(:final motif) => refus(motif),
        };
      case EtatLocal.parcVehicules:
        return ApercuRecu(
          apercuParcVehicules(
            await sources.parcVehicules(),
            maintenant: maintenant,
          ),
        );
      case EtatLocal.locationsVehicules:
        final (contrats, parc) = await (
          sources.contrats(),
          sources.parcVehicules(),
        ).wait;
        return ApercuRecu(apercuLocations(contrats, parc));
      case EtatLocal.reservations:
        final (reservations, unites) = await (
          sources.reservations(),
          sources.unites(),
        ).wait;
        return ApercuRecu(
          apercuReservations(reservations, unites, maintenant: maintenant),
        );
      case EtatLocal.ventes:
        final journal = await sources.journalVentes();
        return ApercuRecu(
          apercuVentes(journal.ventes, paniersOuverts: journal.paniersOuverts),
        );
      case EtatLocal.depenses:
        return ApercuRecu(apercuDepenses(await sources.depenses()));
      case EtatLocal.achatsFournisseurs:
        return ApercuRecu(apercuAchats(await sources.commandes()));
      case EtatLocal.tourisme:
        final tours = await sources.tours();
        return ApercuRecu(
          apercuTourisme(tours.reservations, illisibles: tours.illisibles),
        );
      case EtatLocal.paieEffectif:
        // `periodeValide` du serveur : le mois COURANT quand rien n'est demandé.
        final periode = moisDe(maintenant);
        final (employes, totaux) = await (
          sources.employes(),
          sources.totauxPaie(periode),
        ).wait;
        return ApercuRecu(apercuPaie(employes, totaux, periode: periode));
      case EtatLocal.creancesClients:
        final (clients, creances) = await (
          sources.clients(),
          sources.creances(),
        ).wait;
        return ApercuRecu(
          apercuCreancesClients(
            composerRegistre(clients: clients, creances: creances),
            totaux: totauxCreances(creances),
            maintenant: maintenant,
          ),
        );
      case EtatLocal.balance:
        final lecteur = sources.donneesComptables;
        if (lecteur == null) {
          return refus(
            'La balance générale n\'est pas disponible dans cet état.',
          );
        }
        final donnees = await lecteur();
        if (exerciceDeLaBalance(donnees) == null) {
          return refus(balanceSansExercice);
        }
        return ApercuRecu(apercuBalance(donnees));
    }
  }
}

/// `2026-10` — le mois d'une date, comme `CarbonImmutable::format('Y-m')`.
String moisDe(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
