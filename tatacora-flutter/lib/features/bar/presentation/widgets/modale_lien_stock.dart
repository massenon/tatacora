// Vue Blade maîtresse (PA-183) : pwa/bar/carte.blade.php
import 'package:flutter/material.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../../restaurant/presentation/widgets/textes_modale_restaurant.dart';
import '../../data/boissons_api.dart';
import '../../domain/entities/carte_bar.dart';

/// La modale **« Lier au stock »** de la Carte du bar — composant
/// `pwa.modal-lieraustock` inclus par le corps partagé des cartes (l.710-715),
/// ouvert par « Modifier le lien » / « Lier au stock » de chaque ligne
/// (l.411-414).
///
/// @see EF-M5-02 Carte des boissons
/// @see RG-05 Sortie de stock automatique — le conditionnement est consommé à
///      chaque vente
///
/// ## ⚠ CE GESTE EST REFUSÉ SUR CE POSTE (14/09/2026), et le refus est nommé
///
/// Deux manques, et **chacun suffirait** :
///
///  1. **Il n'y a aucun article auquel se lier.** `articles_local` est
///     délibérément vide (PA-134) : le stock était calculé par le serveur, et
///     aucun référentiel d'articles n'est répliqué ici.
///  2. **Il n'y a nulle part où ranger le conditionnement.**
///     `cartes_boisson_local` n'a que cinq colonnes, et aucune ne porte
///     `unites_vendables_par_unite_stock` — or c'est la raison d'être même de
///     cette modale : un casier de 24 et une bouteille à l'unité ne
///     décrémentent pas pareil.
///
/// Écrire le seul `article_id` en jetant le conditionnement serait le pire des
/// trois choix : la carte annoncerait un rattachement, et chaque vente
/// décrémenterait un casier entier. C'est « un formulaire dont les champs sont
/// collectés puis ignorés » (Article 6), appliqué à du stock.
///
/// Le formulaire n'est donc pas rendu. Ses libellés restent déclarés dans
/// [TextesLienStock] : ils sont la spécification de ce qui manque, et l'écran
/// devra les reprendre tels quels le jour où la colonne existera.
///
/// ⚠ **Les deux aides de la vue sont rendues TELLES QUELLES** (l.80-85 et
/// l.102-104). Elles avaient d'abord été fondues en une reformulation, et la
/// garde `conformite_blade_test` l'a refusée à juste titre : on ne reformule
/// pas un libellé du maître. Ce sont elles qui disent ce que le lien absent
/// recouvre — quels articles y entrent, et ce que vaut un conditionnement.
///
/// ## Le bouton, lui, reste à sa place — et c'est voulu
///
/// `TableCarte` affiche « Lier au stock » sur chaque ligne. Le retirer
/// laisserait croire que le rattachement n'existe pas dans ce produit ; il
/// ouvre donc cette modale, qui DIT pourquoi il ne peut pas se faire ici et où
/// il se fait (Article 3.3 — un contrôle visible mène quelque part).
///
/// ## Deux fournisseurs ont disparu avec le formulaire
///
/// `boissonServeurProvider` relisait la boisson au serveur pour partir du
/// conditionnement ENREGISTRÉ — jamais d'un 1 par défaut, qui aurait divisé la
/// déduction d'un casier par vingt-quatre — et `referentielLienProvider`
/// lisait les articles en suivi permanent avec leur solde au point « bar ».
/// Les deux rendaient « refusé » ou `null` pour tout le monde.
Future<bool?> ouvrirModaleLienStock(BuildContext context, LigneCarte ligne) =>
    showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: AppColors.voileModale,
      builder: (_) => _ModaleLien(ligne: ligne),
    );

