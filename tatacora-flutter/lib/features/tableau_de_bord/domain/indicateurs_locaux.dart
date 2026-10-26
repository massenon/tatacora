/// Les indicateurs de M11 que ce poste peut établir — fonctions PURES.
///
/// Vue Blade maîtresse (PA-183) : `pwa/livewire/accueil.blade.php` ;
/// serveur : `App\Domain\TableauxDeBord\Services\TableauDeBordService`.
///
/// ## Sept indicateurs sur huit depuis le lot 5 (12/10/2026), et pourquoi pas le dernier
///
/// PA-120 : un indicateur dont les tables sources ne sont pas TOUTES détenues
/// sur le poste donne un chiffre plus petit que la réalité, sans le dire.
/// Chaque indicateur a donc été confronté à ses sources (mesuré le
/// 10/10/2026) :
///
/// | Indicateur | Sources | Verdict |
/// |---|---|---|
/// | Taux d'occupation | `reservations_local`, `unites_hebergement_local` | calculé |
/// | Réservations en attente | `reservations_local` | calculé |
/// | Valeur du stock | `articles_local`, `mouvements_stock_local` (M6) | calculé |
/// | Employés actifs | `employes_local` (M13) | calculé |
/// | CA encaissé | `paiements_facture_local` | calculé (v18) : la table est écrite par ce poste |
/// | Trésorerie de caisse | `sessions_caisse_local`, `paiements_facture_local` | calculé (v18), avec les incohérences du serveur répliquées |
/// | Dépenses cumulées | `ecritures_comptables` (classe 6, validées) | **« — »** : source PARTIELLE — seules les dépenses courantes passent une pièce (achats, paie et dépenses d'avant : aucune) |
/// | Factures non soldées | `pieces_facturation_local`, `paiements_facture_local`, `reservations_local` | calculé (v18) |
///
/// Les dépenses saisies existent (`depenses_local`), mais l'indicateur du
/// serveur est un solde de CLASSE 6 VALIDÉE : y poser la somme des dépenses
/// courantes manquerait les achats, la paie et les régularisations, et
/// porterait un nom qui promet le tout. Elles ont leur propre carte au pilotage.
///
/// ## Des règles RECOPIÉES du serveur, donc CONFRONTÉES au serveur
///
/// `test/features/tableau_de_bord/indicateurs_contre_serveur_test.dart`
/// exécute le vrai `TableauDeBordService` (PHP) sur le même scénario et compare
/// chaque mesure, variation comprise. Une formule recopiée sans cette épreuve
/// ne vérifierait qu'elle-même (piège 12).
library;

import '../../caisse/domain/entities/session_caisse.dart';
import '../../facturation/domain/creances.dart';
import '../../facturation/domain/entities/paiement_facture.dart';
import '../../hebergement/domain/entities/reservation.dart';
import '../../hebergement/domain/entities/service_reservation.dart';
import '../../hebergement/domain/entities/unite_hebergement.dart';
import '../../rh/domain/entities/employe.dart';
import '../../stocks/domain/entities/etat_stock.dart';
import 'entities/tableau_de_bord.dart' show PointMensuel;
import 'periode_locale.dart';

