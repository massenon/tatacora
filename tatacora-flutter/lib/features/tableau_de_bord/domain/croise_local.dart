/// Le TABLEAU CROISÉ DYNAMIQUE de la vue d'accueil — réplique, sur le poste,
/// de `Accueil::croiser` et `Accueil::faitsCroises` (`App\Pwa\Livewire`).
///
/// Fonctions PURES : la table de faits est construite à partir d'entités déjà
/// lues (paniers clôturés, dépenses, réservations), le croisement est un calcul
/// sur cette table. Confronté au VRAI serveur par
/// `tool/tableau_de_bord/rejouer_croise.php` (`croise_contre_serveur_test.dart`).
///
/// ## Ce que le serveur fait, et que le poste refait À L'IDENTIQUE
///
///  * **Une ligne élémentaire = un fait** : une vente de trois articles donne
///    trois faits (croiser par produit serait sinon impossible).
///  * **Les dépenses comptent en NÉGATIF** : le total est un solde.
///  * **Les factures sont ABSENTES** : une facture est le document d'une vente
///    ou d'une réservation déjà comptée.
///  * **Le montant d'une réservation est son ACOMPTE** (le serveur n'a aucun
///    montant de séjour sur `reservations`), et la note sous le tableau le dit.
///  * **Le tri est celui de `asort` de PHP 8** : chaînes comparées OCTET par
///    OCTET (« Achats » < « locale » < « — »), sauf deux chaînes numériques,
///    comparées comme des nombres ; les mois sur leur clé `AAAA-MM`.
///
/// ## Deux défauts du SERVEUR, répliqués et NON corrigés (à l'Architecte)
///
///  1. **Les dépenses et les réservations du LENDEMAIN de la période entrent
///     dans le croisement.** Leur filtre est `whereBetween(date, [debut,
///     fin->toDateString()])`, et `fin` est la borne EXCLUE (minuit du jour
///     suivant) : « Ce mois » d'octobre compte une dépense du 1er novembre, qui
///     ouvre une colonne « novembre 2026 ». Les ventes, elles, sont filtrées
///     sur l'instant (`created_at` entre les deux bornes, incluses).
///  2. **L'axe « Jour » se trie sur `d/m/Y`**, pas sur la date : « 01/11/2026 »
///     précède « 31/10/2026 ».
///
/// ## Ce que le poste fait AUTREMENT, et pourquoi
///
///  * Une vente est un panier CLÔTURÉ (le poste n'annule que des paniers
///    ouverts : un panier annulé n'a jamais été une vente).
///  * Une vente SANS mode de règlement (version antérieure du poste ; le
///    serveur n'a pas ce cas) n'est pas « encaissée » : on ne range pas au
///    hasard un argent dont on ignore la forme. Son mode s'écrit « — ».
///
/// @see EF-M11 Tableau de bord — tableau croisé dynamique
library;

import 'dart:convert';

/// Les axes croisables — `Accueil::AXES_CROISE`, DANS SON ORDRE (c'est
/// l'ordre des options des deux listes). Les libellés sont ceux de
/// `accueil_pwa.croise.axes`.
enum AxeCroise {
  source('Source'),
  module('Module'),
  activite('Activité'),
  libelle('Produit / libellé'),
  tiers('Point de vente / canal'),
  mode('Mode de paiement'),
  jour('Jour'),
  mois('Mois'),
  aucun('— aucun —');

  const AxeCroise(this.libelleOption);

  /// Le libellé de l'option (et de l'en-tête de la première colonne).
  final String libelleOption;
}

/// Les quatre mesures — `Accueil::MESURES_CROISE`, dans son ordre.
enum MesureCroise {
  montant('Montant (FCFA)', monnaie: true),
  encaisse('Encaissé (FCFA)', monnaie: true),
  quantite('Quantité', monnaie: false),
  nombre('Nombre de lignes', monnaie: false);

  const MesureCroise(this.libelleOption, {required this.monnaie});

  final String libelleOption;

  /// `true` : rendue en F CFA ; `false` : un compte.
  final bool monnaie;
}

/// Les trois registres de faits — `Accueil::SOURCES_CROISE`, dans son ordre.
enum SourceCroise {
  ventes('Ventes'),
  depenses('Dépenses'),
  reservations('Réservations');

  const SourceCroise(this.libelle);

  final String libelle;
}

