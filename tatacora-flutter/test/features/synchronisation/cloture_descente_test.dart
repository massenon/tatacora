import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/comptabilite/data/cloture_exercice_locale.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/entities/comptabilite.dart';
import 'package:tatacora_flutter/features/synchronisation/data/aligneur_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart';

import '../comptabilite/support/outils_comptabilite.dart';

/// Le serveur est maître de la clôture (le statut d'un exercice descend) — SAUF
/// tant que la demande de clôture de CE poste n'est pas acceptée (26/10/2026) :
/// un exercice « ouvert » redescendu rouvrirait l'écriture dans un exercice
/// dont les pièces de clôture existent déjà ici.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late ComptabiliteDao dao;
  late ClotureExerciceLocale service;
  late String id2031;

  Future<IssueAlignement> descendre(int annee, String statut) => db.transaction(
    () =>
        AligneurCatalogue(
          db,
          DescenteCatalogueDao(db),
          auteur: () async => null,
        ).aligner(
          ElementCatalogue(
            table: TableDescendue.exercicesComptables,
            id: 'srv-$annee',
            actif: true,
            modifieLe: '2031-06-15 10:00:00',
            donnees: {
              'annee': annee,
              'date_debut': '$annee-01-01',
              'date_fin': '$annee-12-31',
              'statut': statut,
              'date_cloture': null,
            },
          ),
        ),
  );

  Future<StatutExercice> statut(int annee) async =>
      (await dao.exerciceDeLAnnee(annee))!.statut;

  Future<void> poserStatutDeLaDerniere(String code) => db.customStatement(
    'UPDATE operations_sync_local SET statut = ? WHERE seq = '
    '(SELECT MAX(seq) FROM operations_sync_local)',
    [code],
  );

  setUp(() async {
    db = await baseInstallee(maintenant: DateTime(2031, 6, 15));
    dao = ComptabiliteDao(db);
    final moteur = moteurSur(db);
    service = ClotureExerciceLocale(
      db,
      moteur,
      maintenant: () => DateTime(2031, 6, 15, 10),
    );
    id2031 = (await dao.exerciceDeLAnnee(2031))!.id;
    await dao.insererExercice(
      annee: 2030,
      dateDebut: '2030-01-01',
      dateFin: '2030-12-31',
    );
  });
  tearDown(() => db.close());

  test(
    'sans demande de clôture, le serveur reste maître : son statut descend',
    () async {
      expect(await descendre(2031, 'en_cloture'), isA<Aligne>());
      expect(await statut(2031), StatutExercice.enCloture);
    },
  );

  test('une demande EN FILE protège la clôture locale ; acceptée, le serveur '
      'reprend la main', () async {
    await service.demarrer(id2031, auteurId: auteurEssai);
    // Le serveur (qui n'a pas encore reçu la demande) redescend « ouvert ».
    final issue = await descendre(2031, 'ouvert');
    expect(issue, isA<ConserveLocalement>());
    expect(await statut(2031), StatutExercice.enCloture);

    // Une ANNÉE VOISINE n'est pas protégée par la demande de 2031.
    expect(await descendre(2030, 'en_cloture'), isA<Aligne>());
    expect(await statut(2030), StatutExercice.enCloture);

    // La demande est acceptée : le statut du serveur s'applique.
    await poserStatutDeLaDerniere('synchronise');
    expect(await descendre(2031, 'cloture'), isA<Aligne>());
    expect(await statut(2031), StatutExercice.cloture);
  });

  test('une demande REFUSÉE protège aussi (la clôture locale existe), jusqu’à '
      'ce qu’une demande ultérieure soit acceptée', () async {
    await service.demarrer(id2031, auteurId: auteurEssai);
    await poserStatutDeLaDerniere('rejete');
    expect(await descendre(2031, 'ouvert'), isA<ConserveLocalement>());
    expect(await statut(2031), StatutExercice.enCloture);

    // On RENVOIE (reprendre la saisie, puis redémarrer) : la dernière demande
    // de l'année décide.
    await service.reprendreSaisie(id2031, auteurId: auteurEssai);
    await poserStatutDeLaDerniere('synchronise');
    expect(await descendre(2031, 'ouvert'), isA<Aligne>());
    expect(await statut(2031), StatutExercice.ouvert);
  });

  test(
    'bloquée, en cours ou en conflit : la clôture locale tient aussi',
    () async {
      await service.demarrer(id2031, auteurId: auteurEssai);
      for (final code in ['en_attente', 'en_cours', 'bloque', 'conflit']) {
        await poserStatutDeLaDerniere(code);
        expect(
          await descendre(2031, 'ouvert'),
          isA<ConserveLocalement>(),
          reason: code,
        );
      }
      expect(await statut(2031), StatutExercice.enCloture);
    },
  );
}
