// Vue Blade maîtresse (PA-183) : pwa/etats/studio.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import 'widgets/barre_outils_etats.dart';
import 'widgets/catalogue_etats_vue.dart';
import 'widgets/panneau_apercu_etat.dart';

/// L'écran **États & Rapports** — `pwa/etats/studio.blade.php`.
///
/// @see EF-M14-01 En-tête normalisée (RG-19)
/// @see EF-M14-02 Bibliothèque d'états standards par module
/// @see EF-M14-03 Génération à la demande avec filtres dynamiques
/// @see EF-M14-06 Archivage horodaté
///
/// Reprise sur la vue Blade le 09/10/2026 (D48). L'ancienne version suivait
/// `prototype_v2/pages/m14-etats-studio.html`, archivé (PA-183) : elle rendait
/// trois boutons d'export, une phrase de refus de la période et un panneau de
/// cinq refus que la vue n'a plus.
///
/// ## Structure de la vue, reprise bloc pour bloc
///
/// 1. barre d'outils (l.40-58) : icône, titre, filet — [BarreOutilsEtats] ;
/// 2. `<aside>` du catalogue de 330 px (l.63-115) : recherche, pastilles de
///    module, liste groupée, compteur — [CatalogueEtatsVue] ;
/// 3. `<section>` d'aperçu (l.118-204) : accueil ou aperçu —
///    [PanneauApercuEtat].
///
/// ## L'écran ne calcule rien lui-même
///
/// Les chiffres viennent de `EtatsApi.apercu`, qui relit les dépôts des modules
/// sources (`apercus_etats.dart`) : une fonction pure par état, jamais une
/// formule écrite dans un widget. Aucune ligne de cet écran ne compose un
/// en-tête de rapport — c'est la non-conformité n° 1 de
/// `RESPECT_TABLEAU_RAPPORT.md` §4 — et il ne produit aucun document.
///
/// ## Les droits sont portés par le MODULE SOURCE
///
/// Éditer l'état des stocks exige un droit sur M6, pas sur M14. Le catalogue
/// est donc le registre fermé de M14 filtré par le droit de lecture sur le
/// module source de chaque état (`EtatsApi.catalogue`), et `apercu` le
/// revérifie.
///
/// ## M14 est LOCAL depuis le 10/10/2026
///
/// Jusqu'au 14/09/2026 l'écran appelait le serveur ; il a ensuite servi un
/// refus (« donnée non disponible »). Il calcule désormais l'aperçu de chaque
/// état dont toutes les sources sont détenues ET écrites sur ce poste (dix sur
/// douze). Les deux autres (créances clients, balance) restent LISTÉS, avec la
/// raison datée de leur refus. Aucune table, aucun cache : chaque sélection
/// relit les modules (PA-120).
///
/// ## Ce que la vue fait et que cet écran ne fait pas
///
/// | Élément de la vue | État ici |
/// |---|---|
/// | Barre d'outils (icône, titre, filet) | rendue |
/// | Catalogue, recherche, pastilles de module, compteur | rendus |
/// | Accueil (titre, décompte, note des droits) | rendu, au mot |
/// | Indicateurs et tableau de l'aperçu | rendus pour 10 états sur 12 ; raison datée pour les 2 autres |
/// | « Période », « Exercice », « Imprimer », « Excel », « PDF » | absents de la vue elle-même |
///
/// Les exports sont absents de la vue par décision du Product Owner : ils ne
/// sont pas rendus ici non plus. L'export PDF A4 réel relève de PA-192.
class EcranEtats extends ConsumerWidget {
  const EcranEtats({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `flex-col lg:flex-row` (l.72). La décision se prend sur la largeur de
    // l'ÉCRAN, jamais sur celle du contenu : la barre latérale déployée
    // fausserait tout (Article 5, défaut de responsive n° 1).
    final large = MediaQuery.sizeOf(context).width >= AppBreakpoints.lg;

    return Column(
      children: [
        const BarreOutilsEtats(),
        Expanded(
          child: large
              ? const Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      // `lg:w-[330px] shrink-0` (l.74).
                      width: AppLayout.catalogueEtats,
                      child: CatalogueEtatsVue(),
                    ),
                    Expanded(child: PanneauApercuEtat()),
                  ],
                )
              // `w-full` en colonne : le catalogue prend sa hauteur naturelle
              // (il n'a pas de `flex-1` au maître dans ce sens), l'aperçu
              // occupe le reste. `Flexible` en `loose` traduit exactement ce
              // `flex: 0 1 auto` — un `Expanded` forcerait un partage à parts
              // égales que le maître ne fait pas.
              : const Column(
                  children: [
                    Flexible(fit: FlexFit.loose, child: CatalogueEtatsVue()),
                    Expanded(child: PanneauApercuEtat()),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Le filet vertical qui sépare le catalogue de l'aperçu — `border-r
/// border-slate-200` (l.74).
///
/// Rendu par le catalogue lui-même, comme au maître : c'est l'`<aside>` qui
/// porte la bordure, pas la section voisine. Le maître la garde **aussi en
/// colonne**, où elle se voit à droite de la liste ; la retirer serait
/// harmoniser silencieusement une incohérence du maître (Article 1,
/// interdit 10).
const BoxDecoration bordureCatalogueEtats = BoxDecoration(
  color: AppColors.neutre0,
  border: Border(right: BorderSide(color: Ardoise.c200)),
);
