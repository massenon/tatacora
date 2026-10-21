// Vue Blade maîtresse (PA-183) : pwa/stocks/inventaires.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/formats.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared_widgets/bouton_standard.dart';
import '../../../shared_widgets/modale_export.dart';
import '../../../shared_widgets/toast_export.dart';
import '../data/stocks_api.dart';
import '../domain/entities/fiche_stock.dart';
import '../domain/entities/mouvement_stock.dart' show TypeMouvement;
import '../domain/messages_stock.dart';
import 'providers_stocks.dart';
import 'widgets/vue_fiche_stock.dart';

// Les refus et les écarts de la vue, NOMMÉS ici (21/10/2026) :
//  - la colonne « Par » de la fiche est RENDUE : chaque mouvement porte son
//    auteur (`mouvements_stock_local.utilisateur_id`) — la vue, elle, rend un
//    tiret (le serveur ne remonte pas l'auteur) ;
//  - le cycle d'inventaire n'affiche ni « à jour » ni « en retard » : aucune
//    table ne porte de périodicité (PA-150) ;
//  - l'INVENTAIRE PHYSIQUE est REFUSÉ : ouvrir, compter, clôturer et
//    régulariser écrivent des tables (`inventaires`, `lignes_inventaire`) que
//    ce poste n'a pas (schéma v34, aucune migration dans ce lot) — voir
//    `TextesInventaires.inventaireNonPorte` et le doc de l'écran. Les deux
//    modales du comptage et de la clôture partielle sont refusées avec lui :
//  - blade-refuse:stocks/inventaires#modale:inventaires.enregistrer_comptage
//  - blade-refuse:stocks/inventaires#modale:inventaires.incomplet_titre
//  - l'en-tête d'impression de la vue (`hidden print:block`, l.119-123) est
//    écrit EN DUR « TATACORA AFRIQUE — GÎTE CHEZ NOËL » pour l'impression du navigateur. Ce
//    poste n'imprime pas l'écran : ses états A4 lisent l'en-tête des Paramètres
//    (raison sociale, adresse, IFU…). Une seconde ligne en dur contredirait la
//    raison sociale saisie. Écart nommé, pas un refus.

/// Les trois onglets du maître (`m6-inventaires.html` l.36-46).
const _onglets = <(String, String)>[
  ('fiche', 'Fiche de stock'),
  ('inventaire', 'Inventaire physique'),
  ('historique', 'Inventaires clôturés'),
];

/// L'écran **Inventaires & Fiches de stock** — la vue `stocks/inventaires`.
///
/// ## Les TROIS onglets de la vue sont rendus
///
/// L'onglet « Fiche de stock » est calculé depuis `mouvements_stock_local` par
/// `calculerFiche` (fonction pure) : stock initial = solde à la veille, flux de
/// la période, stock théorique vérifié par un second chemin (`coherent`). « Tous
/// les articles » (la valeur vide du filtre, PO 06/09/2026) rend la fiche
/// CONSOLIDÉE (`consoliderFiches`) : la fiche de chaque article, jamais un cumul
/// de quantités. La période par défaut couvre trente jours, comme la vue. Rien
/// n'est mis en cache.
///
/// ## L'inventaire physique est REFUSÉ, et l'écran le DIT (21/10/2026)
///
/// « Lancer l'inventaire », la feuille de comptage, « Enregistrer le comptage »
/// et « Clôturer et régulariser » ÉCRIVENT : un inventaire (point, date,
/// auteur), une ligne par article compté (théorique figé, constaté, écart) et,
/// à la clôture, un mouvement de régularisation par écart. Ce poste n'a ni
/// table d'inventaire ni table de lignes, et personne ne les écrirait : un
/// comptage « enregistré » nulle part se perdrait à la fermeture de la fenêtre,
/// et une clôture ne régulariserait rien que le serveur connaisse. Le bouton
/// « Lancer l'inventaire » est donc rendu GRISÉ à sa place (ligne de chaque
/// point du cycle), et la note de l'onglet dit pourquoi — jamais un bouton
/// inerte en silence. Les inventaires clôturés ne se listent pas non plus.
/// Ce qu'il faudrait : voir le rapport du lot (deux tables avec leur auteur
/// unique, l'envoi de l'inventaire et de ses lignes au serveur — qui ne connaît
/// pas encore ces documents dans son flux —, la descente de l'historique).
class EcranInventaires extends ConsumerStatefulWidget {
  const EcranInventaires({super.key});

  @override
  ConsumerState<EcranInventaires> createState() => _EtatEcranInventaires();
}

class _EtatEcranInventaires extends ConsumerState<EcranInventaires> {
  String _onglet = 'fiche';

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      // `p-5 lg:p-8` : 32 px au poste de travail (voir `ecran_parametres`).
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppLayout.maxContentWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _EnTete(),
              _BarreOnglets(
                actif: _onglet,
                onChoisir: (o) => setState(() => _onglet = o),
              ),
              switch (_onglet) {
                'inventaire' => const _OngletInventaire(),
                'historique' => const _OngletHistorique(),
                _ => const _OngletFiche(),
              },
            ],
          ),
        ),
      ),
    );
  }
}

