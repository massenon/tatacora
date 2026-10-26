// Vue Blade maîtresse (PA-183) : pwa/restaurant/restauration.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/cle_comparaison.dart';
import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/restaurant_api.dart';
import '../../domain/entities/plat.dart';
import '../../domain/messages_restaurant.dart';
import '../providers_restaurant.dart';
import 'coquille_modale_restaurant.dart';
import 'coquille_restaurant.dart';
import 'textes_modale_restaurant.dart';

/// La modale du formulaire de fiche technique — création ou composition d'une
/// fiche existante (EF-M4-02, PA-23).
///
/// @see EF-M4-02 Fiches techniques (ingrédients, quantités, coût matière)
/// @see RG-05 Sortie de stock automatique — c'est la composition qui la rend
///   possible
///
/// ## Des articles de stock RÉELS, jamais un texte libre
///
/// Chaque ligne désigne un article du référentiel du stock (M6) et la quantité
/// consommée pour UNE portion. Le maître propose ici un champ de texte
/// « Ingrédients principaux » : il ne permettrait aucune sortie de stock, et la
/// fiche ne servirait à rien (PA-23). Le sélecteur ne propose que ce que le
/// stock de ce poste connaît ; sur un poste sans article, il le DIT et renvoie à
/// l'écran des stocks, au lieu d'offrir un champ libre.
///
/// ## Le coût matière n'est PAS un champ
///
/// Il se calcule de la composition et du coût moyen pondéré de chaque article.
/// Ouvert sur une fiche existante, le formulaire l'affiche en LECTURE SEULE et
/// dans ses trois états (un montant, « incomplet » qui nomme les articles non
/// valorisés, « non calculable » pour une composition vide) : il dit ce que la
/// composition valait à l'ouverture et ne suit pas la frappe — un chiffre qui
/// bougerait au clavier serait un champ déguisé.
///
/// ## La composition est REMPLACÉE, jamais fusionnée
///
/// Ce que l'écran affiche EST la fiche après enregistrement : une ligne retirée
/// disparaît réellement de la nomenclature. Les lignes entièrement vides sont
/// ignorées (un « ajouter un ingrédient » abandonné ne refuse pas une fiche par
/// ailleurs correcte).
///
/// Rend la fiche enregistrée (`null` si la modale est fermée sans enregistrer).
Future<Recette?> ouvrirModaleFiche(BuildContext context, {Recette? fiche}) =>
    showDialog<Recette>(
      context: context,
      // Fermeture au voile — Article 4.6.
      barrierDismissible: true,
      barrierColor: AppColors.voileModale,
      builder: (_) => _ModaleFiche(fiche: fiche),
    );

/// Une ligne de composition en cours de saisie. La quantité reste un TEXTE tant
/// qu'elle n'est pas validée : la troisième décimale se refuse, elle ne se
/// tronque pas.
final class _Ligne {
  _Ligne({this.articleId, String quantite = ''})
    : quantite = TextEditingController(text: quantite);

  String? articleId;
  final TextEditingController quantite;
}

class _ModaleFiche extends ConsumerStatefulWidget {
  const _ModaleFiche({this.fiche});

  final Recette? fiche;

  @override
  ConsumerState<_ModaleFiche> createState() => _ModaleFicheState();
}

class _ModaleFicheState extends ConsumerState<_ModaleFiche> {
  late final TextEditingController _libelle = TextEditingController(
    text: widget.fiche?.libelle ?? '',
  );
  final TextEditingController _recherche = TextEditingController();

  /// Une ligne vierge offerte à la création : un sous-formulaire vide ne
  /// dirait pas qu'on peut en ajouter. Sur une fiche existante, la composition
  /// est lue de la base (voir [initState]).
  final List<_Ligne> _lignes = [];

  bool _pret = false;
  bool _envoi = false;
  String? _refus;
  Map<String, String> _parChamp = const {};

  bool get _modification => widget.fiche != null;

  @override
  void initState() {
    super.initState();
    final fiche = widget.fiche;
    if (fiche == null) {
      _lignes.add(_Ligne());
      _pret = true;
    } else {
      _charger(fiche.id);
    }
  }