/// Les mots de la vue (`accueil_pwa.croise.*`), relus par PHP dans le test.
abstract final class MotsCroise {
  static const String tiret = '—';
  static const String total = 'Total';
  static const String colonneAxe = 'Axe';
  static const String activiteHebergement = 'Hébergement';
  static const String lignes = 'Lignes';
  static const String colonnes = 'Colonnes';
  static const String mesure = 'Mesure';
  static const String sources = 'Sources';
  static const String intro =
      // Toute la phrase entre guillemets SIMPLES (apostrophes échappées) : le
      // comparateur de la vue ne recolle que des morceaux d'une même sorte de
      // guillemets — mélangés, il ne voyait pas la phrase (13/10/2026).
      'Croisez les ventes, les dépenses et les réservations sur la période '
      'choisie en haut de page. Les factures sont volontairement absentes : '
      'une facture est le document d\'une vente ou d\'une réservation déjà '
      'comptée, et l\'ajouter doublerait chaque montant. Une dépense compte en '
      'négatif : le total est un solde, pas une somme.';
  static const String aucuneSource =
      'Aucune source sélectionnée. Cochez au moins un registre.';
  static const String vide =
      'Aucun mouvement sur cette période. Élargissez la période en haut de '
      'page.';
  static String note(int nombre) =>
      '$nombre mouvement(s) agrégé(s) — les dépenses comptent en négatif : le '
      'total est un solde.';
  static const String noteReservations =
      'Le montant retenu pour une réservation est son acompte.';

  /// Le module de chaque registre, tel que le serveur l'écrit sur le fait
  /// (`Accueil::MODULE_COMPTABILITE`, `MODULE_HEBERGEMENT`).
  static const String moduleComptabilite = 'M10';
  static const String moduleHebergement = 'M1';
}

/// Les mois de `translatedFormat('F Y')` en locale `fr` : en minuscules.
const List<String> _moisFr = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

String _deux(int n) => n.toString().padLeft(2, '0');

/// Un fait, réduit à ses axes et à ses mesures (`Accueil::fait`). Montants
/// en FRANCS entiers (le poste n'a pas de sous-unité) ; une dépense est
/// négative.
final class FaitCroise {
  FaitCroise({
    required DateTime date,
    required SourceCroise source,
    required String module,
    required String activite,
    required String libelle,
    required String tiers,
    required String mode,
    required this.quantite,
    required this.montant,
    required this.encaisse,
  }) : _valeurs = {
         AxeCroise.source: source.libelle,
         AxeCroise.module: _ouTiret(module),
         AxeCroise.activite: _ouTiret(activite),
         AxeCroise.libelle: _ouTiret(libelle),
         AxeCroise.tiers: _ouTiret(tiers),
         AxeCroise.mode: _ouTiret(mode),
         AxeCroise.jour: '${_deux(date.day)}/${_deux(date.month)}/${date.year}',
         AxeCroise.mois: '${_moisFr[date.month - 1]} ${date.year}',
         AxeCroise.aucun: MotsCroise.total,
       },
       triMois = '${date.year}-${_deux(date.month)}';

  final Map<AxeCroise, String> _valeurs;

  /// La clé de tri CHRONOLOGIQUE du mois (`tri_mois`).
  final String triMois;
  final int quantite;
  final int montant;
  final int encaisse;

  static String _ouTiret(String v) => v.isEmpty ? MotsCroise.tiret : v;

  String valeur(AxeCroise axe) => _valeurs[axe]!;

  int mesure(MesureCroise m) => switch (m) {
    MesureCroise.montant => montant,
    MesureCroise.encaisse => encaisse,
    MesureCroise.quantite => quantite,
    MesureCroise.nombre => 1,
  };
}

/// Le croisement complet, tel que la vue le reçoit.
final class ResultatCroise {
  const ResultatCroise({
    required this.lignes,
    required this.colonnes,
    required this.grille,
    required this.totauxLignes,
    required this.totauxColonnes,
    required this.total,
    required this.nbFaits,
    required this.axeLigne,
    required this.mesure,
  });

  final List<String> lignes;
  final List<String> colonnes;
  final List<List<int>> grille;
  final List<int> totauxLignes;
  final List<int> totauxColonnes;
  final int total;
  final int nbFaits;
  final AxeCroise axeLigne;
  final MesureCroise mesure;

  /// AUCUN fait : la vue dit « Aucun mouvement… » plutôt qu'une grille de
  /// zéros (une grille vide et une grille de zéros ne disent pas la même
  /// chose).
  bool get vide => nbFaits == 0;
  bool get monnaie => mesure.monnaie;
}

