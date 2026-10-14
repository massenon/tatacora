/// L'ÉTAT DU JOUR d'une unité — ce que la pastille d'une carte affiche.
///
/// Vue Blade maîtresse (PA-183) : pwa/hebergement/hebergement.blade.php
///
/// ## Ce que la pastille dit, et ce qu'elle ne dit pas
///
/// L'en-tête de la vue l'écrit en premier, et c'est la règle qui commande tout
/// ce fichier : elle porte la **disponibilité du jour, dérivée des
/// réservations** (RG-02), jamais `unites_hebergement.statut` lu seul, « qui ne
/// connaît ni date ni période ». Une unité réservée pour le 20 août reste
/// parfaitement réservable pour le 5 septembre : lire la colonne pour répondre
/// « cette chambre est-elle libre ? » interdirait toute réservation à l'avance,
/// ce qu'un gîte fait toute l'année.
///
/// La colonne n'est donc lue que pour les **deux états qu'elle est seule à
/// porter** — `nettoyage` et `hors_service` —, exactement comme le fait le
/// composant Livewire (`Hebergement::etatsDuJour()`).
///
/// ## L'ordre des tests EST la règle métier
///
/// Il n'est pas interchangeable, et la vue le dit : « la maintenance prime sur
/// tout (une chambre condamnée ne se vend pas), puis le ménage, puis qui dort
/// là ce soir, puis qui est attendu ».
///
/// ## Un écart avec le serveur, nommé : il n'y a pas de `sejours` ici
///
/// Le composant Livewire distingue « occupée » de « réservée » en regardant la
/// table `sejours` — un check-in réel sans check-out. **Cette table n'est pas
/// répliquée sur le poste** (`app_database.dart` ne la connaît pas), et le
/// geste de check-in n'existe pas côté client : `ReservationDao` est l'unique
/// auteur des écritures de réservation, et le cycle du séjour n'y passe pas.
///
/// L'équivalent local est le **statut métier de la réservation** :
/// `StatutReservation.enCours` dit qu'un client occupe réellement la chambre,
/// là où `confirmee` / `enAttente` dit qu'il est attendu. Ce n'est pas une
/// approximation commode — c'est la seule source que ce poste détient, et elle
/// répond à la même question. L'écart est écrit ici plutôt que dissimulé
/// derrière une égalité de façade.
library;

import 'reservation.dart';
import 'unite_hebergement.dart';

/// Les cinq états du jour de la vue, avec **ses** libellés.
///
/// Les libellés viennent de `lang/fr` à l'apostrophe près :
/// `pwa.hebergement.pastille_libre` / `pastille_reservee` /
/// `pastille_hors_service`, et `hebergement_pwa.hebergement.pastille_occupee` /
/// `pastille_nettoyage`.
///
/// ⚠ Ce ne sont **pas** les valeurs de `unites_hebergement.statut` : deux
/// seulement coïncident avec la colonne. Les confondre est exactement ce que
/// l'en-tête de la vue interdit.
enum EtatDuJour {
  libre('libre', 'Libre'),
  reservee('reservee', 'Réservée'),
  occupee('occupee', 'Occupée'),
  nettoyage('nettoyage', 'Nettoyage'),
  horsService('hors_service', 'Hors service');

  const EtatDuJour(this.cle, this.libelle);

  /// La clé de la vue (`COULEURS_STATUT`), jamais l'index de l'enum — qui
  /// changerait au premier réordonnancement.
  final String cle;

  /// Le libellé de la pastille, mot pour mot.
  final String libelle;

  /// L'unité est-elle retirée de ce qui se vend ?
  ///
  /// `hors_service` **est l'archive de ce schéma** : aucune table d'archives
  /// n'existe, et c'est le seul état qui retire l'unité de la vente sans rien
  /// effacer — réversible, exactement ce que la modale promet (« reste
  /// restaurable — rien n'est effacé »).
  bool get estArchivee => this == EtatDuJour.horsService;
}

/// L'état du jour d'une unité, dérivé des réservations qui la concernent.
///
/// [reservations] n'a pas besoin d'être filtré sur l'unité : la fonction s'en
/// charge. [aujourdHui] est injecté plutôt que lu de l'horloge — un test qui
/// dépend de `DateTime.now()` échoue un jour sur deux, à minuit.
EtatDuJour etatDuJourDe(
  UniteHebergement unite, {
  required Iterable<Reservation> reservations,
  required DateTime aujourdHui,
}) {
  // 1. La maintenance prime sur tout : une chambre condamnée ne se vend pas,
  //    quelles que soient les réservations qui la visent.
  if (unite.statut == StatutUnite.horsService) return EtatDuJour.horsService;

  // 2. Puis le ménage. La chambre est vide, mais pas prête à recevoir.
  if (unite.statut == StatutUnite.nettoyage) return EtatDuJour.nettoyage;

  // 3. Puis qui dort là ce soir, et 4. qui est attendu.
  //
  // Une réservation ANNULÉE ne retient rien (RG-02) : l'unité redevient
  // disponible immédiatement, et c'est tout l'intérêt de conserver la ligne
  // plutôt que de la supprimer.
  for (final reservation in reservations) {
    if (reservation.uniteId != unite.id) continue;
    if (reservation.statut == StatutReservation.annulee) continue;
    if (!reservation.periode.contient(aujourdHui)) continue;

    return reservation.statut == StatutReservation.enCours
        ? EtatDuJour.occupee
        : EtatDuJour.reservee;
  }

  return EtatDuJour.libre;
}

/// L'état du jour de **tout** le parc, par identifiant d'unité.
///
/// Une seule traversée des réservations pour l'ensemble des unités : la version
/// naïve — une recherche par unité — refait le tour du planning autant de fois
/// qu'il y a de chambres, sur un écran qui les affiche toutes.
Map<String, EtatDuJour> etatsDuJour(
  Iterable<UniteHebergement> parc, {
  required Iterable<Reservation> reservations,
  required DateTime aujourdHui,
}) {
  // Les réservations sont regroupées PAR UNITÉ une fois, puis chaque unité ne
  // lit que les siennes.
  final parUnite = <String, List<Reservation>>{};
  for (final r in reservations) {
    (parUnite[r.uniteId] ??= []).add(r);
  }

  return {
    for (final unite in parc)
      unite.id: etatDuJourDe(
        unite,
        reservations: parUnite[unite.id] ?? const [],
        aujourdHui: aujourdHui,
      ),
  };
}
