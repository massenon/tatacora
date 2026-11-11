/// Les blocs LOCAUX de l'onglet « Pilotage consolidé » — fonctions pures.
///
/// Maître : `tableau-de-bord.js` (`rendreOccupation`, `rendreTopVentes`) et
/// `assets/js/indicateurs-engine.js` — les deux blocs « Occupation &
/// meilleures ventes » du panneau pilotage.
///
/// ## Deux sources sur le même onglet, et il faut savoir laquelle parle
///
/// Les KPI comptables et l'analytique (M10) n'ont PAS de source sur ce poste
/// (`pilotage_api.dart`) ; tout le reste — occupation, meilleures ventes,
/// stock, masse salariale, dépenses courantes, cartes M1/POS — lit la **base
/// locale**, qui le détient.
///
/// ## La PÉRIODE est calculée sur le poste, une seule fois
///
/// Les bornes viennent de [FenetreTableauDeBord] (`periode_locale.dart`),
/// confrontée à la vraie classe `Periode` du serveur. Les fonctions de ce
/// fichier reçoivent la fenêtre — jamais deux calculs de bornes qui
/// divergeraient d'un jour.
///
/// ## Aucun agrégat parallèle (PA-121)
///
/// Ce fichier ne recalcule ni un reste à payer ni un total de panier : la
/// carte M1 passe par [KpisHistorique.calculer] et la carte POS par
/// [KpisJournalVentes.calculer] — les mêmes calculs que leurs écrans. Seuls
/// l'occupation et les classements sont calculés ici, parce qu'ils n'existent
/// nulle part ailleurs dans ce client.
library;

import '../../hebergement/domain/entities/reservation.dart';
import '../../hebergement/domain/entities/service_reservation.dart';
import '../../hebergement/domain/entities/unite_hebergement.dart';
import '../../pos/domain/entities/reference_catalogue.dart';
import '../../stocks/domain/entities/etat_stock.dart';
import '../../ventes/domain/entities/vente.dart';
import 'exploitation_locale.dart' show articlesCritiques;
import 'indicateurs_locaux.dart';
import 'periode_locale.dart';

DateTime _jour(DateTime d) => DateTime(d.year, d.month, d.day);

/* ====================================================================== */
/* « À traiter » : articles critiques                                      */
/* ====================================================================== */

/// `Accueil::PLAFOND_CRITIQUES` — relu par PHP.
const int plafondArticlesCritiques = 50;

/// Le nombre de l'alerte de stock du panneau « À traiter » —
/// `Accueil::articlesCritiques()->count()`, confronté au serveur par exécution
/// (`tool/tableau_de_bord/exporter_indicateurs.php`).
///
/// La règle du serveur, telle quelle : TOUS les articles (journaliers compris)
/// dont le solde, tous points confondus, est inférieur ou égal au seuil
/// ([LigneStock.auSeuilOuDessous]), et la liste est PLAFONNÉE à 50 (`limit`) —
/// au-delà, le titre dit « 50 article(s) » sur un registre qui en compte plus.
/// Deux incohérences du SERVEUR, répliquées et notées (D298), jamais corrigées
/// ici seules : le compte diffère du « sous seuil » de l'écran Stocks (qui
/// écarte les journaliers, toujours critiques ici à seuil et solde nuls), et
/// le plafond de la LISTE devient un plafond du COMPTE.
///
/// [lignes] : l'état de stock NON filtré (tous points, tous articles).
///
/// Depuis le 12/10/2026 (lot 2 de l'accueil) le compte EST la longueur de la
/// liste [articlesCritiques] — celle du bandeau rouge et de la modale de la vue
/// d'exploitation : une seule lecture pour trois usages, comme la vue.
int nombreArticlesCritiques(Iterable<LigneStock> lignes) =>
    articlesCritiques(lignes).length;

/* ====================================================================== */
/* Occupation des chambres                                                 */
/* ====================================================================== */

