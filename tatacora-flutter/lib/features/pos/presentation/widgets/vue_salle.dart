// Vue Blade maîtresse (PA-183) : pwa/pos/comptant.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/cadre_tirete.dart';
import '../../../restaurant/presentation/widgets/corps_carte_commun.dart'
    show styleContenuCarte;
import '../../domain/entities/panier.dart';
import '../../domain/entities/table_pos.dart';
import '../providers_pos.dart';

/// Le panneau **Salle** — premier des trois panneaux du maître.
///
/// ## Pourquoi un panneau permanent et non une fenêtre
///
/// `prototype_v2/pages/pos.html` : *« Panneau PERMANENT, et non plus une
/// modale. Un serveur qui doit ouvrir une fenêtre pour savoir quelles tables
/// sont servies ne la consulte pas : il retient de tête, et se trompe. »*
///
/// ## Les quatre états, et pourquoi ils ne se confondent pas
///
/// | État | Ce qu'il dit |
/// |---|---|
/// | **Fermée** | désactivée en Paramètres, mais **toujours visible** — masquer une table ferait croire qu'elle n'existe pas, et un serveur la chercherait |
/// | **Libre** | active, aucun panier |
/// | **Ouverte** | un panier existe mais il est **vide** : la table est prise, rien n'est commandé |
/// | **En cours** | des consommations sont servies, l'encours s'affiche |
///
/// Confondre « ouverte » et « en cours » ferait croire qu'une commande a été
/// passée alors que personne n'a rien saisi.
class VueSalle extends ConsumerWidget {
  const VueSalle({
    required this.onChoisirTable,
    required this.onChoisirComptoir,
    this.tableActive,
    super.key,
  });

  /// Appelé avec l'identifiant de la table choisie.
  final void Function(TablePos) onChoisirTable;

  /// Le comptoir : une vente **sans aucune table**.
  final VoidCallback onChoisirComptoir;

  /// La table du panier en cours, pour la mettre en évidence.
  final String? tableActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salle = ref.watch(salleProvider);
    // Les paniers RÉELS, pour distinguer « ouverte » (panier vide) d'« en
    // cours » (lignes servies, total affiché) — la vue les dérive des paniers
    // (`PosComptant::etatsDesTables()`), jamais d'un drapeau tenu à part.
    final paniers = {
      for (final p in ref.watch(paniersProvider).value ?? const <Panier>[])
        p.id: p,
    };

