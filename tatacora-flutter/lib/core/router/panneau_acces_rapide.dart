import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/hebergement/presentation/panneau_historique.dart';
import '../di/providers.dart';
import '../navigation/acces_rapide.dart';
import '../navigation/coquille_vue.dart';
import '../navigation/trace_svg.dart';
import '../theme/app_colors.dart';
import '../theme/app_durations.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// Le bouton flottant « Accès rapides » et son panneau — traduction du
/// partiel `partials/acces-rapide` de la vue (chemin sans préfixe, PA-187),
/// lot 3 de `INSTRUCTION.txt` (13/10/2026). Registre, libellés et règles :
/// `core/navigation/acces_rapide.dart`.
///
/// ## Ce que la vue fait, élément par élément
///
/// - Un état Alpine `openDrawer`, FERMÉ au chargement de chaque page.
/// - `@keydown.window.alt.a` bascule, `@keydown.escape.window` ferme : deux
///   écoutes au niveau de la FENÊTRE, quel que soit le champ qui a le focus.
///   Ici, un gestionnaire de [HardwareKeyboard] — l'équivalent au niveau de
///   l'application —, posé pour toute la vie de la coquille mais qui ne
///   traite RIEN sur une page sans panneau : il rend alors la touche non
///   traitée (`false`), comme une page de la vue qui n'inclut pas le partiel
///   (13/10/2026, D353).
/// - Le bouton : `fixed bottom-6 right-6 z-40 w-14 h-14 rounded-full
///   bg-[var(--navy)] text-white shadow-xl hover:bg-[var(--gold)]
///   hover:scale-105 active:scale-95 transition-all`, infobulle
///   « Accès Rapides (Alt+A) ». Il ne sort jamais de l'écran : la vue ne le
///   masque à aucune largeur.
/// - Le voile : `fixed inset-0 bg-black/40 z-50`, `x-transition.opacity`
///   (150 ms à l'entrée, 75 ms à la sortie — Alpine par défaut) ; un clic le
///   ferme.
/// - Le panneau : `fixed top-0 right-0 h-full w-[320px] max-w-[88vw] bg-white
///   z-50 shadow-2xl`, glissement depuis la droite (`translate-x-full` →
///   `translate-x-0`, 200 ms, courbe par défaut de Tailwind) dans les deux
///   sens. Il couvre la barre supérieure, comme la vue (`top-0 h-full`).
/// - Un lien suivi ouvre la page cible : la vue NAVIGUE (`wire:navigate`), et
///   la page d'arrivée rend un panneau fermé, sans animation de sortie. Ce
///   poste ferme le panneau à l'instant, puis navigue.
///
/// ## Trois écarts, nommés et datés (13/10/2026)
///
/// 1. « Historique des réservations » (`pwa.reservations?vue=historique`) :
///    la vue ouvre la page des réservations avec son panneau d'historique
///    (`Reservations::$vue`, propriété `#[Url]`). Ce poste n'a pas d'URL à
///    paramètre : il ouvre la même page, puis le MÊME panneau
///    ([ouvrirHistoriqueReservations]) — le résultat de la vue, par un autre
///    chemin.
/// 2. « Comptabilité » (« Aller à ») mène, dans la vue, au hub comptable ; ce
///    poste n'a pas cet écran (dette D313, PA-204). L'entrée reste à sa place
///    et son clic DIT que l'écran n'est pas porté (Article 3.3) — jamais un
///    lien muet.
/// 3. Les autres paramètres du registre (`vue=creances`, `etat=sous_seuil`,
///    `onglet=…`) n'appartiennent qu'à des pages qui n'incluent pas le
///    panneau : ils ne sont jamais rendus. S'ils l'étaient, ce poste
///    ouvrirait la page sans le filtre — écrit ici pour qu'on ne le découvre
///    pas plus tard.
class PanneauAccesRapide extends ConsumerStatefulWidget {
  const PanneauAccesRapide({required this.routeActive, super.key});