TextStyle _t(
  double taille, {
  FontWeight? poids,
  Color? couleur,
  double? interligne = 1.5,
  double? espacement,
}) => TextStyle(
  fontFamily: AppTextStyles.police,
  fontSize: taille,
  fontWeight: poids,
  color: couleur,
  height: interligne,
  letterSpacing: espacement,
);

BoxDecoration _carte() => BoxDecoration(
  color: AppColors.neutre0,
  borderRadius: BorderRadius.circular(AppRadius.roundedXl),
  border: Border.all(color: AppColors.neutre200),
);

/// `<div class="mb-5 flex … justify-between gap-3">` — le titre à gauche, le
/// lien « Gestion des Stocks » à droite.
class _EnTete extends StatelessWidget {
  const _EnTete();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.mdPlus), // mb-5
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.fact_check_outlined,
                      size: 24,
                      color: AppColors.navy,
                    ),
                    const SizedBox(width: AppSpacing.xsPlus),
                    Text(
                      'Inventaires & Fiches de stock',
                      style: _t(
                        TaillesContenu.lg,
                        poids: FontWeight.bold,
                        couleur: AppColors.navy,
                        interligne: TaillesContenu.interligneLg,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs), // mt-1.5
                Text.rich(
                  TextSpan(
                    style: _t(TaillesContenu.t15, couleur: AppColors.neutre500),
                    children: const [
                      TextSpan(
                        text:
                            'Stock initial, entrées, sorties et stock '
                            'théorique sur une période — le stock est ',
                      ),
                      TextSpan(
                        text: 'calculé',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(text: ', jamais saisi.'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // `text-[13px] px-3.5 py-2 rounded-lg border border-slate-300
          // bg-white` : le bouton standard (14/10/2026).
          BoutonStandard(
            key: const Key('inventaires-gestion-stocks'),
            libelle: 'Gestion des Stocks',
            onPressed: () => GoRouter.of(context).go('/stocks'),
          ),
        ],
      ),
    );
  }
}

/// `flex gap-1 mb-5 border-b border-slate-200` — les onglets au style de
/// `Onglets::classes()`.
class _BarreOnglets extends StatelessWidget {
  const _BarreOnglets({required this.actif, required this.onChoisir});

  final String actif;
  final ValueChanged<String> onChoisir;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.mdPlus), // mb-5
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.neutre200)),
      ),
      child: Row(
        children: [
          for (final (cle, libelle) in _onglets) ...[
            _Onglet(
              key: Key('inventaires-onglet-$cle'),
              libelle: libelle,
              actif: cle == actif,
              onTap: () => onChoisir(cle),
            ),
            if (cle != _onglets.last.$1) const SizedBox(width: AppSpacing.unit),
          ],
        ],
      ),
    );
  }
}

class _Onglet extends StatelessWidget {
  const _Onglet({
    required super.key,
    required this.libelle,
    required this.actif,
    required this.onTap,
  });

  final String libelle;
  final bool actif;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: actif ? AppColors.navy : AppColors.neutre0,
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.smPlus,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            border: Border.all(
              color: actif ? AppColors.navy : AppColors.neutre200,
            ),
          ),
          child: Text(
            libelle,
            style: _t(
              TaillesContenu.t13,
              poids: FontWeight.w600,
              couleur: actif ? AppColors.neutre0 : AppColors.neutre500,
            ),
          ),
        ),
      ),
    );
  }
}

/* ====================================================================== */
/* Onglet « Fiche de stock »                                               */
/* ====================================================================== */

class _OngletFiche extends ConsumerWidget {
  const _OngletFiche();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // « Tous les articles » est la valeur VIDE du filtre : un choix, pas une
    // absence de choix — la vue ouvre sur la fiche consolidée.
    final tous =
        ref.watch(demandeFicheProvider.select((d) => d.articleId)) == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _CartePeriode(),
        if (tous) const _FicheConsolideeVue() else const _FicheUnitaire(),
      ],
    );
  }
}

/// La fiche d'UN article, ou ce que la vue dit quand il n'existe pas
/// (`aucun_article`, `aucun_article_detail`).
class _FicheUnitaire extends ConsumerWidget {
  const _FicheUnitaire();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultat = ref.watch(ficheStockProvider);

    return resultat.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => _Note(cle: const Key('fiche-erreur'), texte: '$e'),
      data: (r) => switch (r) {
        null => const _AucunArticle(),
        FicheRecue(:final fiche) => VueFicheStock(
          fiche: fiche,
          pointLibelle: _libellePoint(ref, fiche.pointId),
        ),
        // L'article choisi n'est plus au référentiel : la vue rend alors son
        // panneau « Aucun article » plutôt qu'une phrase d'erreur.
        FicheRefusee(:final motif)
            when motif == MessagesStock.articleInexistant =>
          const _AucunArticle(),
        FicheRefusee(:final motif) => _Note(
          cle: const Key('fiche-refus'),
          texte: motif,
        ),
        // Jamais produit : une base locale n'est pas hors connexion. L'arm
        // reste parce que le type scellé est partagé.
        FicheInjoignable() => const _Note(
          cle: Key('fiche-hors-ligne'),
          texte: 'La fiche n’a pas pu être lue.',
        ),
      },
    );
  }

  /// Le libellé du point RÉELLEMENT appliqué, tel que la fiche l'a rendu : un
  /// document qui annoncerait un autre point que celui de son calcul affirmerait
  /// une portée qu'il n'a pas.
  static String? _libellePoint(WidgetRef ref, String? pointId) {
    if (pointId == null) return null;

    final points = ref.watch(pointsStockProvider).value ?? const [];
    for (final p in points) {
      if (p.id == pointId) return p.libelle;
    }
    return pointId;
  }
}

