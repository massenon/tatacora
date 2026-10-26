// Vue Blade maîtresse (PA-183) : pwa/bar/carte.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../pos/data/dto/catalogue_dto.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../../restaurant/presentation/widgets/textes_modale_restaurant.dart';
import '../../data/boissons_api.dart';
import '../../domain/apercu_lien.dart';
import '../../domain/entities/boisson.dart';
import '../../domain/entities/carte_bar.dart';
import '../../../pos/presentation/providers_pos.dart' show catalogueDaoProvider;
import '../providers_bar.dart';
import '../providers_catalogue_boissons.dart' show boissonsApiProvider;
import 'selecteur_article_stock.dart';

/// La modale **« Lier au stock »** de la Carte du bar — composant
/// `pwa.modal-lieraustock` inclus par le corps partagé des cartes (l.710-715),
/// ouvert par « Modifier le lien » / « Lier au stock » de chaque ligne
/// (l.411-414).
///
/// @see EF-M5-02 Carte des boissons
/// @see RG-05 Sortie de stock automatique — le conditionnement est consommé à
///      chaque vente
///
/// ## ⚠ Elle ÉCRIT, depuis le 26/10/2026
///
/// Du 14/09 au 26/10/2026 elle ne rendait qu'un refus : aucun article n'était
/// tenu sur le poste et aucune colonne ne portait le conditionnement. Les deux
/// existent maintenant (`articles_local`, `cartes_boisson_local.unites_vendables`
/// depuis la v30) : le formulaire de la vue est rendu en entier — l'article de
/// stock (recherche puis liste, suivi permanent seulement), « Combien de
/// « … » dans une unité de stock ? » et l'aperçu — et « Enregistrer le lien »
/// écrit l'article ET son conditionnement ENSEMBLE ([lierAuStockProvider] ->
/// [BoissonsApi.lierAuStock] -> `CatalogueDao`, qui les met en file).
///
/// Écrire le seul `article_id` en jetant le conditionnement serait le champ
/// collecté puis ignoré : un casier de 24 et une bouteille à l'unité ne
/// décrémentent pas pareil.
///
/// ## Le conditionnement de départ
///
/// Celui qui est ENREGISTRÉ quand la boisson est déjà liée (rouvrir la modale
/// d'un casier de 24 pour corriger l'article et repartir de 1 diviserait la
/// déduction par vingt-quatre) ; à défaut, « 1 », comme
/// `EcranDeCarte::ouvrirLienAuStock()`.
///
/// ## L'aperçu
///
/// Il n'apparaît que si le conditionnement est exploitable (la vue ne montre
/// aucun aperçu bâti sur un champ vide). « Stock actuel » est le solde au
/// point « bar » calculé des mouvements de CE poste ; sans point « bar » ou sans
/// article, la vue dit « non consulté » — jamais un zéro, qui se lirait
/// « rupture ».
///
/// « Délier » n'existe pas au bar : `cartes_boisson.article_id` est NOT NULL, le
/// lien se REMPLACE.
Future<bool?> ouvrirModaleLienStock(BuildContext context, LigneCarte ligne) =>
    showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: AppColors.voileModale,
      builder: (_) => _ModaleLien(ligne: ligne),
    );

/// Les mots de la vue — `lang/fr/carte_pwa.php`, `commun` et `modale_lien`.
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
}

class _ModaleLien extends ConsumerStatefulWidget {
  const _ModaleLien({required this.ligne});

  final LigneCarte ligne;

  @override
  ConsumerState<_ModaleLien> createState() => _EtatModaleLien();
}

class _EtatModaleLien extends ConsumerState<_ModaleLien> {
  final _conversion = TextEditingController(text: '1');

  String? _articleId;
  ArticleDeStock? _article;
  bool _envoi = false;
  String? _refus;
  Map<String, String> _parChamp = const {};

  @override
  void initState() {
    super.initState();
    _articleId = widget.ligne.articleId;
    _partirDeLEnregistre();
  }

  /// Le lien et le conditionnement déjà ENREGISTRÉS, relus à l'ouverture.
  Future<void> _partirDeLEnregistre() async {
    final b = await ref.read(boissonsApiProvider).boisson(widget.ligne.id);
    final dao = ref.read(catalogueDaoProvider);
    if (b is! BarRecu<Boisson>) return;
    final article = b.donnees.articleId.isEmpty
        ? null
        : await dao.articleDeStock(b.donnees.articleId);
    if (!mounted) return;
    setState(() {
      _article = article;
      final facteur = b.donnees.unitesVendablesParUniteStock;
      if (facteur != null) {
        final lu = lireDecimal(facteur);
        if (lu != null) _conversion.text = ecrireDecimal(lu);
      }
    });
  }

