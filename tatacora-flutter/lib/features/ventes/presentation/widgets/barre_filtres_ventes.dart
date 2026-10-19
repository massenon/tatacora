import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/bouton_standard.dart';
import '../../../../shared_widgets/modale_export.dart';
import '../../../../shared_widgets/toast_export.dart';
import '../../../pos/domain/entities/mode_reglement.dart';
import '../../../pos/domain/entities/reference_catalogue.dart';
import '../../domain/entities/vente.dart';
import '../../domain/journal_ventes.dart';
import '../../impression/etat_journal_ventes.dart';
import '../providers_ventes.dart';

/// Les sept filtres du journal et « Exporter » — la barre de la carte
/// (`px-4 py-3 border-b flex flex-wrap items-center gap-2`), puis la ligne
/// « Filtre appliqué : … ».
///
/// ## L'aide du champ de recherche dit la VÉRITÉ
///
/// La vue écrit « N° de vente, table, chambre… ». Ce client ne cherche ni par
/// numéro de vente (aucune séquence n'existe ici) ni par chambre (un panier de
/// séjour porte la réservation, pas l'unité) : l'aide dit ce qui est réellement
/// cherché, plutôt que de promettre une recherche qui ne rendrait jamais rien.
///
/// ## Un seul « Exporter » (dérogation du Product Owner du 01/09/2026)
///
/// Les deux boutons du maître sont remplacés par UN bouton qui ouvre le choix
/// Excel/PDF. L'export porte sur **ce qui est affiché** et se refuse sur une
/// liste vide (PA-119).
class BarreFiltresVentes extends ConsumerStatefulWidget {
  const BarreFiltresVentes({super.key});

  /// L'aide du champ de recherche — ce qui est réellement cherché.
  static const String texteAide = 'Référence, table, client, poste…';

  @override
  ConsumerState<BarreFiltresVentes> createState() => _BarreFiltresVentesState();
}

class _BarreFiltresVentesState extends ConsumerState<BarreFiltresVentes> {
  final _terme = TextEditingController();

  @override
  void dispose() {
    _terme.dispose();
    super.dispose();
  }

  void _maj(FiltreVentes nouveau) =>
      ref.read(filtreVentesProvider.notifier).definir(nouveau);

  @override
  Widget build(BuildContext context) {
    final filtre = ref.watch(filtreVentesProvider);
    final postes = ref.watch(postesJournalProvider);

    final bordure = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      borderSide: const BorderSide(color: AppColors.neutre300),
    );

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md, // px-4
        vertical: AppSpacing.sm, // py-3
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.neutre200)),
      ),
      child: Row(
        // `<div class="flex-1"></div>` + « Exporter » : le bouton est calé à
        // droite de la DERNIÈRE ligne des filtres, quand ceux-ci passent à la
        // ligne.
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Wrap(
              spacing: AppSpacing.xs, // gap-2
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: AppLayout.rechercheVentes,
                  child: TextField(
                    key: const Key('ventes-recherche'),
                    controller: _terme,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.police,
                      fontSize: TaillesContenu.t13,
                      height: 1.5,
                    ),
                    decoration: InputDecoration(
                      hintText: BarreFiltresVentes.texteAide,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xxs,
                      ),
                      border: bordure,
                      enabledBorder: bordure,
                      focusedBorder: bordure.copyWith(
                        borderSide: const BorderSide(color: AppColors.gold),
                      ),
                    ),
                    onChanged: (v) => _maj(filtre.copyWith(terme: v)),
                  ),
                ),
                _Liste<String>(
                  cle: const Key('ventes-filtre-poste'),
                  valeur: filtre.pointVente,
                  libelleVide: 'Tous les postes',
                  options: [for (final p in postes) (p, p)],
                  onChoix: (v) => _maj(filtre.copyWith(pointVente: v)),
                ),
                _Liste<ModuleVendable>(
                  cle: const Key('ventes-filtre-activite'),
                  valeur: filtre.activite,
                  libelleVide: 'Toutes les activités',
                  options: [
                    for (final m in ModuleVendable.values) (m, m.libelle),
                  ],
                  onChoix: (v) => _maj(filtre.copyWith(activite: v)),
                ),
                _Liste<ModeReglement>(
                  cle: const Key('ventes-filtre-reglement'),
                  valeur: filtre.mode,
                  libelleVide: 'Tous les règlements',
                  options: [
                    for (final m in ModeReglement.values) (m, m.libelle),
                  ],
                  onChoix: (v) => _maj(filtre.copyWith(mode: v)),
                ),
                _Liste<StatutVente>(
                  cle: const Key('ventes-filtre-statut'),
                  valeur: filtre.statut,
                  libelleVide: 'Tous les statuts',
                  options: [
                    for (final s in StatutVente.values) (s, s.libelleFiltre),
                  ],
                  onChoix: (v) => _maj(filtre.copyWith(statut: v)),
                ),
                _ChampDate(
                  prefixeCle: 'ventes-filtre-debut',
                  libelle: 'Début',
                  valeur: filtre.debut,
                  onChoix: (d) => _maj(filtre.copyWith(debut: d)),
                ),
                _ChampDate(
                  prefixeCle: 'ventes-filtre-fin',
                  libelle: 'Fin',
                  valeur: filtre.fin,
                  onChoix: (d) => _maj(filtre.copyWith(fin: d)),
                ),
              ],
            ),
          ),
          const _BoutonExporter(),
        ],
      ),
    );
  }
}

