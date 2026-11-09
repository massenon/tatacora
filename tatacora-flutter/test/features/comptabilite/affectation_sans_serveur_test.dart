import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/comptabilite/data/affectation_resultat_locale.dart';
import 'package:tatacora_flutter/features/comptabilite/data/cloture_exercice_locale.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/moteur_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/affectation_resultat.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/refus_comptable.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/sync_manager.dart';
import 'package:tatacora_flutter/features/synchronisation/data/transport_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/bilan_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/suivi_synchronisation.dart';

import '../synchronisation/support/faux_transport.dart';
import 'support/outils_comptabilite.dart';

/// Le poste fonctionne SANS le serveur (décision du PO) — l'affectation du
/// résultat comprise : synchronisation DÉSACTIVÉE, la pièce d'affectation et sa
/// contre-passation se passent, s'écrivent au grand livre du poste et s'enfilent,
/// sans UNE requête réseau ; à la réactivation, tout part dans l'ordre.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late BancSync b;
  late AppDatabase db;
  late FauxTransport interdit;

  setUp(() async {
    b = await BancSync.creer();
    db = await baseInstallee(maintenant: DateTime(2031, 6, 15));
    await poserFormeJuridique(db, 'sarl');
    interdit = FauxTransport((r) => throw StateError('RÉSEAU : ${r.url}'));
    await b.ecrivain.enregistrerSynchronisationActivee(
      false,
      par: 'gerant',
      le: DateTime(2031, 6, 1),
    );
  });
  tearDown(() async {
    await db.close();
    await b.fermer();
  });

  SyncManager manager(TransportSynchronisation t) => SyncManager(
    dao: OperationsSyncDao(db, maintenant: () => b.maintenant),
    transport: t,
    urlServeur: BancSync.urlServeur,
    demonstration: false,
    lecteur: b.lecteur,
    ecrivain: b.ecrivain,
    maintenant: () => b.maintenant,
    descente: DescenteCatalogue(
      db: db,
      transport: t,
      auteur: () async => null,
      maintenant: () => b.maintenant,
    ),
  );

  test('synchronisation DÉSACTIVÉE : l’affectation se passe, se contre-passe '
      'et s’enfile sans une requête ; la réactivation envoie tout dans '
      'l’ordre', () async {
    final dao = ComptabiliteDao(db);
    await dao.insererExercice(
      annee: 2030,
      dateDebut: '2030-01-01',
      dateFin: '2030-12-31',
    );
    final maintenant = DateTime(2031, 6, 15, 10);
    final moteur = MoteurComptable(dao, maintenant: () => maintenant);
    final clotures = ClotureExerciceLocale(
      db,
      moteur,
      maintenant: () => maintenant,
    );
    final affectation = AffectationResultatLocale(
      db,
      moteur,
      maintenant: () => maintenant,
    );
    final bar = (await dao.centreParLibelle('Bar'))!.id;
    final restaurant = (await dao.centreParLibelle('Restaurant'))!.id;
    await moteur.passerEtValider(
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
    await moteur.passerEtValider(
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
    final id = (await dao.exerciceDeLAnnee(2030))!.id;
    await clotures.demarrer(id, auteurId: auteurEssai);
    await clotures.cloturer(id, auteurId: auteurEssai);

    // L'affectation et sa contre-passation : le poste travaille seul.
    final piece = await affectation.affecter(
      id,
      ventilation: {'reserve_legale': 700000, 'report_a_nouveau': 6300000},
      date: '2031-04-30',
      auteurId: auteurEssai,
    );
    expect(piece, 'OD-2031-00001');
    expect((await affectation.active(id))!.numeroPiece, piece);
    await affectation.contrepasser(
      id,
      auteurId: auteurEssai,
      motif: 'Ventilation à revoir en assemblée',
    );
    expect(await affectation.active(id), isNull);
    await affectation.affecter(
      id,
      ventilation: {'report_a_nouveau': 7000000},
      date: '2031-05-02',
      auteurId: auteurEssai,
    );

    // La file se remplit, rien n'est parti.
    final file = OperationsSyncDao(db, maintenant: () => b.maintenant);
    final avant = await file.operations();
    expect(
      {for (final o in avant) o.statut},
      {StatutOperationSync.enAttente},
      reason: 'rien n’est parti : tout attend',
    );
    final pieces = [
      for (final o in avant)
        if (o.table == TableSynchronisee.piecesSaisie) o,
    ];
    expect(pieces, hasLength(2), reason: 'deux affectations enfilées');
    expect(
      [
        for (final o in avant)
          if (o.table == TableSynchronisee.demandesClotureExercice)
            (jsonDecode(o.payload) as Map)['action'],
      ],
      ['demarrer', 'cloturer', 'annuler_affectation'],
    );

    // Tous les chemins réseau, interrupteur éteint : aucune requête.
    final m = manager(interdit);
    final bilan = await m.synchroniserMaintenant();
    expect(bilan.etat, EtatSynchronisation.desactivee);
    expect(interdit.requetes, isEmpty, reason: 'AUCUNE requête réseau');
    expect(
      {for (final o in await file.operations()) o.statut},
      {StatutOperationSync.enAttente},
      reason: 'le passage n’a rien consommé',
    );

    // Les mots du poste : l'opération se dit « Contre-passer l'affectation (2030) ».
    final annulation = (await file.operations(
      table: TableSynchronisee.demandesClotureExercice,
    )).last;
    expect(libelleDocument(annulation), 'Contre-passer l’affectation (2030)');
  });

  test('entreprise individuelle (le défaut), SANS serveur : le résultat va au '
      'compte de l’exploitant, dividende et réserve légale sont refusés '
      'localement, la contre-passation s’enfile avec sa référence', () async {
    // Aucune forme descendue : le défaut du Gîte.
    await (db.delete(db.parametresSystemeLocal)).go();
    final dao = ComptabiliteDao(db);
    await dao.insererExercice(
      annee: 2030,
      dateDebut: '2030-01-01',
      dateFin: '2030-12-31',
    );
    final maintenant = DateTime(2031, 6, 15, 10);
    final moteur = MoteurComptable(dao, maintenant: () => maintenant);
    final clotures = ClotureExerciceLocale(
      db,
      moteur,
      maintenant: () => maintenant,
    );
    final affectation = AffectationResultatLocale(
      db,
      moteur,
      maintenant: () => maintenant,
    );
    final bar = (await dao.centreParLibelle('Bar'))!.id;
    await moteur.passerEtValider(
      DemandePiece(
        journal: 'CAI',
        date: '2030-03-10',
        libelle: 'Ventes bar',
        lignes: [
          LigneDemandee(compte: '5711', debitCentimes: 7000000, centreId: bar),
          LigneDemandee(compte: '7011', creditCentimes: 7000000, centreId: bar),
        ],
      ),
      auteurId: auteurEssai,
    );
    final id = (await dao.exerciceDeLAnnee(2030))!.id;
    await clotures.demarrer(id, auteurId: auteurEssai);
    await clotures.cloturer(id, auteurId: auteurEssai);

    expect((await affectation.forme()).code, 'entreprise_individuelle');
    final carte = (await affectation.etat(id))!;
    expect(carte.postes, postesBeneficeEi);
    expect(carte.proposition['compte_exploitant'], 7000000);

    // Un dividende (compte 465) et une réserve légale : refusés au poste, aux mots du serveur.
    await expectLater(
      affectation.affecter(
        id,
        ventilation: {'dividendes': 1000000, 'compte_exploitant': 6000000},
        date: '2031-04-30',
        auteurId: auteurEssai,
      ),
      throwsA(
        isA<RefusComptable>().having(
          (e) => e.message,
          'message',
          contains('Une entreprise individuelle ne verse pas de dividendes'),
        ),
      ),
    );
    await expectLater(
      affectation.affecter(
        id,
        ventilation: {'reserve_legale': 700000, 'compte_exploitant': 6300000},
        date: '2031-04-30',
        auteurId: auteurEssai,
      ),
      throwsA(
        isA<RefusComptable>().having(
          (e) => e.message,
          'message',
          contains('n\'a pas de réserve légale'),
        ),
      ),
    );
    expect(await affectation.active(id), isNull, reason: 'rien n’est écrit');

    // 50 000 à l'exploitant (1041), 20 000 au report à nouveau.
    await affectation.affecter(
      id,
      ventilation: {'compte_exploitant': 5000000, 'report_a_nouveau': 2000000},
      date: '2031-04-30',
      auteurId: auteurEssai,
    );
    final active = (await affectation.active(id))!;
    expect(active.ventilation, {
      'compte_exploitant': 5000000,
      'report_a_nouveau': 2000000,
    });
    final comptes = <String>{
      for (final l in await dao.toutesLesEcritures())
        if (l.libelle == 'Affectation du résultat de l\'exercice 2030')
          (await dao.compteParId(l.compteId))!.numero,
    };
    expect(comptes, {'131', '1041', '121'});

    await affectation.contrepasser(
      id,
      auteurId: auteurEssai,
      motif: 'Décision de l’exploitant révisée',
      reference: 'Décision du 15/06/2031',
    );
    expect(await affectation.active(id), isNull);

    final file = OperationsSyncDao(db, maintenant: () => b.maintenant);
    final avant = await file.operations();
    final charge =
        jsonDecode(
              avant
                  .firstWhere((o) => o.table == TableSynchronisee.piecesSaisie)
                  .payload,
            )
            as Map<String, dynamic>;
    expect(
      ((charge['affectation'] as Map)['ventilation']
          as Map)['compte_exploitant'],
      5000000,
    );
    final annulation =
        jsonDecode(
              avant
                  .lastWhere(
                    (o) => o.table == TableSynchronisee.demandesClotureExercice,
                  )
                  .payload,
            )
            as Map<String, dynamic>;
    expect(annulation['action'], 'annuler_affectation');
    expect(annulation['reference_decision'], 'Décision du 15/06/2031');

    final bilan = await manager(interdit).synchroniserMaintenant();
    expect(bilan.etat, EtatSynchronisation.desactivee);
    expect(interdit.requetes, isEmpty, reason: 'AUCUNE requête réseau');
  });
}
