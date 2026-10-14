/// La modale d'archivage d'une unité — **et la vue n'y supprime pas**.
///
/// Vue Blade maîtresse (PA-183) : pwa/hebergement/hebergement.blade.php
/// (composant `modale-archivage`, invoqué l.615-619).
///
/// ## Deux états, et le premier est celui qui compte
///
/// 1. **BLOQUÉ** — l'unité est engagée dans une réservation à venir. La vue
///    affiche « Archivage impossible », liste les motifs, et **masque** le
///    bouton de confirmation. Le laisser visible et inerte laisserait croire à
///    une panne ; le masquer dit que la décision n'appartient pas à cet écran.
/// 2. **NOMINAL** — la question, puis le rappel : rien n'est effacé.
///
/// L'état PARTIEL du composant serveur (« N élément(s) seront conservés ») n'a
/// pas d'équivalent ici : il sert la sélection multiple, que cet écran ne porte
/// pas — la vue elle-même déclare sa barre d'action groupée refusée, « le “D”
/// de CRUD n'existe nulle part dans ce dépôt ».
///
/// ## Le titre dit « suppression », le corps dit « archiver »
///
/// Ce n'est pas une incohérence à lisser : le titre et le bouton sont le texte
/// que le client a validé, et le corps est ce que l'utilisateur lit juste avant
/// de cliquer. Rien ne supprime quoi que ce soit — [ParcDao.archiver] pose
/// `hors_service`, et l'unité reste restaurable.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/theme/app_colors.dart';
// `app_spacing.dart` réexporte `app_radius.dart` : l'importer en plus est
// inutile, et l'analyseur le signale.
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../parametres/presentation/providers_options_systeme.dart';
import '../../domain/entities/unite_hebergement.dart';
import '../../domain/refus_parc.dart';
import '../providers_hebergement.dart';

/// Ouvre la modale d'archivage. Rend `true` si l'unité a été archivée.
///
/// Les engagements sont relus **avant** d'ouvrir : la modale doit pouvoir dire
/// pourquoi elle refuse, et non découvrir le refus au moment du clic.
Future<bool> ouvrirArchivageUnite(
  BuildContext context,
  WidgetRef ref,
  UniteHebergement unite,
) async {
  final engagements = await ref.read(parcDaoProvider).engagements(unite.id);
  if (!context.mounted) return false;

  final archivee = await showDialog<bool>(
    context: context,
    builder: (context) =>
        _ModaleArchivage(unite: unite, engagements: engagements),
  );
  return archivee ?? false;
}

class _ModaleArchivage extends ConsumerStatefulWidget {
  const _ModaleArchivage({required this.unite, required this.engagements});

  final UniteHebergement unite;
  final List<EngagementUnite> engagements;

  @override
  ConsumerState<_ModaleArchivage> createState() => _ModaleArchivageState();
}

class _ModaleArchivageState extends ConsumerState<_ModaleArchivage> {
  String? _erreur;

