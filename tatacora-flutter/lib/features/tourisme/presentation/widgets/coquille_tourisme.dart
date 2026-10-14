/// Les briques communes aux trois onglets de M9.
///
/// Elles vivent ici, et non recopiées dans chaque vue : « deux listes décrivant
/// la même chose divergeront — ce n'est qu'une question de temps » (Article 10).
/// Le tiret d'une donnée absente, surtout, n'a qu'un seul auteur — deux
/// écritures du même « rien » se liraient comme deux états.
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
// `app_spacing.dart` réexporte `app_radius.dart`.
import '../../../../core/theme/app_spacing.dart';
import '../../../restaurant/presentation/widgets/coquille_restaurant.dart';
import '../../../restaurant/presentation/widgets/tableau_restaurant.dart';
import '../../domain/departs.dart';

/// Le gabarit de tableau de M9 — et il n'est NI celui de la carte, NI celui du
/// moteur CRUD.
///
/// Mesuré sur la vue maîtresse (`tourisme/departs.blade.php`) :
///
/// | | En-tête | Cellules | Bordure |
/// |---|---|---|---|
/// | M9 (l.270, l.297) | `bg-[var(--navy)]`, `text-white/90` | `px-3 py-2.5` | `border-t` |
/// | `GabaritTableau.carte` | `bg-slate-50` | `px-3 py-2.5` | `border-t` |
/// | `GabaritTableau.crud` | `bg-[var(--navy)]` | **`px-4 py-3`** | `border-b` |
///
/// M9 prend l'en-tête de l'un et les cellules de l'autre. Le rabattre sur le
/// gabarit CRUD « parce qu'il est navy aussi » élargirait chaque cellule de
/// 4 px et changerait le côté de la bordure : c'est l'approximation que
/// l'Article 1 interdit nommément (interdit 09).
const GabaritTableau gabaritTourisme = GabaritTableau(
  enteteFond: AppColors.navy,
  entete: TextesRestaurant.enteteColonneNavy,
  cellule: EdgeInsets.symmetric(
    // `px-3` — 12 px.
    horizontal: AppSpacing.sm,
    // `py-2.5` — 10 px, l'espacement le plus employé du maître.
    vertical: AppSpacing.xsPlus,
  ),
  enBas: false,
);

/// La décoration de la ligne TOTAL — `bg-[var(--navy)] text-white font-bold`
/// (vue l.340).
const BoxDecoration decorationTotalTourisme = BoxDecoration(
  color: AppColors.navy,
);

/// Le style d'une cellule de la ligne TOTAL.
TextStyle get styleTotalTourisme => TextesRestaurant.corpsFort.copyWith(
  color: AppColors.neutre0,
  fontWeight: FontWeight.w700,
);

/// Une cellule dont la donnée **n'existe pas au schéma** — « — » et sa raison.
///
/// Jamais un zéro : « 0 FCFA » sur un acompte se lit « rien versé », alors que
/// la vérité est « on n'en sait rien » (Article 7). La raison vit dans
/// l'infobulle, pour que quelqu'un qui se demande pourquoi la colonne est vide
/// trouve la réponse sans ouvrir le code.
class CelluleAbsenteTourisme extends StatelessWidget {
  const CelluleAbsenteTourisme({super.key, required this.raison});

  final String raison;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: raison,
      child: const Text(
        CarteIndicateurRestaurant.absent,
        style: TextesRestaurant.corps,
      ),
    );
  }
}

/// L'état vide d'un tableau — `py-14 text-center text-slate-400 text-[13px]`
/// dans une carte blanche (vue l.262, l.409, l.533).
///
/// Un tableau vide **dit pourquoi** ; il ne reste pas blanc.
class EtatVideTourisme extends StatelessWidget {
  const EtatVideTourisme({required Key cle, required this.message})
    : super(key: cle);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      // `py-14` — 56 px.
      padding: const EdgeInsets.symmetric(vertical: AppSpacingLarge.p14),
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: Ardoise.c200),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextesRestaurant.corps.copyWith(color: Ardoise.c400),
      ),
    );
  }
}

/// La jauge de remplissage d'un départ — vue l.306-312.
///
/// Trois couleurs, aux seuils du maître (l.293) : rouge à 100 %, or à partir de
/// 70 %, vert en dessous. Le texte « vendues/capacité » porte la MÊME couleur
/// que la barre : un daltonien lit le rapport, la barre n'est qu'un appui.
class JaugeRemplissage extends StatelessWidget {
  const JaugeRemplissage({required Key cle, required this.depart})
    : super(key: cle);

