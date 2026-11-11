// Vue Blade maîtresse (PA-183) : pwa/bar/carte.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
// La coquille des modales est unique pour les écrans « carte » et « CRUD » —
// voir l'en-tête de `ecran_catalogue_boissons.dart` sur son nom de dossier.
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../../restaurant/presentation/widgets/textes_modale_restaurant.dart';
import '../../data/boissons_api.dart';
import '../../domain/entities/boisson.dart';
import '../providers_bar.dart';
import 'modale_lien_stock.dart' show TextesLienStock;
import 'selecteur_article_stock.dart';

/// La modale **« Nouvelle boisson »** de la Carte du bar —
/// `pwa/carte/corps.blade.php` l.717-774, ouverte par le bouton l.117-120.
///
/// @see EF-M5-02 Carte des boissons
/// @see RG-05 Le lien `article_id` rend la décrémentation possible
///
/// Ajout fonctionnel du Product Owner du 03/09/2026 côté PWA
/// (`CarteBar::ouvrirCreationBoisson()`) : sur un poste au comptoir, créer une
/// boisson exigeait un import CSV ou un client HTTP. Porté ici le 11/09/2026.
///
/// ## ⚠ Elle écrit DANS LA BASE LOCALE depuis le 14/09/2026
///
/// Elle postait à `POST /bar/boissons`, puis descendait la réponse dans la
/// carte locale. Le poste est zéro réseau, et la carte du bar n'a plus d'autre
/// auteur que celui-ci : c'est désormais le seul endroit d'où une boisson entre
/// au catalogue de ce poste — donc au point de vente (PA-129, déplacée).
///
/// ## Ce que la vue fait, et qui est tenu à l'identique
///
/// Le titre, le sous-titre, les champs dans leur ordre (Libellé ; Catégorie et
/// Prix côte à côte ; Article de stock), l'aide sous le bloc d'article,
/// « Annuler » puis « Créer la boisson ». La catégorie est pré-remplie avec la
/// PREMIÈRE du registre fermé, comme `ouvrirCreationBoisson()` le fait. L'article
/// de stock est OBLIGATOIRE (`bar.validation.article_obligatoire`) et choisi
/// parmi les articles en suivi permanent de CE poste (`articles_local`), que la
/// recherche filtre.
///
/// ## ⚠ La boisson naît AVEC son article et son conditionnement (26/10/2026)
///
/// Jusqu'au 26/10/2026 la modale n'offrait aucun sélecteur et créait la boisson
/// SANS lien : le serveur, qui exige l'article (`exists:articles,id`), la
/// rejetait à l'envoi, et le poste ne pouvait ni la lier ni la vendre « suivie ».
/// Elle écrit désormais l'article ET son conditionnement dans la carte locale
/// ([creerBoissonProvider] -> `BoissonsApi.enregistrer` -> `CatalogueDao`,
/// création mise en file avec les deux).
///
/// ÉCART DÉLIBÉRÉ — `pwa/carte/corps.blade.php` l.752-764 et l.762.
/// La vue : la création ne pose que l'article ; le conditionnement « se règle
/// ensuite par Lier au stock » (`champ_boisson_article_aide`, rendue telle
/// quelle ci-dessous).
/// Ici : un champ « Combien de « … » dans une unité de stock ? » (celui de la
/// modale « Lier au stock ») suit l'article, obligatoire.
/// Raison (demande du Product Owner du 26/10/2026) : la boisson doit naître liée
/// ET convertie. Sans conditionnement, le serveur garderait le défaut du schéma
/// (1) et une vente sortirait un casier ENTIER par bouteille ; le stock estimé
/// du poste, lui, ignorerait la ligne (« jamais un 1 inventé »).
///
/// ÉCART DÉLIBÉRÉ — `pwa/carte/corps.blade.php` l.770.
/// La vue : « Créer la boisson » est toujours offert, et c'est la validation
/// serveur qui refuse.
/// Ici : il est offert lui aussi — mais les champs sont vérifiés AVANT
/// l'écriture, et le refus s'affiche sous le champ en cause.
/// Raison : il n'y a plus d'aller-retour au bout duquel apprendre qu'un champ
/// est vide, et le catalogue local refuse en plus un libellé déjà pris —
/// deux articles de même nom mettent deux entrées au comptoir.
///
/// ÉCART DÉLIBÉRÉ — `pwa/carte/corps.blade.php` l.725.
/// La vue : les erreurs viennent de la validation Livewire, au retour.
/// Ici : elles viennent du catalogue local, sans réseau ni attente.
Future<bool?> ouvrirModaleNouvelleBoisson(BuildContext context) =>
    showDialog<bool>(
      context: context,
      // Fermeture au voile — Article 4.6 ; l'échappement est branché par la
      // coquille.
      barrierDismissible: true,
      barrierColor: AppColors.voileModale,
      builder: (_) => const _ModaleNouvelleBoisson(),
    );

