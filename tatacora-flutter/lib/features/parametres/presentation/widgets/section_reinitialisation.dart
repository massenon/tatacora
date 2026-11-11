// Vue Blade maîtresse (PA-183) : pwa/transverse/parametres.blade.php
// (la section « Réinitialiser les données de test » de l'onglet Activation & Sécurité).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/navigation/trace_svg.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/mesures_transverses.dart';
import '../../../synchronisation/domain/reinitialisation_serveur.dart';
import '../../../transverse/data/reinitialisation_locale.dart';
import '../../../transverse/presentation/providers_import_export.dart';
import '../../../transverse/presentation/widgets/briques_transverses.dart';

/// Les textes de la section (`pwa.import_export.seeders_*`, `reset_*`), au mot — déplacés de
/// `TextesImportExport` avec la fonction.
TextStyle get _titreCarte => styleTransverse(
  TaillesContenu.sm,
  poids: FontWeight.bold,
  couleur: Ardoise.c700,
);

TextStyle get _aide =>
    styleTransverse(TaillesContenu.t13, couleur: Ardoise.c500);

abstract final class TextesReinitialisation {
  static const String ongletSeeders = 'Réinitialiser les données de test';
  static const String seedersVerrouilleTitre = 'Réinitialisation désactivée';
  static const String seedersVerrouilleTexte =
      'Cette fonction vide les jeux de données de démonstration. Elle reste fermée par défaut : laissée ouverte sur une base d\'exploitation réelle, elle détruirait le travail de l\'entreprise.';
  // « Réinitialiser comme neuf » (lot E, 14/10/2026) — les mots de la vue.
  static const String seedersVerrouilleOuvrirAvant =
      "Un administrateur peut l'ouvrir dans";
  static const String seedersVerrouilleOuvrirLien =
      'Paramètres › Activation & Sécurité';
  static const String seedersBandeauTitre =
      "Fonction ouverte — à refermer dès que l'exploitation réelle commence";

  /// `seeders_bandeau_texte` (au mot) — vraie sur ce poste depuis le
  /// 21/10/2026 : la sauvegarde de sûreté est rangée AVANT le vidage.
  static const String seedersBandeauTexte =
      "Une sauvegarde complète est générée automatiquement avant chaque réinitialisation. C'est le seul filet si la bascule était restée ouverte par erreur.";
  static const String seedersVideTitre = 'Ce qui sera vidé';
  static const String seedersVideTexte =
      "Tout ce que l'exploitation produit : clients, employés et paie, fournisseurs, guides, réservations et séjours, ventes, factures, achats, dépenses, locations, écritures comptables, notifications, caches et files de tâches. Et tout le catalogue : plats, menus, recettes et ingrédients, articles de stock et leurs mouvements, inventaires, carte des boissons, retraits de la carte et historique des prix.";
  static const String seedersConserveTitre = 'Ce qui sera conservé';
  static const String seedersConserveTexte =
      'Comptes et droits, paramètres, journaux, chambres du parc, points de stockage et tables de salle (les lieux, sans article), véhicules, catalogue tourisme et plan comptable.';
  static const String seedersRienAVider =
      'Aucune donnée à vider — la base est déjà vierge.';
  static const String seedersBouton = 'Réinitialiser comme neuf';
  static const String seedersModaleTitre = 'Réinitialiser comme neuf ?';
  static String seedersModaleTexteAvant(int nombre) => '$nombre table(s)';
  static const String seedersModaleTexte1 =
      "vont être vidées : clients, employés, fournisseurs, guides, réservations, ventes, factures, écritures, paie, ainsi que tout le catalogue (plats, menus, recettes et ingrédients, articles de stock et leurs mouvements, inventaires, carte des boissons, retraits de la carte) et tous les jeux de démonstration. Rien n'est semé à nouveau.";
  static const String seedersModaleTexte2 =
      "Les paramètres de l'entreprise, la matrice des droits, votre compte, le journal d'audit, les chambres, les points de stockage, les tables de salle, les véhicules et le catalogue tourisme sont";
  static const String seedersModaleTexte2Fort = 'conservés';
  static const String seedersConfirmationAvant = 'Pour confirmer, saisissez';
  static const String seedersPhraseConfirmation = 'VIDER';
  static const String seedersConfirmationAide =
      "Une saisie plutôt qu'un simple clic : c'est la seule barrière qui résiste à un double-clic distrait.";
  static const String seedersConfirmer = 'Vider définitivement';
  static const String seedersPhraseInvalide =
      'La phrase tapée ne correspond pas à $seedersPhraseConfirmation.';
  // Phase d'essais en production (19/10/2026) — la phrase de la vue,
  // affichée quand le SERVEUR l'annonce (en-tête de synchronisation).
  static const String resetPhaseEssais =
      "Phase d'essais en Production : la réinitialisation reste possible pour effacer les essais avant la mise en service. Chaque poste devra ensuite être réinitialisé à son tour. Désactivez la phase d'essais le jour de la mise en service réelle.";
  static const String resetEnvironnementProduction =
      "Cet écran s'exécute en Production : la réinitialisation est désactivée, quel que soit votre rôle — c'est l'environnement qui refuse, pas un droit qui manque.";

