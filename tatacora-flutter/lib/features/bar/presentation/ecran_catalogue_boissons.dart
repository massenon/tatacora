import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/formats.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
// Le maître ne possède qu'UN moteur CRUD pour tout le dépôt — `crud-ui.js` et
// `crud-engine.js` —, et `m5-bar.html` le configure exactement comme
// `m4-restauration.html`. Son portage Flutter vit dans `features/restaurant/`
// parce que M4 a été livré le premier ; le réécrire ici en donnerait deux
// copies, et « deux listes décrivant la même chose divergeront — ce n'est
// qu'une question de temps » (Article 10). C'est la même décision que
// `vue_couverture_bar.dart` a prise pour le gabarit de tableau (PA-150).
//
// ⚠ Le NOM de ces briques dit « Restaurant » alors qu'elles portent le moteur
// CRUD de toutes les pages qui l'incluent. Les renommer touche les sept
// fichiers de M4 sans changer un pixel : l'arbitrage est ouvert, il n'est pas
// tranché ici en silence.
import '../../restaurant/presentation/widgets/coquille_restaurant.dart';
import '../../restaurant/presentation/widgets/tableau_restaurant.dart';
import '../data/boissons_api.dart';
import '../domain/entities/boisson.dart';
import 'providers_catalogue_boissons.dart';
import 'widgets/modale_boisson.dart';
import 'widgets/modale_detail_boisson.dart';
import 'widgets/modale_export_boissons.dart';

