// Vue Blade maîtresse (PA-183) : pwa/transverse/mon-profil.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/navigation/coquille_vue.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/mesures_transverses.dart';
import '../../../shared_widgets/bouton_standard.dart';
import '../../auth/domain/session_repository.dart';
import 'providers_transverses.dart';
import 'widgets/briques_transverses.dart';

/// L'écran **Mon profil** — lot D du plan du Product Owner (14/10/2026).
///
/// Structure de la vue, dans son ordre : en-tête ; métadonnées de session
/// (avatar aux initiales, login, rôle, trois cartes) ; informations
/// personnelles et mot de passe côte à côte ; journal d'audit des dernières
/// actions.
///
/// ## Ce qui vient du poste, et ce qui y manque (D422)
///
/// - **Login, rôle, initiales** : la session locale (`SessionRepositoryLocal`),
///   mises en forme comme la barre supérieure (`initialesDeLogin`,
///   `roleAffiche`).
/// - **Statut du compte** : `utilisateurs_local.actif`, relu (« Actif » /
///   « Désactivé », couleurs de `MonProfil::STATUTS`) ; « — » si la lecture
///   échoue.
/// - **Dernière connexion, adresse IP** : « — » — le poste ne relève ni l'une
///   ni l'autre (Article 7 de la vue : jamais une date inventée).
/// - **Nom complet** : la vue lit la fiche RH ; ce poste n'a pas de lien
///   compte → employé, il affiche le NOM DU COMPTE saisi à sa création
///   (`utilisateurs_local.nom`). Écart nommé.
/// - **Fonction** : « — » (aucune fiche RH rattachée).
/// - **Mot de passe** : RÉEL depuis le 14/10/2026 — la modale de la vue
///   (ancien, nouveau, confirmation) écrit par
///   `SessionRepositoryLocal.changerMotDePasse` : l'ancien est vérifié contre
///   le dérivé PBKDF2 stocké, le nouveau est dérivé comme à la création du
///   compte. La note de la vue (« ont lieu côté serveur ») est REMPLACÉE par
///   la phrase vraie (piège 13).
/// - **Journal d'audit** : la file d'envoi du poste ne conserve pas
///   l'utilisateur ; le tableau reste vide et le dit, après la phrase de la
///   vue (« Aucune action tracée pour ce compte »), vraie au sens strict.
class EcranMonProfil extends ConsumerWidget {
  const EcranMonProfil({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final droits = ref.watch(droitsProvider);
    final actif = ref.watch(compteSessionActifProvider);
    final large = MediaQuery.sizeOf(context).width >= AppBreakpoints.lg;

    final statut = switch (actif) {
      AsyncData(value: true) => (TextesProfil.statutActif, AppColors.succes),
      AsyncData(value: false) => (
        TextesProfil.statutDesactive,
        AppColors.erreur,
      ),
      _ => (TextesProfil.tiret, AppColors.navy),
    };

    final infos = _Informations(
      nom: session?.nom,
      versRoles: () {
        if (droits.peutLire(ModuleTatacora.roles)) {
          GoRouter.of(context).go('/roles-permissions');
        } else {
          direTransverse(context, LibellesCoquille.sansDroit);
        }
      },
    );
    const motDePasse = _MotDePasse();

    return PageTransverse(
      largeurMax: MesuresTransverses.pageProfil,
      enfants: [
        const EnTeteTransverse(
          trace: TracesCoquille.monProfil,
          titre: TextesProfil.titre,
          sousTitre: TextesProfil.sousTitre,
        ),
        _Metadonnees(
          login: session?.login,
          role: session == null ? null : roleAffiche(session.role),
          statut: statut.$1,
          couleurStatut: statut.$2,
        ),
        const SizedBox(height: AppSpacing.mdPlus), // mb-5
        if (large)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: infos),
                const SizedBox(width: AppSpacing.mdPlus),
                const Expanded(child: motDePasse),
              ],
            ),
          )
        else ...[
          infos,
          const SizedBox(height: AppSpacing.mdPlus),
          motDePasse,
        ],
        const SizedBox(height: AppSpacing.mdPlus),
        _JournalProfil(
          versJournal: () {
            if (droits.peutLire(ModuleTatacora.m14Etats)) {
              GoRouter.of(context).go('/journal-audit');
            } else {
              direTransverse(context, LibellesCoquille.sansDroit);
            }
          },
        ),
      ],
    );
  }
}

