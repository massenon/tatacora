/// Les SIX rapports de la modale « Générer un rapport » de l'accueil —
/// `Accueil::lignesRapport()` et `enTetesRapport()`, répliqués en fonctions
/// PURES (lot C du plan du PO, 14/10/2026).
///
/// | Rapport | Méthode du serveur | Source sur ce poste |
/// |---|---|---|
/// | Synthèse du tableau de bord | `lignesIndicateurs(indicateurs())` | la bande ([TableauDeBord]) |
/// | Liste des réservations | `lignesReservationsRapport` | `ReservationDao` |
/// | État des stocks | `lignesStocksRapport` (`articlesCritiques()`) | [articlesCritiques] |
/// | État de créances | `lignesCreancesRapport` | [creancesParAnciennete] |
/// | État de recettes | `lignesRecettesRapport` (`faitsCroises` ventes + réservations) | `faitsCroises` |
/// | État de ventes | `lignesVentesRapport` (`faitsCroises` ventes) | `faitsCroises` |
///
/// Les cellules sont au FORMAT DU SERVEUR : montants en chaîne décimale brute
/// (« 12000.00 »), dates `d/m/Y`, tiret pour une valeur absente — jamais un
/// zéro. Une liste VIDE se refuse ([messageRapportVide], PA-119).
///
/// ⚠ Synthèse : le serveur calcule ses huit indicateurs ; ce poste en établit
/// sept — « Dépenses cumulées » reste « — » avec sa raison
/// (`RaisonsTableauDeBord.depensesCumulees`). Le document porte le tiret, pas
/// un chiffre de remplacement.
library;

import '../../comptabilite/domain/montant_comptable.dart';
import '../../hebergement/domain/entities/reservation.dart';
import '../../stocks/domain/entities/etat_stock.dart';
import 'croise_local.dart';
import 'entities/tableau_de_bord.dart';
import 'modules_pilotage.dart';

/// `Accueil::TYPES_RAPPORT`, dans l'ordre de la vue, avec leurs libellés
/// (`accueil_pwa.modale_rapport.*`).
enum TypeRapportAccueil {
  synthese('synthese', 'Synthèse du tableau de bord'),
  reservations('reservations', 'Liste des réservations'),
  stocks('stocks', 'État des stocks'),
  creances('creances', 'État de créances'),
  recettes('recettes', 'État de recettes'),
  ventes('ventes', 'État de ventes');

  const TypeRapportAccueil(this.code, this.libelle);

  final String code;
  final String libelle;

  /// `enTetesRapport($type)` — les colonnes du maître, au mot.
  List<String> get entetes => switch (this) {
    TypeRapportAccueil.reservations => const [
      'Client',
      'Canal',
      'Arrivée',
      'Départ',
      'Total',
      'Reste dû',
    ],
    TypeRapportAccueil.stocks => const [
      'Article',
      'Quantité',
      "Seuil d'alerte",
      'État',
    ],
    TypeRapportAccueil.creances => const [
      "Tranche d'ancienneté",
      'Pièces',
      'Montant dû',
    ],
    TypeRapportAccueil.recettes => const [
      'Date',
      'Mouvements',
      "Chiffre d'affaires",
      'Encaissé',
      'Écart (créances)',
    ],
    TypeRapportAccueil.ventes => const [
      'Date',
      'Produit / service',
      'Activité',
      'Point de vente',
      'Quantité',
      'Montant',
      'Mode de paiement',
    ],
    TypeRapportAccueil.synthese => const ['Indicateur', 'Valeur', 'Détail'],
  };
}

/// `accueil_pwa.modale_rapport.vide`.
const String messageRapportVide =
    "Il n'y a rien à exporter sur cette période : le document ne sera pas "
    'produit.';

/// `accueil_pwa.modale_rapport.stocks_etat`.
const String etatSousLeSeuil = "Sous le seuil d'alerte";

String _francs(int francs) => chaineDepuisCentimes(francs * 100);

