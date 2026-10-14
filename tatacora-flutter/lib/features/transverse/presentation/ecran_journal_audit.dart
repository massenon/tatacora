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
import 'widgets/briques_transverses.dart';

/// L'écran **Journal d'Audit** — lot D du plan du Product Owner (14/10/2026).
///
/// Structure de la vue : en-tête ; rangée recherche + filtre d'action ;
/// tableau à six colonnes (Utilisateur, Action, Détail, Date, Heure, Poste) ;
/// mention de lecture seule ; décompte.
///
/// ## Aucune source sur ce poste (D423)
///
/// Le registre de la vue est `journal_audit` du serveur, écrit par les
/// observateurs d'audit. Ce poste n'a AUCUNE table d'audit (le schéma Drift
/// n'en porte pas) : le tableau rend son état vide avec la raison, jamais
/// « Aucune entrée ne correspond à votre recherche » (qui supposerait un
/// registre filtré), et le décompte ne dit pas « 0 entrée(s) » (un zéro
/// plausible). La recherche et le filtre sont rendus, inactifs, avec la même
/// raison en infobulle : il n'y a rien à filtrer.
///
/// Droit : la route de la vue exige M14 en lecture (`module:M14,L`) ; sans
/// lui, l'écran le DIT.
class EcranJournalAudit extends ConsumerWidget {
  const EcranJournalAudit({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final droits = ref.watch(droitsProvider);
    if (!droits.peutLire(ModuleTatacora.m14Etats)) {
      return const RefusDroitTransverse(message: LibellesCoquille.sansDroit);
    }
    final large = MediaQuery.sizeOf(context).width >= AppBreakpoints.lg;
    final filtres = [
      Tooltip(
        message: TextesJournalAudit.aucuneSource,
        child: TextField(
          key: const Key('journal-recherche'),
          enabled: false,
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
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: const BorderSide(color: Ardoise.c200),
            ),
          ),
        ),
      ),
      Tooltip(
        message: TextesJournalAudit.aucuneSource,
        child: Container(
          key: const Key('journal-filtre-action'),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xsPlus,
          ),
          decoration: BoxDecoration(
            color: AppColors.neutre0,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: Ardoise.c200),
          ),
          child: Text(
            TextesJournalAudit.toutesActions,
            style: styleTransverse(TaillesContenu.t15, couleur: Ardoise.c400),
          ),
        ),
      ),
    ];

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
        const CarteTransverse(
          padding: EdgeInsets.zero,
          child: TableauTransverse(
            colonnes: [
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
            lignes: [],
            vide: TextesJournalAudit.aucuneSource,
            cleVide: Key('journal-vide'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm), // mt-3
        Text(
          TextesJournalAudit.mentionLectureSeule,
          style: styleTransverse(TaillesContenu.t13, couleur: Ardoise.c400),
        ),
        const SizedBox(height: AppSpacing.xs), // mt-2
        Text(
          TextesJournalAudit.decompteSurCePoste,
          key: const Key('journal-decompte'),
          style: styleTransverse(TaillesContenu.t13, couleur: Ardoise.c400),
        ),
      ],
    );
  }
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
      "🔒 Ce journal est en lecture seule pour tous les profils, y compris l'Administrateur, conformément au chap. 11.4 du CdCF.";

  /// AJOUTS déclarés (D423).
  static const String aucuneSource =
      "Ce poste ne tient pas de journal d'audit : aucune action n'y est "
      "tracée, il n'y a donc rien à afficher ni à filtrer.";
  static const String decompteSurCePoste =
      "Aucun registre sur ce poste : le décompte de la vue ne s'applique pas.";
}
