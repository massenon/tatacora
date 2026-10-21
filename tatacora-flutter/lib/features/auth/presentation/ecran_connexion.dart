// Vue Blade maîtresse (PA-183) : pwa/livewire/connexion.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/navigation/coquille_vue.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_assets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../domain/session_repository.dart';
import 'formulaire_premier_compte.dart';

/// Écran de connexion — **traduction de `prototype_v2/pages/login.html`**.
///
/// ## Le maître de mise en page
///
/// `prototype_v2/` est la référence, tranchée par le Product Owner le
/// 21/08/2026. Cet écran n'est pas une conception : c'est une traduction, et
/// chaque valeur ci-dessous est relevée dans le HTML, jamais estimée.
///
/// Structure du maître (l.12-24) : `<body class="h-screen flex">`, donc deux
/// colonnes côte à côte.
///
///  - **colonne image** `hidden lg:block lg:w-1/2` — `gite-cover.jpg` en
///    `object-cover`, voile en dégradé, et un bloc de texte aligné **en bas**
///    (`justify-end p-12`) portant le logo, le titre et l'accroche ;
///  - **colonne formulaire** `flex-1 flex items-center justify-center p-6`,
///    contenu borné à `max-w-sm` (384 px).
///
/// Le seuil `lg` de Tailwind vaut 1024 px, exactement [Breakpoints.desktop].
/// En deçà, la colonne image disparaît et le logo réapparaît au-dessus du
/// formulaire (`lg:hidden`, l.26-28) — ce n'est pas une simplification, c'est
/// le comportement responsive du maître.
///
/// ## Ce que cet écran ne contient PAS, et pourquoi
///
/// **Aucune grille de comptes cliquables. Aucun raccourci de connexion par
/// rôle.** Le maître en affiche une (l.54-67) ; `SECURITY_STRICT.md` §12
/// l'interdit dans **tout** environnement, y compris le flavor `demo`. La
/// raison n'est pas théorique : une grille qui pré-remplit le mot de passe
/// transforme chaque capture d'écran de formation, chaque démonstration filmée
/// et chaque poste laissé ouvert en fuite d'identifiants.
///
/// **L'exclusion emporte le séparateur, et c'est le point qu'une lecture rapide
/// inverse.** Le séparateur `my-6` à deux filets (l.47-51) ne porte pas un
/// titre neutre : il annonce littéralement « Comptes de démonstration (RBAC) »,
/// et le paragraphe suivant invite à « cliquer pour vous connecter
/// instantanément ». Les trois n'existent que pour introduire la grille
/// interdite. Les porter sans elle laisserait un intitulé qui n'annonce rien —
/// **moins fidèle** que de les retirer ensemble. Privé de sa grille, le maître
/// va du bouton « Se connecter » au pied de page.
class EcranConnexion extends ConsumerStatefulWidget {
  const EcranConnexion({super.key});

  @override
  ConsumerState<EcranConnexion> createState() => _EtatEcranConnexion();
}

class _EtatEcranConnexion extends ConsumerState<EcranConnexion> {
  final _formulaire = GlobalKey<FormState>();
  final _identifiant = TextEditingController();
  final _motDePasse = TextEditingController();

  bool _enCours = false;
  bool _masque = true;
  String? _erreur;

  @override
  void dispose() {
    _identifiant.dispose();
    _motDePasse.dispose();
    super.dispose();
  }