  /// La route Flutter affichée — elle décide du bouton (la page porte-t-elle
  /// le panneau ?), de « Sur cette page », de l'exclusion de « Aller à » et
  /// du sous-titre.
  final String routeActive;

  @override
  ConsumerState<PanneauAccesRapide> createState() => _EtatPanneauAccesRapide();
}

class _EtatPanneauAccesRapide extends ConsumerState<PanneauAccesRapide>
    with TickerProviderStateMixin {
  bool _ouvert = false;

  // Créés dans `initState`, JAMAIS paresseusement : sur une page sans
  // panneau, `build` ne les touche pas, et un champ paresseux serait alors
  // créé par `dispose()` — dans un arbre déjà démonté, ce que le framework
  // refuse (assertion relevée en test le 13/10/2026 : elle aurait levé à la
  // déconnexion depuis Stocks).

  /// `translate-x-full` ↔ `translate-x-0`, 200 ms dans les deux sens.
  late final AnimationController _glissement;

  /// `x-transition.opacity` : 150 ms à l'entrée, 75 ms à la sortie.
  late final AnimationController _voile;

  /// Les deux courbes : celle de Tailwind (`transition`) et celle d'Alpine
  /// (`x-transition`), toutes deux `cubic-bezier(0.4, 0, 0.2, 1)`.
  late final CurvedAnimation _courbeGlissement;
  late final CurvedAnimation _courbeVoile;

  /// `translate-x-full` (décalé de sa propre largeur) → `translate-x-0`.
  late final Animation<Offset> _position;

  @override
  void initState() {
    super.initState();
    _glissement = AnimationController(
      vsync: this,
      duration: AppDurations.modale,
    );
    _voile = AnimationController(
      vsync: this,
      duration: AppDurations.courte,
      reverseDuration: AppDurations.sortieAlpine,
    );
    _courbeGlissement = CurvedAnimation(
      parent: _glissement,
      curve: AppDurations.tailwindDefaut,
    );
    _courbeVoile = CurvedAnimation(
      parent: _voile,
      curve: AppDurations.tailwindDefaut,
    );
    _position = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(_courbeGlissement);
    HardwareKeyboard.instance.addHandler(_touche);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_touche);
    _courbeGlissement.dispose();
    _courbeVoile.dispose();
    _glissement.dispose();
    _voile.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PanneauAccesRapide ancien) {
    super.didUpdateWidget(ancien);
    // Une autre page : la vue en rend un panneau neuf, donc fermé.
    if (ancien.routeActive != widget.routeActive) _fermerSansAnimation();
  }

  /// `@keydown.window.alt.a` et `@keydown.escape.window`.
  ///
  /// Le gestionnaire est posé pour toute la vie du widget, donc sur TOUTES
  /// les pages de la coquille ; la vue, elle, n'écoute ces touches que sur
  /// les onze pages qui incluent le partiel. Sur une autre page (Stocks…),
  /// rien n'est fait et la touche est rendue NON traitée — sans cette garde,
  /// Alt+A et Échap étaient avalés et basculaient un état invisible
  /// (contrôle du lot 3, 13/10/2026, D353).
  bool _touche(KeyEvent evenement) {
    if (pagesAvecAccesRapide[widget.routeActive] == null) return false;
    if (evenement is! KeyDownEvent) return false;
    if (evenement.logicalKey == LogicalKeyboardKey.keyA &&
        HardwareKeyboard.instance.isAltPressed) {
      _basculer();
      return true;
    }
    if (evenement.logicalKey == LogicalKeyboardKey.escape && _ouvert) {
      _fermer();
      return true;
    }
    return false;
  }

  void _basculer() => _ouvert ? _fermer() : _ouvrir();

  void _ouvrir() {
    setState(() => _ouvert = true);
    _glissement.forward();
    _voile.forward();
  }

  void _fermer() {
    setState(() => _ouvert = false);
    _glissement.reverse();
    _voile.reverse();
  }

  void _fermerSansAnimation() {
    _ouvert = false;
    _glissement.value = 0;
    _voile.value = 0;
  }

  /// Suivre une entrée : fermer, puis aller à l'écran que la vue désigne.
  void _suivre(EntreeAccesRapide entree) {
    final cible = routesFlutterParRoutePwa[entree.routePwa];
    if (cible == null) {
      // Écart 2 : la vue a l'écran, ce poste ne l'a pas — le clic le DIT.
      ScaffoldMessenger.maybeOf(context)
        ?..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(LibellesCoquille.ecranNonPorte(entree.libelle)),
          ),
        );
      return;
    }
    final routeur = GoRouter.of(context);
    setState(_fermerSansAnimation);
    routeur.go(cible);
    if (entree.params['vue'] == 'historique') {
      // Écart 1 : la page d'arrivée, puis son panneau d'historique — ouvert
      // depuis l'OVERLAY du navigateur racine, qui survit à la navigation
      // (ce widget, lui, peut être reconstruit ailleurs).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final hote =
            routeur.routerDelegate.navigatorKey.currentState?.overlay?.context;
        if (hote != null && hote.mounted) ouvrirHistoriqueReservations(hote);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final routePwa = pagesAvecAccesRapide[widget.routeActive];
    // La page ne porte pas le panneau dans la vue : ni bouton, ni panneau.
    if (routePwa == null) return const SizedBox.shrink();

    final droits = ref.watch(droitsProvider);
    final largeurPanneau = largeurPanneauAccesRapide(
      MediaQuery.sizeOf(context).width,
    );

    return Stack(
      children: [
        // `fixed bottom-6 right-6 z-40` — SOUS le voile et le panneau (z-50).
        Positioned(
          right: MesuresAccesRapide.margeBoutonFlottant,
          bottom: MesuresAccesRapide.margeBoutonFlottant,
          child: _BoutonFlottant(ouvert: _ouvert, onTap: _basculer),
        ),
        // Fermés, voile et panneau ne construisent RIEN (`display: none` de
        // la vue) : aucun texte du panneau n'existe tant qu'il n'est pas
        // ouvert, et rien n'intercepte un clic sur la page.
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _voile,
            builder: (context, _) => _voile.isDismissed
                ? const SizedBox.shrink()
                : GestureDetector(
                    key: const Key('voile-acces-rapide'),
                    onTap: _fermer,
                    child: FadeTransition(
                      opacity: _courbeVoile,
                      child: const ColoredBox(color: AppColors.voileModale),
                    ),
                  ),
          ),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          width: largeurPanneau,
          child: AnimatedBuilder(
            animation: _glissement,
            builder: (context, enfant) => _glissement.isDismissed
                ? const SizedBox.shrink()
                : SlideTransition(position: _position, child: enfant),
            child: _Panneau(
              sousTitre: sousTitreAccesRapide(
                droits,
                widget.routeActive,
                marque: LibellesCoquille.marque,
              ),
              contextuelles: actionsContextuelles(droits, routePwa),
              universelles: raccourcisAllerA(droits, routePwa),
              onFermer: _fermer,
              onSuivre: _suivre,
            ),
          ),
        ),
      ],
    );
  }
}