/// Les messages de la modale — un seul endroit, pour que les cas d'essai et
/// l'écran ne puissent pas diverger.
abstract final class TextesNouvelleBoisson {
  // Les mots de la vue — `lang/fr/carte_pwa.php` l.219-229.
  static const String bouton = 'Nouvelle boisson';
  static const String titre = 'Nouvelle boisson';
  static const String sousTitre =
      'La boisson entre à la carte du bar et devient vendable au comptoir.';
  static const String champLibelle = 'Libellé';
  static const String champCategorie = 'Catégorie';
  static const String champPrix = 'Prix de vente (FCFA)';
  static const String champArticle = 'Article de stock';
  static const String inviteArticle = 'Rechercher un article…';
  // Sur UNE ligne : le comparateur recolle les littéraux de même guillemet
  // seulement, et cette phrase porte des apostrophes droites (celles de la
  // vue) — la couper mêlerait `"` et `'`, et elle ne serait plus reconnue.
  static const String aideArticle =
      "L'article de stock est obligatoire : c'est lui que chaque vente décrémente. Le conditionnement (un casier de 24 ?) se règle ensuite par « Lier au stock ».";
  static const String annuler = 'Annuler';
  static const String confirmer = 'Créer la boisson';

  /// `carte_pwa.commun.toast_boisson_creee`.
  static String creee(String libelle) => '« $libelle » est à la carte du bar.';

  /// Le nom de la boisson dans la question du conditionnement, tant que le
  /// libellé n'est pas saisi.
  static const String cetteBoisson = 'cette boisson';

  static const String libelleManquant = 'Le libellé est obligatoire.';
  static const String prixManquant = 'Le prix de vente est obligatoire.';
}

class _ModaleNouvelleBoisson extends ConsumerStatefulWidget {
  const _ModaleNouvelleBoisson();

  @override
  ConsumerState<_ModaleNouvelleBoisson> createState() =>
      _ModaleNouvelleBoissonState();
}

