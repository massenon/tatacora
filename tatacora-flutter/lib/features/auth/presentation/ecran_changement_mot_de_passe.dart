// Vue Blade maîtresse (PA-183) : pwa/livewire/changement-mot-de-passe-obligatoire.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/mesures_connexion.dart';
import '../domain/mot_de_passe_perdu.dart';
import 'ecran_connexion.dart';

/// Les libellés de l'écran — `lang/fr/pwa.php`, groupe `changement_mdp`, au
/// caractère près (un test les confronte à la langue du serveur, résolue par PHP).
abstract final class TextesChangementMotDePasse {
  /// `pwa.changement_mdp.titre_h1`.
  static const titre = 'Définissez votre nouveau mot de passe';

  /// `pwa.changement_mdp.accroche`.
  static const accroche =
      'Votre mot de passe a été réinitialisé par un administrateur. Choisissez '
      'maintenant un mot de passe que vous seul connaissez.';

  /// `pwa.changement_mdp.nouveau` / `confirmation`.
  static const nouveau = 'NOUVEAU MOT DE PASSE';
  static const confirmation = 'CONFIRMER LE NOUVEAU MOT DE PASSE';

  /// `pwa.changement_mdp.regle`.
  static const regle =
      "Min. 8 caractères, différent du mot de passe temporaire et de l'ancien.";

  /// `pwa.changement_mdp.bouton` / `en_cours` / `se_deconnecter`.
  static const bouton = 'ENREGISTRER';
  static const enCours = 'Enregistrement…';
  static const seDeconnecter = 'Se déconnecter';

  /// `pwa.profil.mdp_confirmation_invalide`.
  static const confirmationInvalide =
      'Le nouveau mot de passe et sa confirmation ne correspondent pas.';
}

/// « Définissez votre nouveau mot de passe » — la SEULE page qu'atteint un
/// compte dont le mot de passe a été réinitialisé par un administrateur (29/10/2026,
/// option A du PO). La garde du routeur ferme tout le reste tant que
/// `Session.changementObligatoire` est vrai.
///
/// Traduction de `pwa/livewire/changement-mot-de-passe-obligatoire.blade.php`,
/// dans la mise en page « invité » de la connexion (`CadreInvite`) : mêmes jetons,
/// mêmes pictogrammes, mêmes champs.
///
/// Règles : celles de « Mon profil » (8 caractères au moins, confirmation à
/// l'identique), PLUS différent du temporaire et de l'ancien
/// (`SessionRepositoryLocal.definirNouveauMotDePasse`). Après le changement la
/// session est FERMÉE : on se reconnecte avec le nouveau mot de passe (le message
/// est dit sur l'écran de connexion).
class EcranChangementMotDePasse extends ConsumerStatefulWidget {
  const EcranChangementMotDePasse({super.key});

  @override
  ConsumerState<EcranChangementMotDePasse> createState() =>
      _EtatEcranChangementMotDePasse();
}

class _EtatEcranChangementMotDePasse
    extends ConsumerState<EcranChangementMotDePasse> {
  final _formulaire = GlobalKey<FormState>();
  final _nouveau = TextEditingController();
  final _confirmation = TextEditingController();

  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _nouveau.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _soumettre() async {
    if (_enCours || !_formulaire.currentState!.validate()) return;
    final login = ref.read(sessionProvider)?.login;
    if (login == null) return;
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      // Laisse la fenêtre se redessiner (bouton grisé) avant la dérivation
      // PBKDF2, qui occupe le poste un instant.
      await Future<void>.delayed(Duration.zero);
      await ref
          .read(depotSessionProvider)
          .definirNouveauMotDePasse(login: login, nouveau: _nouveau.text);
      // La session est coupée : on se reconnecte avec le nouveau mot de passe.
      ref
          .read(infoConnexionProvider.notifier)
          .dire(MessagesMotDePassePerdu.succes);
      await ref.read(sessionProvider.notifier).deconnecter();
    } on RefusMotDePassePerdu catch (e) {
      if (!mounted) return;
      if (e.message == MessagesMotDePassePerdu.expire) {
        // Le temporaire a expiré pendant la saisie : plus rien ne s'ouvre avec.
        ref.read(infoConnexionProvider.notifier).dire(e.message);
        await ref.read(sessionProvider.notifier).deconnecter();
        return;
      }
      setState(() {
        _enCours = false;
        _erreur = e.message;
        _nouveau.clear();
        _confirmation.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CadreInvite(
      formulaire: _formulaire,
      enfants: [
        const MarqueConnexion(),
        const SizedBox(height: AppSpacing.md),
        const FiletConnexion(),
        const SizedBox(height: AppSpacing.md),
        // `text-[28px] font-extrabold leading-tight` navy.
        Semantics(
          header: true,
          child: Text(
            TextesChangementMotDePasse.titre,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontSize: Tailles.t28,
              fontWeight: FontWeight.w800,
              height: Tailles.interligneSerre,
              color: AppColors.navy,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          TextesChangementMotDePasse.accroche,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: Tailles.t15,
            color: AppColors.neutre500,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        ChampSecretConnexion(
          etiquette: TextesChangementMotDePasse.nouveau,
          controleur: _nouveau,
          autofocus: true,
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
          TextesChangementMotDePasse.regle,
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
          libelle: TextesChangementMotDePasse.bouton,
          libelleEnCours: TextesChangementMotDePasse.enCours,
          enCours: _enCours,
          onPressed: _soumettre,
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: TextButton(
            key: const Key('changement-se-deconnecter'),
            onPressed: _enCours
                ? null
                : () => ref.read(sessionProvider.notifier).deconnecter(),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.navy,
              textStyle: const TextStyle(
                fontSize: Tailles.t15,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text(TextesChangementMotDePasse.seDeconnecter),
          ),
        ),
        const SizedBox(height: MesuresConnexion.piedHaut),
        Text(
          TextesConnexion.piedDePage,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: Tailles.t13,
            color: AppColors.neutre500,
          ),
        ),
      ],
    );
  }
}
