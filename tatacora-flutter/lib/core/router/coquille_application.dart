import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../di/providers.dart';
import '../../features/alertes/presentation/cloche_notifications.dart';
import '../../features/synchronisation/presentation/bouton_synchronisation.dart';
import '../../features/auth/domain/session.dart';
import '../../features/caisse/domain/indicateur_caisse.dart';
import '../../features/caisse/presentation/providers_caisse.dart';
import '../../features/comptabilite/presentation/widgets/selecteur_exercice_barre.dart';
import '../../features/recherche_globale/presentation/recherche_globale_barre.dart';
import '../navigation/coquille_vue.dart';
import '../navigation/navigation_tatacora.dart';
import '../navigation/trace_svg.dart';
import '../rbac/garde_acces.dart';
import '../responsive/breakpoints.dart';
import '../../features/parametres/data/apparence_poste.dart';
import '../theme/app_assets.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../theme/mesures_transverses_complement.dart';
import 'panneau_acces_rapide.dart';

/// La coquille — barre supérieure et barre latérale de la VUE (PA-183).
///
/// Partiels de la vue traduits ici (chemins sans préfixe, PA-187) :
/// `partials/barre-superieure`, `partials/menu-lateral`, `partials/entree-menu`
/// et `partials/lien-chassis`, plus le registre `MenuLateral` (`app/Pwa/
/// Support/`). `DOCTRINE_PORTAGE_FIDELE_FLUTTER.md` §3.4 : « mêmes groupes,
/// mêmes libellés, même ordre, mêmes icônes ».
///
/// ## Lot 1 « coquille » (12/10/2026, `INSTRUCTION.txt` du PO)
///
/// Repris contre la vue, classe par classe : les icônes sont les TRACÉS SVG de
/// la vue (elles étaient des icônes Material) ; l'interlettrage des titres de
/// groupe est `tracking-wider` (0,05 em, il valait 0,8 px) ; la ligne sous la
/// marque est celle de la vue (`LibellesCoquille.localisation` — « Système
/// de gestion Intégré » depuis les décisions du PO du 13/10/2026, D373 puis
/// D389) ;
/// le rôle s'affiche
/// `ucfirst` ; l'indicateur de caisse et le bouton « Vente » sont rendus ; le
/// menu de compte porte ses six entrées ; les entrées sans écran DISENT
/// qu'elles n'en ont pas. Ce qui reste refusé est nommé à l'endroit où la vue
/// le pose, dans `_BarreSuperieure`.
///
/// ## Structure
///
/// `<aside class="w-[264px] bg-navy … fixed lg:static">` : au-delà de 1024 px
/// la barre est dans le flux ; en deçà elle glisse par-dessus (tiroir).
/// `<header class="h-16 bg-navy … px-4 sm:px-6">`.
///
/// Bascule d'affichage de la barre latérale « pour une vue plein écran » —
/// `#bouton-plein-ecran` de la vue, ajout décidé par le Product Owner le
/// 02/09/2026. Poste de travail seulement (`hidden lg:flex`). Contrairement à
/// la vue, l'état n'est PAS conservé d'une session à l'autre : la vue le range
/// dans `localStorage`, ce client n'a pas d'équivalent décidé ; la barre est
/// visible à chaque ouverture.
final barreLateraleVisibleProvider =
    NotifierProvider<_VisibiliteBarreLaterale, bool>(
      _VisibiliteBarreLaterale.new,
    );

final class _VisibiliteBarreLaterale extends Notifier<bool> {
  @override
  bool build() => true;

  void basculer() => state = !state;
}

/// La route de l'écran POS comptant — la cible de l'indicateur de caisse et du
/// bouton « Vente » (`route('pwa.pos.comptant')` dans la vue).
const String _routePosComptant = '/pos';

/// La route de l'écran Paramètres — cible de « Paramètres du compte »
/// (`liensChassis()['parametres_compte']` → `pwa.parametres`).
const String _routeParametres = '/parametres';

