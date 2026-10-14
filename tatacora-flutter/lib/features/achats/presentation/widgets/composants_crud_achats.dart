// Vue Blade maîtresse (PA-183) : pwa/achats/achats.blade.php
import 'package:flutter/material.dart';

import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../restaurant/presentation/widgets/tableau_restaurant.dart';

/// Les briques du tableau CRUD de `pwa/achats/achats.blade.php`, communes à ses
/// deux onglets (« Fournisseurs » et « Commandes d'achat »).
///
/// La vue répète deux fois le même gabarit — barre d'outils, barre de
/// sélection, tableau à en-tête navy, état vide, pied de pagination — et ne
/// change que les colonnes. Les recopier dans chaque onglet les ferait diverger
/// au premier ajustement ; elles vivent ici, une seule fois.
///
/// ## Ce que ce client ne sait PAS faire de ces gabarits
///
/// Aucune des listes n'a de source sur ce poste (`AchatsApi`, 14/09/2026) :
/// quand elle n'en rend pas, le corps du tableau dit POURQUOI
/// ([CorpsIndisponibleAchats]) au lieu de « Aucun résultat », qui affirmerait
/// qu'il n'y a rien à lister — un registre vide et un registre absent ne se
/// disent pas pareil.

/// Lignes par page — `Achats::PAR_PAGE` de la vue (`Achats.php` l.143). Relue
/// dans la classe PHP par `conformite_achats_test.dart` : une constante
/// recopiée ici ne vérifierait qu'elle-même.
const int parPageAchats = 25;

/// `text-sm` à l'intérieur de `<main>` (13,5 px), interligne 1,5 de la vue.
const TextStyle _styleChamp = TextStyle(
  fontFamily: AppTextStyles.police,
  fontSize: TaillesContenu.sm,
  height: TaillesContenu.interligneSm,
  color: AppColors.anthracite,
);

/// `text-xs font-semibold` d'un bouton de la barre d'outils.
TextStyle _styleBouton(Color couleur) => TextStyle(
  fontFamily: AppTextStyles.police,
  fontSize: TaillesContenu.xs,
  fontWeight: FontWeight.w600,
  height: TaillesContenu.interligneXs,
  color: couleur,
);

/// Le gabarit du tableau de la vue : `<thead class="bg-[var(--navy)]">`, des
/// en-têtes `px-4 py-2.5 text-[11px] font-semibold uppercase tracking-wide
/// text-white/90`, des cellules `px-4 py-2.5` et `border-t border-slate-100`
/// (l.199-215). Même gabarit que la dépense courante — troisième de la
/// famille, ni la carte (`slate-50`) ni le moteur CRUD de l'ancien maître
/// (`px-4 py-3`, bordure en bas).
const GabaritTableau gabaritCrudAchats = GabaritTableau(
  enteteFond: AppColors.navy,
  entete: TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t11,
    fontWeight: FontWeight.w600,
    height: AppLayout.interligneContenu,
    letterSpacing: TaillesContenu.t11 * AppTextStyles.suiviLarge,
    color: AppColors.blanc90,
  ),
  cellule: EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
    vertical: AppSpacing.xsPlus,
  ),
  enBas: false,
);

/// La barre d'outils : `flex flex-col lg:flex-row lg:items-center gap-3 mb-4`
/// (l.89) — recherche extensible, liste de filtre, puis le groupe d'actions
/// « Actualiser », « Exporter » et, pour qui peut écrire, le bouton d'ajout.
///
/// Le bouton d'ajout n'est PAS rendu pour un rôle en lecture (l.145) : le
/// retirer évite de proposer un geste qui sera refusé. Il ne protège rien — la
/// garde est ailleurs.
class BarreOutilsCrudAchats extends StatelessWidget {
  const BarreOutilsCrudAchats({
    required Key cle,
    required this.prefixeCle,
    required this.placeholder,
    required this.controleurRecherche,
    required this.onRecherche,
    required this.filtre,
    required this.onActualiser,
    required this.onExporter,
    required this.libelleAjout,
    required this.onAjout,
  }) : super(key: cle);

  /// `fournisseurs` ou `commandes` : les clés des contrôles en dérivent.
  final String prefixeCle;
  final String placeholder;
  final TextEditingController controleurRecherche;
  final ValueChanged<String> onRecherche;
  final Widget filtre;
  final VoidCallback onActualiser;
  final VoidCallback onExporter;

  /// « Ajouter fournisseur » / « Ajouter commande d'achat ». Le libellé suit
  /// l'onglet, comme au maître (`rendreMiseEnPageCrud()` rappelé au changement
  /// d'onglet).
  final String libelleAjout;

