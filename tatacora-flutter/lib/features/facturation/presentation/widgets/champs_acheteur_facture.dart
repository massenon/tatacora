import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../domain/acheteur_facture.dart';
import '../../domain/ifu_client.dart';
import '../../domain/mode_facturation.dart';
import '../providers_facturation.dart';

/// Les champs de l'ACHETEUR d'une facture — décision du PO du 07/11/2026 (point 2) : « IFU du
/// client » (facultatif, 13 chiffres s'il est rempli), « Nom du client », « Retenir pour ce
/// client » (décoché par défaut) et, seulement quand ce poste normalise, « Normaliser
/// maintenant » (décoché par défaut, jamais automatique).
///
/// MÊME champ, mêmes règles, mêmes phrases qu'au web (`heberges.blade.php`, bloc « acheteur ») :
/// les mots sont ceux de `lang/fr/facturation.php`, rejoués contre le vrai PHP par
/// `parite_regles_communes_test.dart`. Posés dans les modales (hors `<main>`) : échelle [Tailles].
class ChampsAcheteurFacture extends ConsumerStatefulWidget {
  const ChampsAcheteurFacture({
    required this.saisie,
    this.ifuInitial,
    this.nomInitial,
    super.key,
  });

  /// Lu par l'appelant à la confirmation ; mis à jour à chaque frappe.
  final ValueNotifier<AcheteurFacture> saisie;

  /// L'IFU retenu sur la fiche du client (préremplissage), s'il y en a un.
  final String? ifuInitial;
  final String? nomInitial;

  static const Key cleIfu = Key('acheteur-ifu');
  static const Key cleNom = Key('acheteur-nom');
  static const Key cleRetenir = Key('acheteur-retenir');
  static const Key cleNormaliser = Key('acheteur-normaliser-maintenant');
  static const Key cleErreurIfu = Key('acheteur-ifu-erreur');

  @override
  ConsumerState<ChampsAcheteurFacture> createState() =>
      _EtatChampsAcheteurFacture();
}

class _EtatChampsAcheteurFacture extends ConsumerState<ChampsAcheteurFacture> {
  late final TextEditingController _ifu = TextEditingController(
    text: widget.saisie.value.ifu ?? widget.ifuInitial ?? '',
  );
  late final TextEditingController _nom = TextEditingController(
    text: widget.saisie.value.nom ?? widget.nomInitial ?? '',
  );
  late bool _retenir = widget.saisie.value.retenir;
  late bool _normaliser = widget.saisie.value.normaliserMaintenant;

