// Vue Blade maîtresse (PA-183) : pwa/livewire/connexion.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/navigation/coquille_vue.dart';
import '../../../core/navigation/trace_svg.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_durations.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/mesures_connexion.dart';
import '../../parametres/data/apparence_poste.dart';
import '../data/identifiant_memorise.dart';
import '../domain/session_repository.dart';
import 'formulaire_premier_compte.dart';

/// Les libellés de l'écran — `lang/fr/pwa.php`, groupe `connexion`, au
/// caractère près (`ecran_connexion_test.dart` les confronte à la langue du
/// serveur, résolue par PHP : une copie qui dérive fait rougir).
abstract final class TextesConnexion {
  /// `pwa.connexion.titre_h1` — le `<h1>` de la vue, masqué à l'œil.
  static const titreH1 = 'Connexion';

  /// `pwa.connexion.marque_logi` / `marque_restock` — la marque en deux tons.
  static const marqueLogi = 'Logi';
  static const marqueRestock = 'ReStock';

  /// `pwa.marque`.
  static const sousMarque = 'TATACORA AFRIQUE';

  /// `pwa.connexion.slogan`.
  static const slogan = 'VOTRE LOGICIEL DE GESTION INTÉGRÉE';

  /// `pwa.connexion.modules.*` — l'infobulle de chaque pictogramme du bandeau.
  static const restauration = 'Restauration';
  static const hebergement = 'Hébergement';
  static const ecoTourisme = 'Éco-tourisme';
  static const stock = 'Stock';
  static const location = 'Location';
  static const caisse = 'Caisse';
  static const comptabilite = 'Comptabilité';

  /// `pwa.connexion.bandeau_modules`.
  static const bandeauModules = 'Modules de LogiReStock';

  /// `pwa.connexion.bienvenue` / `accroche`.
  static const bienvenue = 'Bienvenue !';
  static const accroche =
      "Connectez-vous à votre espace d'administration LogiReStock.";

  /// `pwa.connexion.login` / `mot_de_passe`.
  static const login = "NOM D'UTILISATEUR OU E-MAIL";
  static const motDePasse = 'MOT DE PASSE';

  /// `pwa.connexion.afficher_mot_de_passe` / `masquer_mot_de_passe`.
  static const afficherMotDePasse = 'Afficher le mot de passe';
  static const masquerMotDePasse = 'Masquer le mot de passe';

  /// `pwa.connexion.se_souvenir` / `mot_de_passe_oublie` /
  /// `mot_de_passe_oublie_aide`.
  static const seSouvenir = 'Se souvenir de moi';
  static const motDePasseOublie = 'Mot de passe oublié ?';
  static const motDePasseOublieAide = "Contactez l'administrateur";

  /// `pwa.connexion.valider` / `connexion_en_cours`.
  static const valider = 'SE CONNECTER';
  static const connexionEnCours = 'Connexion…';

  /// `pwa.pied_de_page`.
  static const piedDePage = 'TATACORA AFRIQUE © 2026 — PAEB / FAGUEZ SARL';

  /// Les refus de saisie (`data-regle-requis` du maître, historiques).
  static const identifiantRequis = 'Veuillez saisir votre identifiant.';
  static const motDePasseRequis = 'Veuillez saisir votre mot de passe.';
}