  /// `null` : le rôle ne peut pas écrire, le bouton n'est pas rendu.
  final VoidCallback? onAjout;

  @override
  Widget build(BuildContext context) {
    final groupe = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BoutonOutil(
          cle: Key('achats-$prefixeCle-actualiser'),
          infobulle: 'Actualiser',
          onTap: onActualiser,
          remplissage: const EdgeInsets.all(AppSpacing.xsPlus), // p-2.5
          enfant: const Icon(
            Icons.refresh,
            size: AppLayout.iconeChamp,
            color: Ardoise.c500,
          ),
        ),
        const SizedBox(width: AppSpacing.xs), // gap-2
        _BoutonOutil(
          cle: Key('achats-$prefixeCle-exporter'),
          onTap: onExporter,
          remplissage: const EdgeInsets.symmetric(
            horizontal: AppSpacing.smPlus, // px-3.5
            vertical: AppSpacing.xsPlus, // py-2.5
          ),
          enfant: _IconeEtLibelle(
            icone: Icons.file_download_outlined,
            libelle: 'Exporter',
            style: _styleBouton(Ardoise.c600),
          ),
        ),
        if (onAjout != null) ...[
          const SizedBox(width: AppSpacing.xs),
          _BoutonOutil(
            cle: Key('achats-$prefixeCle-ajouter'),
            onTap: onAjout!,
            plein: true,
            remplissage: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, // px-4
              vertical: AppSpacing.xsPlus,
            ),
            enfant: _IconeEtLibelle(
              icone: Icons.add,
              libelle: libelleAjout,
              style: _styleBouton(AppColors.neutre0),
            ),
          ),
        ],
      ],
    );

    final recherche = _ChampRecherche(
      cle: Key('achats-$prefixeCle-recherche'),
      placeholder: placeholder,
      controleur: controleurRecherche,
      onChange: onRecherche,
    );

    // `lg:flex-row` : la décision se prend sur la largeur de l'ÉCRAN
    // (Article 5), jamais sur celle du contenu.
    final enRangee = MediaQuery.sizeOf(context).width >= AppBreakpoints.lg;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md), // mb-4
      child: enRangee
          ? Row(
              children: [
                Expanded(child: recherche),
                const SizedBox(width: AppSpacing.sm), // gap-3
                filtre,
                const SizedBox(width: AppSpacing.sm),
                groupe,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                recherche,
                const SizedBox(height: AppSpacing.sm),
                Align(alignment: Alignment.centerLeft, child: filtre),
                const SizedBox(height: AppSpacing.sm),
                Align(alignment: Alignment.centerLeft, child: groupe),
              ],
            ),
    );
  }
}

/// `w-full border border-slate-200 rounded-lg pl-10 pr-4 py-2.5 text-sm
/// bg-white`, la loupe en `absolute left-3.5` (l.90-94).
class _ChampRecherche extends StatelessWidget {
  const _ChampRecherche({
    required Key cle,
    required this.placeholder,
    required this.controleur,
    required this.onChange,
  }) : super(key: cle);

  final String placeholder;
  final TextEditingController controleur;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) {
    final bordure = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      borderSide: const BorderSide(color: Ardoise.c200),
    );

    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        TextField(
          controller: controleur,
          style: _styleChamp,
          onChanged: onChange,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.neutre0,
            hintText: placeholder,
            hintStyle: _styleChamp.copyWith(color: AppColors.neutre400),
            contentPadding: const EdgeInsets.only(
              left: AppSpacing.xlPlus, // pl-10
              right: AppSpacing.md, // pr-4
              // `py-2.5` + le filet de 1 px que la vue compte dans la boîte.
              top: AppLayout.champBordeVertical,
              bottom: AppLayout.champBordeVertical,
            ),
            border: bordure,
            enabledBorder: bordure,
            focusedBorder: bordure.copyWith(
              borderSide: const BorderSide(color: AppColors.gold),
            ),
          ),
        ),
        const Positioned(
          left: AppSpacing.smPlus, // left-3.5
          child: IgnorePointer(
            child: Icon(
              Icons.search,
              size: AppLayout.iconeChamp,
              color: AppColors.neutre400,
            ),
          ),
        ),
      ],
    );
  }
}

/// `border border-slate-200 rounded-lg px-3 py-2.5 text-sm bg-white` (l.98).
class FiltreListeAchats<T> extends StatelessWidget {
  const FiltreListeAchats({
    required Key cle,
    required this.valeur,
    required this.items,
    required this.onChanged,
  }) : super(key: cle);

