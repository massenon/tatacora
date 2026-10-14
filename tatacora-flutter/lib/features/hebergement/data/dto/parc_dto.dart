/// Le parc d'hébergement — catégories et unités.
///
/// ## D'où viennent ces classes (14/09/2026)
///
/// Elles vivaient dans `parc_api.dart`, aux côtés du client HTTP qui
/// descendait `GET /hebergement/parc` (PA-128). Le poste est passé **zéro
/// réseau** : le client a été retiré, ces trois classes sont restées.
///
/// Elles ne sont pas mortes avec lui, et c'est le point : elles sont le
/// **format d'entrée** de [ReservationDao.alignerParc], l'auteur unique du
/// parc local. Le jeu de démonstration (`core/dev/donnees_demonstration.dart`)
/// l'emprunte déjà — c'est aujourd'hui le seul chemin par lequel le parc
/// entre sur un poste neuf.
///
/// ⚠ **PA-128 n'est pas refermée, elle est déplacée.** Sans descente réseau et
/// sans amorçage, `categories_hebergement_local` et `unites_hebergement_local`
/// restent lues partout et écrites nulle part, et un poste neuf ne peut prendre
/// aucune réservation. Le CRUD local du parc est le livrable qui referme ce
/// point ; il n'existe pas encore.
library;

final class ParcDistant {
  const ParcDistant({required this.categories, required this.unites});

  final List<CategorieDistante> categories;
  final List<UniteDistante> unites;

  bool get estVide => categories.isEmpty && unites.isEmpty;
}

final class CategorieDistante {
  const CategorieDistante({
    required this.id,
    required this.libelle,
    required this.capaciteMax,
    required this.tarifBase,
  });

  final String id;
  final String libelle;
  final int capaciteMax;
  final double tarifBase;
}

final class UniteDistante {
  const UniteDistante({
    required this.id,
    required this.categorieId,
    required this.numero,
    required this.statut,
  });

  final String id;
  final String categorieId;
  final String numero;

  /// ⚠ Le cycle opérationnel (`libre`, `occupee`, `reservee`, `nettoyage`,
  /// `hors_service`) — **jamais la disponibilité** : celle-ci dépend de la
  /// période demandée et se déduit des réservations (RG-02, PA-118).
  final String statut;
}