/// `w-[320px] max-w-[88vw]` — la largeur du panneau pour une fenêtre donnée.
/// La borne ne mord que sous 364 px de fenêtre, largeur où la barre
/// supérieure déborde déjà (poste de bureau seulement, décision du PO du
/// 08/10/2026) : elle se prouve donc ici, hors de la coquille.
double largeurPanneauAccesRapide(double largeurFenetre) => math.min(
  MesuresAccesRapide.largeurPanneau,
  largeurFenetre * MesuresAccesRapide.largeurMaxPanneau,
);

/// Un style de texte du panneau : la police de la vue, interlettrage nul, et
/// l'interligne du corps (1,5) sauf mention contraire.
TextStyle _style(
  double taille, {
  required Color couleur,
  FontWeight? poids,
  double interligne = AppLayout.interligneContenu,
  double interlettrage = 0,
}) => TextStyle(
  fontFamily: AppTextStyles.police,
  fontSize: taille,
  fontWeight: poids,
  color: couleur,
  height: interligne,
  letterSpacing: interlettrage,
);

/// Le bouton flottant — l'éclair, navy, doré et agrandi au survol, réduit à
/// la pression (`transition-all`, 150 ms).
class _BoutonFlottant extends StatefulWidget {
  const _BoutonFlottant({required this.ouvert, required this.onTap});

