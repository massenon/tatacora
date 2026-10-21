// Vue Blade maîtresse (PA-183) : pwa/rh/conges-plannings.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared_widgets/bouton_standard.dart';
import '../../restaurant/presentation/widgets/coquille_restaurant.dart';
import '../../restaurant/presentation/widgets/tableau_restaurant.dart';
import '../domain/entities/conge_planning.dart';
import 'providers_conges_plannings.dart';
import 'widgets/modales_conges_plannings.dart';

/// **M13 Congés & Plannings** — les plannings d'équipe par jour et les demandes
/// de congé avec leur validation (EF-M13-02, EF-M13-04, RG-13, RG-14).
///
/// ## Un écran qui existe d'abord à la PWA (21/10/2026)
///
/// Décision du PO : « écrans PWA + poste + synchronisation ». Les services du
/// serveur existaient, aucune vue ne les portait ; la vue a été créée avec cet
/// écran, ses libellés vivent dans `lang/fr/rh_conges_pwa.php`, et le poste les
/// reprend au mot.
///
/// ## Ce que cet écran écrit, et comment
///
/// Uniquement par `CongesPlanningsDao`, qui rejoue RG-13 et RG-14 aux mots du
/// serveur et ENFILE chaque geste. Le serveur rejoue les mêmes règles avec ses
/// données : une décision refusée là-bas revient dans « À traiter ». Rien ne
/// se supprime : une erreur de planning se corrige par un nouveau créneau, un
/// congé refusé se conserve avec sa trace.
///
/// ## Écarts à la vue, nommés
///
/// - Le bandeau vert de succès (`session('pwa-succes')`) est un `SnackBar`.
/// - La colonne « Décidé par » rend « — » pour une demande descendue d'un autre
///   poste : le serveur ne livre pas le validateur.
class EcranCongesPlannings extends ConsumerWidget {
  const EcranCongesPlannings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onglet = ref.watch(ongletCongesPlanningsProvider);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        // `max-w-[1600px] mx-auto p-5 lg:p-8`.
        constraints: const BoxConstraints(
          maxWidth: AppLayout.pageCongesPlannings,
        ),
        child: ListView(
          padding: EdgeInsets.all(
            MediaQuery.sizeOf(context).width >= AppBreakpoints.lg
                ? AppSpacing.xl
                : AppSpacing.mdPlus,
          ),
          children: [
            const _EnTete(),
            // `mb-5` — 20 px.
            const SizedBox(height: AppSpacing.mdPlus),
            const _Indicateurs(),
            const SizedBox(height: AppSpacing.mdPlus),
            const _Onglets(),
            // `mb-4` — 16 px.
            const SizedBox(height: AppSpacing.md),
            switch (onglet) {
              OngletCongesPlannings.plannings => const _PanneauPlannings(),
              OngletCongesPlannings.conges => const _PanneauConges(),
            },
          ],
        ),
      ),
    );
  }
}

/// Un message de bilan (le bandeau vert de la vue).
void _dire(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, key: const Key('conges-plannings-toast')),
      ),
    );
}

/* ====================================================================== */
/* En-tête                                                                 */
/* ====================================================================== */

class _EnTete extends ConsumerWidget {
  const _EnTete();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onglet = ref.watch(ongletCongesPlanningsProvider);
    final peutEcrire = ref.watch(peutEcrireCongesPlanningsProvider);

    return EnTeteRestaurant(
      icone: const Icon(
        Icons.calendar_month_outlined,
        color: AppColors.navy,
        size: AppLayout.iconeTitrePage,
      ),
      titre: 'Congés & Plannings',
      // Un SEUL littéral : le comparateur cherche la phrase de la vue entière.
      sousTitre:
          "Plannings d'équipe par jour et demandes de congé avec leur validation.",
      actions: [
        if (peutEcrire)
          switch (onglet) {
            OngletCongesPlannings.plannings => BoutonStandard(
              key: const Key('conges-plannings-planifier'),
              variante: VarianteBouton.primaire,
              libelle: 'Planifier un créneau',
              onPressed: () async {
                final message = await ouvrirModalePlanning(context);
                if (message == null) return;
                rechargerCongesPlannings(ref);
                if (context.mounted) _dire(context, message);
              },
            ),
            OngletCongesPlannings.conges => BoutonStandard(
              key: const Key('conges-plannings-demander'),
              variante: VarianteBouton.primaire,
              libelle: 'Demander un congé',
              onPressed: () async {
                final message = await ouvrirModaleConge(context);
                if (message == null) return;
                rechargerCongesPlannings(ref);
                if (context.mounted) _dire(context, message);
              },
            ),
          },
      ],
    );
  }
}

