import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_text_styles.dart';

/// La tranche d'une liste affichée sur UNE page — **fonction pure**.
///
/// [page] est ramenée dans `[1, pages]` : un filtre qui réduit la liste alors
/// qu'on était en page 3 ne laisse jamais un tableau vide sous « Page 3 / 1 ».
/// Une liste vide a UNE page (« Page 1 / 1 », « Affichage de 0-0 sur 0 »).
final class TranchePage {
  const TranchePage._({
    required this.page,
    required this.pages,
    required this.debut,
    required this.fin,
    required this.total,
  });

  factory TranchePage.de({
    required int total,
    required int page,
    required int parPage,
  }) {
    assert(parPage > 0, 'parPage doit être positif');
    final pages = total == 0 ? 1 : (total + parPage - 1) ~/ parPage;
    final p = page < 1 ? 1 : (page > pages ? pages : page);
    final premier = (p - 1) * parPage;
    final dernier = premier + parPage > total ? total : premier + parPage;
    return TranchePage._(
      page: p,
      pages: pages,
      // Le décompte de la vue : `0` quand il n'y a rien, sinon le rang du
      // premier élément affiché (base 1).
      debut: total == 0 ? 0 : premier + 1,
      fin: dernier,
      total: total,
    );
  }

  final int page;
  final int pages;

  /// Rang (base 1) du premier élément affiché, `0` si la liste est vide.
  final int debut;

  /// Rang (base 1) du dernier élément affiché.
  final int fin;
  final int total;

  /// Les éléments de [liste] qui tombent sur cette page.
  List<T> decouper<T>(List<T> liste) =>
      total == 0 ? <T>[] : liste.sublist(debut - 1, fin);
}

/// Le pied de pagination d'un tableau : « Affichage de X-Y sur Z » à gauche,
/// « ← Précédent », « Page P / N », « Suivant → » à droite.
///
/// Les mots, le style des liens (`px-3 py-1.5 text-xs rounded-lg border
/// border-slate-200`, inactif à 40 %) et le cadre (`flex items-center
/// justify-between px-4 py-3 border-t border-slate-100`) sont ceux du pied de
/// pagination de la vue d'hébergement (onglet « Réservations en cours »,
/// `pwa.hebergement.reservations_affichage` et `pwa.pagination.*`).
///
/// ## Les contrôles sont TOUJOURS rendus
///
/// La pagination Laravel les masque quand il n'y a qu'une page
/// (`@if ($paginator->hasPages())`). Ce composant les rend toujours, désactivés
/// aux bornes : c'est la demande du Product Owner pour l'historique des ventes
/// (13/10/2026 : « Bouton ← Précédent (désactivé si page 1) … Page 1 / 1 »).
/// Un écran qui veut le comportement Laravel passe [masquerSansPages].
class PiedPagination extends StatelessWidget {
  const PiedPagination({
    required this.tranche,
    required this.onPage,
    required this.prefixeCle,
    this.masquerSansPages = false,
    super.key,
  });

  final TranchePage tranche;
  final ValueChanged<int> onPage;

  /// Préfixe des clés de test : `<prefixe>-decompte`, `-precedent`, `-page`,
  /// `-suivant`.
  final String prefixeCle;

  /// `true` : les liens disparaissent s'il n'y a qu'une page (comme Laravel).
  final bool masquerSansPages;

  static const TextStyle _texte = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.xs,
    height: TaillesContenu.interligneXs,
    color: Ardoise.c500,
  );

  @override
  Widget build(BuildContext context) {
    final fort = _texte.copyWith(fontWeight: FontWeight.bold);
    final t = tranche;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Ardoise.c100)),
      ),
      child: Row(
        children: [
          Flexible(
            child: Wrap(
              key: Key('$prefixeCle-decompte'),
              children: [
                const Text('Affichage de ', style: _texte),
                Text('${t.debut}-${t.fin}', style: fort),
                const Text(' sur ', style: _texte),
                Text('${t.total}', style: fort),
              ],
            ),
          ),
          if (!masquerSansPages || t.pages > 1) ...[
            const SizedBox(width: AppSpacing.sm),
            _Lien(
              cle: Key('$prefixeCle-precedent'),
              libelle: '← Précédent',
              onPressed: t.page <= 1 ? null : () => onPage(t.page - 1),
            ),
            const SizedBox(width: AppSpacing.xs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Text(
                'Page ${t.page} / ${t.pages}',
                key: Key('$prefixeCle-page'),
                style: _texte.copyWith(color: Ardoise.c600),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            _Lien(
              cle: Key('$prefixeCle-suivant'),
              libelle: 'Suivant →',
              onPressed: t.page >= t.pages ? null : () => onPage(t.page + 1),
            ),
          ],
        ],
      ),
    );
  }
}

class _Lien extends StatelessWidget {
  const _Lien({
    required this.cle,
    required this.libelle,
    required this.onPressed,
  });

  final Key cle;
  final String libelle;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? AppColors.opaciteDesactive : 1,
      child: InkWell(
        key: cle,
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xxs,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: Ardoise.c200),
            borderRadius: BorderRadius.circular(AppRadius.roundedLg),
          ),
          child: Text(
            libelle,
            style: PiedPagination._texte.copyWith(color: Ardoise.c600),
          ),
        ),
      ),
    );
  }
}
