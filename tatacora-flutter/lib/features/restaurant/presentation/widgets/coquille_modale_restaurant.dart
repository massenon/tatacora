import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import 'coquille_restaurant.dart';
import 'textes_modale_restaurant.dart';

/// La coquille des modales de M4 — `crud-ui.js` l.85-189.
///
/// ## Ce n'est pas un `AlertDialog`
///
/// L'Article 1 (interdit 06) le nomme : « substituer un composant Material par
/// défaut à un composant maquetté ». Un `AlertDialog` impose son en-tête, ses
/// marges et son pied ; la modale du maître a une structure précise, reprise
/// ici zone par zone :
///
/// ```html
/// <div class="overlay-modale">
///   <div class="boite-modale" style="max-width:560px">
///     <div class="flex items-center justify-between px-6 py-4 border-b …">
///       <h2 class="text-base font-bold">…</h2>
///       <button data-fermer-modale>✕</button>
///     <div class="p-6 …">…</div>
///     <div class="flex justify-end gap-3 px-6 py-4 border-t … bg-slate-50">
/// ```
///
/// ## Fermeture au voile ET à Échap — Article 4.6
///
/// Les deux sont exigées. `barrierDismissible` couvre le voile ; la touche
/// d'échappement est branchée **explicitement** plutôt que laissée au hasard du
/// comportement par défaut — une garde qu'on ne pose pas est une garde qu'on ne
/// peut pas tester.
///
/// ## L'échelle typographique est celle des MODALES
///
/// `#crud-modales-zone` est un frère de `<main>` : le remappage de `app.css`
/// ne s'y applique pas. Les styles employés ici viennent donc de [Tailles] via
/// [TextesRestaurant], famille « modale ».
class CoquilleModaleRestaurant extends StatelessWidget {
  const CoquilleModaleRestaurant({
    required Key cle,
    required this.titre,
    required this.largeur,
    required this.corps,
    required this.actions,
    this.sousTitre,
    this.refus,
    this.cleRefus,
  }) : super(key: cle);

  final String titre;

  /// `style="max-width:…"` du maître — 560, 480 ou 440 px selon la modale.
  final double largeur;

  final Widget corps;

  /// Les boutons de pied, **dans l'ordre du maître** : « Annuler » à gauche,
  /// l'action à droite (`crud-ui.js` l.97-100). L'ordre est un acquis d'usage.
  final List<Widget> actions;

  final String? sousTitre;

  /// Le refus du serveur, affiché **dans la modale** et non en `SnackBar` : la
  /// saisie est encore là, et le message doit rester lisible pendant qu'on la
  /// corrige.
  final String? refus;

  final Key? cleRefus;

  /// `max-h-[60vh]` sur le CORPS de la modale (`crud-ui.js` l.114) — le seul
  /// plafond que le maître écrit.
  ///
  /// ## Ce n'est PAS lui qui garde le pied visible, et il ne faut pas le croire
  ///
  /// Une première rédaction ajoutait un second plafond sur la boîte entière, en
  /// affirmant qu'il empêchait le bouton de validation de sortir de l'écran. La
  /// **mutation qui le retire n'a fait rougir aucun cas** : ce n'est pas lui qui
  /// tient cette propriété, c'est le [Flexible] posé autour du corps — il cède
  /// la hauteur au pied avant de la prendre pour lui.
  ///
  /// Un commentaire qui affirme une garantie n'est pas une garantie (piège 8).
  /// Le plafond inventé a donc été retiré, et le cas de rendu éprouve la vraie
  /// mécanique : il monte la modale sur 500 px de haut et mesure le bas du
  /// bouton.
  static const double fractionCorps = 0.6;

  @override
  Widget build(BuildContext context) {
    final hauteurCorps = MediaQuery.sizeOf(context).height * fractionCorps;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          backgroundColor: AppColors.neutre0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.roundedXl),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: largeur),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // `px-6 py-4 border-b border-slate-100`.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Ardoise.c100)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(titre, style: TextesModaleRestaurant.titre),
                            if (sousTitre != null) ...[
                              const SizedBox(height: AppSpacing.demi),
                              Text(
                                sousTitre!,
                                style: TextesModaleRestaurant.sousTitre,
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Le « ✕ » du maître, avec son libellé d'accessibilité.
                      IconButton(
                        key: const Key('modale-restaurant-fermer'),
                        tooltip: 'Fermer',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, color: Ardoise.c400),
                      ),
                    ],
                  ),
                ),
                // `p-6 space-y-4`, borné en hauteur.
                //
                // **`Flexible` est ce qui garde le pied à l'écran** : il cède
                // la hauteur à l'en-tête et au pied avant de prendre le reste.
                // Le remplacer par un enfant non flexible ferait sortir le
                // bouton de validation de la fenêtre sur un écran bas, et la
                // saisie deviendrait impossible sans qu'aucune erreur ne
                // s'affiche.
                Flexible(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: hauteurCorps),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (refus != null) ...[
                            Container(
                              key: cleRefus,
                              padding: const EdgeInsets.all(AppSpacing.sm),
                              decoration: BoxDecoration(
                                color: AppColors.erreurFond,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.roundedLg,
                                ),
                                border: Border.all(
                                  color: AppColors.erreurBordure,
                                ),
                              ),
                              child: Text(
                                refus!,
                                style: TextesModaleRestaurant.corps.copyWith(
                                  color: AppColors.erreur,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                          ],
                          corps,
                        ],
                      ),
                    ),
                  ),
                ),
                // `flex justify-end gap-3 px-6 py-4 border-t bg-slate-50`.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                  decoration: const BoxDecoration(
                    color: Ardoise.c50,
                    border: Border(top: BorderSide(color: Ardoise.c100)),
                  ),
                  // `flex justify-end gap-3` — rendu en `Wrap` et non en
                  // `Row` : « Annuler » et « Enregistrer les modifications »
                  // debordent de 76 px sur une modale de 390 px de large, et
                  // le second bouton devient inatteignable. Trouve par le test
                  // de rendu, pas par la relecture (Article 9.3). L'ordre et
                  // l'alignement du maitre sont conserves ; seule la mise a la
                  // ligne s'ajoute, la ou le maitre n'a pas de cas etroit.
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: actions,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Une étiquette de champ — `block text-[13px] font-semibold text-slate-700
/// mb-1.5`, suivie d'un astérisque rouge quand le champ est obligatoire
/// (`carte-module.js` l.234).
class EtiquetteChampRestaurant extends StatelessWidget {
  const EtiquetteChampRestaurant({
    super.key,
    required this.texte,
    this.obligatoire = false,
  });

  final String texte;
  final bool obligatoire;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: texte, style: TextesModaleRestaurant.etiquette),
            if (obligatoire)
              const TextSpan(
                text: ' *',
                style: TextStyle(color: PaletteMaitre.rouge500),
              ),
          ],
        ),
      ),
    );
  }
}
