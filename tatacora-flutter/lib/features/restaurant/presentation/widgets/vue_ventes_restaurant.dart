// Vue Blade maîtresse (PA-183) : pwa/restaurant/carte.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/fichiers/enregistrement_export.dart';
import '../../../../core/format/formats.dart';
import '../../../../core/impression/entete_parametree.dart';
import '../../../../shared_widgets/modale_export.dart';
import '../../../../shared_widgets/toast_export.dart';
import '../../../bar/impression/etat_ventes_bar.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/pied_pagination.dart';
import '../../../bar/domain/entities/ventes_bar.dart';
import '../../../facturation/presentation/providers_facturation.dart'
    show factureDaoProvider;
import '../../../pos/domain/entities/reference_catalogue.dart';
import '../../../pos/presentation/providers_pos.dart';
import '../../../ventes/domain/lignes_vente_du_rayon.dart';
import 'cadre_ventes_carte.dart';
import 'coquille_restaurant.dart';
import 'corps_carte_commun.dart';
import 'tableau_restaurant.dart';

/// Ce que l'onglet « Ventes du Restaurant » dit d'une donnée absente (réservé :
/// les ventes se calculent sur ce poste depuis le 26/10/2026).
const String ventesRestaurantAbsentes = 'Les lignes de vente du restaurant';

/// Le filtre du panneau — PROPRE à l'onglet (vue l.556-558).
final filtreVentesRestaurantProvider =
    NotifierProvider<FiltreVentesRestaurantNotifier, FiltreVentesBar>(
      FiltreVentesRestaurantNotifier.new,
    );

final class FiltreVentesRestaurantNotifier extends Notifier<FiltreVentesBar> {
  @override
  FiltreVentesBar build() => const FiltreVentesBar();

  void recherche(String t) => state = FiltreVentesBar(
    recherche: t,
    statut: state.statut,
    du: state.du,
    au: state.au,
  );

  void statut(StatutVenteBar? s) => state = FiltreVentesBar(
    recherche: state.recherche,
    statut: s,
    du: state.du,
    au: state.au,
  );

  void du(DateTime? d) => state = FiltreVentesBar(
    recherche: state.recherche,
    statut: state.statut,
    du: d,
    au: state.au,
  );

  void au(DateTime? d) => state = FiltreVentesBar(
    recherche: state.recherche,
    statut: state.statut,
    du: state.du,
    au: d,
  );

  void page(int p) => state = FiltreVentesBar(
    recherche: state.recherche,
    statut: state.statut,
    du: state.du,
    au: state.au,
    page: p < 1 ? 1 : p,
  );
}

/// Les lignes de vente du rayon M4, filtrées et paginées, CALCULÉES sur les
/// paniers de ce poste (`lignesDuRayon`, réplique de
/// `LignesVenteDuRayonService`) : sans serveur. Recomposées à chaque vente.
final ventesRestaurantProvider = FutureProvider.autoDispose<PageVentesBar>((
  ref,
) async {
  ref.watch(paniersProvider);
  final filtre = ref.watch(filtreVentesRestaurantProvider);
  final paniers = await ref.watch(panierDaoProvider).paniers();
  final numeros = await ref.watch(factureDaoProvider).numerosFactureParPanier();
  return pageDuRayon(
    lignesDuRayon(
      paniers,
      ModuleVendable.m4Restaurant,
      filtre,
      numeroFactureParPanier: numeros,
    ),
    filtre,
  );
});

/// L'onglet **« Ventes du Restaurant »** — `pwa/carte/corps.blade.php`
/// l.563-711 : la barre de filtres du panneau, puis le cadre du tableau.
///
/// ## Calculé sur ce poste (26/10/2026)
///
/// Le poste est plus privilégié que le serveur : ses ventes sont ses paniers
/// clôturés ou annulés, plus ceux que les autres postes lui ont rendus. Le
/// filtre de module est celui de la LIGNE (un ticket mixte porte un plat et une
/// bière), une vente annulée reste au registre sans que son montant compte, les
/// bornes de date sont incluses. Écarts nommés : le panier n'a ni numéro de
/// vente ni auteur (« — »), le « Stock actuel » d'un plat se lit sur l'onglet
/// « Carte du jour ».
class VueVentesRestaurant extends ConsumerWidget {
  const VueVentesRestaurant({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(ventesRestaurantProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _FiltresVentes(),
        page.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => CadreVentesSansDonnee(
            cleMessage: const Key('carte-restaurant-ventes-absentes'),
            message:
                'Les lignes de vente du restaurant n’ont pas pu être lues '
                'sur ce poste.',
          ),
          data: (p) => _Tableau(page: p),
        ),
      ],
    );
  }
}