  final bool ouvert;
  final VoidCallback onTap;

  @override
  State<_BoutonFlottant> createState() => _EtatBoutonFlottant();
}

class _EtatBoutonFlottant extends State<_BoutonFlottant> {
  bool _survol = false;
  bool _presse = false;

  @override
  Widget build(BuildContext context) {
    final echelle = _presse
        ? MesuresAccesRapide.echellePressionBouton
        : _survol
        ? MesuresAccesRapide.echelleSurvolBouton
        : 1.0;

    return Semantics(
      button: true,
      label: LibellesAccesRapide.etiquetteBouton,
      expanded: widget.ouvert, // `:aria-expanded`
      child: Tooltip(
        message: LibellesAccesRapide.titreBouton, // `title="…"`
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _survol = true),
          onExit: (_) => setState(() => _survol = false),
          child: GestureDetector(
            key: const Key('bouton-acces-rapide'),
            onTapDown: (_) => setState(() => _presse = true),
            onTapUp: (_) => setState(() => _presse = false),
            onTapCancel: () => setState(() => _presse = false),
            onTap: widget.onTap,
            child: AnimatedScale(
              scale: echelle,
              duration: AppDurations.courte,
              curve: AppDurations.tailwindDefaut,
              child: AnimatedContainer(
                duration: AppDurations.courte,
                curve: AppDurations.tailwindDefaut,
                width: MesuresAccesRapide.boutonFlottant,
                height: MesuresAccesRapide.boutonFlottant,
                decoration: BoxDecoration(
                  color: _survol ? AppColors.gold : AppColors.navy,
                  shape: BoxShape.circle,
                  boxShadow: AppShadows.tailwindXl,
                ),
                alignment: Alignment.center,
                child: IconeTrace(
                  trace: heriterTraitsRacine(
                    TracesAccesRapide.eclair,
                    cap: 'round',
                  ),
                  taille: MesuresAccesRapide.iconeBoutonFlottant,
                  couleur: AppColors.neutre0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Le panneau — en-tête, sections, pied.
class _Panneau extends StatelessWidget {
  const _Panneau({
    required this.sousTitre,
    required this.contextuelles,
    required this.universelles,
    required this.onFermer,
    required this.onSuivre,
  });

  final String sousTitre;
  final List<EntreeAccesRapide> contextuelles;
  final List<EntreeAccesRapide> universelles;
  final VoidCallback onFermer;
  final ValueChanged<EntreeAccesRapide> onSuivre;

  @override
  Widget build(BuildContext context) {
    const filet = BorderSide(color: AppColors.neutre200); // border-slate-200

    return Container(
      key: const Key('panneau-acces-rapide'),
      decoration: const BoxDecoration(
        color: AppColors.neutre0,
        boxShadow: AppShadows.tailwind2xl,
      ),
      // `flex flex-col` : en-tête et pied `shrink-0`, corps `flex-1`.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // `flex items-center justify-between px-4 py-3.5 border-b`.
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.smPlus,
              ),
              decoration: const BoxDecoration(border: Border(bottom: filet)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // `text-sm font-bold`, couleur navy.
                        Text(
                          LibellesAccesRapide.titre,
                          style: _style(
                            Tailles.t14,
                            couleur: AppColors.navy,
                            poids: FontWeight.bold,
                            interligne: Tailles.interligneSmHorsMain,
                          ),
                        ),
                        // `text-[11px] text-slate-400`.
                        Text(
                          sousTitre,
                          key: const Key('acces-rapide-sous-titre'),
                          style: _style(
                            Tailles.t11,
                            couleur: AppColors.neutre400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _BoutonFermer(onTap: onFermer),
                ],
              ),
            ),
            // `flex-1 overflow-y-auto py-3 px-2`.
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (contextuelles.isEmpty && universelles.isEmpty)
                      // `px-3 py-8 text-center text-[13px] text-slate-400`.
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xl,
                        ),
                        child: Text(
                          LibellesAccesRapide.aucun,
                          key: const Key('acces-rapide-vide'),
                          textAlign: TextAlign.center,
                          style: _style(
                            Tailles.t13,
                            couleur: AppColors.neutre400,
                          ),
                        ),
                      )
                    else ...[
                      if (contextuelles.isNotEmpty)
                        _Section(
                          cle: 'sur-cette-page',
                          titre: LibellesAccesRapide.surCettePage,
                          entrees: contextuelles,
                          onSuivre: onSuivre,
                        ),
                      if (universelles.isNotEmpty)
                        _Section(
                          cle: 'aller-a',
                          titre: LibellesAccesRapide.allerA,
                          entrees: universelles,
                          onSuivre: onSuivre,
                        ),
                    ],
                  ],
                ),
              ),
            ),
            // `px-4 py-2.5 border-t border-slate-200`.
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xsPlus,
              ),
              decoration: const BoxDecoration(border: Border(top: filet)),
              child: const _PiedRaccourcis(),
            ),
          ],
        ),
      ),
    );
  }
}

