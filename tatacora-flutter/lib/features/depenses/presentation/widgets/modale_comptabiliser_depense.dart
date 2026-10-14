import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/bouton_standard.dart';
import '../../../restaurant/presentation/widgets/corps_carte_commun.dart'
    show styleContenuCarte;
import '../ecran_depenses.dart' show LibellesRattrapage;
import '../providers_depenses.dart';

/// Le titre de la fenêtre — dicté par le Product Owner le 14/10/2026.
const String titreComptabiliserDepense = 'Comptabiliser la dépense';

/// Demande le centre de coût de la pièce, puis rend son identifiant — ou
/// `null` si l'opérateur annule.
///
/// ## Pourquoi une fenêtre (PO, 14/10/2026)
///
/// Le bandeau ambre de la vue, qui portait le `<select>` « Centre de coût de la
/// pièce », est retiré de l'écran. Le centre reste OBLIGATOIRE (le moteur
/// refuse sans lui, RG-12) et n'est jamais deviné : la dépense n'en mémorise
/// aucun, aucun compte de charge n'en porte par défaut. Le choix se fait donc
/// ici, au clic sur « Comptabiliser » de la ligne : la liste démarre sur
/// « Choisir un centre », et le bouton de confirmation reste grisé tant
/// qu'aucun centre n'est choisi.
Future<String?> demanderCentreComptabilisation(BuildContext context) =>
    showDialog<String>(
      context: context,
      builder: (_) => const _ModaleComptabiliserDepense(),
    );

class _ModaleComptabiliserDepense extends ConsumerStatefulWidget {
  const _ModaleComptabiliserDepense();

  @override
  ConsumerState<_ModaleComptabiliserDepense> createState() =>
      _ModaleComptabiliserDepenseState();
}

class _ModaleComptabiliserDepenseState
    extends ConsumerState<_ModaleComptabiliserDepense> {
  /// Chaîne vide = « Choisir un centre », l'état de départ.
  String _centre = '';

  @override
  Widget build(BuildContext context) {
    final centres = ref.watch(centresDeCoutProvider).value ?? const [];
    final valeur = styleContenuCarte(TaillesContenu.t13, couleur: Ardoise.c700);

    return Dialog(
      key: const Key('modale-comptabiliser-depense'),
      backgroundColor: AppColors.neutre0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppLayout.modaleParametre,
          maxHeight: AppLayout.hauteurMaxModaleParametre,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.mdPlus),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                titreComptabiliserDepense,
                style: TextStyle(
                  fontFamily: AppTextStyles.police,
                  fontSize: Tailles.t16,
                  fontWeight: FontWeight.bold,
                  color: Ardoise.c800,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                LibellesRattrapage.centre,
                style: styleContenuCarte(
                  TaillesContenu.t12,
                  poids: FontWeight.w600,
                  couleur: Ardoise.c600,
                ),
              ),
              const SizedBox(height: AppSpacing.unit),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.neutre0,
                  borderRadius: BorderRadius.circular(AppRadius.roundedMd),
                  border: Border.all(color: Ardoise.c300),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    key: const Key('depenses-centre-rattrapage'),
                    // Une valeur hors de la liste (centres pas encore lus) ne
                    // doit pas lever : elle retombe sur l'option vide.
                    value: centres.any((c) => c.id == _centre) ? _centre : '',
                    isExpanded: true,
                    isDense: true,
                    itemHeight: null,
                    iconSize: AppLayout.iconeChamp,
                    style: valeur,
                    items: [
                      const DropdownMenuItem<String>(
                        value: '',
                        child: Text(LibellesRattrapage.choisir),
                      ),
                      for (final c in centres)
                        DropdownMenuItem<String>(
                          value: c.id,
                          child: Text(c.libelle),
                        ),
                    ],
                    onChanged: (v) => setState(() => _centre = v ?? ''),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.mdPlus),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  BoutonStandard(
                    key: const Key('depenses-comptabiliser-annuler'),
                    libelle: 'Annuler',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  BoutonStandard(
                    key: const Key('depenses-comptabiliser-confirmer'),
                    libelle: 'Comptabiliser',
                    variante: VarianteBouton.primaire,
                    onPressed: _centre.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(_centre),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
