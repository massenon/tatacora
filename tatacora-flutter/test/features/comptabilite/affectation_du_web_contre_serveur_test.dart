@Timeout(Duration(minutes: 4))
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/comptabilite/data/affectation_resultat_locale.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/moteur_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/entities/comptabilite.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';

import '../synchronisation/support/faux_transport.dart';
import 'support/outils_comptabilite.dart';

/// UNE AFFECTATION PASSÉE AU WEB descend VRAIMENT sur un poste (09/11/2026, PO : « ÇA
/// DOIT APPARAÎTRE »), CONFRONTÉE au vrai serveur : `AffectationResultatService` et
/// `CatalogueDescendantService` sont EXÉCUTÉS (PHP,
/// `tool/comptabilite/rejouer_affectation.php`, base d'essai `TATACORA_BASE_ESSAI`),
/// le flux qu'ils rendent est servi tel quel à un poste Dart, par le vrai chemin
/// (`DescenteCatalogue` -> aligneur -> `AffectationsRecuesDao`), et la carte du poste
/// doit dire ce que dit la carte du serveur :
///
///  1. affectation passée au web : active, mêmes montants, même pièce, même auteur,
///     « Passer l'affectation » n'est plus offert ;
///  2. contre-passée au web : plus active, affectable de nouveau, le même résultat ;
///  3. refaite au web : la nouvelle est l'active, l'ancienne reste en historique.
typedef _Ev = Map<String, Object?>;

