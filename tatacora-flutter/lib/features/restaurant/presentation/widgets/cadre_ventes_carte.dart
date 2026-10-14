/// Le CADRE du panneau « Ventes » des deux cartes — bar et restaurant.
///
/// `pwa/carte/corps.blade.php` l.598-710 : le titre et son compteur, la note
/// sur le stock, les neuf colonnes, la ligne d'état vide, la ligne « TOTAL DE
/// LA PAGE ». Le côté serveur n'a qu'UN fichier pour les deux rayons ; ce
/// fichier est l'unique auteur de ce cadre côté client (09/10/2026), pour la
/// même raison que `corps_carte_commun.dart` : deux écrans jumeaux finissent
/// par diverger.
///
/// ## Ce que ce cadre rend quand AUCUNE ligne de vente n'existe sur le poste
///
/// Le poste est zéro réseau (décision du Product Owner du 14/09/2026) et rien
/// ne lui fournit les ventes d'un rayon : `ventes_bar_local` n'a aucun auteur,
/// et M4 n'a aucune source locale. Jusqu'au 09/10/2026 l'onglet se réduisait à
/// une note grise ; la vue, elle, montre TOUJOURS son cadre — titre, colonnes,
/// ligne de total — même sans une seule vente. Le cadre est donc rendu, et il
/// DIT ce qu'il ne sait pas :
///
///  - le compteur écrit « — ligne(s) · Total validé : — », jamais « 0 ligne(s)
///    · Total validé : 0 FCFA » : un zéro affirmerait « aucune vente », alors
///    que la vraie réponse est « ce poste ne les détient pas » ;
///  - la ligne d'état vide porte la phrase de `core/donnees_absentes.dart`, et
///    NON « Aucune ligne de vente ne correspond à ces critères. » (`ventes_vide`,
///    l.675) : cette phrase-là affirme qu'un filtre a été appliqué à des
///    ventes connues et n'a rien retenu ;
///  - le total de la page est « — », jamais « 0 FCFA ».
///
/// Ce que ce cadre ne rend PAS, et pourquoi (09/10/2026) : la pagination
/// (l.700-709, « Affichage de X-Y sur Z » et ses liens) — elle numérote des
/// lignes qui n'existent pas, et la rendre avec des tirets ne dirait rien de
/// plus que le message de l'état vide, qui est juste au-dessus. À rouvrir le
/// jour où une source locale des ventes existera.
///
/// Deux autres phrases de la vue accompagnent une LIGNE, et n'ont donc rien à
/// accompagner ici — les mots de la vue, nommés plutôt que tus :
///
///  - « annulée(s), hors total » (`ventes_compteur_annulees`, l.609 et l.691) :
///    le décompte des ventes annulées, après le compteur et dans la ligne de
///    total. Sans vente connue, il n'y a rien à décompter, et « dont 0
///    annulée(s) » affirmerait qu'on les a comptées ;
///  - « Cet article n'est plus à la carte : son stock ne se lit plus nulle part. Ce n'est pas un stock nul. » (`ventes_stock_hors_carte`, l.649) :
///    l'infobulle du « — » d'une LIGNE dont l'article a quitté la carte.
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import 'coquille_restaurant.dart';
import 'corps_carte_commun.dart';
import 'tableau_restaurant.dart';

/// Les mots du panneau « Ventes », au mot de la vue (`carte_pwa.commun.ventes_*`).
///
/// Une seule chaîne entre guillemets doubles quand elle contient une
/// apostrophe : le comparateur ne recolle pas deux littéraux adjacents de
/// guillemets différents.
abstract final class TextesVentesCarte {
  /// `ventes_recherche`.
  static const recherche = 'Rechercher un article, un ticket, un utilisateur…';

  /// `ventes_tous_statuts`.
  static const tousStatuts = 'Tous les statuts';

  /// `ventes_statut_validee`.
  static const validee = 'Validée';

  /// `ventes_statut_annulee`.
  static const annulee = 'Annulée';

  /// `ventes_du`.
  static const du = 'Du';

  /// `ventes_au`.
  static const au = 'Au';

  /// `ventes_bornes_aide`.
  static const bornesAide =
      'Les deux bornes sont incluses : une vente du dernier jour de la plage '
      'figure au tableau.';

  /// `ventes_stock_aide`.
  static const stockAide =
      "Le stock affiché est celui d'aujourd'hui, jamais celui du jour de la "
      "vente : aucune table n'en garde la trace.";

  /// `ventes_total_page`.
  static const totalPage = 'TOTAL DE LA PAGE';

  /// `ventes_total_page_aide`.
  static const totalPageAide =
      "Somme des lignes validées affichées ci-dessus. Une vente annulée reste au registre (RG-02) mais son montant n'est pas de l'argent.";

