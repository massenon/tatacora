import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/navigation/navigation_tatacora.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/mode_reglement.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';
import 'package:tatacora_flutter/features/ventes/domain/entities/vente.dart';
import 'package:tatacora_flutter/features/ventes/impression/etat_journal_ventes.dart';

import '../../support/vue_blade.dart';

/// Les gardes de conformité du journal des ventes.
///
/// ## Elles relisent des SOURCES EXTÉRIEURES, jamais des constantes recopiées
///
/// Quatre sources, et **aucune n'appartient à ce dossier Flutter** :
///
///  - la **vue Blade**, `pwa/pos/historique-ventes.blade.php`, et sa classe
///    `app/Pwa/Livewire/Pos/HistoriqueVentes.php`, pour les libellés et les
///    colonnes — le maître du client Flutter depuis PA-182/PA-183
///    (`prototype_v2/` est une ancienne version) ;
///  - le **service de vente** du serveur, `app/Domain/Ventes/Services/
///    VenteService.php`, pour le registre des modes de règlement, celui des
///    activités encaissables et la règle « une note de chambre n'est pas un
///    encaissement » ;
///  - la **barre latérale** de la PWA, `app/Pwa/Support/MenuLateral.php`, pour
///    l'entrée qui distingue ce journal du registre des factures ;
///  - le **serveur**, `tatacora-api/…/SynchronisationService.php`, pour le
///    registre des tables synchronisables : c'est lui qui rend vraie la phrase
///    « enregistré sur ce poste ».
///
/// Un test qui figerait `'note_chambre'` dans une liste écrite ici ne
/// vérifierait que lui-même, et resterait vert le jour où la PWA ou le serveur
/// changerait (piège n° 12 : un prédicat dérivé du champ qu'il vérifie ne
/// vérifie rien).
///
/// ## Elles ÉCHOUENT si la source manque, elles ne sautent pas
///
/// Et chaque extraction vérifie qu'elle a **réellement trouvé quelque chose** :
/// une expression régulière qui ne correspond plus rendrait une liste vide,
/// donc un test vert qui n'a rien regardé — le défaut que ce dépôt a rencontré
/// deux fois (piège n° 4).
void main() {
  /* ================================================================== */
  /* Lecture des sources extérieures                                     */
  /* ================================================================== */

  /// La vue Blade, libellés résolus et COMMENTAIRES Blade retirés (ils citent
  /// les mots de l'ancien prototype, qu'aucun écran n'affiche), plus sa classe
  /// Livewire (les libellés qu'elle compose) — voir [VueBlade.resolue].
  String maitre() =>
      '${VueBlade.resolue('pos/historique-ventes').replaceAll(RegExp(r'\{\{--[\s\S]*?--\}\}'), ' ')}\n'
      '${VueBlade.resoudre(VueBlade.fichier('app/Pwa/Livewire/Pos/HistoriqueVentes.php', role: 'la classe Livewire du journal'))}';

  String venteService() => VueBlade.fichier(
    'app/Domain/Ventes/Services/VenteService.php',
    role: 'le service qui définit ce qu’est une vente et comment elle se règle',
  );

  String menuLateral() => VueBlade.fichier(
    'app/Pwa/Support/MenuLateral.php',
    role: 'la barre latérale de la PWA',
  );

  String serveurSync() => VueBlade.fichier(
    // Depuis le lot S1 du serveur (15/10/2026), le registre vit dans
    // `RegistreSynchronisation`, sous le même nom de constante.
    'app/Shared/Sync/Services/RegistreSynchronisation.php',
    role: 'le registre qui décide ce qui remonte au serveur',
  );

  /// Le code source de TOUS les fichiers Dart du journal, normalisé.
  ///
  /// Les littéraux adjacents sont **recollés** (`'abc '\n  'def'` → `'abc def'`)
  /// et les suites d'espaces réduites à un seul : sans cela, une phrase de la
  /// vue coupée en trois lignes de Dart ne serait jamais retrouvée, et le
  /// balayage passerait à vide.
  String codeDart() {
    final racine = Directory('lib/features/ventes');
    if (!racine.existsSync()) {
      fail(
        'Le dossier lib/features/ventes a disparu : ce test ne mesure rien.',
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
      greaterThanOrEqualTo(6),
      reason:
          'seuls ${fichiers.length} fichiers Dart du journal ont été relus : '
          'le balayage ne couvre plus la fonctionnalité',
    );

    final tout = fichiers.map((f) => f.readAsStringSync()).join('\n');

    // Les COMMENTAIRES sont retirés avant toute comparaison, et c'est ce qui
    // rend ces gardes mordantes dans les deux sens : une phrase de la vue doit
    // se trouver dans une chaîne réellement affichée, pas dans un docblock qui
    // la cite ; et une phrase interdite — « en attente de synchronisation » —
    // reste écrivable en commentaire pour expliquer POURQUOI elle est
    // interdite, sans faire rougir le balayage qui l'interdit.
    final sansCommentaires = tout
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ')
        .replaceAll(RegExp(r'//[^\n]*'), ' ');

    return _normaliser(sansCommentaires.replaceAll(RegExp(r"'\s*\n\s*'"), ''));
  }

  /// Les clés d'un `const NOM = [ 'cle' => … ]` PHP.
  List<String> clesPhp(String source, String nom) {
    final debut = source.indexOf('const $nom = [');
    if (debut < 0) {
      fail(
        'La constante `$nom` a disparu de la source : ce test ne peut plus rien '
        'confronter.',
      );
    }
    final bloc = source.substring(debut, source.indexOf('];', debut));
    return RegExp(
      r"'([A-Za-z0-9_]+)' =>",
    ).allMatches(bloc).map((m) => m.group(1)!).toList();
  }

  /// Les en-têtes de chaque `<thead>` de la vue, dans l'ordre, avec leur
  /// alignement (`text-right` = colonne numérique, alignée à droite).
  List<List<(String, bool)>> entetesDesTableaux() {
    final source = maitre();
    return RegExp(r'<thead[\s\S]*?</thead>')
        .allMatches(source)
        .map(
          (t) => RegExp(r'<th([^>]*)>([\s\S]*?)</th>')
              .allMatches(t.group(0)!)
              .map(
                (c) => (
                  _normaliser(c.group(2)!.replaceAll(RegExp(r'<[^>]*>'), '')),
                  c.group(1)!.contains('text-right'),
                ),
              )
              .toList(),
        )
        .toList();
  }

  /* ================================================================== */
  group('Ce journal N’EST PAS le registre des factures', () {
    test('la vue le dit encore, et c’est ce qui fonde ce lot', () {
      // Si ce sous-titre disparaissait de la vue, tout ce lot perdrait sa
      // raison d'être — et personne ne s'en apercevrait sans ce cas.
      final source = _texteVisible(maitre());

      expect(
        source,
        contains(_normaliser('Historique des ventes')),
        reason: 'le titre a disparu de la vue',
      );
      expect(source, contains(_normaliser('pas des factures')));
      expect(
        source,
        contains(_normaliser('Une vente peut exister sans facture')),
      );

      // Et la barre latérale de la PWA porte l'entrée ET son badge.
      final menu = menuLateral();
      expect(menu, contains("'nom' => 'Historique des ventes'"));
      expect(
        RegExp(
          r"'nom' => 'Historique des ventes'[^\]]*'badge' => 'Journal'",
        ).hasMatch(menu),
        isTrue,
        reason: 'le badge « Journal » de l’entrée a disparu de la PWA',
      );
    });

    test('l’entrée de menu porte le libellé, le badge ET une route', () {
      // Un écran livré sans entrée de menu n'existe que pour qui connaît son
      // URL — c'est-à-dire pour personne, au comptoir (PA-133).
      final entree = toutesLesDestinations.firstWhere(
        (d) => d.nom == 'Historique des ventes',
      );

      expect(entree.page, 'historique-ventes.html');
      expect(entree.badge, 'Journal');
      expect(entree.route, isNotNull);
      expect(
        entree.route,
        isNot('/facturation'),
        reason:
            'le journal et le registre sont deux écrans, pas deux vues du même',
      );
    });
  });

  /* ================================================================== */
  group('Les registres fermés sont ceux du SERVEUR', () {
    test('les modes de règlement sont ceux de `VenteService`', () {
      final codes = clesPhp(venteService(), 'MODES_PAIEMENT');

      expect(
        codes,
        isNotEmpty,
        reason:
            'aucun mode n’a été extrait : le balayage est vide, donc vert, et '
            'il ne protège plus rien',
      );
      expect(
        ModeReglement.values.map((m) => m.code).toList(),
        codes,
        reason:
            'un code divergent rendrait les ventes des deux canaux '
            'incomparables, et le filtre offrirait un règlement qu’aucune '
            'vente ne porte',
      );
    });

    test('⚠ « note_chambre » est le SEUL mode non encaissé — la règle du '
        'serveur', () {
      // `VenteService::CONTREPARTIES_TRESORERIE` : un mode encaissé débite une
      // trésorerie ; `note_chambre` en est absent — il crédite le compte
      // client. Recopier cette règle sur chaque appelant ferait qu'un mode
      // ajouté demain serait compté comme encaissé par OMISSION.
      final source = venteService();
      final tous = clesPhp(source, 'MODES_PAIEMENT').toSet();
      final encaisses = clesPhp(source, 'CONTREPARTIES_TRESORERIE').toSet();

      expect(
        encaisses,
        isNotEmpty,
        reason:
            'la règle « une note de chambre n’est pas un encaissement » a '
            'disparu du serveur : ce cas ne décrit plus rien',
      );

      final nonEncaisses = ModeReglement.values
          .where((m) => !m.encaisse)
          .map((m) => m.code)
          .toList();

      expect(nonEncaisses, tous.difference(encaisses).toList());
      expect(nonEncaisses, ['note_chambre']);
    });

    test('les deux statuts filtrables sont ceux des `option` de la vue', () {
      final valeurs = RegExp(
        r'<option value="(validee|annulee)">([^<]+)<',
      ).allMatches(maitre()).toList();

      expect(valeurs, hasLength(2), reason: 'les options du filtre ont changé');
      expect(
        StatutVente.values.map((s) => s.code).toList(),
        valeurs.map((m) => m.group(1)).toList(),
      );
      expect(
        StatutVente.values.map((s) => s.libelleFiltre).toList(),
        valeurs.map((m) => m.group(2)!.trim()).toList(),
      );
    });

    test(
      '⚠ le registre d’activités du client est PLUS LARGE que celui qu’encaisse '
      'le serveur',
      () {
        // `VenteService::MODULES_ENCAISSABLES` ne connaît que M4 et M5 : le
        // serveur n'encaisse au comptoir que du bar et du restaurant. Le panier
        // de ce client accepte en plus M8 et M9 (règle 4 : bar, restaurant,
        // tourisme et location tiennent dans la même addition). Le filtre suit
        // le registre du CLIENT.
        final modules = RegExp(r"'(M[0-9]+)'")
            .allMatches(
              venteService().substring(
                venteService().indexOf('const MODULES_ENCAISSABLES'),
                venteService().indexOf(
                  ';',
                  venteService().indexOf('const MODULES_ENCAISSABLES'),
                ),
              ),
            )
            .map((m) => m.group(1)!)
            .toSet();

        expect(modules, isNotEmpty);
        final duClient = ModuleVendable.values.map((m) => m.code).toSet();

        expect(
          modules.difference(duClient),
          isEmpty,
          reason:
              'le serveur encaisse une activité que ce client ne sait pas '
              'porter : une vente s’afficherait sans activité',
        );
        expect(
          duClient.difference(modules),
          isNotEmpty,
          reason:
              'l’élargissement est délibéré et documenté ; s’il disparaissait, '
              'c’est que `ModuleVendable` aurait rétréci',
        );

        // ⚠ Et M1 n'est offert NULLE PART : la nuitée est engagée à la
        // réservation, pas encaissée au comptoir.
        expect(duClient, isNot(contains('M1')));
        expect(modules, isNot(contains('M1')));
      },
    );

    test(
      '⚠ le libellé de M8 diverge de la PWA, et il n’y a QU’UN registre',
      () {
        // La PWA écrit « Véhicules » (`VenteService::MODULES`) ; le client dit
        // « Location » depuis `ModuleVendable`, qui sert déjà au point de vente
        // et à la facturation. Ajouter ici une seconde table de libellés
        // donnerait deux listes à tenir — et c'est la seconde qui divergerait,
        // celle que personne ne relit.
        expect(venteService(), contains("'M8' => 'Véhicules'"));
        expect(ModuleVendable.m8Vehicules.libelle, 'Location');
        expect(
          codeDart(),
          isNot(contains('Véhicules')),
          reason:
              'un second registre de libellés est apparu dans le journal : '
              'les deux finiront par diverger',
        );
      },
    );
  });

  /* ================================================================== */
  group('Les colonnes d’export sont celles de la vue', () {
    test('les huit en-têtes du journal imprimé et les cinq du ticket', () {
      final tableaux = entetesDesTableaux();

      expect(
        tableaux,
        isNotEmpty,
        reason: 'aucun en-tête de tableau n’a été extrait de la vue',
      );

      // La vue en pose plusieurs : l'écran (8 colonnes, dont « Actions »),
      // le JOURNAL IMPRIMÉ (8 colonnes, dont « Encaisse »), le détail des
      // lignes (6) et le TICKET d'une vente, dans la modale de détail (5).
      final encaisse = _normaliser(
        VueBlade.libelle('pos_pwa.document.entete_encaisse')!,
      );
      final journal = tableaux.firstWhere(
        (t) => t.length == 8 && t.any((c) => c.$1 == encaisse),
      );
      final vente = tableaux.firstWhere((t) => t.length == 5);

      expect(EtatJournalVentes.entetes, journal.map((c) => c.$1).toList());
      expect(EtatVente.entetes, vente.map((c) => c.$1).toList());
    });

    test('les colonnes numériques sont celles que la vue aligne à droite', () {
      final tableaux = entetesDesTableaux();
      final encaisse = _normaliser(
        VueBlade.libelle('pos_pwa.document.entete_encaisse')!,
      );

      Set<int> aDroite(List<(String, bool)> t) => {
        for (var i = 0; i < t.length; i++)
          if (t[i].$2) i,
      };

      final journal = tableaux.firstWhere(
        (t) => t.length == 8 && t.any((c) => c.$1 == encaisse),
      );
      final vente = tableaux.firstWhere((t) => t.length == 5);

      expect(aDroite(journal), isNotEmpty);
      expect(EtatJournalVentes.colonnesNumeriques, aDroite(journal));
      expect(EtatVente.colonnesNumeriques, aDroite(vente));
    });

    test('le journal imprimé porte le titre de l’en-tête d’impression', () {
      // L'en-tête d'impression de la vue (l.71) et le PDF serveur
      // `pdf/ventes-rapport` disent tous deux « JOURNAL DES VENTES » ; le
      // PDF Flutter disait « Historique des ventes », le titre de l'ÉCRAN
      // (PA-195). Le document suit le document, l'écran suit l'écran.
      final titre = VueBlade.libelle('pos_pwa.document.journal_titre');
      expect(titre, isNotNull);
      expect(
        VueBlade.brute('pos/historique-ventes'),
        contains('pos_pwa.document.journal_titre'),
      );
      expect(EtatJournalVentes.titre, titre);
    });
  });

  /* ================================================================== */
  group('Les libellés viennent de la vue — et le code Dart les porte', () {
    /// Chaque phrase est cherchée des DEUX côtés : dans la vue (elle existe
    /// vraiment) et dans le code Dart (elle a été portée sans reformulation).
    void deuxFaces(Iterable<String> phrases) {
      final m = _texteVisible(maitre());
      final dart = codeDart();

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
              '« $phrase » est dans la vue Blade mais absente du code Dart du '
              'journal : un texte reformulé est un écart',
        );
      }
    }

    test('l’écran reprend les mots de sa vue', () {
      deuxFaces(const [
        'Historique des ventes',
        // Le sous-titre, qui porte la règle de tout l'écran.
        'Le journal des ventes, pas des factures.',
        'Une vente peut exister sans facture',
        'une vente annulée reste une vente',
        'là où une facture annulée produit un avoir',
        'V-2026-00016',
        'F-2026-00042',
        // Les cinq indicateurs et leurs détails.
        'Ventes',
        'Chiffre d’affaires',
        'Encaissé',
        'Porté en note',
        'Sans impact stock',
        'Ventes validées',
        'Réellement dans le tiroir',
        'Créance client, réglée au départ',
        // Les quatre listes de filtre.
        'Tous les postes',
        'Toutes les activités',
        'Tous les règlements',
        'Tous les statuts',
        'Validées',
        'Annulées',
        // Les huit colonnes.
        'Date',
        'Poste',
        'Activités',
        'Règlement',
        'Montant',
        'Statut',
        'Actions',
        // Les pastilles et le vide.
        'annulée',
        'encaissée',
        'en note',
        'Aucune vente ne correspond à ces critères.',
        // La modale.
        'Détail',
        'Fermer',
        'Télécharger',
        'Total ·',
        'Porté en note de chambre : ce montant n’est PAS dans le tiroir. Il '
            'devient une créance, réglée au départ du client.',
        'Elle reste au journal : rien n’est effacé.',
      ]);
    });

    test('⚠ le texte d’aide de la recherche est le SEUL libellé délibérément '
        'différent', () {
      // La vue promet un numéro de vente et une chambre, que ce client ne
      // porte ni l'un ni l'autre. Un champ qui ne trouve pas ce qu'il annonce
      // se lit comme un écran cassé.
      final promesse = VueBlade.libelle('pos_pwa.journal.rechercher');

      expect(
        promesse,
        isNotNull,
        reason:
            'le champ de recherche de la vue a changé : cet écart n’est '
            'peut-être plus un écart',
      );
      expect(promesse, contains('N° de vente'));
      expect(promesse, contains('chambre'));

      expect(
        codeDart(),
        isNot(contains(_normaliser(promesse!))),
        reason:
            'la promesse de la vue est revenue dans le code : la recherche '
            'ne peut la tenir ni sur le numéro de vente, ni sur la chambre',
      );
    });

    test('le badge « stock ✕ » de la vue existe, et n’est pas porté', () {
      // L'écart est réel des deux côtés : la vue le pose, ce client ne le
      // rend pas, et il le NOMME. Sans ce cas, quelqu'un le rajouterait un jour
      // sans savoir qu'il ne s'afficherait jamais.
      expect(_texteVisible(maitre()), contains('stock ✕'));

      // Le panneau « Ce que cet écran ne rend pas » n'est plus affiché (Phase 2,
      // 08/10/2026) : le refus est NOMMÉ dans l'en-tête de `table_ventes.dart`
      // (commentaire, relu ici en brut). Depuis le 14/10/2026 (directive du
      // PO), aucune référence interne « PA-134 » n'est plus affichée : la carte
      // « Sans impact stock » dit « Non tenu ici ».
      final enTete = File(
        'lib/features/ventes/presentation/widgets/table_ventes.dart',
      ).readAsStringSync();
      expect(enTete, contains('Le badge « stock ✕ »'));
      expect(codeDart(), isNot(contains('PA-134')));
      expect(codeDart(), contains('Non tenu ici'));
    });
  });

  /* ================================================================== */
  group('« Enregistré sur ce poste » est vrai, et le SERVEUR le dit', () {
    test('`paniers` n’est PAS au registre des tables synchronisables', () {
      // C'est ce qui rend la phrase vraie. Le jour où `paniers` y entrerait, ce
      // cas rougirait — et il faudrait alors rouvrir le bandeau de l'écran,
      // plutôt que de laisser un journal annoncer un poste isolé qui ne l'est
      // plus.
      final source = serveurSync();
      final debut = source.indexOf('public const TABLES_SYNCHRONISABLES');
      expect(
        debut,
        greaterThan(-1),
        reason:
            'le registre a disparu du serveur : ce test ne mesure plus rien',
      );

      final registre = source.substring(
        source.indexOf('[', debut),
        source.indexOf('];', debut),
      );
      final tables = RegExp(
        "'([a-z_]+)' =>",
      ).allMatches(registre).map((m) => m.group(1)!).toSet();

      expect(tables, isNotEmpty);
      expect(tables, containsAll(const ['reservations', 'clients']));
      expect(tables, isNot(contains('paniers')));
      // `factures` y est entré au lot F5c (décision du PO du 17/10/2026,
      // Q2) : la facture part, provisoire, et reçoit le numéro du serveur.
      // Ce journal, lui, reste celui des ventes, pas des factures.
    });

    test('aucun écran du journal n’annonce une synchronisation', () {
      // Un badge d'attente sur ce qui ne partira jamais est la famille
      // PA-59/60/61 — un indicateur qui dit que tout va bien pendant que rien
      // n'a lieu.
      final dart = codeDart();

      // Depuis le 14/10/2026, l'issue d'un export du journal (liste ou détail
      // d'une vente) est dite par le toast COMMUN du poste, et non plus par
      // une phrase propre à l'écran : le journal doit l'EMPRUNTER (deux
      // exports, deux appels), et ce toast doit dire « enregistré », jamais
      // une synchronisation ni un envoi.
      expect(
        RegExp(r'executerExport\(').allMatches(dart).length,
        2,
        reason: 'la liste et le détail d’une vente disent leur export',
      );
      final toast = File(
        'lib/shared_widgets/toast_export.dart',
      ).readAsStringSync();
      expect(toast, contains("'Export enregistré : "));
      expect(toast, isNot(contains('synchronis')));
      expect(toast, isNot(contains('envoy')));
      expect(dart, isNot(contains('en attente de synchronisation')));
    });
  });
}

/// Le texte **visible** d'une source : balises retirées (la vue Blade n'a
/// plus de JavaScript à préserver), puis [_normaliser].
String _texteVisible(String source) =>
    _normaliser(source.replaceAll(RegExp(r'<[^>]*>'), ''));

/// Apostrophes typographiques ramenées à l'apostrophe droite, entités HTML
/// défaites, suites d'espaces et de sauts de ligne réduites à un espace.
///
/// Sans cette normalisation, une phrase coupée sur trois lignes de la vue ne
/// serait jamais retrouvée dans une chaîne Dart, et **toutes** les assertions
/// de libellé passeraient à vide — le défaut que ces gardes existent pour
/// empêcher.
String _normaliser(String texte) => texte
    .replaceAll('&rsquo;', "'")
    .replaceAll('&amp;', '&')
    .replaceAll('&times;', '×')
    .replaceAll('’', "'")
    .replaceAll(r"\'", "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
