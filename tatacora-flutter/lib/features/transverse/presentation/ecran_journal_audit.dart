// Vue Blade maîtresse (PA-183) : pwa/transverse/journal-audit.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/navigation/coquille_vue.dart';
import '../../../core/navigation/trace_svg.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/mesures_transverses.dart';
import '../domain/journal_poste.dart';
import 'providers_transverses.dart';
import 'widgets/briques_transverses.dart';

/// L'écran **Journal d'Audit** — lot D du plan du Product Owner (14/10/2026),
/// rendu actif le 21/10/2026 (ordre du PO « tout doit être au complet »).
///
/// Structure de la vue : en-tête ; rangée recherche + filtre d'action ;
/// tableau à six colonnes (Utilisateur, Action, Détail, Date, Heure, Poste) ;
/// mention de lecture seule ; décompte, ou troncature au-delà de
/// [plafondJournalAudit] lignes.
///
/// ## La source de ce poste : la file d'envoi
///
/// Le registre de la vue est `journal_audit` du serveur, écrit par ses
/// observateurs. Ce poste n'a aucune table d'audit ; son registre inaltérable
/// est la file d'envoi (voir `journal_poste.dart`) : chaque création et chaque
/// modification qu'il a écrites, avec l'instant d'écriture, le compte connecté
/// et le nom du poste (v38, 26/10/2026). Seule une entrée d'avant la v38, ou
/// écrite sans compte, garde « — » (donnée absente, Article 7 de la vue). Une
/// phrase au pied de l'écran dit d'où vient le registre.
///
/// Droit : la route de la vue exige M14 en lecture (`module:M14,L`) ; sans
/// lui, l'écran le DIT.
class EcranJournalAudit extends ConsumerStatefulWidget {
  const EcranJournalAudit({super.key});

  @override
  ConsumerState<EcranJournalAudit> createState() => _EtatEcranJournalAudit();
}

