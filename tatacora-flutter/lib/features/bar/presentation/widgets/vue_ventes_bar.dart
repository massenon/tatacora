// Vue Blade maîtresse (PA-183) : pwa/bar/carte.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../restaurant/presentation/widgets/cadre_ventes_carte.dart';
import '../../data/boissons_api.dart';
import '../../domain/entities/carte_bar.dart';
import '../../domain/entities/ventes_bar.dart';
import '../../impression/etat_ventes_bar.dart';
import '../providers_bar.dart';
import '../providers_catalogue_boissons.dart';
import '../../../../shared_widgets/modale_export.dart';
import '../../../../shared_widgets/toast_export.dart';
import 'table_carte.dart';

/// Les mots du panneau, au mot de la vue (`carte_pwa.commun.ventes_*`).
abstract final class TextesVentesBar {
  // Les mots COMMUNS aux deux cartes vivent à un seul endroit
  // (`cadre_ventes_carte.dart`, 09/10/2026) : le panneau est le même fichier
  // côté serveur, et deux listes de libellés finiraient par diverger.
  static const recherche = TextesVentesCarte.recherche;
  static const tousStatuts = TextesVentesCarte.tousStatuts;
  static const du = TextesVentesCarte.du;
  static const au = TextesVentesCarte.au;
  static const bornesAide = TextesVentesCarte.bornesAide;
  static final colonnes = [for (final c in colonnesVentesCarte) c.titre];
  static String compteur(int nombre, String total) =>
      '$nombre ligne(s) · Total validé : $total';
  static String annulees(int nombre) => 'dont $nombre annulée(s), hors total';
  static const stockAide = TextesVentesCarte.stockAide;
  static const horsCarte =
      "Cet article n'est plus à la carte : son stock ne se lit plus nulle "
      "part. Ce n'est pas un stock nul.";
  static const vide = 'Aucune ligne de vente ne correspond à ces critères.';
  static const totalPage = TextesVentesCarte.totalPage;
  static const totalPageAide = TextesVentesCarte.totalPageAide;
  static String affichage(int debut, int fin, int total) =>
      'Affichage de $debut-$fin sur $total';

  /// `carte_pwa.bar.export_titre_ventes`.
  static const exportTitre = 'Exporter — Ventes du Bar';

  /// `carte_pwa.export_ventes_vide`.
  static const exportVide =
      "Aucune ligne de vente ne correspond à ces critères : il n'y a rien à exporter. Élargissez la période ou le statut plutôt que de produire un document que l'on croirait complet.";

  /// Hors connexion — l'onglet lit le SERVEUR, sans cache : il le dit, et
  /// n'affiche aucune ligne. Garder la dernière réponse montrerait les ventes
  /// d'hier sous un tableau qui ne dit pas qu'il date.
  static const injoignable =
      'Serveur injoignable : les ventes du bar se lisent au serveur, et ce '
      'poste ne les garde pas. Rien n’est affiché plutôt qu’une liste périmée.';
}

/// L'onglet « Ventes du Bar » — `pwa/carte/corps.blade.php` l.555-700.
///
/// ## Le stock est celui d'AUJOURD'HUI, lu dans la carte
///
/// La colonne « Stock actuel » vient de la carte du jour ([carte]), par le
/// `code` figé de la ligne, et elle est rendue par [CelluleStockCarte] — la
/// même cellule que l'onglet « Carte du jour », comme la vue le fait avec
/// `pwa.carte.cellule-stock`. Une ligne dont l'article n'est plus à la carte
/// rend « — » : elle n'a pas un stock nul, elle n'a plus d'article où le lire.
///
/// ## L'export
///
/// « Exporter — Ventes du Bar » compose au poste le document du JEU FILTRÉ
/// ENTIER ([EtatVentesBar], traduction de `pdf/carte-ventes`) : en-tête RG-19,
/// filtre et résumé, zone de signatures de la directive, pied de rapport.
class VueVentesBar extends ConsumerWidget {
  const VueVentesBar({required this.carte, super.key});

