// Vue Blade maîtresse (PA-183) : pwa/livewire/accueil.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/format/formats.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../depenses/presentation/providers_depenses.dart';
import '../../pos/presentation/providers_pos.dart';
import '../data/sources_croise.dart';
import '../domain/croise_local.dart';
import '../domain/entities/tableau_de_bord.dart';
import '../domain/periode_locale.dart';
import 'ecran_pilotage_consolide.dart' show exporterTableauDeBord;

/// Le panneau « Tableau croisé dynamique » de la vue d'accueil
/// (`accueil.blade.php`, `data-panneau-tb="croise"`, l.1247-1388).
///
/// Porté le 13/10/2026 (`INSTRUCTION1.txt` du PO) : l'onglet était inerte
/// sur un motif périmé. Les données sont celles du POSTE (ventes clôturées,
/// dépenses, réservations), le calcul celui du serveur (`croise_local.dart`,
/// confronté au vrai `Accueil::croiser`).
///
/// ## La période est celle de l'en-tête
///
/// La fenêtre est la MÊME que celle de la bande d'indicateurs (`$periode` de la
/// vue) : un seul sélecteur pour tout l'écran. Tant que la bande n'a rien rendu,
/// aucun croisement n'est affiché.
///
/// ## Un écart, nommé
///
/// La vue pose les quatre sélecteurs et le bouton « Exporter » dans une seule
/// ligne `flex flex-wrap items-end gap-3` avec un `flex-1` qui pousse le bouton
/// à droite ; un `Wrap` Flutter n'a pas d'élément extensible : le bouton est
/// tenu à droite par une `Row`, les sélecteurs passent à la ligne à sa gauche.
class PanneauTableauCroise extends ConsumerWidget {
  const PanneauTableauCroise({required this.tableau, super.key});

  /// La réponse de la bande (ses bornes). `null` : rien n'a été reçu.
  final TableauDeBord? tableau;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configurationCroiseProvider);
    final sources = ref.watch(sourcesCroiseLuesProvider);
    final debut = tableau?.debut;
    final fin = tableau?.finExclue;

    ResultatCroise? croise;
    if (debut != null && fin != null && sources.hasValue) {
      final lues = sources.value!;
      croise = croiser(
        faits: faitsCroises(
          debut: debut,
          finExclue: fin,
          sources: config.sources,
          ventes: lues.ventes,
          depenses: lues.depenses,
          reservations: lues.reservations,
        ),
        axeLigne: config.ligne,
        axeColonne: config.colonne,
        mesure: config.mesure,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Configuration(
          config: config,
          onExporter: () => exporterTableauDeBord(
            context,
            ref,
            fenetre: debut == null || fin == null
                ? null
                : FenetreTableauDeBord.entre(debut, fin),
            tableau: tableau,
          ),
        ),
        const SizedBox(height: AppSpacing.md), // mb-4
        _Tableau(croise: croise, aucuneSource: config.sources.isEmpty),
        const SizedBox(height: AppSpacing.xs), // mt-2
        Text(
          '${croise == null ? 'Non consulté' : MotsCroise.note(croise.nbFaits)} '
          '${MotsCroise.noteReservations}',
          key: const Key('croise-note'),
          style: _style(TaillesContenu.t12, couleur: Ardoise.c400),
        ),
      ],
    );
  }
}

TextStyle _style(double taille, {FontWeight? poids, Color? couleur}) =>
    TextStyle(
      fontFamily: AppTextStyles.police,
      fontSize: taille,
      fontWeight: poids,
      color: couleur,
      height: AppLayout.interligneContenu,
      letterSpacing: 0,
    );

/* ====================================================================== */
/* État de l'écran — les quatre propriétés du composant                    */
/* ====================================================================== */

/// Les quatre propriétés du composant (`$croiseLigne`, `$croiseColonne`,
/// `$croiseMesure`, `$croiseSources`) et leurs défauts : activité, mois,
/// montant, les trois sources.
final class ConfigurationCroise {
  const ConfigurationCroise({
    this.ligne = AxeCroise.activite,
    this.colonne = AxeCroise.mois,
    this.mesure = MesureCroise.montant,
    this.sources = const {
      SourceCroise.ventes,
      SourceCroise.depenses,
      SourceCroise.reservations,
    },
  });

