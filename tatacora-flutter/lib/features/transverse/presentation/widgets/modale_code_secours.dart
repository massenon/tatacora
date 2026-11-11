// Vue Blade maîtresse (PA-183) : pwa/transverse/mon-profil.blade.php
/// « Générer un code de secours » de « Mon profil » (29/10/2026, option A du PO) :
/// l'administrateur CONNECTÉ confirme son mot de passe, puis reçoit un nouveau
/// code (l'ancien cesse de fonctionner), montré UNE fois par la fenêtre du secret.
///
/// Jumeau de la modale `code_secours` de `pwa/transverse/mon-profil.blade.php`
/// (`pwa.profil.code_secours_*`). Le mot de passe saisi est vidé après chaque
/// refus, comme celui de « Modifier le mot de passe ».
///
/// Modale : hors `<main>`, échelle typographique DÉCLARÉE ([Tailles]).
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/mesures_transverses.dart';
import '../../../../shared_widgets/bouton_standard.dart';
import '../../../auth/domain/mot_de_passe_perdu.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';

/// Ouvre la confirmation. [generer] vérifie le mot de passe, écrit et rend le
/// code ; la modale se ferme en le renvoyant. `null` : annulé.
Future<String?> ouvrirModaleGenererCodeSecours(
  BuildContext context, {
  required Future<String> Function(String motDePasse) generer,
}) => showDialog<String>(
  context: context,
  builder: (_) => _ModaleGenererCodeSecours(generer: generer),
);

class _ModaleGenererCodeSecours extends StatefulWidget {
  const _ModaleGenererCodeSecours({required this.generer});

  final Future<String> Function(String motDePasse) generer;

  @override
  State<_ModaleGenererCodeSecours> createState() => _EtatModale();
}

class _EtatModale extends State<_ModaleGenererCodeSecours> {
  final _motDePasse = TextEditingController();
  String? _refus;
  bool _enCours = false;

  @override
  void dispose() {
    _motDePasse.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (_enCours) return;
    if (_motDePasse.text.isEmpty) {
      setState(() => _refus = MessagesMotDePassePerdu.mdpIncorrect);
      return;
    }
    setState(() {
      _enCours = true;
      _refus = null;
    });
    // Laisse la fenêtre se redessiner avant les dérivations PBKDF2.
    await Future<void>.delayed(Duration.zero);
    try {
      final code = await widget.generer(_motDePasse.text);
      if (mounted) Navigator.of(context).pop(code);
    } on RefusMotDePassePerdu catch (e) {
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _refus = e.message;
        _motDePasse.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleRestaurant(
      cle: const Key('profil-code-secours-modale'),
      titre: MessagesMotDePassePerdu.codeSecoursModaleTitre,
      sousTitre: MessagesMotDePassePerdu.codeSecoursModaleSousTitre,
      largeur: MesuresTransverses.modaleCompte,
      refus: _refus,
      cleRefus: const Key('profil-code-secours-refus'),
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            MessagesMotDePassePerdu.codeSecoursMotDePasse,
            style: TextStyle(
              fontFamily: AppTextStyles.police,
              fontSize: Tailles.t15,
              fontWeight: FontWeight.w600,
              color: Ardoise.c700,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          TextField(
            key: const Key('profil-code-secours-mot-de-passe'),
            controller: _motDePasse,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            autofocus: true,
            enabled: !_enCours,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _valider(),
            style: const TextStyle(
              fontFamily: AppTextStyles.police,
              fontSize: Tailles.t13,
              color: Ardoise.c800,
            ),
            decoration: InputDecoration(
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: const BorderSide(color: Ardoise.c200),
              ),
            ),
          ),
        ],
      ),
      actions: [
        BoutonStandard(
          key: const Key('profil-code-secours-annuler'),
          libelle: 'Annuler',
          taillePolice: Tailles.t13,
          margeHorizontale: AppSpacing.md,
          onPressed: _enCours ? null : () => Navigator.of(context).pop(),
        ),
        BoutonStandard(
          key: const Key('profil-code-secours-generer'),
          libelle: MessagesMotDePassePerdu.codeSecoursGenerer,
          variante: VarianteBouton.primaire,
          taillePolice: Tailles.t13,
          onPressed: _enCours ? null : _valider,
        ),
      ],
    );
  }
}