/// `Accueil::croiser` — grille, totaux de lignes, de colonnes, général.
ResultatCroise croiser({
  required List<FaitCroise> faits,
  required AxeCroise axeLigne,
  required AxeCroise axeColonne,
  required MesureCroise mesure,
}) {
  final cellules = <String, int>{};
  // Nom -> clé de tri, dans l'ordre d'insertion (un tableau PHP).
  final lignes = <String, String>{};
  final colonnes = <String, String>{};

  for (final f in faits) {
    final cl = f.valeur(axeLigne);
    final cc = f.valeur(axeColonne);
    lignes[cl] = axeLigne == AxeCroise.mois ? f.triMois : cl;
    colonnes[cc] = axeColonne == AxeCroise.mois ? f.triMois : cc;
    final cle = '$cl\u0000$cc';
    cellules[cle] = (cellules[cle] ?? 0) + f.mesure(mesure);
  }

  final nomsLignes = _asort(lignes);
  final nomsColonnes = _asort(colonnes);

  final grille = <List<int>>[];
  final totauxLignes = <int>[];
  for (final l in nomsLignes) {
    final rangee = [for (final c in nomsColonnes) cellules['$l\u0000$c'] ?? 0];
    grille.add(rangee);
    totauxLignes.add(rangee.fold(0, (a, b) => a + b));
  }
  final totauxColonnes = [
    for (var i = 0; i < nomsColonnes.length; i++)
      grille.fold<int>(0, (a, r) => a + r[i]),
  ];

  return ResultatCroise(
    lignes: nomsLignes,
    colonnes: nomsColonnes,
    grille: grille,
    totauxLignes: totauxLignes,
    totauxColonnes: totauxColonnes,
    total: totauxLignes.fold(0, (a, b) => a + b),
    nbFaits: faits.length,
    axeLigne: axeLigne,
    mesure: mesure,
  );
}

/// `asort($tableau)` : les clés, triées par leur VALEUR selon la comparaison
/// de PHP 8, l'ordre d'insertion départageant les égalités (tri stable).
List<String> _asort(Map<String, String> tableau) {
  final entrees = tableau.entries.toList();
  final indexes = List<int>.generate(entrees.length, (i) => i);
  indexes.sort((a, b) {
    final c = comparerCommePhp(entrees[a].value, entrees[b].value);
    return c != 0 ? c : a.compareTo(b);
  });
  return [for (final i in indexes) entrees[i].key];
}

/// La comparaison `<=>` de PHP 8 entre deux CHAÎNES : numériquement si les
/// deux sont des chaînes numériques, octet par octet (UTF-8) sinon.
int comparerCommePhp(String a, String b) {
  final na = _nombrePhp(a);
  final nb = _nombrePhp(b);
  if (na != null && nb != null) return na.compareTo(nb);
  final oa = utf8.encode(a);
  final ob = utf8.encode(b);
  final n = oa.length < ob.length ? oa.length : ob.length;
  for (var i = 0; i < n; i++) {
    if (oa[i] != ob[i]) return oa[i] < ob[i] ? -1 : 1;
  }
  return oa.length.compareTo(ob.length);
}

/// Une « chaîne numérique » au sens de PHP 8 : blancs autour permis, signe,
/// chiffres avec point décimal, exposant. `null` sinon.
double? _nombrePhp(String s) {
  const blancs = ' \t\n\r\u000B\u000C';
  var debut = 0;
  var fin = s.length;
  while (debut < fin && blancs.contains(s[debut])) {
    debut++;
  }
  while (fin > debut && blancs.contains(s[fin - 1])) {
    fin--;
  }
  final t = s.substring(debut, fin);
  if (t.isEmpty) return null;
  var i = 0;
  if (t[i] == '+' || t[i] == '-') i++;
  var chiffres = 0;
  while (i < t.length && _chiffre(t[i])) {
    i++;
    chiffres++;
  }
  if (i < t.length && t[i] == '.') {
    i++;
    while (i < t.length && _chiffre(t[i])) {
      i++;
      chiffres++;
    }
  }
  if (chiffres == 0) return null;
  if (i < t.length && (t[i] == 'e' || t[i] == 'E')) {
    var j = i + 1;
    if (j < t.length && (t[j] == '+' || t[j] == '-')) j++;
    final debutExposant = j;
    while (j < t.length && _chiffre(t[j])) {
      j++;
    }
    if (j == debutExposant) return null;
    i = j;
  }
  if (i != t.length) return null;
  return double.tryParse(t.startsWith('+') ? t.substring(1) : t);
}

bool _chiffre(String c) => c.compareTo('0') >= 0 && c.compareTo('9') <= 0;

/* ======================================================================== */
/* La table de faits — `Accueil::faitsCroises`, source par source            */
/* ======================================================================== */

/// Une ligne de vente prête à devenir un fait (un panier CLÔTURÉ, une ligne).
final class LigneVenteCroisee {
  const LigneVenteCroisee({
    required this.clotureLe,
    required this.pointVente,
    required this.modeLibelle,
    required this.encaisse,
    required this.module,
    required this.categorie,
    required this.nom,
    required this.quantite,
    required this.montant,
  });