/// Écran de connexion — **traduction de `pwa/livewire/connexion.blade.php`**
/// (refonte du 29/10/2026, demande du PO,
/// `docs/HANDOFF_ECRAN_CONNEXION_LOGIRESTOCK.md`).
///
/// ## Le maître de mise en page
///
/// Une CARTE UNIQUE centrée, une colonne, dans l'ordre de la vue : marque
/// (pictogramme, « LogiReStock » en deux tons, sous-titre), filet, slogan,
/// filet, bandeau de sept pictogrammes, filet, « Bienvenue ! » et son accroche,
/// champ identifiant, champ mot de passe (œil afficher/masquer), « Se souvenir
/// de moi » · « Mot de passe oublié ? », bouton « SE CONNECTER ». L'ancien
/// panneau image à deux colonnes (`login.html`) n'existe plus, ni sur la vue ni
/// ici ; la vue le disait en `hidden lg:block`, le seuil `lg` ne change donc
/// plus rien à cet écran.
///
/// Largeur de la carte `max-w-[560px]`, marge `p-4` puis `md:p-6`, intérieur
/// `p-6` puis `md:p-8` : le palier `md` se décide sur la largeur de l'ÉCRAN
/// (`MediaQuery`), pas sur celle d'un conteneur.
///
/// ## Écarts nommés
///
///  - **Pictogrammes** : les mêmes tracés que la vue (`MesuresConnexion`,
///    dessinés par `IconeTrace`), pas des `Icons.*` Material — le dépôt sait
///    déjà rejouer un SVG de la vue, autant garder le même dessin.
///  - **« Mot de passe oublié ? »** : aucune route de réinitialisation
///    n'existe, ni sur la vue ni au poste (hors ligne). Le lien révèle sur
///    place « Contactez l'administrateur », comme la vue.
///  - **« Se souvenir de moi »** : l'identifiant seul, dans un fichier à côté
///    de `poste.json` (`IdentifiantMemorise`) ; la vue le range dans le
///    navigateur. Jamais le mot de passe.
///  - **Bouton non désactivé à vide** (handoff §5) : la vue ne le fait pas
///    non plus — un champ rempli par le navigateur sans événement de saisie
///    resterait bloqué ; le refus de saisie vide est dit sous les champs.
///  - **Aucun message « réseau »** : la connexion du poste est locale, la
///    branche `ReseauIndisponible` (que plus aucun chemin ne lève) a été retirée.
///
/// ## Ce que cet écran ne contient PAS, et pourquoi
///
/// **Aucune grille de comptes cliquables. Aucun raccourci de connexion par
/// rôle.** `SECURITY_STRICT.md` §12 l'interdit dans **tout** environnement, y
/// compris le flavor `demo` : une grille qui pré-remplit le mot de passe
/// transforme chaque capture d'écran de formation en fuite d'identifiants. Le
/// séparateur et le texte qui l'annonçaient partent avec elle.
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
  bool _souvenir = false;
  bool _aide = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    // « Se souvenir de moi » : l'identifiant mémorisé, JAMAIS le mot de passe.
    ref.read(identifiantMemoriseProvider).lire().then((memorise) {
      if (!mounted || memorise == null || _identifiant.text.isNotEmpty) return;
      setState(() {
        _souvenir = true;
        _identifiant.text = memorise;
      });
    });
  }

  @override
  void dispose() {
    _identifiant.dispose();
    _motDePasse.dispose();
    super.dispose();
  }

  Future<void> _soumettre() async {
    if (_enCours || !_formulaire.currentState!.validate()) return;
    setState(() {
      _enCours = true;
      _erreur = null;
    });

    try {
      final memoire = ref.read(identifiantMemoriseProvider);
      if (_souvenir) {
        await memoire.enregistrer(_identifiant.text.trim());
      } else {
        await memoire.oublier();
      }
      await ref
          .read(sessionProvider.notifier)
          .connecter(_identifiant.text.trim(), _motDePasse.text);
    } on EchecConnexion catch (e) {
      if (mounted) setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // `md:` : la largeur de l'ÉCRAN, pas celle d'un conteneur.
    final large = MediaQuery.sizeOf(context).width >= Breakpoints.tablette;
    final marge = large
        ? MesuresConnexion.margeLarge
        : MesuresConnexion.margeEtroit;
    final interieur = large
        ? MesuresConnexion.interieurLarge
        : MesuresConnexion.interieurEtroit;

    return Scaffold(
      // `<body style="background:var(--fond-clair)">` — #F2F2F2.
      backgroundColor: AppColors.fondClair,
      body: SafeArea(
        // `flex-1 flex items-center justify-center p-4 md:p-6 overflow-y-auto`
        child: LayoutBuilder(
          builder: (context, contraintes) => SingleChildScrollView(
            padding: EdgeInsets.all(marge),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: contraintes.maxHeight - 2 * marge,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: MesuresConnexion.largeurCarte,
                  ),
                  child: _carte(context, interieur),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// `bg-white border border-slate-200 rounded-2xl shadow-sm p-6 md:p-8`.
  Widget _carte(BuildContext context, double interieur) {
    return Container(
      padding: EdgeInsets.all(interieur),
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(MesuresConnexion.rayonCarte),
        border: Border.all(color: AppColors.neutre200),
        boxShadow: MesuresConnexion.ombreCarte,
      ),
      child: Form(
        key: _formulaire,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // `<h1 class="sr-only">` : le titre de la page, lu par les
            // lecteurs d'écran, jamais dessiné.
            Semantics(
              header: true,
              label: TextesConnexion.titreH1,
              child: const SizedBox.shrink(),
            ),
            const _Marque(),
            // **Poste vierge : on cède la place à la création du premier
            // compte.** L'authentification étant locale (PA-103), un poste
            // neuf n'a aucun compte, et afficher un formulaire qui refusera
            // tout ce qu'on y saisit ferait croire à une faute de frappe. Seul
            // l'en-tête de marque est repris (handoff §6).
            ...switch (ref.watch(aucunCompteProvider)) {
              AsyncData(value: true) => const [
                SizedBox(height: MesuresConnexion.filetBas),
                FormulairePremierCompte(),
              ],
              AsyncData() => _contenuConnexion(context),
              // Tant que la réponse n'est pas connue, on n'affiche NI l'un NI
              // l'autre : proposer une connexion puis la remplacer par une
              // création ferait clignoter l'écran d'ouverture.
              _ => const [
                SizedBox(height: MesuresConnexion.filetBas),
                Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            },
          ],
        ),
      ),
    );
  }

  /// Du filet au pied de page : tout ce qui suit la marque dans la vue.
  List<Widget> _contenuConnexion(BuildContext context) {
    final theme = Theme.of(context);
    return [
      // `<hr class="border-slate-200 mt-5">`
      const SizedBox(height: MesuresConnexion.filetHaut),
      const _Filet(),
      // `text-[12px] font-semibold tracking-[0.2em] text-slate-500 text-center py-3`
      Padding(
        padding: const EdgeInsets.symmetric(
          vertical: MesuresConnexion.margeSlogan,
        ),
        child: Text(
          TextesConnexion.slogan,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: Tailles.t12,
            fontWeight: FontWeight.w600,
            letterSpacing: AppTextStyles.suiviSlogan * Tailles.t12,
            color: AppColors.neutre500,
          ),
        ),
      ),
      const _Filet(),
      const _BandeauModules(),
      const _Filet(),
      const SizedBox(height: MesuresConnexion.filetBas), // mb-6
      // `text-[28px] font-extrabold leading-tight` navy.
      Semantics(
        header: true,
        child: Text(
          TextesConnexion.bienvenue,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontSize: Tailles.t28,
            fontWeight: FontWeight.w800,
            height: Tailles.interligneSerre,
            color: AppColors.navy,
          ),
        ),
      ),
      const SizedBox(height: MesuresConnexion.ecartPetit), // mt-1
      // `text-[15px] text-slate-500 mt-1 mb-6`
      Text(
        TextesConnexion.accroche,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontSize: Tailles.t15,
          color: AppColors.neutre500,
        ),
      ),
      const SizedBox(height: MesuresConnexion.filetBas),

      // Ordre de tabulation (handoff §8) : identifiant → mot de passe → œil →
      // « Se souvenir » → « Mot de passe oublié ? » → « SE CONNECTER » — celui
      // du document, donc celui de la lecture.
      _ChampConnexion(
        etiquette: TextesConnexion.login,
        controleur: _identifiant,
        trace: MesuresConnexion.traceUtilisateur,
        autofocus: true,
        indicesAutoRemplissage: const [AutofillHints.username],
        onSoumis: _soumettre,
        validateur: (v) => (v == null || v.trim().isEmpty)
            ? TextesConnexion.identifiantRequis
            : null,
      ),
      const SizedBox(height: AppSpacing.md), // space-y-4
      _ChampConnexion(
        etiquette: TextesConnexion.motDePasse,
        controleur: _motDePasse,
        trace: MesuresConnexion.traceCadenas,
        masque: _masque,
        indicesAutoRemplissage: const [AutofillHints.password],
        onSoumis: _soumettre,
        validateur: (v) =>
            (v == null || v.isEmpty) ? TextesConnexion.motDePasseRequis : null,
        // L'œil : `aria-label` (la phrase entière) et `aria-pressed`.
        suffixe: Semantics(
          toggled: !_masque,
          child: IconButton(
            tooltip: _masque
                ? TextesConnexion.afficherMotDePasse
                : TextesConnexion.masquerMotDePasse,
            onPressed: () => setState(() => _masque = !_masque),
            style: IconButton.styleFrom(
              minimumSize: const Size.square(MesuresConnexion.cibleOeil),
              fixedSize: const Size.square(MesuresConnexion.cibleOeil),
              padding: EdgeInsets.zero,
              foregroundColor: AppColors.neutre500,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: IconeTrace(
              trace: _masque
                  ? MesuresConnexion.traceOeil
                  : MesuresConnexion.traceOeilBarre,
              taille: MesuresConnexion.iconeChamp,
              couleur: AppColors.neutre500,
            ),
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.md),

      // `flex items-center justify-between gap-3 flex-wrap`
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: [
          _CaseSeSouvenir(
            valeur: _souvenir,
            onChanged: (v) => setState(() => _souvenir = v),
          ),
          Semantics(
            expanded: _aide,
            child: TextButton(
              onPressed: () => setState(() => _aide = !_aide),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.navy,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.xs,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(
                  fontSize: Tailles.t15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text(TextesConnexion.motDePasseOublie),
            ),
          ),
        ],
      ),
      if (_aide) ...[
        const SizedBox(height: AppSpacing.md),
        // `role="status"` : la phrase est annoncée à l'ouverture.
        Semantics(
          liveRegion: true,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: AppColors.neutre50,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.neutre200),
            ),
            child: Text(
              TextesConnexion.motDePasseOublieAide,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: Tailles.t15,
                color: AppColors.neutre700,
              ),
            ),
          ),
        ),
      ],

      // `#erreur-identifiants` (`role="alert"`) : n'existe que sur un refus.
      if (_erreur != null) ...[
        const SizedBox(height: AppSpacing.md),
        Semantics(
          liveRegion: true,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, // px-3
              vertical: AppSpacing.xs, // py-2
            ),
            decoration: BoxDecoration(
              color: AppColors.erreurFondLeger,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.erreurBordure),
            ),
            child: Text(
              // La vue préfixe d'un « ⚠ » : le signe porte l'alerte pour qui
              // distingue mal le rouge.
              '⚠ $_erreur',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: Tailles.t15,
                color: AppColors.erreur,
              ),
            ),
          ),
        ),
      ],

      const SizedBox(height: AppSpacing.md),
      _BoutonSeConnecter(enCours: _enCours, onPressed: _soumettre),

      // `text-center text-[13px] text-slate-500 mt-8`
      const SizedBox(height: MesuresConnexion.piedHaut),
      Text(
        TextesConnexion.piedDePage,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          fontSize: Tailles.t13,
          color: AppColors.neutre500,
        ),
      ),
    ];
  }
}

