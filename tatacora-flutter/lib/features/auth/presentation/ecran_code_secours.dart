// Vue Blade maîtresse (PA-183) : pwa/livewire/code-secours.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/mesures_connexion.dart';
import '../../../shared_widgets/affichage_secret_unique.dart';
import '../impression/feuille_code_secours.dart';
import '../domain/mot_de_passe_perdu.dart';
import 'ecran_changement_mot_de_passe.dart';
import 'ecran_connexion.dart';

/// Les libellés de l'écran — `lang/fr/pwa.php`, groupe `code_secours`, au
/// caractère près (un test les confronte à la langue du serveur, résolue par PHP).
abstract final class TextesCodeSecours {
  /// `pwa.code_secours.titre`.
  static const titre = "J'ai perdu mon mot de passe administrateur";

  /// `pwa.code_secours.accroche`.
  static const accroche =
      "Saisissez votre nom d'utilisateur, le code de secours rangé au coffre "
      'et un nouveau mot de passe.';

  /// `pwa.code_secours.login` / `code`.
  static const login = "NOM D'UTILISATEUR";
  static const code = 'CODE DE SECOURS';

  /// `pwa.code_secours.regle`.
  static const regle =
      "Min. 8 caractères. Le code de secours ne sert qu'une fois : un nouveau "
      'vous sera remis.';

  /// `pwa.code_secours.bouton` / `en_cours` / `retour_connexion`.
  static const bouton = 'RÉINITIALISER LE MOT DE PASSE';
  static const enCours = 'Vérification…';
  static const retourConnexion = 'Retour à la connexion';

  /// `pwa.code_secours.nouveau_code_titre` / `mdp_reinitialise` /
  /// `consigne_coffre`.
  static const nouveauCodeTitre = 'Votre nouveau code de secours';
  static const consigneCoffre =
      'Ce code ne sera plus affiché. Notez-le ou imprimez-le et rangez-le au '
      "coffre : l'ancien code ne fonctionne plus.";
}

/// « J'ai perdu mon mot de passe administrateur » — nom d'utilisateur + code de
/// secours + nouveau mot de passe (29/10/2026, option A du PO). Accessible SANS
/// session, depuis le message « Contactez l'administrateur » de la connexion : c'est
/// le recours du DERNIER administrateur du poste.
///
/// Traduction de `pwa/livewire/code-secours.blade.php`, dans la mise en page
/// « invité » de la connexion. Toutes les règles vivent dans `CodeSecoursLocal`
/// (essais limités, refus identique que le compte existe ou non, usage unique,
/// audit) : cet écran n'en recalcule aucune. Après un succès, le NOUVEAU code est
/// affiché UNE seule fois (copier, imprimer, ranger au coffre).
class EcranCodeSecours extends ConsumerStatefulWidget {
  const EcranCodeSecours({super.key});

  @override
  ConsumerState<EcranCodeSecours> createState() => _EtatEcranCodeSecours();
}

class _EtatEcranCodeSecours extends ConsumerState<EcranCodeSecours> {
  final _formulaire = GlobalKey<FormState>();
  final _login = TextEditingController();
  final _code = TextEditingController();
  final _nouveau = TextEditingController();
  final _confirmation = TextEditingController();

  bool _enCours = false;
  String? _erreur;

  /// Le NOUVEAU code, affiché une seule fois ; `null` : formulaire.
  String? _nouveauCode;

  /// Le compte réinitialisé (pour la feuille imprimée).
  String _compte = '';