class _ModaleNouvelleBoissonState
    extends ConsumerState<_ModaleNouvelleBoisson> {
  final _libelle = TextEditingController();
  final _prix = TextEditingController();

  // `ouvrirCreationBoisson()` : la première catégorie du registre fermé.
  CategorieBoisson _categorie = CategorieBoisson.values.first;

  final _conversion = TextEditingController();
  String? _articleId;

  bool _envoi = false;
  String? _refus;
  Map<String, String> _parChamp = const {};

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
      cle: const Key('modale-nouvelle-boisson'),
      titre: TextesNouvelleBoisson.titre,
      sousTitre: TextesNouvelleBoisson.sousTitre,
      largeur: AppLayout.modaleNouvelleBoisson,
      refus: _refus,
      cleRefus: const Key('nouvelle-boisson-refus'),
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // --------------------------------------------- Libellé (l.727-732)
          const EtiquetteChampRestaurant(
            texte: TextesNouvelleBoisson.champLibelle,
            obligatoire: true,
          ),
          TextField(
            key: const Key('nouvelle-boisson-libelle'),
            controller: _libelle,
            // Le libellé nomme la boisson dans la question du conditionnement.
            onChanged: (_) => setState(() {}),
            style: TextesModaleRestaurant.corps,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              errorText: _parChamp['libelle'],
              errorMaxLines: 4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // ---------------- Catégorie et Prix, `grid grid-cols-2` (l.734-750)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const EtiquetteChampRestaurant(
                      texte: TextesNouvelleBoisson.champCategorie,
                      obligatoire: true,
                    ),
                    DropdownButtonFormField<CategorieBoisson>(
                      key: const Key('nouvelle-boisson-categorie'),
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
                      onChanged: (c) {
                        if (c != null) setState(() => _categorie = c);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const EtiquetteChampRestaurant(
                      texte: TextesNouvelleBoisson.champPrix,
                      obligatoire: true,
                    ),
                    TextField(
                      key: const Key('nouvelle-boisson-prix'),
                      controller: _prix,
                      // `type="number" step="1" min="0"` (l.746).
                      keyboardType: TextInputType.number,
                      style: TextesModaleRestaurant.corps,
                      decoration: InputDecoration(
                        isDense: true,
                        border: const OutlineInputBorder(),
                        errorText: _parChamp['prix_vente'],
                        errorMaxLines: 3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // ------------------------------------ Article de stock (l.752-764)
          const EtiquetteChampRestaurant(
            texte: TextesNouvelleBoisson.champArticle,
            obligatoire: true,
          ),
          SelecteurArticleStock(
            prefixeCle: 'nouvelle-boisson-article',
            invite: TextesNouvelleBoisson.inviteArticle,
            aucunArticle: TextesLienStock.aucunArticle,
            articleId: _articleId,
            erreur: _parChamp['article_id'],
            onChoisi: (a) => setState(() {
              _articleId = a?.id;
              _parChamp = const {};
            }),
          ),
          const SizedBox(height: AppSpacing.xxs),
          const Text(
            TextesNouvelleBoisson.aideArticle,
            key: Key('nouvelle-boisson-aide-article'),
            style: TextesModaleRestaurant.aide,
          ),
          const SizedBox(height: AppSpacing.sm),

          // Le conditionnement — AJOUT du poste (voir l'écart en tête de
          // fichier), aux mots de la modale « Lier au stock ».
          EtiquetteChampRestaurant(
            texte: TextesLienStock.champConversion(
              _libelle.text.trim().isEmpty
                  ? TextesNouvelleBoisson.cetteBoisson
                  : _libelle.text.trim(),
            ),
            obligatoire: true,
          ),
          TextField(
            key: const Key('nouvelle-boisson-conversion'),
            controller: _conversion,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextesModaleRestaurant.corps,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              errorText: _parChamp['unites_vendables_par_unite_stock'],
              errorMaxLines: 4,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('nouvelle-boisson-annuler'),
          onPressed: _envoi ? null : () => Navigator.of(context).pop(false),
          child: const Text(
            TextesNouvelleBoisson.annuler,
            style: TextesModaleRestaurant.bouton,
          ),
        ),
        FilledButton(
          key: const Key('nouvelle-boisson-confirmer'),
          onPressed: _envoi ? null : _creer,
          child: const Text(
            TextesNouvelleBoisson.confirmer,
            style: TextesModaleRestaurant.bouton,
          ),
        ),
      ],
    );
  }

  Future<void> _creer() async {
    final libelle = _libelle.text.trim();
    final prix = _prix.text.trim();

    // Les deux champs que l'écran peut juger seul. Le reste — prix illisible,
    // libellé trop long, libellé déjà pris — est rendu par le catalogue, qui
    // est le seul à connaître ce qui s'y trouve déjà.
    final manquants = <String, String>{
      if (libelle.isEmpty) 'libelle': TextesNouvelleBoisson.libelleManquant,
      if (prix.isEmpty) 'prix_vente': TextesNouvelleBoisson.prixManquant,
      // `bar.validation.article_obligatoire` : la vue exige l'article, et le
      // serveur rejetterait la boisson sans lui.
      if (_articleId == null)
        'article_id': TextesCatalogueLocal.articleObligatoire,
      // Le conditionnement est exigé PAR LA MODALE (l'API l'admet absent, comme
      // le service du serveur) : sans lui une vente sortirait un casier ENTIER.
      if (_articleId != null && _conversion.text.trim().isEmpty)
        'unites_vendables_par_unite_stock':
            TextesCatalogueLocal.conversionRequise(
              libelle.isEmpty ? TextesNouvelleBoisson.cetteBoisson : libelle,
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

    final resultat = await ref.read(creerBoissonProvider)(
      SaisieBoisson(
        libelle: libelle,
        categorie: _categorie,
        prixVente: prix,
        articleId: _articleId ?? '',
        unitesVendablesParUniteStock: _conversion.text,
      ),
    );
    if (!mounted) return;

    switch (resultat) {
      case BarRecu<Boisson>(:final donnees):
        final messager = ScaffoldMessenger.of(context);
        Navigator.of(context).pop(true);
        messager.showSnackBar(
          SnackBar(
            content: Text(
              TextesNouvelleBoisson.creee(donnees.libelle),
              key: const Key('nouvelle-boisson-creee'),
            ),
          ),
        );
      case BarRefuse<Boisson>(:final motif, :final erreurs):
        setState(() {
          _envoi = false;
          _refus = motif;
          _parChamp = erreurs;
        });
      case BarInjoignable<Boisson>():
        // Inatteignable : l'écriture est locale. Le cas reste écrit parce que
        // le registre est FERMÉ — le jour où une issue s'ajoute, c'est ici
        // que le compilateur l'exigera.
        setState(() => _envoi = false);
    }
  }
}
