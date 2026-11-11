@Timeout(Duration(minutes: 3))
library;

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/transverse/data/comptes_utilisateurs_dao.dart';
import 'package:tatacora_flutter/features/transverse/domain/comptes_utilisateurs.dart';

import '../comptabilite/support/outils_comptabilite.dart';

/// La règle d'autorité de « Supprimer un compte » (03/11/2026) CONTRE le vrai
/// `SuppressionCompteService` du serveur.
///
/// `tool/transverse/rejouer_suppression_compte.php` rejoue chaque couple (auteur,
/// cible) sur une base d'essai ; le même couple passe par
/// `ComptesUtilisateursDao.supprimerCompte`. Ce qui se compare : le refus (la
/// PHRASE) ou la suppression, cas par cas — jamais une règle recopiée.
///
/// La base d'essai privée se donne par `TATACORA_BASE_ESSAI=tatacora_<nom>_test`.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const roles = ['super_admin', 'administrateur', 'gerant', 'barman'];

  // Tous les couples de rôles, plus « soi-même » pour chacun.
  final couples = <({String auteur, String cible, bool soi})>[
    for (final a in roles)
      for (final c in roles) (auteur: a, cible: c, soi: false),
    for (final a in roles) (auteur: a, cible: a, soi: true),
  ];

  late List<dynamic> serveur;

  /// Pour chaque couple : l'index, dans les résultats, de l'opération `supprimer`.
  final indexSupprimer = <int>[];

  setUpAll(() async {
    // Des comptes NEUFS par couple : un compte supprimé plus tôt devient
    // « introuvable » pour la suite, ce que le poste (une base neuve par couple)
    // ne reproduirait pas.
    final ops = <Map<String, Object?>>[
      {'op': 'libelles'},
    ];
    for (var i = 0; i < couples.length; i++) {
      final c = couples[i];
      ops.add({'op': 'compte', 'ref': 'a$i', 'role': c.auteur});
      if (!c.soi) ops.add({'op': 'compte', 'ref': 'c$i', 'role': c.cible});
      indexSupprimer.add(ops.length);
      ops.add({
        'op': 'supprimer',
        'auteur': 'a$i',
        'cible': c.soi ? 'a$i' : 'c$i',
      });
    }
    final reponse = await executerPhp(
      'rejouer_suppression_compte.php',
      dossier: 'transverse',
      entree: {'ops': ops},
    );
    serveur = reponse['resultats'] as List<dynamic>;
  });

  test('les phrases de refus du poste sont celles du serveur', () {
    final libelles = (serveur[0] as Map)['libelles'] as Map;
    expect(MessagesComptes.refusSuppressionDroit, libelles['droit']);
    expect(MessagesComptes.refusSuppressionSoiMeme, libelles['soi_meme']);
    expect(
      MessagesComptes.refusSuppressionAdministrateur,
      libelles['administrateur'],
    );
  });

  test('chaque couple (auteur, cible) : même refus, même suppression que le '
      'serveur', () async {
    var refuses = 0;
    var acceptes = 0;
    for (var i = 0; i < couples.length; i++) {
      final c = couples[i];
      final attendu = serveur[indexSupprimer[i]] as Map;

      final db = AppDatabase.enMemoire();
      final dao = ComptesUtilisateursDao(db);
      Future<void> poser(String id, String role) => db
          .into(db.utilisateursLocal)
          .insert(
            UtilisateursLocalCompanion.insert(
              id: id,
              login: id,
              nom: id,
              role: role,
              droitsJson: '{}',
              sel: 's',
              empreinte: 'e',
              iterations: 1,
              dateCreation: DateTime(2026, 10, 1),
              dateMotDePasse: DateTime(2026, 10, 1),
              actif: const Value(true),
            ),
          );
      await poser('auteur', c.auteur);
      if (!c.soi) await poser('cible', c.cible);

      String? refus;
      try {
        await dao.supprimerCompte(
          auteurId: 'auteur',
          compteId: c.soi ? 'auteur' : 'cible',
        );
      } on RefusComptes catch (e) {
        refus = e.message;
      }
      final supprime =
          (await (db.select(db.utilisateursLocal)
                    ..where((u) => u.id.equals(c.soi ? 'auteur' : 'cible')))
                  .getSingle())
              .supprimeLe !=
          null;
      await db.close();

      expect(
        (refus, supprime),
        (attendu['refus'], attendu['supprime']),
        reason: '${c.auteur} -> ${c.soi ? 'soi' : c.cible}',
      );
      if (refus == null) {
        acceptes++;
      } else {
        refuses++;
      }
    }
    // Le serveur a RÉELLEMENT accepté et RÉELLEMENT refusé : la comparaison compte.
    expect(acceptes, 2, reason: 'super_admin -> gerant, barman');
    expect(refuses, greaterThan(10));
  });
}