/* ====================================================================== */
/* Indicateurs et onglets                                                  */
/* ====================================================================== */

class _Indicateurs extends ConsumerWidget {
  const _Indicateurs();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creneaux = ref.watch(creneauxProvider).value;
    final demandes = ref.watch(demandesCongeProvider).value;
    final enConge = ref.watch(enCongeAujourdhuiProvider).value;
    final jour = ref.watch(jourPlanningsProvider);
    final enAttente = demandes
        ?.where((d) => d.statut == StatutConge.enAttente)
        .length;

    // `grid grid-cols-2 lg:grid-cols-3 gap-3`.
    final colonnes = MediaQuery.sizeOf(context).width >= AppBreakpoints.lg
        ? 3
        : 2;
    final cartes = <Widget>[
      CarteIndicateurRestaurant(
        cle: const Key('conges-plannings-kpi-plannings'),
        libelle: 'Créneaux du jour',
        valeur: creneaux?.length.toString(),
        detail:
            '${jour.day.toString().padLeft(2, '0')}/'
            '${jour.month.toString().padLeft(2, '0')}/${jour.year}',
      ),
      CarteIndicateurRestaurant(
        cle: const Key('conges-plannings-kpi-en-attente'),
        libelle: 'Demandes en attente',
        valeur: enAttente?.toString(),
        // `text-amber-600` quand il y en a, `text-slate-400` sinon.
        accent: (enAttente ?? 0) > 0 ? PaletteMaitre.ambre600 : Ardoise.c400,
      ),
      CarteIndicateurRestaurant(
        cle: const Key('conges-plannings-kpi-en-conge'),
        libelle: "En congé aujourd'hui",
        valeur: enConge?.toString(),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var debut = 0; debut < cartes.length; debut += colonnes)
          Padding(
            padding: EdgeInsets.only(
              bottom: debut + colonnes < cartes.length ? AppSpacing.sm : 0,
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < colonnes; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: debut + i < cartes.length
                          ? cartes[debut + i]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Onglets extends ConsumerWidget {
  const _Onglets();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actif = ref.watch(ongletCongesPlanningsProvider);

    return Wrap(
      spacing: AppSpacing.xxs,
      runSpacing: AppSpacing.xxs,
      children: [
        for (final o in OngletCongesPlannings.values)
          OngletRestaurant(
            cle: Key('conges-plannings-onglet-${o.cle}'),
            libelle: o.libelle,
            actif: o == actif,
            onChoix: () =>
                ref.read(ongletCongesPlanningsProvider.notifier).definir(o),
          ),
      ],
    );
  }
}

/* ====================================================================== */
/* Plannings                                                               */
/* ====================================================================== */

/// `JJ/MM/AAAA` d'un `AAAA-MM-JJ` (`format('d/m/Y')` de la vue).
String _jour(String iso) {
  final p = iso.split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : iso;
}

class _PanneauPlannings extends ConsumerWidget {
  const _PanneauPlannings();

  static const _colonnes = [
    ColonneRestaurant('Employé'),
    ColonneRestaurant('Service', aDroite: true),
    ColonneRestaurant('Date', aDroite: true),
    ColonneRestaurant('Début', aDroite: true),
    ColonneRestaurant('Fin', aDroite: true),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creneaux = ref.watch(creneauxProvider).value ?? const [];
    final services = ref.watch(servicesRhProvider).value ?? const [];
    final jour = ref.watch(jourPlanningsProvider);
    final service = ref.watch(servicePlanningsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CarteFiltres(
          enfants: [
            Text(
              'Jour',
              style: TextesRestaurant.petitCrud.copyWith(color: Ardoise.c500),
            ),
            OutlinedButton(
              key: const Key('conges-plannings-filtre-jour'),
              onPressed: () async {
                final n = DateTime.now();
                final choisi = await showDatePicker(
                  context: context,
                  initialDate: jour,
                  firstDate: DateTime(n.year - 5),
                  lastDate: DateTime(n.year + 5),
                );
                if (choisi != null) {
                  ref.read(jourPlanningsProvider.notifier).definir(choisi);
                }
              },
              child: Text(
                _jour(
                  '${jour.year.toString().padLeft(4, '0')}-'
                  '${jour.month.toString().padLeft(2, '0')}-'
                  '${jour.day.toString().padLeft(2, '0')}',
                ),
                style: TextesRestaurant.petitCrud,
              ),
            ),
            SizedBox(
              width: AppLayout.filtreServiceCongesPlannings,
              child: DropdownButtonFormField<String?>(
                key: const Key('conges-plannings-filtre-service'),
                initialValue: services.any((s) => s.id == service)
                    ? service
                    : null,
                isExpanded: true,
                style: TextesRestaurant.petitCrud,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    child: Text('Tous les services'),
                  ),
                  for (final s in services)
                    DropdownMenuItem<String?>(
                      value: s.id,
                      child: Text(s.libelle),
                    ),
                ],
                onChanged: (v) =>
                    ref.read(servicePlanningsProvider.notifier).definir(v),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        CadreTableauRestaurant(
          corps: TableauRestaurant(
            gabarit: GabaritTableau.carte,
            colonnes: _colonnes,
            clesLignes: [
              for (final c in creneaux) Key('conges-plannings-creneau-${c.id}'),
            ],
            lignes: [
              for (final c in creneaux)
                [
                  Text(c.employeNom, style: TextesRestaurant.corpsFort),
                  Text(c.serviceLibelle, style: TextesRestaurant.secondaire),
                  Text(_jour(c.date), style: TextesRestaurant.secondaire),
                  Text(c.heureDebut, style: TextesRestaurant.secondaire),
                  Text(c.heureFin, style: TextesRestaurant.secondaire),
                ],
            ],
            videSousEntete: true,
            vide: const EtatVideCongesPlannings(
              cle: Key('conges-plannings-planning-vide'),
              message: 'Aucun créneau planifié ce jour.',
            ),
          ),
        ),
      ],
    );
  }
}

/* ====================================================================== */
/* Congés                                                                  */
/* ====================================================================== */

class _PanneauConges extends ConsumerWidget {
  const _PanneauConges();

  static const _colonnes = [
    ColonneRestaurant('Employé'),
    ColonneRestaurant('Nature', aDroite: true),
    ColonneRestaurant('Du', aDroite: true),
    ColonneRestaurant('Au', aDroite: true),
    ColonneRestaurant('Jours', aDroite: true),
    ColonneRestaurant('Statut', aDroite: true),
    ColonneRestaurant('Décidé par', aDroite: true),
    ColonneRestaurant('', aDroite: true),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final demandes = ref.watch(demandesCongeProvider).value ?? const [];
    final statut = ref.watch(statutCongesProvider);
    final refus = ref.watch(refusCongeProvider);
    final peutEcrire = ref.watch(peutEcrireCongesPlanningsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CarteFiltres(
          enfants: [
            SizedBox(
              width: AppLayout.filtreStatutCongesPlannings,
              child: DropdownButtonFormField<StatutConge?>(
                key: const Key('conges-plannings-filtre-statut'),
                initialValue: statut,
                isExpanded: true,
                style: TextesRestaurant.petitCrud,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<StatutConge?>(
                    child: Text('Tous les statuts'),
                  ),
                  for (final s in StatutConge.values)
                    DropdownMenuItem<StatutConge?>(
                      value: s,
                      child: Text(s.libelle),
                    ),
                ],
                onChanged: (v) =>
                    ref.read(statutCongesProvider.notifier).definir(v),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        CadreTableauRestaurant(
          corps: TableauRestaurant(
            gabarit: GabaritTableau.carte,
            colonnes: _colonnes,
            clesLignes: [
              for (final d in demandes) Key('conges-plannings-conge-${d.id}'),
            ],
            lignes: [
              for (final d in demandes)
                [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(d.employeNom, style: TextesRestaurant.corpsFort),
                      if (refus[d.id] case final message?)
                        Text(
                          message,
                          key: Key('conges-plannings-refus-${d.id}'),
                          style: TextesRestaurant.mention.copyWith(
                            color: PaletteMaitre.rouge700,
                          ),
                        ),
                    ],
                  ),
                  Text(d.type.libelle, style: TextesRestaurant.secondaire),
                  Text(_jour(d.dateDebut), style: TextesRestaurant.secondaire),
                  Text(_jour(d.dateFin), style: TextesRestaurant.secondaire),
                  Text('${d.jours}', style: TextesRestaurant.secondaire),
                  _PastilleStatut(statut: d.statut, id: d.id),
                  Text(d.validateur ?? '—', style: TextesRestaurant.mention),
                  if (peutEcrire && d.statut == StatutConge.enAttente)
                    _ActionsDemande(congeId: d.id)
                  else
                    const SizedBox.shrink(),
                ],
            ],
            videSousEntete: true,
            vide: const EtatVideCongesPlannings(
              cle: Key('conges-plannings-conge-vide'),
              message: 'Aucune demande de congé.',
            ),
          ),
        ),
      ],
    );
  }
}

class _PastilleStatut extends StatelessWidget {
  const _PastilleStatut({required this.statut, required this.id});

  final StatutConge statut;
  final String id;

  @override
  Widget build(BuildContext context) {
    final (fond, couleur) = switch (statut) {
      StatutConge.valide => (
        PaletteMaitre.emeraude50,
        PaletteMaitre.emeraude700,
      ),
      StatutConge.refuse => (PaletteMaitre.rouge50, PaletteMaitre.rouge700),
      StatutConge.enAttente => (PaletteMaitre.ambre50, PaletteMaitre.ambre700),
    };

    return PastilleRestaurant(
      cle: Key('conges-plannings-statut-$id'),
      texte: statut.libelle,
      fond: fond,
      couleur: couleur,
      compacte: true,
    );
  }
}

/// « Valider » et « Refuser » d'une demande en attente.
class _ActionsDemande extends ConsumerWidget {
  const _ActionsDemande({required this.congeId});

  final String congeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: AppSpacing.xxs,
      children: [
        BoutonStandard(
          key: Key('conges-plannings-valider-$congeId'),
          libelle: 'Valider',
          compact: true,
          onPressed: () => _decider(context, ref, valider: true),
        ),
        BoutonStandard(
          key: Key('conges-plannings-refuser-$congeId'),
          libelle: 'Refuser',
          compact: true,
          onPressed: () => _decider(context, ref, valider: false),
        ),
      ],
    );
  }

  Future<void> _decider(
    BuildContext context,
    WidgetRef ref, {
    required bool valider,
  }) async {
    final dao = ref.read(congesPlanningsDaoProvider);
    final refus = ref.read(refusCongeProvider.notifier);
    final login = ref.read(sessionProvider)?.login;

    try {
      if (valider) {
        await dao.valider(congeId, validateur: login);
      } else {
        await dao.refuser(congeId, validateur: login);
      }
    } on RefusCongesPlannings catch (r) {
      // RG-14 : préavis, couverture, paramètre absent — dits tels quels, SOUS
      // la ligne de la demande.
      refus.poser(congeId, r.message);
      return;
    }
    refus.effacer(congeId);
    rechargerCongesPlannings(ref);
    if (context.mounted) {
      _dire(
        context,
        valider ? 'Congé validé.' : 'Congé refusé : la demande est conservée.',
      );
    }
  }
}

/* ====================================================================== */
/* Éléments communs                                                        */
/* ====================================================================== */

/// La carte blanche des filtres — `bg-white rounded-xl border border-slate-200
/// p-3.5`, contrôles en `flex flex-wrap gap-2.5 items-center`.
class _CarteFiltres extends StatelessWidget {
  const _CarteFiltres({required this.enfants});

  final List<Widget> enfants;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.smPlus),
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: Ardoise.c200),
      ),
      child: Wrap(
        spacing: AppSpacing.xsPlus,
        runSpacing: AppSpacing.xsPlus,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: enfants,
      ),
    );
  }
}

/// L'état vide logé dans le tableau (`py-14 text-center text-slate-400`).
class EtatVideCongesPlannings extends StatelessWidget {
  const EtatVideCongesPlannings({Key? cle, required this.message})
    : super(key: cle);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacingLarge.p14),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextesRestaurant.corps.copyWith(color: Ardoise.c400),
        ),
      ),
    );
  }
}