_Ev _piece(
  String journal,
  String date,
  String libelle,
  List<(String, String?, String?, String?)> lignes,
) => {
  't': 'piece',
  'journal': journal,
  'date': date,
  'libelle': libelle,
  'valide': true,
  'lignes': [
    for (final (compte, debit, credit, centre) in lignes)
      {'compte': compte, 'debit': ?debit, 'credit': ?credit, 'centre': ?centre},
  ],
};

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final scenario = <_Ev>[
    _piece('CAI', '2030-03-10', 'Ventes bar', [
      ('5711', '100000.00', null, 'Bar'),
      ('7011', null, '100000.00', 'Bar'),
    ]),
    _piece('CAI', '2030-03-11', 'Achats', [
      ('6011', '30000.00', null, 'Restaurant'),
      ('5711', null, '30000.00', 'Restaurant'),
    ]),
    {'t': 'geste', 'action': 'demarrer', 'annee': 2030},
    {'t': 'geste', 'action': 'cloturer', 'annee': 2030},
    // 0 : rien n'est affecté
    {'t': 'flux_affectations'},
    {'t': 'etat_affectation', 'annee': 2030},
    // 1 : affectation passée AU WEB
    {
      't': 'affecter',
      'annee': 2030,
      'date': '2031-04-30',
      'ventilation': {
        'reserve_legale': '7000.00',
        'autres_reserves': '3000.00',
        'dividendes': '10000.00',
        'report_a_nouveau': '50000.00',
      },
    },
    {'t': 'flux_affectations'},
    {'t': 'etat_affectation', 'annee': 2030},
    {'t': 'flux_affectations', 'role': 'administrateur'},
    // 2 : contre-passée au web
    {
      't': 'contrepasser_affectation',
      'annee': 2030,
      'motif': 'Ventilation rejetée en assemblée',
    },
    {'t': 'flux_affectations'},
    {'t': 'etat_affectation', 'annee': 2030},
    // 3 : refaite au web
    {
      't': 'affecter',
      'annee': 2030,
      'date': '2031-05-02',
      'ventilation': {'report_a_nouveau': '70000.00'},
    },
    {'t': 'flux_affectations'},
    {'t': 'etat_affectation', 'annee': 2030},
  ];

  late List<Map<String, dynamic>> r;

  setUpAll(() async {
    final sortie = await executerPhp(
      'rejouer_affectation.php',
      entree: {
        'aujourdhui': '2031-06-15',
        'exercices': [
          {'annee': 2030, 'statut': 'ouvert'},
          {'annee': 2031, 'statut': 'ouvert'},
        ],
        'cles_messages': const <String>[],
        'evenements': scenario,
      },
    );
    r = [
      for (final x in sortie['resultats'] as List) x as Map<String, dynamic>,
    ];
    for (var i = 0; i < r.length; i++) {
      expect(r[i]['ok'], isTrue, reason: 'événement $i : ${r[i]}');
    }
  });

  late BancSync b;
  late ComptabiliteDao dao;

  setUp(() async {
    b = await BancSync.creer();
    b.maintenant = DateTime(2031, 6, 15, 10);
    await b.semerAuteur();
    await semerAuteur(b.db);
    await baseInstalleeSur(b.db, DateTime(2031, 6, 15));
    dao = ComptabiliteDao(b.db);
    // Un poste qui n'a PAS fait cette clôture : le serveur lui a donné le statut et la date.
    await dao.alignerExerciceDescendu(
      annee: 2030,
      dateDebut: '2030-01-01',
      dateFin: '2030-12-31',
      statut: StatutExercice.cloture,
      dateCloture: DateTime(2031, 6, 15, 10),
    );
    await dao.alignerExerciceDescendu(
      annee: 2031,
      dateDebut: '2031-01-01',
      dateFin: '2031-12-31',
      statut: StatutExercice.ouvert,
    );
  });
  tearDown(() => b.fermer());

  AffectationResultatLocale carte() => AffectationResultatLocale(
    b.db,
    MoteurComptable(dao, maintenant: () => DateTime(2031, 6, 15, 10)),
    maintenant: () => DateTime(2031, 6, 15, 10),
  );

  List<Map<String, Object?>> flux(int i) => [
    for (final e in r[i]['elements'] as List)
      (e as Map).cast<String, Object?>(),
  ];

  Future<void> descendre(int i) async {
    await DescenteCatalogueDao(b.db).effacerCurseur();
    final bilan = await b
        .descente(
          FauxTransport(
            (req) => req.methode == 'GET'
                ? FauxCatalogue(flux(i)).repondre(req)
                : reponseLot(req),
          ),
        )
        .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
    expect(bilan.refuses, 0, reason: 'le poste accepte tout ce que PHP rend');
  }

  Future<String> id() async => (await dao.exerciceDeLAnnee(2030))!.id;

  test('rien d\'affecté au serveur : le flux est vide, la carte du poste '
      'n\'existe pas encore (clôture faite ailleurs)', () async {
    expect(flux(4), isEmpty);
    expect(r[5]['carte'], isTrue);
    expect(r[5]['affectable'], isTrue);
    await descendre(4);
    expect(await carte().etat(await id()), isNull);
  });

  test('passée AU WEB : le poste voit la même affectation que le serveur, et '
      'ne propose plus « Passer »', () async {
    expect(flux(7), hasLength(1), reason: 'le serveur descend l\'affectation');
    final donnees = (flux(7).single['donnees']! as Map).cast<String, Object?>();
    expect(donnees['annee'], 2030);
    expect((donnees['par']! as String), startsWith('comptable.'));
    expect(donnees, isNot(contains('exercice_id')));
    // L'administrateur, qui lit M10, reçoit la même ligne.
    expect(flux(9), hasLength(1));
    expect(r[8]['active_piece'], isNotNull);
    expect(r[8]['affectable'], isFalse);

    await descendre(7);
    final etat = (await carte().etat(await id()))!;
    final a = etat.active!;
    expect(a.parAilleurs, isTrue);
    expect(a.numeroPiece, r[8]['active_piece'], reason: 'la pièce du SERVEUR');
    expect(a.auteur, donnees['par']);
    expect(a.dateApprobation, '2031-04-30');
    expect(a.ventilation, {
      'reserve_legale': 700000,
      'autres_reserves': 300000,
      'dividendes': 1000000,
      'report_a_nouveau': 5000000,
    });
    // Le serveur et le poste disent la même chose du résultat et de la possibilité.
    expect(etat.affectable, r[8]['affectable']);
    expect(
      etat.resultatCentimes,
      (double.parse(r[8]['resultat']! as String) * 100).round(),
    );
    expect(
      (await OperationsSyncDao(b.db).operations()),
      isEmpty,
      reason: 'ce qui descend ne remonte pas',
    );
  });

  test('contre-passée au web : le poste la voit contre-passée et peut la '
      'refaire', () async {
    final donnees = (flux(11).single['donnees']! as Map)
        .cast<String, Object?>();
    expect(
      donnees['contrepassee_le'],
      isNotNull,
      reason: 'le serveur descend la contre-passation',
    );
    expect(r[12]['affectable'], isTrue);

    await descendre(7);
    expect((await carte().etat(await id()))!.affectable, isFalse);
    await descendre(11);
    final apres = (await carte().etat(await id()))!;
    expect(apres.active, isNull);
    expect(apres.affectable, r[12]['affectable']);
    expect(apres.resultatCentimes, 7000000);
  });

  test('refaite au web : la nouvelle est l\'active, l\'ancienne reste en '
      'historique', () async {
    expect(flux(14), hasLength(2));
    await descendre(14);
    final a = (await carte().active(await id()))!;
    expect(a.numeroPiece, r[15]['active_piece']);
    expect(a.ventilation, {'report_a_nouveau': 7000000});
    expect((await carte().etat(await id()))!.affectable, r[15]['affectable']);
  });
}