  final T valeur;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        border: Border.all(color: Ardoise.c200),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, // px-3
          vertical: AppSpacing.xsPlus, // py-2.5
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: valeur,
            isDense: true,
            itemHeight: null,
            iconSize: AppLayout.iconeChamp,
            style: _styleChamp,
            items: items,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}

class _BoutonOutil extends StatelessWidget {
  const _BoutonOutil({
    required Key cle,
    required this.onTap,
    required this.remplissage,
    required this.enfant,
    this.infobulle,
    this.plein = false,
  }) : super(key: cle);

  final VoidCallback onTap;
  final EdgeInsets remplissage;
  final Widget enfant;
  final String? infobulle;

  /// `bg-[var(--navy)] text-white` ; sinon `border border-slate-200 bg-white`.
  final bool plein;

  @override
  Widget build(BuildContext context) {
    final bouton = Material(
      color: plein ? AppColors.navy : AppColors.neutre0,
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        child: Container(
          // Le filet de 1 px des boutons bordés est COMPTÉ dans la boîte : le
          // bouton plein, lui, n'en a pas.
          padding: remplissage,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            border: plein ? null : Border.all(color: Ardoise.c200),
          ),
          child: enfant,
        ),
      ),
    );
    return infobulle == null
        ? bouton
        : Tooltip(message: infobulle!, child: bouton);
  }
}

class _IconeEtLibelle extends StatelessWidget {
  const _IconeEtLibelle({
    required this.icone,
    required this.libelle,
    required this.style,
  });

  final IconData icone;
  final String libelle;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icone, size: AppLayout.iconeChamp, color: style.color),
        const SizedBox(width: AppSpacing.xs), // gap-2
        Text(libelle, style: style),
      ],
    );
  }
}

/// La barre de sélection groupée (l.179-192) : `flex items-center gap-3
/// bg-[var(--navy)] text-white rounded-lg px-4 py-2.5 mb-3 text-xs`.
///
/// « Supprimer » n'y est rendu que pour qui peut archiver, et sur l'onglet
/// des fournisseurs : une commande d'achat ne s'archive pas.
class BarreSelectionAchats extends StatelessWidget {
  const BarreSelectionAchats({
    super.key,
    required this.nombre,
    required this.onSupprimer,
    required this.onExporter,
    required this.onEffacer,
  });

  final int nombre;

