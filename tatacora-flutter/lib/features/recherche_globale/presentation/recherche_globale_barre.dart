/// Le champ de RECHERCHE GLOBALE de la barre supérieure et son panneau de
/// résultats — composant `transverse/recherche-globale` de la vue (chemin sans
/// préfixe, PA-187), porté le 14/10/2026 (lot B du plan du PO).
///
/// Ordre et classes de la vue : `relative hidden md:block mr-3` ; la boîte
/// `flex items-center gap-2 bg-white/10 border border-white/15 rounded-lg px-3
/// py-1.5 w-64 focus-within:border-white/40`, sa loupe 14 px, le champ
/// `text-xs text-white placeholder-white/40` ; le panneau `absolute left-0
/// top-11 w-[420px] max-w-[90vw] bg-white rounded-xl shadow-2xl border
/// border-slate-100`, ouvert au focus et à la saisie, refermé par un clic
/// au-dehors (`@click.outside`). La saisie est relue après 250 ms de calme
/// (`wire:model.live.debounce.250ms`).
///
/// Ce que la recherche lit et ses écarts au serveur :
/// `features/recherche_globale/domain/recherche_globale.dart`.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/navigation/coquille_vue.dart';
import '../../../core/navigation/trace_svg.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_durations.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/recherche_globale_dao.dart';
import '../domain/recherche_globale.dart';

/// La lecture des sources — LECTURE SEULE.
final rechercheGlobaleDaoProvider = Provider<RechercheGlobaleDao>(
  (ref) => RechercheGlobaleDao(ref.watch(baseLocaleProvider)),
);

/// Le champ et son panneau.
class RechercheGlobaleBarre extends ConsumerStatefulWidget {
  const RechercheGlobaleBarre({super.key});

  @override
  ConsumerState<RechercheGlobaleBarre> createState() => _EtatRechercheGlobale();
}

class _EtatRechercheGlobale extends ConsumerState<RechercheGlobaleBarre> {
  final _champ = TextEditingController();
  final _focus = FocusNode();
  final _portail = OverlayPortalController();
  final _lien = LayerLink();
  final _groupe = Object();
  Timer? _attente;

  /// Le terme RELU (après le délai), celui des résultats affichés.
  String _terme = '';
  Future<ResultatsRecherche>? _resultats;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      // `@focus="ouvert = true"`.
      if (_focus.hasFocus) _ouvrir();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _attente?.cancel();
    _champ.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _ouvrir() {
    if (!_portail.isShowing) _portail.show();
  }

  void _fermer() {
    if (_portail.isShowing) _portail.hide();
  }

  /// `@input="ouvert = true"` puis la relecture après 250 ms de calme.
  void _saisie(String valeur) {
    _ouvrir();
    // Le panneau se montre dès le premier caractère (il est masqué champ
    // vide) ; les résultats, eux, attendent le délai.
    setState(() {});
    _attente?.cancel();
    _attente = Timer(AppDurations.debounceRecherche, () {
      if (!mounted) return;
      setState(() {
        _terme = valeur;
        _resultats = _chercher(valeur);
      });
    });
  }

  /// `RechercheGlobale::resultats()` : les pages, puis chaque source dont le
  /// compte peut LIRE le module.
  Future<ResultatsRecherche> _chercher(String brut) async {
    final terme = brut.trim();
    if (!termeSuffisant(terme)) return ResultatsRecherche.vide;
    final droits = ref.read(droitsProvider);
    final role = ref.read(sessionProvider)?.role ?? '';
    final dao = ref.read(rechercheGlobaleDaoProvider);

    final pages = pagesCorrespondantes(
      droits: droits,
      role: role,
      terme: terme,
    );
    final donnees = <FamilleRecherche, List<String>>{};
    for (final famille in FamilleRecherche.values) {
      if (!droits.peutLire(famille.module)) continue;
      final lignes = await dao.chercher(famille, terme);
      if (lignes.isNotEmpty) donnees[famille] = lignes;
    }
    return ResultatsRecherche(pages: pages, donnees: donnees);
  }