/// L'occupation **sur la période**, plus l'instantané.
///
/// « Les deux chiffres cohabitent volontairement : le taux décrit la PÉRIODE,
/// l'instantané décrit MAINTENANT. Les confondre était le défaut d'origine. »
/// (`tableau-de-bord.js`, `rendreOccupation`.)
final class OccupationPilotage {
  const OccupationPilotage({
    required this.unites,
    required this.occupeesMaintenant,
    required this.nuitsOccupees,
    required this.nuitsOffertes,
    required this.tauxCentiemes,
  });

  /// Les unités LOUABLES : une unité hors service n'entre ni au dénominateur ni
  /// dans « occupées à l'instant / N ».
  final int unites;
  final int occupeesMaintenant;
  final int nuitsOccupees;
  final int nuitsOffertes;

  /// Le taux en centièmes de pour cent (`1000` = 10,00 %), tronqué comme
  /// `bcdiv`. `null` et non `0` : sans parc ni période, le taux n'est pas
  /// calculable, et afficher « 0 % » affirmerait une exploitation vide
  /// (Article 7).
  final int? tauxCentiemes;

  /// « 10.00 » — la forme de la vue (`$occupation . ' %'`), ou `null`.
  String? get taux =>
      tauxCentiemes == null ? null : centiemesEnChaine(tauxCentiemes!);
}

/// Calcule l'occupation — la définition hôtelière du maître, en nuitées.
///
/// ## Le taux est CELUI du serveur, pas une seconde formule
///
/// Avant le 10/10/2026 cette fonction recomptait de son côté : elle gardait les
/// unités hors service au dénominateur, comptait les réservations en attente
/// comme des nuits vendues et arrondissait à l'entier. Le taux de ce bloc
/// pouvait donc différer de celui de la bande d'indicateurs, sur le même
/// écran. Il passe désormais par [tauxOccupationCentiemes], confronté à
/// `TableauDeBordService::tauxOccupation` par exécution de PHP.
///
/// ÉCART DÉLIBÉRÉ — `assets/js/indicateurs-engine.js` l.135-136.
/// Le maître : `occupeesMaintenant` compte `unites.filter(u => u.statut ===
/// 'Occupée')` — la colonne `unites_hebergement.statut`.
/// Ici : les unités engagées par une réservation EN COURS à la date du jour,
/// même dérivation que l'historique (PA-111), jamais une seconde.
/// Raison : bug de maquette — cette colonne n'est écrite par PERSONNE (aucune
/// écriture hors seeder dans tout le dépôt, vérifié en PA-153), et le docblock
/// du modèle serveur dit lui-même que `statut` n'est pas la disponibilité
/// (RG-02 : la disponibilité est toujours calculée, jamais stockée). La lire
/// afficherait un zéro plausible en permanence — la famille PA-126.
OccupationPilotage calculerOccupation({
  required List<UniteHebergement> unites,
  required List<Reservation> reservations,
  required DateTime maintenant,
  FenetreTableauDeBord? fenetre,
}) {
  final jour = _jour(maintenant);
  final louables = unitesLouables(unites);

  // Les unités engagées maintenant — un ENSEMBLE, pas un compteur : deux
  // réservations sur la même unité (données incohérentes) ne comptent qu'une
  // chambre occupée.
  final occupees = <String>{};
  for (final r in reservations) {
    // Une réservation à confirmer ne bloque pas physiquement une chambre :
    // la règle du serveur (`STATUTS_NON_OCCUPANTS`), la même que le taux.
    if (!occupePhysiquement(r)) continue;
    final arrivee = _jour(r.periode.arrivee);
    final depart = _jour(r.periode.depart);
    // En cours = arrivée <= aujourd'hui < départ — l'ordre exact de
    // `LigneHistorique.deriver` : le jour du départ, la chambre est libérée.
    if (arrivee.isAfter(jour) || !depart.isAfter(jour)) continue;
    final engagees = [
      for (final l in r.lignes)
        if (l.service == ServiceReservation.hebergement && l.estRenseignee)
          l.itemId,
    ];
    // Une réservation descendue du serveur n'a pas de lignes locales
    // (PA-110 : la fiche est locale) — son unité principale fait foi.
    occupees.addAll(engagees.isEmpty ? [r.uniteId] : engagees);
  }

  if (fenetre == null) {
    return OccupationPilotage(
      unites: louables,
      occupeesMaintenant: occupees.length,
      nuitsOccupees: 0,
      nuitsOffertes: 0,
      tauxCentiemes: null,
    );
  }

  return OccupationPilotage(
    unites: louables,
    occupeesMaintenant: occupees.length,
    nuitsOccupees: nuiteesVendues(reservations, fenetre),
    nuitsOffertes: louables * fenetre.nombreJours,
    // Le taux peut dépasser 100 % si les données sont incohérentes — on ne
    // l'écrête PAS : un plafond masquerait une saisie fausse en la faisant
    // passer pour un établissement plein (`indicateurs-engine.js` l.171-173).
    tauxCentiemes: tauxOccupationCentiemes(
      unites: unites,
      reservations: reservations,
      fenetre: fenetre,
    ),
  );
}