/// L'écran **Bar & POS Boissons** — `prototype_v2/pages/m5-bar.html`.
///
/// @see EF-M5-02 Carte des boissons
/// @see RG-05 Le lien `article_id` rend la décrémentation possible
///
/// C'est le **catalogue des boissons**, rendu par le moteur CRUD générique du
/// maître (`crud-ui.js` + `crud-engine.js`) à partir de la configuration posée
/// l.72-206 : barre d'outils, tableau paginé, cinq modales.
///
/// ## Le maître déclare cette page REMPLACÉE, et la page qui la remplace ne
/// sait pas créer une boisson
///
/// `m5-bar.html` porte en tête son propre bandeau (l.19-25) : « **Écran
/// remplacé.** Cette page reste consultable comme maquette validée par le
/// client, mais elle n'est plus au menu : la version fonctionnelle est
/// [Carte du bar] ». Même forme que `m3-crm.html` et `m4-restaurant.html`, que
/// ce dépôt ne porte pas.
///
/// **Le cas est pourtant différent, et il a été vérifié plutôt que déduit du
/// bandeau.** `m5-bar-carte.html` a deux onglets — « Carte du jour » et
/// « Couverture du stock » — et **aucun contrôle de création ni de
/// modification** (relu l.30-54 : ni bouton d'ajout, ni modale de formulaire).
/// La page annoncée comme remplaçante ne couvre donc pas la fonction de
/// celle-ci. Or :
///
///  - `cartes_boisson` est **vide sur une installation neuve** ;
///  - `POST /bar/boissons` et `PUT /bar/boissons/{id}` existent depuis
///    toujours et **n'avaient aucun client** ;
///  - sans point d'entrée, le catalogue ne pourrait jamais être renseigné, et
///    le point de vente n'aurait rien à vendre — la forme exacte de PA-129,
///    trouvée trois fois déjà dans ce dépôt.
///
/// ÉCART DÉLIBÉRÉ — `prototype_v2/pages/m5-bar.html` l.19-25.
/// Le maître : déclare la page hors menu et renvoie vers `m5-bar-carte.html`.
/// Ici : la page est portée, à sa propre route, atteinte depuis la Carte du
/// bar. **Le bandeau est rendu tel quel**, son lien compris — le retirer
/// masquerait la décision du commanditaire.
/// Raison : c'est le SEUL endroit du maître où une boisson se crée, et la page
/// désignée comme remplaçante ne le fait pas. L'incohérence est **signalée**,
/// pas tranchée seule (doctrine §2) : c'est au Product Owner de dire si cette
/// page doit revenir au menu ou si la Carte du bar doit recevoir un formulaire.
///
/// ## ⚠ Cette raison est PÉRIMÉE depuis le 11/09/2026 (PA-144)
///
/// Le Product Owner a tranché le 03/09/2026, du côté de la vue Blade — seul
/// maître depuis PA-183 : la Carte du bar a reçu son formulaire (corps
/// partagé `carte/corps` des vues PWA, l.117-120 et l.717-774 — chemin écrit
/// sans son préfixe à dessein : cité en entier, il ferait passer cet écran
/// pour un porteur de vue aux yeux de `t-blade-flutter.js`, et effacerait le
/// signalement d'ajout que le Product Owner doit trancher). Il est porté le
/// 11/09/2026 (`modale_nouvelle_boisson.dart`). Une boisson se crée donc
/// depuis la Carte du bar, et cet écran n'est plus le seul point d'entrée.
///
/// Ce qu'il porte encore seul : la **modification** d'une boisson, son détail
/// et l'export du catalogue. La vue n'a aucun écran de catalogue du bar —
/// `t-blade-flutter.js` le signale comme ajout. Le retirer ou le garder est la
/// décision du Product Owner, pas celle d'un lot de portage.
///
/// ## Ce que le formulaire du maître ferait, envoyé tel quel
///
/// Le détail est en tête de [ouvrirModaleBoisson]. En un mot : il serait
/// **refusé en 422** faute d'`article_id`, et son champ « Stock disponible »
/// serait **accepté puis jeté en silence** — aucune règle `prohibited` ne le
/// rejette. Le second cas est le pire des deux : l'utilisateur voit un succès
/// et croit avoir saisi un stock.
///
///  - maitre-refuse:m5-bar.html#modale-suppression
///  - maitre-refuse:m5-bar.html#modale-import
class EcranCatalogueBoissons extends ConsumerWidget {
  const EcranCatalogueBoissons({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultat = ref.watch(boissonsProvider);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        // `max-w-[1440px] mx-auto p-5 lg:p-8` (l.28).
        constraints: const BoxConstraints(maxWidth: AppLayout.maxContentWidth),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.mdPlus),
          children: [
            const _BandeauEcranRemplace(),
            const SizedBox(height: AppSpacing.mdPlus),
            const _EnTete(),
            const SizedBox(height: AppSpacing.mdPlus),
            _BarreOutils(
              resultat: switch (resultat) {
                AsyncData(value: final v) => v,
                _ => null,
              },
            ),
            const SizedBox(height: AppSpacing.md),
            resultat.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => NoteRestaurant(
                cle: const Key('boissons-erreur'),
                texte: '$e',
                icone: Icons.error_outline,
              ),
              data: (r) => switch (r) {
                BarRecu<PageBoissons>(:final donnees) => _Tableau(
                  page: donnees,
                ),
                BarRefuse<PageBoissons>(:final motif) => NoteRestaurant(
                  cle: const Key('boissons-refus'),
                  texte: motif,
                  icone: Icons.lock_outline,
                ),
                BarInjoignable<PageBoissons>() => const NoteRestaurant(
                  cle: Key('boissons-hors-ligne'),
                  texte:
                      'Serveur injoignable. Le catalogue des boissons n’est '
                      'pas répliqué sur ce poste pour cet écran : aucune '
                      'boisson n’est affichée plutôt que celles de la dernière '
                      'consultation, qui ne diraient pas qu’elles datent. La '
                      'Carte du bar, elle, reste consultable hors connexion.',
                ),
              },
            ),
            // Le bloc « Ce que cet écran ne rend pas » qui suivait est RETIRÉ
            // (directive absolue du PO, 14/10/2026) : la page se termine après
            // le tableau ou l'état vide.
          ],
        ),
      ),
    );
  }
}

/// Le bandeau « Écran remplacé » du maître — l.19-25, au mot.
///
/// `background:#FFFBEB;border-bottom:1px solid #FDE68A;padding:10px 20px`,
/// texte `font-size:13px;color:#78350F`. Le lien est **réel** : il navigue
/// vers la Carte du bar (Article 3.3 — « un lien de menu qui ne navigue pas
/// est un défaut »).
class _BandeauEcranRemplace extends StatelessWidget {
  const _BandeauEcranRemplace();