class _EtatEcranJournalAudit extends ConsumerState<EcranJournalAudit> {
  final _recherche = TextEditingController();
  ActionJournalPoste? _action;

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final droits = ref.watch(droitsProvider);
    if (!droits.peutLire(ModuleTatacora.m14Etats)) {
      return const RefusDroitTransverse(message: LibellesCoquille.sansDroit);
    }
    final large = MediaQuery.sizeOf(context).width >= AppBreakpoints.lg;
    final toutes = ref.watch(journalDuPosteProvider).value ?? const [];
    final vue = filtrerJournalPoste(
      toutes,
      recherche: _recherche.text,
      action: _action,
    );
    // Les actions RÉELLEMENT présentes, comme la vue (`actionsPresentes`) : un
    // filtre qui propose une valeur inatteignable passe pour cassé.
    final presentes = [
      for (final a in ActionJournalPoste.values)
        if (toutes.any((e) => e.action == a)) a,
    ];
    final filtres = [
      TextField(
        key: const Key('journal-recherche'),
        controller: _recherche,
        onChanged: (_) => setState(() {}),
        style: styleTransverse(TaillesContenu.sm),
        decoration: InputDecoration(
          isDense: true,
          hintText: TextesJournalAudit.recherche,
          prefixIcon: const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.smPlus),
            child: IconeTrace(
              trace: TracesCoquille.loupe,
              taille: MesuresTransverses.iconePetite,
              couleur: AppColors.neutre400,
            ),
          ),
          prefixIconConstraints: const BoxConstraints(),
          filled: true,
          fillColor: AppColors.neutre0,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: Ardoise.c200),
          ),
        ),
      ),
      Container(
        key: const Key('journal-filtre-action'),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.neutre0,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: Ardoise.c200),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<ActionJournalPoste?>(
            value: _action,
            style: styleTransverse(TaillesContenu.t15, couleur: Ardoise.c400),
            items: [
              const DropdownMenuItem<ActionJournalPoste?>(
                child: Text(TextesJournalAudit.toutesActions),
              ),
              for (final a in presentes)
                DropdownMenuItem<ActionJournalPoste?>(
                  value: a,
                  child: Text(a.libelle),
                ),
            ],
            onChanged: (a) => setState(() => _action = a),
          ),
        ),
      ),
    ];
    final tronque = vue.total > plafondJournalAudit;

    return PageTransverse(
      largeurMax: MesuresTransverses.pageLarge,
      enfants: [
        const EnTeteTransverse(
          trace: TracesCoquille.journalAudit,
          titre: TextesJournalAudit.titre,
          sousTitre: TextesJournalAudit.sousTitre,
          margeBas: AppSpacing.mdPlus, // mb-5
        ),
        if (large)
          Row(
            children: [
              Expanded(child: filtres[0]),
              const SizedBox(width: AppSpacing.sm),
              filtres[1],
            ],
          )
        else ...[
          filtres[0],
          const SizedBox(height: AppSpacing.sm),
          filtres[1],
        ],
        const SizedBox(height: AppSpacing.md), // mb-4
        CarteTransverse(
          padding: EdgeInsets.zero,
          child: TableauTransverse(
            colonnes: const [
              (
                titre: TextesJournalAudit.colUtilisateur,
                alignement: TextAlign.left,
              ),
              (titre: TextesJournalAudit.colAction, alignement: TextAlign.left),
              (titre: TextesJournalAudit.colDetail, alignement: TextAlign.left),
              (titre: TextesJournalAudit.colDate, alignement: TextAlign.left),
              (titre: TextesJournalAudit.colHeure, alignement: TextAlign.left),
              (titre: TextesJournalAudit.colPoste, alignement: TextAlign.left),
            ],
            lignes: [
              for (final e in vue.entrees)
                [
                  // Article 7 de la vue : « — » quand la donnée n'existe pas.
                  celluleTexte(
                    e.utilisateur ?? TextesJournalAudit.absent,
                    couleur: Ardoise.c700,
                    poids: FontWeight.w500,
                  ),
                  _pastilleAction(e.action),
                  celluleTexte(
                    // Le séparateur de la vue n'est PAS un tiret cadratin.
                    '${e.libelleTable} : ${e.entiteId}',
                    couleur: Ardoise.c500,
                  ),
                  celluleTexte(
                    _date(e.dateHeure),
                    couleur: Ardoise.c500,
                    mono: true,
                    taille: TaillesContenu.t15,
                  ),
                  celluleTexte(
                    _heure(e.dateHeure),
                    couleur: Ardoise.c500,
                    mono: true,
                    taille: TaillesContenu.t15,
                  ),
                  celluleTexte(
                    e.poste ?? TextesJournalAudit.absent,
                    couleur: Ardoise.c400,
                    taille: TaillesContenu.t15,
                  ),
                ],
            ],
            vide: TextesJournalAudit.vide,
            cleVide: const Key('journal-vide'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm), // mt-3
        Text(
          TextesJournalAudit.mentionLectureSeule,
          style: styleTransverse(TaillesContenu.t13, couleur: Ardoise.c400),
        ),
        const SizedBox(height: AppSpacing.xs), // mt-2
        if (tronque)
          Text(
            TextesJournalAudit.tronque(plafondJournalAudit, vue.total),
            key: const Key('journal-decompte'),
            style: styleTransverse(
              TaillesContenu.t13,
              couleur: PaletteMaitre.ambre900,
            ),
          )
        else
          Text(
            TextesJournalAudit.decompte(vue.total),
            key: const Key('journal-decompte'),
            style: styleTransverse(TaillesContenu.t13, couleur: Ardoise.c400),
          ),
        // AJOUT du poste, absent de la vue : d'où vient ce registre.
        const SizedBox(height: AppSpacing.xs),
        Text(
          TextesJournalAudit.sourceDuPoste,
          key: const Key('journal-source-poste'),
          style: styleTransverse(TaillesContenu.t13, couleur: Ardoise.c400),
        ),
      ],
    );
  }

  /// La pastille d'action — `text-[15px] font-semibold px-2.5 py-1 rounded`,
  /// aux couleurs du registre de la vue (`JournalAudit::ACTIONS`).
  static Widget _pastilleAction(ActionJournalPoste a) {
    final (fond, texte) = switch (a) {
      ActionJournalPoste.creation => (AppColors.badgeBleuFond, AppColors.info),
      ActionJournalPoste.modification => (
        AppColors.reserveGoldFond,
        AppColors.gold,
      ),
      // `JournalAudit::ACTIONS['suppression']` : #FDECEC / #C62828.
      ActionJournalPoste.suppression ||
      ActionJournalPoste.codeSecoursRefuse ||
      ActionJournalPoste.codeSecoursBloque => (
        AppColors.badgeRougeFond,
        AppColors.erreur,
      ),
      // `JournalAudit::ACTIONS` (29/10/2026) : réinitialisations en doré,
      // code de secours posé en bleu.
      ActionJournalPoste.reinitialisationMotDePasse ||
      ActionJournalPoste.adresseServeurModifiee ||
      ActionJournalPoste.codeSecoursUtilise => (
        AppColors.reserveGoldFond,
        AppColors.gold,
      ),
      ActionJournalPoste.codeSecoursGenere => (
        AppColors.badgeBleuFond,
        AppColors.info,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xsPlus, // px-2.5
        vertical: AppSpacing.unit, // py-1
      ),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(AppRadius.sm), // rounded
      ),
      child: Text(
        a.libelle,
        style: styleTransverse(
          TaillesContenu.t15,
          poids: FontWeight.w600,
          couleur: texte,
        ),
      ),
    );
  }

  static String _deux(int n) => n.toString().padLeft(2, '0');

  /// `d/m/Y` de la vue.
  static String _date(DateTime d) =>
      '${_deux(d.day)}/${_deux(d.month)}/${d.year}';

  /// `H:i:s` de la vue.
  static String _heure(DateTime d) =>
      '${_deux(d.hour)}:${_deux(d.minute)}:${_deux(d.second)}';
}