  final AxeCroise ligne;
  final AxeCroise colonne;
  final MesureCroise mesure;
  final Set<SourceCroise> sources;

  ConfigurationCroise copier({
    AxeCroise? ligne,
    AxeCroise? colonne,
    MesureCroise? mesure,
    Set<SourceCroise>? sources,
  }) => ConfigurationCroise(
    ligne: ligne ?? this.ligne,
    colonne: colonne ?? this.colonne,
    mesure: mesure ?? this.mesure,
    sources: sources ?? this.sources,
  );
}

final configurationCroiseProvider =
    NotifierProvider<_ConfigurationNotifier, ConfigurationCroise>(
      _ConfigurationNotifier.new,
    );

final class _ConfigurationNotifier extends Notifier<ConfigurationCroise> {
  @override
  ConfigurationCroise build() => const ConfigurationCroise();

  void definir(ConfigurationCroise c) => state = c;
}

/// Les trois registres, lus du poste. `autoDispose` : quitter l'écran oublie
/// la lecture, et chaque visite relit (aucun cache, PA-59/60/61).
typedef SourcesLues = ({
  List<LigneVenteCroisee> ventes,
  List<LigneDepenseCroisee> depenses,
  List<ReservationCroisee> reservations,
});

final sourcesCroiseProvider = Provider<SourcesCroise>(
  (ref) => SourcesCroise(
    paniers: ref.watch(depotPanierProvider),
    depenses: ref.watch(depotDepensesProvider),
    base: ref.watch(baseLocaleProvider),
  ),
);

final sourcesCroiseLuesProvider = FutureProvider.autoDispose<SourcesLues>((
  ref,
) async {
  final s = ref.watch(sourcesCroiseProvider);
  return (
    ventes: await s.ventes(),
    depenses: await s.lignesDepense(),
    reservations: await s.reservations(),
  );
});

/* ====================================================================== */
/* Les sélecteurs — `bg-white rounded-xl border p-4 mb-4`                  */
/* ====================================================================== */

class _Configuration extends ConsumerWidget {
  const _Configuration({required this.config, required this.onExporter});