  @override
  Widget build(BuildContext context) {
    return Container(
      // `padding:10px 20px`.
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.mdPlus,
        vertical: AppSpacing.xsPlus,
      ),
      decoration: const BoxDecoration(
        color: PaletteMaitre.ambre50,
        border: Border(bottom: BorderSide(color: PaletteMaitre.ambre200)),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            const TextSpan(
              text: 'Écran remplacé.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const TextSpan(
              text:
                  ' Cette page reste consultable comme maquette validée par le '
                  'client, mais elle n’est plus au menu : la version '
                  'fonctionnelle est ',
            ),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: InkWell(
                key: const Key('boissons-lien-carte'),
                onTap: () => context.go('/bar'),
                child: Text(
                  'Carte du bar',
                  style: TextesRestaurant.corps.copyWith(
                    color: PaletteMaitre.ambre900,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
            const TextSpan(text: '.'),
          ],
        ),
        key: const Key('boissons-bandeau-remplace'),
        style: TextesRestaurant.corps.copyWith(color: PaletteMaitre.ambre900),
      ),
    );
  }
}

/// L'en-tête du maître (l.30-37).
class _EnTete extends StatelessWidget {
  const _EnTete();

  @override
  Widget build(BuildContext context) {
    return const EnTeteRestaurant(
      // Le verre à cocktail du maître (l.33) — `M8 21h8M12 15v6M19 3H5l7 9 7-9z`.
      icone: Icon(
        Icons.local_bar_outlined,
        color: AppColors.navy,
        size: AppLayout.iconeTitrePage,
      ),
      // Le titre du maître (l.34), au mot — esperluette comprise.
      titre: 'Bar & POS Boissons',
      // Le sous-titre du maître (l.36), au mot. Le « < » et le « • » sont les
      // siens ; les reformuler serait un écart (Article 1, interdit 05).
      sousTitre:
          'Point de vente rapide, carte des boissons et déduction automatique '
          'du stock à la vente • Objectif : saisie < 10s',
    );
  }
}

/// La barre d'outils du moteur CRUD — `crud-ui.js` l.16-48.
///
/// Cinq contrôles, dans l'ordre du maître : recherche, filtre de catégorie,
/// « Actualiser », « Importer », « Exporter », « Ajouter boisson ».
class _BarreOutils extends ConsumerStatefulWidget {
  const _BarreOutils({required this.resultat});

  final ResultatBar<PageBoissons>? resultat;

  @override
  ConsumerState<_BarreOutils> createState() => _BarreOutilsState();
}

class _BarreOutilsState extends ConsumerState<_BarreOutils> {
  final _terme = TextEditingController();

  @override
  void dispose() {
    _terme.dispose();
    super.dispose();
  }