    // Présentation alignée sur la vue le 14/10/2026 (NOUVELLE_INSTRUCTION1
    // §3) : `xl:w-[320px] bg-white`, en-tête `px-4 py-3 border-b`, corps
    // `p-4 space-y-4` (l.157-215).
    return Container(
      color: AppColors.neutre0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Ardoise.c200)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // `text-[14px] font-bold` navy — `pos_pwa.comptant.salle`.
                Text(
                  'Salle',
                  style: styleContenuCarte(
                    TaillesContenu.t14,
                    poids: FontWeight.bold,
                    couleur: AppColors.navy,
                  ),
                ),
                // `text-[11px] text-slate-400` — `salle_aide`.
                Text(
                  'Une table par panier. Le comptoir n’en exige aucune.',
                  style: styleContenuCarte(
                    TaillesContenu.t11,
                    couleur: Ardoise.c400,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: salle.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(
                  '$e',
                  style: styleContenuCarte(
                    TaillesContenu.t12,
                    couleur: Ardoise.c400,
                  ),
                ),
              ),
              data: (rayons) => ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  _BoutonComptoir(
                    actif: tableActive == null,
                    onTap: onChoisirComptoir,
                  ),
                  for (final rayon in rayons) ...[
                    // `space-y-4`.
                    const SizedBox(height: AppSpacing.md),
                    // `text-[11px] font-bold mb-1.5 uppercase tracking-wide
                    // text-slate-500`.
                    Text(
                      rayon.espace.libelle.toUpperCase(),
                      style: styleContenuCarte(
                        TaillesContenu.t11,
                        poids: FontWeight.bold,
                        couleur: Ardoise.c500,
                        interlettrage:
                            TaillesContenu.t11 * AppTextStyles.suiviLarge,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    // `grid grid-cols-3 gap-1.5`.
                    LayoutBuilder(
                      builder: (context, contraintes) {
                        const n = LargeursPos.colonnesTables;
                        final largeur =
                            (contraintes.maxWidth - AppSpacing.xxs * (n - 1)) /
                            n;
                        return Wrap(
                          spacing: AppSpacing.xxs,
                          runSpacing: AppSpacing.xxs,
                          children: [
                            for (final c in rayon.cases)
                              SizedBox(
                                width: largeur,
                                child: _CaseTable(
                                  cas: c,
                                  panier: c.panierOuvertId == null
                                      ? null
                                      : paniers[c.panierOuvertId],
                                  selectionnee: c.table.id == tableActive,
                                  onTap: () => onChoisirTable(c.table),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// « Vendre au comptoir · Sans table » — le maître le pose en tête, en bordure
/// tiretée, avant les espaces.
class _BoutonComptoir extends StatelessWidget {
  const _BoutonComptoir({required this.actif, required this.onTap});

  final bool actif;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // `w-full flex items-center gap-3 px-3 py-2.5 rounded-lg border-2
    // border-dashed` (l.171) : navy + `bg-slate-50` choisi, sinon slate-300.
    // Bordure TIRETÉE depuis le 14/10/2026 (lot B du plan du PO) : le cadre
    // `CadreTirete` (brique commune) remplace la bordure pleine de 2 px, qui
    // était un écart de forme faute de `border-dashed` natif. Même épaisseur,
    // même place prise : seul le trait change.
    return InkWell(
      key: const Key('pos-choix-comptoir'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      child: CadreTirete(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xsPlus,
        ),
        fond: actif ? Ardoise.c50 : AppColors.neutre0,
        rayon: AppRadius.roundedLg,
        couleur: actif ? AppColors.navy : Ardoise.c300,
        epaisseur: LargeursPos.bordureComptoir,
        tiret: LargeursPos.tiretComptoir,
        espace: LargeursPos.espaceTiretComptoir,
        child: Row(
          children: [
            // `w-8 h-8 rounded-lg bg-navy text-white font-bold text-[13px]`.
            Container(
              width: LargeursPos.initialeComptoir,
              height: LargeursPos.initialeComptoir,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.navy,
                borderRadius: BorderRadius.circular(AppRadius.roundedLg),
              ),
              child: Text(
                'C',
                style: styleContenuCarte(
                  TaillesContenu.t13,
                  poids: FontWeight.bold,
                  couleur: AppColors.neutre0,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vendre au comptoir',
                    style: styleContenuCarte(
                      TaillesContenu.t13,
                      poids: FontWeight.bold,
                      couleur: AppColors.navy,
                    ),
                  ),
                  Text(
                    'Sans table',
                    style: styleContenuCarte(
                      TaillesContenu.t11,
                      couleur: Ardoise.c500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaseTable extends StatelessWidget {
  const _CaseTable({
    required this.cas,
    required this.panier,
    required this.selectionnee,
    required this.onTap,
  });

  final CaseSalle cas;

  /// Le panier ouvert de la table, s'il est lu : ses lignes tranchent entre
  /// « ouverte » (vide) et « en cours » (total affiché).
  final Panier? panier;
  final bool selectionnee;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Une table FERMÉE reste visible mais inerte : le maître la barre plutôt
    // que de la masquer. (La vue ne rend pas cet état — `table.actif` n'y a
    // pas de source — ; ce poste, lui, en a une.)
    final fermee = cas.fermee;
    final enCours = cas.occupee && (panier?.lignes.isNotEmpty ?? false);
    // Lot F6 (ajout du PO, 18/10/2026 — la vue ne connaît qu'un poste) : une
    // table prise sur un AUTRE poste se montre « ouverte » aux couleurs de la
    // vue, dit « autre poste », et ne s'ouvre pas ici.
    final ailleurs = cas.occupeeAilleurs;
    final ouverte = (cas.occupee && !enCours) || ailleurs;

    // `px-2.5 py-2 rounded-lg border text-left` (l.199) : en cours = bordure
    // or + `bg-amber-50` ; ouverte = `border-blue-300 bg-blue-50` ; libre =
    // `bg-white border-slate-200` ; la table choisie porte `ring-2` navy.
    final fond = fermee
        ? Ardoise.c50
        : enCours
        ? PaletteMaitre.ambre50
        : ouverte
        ? PaletteMaitre.bleu50
        : AppColors.neutre0;
    final bordure = fermee
        ? Ardoise.c200
        : enCours
        ? AppColors.gold
        : ouverte
        ? PaletteMaitre.bleu300
        : Ardoise.c200;
    final couleurEtat = fermee
        ? Ardoise.c400
        : enCours
        ? PaletteMaitre.ambre700
        : ouverte
        ? PaletteMaitre.bleu700
        : Ardoise.c400;

    return InkWell(
      key: Key('pos-table-${cas.table.libelle}'),
      onTap: fermee || ailleurs ? null : onTap,
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xsPlus,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: fond,
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
          border: Border.all(color: bordure),
          // `ring-2 ring-[var(--navy)]` : un anneau HORS de la boîte, comme le
          // `box-shadow` de Tailwind (le fond est opaque, rien ne transparaît).
          boxShadow: selectionnee
              ? const [
                  BoxShadow(
                    color: AppColors.navy,
                    spreadRadius: LargeursPos.anneauTable,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // `block text-[13px] font-bold` navy.
            Text(
              cas.table.libelle,
              style:
                  styleContenuCarte(
                    TaillesContenu.t13,
                    poids: FontWeight.bold,
                    couleur: fermee ? Ardoise.c400 : AppColors.navy,
                  ).copyWith(
                    decoration: fermee ? TextDecoration.lineThrough : null,
                  ),
            ),
            // `block text-[10.5px]` : le total en cours, « ouverte », ou les
            // places. Le libellé dit l'état, il ne se devine pas d'une
            // couleur : un écran de comptoir se lit de biais.
            Text(
              fermee
                  ? 'fermée'
                  : enCours
                  ? formaterFcfa(panier!.total)
                  : ailleurs
                  ? 'autre poste'
                  : ouverte
                  ? 'ouverte'
                  : '${cas.table.places} pl.',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: styleContenuCarte(
                TaillesContenu.t10_5,
                couleur: couleurEtat,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
