// Vue Blade maîtresse (PA-183) : pwa/comptabilite/hub.blade.php
// (l'onglet « Clôtures » : `onglets/clotures.blade.php`).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/format/formats.dart';
import '../../../../core/rbac/garde_acces.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../transverse/presentation/widgets/briques_transverses.dart';
import '../../domain/cloture_exercice.dart';
import '../../domain/entities/comptabilite.dart';
import '../../domain/messages_cloture.dart';
import '../../domain/montant_comptable.dart';
import '../../domain/refus_comptable.dart';
import '../exercice_consulte.dart' show exerciceChoisiProvider;
import '../providers_cloture.dart';
import 'modales_hub_comptabilite.dart';

/// Les mots de l'onglet « Clôtures » — `onglets/clotures.blade.php` de la vue,
/// au caractère près ; les phrases de langue (`comptabilite_pwa.*`,
/// `pwa.comptabilite.motifs.*`) viennent de [MessagesCloture], relues du
/// serveur par un test.
abstract final class TextesOngletClotures {
  static const String exercicesTitre = 'Exercices comptables';
  static const String ouvrirExercice = 'Ouvrir un exercice';
  static const String colExercice = 'Exercice';
  static const String colDebut = 'Début';
  static const String colFin = 'Fin';
  static const String colStatut = 'Statut';
  static const String colResultatReporte = 'Résultat reporté';
  static const String colClotureLe = 'Clôturé le';
  static const String statutOuvert = 'Ouvert';
  static const String statutEnCloture = 'En clôture';
  static const String statutCloture = 'Clôturé';
  static const String tiret = '—';

  /// « Clôture de l'exercice 2026 » (`<h3>` de la vue).
  static String titre(int annee) => "Clôture de l'exercice $annee";

  /// La phrase du maître (`m10-syscohada-etats.js` l.455-458), mot pour mot.
  static const String phraseDesTroisOperations =
      'Trois opérations enchaînées : solde des comptes de gestion (6, 7, 8) par '
      'le compte 13, verrouillage de l’exercice, puis réouverture du suivant par '
      'une écriture d’à-nouveaux au journal AN qui reprend les seuls comptes de '
      'bilan.';

  static const String resultatAReporter = 'Résultat à reporter';
  static String versCompte(String compte, {required bool perte}) =>
      'Vers le compte $compte (${perte ? 'perte' : 'bénéfice'})';
  static const String blocages = 'Blocages';
  static const String avertissements = 'Avertissements';
  static const String clotureImpossible =
      "La clôture est impossible en l'état :";
  static const String controlesSatisfaits =
      'Tous les contrôles bloquants sont satisfaits.';
  static const String avertissementsTitre =
      'Avertissements — la clôture reste possible :';

  /// L'écart du poste, DIT (jamais une promesse que ce poste ne tient pas).
  static const String noteDuPoste =
      'Ici, la clôture porte sur les écritures passées par ce poste. '
      'Chaque geste envoie aussi une demande au serveur, qui reste le seul '
      'comptable : il rejoue ses règles sur toutes les pièces de '
      "l'établissement et passe les siennes. Un refus du serveur se lit dans "
      '« À traiter » de l’écran de synchronisation.';

  static String archiveEnregistree(String chemin) =>
      'Archive enregistrée : $chemin';

  static const String sansDroit =
      "Votre profil n'a pas le droit de modifier la comptabilité.";
  static const String echecInattendu =
      "La clôture n'a pas pu être menée : rien n'a été modifié.";
  static const String illisible =
      "L'état de la clôture de ce poste n'a pas pu être lu.";
}

String _dateCourte(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? iso : formaterDate(d);
}

String _fcfa(int centimes) =>
    formaterMontantDecimal(chaineDepuisCentimes(centimes), suffixe: 'FCFA') ??
    TextesOngletClotures.tiret;

/// `d/m/Y H:i`.
String _dateHeure(DateTime d) {
  String deux(int n) => n.toString().padLeft(2, '0');
  return '${deux(d.day)}/${deux(d.month)}/${d.year} ${deux(d.hour)}:${deux(d.minute)}';
}

/// Onglet « Clôtures » : la liste des exercices, « Ouvrir un exercice », puis,
/// pour l'exercice CONSULTÉ, la carte de sa clôture (résultat à reporter,
/// blocages, avertissements) et le geste que son statut appelle — « Démarrer la
/// clôture », « Clôturer définitivement » ou « Reprendre la saisie », « Rouvrir »
/// (le comptable seul, motif obligatoire) et l'archive légale.
class OngletClotures extends ConsumerStatefulWidget {
  const OngletClotures({
    required this.exercices,
    required this.exercice,
    super.key,
  });