  final ConfigurationCroise config;
  final VoidCallback onExporter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(configurationCroiseProvider.notifier);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: Ardoise.c200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // `text-[12px] text-slate-500 mb-3 max-w-3xl`.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppLayout.largeur3xl),
            child: Text(
              MotsCroise.intro,
              key: const Key('croise-intro'),
              style: _style(TaillesContenu.t12, couleur: Ardoise.c500),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    _Champ(
                      libelle: MotsCroise.lignes,
                      enfant: _Liste<AxeCroise>(
                        cle: const Key('croise-lignes'),
                        valeur: config.ligne,
                        options: AxeCroise.values,
                        libelle: (a) => a.libelleOption,
                        onChoix: (a) =>
                            notifier.definir(config.copier(ligne: a)),
                      ),
                    ),
                    _Champ(
                      libelle: MotsCroise.colonnes,
                      enfant: _Liste<AxeCroise>(
                        cle: const Key('croise-colonnes'),
                        valeur: config.colonne,
                        options: AxeCroise.values,
                        libelle: (a) => a.libelleOption,
                        onChoix: (a) =>
                            notifier.definir(config.copier(colonne: a)),
                      ),
                    ),
                    _Champ(
                      libelle: MotsCroise.mesure,
                      enfant: _Liste<MesureCroise>(
                        cle: const Key('croise-mesure'),
                        valeur: config.mesure,
                        options: MesureCroise.values,
                        libelle: (m) => m.libelleOption,
                        onChoix: (m) =>
                            notifier.definir(config.copier(mesure: m)),
                      ),
                    ),
                    _Champ(
                      libelle: MotsCroise.sources,
                      enfant: Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.unit),
                        child: Wrap(
                          spacing: AppSpacing.xs,
                          children: [
                            for (final s in SourceCroise.values)
                              _CaseSource(
                                source: s,
                                cochee: config.sources.contains(s),
                                onChange: (cochee) {
                                  final nouvelles = {...config.sources};
                                  cochee
                                      ? nouvelles.add(s)
                                      : nouvelles.remove(s);
                                  notifier.definir(
                                    config.copier(sources: nouvelles),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // `text-[12px] font-semibold px-3 py-1.5 rounded-lg border
              // border-slate-200 text-slate-600` : « Exporter », la MÊME
              // modale que l'en-tête (`wire:click="ouvrirExport"`).
              InkWell(
                key: const Key('croise-exporter'),
                onTap: onExporter,
                borderRadius: BorderRadius.circular(AppRadius.roundedLg),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Ardoise.c200),
                    borderRadius: BorderRadius.circular(AppRadius.roundedLg),
                  ),
                  child: Text(
                    'Exporter',
                    style: _style(
                      TaillesContenu.t12,
                      poids: FontWeight.w600,
                      couleur: Ardoise.c600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Un libellé `text-[11px] uppercase tracking-wide text-slate-400 mb-1` au-dessus
/// de son contrôle.
class _Champ extends StatelessWidget {
  const _Champ({required this.libelle, required this.enfant});

  final String libelle;
  final Widget enfant;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        libelle.toUpperCase(),
        // `tracking-wide` : 0.025em, proportionnel à la taille.
        style: _style(TaillesContenu.t11, couleur: Ardoise.c400).copyWith(
          letterSpacing: AppTextStyles.suiviLarge * TaillesContenu.t11,
        ),
      ),
      const SizedBox(height: AppSpacing.unit),
      enfant,
    ],
  );
}

/// `<select class="text-[13px] border border-slate-300 rounded-lg px-2.5
/// py-1.5 bg-white">`.
class _Liste<T> extends StatelessWidget {
  const _Liste({
    required this.cle,
    required this.valeur,
    required this.options,
    required this.libelle,
    required this.onChoix,
  });

  final Key cle;
  final T valeur;
  final List<T> options;
  final String Function(T) libelle;
  final ValueChanged<T> onChoix;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xsPlus),
    decoration: BoxDecoration(
      color: AppColors.neutre0,
      border: Border.all(color: Ardoise.c300),
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        key: cle,
        value: valeur,
        isDense: true,
        style: _style(TaillesContenu.t13, couleur: Ardoise.c700),
        items: [
          for (final o in options)
            DropdownMenuItem<T>(value: o, child: Text(libelle(o))),
        ],
        onChanged: (v) {
          if (v != null) onChoix(v);
        },
      ),
    ),
  );
}

/// `<label class="flex items-center gap-1.5 text-[13px] text-slate-600">`.
class _CaseSource extends StatelessWidget {
  const _CaseSource({
    required this.source,
    required this.cochee,
    required this.onChange,
  });

  final SourceCroise source;
  final bool cochee;
  final ValueChanged<bool> onChange;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onChange(!cochee),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: AppLayout.casePaie,
          child: Checkbox(
            key: Key('croise-source-${source.name}'),
            value: cochee,
            onChanged: (v) => onChange(v ?? false),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          source.libelle,
          style: _style(TaillesContenu.t13, couleur: Ardoise.c600),
        ),
      ],
    ),
  );
}

/* ====================================================================== */
/* Le tableau — `bg-white rounded-xl border overflow-hidden`               */
/* ====================================================================== */

class _Tableau extends StatelessWidget {
  const _Tableau({required this.croise, required this.aucuneSource});

  final ResultatCroise? croise;
  final bool aucuneSource;

  String _valeur(int v) => croise!.monnaie ? formaterFcfa(v) : '$v';

  @override
  Widget build(BuildContext context) {
    final c = croise;
    final enTete = _style(
      TaillesContenu.t11,
      poids: FontWeight.w600,
      couleur: AppColors.blanc90,
    ).copyWith(letterSpacing: AppTextStyles.suiviLarge * TaillesContenu.t11);
    final corps = _style(TaillesContenu.t13, couleur: Ardoise.c700);
    final avecDonnees = c != null && !c.vide;

    Widget cellule(
      String texte, {
      required TextStyle style,
      bool droite = true,
      Key? cle,
    }) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xsPlus,
      ),
      child: Text(
        texte,
        key: cle,
        textAlign: droite ? TextAlign.right : TextAlign.left,
        style: style.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );

    Color? couleurDe(int v, {bool grille = false}) => v < 0
        ? CouleursCroise.negatif
        : (grille && v == 0 ? CouleursCroise.zero : null);

    final rangees = <TableRow>[
      TableRow(
        decoration: const BoxDecoration(color: AppColors.navy),
        children: [
          cellule(
            (c == null ? MotsCroise.colonneAxe : c.axeLigne.libelleOption)
                .toUpperCase(),
            style: enTete,
            droite: false,
            cle: const Key('croise-entete-axe'),
          ),
          if (c != null)
            for (final col in c.colonnes)
              cellule(col.toUpperCase(), style: enTete),
          cellule(MotsCroise.total.toUpperCase(), style: enTete),
        ],
      ),
    ];

    if (avecDonnees) {
      for (var i = 0; i < c.lignes.length; i++) {
        rangees.add(
          TableRow(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Ardoise.c100)),
            ),
            children: [
              cellule(
                c.lignes[i],
                style: corps.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Ardoise.c700,
                ),
                droite: false,
                cle: Key('croise-ligne-$i'),
              ),
              for (var j = 0; j < c.colonnes.length; j++)
                cellule(
                  _valeur(c.grille[i][j]),
                  style: corps.copyWith(
                    color: couleurDe(c.grille[i][j], grille: true),
                  ),
                  cle: Key('croise-cellule-$i-$j'),
                ),
              cellule(
                _valeur(c.totauxLignes[i]),
                style: corps.copyWith(
                  fontWeight: FontWeight.bold,
                  color: couleurDe(c.totauxLignes[i]),
                ),
                cle: Key('croise-total-ligne-$i'),
              ),
            ],
          ),
        );
      }
      // `<tfoot class="bg-slate-50 font-semibold">`, `border-t-2`.
      final pied = corps.copyWith(fontWeight: FontWeight.w600);
      rangees.add(
        TableRow(
          decoration: const BoxDecoration(
            color: Ardoise.c50,
            border: Border(
              // `border-t-2` : deux pixels.
              top: BorderSide(color: Ardoise.c200, width: AppSpacing.demi),
            ),
          ),
          children: [
            cellule(MotsCroise.total, style: pied, droite: false),
            for (var j = 0; j < c.colonnes.length; j++)
              cellule(
                _valeur(c.totauxColonnes[j]),
                style: pied.copyWith(color: couleurDe(c.totauxColonnes[j])),
                cle: Key('croise-total-colonne-$j'),
              ),
            cellule(
              _valeur(c.total),
              style: pied.copyWith(color: couleurDe(c.total)),
              cle: const Key('croise-total-general'),
            ),
          ],
        ),
      );
    }

    final message = avecDonnees
        ? null
        : (aucuneSource ? MotsCroise.aucuneSource : MotsCroise.vide);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: Ardoise.c200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // `overflow-x-auto` + `<table class="w-full">` : au moins la largeur
          // du cadre, davantage si les colonnes l'exigent (on fait défiler).
          LayoutBuilder(
            builder: (context, contraintes) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: contraintes.maxWidth),
                child: IntrinsicWidth(
                  child: Table(
                    key: const Key('croise-table'),
                    defaultColumnWidth: const IntrinsicColumnWidth(flex: 1),
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: rangees,
                  ),
                ),
              ),
            ),
          ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacingLarge.p10,
                horizontal: AppSpacing.md,
              ),
              child: Text(
                message,
                key: const Key('croise-message'),
                textAlign: TextAlign.center,
                style: _style(TaillesContenu.t13, couleur: Ardoise.c400),
              ),
            ),
        ],
      ),
    );
  }
}

/// Les deux couleurs de valeur de la vue : `text-red-600` (négatif) et
/// `text-slate-300` (un zéro de la grille, affiché pâle plutôt que masqué).
abstract final class CouleursCroise {
  static const Color negatif = PaletteMaitre.rouge600;
  static const Color zero = Ardoise.c300;
}