/* ====================================================================== */
/* Meilleures ventes                                                       */
/* ====================================================================== */

/// Le critère de tri d'un classement — ANNONCÉ à l'écran : « un classement
/// par quantité et un classement par montant ne donnent pas le même ordre, et
/// le lecteur doit savoir lequel il regarde » (`tableau-de-bord.js`).
///
/// Le libellé est la PHRASE de la vue (`accueil_pwa.top_ventes.par_quantite` et
/// `par_montant`), en un seul littéral : « classé par quantité vendue » /
/// « classé par montant ».
enum TriClassement {
  quantite('classé par quantité vendue'),
  montant('classé par montant');

  const TriClassement(this.libelle);
  final String libelle;
}

final class LigneClassement {
  const LigneClassement({
    required this.nom,
    required this.quantite,
    required this.montant,
  });

  final String nom;
  final int quantite;
  final int montant;
}

final class ClassementPilotage {
  const ClassementPilotage({
    required this.libelle,
    required this.tri,
    required this.lignes,
    required this.vide,
  });

  final String libelle;
  final TriClassement tri;
  final List<LigneClassement> lignes;

  /// `vide` distingue « aucune vente » de « zéro franc » : le premier appelle
  /// d'élargir la période, le second est un fait d'exploitation.
  final bool vide;
}