/// `aucun_article` (l.310-313 de la vue) : `bg-white rounded-xl border p-10
/// text-center`, le titre en navy, le détail en ardoise.
class _AucunArticle extends StatelessWidget {
  const _AucunArticle();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('fiche-aucun-article'),
      padding: const EdgeInsets.all(AppSpacingLarge.p10),
      decoration: _carte(),
      child: Column(
        children: [
          Text(
            TextesInventaires.aucunArticle,
            style: _t(
              TaillesContenu.t15,
              poids: FontWeight.w600,
              couleur: AppColors.navy,
            ),
          ),
          const SizedBox(height: AppSpacing.unit), // mt-1
          Text(
            TextesInventaires.aucunArticleDetail,
            style: _t(TaillesContenu.t13, couleur: AppColors.neutre500),
          ),
        ],
      ),
    );
  }
}

/// Les phrases de l'écran qui ne sont pas des libellés de colonne — une seule
/// fois chacune.
abstract final class TextesInventaires {
  static const String aucunArticle = 'Aucun article';
  static const String aucunArticleDetail =
      "Créez d'abord un article dans l'écran Stocks.";

  /// Le refus de l'inventaire physique, DIT avec les mots de la vue (voir
  /// l'en-tête de l'écran) : ce que la vue ouvre, et ce que ce poste ne tient
  /// pas. Affiché sous le tableau du cycle ET sous celui de l'historique.
  static const String inventaireNonPorte =
      'Inventaire physique non porté sur ce poste (21/10/2026) : « Lancer '
      'l’inventaire » ouvrirait une feuille de comptage (« Inventaire du … », '
      '« … article(s) comptés », « … écart(s) », « impact valorisé », colonnes '
      '« à compter » et « Écart valorisé », boutons « Enregistrer le comptage », '
      '« Exporter » — « Exporter — Articles en stock » — et « Clôturer et '
      'régulariser »), mais ce poste n’a ni table d’inventaire ni lignes de '
      'comptage : un comptage n’y serait écrit nulle part, et une clôture ne '
      'régulariserait rien que le serveur connaisse. Pour la même raison, la '
      'liste des inventaires clôturés (« Aucun inventaire clôturé » — « Les '
      'inventaires clôturés et leurs régularisations apparaîtront ici. ») ne '
      'peut pas se tenir ici : rien ne s’y inscrirait.';

  /// `export.fiche_tous_articles` : le refus d'exporter la fiche sous « Tous les
  /// articles » (accents absents, comme dans la vue).
  static const String ficheTousArticles =
      "Choisissez un article : le document de fiche de stock est etabli pour un seul article. Sous « Tous les articles », les quantites d'unites differentes ne peuvent pas etre totalisees.";

  /// `cycle_non_definie` : aucune périodicité n'est enregistrée nulle part.
  static const String nonDefinie = 'non définie';

  /// `aucun_point_defini` : rendu quand le poste n'a aucun point de stockage.
  static const String aucunPointDefini =
      "Aucun point de stockage n'est défini : un inventaire porte sur un point, il ne peut pas être ouvert sans lui.";

  /// `lancer` : le bouton de chaque ligne du cycle — grisé ici.
  static const String lancer = "Lancer l'inventaire";
}