/// `p-1.5 rounded-lg hover:bg-slate-100 text-slate-400 hover:text-slate-700
/// transition-colors`, croix de 20 px, `aria-label="Fermer"`.
class _BoutonFermer extends StatefulWidget {
  const _BoutonFermer({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_BoutonFermer> createState() => _EtatBoutonFermer();
}

class _EtatBoutonFermer extends State<_BoutonFermer> {
  bool _survol = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: LibellesAccesRapide.fermer,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _survol = true),
        onExit: (_) => setState(() => _survol = false),
        child: GestureDetector(
          key: const Key('fermer-acces-rapide'),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: AppDurations.courte,
            curve: AppDurations.tailwindDefaut,
            padding: const EdgeInsets.all(AppSpacing.xxs),
            decoration: BoxDecoration(
              color: _survol ? AppColors.neutre100 : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            ),
            child: IconeTrace(
              trace: heriterTraitsRacine(
                TracesAccesRapide.fermer,
                cap: 'round',
              ),
              taille: MesuresAccesRapide.iconeFermer,
              couleur: _survol ? AppColors.neutre700 : AppColors.neutre400,
            ),
          ),
        ),
      ),
    );
  }
}

/// Une section — `<div class="mb-5">`, son titre `px-3 mb-1.5 text-[10px]
/// font-bold uppercase tracking-wider text-slate-400`, ses entrées
/// `space-y-0.5`.
class _Section extends StatelessWidget {
  const _Section({
    required this.cle,
    required this.titre,
    required this.entrees,
    required this.onSuivre,
  });

  final String cle;
  final String titre;
  final List<EntreeAccesRapide> entrees;
  final ValueChanged<EntreeAccesRapide> onSuivre;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: Key('acces-rapide-section-$cle'),
      padding: const EdgeInsets.only(bottom: AppSpacing.mdPlus),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.sm,
              right: AppSpacing.sm,
              bottom: AppSpacing.xxs,
            ),
            child: Text(
              // `uppercase` : la casse est celle du RENDU, pas de la source.
              titre.toUpperCase(),
              style: _style(
                Tailles.t10,
                couleur: AppColors.neutre400,
                poids: FontWeight.bold,
                interlettrage: AppTextStyles.suiviPlusLarge * Tailles.t10,
              ),
            ),
          ),
          for (var i = 0; i < entrees.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.demi),
            _LienAccesRapide(
              cle: '$cle-$i',
              entree: entrees[i],
              onTap: () => onSuivre(entrees[i]),
            ),
          ],
        ],
      ),
    );
  }
}

