// Vue Blade maîtresse (PA-183) : pwa/hebergement/reservations.blade.php
import 'package:uuid/uuid.dart';

import '../entities/fiche_reservation.dart';
import '../entities/periode_sejour.dart';
import '../entities/reservation.dart';
import '../entities/service_reservation.dart';
import '../entities/unite_hebergement.dart';
import '../repositories/reservation_repository.dart';

/// Crée une réservation d'hébergement.
///
/// ## L'identifiant naît ici, pas à l'envoi
///
/// L'UUID v4 est posé **à la création de l'objet**. C'est ce qui rend
/// l'opération idempotente : si le réseau coupe après que le serveur a traité
/// la demande mais avant que la réponse n'arrive, le client la renverra — et
/// le serveur, reconnaissant le même identifiant, n'en appliquera qu'une.
/// Générer l'identifiant au moment de l'envoi produirait un doublon à chaque
/// coupure mal placée.
///
/// ## Le contrôle de chevauchement local est nécessaire mais pas suffisant
///
/// Il donne une réponse immédiate au comptoir, sans réseau. Mais il ne voit
/// que ce que ce poste connaît : un autre poste a pu réserver la même chambre
/// entre-temps. Le serveur reste seul juge — il voit tous les postes et pose
/// un verrou pessimiste. Un refus local est donc **certain** ; une acceptation
/// locale ne l'est pas, et la réservation part en `local`, pas en
/// `synchronise`.
final class CreerReservation {
  CreerReservation(this._depot, {Uuid? uuid, DateTime Function()? maintenant})
    : _uuid = uuid ?? const Uuid(),
      _maintenant = maintenant ?? DateTime.now;

  final ReservationRepository _depot;
  final Uuid _uuid;

  /// Injectable : un test qui dépend de l'heure réelle échoue un jour sur mille.
  final DateTime Function() _maintenant;