/// `<hr class="border-slate-200">`.
class _Filet extends StatelessWidget {
  const _Filet();

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, thickness: 1, color: AppColors.neutre200);
}

/// La marque : pictogramme + « LogiReStock » en deux tons + sous-titre.
class _Marque extends ConsumerWidget {
  const _Marque();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Décision du PO du 29/10/2026 : le logo TÉLÉVERSÉ (Paramètres → Logo &
    // Apparence) coiffe la carte ; absent, le pictogramme de marque.
    final logo = ref.watch(logoTeleverseProvider).value;
    final styleMarque = theme.textTheme.headlineMedium?.copyWith(
      fontSize: Tailles.t28,
      fontWeight: FontWeight.w800,
      height: Tailles.interligneAucun,
    );
    final marque = Semantics(
      container: true,
      label:
          '${TextesConnexion.marqueLogi}${TextesConnexion.marqueRestock} '
          '${TextesConnexion.sousMarque}',
      child: ExcludeSemantics(
        // `flex items-center justify-center gap-3` — `FittedBox` : à 320 px la
        // marque rétrécit au lieu de déborder.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (logo == null) ...[
                const IconeTrace(
                  trace: MesuresConnexion.traceMarque,
                  taille: MesuresConnexion.iconeMarque,
                  couleur: AppColors.navy,
                ),
                const SizedBox(width: MesuresConnexion.ecartMarque),
              ],
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // `text-[28px] font-extrabold leading-none` : « Logi » navy
                  // (primaire), « ReStock » gold (accent).
                  //
                  // Deux `Text` côte à côte et non un `Text.rich` : la vue pose
                  // deux `<span>` (le comparateur d'emplacement lit un texte par
                  // élément), et le rendu est le même, mot collé.
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        TextesConnexion.marqueLogi,
                        style: styleMarque?.copyWith(color: AppColors.navy),
                      ),
                      Text(
                        TextesConnexion.marqueRestock,
                        style: styleMarque?.copyWith(color: AppColors.gold),
                      ),
                    ],
                  ),
                  const SizedBox(height: MesuresConnexion.ecartPetit), // mt-1
                  // `text-[11px] font-bold uppercase tracking-widest text-slate-500`
                  Text(
                    TextesConnexion.sousMarque,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: Tailles.t11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: AppTextStyles.suiviTresLarge * Tailles.t11,
                      color: AppColors.neutre500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (logo == null) return marque;
    // `h-16 w-auto max-w-full object-contain mb-4` : 64 px de haut, proportions
    // gardées, jamais rogné. `alt` = `pwa.alt_logo`.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Image.memory(
          logo,
          height: MesuresConnexion.hauteurLogo,
          fit: BoxFit.contain,
          semanticLabel: LibellesCoquille.altLogo,
        ),
        const SizedBox(height: AppSpacing.md),
        marque,
      ],
    );
  }
}

