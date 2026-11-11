// Vue Blade maîtresse (PA-183) : pwa/transverse/alertes-ouverture-modales.blade.php
// Son partiel `bloc-alerte-ouverture` rend chaque bloc ; la coquille monte le
// tout (jamais une page).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/navigation/acces_rapide.dart'
    show routesFlutterParRoutePwa;
import '../../../core/navigation/trace_svg.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/mesures_modales_ouverture.dart';
import '../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../domain/modales_ouverture.dart';
import 'providers_modales_ouverture.dart';

/// Les DEUX modales d'ouverture de session, ENCHAÎNÉES : « Stock critique » puis
/// « Opérations du jour » (`AlertesOuvertureModales`). Fermer une modale —
/// bouton, Échap ou voile — c'est avancer (`fermer="avancer"` du châssis) ;
/// la dernière fermée, la séquence est finie.
///
/// ## Une fois par CONNEXION, jamais par page
///
/// Elle est lancée par [HoteModalesOuverture] quand le drapeau de connexion
/// (`ouvertureEnAttenteProvider`, posé par `SessionNotifier.connecter` comme
/// `Connexion::seConnecter()` pose le drapeau de session) est présent, puis
/// consommé — même quand il n'y a rien à montrer. Une session restaurée au
/// démarrage n'en déclenche pas.
class HoteModalesOuverture extends ConsumerStatefulWidget {
  const HoteModalesOuverture({super.key});

  @override
  ConsumerState<HoteModalesOuverture> createState() => _EtatHote();
}

class _EtatHote extends ConsumerState<HoteModalesOuverture> {
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    // Un drapeau déjà posé quand la coquille se monte (la connexion précède la
    // première image de la coquille).
    WidgetsBinding.instance.addPostFrameCallback((_) => _verifier());
  }

  Future<void> _verifier() async {
    if (!mounted || _enCours) return;
    if (!ref.read(ouvertureEnAttenteProvider)) return;
    if (ref.read(sessionProvider) == null) return;
    _enCours = true;
    // Consommé tout de suite, même s'il n'y a rien à montrer : on ne recalcule
    // pas à chaque page.
    ref.read(ouvertureEnAttenteProvider.notifier).consommer();
    try {
      ref.invalidate(etapesOuvertureProvider);
      final etapes = await ref.read(etapesOuvertureProvider.future);
      if (!mounted || etapes.isEmpty) return;
      ref.read(modalesOuvertureProvider.notifier).remettreAZero();
      for (var i = 0; i < etapes.length; i++) {
        if (!mounted) return;
        final destination = await showDialog<String>(
          context: context,
          barrierColor: AppColors.voileModale,
          builder: (_) => ModaleEtapeOuverture(
            etape: etapes[i],
            rang: i + 1,
            total: etapes.length,
          ),
        );
        // Un lien de pied quitte la séquence pour l'écran du module.
        if (destination != null && mounted) {
          GoRouter.of(context).go(destination);
          return;
        }
      }
    } finally {
      _enCours = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(ouvertureEnAttenteProvider, (avant, apres) {
      if (apres) _verifier();
    });
    return const SizedBox.shrink();
  }
}

/// Une modale de la séquence (étape [rang] sur [total]). Publique pour que les
/// essais la montent avec des lignes fabriquées (plus de dix lignes, par exemple).
class ModaleEtapeOuverture extends ConsumerWidget {
  const ModaleEtapeOuverture({
    super.key,
    required this.etape,
    required this.rang,
    required this.total,
  });

  final EtapeOuverture etape;
  final int rang;
  final int total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etat = ref.watch(modalesOuvertureProvider);
    final notifieur = ref.read(modalesOuvertureProvider.notifier);
    final stock = etape is EtapeStock;
    final compteur = total > 1 ? ' — $rang / $total' : '';

    String? route(String routePwa) => routesFlutterParRoutePwa[routePwa];

