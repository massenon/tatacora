// Vue Blade maîtresse (PA-183) : pwa/transverse/parametres.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/mesures_transverses.dart';
import '../../../../core/theme/mesures_transverses_complement.dart';
import '../../../transverse/data/envoi_messages_editeur.dart';
import '../../../transverse/presentation/providers_contact_editeur.dart';

/// Le libellé du bouton — `pwa.parametres.email_test_bouton`.
const String libelleEmailDeTest = 'Envoyer un email de test';

/// Le bouton « Envoyer un email de test » de l'onglet Email (SMTP), et la
/// phrase qui rapporte ce que le transport a répondu (`resultatTestEmail` de
/// la vue) : vert si le courriel est parti, rouge sinon — jamais un succès
/// simulé (PA-59/60/61). Réservé à qui peut écrire (`@if ($peutEcrire)`).
///
/// L'envoi passe par l'UNIQUE expéditeur du poste
/// ([ServiceMessagesEditeur.envoyerEmailDeTest]) : la configuration SMTP de
/// Paramètres, le mot de passe de `poste.json`, le transport des messages à
/// l'éditeur.
class BoutonEmailTest extends ConsumerStatefulWidget {
  const BoutonEmailTest({super.key, required this.peutEcrire});

  final bool peutEcrire;

  @override
  ConsumerState<BoutonEmailTest> createState() => _EtatBoutonEmailTest();
}

class _EtatBoutonEmailTest extends ConsumerState<BoutonEmailTest> {
  bool _occupe = false;
  ResultatEmailDeTest? _resultat;

  Future<void> _envoyer() async {
    setState(() => _occupe = true);
    ResultatEmailDeTest resultat;
    try {
      resultat = await ref
          .read(serviceMessagesEditeurProvider)
          .envoyerEmailDeTest();
    } on Object catch (e) {
      resultat = (succes: false, detail: TextesEmailDeTest.echec('$e'));
    }
    if (!mounted) return;
    setState(() {
      _occupe = false;
      _resultat = resultat;
    });
  }

  @override
  Widget build(BuildContext context) {
    final resultat = _resultat;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.peutEcrire)
          OutlinedButton.icon(
            key: const Key('param-email-test'),
            onPressed: _occupe ? null : _envoyer,
            icon: const Icon(
              Icons.send_outlined,
              size: MesuresEmailDeTest.icone,
              color: AppColors.neutre600,
            ),
            label: Text(
              libelleEmailDeTest,
              style: TextStyle(
                fontFamily: AppTextStyles.police,
                fontSize: TaillesContenu.t15,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: AppColors.neutre600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: MesuresEmailDeTest.margeBouton,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: const BorderSide(color: AppColors.neutre200),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.roundedLg),
              ),
            ),
          ),
        if (resultat != null) ...[
          const SizedBox(height: AppSpacing.xs), // mt-2
          Text(
            resultat.detail,
            key: const Key('param-email-test-resultat'),
            style: TextStyle(
              fontFamily: AppTextStyles.police,
              fontSize: TaillesContenu.t13,
              height: 1.5,
              fontWeight: FontWeight.w600,
              color: resultat.succes
                  ? PaletteTransverse.texteVert
                  : PaletteTransverse.texteRouge,
            ),
          ),
        ],
      ],
    );
  }
}
