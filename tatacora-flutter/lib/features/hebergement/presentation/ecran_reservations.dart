// Vue Blade maîtresse (PA-183) : pwa/hebergement/reservations.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/format/formats.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared_widgets/liste_paginee.dart';
import '../../crm/presentation/providers_crm.dart';
import '../../crm/presentation/widgets/modale_nouveau_client.dart';
import '../../caisse/domain/montant_caisse.dart' show formaterCentimesEnFcfa;
import '../domain/entities/annulation_enregistree.dart';
import '../domain/entities/carte_reservation.dart';
import '../domain/entities/fiche_reservation.dart';
import '../domain/entities/reservation.dart';
import 'fiche_reservation.dart';
import 'panneau_historique.dart';
import 'providers_hebergement.dart';
import 'widgets/carte_reservation.dart';
import 'widgets/modale_annulation_reservation.dart';

/// Écran **Réservations** — la vue `hebergement/reservations`.
///
/// ## La page de la vue, dans l'ordre de la vue (Phase 2, 08/10/2026)
///
/// En-tête (titre, sous-titre, « Historique », « Ajouter client », « Nouvelle
/// réservation »), barre à deux onglets « Réservations » / « Annulations »,
/// recherche, grille de cartes, puis l'état vide dans une carte. La page
/// défile d'un bloc, comme `<main>` de la vue (`p-5 lg:p-8`, `max-w-[1440px]`).
///
/// ## Chaque ligne porte son statut de synchronisation
///
/// Un réceptionniste qui ignore qu'une saisie n'est pas partie la ressaisira,
/// et le doublon apparaîtra au moment de facturer.
///
/// ## Une réservation refusée reste, avec son motif
///
/// Elle n'est jamais retirée de la liste : le message du serveur est affiché
/// tel quel, c'est lui qui dit quoi faire.
///
/// ## L'onglet Annulations
///
/// Il liste les réservations annulées du poste. Les colonnes de la vue qui
/// supposent le calcul d'annulation du serveur (total, taux, commission
/// retenue, remboursé, auteur) n'ont pas de source ici : le poste ne stocke que
/// le motif. Elles rendent « — », jamais « 0 » (PA-126).
class EcranReservations extends ConsumerStatefulWidget {
  const EcranReservations({super.key, this.seulementEnSuspens = false});

  /// Le mode « Opérations en attente » du sprint : ce qui n'est pas parti.
  final bool seulementEnSuspens;

  @override
  ConsumerState<EcranReservations> createState() => _EtatEcranReservations();
}

class _EtatEcranReservations extends ConsumerState<EcranReservations> {
  bool _annulations = false;

