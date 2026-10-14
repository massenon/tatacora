import 'package:flutter/material.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../restaurant/presentation/widgets/coquille_restaurant.dart';
import '../../domain/entities/boisson.dart';
import '../../domain/entities/carte_bar.dart';

/// Le tableau de la carte — `m5-bar-carte.html`, onglet « Carte du jour ».
///
/// ## La colonne « Stock » dit POURQUOI elle est vide
///
/// Trois états, et les confondre coûterait cher : un chiffre, « sans lien »
/// (la boisson ne décrémente aucun casier, sa vente ne se rapproche de rien),
/// et « non consulté » (le serveur n'a pas répondu). Écrire « 0 » dans les deux
/// derniers ferait commander des caisses déjà en réserve.
///
/// ## La colonne d'actions n'existe que pour qui peut écrire
///
/// La vue termine chaque ligne par une colonne sans titre (`<th></th>`,
/// corps partagé des cartes l.330) : « Rendre indispo. » / « Remettre »
/// (l.403-409), « Modifier le lien » / « Lier au stock » (l.411-414), puis
/// « Prix » (l.434-435) — l'ordre de la vue. Des callbacks à `null` — un rôle
/// en lecture — retirent leurs boutons, et la colonne entière quand il n'en
/// reste aucun : un bouton qui ne mène qu'à un refus 403 invite à cliquer.
///
/// ## Une ligne RETIRÉE du jour se voit, comme dans la vue
///
/// Atténuée (`opacity-55`, l.336) et sous-titrée de son motif en ambre, avec
/// le commentaire (l.340-344). « Rendre indispo. » et « Remettre » ne sont
/// offerts que si le serveur a dit l'état de la ligne
/// ([LigneCarte.disponibiliteConnue]) : hors connexion, proposer l'un ou
/// l'autre serait deviner.
class TableCarte extends StatelessWidget {
  const TableCarte({
    super.key,
    required this.lignes,
    this.onModifierPrix,
    this.onLierAuStock,
    this.onRetirer,
    this.onRemettre,
    this.onHistorique,
  });

  final List<LigneCarte> lignes;

  final ValueChanged<LigneCarte>? onModifierPrix;

  final ValueChanged<LigneCarte>? onLierAuStock;

  final ValueChanged<LigneCarte>? onRetirer;

  final ValueChanged<LigneCarte>? onRemettre;

  /// « Historique des prix » (l.436-437) — une LECTURE, offerte même à un
  /// rôle qui n'écrit pas : c'est alors le seul bouton de la colonne.
  final ValueChanged<LigneCarte>? onHistorique;

