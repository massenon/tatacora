import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/rh/data/employe_dao.dart';
import 'package:tatacora_flutter/features/rh/data/paie_dao.dart';
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
    final bulletin = (await PaieDao(b.db).parId('bul-1'))!;
    expect(bulletin.netAPayer, 77120);
    expect(await b.total(), 0, reason: 'ce qui descend ne remonte pas');
  });
}
