@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/etats/domain/apercu_etat.dart';
import 'package:tatacora_flutter/features/etats/domain/apercus_etats.dart';
import 'package:tatacora_flutter/features/etats/domain/registre_etats.dart';
import 'package:tatacora_flutter/features/etats/presentation/widgets/panneau_apercu_etat.dart';

import 'registre_serveur_etats.dart';

/// Le registre LOCAL des états confronté à sa SOURCE, le code PHP de M14.
///
/// Rien n'est recopié ici : code, module, libellé, période, indicateurs et
/// en-têtes sont lus dans `CatalogueEtatsService::REGISTRE` et dans les douze
/// classes `Etat*` par l'exécution de PHP (`tool/etats/exporter_registre.php`),
/// puis dans le relevé du navigateur (`reponse-serveur__etats.json`), une
/// seconde source indépendante. Chaque garde commence par prouver que ce
/// qu'elle balaie n'est pas vide (PA-136).
void main() {
  final serveur = ServeurEtats.charger();
  const locaux = EtatLocal.values;

  test(
    'le balayage n’est pas vide : 12 états, 76 en-têtes, 40 indicateurs',
    () {
      // Les comptes sont écrits pour que le test échoue si l'extraction PHP
      // rendait une liste vide ou tronquée.
      expect(serveur.etats.length, 12);
      expect(locaux.length, 12);
      expect(serveur.etats.fold<int>(0, (n, e) => n + e.entetes.length), 76);
      expect(
        serveur.etats.fold<int>(0, (n, e) => n + e.indicateurs.length),
        40,
      );
    },
  );

  test('mêmes codes, dans le même ordre : le registre est fermé', () {
    expect(
      [for (final e in locaux) e.code],
      [for (final e in serveur.etats) e.code],
    );
  });

  test(
    'un code inconnu est refusé, jamais remplacé par un état par défaut',
    () {
      expect(EtatLocal.depuisCode('inconnu'), isNull);
      expect(EtatLocal.depuisCode(''), isNull);
      expect(EtatLocal.depuisCode(null), isNull);
      // Chaque code du serveur est retrouvé tel quel.
      for (final s in serveur.etats) {
        expect(EtatLocal.depuisCode(s.code)?.code, s.code);
      }
    },
  );

  test('module source et libellé du catalogue identiques, état par état', () {
    for (final s in serveur.etats) {
      final l = EtatLocal.depuisCode(s.code)!;
      expect(l.module.code, s.module, reason: s.code);
      expect(l.libelle, s.libelle, reason: s.code);
    }
  });

  test('la phrase de période : le modèle du serveur, ou calculée', () {
    for (final s in serveur.etats) {
      final l = EtatLocal.depuisCode(s.code)!;
      // Deux états n'ont pas de phrase de langue : le tableau de bord écrit le
      // libellé de sa fenêtre (`Periode::libelle()`), la balance — refusée ici
      // — celui de son exercice. Le modèle local est alors `null`.
      if (l.periode == null) {
        expect(
          {'tableau-de-bord', 'balance'},
          contains(s.code),
          reason: '${s.code} devrait avoir une période',
        );
        continue;
      }
      expect(l.periode, s.periode, reason: s.code);
    }
  });

  test('les libellés des indicateurs, dans l’ordre du serveur', () {
    for (final s in serveur.etats) {
      expect(
        EtatLocal.depuisCode(s.code)!.indicateurs,
        s.indicateurs,
        reason: s.code,
      );
    }
  });

  test('les en-têtes de colonnes, dans l’ordre du serveur', () {
    for (final s in serveur.etats) {
      expect(EtatLocal.depuisCode(s.code)!.entetes, s.entetes, reason: s.code);
    }
  });

  test('le relevé du navigateur dit la même chose (seconde source)', () {
    final f = File(
      'tool/conformite_blade/structure/reponse-serveur__etats.json',
    );
    if (!f.existsSync()) fail('Relevé introuvable : ${f.path} (échec).');
    final releve =
        (jsonDecode(f.readAsStringSync()) as Map<String, dynamic>)['data']
            as List<dynamic>;

    expect(releve.length, 12);
    expect(
      [for (final e in locaux) (e.code, e.module.code, e.libelle)],
      [
        for (final x in releve)
          ((x as Map<String, dynamic>)['code'], x['module'], x['libelle']),
      ],
    );
  });

  test('« Sans tarif figé » est le seul indicateur conditionnel', () {
    // Le serveur n'ajoute cet indicateur que s'il y a des réservations sans
    // tarif : il est donc le 4ᵉ de la liste, que le local peut omettre.
    final r = serveur.etat('reservations');
    expect(r.indicateurs.length, 4);
    expect(r.indicateurs.last, 'Sans tarif figé');
    for (final s in serveur.etats.where((e) => e.code != 'reservations')) {
      expect(s.indicateurs, isNot(contains('Sans tarif figé')));
    }
  });

  group('Les phrases de l’écran (pwa.etats.*)', () {
    test('le décompte de l’accueil, au mot', () {
      final modele = serveur.pwaEtats['accueil_detail'] as String;
      expect(modele, contains(':total'));
      expect(decompteAccueilEtats(12), modele.replaceAll(':total', '12'));
      expect(decompteAccueilEtats(0), modele.replaceAll(':total', '0'));
    });

    test('le titre, l’invite, le compteur, l’état vide', () {
      expect(
        serveur.pwaEtats['accueil_titre'],
        'Choisissez un état dans le catalogue',
      );
      expect(serveur.pwaEtats['aucun'], 'Aucun état ne correspond.');
      expect(
        serveur.pwaEtats['aucune_ligne'],
        'Aucune ligne sur cette période.',
      );
      expect(
        serveur.pwaEtats['compteur'],
        ':nombre état(s) · droits portés par le module source',
      );
      expect(serveur.pwaEtats['module_source'], 'module source :module');
      expect(serveur.pwaEtats['lignes'], ':nombre ligne(s)');
    });
  });

  group('Les libellés propres à l’aperçu', () {
    test('les huit indicateurs du tableau de bord, clé par clé', () {
      var n = 0;
      for (final e in libellesIndicateursTableau.entries) {
        expect(
          e.value,
          serveur.langue('tableaux_de_bord.kpi.${e.key}'),
          reason: e.key,
        );
        n++;
      }
      expect(n, 8);
    });

    test('les colonnes du tableau de bord et le « non comparable »', () {
      final t = serveur.etat('tableau-de-bord');
      expect(t.entetes, [
        serveur.langue('tableaux_de_bord.col_indicateur'),
        serveur.langue('tableaux_de_bord.col_periode'),
        serveur.langue('tableaux_de_bord.col_precedent'),
        serveur.langue('tableaux_de_bord.col_variation'),
      ]);
      // Une variation inconnue s'écrit « — » au serveur, comme ici.
      expect(serveur.langue('tableaux_de_bord.non_comparable'), tiretApercu);
    });
  });
}
