// Vue Blade maîtresse (PA-183) : pwa/livewire/accueil.blade.php
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';

/// Les briques des modales de l'accueil (lot C, 14/10/2026) — la forme que la
/// vue répète d'une modale à l'autre :
///
/// * libellé `block text-[15px] font-semibold text-slate-700 mb-1.5`, suivi
///   d'un astérisque `text-red-500` quand le champ est requis ;
/// * champ `champ w-full border border-slate-200 rounded-lg px-3 py-2.5
///   text-sm` ;
/// * valeur affichée (jamais saisie) `text-sm text-slate-700 bg-slate-50
///   rounded-lg px-3 py-2.5` ;
/// * erreur `text-[12px] text-red-600 mt-1` sous le champ qu'elle vise ;
/// * pied « Annuler » (`border border-slate-300`) puis l'action
///   (`text-[13px] px-4 py-2 rounded-lg font-semibold`).
///
/// Hors `<main>` (les modales de la vue sont posées après `</main>`) : échelle
/// typographique DÉCLARÉE ([Tailles]).
const TextStyle _texteCorps = TextStyle(
  fontFamily: AppTextStyles.police,
  fontSize: Tailles.t14, // `text-sm`
  height: AppLayout.interligneContenu,
  letterSpacing: 0,
  color: AppColors.neutre700,
);

/// Le libellé d'un champ, avec son astérisque rouge s'il est requis.
class LibelleChampAccueil extends StatelessWidget {
  const LibelleChampAccueil(this.texte, {super.key, this.requis = false});

  final String texte;
  final bool requis;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontFamily: AppTextStyles.police,
      fontSize: Tailles.t15,
      fontWeight: FontWeight.w600,
      color: AppColors.neutre700,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs), // mb-1.5
      child: Text.rich(
        TextSpan(
          text: texte,
          style: style,
          children: [
            if (requis)
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

/// Une valeur AFFICHÉE, jamais saisie — client, unité, nuits d'une réservation
/// existante : les retaper permettrait de les faire diverger (la vue).
class ValeurAfficheeAccueil extends StatelessWidget {
  const ValeurAfficheeAccueil(this.texte, {super.key});

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm, // px-3
        vertical: AppSpacing.xsPlus, // py-2.5
      ),
      decoration: BoxDecoration(
        color: Ardoise.c50,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      ),
      child: Text(texte, style: _texteCorps),
    );
  }
}

/// L'aide posée en tête du corps — `<p class="text-[12px] text-slate-500">`
/// (check-in, check-out), puis l'espacement `space-y-4` du formulaire.
class AideModaleAccueil extends StatelessWidget {
  const AideModaleAccueil(this.texte, {super.key});

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Text(
        texte,
        style: const TextStyle(
          fontFamily: AppTextStyles.police,
          fontSize: Tailles.t12,
          color: AppColors.neutre500,
        ),
      ),
    );
  }
}

/// Le message d'une erreur, sous le champ qu'elle vise — rien quand il n'y en
/// a pas.
class ErreurChampAccueil extends StatelessWidget {
  const ErreurChampAccueil(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final m = message;
    if (m == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.unit), // mt-1
      child: Text(
        m,
        style: const TextStyle(
          fontFamily: AppTextStyles.police,
          fontSize: Tailles.t12,
          color: PaletteMaitre.rouge600,
        ),
      ),
    );
  }
}

/// La décoration d'un champ de la vue.
InputDecoration decorationChampAccueil({String? indication}) {
  final bordure = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.roundedLg),
    borderSide: const BorderSide(color: AppColors.neutre200),
  );
  return InputDecoration(
    isDense: true,
    hintText: indication,
    filled: true,
    fillColor: AppColors.neutre0,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm, // px-3
      vertical: AppSpacing.xsPlus, // py-2.5
    ),
    border: bordure,
    enabledBorder: bordure,
    focusedBorder: bordure.copyWith(
      borderSide: const BorderSide(color: AppColors.gold),
    ),
  );
}

/// Le style du texte saisi dans un champ.
const TextStyle styleSaisieAccueil = _texteCorps;

/// Un champ texte de la vue.
class ChampTexteAccueil extends StatelessWidget {
  const ChampTexteAccueil({
    super.key,
    required this.controleur,
    this.indication,
    this.numerique = false,
    this.onChange,
  });

  final TextEditingController controleur;
  final String? indication;
  final bool numerique;
  final ValueChanged<String>? onChange;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controleur,
      keyboardType: numerique ? TextInputType.number : TextInputType.text,
      style: styleSaisieAccueil,
      decoration: decorationChampAccueil(indication: indication),
      onChanged: onChange,
    );
  }
}

/// Un `<select>` de la vue : sa première option (la consigne, valeur vide)
/// puis les choix. [valeur] `null` : la consigne est sélectionnée.
class ChampChoixAccueil<T> extends StatelessWidget {
  const ChampChoixAccueil({
    super.key,
    required this.valeur,
    required this.choix,
    required this.onChange,
    this.consigne,
  });

  final T? valeur;
  final List<(T, String)> choix;
  final ValueChanged<T?> onChange;

  /// L'option vide (« Choisissez un client »), absente quand la vue n'en pose
  /// pas (type de client, mode de paiement).
  final String? consigne;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T?>(
      initialValue: valeur,
      isExpanded: true,
      style: styleSaisieAccueil,
      decoration: decorationChampAccueil(),
      items: [
        if (consigne != null)
          DropdownMenuItem<T?>(value: null, child: Text(consigne!)),
        for (final (v, libelle) in choix)
          DropdownMenuItem<T?>(
            value: v,
            child: Text(libelle, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChange,
    );
  }
}

/// « Annuler » — `pwa.modale.annuler`, `border border-slate-300`.
class BoutonAnnulerAccueil extends StatelessWidget {
  const BoutonAnnulerAccueil({super.key, required this.cle});

  final Key cle;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      key: cle,
      onPressed: () => Navigator.of(context).pop(),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Ardoise.c300),
        foregroundColor: AppColors.anthracite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        ),
      ),
      child: const Text(
        'Annuler',
        style: TextStyle(
          fontFamily: AppTextStyles.police,
          fontSize: Tailles.t13,
        ),
      ),
    );
  }
}

/// L'action d'une modale — fond plein ([fond] : navy ou `var(--succes)`),
/// grisée pendant l'écriture pour qu'un double clic n'écrive pas deux fois.
class BoutonValiderAccueil extends StatelessWidget {
  const BoutonValiderAccueil({
    super.key,
    required this.cle,
    required this.libelle,
    required this.fond,
    required this.onPressed,
  });

  final Key cle;
  final String libelle;
  final Color fond;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      key: cle,
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: fond,
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

/// Un bloc libellé + champ + erreur, `space-y-4` entre deux blocs.
class BlocChampAccueil extends StatelessWidget {
  const BlocChampAccueil({
    super.key,
    required this.libelle,
    required this.champ,
    this.requis = false,
    this.erreur,
    this.aDroite,
  });

  final String libelle;
  final bool requis;
  final Widget champ;
  final String? erreur;

  /// Ce que la vue pose à droite du libellé (la case « + Nouveau client »).
  final Widget? aDroite;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md), // space-y-4
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: LibelleChampAccueil(libelle, requis: requis)),
              ?aDroite,
            ],
          ),
          champ,
          ErreurChampAccueil(erreur),
        ],
      ),
    );
  }
}