/// Les textes de la vue (`pwa.profil.*`), au mot.
abstract final class TextesProfil {
  static const String titre = 'Mon profil';
  static const String sousTitre =
      'Vos informations personnelles, votre mot de passe et la trace de vos dernières actions dans le système.';
  static const String metadonnees = 'MÉTADONNÉES DE SESSION';
  static const String derniereConnexion = 'Dernière connexion';
  static const String adresseIp = 'Adresse IP du poste';
  static const String statutCompte = 'Statut du compte';
  static const String noteIp =
      "L'adresse IP affichée est celle relevée par le poste. Sur l'application réelle elle vient du serveur : une adresse déclarée par le navigateur ne prouve rien et ne doit jamais servir de contrôle d'accès.";
  static const String infosTitre = 'Informations personnelles';
  static const String nomComplet = 'Nom complet';
  static const String email = 'Email';
  static const String telephone = 'Téléphone';
  static const String fonction = 'Fonction';
  static const String exempleEmail = 'ex. nom@tatacora.com';
  static const String exempleTelephone = '+229 01 XX XX XX XX';
  static const String noteFonctionAvant =
      "La fonction et les droits d'accès (RBAC) sont gérés par l'administrateur système — voir ";
  static const String noteFonctionLien = 'Rôles & Permissions';
  static const String noteFonctionApres =
      '. Un utilisateur qui pourrait modifier sa propre fonction contournerait la matrice de droits en un clic.';
  static const String mdpTitre = 'Modifier le mot de passe';
  static const String mdpSousTitre =
      'Le changement est immédiat et ne ferme pas votre session.';
  static const String mdpOuvrir = 'Modifier le mot de passe';
  static const String journalTitre = "Journal d'audit — 10 dernières actions";
  static const String journalSousTitre =
      'Vos actions uniquement. Le journal complet, tous utilisateurs, est réservé aux profils qui y ont droit.';
  static const String journalComplet = 'Journal complet →';
  static const String colDateHeure = 'DATE / HEURE';
  static const String colAction = 'ACTION';
  static const String colModule = 'MODULE';
  static const String colIp = 'IP';

  /// `MonProfil::STATUTS`.
  static const String statutActif = 'Actif';
  static const String statutDesactive = 'Désactivé';
  static const String tiret = '—';

  /// AJOUTS déclarés (D422).
  /// `pwa.profil.sans_fiche_rh` (mot pour mot : vraie ici, aucun compte du
  /// poste n'est lié à un employé) suivie de ce que le poste affiche à la
  /// place d'un nom de fiche.
  static const String sansFicheRhPoste =
      "Aucune fiche employé n'est rattachée à ce compte.";

  /// La modale « Modifier le mot de passe » (`pwa.profil.mdp_*`).
  static const String mdpAncien = 'Ancien mot de passe';
  static const String mdpNouveau = 'Nouveau mot de passe';
  static const String mdpConfirmation = 'Confirmer le nouveau mot de passe';
  static const String mdpRegle = 'Min. 8 caractères.';
  static const String mdpBouton = 'Mettre à jour le mot de passe';
  static const String mdpConfirmationInvalide =
      'Le nouveau mot de passe et sa confirmation ne correspondent pas.';
  static const String mdpObligatoire = 'Ce champ est obligatoire.';
  static const String mdpMiseAJour = 'Mot de passe mis à jour.';
  static const String annuler = 'Annuler';

  /// `pwa.profil.journal_vide` (« Aucune action tracée pour ce compte. »),
  /// vraie ici au sens strict : la file d'envoi du poste ne conserve pas
  /// l'utilisateur, aucune action n'est donc tracée AU NOM de ce compte ; le
  /// journal complet du poste (Journal d'Audit) liste ce que le poste a écrit.
  static const String journalSurCePoste = 'Aucune action tracée pour ce compte.';
}

TextStyle get _etiquette =>
    styleTransverse(TaillesContenu.t12, couleur: Ardoise.c500);

class _Metadonnees extends StatelessWidget {
  const _Metadonnees({
    required this.login,
    required this.role,
    required this.statut,
    required this.couleurStatut,
  });