  Future<void> _soumettre() async {
    if (!_formulaire.currentState!.validate()) return;
    setState(() {
      _enCours = true;
      _erreur = null;
    });

    try {
      await ref
          .read(sessionProvider.notifier)
          .connecter(_identifiant.text.trim(), _motDePasse.text);
    } on EchecConnexion catch (e) {
      if (mounted) setState(() => _erreur = e.message);
    } on ReseauIndisponible {
      // Message distinct d'un refus d'identifiants : sans cette distinction,
      // l'utilisateur ressaisit son mot de passe alors que le serveur est
      // simplement injoignable.
      if (mounted) {
        setState(
          () => _erreur = 'Serveur injoignable. Vérifiez la connexion réseau.',
        );
      }
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // `MediaQuery`, et non `LayoutBuilder` : la largeur du CONTENU n'est pas
    // celle de l'écran. Décider d'une mise en page sur `constraints.maxWidth`
    // est le défaut de responsive le plus courant — ici les deux coïncident,
    // mais s'y fier installerait l'habitude qui se trompe ailleurs.
    final deuxColonnes = Breakpoints.de(context) == Palier.desktop;

    return Scaffold(
      // `<body style="background:var(--fond-clair)">` — #F2F2F2.
      backgroundColor: AppColors.fondClair,
      body: SafeArea(
        child: Row(
          children: [
            // `hidden lg:block lg:w-1/2` — la moitié exacte, pas une
            // proportion approchée.
            if (deuxColonnes) const Expanded(child: _ColonneImage()),
            Expanded(child: _colonneFormulaire(context, deuxColonnes)),
          ],
        ),
      ),
    );
  }

  /// `flex-1 flex items-center justify-center p-6 overflow-y-auto` (l.24).
  Widget _colonneFormulaire(BuildContext context, bool deuxColonnes) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg), // p-6 = 24
      child: Center(
        child: ConstrainedBox(
          // `w-full max-w-sm py-8` — max-w-sm vaut 384 px.
          constraints: const BoxConstraints(maxWidth: Largeurs.maxSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Form(
              key: _formulaire,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // `lg:hidden` (l.26-28) : le logo ne réapparaît au-dessus du
                  // formulaire QUE lorsque la colonne image a disparu. Le
                  // montrer dans les deux cas le ferait figurer deux fois.
                  if (!deuxColonnes) ...[
                    const Center(child: _Logo(cote: 56)), // w-14 h-14
                    const SizedBox(height: AppSpacing.lg), // mb-6
                  ],

                  // `text-xl font-bold text-center mb-1` couleur navy.
                  Text(
                    'TATACORA AFRIQUE',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: Tailles.t20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.unit), // mb-1
                  // `text-[15px] text-slate-400 text-center mb-6`
                  Text(
                    'Connectez-vous à votre espace de travail',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: Tailles.t15,
                      color: AppColors.neutre500,
                    ),
                  ),

                  // Pastille « Environnement : … » RETIRÉE le 14/10/2026 —
                  // demande du PO : la vue de connexion n'en a pas, le
                  // formulaire suit directement le sous-titre.
                  const SizedBox(height: AppSpacing.lg), // mb-6
                  // **Poste vierge : on cede la place a la creation du premier
                  // compte.** L'authentification etant locale (PA-103), un
                  // poste neuf n'a aucun compte, et afficher un formulaire qui
                  // refusera tout ce qu'on y saisit ferait croire a une faute
                  // de frappe. La colonne image, elle, ne bouge pas.
                  ...switch (ref.watch(aucunCompteProvider)) {
                    AsyncData(value: true) => const [FormulairePremierCompte()],
                    AsyncData() => _formulaireConnexion(context),
                    // Tant que la reponse n'est pas connue, on n'affiche NI
                    // l'un NI l'autre : proposer une connexion puis la
                    // remplacer par une creation ferait clignoter l'ecran
                    // d'ouverture.
                    _ => const [
                      Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    ],
                  },
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Le formulaire de connexion proprement dit — l.31-45 du maitre.
  List<Widget> _formulaireConnexion(BuildContext context) {
    final theme = Theme.of(context);
    return [
      _Champ(
        etiquette: 'Identifiant',
        child: TextFormField(
          controller: _identifiant,
          autofillHints: const [AutofillHints.username],
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            hintText: 'ex. n.nabogou', // placeholder du maître
          ),
          validator: (v) => (v == null || v.trim().isEmpty)
              // Message du maître, `data-regle-requis` l.34.
              ? 'Veuillez saisir votre identifiant.'
              : null,
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      _Champ(
        etiquette: 'Mot de passe',
        child: TextFormField(
          controller: _motDePasse,
          obscureText: _masque,
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _soumettre(),
          decoration: InputDecoration(
            hintText: '••••••••', // placeholder du maître
            // ÉCART DÉLIBÉRÉ — absent du maître (l.39).
            // Le maître est manipulé au clavier physique ; le
            // poste du comptoir peut être tactile, où une saisie
            // invisible se retape entièrement à la moindre faute.
            suffixIcon: IconButton(
              icon: Icon(_masque ? Icons.visibility : Icons.visibility_off),
              // `:aria-label` de la vue (`pwa.connexion.afficher_mot_de_passe` /
              // `masquer_mot_de_passe`) : la phrase entière, pas un mot.
              tooltip: _masque
                  ? 'Afficher le mot de passe'
                  : 'Masquer le mot de passe',
              onPressed: () => setState(() => _masque = !_masque),
            ),
          ),
          validator: (v) => (v == null || v.isEmpty)
              // Message du maître, `data-regle-requis` l.39.
              ? 'Veuillez saisir votre mot de passe.'
              : null,
        ),
      ),

      // `#erreur-identifiants` (l.41) : masqué tant qu'aucun refus
      // n'a eu lieu, puis rouge sur fond rouge très clair.
      if (_erreur != null) ...[
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, // px-3
            vertical: AppSpacing.xs, // py-2
          ),
          decoration: BoxDecoration(
            color: AppColors.erreurFondLeger,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.erreurBordure),
          ),
          child: Text(
            // Le maître préfixe d'un « ⚠ ». Conservé : le signe
            // porte l'alerte pour qui distingue mal le rouge.
            '⚠ $_erreur',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: Tailles.t15,
              color: AppColors.erreur,
            ),
          ),
        ),
      ],

      const SizedBox(height: AppSpacing.md), // space-y-4
      // `btn w-full py-3 rounded-lg text-white text-sm font-semibold`
      ElevatedButton(
        onPressed: _enCours ? null : _soumettre,
        child: _enCours
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.neutre0,
                ),
              )
            : const Text('Se connecter'),
      ),