/// La carte des filtres — `bg-white rounded-xl border p-4 mb-4`.
class _CartePeriode extends ConsumerWidget {
  const _CartePeriode();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final demande = ref.watch(demandeFicheProvider);
    final referentiel = ref.watch(articlesFicheProvider);
    final articles = referentiel.value ?? const <ArticleFiche>[];
    final points = ref.watch(pointsStockProvider).value ?? const [];

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md), // mb-4
      padding: const EdgeInsets.all(AppSpacing.md), // p-4
      decoration: _carte(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              // `md:grid-cols-5 gap-3`, l'article sur deux colonnes.
              final unite = (c.maxWidth - 4 * AppSpacing.sm) / 5;
              return Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  SizedBox(
                    width: unite * 2 + AppSpacing.sm,
                    child: _ChampListe(
                      cle: const Key('fiche-article'),
                      libelle: 'Article',
                      // Une valeur qui n'est PAS dans la liste (article parti, ou
                      // liste pas encore lue) rend la première option, comme le
                      // `<select>` de la vue — jamais une assertion de Flutter.
                      valeur: articles.any((a) => a.id == demande.articleId)
                          ? demande.articleId
                          : null,
                      items: [
                        if (articles.isNotEmpty)
                          const DropdownMenuItem<String?>(
                            child: Text('Tous les articles'),
                          ),
                        for (final a in articles)
                          DropdownMenuItem<String?>(
                            value: a.id,
                            child: Text(a.libelle),
                          ),
                        if (articles.isEmpty)
                          const DropdownMenuItem<String?>(
                            child: Text(TextesInventaires.aucunArticleDetail),
                          ),
                      ],
                      onChanged: (id) =>
                          ref.read(demandeFicheProvider.notifier).article(id),
                    ),
                  ),
                  SizedBox(
                    width: unite,
                    child: _ChampListe(
                      cle: const Key('fiche-point'),
                      libelle: 'Point de stockage',
                      valeur: demande.pointId,
                      items: [
                        const DropdownMenuItem<String?>(
                          child: Text('Tous les points'),
                        ),
                        for (final p in points)
                          DropdownMenuItem<String?>(
                            value: p.id,
                            child: Text(p.libelle),
                          ),
                      ],
                      onChanged: (id) =>
                          ref.read(demandeFicheProvider.notifier).point(id),
                    ),
                  ),
                  SizedBox(
                    width: unite,
                    child: _ChampBorne(
                      cle: const Key('fiche-debut'),
                      libelle: 'Du',
                      valeur: demande.debut,
                    ),
                  ),
                  SizedBox(
                    width: unite,
                    child: _ChampBorne(
                      cle: const Key('fiche-fin'),
                      libelle: 'Au',
                      valeur: demande.fin,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm), // mt-3
          Row(
            children: [
              for (final r in RaccourciPeriode.values) ...[
                _Raccourci(
                  key: Key('fiche-raccourci-${r.name}'),
                  libelle: r.libelle,
                  onTap: () => ref
                      .read(demandeFicheProvider.notifier)
                      .raccourci(r, DateTime.now()),
                ),
                const SizedBox(width: AppSpacing.xs), // gap-2
              ],
              const Spacer(),
              // `text-[12px] px-3 py-1.5 rounded-lg bg-[var(--navy)]` (vue
              // l.219) : le bouton standard, compact. Il ouvre la modale
              // d'export PARTAGÉE (14/10/2026, demande du PO).
              BoutonStandard(
                key: const Key('fiche-exporter'),
                libelle: TextesExport.bouton,
                compact: true,
                margeVerticale: AppSpacing.xxs,
                variante: VarianteBouton.primaire,
                onPressed: () => _exporter(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// « Exporter » de la fiche — la modale partagée (`stocks_pwa.export.
/// titre_fiche`, sous-titre `sous_titre_filtre` : l'article et la période),
/// puis le PDF A4 ou le tableur (CSV) de la fiche AFFICHÉE. Sans fiche
/// établie (aucun article), l'export est refusé avec le mot de la vue
/// (`fiche_absente`).
Future<void> _exporter(BuildContext context, WidgetRef ref) async {
  final fiche = switch (ref.read(ficheStockProvider).value) {
    FicheRecue(:final fiche) => fiche,
    _ => null,
  };
  if (fiche == null) {
    // « Tous les articles » n'a PAS de document de fiche : l'en-tête, les cumuls
    // et l'unité d'un tel document sont ceux d'UN article, et les quantités
    // d'unités différentes ne se totalisent pas (`export.fiche_tous_articles`).
    // Sans article du tout, la phrase de `export.fiche_absente`.
    final tous = ref.read(demandeFicheProvider).articleId == null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tous
              ? TextesInventaires.ficheTousArticles
              : "Sélectionnez un article avant d'exporter.",
          key: const Key('fiche-export-absente'),
        ),
      ),
    );
    return;
  }

  final demande = ref.read(demandeFicheProvider);
  final articles = ref.read(articlesFicheProvider).value ?? const [];
  final article = articles
      .where((a) => a.id == demande.articleId)
      .firstOrNull
      ?.libelle;
  final points = ref.read(pointsStockProvider).value ?? const [];
  final pointLibelle = fiche.pointId == null
      ? null
      : (points.where((p) => p.id == fiche.pointId).firstOrNull?.libelle ??
            fiche.pointId);
  final debut = demande.debut == null ? '—' : formatIso(demande.debut!);
  final fin = demande.fin == null ? '—' : formatIso(demande.fin!);

  final format = await choisirFormatExport(
    context,
    titre: 'Exporter — Fiche de stock',
    sousTitre:
        'Le document porte les filtres affichés : '
        '${article ?? TextesInventaires.aucunArticle} · $debut → $fin',
  );
  if (format == null || !context.mounted) return;

  // La fenêtre « Enregistrer sous », puis le toast commun (14/10/2026).
  await executerExport(
    context,
    () => switch (format) {
      FormatExport.pdf => ref.read(exporterFicheStockPdfProvider)(
        fiche,
        pointLibelle,
      ),
      FormatExport.excel => ref.read(exporterFicheStockProvider)(
        fiche,
        pointLibelle,
      ),
    },
    cleSucces: const Key('fiche-export-fait'),
  );
}

/// Étiquette `text-[11px] font-semibold text-slate-500 mb-1` + liste.
class _ChampListe extends StatelessWidget {
  const _ChampListe({
    required Key cle,
    required this.libelle,
    required this.valeur,
    required this.items,
    required this.onChanged,
  }) : super(key: cle);

  final String libelle;
  final String? valeur;
  final List<DropdownMenuItem<String?>> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Etiquette(libelle),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, // px-3
            vertical: AppSpacing.xs, // py-2
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            border: Border.all(color: AppColors.neutre300),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: valeur,
              isExpanded: true,
              isDense: true,
              items: items,
              onChanged: items.length < 2 ? null : onChanged,
              style: _t(TaillesContenu.t13, couleur: AppColors.neutre700),
            ),
          ),
        ),
      ],
    );
  }
}

