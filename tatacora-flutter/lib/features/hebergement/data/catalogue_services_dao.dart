import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../pos/data/catalogue_dao.dart';
import '../../pos/domain/entities/article_vendable.dart';
import '../../pos/domain/entities/reference_catalogue.dart';
import '../domain/entities/service_reservation.dart';
import '../domain/repositories/catalogue_services.dart';

/// Le catalogue des cinq services, lu **dans la base locale**.
///
/// ## Pourquoi ce DAO s'appuie sur celui du point de vente
///
/// Quatre des cinq services vendent exactement ce que vend le comptoir :
/// boissons (M5), circuits (M9), véhicules (M8), et plats (M4 — non répliqué).
/// `CatalogueDao` sait déjà les lire, et sait déjà **dire pourquoi le rayon
/// Restaurant est vide**. En réécrire une seconde version ici produirait deux
/// listes qui finiraient par diverger — c'est le défaut que le maître nomme
/// lui-même à propos des canaux (`reservations.html` l.131), et il n'y a pas
/// de raison de le réintroduire ailleurs.
///
/// Le cinquième service, l'hébergement, n'existe pas au point de vente : le
/// parc se lit ici.
///
/// ## La disponibilité de l'hébergement dépend des dates
///
/// Une chambre n'est pas « libre » dans l'absolu : elle l'est sur une période.
/// Le statut de l'unité ne dit que l'état du jour — hors service, en
/// nettoyage. Le chevauchement, lui, se calcule sur les dates demandées, et
/// c'est le même calcul que RG-01, pas une seconde version.
///
/// **Sans dates, tout le parc est proposé** : c'est ce que fait le maître pour
/// les véhicules (`reservations-services.js`, catalogue `vehicule`), et pour
/// la même raison — on ne peut rien conclure d'une période inconnue, et
/// masquer arbitrairement serait pire que proposer. Le contrôle définitif a
/// lieu à l'enregistrement.
class CatalogueServicesDao extends DatabaseAccessor<AppDatabase>
    implements CatalogueServices {
  CatalogueServicesDao(super.db) : _pos = CatalogueDao(db);

  final CatalogueDao _pos;

  @override
  Future<List<RayonService>> rayons({
    DateTime? arrivee,
    DateTime? depart,
    String? exclureReservationId,
  }) async {
    final rayonsPos = await _pos.rayons();

    RayonService depuisPos(ServiceReservation service, ModuleVendable module) {
      final rayon = rayonsPos.firstWhere((r) => r.module == module);
      return RayonService(
        service: service,
        options: rayon.articles.map(_depuisArticle).toList(growable: false),
        motifIndisponibilite: rayon.indisponibiliteLocale,
      );
    }

    // L'ordre est celui du maître (`SERVICES`, l.40) : il commande l'ordre des
    // cases à cocher et celui des blocs de lignes.
    return [
      RayonService(
        service: ServiceReservation.hebergement,
        options: await _chambres(
          arrivee: arrivee,
          depart: depart,
          exclureReservationId: exclureReservationId,
        ),
      ),
      depuisPos(ServiceReservation.restauration, ModuleVendable.m4Restaurant),
      depuisPos(ServiceReservation.bar, ModuleVendable.m5Bar),
      depuisPos(ServiceReservation.tourisme, ModuleVendable.m9Tourisme),
      depuisPos(ServiceReservation.vehicule, ModuleVendable.m8Vehicules),
    ];
  }

  /// Un article du point de vente, vu comme une option de service.
  ///
  /// Un article **sans prix** est marqué indisponible plutôt que ramené à
  /// zéro : le point de vente le montre grisé pour la même raison, et un
  /// montant deviné est une perte à chaque service.
  OptionService _depuisArticle(ArticleVendable a) => OptionService(
    id: a.reference.code,
    libelle: a.detail == null ? a.libelle : '${a.libelle} — ${a.detail}',
    prix: a.prix ?? 0,
    disponible: a.estVendable,
  );

  Future<List<OptionService>> _chambres({
    DateTime? arrivee,
    DateTime? depart,
    String? exclureReservationId,
  }) async {
    final lignes =
        await (select(attachedDatabase.unitesHebergementLocal).join([
              innerJoin(
                attachedDatabase.categoriesHebergementLocal,
                attachedDatabase.categoriesHebergementLocal.id.equalsExp(
                  attachedDatabase.unitesHebergementLocal.categorieId,
                ),
              ),
            ])..orderBy([
              OrderingTerm.asc(attachedDatabase.unitesHebergementLocal.numero),
            ]))
            .get();

    // Les unités déjà engagées sur la période demandée. Bornes semi-ouvertes,
    // comme partout ailleurs : arrivée le 10, départ le 12, deux nuits — une
    // réservation qui commence le 12 ne chevauche pas.
    final engagees = <String>{};
    if (arrivee != null && depart != null) {
      final prises =
          await (select(attachedDatabase.reservationsLocal)..where((r) {
                final chevauche =
                    r.statut.equals('annulee').not() &
                    r.dateArrivee.isSmallerThanValue(depart) &
                    r.dateDepart.isBiggerThanValue(arrivee);
                // Une réservation ne s'occupe pas elle-même : en modification,
                // sa propre chambre doit rester proposable, sans quoi rouvrir
                // la fiche la ferait disparaître de sa propre liste.
                return exclureReservationId == null
                    ? chevauche
                    : chevauche & r.id.equals(exclureReservationId).not();
              }))
              .get();
      engagees.addAll(prises.map((r) => r.uniteId));
    }

    return lignes
        .map((l) {
          final unite = l.readTable(attachedDatabase.unitesHebergementLocal);
          final categorie = l.readTable(
            attachedDatabase.categoriesHebergementLocal,
          );
          return OptionService(
            id: unite.id,
            // La forme du maître : « Bungalow Boukari (Lit Double King) (BNG-01) »
            // se réduit ici à la catégorie et au numéro, seules données que porte
            // ce schéma — l'unité n'a pas de nom propre.
            libelle: '${categorie.libelle} (${unite.numero})',
            prix: categorie.tarifBase.round(),
            disponible: unite.statut == 'libre' && !engagees.contains(unite.id),
          );
        })
        .toList(growable: false);
  }
}