  /// `seeders_modale_texte_2_fin` (au mot) : vraie depuis le 21/10/2026.
  static const String seedersModaleTexte2Fin =
      '. Une sauvegarde complète est générée juste avant.';
  static String seedersFaitSurCePoste(
    int tables,
    int lignes, {
    String? sauvegarde,
  }) =>
      '$tables table(s) vidée(s), $lignes ligne(s) supprimée(s). Les '
      'paramètres, les droits et les référentiels gardés sont intacts'
      '${sauvegarde == null ? '.' : ' — sauvegarde $sauvegarde générée juste avant.'}';
  static const String annuler = 'Annuler';
}

/// La section « Réinitialiser les données de test » de Paramètres › Activation & Sécurité
/// (09/11/2026, décision du PO : « Ramène le bouton … dans PARAMÈTRES » ; elle vivait dans
/// Import & Export depuis le 14/10/2026). LOGIQUE INCHANGÉE (`ReinitialisationLocale`). Les trois états de la vue : Production
/// (encadré rouge), VERROUILLÉ (bascule fermée : cadenas et renvoi aux
/// Paramètres), OUVERT (bandeau, les deux listes mesurées sur la base, le
/// bouton « Réinitialiser comme neuf » et sa modale).
class SectionReinitialisation extends ConsumerStatefulWidget {
  const SectionReinitialisation({
    required this.peutEcrire,
    required this.role,
    super.key,
  });

  final bool peutEcrire;
  final String? role;

  @override
  ConsumerState<SectionReinitialisation> createState() =>
      _SectionReinitialisationState();
}

typedef _EtatReinitialisation = ({
  bool ouverte,
  List<String> effacables,
  List<String> preservees,
  // Le serveur a été réinitialisé (19/10/2026) : la remise à neuf de CE
  // poste s'ouvre, même en build production et bascule fermée.
  DateTime? serveurReinitialiseLe,
  // Le serveur annonce la phase d'essais en production.
  bool phaseEssais,
});

