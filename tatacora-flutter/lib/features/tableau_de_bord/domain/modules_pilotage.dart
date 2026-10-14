/// Les blocs du Pilotage consolidé portés le 13/10/2026 (décision du PO, fin
/// du Pilotage) — FONCTIONS PURES, répliques de `App\Pwa\Livewire\Accueil` :
///
///  * [creancesParAnciennete] — `Accueil::creancesParAnciennete` (le graphique
///    « Créances par ancienneté » et la ligne « Dont + de 90 jours » de la
///    carte Clients & créances) ;
///  * [moduleVehicules] — `Accueil::moduleVehicules` (carte « Location de
///    véhicules »).
///
/// Confrontées au vrai serveur par `tool/tableau_de_bord/rejouer_pilotage.php`.
library;

import '../../facturation/domain/creances.dart';
import '../../vehicules/domain/entities/contrat_location.dart';
import '../../vehicules/domain/entities/vehicule.dart';
import '../../vehicules/domain/indicateurs_vehicules.dart' show sommeDecimales;

/* ======================================================================== */
/* Créances par ancienneté                                                   */
/* ======================================================================== */

/// Une tranche du graphique : sa clé (`0_30`, `30_60`, `60_90`, `plus_90`),
/// le reste dû cumulé et le nombre de pièces.
final class TrancheCreance {
  const TrancheCreance({
    required this.cle,
    required this.montantCentimes,
    required this.pieces,
  });

  final String cle;
  final int montantCentimes;
  final int pieces;
}

/// Les libellés de la vue (`accueil_pwa.creances.tranches`), par clé.
const Map<String, String> libellesTranchesCreances = {
  '0_30': '0 à 30 jours',
  '30_60': '31 à 60 jours',
  '60_90': '61 à 90 jours',
  'plus_90': 'Plus de 90 jours',
};

/// `Accueil::creancesParAnciennete` — les quatre tranches de la BALANCE de
/// l'accueil, sur les factures IMPAYÉES (le prédicat de `SoldeClientService`,
/// [CreanceFacture.estImpayee]), comptées depuis leur date d'ÉMISSION :
///
/// | clé | date d'émission |
/// |---|---|
/// | `0_30` | après J−30 (sans borne haute : une facture datée du futur y entre) |
/// | `30_60` | après J−60, jusqu'à J−30 inclus |
/// | `60_90` | après J−90, jusqu'à J−60 inclus |
/// | `plus_90` | jusqu'à J−90 inclus |
///
/// ⚠ Ce N'EST PAS la balance âgée de l'écran Clients & créances
/// ([TrancheAge.pour], `ClientsCreances::trancheDe`) : une facture de 30 jours
/// pile est en « 31 à 60 jours » ici (bornes semi-ouvertes `>`/`<=` du
/// serveur) et en « 0 à 30 jours » là-bas, et une facture du futur tombe dans
/// « 0 à 30 » ici, dans « plus de 90 » là-bas. Deux règles du SERVEUR,
/// répliquées telles quelles (à l'Architecte : deux balances âgées pour la
/// même créance).
///
/// Le montant est le reste dû BRUT (`SUM(SQL_RESTE_DU)`, sans plancher), comme
/// le serveur.
List<TrancheCreance> creancesParAnciennete(
  List<CreanceFacture> creances,
  DateTime aujourdhui,
) {
  final jour = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day);
  DateTime moins(int jours) =>
      DateTime(jour.year, jour.month, jour.day - jours);

  final bornes = <(String, DateTime?, DateTime?)>[
    // (clé, émission strictement APRÈS, émission jusqu'à INCLUS)
    ('0_30', moins(30), null),
    ('30_60', moins(60), moins(30)),
    ('60_90', moins(90), moins(60)),
    ('plus_90', null, moins(90)),
  ];

  return [
    for (final (cle, apres, jusqua) in bornes)
      () {
        var montant = 0;
        var pieces = 0;
        for (final c in creances) {
          if (!c.estImpayee) continue;
          final e = c.piece.dateEmission;
          final d = DateTime(e.year, e.month, e.day);
          if (apres != null && !d.isAfter(apres)) continue;
          if (jusqua != null && d.isAfter(jusqua)) continue;
          montant += c.resteDuBrutCentimes;
          pieces++;
        }
        return TrancheCreance(
          cle: cle,
          montantCentimes: montant,
          pieces: pieces,
        );
      }(),
  ];
}

/* ======================================================================== */
/* Location de véhicules                                                     */
/* ======================================================================== */

/// La carte M8 du Pilotage.
final class ModuleVehicules {
  const ModuleVehicules({
    required this.parc,
    required this.contratsActifs,
    required this.chiffreAffaires,
    required this.joursLoues,
    required this.immobilises,
  });

  final int parc;
  final int contratsActifs;

  /// Chaîne décimale (`'0.00'` sans contrat) ; `null` si un montant est
  /// illisible — une somme amputée serait plausible et fausse.
  final String? chiffreAffaires;
  final int joursLoues;
  final int immobilises;
}

/// `EcranVehicules::JOURS_PAR_DEFAUT` : la fenêtre de l'écran M8.
const int joursFenetreVehicules = 14;

/// `Accueil::moduleVehicules` : les contrats de la fenêtre [aujourd'hui,
/// aujourd'hui + 14 jours] au sens de `ParcVehiculeService::contratsSurFenetre`
/// — `date_fin >= début` ET `date_debut <= fin`, les DEUX bornes INCLUSES —,
/// agrégés par `agregerContratsActifs` (contrats non annulés ; le poste n'en
/// annule aucun, PA-50 : tous sont actifs), plus le parc et les véhicules
/// immobilisés (`entretien`, `hors_service`).
///
/// ⚠ L'écran Véhicules du poste retient les contrats par un chevauchement
/// STRICT ([ContratLocation.chevauche]) : un contrat qui finit le jour où la
/// fenêtre commence y est exclu, et compté ici comme au serveur. Écart de
/// l'écran du poste, nommé, non corrigé dans ce lot.
ModuleVehicules moduleVehicules({
  required List<Vehicule> parc,
  required List<ContratLocation> contrats,
  required DateTime aujourdhui,
}) {
  String iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
  final debut = iso(aujourdhui);
  final fin = iso(
    DateTime(
      aujourdhui.year,
      aujourdhui.month,
      aujourdhui.day + joursFenetreVehicules,
    ),
  );

  final retenus = [
    for (final c in contrats)
      if (c.fin.compareTo(debut) >= 0 && c.debut.compareTo(fin) <= 0) c,
  ];

  return ModuleVehicules(
    parc: parc.length,
    contratsActifs: retenus.length,
    chiffreAffaires: retenus.isEmpty
        ? '0.00'
        : sommeDecimales(retenus.map((c) => c.montant)),
    joursLoues: retenus.fold(0, (s, c) => s + c.nombreJours),
    immobilises: parc.where((v) => v.statut?.estImmobilise ?? false).length,
  );
}

/// Un `float` PHP rendu par concaténation (`$taux . ' %'`) : un entier s'écrit
/// sans décimale (« 50 »), sinon comme Dart l'écrit (« 66.7 »).
String nombreCommePhp(double v) =>
    v == v.roundToDouble() ? '${v.round()}' : '$v';