  /// `ventes_compteur` quand ni le nombre de lignes ni le total ne sont
  /// connus : « — », pas « 0 ».
  static const compteurAbsent = '— ligne(s) · Total validé : —';
}

/// Les colonnes de la vue (l.619-627) : les trois premières à gauche, les six
/// autres à droite (`$entete(…, true)` pour les trois premières).
const List<ColonneRestaurant> colonnesVentesCarte = [
  ColonneRestaurant('Date'),
  ColonneRestaurant('N° vente'),
  ColonneRestaurant('Article'),
  ColonneRestaurant('Stock actuel', aDroite: true),
  ColonneRestaurant('Prix unitaire', aDroite: true),
  ColonneRestaurant('Quantité', aDroite: true),
  ColonneRestaurant('Montant', aDroite: true),
  ColonneRestaurant('Statut', aDroite: true),
  ColonneRestaurant('Utilisateur', aDroite: true),
];

/// Le cadre du tableau des ventes, SANS ligne : l'état vide de la vue, dit
/// honnêtement (voir l'en-tête du fichier).
class CadreVentesSansDonnee extends StatelessWidget {
  const CadreVentesSansDonnee({
    super.key,
    required this.cleMessage,
    required this.message,
  });

  /// Posée sur le message de l'état vide, pour qu'un test le trouve.
  final Key cleMessage;

  /// Pourquoi il n'y a aucune ligne : la phrase de `donnees_absentes.dart`, ou
  /// le motif du refus. Jamais « Aucune ligne… ».
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // `mb-3` — 12 px (l.598).
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: CadreTableauRestaurant(
        titre: TextesVentesCarte.compteurAbsent,
        aside: TextesVentesCarte.stockAide,
        corps: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TableauRestaurant(
              gabarit: GabaritTableau.carteVue,
              pleineLargeur: true,
              colonnes: colonnesVentesCarte,
              lignes: const [],
              // La vue pose son `<thead>` hors de la boucle : l'en-tête reste
              // affiché au-dessus de la ligne d'état vide (l.616-677).
              videSousEntete: true,
              vide: _EtatVide(cle: cleMessage, message: message),
            ),
            const _TotalDeLaPage(),
          ],
        ),
      ),
    );
  }
}

/// La ligne d'état vide — `<td colspan="9" class="px-3 py-14 text-center
/// text-slate-400 text-[13px]">` sous `border-t border-slate-100` (l.674-675).
class _EtatVide extends StatelessWidget {
  const _EtatVide({required this.cle, required this.message});

  final Key cle;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Ardoise.c100)),
      ),
      // `px-3 py-14`.
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacingLarge.p14,
      ),
      alignment: Alignment.center,
      child: Text(
        message,
        key: cle,
        textAlign: TextAlign.center,
        style: styleContenuCarte(TaillesContenu.t13, couleur: Ardoise.c400),
      ),
    );
  }
}

/// La ligne « TOTAL DE LA PAGE » — `border-t-2 border-slate-300 bg-slate-50
/// font-bold`, cellules `px-3 py-2.5` (l.684-695).
///
/// ÉCART DÉLIBÉRÉ (09/10/2026) : la vue pose ce total dans le MÊME `<table>`
/// que les colonnes, son libellé sur les six premières (`colspan="6"`) et le
/// montant sous « Montant ». Le tableau Flutter ne sait pas fusionner de
/// cellules ; le libellé est ici à gauche et le montant à l'extrémité droite,
/// donc pas sous sa colonne. Le montant vaut « — » : la page n'a aucune ligne
/// à additionner, et « 0 FCFA » affirmerait une somme qui n'a pas été faite.
class _TotalDeLaPage extends StatelessWidget {
  const _TotalDeLaPage();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Ardoise.c50,
        border: Border(
          top: BorderSide(color: Ardoise.c300, width: AppSpacing.demi),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xsPlus,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  TextesVentesCarte.totalPage,
                  style: styleContenuCarte(
                    TaillesContenu.t13,
                    poids: FontWeight.bold,
                    couleur: AppColors.navy,
                  ),
                ),
                Text(
                  TextesVentesCarte.totalPageAide,
                  style: styleContenuCarte(
                    TaillesContenu.t11,
                    couleur: Ardoise.c400,
                  ),
                ),
              ],
            ),
          ),
          Text(
            CarteIndicateurRestaurant.absent,
            style: styleContenuCarte(
              TaillesContenu.t13,
              poids: FontWeight.bold,
              couleur: AppColors.gold,
            ),
          ),
        ],
      ),
    );
  }
}
