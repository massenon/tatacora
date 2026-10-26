import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/mesures_transverses.dart';
import '../../../shared_widgets/bouton_standard.dart';
import '../../../shared_widgets/liste_paginee.dart';
import '../../transverse/presentation/widgets/briques_transverses.dart';
import '../data/journal_reception_dao.dart';
import '../domain/descente_catalogue.dart';
import '../domain/journal_reception.dart';
import '../domain/reinitialisation_serveur.dart';
import 'modales_reception.dart';
import 'providers_reception.dart';
import 'providers_synchronisation.dart';

/// Les mots de la partie « Réception » (26/10/2026).
abstract final class TextesReception {
  static const String onglet = 'Réception';
  static const String sectionBilan = 'Éléments reçus du serveur';
  static const String explication =
      'Chaque élément reçu du serveur est consigné ici avec son issue et, '
      'quand il n’a pas pu être écrit sur ce poste, la cause exacte. Le '
      'journal garde 30 jours d’éléments alignés et 5 000 lignes au plus.';
  static const String sectionListe = 'Journal de réception';
  static const String sectionAnnonces = 'Annonces du serveur';
  static const String relancerTout = 'Relancer tout';
  static const String relancerToutExplication =
      '« Relancer tout » rejoue les éléments refusés ou gardés, puis reprend '
      'la réception depuis le dernier point acquis.';
  static const String reserveAdministrateurs =
      '« Relancer » et « Corriger » sont réservés aux Administrateurs.';
  static const String listeVide = 'Aucun élément reçu ne correspond.';
  static const String lectureImpossible =
      'Lecture du journal de réception impossible sur ce poste.';

  static const String recus = 'Reçus';
  static const String filtreTable = 'Table';
  static const String filtreIssue = 'Issue';
  static const String toutesTables = 'Toutes les tables';
  static const String toutesIssues = 'Toutes les issues';
  static const String effacerFiltres = 'Effacer les filtres';

  static String du(DateTime? d) => d == null ? 'Du…' : 'Du ${_jour(d)}';
  static String au(DateTime? d) => d == null ? 'Au…' : 'Au ${_jour(d)}';
  static String _jour(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  static const String colRecu = 'Reçu le';
  static const String colTable = 'Table';
  static const String colElement = 'Élément';
  static const String colIssue = 'Issue';
  static const String colCause = 'Cause';
  static const String colEssais = 'Essais';
  static const String colActions = 'Actions';

  static String relanceTout(int restant) => restant < 0
      ? 'Relance impossible sur ce poste.'
      : restant == 0
      ? 'Tout est aligné sur ce poste.'
      : '$restant élément(s) restent à traiter : voyez leur cause.';

  static const String essaisPhase =
      'Le serveur annonce une phase d’essais en production : les données '
      'saisies pendant cette phase pourront être réinitialisées.';
  static const String essaisAucune =
      'Le serveur n’annonce aucune phase d’essais.';
  static const String generationRetenue =
      'Ce poste suit la génération courante des données du serveur.';
  static const String generationAttendue =
      'Ce poste n’a pas encore retenu la génération des données du serveur : '
      'elle sera retenue à la première réception réussie.';
  static String signalements(int n) => n == 0
      ? 'Aucun signalement du serveur sur les envois acceptés.'
      : '$n envoi(s) accepté(s) avec un signalement du serveur : voir la '
            'partie Envoi.';
}

Widget _titre(String texte) => Padding(
  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
  child: Text(
    texte,
    style: styleTransverse(
      TaillesContenu.t15,
      poids: FontWeight.w700,
      couleur: AppColors.navy,
    ),
  ),
);

Widget _texte(
  String texte, {
  Key? cle,
  Color couleur = AppColors.neutre700,
  FontWeight? poids,
}) => Text(
  texte,
  key: cle,
  style: styleTransverse(TaillesContenu.t13, couleur: couleur, poids: poids),
);

/// La partie **Réception** de l'écran de synchronisation : ce que le poste a
/// reçu du serveur, ce qui a échoué et POURQUOI, et de quoi corriger et
/// relancer. [apres] : les cartes que l'écran y range (catalogue reçu,
/// contrôle de cohérence). [surVoirEnvoi] ramène à la partie Envoi.
class PartieReception extends ConsumerWidget {
  const PartieReception({
    required this.admin,
    required this.surVoirEnvoi,
    this.apres = const [],
    super.key,
  });

