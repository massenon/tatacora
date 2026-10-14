import '../entities/fiche_reservation.dart';
import '../entities/periode_sejour.dart';
import '../entities/reservation.dart';
import '../entities/service_reservation.dart';
import '../entities/unite_hebergement.dart';
import '../repositories/reservation_repository.dart';

/// Modifie une réservation existante.
///
/// ## L'identifiant NE CHANGE PAS, et c'est tout le sujet
///
/// La réservation garde son UUID. C'est lui qui rend la modification
/// idempotente : le serveur reconnaît l'enregistrement et le met à jour, au
/// lieu d'en créer un second. Générer un nouvel identifiant produirait deux
/// réservations sur la même chambre — la première n'étant supprimée nulle
/// part, elle continuerait de bloquer le planning.
///
/// L'opération part donc en file avec le type **`modification`**, jamais
/// `creation`.
///
/// ## Le contrôle de chevauchement EXCLUT la réservation elle-même
///
/// Sans cette exclusion, rouvrir une réservation pour corriger un acompte
/// serait refusé : sa propre chambre apparaîtrait « déjà réservée », par
/// elle-même. C'est le `exclureReservationId` du maître
/// (`reservations-engine.js`, `occupationSurPeriode`), et il n'a rien
/// d'optionnel — sans lui, l'écran d'édition ne peut rien enregistrer.
///
/// Le contrôle est **refait entièrement**, pas seulement quand les dates
/// changent : entre la création et la modification, un autre poste a pu
/// réserver la même chambre, et c'est justement au moment d'écrire qu'il faut
/// le savoir. Un contrôle conditionnel laisserait passer exactement le cas
/// qu'il existe pour attraper.
///
/// ## Ce que la modification NE fait pas
///
/// Elle ne ressuscite pas une réservation annulée. Une annulation libère
/// l'unité et se voit à l'historique ; la « dé-annuler » par une modification
/// réengagerait une chambre que le planning montre libre depuis, et que
/// quelqu'un a pu revendre entre-temps. Le refus est explicite.
///
/// @see EF-M1-03
/// @see RG-01
final class ModifierReservation {
  const ModifierReservation(this._depot);

  final ReservationRepository _depot;

  /// [existante] est la réservation **relue en base**, pas celle qu'un écran
  /// garde en mémoire depuis son ouverture : entre-temps, le serveur a pu la
  /// rejeter ou l'annuler.
  Future<Reservation> call({
    required Reservation existante,
    required UniteHebergement unite,
    required String clientNom,
    required PeriodeSejour periode,
    int acompte = 0,
    TypeClient? typeClient,
    CanalReservation? canal,
    ModePaiementReservation? modePaiement,
    TypeRemise? remiseType,
    num? remiseValeur,
    List<LigneService> lignes = const [],
  }) async {
    if (existante.statut == StatutReservation.annulee) {
      throw ArgumentError.value(
        existante.statut.code,
        'statut',
        'Une réservation annulée ne se modifie pas : elle a libéré son unité, '
            'et la réengager ici passerait par-dessus une chambre peut-être '
            'revendue depuis. Créez une nouvelle réservation.',
      );
    }

    if (!unite.statut.estLouable) {
      throw UniteIndisponible(
        'L’unité ${unite.numero} est hors service : elle ne peut être réservée '
        'à aucune date.',
      );
    }

    final renseignees = lignes.where((l) => l.estRenseignee).toList();
    final chambres = renseignees
        .where((l) => l.service == ServiceReservation.hebergement)
        .toList();

    // Les deux mêmes refus qu'à la création, et pour la même raison : le
    // schéma serveur ne porte qu'une `unite_id`, NOT NULL. Les recopier ici
    // plutôt que de les partager est un choix — ils tiennent en six lignes, et
    // une fabrique commune masquerait qu'ils s'appliquent à deux gestes
    // distincts, dont l'un pourrait être arbitré autrement.
    if (renseignees.isNotEmpty && chambres.isEmpty) {
      throw ArgumentError.value(
        0,
        'lignes',
        'Une réservation doit porter exactement une chambre : le serveur '
            'l’enregistre sur une unité d’hébergement.',
      );
    }
    if (chambres.length > 1) {
      throw ArgumentError.value(
        chambres.length,
        'lignes',
        'Une réservation ne peut porter qu’une seule chambre : le serveur '
            'n’en enregistre qu’une, et les suivantes seraient perdues sans '
            'que rien ne le signale. Créez une réservation par chambre.',
      );
    }

    if (acompte < 0) {
      throw ArgumentError.value(
        acompte,
        'acompte',
        'Un acompte ne peut pas être négatif.',
      );
    }
    final montant = renseignees.isEmpty
        ? unite.tarifBase * periode.nuits
        : renseignees.fold(0, (somme, l) => somme + l.sousTotal);
    if (acompte > montant) {
      throw ArgumentError.value(
        acompte,
        'acompte',
        'L’acompte ($acompte FCFA) dépasse le montant du séjour ($montant FCFA).',
      );
    }

    // Contrôle local, **la réservation modifiée étant exclue**.
    final conflits = await _depot.consulterDisponibilites(
      periode,
      exclureReservationId: existante.id,
    );
    final surCetteUnite = conflits
        .where((d) => d.unite.id == unite.id)
        .toList();
    if (surCetteUnite.isNotEmpty && !surCetteUnite.first.disponible) {
      final conflit = surCetteUnite.first.reservationEnConflit;
      if (conflit != null) {
        throw ChevauchementDetecte(
          uniteId: unite.id,
          reservationEnConflit: conflit,
        );
      }
      throw UniteIndisponible(
        'L’unité ${unite.numero} n’est pas disponible sur cette période.',
      );
    }

    final modifiee = Reservation(
      // L'identifiant, la référence et la date de création NE bougent pas :
      // c'est la même réservation, pas une nouvelle.
      id: existante.id,
      reference: existante.reference,
      clientId: existante.clientId,
      clientNom: clientNom,
      uniteId: unite.id,
      periode: periode,
      // Le tarif suit la chambre RETENUE, dont le prix a été figé au moment où
      // l'utilisateur l'a choisie dans la liste. Reprendre le tarif courant de
      // l'unité ferait varier le montant à chaque changement de grille, y
      // compris quand l'utilisateur n'a fait que corriger un acompte.
      tarifNuit: chambres.isEmpty
          ? existante.tarifNuit
          : chambres.single.prixUnitaire,
      // Le statut métier est conservé : modifier une fiche ne confirme pas un
      // séjour, et ne le déconfirme pas non plus.
      statut: existante.statut,
      // La modification doit repartir au serveur, même si la création avait
      // déjà été synchronisée.
      statutSynchronisation: StatutSynchronisation.local,
      creeeLe: existante.creeeLe,
      acompte: acompte,
      typeClient: typeClient,
      canal: canal,
      modePaiement: modePaiement,
      remiseType: remiseType == TypeRemise.aucune ? null : remiseType,
      remiseValeur: remiseType == null || remiseType == TypeRemise.aucune
          ? null
          : remiseValeur,
      // Le motif de rejet précédent est EFFACÉ : il portait sur la version
      // d'avant, et le laisser afficherait un refus périmé sur une saisie
      // corrigée — le réceptionniste croirait que sa correction a été refusée.
      lignes: renseignees,
    );

    return _depot.modifier(modifiee);
  }
}