  List<Boisson> get _boissonsAffichees {
    final r = widget.resultat;
    return r is BarRecu<PageBoissons> ? r.donnees.elements : const [];
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      // `gap-3` — 12 px.
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: AppLayout.rechercheRestauration,
          child: TextField(
            key: const Key('boissons-recherche'),
            controller: _terme,
            style: TextesRestaurant.corpsCrud,
            decoration: const InputDecoration(
              // L'invite du maître (l.79) — points de suspension en TROIS
              // points, comme il l'écrit.
              hintText: 'Rechercher une boisson...',
              prefixIcon: Icon(Icons.search, size: AppLayout.iconeChamp),
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              ref.read(rechercheBoissonsProvider.notifier).definir(v);
              // `pageActuelle = 1` du maître (`crud-engine.js` l.89).
              ref.read(pageBoissonsProvider.notifier).premiere();
            },
          ),
        ),
        SizedBox(
          width: AppLayout.filtreCarteRestaurant,
          child: DropdownButtonFormField<CategorieBoisson?>(
            key: const Key('boissons-filtre-categorie'),
            initialValue: ref.watch(categorieBoissonsProvider),
            isExpanded: true,
            style: TextesRestaurant.petitCrud,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              // Le libellé de l'option vide EST celui du filtre au maître
              // (l.84) : « Toutes les catégories ».
              const DropdownMenuItem<CategorieBoisson?>(
                child: Text('Toutes les catégories'),
              ),
              for (final c in CategorieBoisson.values)
                DropdownMenuItem<CategorieBoisson?>(
                  value: c,
                  child: Text(c.libelle),
                ),
            ],
            onChanged: (c) {
              ref.read(categorieBoissonsProvider.notifier).definir(c);
              ref.read(pageBoissonsProvider.notifier).premiere();
            },
          ),
        ),
        IconButton(
          key: const Key('boissons-actualiser'),
          // Le `title` du maître (`crud-ui.js` l.25).
          tooltip: 'Actualiser',
          onPressed: () {
            ref.invalidate(boissonsProvider);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                key: Key('boissons-actualise'),
                // Le message du maître (`crud-ui.js` l.148), au mot.
                content: Text('Données actualisées.'),
              ),
            );
          },
          icon: const Icon(Icons.refresh, color: Ardoise.c500),
        ),
        OutlinedButton.icon(
          key: const Key('boissons-importer'),
          // Aucune route n'accepte d'import : le bouton dit pourquoi au lieu
          // d'ouvrir une modale qui n'enregistrerait rien (Article 6).
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              key: Key('boissons-import-refuse'),
              content: Text(
                // Réécrit le 14/10/2026 (directive du PO) : la modale
                // d'import de la vue n'est pas portée, aucune route n'existe.
                'L’import de boissons n’est pas disponible sur ce poste : un '
                'fichier déposé ici ne créerait aucune boisson.',
              ),
            ),
          ),
          icon: const Icon(Icons.upload_outlined, size: AppLayout.iconeChamp),
          label: const Text('Importer', style: TextesRestaurant.petitCrud),
        ),
        OutlinedButton.icon(
          key: const Key('boissons-exporter'),
          onPressed: () => _exporter(context),
          icon: const Icon(Icons.download_outlined, size: AppLayout.iconeChamp),
          label: const Text('Exporter', style: TextesRestaurant.petitCrud),
        ),
        FilledButton.icon(
          key: const Key('boissons-ajouter'),
          onPressed: () => _ajouter(context),
          icon: const Icon(Icons.add, size: AppLayout.iconeChamp),
          // Le libellé du maître (`crud-engine.js` l.117) : « Ajouter » suivi
          // de `entiteLabelSingulier`, qui vaut « boisson » (l.75).
          label: const Text(
            'Ajouter boisson',
            style: TextesRestaurant.petitCrud,
          ),
        ),
      ],
    );
  }

  Future<void> _ajouter(BuildContext context) async {
    final enregistre = await ouvrirModaleBoisson(context);
    if (enregistre == true) ref.invalidate(boissonsProvider);
  }

  Future<void> _exporter(BuildContext context) async {
    final boissons = _boissonsAffichees;
    final filtre = _filtreLisible(ref);

    final confirme = await ouvrirModaleExportBoissons(
      context,
      nombre: boissons.length,
      filtre: filtre,
    );
    if (confirme != true || !context.mounted) return;

    final chemin = await ref.read(exporterBoissonsProvider)(boissons, filtre);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('boissons-export-fait'),
        content: Text('Export écrit : $chemin'),
      ),
    );
  }
}

/// Le filtre courant, en clair — un export DIT son filtre (PA-119).
///
/// **Il porte sur ce qui est AFFICHÉ**, page comprise.
String _filtreLisible(WidgetRef ref) {
  final morceaux = <String>[];
  final terme = ref.read(rechercheBoissonsProvider).trim();
  if (terme.isNotEmpty) morceaux.add('recherche : $terme');
  final categorie = ref.read(categorieBoissonsProvider);
  if (categorie != null) morceaux.add('catégorie : ${categorie.libelle}');
  morceaux.add('page ${ref.read(pageBoissonsProvider)}');

  return morceaux.join(' · ');
}

/// Le tableau et sa pagination — `crud-ui.js` l.62-82.
class _Tableau extends ConsumerWidget {
  const _Tableau({required this.page});

  final PageBoissons page;