/// Les textes de la vue (`pwa.journal_audit.*`), au mot.
abstract final class TextesJournalAudit {
  static const String titre = "Journal d'Audit";
  static const String sousTitre =
      'Traçabilité intégrale de toute action sensible — utilisateur, action, entité concernée, date et heure (, chap. 11.4 du CdCF)';
  static const String recherche = 'Rechercher (utilisateur, action, détail)...';
  static const String toutesActions = 'Toutes les actions';
  static const String colUtilisateur = 'Utilisateur';
  static const String colAction = 'Action';
  static const String colDetail = 'Détail';
  static const String colDate = 'Date';
  static const String colHeure = 'Heure';
  static const String colPoste = 'Poste';
  static const String mentionLectureSeule =
      "🔒 Ce journal est en lecture seule pour tous les profils, y compris l'Administrateur.";

  /// `pwa.journal_audit.vide`.
  static const String vide = 'Aucune entrée ne correspond à votre recherche.';

  /// La donnée absente — « — » (Article 7 de la vue).
  static const String absent = '—';

  /// `pwa.journal_audit.decompte` — « :total entrée(s) au registre pour ce
  /// filtre. »
  static String decompte(int total) =>
      '$total entrée(s) au registre pour ce filtre.';

  /// `pwa.journal_audit.tronque` — « Seules les :plafond entrées les plus
  /// récentes sont affichées sur :total. Affinez la recherche ou le filtre
  /// d'action pour atteindre les autres. »
  static String tronque(int plafond, int total) =>
      "Seules les $plafond entrées les plus récentes sont affichées sur $total. Affinez la recherche ou le filtre d'action pour atteindre les autres.";

  /// AJOUT déclaré (D423, révisé le 21/10/2026) : la source de ce registre.
  static const String sourceDuPoste =
      "Registre de ce poste : chaque création et chaque modification qu'il a écrites, avec l'heure d'écriture, le compte connecté et le nom du poste (la vue du serveur montre l'adresse réseau). Une entrée d'avant cette version, ou écrite sans compte connecté, garde « — » ; les connexions et les suppressions ne sont pas tracées ici.";
}
