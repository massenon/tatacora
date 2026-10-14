import '../../achats/domain/decimal_texte.dart';
import '../../comptabilite/domain/montant_comptable.dart'
    show chaineDepuisCentimes;
import '../../crm/domain/entities/registre_clients.dart';
import '../../achats/domain/entities/commande_achat.dart';
import '../../hebergement/domain/entities/historique_reservations.dart';
import '../../hebergement/domain/entities/reservation.dart';
import '../../hebergement/domain/entities/unite_hebergement.dart';
import '../../rh/domain/entities/employe.dart';
import '../../rh/domain/services/livre_de_paie_service.dart';
import '../../stocks/domain/entities/etat_stock.dart';
import '../../tableau_de_bord/domain/entities/tableau_de_bord.dart';
import '../../tableau_de_bord/domain/indicateurs_locaux.dart'
    show mentionStockSansCout;
import '../../tourisme/domain/entities/reservation_tour.dart';
import '../../vehicules/domain/entities/contrat_location.dart';
import '../../vehicules/domain/entities/vehicule.dart';
import '../../depenses/domain/entities/depense.dart';
import '../../ventes/domain/entities/vente.dart';
import 'apercu_etat.dart';
import 'registre_etats.dart';

/// Les aperçus des états de M14 — `EtatInterface::calculer([])`, un par état.
///
/// @see EF-M14-02 Bibliothèque d'états standards par module
/// @see EF-M14-03 Génération à la demande
/// @see RG-19 Moteur d'états
///
/// ## Des fonctions PURES, montées à part de la base
///
/// Chaque fonction reçoit des entités DÉJÀ LUES par le dépôt de son module :
/// aucune ne lit Drift, aucune n'écrit. C'est ce qui permet d'éprouver une
/// colonne ou un total sur un cas construit à la main, y compris ceux qu'une
/// base peine à produire (une vente sans mode de règlement, un article en
/// stock sans coût). Les appels se font dans `EtatsApi.apercu`, qui est le
/// seul à connaître les dépôts.
///
/// ## Jamais une seconde formule
///
/// Le stock, le taux d'occupation, le reste à payer d'une réservation, le
/// montant d'une location, le total d'un panier, le livre de paie : chacun est
/// lu de l'entité ou du service de SON module, déjà confronté au serveur
/// (`stocks`, `tableau_de_bord`, `hebergement`, `rh`). Ce fichier ne fait que
/// les ranger dans les colonnes de l'état — des sommes et des comptages.
///
/// ## Le serveur sur chaque cellule, sauf quand il mentirait
///
/// Les colonnes, leur ordre et leurs libellés sont ceux du serveur
/// ([EtatLocal]). Une cellule suit son format : montant `12500.00`, date
/// `09/10/2026`, valeur brute d'un registre (`voiture`, `en_cours`) là où le
/// serveur écrit la valeur brute. Les écarts sont de trois sortes, TOUS dits
/// dans [ApercuEtat.mentions] : une colonne dont la source manque sur ce poste
/// rend « — » (jamais zéro) ; une somme partielle dit « hors N … » ; un
/// numéro qu'aucune séquence n'attribue ici n'est pas inventé.

/* ====================================================================== */
/* Outils                                                                  */
/* ====================================================================== */

/// Les sommes d'une colonne de montants `N.NN`, en centièmes — jamais un
/// `double`. Une chaîne illisible compte pour zéro ET se fait compter par le
/// retour [Somme.illisibles], pour que l'appelant puisse le dire.
final class Somme {
  Somme._(this.centiemes, this.illisibles);

  factory Somme.de(Iterable<String> montants) {
    var total = 0;
    var illisibles = 0;
    for (final m in montants) {
      final c = enCentiemes(m);
      if (c == null) {
        illisibles++;
      } else {
        total += c;
      }
    }
    return Somme._(total, illisibles);
  }

  final int centiemes;
  final int illisibles;

  String get ecrite => depuisCentiemes(centiemes);
}