  /// Les colonnes du maître (`m5-bar.html` l.89-112), dans son ordre.
  ///
  /// « Prix de vente » est un montant : à DROITE, comme tous les montants
  /// (Article 4.3). « Stock disponible » est un nombre calculé, aligné à
  /// droite pour la même raison.
  static const colonnes = [
    ColonneRestaurant('Boisson'),
    ColonneRestaurant('Catégorie'),
    ColonneRestaurant('Prix de vente', aDroite: true),
    ColonneRestaurant('Stock disponible', aDroite: true),
    ColonneRestaurant('Actions', aDroite: true),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CadreTableauRestaurant(
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (page.avertissement != null)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: EncadreRestaurant(
                cle: const Key('boissons-tranche-serveur'),
                ton: TonEncadre.ambre,
                titre: 'Le décompte porte sur la page reçue.',
                texte: page.avertissement!,
              ),
            ),
          TableauRestaurant(
            gabarit: GabaritTableau.crud,
            colonnes: colonnes,
            vide: const EtatVideCrud(),
            clesLignes: [
              for (final b in page.elements) Key('boissons-ligne-${b.id}'),
            ],
            lignes: [
              for (final b in page.elements)
                [
                  Text(b.libelle, style: TextesRestaurant.corpsCrud),
                  _BadgeCategorie(boisson: b),
                  Text(
                    formaterMontantDecimal(b.prixVente, suffixe: 'FCFA') ??
                        CarteIndicateurRestaurant.absent,
                    style: TextesRestaurant.corpsCrud.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.gold,
                    ),
                  ),
                  _Stock(boisson: b),
                  _Actions(boisson: b),
                ],
            ],
          ),
          _Pagination(page: page),
        ],
      ),
    );
  }
}

/// La pastille de catégorie — `m5-bar.html` l.94-108, aux trois couples de
/// couleurs qu'il déclare.
class _BadgeCategorie extends StatelessWidget {
  const _BadgeCategorie({required this.boisson});

  final Boisson boisson;

  @override
  Widget build(BuildContext context) {
    // Le repli du moteur quand la valeur n'est prévue par aucune couleur —
    // `{bg:'#F3F4F6', txt:'#6B7280'}` (`crud-engine.js` l.216).
    final (fond, texte) = switch (boisson.categorie) {
      // `Locale` : `#E8F5E9` / `#2E7D32` (l.97-100).
      CategorieBoisson.locale => (AppColors.badgeVertFond, AppColors.succes),
      // `Maison` : `#FDF3E0` / `#B8891E` (l.101-104).
      CategorieBoisson.maison => (
        AppColors.reserveGoldFond,
        AppColors.reserveGoldTexte,
      ),
      // `Importée` : `#E8EEFD` / `#1D4ED8` (l.105-108).
      CategorieBoisson.importee => (AppColors.badgeBleuFond, AppColors.info),
      null => (AppColors.badgeGrisFond, AppColors.badgeGrisTexte),
    };

    return PastilleRestaurant(
      cle: Key('boissons-categorie-${boisson.id}'),
      texte: boisson.categorieLibelle ?? CarteIndicateurRestaurant.absent,
      fond: fond,
      couleur: texte,
    );
  }
}

/// La colonne « Stock disponible » — **calculée par le serveur, jamais saisie**.
///
/// Trois états, jamais deux (Article 7, et PA-129 pour le même champ sur la
/// Carte du bar) :
///
///  - un **chiffre**, quand le serveur a su le calculer ;
///  - « — », quand il a rendu `null` : aucun `PointStockage` de type `bar`
///    n'existe, et il ne sait donc pas. Afficher « 0 » se lirait « rupture »,
///    et ferait commander des caisses qu'on a déjà.
///
/// Le troisième état — serveur injoignable — ne se rend pas ici mais à
/// l'échelle de l'écran : sans réseau, aucune ligne n'est affichée du tout.
class _Stock extends StatelessWidget {
  const _Stock({required this.boisson});

  final Boisson boisson;

  @override
  Widget build(BuildContext context) {
    final stock = boisson.stockDisponible;

    if (stock == null) {
      return Tooltip(
        message:
            'Le serveur n’a pas pu calculer ce stock : aucun point de '
            'stockage de type « bar » n’est défini. « — » veut dire « on ne '
            'sait pas », pas « rupture ».',
        child: Text(
          CarteIndicateurRestaurant.absent,
          key: Key('boissons-stock-absent-${boisson.id}'),
          style: TextesRestaurant.corpsCrud.copyWith(color: Ardoise.c400),
        ),
      );
    }

    return Tooltip(
      message: 'Stock calculé, en lecture seule : il ne se saisit pas.',
      // La valeur du serveur, **telle quelle**. Ni arrondi, ni mise en forme :
      // `formaterMontantDecimal` arrondit au franc supérieur au-delà de 50
      // centièmes, ce qui conviendrait à un montant et pas à un stock — 42,6
      // casiers deviendraient 43, et l'écran annoncerait un casier qu'on n'a
      // pas, précisément là où l'on décide de ce qu'on vend.
      child: Text(
        stock,
        key: Key('boissons-stock-${boisson.id}'),
        style: TextesRestaurant.corpsCrud,
      ),
    );
  }
}