  /// La navigation d'un résultat : le composant de la vue est remonté à
  /// chaque page, le terme repart donc vide.
  void _reinitialiser() {
    _attente?.cancel();
    _fermer();
    _focus.unfocus();
    _champ.clear();
    setState(() {
      _terme = '';
      _resultats = null;
    });
  }

  void _dire(String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _ouvrirPage(ResultatPage page) {
    _reinitialiser();
    final route = page.route;
    if (route == null) {
      // L'entrée de menu n'a pas d'écran sur ce poste : le clic le DIT,
      // comme l'entrée de la barre latérale (Article 3.3).
      _dire(LibellesCoquille.ecranNonPorte(page.nom));
      return;
    }
    GoRouter.of(context).go(route);
  }

  void _ouvrirDonnee(FamilleRecherche famille) {
    final terme = _terme.trim();
    _reinitialiser();
    GoRouter.of(context).go(famille.route);
    // ÉCART nommé : la vue passe le terme en `?q=` ; l'écran de ce poste
    // s'ouvre non filtré, et le message le dit.
    _dire(LibellesCoquille.rechercheEcranNonFiltre(terme, famille.titre));
  }

  @override
  Widget build(BuildContext context) {
    final focus = _focus.hasFocus;
    final blanc = AppColors.neutre0;

    final champ = Container(
      key: const Key('recherche-globale'),
      width: MesuresBarreSuperieure.champRecherche,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm, // px-3
        vertical: AppSpacing.xxs, // py-1.5
      ),
      decoration: BoxDecoration(
        color: blanc.withValues(alpha: OpacitesBarreSuperieure.fondRecherche),
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        border: Border.all(
          color: blanc.withValues(
            alpha: focus
                ? OpacitesBarreSuperieure.bordureRechercheFocus
                : OpacitesBarreSuperieure.bordureRecherche,
          ),
        ),
      ),
      child: Row(
        children: [
          IconeTrace(
            trace: TracesCoquille.loupe,
            taille: MesuresBarreSuperieure.iconeRecherche,
            couleur: blanc.withValues(alpha: OpacitesBarreSuperieure.loupe),
          ),
          const SizedBox(width: AppSpacing.xs), // gap-2
          Expanded(
            child: TextField(
              key: const Key('recherche-globale-champ'),
              controller: _champ,
              focusNode: _focus,
              onChanged: _saisie,
              cursorColor: blanc,
              style: TextStyle(
                color: blanc,
                fontFamily: AppTextStyles.police,
                fontSize: Tailles.t12,
                height: Tailles.interligneXsHorsMain,
                letterSpacing: 0,
              ),
              decoration: InputDecoration.collapsed(
                hintText: LibellesCoquille.rechercheInvite,
                hintStyle: TextStyle(
                  color: blanc.withValues(
                    alpha: OpacitesBarreSuperieure.inviteRecherche,
                  ),
                  fontFamily: AppTextStyles.police,
                  fontSize: Tailles.t12,
                  height: Tailles.interligneXsHorsMain,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return TapRegion(
      groupId: _groupe,
      // `@click.outside="ouvert = false"`.
      onTapOutside: (_) => _fermer(),
      child: CompositedTransformTarget(
        link: _lien,
        child: OverlayPortal(
          controller: _portail,
          overlayChildBuilder: (context) => _panneau(context),
          child: Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm), // mr-3
            child: champ,
          ),
        ),
      ),
    );
  }

  /// Le panneau. Rien n'est rendu tant que le champ est vide (la vue le
  /// masque, `style="display:none"`).
  Widget _panneau(BuildContext context) {
    if (_champ.text.trim().isEmpty) return const SizedBox.shrink();
    final largeur =
        MediaQuery.sizeOf(context).width *
        MesuresBarreSuperieure.fractionMaxPanneauRecherche;

    return Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: _lien,
        showWhenUnlinked: false,
        offset: const Offset(
          0,
          MesuresBarreSuperieure.decalagePanneauRecherche,
        ),
        child: TapRegion(
          groupId: _groupe,
          child: ConstrainedBox(
            constraints: BoxConstraints.tightFor(
              width: largeur < MesuresBarreSuperieure.panneauRecherche
                  ? largeur
                  : MesuresBarreSuperieure.panneauRecherche,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.neutre0,
                borderRadius: BorderRadius.circular(AppRadius.roundedXl),
                border: Border.all(color: AppColors.neutre100),
                boxShadow: AppShadows.tailwind2xl,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.roundedXl),
                child: Material(
                  type: MaterialType.transparency,
                  child: _contenu(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _message(String texte) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md, // px-4
      vertical: AppSpacing.mdPlus, // py-5
    ),
    child: Text(
      texte,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: AppTextStyles.police,
        fontSize: Tailles.t12,
        height: AppLayout.interligneContenu,
        color: AppColors.neutre400,
      ),
    ),
  );

  Widget _contenu() {
    // La saisie courante, pas encore relue : la vue montre l'état du terme
    // RELU ; tant qu'il n'y en a pas, « trop court » est l'état vrai.
    if (!termeSuffisant(_terme)) {
      return _message(LibellesCoquille.rechercheTropCourt);
    }
    return FutureBuilder<ResultatsRecherche>(
      future: _resultats,
      builder: (context, instantane) {
        if (instantane.hasError) {
          return _message(LibellesCoquille.rechercheLectureImpossible);
        }
        final resultats = instantane.data;
        // Pendant la lecture, rien n'est affirmé (ni « aucun », ni liste).
        if (resultats == null) return const SizedBox.shrink();
        if (resultats.estVide) return _message(LibellesCoquille.rechercheAucun);

        return ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: MesuresBarreSuperieure.hauteurMaxResultats,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (resultats.pages.isNotEmpty) ...[
                  _TitreFamille(LibellesCoquille.rechercheFamillePages),
                  for (final page in resultats.pages)
                    _LigneResultat(
                      key: Key('recherche-page-${page.nom}'),
                      texte: page.nom,
                      page: true,
                      onTap: () => _ouvrirPage(page),
                    ),
                ],
                for (final entree in resultats.donnees.entries) ...[
                  _TitreFamille(entree.key.titre),
                  for (final libelle in entree.value)
                    _LigneResultat(
                      texte: libelle,
                      page: false,
                      onTap: () => _ouvrirDonnee(entree.key),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// `px-4 pt-2 pb-1 text-[10px] font-bold tracking-wider text-slate-400
/// uppercase`.
class _TitreFamille extends StatelessWidget {
  const _TitreFamille(this.titre);

  final String titre;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: AppSpacing.xs,
        bottom: AppSpacing.unit,
      ),
      child: Text(
        titre.toUpperCase(),
        style: TextStyle(
          fontFamily: AppTextStyles.police,
          fontSize: Tailles.t10,
          fontWeight: FontWeight.bold,
          letterSpacing: AppTextStyles.suiviPlusLarge * Tailles.t10,
          height: AppLayout.interligneContenu,
          color: AppColors.neutre400,
        ),
      ),
    );
  }
}

/// Un résultat : « Pages » (`flex items-center gap-2.5 px-4 py-2 text-xs
/// text-slate-700`, flèche 13 px, nom `font-semibold`) ou donnée (`block px-4
/// py-2 text-xs text-slate-700`). `hover:bg-slate-50`.
class _LigneResultat extends StatelessWidget {
  const _LigneResultat({
    required this.texte,
    required this.page,
    required this.onTap,
    super.key,
  });

  final String texte;
  final bool page;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: AppTextStyles.police,
      fontSize: Tailles.t12,
      height: Tailles.interligneXsHorsMain,
      letterSpacing: 0,
      fontWeight: page ? FontWeight.w600 : FontWeight.normal,
      color: AppColors.neutre700,
    );
    return InkWell(
      onTap: onTap,
      hoverColor: AppColors.neutre50,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: page
            ? Row(
                children: [
                  const IconeTrace(
                    trace: TracesCoquille.flechePage,
                    taille: MesuresBarreSuperieure.iconePageRecherche,
                    couleur: AppColors.neutre400,
                  ),
                  const SizedBox(width: AppSpacing.xsPlus), // gap-2.5
                  Expanded(child: Text(texte, style: style)),
                ],
              )
            : Text(texte, style: style),
      ),
    );
  }
}