/// Les quatre classements du maître (`indicateurs-engine.js`, `CLASSEMENTS`) :
/// restauration et bar **en quantités réellement vendues** — « un plat cher
/// vendu deux fois passait devant un plat courant vendu trente fois » —,
/// tourisme et location en montants.
///
/// ## Les faits viennent des DEUX registres locaux, comme au maître
///
/// La table de faits du maître (`CroiseEngine.faits()`) agrège ventes ET
/// réservations. Ici : les lignes des ventes **validées** du journal du poste
/// (les annulées gonfleraient un palmarès d'articles jamais servis), plus les
/// lignes Tourisme et Location des réservations non annulées — quatre services
/// sur cinq se vendent aussi sur une fiche (PA-110).
///
/// ## ⚠ Le journal des ventes est celui de CE poste
///
/// Les paniers ne sont pas synchronisés (`TABLES_SYNCHRONISABLES` ne connaît
/// que `reservations` et `clients`) : sur un site à plusieurs postes, ce
/// classement porterait sur les ventes de ce poste seulement. L'écran le dit
/// — même mention que le journal des ventes (« enregistré sur ce poste »).
///
/// Le regroupement se fait sur le **libellé figé** de la ligne — toujours
/// renseigné — jamais sur une clé facultative : « toutes les lignes sans code
/// se rangeaient sous la clé `undefined`, donc dans une seule entrée »
/// (`indicateurs-engine.js`, en-tête).
List<ClassementPilotage> classerMeilleuresVentes({
  required List<Vente> ventes,
  required List<Reservation> reservations,
  required DateTime debut,
  required DateTime finExclue,
  int limite = 5,
}) {
  final d = _jour(debut);
  final f = _jour(finExclue);
  bool dansPeriode(DateTime date) {
    final j = _jour(date);
    return !j.isBefore(d) && j.isBefore(f);
  }

  // (classement, module POS, service de réservation rattaché)
  const registres = [
    (
      'Restaurant — plats',
      TriClassement.quantite,
      ModuleVendable.m4Restaurant,
      null,
    ),
    ('Bar — boissons', TriClassement.quantite, ModuleVendable.m5Bar, null),
    (
      'Tourisme — circuits',
      TriClassement.montant,
      ModuleVendable.m9Tourisme,
      ServiceReservation.tourisme,
    ),
    (
      'Location — véhicules',
      TriClassement.montant,
      ModuleVendable.m8Vehicules,
      ServiceReservation.vehicule,
    ),
  ];

  return [
    for (final (libelle, tri, module, service) in registres)
      _classer(
        libelle: libelle,
        tri: tri,
        module: module,
        service: service,
        ventes: ventes,
        reservations: reservations,
        dansPeriode: dansPeriode,
        limite: limite,
      ),
  ];
}

ClassementPilotage _classer({
  required String libelle,
  required TriClassement tri,
  required ModuleVendable module,
  required ServiceReservation? service,
  required List<Vente> ventes,
  required List<Reservation> reservations,
  required bool Function(DateTime) dansPeriode,
  required int limite,
}) {
  final compte = <String, ({int quantite, int montant})>{};
  void ajouter(String nom, int quantite, int montant) {
    final actuel = compte[nom] ?? (quantite: 0, montant: 0);
    compte[nom] = (
      quantite: actuel.quantite + quantite,
      montant: actuel.montant + montant,
    );
  }

  for (final v in ventes) {
    if (!v.estValidee || !dansPeriode(v.date)) continue;
    for (final l in v.lignes) {
      if (l.module != module) continue;
      ajouter(l.libelle, l.quantite, l.montant);
    }
  }

  if (service != null) {
    for (final r in reservations) {
      if (r.statut == StatutReservation.annulee) continue;
      // La réservation est un fait daté à l'ARRIVÉE — c'est le jour où la
      // prestation entre en exploitation.
      if (!dansPeriode(r.periode.arrivee)) continue;
      for (final l in r.lignes) {
        if (l.service != service || !l.estRenseignee) continue;
        ajouter(l.libelle, l.quantite, l.sousTotal);
      }
    }
  }

  final lignes =
      [
        for (final e in compte.entries)
          LigneClassement(
            nom: e.key,
            quantite: e.value.quantite,
            montant: e.value.montant,
          ),
      ]..sort((a, b) {
        // À égalité sur le critère principal, on départage par l'autre plutôt que
        // de laisser l'ordre d'insertion décider — deux exécutions donneraient
        // sinon deux classements pour les mêmes données (le maître, au mot).
        int cle(LigneClassement l) =>
            tri == TriClassement.quantite ? l.quantite : l.montant;
        int autre(LigneClassement l) =>
            tri == TriClassement.quantite ? l.montant : l.quantite;
        final ecart = cle(b) - cle(a);
        if (ecart != 0) return ecart;
        final ecartAutre = autre(b) - autre(a);
        if (ecartAutre != 0) return ecartAutre;
        return a.nom.compareTo(b.nom);
      });

  return ClassementPilotage(
    libelle: libelle,
    tri: tri,
    lignes: lignes.take(limite).toList(growable: false),
    vide: lignes.isEmpty,
  );
}
