// Vue Blade maîtresse (PA-183) : pwa/transverse/comptes-utilisateurs.blade.php
// Vue Blade maîtresse (PA-183) : pwa/transverse/mon-profil.blade.php
// Vue Blade maîtresse (PA-183) : pwa/livewire/code-secours.blade.php
/// UN SECRET AFFICHÉ UNE SEULE FOIS — le mot de passe temporaire que
/// l'administrateur communique, ou le code de secours à ranger au coffre
/// (29/10/2026, option A du PO : pas de mot de passe perdu par e-mail).
///
/// Jumeau du composant Blade « secret-unique » des vues : le secret en clair dans
/// une boîte monospace sélectionnable, « Copier » (presse-papiers) et, si
/// l'appelant offre [surImprimer], « Imprimer ». Le secret n'est écrit nulle
/// part ailleurs : la fenêtre qui l'affiche le détruit en se fermant, et rien ne
/// le remet au journal ni aux logs.
///
/// Brique commune (`shared_widgets/`) : aucune valeur n'y est écrite en dur
/// (jetons du thème), échelle typographique des modales ([Tailles]).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_text_styles.dart';
import 'bouton_standard.dart';

/// Les libellés (`pwa.secret_unique.*`).
abstract final class TextesSecretUnique {
  static const String copier = 'Copier';
  static const String copie = 'Copié';
  static const String imprimer = 'Imprimer';
}

class AffichageSecretUnique extends StatefulWidget {
  const AffichageSecretUnique({
    super.key,
    required this.secret,
    required this.consigne,
    this.surImprimer,
    this.prefixeCle = 'secret',
  });

  final String secret;

  /// La phrase qui dit quoi en faire.
  final String consigne;

  /// Offre « Imprimer » quand il est fourni.
  final Future<void> Function()? surImprimer;

  /// Préfixe des clés des widgets (`<prefixe>-valeur`, `-copier`, `-imprimer`).
  final String prefixeCle;

  @override
  State<AffichageSecretUnique> createState() => _EtatAffichageSecretUnique();
}

class _EtatAffichageSecretUnique extends State<AffichageSecretUnique> {
  bool _copie = false;

  Future<void> _copier() async {
    await Clipboard.setData(ClipboardData(text: widget.secret));
    if (mounted) setState(() => _copie = true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.fondClair,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.gold, width: 2),
          ),
          child: SelectableText(
            widget.secret,
            key: Key('${widget.prefixeCle}-valeur'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: AppTextStyles.policeMonospace,
              fontSize: Tailles.t16,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          widget.consigne,
          key: Key('${widget.prefixeCle}-consigne'),
          style: const TextStyle(
            fontFamily: AppTextStyles.police,
            fontSize: Tailles.t13,
            color: Ardoise.c600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            BoutonStandard(
              key: Key('${widget.prefixeCle}-copier'),
              libelle: _copie
                  ? TextesSecretUnique.copie
                  : TextesSecretUnique.copier,
              taillePolice: Tailles.t13,
              onPressed: _copier,
            ),
            if (widget.surImprimer != null)
              BoutonStandard(
                key: Key('${widget.prefixeCle}-imprimer'),
                libelle: TextesSecretUnique.imprimer,
                taillePolice: Tailles.t13,
                onPressed: widget.surImprimer,
              ),
          ],
        ),
      ],
    );
  }
}