  /// Les exercices du poste.
  final List<ExerciceComptable> exercices;

  /// L'exercice consulté (le sélecteur du hub), `null` sans exercice.
  final ExerciceComptable? exercice;

  @override
  ConsumerState<OngletClotures> createState() => _OngletCloturesState();
}

class _OngletCloturesState extends ConsumerState<OngletClotures> {
  final _motif = TextEditingController();
  String? _erreur;
  bool _envoi = false;

  @override
  void dispose() {
    _motif.dispose();
    super.dispose();
  }

  bool get _peutEcrire =>
      ref.read(droitsProvider).peutEcrire(ModuleTatacora.m10Comptabilite);

  /// Un geste : le droit d'écriture M10, puis l'appel, puis — succès ou refus
  /// du serveur du poste (`RefusComptable`, à ses mots) — l'écran le dit.
  Future<void> _faire(
    Future<String?> Function(GestesCloture gestes) geste, {
    required Key cleSucces,
    bool viderMotif = false,
  }) async {
    if (!_peutEcrire) {
      direTransverse(
        context,
        TextesOngletClotures.sansDroit,
        cle: const Key('compta-cloture-sans-droit'),
      );
      return;
    }
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    String? succes;
    try {
      succes = await geste(GestesCloture(ref));
    } on RefusComptable catch (e) {
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _erreur = e.message;
      });
      return;
    } on Object {
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _erreur = TextesOngletClotures.echecInattendu;
      });
      return;
    }
    invaliderApresCloture(ref);
    // L'exercice qu'on vient de clôturer (ou de rouvrir) RESTE l'exercice
    // consulté : sans ce choix, l'exercice par défaut — l'ouvert le plus récent —
    // passerait à N+1 et l'écran ne montrerait plus ni l'archive ni
    // l'empreinte de ce qui vient de se passer.
    final consulte = widget.exercice;
    if (consulte != null) {
      ref.read(exerciceChoisiProvider.notifier).choisir(consulte.id);
    }
    if (!mounted) return;
    if (viderMotif) _motif.clear();
    setState(() => _envoi = false);
    if (succes != null) direTransverse(context, succes, cle: cleSucces);
  }

  @override
  Widget build(BuildContext context) {
    final exercice = widget.exercice;
    final clotures = ref.watch(cloturesDuPosteProvider).value ?? const [];
    final etat = exercice == null
        ? null
        : ref.watch(etatClotureProvider(exercice.id));
    final actives = {
      for (final c in clotures)
        if (c.estActive) c.exerciceId: c,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ListeExercices(
          exercices: widget.exercices,
          consulte: exercice,
          resultatsReportes: {
            for (final c in actives.values) c.exerciceId: c.resultatCentimes,
            if (exercice != null &&
                !actives.containsKey(exercice.id) &&
                etat?.value != null)
              exercice.id: etat!.value!.resultatAReporterCentimes,
          },
        ),
        if (exercice != null) ...[
          const SizedBox(height: AppSpacing.sm),
          if (etat != null && etat.hasError)
            Text(
              TextesOngletClotures.illisible,
              key: const Key('compta-cloture-illisible'),
              style: styleTransverse(
                TaillesContenu.t13,
                couleur: AppColors.erreur,
              ),
            )
          else if (etat?.value != null)
            _CarteCloture(etat: etat!.value!),
          const SizedBox(height: AppSpacing.sm),
          _CarteGeste(
            exercice: exercice,
            active: actives[exercice.id],
            erreur: _erreur,
            envoi: _envoi,
            motif: _motif,
            onDemarrer: () => _faire(
              (g) => g.demarrer(exercice),
              cleSucces: const Key('compta-cloture-demarree'),
            ),
            onReprendre: () => _faire(
              (g) => g.reprendreSaisie(exercice),
              cleSucces: const Key('compta-cloture-reprise'),
            ),
            onCloturer: () => _faire(
              (g) => g.cloturer(exercice),
              cleSucces: const Key('compta-cloture-passee'),
            ),
            onRouvrir: () => _faire(
              (g) => g.rouvrir(exercice, _motif.text),
              cleSucces: const Key('compta-cloture-rouverte'),
              viderMotif: true,
            ),
            onGenererArchive: () => _faire(
              (g) => g.genererArchive(exercice),
              cleSucces: const Key('compta-archive-generee'),
            ),
            onTelechargerArchive: () => _faire((g) async {
              final chemin = await g.telechargerArchive(exercice);
              return chemin == null
                  ? null
                  : TextesOngletClotures.archiveEnregistree(chemin);
            }, cleSucces: const Key('compta-archive-telechargee')),
          ),
        ],
      ],
    );
  }
}