String _jour(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/${d.year}';

/// `lignesIndicateurs` : libellé de la carte, valeur, variation — « — » pour
/// une variation absente (`null` n'est pas « 0 % ») ET pour un indicateur que
/// ce poste n'établit pas.
List<List<String>> lignesSyntheseRapport(
  TableauDeBord tableau,
  Map<String, String> libelles,
) => [
  for (final i in tableau.indicateurs)
    [
      libelles[i.cle] ?? i.cle,
      i.estDisponible ? i.valeur : '—',
      (i.estDisponible ? i.variationPct : null) ?? '—',
    ],
];

/// `lignesReservationsRapport` : réservations NON annulées dont l'arrivée
/// tombe entre le premier jour de la période et le lendemain de sa fin
/// (`whereBetween(date_arrivee, [debut, fin])` sur des DATES — le lendemain
/// compte, défaut du serveur déjà répliqué par `faitsCroises`). Tri : arrivée
/// puis identifiant.
List<List<String>> lignesReservationsRapport({
  required List<Reservation> reservations,
  required DateTime debut,
  required DateTime finExclue,
}) {
  final premier = DateTime(debut.year, debut.month, debut.day);
  final dernier = DateTime(finExclue.year, finExclue.month, finExclue.day);
  bool dedans(DateTime d) {
    final j = DateTime(d.year, d.month, d.day);
    return !j.isBefore(premier) && !j.isAfter(dernier);
  }

  final retenues =
      [
        for (final r in reservations)
          if (r.statut != StatutReservation.annulee &&
              dedans(r.periode.arrivee))
            r,
      ]..sort((a, b) {
        final c = a.periode.arrivee.compareTo(b.periode.arrivee);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
  return [
    for (final r in retenues)
      [
        r.clientNom,
        r.canal?.libelle ?? '—',
        _jour(r.periode.arrivee),
        _jour(r.periode.depart),
        _francs(r.montantTotal),
        _francs(r.resteAPayer),
      ],
  ];
}

/// `lignesStocksRapport` : ce que « Stocks critiques » affiche déjà —
/// chaque ligne SOUS le seuil par construction.
List<List<String>> lignesStocksRapport(List<LigneStock> critiques) => [
  for (final l in critiques)
    [l.libelle, l.stock, l.seuilAlerte, etatSousLeSeuil],
];

/// `lignesCreancesRapport` : les quatre tranches du graphique.
List<List<String>> lignesCreancesRapport(List<TrancheCreance> tranches) => [
  for (final t in tranches)
    [
      libellesTranchesCreances[t.cle] ?? t.cle,
      '${t.pieces}',
      chaineDepuisCentimes(t.montantCentimes),
    ],
];

/// `jour` (`d/m/Y`) → `jour_iso` (`Y-m-d`), la clé de tri chronologique.
String _iso(String jour) {
  final p = jour.split('/');
  return p.length == 3 ? '${p[2]}-${p[1]}-${p[0]}' : jour;
}

/// `lignesRecettesRapport` : par jour, sur les faits Ventes ET Réservations
/// (la même table que le tableau croisé) — date, mouvements, chiffre
/// d'affaires, encaissé, écart (CA − encaissé). Tri chronologique.
List<List<String>> lignesRecettesRapport(List<FaitCroise> faits) {
  final parJour = <String, ({String jour, int ca, int encaisse, int lignes})>{};
  for (final f in faits) {
    final jour = f.valeur(AxeCroise.jour);
    final iso = _iso(jour);
    final avant = parJour[iso];
    parJour[iso] = (
      jour: jour,
      ca: (avant?.ca ?? 0) + f.montant,
      encaisse: (avant?.encaisse ?? 0) + f.encaisse,
      lignes: (avant?.lignes ?? 0) + 1,
    );
  }
  final cles = parJour.keys.toList()..sort();
  return [
    for (final k in cles)
      [
        parJour[k]!.jour,
        '${parJour[k]!.lignes}',
        _francs(parJour[k]!.ca),
        _francs(parJour[k]!.encaisse),
        _francs(parJour[k]!.ca - parJour[k]!.encaisse),
      ],
  ];
}

/// `lignesVentesRapport` : un fait Ventes par ligne, chronologique (`usort`
/// stable sur `jour_iso`) — date, produit, activité, point de vente, quantité,
/// montant, mode.
List<List<String>> lignesVentesRapport(List<FaitCroise> faits) {
  final indexes = List<int>.generate(faits.length, (i) => i)
    ..sort((a, b) {
      final c = _iso(
        faits[a].valeur(AxeCroise.jour),
      ).compareTo(_iso(faits[b].valeur(AxeCroise.jour)));
      return c != 0 ? c : a.compareTo(b);
    });
  return [
    for (final i in indexes)
      [
        faits[i].valeur(AxeCroise.jour),
        faits[i].valeur(AxeCroise.libelle),
        faits[i].valeur(AxeCroise.activite),
        faits[i].valeur(AxeCroise.tiers),
        '${faits[i].quantite}',
        _francs(faits[i].montant),
        faits[i].valeur(AxeCroise.mode),
      ],
  ];
}
