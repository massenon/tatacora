/// Le bouton de SYNCHRONISATION de la barre supérieure et sa modale (lot F3,
/// demande du Product Owner du 16/10/2026 : « la synchronisation manuelle à
/// partir d'un bouton sur le topbar qui ouvre un modal », à côté de la
/// synchronisation automatique — démarrage, toutes les 5 min, après une
/// clôture de caisse — qui ne change pas).
///
/// AJOUT à la vue : la barre supérieure de la PWA n'a pas de bouton de
/// synchronisation (elle est servie par le serveur). Il se pose à gauche de la
/// cloche, avec la forme de la cloche (`p-2`, tracé 20 px, badge `h-3.5`).
///
/// ## Le bouton
///
/// Un voyant ([voyantSynchronisationProvider]) : vert (rien en attente),
/// orange + nombre (opérations en attente), rouge + nombre (à traiter, ou
/// jeton refusé), gris (démonstration, non appairé, serveur injoignable). La
/// phrase de l'état est l'infobulle. Aucune couleur avant la première lecture.
///
/// ## La modale
///
/// L'état en clair, trois compteurs (envoyées, en attente, à traiter), le
/// dernier passage de CETTE session et la dernière réception du serveur ;
/// « Synchroniser maintenant » (tous les comptes : envoyer ce qu'on a saisi
/// n'est pas un geste d'administration) avec sa progression, puis le bilan ;
/// « Voir le détail » mène à l'écran `/synchronisation` quand le compte y a
/// accès — « Renvoyer » et « Débloquer » y restent réservés aux
/// Administrateurs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/format/formats.dart';
import '../../../core/navigation/coquille_vue.dart';
import '../../../core/navigation/navigation_tatacora.dart';
import '../../../core/navigation/trace_svg.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared_widgets/bouton_standard.dart';
import '../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../restaurant/presentation/widgets/textes_modale_restaurant.dart';
import '../domain/bilan_synchronisation.dart';
import '../domain/descente_catalogue.dart';
import '../domain/operation_sync.dart';
import '../domain/voyant_synchronisation.dart';
import 'providers_synchronisation.dart';

/// Les mots du bouton et de la modale.
abstract final class TextesBoutonSynchronisation {
  static const etiquette = 'Synchronisation';
  static const titre = 'Synchronisation';
  static const envoyees = 'Envoyées au serveur';
  static const enAttente = 'En attente d\'envoi';
  static const aTraiter = 'À traiter';
  static const synchroniser = 'Synchroniser maintenant';
  static const detail = 'Voir le détail';
  static const fermer = 'Fermer';
  static const enCours =
      'Envoi de la file, puis réception du serveur… Vous pouvez fermer cette '
      'fenêtre : la synchronisation continue.';
  static const aucunPassage =
      'Aucune synchronisation depuis l\'ouverture du logiciel.';
  static String passage(BilanSynchronisation b) =>
      'Dernier passage : ${b.etat.libelle} Acceptées ${b.synchronisees}, '
      'rejetées ${b.rejetees}, en conflit ${b.conflits}.';
  static const jamaisRecu =
      'Rien n\'a encore été reçu du serveur sur ce poste.';
  static String recu(BilanDescente d) {
    final quand = d.termineeLe == null
        ? ''
        : ' le ${formaterDate(d.termineeLe!.toLocal())} à '
              '${_heure(d.termineeLe!.toLocal())}';
    return 'Dernière réception$quand : ${d.etat.libelle} '
        '${d.appliques} élément(s) appliqué(s).';
  }

  /// Ce que la réception apporte — la réponse à la question du PO du
  /// 16/10/2026 (« le poste B aura-t-il ce que le poste A a enregistré ? »).
  static const portee =
      'Ce poste reçoit du serveur le catalogue, les clients et les '
      'réservations saisis sur les autres postes. Les ventes, dépenses et '
      'caisses des autres postes se consultent sur le serveur.';