/// Une borne de période, en LECTURE : elle se pose par les raccourcis. Le
/// maître emploie un `<input type="date">`, que Flutter n'a pas en natif ; un
/// champ libre laisserait saisir « 32/13 ».
class _ChampBorne extends StatelessWidget {
  const _ChampBorne({
    required Key cle,
    required this.libelle,
    required this.valeur,
  }) : super(key: cle);

  final String libelle;
  final DateTime? valeur;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Etiquette(libelle),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            border: Border.all(color: AppColors.neutre300),
          ),
          child: Text(
            valeur == null ? '—' : formatIso(valeur!),
            style: _t(TaillesContenu.t13, couleur: AppColors.neutre700),
          ),
        ),
      ],
    );
  }
}

class _Etiquette extends StatelessWidget {
  const _Etiquette(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.unit), // mb-1
      child: Text(
        texte,
        style: _t(
          TaillesContenu.t11,
          poids: FontWeight.w600,
          couleur: AppColors.neutre500,
        ),
      ),
    );
  }
}

/// `text-[12px] px-3 py-1.5 rounded-lg bg-slate-100`
class _Raccourci extends StatelessWidget {
  const _Raccourci({
    required super.key,
    required this.libelle,
    required this.onTap,
  });

  final String libelle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.neutre100,
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xxs,
          ),
          child: Text(
            libelle,
            style: _t(TaillesContenu.t12, couleur: AppColors.neutre700),
          ),
        ),
      ),
    );
  }
}

/// La fiche CONSOLIDÉE (« Tous les articles », vue l.223-308) : le bandeau des
/// fiches incohérentes, les quatre cartes, la phrase d'aide, puis le détail des
/// mouvements de tous les articles, du plus ancien au plus récent.
class _FicheConsolideeVue extends ConsumerWidget {
  const _FicheConsolideeVue();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(ficheConsolideeProvider)
        .when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) =>
              _Note(cle: const Key('fiche-consolidee-erreur'), texte: '$e'),
          data: (r) => switch (r) {
            null => const SizedBox.shrink(),
            FicheConsolideeRecue(:final fiche) => _CorpsConsolide(fiche: fiche),
            FicheConsolideeRefusee(:final motif) => _Note(
              cle: const Key('fiche-consolidee-refus'),
              texte: motif,
            ),
          },
        );
  }
}

class _CorpsConsolide extends StatelessWidget {
  const _CorpsConsolide({required this.fiche});

  final FicheConsolidee fiche;

  /// Le signe MOINS du maître (U+2212), écrit par son point de code : le
  /// transcrire à la main le confondrait avec le tiret ASCII.
  static const String _moins = '\u{2212}';

  static const _colonnes = [
    'Date',
    'Article',
    'Type',
    'Motif',
    'Entrée',
    'Sortie',
    'Solde',
    'Utilisateur',
  ];
  static const _parts = [110, 142, 110, 126, 129, 129, 123, 186];

