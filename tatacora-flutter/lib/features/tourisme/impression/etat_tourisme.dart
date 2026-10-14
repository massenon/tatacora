import 'dart:convert';

import '../../../core/format/formats.dart';
import '../domain/departs.dart';
import '../domain/entities/circuit.dart';
import '../domain/entities/reservation_tour.dart';

/// L'export de M9 — le bouton « Exporter » de l'en-tête de la vue
/// (`tourisme/departs.blade.php` l.116-117), servi côté PWA par
/// `Departs::genererExport()` et `TourismeExport`.
///
/// ## Un export porte sur CE QUI EST AFFICHÉ, et il DIT son filtre (PA-119)
///
/// Un état par onglet, aux en-têtes de `TourismeExport::entetesDe()` — relus
/// sur le fichier PHP par `etat_tourisme_test.dart`, jamais recopiés d'après
/// mémoire. Les lignes sont celles que l'onglet affiche, filtres compris ; la
/// première ligne du fichier nomme ces filtres.
///
/// ## « Excel » est rendu en CSV, et l'écart est nommé
///
/// Convention serveur RG-19 : BOM UTF-8 et point-virgule. Aucune bibliothèque
/// XLSX n'est embarquée (même écart que PA-111). Le PDF n'est pas produit sur
/// ce poste : aucun état A4 de M9 n'est classé dans l'en-tête et les visas de
/// l'application (arbitrage PA-192, 09/10/2026).
///
/// ## Les colonnes sans source partent VIDES, jamais à zéro
///
/// « N° », « Véhicule », « Acompte », « Reste dû » et « Indicatif € » n'ont
/// aucune colonne au schéma (vérifié le 09/10/2026 contre `lib/core/database/
/// tables/` : `reservations_tour_local` ne porte ni numéro, ni véhicule, ni
/// acompte ; `circuits_local` ni indicatif). Une case vide dit « la donnée
/// n'existe pas » ; un « 0 » dirait « soldé » ou « gratuit ». Le serveur écrit
/// « — » à leur place : dans un tableur, un tiret casse le typage de la
/// colonne, la case vide non — l'écart est volontaire et la mention du fichier
/// le dit.
final class EtatTourisme {
  const EtatTourisme({
    required this.titre,
    required this.filtre,
    required this.entetes,
    required this.lignes,
    this.mentions = const [],
  });

  /// Le libellé de l'onglet exporté : « Départs planifiés », « Réservations »
  /// ou « Catalogue » (`TourismeExport::title()`).
  final String titre;

  /// La description du filtre appliqué (`Departs::descriptionDuFiltre()`).
  final String filtre;

  final List<String> entetes;

  /// Une valeur `null` s'écrit **vide**, jamais « 0 » ni « — ».
  final List<List<String?>> lignes;

  /// Ce que ce document ne peut pas porter, écrit **dans le fichier** : une
  /// mention qui borne la portée d'un document s'imprime avec lui (PA-135).
  final List<String> mentions;

  bool get vide => lignes.isEmpty;

  /// Le CSV : BOM, titre et filtre, mentions, en-têtes, lignes.
  String csv() {
    final tampon = StringBuffer('\u{FEFF}')
      ..writeln('${_e(titre)};${_e(filtre)}')
      ..writeln();

    for (final m in mentions) {
      tampon.writeln(_e(m));
    }
    if (mentions.isNotEmpty) tampon.writeln();

    tampon.writeln(entetes.map(_e).join(';'));

    for (final ligne in lignes) {
      tampon.writeln(ligne.map((c) => _e(c ?? '')).join(';'));
    }

    return tampon.toString();
  }

  /// Les OCTETS du fichier : de l'UTF-8 réel. `codeUnits` serait faux — ce
  /// sont des unités UTF-16, que `writeAsBytes` tronque à un octet (le BOM
  /// deviendrait 0xFF, le tiret long 0x14).
  List<int> csvOctets() => utf8.encode(csv());

  static String _e(String v) => v.replaceAll(';', ',').replaceAll('\n', ' ');

  /// Les en-têtes de `TourismeExport::entetesDe()`, onglet par onglet.
  static const List<String> entetesDeparts = [
    'N°',
    'Circuit',
    'Départ',
    'Guide',
    'Véhicule',
    'Remplissage',
    'Prix / pers.',
    'CA',
    'État',
  ];