/// Les actions de ligne — `crud-engine.js` l.233-246.
///
/// Le maître en pose quatre ; **deux seulement sont rendues**, et ce n'est pas
/// un choix de ce portage : « Dupliquer » et « Supprimer » sont retirées de
/// l'écran par le moteur lui-même tant que `OptionsSysteme` ne les a pas
/// ouvertes, et elles sont fermées par défaut (`options-systeme.js` l.40-45).
///
/// Et cela tombe juste : le groupe de routes M5 ne porte **aucun `DELETE`**,
/// délibérément — une boisson est référencée par `lignes_vente_bar` en
/// `restrictOnDelete()`.
class _Actions extends ConsumerWidget {
  const _Actions({required this.boisson});

  final Boisson boisson;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: Key('boissons-voir-${boisson.id}'),
          // Le `title` du maître (`crud-engine.js` l.234), au mot.
          tooltip: 'Voir le détail',
          onPressed: () => ouvrirModaleDetailBoisson(context, boisson: boisson),
          icon: const Icon(
            Icons.visibility_outlined,
            size: AppLayout.iconeChamp,
            color: Ardoise.c500,
          ),
        ),
        IconButton(
          key: Key('boissons-modifier-${boisson.id}'),
          tooltip: 'Modifier',
          onPressed: () async {
            final enregistre = await ouvrirModaleBoisson(
              context,
              boisson: boisson,
            );
            if (enregistre == true) ref.invalidate(boissonsProvider);
          },
          icon: const Icon(
            Icons.edit_outlined,
            size: AppLayout.iconeChamp,
            color: Ardoise.c500,
          ),
        ),
      ],
    );
  }
}

/// La pagination du maître — `crud-engine.js` l.252-260, formulation comprise.
class _Pagination extends ConsumerWidget {
  const _Pagination({required this.page});

  final PageBoissons page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courante = page.page;

    return Container(
      // `flex items-center justify-between px-4 py-3 border-t border-slate-100`.
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Ardoise.c100)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          Text(
            // La formulation du maître (`crud-engine.js` l.254), au mot.
            'Affichage de ${page.premier}-${page.dernier} sur ${page.total}',
            key: const Key('boissons-decompte'),
            style: TextesRestaurant.petitCrud,
          ),
          // `flex items-center gap-2` — rendu en `Wrap` : les trois contrôles
          // débordent sur un écran de 390 px et « Suivant → » devient
          // inatteignable. Même défaut mesuré en M4 (Article 9.3).
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton(
                key: const Key('boissons-page-precedente'),
                onPressed: courante <= 1
                    ? null
                    : () => ref
                          .read(pageBoissonsProvider.notifier)
                          .definir(courante - 1),
                // Le libellé du maître, flèche comprise.
                child: const Text(
                  '← Précédent',
                  style: TextesRestaurant.petitCrud,
                ),
              ),
              Padding(
                // `px-2` sur le compteur de page, en plus du `gap-2` du
                // conteneur : le maître pose les deux.
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: Text(
                  'Page $courante / ${page.derniere}',
                  key: const Key('boissons-page-courante'),
                  style: TextesRestaurant.petitCrud,
                ),
              ),
              OutlinedButton(
                key: const Key('boissons-page-suivante'),
                onPressed: courante >= page.derniere
                    ? null
                    : () => ref
                          .read(pageBoissonsProvider.notifier)
                          .definir(courante + 1),
                child: const Text(
                  'Suivant →',
                  style: TextesRestaurant.petitCrud,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Le bloc « Ce que cet écran ne rend pas » (`_NonRendu`) est RETIRÉ le
// 14/10/2026 (directive absolue du PO). Ce qu'il nommait reste vrai et se lit
// au code : champ « Stock disponible » en lecture seule (PA-24), sélecteur
// « Article de stock » ajouté (exigé par le serveur), import et suppression
// sans route, « Dupliquer » et la sélection retirés par le maître, recherche
// et pagination appliquées à la page reçue.