  /// La composition d'une fiche existante, relue à trois décimales (« 0.400 »,
  /// jamais « 0.4 ») : l'enregistrement suivant réécrit la quantité qui est
  /// AFFICHÉE.
  Future<void> _charger(String id) async {
    final lignes = await ref
        .read(restaurantApiProvider)
        .compositionEditable(id);
    if (!mounted) return;
    setState(() {
      _lignes.addAll([
        for (final l
            in lignes ?? const <({String articleId, String quantite})>[])
          _Ligne(articleId: l.articleId, quantite: l.quantite),
      ]);
      // Une fiche déjà vide reçoit UNE ligne vierge — sans elle, l'écran
      // n'offrirait aucun champ à remplir sur la fiche même qu'on ouvre pour
      // la remplir.
      if (_lignes.isEmpty) _lignes.add(_Ligne());
      _pret = true;
    });
  }

  @override
  void dispose() {
    _libelle.dispose();
    _recherche.dispose();
    for (final l in _lignes) {
      l.quantite.dispose();
    }
    super.dispose();
  }

  Future<void> _enregistrer() async {
    setState(() {
      _envoi = true;
      _refus = null;
      _parChamp = const {};
    });

    final messager = ScaffoldMessenger.of(context);
    final navigateur = Navigator.of(context);

    final resultat = await ref
        .read(restaurantApiProvider)
        .enregistrerRecette(
          SaisieFiche(
            id: widget.fiche?.id,
            libelle: _libelle.text,
            lignes: [
              for (final l in _lignes)
                LigneSaisieComposition(
                  articleId: l.articleId ?? '',
                  quantite: l.quantite.text,
                ),
            ],
          ),
        );

    if (!mounted) return;

    switch (resultat) {
      case RestaurantRecu<Recette>(:final donnees):
        invaliderRestaurant(ref);
        // Le message REMPLACE le précédent : les files d'attente de messages
        // feraient lire « menu créé » quatre secondes après avoir créé la fiche.
        messager
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                MessagesRestaurant.ficheEnregistree(
                  libelle: donnees.libelle,
                  creation: !_modification,
                  vide: donnees.compositionVide,
                  incomplet: donnees.coutMatiereIncomplet,
                  articlesSansCout: donnees.articlesSansCout,
                  cout: formaterMontantDecimal(
                    donnees.coutMatiere,
                    suffixe: 'FCFA',
                  ),
                ),
                key: const Key('toast-fiche-enregistree'),
              ),
            ),
          );
        navigateur.pop(donnees);
      case RestaurantRefuse<Recette>(:final motif, :final erreurs):
        setState(() {
          _envoi = false;
          _refus = motif;
          _parChamp = erreurs;
        });
      case RestaurantInjoignable<Recette>():
        // Jamais produite : une base locale n'est pas hors connexion.
        setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final articles = ref.watch(articlesFichesProvider);

    return CoquilleModaleRestaurant(
      cle: const Key('modale-fiche'),
      // `recette_form_titre` / `recette_form_titre_modification`.
      titre: _modification
          ? 'Modifier la fiche technique'
          : 'Nouvelle fiche technique',
      sousTitre: _modification
          // `recette_form_sous_titre_modification`.
          ? 'Composition, libellé et coût matière de la fiche.'
          // `recette_form_sous_titre`.
          : 'La nomenclature qui fait décrémenter le stock à chaque vente.',
      largeur: AppLayout.modaleFiche,
      // Un refus par champ s'affiche SOUS son champ ; seul un refus d'ensemble
      // (aucun champ en cause) occupe le bandeau.
      refus: _parChamp.isEmpty ? _refus : null,
      cleRefus: const Key('modale-fiche-refus'),
      corps: !_pret
          ? const LinearProgressIndicator()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const EtiquetteChampRestaurant(
                  texte: 'Nom de la fiche',
                  obligatoire: true,
                ),
                TextField(
                  key: const Key('modale-fiche-libelle'),
                  controller: _libelle,
                  style: TextesModaleRestaurant.etiquette,
                  decoration: InputDecoration(
                    hintText: 'Ex. Recette Poulet DG',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    errorText: _parChamp['libelle'],
                  ),
                ),
                if (_modification && widget.fiche!.compositionProvisoire) ...[
                  const SizedBox(height: AppSpacing.md),
                  // `recette_bandeau_provisoire` — la marque « composition
                  // provisoire » de la fiche (voir `Recette.compositionProvisoire`).
                  Container(
                    key: const Key('modale-fiche-bandeau-provisoire'),
                    padding: const EdgeInsets.all(AppSpacing.xsPlus),
                    decoration: BoxDecoration(
                      color: PaletteMaitre.ambre50,
                      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
                      border: Border.all(color: PaletteMaitre.ambre200),
                    ),
                    child: Text(
                      "Composition PROVISOIRE : ces quantités ont été posées pour débloquer le service, personne ne les a pesées. Corrigez-les et enregistrez — la marque tombera d'elle-même.",
                      style: TextesModaleRestaurant.aide.copyWith(
                        color: PaletteMaitre.ambre900,
                      ),
                    ),
                  ),
                ],
                if (_modification) ...[
                  const SizedBox(height: AppSpacing.md),
                  _CoutEnregistre(fiche: widget.fiche!),
                ],
                const SizedBox(height: AppSpacing.md),
                _enTeteComposition(),
                const SizedBox(height: AppSpacing.unit),
                const Text(
                  // `recette_composition_aide`, au mot.
                  'Chaque ingrédient est un article de stock réel, avec la quantité consommée pour UNE portion.',
                  style: TextesModaleRestaurant.aide,
                ),
                const SizedBox(height: AppSpacing.xs),
                TextField(
                  key: const Key('modale-fiche-recherche'),
                  controller: _recherche,
                  onChanged: (_) => setState(() {}),
                  style: TextesModaleRestaurant.etiquette,
                  decoration: const InputDecoration(
                    hintText: 'Rechercher un article de stock...',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                ..._composition(articles),
              ],
            ),
      actions: [
        TextButton(
          key: const Key('modale-fiche-annuler'),
          onPressed: _envoi ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler', style: TextesModaleRestaurant.bouton),
        ),
        FilledButton(
          key: const Key('modale-fiche-enregistrer'),
          onPressed: _envoi || !_pret ? null : _enregistrer,
          child: const Text(
            'Enregistrer',
            style: TextesModaleRestaurant.bouton,
          ),
        ),
      ],
    );
  }

  Widget _enTeteComposition() {
    return Row(
      children: [
        const Expanded(
          child: Text('Composition', style: TextesModaleRestaurant.etiquette),
        ),
        OutlinedButton(
          key: const Key('modale-fiche-ajouter'),
          onPressed: () => setState(() => _lignes.add(_Ligne())),
          child: const Text(
            // `recette_bouton_ajouter_ingredient`.
            'Ajouter un ingrédient',
            style: TextesModaleRestaurant.aide,
          ),
        ),
      ],
    );
  }

  /// Les lignes de composition, ou la raison pour laquelle il n'y en a pas.
  List<Widget> _composition(AsyncValue<List<ArticleChoix>?> articles) {
    final choix = switch (articles) {
      AsyncData(value: final v) => v,
      _ => null,
    };

    if (choix == null) {
      return [
        if (articles is AsyncLoading)
          const LinearProgressIndicator()
        else
          const Text(
            // Le référentiel du stock n'a pas pu être lu (droit manquant) :
            // ce n'est pas « il n'y a aucun article ».
            'Le référentiel des articles de stock n’a pas pu être lu. Ce '
            'n’est pas « il n’y en a aucun » : on ne sait pas.',
            key: Key('modale-fiche-articles-inconnus'),
            style: TextesModaleRestaurant.aide,
          ),
      ];
    }

    final terme = cleDeComparaison(_recherche.text.trim());
    final choisis = {
      for (final l in _lignes)
        if (l.articleId != null) l.articleId!,
    };
    // Les articles DÉJÀ CHOISIS restent proposés quel que soit le terme : les
    // filtrer ferait disparaître de son propre sélecteur une ligne déjà saisie.
    final proposes = [
      for (final a in choix)
        if (terme.isEmpty ||
            choisis.contains(a.id) ||
            cleDeComparaison(a.libelle).contains(terme))
          a,
    ];

    return [
      if (choix.isEmpty)
        const Text(
          MessagesRestaurant.aucunArticleDisponible,
          key: Key('modale-fiche-aucun-article-stock'),
          style: TextesModaleRestaurant.aide,
        )
      else if (proposes.isEmpty)
        const Padding(
          padding: EdgeInsets.only(bottom: AppSpacing.xs),
          child: Text(
            MessagesRestaurant.recetteAucunArticle,
            key: Key('modale-fiche-aucun-article'),
            style: TextesModaleRestaurant.aide,
          ),
        ),
      if (_lignes.isEmpty)
        const Text(
          MessagesRestaurant.recetteSansIngredient,
          key: Key('modale-fiche-sans-ingredient'),
          style: TextesModaleRestaurant.aide,
        ),
      for (var i = 0; i < _lignes.length; i++)
        _LigneComposition(
          rang: i,
          ligne: _lignes[i],
          articles: proposes,
          erreurArticle: _parChamp['lignes.$i.article_id'],
          erreurQuantite: _parChamp['lignes.$i.quantite_unitaire'],
          onArticle: (id) => setState(() => _lignes[i].articleId = id),
          onRetirer: () => setState(() {
            _lignes.removeAt(i).quantite.dispose();
          }),
        ),
    ];
  }
}

