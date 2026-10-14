// Vue Blade maîtresse (PA-183) : pwa/hebergement/reservations.blade.php
/// L'historique des réservations — états dérivés, filtres et KPI.
///
/// ## Ce que le maître corrige, et qu'il faut porter avec lui
///
/// `assets/js/reservations-engine.js` l.12 nomme le défaut qu'il répare :
/// *« Aucun historique consultable. La page ne montrait que les… »* — la liste
/// principale n'affiche que le présent. Un séjour terminé la semaine dernière
/// n'y est plus, et la question « ce client est-il déjà venu ? » n'a aucune
/// réponse à l'écran.
///
/// ## L'état d'un séjour se DÉDUIT, il ne se stocke pas
///
/// Quatre états — à venir, en cours, terminée, annulée — et un seul est une
/// donnée : l'annulation. Les trois autres se lisent des dates, à la date du
/// jour. Les stocker exigerait de les faire vieillir chaque nuit : un poste
/// éteint une semaine afficherait « à venir » sur un séjour déjà fini, et
/// personne ne verrait que l'indicateur ment (PA-59/60/61). C'est la même
/// règle que l'occupation d'une table de salle (PA-108) : ce qui se déduit ne
/// se range jamais dans une colonne.
///
/// @see prototype_v2/assets/js/reservations-engine.js — `historique`,
///      `kpisHistorique`
/// @see prototype_v2/assets/js/historique-reservations.js — le panneau
/// @see EF-M1-02
library;

import 'reservation.dart';
import 'service_reservation.dart';

/// Où en est le séjour, à la date de consultation.
enum EtatSejour {
  aVenir('a_venir', 'À venir', 'À venir'),
  enCours('en_cours', 'En cours', 'En cours'),
  termine('termine', 'Terminée', 'Terminées'),
  annulee('annulee', 'Annulée', 'Annulées');

  const EtatSejour(this.code, this.libelle, this.libelleFiltre);

  /// Le code du maître, celui des `<option>` du filtre.
  final String code;

  /// Le libellé du FILTRE, au pluriel — celui du maître
  /// (`prototype_v2/pages/reservations.html` l.85-88 : « Terminées »,
  /// « Annulées »).
  ///
  /// Le maître écrit **deux formes** pour le même état, et ce n'est pas une
  /// négligence : une option de filtre désigne un ENSEMBLE de séjours, un
  /// badge en qualifie UN. Les confondre — ce que faisait ce champ, qui
  /// servait aux deux — met « Terminée » dans une liste déroulante qui
  /// sélectionne toutes les réservations terminées.
  final String libelleFiltre;

  final String libelle;

  static EtatSejour? parCode(String? code) {
    if (code == null || code.isEmpty) return null;
    for (final e in values) {
      if (e.code == code) return e;
    }
    return null;
  }

  /// Vrai quand le séjour compte dans les montants.
  ///
  /// Une réservation annulée reste **listée** — elle n'est jamais effacée
  /// (RG-02) — mais elle ne pèse ni sur le chiffre d'affaires ni sur les
  /// nuitées : additionner un séjour qui n'aura pas lieu annoncerait un
  /// encaissement que personne ne fera.
  bool get compteDansLesMontants => this != EtatSejour.annulee;
}

/// Les critères du panneau. Tous facultatifs, tous cumulatifs.
final class FiltreHistorique {
  const FiltreHistorique({
    this.terme = '',
    this.etat,
    this.service,
    this.debut,
    this.fin,
  });

  /// Cherche dans le client, le canal et la référence — les trois entrées par
  /// lesquelles on retrouve une réservation au comptoir.
  final String terme;

  final EtatSejour? etat;
  final ServiceReservation? service;

  /// Fenêtre de séjour. `null` des deux côtés : toutes périodes.
  final DateTime? debut;
  final DateTime? fin;

  bool get estVide =>
      terme.trim().isEmpty &&
      etat == null &&
      service == null &&
      debut == null &&
      fin == null;

  FiltreHistorique copyWith({
    String? terme,
    EtatSejour? etat,
    ServiceReservation? service,
    DateTime? debut,
    DateTime? fin,
    bool viderEtat = false,
    bool viderService = false,
    bool viderDebut = false,
    bool viderFin = false,
  }) => FiltreHistorique(
    terme: terme ?? this.terme,
    etat: viderEtat ? null : (etat ?? this.etat),
    service: viderService ? null : (service ?? this.service),
    debut: viderDebut ? null : (debut ?? this.debut),
    fin: viderFin ? null : (fin ?? this.fin),
  );
}

/// Une ligne du tableau : la réservation, plus ce qui s'en déduit.
final class LigneHistorique {
  const LigneHistorique({
    required this.reservation,
    required this.etat,
    required this.nuits,
    required this.unites,
    required this.services,
    required this.totalAPayer,
    required this.resteAPayer,
  });

