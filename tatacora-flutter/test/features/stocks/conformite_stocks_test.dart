import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';

import '../../support/vue_blade.dart';

/// Les gardes de conformité des saisies de M6.
///
/// ⚠ **PRÉMISSE PÉRIMÉE depuis le 09/10/2026 (D129 a, source locale de M6).**
/// Ce fichier confronte ce que le client SOUMET aux `FormRequest` du serveur :
/// or le poste ne soumet plus rien à aucun serveur, `SaisieArticle.versJson` et
/// `SaisieMouvement.versJson` n'ont plus d'appelant en production, et
/// `EnregistrerArticleRequest::CHAMPS_CALCULES` interdit même `stock_initial`
/// que l'écran écrit désormais comme une ENTRÉE locale. Les cas restent verts
/// parce qu'ils éprouvent encore les listes fermées de la vue (types
/// saisissables, catégories, unités) ; ils ne prouvent PLUS qu'une route
/// accepterait la saisie. Ne pas s'y fier pour ce second point.
///
///
/// ## Elles relisent des SOURCES EXTÉRIEURES, jamais des constantes recopiées
///
/// Deux sources, et aucune n'appartient à ce dépôt Flutter :
///
/// - la **vue Blade** de la PWA, `pwa/stocks/stocks.blade.php`, et sa classe
///   `app/Pwa/Livewire/Stocks/Stocks.php`, pour les libellés et les listes
///   offertes à la saisie — le maître du client Flutter depuis PA-182/PA-183
///   (`prototype_v2/` est une ancienne version) ;
/// - les ***FormRequest* du serveur*, `tatacora-api/app/Domain/Stocks/Http/
///   Requests/`, pour ce que l'API accepte et refuse réellement.
///
/// Un test qui figerait `'stock_initial'` dans une liste écrite ici ne
/// vérifierait que lui-même, et resterait vert le jour où le serveur changerait
/// (piège 12 : un prédicat dérivé du champ qu'il vérifie ne vérifie rien).
///
/// ## Elles ÉCHOUENT si la source manque, elles ne sautent pas
///
/// Et chaque extraction vérifie qu'elle a **réellement trouvé quelque chose** :
/// une expression régulière qui ne correspond plus rendrait une liste vide,
/// donc un test vert qui n'a rien regardé — c'est exactement le défaut que ce
/// dépôt a rencontré deux fois (piège 4).
void main() {
  /// La vue Blade, ses libellés résolus — voir [VueBlade.resolue] —, ses
  /// COMMENTAIRES Blade retirés : ils citent souvent les mots de l'ancien
  /// prototype, et un libellé qui n'existe qu'en commentaire n'est pas affiché.
  String vue() => _normaliser(
    VueBlade.resolue(
      'stocks/stocks',
    ).replaceAll(RegExp(r'\{\{--[\s\S]*?--\}\}'), ' '),
  );

  /// La classe Livewire qui pilote la vue : c'est elle qui ferme les listes.
  String classe() => VueBlade.fichier(
    'app/Pwa/Livewire/Stocks/Stocks.php',
    role: 'la classe Livewire de l’écran Stocks',
  );

  String requeteServeur(String fichier) {
    final f = File(
      '${VueBlade.racine}/app/Domain/Stocks/Http/Requests/$fichier',
    );
    if (!f.existsSync()) {
      fail(
        'La règle de validation du serveur est introuvable : ${f.path}. '
        'Ce test confronte ce que le client envoie à ce que l’API accepte ; '
        'sans elle il ne vérifierait plus rien.',
      );
    }
    return f.readAsStringSync();
  }

  /// Les chaînes d'un `const NOM = [...]` PHP.
  ///
  /// L'extraction est **prouvée non vide** par l'appelant : sans ce contrôle,
  /// un renommage de la constante rendrait une liste vide, et toutes les
  /// assertions qui en dépendent passeraient à vide.
  List<String> constantePhp(String source, String nom) {
    final debut = source.indexOf('const $nom');
    if (debut < 0) {
      fail(
        'La constante $nom a disparu de la source du serveur. '
        'Ce test ne peut plus rien confronter : vérifiez si la règle a été '
        'renommée ou supprimée, ce qui changerait ce que l’API accepte.',
      );
    }
    final ouvrante = source.indexOf('[', debut);
    final fermante = source.indexOf('];', ouvrante);
    if (ouvrante < 0 || fermante < 0) {
      fail(
        'La constante $nom n’a plus la forme attendue (const $nom = [...]).',
      );
    }

    return RegExp("'([^']+)'")
        .allMatches(source.substring(ouvrante, fermante))
        .map((m) => m.group(1)!)
        .toList();
  }

  /* ================================================================== */
  group('Ce que le serveur REFUSE, le client ne le soumet pas', () {
    test('aucun champ calculé n’entre dans la création d’un article', () {
      // PA-24 : `stock`, `stock_initial`, `stock_disponible`,
      // `quantite_stock`, `cout_moyen_pondere` et `valeur_stock` sont
      // INTERDITS, pas ignorés. Un champ ignoré laisserait le magasinier croire
      // qu'il a compté, et l'écart ne se verrait qu'à l'inventaire suivant.
      final interdits = constantePhp(
        requeteServeur('EnregistrerArticleRequest.php'),
        'CHAMPS_CALCULES',
      );

      expect(
        interdits,
        isNotEmpty,
        reason:
            'aucun champ calculé n’a été extrait : le balayage est vide, donc '
            'vert, et il ne protège plus rien',
      );
      expect(interdits, contains('stock_initial'));
      expect(interdits, contains('cout_moyen_pondere'));

      const saisie = SaisieArticle(
        id: 'a-1',
        libelle: 'Riz local (sac 50 kg)',
        categorie: 'Denrées',
        uniteMesure: 'sac',
        seuilAlerte: '4',
      );

      for (final modification in const [false, true]) {
        final corps = saisie.versJson(modification: modification);
        for (final champ in interdits) {
          expect(
            corps.containsKey(champ),
            isFalse,
            reason:
                '« $champ » est une valeur CALCULÉE depuis les mouvements de '
                'stock. Le soumettre serait refusé en 422 par le serveur, et '
                'le proposer à la saisie ferait croire qu’un stock se déclare.',
          );
        }
      }
    });

    test('aucun champ calculé n’entre dans un mouvement', () {
      final interdits = constantePhp(
        requeteServeur('EnregistrerMouvementRequest.php'),
        'CHAMPS_CALCULES',
      );

      expect(interdits, isNotEmpty);

      const saisie = SaisieMouvement(
        articleId: 'a-1',
        pointId: 'p-1',
        type: TypeMouvement.entree,
        quantite: '10',
        motif: 'Réception SODIS Bénin',
        coutUnitaire: '32000',
      );

      final corps = saisie.versJson();
      for (final champ in interdits) {
        expect(corps.containsKey(champ), isFalse, reason: '« $champ »');
      }
    });

    test(
      'le registre SAISISSABLE est celui du serveur — sans `inventaire`',
      () {
        // Lire et écrire n'ont pas le même registre : on consulte les
        // régularisations d'inventaire, on ne les saisit pas. Les confondre
        // ouvrirait la réécriture libre de n'importe quel solde, sans qu'aucun
        // comptage n'ait eu lieu — l'inventaire deviendrait inopposable.
        final serveur = constantePhp(
          requeteServeur('EnregistrerMouvementRequest.php'),
          'TYPES_SAISISSABLES',
        );
        final consultables = constantePhp(
          requeteServeur('FiltrerMouvementsRequest.php'),
          'TYPES_CONSULTABLES',
        );

        expect(serveur, isNotEmpty);
        expect(consultables, isNotEmpty);

        expect(
          TypeMouvement.saisissables.map((t) => t.code).toList(),
          serveur,
          reason:
              'le formulaire offrirait un type que le serveur refuse, ou en '
              'cacherait un qu’il accepte',
        );
        expect(
          TypeMouvement.values.map((t) => t.code).toSet(),
          consultables.toSet(),
          reason: 'le journal masquerait une partie de l’historique',
        );
        expect(TypeMouvement.inventaire.saisissable, isFalse);
      },
    );

    test('l’identifiant n’est envoyé qu’à la CRÉATION', () {
      // `EnregistrerArticleRequest` pose `prohibited` sur `id` en modification :
      // l'identifiant d'un article ne se modifie pas. L'envoyer quand même
      // ferait refuser en 422 une modification par ailleurs valide.
      const saisie = SaisieArticle(
        id: 'a-1',
        libelle: 'x',
        categorie: null,
        uniteMesure: 'kg',
        seuilAlerte: '0',
      );

      expect(saisie.versJson(modification: false)['id'], 'a-1');
      expect(saisie.versJson(modification: true).containsKey('id'), isFalse);
    });
  });

  /* ================================================================== */
  group('Les libellés viennent de la vue Blade', () {
    test('les trois types de mouvement sont écrits comme elle', () {
      final source = vue();

      for (final type in TypeMouvement.saisissables) {
        expect(
          source,
          contains(_normaliser(type.libelleSaisie!)),
          reason:
              'le libellé « ${type.libelleSaisie} » ne se trouve pas dans '
              'pwa/stocks/stocks.blade.php : un texte reformulé est un écart',
        );
      }
    });

    test('les catégories et les unités sont celles de la PWA', () {
      // La classe `Stocks` ferme les deux listes (`CATEGORIES`, `UNITES`).
      // `articles.categorie` est pourtant une chaîne libre au schéma : sans
      // liste fermée, « Boissons » et « boisson » cohabiteraient et le filtre
      // de l'écran les compterait comme deux catégories.
      final source = classe();
      final categories = constantePhp(source, 'CATEGORIES');
      final unites = constantePhp(source, 'UNITES');

      expect(
        categories,
        isNotEmpty,
        reason: 'CATEGORIES a disparu de la PWA : le test ne mesure plus rien',
      );
      expect(unites, isNotEmpty);

      expect(categoriesMaitre, categories);
      expect(unitesMaitre, unites);
    });

    test('les mots de la confirmation de rupture sont ceux de la vue', () {
      // RG-06 : « Stock insuffisant », « Forcer la sortie », et la phrase qui
      // dit ce que le forçage produit. C'est le seul endroit de l'application
      // où l'on autorise sciemment un stock négatif ; les mots comptent.
      final source = vue();

      expect(source, contains('Stock insuffisant'));
      expect(source, contains('Forcer la sortie'));
      expect(
        source,
        contains(
          _normaliser(
            'Forcer la sortie créera un stock négatif, tracé comme '
            '« rupture forcée » dans la fiche de stock.',
          ),
        ),
      );
    });

    test('« + Nouvel article » et « Créer l’article » sont dans la vue', () {
      final source = vue();

      expect(source, contains('+ Nouvel article'));
      expect(source, contains('Le stock se constitue par mouvements'));
      expect(source, contains("Créer l'article"));
    });
  });
}

/// Apostrophes typographiques ramenées à l'apostrophe droite, suites
/// d'espaces réduites : une phrase coupée sur deux lignes de la vue doit se
/// retrouver telle quelle.
String _normaliser(String texte) => texte
    .replaceAll('’', "'")
    .replaceAll(r"\'", "'")
    .replaceAll(RegExp(r'\s+'), ' ');