  /// La carte du jour NON filtrée — celle où chaque ligne lit son stock.
  final List<LigneCarte> carte;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultat = ref.watch(ventesBarProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // « Exporter » n'est plus ici : c'est le bouton unique de l'EN-TÊTE de
        // la vue (l.101-102), qui exporte l'onglet ACTIF et appelle
        // [exporterVentesBar] quand c'est celui-ci (`exportDesVentes()`).
        const _FiltresVentes(),
        const SizedBox(height: AppSpacing.md),
        resultat.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('$e'),
          data: (r) => switch (r) {
            BarRecu(:final donnees) => _Tableau(page: donnees, carte: carte),
            // Sans ligne, la vue montre quand même son cadre : titre,
            // colonnes, ligne de total (l.598-695). Il le dit sans zéro.
            BarRefuse(:final motif) => CadreVentesSansDonnee(
              cleMessage: const Key('ventes-bar-refuse'),
              message: motif,
            ),
            BarInjoignable() => const CadreVentesSansDonnee(
              cleMessage: Key('ventes-bar-injoignable'),
              message: TextesVentesBar.injoignable,
            ),
          },
        ),
      ],
    );
  }
}

/// « Exporter » → la modale de format → le JEU FILTRÉ ENTIER → le document.
///
/// La liste vide est refusée APRÈS le choix du format, comme
/// `EcranDeCarte::genererExport()`, avec la phrase de la vue
/// (`carte_pwa.export_ventes_vide`). Un refus ou une coupure pendant la
/// lecture des pages ne produit RIEN : un document amputé se lirait complet.
Future<void> exporterVentesBar(BuildContext context, WidgetRef ref) async {
  final format = await choisirFormatExport(
    context,
    // `carte_pwa.bar.export_titre_ventes`.
    titre: TextesVentesBar.exportTitre,
  );
  if (format == null || !context.mounted) return;

  final filtre = ref.read(filtreVentesBarProvider);
  final resultat = await ref.read(boissonsApiProvider).toutesLesVentes(filtre);
  if (!context.mounted) return;

  void dire(String texte, String cle) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(texte, key: Key(cle))));

  final (List<LigneVenteBar>, TotauxVentesBar) jeu;
  switch (resultat) {
    case BarRecu(:final donnees):
      jeu = donnees;
    case BarRefuse(:final motif):
      return dire(motif, 'ventes-bar-export-refuse');
    case BarInjoignable():
      return dire(TextesVentesBar.injoignable, 'ventes-bar-export-injoignable');
  }

  final (lignes, totaux) = jeu;
  if (lignes.isEmpty) {
    return dire(TextesVentesBar.exportVide, 'ventes-bar-export-vide');
  }

  final carte = await ref.read(carteBarProvider.future);
  final description = descriptionFiltreVentes(filtre);
  if (!context.mounted) return;
  await executerExport(
    context,
    () => switch (format) {
      FormatExport.pdf => ref.read(exporterVentesBarPdfProvider)(
        lignes,
        totaux,
        description,
        carte,
      ),
      FormatExport.excel => ref.read(exporterVentesBarProvider)(
        lignes,
        totaux,
        description,
        carte,
      ),
    },
    cleSucces: const Key('ventes-bar-export-fait'),
  );
}

/// La barre de filtres du panneau (vue l.559-588).
class _FiltresVentes extends ConsumerStatefulWidget {
  const _FiltresVentes();

  @override
  ConsumerState<_FiltresVentes> createState() => _FiltresVentesState();
}

class _FiltresVentesState extends ConsumerState<_FiltresVentes> {
  late final TextEditingController _terme = TextEditingController(
    text: ref.read(filtreVentesBarProvider).recherche,
  );

  @override
  void dispose() {
    _terme.dispose();
    super.dispose();
  }

