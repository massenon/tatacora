// Vue Blade maîtresse (PA-183) : pwa/stocks/inventaires.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/donnees_absentes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared_widgets/bouton_standard.dart';
import '../../../shared_widgets/modale_export.dart';
import '../../../shared_widgets/toast_export.dart';
import '../data/stocks_api.dart';
import '../domain/entities/fiche_stock.dart';
import 'providers_stocks.dart';
import 'widgets/vue_fiche_stock.dart';

// Les refus de la vue, DITS ici plutôt qu'affichés (voir `parametres`, même
// règle) — état du 09/10/2026, après la source locale de M6 :
//  - la colonne « Par » de la fiche est RENDUE : chaque mouvement porte son
//    auteur (`mouvements_stock_local.utilisateur_id`) ;
//  - le cycle d'inventaire n'affiche ni « à jour » ni « en retard » : aucune
//    table ne porte de périodicité (PA-150) ;
//  - les colonnes « Manquants » et « Excédents » de l'historique rendent « — » :
//    seule la clôture d'un inventaire les produit, et aucun inventaire n'est
//    tenu sur ce poste (tables `inventaires_local` et `lignes_inventaire_local`
//    à venir, avec leur auteur — voir l'audit §4duotricies).

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
/// Jusqu'au 08/10/2026 l'écran n'en rendait qu'un et NOMMAIT les deux autres
/// dans une note (« Deux onglets du prototype ne sont pas rendus ») : la
/// mesure de géométrie (Phase 1A/1D) a montré qu'aucun n'était cliquable. Les
/// trois onglets existent maintenant, avec la structure de la vue ; **leur
/// contenu dit honnêtement qu'il n'a pas de source sur ce poste** : un
/// « Aucun inventaire clôturé » ou un « 0 FCFA » affirmeraient ce qu'aucune
/// donnée n'atteste (PA-59/60/61). Les valeurs viendront avec la source locale
/// du module M6 (décision du 08/10/2026).
///
/// ## La fiche est locale ; l'inventaire physique ne l'est pas encore
///
/// L'onglet « Fiche de stock » est calculé depuis `mouvements_stock_local` par
/// `calculerFiche` (fonction pure) : stock initial = solde à la veille, flux de
/// la période, stock théorique vérifié par un second chemin (`coherent`).
/// Rien n'est mis en cache.
///
/// Les deux autres onglets restent « sans source » : il n'existe encore ni
/// table d'inventaire ni auteur pour un comptage. « Tous les articles » (la
/// fiche consolidée) n'est pas rendu non plus.
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
    final resultat = ref.watch(ficheStockProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _CartePeriode(),
        resultat.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => _Note(cle: const Key('fiche-erreur'), texte: '$e'),
          data: (r) => switch (r) {
            // Rien demandé : la vue montre alors la fiche CONSOLIDÉE (tous les
            // articles). Ici sa structure, sans valeur inventée.
            null => const _FicheConsolidee(),
            FicheRecue(:final fiche) => VueFicheStock(
              fiche: fiche,
              pointLibelle: _libellePoint(ref, fiche.pointId),
            ),
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
        ),
      ],
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
                      valeur: demande.articleId,
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
                            child: Text(
                              'Créez d’abord un article dans l’écran Stocks.',
                            ),
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Sélectionnez un article avant d'exporter.",
          key: Key('fiche-export-absente'),
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
        '${article ?? '—'} · $debut → $fin',
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

/// La fiche CONSOLIDÉE : les quatre cartes, la phrase d'aide et le tableau du
/// détail — leurs étiquettes et leurs en-têtes, sans valeur : la source des
/// mouvements n'est pas sur ce poste (PA-134).
class _FicheConsolidee extends StatelessWidget {
  const _FicheConsolidee();

  static const _cartes = [
    'Articles au catalogue',
    'Articles mouvementes',
    'Mouvements sur la periode',
    'Valeur du stock theorique',
  ];

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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                  for (final libelle in _cartes)
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
                              '—',
                              style: _t(
                                TaillesContenu.lg,
                                poids: FontWeight.bold,
                                couleur: AppColors.navy,
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
            'Chaque ligne garde l’unite et le solde de son propre article : '
            'les quantites d’articles differents ne s’additionnent pas.',
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
                      '— mouvement(s)',
                      style: _t(
                        TaillesContenu.t11,
                        couleur: AppColors.neutre400,
                      ),
                    ),
                  ],
                ),
              ),
              const _EnTeteTableau(
                _colonnes,
                parts: [110, 142, 110, 126, 129, 129, 123, 186],
              ),
              _LigneVide(texte: donneeNonDisponible('Les mouvements de stock')),
            ],
          ),
        ),
      ],
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

class _OngletInventaire extends StatelessWidget {
  const _OngletInventaire();

  @override
  Widget build(BuildContext context) {
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
          const _EnTeteTableau([
            'Magasin',
            'Periodicite',
            'Dernier inventaire cloture',
            'Etat',
          ]),
          _LigneVide(texte: donneeNonDisponible('Les points de stockage')),
        ],
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
          _LigneVide(texte: donneeNonDisponible('Les inventaires clôturés')),
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
