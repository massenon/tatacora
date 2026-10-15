import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/navigation/navigation_tatacora.dart';
import 'package:tatacora_flutter/core/navigation/trace_svg.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';

import '../../support/vue_blade.dart';

/// Conformité du menu à la VUE BLADE de la PWA — le maître (PA-182, PA-183).
///
/// Source : `tatacora-api/app/Pwa/Support/MenuLateral.php`, constante
/// `NAVIGATION` — le registre que `partials/menu-lateral.blade.php` rend sur
/// chaque page de la PWA. Jusqu'au 10/09/2026, ces cas figeaient des listes
/// recopiées de l'ancien prototype ; ils LISENT désormais le registre servi.
///
/// ## Pourquoi ces contrôles, et pas une relecture
///
/// Le menu est la seule partie de l'interface que **toutes** les pages
/// partagent : une entrée qui dérive dérive partout à la fois. Et c'est aussi
/// la plus facile à « améliorer » sans y penser — renommer « Approvisionnement »
/// en « Achats » paraît anodin et casse le manuel, la formation et l'habitude.
///
/// Ces cas confrontent donc les **nombres**, l'**ordre** et les **libellés** au
/// registre de la PWA. Ils échouent au premier écart, y compris bien
/// intentionné — et le jour où la PWA change son menu, ils disent au Flutter de
/// suivre.
void main() {
  // ------------------------------------------------------------- le maître

  /// Le registre `NAVIGATION` de `MenuLateral.php`, lu ligne à ligne.
  ///
  /// Une entrée tient sur une ligne (`['nom' => …, 'badge' => …]`), un groupe
  /// s'ouvre par `['groupe' => …`. Les commentaires PHP sont écartés : l'un
  /// d'eux cite `nom: 'Tourisme'` du prototype, et le lire en ferait une
  /// entrée fantôme.
  final registre = () {
    final source = VueBlade.fichier(
      'app/Pwa/Support/MenuLateral.php',
      role: 'le registre du menu latéral de la PWA',
    );
    final debut = source.indexOf('const NAVIGATION = [');
    if (debut < 0) {
      fail('`MenuLateral::NAVIGATION` a disparu : le menu ne se lit plus.');
    }
    final fin = source.indexOf('\n    ];', debut);
    final corps = source.substring(debut, fin < 0 ? source.length : fin);

    final epinglees = <({String nom, String? badge})>[];
    final groupes =
        <({String titre, List<({String nom, String? badge})> items})>[];
    String? champ(String ligne, String cle) =>
        RegExp("'$cle'\\s*=>\\s*'([^']+)'").firstMatch(ligne)?.group(1);

    for (final brute in corps.split('\n')) {
      final ligne = brute.trim();
      if (ligne.startsWith('//') || ligne.startsWith('*')) continue;
      final titre = champ(ligne, 'groupe');
      if (titre != null) {
        groupes.add((titre: titre, items: []));
        continue;
      }
      final nom = champ(ligne, 'nom');
      if (nom == null) continue;
      final entree = (nom: nom, badge: champ(ligne, 'badge'));
      if (ligne.contains("'epingle' => true")) {
        epinglees.add(entree);
      } else if (groupes.isNotEmpty) {
        groupes.last.items.add(entree);
      }
    }

    // La garde de la garde. Mesuré le 10/09/2026 : 5 épinglées, 8 groupes,
    // 24 destinations. Les planchers sont posés dessous : s'ils tombent, c'est
    // la LECTURE qui s'est cassée, pas la PWA qui a maigri.
    final total =
        epinglees.length + groupes.fold<int>(0, (s, g) => s + g.items.length);
    if (epinglees.length < 3 || groupes.length < 5 || total < 20) {
      fail(
        'Extraction partielle de `MenuLateral::NAVIGATION` : '
        '${epinglees.length} épinglées, ${groupes.length} groupes, $total '
        'destinations. Ce contrôle passerait à vide.',
      );
    }
    return (epinglees: epinglees, groupes: groupes);
  }();

  List<String> nomsDe(Iterable<DestinationMenu> d) =>
      d.map((x) => x.nom).toList();

  group('Le compte y est — celui du menu de la PWA', () {
    test('les entrées épinglées, dans l’ordre de la PWA', () {
      // `'epingle' => true` — elles précèdent le premier titre de groupe et
      // n'en portent aucun. Mesuré le 10/09/2026 : cinq.
      expect(
        nomsDe(destinationsEpinglees),
        registre.epinglees.map((e) => e.nom).toList(),
      );
      expect(destinationsEpinglees, hasLength(5));
    });

    test('les groupes, dans l’ordre exact de la PWA', () {
      expect(
        groupesMenu.map((g) => g.titre).toList(),
        registre.groupes.map((g) => g.titre).toList(),
        reason: 'l’ordre porte le flux de travail, il ne se réarrange pas',
      );
      expect(groupesMenu, hasLength(8));
    });

    test('chaque groupe porte les entrées de la PWA, dans son ordre', () {
      for (final g in registre.groupes) {
        final flutter = groupesMenu.where((x) => x.titre == g.titre);
        expect(flutter, hasLength(1), reason: 'groupe « ${g.titre} »');
        expect(
          nomsDe(flutter.single.destinations),
          g.items.map((e) => e.nom).toList(),
          reason: 'entrées du groupe « ${g.titre} »',
        );
      }
    });

    test('vingt-quatre destinations au total, comme la PWA', () {
      final pwa =
          registre.epinglees.length +
          registre.groupes.fold<int>(0, (s, g) => s + g.items.length);
      expect(toutesLesDestinations, hasLength(pwa));
      expect(toutesLesDestinations, hasLength(24));
    });
  });

  group('Les libellés sont ceux de la PWA, au caractère près', () {
    test('aucun synonyme n’a remplacé un libellé', () {
      // La coquille précédente disait « Accueil », « Dépenses », « Rapports ».
      // Aucun des trois n'existe au menu de la PWA : c'étaient des synonymes,
      // que la doctrine §2 interdit — « le manuel, la formation et l'habitude
      // s'appuient sur le mot exact ».
      final noms = toutesLesDestinations.map((d) => d.nom).toSet();

      for (final interdit in const ['Accueil', 'Dépenses', 'Rapports']) {
        expect(
          noms,
          isNot(contains(interdit)),
          reason: '« $interdit » n’existe pas au menu de la PWA',
        );
      }

      // Et chaque libellé de la PWA est bien là — la liste n'est plus
      // recopiée ici, elle est lue dans le registre.
      final pwa = {
        ...registre.epinglees.map((e) => e.nom),
        for (final g in registre.groupes) ...g.items.map((e) => e.nom),
      };
      expect(noms, pwa);
    });

    test('les badges de la PWA sont conservés', () {
      // Décoratifs au sens strict, mais porteurs de sens métier : « Comptant »
      // et « Panier ouvert » distinguent les deux points de vente, ce que
      // l'atelier du 19/08/2026 a explicitement demandé.
      final flutter = {
        for (final d in toutesLesDestinations)
          if (d.badge != null) d.nom: d.badge,
      };
      final pwa = {
        for (final e in [
          ...registre.epinglees,
          for (final g in registre.groupes) ...g.items,
        ])
          if (e.badge != null) e.nom: e.badge,
      };
      expect(pwa, isNotEmpty, reason: 'aucun badge lu dans le registre');
      expect(flutter, pwa);
    });
  });

  group('Les icônes sont les TRACÉS de la PWA (12/10/2026)', () {
    /// `MenuLateral::ICONES` — une clé, un tracé, une ligne chacun.
    final icones = () {
      final source = VueBlade.fichier(
        'app/Pwa/Support/MenuLateral.php',
        role: 'le registre des icônes du menu latéral',
      );
      final debut = source.indexOf('const ICONES = [');
      final fin = source.indexOf('\n    ];', debut);
      if (debut < 0 || fin < 0) fail('`MenuLateral::ICONES` introuvable.');
      final table = <String, String>{
        for (final m in RegExp(
          r"^\s*'([a-z]+)' => '(.*)',\s*$",
          multiLine: true,
        ).allMatches(source.substring(debut, fin)))
          m.group(1)!: m.group(2)!,
      };
      // Plancher : 18 tracés au 12/10/2026. Sous ce seuil, c'est la LECTURE
      // qui s'est cassée, et la boucle passerait à vide.
      if (table.length < 15) fail('Extraction partielle : ${table.length}.');
      return table;
    }();

    /// L'icône de chaque entrée — `'icone' => '…'` de `NAVIGATION`.
    final iconeParNom = () {
      final source = VueBlade.fichier('app/Pwa/Support/MenuLateral.php');
      final debut = source.indexOf('const NAVIGATION = [');
      final corps = source.substring(debut, source.indexOf('\n    ];', debut));
      return {
        for (final m in RegExp(
          r"'nom' => '([^']+)', 'icone' => '([a-z]+)'",
        ).allMatches(corps))
          m.group(1)!: m.group(2)!,
      };
    }();

    test(
      'chaque destination dessine le tracé de SON entrée, au caractère près',
      () {
        expect(iconeParNom.length, toutesLesDestinations.length);
        for (final d in toutesLesDestinations) {
          final cle = iconeParNom[d.nom];
          expect(cle, isNotNull, reason: '« ${d.nom} » absent du registre PHP');
          expect(d.icone.cleVue, cle, reason: d.nom);
          expect(d.icone.trace, icones[cle], reason: '${d.nom} ($cle)');
        }
      },
    );

    test('chaque tracé du registre est lisible par le dessinateur', () {
      for (final i in IconeModule.values) {
        expect(icones[i.cleVue], i.trace, reason: i.name);
        expect(() => TraceSvg.lire(i.trace), returnsNormally, reason: i.name);
      }
    });
  });

  group('Registre fermé — on ne peut pas ajouter sans déclarer', () {
    test('chaque destination porte un module', () {
      // Même discipline que `TABLES_SYNCHRONISABLES` côté serveur : déclarer le
      // module est obligatoire, donc dire qui a le droit de voir l'entrée l'est
      // aussi. Une entrée sans module serait visible de tous par omission.
      //
      // `page` est l'ancrage HISTORIQUE de chaque destination vers la page de
      // l'ancien prototype ; il reste unique et renseigné tant que
      // `navigation_tatacora.dart` le porte (PA-183 : il ne fait plus foi).
      for (final d in toutesLesDestinations) {
        expect(d.module, isA<ModuleTatacora>(), reason: d.nom);
        expect(d.page, isNotEmpty, reason: '${d.nom} : page d’origine absente');
        expect(d.page, endsWith('.html'), reason: d.nom);
      }
    });

    test('aucun libellé, aucune page d’origine n’est en double', () {
      final noms = toutesLesDestinations.map((d) => d.nom).toList();
      final pages = toutesLesDestinations.map((d) => d.page).toList();

      expect(noms.toSet(), hasLength(noms.length), reason: 'libellé en double');
      expect(
        pages.toSet(),
        hasLength(pages.length),
        reason:
            'deux entrées vers la même page : ces cas-là ont justement été '
            'FUSIONNÉS, ne pas les rouvrir',
      );
    });
  });

  group('Ce que la couverture dit, sans le masquer', () {
    /// Les chemins que le ROUTEUR sert réellement, lus dans son code source.
    ///
    /// C'est le point de tout ce groupe. `aUnEcran` se définit par
    /// `route != null` : un test qui vérifiait « une destination sans écran
    /// n'annonce aucune route » comparait donc le champ à lui-même et **ne
    /// pouvait pas échouer**. Il a laissé passer exactement ce qu'il prétendait
    /// couvrir — trois écrans livrés (Clients, Bar, Paramètres) et le tableau
    /// de bord, atteignables par aucun clic pendant plusieurs livraisons.
    ///
    /// L'ancrage réel est le routeur : une route déclarée au menu doit y
    /// exister, et un écran servi doit être atteignable depuis le menu.
    Set<String> cheminsDuRouteur() {
      final source = File('lib/core/router/app_router.dart').readAsStringSync();

      return RegExp(
        r"path: '(/[a-z0-9\-/]*)'",
      ).allMatches(source).map((m) => m.group(1)!).toSet();
    }

    /// Les sous-chemins, declares en RELATIF par `go_router` (`path: 'heberges'`
    /// sous `/pos`). Les chercher en absolu ne les trouverait jamais — et un
    /// controle qui ne trouve rien passe.
    Set<String> sousCheminsDuRouteur() {
      final source = File('lib/core/router/app_router.dart').readAsStringSync();

      return RegExp(
        r"path: '([a-z0-9\-]+)'",
      ).allMatches(source).map((m) => m.group(1)!).toSet();
    }

    test('toute route annoncée au menu EXISTE au routeur', () {
      final routeur = cheminsDuRouteur();

      // Plancher : une expression régulière qui ne trouverait plus rien rendrait
      // un ensemble vide, et la boucle ci-dessous serait vide donc verte.
      expect(routeur.length, greaterThanOrEqualTo(8));

      final sous = sousCheminsDuRouteur();

      for (final d in toutesLesDestinations.where((d) => d.aUnEcran)) {
        final segments = d.route!
            .split('/')
            .where((s) => s.isNotEmpty)
            .toList();
        // `go_router` accepte les DEUX styles : un sous-chemin declare en
        // absolu (`path: '/stocks/inventaires'`) ou en relatif sous son parent
        // (`path: 'heberges'`). N'accepter qu'un des deux ferait rougir une
        // route parfaitement servie — le test dirait un defaut qui n'existe
        // pas, et on finirait par le desactiver.
        final connu =
            routeur.contains(d.route) ||
            (segments.length > 1 &&
                routeur.contains('/${segments.first}') &&
                sous.contains(segments.last));

        expect(
          connu,
          isTrue,
          reason:
              'Le menu annonce ${d.route} pour « ${d.nom} », que le routeur '
              'ne sert pas : le clic mènerait à une page d’erreur.',
        );
      }
    });

    test('tout écran SERVI est atteignable depuis le menu', () {
      // La réciproque, et c'est elle qui manquait. Un écran livré sans entrée
      // de menu n'existe que pour qui connaît son URL — c'est-à-dire pour
      // personne, au comptoir.
      const horsMenu = {
        // Trois chemins n'ont volontairement pas d'entrée : ils précèdent la
        // session ou sont atteints par un geste, pas par le menu.
        '/demarrage',
        '/connexion',
        '/synchronisation',
      };

      // Le MENU DE COMPTE de la barre supérieure est aussi un menu (D424) :
      // Mon profil, Journal d'Audit, Aide & À propos, Contactez l'éditeur y
      // vivent, comme dans la vue. Ses routes sont relues dans le code de la
      // coquille (piège 12 : une source extérieure, pas le registre testé).
      final menuCompte = RegExp(r"route: '(/[^']+)'")
          .allMatches(
            File(
              'lib/core/router/coquille_application.dart',
            ).readAsStringSync(),
          )
          .map((m) => m.group(1)!)
          .toSet();
      expect(menuCompte, contains('/mon-profil'), reason: 'plancher');

      final auMenu = {
        ...toutesLesDestinations.where((d) => d.aUnEcran).map((d) => d.route),
        ...menuCompte,
      };

      for (final chemin in cheminsDuRouteur().difference(horsMenu)) {
        // Les sous-chemins (`/hebergement/reservations`) sont déclarés en
        // relatif au routeur : on ne retient que les racines.
        if (chemin.split('/').length > 2) continue;

        expect(
          auMenu,
          contains(chemin),
          reason:
              'Le routeur sert $chemin, qu’aucune entrée de menu n’annonce : '
              'l’écran n’est atteignable par aucun clic.',
        );
      }
    });

    test('les vingt-quatre destinations ont un écran (D424)', () {
      final avec = toutesLesDestinations.where((d) => d.aUnEcran).toList();

      // Ce nombre n'est pas un objectif, c'est un CONSTAT : il doit changer
      // quand un écran est livré. S'il change sans que ce test soit relu, c'est
      // qu'un écran a été branché sans qu'on mesure ce qu'il apporte.
      // 17 → 21 le 14/09/2026 : les quatre modules d'exploitation portés en
      // local pur (Dépense courante, Tourisme, Personnel & Paie,
      // Notifications) avaient un écran livré et AUCUN chemin pour y arriver.
      // 21 → 24 le 14/10/2026 (D417–D419, D424) : Comptabilité, Import &
      // Export et Rôles & Permissions sont portés et branchés.
      expect(
        avec,
        hasLength(24),
        reason:
            'couverture du MENU : ${avec.length}/24 — mettre à jour '
            'AUDIT_CONFORMITE_ECRANS_FLUTTER.md §3 en même temps que ce chiffre',
      );

      expect(
        avec.map((d) => d.nom),
        containsAll(const [
          'Tableau de bord',
          'Point de vente',
          'POS clients hébergés',
          'Réservations',
          'Hébergement',
          'Clients & Créances',
          'Facturation',
          'Bar',
          'Stocks',
          'Inventaires & Fiches',
          'Paramètres',
          // M7, livré le 26/08/2026.
          'Approvisionnement',
          'Fournisseurs',
          // Le JOURNAL des ventes, livré le 26/08/2026. À ne pas confondre avec
          // « Facturation », qui sert le REGISTRE des pièces : les deux lisent
          // des tables différentes et n'affichent jamais le même total.
          'Historique des ventes',
          // M4, livré le 26/08/2026. L'entrée était INERTE faute d'API
          // (PA-146), ce que l'Article 3.3 de la directive de conformité
          // interdit désormais : « l'entrée doit naviguer vers l'écran réel ».
          'Restaurant',
          // Les quatre modules d'exploitation, livrés le 14/09/2026 et
          // branchés au menu le même jour : leurs écrans existaient déjà,
          // sans qu'aucun clic n'y mène.
          'Dépense courante',
          'Tourisme',
          'Personnel & Paie',
          'Notifications',
          'Comptabilité',
          'Import & Export',
          'Rôles & Permissions',
        ]),
      );
    });
  });
}