/// Le coût matière ENREGISTRÉ d'une fiche, en lecture seule et dans ses trois
/// états. Il dit ce que la composition valait à l'ouverture.
class _CoutEnregistre extends StatelessWidget {
  const _CoutEnregistre({required this.fiche});

  final Recette fiche;

  @override
  Widget build(BuildContext context) {
    final String texte;
    Color couleur = Ardoise.c400;
    String? detail;

    if (fiche.compositionVide || fiche.nbIngredients == 0) {
      // `fiches_cout_vide`.
      texte = 'Non calculable';
    } else if (fiche.coutMatiereIncomplet) {
      // `fiches_cout_incomplet` et son infobulle.
      texte = 'Incomplet';
      couleur = PaletteMaitre.ambre600;
      detail =
          'Sans coût moyen pondéré (jamais réceptionnés) : '
          '${fiche.articlesSansCout.join(', ')}';
    } else {
      texte =
          formaterMontantDecimal(fiche.coutMatiere, suffixe: 'FCFA') ??
          CarteIndicateurRestaurant.absent;
      couleur = AppColors.gold;
    }

    return Container(
      key: const Key('modale-fiche-cout'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xsPlus,
      ),
      decoration: BoxDecoration(
        color: Ardoise.c50,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        border: Border.all(color: Ardoise.c200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            // `recette_cout_actuel`, en capitales comme la vue (`uppercase`).
            'Coût matière enregistré'.toUpperCase(),
            style: TextesModaleRestaurant.aide.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            texte,
            key: const Key('modale-fiche-cout-valeur'),
            style: TextesModaleRestaurant.corps.copyWith(
              fontWeight: FontWeight.bold,
              color: couleur,
            ),
          ),
          if (detail != null)
            Text(
              detail,
              key: const Key('modale-fiche-cout-detail'),
              style: TextesModaleRestaurant.aide.copyWith(
                color: PaletteMaitre.ambre700,
              ),
            ),
          const Text(
            // `recette_cout_actuel_aide`.
            "Calculé depuis la composition ci-dessous et le coût moyen pondéré de chaque article. Jamais saisi — il se recalcule à l'enregistrement.",
            style: TextesModaleRestaurant.aide,
          ),
        ],
      ),
    );
  }
}

