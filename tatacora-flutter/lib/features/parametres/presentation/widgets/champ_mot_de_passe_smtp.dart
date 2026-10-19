import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/bouton_standard.dart';
import '../../../synchronisation/presentation/providers_synchronisation.dart';
import '../../../transverse/data/configuration_poste.dart';
import '../../../transverse/domain/comptes_utilisateurs.dart';

/// Les mots du champ « Mot de passe SMTP » — ceux de la vue de Paramètres,
/// onglet Email (SMTP), saisie levée le 19/10/2026 (décision du Product
/// Owner : « enregistrer les configurations dans le poste et le web »).
///
/// Un écart NOMMÉ, parce que la vue parle du serveur : sa mention (« Rangé
/// chiffré sur le serveur … sans lui, la configuration serveur (.env)
/// s'applique ») serait fausse sur ce poste, qui n'a ni `.env` ni repli. Ici, le secret vit dans `poste.json` (profil Windows de
/// l'utilisateur, hors du dépôt, hors de la base Drift) — jamais exporté ni
/// synchronisé, comme au serveur.
abstract final class TextesMotDePasseSmtp {
  static const libelle = 'Mot de passe SMTP';
  static const invite = 'Saisir un nouveau mot de passe';
  static const enregistrer = 'Enregistrer le mot de passe';
  static const effacer = 'Effacer';
  static String renseigne(EtatMotDePasseSmtp e) =>
      'Renseigné le ${e.le == null ? '—' : _date(e.le!)} par '
      '${e.par ?? '—'} — jamais réaffiché.';
  static const absent =
      'Non renseigné ici. Aucun courriel ne peut partir de ce poste.';
  static const reserve =
      'Seul un Administrateur peut saisir ou effacer ce mot de passe.';
  static const mention =
      "Secret technique : n'entre jamais dans les paramètres système. Rangé "
      'dans le profil Windows de ce poste ($cheminConfigurationPosteAffiche), '
      "il n'est jamais réaffiché, exporté ni synchronisé.";
  static const enregistre = 'Mot de passe SMTP enregistré sur ce poste.';
  static const efface = 'Mot de passe SMTP effacé de ce poste.';
  static const vide = 'Le mot de passe doit compter au moins 1 caractère.';

  static String _date(DateTime d) {
    final l = d.toLocal();
    String deux(int n) => n.toString().padLeft(2, '0');
    return '${deux(l.day)}/${deux(l.month)}/${l.year} ${deux(l.hour)}:'
        '${deux(l.minute)}';
  }
}

/// L'état du mot de passe SMTP du poste, relu du fichier — jamais sa valeur.
final etatMotDePasseSmtpProvider =
    FutureProvider.autoDispose<EtatMotDePasseSmtp>(
      (ref) => LecteurConfigurationPoste(
        chemin: ref.watch(cheminConfigurationPosteProvider),
      ).etatMotDePasseSmtp(),
    );

/// Le champ « Mot de passe SMTP » de l'onglet Email (SMTP) : écriture seule,
/// réservée aux Administrateurs (`peutAdministrerComptes`), écrit dans
/// `poste.json` par `EcrivainConfigurationPoste`.
class ChampMotDePasseSmtp extends ConsumerStatefulWidget {
  const ChampMotDePasseSmtp({super.key, required this.peutEcrire});

  final bool peutEcrire;

  @override
  ConsumerState<ChampMotDePasseSmtp> createState() =>
      _ChampMotDePasseSmtpState();
}

class _ChampMotDePasseSmtpState extends ConsumerState<ChampMotDePasseSmtp> {
  final _saisie = TextEditingController();
  bool _occupe = false;
  String? _message;
  bool _erreur = false;

  @override
  void dispose() {
    _saisie.dispose();
    super.dispose();
  }

  EcrivainConfigurationPoste get _ecrivain => EcrivainConfigurationPoste(
    chemin: ref.read(cheminConfigurationPosteProvider),
  );

  Future<void> _geste(Future<String?> Function() action) async {
    setState(() {
      _occupe = true;
      _message = null;
    });
    String? refus;
    String? succes;
    try {
      succes = await action();
    } on ConfigurationPosteIllisible catch (e) {
      refus = '$e';
    } on Object catch (e) {
      refus = 'Opération impossible sur ce poste : $e';
    }
    if (!mounted) return;
    setState(() {
      _occupe = false;
      _message = refus ?? succes;
      _erreur = refus != null || succes == TextesMotDePasseSmtp.vide;
    });
    ref.invalidate(etatMotDePasseSmtpProvider);
  }

  Future<String?> _enregistrer() async {
    if (_saisie.text.isEmpty) return TextesMotDePasseSmtp.vide;
    final session = ref.read(sessionProvider);
    await _ecrivain.enregistrerMotDePasseSmtp(
      _saisie.text,
      par: session?.login ?? '—',
      le: DateTime.now(),
    );
    // La valeur ne reste pas dans le champ.
    _saisie.clear();
    return TextesMotDePasseSmtp.enregistre;
  }

  Future<String?> _effacer() async {
    await _ecrivain.effacerMotDePasseSmtp();
    _saisie.clear();
    return TextesMotDePasseSmtp.efface;
  }

  @override
  Widget build(BuildContext context) {
    final admin =
        widget.peutEcrire &&
        peutAdministrerComptes(ref.watch(sessionProvider)?.role);
    final etat = ref.watch(etatMotDePasseSmtpProvider).value;

    return Column(
      key: const Key('param-smtp-mot-de-passe'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          TextesMotDePasseSmtp.libelle,
          style: _style(TaillesContenu.t15, poids: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.xs),
        if (admin) ...[
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: AppLayout.champMotDePasseSmtp,
                child: TextField(
                  key: const Key('param-smtp-saisie'),
                  controller: _saisie,
                  enabled: !_occupe,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    hintText: TextesMotDePasseSmtp.invite,
                    isDense: true,
                  ),
                ),
              ),
              BoutonStandard(
                key: const Key('param-smtp-enregistrer'),
                libelle: TextesMotDePasseSmtp.enregistrer,
                variante: VarianteBouton.primaire,
                onPressed: _occupe ? null : () => _geste(_enregistrer),
              ),
              if (etat?.renseigne ?? false)
                BoutonStandard(
                  key: const Key('param-smtp-effacer'),
                  libelle: TextesMotDePasseSmtp.effacer,
                  onPressed: _occupe ? null : () => _geste(_effacer),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        if (etat != null)
          Text(
            etat.renseigne
                ? TextesMotDePasseSmtp.renseigne(etat)
                : TextesMotDePasseSmtp.absent,
            key: const Key('param-smtp-etat'),
            style: _style(TaillesContenu.t13, couleur: AppColors.neutre600),
          ),
        if (!admin)
          Text(
            TextesMotDePasseSmtp.reserve,
            key: const Key('param-smtp-reserve'),
            style: _style(TaillesContenu.t12, couleur: AppColors.neutre400),
          ),
        if (_message != null)
          Text(
            _message!,
            key: const Key('param-smtp-message'),
            style: _style(
              TaillesContenu.t13,
              poids: FontWeight.w600,
              couleur: _erreur ? AppColors.erreur : AppColors.succes,
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          TextesMotDePasseSmtp.mention,
          style: _style(TaillesContenu.t12, couleur: AppColors.neutre400),
        ),
      ],
    );
  }

  static TextStyle _style(
    double taille, {
    FontWeight poids = FontWeight.normal,
    Color couleur = AppColors.neutre900,
  }) => TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: taille,
    fontWeight: poids,
    color: couleur,
  );
}
