@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import 'support/scenario_file.dart';

/// L'ANCRAGE EXTÉRIEUR des documents de la file d'envoi (lot F1, piège 12) :
/// une journée complète du poste, écrite par ses VRAIS écrivains, est poussée
/// TELLE QUELLE au vrai moteur de synchronisation du serveur
/// (`tool/sync/valider_charge.php` → `SynchronisationService::traiterLot`,
/// règles de l'API, services de domaine, pièces produites par le serveur), sur
/// `tatacora_test`, puis annulée.
///
/// Un document hors contrat rend `rejete` avec la phrase du serveur : le test
/// rougit sur le motif. Mutation éprouvée (voir le rapport du lot) : retirer
/// la conversion `seuil_alerte` en décimal, la catégorie par défaut d'un
/// article, le rappel du fond à la clôture, ou envoyer les prix de vente en
/// centimes fait rejeter l'opération correspondante.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late List<Map<String, Object?>> operations;
  late List<Map<String, dynamic>> resultats;
  late Map<String, dynamic> etats;
  late List<Map<String, dynamic>> anomalies;
  late ScenarioFile s;

  setUpAll(() async {
    final db = AppDatabase.enMemoire();
    s = await jouerJourneeComplete(db);
    operations = await fileAuProtocole(db);
    await db.close();

    final sortie = await executerPhp(
      'valider_charge.php',
      dossier: 'sync',
      entree: {
        'aujourdhui': '2026-10-12',
        'poste_id': 'poste-essai-f1',
        'operations': operations,
      },
    );
    expect(
      sortie['enveloppe'],
      isEmpty,
      reason: 'l’enveloppe du lot est validée par SynchroniserRequest',
    );
    resultats = [
      for (final r in sortie['resultats'] as List) r as Map<String, dynamic>,
    ];
    etats = sortie['etats'] as Map<String, dynamic>;
    anomalies = [
      for (final a in sortie['anomalies'] as List) a as Map<String, dynamic>,
    ];
  });

  /// La ligne que le SERVEUR a écrite pour l'élément [id] de [table].
  Map<String, dynamic> serveur(String table, String id) {
    final ligne = etats['$table:$id'];
    expect(ligne, isNotNull, reason: 'le serveur n’a rien écrit pour $id');
    return ligne as Map<String, dynamic>;
  }

  Map<String, dynamic> resultatDe(String table, String type, String id) {
    final rang = operations.indexWhere(
      (o) => o['table'] == table && o['type'] == type && o['entite_id'] == id,
    );
    expect(rang, isNot(-1), reason: 'aucune opération $type $table $id');
    return resultats[rang];
  }

  test('la journée a produit une opération par geste, dans l’ordre des '
      'écritures, et AUCUNE écriture comptable', () {
    expect(operations.map((o) => '${o['type']} ${o['table']}').toList(), [
      'creation points_stockage',
      'creation points_stockage',
      'creation articles',
      'modification articles',
      'creation articles',
      'creation cartes_boisson',
      'modification cartes_boisson',
      'creation menus',
      'creation recettes',
      'creation plats',
      'modification plats',
      'creation categories_hebergement',
      'creation unites_hebergement',
      'modification unites_hebergement',
      'modification unites_hebergement',
      'modification unites_hebergement',
      'creation clients',
      'creation reservations',
      'creation reservations',
      'modification reservations',
      'modification reservations',
      'creation fournisseurs',
      'modification fournisseurs',
      'creation commandes_achat',
      'creation bons_reception',
      'creation reglements_fournisseur',
      'creation sessions_caisse',
      'creation tables_salle',
      'creation paniers',
      'creation ventes',
      'modification paniers',
      'modification sessions_caisse',
      'creation depenses',
      'creation circuits',
      'creation guides',
      'creation reservations_tour',
      'modification reservations_tour',
      'creation vehicules',
      'creation contrats_location',
      'creation employes',
      'creation plannings',
      'creation conges',
      'modification conges',
      'creation sejours',
      'creation ventes',
      'modification sejours',
      'creation factures',
      'creation sessions_caisse',
      'creation paiements',
      'creation mouvements_stock',
      'creation modeles_notification',
      'modification modeles_notification',
      'creation parametres_systeme',
      'creation roles',
      'modification roles',
      'creation immobilisations',
      'creation canaux_reservation',
      'modification canaux_reservation',
      'modification canaux_reservation',
      'creation ventes',
    ]);
    expect(resultats, hasLength(operations.length));
  });

  test('le serveur ACCEPTE chaque document : aucun rejet, aucun conflit', () {
    final refus = [
      for (var i = 0; i < resultats.length; i++)
        if (resultats[i]['statut'] != 'synchronise')
          '${operations[i]['type']} ${operations[i]['table']} : '
              '${jsonEncode(resultats[i])}',
    ];
    expect(refus, isEmpty);
  });

  test('articles : créés sous l’UUID du poste, puis modifiés (seuil en '
      'décimal, catégorie)', () {
    final creation = resultatDe('articles', 'creation', s.article);
    expect(creation['entite_id'], s.article);
    expect(creation.containsKey('fusionne_avec'), isFalse);
    final modification = resultatDe('articles', 'modification', s.article);
    expect(modification['statut'], 'synchronise');
    expect(modification['resolution'], isNot('version_serveur_conservee'));

    // Les VALEURS écrites : le seuil en décimal (1250 centièmes → 12.50), la
    // catégorie modifiée, la catégorie par défaut d'un article sans catégorie.
    final biere = serveur('articles', s.article);
    expect(
      (biere['libelle'], biere['categorie'], biere['seuil_alerte']),
      ('Bière F1 65cl', 'Boissons', '12.50'),
    );
    expect(biere['point_stockage_id'], s.point);
    final riz = serveur('articles', s.riz);
    expect(
      (riz['categorie'], riz['seuil_alerte'], riz['unite_mesure']),
      ('Non classé', '2.00', 'kg'),
    );
  });

  test(
    'POS hébergés (lot F5) : arrivée et départ à l’heure du poste, la '
    'note de chambre rattachée à SA réservation, non encaissée, sans caisse',
    () {
      final sejour = serveur('sejours', s.sejour);
      expect(sejour['reservation_id'], s.reservation);
      expect(
        '${sejour['date_checkin_reel']}',
        startsWith('2026-10-20 14:00:00'),
      );
      expect(
        '${sejour['date_checkout_reel']}',
        startsWith('2026-10-22 09:30:00'),
      );
      final vente = serveur('ventes', s.venteSejour);
      expect(
        (vente['mode_paiement'], vente['reservation_id'], vente['encaisse']),
        ('note_chambre', s.reservation, 0),
      );
      expect(vente['session_id'], isNull);
      expect(vente['montant_total'], '5400.00');
    },
  );

  test('M8 (audit) : le véhicule entre au parc (année manquante signalée), '
      'le contrat est numéroté LOC et chiffré par le serveur', () {
    final v = resultatDe('vehicules', 'creation', s.vehicule);
    expect(v['statut'], 'synchronise', reason: '$v');
    final c = resultatDe('contrats_location', 'creation', s.contrat);
    expect(c['statut'], 'synchronise', reason: '$c');
    expect(c['montant'], '90000.00');
    expect('${c['numero']}', startsWith('LOC'));
    expect(
      anomalies.any(
        (a) =>
            a['entite_id'] == s.vehicule && a['type'] == 'vehicule_sans_annee',
      ),
      isTrue,
    );
  });

  test('M13 (audit) : l’employé entre au dossier par EmployeService, le '
      'serveur rend SON matricule', () {
    final r = resultatDe('employes', 'creation', s.employe);
    expect(r['statut'], 'synchronise', reason: '$r');
    expect('${r['matricule']}', isNotEmpty);
    final ecrit = serveur('employes', s.employe);
    expect((ecrit['nom'], ecrit['salaire_base']), ('HOUNSOU', '150000.00'));
  });

  test('M13 (21/10/2026) : le créneau est écrit par PlanningService, la '
      'demande de congé est acceptée puis REFUSÉE et conservée', () {
    final p = resultatDe('plannings', 'creation', s.planning);
    expect(p['statut'], 'synchronise', reason: '$p');
    final ecrit = serveur('plannings', s.planning);
    expect('${ecrit['date']}'.substring(0, 10), '2026-10-23');
    expect('${ecrit['heure_debut']}', startsWith('08:00'));

    final c = resultatDe('conges', 'creation', s.conge);
    expect(c['statut'], 'synchronise', reason: '$c');
    final decision = resultatDe('conges', 'modification', s.conge);
    expect(decision['statut'], 'synchronise', reason: '$decision');
    final conge = serveur('conges', s.conge);
    expect(conge['statut_validation'], 'refuse');
    expect(conge['validateur_id'], isNotNull);
  });

  test('immobilisation (21/10/2026) : écrite par ImmobilisationService sous '
      'l’UUID du poste, le code du serveur revient, la valeur en centimes '
      'devient des francs décimaux', () {
    final r = resultatDe('immobilisations', 'creation', s.immobilisation);
    expect(r['statut'], 'synchronise', reason: '$r');
    expect(r['code'], 'IMMO-2026-00001');
    final ecrit = serveur('immobilisations', s.immobilisation);
    expect(
      (
        ecrit['libelle'],
        ecrit['valeur_origine'],
        ecrit['duree_annees'],
        ecrit['compte_immobilisation'],
      ),
      ('Toyota Land Cruiser Prado', '12000000.00', 5, '231'),
    );
    expect('${ecrit['date_mise_service']}', startsWith('2026-03-20'));
  });

  test('canaux de réservation (21/10/2026) : le canal naît sous l’UUID du '
      'poste par CanalReservationService, se renomme par son ancien nom, se '
      'désactive', () {
    for (final type in ['creation', 'modification']) {
      final r = resultatDe('canaux_reservation', type, s.canal);
      expect(r['statut'], 'synchronise', reason: '$r');
    }
    final ecrit = serveur('canaux_reservation', s.canal);
    expect((ecrit['nom'], '${ecrit['actif']}'), ('Agence Sahel', '0'));
    expect(ecrit['id'], s.canal);
  });

  test('remise du panier (21/10/2026) : le serveur dérive le MÊME net, '
      'encaisse 2 970 F et passe sa pièce dessus', () {
    final charge =
        operations.singleWhere(
              (o) => o['entite_id'] == s.venteRemise,
            )['payload']
            as Map;
    expect(
      (charge['remise_type'], charge['remise_valeur']),
      ('pourcentage', '10.00'),
    );
    // Le total annoncé est le NET (3 300 − 330) : le serveur le confronte.
    expect(charge['montant_cloture'], 2970);
    final r = resultatDe('ventes', 'creation', s.venteRemise);
    expect(r['statut'], 'synchronise', reason: '$r');
    expect(r['montant_total'], '2970.00');
    expect(serveur('ventes', s.venteRemise)['montant_total'], '2970.00');
  });

  test('règlement fournisseur (audit) : écrit par le service, à la date du '
      'poste, la commande en tient compte', () {
    final r = resultatDe('reglements_fournisseur', 'creation', s.reglement);
    expect(r['statut'], 'synchronise', reason: '$r');
    final ecrit = serveur('reglements_fournisseur', s.reglement);
    expect((ecrit['montant'], ecrit['tresorerie']), ('5000.00', 'caisse'));
    expect('${ecrit['date_reglement']}', startsWith('2026-10-12'));
  });

  test('tables (lot F6) : la table R2 fusionne avec celle du serveur, son '
      'addition l’occupe puis se ferme sur la vente', () {
    final table = resultatDe('tables_salle', 'creation', s.tableR2);
    expect(table['statut'], 'synchronise', reason: '$table');
    final ouverture = resultatDe('paniers', 'creation', s.vente);
    expect(ouverture['statut'], 'synchronise', reason: '$ouverture');
    final panier = serveur('paniers', s.vente);
    expect((panier['statut'], panier['vente_id']), ('cloture', s.vente));
  });

  test('réservation (lot F6) : déplacée par RG-01, puis annulée par '
      'AnnulationReservationService avec les montants du poste', () {
    final r = serveur('reservations', s.reservationAnnulee);
    expect(r['statut'], 'annulee');
    expect('${r['date_arrivee']}', startsWith('2026-10-27'));
    expect('${r['date_depart']}', startsWith('2026-10-29'));
    expect(r['taux_annulation'], '20.00');
    expect(r['montant_rembourse_annulation'], '4000.00');
    expect(r['ecriture_remboursement_id'], isNotNull);
  });

  test('facture et encaissement (lots F5c, F5d) : le serveur numérote, '
      'garde le prix vendu, et encaisse dans la caisse du poste', () {
    final facture = resultatDe('factures', 'creation', s.facture);
    expect(facture['statut'], 'synchronise', reason: '$facture');
    expect('${facture['numero']}', matches(RegExp(r'^F-2026-\d{5}$')));
    expect(facture['montant_ttc'], '55400.00');
    final ecrite = serveur('factures', s.facture);
    expect(ecrite['origine'], 'pos_sejour');
    expect(ecrite['client_id'], s.client);

    final paiement = resultatDe('paiements', 'creation', s.paiement);
    expect(paiement['statut'], 'synchronise', reason: '$paiement');
    final encaisse = serveur('paiements', s.paiement);
    expect(encaisse['session_id'], s.sessionDepart);
    expect(encaisse['montant'], '20000.00');
    expect('${encaisse['date_paiement']}', startsWith('2026-10-22 10:00:00'));
  });

  test('tourisme (lot F4) : circuit sans durée rangé vide, guide à 0 et '
      'signalé, réservation créée PUIS annulée par le service', () {
    final circuit = serveur('circuits', s.circuit);
    expect(
      (circuit['prix'], circuit['capacite_max'], circuit['duree']),
      ('15000.00', 8, ''),
    );
    expect(serveur('guides', s.guide)['tarif_jour'], '0.00');
    expect(
      anomalies.any(
        (a) => a['entite_id'] == s.guide && a['type'] == 'guide_sans_tarif',
      ),
      isTrue,
    );
    final resa = serveur('reservations_tour', s.reservationTour);
    expect(
      (resa['statut'], resa['nb_participants'], resa['guide_id']),
      ('annulee', 3, s.guide),
    );
    expect('${resa['date_circuit']}', startsWith('2026-10-20'));
  });

  test('catalogue : les valeurs écrites au serveur sont celles du poste, '
      'dans SES unités', () {
    expect(serveur('cartes_boisson', s.boisson)['prix_vente'], '1100.00');
    expect(serveur('cartes_boisson', s.boisson)['article_id'], s.article);
    final plat = serveur('plats', s.plat);
    expect(
      (plat['prix_vente'], plat['menu_id'], plat['recette_id']),
      ('2700.00', s.menu, s.recette),
    );
    expect(serveur('menus', s.menu)['type'], 'local');
    final unite = serveur('unites_hebergement', s.unite);
    // `nettoyage` : le départ du séjour (lot F5) l'a mise au ménage, comme
    // `SejourService::checkout` — le numéro reste celui du poste.
    expect((unite['numero'], unite['statut']), ('BNG-F1A', 'nettoyage'));
    final categorie = serveur('categories_hebergement', s.categorie);
    expect(
      (categorie['tarif_base'], categorie['capacite_max']),
      ('28000.00', 2),
    );
    expect(serveur('fournisseurs', s.fournisseur)['contact'], '97000002');
    expect(serveur('clients', s.client)['nom'], 'KORA F1');
    final reservation = serveur('reservations', s.reservation);
    expect(
      (
        reservation['acompte'],
        reservation['tarif_nuit'],
        reservation['mode_paiement'],
        reservation['client_id'],
      ),
      ('10000.00', '28000.00', 'especes', s.client),
    );
  });

  test('sessions_caisse : ouverte, puis CLÔTURÉE par le serveur, théorique '
      'recalculé par lui', () {
    expect(
      resultatDe('sessions_caisse', 'creation', s.session)['statut_caisse'],
      'ouverte',
    );
    final cloture = resultatDe('sessions_caisse', 'modification', s.session);
    expect(cloture['statut_caisse'], 'cloturee');
    expect(cloture['montant_constate'], '16000.00');
    // Le serveur recalcule le théorique (fond 10 000 + ses propres espèces
    // de la session : la vente de 6 000) — il ne recopie pas celui du poste.
    expect(cloture['montant_theorique'], '16000.00');
    final session = serveur('sessions_caisse', s.session);
    expect(
      (session['point_vente'], session['montant_fond']),
      ('bar', '10000.00'),
    );
    expect(session['date_ouverture'], '2026-10-12 10:00:00');
    expect(session['date_cloture'], '2026-10-12 19:00:00');
  });

  test('ventes : enregistrée au comptant, numérotée, au TOTAL du poste', () {
    final vente = resultatDe('ventes', 'creation', s.vente);
    expect(vente['numero'], startsWith('V-2026'));
    expect(vente['montant_total'], '6000.00');
    expect(vente['ecart_prix'], isNull, reason: 'prix du poste = catalogue');
  });

  test('depenses : enregistrée par le serveur, numérotée, au montant du '
      'poste, centre résolu', () {
    final depense = resultatDe('depenses', 'creation', s.depense);
    expect(depense['numero'], startsWith('DEP-2026'));
    expect(depense['montant_total'], '12500.00');
    final ecrite = serveur('depenses', s.depense);
    expect(
      (ecrite['date_transaction'], ecrite['tresorerie'], ecrite['libelle']),
      ('2026-10-12', 'caisse', 'Marché F1'),
    );
    // Le centre ne vit pas sur la dépense serveur (il est sur la pièce) : le
    // poste l'envoie relu de SA pièce, et un centre que le serveur ne
    // résoudrait pas ferait REJETER l'opération (`sync.depenses.centre_introuvable`).
    final charge =
        operations.singleWhere((o) => o['entite_id'] == s.depense)['payload']
            as Map;
    expect(charge['centre_libelle'], 'Restaurant');
    expect(charge['centre_id'], isNotNull);
  });

  test('achats : la commande puis son bon, conformité concordante', () {
    expect(
      resultatDe('commandes_achat', 'creation', s.commande)['montant_total'],
      '15612.00',
    );
    final bon = resultatDe('bons_reception', 'creation', s.bon);
    expect(bon['conformite'], 'totale');
    expect(bon.containsKey('conformite_poste'), isFalse);
  });

  test('CLÔTURE d’une caisse que le serveur ne connaît pas : enregistrée, '
      'jamais refusée, avec le RAPPEL de l’ouverture du poste', () async {
    final db = AppDatabase.enMemoire();
    final journee = await jouerJourneeComplete(db);
    final file = await fileAuProtocole(db);
    await db.close();
    // L'ouverture s'est perdue (refusée, ou jamais arrivée) : seule la
    // clôture part.
    final cloture = file.singleWhere(
      (o) => o['table'] == 'sessions_caisse' && o['type'] == 'modification',
    );
    final sortie = await executerPhp(
      'valider_charge.php',
      dossier: 'sync',
      entree: {
        'aujourdhui': '2026-10-12',
        'poste_id': 'poste-essai-f1',
        'operations': [cloture],
      },
    );
    final resultat = (sortie['resultats'] as List).single as Map;
    expect(resultat['statut'], 'cloture_sans_session_serveur');
    expect(resultat['statut_caisse'], 'cloturee_sur_le_poste');
    final anomalie = (sortie['anomalies'] as List).single as Map;
    expect(anomalie['entite_id'], journee.session);
    expect(anomalie['type'], 'cloture_session_inconnue');
    expect(anomalie['details'], {
      'point_vente': 'bar',
      'date_ouverture': '2026-10-12 10:00:00',
      'date_cloture': '2026-10-12 19:00:00',
      'montant_fond': '10000.00',
      'montant_theorique_poste': '16000.00',
      'montant_constate': '16000.00',
    });
  });

  test('Lot 10e : l’enregistrement des paramètres passe en lot par '
      'EnregistrerParametreService ; le rôle naît sous l’UUID du poste et '
      'sa matrice passe par definirNiveau', () {
    final enregistrement = operations.lastWhere(
      (o) => o['table'] == 'parametres_systeme',
    );
    final r = resultatDe(
      'parametres_systeme',
      'creation',
      enregistrement['entite_id']! as String,
    );
    expect(r['statut'], 'synchronise', reason: '$r');
    expect(r['cles_modifiees'], ['tolerance_reception_pct']);

    for (final type in ['creation', 'modification']) {
      final role = resultatDe('roles', type, s.role);
      expect(role['statut'], 'synchronise', reason: '$role');
    }
    expect(serveur('roles', s.role)['libelle'], 'Économe');
  });

  test('Lot 10f : la perte saisie au bar est écrite par MouvementStockService '
      'sous l’UUID du poste, à son heure', () {
    final r = resultatDe('mouvements_stock', 'creation', s.perte);
    expect(r['statut'], 'synchronise', reason: '$r');
    final ecrit = serveur('mouvements_stock', s.perte);
    expect(
      (ecrit['type_mouvement'], ecrit['quantite'], ecrit['motif']),
      ('perte', '1.00', 'Casse'),
    );
  });

  test('Lot 10f : le modèle de notification naît par '
      'ModeleNotificationService, puis se désactive', () {
    for (final type in ['creation', 'modification']) {
      final r = resultatDe('modeles_notification', type, s.modele);
      expect(r['statut'], 'synchronise', reason: '$r');
    }
    final ecrit = serveur('modeles_notification', s.modele);
    expect(
      (ecrit['evenement'], ecrit['canal'], '${ecrit['actif']}'),
      ('sejour_demain', 'whatsapp', '0'),
    );
  });
}