  final bool admin;
  final VoidCallback surVoirEnvoi;
  final List<Widget> apres;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      key: const Key('recep-partie'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CarteBilan(admin: admin),
        const SizedBox(height: AppSpacing.md),
        _CarteJournal(admin: admin, surVoirEnvoi: surVoirEnvoi),
        const SizedBox(height: AppSpacing.md),
        const _CarteAnnonces(),
        for (final c in apres) ...[const SizedBox(height: AppSpacing.md), c],
      ],
    );
  }
}

/* ==================================================================== */
/* Compteurs et « Relancer tout »                                        */
/* ==================================================================== */

class _CarteBilan extends ConsumerStatefulWidget {
  const _CarteBilan({required this.admin});

  final bool admin;

  @override
  ConsumerState<_CarteBilan> createState() => _EtatCarteBilan();
}

class _EtatCarteBilan extends ConsumerState<_CarteBilan> {
  bool _enCours = false;

  Future<void> _relancerTout() async {
    setState(() => _enCours = true);
    final restant = await ref.read(relancerToutProvider)();
    if (!mounted) return;
    setState(() => _enCours = false);
    ref
      ..invalidate(etatFileSynchronisationProvider)
      ..invalidate(compteursReceptionProvider);
    direTransverse(context, TextesReception.relanceTout(restant));
  }

  @override
  Widget build(BuildContext context) {
    final lus = ref.watch(compteursReceptionProvider);
    final filtre = ref.watch(filtreReceptionProvider);
    final c = lus.value ?? const CompteursReception();
    Widget compteur(String cle, int n, String libelle, IssueReception? issue) {
      return InkWell(
        key: Key('recep-filtre-$cle'),
        onTap: () => ref
            .read(filtreReceptionProvider.notifier)
            .poser(
              issue == null
                  ? filtre.avec(effacerIssue: true)
                  : filtre.avec(issue: issue),
            ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$n',
              key: Key('recep-compteur-$cle'),
              style: styleTransverse(
                TaillesContenu.lg,
                poids: FontWeight.w700,
                couleur: issue == IssueReception.refuse && n > 0
                    ? AppColors.erreur
                    : AppColors.navy,
              ),
            ),
            _texte(libelle),
          ],
        ),
      );
    }

    return CarteTransverse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titre(TextesReception.sectionBilan),
          _texte(TextesReception.explication),
          const SizedBox(height: AppSpacing.sm),
          if (lus.hasError)
            _texte(
              TextesReception.lectureImpossible,
              cle: const Key('recep-lecture-impossible'),
              couleur: AppColors.erreur,
            )
          else
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: [
                compteur('recus', c.recus, TextesReception.recus, null),
                for (final i in IssueReception.values)
                  compteur(i.code, c.de(i), i.libelle, i),
              ],
            ),
          const SizedBox(height: AppSpacing.sm),
          _texte(TextesReception.relancerToutExplication),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: BoutonStandard(
              key: const Key('recep-relancer-tout'),
              libelle: TextesReception.relancerTout,
              variante: VarianteBouton.primaire,
              onPressed: widget.admin && !_enCours ? _relancerTout : null,
            ),
          ),
          if (!widget.admin) ...[
            const SizedBox(height: AppSpacing.xxs),
            _texte(
              TextesReception.reserveAdministrateurs,
              cle: const Key('recep-reserve'),
            ),
          ],
        ],
      ),
    );
  }
}

/* ==================================================================== */
/* Le journal : filtres, liste, détail, gestes                           */
/* ==================================================================== */

class _CarteJournal extends ConsumerWidget {
  const _CarteJournal({required this.admin, required this.surVoirEnvoi});

  final bool admin;
  final VoidCallback surVoirEnvoi;

  Future<void> _relancer(
    BuildContext context,
    WidgetRef ref,
    EntreeJournalReception e,
  ) async {
    final r = await ref.read(relancerElementProvider)(
      e.tableServeur,
      e.elementId,
    );
    if (!context.mounted) return;
    ref.invalidate(etatFileSynchronisationProvider);
    direTransverse(context, r.phrase);
  }

  Future<void> _corriger(
    BuildContext context,
    WidgetRef ref,
    EntreeJournalReception e,
  ) async {
    final choix = await ouvrirCorrectionReception(context, e);
    if (!context.mounted || choix == null) return;
    switch (choix) {
      case ChoixCorrection.fermer:
        break;
      case ChoixCorrection.relancer:
        await _relancer(context, ref, e);
      case ChoixCorrection.ouvrirEcran:
        final route = e.explication.route;
        if (route != null) context.go(route);
      case ChoixCorrection.voirElementsLies:
        final lie = e.explication.dependance;
        if (lie != null) {
          ref
              .read(filtreReceptionProvider.notifier)
              .poser(FiltreReception(table: lie));
        }
      case ChoixCorrection.voirFileEnvoi:
        surVoirEnvoi();
    }
  }