  static String _heure(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

/// La couleur d'une teinte — jetons du thème, jamais une valeur en dur.
Color couleurVoyant(TeinteVoyant t) => switch (t) {
  TeinteVoyant.gris => AppColors.neutre400,
  TeinteVoyant.rouge => AppColors.erreur,
  TeinteVoyant.orange => PaletteMaitre.ambre400,
  TeinteVoyant.vert => AppColors.succes,
};

class BoutonSynchronisation extends ConsumerStatefulWidget {
  const BoutonSynchronisation({super.key});

  @override
  ConsumerState<BoutonSynchronisation> createState() =>
      _EtatBoutonSynchronisation();
}

class _EtatBoutonSynchronisation extends ConsumerState<BoutonSynchronisation> {
  bool _survol = false;

  @override
  Widget build(BuildContext context) {
    final voyant = ref.watch(voyantSynchronisationProvider);
    final couleur = voyant == null ? null : couleurVoyant(voyant.teinte);

    return Tooltip(
      message: voyant?.phrase ?? TextesBoutonSynchronisation.etiquette,
      child: MouseRegion(
        onEnter: (_) => setState(() => _survol = true),
        onExit: (_) => setState(() => _survol = false),
        child: Semantics(
          label: TextesBoutonSynchronisation.etiquette,
          button: true,
          child: InkWell(
            key: const Key('bouton-synchronisation'),
            onTap: () => ouvrirModaleSynchronisation(context),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.xs), // p-2
                  child: IconeTrace(
                    trace: TracesCoquille.synchronisation,
                    taille: MesuresBarreSuperieure.iconeCloche,
                    couleur: AppColors.neutre0.withValues(
                      alpha: _survol ? 1 : OpacitesBarreSuperieure.cloche,
                    ),
                  ),
                ),
                // Le voyant : un point de la teinte, ou le badge du nombre.
                if (couleur != null)
                  Positioned(
                    top: MesuresBarreSuperieure.decalageBadgeCloche,
                    right: MesuresBarreSuperieure.decalageBadgeCloche,
                    child: Container(
                      key: Key('voyant-synchronisation-${voyant!.teinte.name}'),
                      constraints: BoxConstraints(
                        minWidth: voyant.badge == null
                            ? AppSpacing.xs
                            : MesuresBarreSuperieure.badgeCloche,
                      ),
                      height: voyant.badge == null
                          ? AppSpacing.xs
                          : MesuresBarreSuperieure.badgeCloche,
                      padding: voyant.badge == null
                          ? EdgeInsets.zero
                          : const EdgeInsets.symmetric(
                              horizontal: AppSpacing.unit,
                            ),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: couleur,
                        borderRadius: BorderRadius.circular(
                          AppRadius.roundedFull,
                        ),
                      ),
                      child: voyant.badge == null
                          ? null
                          : Text(
                              '${voyant.badge}',
                              key: const Key('badge-synchronisation'),
                              style: TextStyle(
                                color: AppColors.neutre0,
                                fontFamily: AppTextStyles.police,
                                fontSize: Tailles.t8,
                                height: Tailles.interligneAucun,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ouvre la modale de synchronisation.
Future<void> ouvrirModaleSynchronisation(BuildContext context) =>
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: AppColors.voileModale,
      builder: (_) => const ModaleSynchronisation(),
    );

class ModaleSynchronisation extends ConsumerWidget {
  const ModaleSynchronisation({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voyant = ref.watch(voyantSynchronisationProvider);
    final comptes = ref.watch(comptesFileSynchronisationProvider).value;
    final bilan = ref.watch(dernierBilanSynchronisationProvider);
    final enCours = ref.watch(synchronisationEnCoursProvider);
    final appairage = ref.watch(appairageActuelProvider);
    final interdite =
        ref.watch(synchronisationInterditeProvider) ||
        ref.watch(urlServeurSynchronisationProvider) == null;
    final descente = ref.watch(etatFileSynchronisationProvider).value;
    final session = ref.watch(sessionProvider);
    final detailAccessible =
        accesRoute(
          '/synchronisation',
          droits: ref.watch(droitsProvider),
          role: session?.role,
        ) ==
        AccesRoute.autorise;

    int n(List<StatutOperationSync> statuts) =>
        statuts.fold(0, (a, s) => a + (comptes?[s] ?? 0));

    Widget ligne(String texte, {Key? cle, Color? couleur}) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        texte,
        key: cle,
        style: TextesModaleRestaurant.aide.copyWith(color: couleur),
      ),
    );

    return CoquilleModaleRestaurant(
      cle: const Key('modale-synchronisation'),
      titre: TextesBoutonSynchronisation.titre,
      sousTitre: voyant?.phrase,
      largeur: AppLayout.modaleExportPwa,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (comptes != null)
            Row(
              children: [
                _Compteur(
                  cle: const Key('sync-modale-envoyees'),
                  libelle: TextesBoutonSynchronisation.envoyees,
                  valeur: n(const [StatutOperationSync.synchronise]),
                  couleur: AppColors.succes,
                ),
                const SizedBox(width: AppSpacing.xs),
                _Compteur(
                  cle: const Key('sync-modale-en-attente'),
                  libelle: TextesBoutonSynchronisation.enAttente,
                  valeur: n(const [
                    StatutOperationSync.enAttente,
                    StatutOperationSync.enCours,
                  ]),
                  couleur: PaletteMaitre.ambre600,
                ),
                const SizedBox(width: AppSpacing.xs),
                _Compteur(
                  cle: const Key('sync-modale-a-traiter'),
                  libelle: TextesBoutonSynchronisation.aTraiter,
                  valeur: n(const [
                    StatutOperationSync.rejete,
                    StatutOperationSync.conflit,
                    StatutOperationSync.bloque,
                  ]),
                  couleur: AppColors.erreur,
                ),
              ],
            ),
          const SizedBox(height: AppSpacing.sm),
          ligne(
            bilan == null
                ? TextesBoutonSynchronisation.aucunPassage
                : TextesBoutonSynchronisation.passage(bilan),
            cle: const Key('sync-modale-passage'),
          ),
          ligne(
            descente?.derniereDescente == null
                ? TextesBoutonSynchronisation.jamaisRecu
                : TextesBoutonSynchronisation.recu(descente!.derniereDescente!),
            cle: const Key('sync-modale-reception'),
          ),
          ligne(TextesBoutonSynchronisation.portee),
          if (enCours) ...[
            const LinearProgressIndicator(key: Key('sync-modale-progression')),
            const SizedBox(height: AppSpacing.xxs),
            ligne(TextesBoutonSynchronisation.enCours),
          ],
        ],
      ),
      actions: [
        BoutonStandard(
          key: const Key('sync-modale-fermer'),
          libelle: TextesBoutonSynchronisation.fermer,
          taillePolice: Tailles.t13,
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (detailAccessible)
          BoutonStandard(
            key: const Key('sync-modale-detail'),
            libelle: TextesBoutonSynchronisation.detail,
            taillePolice: Tailles.t13,
            onPressed: () {
              final routeur = GoRouter.of(context);
              Navigator.of(context).pop();
              routeur.go('/synchronisation');
            },
          ),
        BoutonStandard(
          key: const Key('sync-modale-maintenant'),
          variante: VarianteBouton.primaire,
          taillePolice: Tailles.t13,
          libelle: TextesBoutonSynchronisation.synchroniser,
          onPressed: interdite || appairage.value == null || enCours
              ? null
              : ref.read(synchroniserDepuisEcranProvider),
        ),
      ],
    );
  }
}

class _Compteur extends StatelessWidget {
  const _Compteur({
    required this.cle,
    required this.libelle,
    required this.valeur,
    required this.couleur,
  });

  final Key cle;
  final String libelle;
  final int valeur;
  final Color couleur;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.neutre200),
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$valeur',
            key: cle,
            style: TextStyle(
              color: couleur,
              fontFamily: AppTextStyles.police,
              fontSize: Tailles.t18,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(libelle, style: TextesModaleRestaurant.aide),
        ],
      ),
    ),
  );
}