/// « Exercices comptables » — le tableau des exercices et « Ouvrir un
/// exercice ».
class _ListeExercices extends ConsumerWidget {
  const _ListeExercices({
    required this.exercices,
    required this.consulte,
    required this.resultatsReportes,
  });

  final List<ExerciceComptable> exercices;
  final ExerciceComptable? consulte;

  /// Le résultat reporté (centimes) de chaque exercice qui en a un : celui qui
  /// a été clôturé (écrit à sa clôture) et l'exercice consulté (calculé).
  final Map<String, int> resultatsReportes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tries = [...exercices]..sort((a, b) => b.annee.compareTo(a.annee));
    final proposee = tries.isEmpty
        ? DateTime.now().year
        : tries.first.annee + 1;

    Widget pastille(StatutExercice s) {
      final (fond, texte, libelle) = switch (s) {
        StatutExercice.ouvert => (
          PaletteMaitre.emeraude50,
          PaletteMaitre.emeraude700,
          TextesOngletClotures.statutOuvert,
        ),
        StatutExercice.enCloture => (
          PaletteMaitre.ambre50,
          PaletteMaitre.ambre700,
          TextesOngletClotures.statutEnCloture,
        ),
        StatutExercice.cloture => (
          Ardoise.c100,
          Ardoise.c600,
          TextesOngletClotures.statutCloture,
        ),
      };
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxs,
          vertical: AppSpacing.demi,
        ),
        decoration: BoxDecoration(
          color: fond,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(
          libelle,
          style: styleTransverse(TaillesContenu.t11, couleur: texte),
        ),
      );
    }

    return CarteTransverse(
      key: const Key('compta-exercices'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.smPlus,
            ),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Ardoise.c200)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    TextesOngletClotures.exercicesTitre,
                    style: styleTransverse(
                      TaillesContenu.t14,
                      poids: FontWeight.bold,
                      couleur: AppColors.navy,
                    ),
                  ),
                ),
                BoutonTransverse(
                  cle: const Key('compta-ouvrir-exercice'),
                  libelle: TextesOngletClotures.ouvrirExercice,
                  taille: TaillesContenu.t12,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.smPlus,
                    vertical: AppSpacing.xxs,
                  ),
                  onTap: () =>
                      ref
                          .read(droitsProvider)
                          .peutEcrire(ModuleTatacora.m10Comptabilite)
                      ? ouvrirModaleExercice(context, anneeInitiale: proposee)
                      : direTransverse(
                          context,
                          TextesOngletClotures.sansDroit,
                          cle: const Key('compta-exercice-sans-droit'),
                        ),
                ),
              ],
            ),
          ),
          TableauTransverse(
            colonnes: const [
              (
                titre: TextesOngletClotures.colExercice,
                alignement: TextAlign.left,
              ),
              (
                titre: TextesOngletClotures.colDebut,
                alignement: TextAlign.right,
              ),
              (titre: TextesOngletClotures.colFin, alignement: TextAlign.right),
              (
                titre: TextesOngletClotures.colStatut,
                alignement: TextAlign.right,
              ),
              (
                titre: TextesOngletClotures.colResultatReporte,
                alignement: TextAlign.right,
              ),
              (
                titre: TextesOngletClotures.colClotureLe,
                alignement: TextAlign.right,
              ),
            ],
            vide: TextesOngletClotures.tiret,
            lignes: [
              for (final e in tries)
                [
                  celluleTexte(
                    '${e.annee}',
                    poids: FontWeight.bold,
                    couleur: AppColors.navy,
                  ),
                  celluleTexte(
                    _dateCourte(e.dateDebut),
                    alignement: TextAlign.right,
                  ),
                  celluleTexte(
                    _dateCourte(e.dateFin),
                    alignement: TextAlign.right,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: pastille(e.statut),
                  ),
                  celluleTexte(
                    resultatsReportes.containsKey(e.id)
                        ? _fcfa(resultatsReportes[e.id]!)
                        : TextesOngletClotures.tiret,
                    alignement: TextAlign.right,
                    poids: FontWeight.w600,
                    couleur: (resultatsReportes[e.id] ?? 0) < 0
                        ? PaletteMaitre.rouge600
                        : Ardoise.c600,
                  ),
                  celluleTexte(
                    e.dateCloture == null
                        ? TextesOngletClotures.tiret
                        : formaterDate(e.dateCloture!),
                    alignement: TextAlign.right,
                    taille: TaillesContenu.t12,
                    couleur: Ardoise.c500,
                  ),
                ],
            ],
          ),
        ],
      ),
    );
  }
}

