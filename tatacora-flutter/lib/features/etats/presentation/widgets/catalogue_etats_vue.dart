import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../restaurant/presentation/widgets/coquille_restaurant.dart';
import '../../domain/entities/etat_catalogue.dart';
import '../ecran_etats.dart';
import '../providers_etats.dart';
import 'textes_etats.dart';

/// La colonne de catalogue — `pwa/etats/studio.blade.php` l.62-115.
///
/// Trois zones, dans l'ordre de la vue : la recherche et les filtres de module
/// en tête (hors défilement), la liste groupée par module au milieu, le
/// compteur en pied (hors défilement lui aussi).
///
/// ## Le catalogue ne s'invente pas
///
/// Il vient du registre fermé de M14, filtré par les droits réels du rôle sur
/// le module SOURCE de chaque état (la vue fait de même par
/// `CatalogueEtatsService::pourUtilisateur()`). Les pastilles
/// de module sont les codes RÉELLEMENT présents, triés comme `sort($modules)`
/// (l.76) ; les groupes suivent l'ordre de la réponse (`groupBy`, l.87), et
/// leur en-tête est le code seul (l.89). Le pied dit combien d'états le
/// serveur a rendus.
class CatalogueEtatsVue extends ConsumerStatefulWidget {
  const CatalogueEtatsVue({super.key});

  @override
  ConsumerState<CatalogueEtatsVue> createState() => _CatalogueEtatsVueState();
}

class _CatalogueEtatsVueState extends ConsumerState<CatalogueEtatsVue> {
  final FocusNode _focusRecherche = FocusNode(debugLabel: 'recherche-etats');
  final TextEditingController _recherche = TextEditingController();

  @override
  void dispose() {
    _focusRecherche.dispose();
    _recherche.dispose();
    super.dispose();
  }

  /// `/` place le curseur dans la recherche.
  ///
  /// L'invite de la vue (`pwa.etats.recherche`, studio.blade.php l.67) annonce
  /// « (touche /) » : une invite qui annonce une touche que rien n'écoute est
  /// un compteur écrit en dur (Article 6), donc le raccourci est tenu ici.
  /// Garde : « sauf si l'on est déjà en train de saisir quelque part, où la
  /// touche doit rester une barre oblique » — sans elle on ne pourrait plus
  /// taper `/` dans le champ.
  KeyEventResult _touche(FocusNode node, KeyEvent evenement) {
    if (evenement is! KeyDownEvent) return KeyEventResult.ignored;
    if (evenement.logicalKey != LogicalKeyboardKey.slash) {
      return KeyEventResult.ignored;
    }
    if (_focusRecherche.hasFocus) return KeyEventResult.ignored;

    _focusRecherche.requestFocus();
    _recherche.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _recherche.text.length,
    );
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final resultat = ref.watch(catalogueFiltreProvider);

    return Focus(
      // `autofocus` : sans lui, ce noeud n'est dans la chaine de focus de
      // personne et `onKeyEvent` n'est JAMAIS appele — le raccourci annonce
      // par l'invite du champ n'existerait pas, alors que le code en porte la
      // trace. Un cas monte l'ecran et enfonce reellement la touche.
      autofocus: true,
      onKeyEvent: _touche,
      child: DecoratedBox(
        // `border-r border-slate-200 bg-white` (l.74).
        decoration: bordureCatalogueEtats,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _EnTeteCatalogue(
              controleur: _recherche,
              focus: _focusRecherche,
              onRecherche: (v) =>
                  ref.read(rechercheEtatsProvider.notifier).definir(v),
            ),
            Flexible(child: _Liste(resultat: resultat)),
            _Compteur(resultat: resultat),
          ],
        ),
      ),
    );
  }
}

/// La recherche et les puces de module — l.75-83.
class _EnTeteCatalogue extends ConsumerWidget {
  const _EnTeteCatalogue({
    required this.controleur,
    required this.focus,
    required this.onRecherche,
  });

  final TextEditingController controleur;
  final FocusNode focus;
  final ValueChanged<String> onRecherche;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      // `px-3.5 pt-3.5 pb-2.5 border-b border-slate-100` (l.75).
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.smPlus,
        AppSpacing.smPlus,
        AppSpacing.smPlus,
        AppSpacing.xsPlus,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Ardoise.c100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('etats-recherche'),
            controller: controleur,
            focusNode: focus,
            onChanged: onRecherche,
            style: TextesRestaurant.corps,
            decoration: InputDecoration(
              isDense: true,
              // `pwa.etats.recherche` (studio.blade.php l.67) : DEUX espaces
              // avant la parenthèse, comme la clé de langue.
              hintText: 'Rechercher un état…  (touche /)',
              hintStyle: TextesRestaurant.corps.copyWith(color: Ardoise.c400),
              // `pl-9 pr-3 py-2` (l.81).
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              prefixIcon: const Icon(
                Icons.search,
                size: AppLayout.iconeChamp,
                color: Ardoise.c400,
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: AppLayout.prefixeRechercheEtats,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.roundedLg),
                borderSide: const BorderSide(color: Ardoise.c300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.roundedLg),
                borderSide: const BorderSide(color: Ardoise.c300),
              ),
              // `focus:border-[var(--gold)]` (l.81).
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.roundedLg),
                borderSide: const BorderSide(color: AppColors.gold),
              ),
            ),
          ),
          // `mb-2.5` (l.77).
          const SizedBox(height: AppSpacing.xsPlus),
          const _PucesModule(),
        ],
      ),
    );
  }
}