class _SectionReinitialisationState
    extends ConsumerState<SectionReinitialisation> {
  static const String _cadenas =
      r'<rect x="3" y="11" width="18" height="11" rx="2"/><path stroke-linecap="round" d="M7 11V7a5 5 0 0110 0v4"/>';
  static const String _alerte =
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M12 9v4m0 4h.01M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/>';
  static const String _corbeille =
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M3 6h18M8 6V4a2 2 0 012-2h4a2 2 0 012 2v2m3 0v14a2 2 0 01-2 2H7a2 2 0 01-2-2V6h14z"/>';

  late Future<_EtatReinitialisation> _etat;

  ReinitialisationLocale get _moteur => ReinitialisationLocale(
    ref.read(baseLocaleProvider),
    sauvegardes: ref.read(sauvegardesPosteProvider),
  );

  @override
  void initState() {
    super.initState();
    _etat = _lire();
  }

  // La bascule et les listes sont relues à chaque ouverture de l'onglet et
  // après chaque réinitialisation, jamais gardées d'une visite à l'autre.
  Future<_EtatReinitialisation> _lire() async {
    final moteur = _moteur;
    final serveurReinitialiseLe = await moteur.reinitialisationServeur();
    return (
      ouverte: serveurReinitialiseLe != null || await moteur.estOuverte(),
      effacables: await moteur.tablesEffacables(),
      preservees: await moteur.tablesPreservees(),
      serveurReinitialiseLe: serveurReinitialiseLe,
      phaseEssais: await moteur.phaseEssaisServeur(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_EtatReinitialisation>(
      future: _etat,
      builder: (context, instantane) {
        final etat = instantane.data;
        final reinitialiseLe = etat?.serveurReinitialiseLe;
        final autorisee = _moteur.estAutorisee || reinitialiseLe != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (reinitialiseLe != null) ...[
              EncadreTransverse(
                key: const Key('param-reinit-serveur-reinitialise'),
                fond: PaletteMaitre.rouge50,
                bordure: PaletteMaitre.rouge200,
                child: Text(
                  TextesReinitialisationServeur.constatee(reinitialiseLe),
                  style: styleTransverse(
                    TaillesContenu.t13,
                    poids: FontWeight.w600,
                    couleur: PaletteMaitre.rouge900,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.mdPlus),
            ],
            if (etat?.phaseEssais ?? false) ...[
              EncadreTransverse(
                key: const Key('param-reinit-phase-essais'),
                fond: PaletteMaitre.ambre50,
                bordure: PaletteMaitre.ambre200,
                child: Text(
                  TextesReinitialisation.resetPhaseEssais,
                  style: styleTransverse(
                    TaillesContenu.t13,
                    couleur: PaletteMaitre.ambre900,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.mdPlus),
            ],
            if (!autorisee) ...[
              EncadreTransverse(
                key: const Key('param-reinit-production'),
                fond: PaletteMaitre.rouge50,
                bordure: PaletteMaitre.rouge200,
                child: Text(
                  TextesReinitialisation.resetEnvironnementProduction,
                  style: styleTransverse(
                    TaillesContenu.t13,
                    couleur: PaletteMaitre.rouge900,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.mdPlus),
            ],
            // Pendant la lecture, l'état VERROUILLÉ : une fonction
            // destructrice n'apparaît pas par défaut d'information.
            if (etat == null || !etat.ouverte)
              _verrouille(context)
            else
              ..._ouvert(context, etat, autorisee),
          ],
        );
      },
    );
  }

  Widget _verrouille(BuildContext context) => CarteTransverse(
    key: const Key('param-reinit-verrouille'),
    padding: const EdgeInsets.all(AppSpacing.xl),
    child: Column(
      children: [
        Container(
          width: MesuresTransverses.cadenasReinitialisation,
          height: MesuresTransverses.cadenasReinitialisation,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.badgeGrisFond,
            shape: BoxShape.circle,
          ),
          child: const IconeTrace(
            trace: _cadenas,
            taille: AppLayout.iconeTitrePage,
            couleur: AppColors.neutre400,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(TextesReinitialisation.seedersVerrouilleTitre, style: _titreCarte),
        const SizedBox(height: AppSpacing.xxs),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Largeurs.maxLg),
          child: Text(
            TextesReinitialisation.seedersVerrouilleTexte,
            textAlign: TextAlign.center,
            style: styleTransverse(TaillesContenu.t15, couleur: Ardoise.c500),
          ),
        ),
      ],
    ),
  );

  List<Widget> _ouvert(
    BuildContext context,
    _EtatReinitialisation etat,
    bool autorisee,
  ) {
    Widget liste({
      required Key cle,
      required String titre,
      required String texte,
      required Color couleurTitre,
      required Color fond,
      required Color encre,
      required List<String> tables,
      String? vide,
    }) => CarteTransverse(
      key: cle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            titre,
            style: styleTransverse(
              TaillesContenu.sm,
              poids: FontWeight.bold,
              couleur: couleurTitre,
            ),
          ),
          const SizedBox(height: AppSpacing.unit),
          Text(texte, style: _aide),
          const SizedBox(height: AppSpacing.sm),
          if (tables.isEmpty && vide != null)
            Text(
              vide,
              style: styleTransverse(TaillesContenu.t13, couleur: Ardoise.c400),
            ),
          for (final t in tables)
            Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.unit),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: fond,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Text(
                t,
                style: styleTransverse(
                  TaillesContenu.t13,
                  couleur: encre,
                  police: AppTextStyles.policeMonospace,
                ),
              ),
            ),
        ],
      ),
    );

    final vide = liste(
      cle: const Key('param-reinit-vide'),
      titre: TextesReinitialisation.seedersVideTitre,
      texte: TextesReinitialisation.seedersVideTexte,
      couleurTitre: AppColors.erreur,
      fond: AppColors.badgeRougeFond,
      encre: PaletteTransverse.texteRouge,
      tables: etat.effacables,
      vide: TextesReinitialisation.seedersRienAVider,
    );
    final conserve = liste(
      cle: const Key('param-reinit-conserve'),
      titre: TextesReinitialisation.seedersConserveTitre,
      texte: TextesReinitialisation.seedersConserveTexte,
      couleurTitre: AppColors.succes,
      fond: AppColors.badgeVertFond,
      encre: PaletteTransverse.texteVert,
      tables: etat.preservees,
    );
    final large = MediaQuery.sizeOf(context).width >= AppBreakpoints.lg;

    return [
      EncadreTransverse(
        key: const Key('param-reinit-bandeau'),
        fond: AppColors.badgeRougeFond,
        bordure: PaletteTransverse.bordureRouge,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const IconeTrace(
              trace: _alerte,
              taille: MesuresTransverses.iconeModule,
              couleur: AppColors.erreur,
              epaisseur: MesuresTransverses.traitAppuye,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    TextesReinitialisation.seedersBandeauTitre,
                    style: styleTransverse(
                      TaillesContenu.t15,
                      poids: FontWeight.bold,
                      couleur: PaletteTransverse.texteRouge,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.unit),
                  Text(
                    TextesReinitialisation.seedersBandeauTexte,
                    style: styleTransverse(
                      TaillesContenu.t13,
                      couleur: PaletteTransverse.texteRouge,
                      interligne: AppLayout.interligneDetendu,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.mdPlus),
      if (large)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: vide),
            const SizedBox(width: AppSpacing.mdPlus),
            Expanded(child: conserve),
          ],
        )
      else ...[
        vide,
        const SizedBox(height: AppSpacing.mdPlus),
        conserve,
      ],
      if (widget.peutEcrire &&
          autorisee &&
          ReinitialisationLocale.estPermisA(widget.role)) ...[
        const SizedBox(height: AppSpacing.mdPlus),
        BoutonTransverse(
          cle: const Key('param-reinit-bouton'),
          libelle: TextesReinitialisation.ongletSeeders,
          fond: AppColors.navy,
          trace: _corbeille,
          taille: TaillesContenu.sm,
          pleineLargeur: true,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.mdPlus,
            vertical: AppSpacing.sm,
          ),
          onTap: () => _ouvrirModale(etat.effacables.length),
        ),
      ],
    ];
  }

  Future<void> _ouvrirModale(int nombre) async {
    final bilan = await showDialog<BilanReinitialisation>(
      context: context,
      builder: (_) => _ModaleReinitialisation(
        nombre: nombre,
        executer: () => _moteur.executer(role: widget.role),
      ),
    );
    if (!mounted || bilan == null) return;
    setState(() => _etat = _lire());
    direTransverse(
      context,
      TextesReinitialisation.seedersFaitSurCePoste(
        bilan.tablesVidees,
        bilan.lignesSupprimees,
        sauvegarde: bilan.sauvegarde,
      ),
      cle: const Key('param-reinit-fait'),
    );
  }
}