  @override
  void dispose() {
    _login.dispose();
    _code.dispose();
    _nouveau.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _soumettre() async {
    if (_enCours || !_formulaire.currentState!.validate()) return;
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      // Laisse la fenêtre se redessiner avant les dérivations PBKDF2.
      await Future<void>.delayed(Duration.zero);
      final nouveauCode = await ref
          .read(codeSecoursProvider)
          .reinitialiser(
            login: _login.text,
            code: _code.text,
            nouveau: _nouveau.text,
          );
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _compte = _login.text.trim().toLowerCase();
        _nouveauCode = nouveauCode;
      });
    } on RefusMotDePassePerdu catch (e) {
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _erreur = e.message;
      });
    } finally {
      // Jamais conservés au-delà de l'essai.
      _code.clear();
      _nouveau.clear();
      _confirmation.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titre = Semantics(
      header: true,
      child: Text(
        _nouveauCode == null
            ? TextesCodeSecours.titre
            : TextesCodeSecours.nouveauCodeTitre,
        style: theme.textTheme.headlineMedium?.copyWith(
          fontSize: Tailles.t28,
          fontWeight: FontWeight.w800,
          height: Tailles.interligneSerre,
          color: AppColors.navy,
        ),
      ),
    );
    final retour = Center(
      child: TextButton(
        key: const Key('code-secours-retour'),
        onPressed: () => context.go('/connexion'),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.navy,
          textStyle: const TextStyle(
            fontSize: Tailles.t15,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: const Text(TextesCodeSecours.retourConnexion),
      ),
    );
    final pied = Text(
      TextesConnexion.piedDePage,
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall?.copyWith(
        fontSize: Tailles.t13,
        color: AppColors.neutre500,
      ),
    );

    if (_nouveauCode case final code?) {
      return CadreInvite(
        enfants: [
          const MarqueConnexion(),
          const SizedBox(height: AppSpacing.md),
          const FiletConnexion(),
          const SizedBox(height: AppSpacing.md),
          titre,
          const SizedBox(height: AppSpacing.xxs),
          Semantics(
            liveRegion: true,
            child: Text(
              MessagesMotDePassePerdu.mdpReinitialise,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: Tailles.t15,
                color: AppColors.neutre500,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AffichageSecretUnique(
            secret: code,
            consigne: TextesCodeSecours.consigneCoffre,
            prefixeCle: 'code-secours-nouveau',
            surImprimer: () =>
                ref.read(imprimerCodeSecoursProvider)(code, _compte),
          ),
          const SizedBox(height: AppSpacing.lg),
          BoutonPleinConnexion(
            libelle: TextesCodeSecours.retourConnexion,
            libelleEnCours: TextesCodeSecours.retourConnexion,
            enCours: false,
            onPressed: () => context.go('/connexion'),
          ),
          const SizedBox(height: MesuresConnexion.piedHaut),
          pied,
        ],
      );
    }

    return CadreInvite(
      formulaire: _formulaire,
      enfants: [
        const MarqueConnexion(),
        const SizedBox(height: AppSpacing.md),
        const FiletConnexion(),
        const SizedBox(height: AppSpacing.md),
        titre,
        const SizedBox(height: AppSpacing.xxs),
        Text(
          TextesCodeSecours.accroche,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: Tailles.t15,
            color: AppColors.neutre500,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        ChampConnexion(
          etiquette: TextesCodeSecours.login,
          controleur: _login,
          trace: MesuresConnexion.traceUtilisateur,
          autofocus: true,
          indicesAutoRemplissage: const [AutofillHints.username],
          onSoumis: _soumettre,
          validateur: (v) => (v == null || v.trim().isEmpty)
              ? MessagesMotDePassePerdu.loginRequis
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        ChampSecretConnexion(
          etiquette: TextesCodeSecours.code,
          controleur: _code,
          onSoumis: _soumettre,
          validateur: (v) => (v == null || v.trim().isEmpty)
              ? MessagesMotDePassePerdu.codeRequis
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        ChampSecretConnexion(
          etiquette: TextesChangementMotDePasse.nouveau,
          controleur: _nouveau,
          indicesAutoRemplissage: const [AutofillHints.newPassword],
          onSoumis: _soumettre,
          validateur: (v) => (v == null || v.isEmpty)
              ? MessagesMotDePassePerdu.nouveauRequis
              : v.length < ReglesMotDePassePerdu.longueurMin
              ? MessagesMotDePassePerdu.tropCourt
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        ChampSecretConnexion(
          etiquette: TextesChangementMotDePasse.confirmation,
          controleur: _confirmation,
          indicesAutoRemplissage: const [AutofillHints.newPassword],
          onSoumis: _soumettre,
          validateur: (v) => (v == null || v.isEmpty)
              ? MessagesMotDePassePerdu.confirmationRequise
              : v != _nouveau.text
              ? TextesChangementMotDePasse.confirmationInvalide
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          TextesCodeSecours.regle,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: Tailles.t13,
            color: AppColors.neutre500,
          ),
        ),
        if (_erreur != null) ...[
          const SizedBox(height: AppSpacing.md),
          BandeauAlerteConnexion(message: _erreur!),
        ],
        const SizedBox(height: AppSpacing.md),
        BoutonPleinConnexion(
          libelle: TextesCodeSecours.bouton,
          libelleEnCours: TextesCodeSecours.enCours,
          enCours: _enCours,
          onPressed: _soumettre,
        ),
        const SizedBox(height: AppSpacing.md),
        retour,
        const SizedBox(height: MesuresConnexion.piedHaut),
        pied,
      ],
    );
  }
}