  final String? login;
  final String? role;
  final String statut;
  final Color couleurStatut;

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.sizeOf(context).width >= AppBreakpoints.sm;
    Widget meta(String titre, String valeur, Color couleur, {Key? cle}) =>
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.smPlus,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: Ardoise.c50,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: Ardoise.c100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titre, style: _etiquette),
              const SizedBox(height: AppSpacing.demi),
              Text(
                valeur,
                key: cle,
                style: styleTransverse(
                  TaillesContenu.t15,
                  poids: FontWeight.w600,
                  couleur: couleur,
                  police: AppTextStyles.policeMonospace,
                ),
              ),
            ],
          ),
        );

    final cartes = [
      meta(
        TextesProfil.derniereConnexion,
        TextesProfil.tiret,
        AppColors.navy,
        cle: const Key('profil-meta-connexion'),
      ),
      meta(
        TextesProfil.adresseIp,
        TextesProfil.tiret,
        AppColors.navy,
        cle: const Key('profil-meta-ip'),
      ),
      meta(
        TextesProfil.statutCompte,
        statut,
        couleurStatut,
        cle: const Key('profil-meta-statut'),
      ),
    ];

    return CarteTransverse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: MesuresTransverses.avatarProfil,
                height: MesuresTransverses.avatarProfil,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.gold,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  login == null ? TextesProfil.tiret : initialesDeLogin(login!),
                  key: const Key('profil-avatar'),
                  style: styleTransverse(
                    TaillesContenu.lg,
                    poids: FontWeight.bold,
                    couleur: AppColors.neutre0,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      login ?? TextesProfil.tiret,
                      key: const Key('profil-login'),
                      style: styleTransverse(
                        TaillesContenu.base,
                        poids: FontWeight.bold,
                        couleur: AppColors.navy,
                      ),
                    ),
                    Text(
                      role ?? TextesProfil.tiret,
                      key: const Key('profil-role'),
                      style: styleTransverse(
                        TaillesContenu.t13,
                        couleur: Ardoise.c500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            TextesProfil.metadonnees,
            style:
                styleTransverse(
                  TaillesContenu.t13,
                  poids: FontWeight.bold,
                  couleur: Ardoise.c400,
                ).copyWith(
                  letterSpacing:
                      AppTextStyles.suiviPlusLarge * TaillesContenu.t13,
                ),
          ),
          const SizedBox(height: AppSpacing.xsPlus),
          if (large)
            Row(
              children: [
                for (final (i, c) in cartes.indexed) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.sm),
                  Expanded(child: c),
                ],
              ],
            )
          else
            for (final (i, c) in cartes.indexed) ...[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              c,
            ],
          const SizedBox(height: AppSpacing.xsPlus),
          Text(
            TextesProfil.noteIp,
            style: styleTransverse(TaillesContenu.t12, couleur: Ardoise.c400),
          ),
        ],
      ),
    );
  }
}

/// « Informations personnelles » : quatre champs en LECTURE (la vue les rend
/// en `<p>` grisés), puis l'encart bleu de la fonction.
class _Informations extends StatelessWidget {
  const _Informations({required this.nom, required this.versRoles});

  final String? nom;
  final VoidCallback versRoles;