  final DateTime clotureLe;
  final String pointVente;

  /// Le libellé du mode (`VenteService::MODES_PAIEMENT`), vide si inconnu.
  final String modeLibelle;

  /// La vente est-elle un ENCAISSEMENT (pas une note de chambre, pas un mode
  /// inconnu) ?
  final bool encaisse;
  final String module;
  final String categorie;
  final String nom;
  final int quantite;
  final int montant;
}

/// Une ligne de dépense prête à devenir un fait.
final class LigneDepenseCroisee {
  const LigneDepenseCroisee({
    required this.dateTransaction,
    required this.tresorerie,
    required this.famille,
    required this.nature,
    required this.montant,
  });

  final DateTime dateTransaction;

  /// Le CODE de la trésorerie (`depenses.tresorerie`), tel que le serveur
  /// l'écrit sur le fait.
  final String tresorerie;
  final String famille;
  final String nature;
  final int montant;
}

/// Une réservation prête à devenir un fait.
final class ReservationCroisee {
  const ReservationCroisee({
    required this.dateArrivee,
    required this.annulee,
    required this.acompte,
    required this.nom,
    required this.prenom,
  });

  final DateTime dateArrivee;
  final bool annulee;
  final int acompte;
  final String nom;
  final String prenom;
}

/// Le jour (sans heure) d'un instant.
DateTime _jour(DateTime d) => DateTime(d.year, d.month, d.day);

/// La table de faits sur la fenêtre `[debut, finExclue)` du sélecteur, avec
/// les bornes DU SERVEUR (voir l'en-tête) :
///  * ventes : `debut <= clôture <= finExclue` (deux bornes incluses) ;
///  * dépenses et réservations : `jour(debut) <= date <= jour(finExclue)` —
///    le lendemain de la période est COMPTÉ, défaut du serveur répliqué.
List<FaitCroise> faitsCroises({
  required DateTime debut,
  required DateTime finExclue,
  required Set<SourceCroise> sources,
  List<LigneVenteCroisee> ventes = const [],
  List<LigneDepenseCroisee> depenses = const [],
  List<ReservationCroisee> reservations = const [],
}) {
  final faits = <FaitCroise>[];
  final premierJour = _jour(debut);
  final dernierJour = _jour(finExclue);
  bool dansLesJours(DateTime d) =>
      !_jour(d).isBefore(premierJour) && !_jour(d).isAfter(dernierJour);

  if (sources.contains(SourceCroise.ventes)) {
    for (final l in ventes) {
      if (l.clotureLe.isBefore(debut) || l.clotureLe.isAfter(finExclue)) {
        continue;
      }
      faits.add(
        FaitCroise(
          date: l.clotureLe,
          source: SourceCroise.ventes,
          module: l.module,
          activite: l.categorie,
          libelle: l.nom,
          tiers: l.pointVente,
          mode: l.modeLibelle,
          quantite: l.quantite,
          montant: l.montant,
          // Une note de chambre est une CRÉANCE, pas un encaissement.
          encaisse: l.encaisse ? l.montant : 0,
        ),
      );
    }
  }

  if (sources.contains(SourceCroise.depenses)) {
    for (final l in depenses) {
      if (!dansLesJours(l.dateTransaction)) continue;
      // Un DÉCAISSEMENT : il compte en négatif.
      final montant = -l.montant;
      faits.add(
        FaitCroise(
          date: l.dateTransaction,
          source: SourceCroise.depenses,
          module: MotsCroise.moduleComptabilite,
          activite: l.famille,
          libelle: l.nature,
          tiers: l.tresorerie,
          mode: MotsCroise.tiret,
          quantite: 1,
          montant: montant,
          encaisse: montant,
        ),
      );
    }
  }

  if (sources.contains(SourceCroise.reservations)) {
    for (final r in reservations) {
      if (r.annulee || !dansLesJours(r.dateArrivee)) continue;
      faits.add(
        FaitCroise(
          date: r.dateArrivee,
          source: SourceCroise.reservations,
          module: MotsCroise.moduleHebergement,
          activite: MotsCroise.activiteHebergement,
          // `trim(nom . ' ' . prenom)` — le NOM d'abord, comme le serveur.
          libelle: '${r.nom} ${r.prenom}'.trim(),
          // Le canal n'existe pas au schéma serveur : le tiret de la vue.
          tiers: MotsCroise.tiret,
          mode: MotsCroise.tiret,
          quantite: 1,
          montant: r.acompte,
          encaisse: r.acompte,
        ),
      );
    }
  }

  return faits;
}