  @override
  Widget build(BuildContext context) {
    if (lignes.isEmpty) {
      return Container(
        key: const Key('carte-vide'),
        padding: const EdgeInsets.all(AppSpacing.lg),
        alignment: Alignment.center,
        child: Text(
          'Aucun article ne correspond à ces critères.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    final modifierPrix = onModifierPrix;
    final lierAuStock = onLierAuStock;
    final retirer = onRetirer;
    final remettre = onRemettre;
    final historique = onHistorique;
    final actions =
        modifierPrix != null ||
        lierAuStock != null ||
        retirer != null ||
        remettre != null ||
        historique != null;

    // Le CADRE (`bg-white rounded-xl border border-slate-200 overflow-hidden`,
    // l.304) et son en-tête « N article(s) » sont posés par l'écran, avec
    // `CadreTableauRestaurant` : le tableau ne dessine plus sa propre bordure.
    return LayoutBuilder(
      builder: (context, contraintes) => SingleChildScrollView(
        // `overflow-x-auto` (l.310) : défiler plutôt que comprimer.
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          // `w-full` : au moins la largeur du cadre.
          constraints: BoxConstraints(minWidth: contraintes.maxWidth),
          child: DataTable(
            // `<thead class="bg-[var(--navy)]">` (l.312), en-têtes `px-3 py-2.5`
            // `text-[11px] uppercase tracking-wide text-white/90 font-semibold`.
            headingRowColor: const WidgetStatePropertyAll(AppColors.navy),
            headingTextStyle: TextesRestaurant.enteteColonneNavy,
            // `px-3` de part et d'autre de chaque cellule : 24 px entre deux
            // colonnes, 12 px au bord.
            columnSpacing: AppSpacing.lg,
            horizontalMargin: AppSpacing.sm,
            dividerThickness: 1,
            columns: [
              DataColumn(label: _entete('Article')),
              DataColumn(label: _entete('Catégorie')),
              DataColumn(label: _entete('Prix'), numeric: true),
              // `export_col_disponible` et `col_article_stock` (vue l.325-326).
              DataColumn(label: _entete('Disponible'), numeric: true),
              DataColumn(label: _entete('Article de stock'), numeric: true),
              // `col_stock_vendable` et `export_col_reserve` (vue l.327-328) —
              // en unités VENDABLES depuis PA-199, comme la PWA.
              DataColumn(label: _entete('Stock vendable'), numeric: true),
              DataColumn(label: _entete('Réserve'), numeric: true),
              // `<th class="px-3 py-2.5"></th>` — la colonne d'actions de la vue
              // n'a pas de titre.
              if (actions) const DataColumn(label: SizedBox.shrink()),
            ],
            rows: [
              for (final l in lignes)
                // Pas de clé sur la `DataRow` : elle n'atteint pas l'arbre de
                // widgets (piège 10). Elle est posée sur la cellule de libellé.
                DataRow(
                  cells: [
                    DataCell(
                      _Attenue(
                        ligne: l,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.libelle,
                              key: Key('carte-ligne-${l.id}'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (l.indisponibilite case final retrait?)
                              // `{{ libelleMotif() }} — {{ commentaire }}`
                              // (l.341-343), ambre.
                              Text(
                                retrait.commentaire == null
                                    ? retrait.libelle
                                    : '${retrait.libelle} — ${retrait.commentaire}',
                                key: Key('carte-retrait-${l.id}'),
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: PaletteMaitre.ambre700),
                              ),
                          ],
                        ),
                      ),
                    ),
                    DataCell(
                      _Attenue(
                        ligne: l,
                        child: Text(
                          CategorieBoisson.depuisCode(l.categorie)?.libelle ??
                              (l.categorie.isEmpty ? '—' : l.categorie),
                          // `text-right text-slate-500 text-[12px]` (l.347).
                          style: TextesRestaurant.secondaire,
                        ),
                      ),
                    ),
                    DataCell(
                      _Attenue(
                        ligne: l,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            l.sansPrix
                                ? Text(
                                    'Sans tarif',
                                    key: Key('carte-sans-prix-${l.id}'),
                                    style: const TextStyle(
                                      color: AppColors.alerte,
                                    ),
                                  )
                                : Text(formaterFcfa(l.prix)),
                            // Les deux marques SOUS le prix (vue l.354-360) :
                            // un prix provisoire non marqué se lit comme un
                            // tarif ferme.
                            if (l.prixProvisoire)
                              Text(
                                'provisoire',
                                key: Key('carte-marque-provisoire-${l.id}'),
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: PaletteMaitre.rouge600,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            if (l.prixCorrigeMain)
                              Text(
                                'corrigé à la main',
                                key: Key('carte-marque-corrige-${l.id}'),
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: PaletteMaitre.ambre600),
                              ),
                          ],
                        ),
                      ),
                    ),
                    // « Disponible » — « oui » / « non », les mots de l'export
                    // du maître (vue l.365-371) ; « — » tant que le serveur n'a
                    // pas dit l'état de la ligne.
                    DataCell(
                      _Attenue(
                        ligne: l,
                        child: _Disponible(ligne: l),
                      ),
                    ),
                    // « Article de stock » — le libellé et le conditionnement
                    // en clair, du serveur (vue l.373-380).
                    DataCell(
                      _Attenue(
                        ligne: l,
                        child: _ArticleDeStock(ligne: l),
                      ),
                    ),
                    DataCell(
                      _Attenue(
                        ligne: l,
                        child: CelluleStockCarte(ligne: l),
                      ),
                    ),
                    // « Réserve » — hors point de vente, en unités vendables ;
                    // « — » quand elle n'a pas pu être lue (vue l.390-400) :
                    // un zéro se lirait « rien en réserve ».
                    DataCell(
                      _Attenue(
                        ligne: l,
                        child: Text(
                          l.reserve?.toStringAsFixed(0) ?? '—',
                          key: Key('carte-reserve-${l.id}'),
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: Ardoise.c500),
                        ),
                      ),
                    ),
                    if (actions)
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (l.disponibiliteConnue &&
                                l.estRetiree &&
                                remettre != null) ...[
                              OutlinedButton(
                                key: Key('carte-remettre-${l.id}'),
                                onPressed: () => remettre(l),
                                child: const Text('Remettre'),
                              ),
                              const SizedBox(width: AppSpacing.unit),
                            ],
                            if (l.disponibiliteConnue &&
                                !l.estRetiree &&
                                retirer != null) ...[
                              OutlinedButton(
                                key: Key('carte-retirer-${l.id}'),
                                onPressed: () => retirer(l),
                                child: const Text('Rendre indispo.'),
                              ),
                              const SizedBox(width: AppSpacing.unit),
                            ],
                            if (lierAuStock != null) ...[
                              OutlinedButton(
                                key: Key('carte-lien-${l.id}'),
                                onPressed: () => lierAuStock(l),
                                // `article_stock !== null ? bouton_modifier_lien
                                // : bouton_lier` (l.413).
                                child: Text(
                                  l.estLieAuStock
                                      ? 'Modifier le lien'
                                      : 'Lier au stock',
                                ),
                              ),
                              const SizedBox(width: AppSpacing.unit),
                            ],
                            if (modifierPrix != null) ...[
                              OutlinedButton(
                                key: Key('carte-prix-${l.id}'),
                                onPressed: () => modifierPrix(l),
                                child: const Text('Prix'),
                              ),
                              const SizedBox(width: AppSpacing.unit),
                            ],
                            if (historique != null)
                              OutlinedButton(
                                key: Key('carte-historique-${l.id}'),
                                onPressed: () => historique(l),
                                child: const Text('Historique des prix'),
                              ),
                          ],
                        ),
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

/// L'en-tête d'une colonne : `uppercase` est une règle CSS, on applique la
/// même plutôt que de recopier des libellés déjà en capitales (le CSV et le
/// PDF, eux, gardent la casse du maître).
Widget _entete(String libelle) => Text(libelle.toUpperCase());

/// `opacity-55` d'une ligne retirée (l.336) — posé cellule par cellule, les
/// actions exceptées : « Remettre » doit rester lisible, c'est le geste qui
/// sort de l'état.
class _Attenue extends StatelessWidget {
  const _Attenue({required this.ligne, required this.child});

  final LigneCarte ligne;
  final Widget child;

  @override
  Widget build(BuildContext context) => ligne.estRetiree
      ? Opacity(opacity: AppLayout.opaciteLigneRetiree, child: child)
      : child;
}

/// Le contenu de la cellule de stock d'un article de carte — UN SEUL AUTEUR,
/// comme `pwa/carte/cellule-stock.blade.php` : l'onglet « Carte du jour » et
/// l'onglet « Ventes du Bar » le rendent tous deux (PA-197). Deux cellules
/// écrites à deux endroits finiraient par diverger — un état oublié d'un côté.
///
/// Trois états, jamais deux (PA-129) : un chiffre, « sans lien de stock »,
/// « non consulté ».
class CelluleStockCarte extends StatelessWidget {
  const CelluleStockCarte({required this.ligne, super.key});

  final LigneCarte ligne;

  @override
  Widget build(BuildContext context) {
    final petit = Theme.of(context).textTheme.labelMedium;

    // `cellule-stock.blade.php`, dans son ordre : sans lien, non consulté,
    // rupture, chiffre (ambre sous le seuil).
    if (!ligne.estLieAuStock) {
      return Tooltip(
        message: TextesStockCarte.sansLien,
        child: Text(
          'non suivi',
          key: Key('carte-sans-lien-${ligne.id}'),
          style: petit?.copyWith(color: Ardoise.c400),
        ),
      );
    }

    final stock = ligne.stock;
    if (stock == null) {
      return Tooltip(
        message: TextesStockCarte.nonConsulteDetail,
        child: Text(
          TextesStockCarte.nonConsulte,
          key: Key('carte-stock-inconnu-${ligne.id}'),
          style: petit?.copyWith(color: PaletteMaitre.ambre700),
        ),
      );
    }

    if (ligne.enRupture) {
      return Container(
        key: Key('carte-rupture-${ligne.id}'),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxs,
          // `py-0.5` de `cellule-stock.blade.php` — 2 px.
          vertical: AppSpacing.demi,
        ),
        decoration: BoxDecoration(
          color: PaletteMaitre.rouge50,
          borderRadius: BorderRadius.circular(AppSpacing.unit),
        ),
        child: Text(
          'rupture',
          style: petit?.copyWith(
            color: PaletteMaitre.rouge700,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return Text(
      stock.toStringAsFixed(0),
      key: Key('carte-stock-${ligne.id}'),
      style: TextStyle(
        fontWeight: FontWeight.w700,
        color: ligne.sousSeuil ? PaletteMaitre.ambre600 : AppColors.navy,
      ),
    );
  }
}

/// « oui » / « non » — badges émeraude et ambre de la vue (l.366-370).
class _Disponible extends StatelessWidget {
  const _Disponible({required this.ligne});

  final LigneCarte ligne;

  @override
  Widget build(BuildContext context) {
    final petit = Theme.of(context).textTheme.labelSmall;
    if (!ligne.disponibiliteConnue) {
      return Text(
        '—',
        key: Key('carte-disponible-inconnu-${ligne.id}'),
        style: petit?.copyWith(color: Ardoise.c400),
      );
    }
    final oui = !ligne.estRetiree;
    return Container(
      key: Key('carte-disponible-${ligne.id}'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxs,
        vertical: AppSpacing.demi,
      ),
      decoration: BoxDecoration(
        color: oui ? PaletteMaitre.emeraude50 : PaletteMaitre.ambre50,
        borderRadius: BorderRadius.circular(AppSpacing.unit),
      ),
      child: Text(
        oui ? 'oui' : 'non',
        style: petit?.copyWith(
          fontWeight: FontWeight.w600,
          color: oui ? PaletteMaitre.emeraude700 : PaletteMaitre.ambre700,
        ),
      ),
    );
  }
}

/// Le libellé de l'article de stock, puis son conditionnement en gris — ou
/// « — » avec sa raison en infobulle.
class _ArticleDeStock extends StatelessWidget {
  const _ArticleDeStock({required this.ligne});

  final LigneCarte ligne;

  @override
  Widget build(BuildContext context) {
    final libelle = ligne.lienLibelle;
    if (libelle == null) {
      return Tooltip(
        // Sans lien : la phrase de la vue ; lié mais sans réponse serveur :
        // on ne sait pas — ce n'est pas « aucun article ».
        message: ligne.estLieAuStock
            ? TextesStockCarte.nonConsulte
            : TextesStockCarte.sansLien,
        child: Text(
          '—',
          key: Key('carte-article-stock-absent-${ligne.id}'),
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: Ardoise.c400),
        ),
      );
    }
    return Column(
      key: Key('carte-article-stock-${ligne.id}'),
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          libelle,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: Ardoise.c600),
        ),
        if (ligne.lienDetail case final detail?)
          Text(
            detail,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: Ardoise.c400),
          ),
      ],
    );
  }
}

/// Les mots de la cellule de stock et de ses bandeaux — `carte_pwa.commun`.
abstract final class TextesStockCarte {
  /// `stock_non_consulte`.
  static const nonConsulte = 'non consulté';

  /// `stock_non_consulte_detail`.
  static const nonConsulteDetail =
      "Le stock de cet article n'a pas pu être lu : le chiffre est absent, il n'est pas nul.";

  /// `sans_lien_bar` — l'infobulle de « non suivi ».
  static const sansLien =
      'Non rattaché à un article de stock — la vente ne décrémentera rien.';
}
