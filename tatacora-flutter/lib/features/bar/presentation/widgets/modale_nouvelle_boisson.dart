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
/// PREMIÈRE du registre fermé, comme `ouvrirCreationBoisson()` le fait.
///
/// ## Trois écarts, tous nommés
///
/// ÉCART DÉLIBÉRÉ — `pwa/carte/corps.blade.php` l.752-764.
/// La vue : un sélecteur d'article de stock OBLIGATOIRE, alimenté par une
/// recherche serveur, et une création refusée sans lui (`exists:articles,id`).
/// Ici : **aucun sélecteur**. `articles_local` est délibérément vide (PA-134) —
/// le stock était calculé par le serveur, et aucun référentiel d'articles n'est
/// répliqué sur ce poste. La boisson naît donc **sans lien de stock**, et le
/// bloc DIT lequel des deux cas s'applique.
/// Raison : exiger un article rendrait la création impossible, c'est-à-dire
/// laisserait le point de vente sans rien à vendre — le défaut même que ce lot
/// referme. Un sélecteur vide, lui, aurait été un champ qui ne peut rien
/// proposer et refuse tout (Article 6).
///
/// ÉCART DÉLIBÉRÉ — `pwa/carte/corps.blade.php` l.770.
/// La vue : « Créer la boisson » est toujours offert, et c'est la validation
/// serveur qui refuse.
/// Ici : il est offert lui aussi — mais les trois champs sont vérifiés AVANT
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

  // La phrase de la vue pour une recherche sans résultat — celle de la modale
  // « Lier au stock », qui propose la même liste d'articles. Conservée : elle
  // redeviendra la phrase de ce bloc le jour où un référentiel local existera.
  static const String aucunResultat =
      'Aucun article en suivi permanent ne correspond à cette recherche.';

  /// Ce que le bloc « Article de stock » dit à la place du sélecteur.
  ///
  /// L'aide de la vue, juste au-dessus, annonce un article OBLIGATOIRE : sans
  /// cette phrase, l'utilisateur chercherait un champ absent et croirait
  /// l'écran cassé. Elle dit donc les deux choses qui comptent — pourquoi il
  /// n'y a rien à choisir, et ce qui en découle à la vente.
  static const String sansReferentielLocal =
      'Aucun article de stock n’est tenu sur ce poste : il n’y a donc rien à '
      'rattacher, et le champ ci-dessus n’a pas de liste. La boisson entre à '
      'la carte SANS lien de stock — elle est vendable immédiatement, mais sa '
      'vente ne décrémentera aucun casier, et la carte l’affichera « non '
      'suivi ». Le rapprochement se fait sur le poste qui tient les stocks.';

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

  bool _envoi = false;
  String? _refus;
  Map<String, String> _parChamp = const {};

  @override
  void dispose() {
    _libelle.dispose();
    _prix.dispose();
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
          //
          // La place du bloc est celle de la vue ; son contenu dit pourquoi il
          // n'y a rien à choisir ici — voir l'écart en tête de fichier.
          const EtiquetteChampRestaurant(
            texte: TextesNouvelleBoisson.champArticle,
          ),
          const SizedBox(height: AppSpacing.xxs),
          const Text(
            TextesNouvelleBoisson.aideArticle,
            key: Key('nouvelle-boisson-aide-article'),
            style: TextesModaleRestaurant.aide,
          ),
          const SizedBox(height: AppSpacing.xs),
          const _Avertissement(
            cle: Key('nouvelle-boisson-sans-referentiel'),
            texte: TextesNouvelleBoisson.sansReferentielLocal,
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
      SaisieBoisson(libelle: libelle, categorie: _categorie, prixVente: prix),
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

/// Ce que la modale dit du bloc d'article qu'elle ne peut pas offrir.
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