/// Le bandeau de sept pictogrammes : restauration, hébergement, éco-tourisme,
/// stock, location, caisse, comptabilité — `flex … justify-between py-4`, un
/// `title` (infobulle) et un libellé lu par module.
class _BandeauModules extends StatelessWidget {
  const _BandeauModules();

  static const _modules = <(String, String)>[
    (TextesConnexion.restauration, MesuresConnexion.traceRestauration),
    (TextesConnexion.hebergement, MesuresConnexion.traceHebergement),
    (TextesConnexion.ecoTourisme, MesuresConnexion.traceEcoTourisme),
    (TextesConnexion.stock, MesuresConnexion.traceStock),
    (TextesConnexion.location, MesuresConnexion.traceLocation),
    (TextesConnexion.caisse, MesuresConnexion.traceCaisse),
    (TextesConnexion.comptabilite, MesuresConnexion.traceComptabilite),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: MesuresConnexion.margeBandeau,
      ),
      child: Semantics(
        container: true,
        label: TextesConnexion.bandeauModules,
        child: Row(
          children: [
            for (final (libelle, trace) in _modules)
              Expanded(
                child: Center(
                  child: Tooltip(
                    message: libelle,
                    child: Semantics(
                      label: libelle,
                      child: ExcludeSemantics(
                        child: IconeTrace(
                          trace: trace,
                          taille: MesuresConnexion.iconeModule,
                          couleur: AppColors.neutre500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Un champ étiqueté — `.groupe-champ` de la vue : `<label>` en capitales AU
/// DESSUS du champ (pas un `labelText` flottant), icône à gauche, bordure
/// `slate-300` (survol `slate-400`), anneau de focus navy, erreur dessous.
class _ChampConnexion extends StatefulWidget {
  const _ChampConnexion({
    required this.etiquette,
    required this.controleur,
    required this.trace,
    required this.validateur,
    required this.onSoumis,
    required this.indicesAutoRemplissage,
    this.masque = false,
    this.autofocus = false,
    this.suffixe,
  });

  final String etiquette;
  final TextEditingController controleur;
  final String trace;
  final String? Function(String?) validateur;
  final VoidCallback onSoumis;
  final List<String> indicesAutoRemplissage;
  final bool masque;
  final bool autofocus;
  final Widget? suffixe;

  @override
  State<_ChampConnexion> createState() => _EtatChampConnexion();
}

class _EtatChampConnexion extends State<_ChampConnexion> {
  final _focus = FocusNode();
  bool _survol = false;
  bool _focalise = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() => _focalise = _focus.hasFocus);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  OutlineInputBorder _bordure(Color couleur, {double epaisseur = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(MesuresConnexion.rayonChamp),
        borderSide: BorderSide(color: couleur, width: epaisseur),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // `block text-[12px] font-bold tracking-wider text-slate-800 mb-1.5`.
        // Le libellé est porté par le champ (sémantique), pas lu deux fois.
        ExcludeSemantics(
          child: Text(
            widget.etiquette,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: Tailles.t12,
              fontWeight: FontWeight.w700,
              letterSpacing: AppTextStyles.suiviPlusLarge * Tailles.t12,
              color: AppColors.neutre800,
            ),
          ),
        ),
        const SizedBox(height: MesuresConnexion.ecartLabel),
        MouseRegion(
          onEnter: (_) => setState(() => _survol = true),
          onExit: (_) => setState(() => _survol = false),
          child: AnimatedContainer(
            duration: AppDurations.courte,
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(MesuresConnexion.rayonChamp),
              boxShadow: _focalise ? AppShadows.focusChamp : const [],
            ),
            child: Semantics(
              label: widget.etiquette,
              child: TextFormField(
                controller: widget.controleur,
                focusNode: _focus,
                autofocus: widget.autofocus,
                obscureText: widget.masque,
                autofillHints: widget.indicesAutoRemplissage,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => widget.onSoumis(),
                validator: widget.validateur,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: Tailles.t16,
                  color: AppColors.neutre900,
                ),
                decoration: InputDecoration(
                  constraints: const BoxConstraints(
                    minHeight: MesuresConnexion.hauteurChamp,
                  ),
                  // `pl-11` : le texte démarre après l'icône (`left-3.5`).
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(
                      left: MesuresConnexion.margeIcone,
                      right: AppSpacing.sm,
                    ),
                    child: IconeTrace(
                      trace: widget.trace,
                      taille: MesuresConnexion.iconeChamp,
                      couleur: AppColors.neutre500,
                    ),
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: MesuresConnexion.retraitIcone,
                    minHeight: MesuresConnexion.iconeChamp,
                  ),
                  suffixIcon: widget.suffixe == null
                      ? null
                      : Padding(
                          padding: const EdgeInsets.only(right: 6), // right-1.5
                          child: widget.suffixe,
                        ),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: MesuresConnexion.cibleOeil,
                    minHeight: MesuresConnexion.cibleOeil,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm + 2,
                    vertical: AppSpacing.md,
                  ),
                  enabledBorder: _bordure(
                    _survol ? AppColors.neutre400 : AppColors.neutre300,
                  ),
                  border: _bordure(AppColors.neutre300),
                  focusedBorder: _bordure(AppColors.navy),
                  errorBorder: _bordure(AppColors.erreur),
                  focusedErrorBorder: _bordure(AppColors.erreur),
                  // `.message-erreur` : 13 px, rouge, 4 px sous le champ.
                  errorStyle: theme.textTheme.bodySmall?.copyWith(
                    fontSize: Tailles.t13,
                    color: AppColors.erreur,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// « Se souvenir de moi » — la case et son libellé, un seul arrêt de
/// tabulation, un seul élément pour un lecteur d'écran.
class _CaseSeSouvenir extends StatelessWidget {
  const _CaseSeSouvenir({required this.valeur, required this.onChanged});

  final bool valeur;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      // La case porte le focus ; le libellé n'ajoute pas d'arrêt.
      canRequestFocus: false,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: () => onChanged(!valeur),
      child: MergeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: MesuresConnexion.caseACocher + AppSpacing.md,
              height: MesuresConnexion.caseACocher + AppSpacing.md,
              child: Checkbox(
                value: valeur,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: AppColors.navy,
                side: const BorderSide(color: AppColors.neutre300, width: 1.5),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: MesuresConnexion.ecartCase),
            // `Flexible` : à 320 px, ou sous une police plus large, le libellé
            // passe à la ligne au lieu de déborder.
            Flexible(
              child: Text(
                TextesConnexion.seSouvenir,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: Tailles.t15,
                  color: AppColors.neutre700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Le bouton plein « SE CONNECTER » : navy, 52 px, rayon 12, capitales.
/// Au repos le cadenas ouvert ; en cours, la pastille tournante et
/// « Connexion… » (`aria-busy`), le bouton est désactivé.
class _BoutonSeConnecter extends StatelessWidget {
  const _BoutonSeConnecter({required this.enCours, required this.onPressed});

  final bool enCours;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      // `aria-busy` : l'état de chargement est annoncé.
      label: enCours
          ? TextesConnexion.connexionEnCours
          : TextesConnexion.valider,
      child: ExcludeSemantics(
        child: SizedBox(
          height: MesuresConnexion.hauteurChamp,
          child: ElevatedButton(
            onPressed: enCours ? null : onPressed,
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(
                Size.fromHeight(MesuresConnexion.hauteurChamp),
              ),
              backgroundColor: WidgetStateProperty.resolveWith(
                (etats) => etats.contains(WidgetState.disabled)
                    // `.btn:disabled { opacity: .4 }`
                    ? AppColors.navy.withValues(alpha: 0.4)
                    : AppColors.navy,
              ),
              foregroundColor: const WidgetStatePropertyAll(AppColors.neutre0),
              // `.btn:hover { filter: brightness(0.92) }`
              overlayColor: WidgetStateProperty.resolveWith(
                (etats) => etats.contains(WidgetState.hovered)
                    ? const Color(0x14000000)
                    : null,
              ),
              elevation: const WidgetStatePropertyAll(0),
              shape: WidgetStateProperty.resolveWith(
                (etats) => RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    MesuresConnexion.rayonChamp,
                  ),
                  // Anneau de focus visible : jamais retiré sans équivalent.
                  side: etats.contains(WidgetState.focused)
                      ? const BorderSide(color: AppColors.gold, width: 2)
                      : BorderSide.none,
                ),
              ),
              textStyle: WidgetStatePropertyAll(
                TextStyle(
                  fontSize: Tailles.t16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: AppTextStyles.suiviPlusLarge * Tailles.t16,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (enCours)
                  const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.neutre0,
                    ),
                  )
                else
                  const IconeTrace(
                    trace: MesuresConnexion.traceCadenasOuvert,
                    taille: MesuresConnexion.iconeChamp,
                    couleur: AppColors.neutre0,
                  ),
                const SizedBox(width: MesuresConnexion.ecartCase),
                Flexible(
                  child: Text(
                    enCours
                        ? TextesConnexion.connexionEnCours
                        : TextesConnexion.valider,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
