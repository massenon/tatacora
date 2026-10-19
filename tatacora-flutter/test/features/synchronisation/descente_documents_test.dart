import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/caisse/domain/especes_de_la_session.dart';
import 'package:tatacora_flutter/features/depenses/data/depense_dao.dart';
import 'package:tatacora_flutter/features/depenses/domain/entities/depense.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart';

import 'support/faux_transport.dart';

/// Lot F4 (décision du PO du 17/10/2026, « NE PLUS LIMITER ») : la journée
/// d'un poste A descend sur ce poste — caisse, vente, dépense, commande,
/// réception, règlement, mouvements de stock, tourisme — SANS aucune pièce
/// locale (Q1), avec son poste d'origine, et rien ne remonte.
void main() {
  late BancSync b;

  setUp(() async {
    b = await BancSync.creer();
    await b.semerAuteur();
  });
  tearDown(() => b.fermer());

  Future<int> compte(String table, [String where = '1 = 1']) async =>
      (await b.db
                  .customSelect('SELECT COUNT(*) AS n FROM $table WHERE $where')
                  .getSingle())
              .data['n']
          as int;

  Future<Map<String, Object?>?> ligne(String table, String id) async =>
      (await b.db
              .customSelect(
                'SELECT * FROM $table WHERE id = ?',
                variables: [Variable.withString(id)],
              )
              .getSingleOrNull())
          ?.data;

  Map<String, Object?> doc(
    String table,
    String id,
    Map<String, Object?> donnees, {
    String? poste = 'POSTE-A',
  }) => {...element(table, id, donnees), 'poste_origine': poste};

  /// Le catalogue dont la journée a besoin, puis la journée du poste A.
  List<Map<String, Object?>> journee({
    String statutVente = 'validee',
    String modeVente = 'especes',
    String? dateCloture,
    String statutCommande = 'receptionnee',
  }) => [
    element('points_stockage', 'ps-bar', {'libelle': 'Bar', 'type': 'bar'}),
    element('articles', 'art-biere', {
      'libelle': 'Bière 65cl',
      'categorie': 'Boissons',
      'unite_mesure': 'bouteille',
      'point_stockage_id': 'ps-bar',
      'suivi': 'permanent',
      'seuil_alerte': '0.00',
    }),
    element('fournisseurs', 'f-1', {'raison_sociale': 'SOBEBRA'}),
    element('clients', 'cl-1', {
      'nom': 'Sabi',
      'telephone': '96000003',
      'type_client': 'groupe',
    }),
    doc('sessions_caisse', 'sess-1', {
      'point_vente': 'bar',
      'date_ouverture': '2026-10-15 07:00:00',
      'montant_fond': '10000.00',
      'date_cloture': dateCloture,
      'montant_theorique': dateCloture == null ? null : '13000.00',
      'montant_constate': dateCloture == null ? null : '13000.00',
    }),
    doc('ventes', 'v-1', {
      'numero': 'V-2026-00001',
      'session_id': 'sess-1',
      'point_vente': 'Bar',
      'client_id': null,
      'client_mention': 'Table 4',
      'table_id': 'table-inconnue',
      'montant_total': '3000.00',
      'mode_paiement': modeVente,
      'encaisse': true,
      'statut': statutVente,
      'motif_annulation': null,
      'annulee_at': null,
      // Lot P1-1 : la date MÉTIER (`created_at`) précède la réception au
      // serveur (`date_creation`) d'une vente faite hors ligne.
      'created_at': '2026-10-15 09:05:00',
      'date_creation': '2026-10-15 09:30:00',
      'lignes': [
        {
          'code': 'boisson-1',
          'nom': 'Béninoise 65cl',
          'categorie': 'locale',
          'module': 'M5',
          'prix_unitaire': '1000.00',
          'quantite': 3,
          'montant': '3000.00',
        },
      ],
    }),
    doc('depenses', 'dep-1', {
      'numero': 'DEP-1',
      'date_transaction': '2026-10-15',
      'tresorerie': 'caisse',
      'montant_total': '12500.00',
      'libelle': 'Marché du matin',
      'lignes': [
        {
          'libelle': 'Tomates',
          'compte_charge': '6011',
          'nature': 'Tomate',
          'famille': 'Marché',
          'montant': '12500.00',
        },
      ],
    }),
    doc('commandes_achat', 'cmd-1', {
      'fournisseur_id': 'f-1',
      'date_commande': '2026-10-15',
      'statut': statutCommande,
      'montant_total': '24000.00',
      'date_creation': '2026-10-15 08:10:00',
      'lignes': [
        {
          'article_id': 'art-biere',
          'quantite_commandee': '24.00',
          'prix_unitaire': '1000.00',
        },
      ],
    }),
    doc('bons_reception', 'bon-1', {
      'commande_id': 'cmd-1',
      'date_reception': '2026-10-15',
      'conformite': 'totale',
      'created_at': '2026-10-15 10:00:00',
      'lignes': [
        {'article_id': 'art-biere', 'point_id': 'ps-bar', 'quantite': '24.00'},
      ],
    }),
    doc('reglements_fournisseur', 'reg-1', {
      'commande_id': 'cmd-1',
      'montant': '10000.00',
      'tresorerie': 'caisse',
      'date_reglement': '2026-10-15',
      'statut': 'actif',
      'motif_annulation': null,
      'date_annulation': null,
    }, poste: null),
    // L'entrée de la réception (écrite par le serveur) et la sortie de la
    // vente (RG-05 au serveur) : le stock du poste se recalcule d'elles.
    doc('mouvements_stock', 'm-entree', {
      'article_id': 'art-biere',
      'point_id': 'ps-bar',
      'type_mouvement': 'entree',
      'quantite': '24.00',
      'motif': 'Réception commande cmd-1 — bon bon-1',
      'date_mouvement': '2026-10-15 10:00:00',
    }),
    doc('mouvements_stock', 'm-sortie', {
      'article_id': 'art-biere',
      'point_id': 'ps-bar',
      'type_mouvement': 'sortie',
      'quantite': '3.00',
      'motif': 'Vente V-2026-00001',
      'date_mouvement': '2026-10-15 09:30:00',
    }),
    doc('circuits', 'circ-1', {
      'nom': 'Chutes de Kota',
      'theme': 'nature',
      'zone': 'Atacora',
      'duree': '1 jour',
      'prix': '15000.00',
      'capacite_max': 8,
    }),
    doc('guides', 'g-1', {'nom': 'Moussa', 'zone_competence': 'Atacora'}),
    doc('reservations_tour', 'rt-1', {
      'circuit_id': 'circ-1',
      'client_id': 'cl-1',
      'guide_id': 'g-1',
      'date_circuit': '2026-10-20',
      'nb_participants': 4,
      'statut': 'reservee',
    }),
  ];

  Future<BilanDescente> descendre(List<Map<String, Object?>> elements) async {
    // Le faux serveur reprend après le curseur ; le vrai re-sert un document
    // modifié (piège rencontré au F3).
    await DescenteCatalogueDao(b.db).effacerCurseur();
    return b
        .descente(
          FauxTransport(
            (r) => r.methode == 'GET'
                ? FauxCatalogue(elements).repondre(r)
                : reponseLot(r),
          ),
        )
        .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
  }

  test('la journée du poste A est écrite ici, SANS aucune pièce, avec son '
      'origine ; rien ne part dans la file', () async {
    final bilan = await descendre(journee());
    expect(bilan.refuses, 0, reason: bilan.motifsRefus.join(' ; '));
    expect(bilan.enAttenteDeDependance, 0);

    expect(await compte('ecritures_local'), 0, reason: 'Q1 : aucune pièce');
    expect(await b.total(), 0, reason: 'ce qui descend ne remonte pas');

    for (final (table, id) in const [
      ('sessions_caisse_local', 'sess-1'),
      ('paniers_local', 'v-1'),
      ('depenses_local', 'dep-1'),
      ('commandes_achat_local', 'cmd-1'),
      ('bons_reception_local', 'bon-1'),
      ('reglements_fournisseur_local', 'reg-1'),
      ('mouvements_stock_local', 'm-entree'),
      ('circuits_local', 'circ-1'),
      ('guides_local', 'g-1'),
      ('reservations_tour_local', 'rt-1'),
    ]) {
      expect(await ligne(table, id), isNotNull, reason: '$table:$id');
    }
    final origine = await b.db
        .customSelect(
          'SELECT poste_origine FROM origines_documents_local '
          "WHERE table_serveur = 'ventes' AND entite_id = 'v-1'",
        )
        .getSingle();
    expect(origine.data['poste_origine'], 'POSTE-A');
    final reglement = await b.db
        .customSelect(
          'SELECT poste_origine FROM origines_documents_local '
          "WHERE entite_id = 'reg-1'",
        )
        .getSingle();
    expect(reglement.data['poste_origine'], isNull, reason: 'saisi au serveur');
  });

  test('la vente : un panier CLÔTURÉ de la session partagée — le théorique '
      'de la caisse la compte ; ses lignes et sa mention sont là', () async {
    await descendre(journee());
    final paniers = await PanierDao(b.db).paniers(statut: StatutPanier.cloture);
    final v = paniers.singleWhere((p) => p.id == 'v-1');
    expect(v.sessionEncaissementId, 'sess-1');
    expect(v.montantCloture, 3000);
    expect(v.clotureLe, DateTime(2026, 10, 15, 9, 5), reason: 'date métier');
    expect(v.clientNom, 'Table 4');
    expect(v.tableId, isNull, reason: 'table inconnue du plan de ce poste');
    expect(v.lignes.single.libelle, 'Béninoise 65cl');
    expect((v.lignes.single.prixUnitaire, v.lignes.single.quantite), (1000, 3));
    expect(especesEncaisseesCentimes(paniers, 'sess-1'), 300000);
  });

  test('le stock se recalcule des mouvements descendus ; le bon n’écrit '
      'AUCUNE entrée lui-même (pas de double comptage)', () async {
    await descendre(journee());
    expect(await compte('mouvements_stock_local'), 2);
    final etat = await StocksDao(b.db).etat();
    final biere = etat.lignes.singleWhere((l) => l.id == 'art-biere');
    expect(biere.stock, anyOf('21', '21.00', '21.0'), reason: '24 − 3');
    final l = await ligne('lignes_bon_reception_local', 'bon-1:0');
    expect(l!['quantite_centiemes'], 2400);
  });

  test('la dépense descendue a sa pièce AU SERVEUR : le rattrapage la '
      'REFUSE, rien n’est écrit', () async {
    await descendre(journee());
    final dao = DepenseDao(b.db);
    final d = (await dao.parId('dep-1'))!;
    expect(d.recueDuServeur, isTrue);
    expect(d.posteOrigine, 'POSTE-A');
    expect(d.pieceAuServeur, isTrue);
    expect(d.montantTotal, 12500);
    await expectLater(
      dao.comptabiliser('dep-1', auteurId: 'u-admin', centreId: 'c-1'),
      throwsA(
        isA<RefusDepense>().having(
          (r) => r.message,
          'message',
          const RefusDepense.recueDuServeur().message,
        ),
      ),
    );
    expect(await compte('ecritures_local'), 0);
    // La liste (le chemin de l'écran) porte le même drapeau que `parId`.
    expect((await dao.depenses()).single.pieceAuServeur, isTrue);
  });

  group('lot F5 : séjours et note de chambre des autres postes', () {
    List<Map<String, Object?>> hebergement({
      String? depart,
      bool horsService = false,
    }) => [
      ...journee().take(4),
      element('categories_hebergement', 'cat-1', {
        'libelle': 'Bungalow',
        'capacite_max': 2,
        'tarif_base': '25000.00',
      }),
      element('unites_hebergement', 'u-1', {
        'categorie_id': 'cat-1',
        'numero': 'B-01',
        'statut': horsService ? 'hors_service' : 'libre',
      }, actif: !horsService),
      doc('reservations', 'res-a', {
        'client_id': 'cl-1',
        'unite_id': 'u-1',
        'date_arrivee': '2026-10-17',
        'date_depart': '2026-10-19',
        'statut': 'confirmee',
        'acompte': '0.00',
        'tarif_nuit': '25000.00',
        'remise_type': 'aucune',
        'remise_valeur': '0.00',
      }),
      doc('sejours', 'sej-a', {
        'reservation_id': 'res-a',
        'date_checkin_reel': '2026-10-17 10:15:00',
        'date_checkout_reel': depart,
      }),
      doc('ventes', 'v-note', {
        'numero': 'V-2026-00009',
        'session_id': null,
        'point_vente': 'Restaurant',
        'client_id': 'cl-1',
        'reservation_id': 'res-a',
        'client_mention': null,
        'table_id': null,
        'montant_total': '2500.00',
        'mode_paiement': 'note_chambre',
        'encaisse': false,
        'statut': 'validee',
        'date_creation': '2026-10-17 20:00:00',
        'lignes': [
          {
            'code': 'plat-1',
            'nom': 'Riz sauce',
            'categorie': null,
            'module': 'M4',
            'prix_unitaire': '2500.00',
            'quantite': 1,
            'montant': '2500.00',
          },
        ],
      }),
    ];

    test('l’arrivée descend : séjour, réservation EN COURS, chambre OCCUPÉE ; '
        'la consommation est un panier de SÉJOUR de cette réservation, sans '
        'pièce', () async {
      final bilan = await descendre(hebergement());
      expect(bilan.refuses, 0, reason: bilan.motifsRefus.join(' ; '));

      final s = (await ligne('sejours_local', 'sej-a'))!;
      expect(s['reservation_id'], 'res-a');
      expect(s['date_checkout_reel'], isNull);
      expect(
        (await ligne('reservations_local', 'res-a'))!['statut'],
        'en_cours',
      );
      expect(
        (await ligne('unites_hebergement_local', 'u-1'))!['statut'],
        'occupee',
      );

      final p = (await ligne('paniers_local', 'v-note'))!;
      expect(
        (p['type_vente'], p['reservation_id'], p['mode_paiement']),
        ('sur_sejour', 'res-a', 'note_chambre'),
      );
      expect(p['session_encaissement_id'], isNull);
      expect(await compte('ecritures_local'), 0);
    });

    test('le départ descend : séjour clos, réservation TERMINÉE, chambre en '
        'NETTOYAGE ; une chambre hors service n’est jamais touchée', () async {
      await descendre(hebergement());
      await descendre(hebergement(depart: '2026-10-19 09:40:00'));
      expect(
        (await ligne('sejours_local', 'sej-a'))!['date_checkout_reel'],
        isNotNull,
      );
      expect(
        (await ligne('reservations_local', 'res-a'))!['statut'],
        'terminee',
      );
      expect(
        (await ligne('unites_hebergement_local', 'u-1'))!['statut'],
        'nettoyage',
      );

      // Mise hors service AU SERVEUR, puis un séjour qui redescend : la
      // chambre reste hors service.
      await b.db.customStatement('DELETE FROM sejours_local');
      await descendre(hebergement(horsService: true));
      expect(
        (await ligne('unites_hebergement_local', 'u-1'))!['statut'],
        'hors_service',
      );
    });

    test('une arrivée déjà pointée ICI n’est pas doublée : refusée ici, le '
        'serveur tranche', () async {
      final sans = hebergement().where((e) => e['table'] != 'sejours').toList();
      await descendre(sans);
      await b.db.customStatement(
        'INSERT INTO sejours_local (id, reservation_id, date_checkin_reel, '
        "occupants, date_creation, date_modification) VALUES ('sej-local', "
        "'res-a', 0, '[]', 0, 0)",
      );
      final bilan = await descendre(hebergement());
      expect(bilan.refuses, 1);
      expect(await compte('sejours_local'), 1);
    });

    test('une note de chambre sans réservation au serveur (vente d’avant le '
        'F5) est refusée avec son motif', () async {
      final bilan = await descendre(journee(modeVente: 'note_chambre'));
      expect(bilan.refuses, 1);
      expect(bilan.motifsRefus.single, contains('sans réservation'));
      expect(await ligne('paniers_local', 'v-1'), isNull);
    });
  });

  test(
    'une vente reçue AVANT sa session attend (jamais une clé violée)',
    () async {
      final sansSession = journee()
          .where((e) => e['table'] != 'sessions_caisse')
          .toList();
      final bilan = await descendre(sansSession);
      expect(bilan.enAttenteDeDependance, 1);
      expect(await ligne('paniers_local', 'v-1'), isNull);
    },
  );

  test(
    'états qui ne reculent jamais : la caisse close au serveur se ferme '
    'ici, jamais ne se rouvre ; la commande avance, jamais ne recule',
    () async {
      await descendre(journee(statutCommande: 'envoyee'));
      expect(
        (await ligne('sessions_caisse_local', 'sess-1'))!['date_cloture'],
        isNull,
      );

      await descendre(
        journee(dateCloture: '2026-10-15 22:00:00', statutCommande: 'cloturee'),
      );
      final s = (await ligne('sessions_caisse_local', 'sess-1'))!;
      expect(s['date_cloture'], isNotNull);
      expect(s['montant_constate_centimes'], 1300000);
      expect(
        (await ligne('commandes_achat_local', 'cmd-1'))!['statut'],
        'cloturee',
      );

      await descendre(journee(statutCommande: 'envoyee'));
      expect(
        (await ligne('sessions_caisse_local', 'sess-1'))!['date_cloture'],
        isNotNull,
        reason: 'jamais rouverte',
      );
      expect(
        (await ligne('commandes_achat_local', 'cmd-1'))!['statut'],
        'cloturee',
        reason: 'jamais en arrière',
      );
    },
  );

  test('la réservation de circuit occupe le guide ; annulée au serveur, '
      'annulée ici', () async {
    await descendre(journee());
    expect(
      (await ligne('reservations_tour_local', 'rt-1'))!['statut'],
      'reservee',
    );
    final annulee = journee().map((e) {
      if (e['id'] != 'rt-1') return e;
      return {
        ...e,
        'donnees': {
          ...(e['donnees']! as Map<String, Object?>),
          'statut': 'annulee',
        },
      };
    }).toList();
    await descendre(annulee);
    expect(
      (await ligne('reservations_tour_local', 'rt-1'))!['statut'],
      'annulee',
    );
  });

  test('les tables de documents suivent l’ordre du serveur et chacune a son '
      'libellé français', () {
    final noms = [for (final t in TableDescendue.values) t.nomServeur];
    expect(noms.indexOf('sessions_caisse'), lessThan(noms.indexOf('ventes')));
    expect(
      noms.indexOf('commandes_achat'),
      lessThan(noms.indexOf('bons_reception')),
    );
    expect(
      noms.indexOf('clients'),
      lessThan(noms.indexOf('reservations_tour')),
    );
    for (final t in TableDescendue.values) {
      expect(
        libelleTableServeur(t.nomServeur),
        isNot(t.nomServeur),
        reason: 'libellé manquant pour ${t.nomServeur}',
      );
    }
  });
}