  @override
  Widget build(BuildContext context) {
    // Les quatre cartes, dans l'ordre de la vue (l.241-258) : le nombre
    // d'articles, ceux qui ont bougé (bleu), les mouvements, la valeur.
    final cartes = <(Key, String, String, Color)>[
      (
        const Key('fiche-consolidee-articles'),
        'Articles au catalogue',
        '${fiche.articles}',
        AppColors.navy,
      ),
      (
        const Key('fiche-consolidee-mouvementes'),
        'Articles mouvementes',
        '${fiche.articlesAvecMouvement}',
        PaletteMaitre.bleu600,
      ),
      (
        const Key('fiche-consolidee-mouvements'),
        'Mouvements sur la periode',
        '${fiche.mouvements}',
        AppColors.navy,
      ),
      (
        const Key('fiche-consolidee-valeur'),
        'Valeur du stock theorique',
        formaterFcfa(int.parse(fiche.valeurStockTheorique)),
        AppColors.navy,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (fiche.incoherents.isNotEmpty)
          Container(
            key: const Key('fiche-consolidee-incoherente'),
            margin: const EdgeInsets.only(bottom: AppSpacing.md), // mb-4
            padding: const EdgeInsets.all(AppSpacing.smPlus), // p-3.5
            decoration: BoxDecoration(
              color: PaletteMaitre.rouge50,
              borderRadius: BorderRadius.circular(AppRadius.roundedXl),
              border: Border.all(color: PaletteMaitre.rouge200),
            ),
            child: Text.rich(
              TextSpan(
                style: _t(TaillesContenu.t13, couleur: PaletteMaitre.rouge800),
                children: [
                  // `incoherence` en gras, puis `incoherents_liste` : chaque
                  // fiche incohérente est NOMMÉE, pas noyée dans un compteur.
                  const TextSpan(
                    text: 'Incohérence détectée.',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(
                    text:
                        ' Articles concernes : ${fiche.incoherents.join(', ')}.',
                  ),
                ],
              ),
            ),
          ),
        LayoutBuilder(
          builder: (context, c) {
            // `grid-cols-2 lg:grid-cols-4 gap-3 mb-4`
            final largeur = (c.maxWidth - 3 * AppSpacing.sm) / 4;
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final (cle, libelle, valeur, couleur) in cartes)
                    SizedBox(
                      width: largeur,
                      child: Container(
                        padding: const EdgeInsets.all(
                          AppSpacing.smPlus,
                        ), // p-3.5
                        decoration: _carte(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              libelle.toUpperCase(),
                              style: _t(
                                TaillesContenu.t11,
                                poids: FontWeight.w600,
                                couleur: AppColors.neutre400,
                                espacement: 0.5,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.demi), // mt-0.5
                            Text(
                              valeur,
                              key: cle,
                              style: _t(
                                TaillesContenu.lg,
                                poids: FontWeight.bold,
                                couleur: couleur,
                                interligne: TaillesContenu.interligneLg,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm), // mb-3
          child: Text(
            "Chaque ligne garde l'unite et le solde de son propre article : les quantites d'articles differents ne s'additionnent pas.",
            style: _t(TaillesContenu.t12, couleur: AppColors.neutre500),
          ),
        ),
        Container(
          decoration: _carte(),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, // px-4
                  vertical: AppSpacing.sm, // py-3
                ),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppColors.neutre200),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Détail des mouvements',
                      style: _t(
                        TaillesContenu.t13,
                        poids: FontWeight.bold,
                        couleur: AppColors.navy,
                      ),
                    ),
                    Text(
                      '${fiche.mouvements} mouvement(s)',
                      key: const Key('fiche-consolidee-nombre'),
                      style: _t(
                        TaillesContenu.t11,
                        couleur: AppColors.neutre400,
                      ),
                    ),
                  ],
                ),
              ),
              const _EnTeteTableau(_colonnes, parts: _parts),
              if (fiche.lignes.isEmpty)
                const _LigneVide(texte: 'Aucun mouvement sur cette période.')
              else
                for (final (i, l) in fiche.lignes.indexed)
                  _LigneConsolidee(
                    cle: Key('fiche-consolidee-ligne-$i'),
                    ligne: l,
                    parts: _parts,
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Une ligne du détail consolidé (vue l.293-303) : `border-t border-slate-100`,
/// cellules `px-4 py-2.5`. Le type est un badge coloré ; l'entrée est en vert
/// avec son unité, la sortie en bleu, le solde en gras — chaque solde est celui
/// de SON article.
///
/// ÉCART avec la vue, nommé : sa colonne « Utilisateur » rend toujours un tiret
/// (le serveur ne remonte pas l'auteur du mouvement) ; ce poste le connaît
/// (`mouvements_stock_local.utilisateur_id`), il l'écrit — comme sa fiche d'un
/// seul article, dont la colonne « Par » est déjà rendue.
class _LigneConsolidee extends StatelessWidget {
  const _LigneConsolidee({
    required Key cle,
    required this.ligne,
    required this.parts,
  }) : super(key: cle);

  final LigneFicheConsolidee ligne;
  final List<int> parts;

  Widget _cellule(
    int i,
    Widget enfant, {
    Alignment alignement = Alignment.centerLeft,
  }) => Expanded(
    flex: parts[i],
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md, // px-4
        vertical: AppSpacing.xsPlus, // py-2.5
      ),
      child: Align(alignment: alignement, child: enfant),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = ligne.ligne;
    final type = TypeMouvement.values
        .where((t) => t.libelle == l.type)
        .firstOrNull;
    final (fondType, texteType) = switch (type) {
      TypeMouvement.entree => (
        PaletteMaitre.emeraude50,
        PaletteMaitre.emeraude700,
      ),
      TypeMouvement.sortie => (PaletteMaitre.bleu50, PaletteMaitre.bleu700),
      TypeMouvement.perte => (PaletteMaitre.rouge50, PaletteMaitre.rouge700),
      TypeMouvement.inventaire => (
        PaletteMaitre.ambre50,
        PaletteMaitre.ambre700,
      ),
      null => (AppColors.neutre100, AppColors.neutre600),
    };
    final entree = l.entree != '0.00';
    final sortie = l.sortie != '0.00';

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Ardoise.c100)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _cellule(
            0,
            Text(dateHeureDeLaVue(l.date), style: _t(TaillesContenu.t13)),
          ),
          _cellule(
            1,
            Text(
              ligne.article,
              style: _t(
                TaillesContenu.t13,
                poids: FontWeight.w600,
                couleur: Ardoise.c700,
              ),
            ),
          ),
          _cellule(
            2,
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs, // px-2
                vertical: AppSpacing.demi, // py-0.5
              ),
              decoration: BoxDecoration(
                color: fondType,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                l.ruptureForcee ? '${l.type} — rupture forcée' : l.type,
                style: _t(
                  TaillesContenu.t11,
                  poids: FontWeight.w600,
                  couleur: texteType,
                ),
              ),
            ),
          ),
          _cellule(
            3,
            Text(l.motif, style: _t(TaillesContenu.t13, couleur: Ardoise.c600)),
          ),
          _cellule(
            4,
            Text(
              entree ? '+${l.entree} ${ligne.unite}' : '—',
              style: _t(
                TaillesContenu.t13,
                poids: entree ? FontWeight.w600 : null,
                couleur: entree ? PaletteMaitre.emeraude600 : Ardoise.c300,
              ),
            ),
            alignement: Alignment.centerRight,
          ),
          _cellule(
            5,
            Text(
              sortie
                  ? '${_CorpsConsolide._moins}${l.sortie} ${ligne.unite}'
                  : '—',
              style: _t(
                TaillesContenu.t13,
                poids: sortie ? FontWeight.w600 : null,
                couleur: sortie ? PaletteMaitre.bleu600 : Ardoise.c300,
              ),
            ),
            alignement: Alignment.centerRight,
          ),
          _cellule(
            6,
            Text(
              '${l.solde} ${ligne.unite}',
              style: _t(TaillesContenu.t13, poids: FontWeight.bold),
            ),
            alignement: Alignment.centerRight,
          ),
          _cellule(
            7,
            Text(
              l.par ?? '—',
              style: _t(
                TaillesContenu.t12,
                couleur: l.par == null ? Ardoise.c300 : Ardoise.c600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `<thead class="bg-[var(--navy)] text-[11px] uppercase tracking-wide
/// text-white/90 font-semibold">` — colonnes de largeur égale, les nombres
/// alignés à droite comme la vue.
class _EnTeteTableau extends StatelessWidget {
  const _EnTeteTableau(this.colonnes, {this.droite = const {}, this.parts});

  final List<String> colonnes;
  final Set<String> droite;

  /// Les parts de largeur de chaque colonne, relevées sur la vue rendue
  /// (`<table class="w-full">` : la largeur de colonne vient de son contenu, que
  /// l'état vide réduit à la seule largeur de l'en-tête). À défaut, parts égales.
  final List<int>? parts;

  static const _aDroiteParDefaut = {'Entrée', 'Sortie', 'Solde'};

  @override
  Widget build(BuildContext context) {
    final aDroite = droite.isEmpty ? _aDroiteParDefaut : droite;
    return Container(
      color: AppColors.navy,
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.xsPlus, // py-2.5
      ),
      child: Row(
        children: [
          for (var i = 0; i < colonnes.length; i++)
            Expanded(
              flex: parts?[i] ?? 1,
              child: Padding(
                // `px-4` de chaque `<th>`.
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Text(
                  colonnes[i].toUpperCase(),
                  textAlign: aDroite.contains(colonnes[i])
                      ? TextAlign.right
                      : TextAlign.left,
                  style: _t(
                    TaillesContenu.t11,
                    poids: FontWeight.w600,
                    couleur: AppColors.neutre0.withValues(alpha: 0.90),
                    espacement: 0.5, // tracking-wide
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LigneVide extends StatelessWidget {
  const _LigneVide({required this.texte});

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl), // p-8
      child: Text(
        texte,
        textAlign: TextAlign.center,
        style: _t(TaillesContenu.t13, couleur: AppColors.neutre400),
      ),
    );
  }
}

/* ====================================================================== */
/* Onglet « Inventaire physique »                                          */
/* ====================================================================== */

class _OngletInventaire extends ConsumerWidget {
  const _OngletInventaire();

  /// Les parts de largeur des cinq colonnes du cycle (`px-3 py-2`).
  static const _parts = [180, 150, 220, 150, 190];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final points = ref.watch(pointsStockProvider).value ?? const [];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md), // p-4
      decoration: _carte(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm), // mb-3
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Aucun inventaire en cours',
                  style: _t(
                    TaillesContenu.t15,
                    poids: FontWeight.w600,
                    couleur: AppColors.navy,
                  ),
                ),
                const SizedBox(height: AppSpacing.demi),
                Text(
                  'Ouvrir un inventaire fige le stock théorique de chaque '
                  'article à cet instant.',
                  style: _t(TaillesContenu.t13, couleur: AppColors.neutre500),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs), // mb-2
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cycle d’inventaire par magasin',
                  style: _t(
                    TaillesContenu.t13,
                    poids: FontWeight.bold,
                    couleur: AppColors.navy,
                  ),
                ),
                const SizedBox(height: AppSpacing.demi),
                Text(
                  'La périodicité signale une échéance ; elle n’empêche jamais '
                  'de lancer un inventaire.',
                  style: _t(TaillesContenu.t12, couleur: AppColors.neutre500),
                ),
              ],
            ),
          ),
          // La cinquième colonne, celle du bouton, n'a pas d'en-tête (vue
          // l.452-456) : « Lancer l'inventaire » n'est le nom d'aucune colonne.
          const _EnTeteTableau([
            'Magasin',
            'Periodicite',
            'Dernier inventaire cloture',
            'Etat',
            '',
          ], parts: _parts),
          if (points.isEmpty)
            const _LigneVide(texte: TextesInventaires.aucunPointDefini)
          else
            for (final p in points)
              _LigneCycle(
                cle: Key('inventaire-cycle-${p.id}'),
                libelle: p.libelle,
                parts: _parts,
              ),
          const _NoteNonPortee(cle: Key('inventaire-non-porte')),
        ],
      ),
    );
  }
}

/// Une ligne du « Cycle d'inventaire par magasin » (vue l.460-477) : le point,
/// sa périodicité et son état — « non définie » : aucune périodicité n'est
/// enregistrée nulle part —, son dernier inventaire, et le bouton « Lancer
/// l'inventaire », GRISÉ (voir [TextesInventaires.inventaireNonPorte]).
///
/// « Dernier inventaire clôturé » rend « — » : la vue y met une date ou
/// « aucun » ; ce poste ne tient aucun inventaire, il ne peut donc affirmer
/// ni l'un ni l'autre (un « aucun » dirait qu'il n'en existe pas ailleurs).
class _LigneCycle extends StatelessWidget {
  const _LigneCycle({
    required Key cle,
    required this.libelle,
    required this.parts,
  }) : super(key: cle);