  /// Dérive tout ce que la ligne affiche, à la date [maintenant].
  ///
  /// [maintenant] est **injecté** : un historique qui lit l'horloge système
  /// dans son calcul devient intestable aux bornes — et ce sont précisément
  /// les bornes qui comptent ici, le jour d'arrivée et le jour de départ.
  factory LigneHistorique.deriver(
    Reservation r, {
    required DateTime maintenant,
  }) {
    final jour = _jour(maintenant);
    final arrivee = _jour(r.periode.arrivee);
    final depart = _jour(r.periode.depart);

    final etat = r.statut == StatutReservation.annulee
        ? EtatSejour.annulee
        // L'ordre des trois tests est celui du maître, et il n'est pas
        // indifférent : un séjour dont le départ est aujourd'hui est
        // TERMINÉ — la chambre se libère le matin du départ, elle est
        // relouable le soir même.
        : !depart.isAfter(jour)
        ? EtatSejour.termine
        : !arrivee.isAfter(jour)
        ? EtatSejour.enCours
        : EtatSejour.aVenir;

    final recap = r.recapitulatif;

    return LigneHistorique(
      reservation: r,
      etat: etat,
      // Le maître plancherait à une nuit : une arrivée et un départ le même
      // jour restent une nuitée facturée, jamais zéro.
      nuits: r.nuits < 1 ? 1 : r.nuits,
      unites: [
        for (final l in r.lignes)
          if (l.service == ServiceReservation.hebergement) l.itemId,
      ],
      services: {for (final l in r.lignes) l.service}.toList(growable: false),
      totalAPayer: recap.total,
      resteAPayer: recap.reste,
    );
  }

  final Reservation reservation;
  final EtatSejour etat;
  final int nuits;

  /// Les unités d'hébergement engagées, par leur identifiant.
  final List<String> unites;

  final List<ServiceReservation> services;

  /// Après remise — c'est ce que le client doit.
  final int totalAPayer;

  /// Après remise et acompte.
  final int resteAPayer;

  String get client => reservation.clientNom;
  String? get canal => reservation.canal?.libelle;
}

/// Filtre et trie l'historique.
///
/// Fonction **pure** : elle ne lit ni base ni horloge. C'est ce qui permet de
/// l'éprouver aux bornes — le jour d'arrivée, le jour de départ, une
/// réservation à cheval sur la fenêtre demandée.
List<LigneHistorique> filtrerHistorique(
  List<Reservation> reservations, {
  required FiltreHistorique filtre,
  required DateTime maintenant,
}) {
  final terme = filtre.terme.trim().toLowerCase();
  final debut = filtre.debut == null ? null : _jour(filtre.debut!);
  final fin = filtre.fin == null ? null : _jour(filtre.fin!);

  final lignes =
      reservations
          .map((r) => LigneHistorique.deriver(r, maintenant: maintenant))
          .where((l) {
            if (terme.isNotEmpty) {
              final champs = [
                l.reservation.clientNom,
                l.canal ?? '',
                l.reservation.reference,
              ].join(' ').toLowerCase();
              if (!champs.contains(terme)) return false;
            }
            if (filtre.etat != null && l.etat != filtre.etat) return false;
            if (filtre.service != null &&
                !l.services.contains(filtre.service)) {
              return false;
            }

            // **Chevauchement avec la fenêtre demandée, pas inclusion
            // stricte** : une réservation à cheval sur le mois doit apparaître
            // dans les deux mois. L'inclusion stricte ferait disparaître des
            // listes mensuelles exactement les séjours les plus longs.
            if (debut != null &&
                _jour(l.reservation.periode.depart).isBefore(debut)) {
              return false;
            }
            if (fin != null &&
                _jour(l.reservation.periode.arrivee).isAfter(fin)) {
              return false;
            }
            return true;
          })
          .toList()
        // Du séjour le plus récent au plus ancien.
        ..sort(
          (a, b) => b.reservation.periode.arrivee.compareTo(
            a.reservation.periode.arrivee,
          ),
        );

  return lignes;
}

/// Les six indicateurs de l'en-tête du panneau.
final class KpisHistorique {
  const KpisHistorique({
    required this.total,
    required this.aVenir,
    required this.enCours,
    required this.termine,
    required this.annulee,
    required this.nuitees,
    required this.chiffreAffaires,
    required this.resteAEncaisser,
  });

  factory KpisHistorique.calculer(List<LigneHistorique> lignes) {
    var nuitees = 0;
    var chiffreAffaires = 0;
    var resteAEncaisser = 0;

    for (final l in lignes) {
      if (!l.etat.compteDansLesMontants) continue;
      // Une réservation sans unité compte quand même une nuitée par nuit : le
      // maître plancherait à 1. Un séjour porté par deux chambres en compte le
      // double — c'est ce que « nuitée » veut dire dans l'hôtellerie.
      final unites = l.unites.isEmpty ? 1 : l.unites.length;
      nuitees += l.nuits * unites;
      chiffreAffaires += l.totalAPayer;
      resteAEncaisser += l.resteAPayer;
    }

    int compter(EtatSejour e) => lignes.where((l) => l.etat == e).length;

    return KpisHistorique(
      total: lignes.length,
      aVenir: compter(EtatSejour.aVenir),
      enCours: compter(EtatSejour.enCours),
      termine: compter(EtatSejour.termine),
      annulee: compter(EtatSejour.annulee),
      nuitees: nuitees,
      chiffreAffaires: chiffreAffaires,
      // Un reste à payer cumulé est une **créance client** : c'est ce qui
      // alimente le suivi des relances, et c'est pourquoi il est affiché en
      // rouge dès qu'il dépasse zéro.
      resteAEncaisser: resteAEncaisser,
    );
  }

  final int total;
  final int aVenir;
  final int enCours;
  final int termine;
  final int annulee;
  final int nuitees;
  final int chiffreAffaires;
  final int resteAEncaisser;
}

/// Ramène une date à minuit.
///
/// Sans cela, une réservation saisie à 14 h et consultée à 9 h le jour de son
/// arrivée serait annoncée « à venir » alors que le client est au comptoir.
DateTime _jour(DateTime d) => DateTime(d.year, d.month, d.day);
