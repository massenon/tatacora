import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/entities/piece_facturation.dart';
import '../providers_facturation.dart';

/// L'annulation **par avoir** — la seule façon d'annuler une facture.
///
/// ## Pourquoi cette fonction existe séparément
///
/// Elle vivait dans le widget de ligne, remplacé le 21/08/2026 par le tableau
/// du maître. **Le remplacement l'a emportée**, et l'écran a passé quelques
/// minutes sans aucun moyen d'annuler une facture — un défaut de la famille
/// PA-81 : un retrait vérifié sur son rôle d'affichage, pas sur l'ensemble de
/// ce que le code retiré faisait.
///
/// Extraite ici, elle ne dépend plus d'une mise en page : le tableau peut
/// changer encore sans la reprendre.
///
/// ## Le libellé dit ce qui se passe
///
/// « Annuler par avoir », pas « Annuler ». Rien n'est effacé : une pièce
/// contre-passée reste au registre, et un avoir de montant négatif la
/// neutralise (propriété n°4 du moteur, PA-99). Un trou dans la numérotation
/// est indistinguable d'une pièce dissimulée.
///
/// ## Le motif est obligatoire
///
/// Une annulation sans raison est indistinguable d'une erreur de manipulation,
/// et c'est le seul élément qu'un contrôle pourra lire des années plus tard.
Future<void> annulerParAvoir(
  BuildContext context,
  WidgetRef ref,
  PieceFacturation piece,
) async {
  final motif = TextEditingController();
  final formulaire = GlobalKey<FormState>();

  final confirme = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Annuler ${piece.numero} par avoir'),
      content: Form(
        key: formulaire,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'La facture reste au registre. Un avoir de montant négatif la '
              'neutralise, et porte son propre numéro.',
              style: TextStyle(
                color: AppColors.neutre500,
                fontFamily: AppTextStyles.police,
                fontSize: Tailles.t13,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: motif,
              key: const Key('facturation-motif-avoir'),
              decoration: const InputDecoration(
                labelText: 'Motif de l’annulation',
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Un motif est requis : une annulation sans raison est '
                        'indistinguable d’une erreur.'
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Renoncer'),
        ),
        FilledButton(
          key: const Key('facturation-confirmer-avoir'),
          onPressed: () {
            if (formulaire.currentState!.validate()) {
              Navigator.of(context).pop(true);
            }
          },
          child: const Text('Émettre l’avoir'),
        ),
      ],
    ),
  );

  if (confirme != true) return;

  try {
    await ref.read(facturerProvider).annuler(piece.id, motif.text.trim());
    ref.invalidate(registreProvider);
  } on Object catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}