  final String libelle;
  final List<int> parts;

  Widget _cellule(
    int i,
    Widget enfant, {
    Alignment alignement = Alignment.centerLeft,
  }) => Expanded(
    flex: parts[i],
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm, // px-3
        vertical: AppSpacing.xs, // py-2
      ),
      child: Align(alignment: alignement, child: enfant),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final nonDefinie = Text(
      TextesInventaires.nonDefinie,
      style: _t(TaillesContenu.t12, couleur: AppColors.neutre400),
    );

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Ardoise.c100)),
      ),
      child: Row(
        children: [
          _cellule(
            0,
            Text(
              libelle,
              style: _t(
                TaillesContenu.t13,
                poids: FontWeight.w600,
                couleur: AppColors.navy,
              ),
            ),
          ),
          _cellule(1, nonDefinie),
          _cellule(
            2,
            Tooltip(
              message: 'Aucun inventaire n’est tenu sur ce poste.',
              child: Text(
                '—',
                style: _t(TaillesContenu.t13, couleur: AppColors.neutre400),
              ),
            ),
          ),
          _cellule(3, nonDefinie),
          _cellule(
            4,
            Tooltip(
              message:
                  'Inventaire physique non porté sur ce poste : voir la note '
                  'sous le tableau.',
              child: BoutonStandard(
                key: Key('${(key as ValueKey<String>).value}-lancer'),
                libelle: TextesInventaires.lancer,
                compact: true,
                margeVerticale: AppSpacing.xxs, // py-1.5
                variante: VarianteBouton.primaire,
                // Grisé, jamais inerte en silence : la note dit pourquoi.
                onPressed: null,
              ),
            ),
            alignement: Alignment.centerRight,
          ),
        ],
      ),
    );
  }
}

