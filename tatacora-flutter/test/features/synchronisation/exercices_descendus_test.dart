import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/moteur_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/entities/comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/refus_comptable.dart';
import 'package:tatacora_flutter/features/synchronisation/data/aligneur_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart';

import '../comptabilite/support/outils_comptabilite.dart';

/// Passage d'année (20/10/2026) : les exercices du serveur DESCENDENT, avec
/// leur statut. Une clôture faite au serveur verrouille l'année sur le poste
/// — l'exercice local garde son identifiant (ses écritures le désignent) —,
/// et rien ne repart vers le serveur.
void main() {
  late AppDatabase db;

  setUp(
    () async => db = await baseInstallee(maintenant: DateTime(2031, 6, 15)),
  );
  tearDown(() => db.close());

  Future<IssueAlignement> descendre(Map<String, Object?> donnees) =>
      db.transaction(
        () =>
            AligneurCatalogue(
              db,
              DescenteCatalogueDao(db),
              auteur: () async => null,
            ).aligner(
              ElementCatalogue(
                table: TableDescendue.exercicesComptables,
                id: 'srv-${donnees['annee']}',
                actif: true,
                modifieLe: '2031-06-15 10:00:00',
                donnees: donnees,
              ),
            ),
      );

  Future<RefusComptable> refus(Future<Object?> action) async {
    try {
      await action;
    } on RefusComptable catch (e) {
      return e;
    }
    fail('refus attendu');
  }

  DemandePiece vente(String date, String centre) => DemandePiece(
    journal: 'VTE',
    date: date,
    libelle: 'Vente',
    lignes: [
      const LigneDemandee(compte: '5711', debitCentimes: 100),
      LigneDemandee(compte: '7061', creditCentimes: 100, centreId: centre),
    ],
  );

  test('une clôture du serveur verrouille l’année ici, même identifiant '
      'local ; une année absente y naît ; rien ne repart', () async {
    final dao = ComptabiliteDao(db);
    final avant = (await dao.exerciceDeLAnnee(2031))!;
    final restaurant = (await dao.centreParLibelle('Restaurant'))!.id;
    final moteur = moteurSur(db);
    expect(
      await moteur.passer(
        vente('2031-06-15', restaurant),
        auteurId: auteurEssai,
      ),
      hasLength(2),
    );

    expect(
      await descendre({
        'annee': 2031,
        'date_debut': '2031-01-01',
        'date_fin': '2031-12-31',
        'statut': 'cloture',
        'date_cloture': '2032-03-31T10:00:00+00:00',
      }),
      isA<Aligne>(),
    );
    final apres = (await dao.exerciceDeLAnnee(2031))!;
    expect(apres.id, avant.id);
    expect(apres.statut, StatutExercice.cloture);

    // Une pièce de l'année close est désormais refusée sur le poste.
    final e = await refus(
      moteur.passer(vente('2031-06-16', restaurant), auteurId: auteurEssai),
    );
    expect(e.motif, MotifRefus.exerciceNonOuvert);

    // L'exercice suivant, ouvert au serveur, naît ici.
    await descendre({
      'annee': 2032,
      'date_debut': '2032-01-01',
      'date_fin': '2032-12-31',
      'statut': 'ouvert',
      'date_cloture': null,
    });
    expect((await dao.exerciceDeLAnnee(2032))!.statut, StatutExercice.ouvert);

    expect(await OperationsSyncDao(db).operations(), isEmpty);
    expect(
      await descendre({'annee': 2033, 'statut': 'inconnu'}),
      isA<RefuseParLePoste>(),
    );
  });
}