  Future<void> _detail(
    BuildContext context,
    WidgetRef ref,
    EntreeJournalReception e,
  ) async {
    final complete =
        await ref
            .read(journalReceptionDaoProvider)
            .lire(e.tableServeur, e.elementId) ??
        e;
    if (!context.mounted) return;
    final geste = await ouvrirDetailReception(context, complete, gestes: admin);
    if (!context.mounted) return;
    switch (geste) {
      case GesteReception.relancer:
        await _relancer(context, ref, complete);
      case GesteReception.corriger:
        await _corriger(context, ref, complete);
      case GesteReception.aucun || null:
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lus = ref.watch(entreesReceptionProvider);
    final filtre = ref.watch(filtreReceptionProvider);
    return CarteTransverse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titre(TextesReception.sectionListe),
          _Filtres(filtre: filtre),
          const SizedBox(height: AppSpacing.sm),
          switch (lus) {
            AsyncData(:final value) => ListePaginee<EntreeJournalReception>(
              elements: value,
              prefixeCle: 'recep-pagination',
              masquerSiVide: true,
              cleRemiseAZero: filtre,
              constructeur: (context, page) => TableauTransverse(
                colonnes: const [
                  (titre: TextesReception.colRecu, alignement: TextAlign.left),
                  (titre: TextesReception.colTable, alignement: TextAlign.left),
                  (
                    titre: TextesReception.colElement,
                    alignement: TextAlign.left,
                  ),
                  (titre: TextesReception.colIssue, alignement: TextAlign.left),
                  (titre: TextesReception.colCause, alignement: TextAlign.left),
                  (
                    titre: TextesReception.colEssais,
                    alignement: TextAlign.right,
                  ),
                  (
                    titre: TextesReception.colActions,
                    alignement: TextAlign.right,
                  ),
                ],
                largeurs: MesuresTransverses.colonnesReception,
                vide: TextesReception.listeVide,
                cleVide: const Key('recep-vide'),
                lignes: [for (final e in page) _ligne(context, ref, e)],
              ),
            ),
            AsyncError() => _texte(
              TextesReception.lectureImpossible,
              couleur: AppColors.erreur,
            ),
            _ => const LinearProgressIndicator(),
          },
        ],
      ),
    );
  }

  List<Widget> _ligne(
    BuildContext context,
    WidgetRef ref,
    EntreeJournalReception e,
  ) {
    final k = '${e.tableServeur}-${e.elementId}';
    final x = e.issue.ouverte ? e.explication : null;
    return [
      _texte(TextesModalesReception.sur(e.recuLe), cle: Key('recep-recu-$k')),
      _texte(e.libelleTable, cle: Key('recep-table-$k')),
      _texte(e.etiquette ?? e.elementId, cle: Key('recep-element-$k')),
      _texte(
        e.issue.libelle,
        cle: Key('recep-issue-$k'),
        couleur: e.issue == IssueReception.refuse
            ? AppColors.erreur
            : AppColors.neutre700,
        poids: e.issue.ouverte ? FontWeight.w600 : null,
      ),
      _texte(x?.titre ?? '—', cle: Key('recep-cause-$k')),
      _texte('${e.tentatives}', cle: Key('recep-essais-$k')),
      Wrap(
        alignment: WrapAlignment.end,
        spacing: AppSpacing.xs,
        children: [
          BoutonStandard(
            key: Key('recep-detail-$k'),
            libelle: TextesModalesReception.detail,
            compact: true,
            onPressed: () => _detail(context, ref, e),
          ),
          if (admin && e.issue.ouverte) ...[
            BoutonStandard(
              key: Key('recep-relancer-$k'),
              libelle: TextesModalesReception.relancer,
              compact: true,
              onPressed: () => _relancer(context, ref, e),
            ),
            BoutonStandard(
              key: Key('recep-corriger-$k'),
              libelle: TextesModalesReception.corriger,
              compact: true,
              variante: VarianteBouton.primaire,
              onPressed: () async {
                final complete =
                    await ref
                        .read(journalReceptionDaoProvider)
                        .lire(e.tableServeur, e.elementId) ??
                    e;
                if (context.mounted) await _corriger(context, ref, complete);
              },
            ),
          ],
        ],
      ),
    ];
  }
}

class _Filtres extends ConsumerWidget {
  const _Filtres({required this.filtre});