    final corps = <Widget>[
      if (etat.erreur != null)
        Container(
          key: const Key('ouverture-erreur'),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.smPlus, // px-3.5
            vertical: AppSpacing.xsPlus, // py-2.5
          ),
          decoration: BoxDecoration(
            color: AppColors.badgeRougeFond,
            borderRadius: BorderRadius.circular(AppRadius.roundedLg),
          ),
          child: Text(
            etat.erreur!,
            style: const TextStyle(
              fontFamily: AppTextStyles.police,
              fontSize: Tailles.t13,
              color: AppColors.annulationTexteRouge,
            ),
          ),
        ),
      if (etape case EtapeStock(:final lignes))
        _Bloc(
          cle: 'stock',
          titre: TextesOuverture.blocStockTitre,
          sousTitre: TextesOuverture.blocStockSousTitre,
          couleur: MesuresModalesOuverture.couleurStock,
          trace: MesuresModalesOuverture.traceStock,
          libelleLien: TextesOuverture.lienStocks,
          surLien: () =>
              Navigator.of(context).pop(route('pwa.stocks.liste') ?? '/stocks'),
          lignes: [
            for (final l in lignes)
              _Ligne(
                cle: 'stock:${l.articleId}',
                libelle: l.libelle,
                detail: l.detail,
                critique: l.critique,
              ),
          ],
        ),
      if (etape case EtapeOperations(:final departs, :final creances)) ...[
        if (departs.isNotEmpty)
          _Bloc(
            cle: 'departs',
            titre: TextesOuverture.blocDepartsTitre,
            sousTitre: TextesOuverture.blocDepartsSousTitre,
            couleur: MesuresModalesOuverture.couleurDeparts,
            trace: MesuresModalesOuverture.traceDeparts,
            libelleLien: TextesOuverture.lienReservations,
            surLien: () => Navigator.of(
              context,
            ).pop(route('pwa.reservations') ?? '/hebergement/reservations'),
            lignes: [
              for (final l in departs)
                _Ligne(
                  cle: 'sejour:${l.sejourId}',
                  libelle: l.libelle,
                  detail: l.detail,
                  critique: l.critique,
                  traitee: etat.traites.contains('sejour:${l.sejourId}'),
                  action: etat.traites.contains('sejour:${l.sejourId}')
                      ? const _Etiquette(
                          cle: 'fait',
                          texte: TextesOuverture.fait,
                        )
                      : _BoutonAction(
                          cle: 'checkout:${l.sejourId}',
                          texte: TextesOuverture.checkout,
                          couleur: MesuresModalesOuverture.couleurDeparts,
                          surAppui: () => notifieur.effectuerCheckOut(l),
                        ),
                ),
            ],
          ),
        if (creances.isNotEmpty)
          _Bloc(
            cle: 'creances',
            titre: TextesOuverture.blocCreancesTitre,
            sousTitre: TextesOuverture.blocCreancesSousTitre,
            couleur: MesuresModalesOuverture.couleurCreances,
            trace: MesuresModalesOuverture.traceCreances,
            libelleLien: TextesOuverture.lienCreances,
            surLien: () =>
                Navigator.of(context).pop(route('pwa.clients') ?? '/crm'),
            lignes: [
              for (final l in creances)
                _Ligne(
                  cle: 'client:${l.clientId}:${l.libelle}',
                  libelle: l.libelle,
                  detail: l.detail,
                  critique: l.critique,
                  traitee: etat.traites.contains(l.cleTraitee),
                  action: etat.traites.contains(l.cleTraitee)
                      ? const _Etiquette(
                          cle: 'tracee',
                          texte: TextesOuverture.tracee,
                        )
                      : l.relanceRequise
                      ? _ActionRelance(
                          ligne: l,
                          canal: etat.canalRelance,
                          surCanal: notifieur.choisirCanal,
                          surAppui: () => notifieur.tracerRelance(l),
                        )
                      : const _Etiquette(
                          cle: 'recente',
                          texte: TextesOuverture.relanceRecente,
                        ),
                ),
            ],
          ),
      ],
    ];

    return CoquilleModaleRestaurant(
      cle: Key('ouverture-modale-$rang'),
      titre: stock
          ? TextesOuverture.titreStock
          : TextesOuverture.titreOperations,
      sousTitre:
          (stock
              ? TextesOuverture.sousTitreStock
              : TextesOuverture.sousTitreOperations) +
          compteur,
      largeur: MesuresModalesOuverture.largeurModale,
      corps: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, c) in corps.indexed) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            c,
          ],
        ],
      ),
      actions: [
        FilledButton(
          key: const Key('ouverture-avancer'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.navy,
            foregroundColor: AppColors.neutre0,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.mdPlus, // px-5
              vertical: AppSpacing.xsPlus, // py-2.5
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            ),
            textStyle: const TextStyle(
              fontFamily: AppTextStyles.police,
              fontSize: Tailles.t14,
              fontWeight: FontWeight.w600,
            ),
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            rang < total
                ? TextesOuverture.suivant
                : TextesOuverture.prisConnaissance,
          ),
        ),
      ],
    );
  }
}