  @override
  Widget build(BuildContext context) {
    // Le maître ne connaît pas le hors-ligne : « Opérations en attente » est un
    // autre écran du sprint, qui répond à « qu'est-ce qui n'est pas parti ? ».
    if (widget.seulementEnSuspens) return const _PanneauSansSynchronisation();

    final peutAnnuler = ref
        .watch(droitsProvider)
        .peutEcrire(ModuleTatacora.m1Hebergement);

    return RefreshIndicator(
      // Relit la base locale, et rien d'autre : il n'y a plus de serveur avec
      // qui se remettre d'accord.
      onRefresh: () async => rafraichirListes(ref),
      child: SingleChildScrollView(
        // Sans cela, une page plus courte que l'écran ne défile pas, et le
        // geste « tirer pour rafraîchir » ne part jamais.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.xl), // lg:p-8
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppLayout.maxContentWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _EnTetePage(peutEcrire: peutAnnuler),
                _BarreOnglets(
                  annulations: _annulations,
                  onChoisir: (annulations) {
                    // Les deux recherches de la vue sont distinctes : on ne
                    // laisse pas un terme de l'une filtrer l'autre.
                    ref.read(rechercheReservationProvider.notifier).definir('');
                    setState(() => _annulations = annulations);
                  },
                ),
                if (_annulations)
                  const _OngletAnnulations()
                else ...[
                  const _ChampRecherche(),
                  _Grille(peutAnnuler: peutAnnuler),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

TextStyle _t(
  double taille, {
  FontWeight? poids,
  Color? couleur,
  double? espacement,
}) => TextStyle(
  fontFamily: AppTextStyles.police,
  fontSize: taille,
  fontWeight: poids,
  color: couleur,
  height: 1.5,
  letterSpacing: espacement,
);

/// Le geste « Annuler » d'une carte : la modale du serveur (taux, commission,
/// remboursement), pas un simple motif — voir
/// [ouvrirModaleAnnulationReservation].
Future<void> _annuler(
  BuildContext context,
  WidgetRef ref,
  Reservation reservation,
) async {
  await ouvrirModaleAnnulationReservation(context, ref, reservation);
}

/// L'en-tête de la vue (`flex flex-col sm:flex-row sm:items-center
/// sm:justify-between gap-4 mb-5`) : titre, sous-titre, trois boutons.
///
/// ## Le sous-titre n'est pas décoratif
///
/// *« Une réservation peut combiner Hébergement, Restauration, Bar, Tourisme
/// et/ou Location de véhicule sur une même fiche client. »* C'est la phrase qui
/// dit ce qu'est une réservation ici, et le client a passé un mois à ne pas la
/// tenir : son sous-total valait `tarif × nuits` (PA-110).
///
/// ## Les trois boutons de la vue
///
/// « Ajouter client » ouvre la modale du registre des clients (M3) et écrit
/// par le même chemin que l'écran Clients — il n'était pas rendu tant que cette
/// modale n'existait pas ; il l'est maintenant, branché. « Historique » et
/// « Nouvelle réservation » sont branchés depuis toujours.
class _EnTetePage extends ConsumerWidget {
  const _EnTetePage({required this.peutEcrire});

  final bool peutEcrire;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final titre = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              size: AppLayout.iconeTitrePage,
              color: AppColors.navy,
            ),
            const SizedBox(width: AppSpacing.xsPlus), // gap-2.5
            Text(
              'Réservations',
              style: _t(
                TaillesContenu.lg,
                poids: FontWeight.bold,
                couleur: AppColors.navy,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs), // mt-1.5
        Text(
          'Une réservation peut combiner Hébergement, Restauration, Bar, '
          'Tourisme et/ou Location de véhicule sur une même fiche client.',
          style: _t(TaillesContenu.t15, couleur: AppColors.neutre500),
        ),
      ],
    );
    final boutons = Wrap(
      spacing: AppSpacing.sm, // gap-3
      runSpacing: AppSpacing.sm,
      children: [
        _BoutonEntete(
          cle: const Key('bouton-historique'),
          icone: Icons.history,
          libelle: 'Historique',
          onTap: () => ouvrirHistoriqueReservations(context),
        ),
        if (peutEcrire)
          _BoutonEntete(
            cle: const Key('bouton-ajouter-client'),
            icone: Icons.person_add_alt_outlined,
            libelle: 'Ajouter client',
            contour: AppColors.navy,
            onTap: () => _ajouterClient(context, ref),
          ),
        if (peutEcrire)
          _BoutonEntete(
            cle: const Key('bouton-nouvelle-reservation'),
            icone: Icons.add,
            libelle: 'Nouvelle réservation',
            plein: true,
            onTap: () => ouvrirFicheReservation(context),
          ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.mdPlus), // mb-5
      child: LayoutBuilder(
        builder: (context, contraintes) {
          // `flex-col sm:flex-row sm:items-center sm:justify-between gap-4` :
          // en rangée, le bloc de titre rétrécit et son sous-titre passe à la
          // ligne ; les boutons (`shrink-0`) gardent leur largeur.
          if (contraintes.maxWidth < AppLayout.enTeteReservationsEnRangee) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titre,
                const SizedBox(height: AppSpacing.md),
                boutons,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(child: titre),
              const SizedBox(width: AppSpacing.md),
              boutons,
            ],
          );
        },
      ),
    );
  }

  /// Même geste que « + Nouveau client » de l'écran Clients : le DAO écrit le
  /// client ET son entrée de file dans la même transaction (PA-116).
  Future<void> _ajouterClient(BuildContext context, WidgetRef ref) async {
    final saisie = await demanderClientRegistre(context);
    if (saisie == null) return;

    await ref
        .read(clientDaoProvider)
        .creer(nom: saisie.nom, telephone: saisie.telephone, type: saisie.type);
    ref
      ..invalidate(registreClientsProvider)
      ..invalidate(clientsProvider);
  }
}

class _BoutonEntete extends StatelessWidget {
  const _BoutonEntete({
    required Key cle,
    required this.icone,
    required this.libelle,
    required this.onTap,
    this.plein = false,
    this.contour,
  }) : super(key: cle);

