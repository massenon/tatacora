import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/rbac/garde_acces.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/textes_proforma.dart';

/// « Créer une proforma » dans un module (PO, 07/11/2026) : ouvre l'écran Proformas PRÉREMPLI
/// depuis [flux] (`location`, `tourisme`, `hebergement`) et [source] (l'élément du module), ou
/// vide pour un événement (aucun module événement n'existe). Réservé au droit d'écriture sur M2
/// (`@if (auth()->user()?->niveauSurModule('M2') === 'C')` de la vue web) : absent sinon.
class BoutonCreerProforma extends ConsumerWidget {
  const BoutonCreerProforma({
    required this.flux,
    this.source,
    this.court = false,
    super.key,
  });

  final String flux;
  final String? source;

  /// Le libellé court « Proforma » (cartes de réservation), l'infobulle gardant le libellé entier.
  final bool court;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peut = ref
        .watch(droitsProvider)
        .niveau(ModuleTatacora.m2Facturation)
        .peutEcrire;
    if (!peut) return const SizedBox.shrink();
    final entier = TextesProforma.ui['creer_depuis_module']!;
    return Tooltip(
      message: entier,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.rounded),
        onTap: () => context.go(
          Uri(
            path: '/facturation/proformas',
            queryParameters: {'flux': flux, 'source': ?source},
          ).toString(),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.demi,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: Ardoise.c300),
            borderRadius: BorderRadius.circular(AppRadius.rounded),
          ),
          child: Text(
            court ? TextesProforma.ui['creer_court']! : entier,
            style: TextStyle(
              fontFamily: AppTextStyles.police,
              fontSize: TaillesContenu.t11,
              color: Ardoise.c700,
            ),
          ),
        ),
      ),
    );
  }
}