  @override
  void dispose() {
    _conversion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ligne = widget.ligne;
    return CoquilleModaleRestaurant(
      cle: const Key('modale-lien-stock'),
      titre: TextesLienStock.titre,
      sousTitre: TextesLienStock.sousTitre(
        ligne.libelle,
        formaterFcfa(ligne.prix),
      ),
      largeur: AppLayout.modaleLienStock,
      refus: _refus,
      cleRefus: const Key('lien-stock-refus'),
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ------------------------------------------- Article (l.34-62)
          const EtiquetteChampRestaurant(
            texte: TextesLienStock.champArticle,
            obligatoire: true,
          ),
          SelecteurArticleStock(
            prefixeCle: 'lien-stock-article',
            invite: TextesLienStock.inviteArticle,
            aucunArticle: TextesLienStock.aucunArticle,
            articleId: _articleId,
            avecUnite: true,
            erreur: _parChamp['article_id'],
            onChoisi: (a) => setState(() {
              _articleId = a?.id;
              _article = a;
              _parChamp = const {};
            }),
          ),
          const SizedBox(height: AppSpacing.xs),
          // `aide_article` : « suivi permanent » en gras, comme la vue.
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
          const SizedBox(height: AppSpacing.md),

          // -------------------------------------- Conversion (l.64-80)
          EtiquetteChampRestaurant(
            texte: TextesLienStock.champConversion(ligne.libelle),
            obligatoire: true,
          ),
          TextField(
            key: const Key('lien-stock-conversion'),
            controller: _conversion,
            // `type="number" min="0.0001" step="any"` : la virgule du Bénin est
            // acceptée par [lireDecimal].
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextesModaleRestaurant.corps,
            onChanged: (_) => setState(() => _parChamp = const {}),
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              errorText: _parChamp['unites_vendables_par_unite_stock'],
              errorMaxLines: 4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // `aide_conversion` : « 24 » et « 1 » en gras, comme la vue.
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

          // --------------------------------------------- Aperçu (l.87-115)
          if (_article != null &&
              decrementParVente(_conversion.text) != null) ...[
            const SizedBox(height: AppSpacing.md),
            _Apercu(
              article: _article!,
              nom: ligne.libelle,
              conditionnement: _conversion.text,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const Key('lien-stock-annuler'),
          onPressed: _envoi ? null : () => Navigator.of(context).pop(false),
          child: const Text(
            TextesLienStock.annuler,
            style: TextesModaleRestaurant.bouton,
          ),
        ),
        FilledButton(
          key: const Key('lien-stock-enregistrer'),
          onPressed: _envoi ? null : _enregistrer,
          child: const Text(
            TextesLienStock.confirmer,
            style: TextesModaleRestaurant.bouton,
          ),
        ),
      ],
    );
  }

  Future<void> _enregistrer() async {
    final articleId = _articleId;
    if (articleId == null) {
      setState(
        () =>
            _parChamp = {'article_id': TextesCatalogueLocal.articleObligatoire},
      );
      return;
    }
    setState(() {
      _envoi = true;
      _refus = null;
      _parChamp = const {};
    });

    final resultat = await ref.read(lierAuStockProvider)(
      id: widget.ligne.id,
      articleId: articleId,
      unitesVendablesParUniteStock: _conversion.text,
    );
    if (!mounted) return;

    switch (resultat) {
      case BarRecu<Boisson>(:final donnees):
        final messager = ScaffoldMessenger.of(context);
        Navigator.of(context).pop(true);
        messager.showSnackBar(
          SnackBar(
            content: Text(
              TextesLienStock.rattache(donnees.libelle),
              key: const Key('lien-stock-enregistre'),
            ),
          ),
        );
      case BarRefuse<Boisson>(:final motif, :final erreurs):
        setState(() {
          _envoi = false;
          // Le motif global seul quand AUCUN champ n'est en cause (boisson
          // introuvable) : sinon il redirait la phrase déjà sous le champ.
          _refus = erreurs.isEmpty ? motif : null;
          _parChamp = erreurs;
        });
      case BarInjoignable<Boisson>():
        // Inatteignable : l'écriture est locale (registre fermé, voir
        // `ResultatBar`).
        setState(() => _envoi = false);
    }
  }
}

/// L'aperçu — « Stock actuel », « Soit, en unités vendables », « Chaque vente
/// décrémentera » (`modal-lieraustock` l.87-115). Affiché, jamais soumis : le
/// serveur recalcule tout à la vente.
class _Apercu extends ConsumerWidget {
  const _Apercu({
    required this.article,
    required this.nom,
    required this.conditionnement,
  });

  final ArticleDeStock article;
  final String nom;
  final String conditionnement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final solde = ref.watch(soldeAuBarProvider(article.id)).value;
    final vendables = solde == null
        ? null
        : unitesVendables(solde: solde, conditionnement: conditionnement);
    final decrement = decrementParVente(conditionnement)!;

    Widget ligne(String libelle, Widget valeur) => Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(libelle, style: TextesModaleRestaurant.note),
        valeur,
      ],
    );
    const absent = Text(
      TextesLienStock.nonConsulte,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        color: PaletteMaitre.ambre700,
      ),
    );

    return Container(
      key: const Key('lien-stock-apercu'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(color: Ardoise.c200),
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ligne(
            TextesLienStock.apercuStock,
            solde == null
                ? absent
                : Text(
                    '$solde ${article.uniteMesure}',
                    style: TextesModaleRestaurant.corps,
                  ),
          ),
          ligne(
            TextesLienStock.apercuVendables,
            vendables == null
                ? absent
                : Text(
                    '$vendables × $nom',
                    style: TextesModaleRestaurant.corps,
                  ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          ligne(
            TextesLienStock.apercuDecrement,
            Text(
              '${ecrireDecimal(decrement)} ${article.uniteMesure}',
              key: const Key('lien-stock-decrement'),
              style: TextesModaleRestaurant.note,
            ),
          ),
        ],
      ),
    );
  }
}