  final IconData icone;
  final String libelle;
  final VoidCallback onTap;
  final bool plein;
  final Color? contour;

  @override
  Widget build(BuildContext context) {
    final texte = plein ? AppColors.neutre0 : (contour ?? AppColors.neutre700);
    return Material(
      color: plein ? AppColors.navy : AppColors.neutre0,
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, // px-4
            vertical: AppSpacing.xsPlus, // py-2.5
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            border: plein
                ? null
                : Border.all(color: contour ?? AppColors.neutre300),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icone, size: AppLayout.iconeChamp, color: texte),
              const SizedBox(width: AppSpacing.xs), // gap-2
              Text(
                libelle,
                style: _t(
                  TaillesContenu.t15,
                  poids: FontWeight.w600,
                  couleur: texte,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La barre d'onglets (`flex flex-wrap items-center gap-1.5 mb-4`), classes de
/// `Onglets::classes()` : `px-3.5 py-2 rounded-lg text-[13px] font-semibold`.
class _BarreOnglets extends StatelessWidget {
  const _BarreOnglets({required this.annulations, required this.onChoisir});

  final bool annulations;
  final ValueChanged<bool> onChoisir;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md), // mb-4
      child: Wrap(
        spacing: AppSpacing.xxs, // gap-1.5
        runSpacing: AppSpacing.xxs,
        children: [
          for (final (estAnnulations, libelle) in const [
            (false, 'Réservations'),
            (true, 'Annulations'),
          ])
            Material(
              key: Key(
                estAnnulations
                    ? 'reservations-onglet-annulations'
                    : 'reservations-onglet-actives',
              ),
              color: estAnnulations == annulations
                  ? AppColors.navy
                  : AppColors.neutre0,
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
              child: InkWell(
                onTap: () => onChoisir(estAnnulations),
                borderRadius: BorderRadius.circular(AppRadius.roundedLg),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.smPlus, // px-3.5
                    vertical: AppSpacing.xs, // py-2
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.roundedLg),
                    // Le contour existe aussi sur l'onglet actif (marine sur
                    // marine) : sans lui le bouton est 2 px plus court.
                    border: Border.all(
                      color: estAnnulations == annulations
                          ? AppColors.navy
                          : AppColors.neutre200,
                    ),
                  ),
                  child: Text(
                    libelle,
                    style: _t(
                      TaillesContenu.t13,
                      poids: FontWeight.w600,
                      couleur: estAnnulations == annulations
                          ? AppColors.neutre0
                          : AppColors.neutre500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// La grille de cartes — `#grille-reservations`, une colonne, deux au-delà du
/// seuil `lg` de la vue — puis l'état vide dans sa carte.
class _Grille extends ConsumerWidget {
  const _Grille({required this.peutAnnuler});

  final bool peutAnnuler;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartes = ref.watch(cartesReservationProvider);

    return cartes.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text('$e', textAlign: TextAlign.center),
        ),
      ),
      data: (toutes) {
        // L'onglet « Réservations » n'a que les réservations actives : les
        // annulées vivent dans l'onglet « Annulations ».
        final liste = [
          for (final c in toutes)
            if (c.reservation.estActive) c,
        ];
        if (liste.isEmpty) return const _CarteVide(cle: Key('grille-vide'));

        // Dix réservations par page (PO, 14/10/2026) ; les exports lisent
        // le provider, la liste ENTIÈRE.
        return ListePaginee<CarteReservation>(
          elements: liste,
          prefixeCle: 'reservations-pagination',
          cleRemiseAZero: ref.watch(rechercheReservationProvider),
          constructeur: (_, page) => LayoutBuilder(
            builder: (context, contraintes) {
              // `lg:grid-cols-2` : deux colonnes au-delà de 1024 px.
              final colonnes = contraintes.maxWidth >= 1024 ? 2 : 1;
              final largeur =
                  (contraintes.maxWidth - AppSpacing.md * (colonnes - 1)) /
                  colonnes;

              // ⚠ Un `Wrap`, et NON un `GridView` à hauteur fixe : la carte la
              // plus fournie déborderait de 22 px et cacherait le reste dû et le
              // bouton d'annulation. Les lignes de grille CSS de la vue ont une
              // hauteur libre ; c'est ce que fait un `Wrap`.
              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  for (final carte in page)
                    SizedBox(
                      width: largeur,
                      child: VueCarteReservation(
                        carte: carte,
                        peutAnnuler: peutAnnuler,
                        onAnnuler: () =>
                            _annuler(context, ref, carte.reservation),
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// `bg-white rounded-xl border border-slate-200 py-16 text-center
/// text-slate-400 text-sm` : l'état vide de la vue.
class _CarteVide extends StatelessWidget {
  const _CarteVide({required this.cle, this.message});

  final Key cle;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: AppSpacingLarge.p16),
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: AppColors.neutre200),
      ),
      child: Text(
        // Le message de la vue, mot pour mot. Il vaut aussi quand la recherche
        // ne rend rien : une grille vide sans phrase se lit comme un écran
        // cassé.
        message ?? 'Aucune réservation pour l’instant.',
        key: cle,
        textAlign: TextAlign.center,
        style: _t(TaillesContenu.sm, couleur: AppColors.neutre400),
      ),
    );
  }
}

/// La recherche de la page — `#recherche-reservation`, `relative mb-4
/// max-w-md`.
///
/// Elle cherche **dans le nom du client seulement**, comme la vue. Le panneau
/// Historique, lui, cherche aussi dans le canal et la référence : les deux
/// répondent à des questions différentes.
class _ChampRecherche extends ConsumerStatefulWidget {
  const _ChampRecherche();

  @override
  ConsumerState<_ChampRecherche> createState() => _ChampRechercheState();
}

class _ChampRechercheState extends ConsumerState<_ChampRecherche> {
  final _terme = TextEditingController();

  @override
  void dispose() {
    _terme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md), // mb-4
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Largeurs.maxMd),
          child: TextField(
            key: const Key('recherche-reservation'),
            controller: _terme,
            style: _t(TaillesContenu.sm),
            decoration: const InputDecoration(
              hintText: 'Rechercher un client...',
              prefixIcon: Icon(Icons.search, size: AppLayout.iconeChamp),
              prefixIconConstraints: BoxConstraints(
                minWidth: AppSpacing.xl + AppSpacing.xs,
              ),
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (v) =>
                ref.read(rechercheReservationProvider.notifier).definir(v),
          ),
        ),
      ),
    );
  }
}

/// L'onglet **Annulations** : recherche, filtre par canal, puis la table.
class _OngletAnnulations extends ConsumerStatefulWidget {
  const _OngletAnnulations();

  @override
  ConsumerState<_OngletAnnulations> createState() => _EtatOngletAnnulations();
}

class _EtatOngletAnnulations extends ConsumerState<_OngletAnnulations> {
  static const _titres = [
    'Client',
    'Séjour',
    'Total',
    'Taux',
    'Commission retenue',
    'Remboursé',
    'Annulée le',
    'Par',
  ];
  static const _droite = {2, 3, 4, 5};
  static const _parts = [2000, 2200, 1000, 800, 1500, 1200, 1500, 1000];

  CanalReservation? _canal;

  @override
  Widget build(BuildContext context) {
    final cartes = ref.watch(cartesReservationProvider);
    final terme = ref.watch(rechercheReservationProvider).trim().toLowerCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md), // mb-4
          child: Wrap(
            spacing: AppSpacing.sm, // gap-3
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: Largeurs.maxMd),
                child: SizedBox(
                  width: Largeurs.maxMd,
                  child: TextField(
                    key: const Key('annulations-recherche'),
                    style: _t(TaillesContenu.sm),
                    decoration: const InputDecoration(
                      hintText: 'Rechercher un client...',
                      prefixIcon: Icon(
                        Icons.search,
                        size: AppLayout.iconeChamp,
                      ),
                      prefixIconConstraints: BoxConstraints(
                        minWidth: AppSpacing.xl + AppSpacing.xs,
                      ),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => ref
                        .read(rechercheReservationProvider.notifier)
                        .definir(v),
                  ),
                ),
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<CanalReservation?>(
                  key: const Key('annulations-canal'),
                  value: _canal,
                  itemHeight: null,
                  iconSize: AppLayout.iconeChamp,
                  style: _t(TaillesContenu.sm, couleur: AppColors.neutre900),
                  items: [
                    DropdownMenuItem<CanalReservation?>(
                      value: null,
                      child: Text(
                        'Tous les canaux',
                        style: _t(TaillesContenu.sm),
                      ),
                    ),
                    for (final c in CanalReservation.values)
                      DropdownMenuItem<CanalReservation?>(
                        value: c,
                        child: Text(c.libelle, style: _t(TaillesContenu.sm)),
                      ),
                  ],
                  onChanged: (v) => setState(() => _canal = v),
                ),
              ),
            ],
          ),
        ),
        cartes.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('$e'),
          data: (toutes) {
            final lignes = [
              for (final c in toutes)
                if (!c.reservation.estActive &&
                    (_canal == null || c.reservation.canal == _canal) &&
                    (terme.isEmpty ||
                        c.reservation.clientNom.toLowerCase().contains(terme)))
                  c.reservation,
            ];
            if (lignes.isEmpty) {
              return const _CarteVide(
                cle: Key('annulations-vide'),
                message: 'Aucune réservation annulée pour le moment.',
              );
            }
            return ListePaginee<Reservation>(
              elements: lignes,
              prefixeCle: 'annulations-pagination',
              cleRemiseAZero: (terme, _canal),
              constructeur: (_, page) => _Table(
                titres: _titres,
                droite: _droite,
                parts: _parts,
                // Les deux couleurs de la vue : la commission retenue en rouge
                // sombre, le remboursé en vert (`reservations.blade.php` l.316-317).
                couleurs: const {
                  4: AppColors.annulationTexteRouge,
                  5: PaletteMaitre.emeraude700,
                },
                lignes: [
                  for (final r in page)
                    [
                      r.clientNom,
                      '${formaterDate(r.periode.arrivee)} → '
                          '${formaterDate(r.periode.depart)}',
                      ..._cellulesDAnnulation(r.annulation),
                    ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Les six dernières cellules d'une ligne de l'onglet Annulations : total, taux,
/// commission retenue, remboursé, date, auteur — celles que `AnnulationReservation
/// Service` a FIXÉES (v19).
///
/// ## Un tiret n'est pas un zéro
///
/// Une annulation d'AVANT la v19 n'avait ni taux ni montants : lui en prêter
/// affirmerait une commission que personne n'a retenue, sur le compte d'un
/// client. Elle garde ses tirets, comme la vue (`$tiret`) devant une colonne
/// `null`. Un « 0 FCFA » de commission n'apparaît que pour une annulation qui
/// l'a réellement fixée à zéro.
List<String> _cellulesDAnnulation(AnnulationEnregistree? a) {
  if (a == null) return List.filled(6, '—');
  final d = a.date;
  final heure =
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
  return [
    formaterCentimesEnFcfa(a.totalCentimes),
    a.tauxAffiche,
    formaterCentimesEnFcfa(a.commissionCentimes),
    formaterCentimesEnFcfa(a.rembourseCentimes),
    '${formaterDate(d)} $heure',
    a.auteurLogin ?? '—',
  ];
}

/// Table de la vue (`bg-white rounded-xl border overflow-x-auto`, en-tête
/// marine `px-4 py-3`, lignes `px-4 py-2.5`).
class _Table extends StatelessWidget {
  const _Table({
    required this.titres,
    required this.droite,
    required this.parts,
    required this.lignes,
    this.couleurs = const {},
  });

  final List<String> titres;
  final Set<int> droite;
  final List<int> parts;
  final List<List<String>> lignes;

  /// La couleur de texte d'une colonne, quand la vue lui en donne une.
  final Map<int, Color> couleurs;

  Widget _ligne(List<String> cellules, TextStyle style, double vertical) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: vertical,
      ),
      child: Row(
        children: [
          for (var i = 0; i < cellules.length; i++)
            Expanded(
              flex: parts[i],
              child: Text(
                cellules[i],
                textAlign: droite.contains(i) ? TextAlign.right : null,
                style: couleurs.containsKey(i)
                    ? style.copyWith(color: couleurs[i])
                    : style,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: AppColors.neutre200),
      ),
      child: Column(
        children: [
          Container(
            color: AppColors.navy,
            child: _ligne(
              [for (final t in titres) t.toUpperCase()],
              _t(
                TaillesContenu.t11,
                poids: FontWeight.w600,
                couleur: AppColors.neutre0,
                espacement: 0.5,
              ),
              AppSpacing.sm,
            ),
          ),
          for (final l in lignes)
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.neutre100)),
              ),
              child: _ligne(
                l,
                _t(TaillesContenu.t13, couleur: AppColors.neutre500),
                AppSpacing.xsPlus,
              ),
            ),
        ],
      ),
    );
  }
}

/// Ce que répond la route « Opérations en attente » depuis le 14/09/2026.
///
/// ## Pourquoi un panneau, et pas une liste
///
/// Cet écran listait les réservations dont le statut de synchronisation était
/// en suspens. Le poste est zéro réseau : **rien ne part plus nulle part**, et
/// `reservations_local.statut_sync` naît à `local` — les lister ici les
/// présenterait donc TOUTES comme « pas encore parties au serveur », ce qui
/// est l'indicateur qui affirme un état qu'il n'a pas vérifié (PA-59/60/61),
/// appliqué cette fois au planning entier.
///
/// Une liste vide et son « Tout est synchronisé » mentiraient autrement :
/// rien n'est synchronisé, il n'y a simplement plus de synchronisation.
///
/// La route qui mène ici vit dans `app_router.dart` et n'est pas retirée :
/// c'est le rôle de la session principale, avec l'entrée de menu qui la
/// désigne.
class _PanneauSansSynchronisation extends StatelessWidget {
  const _PanneauSansSynchronisation();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.dns_outlined,
              size: 40,
              color: AppColors.neutre500,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Ce poste n’envoie rien à un serveur',
              key: const Key('reservations-sans-synchronisation'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.unit),
            Text(
              'Toutes les réservations sont enregistrées sur ce poste, et '
              'elles y restent. Il n’y a donc aucune opération en attente, '
              'et rien à relancer.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.neutre500),
            ),
          ],
        ),
      ),
    );
  }
}