/// Le message de l'Article 3.3 : un contrôle sans écran DIT pourquoi il ne
/// mène nulle part, au lieu de ne rien faire. Le message précédent est RETIRÉ,
/// pas seulement masqué : deux clics sur deux entrées sans écran doivent dire
/// chacun le leur, tout de suite.
void _direMessage(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..removeCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class CoquilleApplication extends ConsumerWidget {
  const CoquilleApplication({
    required this.routeActive,
    required this.child,
    super.key,
  });

  final String routeActive;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `MediaQuery` et non `constraints.maxWidth` — doctrine §2, défaut de
    // responsive n° 1 : la largeur du contenu n'est pas celle de l'écran.
    final large = Breakpoints.de(context) == Palier.desktop;
    final barreVisible = ref.watch(barreLateraleVisibleProvider);

    return Scaffold(
      backgroundColor: AppColors.fondClair,
      // `lg:hidden` : le tiroir n'existe qu'en deçà du seuil. Au-delà, la barre
      // latérale est dans le flux et un tiroir ferait doublon.
      drawer: large ? null : const Drawer(child: _BarreLaterale()),
      // Une pile : la page, puis le bouton flottant « Accès rapides » et son
      // panneau (`partials/acces-rapide`, lot 3, 13/10/2026), posés AU-DESSUS
      // de la barre supérieure comme les `fixed` de la vue. Le panneau ne rend
      // rien sur une page dont la vue ne l'inclut pas.
      body: Stack(
        children: [
          Column(
            children: [
              _BarreSuperieure(routeActive: routeActive),
              // `#shell-banniere` : le bandeau « Accès lecture seule », sous la
              // barre supérieure et avant le corps (`partials/banniere`).
              BandeauLectureSeule(routeActive: routeActive),
              Expanded(
                child: Row(
                  // La barre latérale et la page occupent TOUTE la hauteur
                  // (`flex flex-1 overflow-hidden`, enfants `h-full`) : sans
                  // `stretch`, une page plus courte que la fenêtre se
                  // centrait verticalement (9 px de décalage mesuré sur
                  // Inventaires, Phase 1D).
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // `fixed lg:static` : au-delà du seuil, la barre occupe
                    // sa place dans la rangée au lieu de flotter.
                    if (large && barreVisible) const _BarreLaterale(),
                    // Marge basse de sûreté sous CHAQUE écran (demande du PO
                    // du 14/10/2026) : le dernier bouton ne passe jamais sous
                    // la barre des tâches Windows. Écart à la vue, qui n'en a
                    // pas besoin (le navigateur borne la page à sa fenêtre).
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(
                          bottom: AppLayout.margeBasseEcran,
                        ),
                        child: child,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned.fill(child: PanneauAccesRapide(routeActive: routeActive)),
        ],
      ),
    );
  }
}

/// La barre supérieure — `partials/barre-superieure`, le bloc `<header>`.
///
/// `h-16` = 64 px, fond navy, `px-4 sm:px-6`. Ordre de la vue, de gauche à
/// droite : menu mobile, bascule plein écran, logo et identité, `flex-1`,
/// recherche globale, pastille « Réseau », indicateur de caisse, « Vente »,
/// cloche, menu de compte.
class _BarreSuperieure extends ConsumerWidget implements PreferredSizeWidget {
  const _BarreSuperieure({required this.routeActive});

  /// La route affichée — l'indicateur de caisse se relit quand elle change.
  final String routeActive;

  @override
  Size get preferredSize =>
      const Size.fromHeight(AppLayout.hauteurBarreSuperieure);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final droits = ref.watch(droitsProvider);
    final large = Breakpoints.de(context) == Palier.desktop;
    final moyen = Breakpoints.de(context) != Palier.mobile;
    final blancAttenue = AppColors.neutre0.withValues(
      alpha: OpacitesCoquille.texteAttenue,
    );
    // `MenuLateral::peutVoirRoute($u, 'pwa.pos.comptant')` : le module de la
    // route au registre — M5 —, masqué sur `-` seulement (comme la barre
    // latérale). `IndicateurCaisse::pour()` applique la MÊME règle.
    final peutVendre = droits.peutLire(ModuleTatacora.m5Bar);

    return Container(
      height: AppLayout.hauteurBarreSuperieure,
      color: AppColors.navy,
      padding: EdgeInsets.symmetric(
        horizontal: moyen ? AppSpacing.lg : AppSpacing.md,
      ),
      child: Row(
        children: [
          // `#bouton-menu-mobile`, `lg:hidden … mr-3`, tracé 22 px.
          if (!large)
            Builder(
              builder: (context) => Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: Tooltip(
                  message: LibellesCoquille.ouvrirMenu,
                  child: InkWell(
                    key: const Key('bouton-menu-mobile'),
                    onTap: () => Scaffold.of(context).openDrawer(),
                    child: IconeTrace(
                      trace: TracesCoquille.menuMobile,
                      taille: AppLayout.iconeBarreSuperieure,
                      couleur: blancAttenue,
                    ),
                  ),
                ),
              ),
            ),

          // `#bouton-plein-ecran` : `hidden lg:flex … mr-3`, tracé 22 px.
          if (large) ...[
            Tooltip(
              message: LibellesCoquille.pleinEcran,
              child: InkWell(
                key: const Key('bouton-plein-ecran'),
                onTap: () =>
                    ref.read(barreLateraleVisibleProvider.notifier).basculer(),
                child: IconeTrace(
                  trace: TracesCoquille.pleinEcran,
                  taille: AppLayout.iconeBarreSuperieure,
                  couleur: blancAttenue,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm), // mr-3
          ],

          // Le logo : `w-[73px] h-10 rounded-lg bg-white object-contain
          // ring-2 ring-gold` (`partials/barre-superieure`). Décision du PO
          // du 14/10/2026 (D392) : le logo est un PNG PAYSAGE, `object-contain`
          // — d'où `BoxFit.contain`, jamais d'étirement. PA-210 tranchée par
          // le PO le 14/10/2026, option (c) : cadre PAYSAGE au ratio du logo
          // (73 × 40), fond blanc comme le PNG.
          //
          // L'anneau est un `box-shadow: 0 0 0 2px` : il ne prend aucune
          // place ET n'est peint que HORS de la boîte. Une `BoxShadow`
          // Flutter, elle, se peint aussi SOUS la boîte : tant que l'image
          // couvrait tout, rien ne se voyait ; avec `contain`, les bandes
          // libres au-dessus et au-dessous du paysage seraient dorées, là où
          // la vue laisse voir le bleu nuit de la barre. D'où une bordure
          // tracée À L'EXTÉRIEUR (`strokeAlignOutside`) : même anneau, aucune
          // place prise, rien sous l'image.
          Semantics(
            label: LibellesCoquille.altLogo,
            image: true,
            child: Container(
              key: const Key('logo-barre-superieure'),
              decoration: BoxDecoration(
                color: AppColors.neutre0, // bg-white
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: AppColors.gold,
                  width: AppLayout.anneauLogo,
                  strokeAlign: BorderSide.strokeAlignOutside,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                // Le logo téléversé (Paramètres → Logo & Apparence), à défaut
                // l'actif livré.
                child: switch (ref.watch(logoTeleverseProvider).value) {
                  final octets? => Image.memory(
                    octets,
                    width: AppLayout.logoBarreSuperieureLargeur,
                    height: AppLayout.logoBarreSuperieure,
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                  ),
                  _ => Image.asset(
                    AppAssets.logo,
                    width: AppLayout.logoBarreSuperieureLargeur,
                    height: AppLayout.logoBarreSuperieure,
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                  ),
                },
              ),
            ),
          ),
          // `gap-3` = 12 px. ⚠ Il valait 16 (`AppSpacing.md`) jusqu'au
          // 12/10/2026 sous un commentaire qui disait 12 : la marque et son
          // badge étaient décalés de 4 px vers la droite (relevé du châssis).
          const SizedBox(width: AppSpacing.sm),
          // `hidden md:block` : l'identité disparaît en mobile, le logo reste.
          //
          // L'identité OCCUPE la place du `<div class="flex-1">` qui la suit
          // (`Expanded`, contenu calé à gauche) au lieu d'un `Spacer` : à
          // largeur suffisante, les positions sont les mêmes (identité au même
          // x, éléments de droite poussés au bord). Écart de la vue
          // (`partials/barre-superieure` l.127, `shrink-0` : la marque ne
          // rétrécit jamais, et une barre trop étroite DÉBORDE), daté du
          // 13/10/2026 : la ligne sous la marque a pris ~105 px avec la
          // décision du PO (D373 ; « Système de gestion Intégré » depuis
          // D389, quelques pixels de moins) ; à
          // largeur insuffisante, elle se coupe par une ellipse plutôt que de
          // pousser la barre hors de la fenêtre (débordement = erreur de rendu
          // Flutter).
          if (moyen)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ⚠ Défaut corrigé le 14/10/2026 (passe finale) : le badge
                  // était INFLEXIBLE — quand la recherche globale (lot B) a
                  // réduit la place de l'identité, la marque se réduisait à
                  // rien et le badge DÉBORDAIT (erreur de rendu, contenu
                  // coupé), contrairement à l'ellipse promise ci-dessus. Les
                  // deux sont désormais flexibles, chacun au prorata de sa
                  // largeur NATURELLE : à largeur suffisante, chacun reçoit au
                  // moins sa largeur (rendu identique) ; sinon, les deux se
                  // coupent par une ellipse, sans jamais déborder.
                  Builder(
                    builder: (context) {
                      final echelle = MediaQuery.textScalerOf(context);
                      double largeur(String texte, TextStyle style) =>
                          (TextPainter(
                            text: TextSpan(text: texte, style: style),
                            textDirection: TextDirection.ltr,
                            textScaler: echelle,
                            maxLines: 1,
                          )..layout()).width;
                      final styleMarque = TextStyle(
                        // `tracking-tight` : −0,025 em.
                        letterSpacing: AppTextStyles.suiviSerre * Tailles.t16,
                        color: AppColors.neutre0,
                        fontFamily: AppTextStyles.police,
                        fontSize: Tailles.t16,
                        fontWeight: FontWeight.bold,
                      );
                      const styleBadge = TextStyle(
                        color: AppColors.gold,
                        fontFamily: AppTextStyles.police,
                        fontSize: Tailles.t10,
                        fontWeight: FontWeight.w600,
                      );
                      // Badge : texte + `px-1.5` des deux côtés + bordure 1 px.
                      final lMarque = largeur(
                        LibellesCoquille.marque,
                        styleMarque,
                      );
                      final lBadge =
                          largeur(LibellesCoquille.enseigneCourte, styleBadge) +
                          2 * AppSpacing.xxs +
                          2 * AppLayout.bordureControle;
                      int flex(double l) => math.max(1, l.ceil());
                      return Row(
                        children: [
                          Flexible(
                            flex: flex(lMarque),
                            child: Text(
                              LibellesCoquille.marque,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: styleMarque,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs), // gap-2
                          // Le badge doré « Gîte Chez Noël » — bordure, pas un
                          // fond.
                          Flexible(
                            flex: flex(lBadge),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xxs,
                                vertical: AppSpacing.demi,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.gold),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm,
                                ),
                              ),
                              child: Text(
                                LibellesCoquille.enseigneCourte,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                style: styleBadge,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  Text(
                    LibellesCoquille.localisation,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.neutre0.withValues(
                        alpha: OpacitesCoquille.texteSecondaire,
                      ),
                      fontFamily: AppTextStyles.police,
                      fontSize: Tailles.t11,
                    ),
                  ),
                ],
              ),
            )
          else
            const Spacer(), // `<div class="flex-1"></div>`, sans identité
          // La recherche globale (`<livewire:pwa.recherche-globale />`,
          // `partials/barre-superieure` l.162, ajout du PO du 01/09/2026) —
          // PORTÉE le 14/10/2026 (lot B) : `hidden md:block mr-3`. Elle lit
          // les sources LOCALES du poste sous le droit de chaque module ; ses
          // écarts au serveur sont nommés dans
          // `features/recherche_globale/domain/recherche_globale.dart`.
          if (moyen) const RechercheGlobaleBarre(),
          // AJOUT du PO (20/10/2026) — le sélecteur d'exercice global
          // (`<livewire:pwa.selecteur-exercice />`, juste après la recherche),
          // sur les seuls écrans qui le suivent.
          if (moyen) SelecteurExerciceBarre(routeActive: routeActive),
          //
          // REFUSÉ — la pastille « Réseau » (l.154-157). Ce poste est ZÉRO
          // RÉSEAU (14/09/2026) : un badge vert affirmerait une liaison qui
          // n'existe pas, la famille PA-59/60/61. Refus daté du 12/10/2026.
          // Le poste se synchronise de nouveau depuis le 15/10/2026 : l'état
          // de la synchronisation est dit par le bouton de synchronisation
          // (plus loin, lot F3), pas par une pastille « Réseau ».
          //
          // La pastille d'ENVIRONNEMENT (« Environnement : Développement ») est
          // RETIRÉE le 21/10/2026, à la demande du PO : la barre est celle de
          // la vue.

          // `#indicateur-caisse` (l.167-186) — `hidden md:block`, rôle avec M5.
          if (moyen && peutVendre) _IndicateurCaisse(routeActive: routeActive),

          // « Vente » (l.189-198) — même garde que l'indicateur.
          if (peutVendre) const _BoutonVente(),

          // La cloche et son panneau (`<livewire:pwa.cloche-notifications />`,
          // l.224) — PORTÉE le 14/10/2026 (lot B). Elle liste les alertes
          // DÉRIVÉES du poste (stock, caisse, créances ; les arrivées du jour
          // ne le sont pas, et le panneau le dit) et écrit l'état « vu » du
          // compte dans `alertes_vues_local` (schéma v22). Ses 36 px entre
          // « Vente » et le menu de compte ramènent « Vente » et l'indicateur
          // de caisse à leur place (décalage de ~35 px relevé au lot 1).
          // AJOUT du PO (16/10/2026, lot F3) — le bouton de SYNCHRONISATION :
          // la vue n'en a pas (elle est servie par le serveur). À gauche de la
          // cloche, avec sa forme ; un voyant dit l'état de la file, la
          // modale lance « Synchroniser maintenant ». La pastille « Réseau »
          // reste refusée : un poste ne sait pas s'il est « en réseau », il
          // sait ce qui attend de partir.
          if (session != null) const BoutonSynchronisation(),
          if (session != null) ClocheNotifications(routeActive: routeActive),
          if (session != null) _MenuProfil(session: session),
        ],
      ),
    );
  }
}

/// L'indicateur de caisse — `#indicateur-caisse`, état RÉEL de
/// `sessions_caisse_local` (`IndicateurCaisse::pour()`, répliqué dans
/// `features/caisse/domain/indicateur_caisse.dart`).
///
/// Écart de la VUE, repris tel quel : c'est un LIEN vers le POS comptant, pas
/// un bouton d'action — le geste de caisse a un seul propriétaire, la barre de
/// session de l'écran POS. Tant que l'état n'est pas lu (ou si la lecture
/// échoue), RIEN n'est rendu : « Caisse fermée » sans lecture serait un état
/// affirmé et non vérifié (PA-59/60/61). Garanti par
/// `coquille_rendu_test.dart` (dépôt muet, dépôt qui lève).
///
/// ## Relu à CHAQUE navigation, comme la vue (12/10/2026, contrôle B-1)
///
/// La vue rappelle `IndicateurCaisse::pour()` à chaque rendu de page : une
/// caisse ouverte la veille passe au rouge dès la page suivante. Ce widget
/// relit [indicateurCaisseProvider] à son montage (coquille recréée : après
/// une reconnexion, l'état d'avant ne doit pas resservir) et à chaque
/// changement de [routeActive] (coquille conservée par la `ShellRoute`).
/// L'invalidation garde la valeur précédente pendant la relecture : la
/// pastille ne clignote pas d'une page à l'autre.
class _IndicateurCaisse extends ConsumerStatefulWidget {
  const _IndicateurCaisse({required this.routeActive});

  final String routeActive;

  @override
  ConsumerState<_IndicateurCaisse> createState() => _EtatIndicateurCaisse();
}

class _EtatIndicateurCaisse extends ConsumerState<_IndicateurCaisse> {
  /// La relecture est posée APRÈS l'image en cours : invalider pendant la
  /// construction marquerait à reconstruire un widget déjà construit dans la
  /// même passe, ce que le framework refuse (assertion relevée en test).
  void _relire() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(indicateurCaisseProvider);
    });
  }

  @override
  void initState() {
    super.initState();
    _relire();
  }

  @override
  void didUpdateWidget(covariant _IndicateurCaisse ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.routeActive != widget.routeActive) _relire();
  }

  @override
  Widget build(BuildContext context) {
    final lu = ref.watch(indicateurCaisseProvider);
    final indicateur = lu.hasValue && !lu.hasError ? lu.value : null;
    if (indicateur == null) return const SizedBox.shrink();

    final fermee = indicateur.etat == EtatCaisse.fermee;
    final tardive = indicateur.etat == EtatCaisse.tardive;
    // `bg-slate-400` / `bg-emerald-400` / `bg-red-400`.
    final pastille = fermee
        ? AppColors.neutre400
        : tardive
        ? PaletteMaitre.rouge400
        : PaletteMaitre.emeraude400;
    // `border-white/15`, ou `border-red-400/60 bg-red-500/10` passé 24 h.
    final bordure = tardive
        ? PaletteMaitre.rouge400.withValues(
            alpha: OpacitesCoquille.bordureCaisseTardive,
          )
        : AppColors.neutre0.withValues(alpha: OpacitesCoquille.bordureCaisse);
    final fond = tardive
        ? PaletteMaitre.rouge500.withValues(
            alpha: OpacitesCoquille.fondCaisseTardive,
          )
        : Colors.transparent;
    // `text-white/80` fermée, `text-white/90` ouverte.
    final couleurTexte = AppColors.neutre0.withValues(
      alpha: fermee
          ? OpacitesCoquille.texteAttenue
          : OpacitesCoquille.texteCaisseOuverte,
    );

    Widget lien = Material(
      color: fond,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md), // rounded-lg
        side: BorderSide(color: bordure, width: AppLayout.filetCoquille),
      ),
      child: InkWell(
        key: const Key('indicateur-caisse'),
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => GoRouter.of(context).go(_routePosComptant),
        child: Padding(
          // `px-3 py-2`, plus le filet de 1 px que le navigateur compte DANS
          // la boîte et que `RoundedRectangleBorder` n'ajoute pas.
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm + AppLayout.bordureControle,
            vertical: AppSpacing.xs + AppLayout.bordureControle,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                key: const Key('pastille-caisse'),
                width: AppLayout.pastilleCaisse,
                height: AppLayout.pastilleCaisse,
                decoration: BoxDecoration(
                  color: pastille,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.xs), // gap-2
              Text(
                fermee
                    ? LibellesCoquille.caisseFermee
                    : LibellesCoquille.caisseCloturer,
                style: TextStyle(
                  color: couleurTexte,
                  fontFamily: AppTextStyles.police,
                  fontSize: Tailles.t12,
                  height: Tailles.interligneXsHorsMain,
                  letterSpacing: 0,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // `title="Clôturer la caisse du :point"` — sur la caisse OUVERTE seulement.
    final point = indicateur.point;
    if (!fermee && point != null) {
      lien = Tooltip(
        message: LibellesCoquille.caisseCloturerTitre(point.libelle),
        child: lien,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs), // mr-2
      child: lien,
    );
  }
}

/// Le bouton « Vente » — `bg-gold text-white text-xs font-bold px-3.5 py-2
/// rounded-lg shadow-sm mr-2`, tracé 15 px à 2,5, vers le POS comptant.
/// « Vente » et non « Point de vente » : directive du PO du 02/09/2026, portée
/// par la vue.
class _BoutonVente extends StatelessWidget {
  const _BoutonVente();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs), // mr-2
      child: Tooltip(
        message: LibellesCoquille.venteTitre,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.gold,
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: AppShadows.tailwindSm,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: const Key('bouton-vente'),
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () => GoRouter.of(context).go(_routePosComptant),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.smPlus, // px-3.5
                  vertical: AppSpacing.xs, // py-2
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const IconeTrace(
                      trace: TracesCoquille.vente,
                      taille: AppLayout.iconeVente,
                      couleur: AppColors.neutre0,
                      epaisseur: AppLayout.epaisseurTraceVente,
                    ),
                    const SizedBox(width: AppSpacing.xs), // gap-2
                    Text(
                      LibellesCoquille.vente,
                      style: TextStyle(
                        color: AppColors.neutre0,
                        fontFamily: AppTextStyles.police,
                        fontSize: Tailles.t12,
                        height: Tailles.interligneXsHorsMain,
                        letterSpacing: 0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Une entrée du menu de compte — `lien-chassis` : un lien quand l'écran
/// existe et que le droit le permet, sinon une ligne qui DIT pourquoi.
final class _EntreeCompte {
  const _EntreeCompte(this.cle, this.libelle, this.trace, {this.route});

  final String cle;
  final String libelle;
  final String trace;

  /// La route Flutter, `null` quand ce poste n'a pas l'écran.
  final String? route;
}

/// Le menu de compte — `#menu-profil`, `partials/barre-superieure` l.213-266.
///
/// En-tête (login, rôle), puis les quatre entrées de compte (Mon profil,
/// Paramètres du compte, Import & Export, Journal d'Audit), un filet, les deux
/// entrées d'aide (Aide & À propos, Contactez l'éditeur), un filet, et la
/// Déconnexion en rouge — l'ordre de la vue.
///
/// ## Les droits et les écrans, entrée par entrée (12/10/2026)
///
/// La vue garde chaque LIGNE et remplace le lien par une `<span>` portant sa
/// raison quand le droit manque (`MenuLateral::liensChassis()` : PARAM pour
/// Paramètres et Import & Export, M14 pour le Journal d'Audit). Ce client fait
/// de même. Depuis le 14/10/2026 (lot D, D424) les six entrées ont leur écran
/// Flutter ; la seconde raison (« Écran de consultation à venir », message au
/// clic) ne reste que le repli d'une entrée qui perdrait sa route.
///
/// Écart de rendu, daté : l'ombre `shadow-2xl` du panneau n'est pas rendue —
/// `PopupMenuButton` n'accepte qu'une élévation Material, qui ne reproduit pas
/// l'ombre de la vue ; le filet `border-slate-100` tient le contour.
class _MenuProfil extends ConsumerWidget {
  const _MenuProfil({required this.session});

  final Session session;

  static const _compte = [
    _EntreeCompte(
      'mon_profil',
      LibellesCoquille.monProfil,
      TracesCoquille.monProfil,
      route: '/mon-profil',
    ),
    _EntreeCompte(
      'parametres_compte',
      LibellesCoquille.parametresCompte,
      TracesCoquille.parametresCompte,
      route: _routeParametres,
    ),
    _EntreeCompte(
      'import_export',
      LibellesCoquille.importExport,
      TracesCoquille.importExport,
      route: '/import-export',
    ),
    _EntreeCompte(
      'journal_audit',
      LibellesCoquille.journalAudit,
      TracesCoquille.journalAudit,
      route: '/journal-audit',
    ),
    // Décision PO du 18/10/2026 — même tracé que la vue (Import & Export).
    _EntreeCompte(
      'synchronisation_postes',
      LibellesCoquille.synchronisationPostes,
      TracesCoquille.importExport,
      route: '/synchronisation-postes',
    ),
  ];

  static const _aide = [
    _EntreeCompte(
      'aide_a_propos',
      LibellesCoquille.aideAPropos,
      TracesCoquille.aideAPropos,
      route: '/aide-a-propos',
    ),
    _EntreeCompte(
      'contact_editeur',
      LibellesCoquille.contactEditeur,
      TracesCoquille.contactEditeur,
      route: '/contact-editeur',
    ),
  ];

  /// Le module exigé par chaque lien — `liensChassis()`, `$exigences`.
  static ModuleTatacora? _moduleExige(String cle) => switch (cle) {
    'parametres_compte' || 'import_export' => ModuleTatacora.parametres,
    'journal_audit' => ModuleTatacora.m14Etats,
    _ => null,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moyen = Breakpoints.de(context) != Palier.mobile;
    final droits = ref.watch(droitsProvider);
    final role = roleAffiche(session.role);

    bool autorise(_EntreeCompte e) {
      final module = _moduleExige(e.cle);
      return module == null || droits.peutLire(module);
    }

    /// La raison d'une ligne qui ne mène nulle part — `null` pour un lien.
    String? raison(_EntreeCompte e) {
      if (!autorise(e)) return LibellesCoquille.sansDroit;
      if (e.route == null) return LibellesCoquille.ecranAVenir;
      return null;
    }

    final toutes = [..._compte, ..._aide];

    PopupMenuItem<String> ligne(_EntreeCompte e) {
      final pourquoi = raison(e);
      Widget contenu = Row(
        children: [
          IconeTrace(
            trace: e.trace,
            taille: AppLayout.iconeMenuCompte,
            couleur: AppColors.neutre600,
          ),
          const SizedBox(width: AppSpacing.xsPlus), // gap-2.5
          // `Flexible` : dans la vue, un libellé trop long pour `w-56` passe à
          // la ligne (comportement par défaut du navigateur), il ne déborde pas.
          Flexible(
            child: Text(
              e.libelle,
              style: TextStyle(
                fontFamily: AppTextStyles.police,
                fontSize: Tailles.t12,
                height: Tailles.interligneXsHorsMain,
                letterSpacing: 0,
                color: AppColors.neutre600, // text-slate-600
              ),
            ),
          ),
        ],
      );
      if (pourquoi != null) {
        contenu = Tooltip(message: pourquoi, child: contenu);
      }
      return PopupMenuItem<String>(
        key: Key('compte-${e.cle}'),
        value: e.cle,
        height: AppLayout.ligneMenuCompte,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: contenu,
      );
    }

    PopupMenuItem<String> separateur() => PopupMenuItem<String>(
      enabled: false,
      height: AppLayout.separateurMenuCompte,
      padding: EdgeInsets.zero,
      child: Container(
        height: AppLayout.filetCoquille,
        color: AppColors.neutre100, // border-slate-100
      ),
    );

    return Container(
      // `relative ml-2 pl-3 border-l border-white/10`.
      margin: const EdgeInsets.only(left: AppSpacing.xs),
      padding: const EdgeInsets.only(left: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: AppColors.neutre0.withValues(alpha: OpacitesCoquille.filet),
            width: AppLayout.filetCoquille,
          ),
        ),
      ),
      child: PopupMenuButton<String>(
        tooltip: session.login,
        offset: const Offset(0, AppLayout.decalageMenuCompte), // top-12
        color: AppColors.neutre0,
        elevation: 0,
        menuPadding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg), // rounded-xl
          side: const BorderSide(color: AppColors.neutre100),
        ),
        constraints: const BoxConstraints.tightFor(
          width: AppLayout.menuCompte,
        ), // w-56
        onSelected: (cle) {
          if (cle == 'deconnexion') {
            ref.read(sessionProvider.notifier).deconnecter();
            return;
          }
          final e = toutes.firstWhere((x) => x.cle == cle);
          if (!autorise(e)) {
            _direMessage(context, LibellesCoquille.sansDroit);
          } else if (e.route == null) {
            _direMessage(context, LibellesCoquille.ecranNonPorte(e.libelle));
          } else {
            GoRouter.of(context).go(e.route!);
          }
        },
        itemBuilder: (context) => [
          // `px-4 py-2.5 border-b border-slate-100` : login et rôle.
          PopupMenuItem<String>(
            enabled: false,
            padding: EdgeInsets.zero,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xsPlus,
              ),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.neutre100)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.login,
                    style: TextStyle(
                      fontFamily: AppTextStyles.police,
                      fontSize: Tailles.t12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.neutre700, // text-slate-700
                    ),
                  ),
                  Text(
                    role,
                    style: TextStyle(
                      fontFamily: AppTextStyles.police,
                      fontSize: Tailles.t11,
                      color: AppColors.neutre400, // text-slate-400
                    ),
                  ),
                ],
              ),
            ),
          ),
          for (final e in _compte) ligne(e),
          separateur(),
          for (final e in _aide) ligne(e),
          separateur(),
          PopupMenuItem<String>(
            key: const Key('compte-deconnexion'),
            value: 'deconnexion',
            height: AppLayout.ligneMenuCompte,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                const IconeTrace(
                  trace: TracesCoquille.deconnexion,
                  taille: AppLayout.iconeMenuCompte,
                  couleur: AppColors.erreur,
                ),
                const SizedBox(width: AppSpacing.xsPlus), // gap-2.5
                Flexible(
                  child: Text(
                    LibellesCoquille.deconnexion,
                    style: TextStyle(
                      fontFamily: AppTextStyles.police,
                      fontSize: Tailles.t12,
                      height: Tailles.interligneXsHorsMain,
                      letterSpacing: 0,
                      color: AppColors.erreur, // text-[var(--erreur)]
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        // `#bouton-menu-profil` : `flex items-center gap-2 px-2 py-1.5`.
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.xxs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Avatar(initiales: initialesDeLogin(session.login)),
              // `hidden sm:block`
              if (moyen) ...[
                const SizedBox(width: AppSpacing.xs),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.login,
                      style: TextStyle(
                        color: AppColors.neutre0,
                        fontFamily: AppTextStyles.police,
                        fontSize: Tailles.t12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      role,
                      style: TextStyle(
                        color: AppColors.gold,
                        fontFamily: AppTextStyles.police,
                        fontSize: Tailles.t10,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(width: AppSpacing.xs), // gap-2
              IconeTrace(
                trace: TracesCoquille.chevron,
                taille: AppLayout.iconeChevronCompte,
                couleur: AppColors.neutre0.withValues(
                  alpha: OpacitesCoquille.chevron,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `w-8 h-8 rounded-full bg-gold text-navy font-bold text-xs` — l'avatar aux
/// initiales, le MÊME dans la barre supérieure et au pied de la barre latérale.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.initiales});

  final String initiales;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppLayout.avatarCoquille,
      height: AppLayout.avatarCoquille,
      decoration: const BoxDecoration(
        color: AppColors.gold,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initiales,
        style: TextStyle(
          color: AppColors.navy,
          fontFamily: AppTextStyles.police,
          fontSize: Tailles.t12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// La barre latérale — `partials/menu-lateral`, entrées `partials/entree-menu`,
/// registre `MenuLateral::NAVIGATION`.
///
/// `w-[264px] bg-navy flex flex-col h-full`, une zone défilante puis un pied
/// séparé par `border-t border-white/10`.
class _BarreLaterale extends ConsumerWidget {
  const _BarreLaterale();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final droits = ref.watch(droitsProvider);
    final session = ref.watch(sessionProvider);
    final routeActive = GoRouterState.of(context).uri.path;

    /// `MenuLateral::pour()` : l'entrée **disparaît** sur `-`, elle n'est pas
    /// grisée. Premier des trois niveaux RBAC de RG-16. Et le masquage PAR
    /// RÔLE (`ROUTES_MASQUEES_PAR_ROLE`, Phase 1B) : le gérant ne voit pas les
    /// onze entrées que la vue lui cache.
    ///
    /// La règle vit dans `navigation_tatacora.dart` ([destinationVisible]) :
    /// la garde du routeur en lit la moitié « accès » ([destinationAccessible]),
    /// pour qu'une entrée absente du menu soit aussi une route refusée.
    bool visible(DestinationMenu d) =>
        destinationVisible(d, droits: droits, role: session?.role);

    final enfants = <Widget>[
      for (final d in destinationsEpinglees)
        if (visible(d)) _LienLateral(destination: d, routeActive: routeActive),
      // `.sidebar-nav .epingle:last-of-type` (`app.css` l.184-188) : le bloc
      // des entrées épinglées est séparé du reste par UNE bordure —
      // `padding-bottom: .5rem`, `border-bottom: 1px rgba(255,255,255,.1)`,
      // `margin-bottom: .25rem`.
      if (destinationsEpinglees.any(visible))
        Container(
          key: const Key('filet-epingles'),
          margin: const EdgeInsets.only(
            top: AppSpacing.xs,
            bottom: AppSpacing.unit,
          ),
          height: AppLayout.filetCoquille,
          color: AppColors.neutre0.withValues(alpha: OpacitesCoquille.filet),
        ),
      for (final groupe in groupesMenu)
        // Un groupe dont toutes les entrées sont masquées ne laisse pas son
        // titre orphelin (`if ($items === []) continue;`).
        if (groupe.destinations.any(visible)) ...[
          _TitreGroupe(titre: groupe.titre),
          for (final d in groupe.destinations)
            if (visible(d))
              _LienLateral(destination: d, routeActive: routeActive),
        ],
    ];

    return Container(
      width: AppLayout.sidebarWidth, // w-[264px]
      color: AppColors.navy,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(
                top: AppSpacing.xs,
                bottom: AppSpacing.sm,
                // La zone défilante de la vue réserve la place de sa barre de
                // défilement (`overflow-y-auto`, 8 px) : badges et noms
                // s'arrêtent 8 px plus tôt (mesuré, Phase 1D).
                right: AppLayout.gouttiereDefilement,
              ),
              children: enfants,
            ),
          ),
          if (session != null)
            _PiedBarreLaterale(
              initiales: initialesDeLogin(session.login),
              nom: session.login,
              fonction: roleAffiche(session.role),
              onDeconnexion: () =>
                  ref.read(sessionProvider.notifier).deconnecter(),
            ),
        ],
      ),
    );
  }
}

/// `<p class="px-4 pt-3 pb-1 text-[10.5px] font-bold tracking-wider
/// text-white/45">{{ Str::upper($section['groupe']) }}</p>`
class _TitreGroupe extends StatelessWidget {
  const _TitreGroupe({required this.titre});

  final String titre;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: AppSpacing.sm,
        bottom: AppSpacing.unit,
      ),
      child: Text(
        titre.toUpperCase(),
        style: TextStyle(
          color: AppColors.neutre0.withValues(
            alpha: OpacitesCoquille.titreGroupe,
          ),
          fontFamily: AppTextStyles.police,
          // La vue écrit `text-[10.5px]` — une demi-unité, relevée telle
          // quelle plutôt qu'arrondie à 10 ou 11.
          fontSize: Tailles.t10_5,
          fontWeight: FontWeight.bold,
          // `tracking-wider` : 0,05 em, PROPORTIONNEL à la taille.
          letterSpacing: AppTextStyles.suiviPlusLarge * Tailles.t10_5,
          // `line-height` hérité du corps (1,5), comme les entrées.
          height: AppLayout.interligneContenu,
        ),
      ),
    );
  }
}

/// `<a class="lien-sidebar … flex items-center gap-2.5 mx-2 px-3 py-[7px]
/// rounded-lg text-white hover:bg-white/10 text-[14px] font-medium">`, son
/// `<svg width="17">` et son nom `flex-1 truncate`.
///
/// Une entrée SANS écran Flutter suit la branche `<span aria-disabled
/// title="Écran de consultation à venir">` de la vue — mêmes classes, même
/// infobulle — et son clic DIT que l'écran n'est pas porté (Article 3.3).
class _LienLateral extends StatelessWidget {
  const _LienLateral({required this.destination, required this.routeActive});

  final DestinationMenu destination;
  final String routeActive;

  @override
  Widget build(BuildContext context) {
    final route = destination.route;
    final actif = route != null && routeActive == route;

    Widget lien = Material(
      // `.lien-sidebar.actif { background: var(--gold-actif); color: #fff;
      // font-weight: 700 }` (`public/assets/css/app.css` l.165-170).
      color: actif ? AppColors.goldActif : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.md), // rounded-lg
      child: InkWell(
        key: Key('lien-lateral-${destination.nom}'),
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: route != null
            ? () => GoRouter.of(context).go(route)
            : () => _direMessage(
                context,
                LibellesCoquille.ecranNonPorte(destination.nom),
              ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, // px-3
            vertical: AppSpacing.entreeSidebar, // py-[7px]
          ),
          child: Row(
            children: [
              IconeTrace(
                trace: destination.icone.trace,
                taille: AppLayout.iconeLienSidebar, // width="17"
                couleur: AppColors.neutre0,
              ),
              const SizedBox(width: AppSpacing.xsPlus), // gap-2.5
              Expanded(
                child: Text(
                  destination.nom,
                  overflow: TextOverflow.ellipsis, // truncate
                  style: TextStyle(
                    color: AppColors.neutre0,
                    fontFamily: AppTextStyles.police,
                    fontSize: Tailles.lienSidebar,
                    // La vue hérite du `line-height` du corps (1,5) : une
                    // entrée fait 21 + 14 = 35 px, pas 34 (mesuré, Phase 1D).
                    height: AppLayout.interligneContenu,
                    fontWeight: actif ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (destination.badge != null) _Badge(destination.badge!),
            ],
          ),
        ),
      ),
    );
    if (route == null) {
      lien = Tooltip(message: LibellesCoquille.ecranAVenir, child: lien);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs), // mx-2
      child: lien,
    );
  }
}

/// `<span class="text-[8px] font-bold bg-succes text-white rounded px-1.5
/// py-0.5">`
class _Badge extends StatelessWidget {
  const _Badge(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxs,
        vertical: AppSpacing.demi,
      ),
      decoration: BoxDecoration(
        color: AppColors.succes,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        texte,
        style: TextStyle(
          color: AppColors.neutre0,
          fontFamily: AppTextStyles.police,
          fontSize: Tailles.t8,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Le pied de la barre latérale — `border-t border-white/10 px-4 py-3`.
class _PiedBarreLaterale extends StatelessWidget {
  const _PiedBarreLaterale({
    required this.initiales,
    required this.nom,
    required this.fonction,
    required this.onDeconnexion,
  });

  final String initiales;
  final String nom;
  final String fonction;
  final VoidCallback onDeconnexion;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: AppColors.neutre0.withValues(alpha: OpacitesCoquille.filet),
            width: AppLayout.filetCoquille,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md, // px-4
        vertical: AppSpacing.sm, // py-3
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Avatar(initiales: initiales),
              const SizedBox(width: AppSpacing.xsPlus), // gap-2.5
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nom,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.neutre0,
                        fontFamily: AppTextStyles.police,
                        fontSize: Tailles.t12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      fonction,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.neutre0.withValues(
                          alpha: OpacitesCoquille.texteSecondaire,
                        ),
                        fontFamily: AppTextStyles.police,
                        fontSize: Tailles.t10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xsPlus), // mb-2.5
          // `w-full flex items-center justify-center gap-2 bg-[var(--erreur)]
          // text-white text-xs font-semibold rounded-lg py-2` — fond ROUGE,
          // décision du PO du 03/09/2026 portée par la vue ; l'icône de sortie
          // est À GAUCHE du libellé, centrés ensemble.
          Material(
            color: AppColors.erreur,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: InkWell(
              key: const Key('bouton-deconnexion-sidebar'),
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: onDeconnexion,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const IconeTrace(
                      trace: TracesCoquille.deconnexion,
                      taille: AppLayout.iconeDeconnexionSidebar,
                      couleur: AppColors.neutre0,
                    ),
                    const SizedBox(width: AppSpacing.xs), // gap-2
                    Text(
                      LibellesCoquille.deconnexion,
                      style: TextStyle(
                        color: AppColors.neutre0,
                        fontFamily: AppTextStyles.police,
                        fontSize: Tailles.t12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xsPlus), // mt-2.5
          Text(
            LibellesCoquille.mentionPiedMenu,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.neutre0.withValues(
                alpha: OpacitesCoquille.mentionPied,
              ),
              fontFamily: AppTextStyles.police,
              fontSize: Tailles.t10,
            ),
          ),
        ],
      ),
    );
  }
}

/// Les routes dont l'écran de la vue N'OFFRE PAS d'écriture : la vue
/// (`BanniereEcriture::pour`) ne rend le bandeau que pour un composant qui
/// porte une constante `MODULE` ET le trait `AutoriseEcriture` ; l'état de
/// consultation pure ne dit rien. Journal d'Audit, États, Mon profil, Aide,
/// Contact et les écrans de synchronisation (ajouts du poste) n'ont ni l'une
/// ni l'autre.
const Set<String> routesSansBandeauLectureSeule = {
  '/journal-audit',
  '/etats',
  '/mon-profil',
  '/aide-a-propos',
  '/contact-editeur',
  '/synchronisation',
  '/synchronisation-postes',
  '/comptes-utilisateurs',
};

/// Le module d'un chemin, lu au MÊME registre que la garde du routeur
/// ([toutesLesDestinations], [modulesDesRoutesHorsMenu]) : l'entrée du menu la
/// plus spécifique dont le chemin est un préfixe. `null` : route sans module.
ModuleTatacora? moduleDeLaRoute(String chemin) {
  DestinationMenu? porteuse;
  for (final d in toutesLesDestinations) {
    final route = d.route;
    if (route == null) continue;
    if (route == chemin ||
        (chemin.startsWith('$route/') &&
            (porteuse == null || route.length > porteuse.route!.length))) {
      porteuse = d;
      if (route == chemin) break;
    }
  }
  return porteuse?.module ?? modulesDesRoutesHorsMenu[chemin];
}

/// Le bandeau d'accès en lecture seule — `partials/banniere`.
///
/// Rendu quand le module de l'écran offre l'écriture et que le profil n'y a
/// pas le niveau `C` (`BanniereEcriture::LECTURE_SEULE`) ; rien sinon, comme la
/// zone `#shell-banniere` laissée vide. Le bouton referme la session
/// (`seDeconnecter` de la vue), le seul chemin de fermeture de ce poste aussi.
class BandeauLectureSeule extends ConsumerWidget {
  const BandeauLectureSeule({required this.routeActive, super.key});

  final String routeActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (routesSansBandeauLectureSeule.contains(routeActive)) {
      return const SizedBox.shrink();
    }
    final module = moduleDeLaRoute(routeActive);
    final droits = ref.watch(droitsProvider);
    if (module == null || droits.peutEcrire(module)) {
      return const SizedBox.shrink();
    }
    final etroit = Breakpoints.de(context) == Palier.mobile;
    final texte = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: LibellesCoquille.banniereLectureTitre,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const TextSpan(text: ' '),
          const TextSpan(text: LibellesCoquille.banniereLectureDetail),
        ],
      ),
      style: TextStyle(
        color: PaletteMaitre.ambre900,
        fontFamily: AppTextStyles.police,
        fontSize: Tailles.t12,
      ),
    );
    final bouton = InkWell(
      key: const Key('bouton-changer-compte-banniere'),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: () => ref.read(sessionProvider.notifier).deconnecter(),
      child: Container(
        padding: MesuresBandeauLectureSeule.margeBouton,
        decoration: BoxDecoration(
          color: PaletteMaitre.ambre900,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Text(
          LibellesCoquille.banniereChangerProfil,
          style: TextStyle(
            color: AppColors.neutre0,
            fontFamily: AppTextStyles.police,
            fontSize: Tailles.t11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
    return Container(
      key: const Key('shell-banniere'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg, // px-6
        vertical: AppSpacing.sm, // py-3
      ),
      decoration: const BoxDecoration(
        color: PaletteMaitre.ambre50, // bg-amber-50
        border: Border(
          bottom: BorderSide(
            color: PaletteMaitre.ambre300, // border-amber-300
            width: MesuresBandeauLectureSeule.filetBas,
          ),
        ),
      ),
      child: etroit
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                texte,
                const SizedBox(height: AppSpacing.xs), // gap-2
                bouton,
              ],
            )
          : Row(
              children: [
                Expanded(child: texte),
                const SizedBox(width: AppSpacing.xs), // gap-2
                bouton,
              ],
            ),
    );
  }
}