int _ordinal(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 86400000;

/* ====================================================================== */
/* Occupation                                                              */
/* ====================================================================== */

/// Une réservation occupe-t-elle physiquement une unité ?
///
/// `STATUTS_NON_OCCUPANTS = ['annulee', 'en_attente']` du serveur : une
/// réservation encore à confirmer ne bloque pas une chambre dans le calcul du
/// taux. (Avant le 10/10/2026, `calculerOccupation` ne retranchait que les
/// annulées : une réservation en attente comptait comme une nuit vendue, et le
/// taux était supérieur à celui de la vue.)
bool occupePhysiquement(Reservation r) =>
    r.statut != StatutReservation.annulee &&
    r.statut != StatutReservation.enAttente;

/// Les unités qui entrent au dénominateur : une unité hors service n'est pas
/// louable, et la compter ferait chuter le taux sans qu'aucune vente n'ait été
/// manquée (`tauxOccupation()` du serveur).
int unitesLouables(List<UniteHebergement> unites) =>
    unites.where((u) => u.statut.estLouable).length;

/// Les nuits d'une réservation qui tombent DANS la fenêtre — bornes
/// semi-ouvertes. Une réservation à cheval sur deux fenêtres ne compte que ses
/// nuits intérieures, sans quoi le taux dépasserait 100 % en fin de mois.
int nuitsDansLaFenetre(Reservation r, FenetreTableauDeBord fenetre) {
  final arrivee = _ordinal(r.periode.arrivee);
  final depart = _ordinal(r.periode.depart);
  final debut = _ordinal(fenetre.debut);
  final fin = _ordinal(fenetre.finExclue);
  // `date_arrivee < fin ET date_depart > debut` — le filtre du serveur.
  if (arrivee >= fin || depart <= debut) return 0;
  final d = arrivee > debut ? arrivee : debut;
  final f = depart < fin ? depart : fin;
  // `DATEDIFF(LEAST(depart, fin), GREATEST(arrivee, debut))`, SANS plancher :
  // sur une fenêtre ordonnée le filtre ci-dessus le rend toujours positif ; sur
  // une période personnalisée INVERSÉE (que le serveur accepte, D297) le
  // serveur somme des nuits NÉGATIVES, et ce poste aussi.
  return f - d;
}

/// Les nuitées vendues sur la fenêtre.
///
/// Une unité par réservation, comme le serveur (`reservations.unite_id`). Une
/// fiche locale qui porterait PLUSIEURS lignes d'hébergement compte chaque
/// unité (même plancher que `KpisHistorique`) ; sans ligne locale — une fiche
/// reprise de l'ancienne version —, l'unité principale compte pour une.
int nuiteesVendues(List<Reservation> reservations, FenetreTableauDeBord f) {
  var total = 0;
  for (final r in reservations) {
    if (!occupePhysiquement(r)) continue;
    final nuits = nuitsDansLaFenetre(r, f);
    if (nuits == 0) continue;
    final unites = r.lignes
        .where(
          (l) => l.service == ServiceReservation.hebergement && l.estRenseignee,
        )
        .length;
    total += nuits * (unites == 0 ? 1 : unites);
  }
  return total;
}

/// Le taux d'occupation en CENTIÈMES de pour cent (`1000` = 10,00 %), ou
/// `null` quand il n'est pas calculable.
///
/// **ÉCART DÉLIBÉRÉ avec le serveur** : sans unité louable ou sans jour, le
/// serveur rend `'0.00'`. Ici `null`, qui s'affiche « — » : zéro dirait « un
/// hôtel vide » d'un parc qui n'a jamais été renseigné (PA-126, Article 7).
///
/// La troncature est celle de `bcdiv(bcmul(nuitées, 100, 4), capacité, 2)` :
/// on tronque à deux décimales, on n'arrondit jamais — un taux de 66,666 %
/// affiché 66,67 % se lirait comme plus que ce qui a été vendu.
int? tauxOccupationCentiemes({
  required List<UniteHebergement> unites,
  required List<Reservation> reservations,
  required FenetreTableauDeBord fenetre,
}) {
  final capacite = unitesLouables(unites) * fenetre.nombreJours;
  if (capacite == 0) return null;
  return (nuiteesVendues(reservations, fenetre) * 10000) ~/ capacite;
}

/// `'10.00'` — la forme du serveur (`bcmath`, deux décimales, point).
String centiemesEnChaine(int centiemes) {
  final negatif = centiemes < 0;
  final absolu = centiemes.abs();
  final entier = absolu ~/ 100;
  final reste = (absolu % 100).toString().padLeft(2, '0');
  return '${negatif ? '-' : ''}$entier.$reste';
}

/* ====================================================================== */
/* Réservations en attente                                                 */
/* ====================================================================== */

/// Réservations à confirmer CRÉÉES sur la fenêtre (`whereBetween` sur
/// `date_creation`, les deux bornes incluses — voir
/// [FenetreTableauDeBord.contientComme]).
int reservationsEnAttente(
  List<Reservation> reservations,
  FenetreTableauDeBord fenetre,
) => reservations
    .where(
      (r) =>
          r.statut == StatutReservation.enAttente &&
          fenetre.contientComme(r.creeeLe),
    )
    .length;

/* ====================================================================== */
/* Effectif                                                                */
/* ====================================================================== */

/// Employés `actif` — l'auteur du décompte est `effectif()` du serveur. Un
/// salarié en congé n'est pas « actif » ici : le serveur filtre
/// `statut = 'actif'`, pas `estEnPoste`.
int employesActifs(List<Employe> employes) =>
    employes.where((e) => e.statut == StatutEmploye.actif).length;

/// Le total de la note « Sur N au total » : tous les statuts sauf `parti`.
int effectifTotal(List<Employe> employes) =>
    employes.where((e) => e.statut != StatutEmploye.parti).length;

/* ====================================================================== */
/* Variation (EF-M11-03)                                                   */
/* ====================================================================== */

/// La variation en pourcent par rapport à la période précédente, ou `null`
/// quand elle n'a pas de sens.
///
/// Une base nulle ne donne ni « +100 % » ni « +∞ » : passer de 0 à 1
/// réservation est un démarrage, pas une progression de 100 %. Même troncature
/// que `bcdiv(bcmul(écart, 100, 4), précédent, 2)`. Les deux entrées sont des
/// chaînes à au plus deux décimales, comme celles du serveur.
String? variationEnPourcent(String courant, String precedent) {
  final c = _echelle4(courant);
  final p = _echelle4(precedent);
  // `bccomp($precedent, '0', 2) === 0` : comparaison à deux décimales.
  if (p ~/ 100 == 0) return null;
  final ecartPourCent = (c - p) * 100;
  return centiemesEnChaine(ecartPourCent ~/ (p ~/ 100));
}

/// « 10.00 » -> 100000 : l'entier à QUATRE décimales.
int _echelle4(String texte) {
  final negatif = texte.startsWith('-');
  final propre = negatif ? texte.substring(1) : texte;
  final parties = propre.split('.');
  final entier = int.parse(parties[0]);
  final decimales = parties.length > 1
      ? parties[1].padRight(4, '0').substring(0, 4)
      : '0000';
  final valeur = entier * 10000 + int.parse(decimales);
  return negatif ? -valeur : valeur;
}

/* ====================================================================== */
/* Stock                                                                   */
/* ====================================================================== */

/// La mention qui accompagne la valeur du stock quand des articles ont du stock
/// SANS aucune entrée valorisée : leur coût est inconnu, ils comptent pour zéro
/// franc dans la somme, et la somme est donc MINORÉE (D119). Vide si tous les
/// articles en stock ont un coût — un « 0 » sur registre vide reste vrai.
String mentionStockSansCout(KpisStock k) =>
    k.sansValorisation == 0 ? '' : '${k.sansValorisation} article(s) sans coût';

/* ====================================================================== */
/* Argent encaissé (lot 5, 12/10/2026)                                     */
/* ====================================================================== */

/// Chiffre d'affaires ENCAISSÉ de la fenêtre, en centimes —
/// `TableauDeBordService::chiffreAffairesEncaisse` :
///
/// ```php
/// DB::table('paiements')->whereBetween('date_paiement', [$debut, $fin])->sum('montant');
/// ```
///
/// ⚠ **Le serveur ne filtre PAS le statut.** Un encaissement ANNULÉ (PA-168) est
/// compté, alors que `Facture::SQL_PAIEMENTS_RECUS` et `encaisseDepuis` l'excluent
/// tous deux : le tableau de bord et l'écran Clients & Créances peuvent donc
/// afficher deux « encaissés » différents pour la même période. Défaut du
/// SERVEUR, répliqué à l'identique et signalé à l'Architecte (D233) — le corriger
/// ici seul ferait diverger les deux postes.
///
/// Ne lit que les encaissements de FACTURES : les ventes du comptoir ne sont pas
/// dans `paiements`, elles sont dans `ventes` — le serveur ne les compte pas dans
/// ce chiffre, ce poste non plus.
int chiffreAffairesEncaisseCentimes(
  List<PaiementFacture> paiements,
  FenetreTableauDeBord fenetre,
) => paiements
    .where((p) => fenetre.contientComme(p.datePaiement))
    .fold(0, (t, p) => t + p.montantCentimes);

/// Trésorerie de caisse de la fenêtre, en centimes —
/// `TableauDeBordService::tresorerieCaisse` : le FOND des sessions OUVERTES (quelle
/// que soit la période) plus les encaissements de la fenêtre rattachés à ces
/// sessions OUVERTES.
///
/// ⚠ Trois incohérences du serveur, répliquées (D233) :
///  - les ventes du comptoir n'y entrent pas — le tiroir contient pourtant leurs
///    espèces (le théorique de la clôture, lui, les compte, et ignore les
///    encaissements de facture : deux définitions du tiroir) ;
///  - les encaissements ANNULÉS y entrent (aucun filtre de statut) ;
///  - la fenêtre ne borne que les encaissements : le fond est toujours entier, si
///    bien que la « précédente » valeur ne diffère de la courante que par les
///    paiements.
int tresorerieCaisseCentimes({
  required List<SessionCaisse> sessions,
  required List<PaiementFacture> paiements,
  required FenetreTableauDeBord fenetre,
}) {
  final ouvertes = {
    for (final s in sessions)
      if (s.estOuverte) s.id,
  };
  final fonds = sessions
      .where((s) => s.estOuverte)
      .fold(0, (t, s) => t + s.fondCentimes);
  final encaissements = paiements
      .where(
        (p) =>
            ouvertes.contains(p.sessionId) &&
            fenetre.contientComme(p.datePaiement),
      )
      .fold(0, (t, p) => t + p.montantCentimes);
  return fonds + encaissements;
}

/// Factures dont le règlement reste incomplet, émises dans la fenêtre —
/// `TableauDeBordService::facturesImpayees` :
/// `appliquerPredicatImpayee(...)->whereBetween('date_emission', [$debut, $fin])`.
///
/// `date_emission` est une DATE : comparée aux bornes, elle vaut minuit de son
/// jour. Le prédicat « impayée » est LE MÊME que celui du solde des clients
/// (`CreanceFacture.estImpayee`) — PA-121, une formule.
int facturesImpayeesDansLaFenetre(
  List<CreanceFacture> creances,
  FenetreTableauDeBord fenetre,
) => creances.where((c) {
  if (!c.estImpayee) return false;
  final e = c.piece.dateEmission;
  return fenetre.contientComme(DateTime(e.year, e.month, e.day));
}).length;

/// Une ligne d'écriture VALIDÉE de classe 6 (charge), pour « Dépenses
/// cumulées » : sa date `AAAA-MM-JJ`, son débit et son crédit en centimes.
final class ChargeDatee {
  const ChargeDatee({
    required this.date,
    required this.debitCentimes,
    required this.creditCentimes,
  });

  final String date;
  final int debitCentimes;
  final int creditCentimes;
}

/// « Dépenses cumulées » de la fenêtre, en centimes —
/// `TableauDeBordService::depensesCumulees` : la somme DÉBIT − CRÉDIT des
/// écritures validées de classe 6 dont la date tombe dans la fenêtre (un
/// crédit de compte de charge est un avoir fournisseur, il vient en
/// diminution). Les brouillons ne comptent pas (RG-12) : la liste reçue ne
/// porte que des lignes validées.
int depensesCumuleesCentimes(
  List<ChargeDatee> charges,
  FenetreTableauDeBord fenetre,
) {
  var total = 0;
  for (final c in charges) {
    final jour = DateTime.tryParse(c.date);
    if (jour == null) continue;
    // `whereBetween` du serveur : les DEUX bornes incluses, la fin comprise —
    // une écriture du 1er du mois suivant tombe donc aussi dans le mois qui
    // précède (particularité du serveur, répliquée comme pour les encaissements).
    if (!fenetre.contientComme(DateTime(jour.year, jour.month, jour.day))) {
      continue;
    }
    total += c.debitCentimes - c.creditCentimes;
  }
  return total;
}

/// `TableauDeBordService::serieMensuelle` : pour chacun des [mois] derniers
/// mois (du plus ANCIEN au plus récent), le chiffre d'affaires encaissé et les
/// dépenses — calculés par les MÊMES fonctions que la bande d'indicateurs, pour
/// que la courbe et la bande ne puissent pas se contredire. Ancré au premier du
/// mois : retrancher des mois à un 31 déborderait (relevé du 31/08/2026).
List<PointMensuel> serieMensuelleLocale({
  required List<PaiementFacture> encaissements,
  required List<ChargeDatee> charges,
  required int mois,
  required DateTime reference,
}) {
  final nombre = mois < 1 ? 1 : (mois > 12 ? 12 : mois);
  final premier = DateTime(reference.year, reference.month, 1);
  final points = <PointMensuel>[];
  for (var i = nombre - 1; i >= 0; i--) {
    final debut = DateTime(premier.year, premier.month - i, 1);
    final fin = DateTime(debut.year, debut.month + 1, 1);
    final fenetre = FenetreTableauDeBord.entre(debut, fin);
    points.add(
      PointMensuel(
        mois:
            '${debut.year.toString().padLeft(4, '0')}-'
            '${debut.month.toString().padLeft(2, '0')}',
        chiffreAffaires: centiemesEnChaine(
          chiffreAffairesEncaisseCentimes(encaissements, fenetre),
        ),
        depenses: centiemesEnChaine(depensesCumuleesCentimes(charges, fenetre)),
      ),
    );
  }
  return points;
}