/// Une entrée — `flex items-center gap-3 px-3 py-2.5 rounded-lg
/// text-[13px] text-slate-700 hover:bg-[var(--navy)] hover:text-white
/// transition-colors`. L'icône reste DORÉE au survol : la vue écrit
/// `group-hover:text-white` sans aucun parent `group`, la règle ne s'applique
/// donc jamais — reproduit tel quel. Le chevron suit la couleur du texte à
/// 30 %.
class _LienAccesRapide extends StatefulWidget {
  const _LienAccesRapide({
    required this.cle,
    required this.entree,
    required this.onTap,
  });

  final String cle;
  final EntreeAccesRapide entree;
  final VoidCallback onTap;

  @override
  State<_LienAccesRapide> createState() => _EtatLienAccesRapide();
}

class _EtatLienAccesRapide extends State<_LienAccesRapide> {
  bool _survol = false;

  @override
  Widget build(BuildContext context) {
    final texte = _survol ? AppColors.neutre0 : AppColors.neutre700;
    final trace = iconesAccesRapide[widget.entree.icone];

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _survol = true),
      onExit: (_) => setState(() => _survol = false),
      child: GestureDetector(
        key: Key('acces-rapide-${widget.cle}'),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppDurations.courte,
          curve: AppDurations.tailwindDefaut,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xsPlus,
          ),
          decoration: BoxDecoration(
            color: _survol ? AppColors.navy : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.roundedLg),
          ),
          child: Row(
            children: [
              if (trace != null)
                IconeTrace(
                  trace: heriterTraitsRacine(
                    trace,
                    cap: 'round',
                    join: 'round',
                  ),
                  taille: MesuresAccesRapide.iconeEntree,
                  couleur: AppColors.gold,
                ),
              const SizedBox(width: AppSpacing.sm), // gap-3
              Expanded(
                child: Text(
                  widget.entree.libelle,
                  style: _style(Tailles.t13, couleur: texte),
                ),
              ),
              const SizedBox(width: AppSpacing.sm), // gap-3
              IconeTrace(
                trace: TracesAccesRapide.chevron,
                taille: MesuresAccesRapide.iconeChevron,
                couleur: texte.withValues(alpha: OpacitesAccesRapide.chevron),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Le pied — `<kbd>Alt</kbd> + <kbd>A</kbd> pour ouvrir · <kbd>Échap</kbd>
/// pour fermer`, `text-[10px] text-slate-400 text-center`.
class _PiedRaccourcis extends StatelessWidget {
  const _PiedRaccourcis();

  @override
  Widget build(BuildContext context) {
    final style = _style(Tailles.t10, couleur: AppColors.neutre400);
    InlineSpan touche(String libelle) => WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: _Touche(libelle: libelle, style: style),
    );

    return Text.rich(
      key: const Key('acces-rapide-pied'),
      TextSpan(
        style: style,
        children: [
          touche(LibellesAccesRapide.toucheAlt),
          const TextSpan(text: ' ${LibellesAccesRapide.plus} '),
          touche(LibellesAccesRapide.toucheA),
          const TextSpan(text: ' ${LibellesAccesRapide.pourOuvrir} '),
          touche(LibellesAccesRapide.toucheEchap),
          const TextSpan(text: ' ${LibellesAccesRapide.pourFermer}'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

/// `<kbd class="px-1.5 py-0.5 bg-slate-100 rounded font-sans">` — un élément
/// EN LIGNE : son rembourrage vertical se peint autour du texte sans agrandir
/// la ligne (comportement CSS d'une boîte en ligne). Le fond est donc peint
/// au-delà de la boîte, la mise en page garde la hauteur de la ligne.
class _Touche extends StatelessWidget {
  const _Touche({required this.libelle, required this.style});

  final String libelle;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: -AppSpacing.demi,
          bottom: -AppSpacing.demi,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.neutre100,
              borderRadius: BorderRadius.circular(AppRadius.rounded),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          child: Text(libelle, style: style),
        ),
      ],
    );
  }
}
