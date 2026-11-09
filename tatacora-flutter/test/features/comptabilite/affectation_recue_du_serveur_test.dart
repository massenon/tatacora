import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/comptabilite/data/affectation_resultat_locale.dart';
import 'package:tatacora_flutter/features/comptabilite/data/affectations_recues_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/cloture_exercice_locale.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/moteur_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/entities/comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/refus_comptable.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';

import '../synchronisation/support/faux_transport.dart';
import 'support/outils_comptabilite.dart';

/// UNE AFFECTATION DU RÉSULTAT passée au WEB (ou par un autre poste) APPARAÎT sur le
/// poste après la synchronisation (09/11/2026, PO : « ÇA DOIT APPARAÎTRE »).
///
/// Le chemin est celui de la production : un élément `affectations_resultat` du flux
/// du serveur -> `DescenteCatalogue` -> `AligneurCatalogue._affectationRecue` ->
/// `AffectationsRecuesDao` (seul écrivain de `affectations_resultat_local`) ->
/// `AffectationResultatLocale` (la carte). Chaque cas RELIT la base.
///
/// Ce que ces cas tiennent :
///  - une affectation du web s'affiche (auteur, date, pièce, ventilation) et
///    « Passer l'affectation » n'est plus offert (l'unicité est connue du poste) ;
///  - sa contre-passation au web fait réapparaître la possibilité de la refaire ;
///  - l'affectation de CE poste, reprise par le serveur (identifiant d'origine), ne
///    s'affiche JAMAIS deux fois ; contre-passée au web, elle n'est plus active ;
///  - rien n'est enfilé, aucun réseau n'est requis pour lire.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late BancSync b;
  late ComptabiliteDao dao;
  final maintenant = DateTime(2031, 6, 15, 10);

  setUp(() async {
    b = await BancSync.creer();
    b.maintenant = maintenant;
    await b.semerAuteur();
    await semerAuteur(b.db);
    await baseInstalleeSur(b.db, maintenant);
    dao = ComptabiliteDao(b.db);
  });
  tearDown(() => b.fermer());

  MoteurComptable moteur() =>
      MoteurComptable(dao, maintenant: () => maintenant);

  AffectationResultatLocale locale() =>
      AffectationResultatLocale(b.db, moteur(), maintenant: () => maintenant);

  Future<String> idExercice(int annee) async =>
      (await dao.exerciceDeLAnnee(annee))!.id;

  /// 2030 CLÔTURÉ AILLEURS : le poste n'a ni sa clôture ni son résultat, seulement le
  /// statut et la date que le serveur lui a donnés ; 2031 ouvert.
  Future<void> exerciceClotureAilleurs({DateTime? dateCloture}) async {
    await dao.alignerExerciceDescendu(
      annee: 2030,
      dateDebut: '2030-01-01',
      dateFin: '2030-12-31',
      statut: StatutExercice.cloture,
      dateCloture: dateCloture ?? DateTime(2031, 1, 10, 9),
    );
    await dao.alignerExerciceDescendu(
      annee: 2031,
      dateDebut: '2031-01-01',
      dateFin: '2031-12-31',
      statut: StatutExercice.ouvert,
    );
  }

  /// 2030 clôturé PAR CE POSTE (bénéfice de 70 000), sa clôture locale active.
  Future<void> exerciceClotureIci() async {
    await dao.insererExercice(
      annee: 2030,
      dateDebut: '2030-01-01',
      dateFin: '2030-12-31',
    );
    final bar = (await dao.centreParLibelle('Bar'))!.id;
    final restaurant = (await dao.centreParLibelle('Restaurant'))!.id;
    await moteur().passerEtValider(
      DemandePiece(
        journal: 'CAI',
        date: '2030-03-10',
        libelle: 'Ventes bar',
        lignes: [
          LigneDemandee(compte: '5711', debitCentimes: 10000000, centreId: bar),
          LigneDemandee(
            compte: '7011',
            creditCentimes: 10000000,
            centreId: bar,
          ),
        ],
      ),
      auteurId: auteurEssai,
    );
    await moteur().passerEtValider(
      DemandePiece(
        journal: 'CAI',
        date: '2030-03-11',
        libelle: 'Marché',
        lignes: [
          LigneDemandee(
            compte: '6011',
            debitCentimes: 3000000,
            centreId: restaurant,
          ),
          LigneDemandee(
            compte: '5711',
            creditCentimes: 3000000,
            centreId: restaurant,
          ),
        ],
      ),
      auteurId: auteurEssai,
    );
    final clotures = ClotureExerciceLocale(
      b.db,
      moteur(),
      maintenant: () => maintenant,
    );
    final id = await idExercice(2030);
    await clotures.demarrer(id, auteurId: auteurEssai);
    await clotures.cloturer(id, auteurId: auteurEssai);
  }

  /// Un élément `affectations_resultat` tel que le serveur le rend.
  Map<String, Object?> affectationDuServeur(
    String id, {
    String resultat = '70000.00',
    String reserve = '7000.00',
    String autres = '0.00',
    String dividendes = '10000.00',
    String reportCrediteur = '53000.00',
    String reportDebiteur = '0.00',
    String piece = 'OD-2031-00007',
    String? pieceOrigine,
    String? par = 'comptable-web',
    String affecteeLe = '2031-05-02 14:30:00',
    String? contrepasseeLe,
    int annee = 2030,
  }) => element('affectations_resultat', id, {
    'annee': annee,
    'resultat': resultat,
    'date_approbation': '2031-04-30',
    'reserve_legale': reserve,
    'autres_reserves': autres,
    'dividendes': dividendes,
    'report_a_nouveau_crediteur': reportCrediteur,
    'report_a_nouveau_debiteur': reportDebiteur,
    'piece_affectation': piece,
    'piece_origine_id': pieceOrigine,
    'affectee_le': affecteeLe,
    'contrepassee_le': contrepasseeLe,
    'par': par,
  });

  /// La synchronisation : le flux du serveur descend, par le vrai chemin.
  Future<void> descendre(List<Map<String, Object?>> elements) async {
    await DescenteCatalogueDao(b.db).effacerCurseur();
    final bilan = await b
        .descente(
          FauxTransport(
            (r) => r.methode == 'GET'
                ? FauxCatalogue(elements).repondre(r)
                : reponseLot(r),
          ),
        )
        .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
    expect(bilan.refuses, 0, reason: 'rien n’est refusé par le poste');
  }

  Future<int> nombreEnFile() async =>
      (await OperationsSyncDao(b.db).operations()).length;

  test('une affectation passée AU WEB apparaît : auteur, date, pièce, '
      'ventilation ; « Passer » n’est plus offert', () async {
    await exerciceClotureAilleurs();
    final id = await idExercice(2030);
    expect(
      await locale().etat(id),
      isNull,
      reason: 'avant la synchronisation, ce poste n’a rien à montrer',
    );

    await descendre([affectationDuServeur('aff-web-1')]);

    final etat = (await locale().etat(id))!;
    expect(etat.resultatCentimes, 7000000);
    expect(etat.annee, 2030);
    expect(etat.affectable, isFalse, reason: 'l’unicité est connue du poste');
    final a = etat.active!;
    expect(a.parAilleurs, isTrue);
    expect(a.numeroPiece, 'OD-2031-00007');
    expect(a.auteur, 'comptable-web');
    expect(a.passeeLe, DateTime(2031, 5, 2, 14, 30));
    expect(a.dateApprobation, '2031-04-30');
    expect(a.ventilation, {
      'reserve_legale': 700000,
      'dividendes': 1000000,
      'report_a_nouveau': 5300000,
    });

    // Une table, une ligne ; rien n'a été enfilé : ce qui descend ne remonte pas.
    expect(await AffectationsRecuesDao(b.db).deLAnnee(2030), hasLength(1));
    expect(await nombreEnFile(), 0);

    // Et le poste refuse d'en passer une seconde, à la phrase du serveur.
    await expectLater(
      locale().affecter(
        id,
        ventilation: {'report_a_nouveau': 7000000},
        date: '2031-05-03',
        auteurId: auteurEssai,
      ),
      throwsA(
        isA<RefusComptable>()
            .having((r) => r.motif, 'motif', MotifRefus.affectationDejaPassee)
            .having((r) => r.message, 'message', contains('OD-2031-00007')),
      ),
    );
    expect(await nombreEnFile(), 0);
  });

  test('descendue une seconde fois, la même affectation ne fait pas de '
      'doublon (rejeu idempotent)', () async {
    await exerciceClotureAilleurs();
    await descendre([affectationDuServeur('aff-web-1')]);
    await descendre([affectationDuServeur('aff-web-1')]);
    expect(await AffectationsRecuesDao(b.db).deLAnnee(2030), hasLength(1));
  });

  test('une perte passée au web : imputation et report débiteur se lisent '
      'comme au serveur', () async {
    await exerciceClotureAilleurs();
    await descendre([
      affectationDuServeur(
        'aff-perte',
        resultat: '-30000.00',
        reserve: '0.00',
        autres: '5000.00',
        dividendes: '0.00',
        reportCrediteur: '10000.00',
        reportDebiteur: '15000.00',
      ),
    ]);
    final etat = (await locale().etat(await idExercice(2030)))!;
    expect(etat.resultatCentimes, -3000000);
    expect(etat.active!.ventilation, {
      'autres_reserves': 500000,
      'imputation_report_crediteur': 1000000,
      'report_a_nouveau': 1500000,
    });
  });

  test('la contre-passation faite AU WEB rend la possibilité de la refaire, '
      'et le poste la refait', () async {
    await exerciceClotureAilleurs();
    final id = await idExercice(2030);
    await descendre([affectationDuServeur('aff-web-1')]);
    expect((await locale().etat(id))!.affectable, isFalse);

    // Le web contre-passe : la MÊME ligne redescend, datée.
    await descendre([
      affectationDuServeur('aff-web-1', contrepasseeLe: '2031-05-10 09:00:00'),
    ]);
    final apres = (await locale().etat(id))!;
    expect(apres.active, isNull);
    expect(apres.affectable, isTrue);
    expect(
      apres.resultatCentimes,
      7000000,
      reason: 'le résultat de la clôture reste lisible sur la ligne reçue',
    );

    // Refaite ICI : une pièce, enfilée comme une pièce saisie à la main.
    final piece = await locale().affecter(
      id,
      ventilation: {'report_a_nouveau': 7000000},
      date: '2031-05-12',
      auteurId: auteurEssai,
    );
    final nouvelle = (await locale().active(id))!;
    expect(nouvelle.parAilleurs, isFalse);
    expect(nouvelle.numeroPiece, piece);
    expect(
      [
        for (final o in await OperationsSyncDao(b.db).operations())
          o.table.nomServeur,
      ],
      ['pieces_saisie'],
    );
  });

  test(
    'une contre-passée du web n’est reprise que si elle date de la '
    'clôture en cours : exercice rouvert puis reclos, pas de vieux résultat',
    () async {
      // Clôturé de nouveau le 1er juin : la ligne contre-passée est d'AVANT.
      await exerciceClotureAilleurs(dateCloture: DateTime(2031, 6, 1, 8));
      await descendre([
        affectationDuServeur(
          'aff-vieille',
          contrepasseeLe: '2031-05-10 09:00:00',
        ),
      ]);
      expect(
        await locale().etat(await idExercice(2030)),
        isNull,
        reason: 'le résultat de la clôture en cours est inconnu : pas de carte',
      );
    },
  );

  test('l’affectation de CE poste, reprise par le serveur, ne s’affiche pas '
      'deux fois', () async {
    await exerciceClotureIci();
    final id = await idExercice(2030);
    final piece = await locale().affecter(
      id,
      ventilation: {'reserve_legale': 700000, 'report_a_nouveau': 6300000},
      date: '2031-04-30',
      auteurId: auteurEssai,
    );
    final avant = (await locale().active(id))!;
    expect(avant.numeroPiece, piece);
    expect(avant.parAilleurs, isFalse);
    final origine = await b.db
        .customSelect('SELECT id FROM pieces_saisie_local')
        .getSingle()
        .then((r) => r.data['id']! as String);

    // Le serveur l'a reprise (sa pièce porte l'identifiant d'origine du poste).
    await descendre([
      affectationDuServeur(
        'aff-reprise',
        reserve: '7000.00',
        dividendes: '0.00',
        reportCrediteur: '63000.00',
        piece: 'OD-2031-00099',
        pieceOrigine: origine,
        par: 'compta-u-compta',
      ),
    ]);

    final apres = (await locale().active(id))!;
    expect(
      apres.parAilleurs,
      isFalse,
      reason: 'c’est SA pièce : lue du journal du poste, jamais deux fois',
    );
    expect(apres.numeroPiece, piece);
    expect((await locale().etat(id))!.affectable, isFalse);
  });

  test('l’affectation de ce poste contre-passée au WEB n’est plus active, '
      'et le poste peut la refaire — sans double', () async {
    await exerciceClotureIci();
    final id = await idExercice(2030);
    await locale().affecter(
      id,
      ventilation: {'reserve_legale': 700000, 'report_a_nouveau': 6300000},
      date: '2031-04-30',
      auteurId: auteurEssai,
    );
    final origine = await b.db
        .customSelect('SELECT id FROM pieces_saisie_local')
        .getSingle()
        .then((r) => r.data['id']! as String);

    await descendre([
      affectationDuServeur(
        'aff-reprise',
        piece: 'OD-2031-00099',
        pieceOrigine: origine,
        reportCrediteur: '63000.00',
        dividendes: '0.00',
        contrepasseeLe: '2031-05-10 09:00:00',
      ),
    ]);

    // Les lignes du journal du poste n'ont pas bougé ; le serveur, juge, dit
    // « contre-passée » : la carte offre de nouveau l'affectation.
    expect(await locale().active(id), isNull);
    final etat = (await locale().etat(id))!;
    expect(etat.affectable, isTrue);
    expect(etat.resultatCentimes, 7000000);

    final seconde = await locale().affecter(
      id,
      ventilation: {'report_a_nouveau': 7000000},
      date: '2031-05-12',
      auteurId: auteurEssai,
    );
    final active = (await locale().active(id))!;
    expect(active.numeroPiece, seconde);
    expect(active.parAilleurs, isFalse);
  });

  test(
    'l’affectation d’une autre pièce du poste n’est pas confondue avec '
    'celle d’ailleurs : deux affectations, la contre-passée puis l’active',
    () async {
      await exerciceClotureAilleurs();
      final id = await idExercice(2030);
      await descendre([
        affectationDuServeur(
          'aff-1',
          piece: 'OD-2031-00007',
          affecteeLe: '2031-05-02 14:30:00',
          contrepasseeLe: '2031-05-10 09:00:00',
        ),
        affectationDuServeur(
          'aff-2',
          piece: 'OD-2031-00012',
          affecteeLe: '2031-05-11 08:00:00',
          par: 'autre-poste',
        ),
      ]);
      final a = (await locale().active(id))!;
      expect(
        a.numeroPiece,
        'OD-2031-00012',
        reason: 'la contre-passée est passée',
      );
      expect(a.auteur, 'autre-poste');
      expect(await AffectationsRecuesDao(b.db).deLAnnee(2030), hasLength(2));
    },
  );

  test('un montant à fraction de centime est REFUSÉ par le poste, pas '
      'arrondi', () async {
    await exerciceClotureAilleurs();
    await DescenteCatalogueDao(b.db).effacerCurseur();
    final bilan = await b
        .descente(
          FauxTransport(
            (r) => r.methode == 'GET'
                ? FauxCatalogue([
                    affectationDuServeur('aff-bizarre', reserve: '7000.005'),
                  ]).repondre(r)
                : reponseLot(r),
          ),
        )
        .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
    expect(bilan.refuses, 1);
    expect(await AffectationsRecuesDao(b.db).deLAnnee(2030), isEmpty);
  });
}