/// `text-[13px] border border-slate-300 rounded-lg px-2.5 py-1.5 bg-white`
class _Liste<T> extends StatelessWidget {
  const _Liste({
    required Key cle,
    required this.valeur,
    required this.libelleVide,
    required this.options,
    required this.onChoix,
  }) : super(key: cle);

  final T? valeur;
  final String libelleVide;
  final List<(T, String)> options;
  final ValueChanged<T?> onChoix;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        border: Border.all(color: AppColors.neutre300),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xsPlus, // px-2.5
          vertical: AppSpacing.xxs, // py-1.5
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T?>(
            value: valeur,
            isDense: true,
            itemHeight: null,
            // L'icône par défaut (24 px) grandit la liste au-delà de sa ligne.
            iconSize: AppLayout.iconeChamp,
            style: const TextStyle(
              fontFamily: AppTextStyles.police,
              fontSize: TaillesContenu.t13,
              height: 1.5,
              color: AppColors.neutre700,
            ),
            items: [
              DropdownMenuItem<T?>(child: Text(libelleVide)),
              for (final (v, libelle) in options)
                DropdownMenuItem<T?>(value: v, child: Text(libelle)),
            ],
            onChanged: onChoix,
          ),
        ),
      ),
    );
  }
}

/// Une borne de période. Le maître emploie un `<input type="date">` ; Flutter
/// n'en a pas en natif, donc un champ au même cadre qui ouvre le sélecteur de
/// date. Une borne posée se réinitialise d'un geste.
class _ChampDate extends StatelessWidget {
  const _ChampDate({
    required this.prefixeCle,
    required this.libelle,
    required this.valeur,
    required this.onChoix,
  });

  /// Les clés `<prefixe>` (le champ) et `<prefixe>-effacer` (la croix).
  final String prefixeCle;

  final String libelle;
  final DateTime? valeur;
  final ValueChanged<DateTime?> onChoix;

  @override
  Widget build(BuildContext context) {
    final d = valeur;

    return SizedBox(
      width: AppLayout.champDateVentes,
      child: Material(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        child: InkWell(
          key: Key(prefixeCle),
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
          onTap: () async {
            final choisie = await showDatePicker(
              context: context,
              initialDate: d ?? DateTime.now(),
              // Bornes larges : un journal de poste peut porter des ventes
              // anciennes, et une borne trop courte les rendrait inatteignables.
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
            );
            if (choisie != null) onChoix(choisie);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xsPlus,
              vertical: AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
              border: Border.all(color: AppColors.neutre300),
            ),
            child: Row(
              children: [
                Text(
                  d == null
                      ? libelle
                      : '${d.day.toString().padLeft(2, '0')}/'
                            '${d.month.toString().padLeft(2, '0')}/${d.year}',
                  style: TextStyle(
                    fontFamily: AppTextStyles.police,
                    fontSize: TaillesContenu.t13,
                    height: 1.5,
                    color: d == null
                        ? AppColors.neutre500
                        : AppColors.neutre700,
                  ),
                ),
                if (d != null) ...[
                  const SizedBox(width: AppSpacing.unit),
                  GestureDetector(
                    key: Key('$prefixeCle-effacer'),
                    onTap: () => onChoix(null),
                    child: const Icon(
                      Icons.close,
                      size: AppLayout.iconeChamp,
                      color: AppColors.neutre500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `text-[12px] px-3 py-1.5 rounded-lg bg-[var(--navy)] text-white font-semibold`
///
/// Il ouvre la modale d'export PARTAGÉE (PO, 14/10/2026) — l'ancien dialogue
/// à deux boutons « Export Excel » / « Export PDF » est retiré. Le document
/// choisi passe par la fenêtre « Enregistrer sous », et l'issue est dite par
/// le toast commun.
class _BoutonExporter extends ConsumerWidget {
  const _BoutonExporter();

  /// Le titre de la modale (PO, 14/10/2026).
  static const String titreModale = 'Exporter le journal des ventes';

  /// Le bouton standard compact (PO, 14/10/2026).
  @override
  Widget build(BuildContext context, WidgetRef ref) => BoutonStandard(
    key: const Key('ventes-exporter'),
    libelle: TextesExport.bouton,
    variante: VarianteBouton.primaire,
    // `text-[12px] px-3 py-1.5 … font-semibold` : pas `compact`, qui
    // rendrait le texte en graisse normale.
    taillePolice: TaillesContenu.t12,
    margeHorizontale: AppSpacing.sm,
    margeVerticale: AppSpacing.xxs,
    onPressed: () => _exporter(context, ref),
  );

  Future<void> _exporter(BuildContext context, WidgetRef ref) async {
    final format = await choisirFormatExport(context, titre: titreModale);
    if (format == null || !context.mounted) return;

    final etat = composerEtatJournal(ref);
    if (etat.estVide) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            messageExportVentesVide,
            key: Key('ventes-export-vide'),
          ),
        ),
      );
      return;
    }

    await executerExport(
      context,
      () => switch (format) {
        FormatExport.pdf => ref.read(exporterJournalVentesPdfProvider)(etat),
        FormatExport.excel => ref.read(exporterJournalVentesProvider)(etat),
      },
      cleSucces: const Key('ventes-export-chemin'),
    );
  }
}