/// Les puces de filtre — `rendreFiltresModule()`, `m14-etats-studio.js`
/// l.44-59. « Tous » d'abord, puis un code par module **réellement présent**
/// au catalogue : un filtre qui ne filtrerait rien serait un bouton inerte.
class _PucesModule extends ConsumerWidget {
  const _PucesModule();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etats = ref.watch(catalogueEtatsProvider).value ?? const [];
    if (etats.isEmpty) return const SizedBox.shrink();

    final actif = ref.watch(moduleFiltreEtatsProvider);
    final codes = modulesDuCatalogue(etats);

    return Wrap(
      // `flex gap-1.5 flex-wrap` (l.83).
      spacing: AppSpacing.xxs,
      runSpacing: AppSpacing.xxs,
      children: [
        _Puce(
          cle: const Key('etats-module-tous'),
          libelle: 'Tous',
          actif: actif == null,
          onChoix: () =>
              ref.read(moduleFiltreEtatsProvider.notifier).definir(null),
        ),
        for (final code in codes)
          _Puce(
            cle: Key('etats-module-$code'),
            libelle: code,
            actif: actif == code,
            onChoix: () =>
                ref.read(moduleFiltreEtatsProvider.notifier).definir(code),
          ),
      ],
    );
  }
}

class _Puce extends StatelessWidget {
  const _Puce({
    required Key cle,
    required this.libelle,
    required this.actif,
    required this.onChoix,
  }) : super(key: cle);

  final String libelle;
  final bool actif;
  final VoidCallback onChoix;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onChoix,
      child: Container(
        // `text-[11px] px-2 py-1 rounded-lg border` (JS l.49-55).
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.unit,
        ),
        decoration: BoxDecoration(
          color: actif ? AppColors.navy : AppColors.neutre0,
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
          border: Border.all(color: actif ? AppColors.navy : Ardoise.c200),
        ),
        child: Text(
          libelle,
          style: TextesEtats.puceModule.copyWith(
            color: actif ? AppColors.neutre0 : Ardoise.c500,
          ),
        ),
      ),
    );
  }
}

/// La liste groupée par module — `rendreCatalogue()`, JS l.61-104.
class _Liste extends ConsumerWidget {
  const _Liste({required this.resultat});

  final AsyncValue<List<EtatCatalogue>> resultat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return resultat.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => NoteRestaurant(
        cle: const Key('etats-catalogue-erreur'),
        texte: '$e',
        icone: Icons.error_outline,
      ),
      data: (etats) => etats.isEmpty
          ? const Padding(
              // « Aucun état ne correspond. » — JS l.98, au mot.
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacingLarge.p12,
              ),
              child: Text(
                'Aucun état ne correspond.',
                key: Key('etats-catalogue-vide'),
                textAlign: TextAlign.center,
                style: TextesRestaurant.corps,
              ),
            )
          : _Groupes(groupes: grouperParModule(etats)),
    );
  }
}

class _Groupes extends ConsumerStatefulWidget {
  const _Groupes({required this.groupes});

  final List<GroupeCatalogue> groupes;

  @override
  ConsumerState<_Groupes> createState() => _GroupesState();
}

class _GroupesState extends ConsumerState<_Groupes> {
  final ScrollController _defilement = ScrollController();

  /// Vrai quand la liste dépasse sa hauteur : la barre de défilement existe
  /// alors, et prend sa place (voir [AppLayout.gouttiereDefilement]).
  bool _deborde = false;

  @override
  void dispose() {
    _defilement.dispose();
    super.dispose();
  }

