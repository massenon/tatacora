@Timeout(Duration(minutes: 4))
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/ecritures_serveur_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/moteur_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/montant_comptable.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import 'support/faux_transport.dart';
import 'support/scenario_file.dart';

/// D246 ROUVERT (28/10/2026) confronté au VRAI serveur : les comptes et les
/// pièces saisies à la main que le poste enfile sont poussés TELS QUELS au vrai
/// `SynchronisationService` (`tool/comptabilite/rejouer_plan_et_pieces.php`) ; le
/// serveur rejoue `PlanComptableService` et `PasserEcritureService`, passe SA
/// pièce, et ce qu'il rend (numéro, lignes, origine) est RELU — puis redescendu au
/// poste, qui reconnaît sa pièce sans la compter deux fois.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final maintenant = DateTime(2031, 6, 15, 10);

  late BancSync b;
  late MoteurComptable moteur;
  late ComptabiliteDao dao;
  late String bar;

  setUp(() async {
    b = await BancSync.creer();
    await semerAuteur(b.db);
    await baseInstalleeSur(b.db, maintenant);
    moteur = moteurSur(b.db, maintenant: () => maintenant);
    dao = ComptabiliteDao(b.db);
    bar = (await dao.centres()).firstWhere((c) => c.libelle == 'Bar').id;
  });
  tearDown(() => b.fermer());

  DemandePiece charge({String date = '2031-06-10'}) => DemandePiece(
    journal: 'OD',
    date: date,
    libelle: 'Charge diverse',
    lignes: [
      LigneDemandee(
        compte: '6099',
        debitCentimes: 123456,
        creditCentimes: 0,
        centreId: bar,
        libelle: 'Détail',
      ),
      const LigneDemandee(compte: '5711', creditCentimes: 123456),
    ],
  );

  Future<Map<String, dynamic>> pousser(
    List<Map<String, Object?>> operations, {
    bool redescente = false,
  }) => executerPhp(
    'rejouer_plan_et_pieces.php',
    entree: {
      'aujourdhui': '2031-06-15',
      'poste_id': 'poste-essai-pieces',
      'role': 'comptable',
      'operations': operations,
      'redescente': redescente,
    },
  );

  List<Map<String, dynamic>> liste(Object? x) => [
    for (final e in x! as List) (e as Map).cast<String, dynamic>(),
  ];

  test('le compte puis la pièce qui le cite : le serveur rejoue et passe '
      'une pièce IDENTIQUE à celle du poste, avec l’origine du poste', () async {
    final compte = await moteur.creerCompte(
      '6099',
      'Charges diverses',
      'charge',
    );
    await moteur.saisirPiece(charge(), auteurId: auteurEssai, valider: true);
    await moteur.saisirPiece(
      charge(date: '2031-06-12'),
      auteurId: auteurEssai,
      valider: false,
    );

    final serveur = await pousser(await fileAuProtocole(b.db));
    expect(serveur['enveloppe'], isEmpty);
    final r = liste(serveur['resultats']);
    expect(
      r.map((x) => x['statut']),
      everyElement('synchronise'),
      reason: '$r',
    );
    expect(r[0]['numero'], '6099');

    // Le compte est au plan du serveur, sous l'identifiant du poste.
    final c = liste(
      serveur['comptes'],
    ).singleWhere((x) => x['numero'] == '6099');
    expect(c['id'], compte.id);
    expect(c['libelle'], 'Charges diverses');
    expect(c['classe'], '6');
    expect(c['nature'], 'charge');

    // Deux pièces, deux numéros : ceux du poste (même registre, même séquence).
    final localValidee = await dao.lignesDeLaPiece('OD-2031-00001');
    expect(r[1]['numero_piece'], 'OD-2031-00001');
    expect(r[1]['statut_piece'], 'validee');
    expect(r[2]['numero_piece'], 'OD-2031-00002');
    expect(r[2]['statut_piece'], 'brouillon');

    final lignes = liste(serveur['lignes']);
    expect(lignes, hasLength(4));
    String cle(
      String j,
      String n,
      String d,
      String cpt,
      String ctr,
      String db,
      String cr,
      String st,
    ) => '$j|$n|$d|$cpt|$ctr|$db|$cr|$st';
    final exercice = (await dao.exerciceDeLAnnee(2031))!;
    final statuts = {
      for (final n in ['OD-2031-00001', 'OD-2031-00002'])
        n: (await dao.lignesDeLaPiece(n)).first.estValidee
            ? 'validee'
            : 'brouillon',
    };
    final attendu = [
      for (final l in await dao.lignesPourArchive(exercice.id))
        if (statuts.containsKey(l.numeroPiece))
          cle(
            'OD',
            l.numeroPiece!,
            l.dateEcriture,
            l.numeroCompte,
            l.libelleCentre,
            chaineDepuisCentimes(l.debitCentimes),
            chaineDepuisCentimes(l.creditCentimes),
            statuts[l.numeroPiece]!,
          ),
    ]..sort();
    final recu = [
      for (final l in lignes)
        cle(
          l['journal'] as String,
          l['numero_piece'] as String,
          l['date'] as String,
          l['compte'] as String,
          l['centre'] as String,
          l['debit'] as String,
          l['credit'] as String,
          l['statut'] as String,
        ),
    ]..sort();
    expect(recu, attendu);
    expect(localValidee, hasLength(2));

    // Chaque ligne du serveur porte l'origine de SA pièce de saisie.
    final origines = (await b.db.select(b.db.piecesSaisieLocal).get())
      ..sort((a, b) => a.numeroPiece.compareTo(b.numeroPiece));
    expect(
      {for (final l in lignes) '${l['numero_piece']}': l['origine']},
      {for (final o in origines) o.numeroPiece: o.id},
    );
    expect(liste(serveur['sources']).map((s) => s['nombre_lignes']), [2, 2]);

    // Rejeu du MÊME lot : aucun second numéro, aucune seconde pièce.
    final rejeu = await pousser([
      ...await fileAuProtocole(b.db),
      ...await fileAuProtocole(b.db),
    ]);
    expect(liste(rejeu['lignes']), hasLength(4));
  });

  test('redescendue, la pièce est reconnue par son origine : ni renvoyée, ni '
      'comptée deux fois', () async {
    await moteur.creerCompte('6099', 'Charges diverses', 'charge');
    await moteur.saisirPiece(charge(), auteurId: auteurEssai, valider: true);

    final serveur = await pousser(
      await fileAuProtocole(b.db),
      redescente: true,
    );
    final elements = liste(serveur['descente']);
    expect(
      elements.where((e) => e['table'] == 'ecritures_comptables'),
      hasLength(2),
    );
    // Le plan descend AVANT les écritures qui citent le compte.
    expect(
      elements.indexWhere((e) => e['table'] == 'plan_comptable'),
      lessThan(
        elements.indexWhere((e) => e['table'] == 'ecritures_comptables'),
      ),
    );

    expect(await dao.piecesSaisiesNonReprises(), hasLength(1));
    await DescenteCatalogueDao(b.db).effacerCurseur();
    final bilan = await b
        .descente(FauxTransport((r) => FauxCatalogue(elements).repondre(r)))
        .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
    expect(bilan.refuses, 0, reason: bilan.motifsRefus.join(' ; '));
    expect(await dao.piecesSaisiesNonReprises(), isEmpty);

    // Le miroir porte la pièce du serveur UNE fois (2 lignes), 123 456 centimes.
    final miroir = await EcrituresServeurDao(b.db).deLAnnee(2031);
    expect(miroir.where((l) => l.numeroCompte == '6099'), hasLength(1));
    expect(
      miroir.fold<int>(0, (s, l) => s + l.debitCentimes),
      miroir.fold<int>(0, (s, l) => s + l.creditCentimes),
    );
    expect(
      miroir.where((l) => l.numeroCompte == '6099').single.debitCentimes,
      123456,
    );
    // La file ne porte QUE ce que le poste a saisi : rien de descendu.
    final tables = {
      for (final o in await b.dao.operations()) o.table.nomServeur,
    };
    expect(tables, {'plan_comptable', 'pieces_saisie'});
  });

  test('les refus du serveur sont dits à ses mots, sans rien écrire', () async {
    await moteur.creerCompte('6099', 'Charges diverses', 'charge');
    // Un autre poste a recréé 6099 sous un autre libellé : refus lisible.
    final operations = await fileAuProtocole(b.db);
    final autre = {
      ...operations.first,
      'uuid_operation': '5a0c1c7e-4a0e-4c43-9a0e-0d6b3f6a0001',
      'entite_id': '5a0c1c7e-4a0e-4c43-9a0e-0d6b3f6a0002',
      'payload': {
        'numero_compte': '6099',
        'libelle': 'Un autre libellé',
        'nature': 'charge',
      },
    };
    final serveur = await pousser([...operations, autre]);
    expect(serveur['enveloppe'], isEmpty);
    final r = liste(serveur['resultats']);
    expect(r[0]['statut'], 'synchronise');
    expect(r[1]['statut'], 'rejete');
    expect(r[1]['motif'], 'Le compte 6099 existe déjà au plan comptable.');
    expect(
      liste(serveur['comptes']).where((c) => c['numero'] == '6099'),
      hasLength(1),
    );
  });
}
