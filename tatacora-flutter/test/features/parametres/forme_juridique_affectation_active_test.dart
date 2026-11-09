import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/comptabilite/data/affectation_resultat_locale.dart';
import 'package:tatacora_flutter/features/comptabilite/data/cloture_exercice_locale.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/moteur_comptable.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_dao.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_depot_local.dart';
import 'package:tatacora_flutter/features/parametres/domain/enregistrer_parametres.dart';
import 'package:tatacora_flutter/features/parametres/domain/regles_parametres.dart';
import 'package:tatacora_flutter/features/parametres/domain/resultats_parametres.dart';

import '../comptabilite/support/outils_comptabilite.dart';

/// La forme juridique ne se change pas SOUS une affectation active (09/11/2026) : la garde
/// du serveur, lue ici sur la VRAIE comptabilité du poste (`existeUneActive`, pas un
/// stub) — l'affectation passée ici ou descendue du serveur. Le jugement contre le vrai
/// PHP est dans `reglages_facturation_contre_serveur_test.dart`.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test(
    'active tant qu’une affectation est passée, libre après sa '
    'contre-passation ; sans câblage du jugement, le changement est refusé',
    () async {
      final db = await baseInstallee(maintenant: DateTime(2031, 6, 15));
      addTearDown(db.close);
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
            LigneDemandee(
              compte: '5711',
              debitCentimes: 10000000,
              centreId: bar,
            ),
            LigneDemandee(
              compte: '7011',
              creditCentimes: 10000000,
              centreId: bar,
            ),
          ],
        ),
        auteurId: auteurEssai,
      );
      final id = (await dao.exerciceDeLAnnee(2030))!.id;
      await clotures.demarrer(id, auteurId: auteurEssai);
      await clotures.cloturer(id, auteurId: auteurEssai);

      final cas = EnregistrerParametres(
        ParametresDepotLocal(db),
        affectationActive: affectation.existeUneActive,
      );
      Future<ResultatEcriture> changer(String forme) => cas.executer(
        {'forme_juridique': forme},
        peutEcrire: true,
        auteurId: auteurEssai,
        estAdministrateur: true,
      );

      // Aucune affectation : la forme se change.
      expect(await affectation.existeUneActive(), isFalse);
      expect(await changer('sarl'), isA<EcritureAcceptee>());

      // Une affectation ACTIVE : la forme est gelée, avec la phrase du serveur.
      await affectation.affecter(
        id,
        ventilation: {'reserve_legale': 1000000, 'report_a_nouveau': 9000000},
        date: '2031-04-30',
        auteurId: auteurEssai,
      );
      expect(await affectation.existeUneActive(), isTrue);
      final refus = await changer('sa') as EcritureRefusee;
      expect(
        refus.motif,
        MessagesReglagesAdministrateur.formeAffectationActive,
      );
      expect((await ParametresDao(db).lireTout())['forme_juridique'], 'sarl');

      // La même valeur n'est pas un changement : acceptée même sous une affectation.
      expect(await changer('sarl'), isA<EcritureAcceptee>());

      // Contre-passée : la forme se libère.
      await affectation.contrepasser(
        id,
        auteurId: auteurEssai,
        motif: 'Ventilation à revoir en assemblée',
      );
      expect(await affectation.existeUneActive(), isFalse);
      expect(await changer('sa'), isA<EcritureAcceptee>());
      expect((await ParametresDao(db).lireTout())['forme_juridique'], 'sa');

      // Fermer par défaut : sans le jugement câblé, un changement est refusé.
      final sansJugement = EnregistrerParametres(ParametresDepotLocal(db));
      final r = await sansJugement.executer(
        {'forme_juridique': 'sarl'},
        peutEcrire: true,
        auteurId: auteurEssai,
        estAdministrateur: true,
      );
      expect(
        (r as EcritureRefusee).motif,
        MessagesReglagesAdministrateur.formeAffectationActive,
      );
    },
  );
}