/// Un montant, ramené à la forme du serveur (`12500` -> `12500.00`).
String _montantEcrit(String brut) {
  final c = enCentiemes(brut);
  return c == null ? brut : depuisCentiemes(c);
}

ApercuEtat _apercu(
  EtatLocal etat, {
  required String periode,
  required List<String> valeurs,
  required List<List<String>> lignes,
  List<String> mentions = const [],
  List<String>? libellesIndicateurs,
}) {
  final libelles = libellesIndicateurs ?? etat.indicateurs;
  assert(
    libelles.length == valeurs.length,
    '${etat.code} : ${valeurs.length} valeur(s) pour ${libelles.length} '
    'indicateur(s)',
  );
  for (final l in lignes) {
    assert(
      l.length == etat.entetes.length,
      '${etat.code} : ${l.length} cellules pour ${etat.entetes.length} '
      'colonnes — un décalage place chaque valeur sous le mauvais intitulé.',
    );
  }
  return ApercuEtat(
    code: etat.code,
    titre: etat.libelle,
    periode: periode,
    moduleSource: etat.module.code,
    indicateurs: [
      for (var i = 0; i < valeurs.length; i++)
        IndicateurApercu(libelles[i], valeurs[i]),
    ],
    entetes: etat.entetes,
    lignes: lignes,
    mentions: mentions,
  );
}

/// La phrase de période d'une photographie : « Arrêté au 09/10/2026 à 14:03 ».
String _arreteAu(EtatLocal etat, DateTime maintenant) =>
    etat.periode!.replaceFirst(':date', instantServeur(maintenant));

/* ====================================================================== */
/* M6 — Stocks                                                             */
/* ====================================================================== */

/// `EtatStocks` : tous les articles, par libellé, au coût moyen pondéré.
///
/// Un article en achat JOURNALIER n'a pas de quantité suivie : le serveur lui
/// lit un solde de `0.00` et le range « sous seuil » (D146). Ici il se lit
/// « non suivi » et « — », jamais « 0 ».
const String phraseVentesSansSortie =
    'Ce stock ne compte que les mouvements saisis sur ce poste : les ventes '
    'du bar et du restaurant n\'y écrivent aucune sortie, il peut donc '
    'dépasser le stock réel d\'autant.';

ApercuEtat apercuStocks(EtatStock etat, {required DateTime maintenant}) {
  const modele = EtatLocal.stocks;
  final lignes = <List<String>>[];

  for (final l in etat.lignes) {
    final journalier = l.estJournalier;
    // Comme `EtatStocks` : critique = quantité <= seuil (la rupture en fait
    // partie). Un article non suivi n'est ni critique ni normal.
    final critique = !journalier && (l.enRupture || l.sousSeuil);
    lignes.add([
      l.libelle,
      l.categorie ?? '',
      l.uniteMesure,
      journalier ? 'non suivi' : l.stock,
      journalier ? '' : l.seuilAlerte,
      journalier ? '' : (critique ? 'Sous seuil' : 'Normal'),
      (journalier || l.valeurInconnue)
          ? ''
          : montantServeur(int.parse(l.valeurStock)),
    ]);
  }

  final k = etat.kpis;
  final sansCout = mentionStockSansCout(k);
  final valeur = montantServeur(int.parse(k.valeurStock));

  return _apercu(
    modele,
    periode: _arreteAu(modele, maintenant),
    valeurs: [
      '${lignes.length}',
      '${k.sousSeuil}',
      // Une somme partielle DIT ce qu'elle ne comprend pas : du stock sans
      // aucune entrée valorisée a un coût inconnu, il pèse zéro dans la somme.
      sansCout.isEmpty ? valeur : '$valeur (hors $sansCout)',
    ],
    lignes: lignes,
    mentions: [
      if (k.journaliers > 0)
        '${k.journaliers} article(s) en achat journalier ne sont pas suivis '
            'en quantité : ils se lisent « non suivi » et « — », jamais « 0 ». '
            'Le compte « Sous seuil » diffère donc de celui du serveur, qui '
            // Références D146, D187 retirées du texte imprimé (directive du
            // PO, 14/10/2026).
            'range ces articles sous le seuil avec une quantité de 0.00.',
      phraseVentesSansSortie,
    ],
  );
}

