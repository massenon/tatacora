import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/bouton_standard.dart';
import '../../../transverse/presentation/widgets/briques_transverses.dart';
import '../../domain/anciennes_pieces_saisies.dart';
import '../../domain/montant_comptable.dart';
import '../providers_comptabilite.dart';
import '../providers_etats_financiers.dart';
import '../../../../core/format/formats.dart';

/// Lot A3 (28/10/2026) : le geste explicite « Envoyer mes anciennes pièces
/// saisies » du hub comptable. Les pièces saisies à la main AVANT la v44 ne sont
/// ni marquées ni envoyées ; rien ne les déduit en silence. Ce bloc n'apparaît
/// que s'il y en a, pour l'administration et le comptable, et la confirmation
/// dit le nombre et le total. Tant que le geste n'est pas fait, les pièces
/// restent comptées au poste.
abstract final class TextesEnvoiAnciennesPieces {
  static const String bouton = 'Envoyer mes anciennes pièces saisies';
  static const String confirmer = 'Envoyer';
  static const String annuler = 'Annuler';
  static String intro(int n) => n == 1
      ? 'Une pièce saisie à la main avant la synchronisation des écritures n’a pas encore été envoyée au serveur. Elle reste comptée sur ce poste.'
      : '$n pièces saisies à la main avant la synchronisation des écritures n’ont pas encore été envoyées au serveur. Elles restent comptées sur ce poste.';
  static String confirmation(int n, String total) =>
      'Envoyer ${n == 1 ? 'une ancienne pièce saisie' : '$n anciennes pièces saisies'} à la main, pour un total de $total ? Elles sont marquées puis envoyées au serveur (si la synchronisation est activée) ; le geste ne se défait pas.';
  static String fait(int n) => n == 1
      ? 'Une ancienne pièce marquée et mise en file d’envoi.'
      : '$n anciennes pièces marquées et mises en file d’envoi.';
  static const String echec =
      'Les anciennes pièces n’ont pas pu être marquées. Rien n’a été écrit.';
}

class BlocEnvoiAnciennesPieces extends ConsumerWidget {
  const BlocEnvoiAnciennesPieces({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(sessionProvider)?.role;
    if (!peutEnvoyerAnciennesPieces(role)) return const SizedBox.shrink();
    final n = ref
        .watch(piecesManuellesEnAttenteProvider)
        .value
        ?.anciennesNonEnvoyees;
    if (n == null || n == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: EncadreTransverse(
        fond: Ardoise.c50,
        bordure: Ardoise.c200,
        padding: const EdgeInsets.all(AppSpacing.smPlus),
        child: Row(
          children: [
            Expanded(
              child: Text(
                TextesEnvoiAnciennesPieces.intro(n),
                key: const Key('compta-anciennes-pieces-intro'),
                style: styleTransverse(
                  TaillesContenu.t13,
                  couleur: Ardoise.c700,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            BoutonStandard(
              key: const Key('compta-anciennes-pieces-bouton'),
              libelle: TextesEnvoiAnciennesPieces.bouton,
              compact: true,
              onPressed: () => _geste(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _geste(BuildContext context, WidgetRef ref) async {
    final dao = ref.read(comptabiliteDaoProvider);
    final pieces = await dao.anciennesPiecesSaisies();
    if (pieces.isEmpty || !context.mounted) return;
    final total = formaterMontantDecimal(
      chaineDepuisCentimes(totalAnciennesPieces(pieces)),
      suffixe: 'FCFA',
    );
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.voileModale,
      builder: (c) => AlertDialog(
        key: const Key('compta-anciennes-pieces-confirmation'),
        content: Text(
          TextesEnvoiAnciennesPieces.confirmation(pieces.length, total ?? ''),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text(TextesEnvoiAnciennesPieces.annuler),
          ),
          TextButton(
            key: const Key('compta-anciennes-pieces-confirmer'),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text(TextesEnvoiAnciennesPieces.confirmer),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    String message;
    try {
      final moteur = await ref.read(moteurComptableProvider.future);
      final nombre = await moteur.envoyerAnciennesPieces(
        auteurId: ref.read(sessionProvider)?.utilisateurId ?? '',
      );
      message = TextesEnvoiAnciennesPieces.fait(nombre);
    } on Object {
      message = TextesEnvoiAnciennesPieces.echec;
    }
    ref.invalidate(piecesManuellesEnAttenteProvider);
    if (!context.mounted) return;
    direTransverse(
      context,
      message,
      cle: const Key('compta-anciennes-pieces-fait'),
    );
  }
}