  /// `null` : pas de « Supprimer » (onglet des commandes, ou droit absent).
  final VoidCallback? onSupprimer;
  final VoidCallback onExporter;
  final VoidCallback onEffacer;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontFamily: AppTextStyles.police,
      fontSize: TaillesContenu.xs,
      height: TaillesContenu.interligneXs,
      color: AppColors.neutre0,
    );
    final souligne = base.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: AppColors.neutre0.withValues(alpha: 0.4),
    );

    Widget lien(Key cle, String libelle, VoidCallback onTap) => InkWell(
      key: cle,
      onTap: onTap,
      child: Text(libelle, style: souligne),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm), // mb-3
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xsPlus,
      ),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      ),
      child: Row(
        children: [
          // `:nombre sélectionné(s)` — le nombre en <strong>.
          Text.rich(
            TextSpan(
              style: base,
              children: [
                TextSpan(
                  text: '$nombre',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const TextSpan(text: ' sélectionné(s)'),
              ],
            ),
            key: const Key('achats-selection-compte'),
          ),
          const Spacer(),
          if (onSupprimer != null) ...[
            lien(
              const Key('achats-selection-supprimer'),
              'Supprimer',
              onSupprimer!,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          lien(const Key('achats-selection-exporter'), 'Exporter', onExporter),
          const SizedBox(width: AppSpacing.sm),
          InkWell(
            key: const Key('achats-selection-effacer'),
            onTap: onEffacer,
            child: Text(
              '✕',
              semanticsLabel: 'Annuler',
              style: base.copyWith(
                color: AppColors.neutre0.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// La case de l'en-tête et des lignes : `w-4 h-4 rounded`.
class CaseSelectionAchats extends StatelessWidget {
  const CaseSelectionAchats({
    required Key cle,
    required this.valeur,
    required this.etiquette,
    required this.onChanged,
    this.surMarine = false,
  }) : super(key: cle);

  final bool valeur;

  /// L'`aria-label` de la vue : « Tout sélectionner » / « Sélectionner cette
  /// ligne ».
  final String etiquette;
  final ValueChanged<bool> onChanged;

  /// La case de l'en-tête repose sur le fond navy : sa bordure doit rester
  /// visible (la vue la laisse au navigateur, qui la dessine en gris moyen).
  final bool surMarine;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppLayout.casePaie,
      height: AppLayout.casePaie,
      child: Checkbox(
        value: valeur,
        semanticLabel: etiquette,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        side: surMarine ? const BorderSide(color: AppColors.neutre0) : null,
        onChanged: (v) => onChanged(v ?? false),
      ),
    );
  }
}

/// L'état vide de la vue (l.276-280) : `flex flex-col items-center
/// justify-center py-16 text-center` — loupe de 40 px, « Aucun résultat » en
/// `text-sm font-semibold`, puis la phrase en `text-xs text-slate-400 mt-1`.
class EtatVideTableauAchats extends StatelessWidget {
  const EtatVideTableauAchats({super.key, this.titre = 'Aucun résultat'});

  /// La première ligne : « Aucun résultat » par défaut, et la phrase propre de
  /// l'onglet « Dettes fournisseurs » (`pwa.appro.dettes_vide`) — la seconde
  /// ligne est la même (`pwa.achats.vide_detail`).
  final String titre;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacingLarge.p16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.sm), // mb-3
              child: Icon(
                Icons.search,
                size: AppLayout.iconeEtatVide,
                color: Ardoise.c300,
              ),
            ),
            Text(
              titre,
              style: TextStyle(
                fontFamily: AppTextStyles.police,
                fontSize: TaillesContenu.sm,
                fontWeight: FontWeight.w600,
                height: AppLayout.interligneContenu,
                color: Ardoise.c500,
              ),
            ),
            const SizedBox(height: AppSpacing.unit), // mt-1
            Text(
              'Essayez de modifier votre recherche ou vos filtres.',
              style: TextStyle(
                fontFamily: AppTextStyles.police,
                fontSize: TaillesContenu.xs,
                height: TaillesContenu.interligneXs,
                color: Ardoise.c400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ce que le corps du tableau dit quand la liste n'a AUCUNE source : le motif
/// de `core/donnees_absentes.dart`, à la place de « Aucun résultat ».
///
/// ÉCART DÉLIBÉRÉ — `pwa/achats/achats.blade.php` l.276-280.
/// La vue : « Aucun résultat / Essayez de modifier votre recherche ou vos
/// filtres », quand la requête ne retient rien.
/// Ici : la phrase d'absence de donnée, quand le poste n'a pas la liste.
/// Raison (09/10/2026, relue contre `AchatsApi`) : `fournisseurs()` et
/// `commandes()` rendent `AchatsRefuse` sans rien lire — ce poste n'a aucune
/// table de M7 (décision du Product Owner du 14/09/2026, zéro réseau). « Aucun
/// résultat » dirait qu'il n'y a aucun fournisseur ; « essayez de modifier vos
/// filtres » enverrait chercher un réglage qui n'y est pour rien.
class CorpsIndisponibleAchats extends StatelessWidget {
  const CorpsIndisponibleAchats({required Key cle, required this.motif})
    : super(key: cle);

  final String motif;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacingLarge.p16,
      ),
      child: Center(
        child: Text(
          motif,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppTextStyles.police,
            fontSize: TaillesContenu.sm,
            height: AppLayout.interligneContenu,
            color: Ardoise.c500,
          ),
        ),
      ),
    );
  }
}

/// Le pied du cadre (l.283-290) : « Affichage de 1-25 sur 40 » à gauche, les
/// liens de pagination à droite — `px-4 py-3 border-t border-slate-100`.
///
/// [total] `null` : la liste n'a pas de source, le décompte rend des tirets,
/// jamais « 0-0 sur 0 » (qui affirmerait un registre vide).
class PiedTableauAchats extends StatelessWidget {
  const PiedTableauAchats({
    super.key,
    required this.debut,
    required this.fin,
    required this.total,
    required this.page,
    required this.derniere,
    required this.onPage,
  });

  final int? debut;
  final int? fin;
  final int? total;
  final int page;
  final int derniere;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontFamily: AppTextStyles.police,
      fontSize: TaillesContenu.xs,
      height: TaillesContenu.interligneXs,
      color: Ardoise.c500,
    );
    final fort = base.copyWith(fontWeight: FontWeight.bold);

    Widget nombre(int? v) => Text(v == null ? '—' : '$v', style: fort);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Ardoise.c100)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // « Affichage de <strong>1</strong>-<strong>25</strong> sur
          // <strong>40</strong> » : un nœud de texte par morceau, comme la vue.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Affichage de ', style: base),
              nombre(debut),
              Text('-', style: base),
              nombre(fin),
              Text(' sur ', style: base),
              nombre(total),
            ],
          ),
          // `->links()` : rien quand il n'y a qu'une page (`hasPages()`).
          if (derniere > 1)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LienPage(
                  cle: const Key('achats-page-precedente'),
                  libelle: '← Précédent',
                  style: base,
                  onTap: page > 1 ? () => onPage(page - 1) : null,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Page $page / $derniere',
                  key: const Key('achats-page-courante'),
                  style: base,
                ),
                const SizedBox(width: AppSpacing.sm),
                _LienPage(
                  cle: const Key('achats-page-suivante'),
                  libelle: 'Suivant →',
                  style: base,
                  onTap: page < derniere ? () => onPage(page + 1) : null,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Un lien de pagination. À la première ou à la dernière page, le lien est un
/// SIMPLE TEXTE grisé, pas un bouton : Laravel rend un `<span>` désactivé, et
/// un bouton qui ne fait rien empêcherait de savoir si la fonction manque.
class _LienPage extends StatelessWidget {
  const _LienPage({
    required this.cle,
    required this.libelle,
    required this.style,
    required this.onTap,
  });

  final Key cle;
  final String libelle;
  final TextStyle style;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) {
      return Text(
        libelle,
        key: cle,
        style: style.copyWith(color: Ardoise.c400),
      );
    }
    return InkWell(
      key: cle,
      onTap: onTap,
      child: Text(libelle, style: style.copyWith(color: AppColors.navy)),
    );
  }
}