/* ====================================================================== */
/* M11 — Tableau de bord                                                   */
/* ====================================================================== */

/// Les libellés de `lang/fr/tableaux_de_bord.php` (`kpi.*`), relus par un test.
/// Registre fermé : une clé inconnue est écrite telle quelle, jamais devinée.
const Map<String, String> libellesIndicateursTableau = {
  'chiffre_affaires_encaisse': "Chiffre d'affaires encaissé",
  'taux_occupation': "Taux d'occupation (nuitées)",
  'tresorerie_caisse': 'Trésorerie en caisse',
  'depenses_cumulees': 'Dépenses cumulées',
  'reservations_en_attente': 'Réservations en attente',
  'factures_impayees': 'Factures non soldées',
  'valeur_stock': 'Valeur du stock (CMP)',
  'employes_actifs': 'Employés actifs',
};

/// Les deux indicateurs qui sont des PHOTOGRAPHIES : le serveur écrit `0.00`
/// (stock) ou le total de l'effectif (employés) sous « Période précédente ».
/// Aucun n'est une valeur de la période précédente : ce poste écrit « — ».
const Set<String> _photographies = {'valeur_stock', 'employes_actifs'};

ApercuEtat apercuTableauDeBord(TableauDeBord tableau) {
  const modele = EtatLocal.tableauDeBord;
  final lignes = <List<String>>[];
  final mentions = <String>[];

  for (final i in tableau.indicateurs) {
    final libelle = libellesIndicateursTableau[i.cle] ?? i.cle;
    if (!i.estDisponible) {
      lignes.add([libelle, '', '', '']);
      mentions.add('$libelle : ${i.raisonAbsence}');
      continue;
    }
    final valeur = i.unite == UniteIndicateur.montant
        ? _montantEcrit(i.valeur)
        : i.valeur;
    final photo = _photographies.contains(i.cle);
    lignes.add([
      libelle,
      i.mention == null ? valeur : '$valeur (${i.mention})',
      photo
          ? ''
          : (i.unite == UniteIndicateur.montant
                ? _montantEcrit(i.precedent)
                : i.precedent),
      // `variation_pct === null` : le serveur écrit `non_comparable` ('—'), pas
      // « +100 % » sur une base nulle.
      i.variationPct == null ? tiretApercu : '${i.variationPct} %',
    ]);
  }

  if (tableau.indicateurs.any((i) => _photographies.contains(i.cle))) {
    mentions.add(
      'Valeur du stock et employés actifs sont des photographies à l\'instant : '
      'ils n\'ont pas de période précédente, la colonne se lit « — ».',
    );
  }

  String? lire(String cle, {String suffixe = ''}) {
    final i = tableau.parCle(cle);
    if (i == null || !i.estDisponible) return null;
    return '${i.unite == UniteIndicateur.montant ? _montantEcrit(i.valeur) : i.valeur}$suffixe';
  }

  final employes = tableau.parCle('employes_actifs');

  return _apercu(
    modele,
    periode: tableau.libellePeriode,
    valeurs: [
      lire('chiffre_affaires_encaisse') ?? '',
      lire('taux_occupation', suffixe: ' %') ?? '',
      lire('depenses_cumulees') ?? '',
      // `actifs / total` — le total est porté par `precedent`, le même
      // détournement que le serveur.
      employes == null || !employes.estDisponible
          ? ''
          : '${employes.valeur} / ${employes.precedent}',
    ],
    lignes: lignes,
    mentions: mentions,
  );
}

/* ====================================================================== */
/* M8 — Parc et locations                                                  */
/* ====================================================================== */

