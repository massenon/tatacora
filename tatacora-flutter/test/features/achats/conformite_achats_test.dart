import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/achats/data/achats_api.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/bon_reception.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/commande_achat.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/fournisseur.dart';
import 'package:tatacora_flutter/features/achats/presentation/widgets/composants_crud_achats.dart';

import '../../support/vue_blade.dart';

/// Les gardes de conformité de M7.
///
/// ## Elles relisent des SOURCES EXTÉRIEURES, jamais des constantes recopiées
///
/// Trois sources, et **aucune n'appartient à ce dépôt Flutter** :
///
/// - les deux **vues Blade** de la PWA — le maître du client Flutter depuis
///   PA-182/PA-183, `prototype_v2/` étant une ancienne version —,
///   `pwa/achats/approvisionnement.blade.php` et `pwa/achats/achats.blade.php`,
///   avec leurs classes Livewire (`app/Pwa/Livewire/Achats/`), pour les
///   libellés et les listes fermées ;
/// - les ***FormRequest* et les *Service* du serveur**,
///   `tatacora-api/app/Domain/Achats/`, pour ce que l'API accepte et refuse
///   réellement ;
/// - le **fichier de langue** du serveur, `tatacora-api/lang/fr/achats.php`,
///   pour le message par lequel ce client reconnaît le refus de RG-10.
///
/// Un test qui figerait `'montant_estime'` dans une liste écrite ici ne
/// vérifierait que lui-même, et resterait vert le jour où le serveur
/// changerait (piège 12 : un prédicat dérivé du champ qu'il vérifie ne vérifie
/// rien).
///
/// ## Elles ÉCHOUENT si la source manque, elles ne sautent pas
///
/// Et chaque extraction vérifie qu'elle a **réellement trouvé quelque chose** :
/// une expression régulière qui ne correspond plus rendrait une liste vide,
/// donc un test vert qui n'a rien regardé — le défaut que ce dépôt a rencontré
/// deux fois (piège 4).
///
/// ## Prémisse périmée le 09/10/2026 (D143 a) : le corps HTTP n'existe plus
///
/// M7 est LOCAL : plus aucune requête ne part, et `SaisieFournisseur.versJson`,
/// `SaisieCommande.versJson` et `SaisieReception.versJson` n'ont plus
/// d'appelant. Les gardes « ce que le serveur REFUSE, le client ne le
/// soumet pas » vérifient donc un corps qui ne part nulle part ; elles restent
/// vertes et conservées (les registres fermés et les libellés, eux, gardent
/// tout leur sens), et le bon endroit des règles est désormais
/// `calcul_achats_contre_serveur_test.dart`. Même cas que
/// `conformite_stocks_test.dart` (D129 a).
///
/// ## Le contrôle des libellés est à DEUX FACES
///
/// Chaque phrase est cherchée dans le maître **et** dans le code source des
/// écrans. Ne la chercher que dans le maître laisserait passer un texte
/// reformulé côté Flutter ; ne la chercher que dans le code Dart ne vérifierait
/// que lui-même. Les deux ensemble mordent des deux côtés.
void main() {
  /* ================================================================== */
  /* Lecture des sources extérieures                                     */
  /* ================================================================== */

  String fichier(String chemin, String pourquoi) {
    final f = File(chemin);
    if (!f.existsSync()) {
      fail(
        'Source introuvable : ${f.path}. $pourquoi Sans elle, ce test ne '
        'vérifierait plus rien — et il resterait vert.',
      );
    }
    return f.readAsStringSync();
  }

  /// La vue Blade d'un écran ET la classe Livewire qui la pilote, libellés
  /// résolus : les libellés de statut de la PWA vivent dans la classe
  /// (`Achats::STATUTS`), pas dans le gabarit.
  ///
  /// Les COMMENTAIRES Blade sont retirés : ils citent souvent les mots de
  /// l'ancien prototype, et un libellé qui n'existe qu'en commentaire n'est
  /// pas affiché.
  String ecranBlade(String vue, String classe) =>
      '${VueBlade.resolue(vue).replaceAll(RegExp(r'\{\{--[\s\S]*?--\}\}'), ' ')}\n'
      '${VueBlade.resoudre(VueBlade.fichier('app/Pwa/Livewire/Achats/$classe', role: 'la classe Livewire de l’écran'))}';

  // La vue de l'approvisionnement lit ses libellés de statut dans
  // `Achats::STATUTS` (`@foreach (Achats::STATUTS …)`) : le registre de la
  // classe voisine fait donc partie de ce que cet écran affiche.
  String maitreApprovisionnement() =>
      '${ecranBlade('achats/approvisionnement', 'Approvisionnement.php')}\n'
      '${VueBlade.fichier('app/Pwa/Livewire/Achats/Achats.php')}';

  String maitreAchats() => ecranBlade('achats/achats', 'Achats.php');

  String serveur(String relatif) => fichier(
    '${VueBlade.racine}/app/Domain/Achats/$relatif',
    'C’est la règle que l’API applique réellement.',
  );

  /// Les chaînes d'un `const NOM = [...]` PHP.
  List<String> constantePhp(String source, String nom) {
    final debut = source.indexOf('const $nom');
    if (debut < 0) {
      fail(
        'La constante $nom a disparu de la source du serveur. Ce test ne peut '
        'plus rien confronter : vérifiez si la règle a été renommée ou '
        'supprimée, ce qui changerait ce que l’API accepte.',
      );
    }
    final ouvrante = source.indexOf('[', debut);
    final fermante = source.indexOf('];', ouvrante);
    if (ouvrante < 0 || fermante < 0) {
      fail(
        'La constante $nom n’a plus la forme attendue (const $nom = [...]).',
      );
    }

    return RegExp("'([a-z_]+)'")
        .allMatches(source.substring(ouvrante, fermante))
        .map((m) => m.group(1)!)
        .toList();
  }

  /// La valeur d'un `const NOM = '...';` PHP — une chaîne, pas une liste.
  String scalairePhp(String source, String nom) {
    final motif = RegExp("const $nom = '([^']+)'");
    final trouve = motif.firstMatch(source);
    if (trouve == null) {
      fail(
        'La constante scalaire $nom a disparu de la source du serveur. Ce '
        'client s’en sert pour reconnaître un refus : sans elle, il rangerait '
        'ce refus avec les erreurs de saisie.',
      );
    }
    return trouve.group(1)!;
  }

  /// Le code source de TOUS les fichiers Dart de M7, normalisé.
  ///
  /// Les littéraux adjacents sont **recollés** (`'abc '\n  'def'` → `'abc def'`)
  /// et les suites d'espaces réduites à un seul : sans cela, une phrase du
  /// maître coupée en trois lignes de Dart ne serait jamais retrouvée, et le
  /// balayage passerait à vide.
  String codeDart() {
    final racine = Directory('lib/features/achats');
    if (!racine.existsSync()) {
      fail(
        'Le dossier lib/features/achats a disparu : ce test ne mesure rien.',
      );
    }

    final fichiers = racine
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    // Plancher : un dossier renommé rendrait le balayage vide, donc vert —
    // c'est exactement le défaut que cette famille de gardes protège.
    expect(
      fichiers.length,
      greaterThanOrEqualTo(12),
      reason:
          'seuls ${fichiers.length} fichiers Dart de M7 ont été relus : le '
          'balayage ne couvre plus la fonctionnalité',
    );

    final tout = fichiers.map((f) => f.readAsStringSync()).join('\n');
    return _normaliser(tout.replaceAll(RegExp(r"'\s*\n\s*'"), ''));
  }

  /* ================================================================== */
  group('Ce que le serveur REFUSE, le client ne le soumet pas', () {
    test('aucun champ calculé n’entre dans une commande d’achat', () {
      // PA-24 : `montant_total`, `montant_estime`, `montant_regle`,
      // `reste_du` et `nombre_lignes` sont INTERDITS, pas ignorés. Le maître
      // porte pourtant « Montant estimé (FCFA) » en champ de saisie : un total
      // saisi ne bougerait plus quand une ligne change, et il se lit
      // exactement comme un total juste.
      final interdits = constantePhp(
        serveur('Http/Requests/CreerCommandeAchatRequest.php'),
        'CHAMPS_CALCULES',
      );

      expect(
        interdits,
        isNotEmpty,
        reason:
            'aucun champ calculé n’a été extrait : le balayage est vide, donc '
            'vert, et il ne protège plus rien',
      );
      expect(interdits, contains('montant_estime'));
      expect(interdits, contains('montant_total'));

      final corps = SaisieCommande(
        fournisseurId: 'f-1',
        dateCommande: '2026-08-26',
        statut: StatutCommande.brouillon,
        lignes: const [
          LigneSaisieCommande(
            articleId: 'a-1',
            libelle: 'Riz local (sac 50 kg)',
            uniteMesure: 'sac',
            quantite: '10',
            prixUnitaire: '29000',
          ),
        ],
      ).versJson();

      final ligne = (corps['lignes'] as List).first as Map<String, dynamic>;

      for (final champ in interdits) {
        expect(
          corps.containsKey(champ),
          isFalse,
          reason:
              '« $champ » est CALCULÉ depuis les lignes de la commande. Le '
              'soumettre serait refusé en 422, et le proposer à la saisie '
              'ferait croire qu’un montant de commande se déclare.',
        );
        expect(ligne.containsKey(champ), isFalse, reason: 'ligne : « $champ »');
      }

      // `id` est `prohibited` : `commandes_achat` n'est pas au registre
      // synchronisable et aucun mécanisme de rejeu n'existe. En envoyer un
      // laisserait croire à une idempotence qui n'a pas lieu.
      expect(corps.containsKey('id'), isFalse);
      expect(corps.containsKey('utilisateur_id'), isFalse);
    });

    test('aucun champ calculé n’entre dans un fournisseur', () {
      final interdits = constantePhp(
        serveur('Http/Requests/EnregistrerFournisseurRequest.php'),
        'CHAMPS_CALCULES',
      );

      expect(interdits, isNotEmpty);
      // Ceux-là n'ont même AUCUNE table : ni facture ni règlement fournisseur
      // n'existent au schéma (PA-21).
      expect(interdits, contains('encours'));
      expect(interdits, contains('total_du'));

      const saisie = SaisieFournisseur(
        id: 'f-1',
        raisonSociale: 'Grand Marché Natitingou SARL',
        contact: '01 90 12 34 56',
        categorie: 'Denrées alimentaires',
        conditionsPaiement: 'Comptant',
        evaluationCode: 'excellent',
      );

      for (final modification in const [false, true]) {
        final corps = saisie.versJson(modification: modification);
        for (final champ in interdits) {
          expect(corps.containsKey(champ), isFalse, reason: '« $champ »');
        }
      }
    });

    test('l’identifiant d’un fournisseur n’est envoyé qu’à la CRÉATION', () {
      // `EnregistrerFournisseurRequest` pose `prohibited` sur `id` en
      // modification : l'identifiant ne se modifie pas. L'envoyer quand même
      // ferait refuser en 422 une modification par ailleurs valide.
      final source = serveur('Http/Requests/EnregistrerFournisseurRequest.php');
      expect(
        source,
        contains("? ['prohibited']"),
        reason:
            'la règle `prohibited` sur `id` en modification a disparu du '
            'serveur : ce cas ne décrit plus rien',
      );

      const saisie = SaisieFournisseur(
        id: 'f-1',
        raisonSociale: 'x',
        contact: null,
        categorie: null,
        conditionsPaiement: null,
        evaluationCode: null,
      );

      expect(saisie.versJson(modification: false)['id'], 'f-1');
      expect(saisie.versJson(modification: true).containsKey('id'), isFalse);
    });

    test('aucun champ calculé n’entre dans une réception', () {
      final interdits = constantePhp(
        serveur('Http/Requests/EnregistrerReceptionRequest.php'),
        'CHAMPS_CALCULES',
      );

      expect(interdits, isNotEmpty);
      // Le verdict RG-10 : l'accepter en entrée permettrait de déclarer
      // « totale » une livraison amputée de moitié, et la créance sur le
      // fournisseur serait perdue sans que rien ne le signale.
      expect(interdits, contains('conformite'));
      expect(interdits, contains('tolerance_pct'));

      final corps = const SaisieReception(
        commandeId: 'c-1',
        pointStockageId: 'p-1',
        dateReception: null,
        lignes: [
          LigneSaisieReception(
            articleId: 'a-1',
            libelle: 'Riz local',
            uniteMesure: 'sac',
            quantiteCommandee: '10.00',
            quantiteDejaRecue: '0.00',
            quantiteRecue: '10',
          ),
        ],
      ).versJson();

      for (final champ in interdits) {
        expect(corps.containsKey(champ), isFalse, reason: '« $champ »');
      }
      expect(corps.containsKey('id'), isFalse);
      expect(corps.containsKey('utilisateur_id'), isFalse);
    });
  });

  /* ================================================================== */
  group('Les registres fermés sont ceux du SERVEUR', () {
    test('les cinq statuts filtrables sont ceux de l’enum du schéma', () {
      final serveurStatuts = constantePhp(
        serveur('Models/CommandeAchat.php'),
        'STATUTS',
      );

      expect(serveurStatuts, isNotEmpty);
      expect(
        StatutCommande.values.map((s) => s.code).toList(),
        serveurStatuts,
        reason:
            'le filtre offrirait un statut que le serveur refuse en 422, ou en '
            'cacherait un — et la liste entière s’afficherait sous un intitulé '
            'qui promet le contraire',
      );
    });

    test('SEULS deux statuts sont saisissables, et ce sont les siens', () {
      // Deux registres, pas un : on filtre un état constaté, on ne le pose pas.
      // Les confondre permettrait d'afficher une commande « Reçue » dont
      // aucune marchandise n'est entrée en stock (PA-59/60/61).
      final saisissables = constantePhp(
        serveur('Services/CommandeAchatService.php'),
        'STATUTS_SAISISSABLES',
      );

      expect(saisissables, isNotEmpty);
      expect(saisissables, hasLength(lessThan(StatutCommande.values.length)));
      expect(
        StatutCommande.saisissables.map((s) => s.code).toList(),
        saisissables,
      );

      // Et la réciproque : les trois autres sont nommés à l'écran, pas
      // silencieusement retirés du formulaire.
      expect(StatutCommande.refusesALaCreation, hasLength(3));
      for (final s in StatutCommande.refusesALaCreation) {
        expect(saisissables, isNot(contains(s.code)));
      }
    });

    test(
      'les trois conformités sont celles de l’enum, pas les deux du maître',
      () {
        final conformites = constantePhp(
          serveur('Models/BonReception.php'),
          'CONFORMITES',
        );

        expect(conformites, isNotEmpty);
        expect(
          ConformiteReception.values.map((c) => c.code).toList(),
          conformites,
          reason:
              'recevoir moins que commandé ouvre une créance sur le fournisseur ; '
              'recevoir un article hors commande est une anomalie d’une tout '
              'autre nature — les grouper perdrait l’information qui compte',
        );

        // Et « avec écart » regroupe les deux qui ne sont pas `totale`.
        expect(ConformiteReception.totale.avecEcart, isFalse);
        expect(ConformiteReception.partielle.avecEcart, isTrue);
        expect(ConformiteReception.nonConforme.avecEcart, isTrue);
      },
    );

    test('les quatre évaluations sont celles de l’enum du schéma', () {
      final evaluations = constantePhp(
        serveur('Models/Fournisseur.php'),
        'EVALUATIONS',
      );

      expect(evaluations, isNotEmpty);
      expect(
        EvaluationFournisseur.values.map((e) => e.code).toList(),
        evaluations,
      );

      // `null` n'est PAS « À revoir » : il veut dire « pas encore évalué », et
      // les confondre reprocherait à un fournisseur neuf une mauvaise note que
      // personne ne lui a donnée.
      expect(EvaluationFournisseur.depuisCode(null), isNull);
      const neuf = Fournisseur(
        id: 'f',
        raisonSociale: 'x',
        contact: null,
        categorie: null,
        conditionsPaiement: null,
        evaluationCode: null,
        actif: true,
      );
      expect(neuf.libelleEvaluation, 'Non évaluée');
      expect(
        neuf.libelleEvaluation,
        isNot(EvaluationFournisseur.aRevoir.libelle),
      );
      expect(neuf.estEvalue, isFalse);
    });

    test('un code inconnu ne retombe sur AUCUN cas plausible', () {
      // Une valeur ajoutée à un enum demain ne doit pas hériter du
      // comportement du premier cas par omission : l'écran affiche le code
      // brut, ce qui se voit, plutôt qu'un libellé faux, qui ne se voit pas.
      expect(StatutCommande.depuisCode('annulee'), isNull);
      expect(ConformiteReception.depuisCode('douteuse'), isNull);
      expect(EvaluationFournisseur.depuisCode('excellentissime'), isNull);
    });
  });

  /* ================================================================== */
  group('Le refus de RG-10 est reconnu par la clé du SERVEUR', () {
    test('la clé de tolérance du client est celle de ReceptionService', () {
      // C'est la seule chose qui distingue « la tolérance n'est pas
      // configurée » d'une erreur de saisie : les deux valent 422. Une clé
      // renommée au serveur ferait retomber ce refus dans les refus
      // ordinaires, et l'écran renverrait le magasinier corriger des quantités
      // parfaitement justes.
      final cle = scalairePhp(
        serveur('Services/ReceptionService.php'),
        'CLE_TOLERANCE',
      );

      expect(cle, isNotEmpty);
      expect(AchatsApi.cleTolerance, cle);
    });

    test('le message de langue du serveur PORTE bien cette clé', () {
      // La reconnaissance se fait sur le texte du message : si le fichier de
      // langue cessait de l'interpoler, le client ne reconnaîtrait plus rien.
      final langue = fichier(
        '${VueBlade.racine}/lang/fr/achats.php',
        'C’est le message que ce client reconnaît pour distinguer le refus de '
            'RG-10 d’une erreur de saisie.',
      );

      final ligne = RegExp(
        r"'tolerance_absente' => (.*?)\n\s*\.\s*(.*?),\n",
        dotAll: true,
      ).firstMatch(langue);

      expect(
        ligne,
        isNotNull,
        reason:
            'le message `tolerance_absente` a disparu du fichier de langue : '
            'ce test ne mesure plus rien',
      );
      expect(
        ligne!.group(0),
        contains(AchatsApi.cleTolerance),
        reason:
            'le message ne nomme plus la clé de tolérance : le client ne peut '
            'plus distinguer ce refus d’une erreur de saisie',
      );
    });
  });

  /* ================================================================== */
  group('Les libellés viennent de la vue Blade — et le code Dart les porte', () {
    /// Chaque phrase est cherchée des DEUX côtés : dans la vue Blade (elle
    /// existe vraiment) et dans le code Dart (elle a été portée sans
    /// reformulation).
    void deuxFaces(String maitre, String dart, Iterable<String> phrases) {
      // Brut PLUS sans balises : les invites vivent dans des attributs
      // (`placeholder`), qu'un simple retrait des balises effacerait.
      final m = _normaliser(
        '$maitre\n${maitre.replaceAll(RegExp(r'<[^>]*>'), '')}',
      );
      for (final phrase in phrases) {
        final attendue = _normaliser(phrase);
        expect(
          m,
          contains(attendue),
          reason:
              '« $phrase » ne se trouve PLUS dans la vue Blade : cette garde '
              'ne mesure plus rien, vérifiez si la PWA a changé',
        );
        expect(
          dart,
          contains(attendue),
          reason:
              '« $phrase » est dans la vue Blade mais absente du code Dart de '
              'M7 : un texte reformulé est un écart',
        );
      }
    }

    test('l’écran Approvisionnement reprend les mots de sa vue', () {
      deuxFaces(maitreApprovisionnement(), codeDart(), const [
        'Approvisionnement',
        // Les quatre onglets (l.36-39), y compris celui qui n'a aucune donnée.
        'Besoins',
        'Commandes',
        'Réceptions',
        'Dettes fournisseurs',
        // Les cinq indicateurs (l.96-100), y compris les deux sans chiffre.
        'Articles sous seuil',
        'Commandes en attente',
        'Réceptions partielles',
        'Fournisseurs à payer',
        'Total dû',
        // Les listes et leurs textes vides.
        'Articles à réapprovisionner',
        'Aucun article sous son seuil. Rien à commander.',
        'Bons de commande',
        'Aucune commande. Passez par l’onglet Besoins.',
        'Bons de réception',
        'Aucune réception enregistrée.',
        'Dettes fournisseurs',
        // Les sous-titres de liste. Celui des besoins est fait de DEUX clés
        // rendues côte à côte (`besoins_detail`, `besoins_portee`, l.158) —
        // PA-185 : la phrase de l'ancien prototype sur le suivi journalier,
        // que la vue ne porte plus, est retirée.
        "Stock calculé ≤ seuil d'alerte. Le compteur « Articles sous seuil » "
            'porte sur TOUT le référentiel, jamais sur les seules lignes '
            'affichées : la recherche masque des lignes, elle ne réduit pas '
            "ce qu'il y a à commander.",
        // Le sous-titre de l'onglet Réceptions n'est PLUS attendu ici : la vue
        // affirme un recalcul du coût moyen pondéré que le serveur exécuté ne
        // fait pas (D266). Écart nommé, testé à part ci-dessous (D276).
        // La barre d'outils et ses deux exports.
        'Export Excel',
        'Export PDF',
        'Article, point de stockage…',
        'Fournisseur, n° de commande…',
        'Commander la sélection',
        // « Toutes les réceptions » n'est PLUS attendu (PA-185, 11/09/2026) :
        // la vue n'a aucun filtre sur l'onglet Réceptions, et le filtre du
        // client est retiré. Le libellé ne survit côté Flutter que comme
        // PORTÉE d'export, toujours vraie sans filtre.
        // Les modales.
        'Nouveau bon de commande',
        'Créer le bon de commande',
        'Valider la réception',
        'Point de stockage',
        'Commandé',
        'Déjà reçu',
        'Reçu maintenant',
        // Les libellés de statut — le registre `Achats::STATUTS`, commun aux
        // deux vues (PA-185).
        'Réceptionnée partiellement',
        'Clôturée',
      ]);
    });

    test('D276 — trois phrases FAUSSES de la vue sont remplacées par la vraie, '
        'et l’écart est nommé', () {
      final vue = _normaliser(maitreApprovisionnement());
      // Le code RENDU : les lignes de commentaire sont retirées. Les écarts
      // nommés citent la phrase fausse de la vue, par définition ; seul le code
      // qui l'afficherait compte.
      //
      // R-G (D285) : TOUT `lib/`, plus le seul module des achats. La même
      // affirmation fausse posée ailleurs — le stock, le tableau de bord, un
      // état — serait le même mensonge sur de l'argent, et la garde ne le
      // voyait pas.
      final fichiersDart = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      // Balayage non vide, et qui dépasse réellement M7.
      expect(
        fichiersDart.where(
          (f) => !f.path.replaceAll(r'\', '/').contains('features/achats/'),
        ),
        hasLength(greaterThan(300)),
      );
      final dartNormalise = _normaliser(
        fichiersDart
            .map(
              (f) => f
                  .readAsLinesSync()
                  .where((l) => !l.trimLeft().startsWith('//'))
                  .join('\n'),
            )
            .join('\n')
            // Les littéraux adjacents sont recollés, quelle que soit la quote.
            .replaceAll(RegExp(r'''(?:'|")\s*[\r\n]+\s*(?:'|")'''), ''),
      );

      // 1. La vue porte bien les deux phrases fausses (sinon cet écart n'a plus
      //    d'objet : la vue a été corrigée, il faut le retirer).
      final fausseSousTitre = _normaliser(
        'Chaque réception a généré une entrée de stock valorisée au prix de '
        'la commande, qui a recalculé le coût moyen pondéré de l’article.',
      );
      final fausseAide = _normaliser(
        'met à jour le coût moyen pondéré au prix de cette commande',
      );
      // La phrase du sous-titre et celle de l'aide sont des clés de langue :
      // la vue ne porte que la clé, le texte est dans le fichier de langue.
      final langue = _normaliser(
        fichier(
          '${VueBlade.racine}/lang/fr/achats_pwa.php',
          'C’est le texte que la PWA affiche réellement.',
        ),
      );
      expect(
        vue.contains(fausseSousTitre) || langue.contains(fausseSousTitre),
        isTrue,
        reason:
            'la vue ne porte plus la phrase fausse du sous-titre : '
            'retirer l’écart D276',
      );
      expect(
        vue.contains(fausseAide) || langue.contains(fausseAide),
        isTrue,
        reason:
            'la vue ne porte plus la phrase fausse de l’aide : '
            'retirer l’écart D276',
      );
      expect(
        langue,
        contains(_normaliser('ni aucun coût moyen pondéré mis à jour')),
        reason: 'le serveur a changé `prix_obligatoire` : retirer l’écart D276',
      );

      // 2. Aucune des trois affirmations fausses n'est rendue par le poste,
      //    ni en ligne de code ni en phrase.
      for (final fausse in [
        'valorisée au prix de la commande',
        'recalculé le coût moyen pondéré',
        'met à jour le coût moyen pondéré au prix',
        'ni aucun coût moyen pondéré mis à jour',
        'stock et coût moyen pondéré mis à jour',
      ]) {
        expect(
          dartNormalise.contains(_normaliser(fausse)),
          isFalse,
          reason:
              '« $fausse » est une affirmation FAUSSE sur de l’argent : '
              'le poste ne doit pas l’afficher',
        );
      }

      // 3. La phrase VRAIE est celle du poste.
      for (final vraie in [
        'Chaque réception a généré une entrée de stock, non valorisée : le '
            "coût moyen pondéré de l'article n'est pas recalculé à la "
            'réception.',
        "La réception génère l'entrée de stock ; le coût moyen pondéré "
            "n'est pas recalculé à la réception.",
        'Le prix unitaire est obligatoire et strictement positif : sans lui '
            'aucun montant de commande ne peut être calculé.',
      ]) {
        expect(
          dartNormalise,
          contains(_normaliser(vraie)),
          reason: 'la phrase vraie a disparu : $vraie',
        );
      }
    });

    test('l’écran Fournisseurs reprend les mots de SA vue', () {
      deuxFaces(maitreAchats(), codeDart(), const [
        'Fournisseurs & Achats',
        'Fournisseurs',
        'Commandes d’achat',
        'Rechercher un fournisseur...',
        'Toutes les évaluations',
        // Les colonnes (l.85-125).
        'Contact',
        'Catégorie fournie',
        'Conditions',
        'Évaluation',
        // Les champs du formulaire (l.133-184).
        'Raison sociale',
        'Contact (téléphone)',
        'Conditions de paiement',
        'Ex. Grand Marché Natitingou SARL',
        // Les quatre évaluations.
        'Excellent',
        'Bon',
        'Moyen',
        'À revoir',
        // Les libellés de statut — le même registre que l'écran
        // Approvisionnement (`Achats::STATUTS`, PA-185).
        'Réceptionnée partiellement',
        'Brouillon',
        // Les contrôles de la page (09/10/2026), des deux onglets.
        'Ajouter fournisseur',
        "Ajouter commande d'achat",
        'Rechercher une commande (fournisseur)...',
        'Voir le détail',
        'Restaurer',
        'Archivé',
        'Aucun résultat',
        'Essayez de modifier votre recherche ou vos filtres.',
        'Date de commande',
        'Montant estimé',
        'Tout sélectionner',
        'Sélectionner cette ligne',
        // Les titres d'export, passés au partiel partagé par la vue. Le texte
        // de l'archivage, lui, vit dans le COMPOSANT `modale-archivage`, que
        // `VueBlade.resolue` ne déplie pas : il est confronté par le
        // comparateur (`t-blade-flutter.js`, bloc `modale-archivage`).
        "Exporter — Commandes d'achat",
        'Exporter — Fournisseurs',
      ]);
    });

    test('les lignes par page du client sont celles de la vue', () {
      // `Achats::PAR_PAGE` règle le décompte « Affichage de 26-50 sur 60 » : une
      // constante recopiée ici ne vérifierait qu'elle-même.
      final classe = VueBlade.fichier(
        'app/Pwa/Livewire/Achats/Achats.php',
        role: 'la classe Livewire de l’écran Fournisseurs',
      );
      final m = RegExp(r'const PAR_PAGE = (\d+);').firstMatch(classe);
      if (m == null) fail('`Achats::PAR_PAGE` a disparu : rien à confronter.');

      expect(int.parse(m.group(1)!), 25);
      expect(parPageAchats, int.parse(m.group(1)!));
    });

    test('les listes fermées de la PWA sont celles du formulaire', () {
      // `fournisseurs.categorie` et `conditions_paiement` sont des chaînes
      // LIBRES au schéma : la liste ne vient donc que de l'écran — la classe
      // `Achats` de la PWA la ferme (`CATEGORIES`, `CONDITIONS_PAIEMENT`), et
      // le formulaire y ajoute la valeur déjà portée par la fiche.
      final classe = VueBlade.fichier(
        'app/Pwa/Livewire/Achats/Achats.php',
        role: 'la classe Livewire de l’écran Fournisseurs',
      );
      List<String> liste(String nom) {
        final m = RegExp('const $nom = \\[(.*?)\\];').firstMatch(classe);
        if (m == null) fail('`Achats::$nom` a disparu : rien à confronter.');
        return RegExp(
          "'([^']+)'",
        ).allMatches(m.group(1)!).map((c) => c.group(1)!).toList();
      }

      final categories = liste('CATEGORIES');
      final conditions = liste('CONDITIONS_PAIEMENT');

      expect(categories, isNotEmpty);
      expect(conditions, isNotEmpty);
      expect(categoriesFournisseurMaitre, categories);
      expect(conditionsPaiementMaitre, conditions);
    });

    test('les DEUX vues lisent le MÊME registre de statuts', () {
      // PA-185 : l'ancien prototype nommait différemment le même statut sur
      // ses deux pages (« Reçue partiellement » / « Réceptionnée
      // partiellement ») ; la PWA ne l'a jamais repris. Ses deux vues rendent
      // `Achats::STATUTS` (`approvisionnement.blade.php` l.146 et l.252) : le
      // client n'a donc plus qu'UN jeu de libellés, ce registre, au mot près.
      final appro = VueBlade.brute('achats/approvisionnement');
      final achats = VueBlade.brute('achats/achats');
      expect(appro, contains('Achats::STATUTS'));
      expect(achats, contains('STATUTS'));

      final classe = VueBlade.fichier(
        'app/Pwa/Livewire/Achats/Achats.php',
        role: 'le registre des statuts, commun aux deux vues',
      );
      // Le bloc `STATUTS` SEUL : la classe porte d'autres tableaux de même
      // forme (`EVALUATIONS`), qui gonfleraient le registre.
      final bloc = RegExp(
        r'const STATUTS = \[(.*?)\];',
        dotAll: true,
      ).firstMatch(classe);
      if (bloc == null) {
        fail('`Achats::STATUTS` a disparu : rien à confronter.');
      }
      final registre = {
        for (final m in RegExp(
          r"'([a-z_]+)' => \['libelle' => '([^']+)'",
        ).allMatches(bloc.group(1)!))
          m.group(1)!: m.group(2)!,
      };

      // La garde de la garde : un registre vide rendrait la boucle muette.
      expect(registre.length, StatutCommande.values.length);
      for (final s in StatutCommande.values) {
        expect(registre[s.code], s.libelle, reason: 'Statut `${s.code}`');
      }
      expect(_normaliser(appro), isNot(contains('Reçue')));
    });
  });
}

/// Apostrophes typographiques ramenées à l'apostrophe droite, échappements
/// JavaScript défaits, suites d'espaces et de sauts de ligne réduites à un
/// espace.
///
/// Sans cette normalisation, une phrase coupée sur trois lignes de HTML ne
/// serait jamais retrouvée dans une chaîne Dart, et **toutes** les assertions
/// de libellé passeraient à vide — le défaut que ces gardes existent pour
/// empêcher.
String _normaliser(String texte) => texte
    .replaceAll('’', "'")
    .replaceAll(r"\'", "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