/// Le bouton de ligne : `text-[12px] px-2.5 py-1 rounded-lg border
/// border-slate-200 hover:bg-slate-100` (l.246-247), rouge pour « Supprimer »
/// (`border-red-200 text-[var(--erreur)]`).
class BoutonLigneAchats extends StatelessWidget {
  const BoutonLigneAchats({
    required Key cle,
    required this.libelle,
    required this.onTap,
    this.danger = false,
  }) : super(key: cle);

  final String libelle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.neutre0,
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xsPlus, // px-2.5
            vertical: AppSpacing.unit, // py-1
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            border: Border.all(
              color: danger ? PaletteMaitre.rouge200 : Ardoise.c200,
            ),
          ),
          child: Text(
            libelle,
            style: TextStyle(
              fontFamily: AppTextStyles.police,
              fontSize: TaillesContenu.t12,
              height: AppLayout.interligneContenu,
              color: danger ? AppColors.erreur : AppColors.anthracite,
            ),
          ),
        ),
      ),
    );
  }
}

/// Le décompte du pied pour la page [numeroPage] : « Affichage de 26-50 sur
/// 60 ». `null` partout quand la liste n'a pas de source — des tirets, jamais
/// « 0-0 sur 0 », qui affirmerait un registre vide.
({int? debut, int? fin, int? total}) decompteAchats({
  required bool disponible,
  required int total,
  required int numeroPage,
  required int affiches,
}) {
  if (!disponible) return (debut: null, fin: null, total: null);
  if (total == 0) return (debut: 0, fin: 0, total: 0);
  final debut = (numeroPage - 1) * parPageAchats + 1;
  return (debut: debut, fin: debut + affiches - 1, total: total);
}

/// Le cadre `bg-white rounded-xl border border-slate-200 overflow-hidden`
/// (l.196 et l.296) : le tableau à en-tête navy, son corps vide, son pied.
class CadreTableauAchats extends StatelessWidget {
  const CadreTableauAchats({
    super.key,
    required this.colonnes,
    required this.lignes,
    required this.vide,
    required this.pied,
  });

  /// La première colonne est celle de la case : sa largeur est fixe (48 px).
  final List<ColonneRestaurant> colonnes;
  final List<List<Widget>> lignes;

  /// Ce qui occupe le corps sans ligne : « Aucun résultat », le motif d'absence
  /// ou le chargement.
  final Widget vide;
  final PiedTableauAchats pied;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: Ardoise.c200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TableauRestaurant(
            gabarit: gabaritCrudAchats,
            pleineLargeur: true,
            repartitionProportionnelle: true,
            videSousEntete: true,
            // La colonne de la case : `th px-4 py-2.5 w-10`, 48 px.
            largeursFixes: const {0: AppLayout.colonneSelection},
            colonnes: colonnes,
            lignes: lignes,
            vide: vide,
          ),
          pied,
        ],
      ),
    );
  }
}
