// Vue Blade maîtresse (PA-183) : pwa/achats/achats.blade.php
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../../restaurant/presentation/widgets/textes_modale_restaurant.dart';
import '../../domain/entities/fournisseur.dart';

/// La modale **« Détail — [fournisseur] »** — `pwa/achats/achats.blade.php`
/// l.395-423 (`crud-ui.js` l.107-121 de l'ancien maître).
///
/// Cinq paires étiquette / valeur, dans l'ordre des colonnes du tableau, puis
/// deux boutons : « Fermer », et « Modifier » pour qui peut écrire. Une valeur
/// absente rend « — » : une ligne vide se lirait comme une donnée non chargée.
///
/// Rend `true` quand l'utilisateur choisit « Modifier » — c'est l'appelant qui
/// ouvre le formulaire, une fois cette fenêtre fermée : deux dialogues
/// empilés rendraient la fermeture du second ambiguë.
Future<bool?> ouvrirDetailFournisseur(
  BuildContext context, {
  required Fournisseur fournisseur,
  required bool peutEcrire,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierColor: AppColors.voileModale,
    builder: (_) =>
        _ModaleDetail(fournisseur: fournisseur, peutEcrire: peutEcrire),
  );
}

class _ModaleDetail extends StatelessWidget {
  const _ModaleDetail({required this.fournisseur, required this.peutEcrire});

  final Fournisseur fournisseur;
  final bool peutEcrire;

  @override
  Widget build(BuildContext context) {
    final f = fournisseur;

    // L'ordre et les libellés de la vue (l.400-406).
    final paires = <(String, String?)>[
      ('Fournisseur', f.raisonSociale),
      ('Contact', f.contact),
      ('Catégorie fournie', f.categorie),
      ('Conditions', f.conditionsPaiement),
      // `Achats::EVALUATIONS[...]['libelle'] ?? null` : « — » pour une fiche
      // pas encore évaluée. Un code inconnu garde son code brut (voir le
      // badge du tableau).
      ('Évaluation', f.estEvalue ? f.libelleEvaluation : null),
    ];

    return CoquilleModaleRestaurant(
      cle: const Key('modale-detail-fournisseur'),
      titre: 'Détail — ${f.raisonSociale}',
      largeur: AppLayout.modaleDetailAchats,
      corps: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // `space-y-3` : douze pixels entre deux paires.
          for (final (i, (libelle, valeur)) in paires.indexed) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            _Paire(libelle: libelle, valeur: valeur),
          ],
        ],
      ),
      actions: [
        OutlinedButton(
          key: const Key('detail-fournisseur-fermer'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Fermer', style: TextesModaleRestaurant.bouton),
        ),
        if (peutEcrire)
          FilledButton(
            key: const Key('detail-fournisseur-modifier'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Modifier', style: TextesModaleRestaurant.bouton),
          ),
      ],
    );
  }
}

/// `flex justify-between gap-4 border-b border-slate-100 pb-2` : l'étiquette
/// en `text-[12px] font-semibold text-slate-500`, la valeur en `text-[13px]
/// text-slate-800 text-right`.
class _Paire extends StatelessWidget {
  const _Paire({required this.libelle, required this.valeur});

  final String libelle;
  final String? valeur;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs), // pb-2
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Ardoise.c100)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            libelle,
            style: const TextStyle(
              fontFamily: AppTextStyles.police,
              fontSize: Tailles.t12,
              fontWeight: FontWeight.w600,
              color: Ardoise.c500,
            ),
          ),
          const SizedBox(width: AppSpacing.md), // gap-4
          Flexible(
            child: Text(
              valeur ?? '—',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: AppTextStyles.police,
                fontSize: Tailles.t13,
                color: Ardoise.c800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
