@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/comptes_syscohada.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/plan_comptable_fichier.dart';

import 'support/outils_comptabilite.dart';

/// La table de correspondance rôle -> compte, CONFRONTÉE à `ComptesSyscohada.php`
/// par réflexion (PHP exécuté) — jamais deux listes qui divergent.
///
/// La table est « à valider par le comptable » au serveur ; la répliquer ne la
/// valide pas, elle garantit seulement que le poste ne dérive pas.
void main() {
  late Map<String, dynamic> serveur;
  late Set<String> plan;

  setUpAll(() async {
    serveur = await executerPhp('exporter_referentiel.php');
    plan = lirePlanComptable(lirePlanEmbarque()).map((c) => c.numero).toSet();
  });

  test('19 rôles relus de la classe du serveur — export non vide', () {
    expect(serveur['comptes'], hasLength(19));
    expect(ComptesSyscohada.tous, hasLength(19));
  });

  test(
    'chaque rôle porte le MÊME compte que le serveur, dans les deux sens',
    () {
      final distants = (serveur['comptes'] as Map<String, dynamic>)
          .cast<String, String>();
      expect(ComptesSyscohada.tous.keys.toSet(), distants.keys.toSet());
      for (final e in distants.entries) {
        expect(ComptesSyscohada.tous[e.key], e.value, reason: 'rôle ${e.key}');
      }
    },
  );

  test('les constantes Dart nommées sont celles de la table `tous`', () {
    // Les 19 constantes sont lues UNE à UNE : `tous` pourrait en omettre une
    // sans qu'aucun test précédent ne le voie.
    expect(ComptesSyscohada.tous.values.toSet(), {
      ComptesSyscohada.clients,
      ComptesSyscohada.fournisseurs,
      ComptesSyscohada.avancesClients,
      ComptesSyscohada.tvaFactureeBiens,
      ComptesSyscohada.tvaFactureePrestations,
      ComptesSyscohada.tvaRecuperableAchats,
      ComptesSyscohada.caisse,
      ComptesSyscohada.banque,
      ComptesSyscohada.mobileMoney,
      ComptesSyscohada.produitPrestations,
      ComptesSyscohada.produitMarchandises,
      ComptesSyscohada.produitLocations,
      ComptesSyscohada.achatsMarchandises,
      ComptesSyscohada.electricite,
      ComptesSyscohada.eau,
      ComptesSyscohada.locationMaterielTransport,
      ComptesSyscohada.telephoneInternet,
      ComptesSyscohada.resultatBenefice,
      ComptesSyscohada.resultatPerte,
    });
  });

  test(
    'centres, journaux, centres par défaut et natures : ceux du serveur',
    () {
      expect(
        ComptesSyscohada.centres,
        (serveur['centres'] as Map<String, dynamic>).cast<String, String>(),
      );
      expect(ComptesSyscohada.centres, hasLength(7));
      expect(
        ComptesSyscohada.journaux,
        (serveur['journaux'] as Map<String, dynamic>).cast<String, String>(),
      );
      expect(ComptesSyscohada.journaux, hasLength(5));
      expect(
        ComptesSyscohada.centreParDefaut,
        (serveur['centre_par_defaut'] as Map<String, dynamic>)
            .cast<String, String>(),
      );
      expect(ComptesSyscohada.centreParDefaut, hasLength(11));
      expect(ComptesSyscohada.natures, serveur['natures']);
    },
  );

  group('Aucun compte inventé', () {
    test('chaque compte de la table existe au plan embarqué', () {
      for (final e in ComptesSyscohada.tous.entries) {
        expect(plan, contains(e.value), reason: 'rôle ${e.key}');
      }
      for (final n in ComptesSyscohada.centreParDefaut.keys) {
        expect(plan, contains(n), reason: 'centre par défaut du compte $n');
      }
    });

    test('chaque centre par défaut désigne un des sept centres', () {
      for (final e in ComptesSyscohada.centreParDefaut.entries) {
        expect(
          ComptesSyscohada.centres.keys,
          contains(e.value),
          reason: 'compte ${e.key}',
        );
      }
    });

    test(
      'chaque compte de la table est IMPUTABLE (4 chiffres, ou feuille)',
      () {
        for (final e in ComptesSyscohada.tous.entries) {
          final n = e.value;
          final division =
              n.length < 4 &&
              plan.any((autre) => autre != n && autre.startsWith(n));
          expect(division, isFalse, reason: '${e.key} = $n est une division');
        }
      },
    );

    test('balayage de lib/ : aucun numéro de compte en dur hors du plan', () {
      final fichiers = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
          .toList();

      // Plancher : un dossier renommé rendrait le balayage vide, donc vert.
      expect(fichiers.length, greaterThan(300));

      final litteral = RegExp('[\'"]([1-9][0-9]{0,3})[\'"]');
      final trouves = <String>[];
      final fautifs = <String>[];

      for (final f in fichiers) {
        final chemin = f.path.replaceAll(r'\', '/');
        final dansComptabilite = chemin.contains('lib/features/comptabilite/');
        final lignes = f.readAsLinesSync();
        for (var i = 0; i < lignes.length; i++) {
          final l = lignes[i];
          // Hors du module : seuls comptent les littéraux d'une ligne qui parle
          // d'un compte (les `width="24"` des commentaires n'en sont pas).
          if (!dansComptabilite && !l.toLowerCase().contains('compte')) {
            continue;
          }
          if (l.trimLeft().startsWith('//')) continue;
          for (final m in litteral.allMatches(l)) {
            final n = m.group(1)!;
            trouves.add(n);
            if (!plan.contains(n)) fautifs.add('$chemin:${i + 1} -> $n');
          }
        }
      }

      // Non vide : le balayage a réellement vu les comptes du module — au
      // moins les 19 rôles et les 11 centres par défaut.
      expect(trouves.length, greaterThanOrEqualTo(29));
      expect(fautifs, isEmpty, reason: 'compte absent du plan : $fautifs');
    });
  });
}