      // `text-center text-[13px] text-slate-400 mt-8` (l.57).
      const SizedBox(height: AppSpacing.xl),
      Text(
        'TATACORA AFRIQUE © 2026 — PAEB / FAGUEZ SARL',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          fontSize: Tailles.t13,
          color: AppColors.neutre500,
        ),
      ),
    ];
  }
}

/// La colonne image — `hidden lg:block lg:w-1/2 relative` (l.14-22).
///
/// Trois plans superposés, dans cet ordre : la photo en `object-cover`, le
/// voile en dégradé, puis le texte. C'est un `Stack`, pas une `Column` : le
/// texte se pose SUR la photo.
class _ColonneImage extends StatelessWidget {
  const _ColonneImage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        // `absolute inset-0 w-full h-full object-cover`
        Image.asset(
          'assets/img/gite-cover.jpg',
          fit: BoxFit.cover,
          // La photo est EMBARQUÉE, jamais chargée du réseau : la connexion
          // doit s'afficher entière au Gîte, hors ligne.
          semanticLabel: 'Gîte Chez Noël, Natitingou',
        ),

        // `linear-gradient(180deg, rgba(20,33,61,.2), rgba(20,33,61,.85))`
        // Le navy du dépôt EST rgb(20,33,61) : les deux arrêts se dérivent
        // donc de `AppColors.navy`, ils ne se recopient pas en hexadécimal.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.navy.withValues(alpha: 0.20),
                AppColors.navy.withValues(alpha: 0.85),
              ],
            ),
          ),
        ),

        // `relative z-10 h-full flex flex-col justify-end p-12 text-white`
        Padding(
          padding: const EdgeInsets.all(AppSpacingLarge.p12), // p-12
          child: Column(
            // `justify-end` : le bloc est collé EN BAS, pas centré.
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Logo(cote: 64), // w-16 h-16
              const SizedBox(height: AppSpacing.lg), // mb-6
              // `text-3xl font-bold mb-2 leading-tight` — le maître force le
              // retour à la ligne par un <br>, il ne le laisse pas au hasard
              // de la largeur disponible.
              Text(
                // `pwa.connexion.titre_panneau`, au mot près : le saut de
                // ligne est celui de son `<br>`, qui tient le titre sur deux
                // lignes à la césure voulue. DÉCISION DU PRODUCT OWNER DU
                // 13/10/2026 (PA-208, D385) : la vue écrit désormais
                // une mention propre à la place du nom d'un autre produit —
                // elle a été corrigée d'abord, ce client la suit. Seconde
                // décision du même jour (PA-209, D389) : la mention est
                // « Système de gestion Intégré », casse exacte du PO.
                'Système de gestion Intégré\nTATACORA AFRIQUE',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontSize: Tailles.t30,
                  fontWeight: FontWeight.bold,
                  height: Tailles.interligneSerre, // leading-tight
                  color: AppColors.neutre0,
                ),
              ),
              const SizedBox(height: AppSpacing.xs), // mb-2
              // `text-white/70 text-sm max-w-md`
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: Largeurs.maxMd),
                child: Text(
                  'Hébergement, restauration, tourisme, véhicules, achats, '
                  'stocks, comptabilité et ressources humaines — une seule '
                  'plateforme, pour le Gîte Chez Noël à Natitingou.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: Tailles.t14,
                    color: AppColors.neutre0.withValues(alpha: 0.70),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Le logo cerclé d'or — `rounded-xl ring-2 ring-[var(--gold)] object-contain`.
///
/// Deux tailles au maître, et une seule différence entre elles : le côté.
/// 64 px dans la colonne image, 56 px au-dessus du formulaire en étroit.
///
/// Décision du PO du 14/10/2026 (D392, PA-210) : le logo est un PNG
/// PAYSAGE ; la vue de connexion garde son cadre carré et passe
/// d'`object-cover` (qui le rognait) à `object-contain` — `BoxFit.contain`,
/// jamais d'étirement. Les bandes libres restent transparentes, comme dans
/// la vue (le conteneur n'a pas de fond).
class _Logo extends StatelessWidget {
  const _Logo({required this.cote});

  final double cote;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: cote,
      height: cote,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg), // rounded-xl
        border: Border.all(color: AppColors.gold, width: 2), // ring-2
      ),
      clipBehavior: Clip.antiAlias,
      // `alt="{{ __('pwa.alt_logo') }}"` : le texte de remplacement du logo.
      child: Image.asset(
        AppAssets.logo,
        fit: BoxFit.contain,
        semanticLabel: LibellesCoquille.altLogo,
      ),
    );
  }
}

/// Un groupe étiquette + champ — `.groupe-champ` du maître (l.32-36).
///
/// L'étiquette est un `<label>` AU-DESSUS du champ, avec un astérisque rouge,
/// et non un `labelText` flottant de Material : ce sont deux mises en page
/// différentes, et c'est la première que le commanditaire a validée.
class _Champ extends StatelessWidget {
  const _Champ({required this.etiquette, required this.child});

  final String etiquette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // `block text-[15px] font-semibold text-slate-700 mb-1.5`
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: etiquette),
              // `<span class="text-red-500">*</span>`
              TextSpan(
                text: ' *',
                style: TextStyle(color: AppColors.erreur),
              ),
            ],
          ),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: Tailles.t15,
            fontWeight: FontWeight.w600,
            color: AppColors.neutre700,
          ),
        ),
        const SizedBox(height: 6), // mb-1.5
        child,
      ],
    );
  }
}
