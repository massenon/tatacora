import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/features/achats/data/achats_api.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/archivage_fournisseur.dart';
import 'package:tatacora_flutter/features/achats/domain/messages_achats.dart';
import 'package:tatacora_flutter/features/achats/presentation/providers_achats.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_dao.dart';
import 'package:tatacora_flutter/features/parametres/domain/options_systeme.dart';
import 'package:tatacora_flutter/features/parametres/presentation/providers_options_systeme.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import 'support/outils_reglement.dart';

/// Les gardes de l'archivage qu'AUCUN écran ne peut jouer : la règle relue à
/// CHAQUE geste (la bascule peut se refermer entre l'ouverture de la
/// confirmation et le clic), le code du refus, et le défaut FERMÉ pendant que la
/// bascule n'est pas encore lue.
///
/// Trois mutations survivaient à la parité et aux écrans avant ce fichier :
/// `role: 'administrateur'` en dur dans le fournisseur d'API, `?? true` sur la
/// bascule en cours de lecture, et le code 422 à la place de 403.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final maintenant = DateTime(2026, 10, 13, 10);

  Future<(ProviderContainer, AppDatabase)> monter({
    required String role,
    String niveau = 'C',
    String? bascule,
    List<Override> enPlus = const [],
  }) async {
    final db = AppDatabase.enMemoire();
    addTearDown(db.close);
    await db.customStatement('SELECT 1');
    await semerAuteur(db);
    await ParametresDao(
      db,
      maintenant: () => maintenant,
    ).ecrire({OptionsSysteme.cleSuppression: bascule}, auteurId: null);
    final droits = GardeAcces.depuisJson({'M7': niveau});
    final c = ProviderContainer(
      overrides: [
        baseLocaleProvider.overrideWithValue(db),
        droitsProvider.overrideWithValue(droits),
        sessionProvider.overrideWithBuild(
          (ref, notifier) => Session(
            utilisateurId: auteurEssai,
            login: 'essai',
            nom: 'Essai',
            role: role,
            droits: droits,
          ),
        ),
        ...enPlus,
      ],
    );
    addTearDown(c.dispose);
    return (c, db);
  }

  /// Le refus d'un résultat, ou l'échec du test : jamais un cast muet.
  AchatsRefuse<T> refus<T>(ResultatAchats<T> r) {
    expect(r, isA<AchatsRefuse<T>>());
    return r as AchatsRefuse<T>;
  }

  group('Le refus de la bascule fermée', () {
    test(
      'est un 403 qui porte la phrase du serveur, aux deux gestes',
      () async {
        final (c, _) = await monter(role: 'achats');
        final api = c.read(achatsApiProvider);

        final ouverture = refus(await api.preparerArchivage(['f-1']));
        final execution = refus(await api.archiverFournisseurs(['f-1']));

        expect(ouverture.code, 403);
        expect(execution.code, 403);
        expect(ouverture.motif, MessagesAchats.refusBascule);
        expect(execution.motif, MessagesAchats.refusBascule);
      },
    );

    test(
      'sans le droit d’écrire : 403 aussi, avec LA phrase du droit',
      () async {
        final (c, _) = await monter(role: 'administrateur', niveau: 'L');
        final r = refus(
          await c.read(achatsApiProvider).preparerArchivage(['f-1']),
        );
        expect(r.code, 403);
        expect(r.motif, MessagesAchats.droitEcritureRefuse);
      },
    );
  });

  group('La règle est relue à CHAQUE geste, pas figée à l’ouverture', () {
    test('la bascule se referme entre l’ouverture et le clic : rien n’est '
        'archivé, le rôle de la SESSION décide', () async {
      final (c, db) = await monter(role: 'achats', bascule: 'true');
      await semerCommande(db, statut: 'cloturee');
      final api = c.read(achatsApiProvider);

      final ouverture = await api.preparerArchivage(['f-1']);
      expect(
        ouverture,
        isA<AchatsRecu<LotArchivage>>(),
        reason: 'bascule ouverte',
      );

      await ParametresDao(
        db,
        maintenant: () => maintenant,
      ).ecrire({OptionsSysteme.cleSuppression: 'false'}, auteurId: null);

      final execution = refus(await api.archiverFournisseurs(['f-1']));
      expect(execution.motif, MessagesAchats.refusBascule);
      expect(
        (await db.select(db.fournisseursLocal).getSingle()).actif,
        isTrue,
        reason: 'le fournisseur est resté actif',
      );
    });

    test('un administrateur archive bascule fermée (le rôle vient de la '
        'session)', () async {
      final (c, db) = await monter(role: 'administrateur', bascule: 'false');
      await semerCommande(db, statut: 'cloturee');
      final r = await c.read(achatsApiProvider).archiverFournisseurs(['f-1']);
      expect(r, isA<AchatsRecu<ResultatArchivage>>());
      expect(
        (await db.select(db.fournisseursLocal).getSingle()).actif,
        isFalse,
      );
    });
  });

  group('Tant que la bascule n’est pas lue, la porte reste FERMÉE', () {
    test('lecture en cours : un acheteur ne peut pas archiver', () async {
      final attente = Completer<bool>();
      final (c, _) = await monter(
        role: 'achats',
        enPlus: [
          suppressionActiveProvider.overrideWith((ref) => attente.future),
        ],
      );
      // Le fournisseur est autoDispose : on l'écoute pour qu'il reste vivant.
      final ecoute = c.listen(
        peutArchiverProvider(ModuleTatacora.m7Achats),
        (_, _) {},
      );
      addTearDown(ecoute.close);
      expect(ecoute.read(), isFalse);
      attente.complete(true);
    });

    test('lecture en erreur : fermée aussi', () async {
      final (c, _) = await monter(
        role: 'achats',
        enPlus: [
          suppressionActiveProvider.overrideWith(
            (ref) => Future<bool>.error(StateError('base illisible')),
          ),
        ],
      );
      final ecoute = c.listen(
        peutArchiverProvider(ModuleTatacora.m7Achats),
        (_, _) {},
      );
      addTearDown(ecoute.close);
      await Future<void>.delayed(Duration.zero);
      expect(ecoute.read(), isFalse);
    });

    test('lue ouverte : un acheteur peut archiver', () async {
      final (c, _) = await monter(role: 'achats', bascule: 'true');
      await c.read(suppressionActiveProvider.future);
      expect(c.read(peutArchiverProvider(ModuleTatacora.m7Achats)), isTrue);
    });
  });
}