ApercuEtat apercuParcVehicules(
  List<Vehicule> parc, {
  required DateTime maintenant,
}) {
  const modele = EtatLocal.parcVehicules;
  // `orderBy('categorie')->orderBy('immatriculation')` : la valeur STOCKÉE.
  final ordonnes = [...parc]
    ..sort((a, b) {
      final c = (a.categorieBrute ?? '').toLowerCase().compareTo(
        (b.categorieBrute ?? '').toLowerCase(),
      );
      return c != 0
          ? c
          : a.immatriculation.toLowerCase().compareTo(
              b.immatriculation.toLowerCase(),
            );
    });

  final louables = ordonnes.where((v) => v.estLouable).toList();
  // Seuls les véhicules louables entrent dans le potentiel journalier : un
  // véhicule hors service gonflerait un chiffre d'affaires inatteignable.
  final potentiel = Somme.de(louables.map((v) => v.tarifJour));

  return _apercu(
    modele,
    periode: _arreteAu(modele, maintenant),
    valeurs: [
      '${ordonnes.length}',
      '${louables.length}',
      '${ordonnes.length - louables.length}',
      potentiel.ecrite,
    ],
    lignes: [
      for (final v in ordonnes)
        [
          v.immatriculation,
          v.categorieBrute ?? '',
          v.annee == null ? '' : '${v.annee}',
          v.capacite == null ? '' : '${v.capacite}',
          _montantEcrit(v.tarifJour),
          v.statutBrut ?? '',
          v.exigePermis ? 'Oui' : 'Non',
        ],
    ],
    mentions: [
      if (potentiel.illisibles > 0)
        '${potentiel.illisibles} tarif(s) journalier(s) illisible(s) : hors du '
            'cumul.',
    ],
  );
}

ApercuEtat apercuLocations(
  List<ContratLocation> contrats,
  List<Vehicule> parc,
) {
  const modele = EtatLocal.locationsVehicules;
  final categorieDe = {
    for (final v in parc) v.immatriculation: v.categorieBrute,
  };
  final montant = Somme.de(contrats.map((c) => c.montant));

  return _apercu(
    modele,
    periode: modele.periode!,
    valeurs: ['${contrats.length}', montant.ecrite],
    lignes: [
      for (final c in contrats)
        [
          c.clientNom ?? '',
          '${categorieDe[c.immatriculation] ?? tiretApercu} — ${c.immatriculation}',
          dateIsoServeur(c.debut),
          dateIsoServeur(c.fin),
          '${c.nombreJours}',
          _montantEcrit(c.montant),
        ],
    ],
    mentions: const [
      'Le montant d\'un contrat est recalculé au tarif courant du véhicule : '
          'aucune colonne ne le fige à la signature (constaté le 10/10/2026). '
          'Modifier la grille réécrit les contrats déjà signés.',
    ],
  );
}

/* ====================================================================== */
/* M1 — Réservations                                                       */
/* ====================================================================== */