String _fcfa(String brut) =>
    formaterMontantDecimal(brut, suffixe: 'FCFA') ?? '—';

class _Tableau extends ConsumerWidget {
  const _Tableau({required this.page});

  final PageVentesBar page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final petit = styleContenuCarte(TaillesContenu.t12, couleur: Ardoise.c500);
    final normal = styleContenuCarte(TaillesContenu.t13, couleur: Ardoise.c700);
    final gras = styleContenuCarte(
      TaillesContenu.t13,
      poids: FontWeight.w600,
      couleur: Ardoise.c800,
    );
    String horodatage(DateTime? d) => d == null
        ? '—'
        : '${formaterDate(d)} ${d.hour.toString().padLeft(2, '0')}:'
              '${d.minute.toString().padLeft(2, '0')}';
    final totaux = page.totaux;
    final tranche = TranchePage.de(
      total: totaux.lignes,
      page: page.page,
      parPage: page.parPage,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: CadreTableauRestaurant(
        titre: [
          '${totaux.lignes} ligne(s) · Total validé : ${_fcfa(totaux.totalValide)}',
          if (totaux.annulees > 0)
            'dont ${totaux.annulees} annulée(s), hors total',
        ].join(' — '),
        aside: TextesVentesCarte.stockAide,
        corps: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TableauRestaurant(
              gabarit: GabaritTableau.carteVue,
              pleineLargeur: true,
              colonnes: colonnesVentesCarte,
              videSousEntete: true,
              vide: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacingLarge.p14,
                ),
                alignment: Alignment.center,
                child: Text(
                  'Aucune ligne de vente ne correspond à ces critères.',
                  key: const Key('carte-restaurant-ventes-vide'),
                  textAlign: TextAlign.center,
                  style: styleContenuCarte(
                    TaillesContenu.t13,
                    couleur: Ardoise.c400,
                  ),
                ),
              ),
              lignes: [
                for (final l in page.lignes)
                  [
                    Text(horodatage(l.date), style: petit),
                    Text(l.numero ?? '—', style: petit),
                    Text(l.nom, style: gras),
                    Tooltip(
                      message:
                          'Le stock d’un plat se lit sur l’onglet « Carte du '
                          'jour ».',
                      child: Text('—', style: petit),
                    ),
                    Text(_fcfa(l.prixUnitaire), style: normal),
                    Text('${l.quantite}', style: gras),
                    Text(
                      _fcfa(l.montant),
                      style: styleContenuCarte(
                        TaillesContenu.t13,
                        poids: FontWeight.w600,
                        couleur: AppColors.gold,
                      ),
                    ),
                    Tooltip(
                      message: l.motifAnnulation ?? '',
                      child: Text(
                        l.annulee
                            ? TextesVentesCarte.annulee
                            : TextesVentesCarte.validee,
                        style: styleContenuCarte(
                          TaillesContenu.t12,
                          poids: FontWeight.w600,
                          couleur: l.annulee
                              ? PaletteMaitre.rouge600
                              : PaletteMaitre.emeraude700,
                        ),
                      ),
                    ),
                    Text(l.utilisateur ?? '—', style: petit),
                  ],
              ],
            ),
            Container(
              decoration: const BoxDecoration(
                color: Ardoise.c50,
                border: Border(
                  top: BorderSide(color: Ardoise.c300, width: AppSpacing.demi),
                ),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xsPlus,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          TextesVentesCarte.totalPage,
                          style: styleContenuCarte(
                            TaillesContenu.t13,
                            poids: FontWeight.bold,
                            couleur: AppColors.navy,
                          ),
                        ),
                        Text(
                          TextesVentesCarte.totalPageAide,
                          style: styleContenuCarte(
                            TaillesContenu.t11,
                            couleur: Ardoise.c400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _fcfa(page.totalPage),
                    key: const Key('carte-restaurant-ventes-total-page'),
                    style: styleContenuCarte(
                      TaillesContenu.t13,
                      poids: FontWeight.bold,
                      couleur: AppColors.gold,
                    ),
                  ),
                ],
              ),
            ),
            PiedPagination(
              tranche: tranche,
              prefixeCle: 'carte-restaurant-ventes',
              masquerSansPages: true,
              onPage: (p) =>
                  ref.read(filtreVentesRestaurantProvider.notifier).page(p),
            ),
          ],
        ),
      ),
    );
  }
}