  Future<void> _choisirDate({required bool debut}) async {
    final filtre = ref.read(filtreVentesBarProvider);
    final actuelle = debut ? filtre.du : filtre.au;
    final choisie = await showDatePicker(
      context: context,
      initialDate: actuelle ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (choisie == null || !mounted) return;
    final notifier = ref.read(filtreVentesBarProvider.notifier);
    debut ? notifier.du(choisie) : notifier.au(choisie);
  }

  @override
  Widget build(BuildContext context) {
    final filtre = ref.watch(filtreVentesBarProvider);
    final notifier = ref.read(filtreVentesBarProvider.notifier);

    Widget borne({required bool debut}) {
      final valeur = debut ? filtre.du : filtre.au;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            debut ? TextesVentesBar.du : TextesVentesBar.au,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(width: AppSpacing.xxs),
          OutlinedButton(
            key: Key(debut ? 'ventes-bar-du' : 'ventes-bar-au'),
            onPressed: () => _choisirDate(debut: debut),
            child: Text(valeur == null ? 'jj/mm/aaaa' : formaterDate(valeur)),
          ),
          if (valeur != null)
            IconButton(
              key: Key(
                debut ? 'ventes-bar-du-effacer' : 'ventes-bar-au-effacer',
              ),
              tooltip: 'Effacer',
              icon: const Icon(Icons.close, size: 16),
              onPressed: () => debut ? notifier.du(null) : notifier.au(null),
            ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppSpacing.md),
        border: Border.all(color: AppColors.neutre200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: AppLayout.rechercheMinCarteRestaurant,
                  maxWidth: AppLayout.rechercheRestauration,
                ),
                child: TextField(
                  key: const Key('ventes-bar-recherche'),
                  controller: _terme,
                  decoration: const InputDecoration(
                    hintText: TextesVentesBar.recherche,
                    prefixIcon: Icon(Icons.search, size: 16),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: notifier.recherche,
                ),
              ),
              SizedBox(
                width: AppLayout.filtreCarteRestaurant,
                child: DropdownButtonFormField<StatutVenteBar?>(
                  key: const Key('ventes-bar-statut'),
                  initialValue: filtre.statut,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<StatutVenteBar?>(
                      child: Text(TextesVentesBar.tousStatuts),
                    ),
                    for (final s in StatutVenteBar.values)
                      DropdownMenuItem<StatutVenteBar?>(
                        value: s,
                        child: Text(s.libelle),
                      ),
                  ],
                  onChanged: notifier.statut,
                ),
              ),
              borne(debut: true),
              borne(debut: false),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            TextesVentesBar.bornesAide,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _Tableau extends ConsumerWidget {
  const _Tableau({required this.page, required this.carte});

  final PageVentesBar page;
  final List<LigneCarte> carte;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parId = {for (final l in carte) l.id: l};
    final styleEntete = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: AppColors.neutre0,
      fontWeight: FontWeight.w700,
    );
    String fcfa(String brut) =>
        formaterMontantDecimal(brut, suffixe: 'FCFA') ?? '—';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppSpacing.md),
        border: Border.all(color: AppColors.neutre200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Le COMPTEUR porte sur le jeu filtré ENTIER, jamais sur la page.
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                Text.rich(
                  key: const Key('ventes-bar-compteur'),
                  TextSpan(
                    text: TextesVentesBar.compteur(
                      page.totaux.lignes,
                      fcfa(page.totaux.totalValide),
                    ),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w700,
                    ),
                    children: [
                      if (page.totaux.annulees > 0)
                        TextSpan(
                          text:
                              ' — ${TextesVentesBar.annulees(page.totaux.annulees)}',
                          style: const TextStyle(
                            color: AppColors.erreur,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  TextesVentesBar.stockAide,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: const WidgetStatePropertyAll(AppColors.navy),
              columns: [
                for (final (i, c) in TextesVentesBar.colonnes.indexed)
                  DataColumn(
                    numeric: i >= 3,
                    label: Text(c.toUpperCase(), style: styleEntete),
                  ),
              ],
              rows: [
                for (final l in page.lignes)
                  DataRow(
                    cells: [
                      for (final cellule in _cellules(context, l, parId, fcfa))
                        DataCell(
                          l.annulee
                              ? Opacity(
                                  opacity: AppLayout.opaciteLigneRetiree,
                                  child: cellule,
                                )
                              : cellule,
                        ),
                    ],
                  ),
                // L'état vide garde les en-têtes et DIT pourquoi il est vide.
                if (page.lignes.isEmpty)
                  DataRow(
                    cells: [
                      const DataCell(
                        Text(TextesVentesBar.vide, key: Key('ventes-bar-vide')),
                      ),
                      for (var i = 1; i < TextesVentesBar.colonnes.length; i++)
                        const DataCell(SizedBox.shrink()),
                    ],
                  ),
                // TOTAL DE LA PAGE — les lignes VALIDÉES affichées seulement.
                DataRow(
                  color: const WidgetStatePropertyAll(AppColors.neutre50),
                  cells: [
                    DataCell(
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            TextesVentesBar.totalPage,
                            style: const TextStyle(
                              color: AppColors.navy,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            TextesVentesBar.totalPageAide,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                    for (var i = 1; i < 6; i++)
                      const DataCell(SizedBox.shrink()),
                    DataCell(
                      Text(
                        fcfa(page.totalPage),
                        key: const Key('ventes-bar-total-page'),
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        page.annuleesPage > 0
                            ? TextesVentesBar.annulees(page.annuleesPage)
                            : '',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    const DataCell(SizedBox.shrink()),
                  ],
                ),
              ],
            ),
          ),
          _Pagination(page: page),
        ],
      ),
    );
  }

  List<Widget> _cellules(
    BuildContext context,
    LigneVenteBar l,
    Map<String, LigneCarte> parId,
    String Function(String) fcfa,
  ) {
    final petit = Theme.of(context).textTheme.labelMedium;
    final articleDeCarte = l.code == null ? null : parId[l.code];
    final date = l.date;

    return [
      Text(
        date == null
            ? '—'
            : '${formaterDate(date)} '
                  '${date.hour.toString().padLeft(2, '0')}:'
                  '${date.minute.toString().padLeft(2, '0')}',
        style: petit,
      ),
      Text(l.numero ?? '—', style: petit),
      Text(l.nom, style: const TextStyle(fontWeight: FontWeight.w600)),
      articleDeCarte != null
          ? CelluleStockCarte(ligne: articleDeCarte)
          : Tooltip(
              message: TextesVentesBar.horsCarte,
              child: Text(
                '—',
                key: Key('ventes-bar-hors-carte-${l.id}'),
                style: petit,
              ),
            ),
      Text(fcfa(l.prixUnitaire)),
      Text(
        '${l.quantite}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      Text(
        fcfa(l.montant),
        style: const TextStyle(
          color: AppColors.gold,
          fontWeight: FontWeight.w600,
        ),
      ),
      _BadgeStatut(ligne: l),
      Text(l.utilisateur ?? '—', style: petit),
    ];
  }
}

/// « Validée » / « Annulée » — le motif d'une annulation part en infobulle
/// (vue l.650-660) : le tableau dirait sinon « annulée » sans dire pourquoi.
class _BadgeStatut extends StatelessWidget {
  const _BadgeStatut({required this.ligne});

  final LigneVenteBar ligne;

  @override
  Widget build(BuildContext context) {
    final statut = ligne.annulee
        ? StatutVenteBar.annulee
        : StatutVenteBar.validee;
    final badge = Container(
      key: Key('ventes-bar-statut-${ligne.id}'),
      padding: const EdgeInsets.symmetric(
        // `px-1.5 py-0.5` de la vue (l.654-659) — 6 px et 2 px.
        horizontal: AppSpacing.xxs,
        vertical: AppSpacing.demi,
      ),
      decoration: BoxDecoration(
        color: ligne.annulee
            ? AppColors.badgeRougeFond
            : AppColors.badgeVertFond,
        borderRadius: BorderRadius.circular(AppSpacing.xxs),
      ),
      child: Text(
        statut.libelle,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: ligne.annulee ? AppColors.erreur : AppColors.succes,
        ),
      ),
    );
    final motif = ligne.motifAnnulation;
    return ligne.annulee && motif != null && motif.isNotEmpty
        ? Tooltip(message: motif, child: badge)
        : badge;
  }
}

class _Pagination extends ConsumerWidget {
  const _Pagination({required this.page});

  final PageVentesBar page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(filtreVentesBarProvider.notifier);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            TextesVentesBar.affichage(
              page.premier,
              page.dernier,
              page.totaux.lignes,
            ),
            key: const Key('ventes-bar-affichage'),
            style: Theme.of(context).textTheme.labelMedium,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: const Key('ventes-bar-page-precedente'),
                icon: const Icon(Icons.chevron_left),
                onPressed: page.page > 1
                    ? () => notifier.page(page.page - 1)
                    : null,
              ),
              Text('${page.page} / ${page.derniere}'),
              IconButton(
                key: const Key('ventes-bar-page-suivante'),
                icon: const Icon(Icons.chevron_right),
                onPressed: page.page < page.derniere
                    ? () => notifier.page(page.page + 1)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