ApercuEtat apercuReservations(
  List<Reservation> reservations,
  List<UniteHebergement> unites, {
  required DateTime maintenant,
}) {
  const modele = EtatLocal.reservations;
  final numeroDe = {for (final u in unites) u.id: u.numero};

  // `statut != annulee` : `calculer([])` n'inclut pas les annulées.
  final retenues =
      [
        for (final r in reservations)
          if (r.statut != StatutReservation.annulee)
            LigneHistorique.deriver(r, maintenant: maintenant),
      ]..sort((a, b) {
        final c = b.reservation.periode.arrivee.compareTo(
          a.reservation.periode.arrivee,
        );
        return c != 0 ? c : a.reservation.id.compareTo(b.reservation.id);
      });

  var montant = 0;
  var reste = 0;
  var sansTarif = 0;
  final lignes = <List<String>>[];

  for (final l in retenues) {
    final r = l.reservation;
    // Une réservation sans tarif (reprise d'avant le tarif figé) n'a pas de
    // montant : elle est exclue des sommes et rend « — », jamais zéro.
    final valorisee = r.recapitulatif.sousTotal > 0;
    if (valorisee) {
      montant += l.totalAPayer;
      reste += l.resteAPayer;
    } else {
      sansTarif++;
    }
    lignes.add([
      r.clientNom,
      numeroDe[r.uniteId] ?? '',
      dateServeur(r.periode.arrivee),
      dateServeur(r.periode.depart),
      '${l.nuits}',
      l.etat.libelle,
      valorisee ? montantServeur(l.totalAPayer) : tiretApercu,
      valorisee ? montantServeur(l.resteAPayer) : tiretApercu,
    ]);
  }

  return _apercu(
    modele,
    periode: modele.periode!,
    valeurs: [
      '${lignes.length}',
      montantServeur(montant),
      montantServeur(reste),
      if (sansTarif > 0) '$sansTarif',
    ],
    libellesIndicateurs: sansTarif > 0
        ? null
        : modele.indicateurs.sublist(0, 3),
    lignes: lignes,
    mentions: [
      'Le statut est déduit des dates (À venir, En cours, Terminée) : ce poste '
          'n\'enregistre ni confirmation ni arrivée. Les réservations '
          'annulées sont exclues, comme au serveur.',
      if (sansTarif > 0)
        '$sansTarif réservation(s) sans tarif figé : hors des montants, '
            '« — » en montant et en reste dû.',
    ],
  );
}

/* ====================================================================== */
/* M5 — Ventes                                                             */
/* ====================================================================== */

ApercuEtat apercuVentes(List<Vente> ventes, {int paniersOuverts = 0}) {
  const modele = EtatLocal.ventes;
  // `statut != annulee` : `calculer([])` n'inclut pas les annulées.
  final retenues = [
    for (final v in ventes)
      if (v.estValidee) v,
  ];

  var montant = 0;
  var encaissees = 0;
  var sansMode = 0;
  final lignes = <List<String>>[];

  for (final v in retenues) {
    montant += v.montant;
    final encaisse = v.encaisse;
    if (encaisse == true) encaissees++;
    if (encaisse == null) sansMode++;
    lignes.add([
      v.referenceLocale,
      dateHeureServeur(v.date),
      v.pointVente ?? '',
      v.clientNom ?? tiretApercu,
      v.mode?.code ?? '',
      // Trois réponses, pas deux : « on ne sait pas » n'est ni Oui ni Non.
      encaisse == null ? '' : (encaisse ? 'Oui' : 'Non'),
      montantServeur(v.montant),
    ]);
  }

  return _apercu(
    modele,
    periode: modele.periode!,
    valeurs: [
      '${lignes.length}',
      '$encaissees / ${lignes.length}',
      montantServeur(montant),
    ],
    lignes: lignes,
    mentions: [
      'N° : identifiant local abrégé de la vente — aucune séquence de numéros '
          'de vente n\'existe sur ce poste.',
      if (sansMode > 0)
        '$sansMode vente(s) sans mode de règlement : « Encaissée » se lit '
            '« — », elles ne sont pas comptées parmi les encaissées.',
      if (paniersOuverts > 0)
        '$paniersOuverts panier(s) encore ouvert(s) : ce ne sont pas des '
            'ventes, ils ne figurent pas ici.',
    ],
  );
}

/* ====================================================================== */
/* M10 — Dépenses                                                          */
/* ====================================================================== */