  static const List<String> entetesReservations = [
    'N°',
    'Client',
    'Circuit',
    'Départ',
    'Pers.',
    'Prix / pers.',
    'Montant',
    'Acompte',
    'Reste dû',
  ];

  static const List<String> entetesCatalogue = [
    'Prestation',
    'Type',
    'Durée',
    'Zone / thème',
    'Prix',
    'Indicatif €',
    'Départs planifiés',
  ];

  /// L'état de l'onglet « Départs planifiés ».
  ///
  /// La colonne « État » reprend ce que l'écran affiche (Annulé, Complet,
  /// « N place(s) ») : le serveur y écrit « Planifiés » ou « Annulé », ce qui
  /// perdrait l'information qui décide d'une vente.
  static EtatTourisme departs(List<Depart> departs, {required String filtre}) {
    return EtatTourisme(
      titre: 'Départs planifiés',
      filtre: filtre,
      entetes: entetesDeparts,
      lignes: [
        for (final d in departs)
          [
            null,
            d.circuitNom,
            formaterDate(d.date),
            d.guideNom,
            null,
            '${d.placesVendues}/${d.capacite}',
            d.prixUnitaire.toString(),
            d.chiffreAffaires.toString(),
            _etatDepart(d),
          ],
      ],
      mentions: const [
        'Colonnes « N° » et « Véhicule » vides : aucune n\'a de colonne sur '
            'ce poste. Une case vide dit « la donnée n\'existe pas ».',
        'Colonne « État » : celle de l\'écran (Annulé, Complet, ou le nombre '
            'de places restantes).',
      ],
    );
  }

  /// L'état de l'onglet « Réservations ».
  static EtatTourisme reservations(
    List<ReservationTour> reservations, {
    required String filtre,
  }) {
    return EtatTourisme(
      titre: 'Réservations',
      filtre: filtre,
      entetes: entetesReservations,
      lignes: [
        for (final r in reservations)
          [
            null,
            r.clientNom,
            r.circuitNom,
            formaterDate(r.dateCircuit),
            r.nbParticipants.toString(),
            r.prixUnitaire.toString(),
            r.montant.toString(),
            null,
            null,
          ],
      ],
      mentions: const [
        'Colonnes « N° », « Acompte » et « Reste dû » vides : aucune n\'a de '
            'colonne sur ce poste. Un « 0 » dirait « soldé » ; une case vide '
            'dit « la donnée n\'existe pas ».',
        'Colonne « Montant » : le prix du circuit AU MOMENT DE L\'EXPORT '
            'multiplié par les personnes. Aucune colonne ne fige le prix à la '
            'réservation.',
      ],
    );
  }

  /// L'état de l'onglet « Catalogue ».
  ///
  /// [departsParCircuit] est le compte de l'écran : un circuit absent de la
  /// table n'a aucun départ dans la période, et l'écran y écrit « — ». Le
  /// fichier fait de même (case vide).
  static EtatTourisme catalogue(
    List<Circuit> circuits, {
    required Map<String, int> departsParCircuit,
    required String filtre,
  }) {
    return EtatTourisme(
      titre: 'Catalogue',
      filtre: filtre,
      entetes: entetesCatalogue,
      lignes: [
        for (final c in circuits)
          [
            c.nom,
            Circuit.type,
            c.duree,
            '${c.zone} · ${c.theme}',
            c.prix.toString(),
            null,
            departsParCircuit[c.id]?.toString(),
          ],
      ],
      mentions: const [
        'Colonne « Indicatif € » vide : aucune colonne d\'indicatif en euros '
            'ne figure au schéma.',
        'Colonne « Départs planifiés » vide : aucun départ dans la période '
            'affichée (comme l\'écran).',
        'Colonne « Durée » vide : aucune durée renseignée au catalogue.',
      ],
    );
  }

  static String _etatDepart(Depart d) => switch (d.etat) {
    EtatDepart.annule => 'Annulé',
    EtatDepart.complet => 'Complet',
    EtatDepart.placesDisponibles => '${d.placesRestantes} place(s)',
  };
}
