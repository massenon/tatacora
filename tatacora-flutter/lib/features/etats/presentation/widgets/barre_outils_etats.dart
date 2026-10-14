import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import 'textes_etats.dart';

/// La barre d'outils du studio — `pwa/etats/studio.blade.php` l.40-58.
///
/// Ordre de la vue, de gauche à droite : icône, titre (`pwa.etats.titre`),
/// filet vertical, puis un poussoir d'espace (`flex-1`). **Rien d'autre**, et
/// c'est le point de cette reprise (09/10/2026, D48).
///
/// ## Ce que cette barre ne porte plus, et pourquoi
///
/// ÉCART DÉLIBÉRÉ, DÉCISION DU PRODUCT OWNER — `studio.blade.php` l.50-55 et
/// `App\Pwa\Livewire\Etats\EtatsStudio` (docblock, jetons `maitre-refuse:
/// …#periode`, `#exports`, `#impression`).
/// La vue : n'affiche ni « Période » (deux champs de date et « Exercice »), ni
/// « Imprimer », « Excel » ou « PDF ». Les contrôles sont ABSENTS, pas grisés
/// (Article 3.3).
/// Ici : même chose. L'ancienne version de cet écran rendait les trois boutons
/// d'export et une phrase de refus de la période ; les deux sont retirés.
/// Raisons, vérifiées le 09/10/2026 : (1) la période — aucun des trois états
/// du registre serveur ne lit de plage de dates (`EtatStocks` lit `point_id` et
/// `sous_seuil`, `EtatParcVehicules` `categorie` et `statut`,
/// `EtatTableauDeBord` un CODE de période) ; envoyer `debut`/`fin` ferait
/// inscrire au journal d'audit un filtre que le document n'a pas appliqué.
/// (2) les exports — la vue les refuse tant que le Product Owner n'a pas
/// tranché `LARAVEL_PWA.md` §2, puisque la génération ÉCRIT dans
/// `etats_generes` (EF-M14-06). Et ce poste ne les honorerait pas : il compose
/// l'APERÇU des états (10/10/2026) mais ne produit aucun document — ni
/// en-tête normalisée ni archivage, qui sont au serveur. Le client suit la vue : un bouton que le maître n'a pas ne
/// se rajoute pas de son propre chef, et un bouton qui ne produirait rien
/// serait inerte (Article 3.3). L'export PDF A4 réel relève de PA-192, pas de
/// ce lot.
class BarreOutilsEtats extends StatelessWidget {
  const BarreOutilsEtats({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      // `px-5 py-3 border-b border-slate-200 bg-white` (l.41).
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.mdPlus,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        color: AppColors.neutre0,
        border: Border(bottom: BorderSide(color: Ardoise.c200)),
      ),
      // `flex flex-wrap items-center gap-2.5` (l.42).
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.xsPlus,
        runSpacing: AppSpacing.xsPlus,
        children: [
          // `flex items-center gap-2.5 mr-2` (l.43).
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ÉCART DÉLIBÉRÉ — `studio.blade.php` l.44.
                // La vue : un SVG tracé à la main — une feuille cornée portant
                // trois lignes de texte.
                // Ici : `Icons.description_outlined`, la feuille cornée à
                // lignes de la bibliothèque déjà employée par le châssis.
                // Raison : ce dépôt ne transporte aucun SVG, et redessiner le
                // tracé en `CustomPainter` pour une icône de 20 px
                // introduirait un chemin à maintenir sans rien changer de ce
                // que l'utilisateur voit (daté du 09/10/2026).
                const Icon(
                  Icons.description_outlined,
                  size: AppSpacing.mdPlus,
                  color: AppColors.navy,
                ),
                const SizedBox(width: AppSpacing.xsPlus),
                // `pwa.etats.titre` (l.45), au mot — esperluette comprise.
                Text('États & Rapports', style: TextesEtats.titreBarre),
              ],
            ),
          ),

          // `h-5 w-px bg-slate-200` (l.48) — le filet vertical.
          Container(
            width: AppLayout.filetVertical,
            height: AppSpacing.mdPlus,
            color: Ardoise.c200,
          ),
        ],
      ),
    );
  }
}