ApercuEtat apercuDepenses(List<Depense> depenses) {
  const modele = EtatLocal.depenses;
  var total = 0;
  for (final d in depenses) {
    total += d.montantTotal;
  }

  return _apercu(
    modele,
    periode: modele.periode!,
    valeurs: ['${depenses.length}', montantServeur(total)],
    lignes: [
      for (final d in depenses)
        [
          '',
          dateServeur(d.dateTransaction),
          d.libelle,
          d.tresorerie?.code ?? '',
          montantServeur(d.montantTotal),
          // Les deux mots du serveur (`etats_m14.depenses.ecriture_passee` /
          // `ecriture_absente`). LUS de la clé étrangère vers la pièce, jamais
          // d'un drapeau : une dépense d'avant la v16 n'en a pas et se lit
          // « Absente ». Jusqu'au 10/10/2026 la cellule était vide (« — »)
          // parce qu'aucune pièce n'existait : la source existe maintenant.
          d.estComptabilisee ? 'Passée' : 'Absente',
        ],
    ],
    mentions: [
      'N° : aucune séquence de numéros de dépense n\'existe sur ce poste.',
      if (depenses.any((d) => !d.estComptabilisee))
        'Écriture : « Absente » pour ${depenses.where((d) => !d.estComptabilisee).length} '
            'dépense(s) saisie(s) avant que ce poste passe une pièce '
            'comptable ; elles manquent au grand livre tant que leur pièce '
            'n\'est pas passée (constaté le 10/10/2026).'
      else
        'Écriture : « Passée » pour chaque dépense de cette liste, lue de la '
            'pièce comptable qu\'elle porte (constaté le 10/10/2026).',
    ],
  );
}

/* ====================================================================== */
/* M7 — Achats                                                             */
/* ====================================================================== */

ApercuEtat apercuAchats(List<CommandeAchat> commandes) {
  const modele = EtatLocal.achatsFournisseurs;
  final montant = Somme.de(commandes.map((c) => c.montantTotal));
  // « Reste dû » : `CommandeAchat::montantTotal() - montant_regle` du serveur,
  // où `montant_regle` est RECALCULÉ des règlements actifs. Sur le poste, le
  // règlement fournisseur est un vrai geste depuis le 12/10/2026 (D66) : « Réglé »
  // et le reste se LISENT de `reglements_fournisseur_local`, plus un « — » qui
  // disait « aucun règlement n'est enregistré ici » (motif périmé, retiré — D264).
  final reste = Somme.de(commandes.map((c) => c.resteDu));

  return _apercu(
    modele,
    periode: modele.periode!,
    valeurs: ['${commandes.length}', montant.ecrite, reste.ecrite],
    lignes: [
      for (final c in commandes)
        [
          c.fournisseurRaisonSociale,
          dateIsoServeur(c.dateCommande),
          c.statutCode,
          _montantEcrit(c.montantTotal),
          _montantEcrit(c.montantRegle),
          _montantEcrit(c.resteDu),
        ],
    ],
    // Le serveur ne porte AUCUNE mention sur cet état.
    mentions: const [],
  );
}

/* ====================================================================== */
/* M9 — Tourisme                                                           */
/* ====================================================================== */

ApercuEtat apercuTourisme(
  List<ReservationTour> reservations, {
  int illisibles = 0,
}) {
  const modele = EtatLocal.tourisme;
  // `STATUTS_INACTIFS = ['annulee']` : `calculer([])` n'inclut pas les annulées.
  final retenues = [
    for (final r in reservations)
      if (!r.estAnnulee) r,
  ]..sort((a, b) => b.dateCircuit.compareTo(a.dateCircuit));

  var participants = 0;
  var montant = 0;
  for (final r in retenues) {
    participants += r.nbParticipants;
    montant += r.montant;
  }

  return _apercu(
    modele,
    periode: modele.periode!,
    valeurs: ['${retenues.length}', '$participants', montantServeur(montant)],
    lignes: [
      for (final r in retenues)
        [
          r.circuitNom,
          r.clientNom,
          r.guideNom,
          dateServeur(r.dateCircuit),
          '${r.nbParticipants}',
          r.statut.cle,
          montantServeur(r.montant),
        ],
    ],
    mentions: [
      'Le montant est le prix actuel du circuit multiplié par les '
          'participants : aucune colonne ne le fige à la réservation '
          '(constaté le 10/10/2026).',
      if (illisibles > 0)
        '$illisibles réservation(s) de statut inconnu écartée(s) : hors des '
            'comptes et des montants.',
    ],
  );
}