/// La note de l'inventaire physique refusé — sous le tableau du cycle, et dans
/// le corps de l'onglet des inventaires clôturés.
class _NoteNonPortee extends StatelessWidget {
  const _NoteNonPortee({required this.cle});

  /// La clé est posée sur le TEXTE (les tests lisent le texte par sa clé).
  final Key cle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Text(
        TextesInventaires.inventaireNonPorte,
        key: cle,
        style: _t(TaillesContenu.t12, couleur: AppColors.neutre500),
      ),
    );
  }
}

/* ====================================================================== */
/* Onglet « Inventaires clôturés »                                         */
/* ====================================================================== */

class _OngletHistorique extends StatelessWidget {
  const _OngletHistorique();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _carte(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _EnTeteTableau(
            [
              'Date',
              'Point',
              'Articles',
              'Régularisés',
              'Manquants',
              'Excédents',
              'Impact net',
              'Par',
            ],
            droite: {
              'Articles',
              'Régularisés',
              'Manquants',
              'Excédents',
              'Impact net',
            },
          ),
          // Pas de « Aucun inventaire clôturé » : ce poste n'en tient aucun, il
          // ne peut donc dire ni qu'il y en a ni qu'il n'y en a pas. La note le
          // dit, avec les mots de la vue.
          const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: _NoteNonPortee(cle: Key('historique-non-porte')),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required Key cle, required this.texte}) : super(key: cle);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.neutre100,
        borderRadius: BorderRadius.circular(AppSpacing.md),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.neutre500),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              texte,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: AppColors.neutre500),
            ),
          ),
        ],
      ),
    );
  }
}