/// La modale de la vue : titre, texte, saisie du mot « VIDER », Annuler /
/// « Vider définitivement » — inerte tant que le mot n'est pas tapé ; le mot
/// est REVÉRIFIÉ au clic, et le moteur relit bascule, rôle et environnement.
class _ModaleReinitialisation extends StatefulWidget {
  const _ModaleReinitialisation({required this.nombre, required this.executer});

  final int nombre;
  final Future<BilanReinitialisation> Function() executer;

  @override
  State<_ModaleReinitialisation> createState() =>
      _ModaleReinitialisationState();
}

class _ModaleReinitialisationState extends State<_ModaleReinitialisation> {
  final _saisie = TextEditingController();
  String? _erreur;
  bool _enCours = false;

  bool get _motTape =>
      _saisie.text.trim().toUpperCase() ==
      TextesReinitialisation.seedersPhraseConfirmation;

  @override
  void dispose() {
    _saisie.dispose();
    super.dispose();
  }

  Future<void> _confirmer() async {
    if (!_motTape) {
      setState(() => _erreur = TextesReinitialisation.seedersPhraseInvalide);
      return;
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final bilan = await widget.executer();
      if (mounted) Navigator.of(context).pop(bilan);
    } on ReinitialisationRefusee catch (refus) {
      if (mounted) {
        setState(() {
          _enCours = false;
          _erreur = refus.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final texte = styleTransverse(
      TaillesContenu.t15,
      couleur: Ardoise.c600,
      interligne: AppLayout.interligneDetendu,
    );
    return Dialog(
      key: const Key('param-reinit-modale'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Largeurs.maxLg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                TextesReinitialisation.seedersModaleTitre,
                style: styleTransverse(
                  TaillesContenu.base,
                  poids: FontWeight.bold,
                  couleur: AppColors.erreur,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text:
                          '${TextesReinitialisation.seedersModaleTexteAvant(widget.nombre)} ',
                      style: texte.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const TextSpan(
                      text: '${TextesReinitialisation.seedersModaleTexte1}\n\n',
                    ),
                    const TextSpan(
                      text: '${TextesReinitialisation.seedersModaleTexte2} ',
                    ),
                    TextSpan(
                      text: TextesReinitialisation.seedersModaleTexte2Fort,
                      style: texte.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const TextSpan(
                      text: TextesReinitialisation.seedersModaleTexte2Fin,
                    ),
                  ],
                ),
                style: texte,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                '${TextesReinitialisation.seedersConfirmationAvant} '
                '${TextesReinitialisation.seedersPhraseConfirmation}',
                style: styleTransverse(
                  TaillesContenu.t13,
                  poids: FontWeight.w600,
                  couleur: Ardoise.c700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              TextField(
                key: const Key('param-reinit-saisie'),
                controller: _saisie,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) => setState(() {}),
                style: styleTransverse(
                  TaillesContenu.sm,
                  police: AppTextStyles.policeMonospace,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: TextesReinitialisation.seedersPhraseConfirmation,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                TextesReinitialisation.seedersConfirmationAide,
                style: styleTransverse(
                  TaillesContenu.t12,
                  couleur: Ardoise.c400,
                ),
              ),
              if (_erreur != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _erreur!,
                  key: const Key('param-reinit-erreur'),
                  style: styleTransverse(
                    TaillesContenu.t12,
                    couleur: PaletteMaitre.rouge600,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.mdPlus),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  BoutonTransverse(
                    cle: const Key('param-reinit-annuler'),
                    libelle: TextesReinitialisation.annuler,
                    taille: TaillesContenu.sm,
                    couleurContour: Ardoise.c200,
                    couleurTexteContour: Ardoise.c600,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Opacity(
                    opacity: _motTape && !_enCours ? 1 : 0.5,
                    child: BoutonTransverse(
                      cle: const Key('param-reinit-confirmer'),
                      libelle: TextesReinitialisation.seedersConfirmer,
                      fond: AppColors.erreur,
                      taille: TaillesContenu.sm,
                      onTap: () {
                        if (_motTape && !_enCours) _confirmer();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
