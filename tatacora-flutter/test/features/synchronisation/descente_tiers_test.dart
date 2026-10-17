import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/bilan_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart';

import 'support/faux_transport.dart';

/// Lot F3 (décision du Product Owner du 16/10/2026) : les CLIENTS et les
/// RÉSERVATIONS de tous les postes descendent. La question du PO : « le
/// poste B aura-t-il ce que le poste A a enregistré ? » — ici, le faux
/// serveur rend ce que le poste A a poussé, et le poste B doit le voir,
/// au point que la chambre ne se présente plus libre (RG-01).
void main() {
  late BancSync b;

  setUp(() async {
    b = await BancSync.creer();
    await b.semerAuteur();
  });
  tearDown(() => b.fermer());

  Future<Map<String, Object?>?> ligne(String table, String id) async =>
      (await b.db
              .customSelect(
                'SELECT * FROM $table WHERE id = ?',
                variables: [Variable.withString(id)],
              )
              .getSingleOrNull())
          ?.data;

  FauxTransport transportDe(FauxCatalogue cat) => FauxTransport(
    (r) => r.methode == 'GET' ? cat.repondre(r) : reponseLot(r),
  );

  /// Une descente de [elements]. Le faux serveur reprend APRÈS le curseur
  /// posé ; le vrai, lui, re-sert un élément MODIFIÉ (son `updated_at`
  /// avance). Le curseur est donc oublié avant chaque descente : sans quoi la
  /// seconde ne rendrait rien, et un cas « rien n'est réécrit » passerait à
  /// vide (vu en écrivant ce fichier).
  Future<BilanDescente> descendre(List<Map<String, Object?>> elements) async {
    await DescenteCatalogueDao(b.db).effacerCurseur();
    return b
        .descente(transportDe(FauxCatalogue(elements)))
        .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
  }

  const idReservation = '0a1b2c3d-0000-4000-8000-000000000001';

  /// Le parc, puis le client et la réservation qu'un poste A a poussés.
  List<Map<String, Object?>> parcEtSejour({
    String statut = 'confirmee',
    Map<String, Object?> sejour = const {},
  }) => [
    element('categories_hebergement', 'cat-1', {
      'libelle': 'Bungalow',
      'capacite_max': 2,
      'tarif_base': '25000.00',
    }),
    element('unites_hebergement', 'u-1', {
      'categorie_id': 'cat-1',
      'numero': 'B-01',
      'statut': 'libre',
    }),
    element('clients', 'cl-1', {
      'nom': 'Sabi',
      'prenom': 'Awa',
      'telephone': '96000003',
      'email': null,
      'type_client': 'groupe',
    }),
    element('reservations', idReservation, {
      'client_id': 'cl-1',
      'unite_id': 'u-1',
      'date_arrivee': '2026-11-02',
      'date_depart': '2026-11-04',
      'statut': statut,
      'acompte': '10000.00',
      'tarif_nuit': '24000.00',
      'remise_type': 'pourcentage',
      'remise_valeur': '10.00',
      'mode_paiement': 'mobile_money',
      'taux_annulation': null,
      'montant_total_annulation': null,
      'montant_commission_annulation': null,
      'montant_rembourse_annulation': null,
      'date_annulation': null,
      ...sejour,
    }),
  ];

  final novembre = PeriodeSejour(
    arrivee: DateTime.utc(2026, 11, 3),
    depart: DateTime.utc(2026, 11, 5),
  );

  group('ce que le poste A a enregistré, le poste B le voit', () {
    test('le client et la réservation sont écrits, et la chambre n’est plus '
        'libre pour RG-01 ; rien ne part dans la file', () async {
      final bilan = await descendre(parcEtSejour());
      expect((bilan.appliques, bilan.refuses), (4, 0));

      final client = (await ligne('clients_local', 'cl-1'))!;
      expect(client['nom'], 'Sabi');
      expect(client['type_client'], 'groupe');
      expect(client['statut_sync'], 'synchronise');

      final r = (await ligne('reservations_local', idReservation))!;
      expect(r['reference'], 'SRV-0A1B2C3D');
      expect(r['tarif_nuit'], 24000);
      expect(r['acompte'], 10000);
      expect(r['mode_paiement'], 'mobileMoney');
      expect((r['remise_type'], r['remise_valeur']), ('pourcentage', 10.0));
      expect(r['statut_sync'], 'synchronise');

      final sejour = (await ReservationDao(b.db).parId(idReservation))!;
      expect(sejour.periode.arrivee, DateTime.utc(2026, 11, 2));
      expect(sejour.periode.depart, DateTime.utc(2026, 11, 4));

      // La règle du poste B : la chambre est prise du 2 au 4.
      final pris = await ReservationDao(b.db).chevauchant(novembre);
      expect(pris.map((x) => x.id), [idReservation]);

      // Ce qui descend ne remonte pas, et ne passe AUCUNE pièce (le serveur
      // a passé celle de l'acompte, D246).
      expect(await b.total(), 0);
      final pieces = await b.db
          .customSelect('SELECT COUNT(*) AS n FROM ecritures_local')
          .getSingle();
      expect(pieces.data['n'], 0);
    });

    test('une réservation dont le client n’est pas encore reçu attend '
        '(jamais une clé étrangère violée)', () async {
      final bilan = await descendre([
        ...parcEtSejour().take(2),
        parcEtSejour().last,
      ]);
      expect(bilan.enAttenteDeDependance, 1);
      expect(await ligne('reservations_local', idReservation), isNull);
    });

    test(
      'tarif absent au serveur → 0, visiblement faux plutôt que '
      'recalculé ; fraction de franc et statut inconnu sont REFUSÉS',
      () async {
        final bilan = await descendre([
          ...parcEtSejour(sejour: {'tarif_nuit': null}),
          element('reservations', 'r-fraction', {
            ...parcEtSejour().last['donnees']! as Map<String, Object?>,
            'acompte': '10000.50',
          }),
          element('reservations', 'r-inconnu', {
            ...parcEtSejour().last['donnees']! as Map<String, Object?>,
            'statut': 'perdue',
          }),
        ]);
        expect(bilan.refuses, 2);
        expect(
          (await ligne('reservations_local', idReservation))!['tarif_nuit'],
          0,
        );
        expect(await ligne('reservations_local', 'r-fraction'), isNull);
        expect(await ligne('reservations_local', 'r-inconnu'), isNull);
      },
    );
  });

  group('une réservation déjà sur ce poste : le statut avance, jamais ne '
      'recule', () {
    Future<void> statutLocal(String statut) => b.db.customStatement(
      'UPDATE reservations_local SET statut = ? WHERE id = ?',
      [statut, idReservation],
    );

    Future<String> statut() async =>
        (await ligne('reservations_local', idReservation))!['statut']!
            as String;

    test('séjour ouvert ICI (en_cours) : un « confirmee » du serveur ne le '
        'ramène pas en arrière ; un « terminee » le fait avancer', () async {
      await descendre(parcEtSejour());
      await statutLocal('en_cours');

      await descendre(parcEtSejour(statut: 'confirmee'));
      expect(await statut(), 'en_cours');

      await descendre(parcEtSejour(statut: 'terminee'));
      expect(await statut(), 'terminee');
    });

    test('les dates d’une réservation existante ne sont pas réécrites (écart '
        'nommé)', () async {
      await descendre(parcEtSejour());
      await descendre(
        parcEtSejour(
          sejour: {'date_arrivee': '2026-12-01', 'date_depart': '2026-12-03'},
        ),
      );
      final r = (await ReservationDao(b.db).parId(idReservation))!;
      expect(r.periode.arrivee, DateTime.utc(2026, 11, 2));
    });

    test('annulée AU SERVEUR : annulée ici avec ses conditions, sans pièce, '
        'et la chambre est libérée', () async {
      await descendre(parcEtSejour());
      await descendre(
        parcEtSejour(
          statut: 'annulee',
          sejour: {
            'taux_annulation': '10.00',
            'montant_total_annulation': '43200.00',
            'montant_commission_annulation': '4320.00',
            'montant_rembourse_annulation': '0.00',
            'date_annulation': '2026-10-16 09:30:00',
          },
        ),
      );
      final r = (await ligne('reservations_local', idReservation))!;
      expect(r['statut'], 'annulee');
      expect(r['taux_annulation_centiemes'], 1000);
      expect(r['montant_total_annulation_centimes'], 4320000);
      expect(r['montant_commission_annulation_centimes'], 432000);
      expect(r['montant_rembourse_annulation_centimes'], 0);
      expect(r['ecriture_remboursement_id'], isNull);
      expect(await ReservationDao(b.db).chevauchant(novembre), isEmpty);
    });

    test(
      'annulée ICI : un statut actif du serveur ne la ressuscite pas',
      () async {
        await descendre(parcEtSejour());
        await statutLocal('annulee');
        await descendre(parcEtSejour(statut: 'en_cours'));
        expect(await statut(), 'annulee');
      },
    );
  });

  group('clients', () {
    test(
      'un client archivé au serveur reste proposé, et le bilan le compte',
      () async {
        final bilan = await descendre([
          element('clients', 'cl-2', {
            'nom': 'Ancien',
            'telephone': '97000002',
            'type_client': 'agence',
          }, actif: false),
        ]);
        expect((bilan.appliques, bilan.archivesNonPortees), (1, 1));
        expect(await ligne('clients_local', 'cl-2'), isNotNull);
      },
    );

    test('une fiche modifiée ici et pas encore partie est CONSERVÉE ; '
        'sinon la version du serveur la remplace', () async {
      final [id] = await b.enfilerClients(1);
      await b.db.customStatement(
        "INSERT INTO clients_local (id, nom, telephone, type_client) "
        "VALUES (?, 'Local', '97001000', 'particulier')",
        [id],
      );
      final serveur = element('clients', id, {
        'nom': 'Serveur',
        'telephone': '97001000',
        'type_client': 'particulier',
      });

      final bilan = await descendre([serveur]);
      expect(bilan.conservesLocalement, 1);
      expect((await ligne('clients_local', id))!['nom'], 'Local');

      await b.db.customStatement(
        "UPDATE operations_sync_local SET statut = 'synchronise'",
      );
      await descendre([serveur]);
      expect((await ligne('clients_local', id))!['nom'], 'Serveur');
    });

    test('type de client inconnu : refusé, compté', () async {
      final bilan = await descendre([
        element('clients', 'cl-3', {
          'nom': 'X',
          'telephone': '1',
          'type_client': 'vip',
        }),
      ]);
      expect(bilan.refuses, 1);
      expect(bilan.motifsRefus.single, contains('vip'));
    });
  });

  test('les deux tables descendent APRÈS le parc et AVANT les centres de '
      'coût, le client avant la réservation', () {
    final noms = [for (final t in TableDescendue.values) t.nomServeur];
    expect(noms.indexOf('clients'), lessThan(noms.indexOf('reservations')));
    expect(
      noms.indexOf('unites_hebergement'),
      lessThan(noms.indexOf('reservations')),
    );
  });
}
