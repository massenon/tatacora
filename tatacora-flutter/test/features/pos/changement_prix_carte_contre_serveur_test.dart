@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/pos/domain/changement_prix_carte.dart';

import '../comptabilite/support/outils_comptabilite.dart';

/// Ce qu'un changement de prix TRACE, CONFRONTÉ au serveur en l'exécutant
/// (piège 12) : `tool/carte/rejouer_historique_prix.php` fait tourner de vrais
/// `CarteBoisson` et `Plat` sous leurs vrais observateurs
/// (`CarteBoissonObserver`, `PlatObserver` -> `TraceurHistoriquePrix`), en
/// transaction annulée, et rend les traces écrites. La fonction pure du poste,
/// [changementsDePrix], doit produire les MÊMES.
void main() {
  // (nom, rayon, prix avant, prix après, marque avant, marque après)
  const scenarios = <(String, String, int, int, bool, bool)>[
    ('boisson : le prix monte', 'carte_boisson', 1000, 1200, false, false),
    ('boisson : le prix baisse', 'carte_boisson', 1500, 900, false, false),
    ('boisson : même prix', 'carte_boisson', 1000, 1000, false, false),
    ('plat : le prix seul', 'plat', 500, 700, false, false),
    ('plat : même prix, rien', 'plat', 500, 500, false, false),
    ('plat : prix ET marque posée', 'plat', 500, 700, false, true),
    ('plat : la marque seule', 'plat', 500, 500, false, true),
    ('plat : marque levée avec le prix', 'plat', 500, 600, true, false),
    ('plat : marque levée seule', 'plat', 500, 500, true, false),
    ('plat : marque gardée, prix change', 'plat', 500, 650, true, true),
    ('plat : tout est identique', 'plat', 500, 500, true, true),
    ('plat : grand montant', 'plat', 1, 99999999, false, false),
  ];

  late Map<String, dynamic> serveur;

  setUpAll(() async {
    serveur = await executerPhp(
      'rejouer_historique_prix.php',
      dossier: 'carte',
      entree: {
        'scenarios': [
          for (final (nom, source, avant, apres, ca, cb) in scenarios)
            {
              'nom': nom,
              'source': source,
              'prix_avant': avant,
              'prix_apres': apres,
              'corrige_avant': ca,
              'corrige_apres': cb,
            },
        ],
      },
    );
  });

  test(
    'le script a rendu tous les scénarios (l’extraction n’est pas vide)',
    () {
      expect(serveur.keys, [for (final s in scenarios) s.$1]);
      expect(
        serveur.values.any(
          (v) => ((v as Map<String, dynamic>)['traces'] as List).isNotEmpty,
        ),
        isTrue,
      );
    },
  );

  test('à la CRÉATION le serveur ne trace rien : l’observateur ne naît qu’à '
      'la modification', () {
    for (final v in serveur.values) {
      expect((v as Map<String, dynamic>)['a_la_creation'], 0);
    }
  });

  for (final (nom, source, avant, apres, ca, cb) in scenarios) {
    test('le poste trace comme le serveur — $nom', () {
      final attendu = [
        for (final t
            in (serveur[nom] as Map<String, dynamic>)['traces']
                as List<dynamic>)
          ChangementPrix(
            champ: (t as Map<String, dynamic>)['champ'] as String,
            ancien: t['ancien'] as String?,
            nouveau: t['nouveau'] as String?,
          ),
      ];

      // Une boisson du poste n'a pas la marque : `null` des deux côtés. Le
      // serveur, lui, la porte (faux, faux) — le résultat est le même.
      final poste = changementsDePrix(
        prixAvant: avant,
        prixApres: apres,
        corrigeAvant: source == 'plat' ? ca : null,
        corrigeApres: source == 'plat' ? cb : null,
      );

      expect(poste, attendu);
    });
  }

  test(
    'le registre des rayons et des champs est RELU du modèle du serveur',
    () {
      final source = File(
        '../tatacora-api/app/Domain/Carte/Models/HistoriquePrixCarte.php',
      ).readAsStringSync();
      String constante(String nom) =>
          RegExp("const $nom = '([a-z_]+)';").firstMatch(source)!.group(1)!;

      // Prouvé non vide : les quatre constantes existent.
      expect(constante('SOURCE_BOISSON'), SourceCarte.boisson.code);
      expect(constante('SOURCE_PLAT'), SourceCarte.plat.code);
      expect(constante('CHAMP_PRIX_VENTE'), champPrixVente);
      expect(constante('CHAMP_PRIX_CORRIGE_MAIN'), champPrixCorrigeMain);
      expect(champsDePrixTraces, [champPrixVente, champPrixCorrigeMain]);
    },
  );
}