  bool _onMetriques(ScrollMetricsNotification n) {
    final deborde = n.metrics.maxScrollExtent > 0;
    if (deborde != _deborde) {
      // Hors de la phase de mise en page : la notification part après elle,
      // mais un `setState` direct y serait refusé si cela changeait un jour.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _deborde = deborde);
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(etatSelectionneProvider);

    return NotificationListener<ScrollMetricsNotification>(
      onNotification: _onMetriques,
      child: ScrollbarTheme(
        // `::-webkit-scrollbar` (app.css l.79-81) : 8 px, pouce `--neutre-200`
        // arrondi à 8 px, piste transparente.
        data: ScrollbarThemeData(
          thickness: const WidgetStatePropertyAll(
            AppLayout.gouttiereDefilement,
          ),
          radius: const Radius.circular(AppRadius.roundedLg),
          thumbColor: const WidgetStatePropertyAll(AppColors.neutre200),
          thumbVisibility: const WidgetStatePropertyAll(true),
        ),
        child: Scrollbar(
          controller: _defilement,
          child: Padding(
            padding: EdgeInsets.only(
              right: _deborde ? AppLayout.gouttiereDefilement : 0,
            ),
            child: ListView(
              controller: _defilement,
              // `flex-1 overflow-y-auto` (studio.blade.php l.83).
              padding: EdgeInsets.zero,
              children: [
                for (final g in widget.groupes) ...[
                  Padding(
                    // `px-3.5 pt-3 pb-1` (l.89).
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.smPlus,
                      AppSpacing.sm,
                      AppSpacing.smPlus,
                      AppSpacing.unit,
                    ),
                    child: Text(
                      g.enTete,
                      key: Key('etats-groupe-${g.module}'),
                      style: TextesEtats.enTeteGroupe,
                    ),
                  ),
                  for (final e in g.etats)
                    _EntreeEtat(etat: e, selectionne: selection == e.code),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Une entrée du catalogue — JS l.84-95.
class _EntreeEtat extends ConsumerWidget {
  const _EntreeEtat({required this.etat, required this.selectionne});

  final EtatCatalogue etat;
  final bool selectionne;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      key: Key('etats-entree-${etat.code}'),
      onTap: () =>
          ref.read(etatSelectionneProvider.notifier).definir(etat.code),
      child: Container(
        width: double.infinity,
        // `w-full text-left px-3.5 py-2.5 border-l-2 border-transparent`
        // (JS l.86). Le liseré gauche existe même transparent : sans lui,
        // l'entrée sélectionnée se décalerait de deux pixels.
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.smPlus,
          vertical: AppSpacing.xsPlus,
        ),
        decoration: BoxDecoration(
          color: selectionne ? AppColors.navy : null,
          border: Border(
            left: BorderSide(
              width: AppLayout.lisereEntreeEtat,
              color: selectionne ? AppColors.navy : Colors.transparent,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    etat.libelle,
                    style: selectionne
                        ? TextesEtats.libelleEtatActif
                        : TextesEtats.libelleEtat,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                // `shrink-0 mt-0.5` (studio.blade.php l.99).
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.demi),
                  child: _BadgeModule(
                    module: etat.module,
                    surFondNavy: selectionne,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// La pastille du module source — `studio.blade.php` l.99.
class _BadgeModule extends StatelessWidget {
  const _BadgeModule({required this.module, required this.surFondNavy});

  final String module;
  final bool surFondNavy;

  @override
  Widget build(BuildContext context) {
    return Container(
      // `px-1.5 py-0.5 rounded bg-slate-100 text-slate-500` ; sur une entrée
      // sélectionnée, `rgba(255,255,255,.15)` et `#fff` (l.25 du HTML).
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxs,
        vertical: AppSpacing.demi,
      ),
      decoration: BoxDecoration(
        color: surFondNavy
            ? AppColors.neutre0.withValues(alpha: AppColors.opaciteBadgeActif)
            : Ardoise.c100,
        borderRadius: BorderRadius.circular(AppRadius.rounded),
      ),
      child: Text(
        module,
        style: TextesEtats.badgeModule.copyWith(
          color: surFondNavy ? AppColors.neutre0 : Ardoise.c500,
        ),
      ),
    );
  }
}

/// Le pied de la colonne — `studio.blade.php` l.112-114, `pwa.etats.compteur` :
/// `N état(s) · droits portés par le module source`.
///
/// Tant que le catalogue n'est pas reçu, le nombre est « — » et non « 0 » :
/// un « 0 état(s) » affirmerait un catalogue vide que personne n'a constaté
/// (Article 7).
class _Compteur extends StatelessWidget {
  const _Compteur({required this.resultat});

  final AsyncValue<List<EtatCatalogue>> resultat;

  @override
  Widget build(BuildContext context) {
    final nombre = resultat.value?.length;

    return Container(
      width: double.infinity,
      // `px-3.5 py-2 border-t border-slate-100` (l.87).
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.smPlus,
        vertical: AppSpacing.xs,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Ardoise.c100)),
      ),
      child: Text(
        key: const Key('etats-compteur'),
        nombre == null
            // Article 7 : la donnée n'existe pas encore, elle ne vaut pas zéro.
            ? '— état(s) · droits portés par le module source'
            : '$nombre état(s) · droits portés par le module source',
        style: TextesRestaurant.mention,
      ),
    );
  }
}