  /// [typeClient], [canal], [modePaiement] et la remise viennent de la FICHE
  /// du maitre (`prototype_v2/pages/reservations.html`). Ils sont **optionnels
  /// et non defaultes** : un appelant qui ne les connait pas — la
  /// synchronisation descendante, un test de disponibilite — ne doit pas se
  /// voir attribuer « Physique » par la signature. Une origine inventee fausse
  /// l'analyse par canal sans que rien ne le signale.
  ///
  /// [auteurId] nomme celui qui encaisse l'acompte (RG-15) : un acompte encaisse
  /// produit sa piece comptable dans la meme transaction que la reservation
  /// (regle du PO du 31/08/2026), et une piece sans auteur est refusee.
  Future<Reservation> call({
    required UniteHebergement unite,
    required String clientId,
    required String clientNom,
    required PeriodeSejour periode,
    int acompte = 0,
    TypeClient? typeClient,
    CanalReservation? canal,
    ModePaiementReservation? modePaiement,
    TypeRemise? remiseType,
    num? remiseValeur,
    List<LigneService> lignes = const [],
    required String auteurId,
  }) async {
    if (!unite.statut.estLouable) {
      throw UniteIndisponible(
        'L’unité ${unite.numero} est hors service : elle ne peut être réservée '
        'à aucune date.',
      );
    }

    final maintenant = _maintenant();
    // On compare des JOURS (année/mois/jour tels que saisis), jamais des instants : le
    // sélecteur rend minuit LOCAL, qui à Cotonou (UTC+1) précède minuit UTC — une
    // arrivée « aujourd'hui » était refusée comme « dans le passé » (constat du PO).
    final jourArrivee = DateTime.utc(
      periode.arrivee.year,
      periode.arrivee.month,
      periode.arrivee.day,
    );
    if (jourArrivee.isBefore(
      DateTime.utc(maintenant.year, maintenant.month, maintenant.day),
    )) {
      throw ArgumentError.value(
        periode.arrivee,
        'arrivee',
        'Une arrivée dans le passé fausserait la disponibilité de toutes les '
            'périodes antérieures.',
      );
    }

    // ---- Les services inclus ---------------------------------------------
    //
    // Le maitre rend la selection OBLIGATOIRE (`reservations.html` l.144,
    // asterisque rouge) : une reservation sans service ne designe rien. Le
    // refus est LOCAL et immediat, comme le refus de chevauchement.
    final renseignees = lignes.where((l) => l.estRenseignee).toList();
    if (lignes.isNotEmpty && renseignees.isEmpty) {
      throw ArgumentError.value(
        lignes.length,
        'lignes',
        'Aucune ligne de service n a d element choisi.',
      );
    }

    // RÉSERVATION MULTI-CHAMBRES (décision du PO du 10/11/2026 : « pour UNE SEULE réservation un
    // client peut réserver UNE ou PLUSIEURS chambres »). La PREMIÈRE chambre vit sur
    // `reservations.unite_id` ; les suivantes partent comme lignes de service `hebergement` (le
    // serveur les range, les verrouille et les rend à tous les postes). Il faut au moins une
    // chambre — le serveur écrit `unite_id` NOT NULL, une fiche de circuit seul ne passe pas par
    // ici — et jamais deux fois la même.
    final chambres = renseignees
        .where((l) => l.service == ServiceReservation.hebergement)
        .toList();
    if (renseignees.isNotEmpty && chambres.isEmpty) {
      throw ArgumentError.value(
        0,
        'lignes',
        'Une réservation doit porter au moins une chambre : le serveur '
            'l’enregistre sur une unité d’hébergement.',
      );
    }
    final vues = <String>{};
    for (final chambre in chambres) {
      if (!vues.add(chambre.itemId)) {
        throw ArgumentError.value(
          chambre.itemId,
          'lignes',
          'La chambre « ${chambre.libelle} » figure deux fois dans la '
              'réservation : une chambre ne se réserve qu’une fois.',
        );
      }
    }

    if (acompte < 0) {
      throw ArgumentError.value(
        acompte,
        'acompte',
        'Un acompte ne peut pas être négatif.',
      );
    }
    // Le montant de reference, c'est le RECAPITULATIF, pas la seule chambre.
    // Controler l'acompte contre le tarif d'hebergement seul refuserait un
    // acompte parfaitement legitime des qu'un circuit entre dans la fiche.
    final montant = renseignees.isEmpty
        ? unite.tarifBase * periode.nuits
        : renseignees.fold(0, (somme, l) => somme + l.sousTotal);
    if (acompte > montant) {
      // Un acompte supérieur au dû transformerait la créance en dette envers
      // le client, sans qu'aucun écran ne le montre.
      throw ArgumentError.value(
        acompte,
        'acompte',
        'L’acompte ($acompte FCFA) dépasse le montant du séjour ($montant FCFA).',
      );
    }

    // Contrôle local — voir le docblock de classe sur sa portée. Il vise CHAQUE chambre de la
    // réservation, la principale comme les supplémentaires, et nomme celle qui est prise.
    final conflits = await _depot.consulterDisponibilites(periode);
    final chambresVisees = <String>{unite.id, ...chambres.map((l) => l.itemId)};
    for (final uniteId in chambresVisees) {
      final surCetteUnite = conflits
          .where((d) => d.unite.id == uniteId)
          .toList();
      if (surCetteUnite.isNotEmpty && !surCetteUnite.first.disponible) {
        final conflit = surCetteUnite.first.reservationEnConflit;
        if (conflit != null) {
          throw ChevauchementDetecte(
            uniteId: uniteId,
            reservationEnConflit: conflit,
          );
        }
        throw UniteIndisponible(
          'L’unité ${surCetteUnite.first.unite.numero} n’est pas disponible '
          'sur cette période.',
        );
      }
    }

    final reservation = Reservation(
      id: _uuid.v4(),
      // Référence PROVISOIRE : la numérotation continue exigée par la
      // facturation appartient au serveur. La marquer comme telle évite qu'un
      // client reparte avec un numéro qui changera.
      reference: 'LOC-${_uuid.v4().substring(0, 8).toUpperCase()}',
      clientId: clientId,
      clientNom: clientNom,
      uniteId: unite.id,
      periode: periode,
      // Tarif FIGÉ : reprendre le tarif courant ferait varier le montant d'une
      // réservation passée à chaque changement de grille.
      tarifNuit: unite.tarifBase,
      // `en_attente`, jamais `confirmee` : le serveur n'accepte pas `statut` a
      // la creation et applique ce defaut. Creer en « confirmee » ferait
      // regresser l'affichage a la premiere synchronisation — le client verrait
      // sa reservation passer de confirmee a en attente.
      statut: StatutReservation.enAttente,
      statutSynchronisation: StatutSynchronisation.local,
      creeeLe: maintenant,
      acompte: acompte,
      typeClient: typeClient,
      canal: canal,
      modePaiement: modePaiement,
      // « Aucune » n'est pas une remise : la ranger comme telle ferait
      // apparaitre une ligne de remise a zero sur une reservation qui n'en a
      // pas. La valeur ne suit que si le type la rend lisible.
      remiseType: remiseType == TypeRemise.aucune ? null : remiseType,
      remiseValeur: remiseType == null || remiseType == TypeRemise.aucune
          ? null
          : remiseValeur,
      // Les lignes SANS choix ne sont pas enregistrees : le maitre les laisse
      // vivre a l'ecran le temps de la saisie, elles ne designent rien une
      // fois la fiche fermee.
      lignes: renseignees,
    );

    // La réservation ET la pièce de son acompte, dans la même transaction.
    return _depot.creer(reservation, auteurId: auteurId);
  }
}