/// La barre de filtres du panneau — `bg-white rounded-xl border border-slate-200
/// p-3.5 mb-4`, une rangée `flex flex-wrap gap-2.5 items-center`, puis la note
/// des bornes (`mt-2`) — l.567-596.
class _FiltresVentes extends ConsumerStatefulWidget {
  const _FiltresVentes();

  @override
  ConsumerState<_FiltresVentes> createState() => _FiltresVentesState();
}

class _FiltresVentesState extends ConsumerState<_FiltresVentes> {
  /// `gap-2.5` — 10 px.
  static const double _ecart = AppSpacing.xsPlus;

  late final TextEditingController _terme = TextEditingController(
    text: ref.read(filtreVentesRestaurantProvider).recherche,
  );

  @override
  void dispose() {
    _terme.dispose();
    super.dispose();
  }

  Future<void> _choisir({required bool debut}) async {
    final filtre = ref.read(filtreVentesRestaurantProvider);
    final actuelle = debut ? filtre.du : filtre.au;
    final choisie = await showDatePicker(
      context: context,
      initialDate: actuelle ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (choisie == null || !mounted) return;
    final n = ref.read(filtreVentesRestaurantProvider.notifier);
    debut ? n.du(choisie) : n.au(choisie);
  }

  /// La largeur d'un texte, pour décider si la rangée tient sur une ligne.
  double _largeur(String texte, TextStyle style) {
    final mesure = TextPainter(
      text: TextSpan(text: texte, style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    return mesure.width;
  }

  @override
  Widget build(BuildContext context) {
    final filtre = ref.watch(filtreVentesRestaurantProvider);
    final notifier = ref.read(filtreVentesRestaurantProvider.notifier);
    final styleBorne = styleContenuCarte(
      TaillesContenu.t12,
      couleur: Ardoise.c500,
    );

    final recherche = TextField(
      key: const Key('carte-restaurant-ventes-recherche'),
      controller: _terme,
      style: styleContenuCarte(TaillesContenu.t13),
      decoration: decorationRechercheCarte(TextesVentesCarte.recherche),
      onChanged: notifier.recherche,
    );

    final statut = ListeFiltre<String>(
      cleListe: const Key('carte-restaurant-ventes-statut'),
      largeur: AppLayout.filtreStatutVentesCarte,
      valeur: filtre.statut?.code ?? '',
      options: const [
        ('', TextesVentesCarte.tousStatuts),
        ('validee', TextesVentesCarte.validee),
        ('annulee', TextesVentesCarte.annulee),
      ],
      onChange: (code) => notifier.statut(
        StatutVenteBar.values.where((s) => s.code == code).firstOrNull,
      ),
    );

    Widget borne(String libelle, Key cle, {required bool debut}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(libelle, style: styleBorne),
        // `gap-1.5` — 6 px.
        const SizedBox(width: AppSpacing.xxs),
        _ChampDate(
          cle: cle,
          valeur: debut ? filtre.du : filtre.au,
          onTap: () => _choisir(debut: debut),
          onEffacer: () => debut ? notifier.du(null) : notifier.au(null),
        ),
      ],
    );

    final du = borne(
      TextesVentesCarte.du,
      const Key('carte-restaurant-ventes-du'),
      debut: true,
    );
    final au = borne(
      TextesVentesCarte.au,
      const Key('carte-restaurant-ventes-au'),
      debut: false,
    );

    return Container(
      // `mb-4`, `p-3.5`.
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.smPlus),
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: Ardoise.c200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, contraintes) {
              // Ce que prennent les contrôles qui ne s'étirent pas : la liste
              // et les deux bornes (libellé, 6 px, champ).
              final controles =
                  AppLayout.filtreStatutVentesCarte +
                  2 * (AppLayout.champDateVentesCarte + AppSpacing.xxs) +
                  _largeur(TextesVentesCarte.du, styleBorne) +
                  _largeur(TextesVentesCarte.au, styleBorne);
              final minimum =
                  AppLayout.rechercheMinCarteRestaurant +
                  controles +
                  _ecart * 3;

              if (contraintes.maxWidth >= minimum) {
                return Row(
                  children: [
                    Expanded(child: recherche),
                    const SizedBox(width: _ecart),
                    statut,
                    const SizedBox(width: _ecart),
                    du,
                    const SizedBox(width: _ecart),
                    au,
                  ],
                );
              }

              // Trop étroit : `flex-wrap` — la recherche prend sa ligne.
              return Wrap(
                spacing: _ecart,
                runSpacing: _ecart,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(width: contraintes.maxWidth, child: recherche),
                  statut,
                  du,
                  au,
                ],
              );
            },
          ),
          // `mt-2` — 8 px (l.595).
          const SizedBox(height: AppSpacing.xs),
          Text(
            TextesVentesCarte.bornesAide,
            style: styleContenuCarte(TaillesContenu.t11, couleur: Ardoise.c400),
          ),
        ],
      ),
    );
  }
}

