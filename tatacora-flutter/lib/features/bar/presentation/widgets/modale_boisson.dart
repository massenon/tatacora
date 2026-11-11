import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
// Le moteur CRUD du maître est unique et son portage vit dans
// `features/restaurant/` — voir l'en-tête de `ecran_catalogue_boissons.dart`.
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../../restaurant/presentation/widgets/textes_modale_restaurant.dart';
import '../../data/boissons_api.dart';
import '../../domain/entities/boisson.dart';
import '../providers_catalogue_boissons.dart';
import 'modale_lien_stock.dart' show TextesLienStock;
import 'modale_nouvelle_boisson.dart' show TextesNouvelleBoisson;
import 'selecteur_article_stock.dart';

/// La modale de formulaire du moteur CRUD — `crud-ui.js` l.85-103, remplie par
/// `champsFormulaire` de `prototype_v2/pages/m5-bar.html` l.121-160.
///
/// ## Le formulaire du maître ne pouvait PAS créer une boisson, et c'est mesuré
///
/// Ses quatre champs sont : Nom de la boisson, Catégorie, Prix de vente
/// (FCFA), Stock disponible (unités). Le quatrième est le piège : le stock **se
/// lit, il ne se saisit pas** (PA-24). Côté serveur, aucune règle `prohibited`
/// ne le rejetait — il était ACCEPTÉ puis jeté en silence, et l'utilisateur
/// voyait « Boisson enregistrée » en croyant avoir saisi un stock. C'est
/// exactement « un formulaire dont les champs sont collectés puis ignorés à la
/// validation » (Article 6).
///
/// ## ⚠ Ce formulaire écrit DANS LA BASE LOCALE depuis le 14/09/2026
///
/// Il postait à `POST`/`PUT /bar/boissons`. Le poste est zéro réseau : la
/// saisie va dans `cartes_boisson_local`, par [BoissonsApi] et le
/// `CatalogueDao`, seul auteur de cette table.
///
/// ## Ce qui est fait de la quatrième place, et pourquoi
///
/// ÉCART DÉLIBÉRÉ — `prototype_v2/pages/m5-bar.html` l.121-160.
/// Le maître : quatre champs, dont un que rien n'écrit.
/// Ici : les trois premières **positions** du maître sont tenues, dans son
/// ordre. La quatrième — « Stock disponible (unités) » — n'est pas un champ :
/// elle affiche en lecture seule ce que ce poste sait du stock, c'est-à-dire
/// rien, et elle DIT pourquoi.
/// Raison : le stock se calcule des mouvements, et ce poste n'en a aucun
/// (PA-134). Afficher « 0 » se lirait « rupture » sur l'écran où l'on décide de
/// commander ; offrir un champ ferait ressusciter le défaut PA-24.
///
/// ÉCART DÉLIBÉRÉ — le sélecteur « Article de stock », RÉTABLI à la CRÉATION
/// (26/10/2026).
/// Il remplace le champ de stock du maître par une vraie clé étrangère, parce
/// que le serveur exige `article_id` (`required`, `exists:articles,id`) : une
/// boisson saisie sans lui était rejetée à l'envoi, et ne décrémentait rien.
/// Retiré le 14/09/2026 quand `articles_local` était vide, il revient avec le
/// module Stocks du poste (`articles_local` est alimenté) — le même
/// [SelecteurArticleStock] que la Carte du bar —, suivi du conditionnement
/// (« Combien de … dans une unité de stock ? »).
/// ⚠ À la MODIFICATION, le lien existant est **conservé** tel quel : il se
/// change par « Modifier le lien » de la Carte du bar, qui porte l'aperçu.
///
/// ## Le titre « Nouveau » du gabarit n'est JAMAIS affiché, chez le maître non plus
///
/// `crud-ui.js` l.91 écrit en dur
/// `<h2 id="crud-titre-formulaire">Nouveau</h2>` — c'est un **texte de
/// remplissage** du gabarit HTML, que `crud-engine.js` l.387 et l.399
/// remplacent avant toute ouverture, par « Ajouter `<singulier>` » ou
/// « Modifier — `<valeur>` ». Personne ne voit donc jamais « Nouveau » sur
/// cette modale, ni au maître ni ici.
Future<bool?> ouvrirModaleBoisson(BuildContext context, {Boisson? boisson}) =>
    showDialog<bool>(
      context: context,
      // Fermeture au voile — Article 4.6. L'échappement est branché par la
      // coquille.
      barrierDismissible: true,
      barrierColor: AppColors.voileModale,
      builder: (_) => _ModaleBoisson(boisson: boisson),
    );

class _ModaleBoisson extends ConsumerStatefulWidget {
  const _ModaleBoisson({this.boisson});

