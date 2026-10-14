// Vue Blade maîtresse (PA-183) : pwa/stocks/stocks.blade.php
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// La coquille commune aux deux modales de l'écran Stocks —
/// `prototype_v2/pages/m6-stocks.html` l.252-265 (`coquilleModale`).
///
/// Le maître la factorise lui-même : en-tête (titre + sous-titre), corps
/// défilant, pied à deux boutons (« Annuler », puis le libellé de validation).
/// La recopier dans chaque modale la ferait diverger au premier ajustement,
/// exactement comme l'en-tête d'état recopiée que `RESPECT_TABLEAU_RAPPORT.md`
/// §4 recense en non-conformité n° 1.
///
/// ## Les deux bornes du maître sont portées, et l'une est indispensable
///
/// `max-w-lg` (512 px) et `max-h-[88vh]` — deux mesures relevées sur le maître,
/// pas déduites d'une échelle. Sans la seconde, la modale de mouvement, qui
/// porte le journal de l'article sous son formulaire, déborde de l'écran et
/// **son pied disparaît avec le bouton d'enregistrement** : le formulaire
/// devient impossible à valider sans qu'aucune erreur ne s'affiche.
class CoquilleModaleStock extends StatelessWidget {
  const CoquilleModaleStock({
    required Key cle,
    required this.titre,
    required this.sousTitre,
    required this.corps,
    required this.libelleValidation,
    required this.cleValidation,
    required this.onValider,
    required this.envoiEnCours,
    this.refus,
    this.cleRefus,
  }) : super(key: cle);

  final String titre;
  final String sousTitre;
  final Widget corps;
  final String libelleValidation;
  final Key cleValidation;
  final Future<void> Function() onValider;

  /// Pendant l'envoi, le bouton est **désactivé**, pas seulement occupé : sans
  /// cela un second clic créerait un second article, et l'identifiant fourni
  /// par le client ferait alors refuser le premier envoi qui revient — on
  /// verrait une erreur sur l'enregistrement qui a réussi.
  final bool envoiEnCours;

  /// Le refus du serveur, affiché **dans la modale** et non en `SnackBar` : la
  /// saisie est encore là, et le message doit rester lisible pendant qu'on la
  /// corrige.
  final String? refus;

  final Key? cleRefus;

  @override
  Widget build(BuildContext context) {
    final hauteurMax =
        MediaQuery.of(context).size.height *
        AppLayout.fractionHauteurModaleStock;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(titre, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.unit),
          Text(sousTitre, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: hauteurMax),
        child: SizedBox(
          width: AppLayout.modaleStock,
          child: SingleChildScrollView(
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
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: AppColors.erreurBordure),
                    ),
                    child: Text(
                      refus!,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.erreur,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                corps,
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('modale-stock-annuler'),
          onPressed: envoiEnCours ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: cleValidation,
          onPressed: envoiEnCours ? null : onValider,
          child: Text(libelleValidation),
        ),
      ],
    );
  }
}