/// Un bloc : bandeau teinté (couleur à 7 %), compteur rond, dix lignes au plus
/// puis « … et N autre(s) », lien de pied.
class _Bloc extends StatelessWidget {
  const _Bloc({
    required this.cle,
    required this.titre,
    required this.sousTitre,
    required this.couleur,
    required this.trace,
    required this.libelleLien,
    required this.surLien,
    required this.lignes,
  });

  final String cle;
  final String titre;
  final String sousTitre;
  final Color couleur;
  final String trace;
  final String libelleLien;
  final VoidCallback surLien;
  final List<_Ligne> lignes;

  @override
  Widget build(BuildContext context) {
    final visibles = lignes.take(lignesParBloc).toList();
    return Container(
      key: Key('ouverture-bloc-$cle'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: Ardoise.c200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: couleur.withValues(
              alpha: MesuresModalesOuverture.alphaBandeau,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, // px-4
              vertical: AppSpacing.sm, // py-3
            ),
            child: Row(
              children: [
                IconeTrace(
                  trace: trace,
                  taille: MesuresModalesOuverture.icone,
                  couleur: couleur,
                  epaisseur: MesuresModalesOuverture.epaisseurIcone,
                ),
                const SizedBox(width: AppSpacing.xsPlus), // gap-2.5
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titre,
                        style: TextStyle(
                          fontFamily: AppTextStyles.police,
                          fontSize: Tailles.t14,
                          fontWeight: FontWeight.bold,
                          color: couleur,
                        ),
                      ),
                      Text(
                        sousTitre,
                        style: const TextStyle(
                          fontFamily: AppTextStyles.police,
                          fontSize: Tailles.t11,
                          color: Ardoise.c500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  key: Key('ouverture-compteur-$cle'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xsPlus, // px-2.5
                    vertical: AppSpacing.unit, // py-1
                  ),
                  decoration: BoxDecoration(
                    color: couleur,
                    borderRadius: BorderRadius.circular(AppRadius.roundedFull),
                  ),
                  child: Text(
                    '${lignes.length}',
                    style: const TextStyle(
                      fontFamily: AppTextStyles.police,
                      fontSize: Tailles.t12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.neutre0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: MesuresModalesOuverture.hauteurMaxBloc,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final l in visibles) l.construire(couleur),
                  if (lignes.length > lignesParBloc)
                    Padding(
                      key: Key('ouverture-et-autres-$cle'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs, // py-2
                      ),
                      child: Text(
                        TextesOuverture.etAutres(lignes.length - lignesParBloc),
                        style: const TextStyle(
                          fontFamily: AppTextStyles.police,
                          fontSize: Tailles.t11,
                          color: Ardoise.c400,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          InkWell(
            key: Key('ouverture-lien-$cle'),
            onTap: surLien,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xsPlus, // py-2.5
              ),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Ardoise.c100)),
              ),
              child: Text(
                '$libelleLien →',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTextStyles.police,
                  fontSize: Tailles.t12,
                  fontWeight: FontWeight.bold,
                  color: couleur,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Une ligne : pastille (rouge si critique), libellé, détail, action inline.
class _Ligne {
  const _Ligne({
    required this.cle,
    required this.libelle,
    required this.detail,
    required this.critique,
    this.traitee = false,
    this.action,
  });

  final String cle;
  final String libelle;
  final String detail;
  final bool critique;
  final bool traitee;
  final Widget? action;

  Widget construire(Color couleur) => Opacity(
    key: Key('ouverture-ligne-$cle'),
    // `opacity-45` d'une ligne traitée.
    opacity: traitee ? MesuresModalesOuverture.opaciteLigneTraitee : 1,
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xsPlus,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Ardoise.c100)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs), // mt-1.5
            child: Container(
              key: Key('ouverture-pastille-$cle'),
              width: MesuresModalesOuverture.pastille,
              height: MesuresModalesOuverture.pastille,
              decoration: BoxDecoration(
                color: critique ? AppColors.erreur : couleur,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs), // gap-2
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  libelle,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.police,
                    fontSize: Tailles.t12,
                    fontWeight: FontWeight.w600,
                    color: Ardoise.c700,
                  ),
                ),
                Text(
                  detail,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.police,
                    fontSize: Tailles.t11,
                    color: Ardoise.c500,
                  ),
                ),
              ],
            ),
          ),
          ?action,
        ],
      ),
    ),
  );
}