  @override
  Widget build(BuildContext context) {
    Widget champ(
      String libelle,
      String valeur, {
      String? note,
      Key? cle,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.smPlus),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            libelle,
            style: styleTransverse(
              TaillesContenu.t15,
              poids: FontWeight.w600,
              couleur: Ardoise.c700,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xsPlus,
            ),
            decoration: BoxDecoration(
              color: Ardoise.c100,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: Ardoise.c200),
            ),
            child: Text(
              valeur,
              key: cle,
              style: styleTransverse(TaillesContenu.sm, couleur: Ardoise.c600),
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: AppSpacing.unit),
            Text(
              note,
              style: styleTransverse(TaillesContenu.t12, couleur: Ardoise.c400),
            ),
          ],
        ],
      ),
    );

    final bleu = styleTransverse(
      TaillesContenu.t13,
      couleur: PaletteMaitre.bleu900,
    );
    return CarteTransverse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            TextesProfil.infosTitre,
            style: styleTransverse(
              TaillesContenu.sm,
              poids: FontWeight.bold,
              couleur: Ardoise.c700,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          champ(
            TextesProfil.nomComplet,
            (nom == null || nom!.trim().isEmpty) ? TextesProfil.tiret : nom!,
            note: TextesProfil.sansFicheRhPoste,
            cle: const Key('profil-nom-complet'),
          ),
          champ(
            TextesProfil.email,
            TextesProfil.tiret,
            note: TextesProfil.exempleEmail,
          ),
          champ(
            TextesProfil.telephone,
            TextesProfil.tiret,
            note: TextesProfil.exempleTelephone,
          ),
          champ(TextesProfil.fonction, TextesProfil.tiret),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xsPlus,
            ),
            decoration: BoxDecoration(
              color: AppColors.badgeBleuFond,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Wrap(
              children: [
                Text(TextesProfil.noteFonctionAvant, style: bleu),
                InkWell(
                  key: const Key('profil-lien-roles'),
                  onTap: versRoles,
                  child: Text(
                    TextesProfil.noteFonctionLien,
                    style: bleu.copyWith(
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                Text(TextesProfil.noteFonctionApres, style: bleu),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// « Modifier le mot de passe » : titre, sous-titre et le bouton doré.
class _MotDePasse extends StatelessWidget {
  const _MotDePasse();

  @override
  Widget build(BuildContext context) => CarteTransverse(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          TextesProfil.mdpTitre,
          style: styleTransverse(
            TaillesContenu.sm,
            poids: FontWeight.bold,
            couleur: Ardoise.c700,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          TextesProfil.mdpSousTitre,
          style: styleTransverse(TaillesContenu.t13, couleur: Ardoise.c500),
        ),
        const SizedBox(height: AppSpacing.md),
        BoutonTransverse(
          cle: const Key('profil-mdp-ouvrir'),
          libelle: TextesProfil.mdpOuvrir,
          fond: AppColors.gold,
          taille: TaillesContenu.sm,
          pleineLargeur: true,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.mdPlus,
            vertical: AppSpacing.xsPlus,
          ),
          onTap: () => _ouvrirModaleMotDePasse(context),
        ),
      ],
    ),
  );
}

Future<void> _ouvrirModaleMotDePasse(BuildContext context) async {
  final fait = await showDialog<bool>(
    context: context,
    barrierColor: AppColors.voileModale,
    builder: (_) => const _ModaleMotDePasse(),
  );
  if (fait == true && context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.succes,
          content: Text(
            TextesProfil.mdpMiseAJour,
            key: Key('profil-mdp-mis-a-jour'),
          ),
        ),
      );
  }
}

/// La modale « Modifier le mot de passe » — fenêtre COMPACTE (`Dialog` borné
/// à 480 px, la largeur de la vue), trois champs masqués, la note, puis
/// « Annuler » / « Mettre à jour le mot de passe ». Les saisies sont vidées
/// après chaque tentative refusée de l'ancien mot de passe, comme au
/// serveur : un mot de passe soumis ne survit pas à l'échec de sa
/// vérification.
class _ModaleMotDePasse extends ConsumerStatefulWidget {
  const _ModaleMotDePasse();

  @override
  ConsumerState<_ModaleMotDePasse> createState() => _ModaleMotDePasseState();
}

class _ModaleMotDePasseState extends ConsumerState<_ModaleMotDePasse> {
  final _ancien = TextEditingController();
  final _nouveau = TextEditingController();
  final _confirmation = TextEditingController();
  String? _erreurAncien;
  String? _erreurNouveau;
  String? _erreurConfirmation;
  bool _enCours = false;

  @override
  void dispose() {
    _ancien.dispose();
    _nouveau.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (_enCours) return;
    final ancien = _ancien.text;
    final nouveau = _nouveau.text;
    final confirmation = _confirmation.text;

    // Les règles de saisie du serveur, dans son ordre.
    setState(() {
      _erreurAncien = ancien.isEmpty ? TextesProfil.mdpObligatoire : null;
      _erreurNouveau = nouveau.isEmpty
          ? TextesProfil.mdpObligatoire
          : nouveau.length < 8
          ? TextesProfil.mdpRegle
          : null;
      _erreurConfirmation = confirmation.isEmpty
          ? TextesProfil.mdpObligatoire
          : null;
    });
    if (_erreurAncien != null ||
        _erreurNouveau != null ||
        _erreurConfirmation != null) {
      return;
    }
    if (nouveau != confirmation) {
      setState(
        () => _erreurConfirmation = TextesProfil.mdpConfirmationInvalide,
      );
      return;
    }

    final login = ref.read(sessionProvider)?.login;
    if (login == null) return;
    setState(() => _enCours = true);
    // Laisse la fenêtre se redessiner (bouton grisé) avant la dérivation
    // PBKDF2, qui occupe le poste un instant.
    await Future<void>.delayed(Duration.zero);
    try {
      await ref
          .read(depotSessionProvider)
          .changerMotDePasse(login: login, ancien: ancien, nouveau: nouveau);
      if (mounted) Navigator.of(context).pop(true);
    } on EchecConnexion catch (e) {
      if (!mounted) return;
      final identique = nouveau == ancien;
      setState(() {
        _enCours = false;
        if (identique) {
          _erreurNouveau = e.message;
        } else {
          _erreurAncien = e.message;
          _ancien.clear();
          _nouveau.clear();
          _confirmation.clear();
        }
      });
    }
  }

  Widget _champ({
    required Key cle,
    required String libelle,
    required TextEditingController controleur,
    required String? erreur,
    required List<String> autofill,
    String? aide,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          libelle,
          style: styleTransverse(
            TaillesContenu.t15,
            poids: FontWeight.w600,
            couleur: Ardoise.c700,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        TextField(
          key: cle,
          controller: controleur,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: autofill,
          enabled: !_enCours,
          onSubmitted: (_) => _valider(),
          style: styleTransverse(TaillesContenu.sm),
          decoration: InputDecoration(
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: const BorderSide(color: Ardoise.c200),
            ),
          ),
        ),
        if (erreur != null) ...[
          const SizedBox(height: AppSpacing.unit),
          Text(
            erreur,
            style: styleTransverse(
              TaillesContenu.t12,
              couleur: AppColors.erreur,
            ),
          ),
        ],
        if (aide != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            aide,
            style: styleTransverse(TaillesContenu.t12, couleur: Ardoise.c400),
          ),
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('profil-mdp-modale'),
      backgroundColor: AppColors.neutre0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: MesuresTransverses.modaleMotDePasse,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                TextesProfil.mdpTitre,
                style: styleTransverse(
                  TaillesContenu.base,
                  poids: FontWeight.bold,
                  couleur: AppColors.navy,
                ),
              ),
              const SizedBox(height: AppSpacing.unit),
              Text(
                TextesProfil.mdpSousTitre,
                style: styleTransverse(
                  TaillesContenu.t13,
                  couleur: Ardoise.c500,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _champ(
                cle: const Key('profil-mdp-ancien'),
                libelle: TextesProfil.mdpAncien,
                controleur: _ancien,
                erreur: _erreurAncien,
                autofill: const [AutofillHints.password],
              ),
              _champ(
                cle: const Key('profil-mdp-nouveau'),
                libelle: TextesProfil.mdpNouveau,
                controleur: _nouveau,
                erreur: _erreurNouveau,
                autofill: const [AutofillHints.newPassword],
                aide: TextesProfil.mdpRegle,
              ),
              _champ(
                cle: const Key('profil-mdp-confirmation'),
                libelle: TextesProfil.mdpConfirmation,
                controleur: _confirmation,
                erreur: _erreurConfirmation,
                autofill: const [AutofillHints.newPassword],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  BoutonStandard(
                    key: const Key('profil-mdp-annuler'),
                    libelle: TextesProfil.annuler,
                    onPressed: _enCours
                        ? null
                        : () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  BoutonStandard(
                    key: const Key('profil-mdp-valider'),
                    variante: VarianteBouton.or,
                    libelle: TextesProfil.mdpBouton,
                    onPressed: _enCours ? null : _valider,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Le journal des dernières actions : titre, « Journal complet → », tableau à
/// en-tête navy, et la raison de son vide.
class _JournalProfil extends StatelessWidget {
  const _JournalProfil({required this.versJournal});

  final VoidCallback versJournal;

  @override
  Widget build(BuildContext context) => CarteTransverse(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.mdPlus,
            vertical: AppSpacing.md,
          ),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Ardoise.c100)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      TextesProfil.journalTitre,
                      style: styleTransverse(
                        TaillesContenu.sm,
                        poids: FontWeight.bold,
                        couleur: Ardoise.c700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.demi),
                    Text(
                      TextesProfil.journalSousTitre,
                      style: styleTransverse(
                        TaillesContenu.t12,
                        couleur: Ardoise.c500,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                key: const Key('profil-journal-complet'),
                onTap: versJournal,
                child: Text(
                  TextesProfil.journalComplet,
                  style: styleTransverse(
                    TaillesContenu.t13,
                    poids: FontWeight.w600,
                    couleur: AppColors.navy,
                  ),
                ),
              ),
            ],
          ),
        ),
        const TableauTransverse(
          colonnes: [
            (titre: TextesProfil.colDateHeure, alignement: TextAlign.left),
            (titre: TextesProfil.colAction, alignement: TextAlign.left),
            (titre: TextesProfil.colModule, alignement: TextAlign.left),
            (titre: TextesProfil.colIp, alignement: TextAlign.left),
          ],
          lignes: [],
          vide: TextesProfil.journalSurCePoste,
          cleVide: Key('profil-journal-vide'),
        ),
      ],
    ),
  );
}
