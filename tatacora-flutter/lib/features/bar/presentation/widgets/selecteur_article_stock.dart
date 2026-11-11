// Vue Blade maîtresse (PA-183) : pwa/bar/carte.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../pos/data/dto/catalogue_dto.dart';
import '../../../restaurant/presentation/widgets/textes_modale_restaurant.dart';
import '../providers_bar.dart';

/// Le sélecteur d'**article de stock** des deux modales de la Carte du bar —
/// « Nouvelle boisson » et « Lier au stock » (`pwa.modal-lieraustock`, champ
/// `lien-article`) : un champ de recherche, puis la liste des articles en suivi
/// permanent qui correspondent.
///
/// ## Un seul composant, parce que la vue n'a qu'une liste
///
/// Les deux modales de la vue lisent la même `$articlesDeStock`, filtrée par la
/// même `rechercheArticleStock`. Deux sélecteurs écrits à part finiraient par ne
/// plus proposer les mêmes articles.
///
/// ## D'où viennent les articles
///
/// De `articles_local`, c'est-à-dire du module Stocks de CE poste
/// ([articlesDeStockProvider]) — plus d'une liste vide « délibérée » (PA-134) :
/// l'article d'une boisson se choisit parmi ceux que le poste détient, sans
/// réseau. Une liste vide se DIT, elle ne laisse pas un champ muet.
class SelecteurArticleStock extends ConsumerStatefulWidget {
  const SelecteurArticleStock({
    super.key,
    required this.prefixeCle,
    required this.invite,
    required this.aucunArticle,
    required this.articleId,
    required this.onChoisi,
    this.avecUnite = false,
    this.erreur,
  });

  /// Préfixe des clés : `<prefixe>-recherche` et `<prefixe>-liste`.
  final String prefixeCle;

  /// `modale_lien.invite_article` / `champ_boisson_article_invite`.
  final String invite;

  /// `modale_lien.aucun_article_stock`.
  final String aucunArticle;

  /// L'article actuellement choisi, ou `null`.
  final String? articleId;

  final ValueChanged<ArticleDeStock?> onChoisi;

  /// Le lien rend « libellé — unité de mesure » (`modal-lieraustock` l.79) ; la
  /// création, le seul libellé (`corps.blade.php` l.758).
  final bool avecUnite;

  final String? erreur;

  @override
  ConsumerState<SelecteurArticleStock> createState() =>
      _EtatSelecteurArticleStock();
}

class _EtatSelecteurArticleStock extends ConsumerState<SelecteurArticleStock> {
  String _terme = '';

  @override
  Widget build(BuildContext context) {
    final articles = ref.watch(articlesDeStockProvider(_terme));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: Key('${widget.prefixeCle}-recherche'),
          style: TextesModaleRestaurant.corps,
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            hintText: widget.invite,
          ),
          onChanged: (terme) => setState(() => _terme = terme.trim()),
        ),
        const SizedBox(height: AppSpacing.xs),
        articles.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => Text('$e', style: TextesModaleRestaurant.aide),
          data: (liste) {
            // Un choix filtré par la recherche reste CHOISI : seul le menu
            // change, jamais la saisie de l'utilisateur.
            final courant = liste.any((a) => a.id == widget.articleId)
                ? widget.articleId
                : null;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                InputDecorator(
                  decoration: InputDecoration(
                    isDense: true,
                    border: const OutlineInputBorder(),
                    errorText: widget.erreur,
                    errorMaxLines: 4,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      key: Key('${widget.prefixeCle}-liste'),
                      isDense: true,
                      isExpanded: true,
                      value: courant,
                      style: TextesModaleRestaurant.corps,
                      hint: Text(
                        widget.invite,
                        style: TextesModaleRestaurant.aide,
                      ),
                      items: [
                        for (final a in liste)
                          DropdownMenuItem<String>(
                            value: a.id,
                            child: Text(
                              widget.avecUnite
                                  ? '${a.libelle} — ${a.uniteMesure}'
                                  : a.libelle,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (id) => widget.onChoisi(
                        liste.where((a) => a.id == id).firstOrNull,
                      ),
                    ),
                  ),
                ),
                if (liste.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xxs),
                    child: Text(
                      widget.aucunArticle,
                      key: Key('${widget.prefixeCle}-aucun'),
                      style: TextesModaleRestaurant.aide.copyWith(
                        color: PaletteMaitre.ambre700,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