/// Un `<input type="date">` — `text-[13px] border border-slate-300 rounded-lg
/// px-3 py-2` (l.584-585) : « jj/mm/aaaa » tant que rien n'est choisi, puis la
/// date choisie ; un toucher ouvre le calendrier, la croix efface la borne.
class _ChampDate extends StatelessWidget {
  const _ChampDate({
    required this.cle,
    required this.valeur,
    required this.onTap,
    required this.onEffacer,
  });

  final Key cle;
  final DateTime? valeur;
  final VoidCallback onTap;
  final VoidCallback onEffacer;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: cle,
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      child: Container(
        width: AppLayout.champDateVentesCarte,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.neutre0,
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
          border: Border.all(color: Ardoise.c300),
        ),
        child: SizedBox(
          // Une ligne de texte, comme la liste voisine.
          height: TaillesContenu.t13 * 1.5,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  valeur == null ? 'jj/mm/aaaa' : formaterDate(valeur!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: styleContenuCarte(
                    TaillesContenu.t13,
                    couleur: Ardoise.c700,
                  ),
                ),
              ),
              if (valeur != null)
                GestureDetector(
                  key: Key('${(cle as ValueKey<String>).value}-effacer'),
                  onTap: onEffacer,
                  child: const Icon(
                    Icons.close,
                    size: AppLayout.iconeChamp,
                    color: Ardoise.c500,
                  ),
                )
              else
                const Icon(
                  Icons.calendar_today_outlined,
                  size: AppLayout.iconeChamp,
                  color: Ardoise.c500,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Le titre de la vue (`carte_pwa.restaurant.export_titre_ventes`).
const String titreExportVentesRestaurant = 'Exporter — Ventes du Restaurant';

/// Le titre du document exporté.
const String titreDocumentVentesRestaurant = 'Ventes du Restaurant';

/// « Exporter » sur l'onglet des ventes : la modale de format, puis le JEU
/// FILTRÉ ENTIER (jamais la seule page) en PDF A4 ou en tableur, calculé sur
/// ce poste. Une liste vide se refuse APRÈS le choix du format.
Future<void> exporterVentesRestaurant(
  BuildContext context,
  WidgetRef ref,
) async {
  final format = await choisirFormatExport(
    context,
    titre: titreExportVentesRestaurant,
  );
  if (format == null || !context.mounted) return;

  final filtre = ref.read(filtreVentesRestaurantProvider);
  final paniers = await ref.read(panierDaoProvider).paniers();
  final numeros = await ref.read(factureDaoProvider).numerosFactureParPanier();
  final lignes = lignesDuRayon(
    paniers,
    ModuleVendable.m4Restaurant,
    filtre,
    numeroFactureParPanier: numeros,
  );
  if (!context.mounted) return;
  if (lignes.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Aucune ligne de vente ne correspond à ces critères : il n’y a '
          'rien à exporter. Élargissez la période ou le statut plutôt que de '
          'produire un document que l’on croirait complet.',
          key: Key('carte-restaurant-export-ventes-vide'),
        ),
      ),
    );
    return;
  }
  final totaux = totauxDuRayon(lignes);
  final description = descriptionFiltreVentes(filtre);
  final export = ref.read(enregistrementExportProvider);
  await executerExport(
    context,
    () async => switch (format) {
      FormatExport.pdf => export.exporter(
        base: 'ventes_du_restaurant',
        type: TypeFichierEnregistre.pdf,
        octets: await EtatVentesBar.pdf(
          lignes,
          totaux,
          filtre: description,
          carte: const [],
          entete: await ref.read(lireEnteteEtablissementProvider)(),
          titreDocument: titreDocumentVentesRestaurant,
        ),
      ),
      FormatExport.excel => export.exporter(
        base: 'ventes_du_restaurant',
        type: TypeFichierEnregistre.csv,
        octets: EtatVentesBar.csvOctets(
          lignes,
          totaux,
          filtre: description,
          carte: const [],
          titreDocument: titreDocumentVentesRestaurant,
        ),
      ),
    },
    cleSucces: const Key('carte-restaurant-export-ventes-fait'),
  );
}