  static const TextStyle _etiquette = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t12,
    fontWeight: FontWeight.w600,
    color: Ardoise.c600,
  );
  static const TextStyle _petit = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t11,
    color: Ardoise.c500,
  );
  static const TextStyle _champ = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t13,
    color: AppColors.anthracite,
  );

  @override
  void initState() {
    super.initState();
    // L'état initial est posé tout de suite : une confirmation sans frappe porte la fiche.
    WidgetsBinding.instance.addPostFrameCallback((_) => _publier());
  }

  @override
  void dispose() {
    _ifu.dispose();
    _nom.dispose();
    super.dispose();
  }

  void _publier() {
    if (!mounted) return;
    widget.saisie.value = AcheteurFacture(
      ifu: _ifu.text,
      nom: _nom.text,
      retenir: _retenir,
      normaliserMaintenant: _normaliser,
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final valide = IfuClient.valide(_ifu.text);
    final par = ref.watch(certifieParProvider).value ?? CertifiePar.rien;

    InputDecoration decoration({String? erreur}) => InputDecoration(
      isDense: true,
      errorText: erreur,
      errorMaxLines: 3,
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(color: Ardoise.c200),
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(TextesIfuClient.nomLabel, style: _etiquette),
          const SizedBox(height: AppSpacing.unit),
          TextField(
            key: ChampsAcheteurFacture.cleNom,
            controller: _nom,
            maxLength: 100,
            buildCounter:
                (_, {required currentLength, required isFocused, maxLength}) =>
                    null,
            style: _champ,
            decoration: decoration(),
            onChanged: (_) => _publier(),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(TextesIfuClient.label, style: _etiquette),
          const SizedBox(height: AppSpacing.unit),
          TextField(
            key: ChampsAcheteurFacture.cleIfu,
            controller: _ifu,
            keyboardType: TextInputType.number,
            // 13 chiffres ; les séparateurs de saisie sont tolérés et ôtés (la règle commune).
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9 .\-]')),
              LengthLimitingTextInputFormatter(20),
            ],
            style: _champ,
            decoration: decoration(
              erreur: valide ? null : TextesIfuClient.invalide,
            ),
            onChanged: (_) => _publier(),
          ),
          const SizedBox(height: AppSpacing.unit),
          const Text(TextesIfuClient.aide, style: _petit),
          InkWell(
            key: ChampsAcheteurFacture.cleRetenir,
            onTap: () {
              _retenir = !_retenir;
              _publier();
            },
            child: Row(
              children: [
                Checkbox(
                  value: _retenir,
                  onChanged: (v) {
                    _retenir = v ?? false;
                    _publier();
                  },
                ),
                const Expanded(
                  child: Text(TextesIfuClient.retenir, style: _petit),
                ),
              ],
            ),
          ),
          // « Normaliser maintenant » : seulement quand CE poste normalise (boîtier, ou le
          // serveur en ligne) ; jamais coché d'office.
          if (par != CertifiePar.rien)
            InkWell(
              key: ChampsAcheteurFacture.cleNormaliser,
              onTap: () {
                _normaliser = !_normaliser;
                _publier();
              },
              child: Row(
                children: [
                  Checkbox(
                    value: _normaliser,
                    onChanged: (v) {
                      _normaliser = v ?? false;
                      _publier();
                    },
                  ),
                  const Expanded(
                    child: Text(
                      TextesIfuClient.normaliserMaintenant,
                      style: _petit,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Le dialogue « Facture » du POS au comptoir : l'acheteur saisi y est gardé pour le
/// PROCHAIN encaissement (`acheteurFactureProvider`), puis remis à zéro.
class ModaleAcheteurFacture extends StatefulWidget {
  const ModaleAcheteurFacture({
    required this.initial,
    this.nomInitial,
    super.key,
  });

  final AcheteurFacture initial;
  final String? nomInitial;

  static const String titre = 'Facture';
  static const String valider = 'Valider';
  static const String annuler = 'Annuler';

  @override
  State<ModaleAcheteurFacture> createState() => _EtatModaleAcheteurFacture();
}

class _EtatModaleAcheteurFacture extends State<ModaleAcheteurFacture> {
  late final ValueNotifier<AcheteurFacture> _saisie = ValueNotifier(
    widget.initial,
  );

  @override
  void dispose() {
    _saisie.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CoquilleModaleRestaurant(
    cle: const Key('modale-acheteur-facture'),
    titre: ModaleAcheteurFacture.titre,
    largeur: 440,
    corps: ChampsAcheteurFacture(
      saisie: _saisie,
      nomInitial: widget.nomInitial,
    ),
    actions: [
      TextButton(
        key: const Key('acheteur-annuler'),
        onPressed: () => Navigator.of(context).pop(),
        child: const Text(ModaleAcheteurFacture.annuler),
      ),
      ValueListenableBuilder<AcheteurFacture>(
        valueListenable: _saisie,
        builder: (context, acheteur, _) => FilledButton(
          key: const Key('acheteur-valider'),
          onPressed: acheteur.ifuValide
              ? () => Navigator.of(context).pop(acheteur)
              : null,
          child: const Text(ModaleAcheteurFacture.valider),
        ),
      ),
    ],
  );
}
