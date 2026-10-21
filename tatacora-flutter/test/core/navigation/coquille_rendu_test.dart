import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/navigation/coquille_vue.dart';
import 'package:tatacora_flutter/core/navigation/navigation_tatacora.dart';
import 'package:tatacora_flutter/core/navigation/trace_svg.dart';
import 'package:tatacora_flutter/core/router/coquille_application.dart';
import 'package:tatacora_flutter/core/theme/app_assets.dart';
import 'package:tatacora_flutter/core/theme/app_colors.dart';
import 'package:tatacora_flutter/core/theme/app_spacing.dart';
import 'package:tatacora_flutter/core/theme/app_text_styles.dart';
import 'package:tatacora_flutter/features/caisse/domain/entities/session_caisse.dart';
import 'package:tatacora_flutter/features/caisse/domain/indicateur_caisse.dart';
import 'package:tatacora_flutter/features/caisse/domain/repositories/sessions_caisse_repository.dart';
import 'package:tatacora_flutter/features/caisse/presentation/providers_caisse.dart';

import '../../support/ajouts_menu_poste.dart';
import '../../support/coquille_montee.dart';
import '../../support/vue_blade.dart';

/// Lot 1 « coquille » (12/10/2026) — le RENDU de la barre supérieure, du menu
/// de compte et de la barre latérale, confronté à la VUE (PA-183).
///
/// Ces cas ne recopient pas la vue : les libellés sont relus dans les clés de
/// langue résolues par PHP, les tracés dans les partiels Blade, les droits dans
/// le relevé que la PWA a servi à chaque rôle (`structure/barre-laterale.json`).
/// Ils échouent (ils ne sautent pas) si PHP ou la vue sont introuvables.
void main() {
  final droitsParRole = () {
    final f = File('tool/conformite_blade/structure/barre-laterale.json');
    if (!f.existsSync()) fail('Relevé introuvable : ${f.path}.');
    final roles =
        (jsonDecode(f.readAsStringSync()) as Map<String, dynamic>)['roles']
            as Map<String, dynamic>;
    return {
      for (final e in roles.entries)
        e.key:
            (e.value as Map<String, dynamic>)['droits'] as Map<String, dynamic>,
    };
  }();

  String routeCourante(WidgetTester tester) => tester
      .widget<CoquilleApplication>(find.byType(CoquilleApplication))
      .routeActive;

  group('Les libellés de la coquille sont ceux de la vue', () {
    test('chaque chaîne est la clé de langue que la vue rend', () {
      final attendus = <String, String>{
        'pwa.marque': LibellesCoquille.marque,
        'pwa.enseigne_courte': LibellesCoquille.enseigneCourte,
        'pwa.alt_logo': LibellesCoquille.altLogo,
        'pwa.mention_pied_menu': LibellesCoquille.mentionPiedMenu,
        'pwa.accueil.deconnexion': LibellesCoquille.deconnexion,
        'pwa.coquille.ouvrir_menu': LibellesCoquille.ouvrirMenu,
        'pwa.coquille.plein_ecran': LibellesCoquille.pleinEcran,
        'pwa.coquille.vente': LibellesCoquille.vente,
        'pwa.coquille.vente_titre': LibellesCoquille.venteTitre,
        'pwa.coquille.caisse_fermee': LibellesCoquille.caisseFermee,
        'pwa.coquille.caisse_cloturer': LibellesCoquille.caisseCloturer,
        'pwa.coquille.mon_profil': LibellesCoquille.monProfil,
        'pwa.coquille.parametres_compte': LibellesCoquille.parametresCompte,
        'pwa.coquille.import_export': LibellesCoquille.importExport,
        'pwa.coquille.journal_audit': LibellesCoquille.journalAudit,
        'pwa.coquille.aide_a_propos': LibellesCoquille.aideAPropos,
        'pwa.coquille.contact_editeur': LibellesCoquille.contactEditeur,
        'pwa.coquille.ecran_a_venir': LibellesCoquille.ecranAVenir,
        'pwa.coquille.sans_droit': LibellesCoquille.sansDroit,
      };
      for (final e in attendus.entries) {
        expect(VueBlade.libelle(e.key), e.value, reason: e.key);
      }
      // Le titre de la caisse ouverte porte un paramètre `:point`.
      expect(
        VueBlade.libelle('pwa.coquille.caisse_cloturer_titre'),
        LibellesCoquille.caisseCloturerTitre(':point'),
      );
    });

    // Décision du PO du 13/10/2026 (D373, renverse D307) : la ligne sous la
    // marque n'est plus écrite en dur par la vue, elle rend la clé de
    // localisation des états. Le cas relit la VUE (quelle clé est rendue sous
    // la marque) puis la LANGUE (sa valeur, résolue par PHP) : remettre
    // l'ancienne mention dans `LibellesCoquille` le fait rougir.
    test('la ligne sous la marque est la clé de langue que la barre rend', () {
      final barre = VueBlade.brute(
        'partials/barre-superieure',
      ).replaceAll(RegExp(r'\{\{--.*?--\}\}', dotAll: true), '');
      final ligne = RegExp(
        r'<p class="text-white/40 text-\[11px\]">(.*?)</p>',
      ).firstMatch(barre);
      expect(ligne, isNotNull, reason: 'ligne sous la marque introuvable');
      expect(
        ligne!.group(1)!.trim(),
        "{{ __('rapports.entete.localisation') }}",
      );
      expect(
        VueBlade.libelle('rapports.entete.localisation'),
        LibellesCoquille.localisation,
      );
      // Le nom de l'autre produit (PA-194) n'est plus rendu par la barre.
      expect(barre, isNot(contains('LogiRestock')));
    });

    test('chaque tracé de la coquille est écrit tel quel dans la vue', () {
      final sources = [
        VueBlade.brute('partials/barre-superieure'),
        VueBlade.brute('partials/menu-lateral'),
      ].join('\n');
      for (final t in const [
        TracesCoquille.deconnexion,
        TracesCoquille.chevron,
        TracesCoquille.pleinEcran,
        TracesCoquille.menuMobile,
        TracesCoquille.vente,
        TracesCoquille.monProfil,
        TracesCoquille.parametresCompte,
        TracesCoquille.importExport,
        TracesCoquille.journalAudit,
        TracesCoquille.aideAPropos,
        TracesCoquille.contactEditeur,
      ]) {
        expect(sources, contains(t), reason: t);
        expect(() => TraceSvg.lire(t), returnsNormally, reason: t);
      }
    });
  });

  group('Les tracés se lisent comme SVG les lit', () {
    test('un arc à drapeaux COLLÉS se lit 0, 0, .33', () {
      // `a1.65 1.65 0 00.33 1.82` : rx, ry, rotation, grand arc 0, sens 0,
      // puis x = .33, y = 1.82 — la forme compacte de l'engrenage.
      final p = cheminDepuisD('M0 0a1.65 1.65 0 00.33 1.82');
      final b = p.getBounds();
      expect(b.right, closeTo(0.33, 0.5));
      expect(b.bottom, closeTo(1.82, 0.01));
    });

    test('le sens de l’arc suit le drapeau `sweep`', () {
      // Demi-cercle de (0,0) à (4,0), rayon 2. sweep = 1 (horaire, y vers le
      // bas) passe PAR LE HAUT ; sweep = 0 passe par le bas.
      final horaire = cheminDepuisD('M0 0A2 2 0 0 1 4 0').getBounds();
      final antihoraire = cheminDepuisD('M0 0A2 2 0 0 0 4 0').getBounds();
      expect(horaire.top, closeTo(-2, 0.01));
      expect(horaire.bottom, closeTo(0, 0.01));
      expect(antihoraire.bottom, closeTo(2, 0.01));
      expect(antihoraire.top, closeTo(0, 0.01));
    });

    test('un tracé illisible LÈVE, il ne dessine pas autre chose', () {
      expect(() => cheminDepuisD('M0 0 X 3 4'), throwsFormatException);
      expect(
        () => TraceSvg.lire('<polygon points="0 0"/>'),
        throwsFormatException,
      );
    });
  });

  group('Barre latérale', () {
    testWidgets('les titres de groupe ont l’interlettrage de la vue', (
      tester,
    ) async {
      await monterCoquille(
        tester,
        role: 'administrateur',
        droits: droitsParRole['administrateur']!,
        routeActive: '/tableau-de-bord',
      );
      final style = tester
          .widget<Text>(find.text('RÉSERVATIONS & SÉJOURS'))
          .style!;
      // `text-[10.5px] font-bold tracking-wider text-white/45`.
      expect(style.fontSize, 10.5);
      expect(style.letterSpacing, closeTo(0.525, 1e-9));
      expect(style.fontWeight, FontWeight.bold);
      expect(style.color!.a, closeTo(0.45, 0.01));
      expect(AppTextStyles.suiviPlusLarge, 0.05);
    });

    testWidgets('chaque entrée dessine le tracé de son module', (tester) async {
      await monterCoquille(
        tester,
        role: 'administrateur',
        droits: droitsParRole['administrateur']!,
        routeActive: '/tableau-de-bord',
      );
      var verifiees = 0;
      for (final d in toutesLesDestinations) {
        final lien = find.byKey(Key('lien-lateral-${d.nom}'));
        if (lien.evaluate().isEmpty) continue; // hors fenêtre de la liste
        final icone = tester.widget<IconeTrace>(
          find.descendant(of: lien, matching: find.byType(IconeTrace)),
        );
        expect(icone.trace, d.icone.trace, reason: d.nom);
        expect(icone.taille, 17, reason: d.nom);
        verifiees++;
      }
      expect(verifiees, greaterThanOrEqualTo(15), reason: 'plancher');
    });

    testWidgets('toute entrée À ROUTE mène à sa route, au clic', (
      tester,
    ) async {
      var visitees = 0;
      for (final d in toutesLesDestinations.where((d) => d.route != null)) {
        await monterCoquille(
          tester,
          role: 'administrateur',
          droits: droitsParRole['administrateur']!,
          routeActive: '/tableau-de-bord',
        );
        final lien = find.byKey(Key('lien-lateral-${d.nom}'));
        await tester.scrollUntilVisible(
          lien,
          80,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        // Entièrement visible : une entrée à moitié sous le pied de la barre
        // recevrait le clic sur le pied.
        await tester.ensureVisible(lien);
        await tester.pumpAndSettle();
        await tester.tap(lien);
        await tester.pumpAndSettle();
        expect(routeCourante(tester), d.route, reason: d.nom);
        visitees++;
      }
      // 21 → 24 le 14/10/2026 (D424) : Comptabilité, Import & Export et
      // Rôles & Permissions ont leur écran. Plus chaque AJOUT du poste déclaré
      // (`ajouts_menu_poste.dart`) : « Comptes utilisateurs » (PO, 14/10/2026),
      // atteint ici parce que la session est `administrateur` — l'entrée est
      // réservée aux rôles d'administration (`rolesExiges`).
      expect(visitees, 25 + ajoutsMenuPoste.length);
    });

    testWidgets('plus AUCUNE entrée sans écran (D424) : les trois anciennes ne '
        'portent plus l’infobulle « à venir »', (tester) async {
      await monterCoquille(
        tester,
        role: 'administrateur',
        droits: droitsParRole['administrateur']!,
        routeActive: '/tableau-de-bord',
      );
      expect(toutesLesDestinations.where((d) => d.route == null), isEmpty);
      for (final nom in const [
        'Comptabilité',
        'Import & Export',
        'Rôles & Permissions',
      ]) {
        final lien = find.byKey(Key('lien-lateral-$nom'));
        await tester.scrollUntilVisible(
          lien,
          80,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        final infobulles = find.ancestor(
          of: lien,
          matching: find.byType(Tooltip),
        );
        expect(
          tester
              .widgetList<Tooltip>(infobulles)
              .where((t) => t.message == LibellesCoquille.ecranAVenir),
          isEmpty,
          reason: nom,
        );
      }
    });

    testWidgets('le pied : rôle en capitale initiale, déconnexion rouge, '
        'sortie À GAUCHE', (tester) async {
      await monterCoquille(
        tester,
        role: 'administrateur',
        droits: droitsParRole['administrateur']!,
        routeActive: '/tableau-de-bord',
      );
      // Le rôle arrive BRUT (« administrateur ») ; la vue rend `ucfirst`.
      expect(find.text('administrateur'), findsNothing);
      expect(find.text('Administrateur'), findsNWidgets(2)); // barre + pied
      final bouton = find.byKey(const Key('bouton-deconnexion-sidebar'));
      final materiel = tester.widget<Material>(
        find.ancestor(of: bouton, matching: find.byType(Material)).first,
      );
      expect(materiel.color, AppColors.erreur);
      final icone = find.descendant(
        of: bouton,
        matching: find.byType(IconeTrace),
      );
      expect(
        tester.widget<IconeTrace>(icone).trace,
        TracesCoquille.deconnexion,
      );
      final texte = find.descendant(
        of: bouton,
        matching: find.text(LibellesCoquille.deconnexion),
      );
      expect(
        tester.getRect(icone).right,
        lessThanOrEqualTo(tester.getRect(texte).left),
      );
    });
  });

  group('Initiales et rôle, calculés comme la vue', () {
    test('strtoupper(substr(login, 0, 2)) — en OCTETS, ASCII seulement', () {
      expect(initialesDeLogin('barre.admin'), 'BA');
      expect(initialesDeLogin('a'), 'A');
      // « é » fait deux octets : `substr` le rend seul, `strtoupper` ne le
      // touche pas (PHP 8.2+).
      expect(initialesDeLogin('éric'), 'é');
    });

    test('ucfirst, rien de plus', () {
      expect(roleAffiche('administrateur'), 'Administrateur');
      expect(roleAffiche('super_admin'), 'Super_admin');
      expect(roleAffiche(''), '');
    });
  });

  group('Barre supérieure', () {
    testWidgets('la ligne sous la marque et le logo', (tester) async {
      await monterCoquille(
        tester,
        role: 'administrateur',
        droits: droitsParRole['administrateur']!,
        routeActive: '/tableau-de-bord',
      );
      expect(find.text(LibellesCoquille.localisation), findsOneWidget);
      // Décision du PO du 13/10/2026 (D373) : l'autre produit n'est plus
      // nommé sous la marque.
      expect(find.textContaining('LogiRestock'), findsNothing);
      expect(find.bySemanticsLabel(LibellesCoquille.altLogo), findsOneWidget);

      // Décision du PO du 14/10/2026 (D392, PA-210) : logo PNG paysage, cadre
      // carré gardé, `object-contain` dans la vue — relu ici, puis exigé de
      // l'écran (`BoxFit.contain`, jamais `cover` qui rogne).
      final vue = VueBlade.brute(
        'partials/barre-superieure',
      ).replaceAll(RegExp(r'\{\{--.*?--\}\}', dotAll: true), '');
      final balise = RegExp(r'<img[^\n]*urlLogo\(\)[^\n]*>').firstMatch(vue);
      expect(balise, isNotNull, reason: 'logo de la barre introuvable');
      // D430 (PA-210 option c, 14/10/2026) : cadre PAYSAGE 73 × 40 sur fond
      // blanc dans la barre.
      expect(
        balise!.group(0),
        contains('w-[73px] h-10 rounded-lg bg-white object-contain'),
      );
      final logo = find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName == AppAssets.logo,
      );
      expect(logo, findsOneWidget);
      expect(tester.widget<Image>(logo).fit, BoxFit.contain);
      // L'anneau `ring-2` est tracé HORS de la boîte, sans ombre : une
      // `BoxShadow` remplirait de doré les bandes libres du paysage. Le fond
      // est le `bg-white` de la vue (D430).
      final cadre = tester.widget<Container>(
        find.byKey(const Key('logo-barre-superieure')),
      );
      final decoration = cadre.decoration! as BoxDecoration;
      expect(decoration.boxShadow, isNull);
      expect(decoration.color, AppColors.neutre0);
      final anneau = (decoration.border! as Border).top;
      expect(anneau.color, AppColors.gold);
      expect(anneau.width, AppLayout.anneauLogo);
      expect(anneau.strokeAlign, BorderSide.strokeAlignOutside);
      expect(
        tester.getSize(find.byKey(const Key('logo-barre-superieure'))),
        const Size(
          AppLayout.logoBarreSuperieureLargeur,
          AppLayout.logoBarreSuperieure,
        ),
      );
    });

    testWidgets('« Vente » et l’indicateur : présents avec M5, absents sans', (
      tester,
    ) async {
      await monterCoquille(
        tester,
        role: 'barman',
        droits: droitsParRole['barman']!,
        routeActive: '/tableau-de-bord',
      );
      expect(find.byKey(const Key('bouton-vente')), findsOneWidget);
      expect(find.byKey(const Key('indicateur-caisse')), findsOneWidget);
      expect(find.byTooltip(LibellesCoquille.venteTitre), findsOneWidget);
      await tester.tap(find.byKey(const Key('bouton-vente')));
      await tester.pumpAndSettle();
      expect(routeCourante(tester), '/pos');
    });

    // Un cas À PART : remonter la coquille dans le même cas garderait la
    // session du premier montage (la `ProviderScope` est réutilisée).
    testWidgets('« Vente » et l’indicateur : absents sans M5', (tester) async {
      // `guide` : M5 = '-' dans la matrice servie.
      expect(droitsParRole['guide']!['M5'], '-');
      await monterCoquille(
        tester,
        role: 'guide',
        droits: droitsParRole['guide']!,
        routeActive: '/tableau-de-bord',
      );
      expect(find.byKey(const Key('bouton-vente')), findsNothing);
      expect(find.byKey(const Key('indicateur-caisse')), findsNothing);
    });

    Future<void> monterAvecCaisse(
      WidgetTester tester,
      SessionCaisse? session,
      DateTime maintenant,
    ) => monterCoquille(
      tester,
      role: 'administrateur',
      droits: droitsParRole['administrateur']!,
      routeActive: '/tableau-de-bord',
      // La police de test (Ahem) donne à chaque glyphe la largeur de sa
      // taille : « Clôturer la caisse » et la pastille d'environnement ne
      // tiennent plus à 1 600 px. En Inter, la barre tient à 1 383 px (relevé).
      taille: const Size(2400, 1400),
      surcharges: [
        depotSessionsCaisseProvider.overrideWithValue(_DepotFixe(session)),
        horlogeCaisseProvider.overrideWithValue(() => maintenant),
      ],
    );

    Color pastille(WidgetTester tester) =>
        (tester
                    .widget<Container>(find.byKey(const Key('pastille-caisse')))
                    .decoration!
                as BoxDecoration)
            .color!;

    final ouverture = DateTime(2026, 10, 12, 7);
    SessionCaisse session(PointDeVenteCaisse point) => SessionCaisse(
      id: 's-1',
      point: point,
      utilisateurOuvertureId: 'u-1',
      dateOuverture: ouverture,
      fondCentimes: 1000000,
    );

    testWidgets('caisse fermée : libellé et pastille ardoise', (tester) async {
      await monterAvecCaisse(tester, null, ouverture);
      expect(find.text(LibellesCoquille.caisseFermee), findsOneWidget);
      expect(pastille(tester), AppColors.neutre400);
      await tester.tap(find.byKey(const Key('indicateur-caisse')));
      await tester.pumpAndSettle();
      expect(routeCourante(tester), '/pos');
    });

    testWidgets('caisse ouverte : « Clôturer la caisse », pastille émeraude, '
        'point en infobulle', (tester) async {
      await monterAvecCaisse(
        tester,
        session(PointDeVenteCaisse.restaurant),
        ouverture.add(const Duration(hours: 23, minutes: 59)),
      );
      expect(find.text(LibellesCoquille.caisseCloturer), findsOneWidget);
      expect(pastille(tester), PaletteMaitre.emeraude400);
      expect(
        find.byTooltip('Clôturer la caisse du Restaurant'),
        findsOneWidget,
      );
    });

    testWidgets('caisse ouverte depuis 24 h : pastille rouge', (tester) async {
      await monterAvecCaisse(
        tester,
        session(PointDeVenteCaisse.bar),
        // Littéral, pas `seuilCaisseTardive` : un seuil muté suivrait la
        // constante, et ce cas ne verrait rien.
        ouverture.add(const Duration(hours: 24)),
      );
      expect(find.text(LibellesCoquille.caisseCloturer), findsOneWidget);
      expect(pastille(tester), PaletteMaitre.rouge400);
    });

    // Contrôle B-1 (12/10/2026, bloquant) : la vue rappelle
    // `IndicateurCaisse::pour()` à chaque rendu de page. Un poste resté
    // allumé doit voir la pastille passer au ROUGE à la navigation suivante —
    // elle restait verte jusqu'au prochain geste de caisse.
    for (final partagee in const [true, false]) {
      testWidgets('poste resté allumé : 25 h plus tard, la navigation suivante '
          'rougit la pastille (${partagee ? 'coquille conservée, '
                    'didUpdateWidget' : 'coquille remontée, initState'})', (
        tester,
      ) async {
        var maintenant = ouverture.add(const Duration(hours: 1));
        await monterCoquille(
          tester,
          role: 'administrateur',
          droits: droitsParRole['administrateur']!,
          routeActive: '/tableau-de-bord',
          taille: const Size(2400, 1400),
          coquillePartagee: partagee,
          surcharges: [
            depotSessionsCaisseProvider.overrideWithValue(
              _DepotFixe(session(PointDeVenteCaisse.bar)),
            ),
            horlogeCaisseProvider.overrideWithValue(() => maintenant),
          ],
        );
        expect(pastille(tester), PaletteMaitre.emeraude400);

        // L'horloge avance ; rien ne se relit tant qu'on ne navigue pas (la
        // vue non plus : elle recalcule au RENDU de la page suivante).
        maintenant = ouverture.add(const Duration(hours: 25));
        await tester.pumpAndSettle();
        expect(pastille(tester), PaletteMaitre.emeraude400);

        await tester.tap(find.byKey(const Key('bouton-vente')));
        await tester.pumpAndSettle();
        expect(routeCourante(tester), '/pos');
        expect(pastille(tester), PaletteMaitre.rouge400);
      });
    }

    // Contrôle B-2 (12/10/2026) : tant que l'état n'est pas LU, rien n'est
    // rendu — ni « Caisse fermée », ni l'indicateur. Le bouton « Vente », lui,
    // est là : la barre est bien rendue, l'absence n'est pas un montage vide.
    testWidgets('dépôt qui ne répond jamais : ni « Caisse fermée », ni '
        'indicateur', (tester) async {
      await monterCoquille(
        tester,
        role: 'administrateur',
        droits: droitsParRole['administrateur']!,
        routeActive: '/tableau-de-bord',
        taille: const Size(2400, 1400),
        surcharges: [
          depotSessionsCaisseProvider.overrideWithValue(_DepotMuet()),
          horlogeCaisseProvider.overrideWithValue(() => ouverture),
        ],
      );
      expect(find.byKey(const Key('bouton-vente')), findsOneWidget);
      expect(find.text(LibellesCoquille.caisseFermee), findsNothing);
      expect(find.text(LibellesCoquille.caisseCloturer), findsNothing);
      expect(find.byKey(const Key('indicateur-caisse')), findsNothing);
    });

    testWidgets('dépôt qui LÈVE : ni « Caisse fermée », ni indicateur', (
      tester,
    ) async {
      await monterCoquille(
        tester,
        role: 'administrateur',
        droits: droitsParRole['administrateur']!,
        routeActive: '/tableau-de-bord',
        taille: const Size(2400, 1400),
        surcharges: [
          depotSessionsCaisseProvider.overrideWithValue(_DepotQuiLeve()),
          horlogeCaisseProvider.overrideWithValue(() => ouverture),
        ],
      );
      expect(find.byKey(const Key('bouton-vente')), findsOneWidget);
      expect(find.text(LibellesCoquille.caisseFermee), findsNothing);
      expect(find.text(LibellesCoquille.caisseCloturer), findsNothing);
      expect(find.byKey(const Key('indicateur-caisse')), findsNothing);
      // Riverpod réessaie une lecture qui lève (délais croissants) : on laisse
      // passer les nouvelles tentatives — elles lèvent toutes — pour qu'aucun
      // minuteur ne reste en attente, et l'on revérifie après.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(seconds: 10));
      }
      expect(find.text(LibellesCoquille.caisseFermee), findsNothing);
      expect(find.byKey(const Key('indicateur-caisse')), findsNothing);
    });
  });

  group('Menu de compte', () {
    Future<void> ouvrir(WidgetTester tester, String role) async {
      await monterCoquille(
        tester,
        role: role,
        droits: droitsParRole[role]!,
        routeActive: '/tableau-de-bord',
      );
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
    }

    testWidgets('les six entrées et la déconnexion, dans l’ordre de la vue', (
      tester,
    ) async {
      await ouvrir(tester, 'administrateur');
      final ordre = [
        LibellesCoquille.monProfil,
        LibellesCoquille.parametresCompte,
        LibellesCoquille.importExport,
        LibellesCoquille.journalAudit,
        LibellesCoquille.aideAPropos,
        LibellesCoquille.contactEditeur,
        LibellesCoquille.deconnexion,
      ];
      final y = [
        for (final l in ordre)
          tester
              .getRect(
                find.descendant(
                  of: find.byType(PopupMenuItem<String>),
                  matching: find.text(l),
                ),
              )
              .top,
      ];
      for (var i = 1; i < y.length; i++) {
        expect(y[i], greaterThan(y[i - 1]), reason: ordre[i]);
      }
      // L'en-tête porte le rôle en capitale initiale, comme la vue.
      expect(
        find.descendant(
          of: find.byType(PopupMenuItem<String>),
          matching: find.text('Administrateur'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('« Paramètres du compte » ouvre l’écran Paramètres', (
      tester,
    ) async {
      await ouvrir(tester, 'administrateur');
      await tester.tap(find.text(LibellesCoquille.parametresCompte));
      await tester.pumpAndSettle();
      expect(routeCourante(tester), '/parametres');
    });

    // Les cinq autres entrées ont leur écran depuis le 14/10/2026 (D424) : le
    // message « écran non encore porté » ne vise plus aucune d'elles.
    for (final (libelle, route) in const [
      (LibellesCoquille.monProfil, '/mon-profil'),
      (LibellesCoquille.importExport, '/import-export'),
      (LibellesCoquille.journalAudit, '/journal-audit'),
      (LibellesCoquille.aideAPropos, '/aide-a-propos'),
      (LibellesCoquille.contactEditeur, '/contact-editeur'),
    ]) {
      testWidgets('« $libelle » ouvre $route, sans message « non porté »', (
        tester,
      ) async {
        await ouvrir(tester, 'administrateur');
        await tester.tap(
          find.descendant(
            of: find.byType(PopupMenuItem<String>),
            matching: find.text(libelle),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(LibellesCoquille.ecranNonPorte(libelle)),
          findsNothing,
        );
        expect(routeCourante(tester), route);
      });
    }

    testWidgets('sans droit PARAM, « Paramètres du compte » dit pourquoi', (
      tester,
    ) async {
      expect(droitsParRole['barman']!['PARAM'], '-');
      await ouvrir(tester, 'barman');
      expect(find.byTooltip(LibellesCoquille.sansDroit), findsNWidgets(2));
      await tester.tap(find.text(LibellesCoquille.parametresCompte));
      await tester.pump();
      expect(find.text(LibellesCoquille.sansDroit), findsOneWidget);
      expect(routeCourante(tester), '/tableau-de-bord');
      await _laisserPartirLeMessage(tester);
    });
  });

  group('Indicateur de caisse — dérivation pure', () {
    final t0 = DateTime(2026, 10, 12, 7);
    SessionCaisse s() => SessionCaisse(
      id: 's',
      point: PointDeVenteCaisse.bar,
      utilisateurOuvertureId: 'u',
      dateOuverture: t0,
      fondCentimes: 0,
    );

    test('aucune session : fermée, sans point', () {
      final i = indicateurCaisse(null, t0);
      expect(i.etat, EtatCaisse.fermee);
      expect(i.point, isNull);
    });

    test('le seuil est 24 h, BORNE COMPRISE (`>= 24`)', () {
      expect(
        indicateurCaisse(
          s(),
          t0.add(const Duration(hours: 23, minutes: 59, seconds: 59)),
        ).etat,
        EtatCaisse.ouverte,
      );
      expect(
        indicateurCaisse(s(), t0.add(const Duration(hours: 24))).etat,
        EtatCaisse.tardive,
      );
    });
  });
}

/// Le message reste 4 s APRÈS son entrée : on laisse l'entrée finir (le
/// minuteur ne démarre qu'à ce moment), puis on avance l'horloge du test
/// au-delà, sans quoi le minuteur resterait en attente à la fin du cas.
Future<void> _laisserPartirLeMessage(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

/// Un dépôt qui ne répond JAMAIS (base verrouillée, lecture pendante).
final class _DepotMuet extends _DepotFixe {
  _DepotMuet() : super(null);

  @override
  Future<SessionCaisse?> sessionOuverteLaPlusRecente() =>
      Completer<SessionCaisse?>().future;

  @override
  Future<SessionCaisse?> sessionOuverte(PointDeVenteCaisse point) =>
      Completer<SessionCaisse?>().future;
}

/// Un dépôt dont la lecture LÈVE (base illisible).
final class _DepotQuiLeve extends _DepotFixe {
  _DepotQuiLeve() : super(null);

  @override
  Future<SessionCaisse?> sessionOuverteLaPlusRecente() async =>
      throw Exception('base illisible');

  @override
  Future<SessionCaisse?> sessionOuverte(PointDeVenteCaisse point) async =>
      throw Exception('base illisible');
}

/// Un dépôt de sessions qui rend une session fixe — la lecture de la barre
/// supérieure n'appelle que [sessionOuverteLaPlusRecente] et
/// [sessionOuverte] (par `sessionDuBarProvider`).
final class _DepotFixe implements SessionsCaisseRepository {
  _DepotFixe(this.session);

  final SessionCaisse? session;

  @override
  Future<SessionCaisse?> sessionOuverteLaPlusRecente() async => session;

  @override
  Future<SessionCaisse?> sessionOuverte(PointDeVenteCaisse point) async =>
      session?.point == point ? session : null;

  @override
  Future<List<SessionCaisse>> sessions() async => [?session];

  @override
  Future<SessionCaisse> ouvrir({
    required PointDeVenteCaisse point,
    required String? fondSaisi,
    required String auteurId,
    required bool peutEcrire,
  }) => throw UnimplementedError('lecture seule');

  @override
  Future<ClotureCaisse> cloturer({
    required PointDeVenteCaisse point,
    required String? constateSaisi,
    required bool peutEcrire,
    int? especesEncaisseesCentimes,
  }) => throw UnimplementedError('lecture seule');
}