/// Les mots de la vue — `lang/fr/carte_pwa.php`, `commun` et `modale_lien`.
///
/// Conservés en entier bien que le formulaire ne soit plus rendu : ils disent
/// ce que le geste absent recouvre, et ils sont ce que l'écran reprendra.
abstract final class TextesLienStock {
  static const String boutonLier = 'Lier au stock';
  static const String boutonModifier = 'Modifier le lien';
  static const String titre = 'Lier au stock';
  static String sousTitre(String article, String prix) => '$article — $prix';
  static const String champArticle = 'Article de stock';
  static const String inviteArticle = 'Rechercher un article de stock…';
  static const String aucunArticle =
      'Aucun article en suivi permanent ne correspond à cette recherche.';
  static String champConversion(String article) =>
      'Combien de « $article » dans une unité de stock ?';
  static const String apercuStock = 'Stock actuel';
  static const String apercuVendables = 'Soit, en unités vendables';
  static const String apercuDecrement = 'Chaque vente décrémentera';
  static const String nonConsulte = 'non consulté';
  static const String annuler = 'Annuler';
  static const String confirmer = 'Enregistrer le lien';
  static String rattache(String article) =>
      '« $article » est rattaché au stock.';

  /// Le bouton « Fermer » remplace « Annuler » : il n'y a rien à annuler.
  static const String fermer = 'Fermer';
}

class _ModaleLien extends StatelessWidget {
  const _ModaleLien({required this.ligne});

  final LigneCarte ligne;

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleRestaurant(
      cle: const Key('modale-lien-stock'),
      titre: TextesLienStock.titre,
      sousTitre: TextesLienStock.sousTitre(
        ligne.libelle,
        formaterFcfa(ligne.prix),
      ),
      largeur: AppLayout.modaleLienStock,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Le motif vient de `BoissonsApi`, seul endroit où il est écrit :
          // deux phrases voisines finiraient par donner deux causes pour une
          // seule situation.
          const _Avertissement(
            cle: Key('lien-stock-sans-colonne'),
            texte: TextesCatalogueLocal.lienSansColonne,
          ),
          const SizedBox(height: AppSpacing.md),

          // `aide_article` : « suivi permanent » en gras, comme la vue. Elle
          // dit QUELS articles pourraient entrer dans ce lien.
          const Text.rich(
            TextSpan(
              style: TextesModaleRestaurant.aide,
              children: [
                TextSpan(text: 'Seuls les articles en '),
                TextSpan(
                  text: 'suivi permanent',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                // Sur UNE ligne : le comparateur ne recolle que des littéraux de
                // même guillemet, et l'apostrophe droite de la vue impose `"`.
                TextSpan(
                  text:
                      " apparaissent : un article en achat journalier n'est pas suivi, le rattacher ne décrémenterait rien.",
                ),
              ],
            ),
            key: Key('lien-stock-aide-article'),
          ),
          const SizedBox(height: AppSpacing.sm),

          // `aide_conversion` : « 24 » et « 1 » en gras, comme la vue. Elle dit
          // ce que porte la colonne manquante — et pourquoi un demi-lien serait
          // pire que pas de lien du tout.
          const Text.rich(
            TextSpan(
              style: TextesModaleRestaurant.aide,
              children: [
                TextSpan(text: 'Un casier de 24 bouteilles ? Saisissez '),
                TextSpan(
                  text: '24',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: ". Un bidon d'huile utilisé entier ? Saisissez ",
                ),
                TextSpan(
                  text: '1',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: '.'),
              ],
            ),
            key: Key('lien-stock-aide-conversion'),
          ),
        ],
      ),
      actions: [
        // Un seul bouton : il n'y a rien à enregistrer, donc rien à annuler.
        // « Enregistrer le lien », grisé, inviterait à cliquer pour ne
        // produire qu'un refus.
        FilledButton(
          key: const Key('lien-stock-fermer'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(
            TextesLienStock.fermer,
            style: TextesModaleRestaurant.bouton,
          ),
        ),
      ],
    );
  }
}

/// Ce que la modale dit du geste qu'elle ne peut pas porter.
class _Avertissement extends StatelessWidget {
  const _Avertissement({required this.cle, required this.texte});

  final Key cle;
  final String texte;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: cle,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: PaletteMaitre.ambre50,
        border: Border.all(color: PaletteMaitre.ambre200),
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      ),
      child: Text(
        texte,
        style: TextesModaleRestaurant.corps.copyWith(
          color: PaletteMaitre.ambre900,
        ),
      ),
    );
  }
}