class _Etiquette extends StatelessWidget {
  const _Etiquette({required this.cle, required this.texte});
  final String cle;
  final String texte;

  @override
  Widget build(BuildContext context) => Text(
    texte,
    key: Key('ouverture-etiquette-$cle'),
    style: const TextStyle(
      fontFamily: AppTextStyles.police,
      fontSize: Tailles.t10,
      fontWeight: FontWeight.w600,
      color: Ardoise.c400,
    ),
  );
}

class _BoutonAction extends StatelessWidget {
  const _BoutonAction({
    required this.cle,
    required this.texte,
    required this.couleur,
    required this.surAppui,
  });

  final String cle;
  final String texte;
  final Color couleur;
  final VoidCallback surAppui;

  @override
  Widget build(BuildContext context) => Material(
    color: couleur,
    borderRadius: BorderRadius.circular(AppRadius.rounded),
    child: InkWell(
      key: Key('ouverture-action-$cle'),
      borderRadius: BorderRadius.circular(AppRadius.rounded),
      onTap: surAppui,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xsPlus, // px-2.5
          vertical: AppSpacing.unit, // py-1
        ),
        child: Text(
          texte,
          style: const TextStyle(
            fontFamily: AppTextStyles.police,
            fontSize: Tailles.t10,
            fontWeight: FontWeight.bold,
            color: AppColors.neutre0,
          ),
        ),
      ),
    ),
  );
}

/// Le canal au choix puis « Relancer » (`select` + bouton de la vue).
class _ActionRelance extends StatelessWidget {
  const _ActionRelance({
    required this.ligne,
    required this.canal,
    required this.surCanal,
    required this.surAppui,
  });

  final LigneCreanceOuverture ligne;
  final String canal;
  final ValueChanged<String> surCanal;
  final VoidCallback surAppui;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.unit,
          vertical: AppSpacing.demi,
        ),
        decoration: BoxDecoration(
          color: AppColors.neutre0,
          borderRadius: BorderRadius.circular(AppRadius.rounded),
          border: Border.all(color: Ardoise.c200),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: Key('ouverture-canal-${ligne.clientId}'),
            value: canal,
            isDense: true,
            style: const TextStyle(
              fontFamily: AppTextStyles.police,
              fontSize: Tailles.t10,
              color: Ardoise.c700,
            ),
            items: [
              for (final (code, libelle) in canauxRelanceOuverture)
                DropdownMenuItem(value: code, child: Text(libelle)),
            ],
            onChanged: (v) {
              if (v != null) surCanal(v);
            },
          ),
        ),
      ),
      const SizedBox(width: AppSpacing.unit),
      _BoutonAction(
        cle: 'relancer:${ligne.clientId}',
        texte: TextesOuverture.relancer,
        couleur: MesuresModalesOuverture.couleurCreances,
        surAppui: surAppui,
      ),
    ],
  );
}
