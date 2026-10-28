import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/rh/data/employe_dao.dart';
import 'package:tatacora_flutter/features/rh/data/paie_dao.dart';
import 'package:tatacora_flutter/features/rh/domain/entities/employe.dart';
import 'package:tatacora_flutter/features/rh/domain/refus_rh.dart';
import 'package:tatacora_flutter/features/rh/domain/services/calcul_paie_service.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';

import 'support/faux_transport.dart';

/// Audit de couverture (18/10/2026) : le dossier RH et la paie montent et
/// descendent ; le matricule et le numéro du serveur font foi.
void main() {
  late BancSync b;
  late EmployeDao rh;
  late String hebergement;

  setUp(() async {
    b = await BancSync.creer();
    await b.semerAuteur();
    rh = EmployeDao(b.db);
    await rh.installerServices();
    hebergement = (await b.db.select(b.db.servicesRhLocal).get())
        .firstWhere((s) => s.libelle == 'Hébergement')
        .id;
  });
  tearDown(() => b.fermer());

  Future<List<String>> file() async => [
    for (final o in await b.dao.operations())
      '${o.type.code} ${o.table.nomServeur} ${o.payload}',
  ];

  Future<String> embaucher() async => (await rh.creer(
    nom: 'HOUNSOU',
    prenom: 'Marceline',
    poste: 'Réceptionniste',
    serviceId: hebergement,
    dateEmbauche: DateTime(2023, 2, 1),
    salaireBase: 150000,
  )).id;

  test('embauche, retouche, départ, bulletin : chaque geste part', () async {
    final id = await embaucher();
    final employe = (await rh.parId(id))!;
    await rh.archiver(id);
    await PaieDao(b.db).etablir(
      employe: employe,
      periode: '2026-10',
      retenues: const RetenuesSalariales(
        brut: 150000,
        cnssSalarie: 5400,
        revenuImposable: 144600,
        its: 9000,
        totalRetenues: 14400,
        netAPayer: 135600,
      ),
      chargesPatronalesConfirmees: 23000,
    );

    final ops = await file();
    expect(ops, hasLength(3));
    expect(ops[0], startsWith('creation employes '));
    expect(
      jsonDecode(ops[0].substring('creation employes '.length)),
      containsPair('service_libelle', 'Hébergement'),
    );
    expect(ops[1], 'modification employes {"statut":"parti"}');
    expect(
      ops[2],
      'creation bulletins_paie '
      '{"employe_id":"$id","periode":"2026-10","net_a_payer":135600}',
    );
  });

  test('le matricule du serveur remplace celui du poste (réponse de '
      'l’envoi)', () async {
    final id = await embaucher();
    final t = FauxTransport(
      (r) => reponseLot(
        r,
        particulier: (o) => o['entite_id'] == id
            ? {
                'uuid_operation': o['uuid_operation'],
                'statut': 'synchronise',
                'entite_id': id,
                'matricule': 'EMP-2026-00042',
              }
            : null,
      ),
    );
    await b.manager(t).synchroniserMaintenant();
    expect((await rh.parId(id))!.matricule, 'EMP-2026-00042');
  });

  test('le dossier du serveur descend : service reconnu par libellé, '
      'employé et bulletin inscrits', () async {
    await DescenteCatalogueDao(b.db).effacerCurseur();
    final bilan = await b
        .descente(
          FauxTransport(
            (r) => r.methode == 'GET'
                ? FauxCatalogue([
                    element('services', 'srv-heb', {'libelle': 'Hébergement'}),
                    element('employes', 'emp-1', {
                      'matricule': 'EMP-2026-00007',
                      'nom': 'KORA',
                      'prenom': 'Jean',
                      'email': 'jean.kora@exemple.bj',
                      'poste': 'Veilleur',
                      'service_id': 'srv-heb',
                      'date_embauche': '2024-01-15',
                      'numero_cnss': null,
                      'type_contrat': 'CDI',
                      'date_fin_contrat': null,
                      'salaire_base': '80000.00',
                      'statut': 'actif',
                    }),
                    element('bulletins_paie', 'bul-1', {
                      'numero': 'BUL-2026-10-0001',
                      'employe_id': 'emp-1',
                      'periode': '2026-10',
                      'salaire_base': '80000.00',
                      'total_primes': '0.00',
                      'total_retenues': '2880.00',
                      'cnss_salarie': '2880.00',
                      'its': '0.00',
                      'charges_patronales_confirmees': '12320.00',
                      'net_a_payer': '77120.00',
                      'statut': 'brouillon',
                      'motif_annulation': null,
                    }),
                  ]).repondre(r)
                : reponseLot(r),
          ),
        )
        .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
    expect(bilan.refuses, 0, reason: bilan.motifsRefus.join(' ; '));

    final e = (await rh.parId('emp-1'))!;
    expect((e.matricule, e.serviceId), ('EMP-2026-00007', hebergement));
    // L'e-mail facultatif (v45) descend avec le dossier ; absent, il reste vide.
    expect(e.email, 'jean.kora@exemple.bj');
    final bulletin = (await PaieDao(b.db).parId('bul-1'))!;
    expect(bulletin.netAPayer, 77120);
    expect(await b.total(), 0, reason: 'ce qui descend ne remonte pas');
  });

  group('E-mail facultatif (v45)', () {
    Map<String, Object?> charge(String operation) =>
        jsonDecode(operation.substring(operation.indexOf('{')))
            as Map<String, Object?>;

    Future<void> retoucher(String id, {String? email, String? poste}) =>
        rh.mettreAJour(
          id,
          nom: 'HOUNSOU',
          prenom: 'Marceline',
          poste: poste ?? 'Réceptionniste',
          serviceId: hebergement,
          dateEmbauche: DateTime(2023, 2, 1),
          salaireBase: 150000,
          email: email,
          statut: StatutEmploye.actif,
        );

    test(
      'il est normalisé à la saisie et part dans la création, puis dans '
      'chaque modification ; vider l’adresse l’EFFACE (null explicite)',
      () async {
        final employe = await rh.creer(
          nom: 'HOUNSOU',
          prenom: 'Marceline',
          poste: 'Réceptionniste',
          serviceId: hebergement,
          dateEmbauche: DateTime(2023, 2, 1),
          salaireBase: 150000,
          email: '  Marceline.HOUNSOU@Exemple.BJ ',
        );
        expect(employe.email, 'marceline.hounsou@exemple.bj');

        // Le dossier est connu du serveur (sa création attend dans la file) : la
        // retouche part en modification, dossier ENTIER.
        await retoucher(employe.id, email: 'MH@exemple.bj');
        await retoucher(employe.id, email: '   ');

        final ops = await file();
        expect(ops, hasLength(3));
        expect(ops[0], startsWith('creation employes '));
        expect(charge(ops[0])['email'], 'marceline.hounsou@exemple.bj');
        expect(ops[1], startsWith('modification employes '));
        expect(charge(ops[1])['email'], 'mh@exemple.bj');
        expect(charge(ops[2]), containsPair('email', null));
        expect((await rh.parId(employe.id))!.email, isNull);
      },
    );

    test('mal formé : refus avec la phrase du serveur, RIEN n’est écrit ni '
        'enfilé ; deux dossiers peuvent partager une adresse', () async {
      await expectLater(
        rh.creer(
          nom: 'X',
          prenom: 'Y',
          poste: 'Z',
          serviceId: hebergement,
          dateEmbauche: DateTime(2023, 2, 1),
          salaireBase: 1,
          email: 'pas-une-adresse',
        ),
        throwsA(
          isA<EmailInvalide>().having(
            (e) => e.message,
            'message',
            'Adresse email invalide.',
          ),
        ),
      );
      expect(await rh.employes(), isEmpty);
      expect(await file(), isEmpty);

      for (final nom in ['A', 'B']) {
        await rh.creer(
          nom: nom,
          prenom: 'Y',
          poste: 'Z',
          serviceId: hebergement,
          dateEmbauche: DateTime(2023, 2, 1),
          salaireBase: 1,
          email: 'commune@exemple.bj',
        );
      }
      expect(
        {for (final e in await rh.employes()) e.email},
        {'commune@exemple.bj'},
      );
    });

    test('l’archivage n’envoie toujours que le statut', () async {
      final id = await embaucher();
      await b
          .manager(FauxTransport((r) => reponseLot(r)))
          .synchroniserMaintenant();
      await rh.archiver(id);
      final ops = await file();
      expect(ops.last, 'modification employes {"statut":"parti"}');
    });
  });
}
