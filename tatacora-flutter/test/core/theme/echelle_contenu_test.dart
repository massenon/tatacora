import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/theme/app_text_styles.dart';

import '../../support/vue_blade.dart';

/// La FRONTIÈRE entre l'échelle déclarée et l'échelle effective.
///
/// La feuille servie par la PWA (`tatacora-api/public/assets/css/app.css`)
/// remappe chaque palier typographique **à l'intérieur de `main`** : une classe
/// `text-[13px]` y rend 12,5 px. Article 0 — la vue Blade fait foi sur ce qui
/// *se voit* (PA-182, PA-183), et ce qui se voit est le pixel rendu, jamais le
/// nom de la classe. Le contenu de page emploie donc [TaillesContenu] ; le reste
/// emploie [Tailles].
///
/// ## Ce que cette garde protège, et que rien d'autre ne protégeait
///
/// `conformite_jetons_maitre_test.dart` vérifie que les deux échelles
/// **valent** ce que vaut la feuille servie. Elle ne dit rien de *qui les
/// emploie* — un écran de contenu repassé sur l'échelle déclarée y resterait
/// vert, et le défaut serait d'un demi à un pixel et demi : invisible à la
/// relecture, invisible en revue.
///
/// ## Elle s'ancre sur les VUES BLADE, pas sur elle-même
///
/// Piège 12 : un prédicat dérivé du champ qu'il vérifie ne vérifie rien. La
/// classification ci-dessous n'est pas un décret — chacune de ses trois
/// familles est **re-mesurée dans les vues** à chaque exécution :
///
/// - la connexion et le démarrage sont les 2 seules pages sans `<main>` ;
/// - les conteneurs de modales sont tous hors `</main>` ;
/// - la barre latérale est ramenée à 14 px par une règle propre.
///
/// Le jour où la PWA déplace l'un des trois, cette garde le dit — au lieu de
/// rester verte sur une frontière devenue fausse (PA-144). Jusqu'au 10/09/2026
/// elle mesurait ces trois faits dans `prototype_v2/`, une ancienne version.
///
/// ## Elle ÉCHOUE si la source manque, et porte des planchers
///
/// Un balayage vide est vert. C'est le défaut qu'elle protège.
void main() {
  // ------------------------------------------------------------- le maître
  String feuilleServie(String role) =>
      VueBlade.fichier('public/assets/css/app.css', role: role);

  String cheminDeVue(String nom) =>
      'resources/views/${nom.replaceAll('.', '/')}.blade.php';

  /// Les commentaires Blade parlent des pages — « `<main>` », « modale » — sans
  /// en être : les lire ferait compter un mot comme une balise.
  String sansCommentaires(String s) =>
      s.replaceAll(RegExp(r'\{\{--[\s\S]*?--\}\}'), ' ');

  final motifInclude = RegExp(
    r"@include(?:If|When|Unless)?\(\s*'(pwa\.[a-z0-9_.\-]+)'",
  );

  /// Une vue, ses `@include` DÉPLIÉS à leur place : c'est la position dans la
  /// page rendue qui décide si une modale est dans `<main>`, pas le fichier
  /// où elle est écrite.
  String deplier(String nom, [int profondeur = 0]) {
    final source = sansCommentaires(VueBlade.fichier(cheminDeVue(nom)));
    if (profondeur > 6) return source;
    return source.replaceAllMapped(motifInclude, (m) {
      final inclus = File('${VueBlade.racine}/${cheminDeVue(m[1]!)}');
      if (!inclus.existsSync()) return m[0]!;
      return '<!--INCLUS:${m[1]}-->${deplier(m[1]!, profondeur + 1)}'
          '<!--/INCLUS-->';
    });
  }

  /// Les pages servies : les vues qui incluent la barre supérieure (donc la
  /// coquille) sans être elles-mêmes incluses, plus les deux pages que la PWA
  /// sert HORS coquille. Même définition que
  /// `tool/conformite_blade/t-blade-flutter.js`.
  const horsCoquille = ['pwa.demarrage', 'pwa.livewire.connexion'];

  late final pages = () {
    final racine = Directory('${VueBlade.racine}/resources/views/pwa');
    if (!racine.existsSync()) {
      fail('Les vues de la PWA sont introuvables : ${racine.path}');
    }
    final separateur = String.fromCharCode(92);
    final inclusions = <String, Set<String>>{};
    for (final f in racine.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.blade.php')) continue;
      final relatif = f.path
          .replaceAll(separateur, '/')
          .split('/resources/views/pwa/')
          .last
          .replaceAll('.blade.php', '');
      inclusions['pwa.${relatif.replaceAll('/', '.')}'] = motifInclude
          .allMatches(sansCommentaires(f.readAsStringSync()))
          .map((m) => m[1]!)
          .toSet();
    }
    final incluses = inclusions.values.expand((s) => s).toSet();
    bool coquille(String nom, [Set<String>? vus]) {
      final pile = vus ?? <String>{};
      if (!pile.add(nom)) return false;
      final enfants = inclusions[nom] ?? const <String>{};
      return enfants.contains('pwa.partials.barre-superieure') ||
          enfants.any((e) => coquille(e, pile));
    }

    final avec =
        inclusions.keys
            .where((n) => !incluses.contains(n) && coquille(n))
            .toList()
          ..sort();
    for (final n in horsCoquille) {
      if (!inclusions.containsKey(n)) fail('La page `$n` a disparu.');
    }
    // Mesuré le 10/09/2026 (PA-183) : 41 pages sous coquille, plus les deux
    // hors coquille. Le plancher est posé dessous.
    expect(
      avec.length,
      greaterThanOrEqualTo(38),
      reason:
          'Seules ${avec.length} pages sous coquille relues, contre 41 le '
          '10/09/2026 : le balayage s est vidé, et il serait vert.',
    );
    return (sousCoquille: avec, toutes: [...avec, ...horsCoquille]);
  }();

  // ------------------------------------------------------------ le portage
  //
  // Deux familles, toutes deux FERMÉES. Un fichier qui emploie un palier
  // typographique sans figurer dans l une des deux fait échouer la suite :
  // c est ce qui oblige à trancher, pour chaque nouvel écran, s il est dans
  // le `<main>` de sa vue Blade ou hors de lui.

  /// Rendu **à l'intérieur** du contenu de page — l'équivalent Flutter du
  /// `<main>` de la vue. Échelle effective.
  const contenuDePage = <String>{
    // Le panneau « Tableau croisé dynamique » (13/10/2026) : dans le `<main>`
    // de la vue d'accueil (`data-panneau-tb="croise"`).
    'lib/features/tableau_de_bord/presentation/ecran_tableau_croise.dart',
    // Le graphique « Créances par ancienneté » du Pilotage (13/10/2026).
    'lib/features/tableau_de_bord/presentation/widgets/graphique_creances_anciennete.dart',
    'lib/features/ventes/presentation/ecran_historique_ventes.dart',
    'lib/features/ventes/presentation/widgets/barre_filtres_ventes.dart',
    'lib/features/ventes/presentation/widgets/table_ventes.dart',
    'lib/shared_widgets/tableau_tatacora.dart',
    // M4, livré le 26/08/2026 — les deux écrans du restaurant. Leurs styles de
    // CONTENU vivent ici ; ceux de leurs modales sont dans un fichier séparé,
    // classé dans l'autre camp.
    'lib/features/restaurant/presentation/widgets/coquille_restaurant.dart',
    // M14 — `etats/studio.blade.php` vit entièrement dans `<main>` et n'a
    // AUCUNE modale. Tout y relève donc de l'échelle EFFECTIVE.
    'lib/features/etats/presentation/widgets/textes_etats.dart',
    // Onglet « Pilotage consolidé » du tableau de bord : la barre d'onglets et
    // le panneau pilotage de `livewire/accueil.blade.php` vivent tous deux
    // DANS `<main>` : échelle EFFECTIVE partout.
    'lib/features/tableau_de_bord/presentation/ecran_pilotage_consolide.dart',
    'lib/features/tableau_de_bord/presentation/onglets_tableau_de_bord.dart',
    'lib/features/tableau_de_bord/presentation/widgets/graphique_marge_centres.dart',
    // La période du tableau de bord (12/10/2026, D296) : le `<select>`, les
    // deux `<input type="date">` et le « Au » de l'en-tête, et ceux de la barre
    // du pilotage, sont tous DANS `<main>` de la vue d'accueil (l.219 et
    // suivantes) : échelle EFFECTIVE.
    'lib/features/tableau_de_bord/presentation/ecran_tableau_de_bord.dart',
    'lib/features/tableau_de_bord/presentation/widgets/champ_date_periode.dart',
    // La « Vue d'exploitation » de l'accueil (12/10/2026, lot 2) : raccourcis,
    // bande d'indicateurs, bandeau d'alertes, récapitulatif, graphiques,
    // chambres disponibles, consultation de secours — tous DANS `<main>` de
    // la vue d'accueil (l.219-1392) : échelle EFFECTIVE. La modale « Articles
    // sous le seuil d'alerte » vit dans un fichier à part, classé dans l'autre
    // camp.
    'lib/features/tableau_de_bord/presentation/widgets/panneau_exploitation.dart',
    'lib/features/tableau_de_bord/presentation/widgets/graphiques_tableau_de_bord.dart',
    // Modules d exploitation, portés le 14/09/2026. Les quatre fichiers
    // ci-dessous rendent le CORPS de leur page ; leurs modales sont dans des
    // fichiers séparés, classés dans l autre camp — c est la même frontière
    // fichier/vue que pour le restaurant.
    'lib/features/hebergement/presentation/widgets/vue_plan_hebergement.dart',
    // Hébergement & Réservations, repris sur la vue le 09/10/2026 (Phase 2) :
    // l'écran (en-tête, onglets, rangée de boutons), le bouton qu'il partage
    // avec le plan, et les trois autres panneaux — réservations en cours,
    // calendrier d'occupation et disponibilités — rendent le CORPS de la page
    // (échelle EFFECTIVE). Les deux modales de l'unité sont dans l'autre camp.
    'lib/features/hebergement/presentation/ecran_hebergement.dart',
    'lib/features/hebergement/presentation/widgets/bouton_hebergement.dart',
    'lib/features/hebergement/presentation/widgets/vue_reservations_en_cours.dart',
    'lib/features/hebergement/presentation/widgets/vue_calendrier_occupation.dart',
    'lib/features/hebergement/presentation/widgets/vue_disponibilites.dart',
    'lib/features/notifications/presentation/ecran_notifications.dart',
    // Personnel & Paie, repris sur la vue le 09/10/2026 : l'écran et les cinq
    // panneaux d'onglet rendent le CORPS de la page (échelle EFFECTIVE) ; les
    // cinq modales sont dans `modales_paie.dart`, classé dans l'autre camp.
    'lib/features/rh/presentation/ecran_paie.dart',
    'lib/features/rh/presentation/widgets/panneaux_paie.dart',
    // Paramètres, repris sur la vue le 08/10/2026 (Phase 2, écran n° 1) : le
    // fichier rend le CORPS de la page ; la fenêtre « Modifier » est une
    // modale, ouverte par `showDialog`, dont le cadre vit dans
    // `cadre_modale_parametre.dart` (classé dans l'autre camp, 15/10/2026).
    'lib/features/parametres/presentation/ecran_parametres.dart',
    // L'onglet « Espaces & tables » (Lot J1, 14/10/2026) : le panneau
    // `@elseif ($onglet === 'tables')` de `transverse/parametres.blade.php`
    // (l.322), dans `<main>` (fermé l.507) — échelle EFFECTIVE.
    'lib/features/parametres/presentation/widgets/onglet_espaces_tables.dart',
    // L'onglet « Synchronisation » (lot F2a, 15/10/2026) : un AJOUT du poste,
    // rendu dans la carte du formulaire de Paramètres comme les autres
    // onglets, donc dans `<main>` — échelle EFFECTIVE.
    'lib/features/parametres/presentation/widgets/onglet_synchronisation.dart',
    // L'onglet « Logo & Apparence » (21/10/2026) : le panneau
    // `@elseif ($onglet === 'apparence')` de la vue de Paramètres, dans
    // `<main>` — échelle EFFECTIVE. Sa modale n'emploie que les styles de
    // `TextesModaleRestaurant`.
    'lib/features/parametres/presentation/widgets/onglet_apparence.dart',
    // L'onglet « Canaux de réservation » et le bouton « Envoyer un email de
    // test » (21/10/2026) : les panneaux `@elseif ($onglet === 'canaux')` et
    // `'email'` de la vue de Paramètres, dans `<main>` — échelle EFFECTIVE.
    'lib/features/parametres/presentation/widgets/onglet_canaux.dart',
    'lib/features/parametres/presentation/widgets/bouton_email_test.dart',
    // Le champ « Mot de passe SMTP » de l'onglet Email (SMTP) (19/10/2026) :
    // le bloc `groupe-champ` du panneau `@elseif ($onglet === 'email')` de
    // la vue de Paramètres, dans `<main>` — échelle EFFECTIVE.
    'lib/features/parametres/presentation/widgets/champ_mot_de_passe_smtp.dart',
    // Inventaires & Fiches de stock, repris sur la vue le 08/10/2026 (Phase 2,
    // écran n° 2) : le fichier rend le CORPS de la page, ses trois onglets
    // compris ; aucune modale n'y est ouverte.
    'lib/features/stocks/presentation/ecran_inventaires.dart',
    // Gestion des Stocks, repris sur la vue le 08/10/2026 (Phase 2, écran
    // n° 7) : corps de page ; ses modales vivent dans `widgets/`.
    'lib/features/stocks/presentation/ecran_stocks.dart',
    // Le tableau des articles (source locale de M6, 09/10/2026) : il rend la
    // table de la page (en-tête navy, cellules, badge de suivi, boutons de
    // ligne) — échelle EFFECTIVE. Les modales d'article, de mouvement et de
    // point vivent dans d'autres fichiers de `widgets/`, hors de `<main>`.
    'lib/features/stocks/presentation/widgets/table_stocks.dart',
    'lib/features/achats/presentation/ecran_approvisionnement.dart',
    'lib/features/achats/presentation/widgets/vue_besoins.dart',
    'lib/features/achats/presentation/widgets/coquille_achats.dart',
    // Fournisseurs & Achats, repris sur la vue le 09/10/2026 (Phase 2) : l'écran
    // (en-tête, onglets, note), la barre d'outils et le tableau communs aux deux
    // onglets, et les deux onglets rendent le CORPS de la page (échelle
    // EFFECTIVE). Les trois modales — formulaire, détail, archivage — sont dans
    // `modale_*.dart`, classées dans l'autre camp.
    'lib/features/achats/presentation/ecran_fournisseurs.dart',
    'lib/features/achats/presentation/widgets/composants_crud_achats.dart',
    'lib/features/achats/presentation/widgets/vue_fournisseurs.dart',
    'lib/features/achats/presentation/widgets/vue_commandes_achats.dart',
    // Règlement fournisseur (12/10/2026, D66) : l'onglet « Dettes Fournisseurs »
    // (cartes, tableau groupé) et les deux bandeaux de la page sont du CORPS de
    // page — échelle EFFECTIVE. La modale « Régler » vit dans `modale_reglement`.
    'lib/features/achats/presentation/widgets/vue_dettes.dart',
    'lib/features/achats/presentation/widgets/bandeaux_appro.dart',
    'lib/features/hebergement/presentation/ecran_reservations.dart',
    // Restaurant & Cuisine, repris sur la vue le 08/10/2026 (Phase 2, écran
    // n° 3) : corps de page, trois onglets, aucune modale propre.
    'lib/features/restaurant/presentation/ecran_restauration.dart',
    // Clients & Créances, repris sur la vue le 08/10/2026 (Phase 2, écran
    // n° 4) : corps de page, quatre onglets ; son tableau vit dans
    // `table_clients.dart`, classé ci-dessous.
    'lib/features/crm/presentation/ecran_clients.dart',
    'lib/features/crm/presentation/widgets/table_clients.dart',
    // Facturation & Caisse MECeF, repris sur la vue le 08/10/2026 (Phase 2,
    // écran n° 5) : corps de page ; le ticket ouvert depuis une ligne est une
    // fenêtre (`vue_ticket.dart`), hors de ce classement.
    'lib/features/facturation/presentation/ecran_facturation.dart',
    // Carte du bar, reprise sur la vue le 08/10/2026 (Phase 2) : corps de
    // page (en-tête, indicateurs, onglets, filtres, bandeaux). Ses modales
    // vivent dans `widgets/modale_*.dart`, classées dans l'autre camp.
    'lib/features/bar/presentation/ecran_carte_bar.dart',
    // Carte du restaurant, reprise sur la vue le 09/10/2026 (Phase 2) : corps
    // de page, trois onglets. Les trois fichiers ci-dessous rendent le CORPS
    // partagé `pwa/carte/corps.blade.php` (dans `<main>`), le premier pour les
    // DEUX cartes, bar et restaurant. Aucune modale propre : les cinq modales
    // de la vue sont refusées (voir l'en-tête de l'écran) et le choix du
    // format d'export vit dans `modale_export_carte.dart`, classé ailleurs.
    'lib/features/restaurant/presentation/ecran_carte_restaurant.dart',
    'lib/features/restaurant/presentation/widgets/corps_carte_commun.dart',
    'lib/features/restaurant/presentation/widgets/vue_couverture.dart',
    // L'onglet « Carte du jour » (`corps.blade.php` l.297-454), dans `<main>` :
    // il emploie `TaillesContenu.t10` pour les deux marques de prix (des `<div>`
    // de 10 px sous le prix, l.355-360). Classé le 09/10/2026, à la livraison de
    // la source locale de M4 qui les rend.
    'lib/features/restaurant/presentation/widgets/vue_carte_du_jour.dart',
    // Panneau « Ventes » des deux cartes, repris sur la vue le 09/10/2026 : le
    // cadre du tableau (`corps.blade.php` l.598-695, commun au bar et au
    // restaurant) et la barre de filtres du restaurant (l.567-596) sont dans
    // `<main>`. Aucune modale.
    'lib/features/restaurant/presentation/widgets/cadre_ventes_carte.dart',
    'lib/features/restaurant/presentation/widgets/vue_ventes_restaurant.dart',
    // Dépense courante, reprise sur la vue le 09/10/2026 (Phase 2) : corps de
    // page (en-tête, bande d'indicateurs, barre de contrôles, tableau). La
    // modale « Nouvelle Dépense » vit dans `modale_depense.dart`, classée dans
    // l'autre camp ; le choix du format d'export est celui du partiel partagé
    // (`modale_export_carte.dart`).
    'lib/features/depenses/presentation/ecran_depenses.dart',
    'lib/features/depenses/presentation/widgets/barre_filtres_depenses.dart',
    'lib/features/depenses/presentation/widgets/table_depenses.dart',
    // POS clients hébergés, repris sur la vue le 09/10/2026 (Phase 2) : l'écran
    // (en-tête, indicateurs, colonne des séjours), la colonne catalogue et la
    // colonne panier sont dans `<main>` de `pos/heberges.blade.php`
    // (l.56-278). La modale de clôture (l.291-369) est posée après `</main>` :
    // elle vit dans `modale_cloture_sejour.dart`, classé dans l'autre camp.
    'lib/features/pos/presentation/ecran_pos_heberges.dart',
    'lib/features/pos/presentation/widgets/catalogue_heberges.dart',
    'lib/features/pos/presentation/widgets/panier_heberges.dart',
    // Barre de session de caisse du POS comptant (12/10/2026) : la bande
    // `px-5 py-2.5 border-b` est le PREMIER enfant de `<main>` de
    // `pos/comptant.blade.php` (l.74-152). Ses deux modales (l.638-700) sont
    // posées après `</main>` : elles vivent dans `modale_ouverture_caisse.dart`
    // et `modale_cloture_caisse.dart`, classés dans l'autre camp.
    'lib/features/caisse/presentation/widgets/barre_session_caisse.dart',
    // POS au comptant en trois colonnes (14/10/2026, lots A–D) : l'écran, le
    // catalogue, le panier et la salle sont dans `<main>` de
    // `pos/comptant.blade.php` ; ses modales de caisse sont classées dans
    // l'autre camp.
    'lib/features/pos/presentation/ecran_pos_comptant.dart',
    'lib/features/pos/presentation/widgets/vue_catalogue.dart',
    'lib/features/pos/presentation/widgets/vue_panier.dart',
    'lib/features/pos/presentation/widgets/vue_salle.dart',
    // Le tableau « Réservations du jour » de l'accueil (l.432-541, dans
    // `<main>` de `livewire/accueil.blade.php`, lot C du 14/10/2026). Ses
    // modales vivent dans `champs_modale_accueil.dart`, classé hors.
    'lib/features/tableau_de_bord/presentation/widgets/reservations_du_jour.dart',
    // Les écrans portés le 14/10/2026 (PA-204, D417–D423) : corps de page,
    // dans le `<main>` de leur vue (`comptabilite/hub`, `transverse/*`).
    'lib/features/comptabilite/presentation/ecran_comptabilite.dart',
    'lib/features/comptabilite/presentation/widgets/onglets_etats_financiers.dart',
    // Onglets « Grand livre » et « Analytique » (26/10/2026) : corps de page,
    // dans le `<main>` de `comptabilite/hub`.
    'lib/features/comptabilite/presentation/widgets/onglets_grand_livre_analytique.dart',
    // Onglets « Plan comptable » et « Clôtures » (21/10/2026) : corps de page,
    // dans le `<main>` de `comptabilite/hub` ; leurs modales sont dans
    // `modales_hub_comptabilite.dart`, classé dans l'autre camp.
    'lib/features/comptabilite/presentation/widgets/onglets_plan_clotures.dart',
    // Onglet « Immobilisations » (21/10/2026) : corps de page, dans le `<main>`
    // de `comptabilite/hub` ; ses modales sont dans `modales_immobilisations.dart`.
    'lib/features/comptabilite/presentation/widgets/onglet_immobilisations.dart',
    'lib/features/transverse/presentation/ecran_aide_a_propos.dart',
    'lib/features/transverse/presentation/ecran_contact_editeur.dart',
    'lib/features/transverse/presentation/ecran_import_export.dart',
    'lib/features/transverse/presentation/ecran_journal_audit.dart',
    'lib/features/transverse/presentation/ecran_mon_profil.dart',
    'lib/features/transverse/presentation/ecran_roles_permissions.dart',
    'lib/features/transverse/presentation/widgets/briques_transverses.dart',
    // « Synchroniser les postes » (18/10/2026, décision PO) : corps de page,
    // dans le `<main>` de `transverse/synchronisation-postes`.
    'lib/features/synchronisation/presentation/ecran_synchronisation_postes.dart',
    // « Comptes utilisateurs » (Lot J2, AJOUT du PO du 14/10/2026, aucune vue)
    // : une page sous la coquille, rendue comme ses voisines transverses dans
    // le contenu de page — échelle EFFECTIVE. Ses modales sont dans
    // `modales_comptes.dart`, classé dans l'autre camp.
    'lib/features/transverse/presentation/ecran_comptes_utilisateurs.dart',
    // L'écran « Synchronisation » (lot F2b, AJOUT du PO du 15/10/2026, aucune
    // vue) : une page sous la coquille, bâtie des briques transverses, sans
    // modale — échelle EFFECTIVE.
    'lib/features/synchronisation/presentation/ecran_synchronisation.dart',
    // La partie « Réception » de ce même écran (26/10/2026, AJOUT du PO, aucune
    // vue) : ses cartes, compteurs, filtres et liste sont des corps de page —
    // échelle EFFECTIVE. Ses modales sont dans `modales_reception.dart`.
    'lib/features/synchronisation/presentation/partie_reception.dart',
    // Le bouton standard (D432, 14/10/2026) : barres d'action des pages, dans
    // `<main>` — `text-[13px]` y rend 12,5. Une modale lui passe `Tailles.t13`.
    'lib/shared_widgets/bouton_standard.dart',
  };

  /// Rendu **hors** du contenu de page. Échelle déclarée. Chaque entrée porte
  /// sa raison : sans elle, la liste redeviendrait un décret.
  const horsContenuDePage = <String, String>{
    'lib/core/navigation/actualisation_ecran.dart':
        'Menu contextuel « Actualiser » (demande du PO du 26/10/2026) : une '
        'surcouche du châssis, posée au-dessus de la page, hors `<main>`.',
    'lib/core/router/coquille_application.dart':
        'Châssis. `#shell-topbar`, `#shell-banniere` et `#shell-sidebar` sont '
        'des frères de `<main>` dans chaque page sous coquille.',
    'lib/features/auth/presentation/ecran_connexion.dart':
        '`livewire/connexion.blade.php` est l une des deux seules pages sans '
        '`<main>`.',
    'lib/features/auth/presentation/ecran_demarrage.dart':
        '`demarrage.blade.php` est la seconde page sans `<main>`.',
    'lib/features/auth/presentation/formulaire_premier_compte.dart':
        'Rendu par l écran de connexion, donc hors `<main>` comme lui.',
    'lib/features/ventes/presentation/widgets/dialogue_detail_vente.dart':
        'Modale. Les conteneurs de modales des vues sont hors `</main>`.',
    'lib/features/facturation/presentation/widgets/vue_ticket.dart':
        'Modale — ouverte par `showDialog` dans `afficherTicket`.',
    'lib/features/facturation/presentation/widgets/dialogue_avoir.dart':
        'Modale — `AlertDialog` d annulation par avoir, hors `<main>`.',
    'lib/features/restaurant/presentation/widgets/textes_modale_restaurant.dart':
        'Modales. Celles de `restaurant/restauration.blade.php` et de '
        '`carte/corps.blade.php` sont posées après `</main>` : le remappage '
        'ne les atteint pas. Ce fichier ne porte QUE ces styles-là, '
        'précisément pour que la frontière de la vue soit une frontière de '
        'fichiers.',
    'lib/features/depenses/presentation/widgets/modale_depense.dart':
        'Modale. Le formulaire de `depenses/depenses.blade.php` (`<x-pwa.modale>`, '
        'l.324-511) est posé après `</main>` : le remappage typographique ne '
        'l atteint pas.',
    'lib/features/hebergement/presentation/widgets/modale_unite.dart':
        'Modale de création et d édition d une unité, hors `</main>` dans '
        '`hebergement/plan.blade.php`.',
    'lib/features/hebergement/presentation/widgets/modale_archivage_unite.dart':
        'Modale de confirmation d archivage, posée avec la précédente hors '
        '`</main>`.',
    'lib/features/rh/presentation/widgets/modales_paie.dart':
        'Modales de la paie — fiche employé, établissement, annulation, '
        'archivage et bulletin (cinq `<x-pwa.modale>` de `rh/paie.blade.php`, '
        'toutes hors `</main>`). Ce fichier ne porte QUE leurs styles, pour '
        'que la frontière de la vue reste une frontière de fichiers.',
    'lib/features/pos/presentation/widgets/modales_comptant.dart':
        'Modales de `pos/comptant.blade.php` — « Vente encaissée », journal '
        'du jour, annulation, « Stock insuffisant » —, toutes posées après '
        '`</main>` : le remappage typographique ne les atteint pas.',
    'lib/features/pos/presentation/widgets/modale_cloture_sejour.dart':
        'Modale « Clôturer avant le départ ? » de `pos/heberges.blade.php` '
        '(`<x-pwa.modale>`, l.291-369), posée après `</main>` : le remappage '
        'typographique ne l atteint pas.',
    'lib/features/caisse/presentation/widgets/modale_ouverture_caisse.dart':
        'Modale « Ouvrir la caisse » de `pos/comptant.blade.php` '
        '(`<x-pwa.modale>`, l.638-660), posée après `</main>` : le remappage '
        'typographique ne l atteint pas.',
    'lib/features/crm/presentation/widgets/modale_recouvrement.dart':
        'Modale « Ajouter un recouvrement » de `crm/clients-creances.blade.php` '
        '(`<x-pwa.modale>`, après `</main>` l.594) : le remappage typographique '
        'ne l atteint pas.',
    'lib/features/crm/presentation/widgets/modale_historique_client.dart':
        'Modale « Historique d un client » de `crm/clients-creances.blade.php` '
        '(`<x-pwa.modale>`, après `</main>` l.594) : le remappage '
        'typographique ne l atteint pas.',
    'lib/features/crm/presentation/widgets/modale_relance.dart':
        'Modale « Tracer une relance » de `crm/clients-creances.blade.php` '
        '(`<x-pwa.modale>`, après `</main>` l.594) : le remappage '
        'typographique ne l atteint pas.',
    'lib/features/crm/presentation/dialogue_nouveau_client.dart':
        'Modale « Ajouter un client » de `hebergement/reservations.blade.php` '
        '(`<x-pwa.modale>`, l.745-784), posée après `</main>` (l.341) : le '
        'remappage typographique ne l atteint pas.',
    'lib/features/hebergement/presentation/widgets/modale_reservation_rapide.dart':
        'Modale « Réservation rapide » de `hebergement/hebergement.blade.php` '
        '(`<x-pwa.modale>`, l.560-628), posée hors `</main>` : le remappage '
        'typographique ne l atteint pas.',
    'lib/features/hebergement/presentation/widgets/modale_annulation_reservation.dart':
        'Modale « Annuler la réservation » de `hebergement/reservations.blade.php` '
        '(`<x-pwa.modale>`, l.793-879), posée après `</main>` (l.341) : le '
        'remappage typographique ne l atteint pas.',
    'lib/features/caisse/presentation/widgets/modale_cloture_caisse.dart':
        'Modale « Clôturer la caisse » de `pos/comptant.blade.php` '
        '(`<x-pwa.modale>`, l.660-700), posée après `</main>`.',
    'lib/features/achats/presentation/widgets/modale_fournisseur.dart':
        'Modale « Nouveau fournisseur » / « Modifier le fournisseur » de '
        '`achats/achats.blade.php` (`<x-pwa.modale>`, l.425-498), posée après '
        '`</main>` : le remappage typographique ne l atteint pas.',
    'lib/features/achats/presentation/widgets/modale_detail_fournisseur.dart':
        'Modale « Détail — » de `achats/achats.blade.php` (`<x-pwa.modale>`, '
        'l.395-423), posée après `</main>`.',
    'lib/features/achats/presentation/widgets/modale_archivage_achats.dart':
        'Modale de confirmation d archivage (`<x-pwa.modale-archivage>`, '
        'l.504-511), posée après `</main>`.',
    'lib/features/stocks/presentation/widgets/modales_inventaire.dart':
        'Modales « Enregistrer le comptage » et « Inventaire incomplet » de '
        '`stocks/inventaires.blade.php` (`<x-pwa.modale>`, l.674-714), posées '
        'après `</main>` : le remappage typographique ne les atteint pas.',
    'lib/features/tableau_de_bord/presentation/widgets/modale_stocks_critiques.dart':
        'Modale « Articles sous le seuil d alerte » de la vue d accueil '
        '(`<x-pwa.modale>`, l.1689-1719), posée après `</main>` (l.1392) : le '
        'remappage typographique ne l atteint pas.',
    'lib/core/router/panneau_acces_rapide.dart':
        'Châssis. Le bouton flottant et le panneau « Accès rapides » '
        '(`partials/acces-rapide`) sont inclus APRÈS `</main>` dans les onze '
        'vues qui les portent (ex. `livewire/accueil.blade.php` l.1752, '
        '`</main>` l.1392) : le remappage typographique ne les atteint pas.',
    'lib/features/alertes/presentation/cloche_notifications.dart':
        'Châssis. La cloche et son panneau vivent dans la barre supérieure '
        '(`partials/barre-superieure`, frère de `<main>`), lot B du 14/10/2026.',
    'lib/features/comptabilite/presentation/widgets/selecteur_exercice_barre.dart':
        'Châssis. Le sélecteur d exercice global (ajout du PO du 20/10/2026, '
        '`<livewire:pwa.selecteur-exercice />`) vit dans la barre supérieure, '
        'après la recherche, frère de `<main>` : échelle déclarée.',
    'lib/features/synchronisation/presentation/bouton_synchronisation.dart':
        'Châssis. Le bouton de synchronisation (ajout du PO du 16/10/2026, lot '
        'F3) vit dans la barre supérieure à côté de la cloche, et sa modale '
        'est posée hors `<main>` : échelle déclarée.',
    'lib/features/recherche_globale/presentation/recherche_globale_barre.dart':
        'Châssis. `<livewire:pwa.recherche-globale />` est posée dans la barre '
        'supérieure (`partials/barre-superieure` l.162), hors `<main>`.',
    'lib/features/tableau_de_bord/presentation/widgets/champs_modale_accueil.dart':
        'Modales de l accueil (check-in, check-out, payer, client et '
        'réservation rapides) : `<x-pwa.modale>` posées après `</main>` '
        '(l.1392) de `livewire/accueil.blade.php`.',
    'lib/features/tableau_de_bord/presentation/widgets/modales_rapides_accueil.dart':
        'Modales rapides de l accueil, posées après `</main>` (l.1392).',
    'lib/features/tableau_de_bord/presentation/widgets/modale_rapport_accueil.dart':
        'Modale « Générer un rapport » de l accueil, posée après `</main>`.',
    'lib/features/stocks/presentation/widgets/modale_import_articles.dart':
        'Modale « Importer des articles » de `stocks/stocks.blade.php` '
        '(`etatFormulaire === import`, l.746-775), posée après `</main>`.',
    'lib/features/stocks/presentation/widgets/modale_article.dart':
        'Modale « Nouvel article » / « Modifier l article » de '
        '`stocks/stocks.blade.php`, posée après `</main>`.',
    'lib/features/bar/presentation/widgets/modale_export_carte.dart':
        'Modale d export de la carte du bar, posée après `</main>` de '
        '`carte/corps.blade.php`.',
    'lib/features/crm/presentation/widgets/barre_exports_clients.dart':
        'Pied de la modale d export des clients (`crm/clients-creances`), '
        'posée après `</main>`.',
    'lib/features/transverse/presentation/widgets/modales_roles.dart':
        'Modales de `transverse/roles-permissions` (nouveau rôle, droits, '
        'rétablir le socle), posées après `</main>`.',
    // Lots J1/J2 (14/10/2026), classés le 15/10/2026.
    'lib/features/comptabilite/presentation/widgets/modale_ecriture.dart':
        'Modale « Passer une écriture » : `<x-pwa.modale>` '
        '`comptabilite_pwa.modale_piece_titre` de `comptabilite/hub.blade.php` '
        '(l.292), posée après `</main>` (l.283). Rendue sur l échelle '
        'effective jusqu au 15/10/2026 : ramenée à la déclarée.',
    'lib/features/comptabilite/presentation/widgets/modales_etats_comptables.dart':
        'Fenêtres « Tableau des flux de trésorerie », « Notes annexes » et '
        '« États financiers » (pages séparées de la vue, ouvertes depuis les '
        'tuiles du hub par `showDialog`) : des fenêtres, hors du contenu de '
        'page.',
    'lib/features/comptabilite/presentation/widgets/modales_immobilisations.dart':
        'Modales « Nouvelle immobilisation » et « Plan » de '
        '`comptabilite/hub.blade.php` (`<x-pwa.modale>`, `etatFormulaire` '
        '`immo` et `planAmortissement`), posées après `</main>`.',
    'lib/features/comptabilite/presentation/widgets/modales_hub_comptabilite.dart':
        'Modales « Créer un compte » et « Ouvrir un exercice » de '
        '`comptabilite/hub.blade.php` (`<x-pwa.modale>`, `etatFormulaire` '
        '`compte` et `exercice`), posées après `</main>` : le remappage '
        'typographique ne les atteint pas.',
    'lib/features/parametres/presentation/widgets/cadre_modale_parametre.dart':
        'Fenêtre « Modifier » de Paramètres (compacte, PO du 14/10/2026), '
        'ouverte par `showDialog` : une modale, hors du contenu de page.',
    'lib/features/synchronisation/presentation/modales_reception.dart':
        'Détail, « Corriger » et formulaire de correction de la charge de '
        'l\'écran de synchronisation (ajout du PO du 26/10/2026, sans vue) : '
        'des fenêtres ouvertes par `showDialog`, hors du contenu de page.',
    'lib/features/transverse/presentation/widgets/modales_comptes.dart':
        'Modales de « Comptes utilisateurs » (ajout du PO du 14/10/2026, sans '
        'vue) : des fenêtres ouvertes par `showDialog`, hors du contenu de '
        'page, comme toutes les modales de la vue.',
    'lib/features/transverse/presentation/widgets/modales_contact_editeur.dart':
        'Modales « Envoyer un message » et « Signaler un bug » de '
        '`transverse/contact-editeur.blade.php` (`<x-pwa.modale>`, l.130 et '
        'l.155), posées après `</main>` (l.125).',
    'lib/features/depenses/presentation/widgets/modale_comptabiliser_depense.dart':
        'Fenêtre « Comptabiliser la dépense » (PO, 14/10/2026), qui remplace '
        'la bande jaune du contenu de page : une modale ouverte par '
        '`showDialog`, hors du contenu. Rendue sur l échelle effective '
        'jusqu au 15/10/2026 : ramenée à la déclarée.',
    'lib/shared_widgets/modale_export.dart':
        'Le partiel `pwa.partials.modale-export`, inclus après `</main>` par '
        'chaque vue qui l ouvre : le remappage typographique ne l atteint pas.',
  };

  /// Les paliers s'écrivent `Tailles.tNN` et `TaillesContenu.tNN`.
  ///
  /// Aucune expression régulière ici, et c'est délibéré : le shell de cet
  /// environnement replie les antislashs doublés, une limite de mot devient
  /// l'octet 0x08 et le motif ne correspond plus à rien — trois occurrences
  /// réelles dans ce dépôt (piège 4). `Tailles.t` n'est pas un préfixe de
  /// `TaillesContenu.t` : après `Tailles` vient un `C`, jamais un point. Deux
  /// `contains` suffisent, et ils ne peuvent pas se vider en silence.
  const jetonDeclare = 'Tailles.t';
  const jetonEffectif = 'TaillesContenu.t';

  int occurrences(String source, String motif) =>
      source.split(motif).length - 1;

  List<File> fichiersDeLib() {
    final racine = Directory('lib');
    if (!racine.existsSync()) {
      fail(
        'Le répertoire `lib/` est introuvable depuis ${Directory.current.path}.',
      );
    }
    return racine
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('.g.dart'))
        .toList();
  }

  /// Windows rend `lib\core\theme\…`. Le séparateur est désigné par son code
  /// plutôt qu'écrit en clair — un antislash littéral est précisément ce que
  /// le piège 4 transforme en octet de contrôle au passage d'un script.
  final separateurWindows = String.fromCharCode(92);
  String normaliser(File f) => f.path.replaceAll(separateurWindows, '/');

  // =========================================================================
  group('La vue Blade ancre la frontière', () {
    test('le remappage existe, et sa portée est bien `main`', () {
      final css = feuilleServie('le remappage typographique');

      final remaps = css
          .split('\n')
          .where((l) => l.trimLeft().startsWith('main .text-'))
          .toList();
      expect(
        remaps.length,
        greaterThanOrEqualTo(18),
        reason:
            'Seules ${remaps.length} règles `main .text-…` trouvées dans la '
            'feuille servie. Le remappage a été retiré ou sa portée élargie : '
            'les deux échelles de ce dépôt n ont plus de fondement, et tous '
            'les contrôles ci-dessous porteraient sur une distinction '
            'imaginaire.',
      );

      // La règle qui porte la classe la plus employée des vues.
      final ligne13 = remaps.singleWhere(
        (l) => l.contains('13px') && l.contains('font-size:'),
        orElse: () => fail(
          'Aucune règle ne remappe `text-[13px]` dans `main`. C est la classe '
          'la plus employée : sans elle, `TaillesContenu` ne décrirait plus '
          'rien.',
        ),
      );
      final valeur = double.parse(
        ligne13.split('font-size:')[1].split('px')[0].trim(),
      );
      expect(
        valeur,
        TaillesContenu.t13,
        reason:
            'La feuille servie remappe `text-[13px]` à $valeur px, quand '
            '`TaillesContenu.t13` vaut ${TaillesContenu.t13}.',
      );
      expect(
        valeur,
        isNot(Tailles.t13),
        reason:
            'La feuille ne remappe plus `text-[13px]` : les deux échelles se '
            'confondent, et la frontière que cette garde tient n a plus '
            'd objet. Ce n est pas une réussite, c est une perte de sens — '
            'rouvrez la question au lieu de supprimer le contrôle.',
      );
    });

    test('la connexion et le démarrage sont les 2 seules pages sans `main`', () {
      final sans = <String>[];
      for (final page in pages.toutes) {
        if (!deplier(page).contains('<main')) sans.add(page);
      }
      sans.sort();
      expect(
        sans,
        horsCoquille,
        reason:
            'Les pages hors `<main>` ont changé : $sans. '
            '`ecran_connexion.dart` et `ecran_demarrage.dart` sont classés '
            'hors contenu POUR CETTE RAISON. Si elle a cessé d être vraie, la '
            'classification est devenue un oubli, pas une décision (PA-144).',
      );
    });

    test('aucun conteneur de modale n est dans `main`', () {
      // On ne cherche pas deux identifiants connus : on relève TOUT conteneur
      // de modale de la PWA — le cadre `<x-pwa.modale>`, les composants
      // `<x-pwa.modale-*>`/`<x-pwa.modal-*>`, les partiels `modale-*` et les
      // modales écrites à la main (`overlay-modale`) —, à sa place dans la
      // page dépliée. Une liste d'identifiants aurait manqué les suivants, et
      // se serait vidée au premier renommage — en restant verte.
      final conteneur = RegExp(
        r'<x-pwa\.modale\b|<x-pwa\.modale?-[a-z\-]+|'
        r'<!--INCLUS:pwa\.partials\.modale[a-z\-]*-->|'
        r'class="[^"]*\boverlay-modale\b',
      );
      var vus = 0;
      final dedans = <String>[];
      for (final page in pages.sousCoquille) {
        final html = deplier(page);
        final finMain = html.lastIndexOf('</main>');
        if (finMain < 0) continue;
        for (final m in conteneur.allMatches(html)) {
          vus++;
          if (m.start < finMain) {
            final extrait = m[0]!.length > 40 ? m[0]!.substring(0, 40) : m[0]!;
            dedans.add('$page — $extrait');
          }
        }
      }
      // Mesuré le 10/09/2026 (PA-183) : 133 conteneurs sur les 41 pages sous
      // coquille. Plancher posé dessous.
      expect(
        vus,
        greaterThanOrEqualTo(120),
        reason:
            'Seuls $vus conteneurs de modale repérés dans les vues. La '
            'convention a changé : ce contrôle ne regarde plus rien, et il '
            'serait vert.',
      );
      expect(
        dedans,
        isEmpty,
        reason:
            'Sur $vus conteneurs de modale relus, ${dedans.length} sont DANS '
            '`<main>` : ils subissent donc le remappage, et les fichiers de '
            'modale de ce dépôt sont classés sur l échelle déclarée à tort.\n'
            '${dedans.join('\n')}',
      );
    });

    test('la barre latérale est ramenée à sa taille déclarée', () {
      final css = feuilleServie('la règle de la barre latérale');
      expect(
        css.contains('#shell-sidebar .lien-sidebar'),
        isTrue,
        reason:
            'La règle qui ramène le menu à 14 px a disparu de la feuille '
            'servie. C est elle qui justifie que le châssis reste sur '
            'l échelle déclarée alors même qu il borde le contenu.',
      );
    });
  });

  group('Le portage respecte la frontière', () {
    test('chaque fichier qui emploie un palier est classé, dans un camp', () {
      final fichiers = fichiersDeLib();
      expect(
        fichiers.length,
        greaterThanOrEqualTo(150),
        reason:
            'Seuls ${fichiers.length} fichiers Dart relus. Un répertoire a été '
            'renommé : le balayage est devenu creux, donc vert.',
      );

      final defauts = <String>[];
      var sitesDeclares = 0;
      var sitesEffectifs = 0;
      final contenuVus = <String>{};
      final horsVus = <String>{};

      for (final f in fichiers) {
        final chemin = normaliser(f);
        // Le fichier des jetons les DÉFINIT ; sa doc les cite. Ce n est pas un
        // lieu de rendu.
        if (chemin.startsWith('lib/core/theme/')) continue;
        final source = f.readAsStringSync();

        final nDeclare = occurrences(source, jetonDeclare);
        final nEffectif = occurrences(source, jetonEffectif);
        if (nDeclare == 0 && nEffectif == 0) continue;

        sitesDeclares += nDeclare;
        sitesEffectifs += nEffectif;

        final estContenu = contenuDePage.contains(chemin);
        final estHors = horsContenuDePage.containsKey(chemin);

        if (!estContenu && !estHors) {
          defauts.add(
            '$chemin — emploie un palier typographique sans être classé. '
            'Décidez : ce qu il rend est-il dans le `<main>` de sa vue Blade '
            '(échelle EFFECTIVE, `TaillesContenu`) ou hors de lui — châssis, '
            'connexion, démarrage, modale (échelle DÉCLARÉE, `Tailles`) ?',
          );
          continue;
        }
        if (estContenu && estHors) {
          defauts.add('$chemin — classé dans les DEUX camps.');
          continue;
        }

        if (estContenu) {
          contenuVus.add(chemin);
          if (nDeclare > 0) {
            defauts.add(
              '$chemin — écran de CONTENU, mais $nDeclare palier(s) sur '
              'l échelle DÉCLARÉE. Dans un `<main>`, la PWA rend 12,5 px là '
              'où la classe dit 13 : employez `TaillesContenu`.',
            );
          }
        } else {
          horsVus.add(chemin);
          if (nEffectif > 0) {
            defauts.add(
              '$chemin — rendu HORS du contenu de page '
              '(${horsContenuDePage[chemin]}), mais $nEffectif palier(s) sur '
              'l échelle EFFECTIVE. Le remappage de la feuille servie ne l '
              'atteint pas : employez `Tailles`.',
            );
          }
        }
      }

      expect(defauts, isEmpty, reason: defauts.join('\n'));

      // -------------------------------------------------------- les planchers
      expect(
        sitesDeclares + sitesEffectifs,
        greaterThanOrEqualTo(55),
        reason:
            'Seuls ${sitesDeclares + sitesEffectifs} paliers typographiques '
            'rencontrés dans `lib/`, contre 62 mesurés le 26/08/2026. Les '
            'jetons ont été renommés, ou remplacés par des valeurs en dur : ce '
            'balayage ne regarde plus le portage.',
      );
      expect(
        sitesEffectifs,
        greaterThanOrEqualTo(13),
        reason:
            'Seuls $sitesEffectifs paliers sur l échelle effective, contre 13 '
            'à la bascule du 26/08/2026. Elle a été défaite.',
      );
      expect(
        contenuVus.length,
        greaterThanOrEqualTo(4),
        reason:
            'Seuls ${contenuVus.length} fichiers de contenu rencontrés sur '
            '${contenuDePage.length} déclarés. La liste est devenue plus large '
            'que la réalité : elle nomme des fichiers qui n existent plus, et '
            'ne protège plus rien.',
      );
      expect(
        horsVus.length,
        greaterThanOrEqualTo(7),
        reason:
            'Seuls ${horsVus.length} fichiers hors contenu rencontrés, contre '
            '${horsContenuDePage.length} déclarés.',
      );
    });

    test('les deux jetons se distinguent réellement', () {
      // Sans ce cas, tout le balayage reposerait sur une supposition : que
      // `Tailles.t` ne mord pas sur `TaillesContenu.t`. S il mordait, chaque
      // écran de contenu serait compté comme employant AUSSI l échelle
      // déclarée, et la suite crierait à tort — jusqu à être désactivée.
      expect(occurrences('fontSize: TaillesContenu.t13', jetonDeclare), 0);
      expect(occurrences('fontSize: TaillesContenu.t13', jetonEffectif), 1);
      expect(occurrences('fontSize: Tailles.t13', jetonDeclare), 1);
      expect(occurrences('fontSize: Tailles.t13', jetonEffectif), 0);
      // Et les membres qui ne sont pas des paliers ne sont comptés nulle part.
      expect(occurrences('Tailles.lienSidebar', jetonDeclare), 0);
      expect(occurrences('Tailles.interligneSerre', jetonDeclare), 0);
    });
  });
}