  final FiltreReception filtre;

  Future<void> _date(
    BuildContext context,
    WidgetRef ref, {
    required bool debut,
  }) async {
    final aujourdHui = DateTime.now();
    final choix = await showDatePicker(
      context: context,
      initialDate: (debut ? filtre.du : filtre.au) ?? aujourdHui,
      firstDate: DateTime(aujourdHui.year - 2),
      lastDate: DateTime(aujourdHui.year + 1),
    );
    if (choix == null) return;
    ref
        .read(filtreReceptionProvider.notifier)
        .poser(filtre.avec(du: debut ? choix : null, au: debut ? null : choix));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tables = ref.watch(tablesReceptionProvider).value ?? const [];
    final notifier = ref.read(filtreReceptionProvider.notifier);
    final style = styleTransverse(
      TaillesContenu.t13,
      couleur: AppColors.neutre700,
    );
    final tableValide = filtre.table != null && !tables.contains(filtre.table)
        ? [...tables, filtre.table!]
        : tables;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: MesuresTransverses.filtreReceptionTable,
          child: DropdownButton<String?>(
            key: const Key('recep-filtre-table'),
            value: filtre.table,
            isExpanded: true,
            style: style,
            hint: Text(TextesReception.filtreTable, style: style),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(TextesReception.toutesTables, style: style),
              ),
              for (final t in tableValide)
                DropdownMenuItem<String?>(
                  value: t,
                  child: Text(libelleTableServeur(t), style: style),
                ),
            ],
            onChanged: (v) => notifier.poser(
              v == null
                  ? filtre.avec(effacerTable: true)
                  : filtre.avec(table: v),
            ),
          ),
        ),
        SizedBox(
          width: MesuresTransverses.filtreReceptionIssue,
          child: DropdownButton<IssueReception?>(
            key: const Key('recep-filtre-issue'),
            value: filtre.issue,
            isExpanded: true,
            style: style,
            hint: Text(TextesReception.filtreIssue, style: style),
            items: [
              DropdownMenuItem<IssueReception?>(
                value: null,
                child: Text(TextesReception.toutesIssues, style: style),
              ),
              for (final i in IssueReception.values)
                DropdownMenuItem<IssueReception?>(
                  value: i,
                  child: Text(i.libelle, style: style),
                ),
            ],
            onChanged: (v) => notifier.poser(
              v == null
                  ? filtre.avec(effacerIssue: true)
                  : filtre.avec(issue: v),
            ),
          ),
        ),
        BoutonStandard(
          key: const Key('recep-filtre-du'),
          libelle: TextesReception.du(filtre.du),
          compact: true,
          onPressed: () => _date(context, ref, debut: true),
        ),
        BoutonStandard(
          key: const Key('recep-filtre-au'),
          libelle: TextesReception.au(filtre.au),
          compact: true,
          onPressed: () => _date(context, ref, debut: false),
        ),
        if (!filtre.vide)
          BoutonStandard(
            key: const Key('recep-filtre-effacer'),
            libelle: TextesReception.effacerFiltres,
            compact: true,
            onPressed: () => notifier.poser(const FiltreReception()),
          ),
      ],
    );
  }
}

/* ==================================================================== */
/* Annonces du serveur                                                    */
/* ==================================================================== */

class _CarteAnnonces extends ConsumerWidget {
  const _CarteAnnonces();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(annoncesServeurProvider).value;
    final signalements = ref
        .watch(etatFileSynchronisationProvider)
        .value
        ?.anomalies
        .length;
    return CarteTransverse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titre(TextesReception.sectionAnnonces),
          if (a != null) ...[
            _texte(
              a.phaseEssais
                  ? TextesReception.essaisPhase
                  : TextesReception.essaisAucune,
              cle: const Key('recep-annonce-essais'),
              couleur: a.phaseEssais ? AppColors.erreur : AppColors.neutre700,
            ),
            _texte(
              a.generationRetenue
                  ? TextesReception.generationRetenue
                  : TextesReception.generationAttendue,
              cle: const Key('recep-annonce-generation'),
            ),
            if (a.reinitialiseLe != null)
              _texte(
                TextesReinitialisationServeur.constatee(a.reinitialiseLe!),
                cle: const Key('recep-annonce-reinitialise'),
                couleur: AppColors.erreur,
                poids: FontWeight.w600,
              ),
          ],
          if (signalements != null)
            _texte(
              TextesReception.signalements(signalements),
              cle: const Key('recep-annonce-signalements'),
            ),
        ],
      ),
    );
  }
}
