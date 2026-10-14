// Vue Blade maîtresse (PA-183) : pwa/pos/comptant.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../domain/messages_caisse.dart';
import '../../domain/regles_caisse.dart';
import '../providers_caisse.dart';

/// La modale **« Ouvrir la caisse bar »** (`pos/comptant.blade.php` l.638-660),
/// posée dans le châssis partagé des modales ([CoquilleModaleRestaurant],
/// l'équivalent de `x-pwa.modale`).
///
/// ## Aucun fond pré-rempli
///
/// Le champ naît VIDE, comme `$fondCaisseSaisi = ''` du composant : un fond de
/// caisse prérempli serait un montant inventé sur une pièce d'exploitation
/// (« la leçon de PA-53 »). Le serveur le refuse (`required`), le poste aussi.
///
/// ## Le refus s'affiche SOUS le champ, la saisie reste
///
/// `@error('fondCaisseSaisi')` de la vue (l.646-648) : la modale ne se ferme pas
/// sur un refus, le caissier corrige. Les phrases sont celles du serveur, y
/// compris celle qui nomme le champ « fond caisse saisi » (voir
/// `MessagesCaisse`) — incohérence du serveur répliquée, pas corrigée.
///
/// Ce fichier PORTE cette modale de la vue : il cite donc la vue en tête (PA-183).
class ModaleOuvertureCaisse extends ConsumerStatefulWidget {
  const ModaleOuvertureCaisse({super.key});

  @override
  ConsumerState<ModaleOuvertureCaisse> createState() =>
      _EtatModaleOuvertureCaisse();
}

class _EtatModaleOuvertureCaisse extends ConsumerState<ModaleOuvertureCaisse> {
  final TextEditingController _fond = TextEditingController();
  String? _refus;
  bool _envoi = false;

  @override
  void dispose() {
    _fond.dispose();
    super.dispose();
  }

  Future<void> _ouvrir() async {
    setState(() {
      _refus = null;
      _envoi = true;
    });
    // Capturés AVANT l'`await` : le contexte peut ne plus être monté après.
    final navigateur = Navigator.of(context);
    final messages = ScaffoldMessenger.of(context);
    try {
      final succes = await ouvrirLaCaisse(ref, _fond.text);
      navigateur.pop();
      messages.showSnackBar(SnackBar(content: Text(succes)));
    } on RefusCaisse catch (e) {
      if (mounted) setState(() => _refus = e.message);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleRestaurant(
      cle: const Key('modale-ouverture-caisse'),
      titre: MessagesCaisse.titreOuverture(pointDeCaisseDuComptoir.code),
      largeur: LargeursPos.modaleCaisse,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // `block text-[13px] font-semibold text-slate-700 mb-2`.
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text(
              MessagesCaisse.etiquetteFond,
              style: TextStyle(
                fontFamily: AppTextStyles.police,
                fontSize: Tailles.t13,
                fontWeight: FontWeight.w600,
                color: Ardoise.c700,
              ),
            ),
          ),
          ChampMontantCaisse(
            cle: const Key('caisse-fond-saisi'),
            controleur: _fond,
          ),
          if (_refus != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              // `mt-2 text-[12px] text-red-600`.
              child: Text(
                _refus!,
                key: const Key('caisse-refus'),
                style: const TextStyle(
                  fontFamily: AppTextStyles.police,
                  fontSize: Tailles.t12,
                  color: PaletteMaitre.rouge600,
                ),
              ),
            ),
        ],
      ),
      actions: [
        BoutonAnnulerCaisse(
          onPressed: _envoi ? null : () => Navigator.of(context).pop(),
        ),
        BoutonActionCaisse(
          cle: const Key('caisse-ouvrir-confirmer'),
          libelle: MessagesCaisse.ouvrirLaCaisse,
          onPressed: _envoi ? null : _ouvrir,
        ),
      ],
    );
  }
}

/// `w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2
/// focus:border-[var(--gold)]` — le champ de montant des deux modales.
class ChampMontantCaisse extends StatelessWidget {
  const ChampMontantCaisse({
    required this.cle,
    required this.controleur,
    super.key,
  });

  final Key cle;
  final TextEditingController controleur;

  @override
  Widget build(BuildContext context) {
    final bordure = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      borderSide: const BorderSide(color: Ardoise.c300),
    );
    return TextField(
      key: cle,
      controller: controleur,
      // `type="number"` : le clavier numérique. La VALIDATION reste celle du
      // serveur (`required|numeric|min:0`), pas un filtre de saisie : un
      // `1e3` ou un espace doivent atteindre la règle pour être refusés par
      // elle, comme au serveur.
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(
        fontFamily: AppTextStyles.police,
        fontSize: Tailles.t13,
      ),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        enabledBorder: bordure,
        border: bordure,
        focusedBorder: bordure.copyWith(
          borderSide: const BorderSide(color: AppColors.gold),
        ),
      ),
    );
  }
}

/// Le bouton « Annuler » du pied (`border border-slate-300 hover:bg-slate-50`).
class BoutonAnnulerCaisse extends StatelessWidget {
  const BoutonAnnulerCaisse({required this.onPressed, super.key});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      key: const Key('caisse-annuler'),
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Ardoise.c300),
        foregroundColor: AppColors.anthracite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        ),
      ),
      child: const Text(
        MessagesCaisse.annuler,
        style: TextStyle(
          fontFamily: AppTextStyles.police,
          fontSize: Tailles.t13,
        ),
      ),
    );
  }
}

/// Le bouton d'action du pied (`bg-[var(--navy)] text-white font-semibold`).
class BoutonActionCaisse extends StatelessWidget {
  const BoutonActionCaisse({
    required this.cle,
    required this.libelle,
    required this.onPressed,
    super.key,
  });

  final Key cle;
  final String libelle;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      key: cle,
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.navy,
        foregroundColor: AppColors.neutre0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        ),
      ),
      child: Text(
        libelle,
        style: const TextStyle(
          fontFamily: AppTextStyles.police,
          fontSize: Tailles.t13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