  bool get _bloque => widget.engagements.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // Le titre de la vue, mot pour mot (`pwa.archivage.titre`).
      title: const Text(
        'Confirmer la suppression',
        textAlign: TextAlign.center,
      ),
      content: SizedBox(
        width: AppLayout.modaleArchivageUnite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _pastilleRouge(),
              const SizedBox(height: AppSpacing.md),
              if (_bloque) ..._etatBloque() else ..._etatNominal(),
              if (_erreur != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    _erreur!,
                    key: const Key('plan-archivage-erreur'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: PaletteMaitre.rouge600,
                      fontFamily: AppTextStyles.police,
                      fontSize: Tailles.t12,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      // Boutons CENTRÉS, pas alignés à droite — la vue les centre.
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          key: const Key('plan-archivage-annuler'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        // Le bouton DISPARAÎT quand l'archivage est bloqué — il n'est pas
        // grisé. Un bouton grisé invite à cliquer et ne produit qu'un refus.
        if (!_bloque)
          FilledButton(
            key: const Key('plan-archivage-confirmer'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.erreur),
            onPressed: _archiver,
            child: const Text('Supprimer définitivement'),
          ),
      ],
    );
  }

  /// Le rond rouge et sa corbeille — `w-14 h-14 rounded-full bg-red-50`.
  Widget _pastilleRouge() => Center(
    child: Container(
      width: AppSpacingLarge.p14,
      height: AppSpacingLarge.p14,
      decoration: const BoxDecoration(
        color: PaletteMaitre.rouge50,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.delete_outline,
        color: AppColors.erreur,
        size: AppSpacing.lgPlus,
      ),
    ),
  );

  /// ÉTAT 1 — plus rien n'est archivable.
  List<Widget> _etatBloque() => [
    const Text(
      'Archivage impossible',
      key: Key('plan-archivage-impossible'),
      textAlign: TextAlign.center,
      style: TextStyle(
        color: AppColors.erreur,
        fontFamily: AppTextStyles.police,
        fontSize: Tailles.t13,
        fontWeight: FontWeight.w600,
      ),
    ),
    const SizedBox(height: AppSpacing.xxs),
    // Le motif NOMME les réservations qui tiennent la chambre : « il ne peut
    // pas être archivé » sans dire par quoi enverrait chercher ailleurs.
    Text(
      UniteEngagee(widget.engagements).message,
      key: const Key('plan-archivage-verrou'),
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Ardoise.c600,
        fontFamily: AppTextStyles.police,
        fontSize: Tailles.t13,
      ),
    ),
    const SizedBox(height: AppSpacing.xs),
    const Text(
      "Retirez d'abord l'élément des opérations concernées, ou laissez-le en place : une carte historique reste lisible.",
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Ardoise.c500,
        fontFamily: AppTextStyles.police,
        fontSize: Tailles.t13,
      ),
    ),
  ];

  /// ÉTAT 3 — la question, puis le rappel.
  List<Widget> _etatNominal() => [
    // `pwa.archivage.question` + `hebergement_pwa…archivage_element`, assemblés
    // comme la vue les assemble : « Voulez-vous archiver l'unité BNG-01 ? ».
    Text(
      "Voulez-vous archiver l'unité ${widget.unite.numero} ?",
      key: const Key('plan-archivage-question'),
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Ardoise.c500,
        fontFamily: AppTextStyles.police,
        fontSize: Tailles.t14,
      ),
    ),
    const SizedBox(height: AppSpacing.xs),
    // Le rappel de la vue. Son `<strong>` porte sur « archives » ; en Flutter
    // la phrase est rendue d'un seul tenant — la mise en gras d'un mot n'est
    // pas ce qui la rend vraie.
    const Text(
      "L'élément part aux archives et reste restaurable — rien n'est effacé.",
      key: Key('plan-archivage-rappel'),
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Ardoise.c500,
        fontFamily: AppTextStyles.police,
        fontSize: Tailles.t13,
      ),
    ),
  ];

  Future<void> _archiver() async {
    try {
      // La bascule « Suppression d'un enregistrement » est RELUE au moment du
      // geste, par son lecteur déclaré (`lireSuppressionActive`) : elle a pu
      // être refermée en Paramètres entre l'ouverture de cette modale et le
      // clic. Même partage que le serveur : le COMPOSANT revérifie la bascule
      // (`Hebergement::archiverUnite` → `exigerSuppressionOuverte()`), le
      // service garde le verrou des réservations.
      if (!await lireSuppressionActive(ref.read(baseLocaleProvider))) {
        throw const SuppressionFermee();
      }
      // Le verrou est RECONTRÔLÉ par le DAO au moment d'agir : entre
      // l'ouverture de cette modale et le clic, une réservation a pu naître.
      await ref.read(parcDaoProvider).archiver(widget.unite.id);
    } on RefusParc catch (refus) {
      // Le message du domaine est rendu TEL QUEL : c'est lui qui nomme la
      // raison exacte, et la reformuler perdrait la seule information utile.
      if (mounted) setState(() => _erreur = refus.message);
      return;
    }

    if (!mounted) return;
    rafraichirListes(ref);
    Navigator.of(context).pop(true);
  }
}