/* ====================================================================== */
/* M13 — Paie et effectif                                                  */
/* ====================================================================== */

ApercuEtat apercuPaie(
  List<Employe> employes,
  TotauxLivre totaux, {
  required String periode,
}) {
  const modele = EtatLocal.paieEffectif;
  final ordonnes = [...employes]
    ..sort((a, b) => a.nom.toLowerCase().compareTo(b.nom.toLowerCase()));
  final actifs = ordonnes.where((e) => e.statut == StatutEmploye.actif).length;
  final sansBulletin = totaux.effectif == 0;

  return _apercu(
    modele,
    periode: modele.periode!.replaceFirst(':periode', periode),
    valeurs: [
      '${ordonnes.length}',
      '$actifs',
      // Une masse salariale « 0 » sans bulletin se lirait « personne n'est
      // payé » : c'est « aucun bulletin établi », et rien n'a été mesuré.
      sansBulletin ? '' : montantServeur(totaux.brut),
      sansBulletin ? '' : montantServeur(totaux.net),
      '${totaux.effectif}',
    ],
    lignes: [
      for (final e in ordonnes)
        [
          e.nomComplet(),
          e.matricule.isEmpty ? tiretApercu : e.matricule,
          e.poste,
          e.serviceLibelle ?? '',
          dateServeur(e.dateEmbauche),
          e.statut.code,
          montantServeur(e.salaireBase),
        ],
    ],
    mentions: [
      if (sansBulletin)
        'Aucun bulletin établi pour la période $periode : la masse salariale '
            'brute et le net à payer se lisent « — », pas « 0 ».',
    ],
  );
}

/* ====================================================================== */
/* M3 — Créances clients (lot 5, 12/10/2026)                               */
/* ====================================================================== */

/// `EtatCreancesClients::calculer([])` : les clients DÉBITEURS, du plus gros
/// solde au plus petit, et les trois totaux de `SoldeClientService::totaux()`.
///
/// Réutilise le registre de l'écran Clients & Créances — la MÊME composition, la
/// même formule (`creances.dart`) : un état ne recalcule jamais le solde, il
/// range les lignes que l'écran affiche. Une seconde requête finirait par
/// diverger de l'écran (PA-126).
///
/// ## Les trois totaux viennent des FACTURES, pas des lignes
///
/// `totaux()` du serveur somme toutes les factures impayées, y compris celles
/// d'un client absent du registre. L'appelant passe donc [totaux], calculé par
/// `totauxCreances` sur la même liste de créances que le registre.
///
/// ## Le libellé « Total dû (maximum) » est celui du serveur, et il est périmé
///
/// Le serveur nomme encore ce total « maximum » alors que `paiements` a un
/// écrivain depuis PA-165 : le total ne l'est plus. Le libellé est confronté au
/// serveur (`registre_contre_serveur_test`) et reste donc tel quel ; la
/// divergence est consignée à l'Architecte (D233), pas corrigée ici.
ApercuEtat apercuCreancesClients(
  List<LigneClient> registre, {
  required ({int totalDuCentimes, int nbPieces, int nbClients}) totaux,
  required DateTime maintenant,
}) {
  const modele = EtatLocal.creancesClients;
  final debiteurs = registre.where((l) => l.estDebiteur).toList();

  return _apercu(
    modele,
    periode: _arreteAu(modele, maintenant),
    valeurs: [
      '${totaux.nbClients}',
      '${totaux.nbPieces}',
      chaineDepuisCentimes(totaux.totalDuCentimes),
    ],
    lignes: [
      for (final l in debiteurs)
        [
          l.client.nomComplet,
          l.client.telephone,
          // La valeur BRUTE du registre (`particulier`), comme le serveur — pas
          // le libellé de l'écran (« Particulier »).
          l.client.type.code,
          '${l.nbPieces}',
          chaineDepuisCentimes(l.soldeCentimes),
        ],
    ],
  );
}