/// « Clôture de l'exercice N » — la phrase des trois opérations, les trois
/// cartes (résultat à reporter, blocages, avertissements) et leurs listes.
class _CarteCloture extends StatelessWidget {
  const _CarteCloture({required this.etat});

  final EtatClotureLocal etat;

  @override
  Widget build(BuildContext context) {
    final perte = etat.resultatAReporterCentimes < 0;
    final petit = styleTransverse(TaillesContenu.t12, couleur: Ardoise.c500);

    Widget carte(
      Key cle,
      String titre,
      String valeur,
      Color couleur, {
      String? sous,
    }) => Expanded(
      child: Container(
        key: cle,
        padding: const EdgeInsets.all(AppSpacing.smPlus),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: Ardoise.c200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titre.toUpperCase(),
              style: styleTransverse(
                TaillesContenu.t11,
                poids: FontWeight.w600,
                couleur: Ardoise.c400,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              valeur,
              style: styleTransverse(
                TaillesContenu.t18,
                poids: FontWeight.bold,
                couleur: couleur,
              ),
            ),
            if (sous != null)
              Text(
                sous,
                style: styleTransverse(
                  TaillesContenu.t11,
                  couleur: Ardoise.c400,
                ),
              ),
          ],
        ),
      ),
    );

    Widget liste(List<String> phrases, Color couleur) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in phrases)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Text(
              '• $p',
              style: styleTransverse(TaillesContenu.t12, couleur: couleur),
            ),
          ),
      ],
    );

    final blocages = [
      for (final b in etat.blocages)
        MessagesCloture.dire('pwa.comptabilite.motifs.${b.code}'),
    ];
    final avertissements = [
      for (final a in etat.avertissements)
        MessagesCloture.dire('pwa.comptabilite.motifs.${a.code}'),
    ];

    return CarteTransverse(
      key: const Key('compta-cloture-carte'),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            TextesOngletClotures.titre(etat.annee),
            style: styleTransverse(
              TaillesContenu.t14,
              poids: FontWeight.bold,
              couleur: AppColors.navy,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(TextesOngletClotures.phraseDesTroisOperations, style: petit),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              carte(
                const Key('compta-cloture-resultat'),
                TextesOngletClotures.resultatAReporter,
                _fcfa(etat.resultatAReporterCentimes),
                perte ? PaletteMaitre.rouge600 : AppColors.navy,
                sous: TextesOngletClotures.versCompte(
                  etat.compteDeDestination,
                  perte: perte,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              carte(
                const Key('compta-cloture-nb-blocages'),
                TextesOngletClotures.blocages,
                '${blocages.length}',
                blocages.isNotEmpty
                    ? PaletteMaitre.rouge600
                    : PaletteMaitre.emeraude600,
              ),
              const SizedBox(width: AppSpacing.sm),
              carte(
                const Key('compta-cloture-nb-avertissements'),
                TextesOngletClotures.avertissements,
                '${avertissements.length}',
                avertissements.isNotEmpty
                    ? PaletteMaitre.ambre600
                    : Ardoise.c400,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (blocages.isNotEmpty)
            EncadreTransverse(
              key: const Key('compta-cloture-blocages'),
              fond: PaletteMaitre.rouge50,
              bordure: PaletteMaitre.rouge200,
              padding: const EdgeInsets.all(AppSpacing.smPlus),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    TextesOngletClotures.clotureImpossible,
                    style: styleTransverse(
                      TaillesContenu.t13,
                      poids: FontWeight.w600,
                      couleur: PaletteMaitre.rouge900,
                    ),
                  ),
                  liste(blocages, PaletteMaitre.rouge800),
                ],
              ),
            )
          else
            EncadreTransverse(
              key: const Key('compta-cloture-controles-ok'),
              fond: PaletteMaitre.emeraude50,
              bordure: PaletteMaitre.emeraude200,
              padding: const EdgeInsets.all(AppSpacing.smPlus),
              child: Text(
                TextesOngletClotures.controlesSatisfaits,
                style: styleTransverse(
                  TaillesContenu.t13,
                  couleur: PaletteMaitre.emeraude900,
                ),
              ),
            ),
          if (avertissements.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            EncadreTransverse(
              key: const Key('compta-cloture-avertissements'),
              fond: PaletteMaitre.ambre50,
              bordure: PaletteMaitre.ambre200,
              padding: const EdgeInsets.all(AppSpacing.smPlus),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    TextesOngletClotures.avertissementsTitre,
                    style: styleTransverse(
                      TaillesContenu.t13,
                      poids: FontWeight.w600,
                      couleur: PaletteMaitre.ambre900,
                    ),
                  ),
                  liste(avertissements, PaletteMaitre.ambre800),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Le geste que le statut de l'exercice appelle, avec son archive légale.
class _CarteGeste extends ConsumerWidget {
  const _CarteGeste({
    required this.exercice,
    required this.active,
    required this.erreur,
    required this.envoi,
    required this.motif,
    required this.onDemarrer,
    required this.onReprendre,
    required this.onCloturer,
    required this.onRouvrir,
    required this.onGenererArchive,
    required this.onTelechargerArchive,
  });

  final ExerciceComptable exercice;
  final ClotureExercice? active;
  final String? erreur;
  final bool envoi;
  final TextEditingController motif;
  final VoidCallback onDemarrer;
  final VoidCallback onReprendre;
  final VoidCallback onCloturer;
  final VoidCallback onRouvrir;
  final VoidCallback onGenererArchive;
  final VoidCallback onTelechargerArchive;

  String _t(String cle, [Map<String, String> v = const {}]) =>
      MessagesCloture.dire('comptabilite_pwa.$cle', v);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final annee = '${exercice.annee}';
    final titre = styleTransverse(
      TaillesContenu.t14,
      poids: FontWeight.bold,
      couleur: AppColors.navy,
    );
    final note = styleTransverse(TaillesContenu.t12, couleur: Ardoise.c500);
    final peutRouvrir = ref.watch(sessionProvider)?.role == roleReouverture;

    Widget bouton(
      Key cle,
      String libelle,
      VoidCallback onTap, {
      bool plein = true,
      bool danger = false,
    }) => BoutonTransverse(
      cle: cle,
      libelle: libelle,
      fond: plein ? AppColors.navy : null,
      couleurContour: danger ? PaletteMaitre.rouge200 : Ardoise.c300,
      couleurTexteContour: danger ? PaletteMaitre.rouge700 : Ardoise.c700,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.smPlus,
      ),
      onTap: envoi ? () {} : onTap,
    );

    final Widget corps = switch (exercice.statut) {
      StatutExercice.ouvert => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_t('cloture_demarrer', {'annee': annee}), style: titre),
          const SizedBox(height: AppSpacing.xxs),
          Text(_t('cloture_demarrer_note', {'annee': annee}), style: note),
          const SizedBox(height: AppSpacing.sm),
          bouton(
            const Key('compta-cloture-demarrer'),
            _t('cloture_demarrer', {'annee': annee}),
            onDemarrer,
          ),
        ],
      ),
      StatutExercice.enCloture => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_t('cloture_definitive', {'annee': annee}), style: titre),
          const SizedBox(height: AppSpacing.xxs),
          Text(_t('cloture_definitive_note'), style: note),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              bouton(
                const Key('compta-cloture-cloturer'),
                _t('cloture_definitive', {'annee': annee}),
                onCloturer,
              ),
              bouton(
                const Key('compta-cloture-reprendre'),
                _t('cloture_reprendre'),
                onReprendre,
                plein: false,
              ),
            ],
          ),
        ],
      ),
      StatutExercice.cloture => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (active != null) ...[
            Text(
              _t('cloture_passee', {
                'date': _dateHeure(active!.clotureeLe),
                'cloture': active!.pieceCloture ?? '—',
                'an': active!.pieceANouveaux ?? '—',
              }),
              key: const Key('compta-cloture-passee-texte'),
              style: styleTransverse(TaillesContenu.t13, couleur: Ardoise.c600),
            ),
            const SizedBox(height: AppSpacing.sm),
            _BlocArchive(
              cloture: active!,
              envoi: envoi,
              onGenerer: onGenererArchive,
              onTelecharger: onTelechargerArchive,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          Text(_t('reouvrir', {'annee': annee}), style: titre),
          const SizedBox(height: AppSpacing.xxs),
          Text(_t('reouvrir_note'), style: note),
          const SizedBox(height: AppSpacing.sm),
          if (peutRouvrir) ...[
            Text(
              _t('reouvrir_motif'),
              style: styleTransverse(
                TaillesContenu.t13,
                poids: FontWeight.w600,
                couleur: Ardoise.c700,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            TextField(
              key: const Key('compta-cloture-motif'),
              controller: motif,
              enabled: !envoi,
              minLines: 2,
              maxLines: 3,
              style: styleTransverse(TaillesContenu.t13),
              decoration: InputDecoration(
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.roundedMd),
                  borderSide: const BorderSide(color: Ardoise.c200),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            bouton(
              const Key('compta-cloture-rouvrir'),
              _t('reouvrir', {'annee': annee}),
              onRouvrir,
              plein: false,
              danger: true,
            ),
          ] else
            Text(
              _t('reouvrir_reserve'),
              key: const Key('compta-cloture-reouverture-reservee'),
              style: styleTransverse(TaillesContenu.t12, couleur: Ardoise.c400),
            ),
        ],
      ),
    };

    return CarteTransverse(
      key: const Key('compta-cloture-geste'),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (erreur != null) ...[
            EncadreTransverse(
              fond: PaletteMaitre.rouge50,
              bordure: PaletteMaitre.rouge200,
              padding: const EdgeInsets.all(AppSpacing.smPlus),
              child: Text(
                erreur!,
                key: const Key('compta-cloture-erreur'),
                style: styleTransverse(
                  TaillesContenu.t13,
                  couleur: PaletteMaitre.rouge800,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          corps,
          const SizedBox(height: AppSpacing.md),
          Text(
            TextesOngletClotures.noteDuPoste,
            key: const Key('compta-cloture-note-du-poste'),
            style: styleTransverse(TaillesContenu.t11, couleur: Ardoise.c400),
          ),
        ],
      ),
    );
  }
}

/// « Archive légale » : l'empreinte et « Télécharger l'archive (ZIP) », ou
/// « Générer l'archive » quand elle n'a pas été produite.
class _BlocArchive extends StatelessWidget {
  const _BlocArchive({
    required this.cloture,
    required this.envoi,
    required this.onGenerer,
    required this.onTelecharger,
  });

  final ClotureExercice cloture;
  final bool envoi;
  final VoidCallback onGenerer;
  final VoidCallback onTelecharger;

  String _t(String cle) => MessagesCloture.dire('comptabilite_pwa.$cle');

  @override
  Widget build(BuildContext context) {
    final empreinte = cloture.archiveEmpreinte;
    return Container(
      key: const Key('compta-archive'),
      padding: const EdgeInsets.all(AppSpacing.smPlus),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Ardoise.c200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t('archive_ecran'),
            style: styleTransverse(
              TaillesContenu.t14,
              poids: FontWeight.bold,
              couleur: AppColors.navy,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            _t('archive_ecran_note'),
            style: styleTransverse(TaillesContenu.t12, couleur: Ardoise.c500),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (empreinte != null) ...[
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '${_t('archive_empreinte')} '),
                  TextSpan(
                    text: empreinte,
                    style: styleTransverse(
                      TaillesContenu.t11,
                      police: AppTextStyles.policeMonospace,
                    ),
                  ),
                ],
              ),
              key: const Key('compta-archive-empreinte'),
              style: styleTransverse(TaillesContenu.t12, couleur: Ardoise.c600),
            ),
            const SizedBox(height: AppSpacing.xs),
            BoutonTransverse(
              cle: const Key('compta-archive-telecharger'),
              libelle: _t('archive_telecharger'),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.smPlus,
              ),
              onTap: envoi ? () {} : onTelecharger,
            ),
          ] else ...[
            Text(
              _t('archive_absente'),
              key: const Key('compta-archive-absente'),
              style: styleTransverse(
                TaillesContenu.t12,
                couleur: PaletteMaitre.ambre700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            BoutonTransverse(
              cle: const Key('compta-archive-generer'),
              libelle: _t('archive_generer'),
              fond: AppColors.navy,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.smPlus,
              ),
              onTap: envoi ? () {} : onGenerer,
            ),
          ],
        ],
      ),
    );
  }
}