  final Boisson? boisson;

  @override
  ConsumerState<_ModaleBoisson> createState() => _ModaleBoissonState();
}

class _ModaleBoissonState extends ConsumerState<_ModaleBoisson> {
  late final TextEditingController _libelle = TextEditingController(
    text: widget.boisson?.libelle ?? '',
  );
  late final TextEditingController _prix = TextEditingController(
    text: widget.boisson?.prixVente ?? '',
  );

  late CategorieBoisson? _categorie = widget.boisson?.categorie;

  // Le lien, à la CRÉATION seulement (voir l'écart en tête de fichier).
  final _conversion = TextEditingController();
  String? _articleId;

  bool _envoi = false;
  String? _refus;
  Map<String, String> _parChamp = const {};

  bool get _modification => widget.boisson != null;

  @override
  void dispose() {
    _libelle.dispose();
    _prix.dispose();
    _conversion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleRestaurant(
      cle: const Key('modale-boisson'),
      // Les titres du maître — `crud-engine.js` l.387 et l.399. Le second
      // interpole `entiteLabelSingulier`, qui vaut « boisson » (l.75).
      titre: _modification
          ? 'Modifier — ${widget.boisson!.libelle}'
          : 'Ajouter boisson',
      largeur: AppLayout.modalePlat,
      refus: _refus,
      cleRefus: const Key('modale-boisson-refus'),
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ---------------------------------------------- 1. Nom (l.123-129)
          const EtiquetteChampRestaurant(
            texte: 'Nom de la boisson',
            obligatoire: true,
          ),
          TextField(
            key: const Key('modale-boisson-libelle'),
            controller: _libelle,
            // Le libellé nomme la boisson dans la question du conditionnement.
            onChanged: (_) => setState(() {}),
            style: TextesModaleRestaurant.corps,
            decoration: InputDecoration(
              // Le `placeholder` du maître (l.128), au mot.
              hintText: 'Ex. Sodabi',
              isDense: true,
              border: const OutlineInputBorder(),
              errorText: _parChamp['libelle'],
              errorMaxLines: 4,
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ---------------------------------------- 2. Catégorie (l.130-141)
          const EtiquetteChampRestaurant(texte: 'Catégorie', obligatoire: true),
          DropdownButtonFormField<CategorieBoisson>(
            key: const Key('modale-boisson-categorie'),
            initialValue: _categorie,
            isExpanded: true,
            style: TextesModaleRestaurant.corps,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              errorText: _parChamp['categorie'],
            ),
            items: [
              for (final c in CategorieBoisson.values)
                DropdownMenuItem(value: c, child: Text(c.libelle)),
            ],
            onChanged: (c) => setState(() => _categorie = c),
          ),
          const SizedBox(height: AppSpacing.md),

          // ------------------------------------- 3. Prix de vente (l.142-148)
          const EtiquetteChampRestaurant(
            texte: 'Prix de vente (FCFA)',
            obligatoire: true,
          ),
          TextField(
            key: const Key('modale-boisson-prix'),
            controller: _prix,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextesModaleRestaurant.corps,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              errorText: _parChamp['prix_vente'],
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ------------- 4. La place de « Stock disponible (unités) » (l.149-155)
          const EtiquetteChampRestaurant(texte: 'Stock disponible (unités)'),
          const SizedBox(height: AppSpacing.xxs),
          _StockCalcule(boisson: widget.boisson),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            // Réécrit en français utilisateur (directive du PO, 14/10/2026) :
            // la raison technique est PA-24.
            'Le stock ne se saisit pas : il se calcule des mouvements. Le '
            'champ est en lecture seule — et vide, plutôt que faux.',
            key: const Key('modale-boisson-aide-article'),
            style: TextesModaleRestaurant.aide,
          ),

          // ---- Le lien au stock, à la création (écart : voir l'en-tête) ----
          if (!_modification) ...[
            const SizedBox(height: AppSpacing.md),
            const EtiquetteChampRestaurant(
              texte: TextesNouvelleBoisson.champArticle,
              obligatoire: true,
            ),
            SelecteurArticleStock(
              prefixeCle: 'modale-boisson-article',
              invite: TextesNouvelleBoisson.inviteArticle,
              aucunArticle: TextesLienStock.aucunArticle,
              articleId: _articleId,
              erreur: _parChamp['article_id'],
              onChoisi: (a) => setState(() {
                _articleId = a?.id;
                _parChamp = const {};
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            EtiquetteChampRestaurant(
              texte: TextesLienStock.champConversion(
                _libelle.text.trim().isEmpty
                    ? TextesNouvelleBoisson.cetteBoisson
                    : _libelle.text.trim(),
              ),
              obligatoire: true,
            ),
            TextField(
              key: const Key('modale-boisson-conversion'),
              controller: _conversion,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: TextesModaleRestaurant.corps,
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                errorText: _parChamp['unites_vendables_par_unite_stock'],
                errorMaxLines: 4,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const Key('modale-boisson-annuler'),
          onPressed: _envoi ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annuler', style: TextesModaleRestaurant.bouton),
        ),
        FilledButton(
          key: const Key('modale-boisson-enregistrer'),
          onPressed: _envoi ? null : _enregistrer,
          // Les libellés du maître — `crud-ui.js` l.99.
          child: Text(
            _modification ? 'Enregistrer les modifications' : 'Enregistrer',
            style: TextesModaleRestaurant.bouton,
          ),
        ),
      ],
    );
  }

  Future<void> _enregistrer() async {
    final categorie = _categorie;

    // Les obligatoires que l'écran peut juger seul. Le reste — prix illisible,
    // libellé déjà pris — vient du catalogue, seul à savoir ce qu'il contient.
    final manquants = <String, String>{
      if (_libelle.text.trim().isEmpty)
        'libelle': 'Le nom de la boisson est obligatoire.',
      if (categorie == null) 'categorie': 'La catégorie est obligatoire.',
      if (_prix.text.trim().isEmpty)
        'prix_vente': 'Le prix de vente est obligatoire.',
      if (!_modification && _articleId == null)
        'article_id': TextesCatalogueLocal.articleObligatoire,
      if (!_modification &&
          _articleId != null &&
          _conversion.text.trim().isEmpty)
        'unites_vendables_par_unite_stock':
            TextesCatalogueLocal.conversionRequise(
              _libelle.text.trim().isEmpty
                  ? TextesNouvelleBoisson.cetteBoisson
                  : _libelle.text.trim(),
            ),
    };

    if (manquants.isNotEmpty) {
      setState(() => _parChamp = manquants);
      return;
    }

    setState(() {
      _envoi = true;
      _refus = null;
      _parChamp = const {};
    });

    final resultat = await ref
        .read(boissonsApiProvider)
        .enregistrer(
          SaisieBoisson(
            libelle: _libelle.text.trim(),
            categorie: categorie!,
            prixVente: _prix.text.trim(),
            // Le lien existant est CONSERVÉ : l'effacer romprait un
            // rattachement que ce poste ne peut pas rétablir.
            articleId: _modification
                ? widget.boisson!.articleId
                : (_articleId ?? ''),
            // À la modification, le conditionnement existant est repris par
            // l'API (`BoissonsApi.enregistrer`) ; à la création, il est saisi.
            unitesVendablesParUniteStock: _modification ? '' : _conversion.text,
            // L'identifiant désigne la ligne à remplacer ; il est absent à la
            // création, où le catalogue en tire un neuf.
            id: widget.boisson?.id,
          ),
        );

    if (!mounted) return;

    switch (resultat) {
      case BarRecu<Boisson>():
        Navigator.of(context).pop(true);
      case BarRefuse<Boisson>(:final motif, :final erreurs):
        setState(() {
          _envoi = false;
          _refus = motif;
          _parChamp = erreurs;
        });
      case BarInjoignable<Boisson>():
        // Inatteignable : l'écriture est locale. Le cas reste écrit parce que
        // le registre est FERMÉ.
        setState(() => _envoi = false);
    }
  }
}

/// Le stock, en lecture seule — et **absent sur ce poste**.
///
/// Trois états possibles, et un seul survient ici. La distinction est gardée
/// parce qu'elle est la règle : « — » veut dire « on ne sait pas », jamais
/// « rupture ». Un « 0 » à cette place ferait commander des caisses déjà en
/// réserve.
class _StockCalcule extends StatelessWidget {
  const _StockCalcule({required this.boisson});

  final Boisson? boisson;

  @override
  Widget build(BuildContext context) {
    final b = boisson;

    final (texte, cle) = switch (b) {
      null => (
        'Stock disponible : — (la boisson n’existe pas encore).',
        'modale-boisson-stock-creation',
      ),
      Boisson(stockDisponible: null) => (
        'Stock disponible : — . Ce poste ne tient aucun mouvement de stock : '
            'le chiffre est ABSENT, il n’est pas nul. « — » n’est pas « 0 », '
            'et ne veut pas dire « en rupture ».',
        'modale-boisson-stock-inconnu',
      ),
      Boisson(:final stockDisponible) => (
        'Stock disponible : $stockDisponible unité(s). Lecture seule.',
        'modale-boisson-stock-lu',
      ),
    };

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: Ardoise.c50,
        border: Border.all(color: Ardoise.c200),
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      ),
      child: Text(texte, key: Key(cle), style: TextesModaleRestaurant.aide),
    );
  }
}