  final Depart depart;

  /// Les seuils de la vue (l.293), nommés plutôt que semés dans le `build`.
  static const int seuilComplet = 100;
  static const int seuilTendu = 70;

  static Color couleurPour(int pourcentage) {
    if (pourcentage >= seuilComplet) return PaletteMaitre.rouge600;
    if (pourcentage >= seuilTendu) return AppColors.gold;
    return PaletteMaitre.emeraude600;
  }

  @override
  Widget build(BuildContext context) {
    final pourcentage = depart.pourcentageRemplissage;
    final couleur = couleurPour(pourcentage);

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // `w-20 h-2 rounded-full bg-slate-200 overflow-hidden`.
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.roundedFull),
          child: SizedBox(
            width: AppLayout.jaugeRemplissage,
            height: AppLayout.hauteurJaugeRemplissage,
            child: Stack(
              children: [
                Container(color: Ardoise.c200),
                FractionallySizedBox(
                  widthFactor: pourcentage / 100,
                  child: Container(color: couleur),
                ),
              ],
            ),
          ),
        ),
        // `gap-2` — 8 px.
        const SizedBox(width: AppSpacing.xs),
        Text(
          '${depart.placesVendues}/${depart.capacite}',
          style: TextesRestaurant.secondaire.copyWith(
            fontWeight: FontWeight.w600,
            color: couleur,
          ),
        ),
      ],
    );
  }
}

/// La pastille « État » d'un départ — vue l.317-323.
///
/// Les trois états sont ceux de [EtatDepart], et le `switch` est exhaustif :
/// un quatrième état ajouté demain fera échouer la compilation plutôt que de
/// recevoir une pastille par omission.
class PastilleEtatDepart extends StatelessWidget {
  const PastilleEtatDepart({required Key cle, required this.depart})
    : super(key: cle);

  final Depart depart;

  @override
  Widget build(BuildContext context) {
    final (texte, fond, couleur) = switch (depart.etat) {
      // `bg-slate-100 text-slate-500` — « Annulé ».
      EtatDepart.annule => (
        'Annulé',
        AppColors.badgeGrisFond,
        AppColors.badgeGrisTexte,
      ),
      // `bg-red-50 text-red-700` — « Complet ».
      EtatDepart.complet => (
        'Complet',
        PaletteMaitre.rouge50,
        PaletteMaitre.rouge700,
      ),
      // `bg-emerald-50 text-emerald-700` — « N place(s) ».
      //
      // ⚠ Le maître écrit « place(s) » au singulier-pluriel, y compris pour
      // une seule place. Le « corriger » serait harmoniser une décision du
      // maître (interdit 10).
      EtatDepart.placesDisponibles => (
        '${depart.placesRestantes} place(s)',
        PaletteMaitre.emeraude50,
        PaletteMaitre.emeraude700,
      ),
    };

    return PastilleRestaurant(
      cle: Key('tourisme-etat-${Depart.cle(depart.circuitId, depart.date)}'),
      compacte: true,
      texte: texte,
      fond: fond,
      couleur: couleur,
    );
  }
}

/// Un bouton d'action de ligne — `text-[11px] px-2 py-0.5 rounded`.
///
/// Le maître en pose deux formes : pleine (navy) pour l'action principale
/// d'une ligne, bordée pour les secondaires (vue l.328-335).
class ActionLigneTourisme extends StatelessWidget {
  const ActionLigneTourisme({
    required Key cle,
    required this.libelle,
    required this.onPresse,
    this.pleine = false,
  }) : super(key: cle);

  final String libelle;
  final VoidCallback onPresse;
  final bool pleine;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      padding: WidgetStatePropertyAll(
        // `px-2 py-0.5` — 8 px et 2 px.
        const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.demi,
        ),
      ),
      minimumSize: const WidgetStatePropertyAll(Size.zero),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    final texte = Text(libelle, style: TextesRestaurant.pastilleCarte);

    // ⚠ La clé est portée par CE widget, et surtout pas RECOPIÉE sur le bouton
    // qu'il rend : la poser aux deux endroits fait correspondre `find.byKey` à
    // DEUX widgets, et `tap()` échoue alors en « ambiguously found multiple
    // matching widgets ». Même famille que le piège 10 de ce dépôt — une clé
    // qui ne désigne pas un seul widget est une clé qui ment.
    return pleine
        ? FilledButton(onPressed: onPresse, style: style, child: texte)
        : OutlinedButton(onPressed: onPresse, style: style, child: texte);
  }
}