class _LigneComposition extends StatelessWidget {
  const _LigneComposition({
    required this.rang,
    required this.ligne,
    required this.articles,
    required this.erreurArticle,
    required this.erreurQuantite,
    required this.onArticle,
    required this.onRetirer,
  });

  final int rang;
  final _Ligne ligne;
  final List<ArticleChoix> articles;
  final String? erreurArticle;
  final String? erreurQuantite;
  final ValueChanged<String?> onArticle;
  final VoidCallback onRetirer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          SizedBox(
            width: AppLayout.articleLigneFiche,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // `recette_label_article`.
                Text('Article de stock', style: TextesModaleRestaurant.aide),
                DropdownButtonFormField<String>(
                  key: Key('modale-fiche-article-$rang'),
                  initialValue: articles.any((a) => a.id == ligne.articleId)
                      ? ligne.articleId
                      : null,
                  isExpanded: true,
                  style: TextesModaleRestaurant.etiquette,
                  decoration: InputDecoration(
                    // `recette_invite_article`.
                    hintText: 'Choisir un article',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    errorText: erreurArticle,
                    errorMaxLines: 5,
                  ),
                  items: [
                    for (final a in articles)
                      DropdownMenuItem(
                        value: a.id,
                        child: Text(
                          '${a.libelle} — ${a.uniteMesure}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: onArticle,
                ),
              ],
            ),
          ),
          SizedBox(
            width: AppLayout.quantiteLigneFiche,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // `recette_label_quantite`.
                Text(
                  'Quantité par portion',
                  style: TextesModaleRestaurant.aide,
                ),
                TextField(
                  key: Key('modale-fiche-quantite-$rang'),
                  controller: ligne.quantite,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: TextesModaleRestaurant.etiquette,
                  decoration: InputDecoration(
                    isDense: true,
                    border: const OutlineInputBorder(),
                    errorText: erreurQuantite,
                    errorMaxLines: 5,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            key: Key('modale-fiche-retirer-$rang'),
            onPressed: onRetirer,
            child: const Text(
              // `recette_bouton_retirer_ingredient`.
              'Retirer cette ligne',
              style: TextesModaleRestaurant.aide,
            ),
          ),
        ],
      ),
    );
  }
}
