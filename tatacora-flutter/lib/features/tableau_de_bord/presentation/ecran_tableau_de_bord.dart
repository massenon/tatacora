// Vue Blade maîtresse (PA-183) : pwa/livewire/accueil.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/format/formats.dart';
import '../../../core/navigation/trace_svg.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../caisse/presentation/providers_caisse.dart'
    show depotSessionsCaisseProvider;
import '../../facturation/presentation/providers_facturation.dart';
import '../../facturation/presentation/providers_paiements.dart';
import '../../hebergement/presentation/providers_hebergement.dart';
import '../../restaurant/presentation/widgets/corps_carte_commun.dart'
    show PageCarte;
import '../../rh/presentation/providers_rh.dart';
import '../../stocks/presentation/providers_stocks.dart';
import '../../ventes/presentation/providers_ventes.dart';
import '../data/tableau_de_bord_local.dart';
import '../domain/entities/tableau_de_bord.dart';
import '../domain/periode_locale.dart';
import 'ecran_pilotage_consolide.dart';
import 'ecran_tableau_croise.dart';
import 'onglets_tableau_de_bord.dart';
import 'widgets/champ_date_periode.dart';
import 'widgets/graphiques_tableau_de_bord.dart';
import 'widgets/modale_rapport_accueil.dart';
import 'widgets/panneau_exploitation.dart';
import 'widgets/reservations_du_jour.dart';
import 'widgets/traces_accueil.dart';

/// Le tableau de bord, établi sur la base du poste. Chaque lecteur est celui
/// de l'écran du module source : jamais une seconde requête (PA-121).
final tableauDeBordLocalProvider = Provider<TableauDeBordLocal>(
  (ref) => TableauDeBordLocal(
    unites: () => ref.read(depotReservationProvider).unites(),
    reservations: () => ref.read(depotReservationProvider).reservations(),
    employes: () => ref.read(employeDaoProvider).employes(),
    stock: () => ref.read(stocksApiProvider).etat(),
    pieces: () => ref.read(factureDaoProvider).pieces(),
    creances: () => lireCreances(ref.read),
    paiements: () => ref.read(depotPaiementsFactureProvider).paiements(),
    sessions: () => ref.read(depotSessionsCaisseProvider).sessions(),
    peutLire: () =>
        ref.read(droitsProvider).peutLire(ModuleTatacora.m11TableauxDeBord),
    maintenant: ref.watch(horlogeTableauDeBordProvider),
  ),
);

/// La période consultée — celle de TOUT l'écran (bande, graphiques, pilotage,
/// alertes), comme `filtrePeriode`/`du`/`au` du composant de la vue. Défaut :
/// celui de la vue (« Ce mois », `Accueil::$filtrePeriode`).
final periodeTableauDeBordProvider =
    NotifierProvider<_PeriodeNotifier, SelectionPeriode>(_PeriodeNotifier.new);

final class _PeriodeNotifier extends Notifier<SelectionPeriode> {
  @override
  SelectionPeriode build() => SelectionPeriode.parDefaut;

  /// Le `<select wire:model.live="filtrePeriode">` : les bornes saisies sont
  /// GARDÉES (`$du`/`$au` survivent au changement de code).
  void definir(PeriodeTableauDeBord periode) =>
      state = state.avecPeriode(periode);

  /// Les champs de l'en-tête (`wire:model.live="du"` / `"au"`), visibles en
  /// « Période personnalisée » seulement : la borne, rien d'autre.
  void definirDu(DateTime jour) => state = state.avecDu(jour);
  void definirAu(DateTime jour) => state = state.avecAu(jour);

  /// Les mêmes champs VIDÉS : le contrôle natif de la vue se vide, `$du` /
  /// `$au` deviennent `''` et la période retombe sur le mois courant.
  void effacerDu() => state = state.sansDu();
  void effacerAu() => state = state.sansAu();

  /// Les champs de la barre du pilotage : la borne ET la bascule sur
  /// « Période personnalisée » (`x-on:change="$wire.set('filtrePeriode',
  /// 'personnalisee')"`) — sans elle, `Periode::resoudre` ignorerait la date
  /// et le champ serait inerte (Article 3.3).
  void saisirDu(DateTime jour) => state = state
      .avecDu(jour)
      .avecPeriode(PeriodeTableauDeBord.personnalisee);
  void saisirAu(DateTime jour) => state = state
      .avecAu(jour)
      .avecPeriode(PeriodeTableauDeBord.personnalisee);

  /// Vider un champ de la barre du pilotage déclenche aussi l'événement
  /// `change` du navigateur, donc la même bascule sur « personnalisée » :
  /// borne vide, période résolue sur le mois courant.
  void viderDu() =>
      state = state.sansDu().avecPeriode(PeriodeTableauDeBord.personnalisee);
  void viderAu() =>
      state = state.sansAu().avecPeriode(PeriodeTableauDeBord.personnalisee);
}

/// La consultation elle-même.
///
/// `autoDispose` : quitter l'écran doit oublier la réponse. La garder ferait
/// réafficher, au retour, des chiffres qui datent de la visite précédente sans
/// que rien ne le dise.
final tableauDeBordProvider = FutureProvider.autoDispose<ResultatTableauDeBord>(
  (ref) => ref
      .watch(tableauDeBordLocalProvider)
      .consulter(ref.watch(periodeTableauDeBordProvider)),
);

/// L'étendue de la série mensuelle — 3, 6 ou 12 mois.
///
/// Séparée de la période : la vue pose deux commandes indépendantes sur le
/// même écran, et les lier ferait recalculer les huit KPI à chaque bascule de
/// 3 à 6 mois.
final moisSerieProvider = NotifierProvider<_MoisNotifier, int>(
  _MoisNotifier.new,
);

final class _MoisNotifier extends Notifier<int> {
  /// Le défaut du composant : `public int $moisSerie = 3;` — « 3 mois ».
  @override
  int build() => 3;

  void definir(int mois) => state = mois;
}

/// Les séries des graphiques.
///
/// Un appel SÉPARÉ de la bande d'indicateurs : la bande peut s'afficher
/// pendant que les graphiques chargent, et un refus sur l'un n'efface pas
/// l'autre.
final seriesTableauDeBordProvider = FutureProvider.autoDispose<ResultatSeries>(
  (ref) => ref
      .watch(tableauDeBordLocalProvider)
      .consulterSeries(
        selection: ref.watch(periodeTableauDeBordProvider),
        mois: ref.watch(moisSerieProvider),
      ),
);

/// L'écran **Tableau de bord** — la vue d'accueil de la PWA (M11).
///
/// ## La « Vue d'exploitation » suit la vue, bloc par bloc (12/10/2026)
///
/// Lot 2 de `INSTRUCTION.txt` du Product Owner. L'en-tête est celui de la vue
/// (titre SANS icône, sous-titre, trois onglets, libellé de période à leur
/// droite, sélecteur, « Actualiser », « Exporter ») ; le corps porte, dans son
/// ordre, la grille des raccourcis, la bande des huit indicateurs, le bandeau
/// d'alertes de stock, le récapitulatif de la journée, la ligne des
/// graphiques, « Statistiques de ventes par activité », « Chambres
/// disponibles » et « Consultation de secours ». Voir
/// `widgets/panneau_exploitation.dart` pour la table des blocs ; le tableau
/// des arrivées du jour est porté depuis le 14/10/2026 (lot C,
/// `widgets/reservations_du_jour.dart`).
///
/// ## Sans droit de lecture sur M11, la page de la vue — pas un refus
///
/// `/pwa` est la page d'atterrissage de TOUS les rôles : sans M11, la vue
/// titre « Consultation de secours » et rend les blocs que les autres droits
/// ouvrent (raccourcis, alertes de stock, chambres disponibles, écrans de
/// consultation), sans bande, sans graphique ni récapitulatif — « le droit se
/// vérifie avant le calcul ». Cet écran affichait jusqu'ici « Accès refusé ».
///
/// ## M11 se lit sur le poste, indicateur par indicateur (10/10/2026)
///
/// Chaque indicateur est établi ou **dit pourquoi il ne l'est pas** : « — » et
/// une raison datée, jamais un zéro (PA-120, Article 7). Voir
/// `domain/entities/tableau_de_bord.dart`. Aucun cache : les fournisseurs sont
/// `autoDispose`, et chaque visite recalcule (PA-59/60/61).
class EcranTableauDeBord extends ConsumerWidget {
  /// [periodeDemandee] : le code de période DEMANDÉ par l'adresse
  /// (`/tableau-de-bord?periode=…`, la propriété `#[Url] filtrePeriode` du
  /// composant de la vue). Absent, il est lu de l'adresse de la route, quand
  /// l'écran est monté par le routeur.
  const EcranTableauDeBord({this.periodeDemandee, super.key});

  final String? periodeDemandee;

  /// Les libellés et les notes des huit indicateurs, indexés par la clé du
  /// serveur — ceux de `lang/fr/accueil_pwa.php` (clés `accueil_pwa.kpi.<clé>.libelle`
  /// et `accueil_pwa.kpi.<clé>.note`, composées à la volée par la vue),
  /// relus par un test : une copie qui divergerait de la vue resterait verte.
  ///
  /// Registre **fermé** : une clé inconnue s'affiche avec sa clé brute plutôt
  /// que d'être masquée — un indicateur ajouté doit se voir, même mal nommé.
  static const libelles = {
    'chiffre_affaires_encaisse': "Chiffre d'affaires encaissé",
    'taux_occupation': "Taux d'occupation hôtel",
    'tresorerie_caisse': 'Trésorerie (caisse)',
    'depenses_cumulees': 'Dépenses cumulées',
    'reservations_en_attente': 'Réservations en attente',
    'factures_impayees': 'Factures non soldées',
    'valeur_stock': 'Valeur du stock',
    'employes_actifs': 'Employés actifs',
  };

  /// `:total` est remplacé par l'effectif total (champ `precedent` de
  /// `employes_actifs`, comme au serveur).
  static const notes = {
    'chiffre_affaires_encaisse': 'Somme des paiements reçus sur la période',
    'taux_occupation': 'Nuitées vendues rapportées à la capacité de la période',
    'tresorerie_caisse': 'Sessions de caisse ouvertes et leurs encaissements',
    'depenses_cumulees': 'Écritures validées de classe 6 sur la période',
    'reservations_en_attente': 'À confirmer',
    'factures_impayees': 'Certifiées dont le règlement reste incomplet',
    'valeur_stock':
        "Au coût moyen pondéré, à l'instant — jamais au prix de vente",
    'employes_actifs': 'Sur :total au total',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A3 — LE REPLI DE PÉRIODE SE DIT. Une période demandée que le sélecteur ne
    // connaît pas retombe sur le défaut ET le nomme (`periodeRefusee()` de la
    // vue) ; une période connue est appliquée UNE fois, à l'ouverture (sinon
    // l'adresse écraserait chaque choix du sélecteur).
    final demande =
        periodeDemandee ??
        GoRouter.maybeOf(
          context,
        )?.routeInformationProvider.value.uri.queryParameters['periode'];
    final connue = demande == null
        ? null
        : PeriodeTableauDeBord.parCode(demande);
    final refusee = (demande != null && connue == null) ? demande : null;
    return _AppliquePeriodeDemandee(
      periode: connue,
      child: _corps(context, ref, refusee),
    );
  }

  Widget _corps(BuildContext context, WidgetRef ref, String? refusee) {
    final resultat = ref.watch(tableauDeBordProvider);
    final onglet = ref.watch(ongletTableauDeBordProvider);
    final autorise = ref
        .watch(droitsProvider)
        .peutLire(ModuleTatacora.m11TableauxDeBord);

    // L'onglet Pilotage lit ses sources bloc par bloc. Il reçoit la RÉPONSE
    // ENTIÈRE de la bande, pas seulement ses bornes : ses cartes « Chiffre
    // d'affaires encaissé » et « Trésorerie (caisse) » et ses alertes « À
    // traiter » sont les indicateurs M11 de la bande (`accueil.blade.php`,
    // `$indicateurs`), un seul calcul sur une seule fenêtre (R1, R3 du
    // contrôle du 12/10/2026) — jamais une seconde formule.
    if (autorise && onglet == OngletTableauDeBord.pilotage) {
      final tableau = switch (resultat.value) {
        TableauDeBordRecu(:final tableau) => tableau,
        _ => null,
      };
      final marge = MediaQuery.sizeOf(context).width >= AppBreakpoints.lg
          ? AppSpacing.xl
          : AppSpacing.mdPlus;
      return Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(marge, marge, marge, 0),
            child: Column(
              children: [
                const _EnTete(),
                if (refusee != null) _BandeauPeriodeInconnue(code: refusee),
              ],
            ),
          ),
          Expanded(
            child: EcranPilotageConsolide(
              tableau: tableau,
              // « Chargement… » tant que la bande n'a rien rendu ; « Non
              // consulté » est réservé à une bande refusée (droit M11).
              bandeEnChargement: resultat.isLoading && !resultat.hasValue,
            ),
          ),
        ],
      );
    }

    // L'onglet « Tableau croisé dynamique » (`data-panneau-tb="croise"`) : la
    // MÊME fenêtre que la bande, transmise par sa réponse (13/10/2026).
    if (autorise && onglet == OngletTableauDeBord.croise) {
      final tableau = switch (resultat.value) {
        TableauDeBordRecu(:final tableau) => tableau,
        _ => null,
      };
      return PageCarte(
        largeurMax: MesuresAccueil.page,
        enfants: [
          const _EnTete(),
          const SizedBox(height: AppSpacing.mdPlus), // mb-5
          if (refusee != null) _BandeauPeriodeInconnue(code: refusee),
          PanneauTableauCroise(tableau: tableau),
        ],
      );
    }

    return PageCarte(
      largeurMax: MesuresAccueil.page,
      enfants: [
        const _EnTete(),
        const SizedBox(height: AppSpacing.mdPlus), // mb-5
        if (refusee != null) _BandeauPeriodeInconnue(code: refusee),
        resultat.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          // La lecture de la bande a ÉCHOUÉ : la vue rend la page entière et
          // remplace la seule bande par l'encadré « Non consulté » (son
          // `catch`, qui « ne remplace aucun chiffre ») — jamais l'exception
          // technique à l'écran (Article 7).
          error: (e, _) => const _Corps(tableau: null, bandeEnEchec: true),
          data: (r) => switch (r) {
            TableauDeBordRecu(:final tableau) => _Corps(tableau: tableau),
            // Sans droit M11 : la page de la vue pour ce rôle, sans aucun
            // chiffre consolidé (les blocs M11 ne sont pas construits).
            TableauDeBordRefuse() => const _Corps(tableau: null),
          },
        ),
      ],
    );
  }
}

/// L'en-tête de la vue (l.236-306) : `flex flex-col lg:flex-row lg:items-center
/// gap-3 mb-5`.
///
/// À partir de `lg` (largeur d'ÉCRAN, Article 5), trois éléments sur une
/// ligne : le bloc titre (titre, sous-titre `mt-1`, onglets `mt-3`), le libellé
/// de période (`lg:self-end lg:mr-3` : en bas, juste à droite du bloc), puis
/// les commandes (`lg:ml-auto` : à droite, centrées). En dessous, ils
/// s'empilent.
class _EnTete extends ConsumerWidget {
  const _EnTete();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autorise = ref
        .watch(droitsProvider)
        .peutLire(ModuleTatacora.m11TableauxDeBord);
    final large = MediaQuery.sizeOf(context).width >= AppBreakpoints.lg;

    // `text-lg lg:text-xl font-bold` navy. Sans M11, le titre de la page de
    // consultation (`pwa.accueil.titre` / `sous_titre`) : nommer « Tableau de
    // bord » un écran qu'on ne reçoit pas tromperait (la vue, l.238-246).
    final bloc = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          autorise ? 'Tableau de bord' : 'Consultation de secours',
          key: const Key('tdb-titre'),
          style: styleExploitation(
            large ? TaillesContenu.xl : TaillesContenu.lg,
            poids: FontWeight.w700,
            interligne: large
                ? TaillesContenu.interligneXl
                : TaillesContenu.interligneLg,
            couleur: AppColors.navy,
          ),
        ),
        const SizedBox(height: AppSpacing.unit), // mt-1
        Text(
          autorise
              ? 'Vision consolidée et en temps réel de la performance de '
                    'chaque activité'
              : 'Consultation de secours — les écrans auxquels votre rôle '
                    'donne accès.',
          key: const Key('tdb-sous-titre'),
          style: styleExploitation(
            TaillesContenu.t15,
            couleur: AppColors.neutre500,
          ),
        ),
        if (autorise) ...[
          const SizedBox(height: AppSpacing.sm), // mt-3
          const BarreOngletsTableauDeBord(),
        ],
      ],
    );
    if (!autorise) return bloc;

    final periode = Text(
      // La fenêtre que le calcul emploie, par la MÊME fonction
      // (`FenetreTableauDeBord.resoudre`, celle de `TableauDeBordLocal`) :
      // aucune seconde règle de bornes. En « Période personnalisée » sans ses
      // deux dates, elle dit les dates du MOIS — celles qui sont calculées.
      FenetreTableauDeBord.resoudre(
        ref.watch(periodeTableauDeBordProvider),
        ref.watch(horlogeTableauDeBordProvider)(),
      ).libelle,
      key: const Key('tdb-libelle-periode'),
      style: styleExploitation(
        TaillesContenu.t12,
        couleur: AppColors.neutre400,
      ),
    );
    const commandes = _Commandes();

    if (!large) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bloc,
          const SizedBox(height: AppSpacing.sm), // gap-3
          periode,
          const SizedBox(height: AppSpacing.sm),
          commandes,
        ],
      );
    }
    // Les éléments d'une ligne flexible CSS RÉTRÉCISSENT quand la ligne ne
    // tient pas (`flex-shrink: 1`), et le bloc titre passe alors à la ligne.
    // Ici : le bloc est le seul élément souple ; `lg:ml-auto` est rendu par
    // `spaceBetween`, `lg:items-center` par le centrage de la rangée, et
    // `lg:self-end` par l'alignement BAS de la petite rangée bloc + période.
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(child: bloc),
              const SizedBox(width: AppSpacing.sm), // gap-3
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm), // mr-3
                child: periode,
              ),
            ],
          ),
        ),
        commandes,
      ],
    );
  }
}

/// `lg:ml-auto flex flex-wrap gap-2` : le sélecteur de période, les deux
/// dates en « Période personnalisée », « Actualiser » et « Exporter ».
class _Commandes extends ConsumerWidget {
  const _Commandes();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(periodeTableauDeBordProvider);
    final periodes = ref.read(periodeTableauDeBordProvider.notifier);
    final aujourdhui = ref.read(horlogeTableauDeBordProvider)();
    final bordure = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      borderSide: const BorderSide(color: AppColors.neutre200),
    );

    return Wrap(
      spacing: AppSpacing.xs, // gap-2
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // `champ text-[15px] border border-slate-200 rounded-lg px-3 py-2.5
        // bg-white`. La période change aussi AILLEURS que par ce sélecteur —
        // « Exercice entier » et les deux dates du pilotage. Le champ suit :
        // `DropdownButtonFormField.didUpdateWidget` reprend un `initialValue`
        // qui a changé (SDK Flutter, `dropdown.dart`), et les tests lisent la
        // VALEUR du champ, pas un texte que la pile du menu contient toujours.
        SizedBox(
          width: MesuresAccueil.selecteurPeriode,
          child: DropdownButtonFormField<PeriodeTableauDeBord>(
            key: const Key('tdb-periode'),
            initialValue: selection.periode,
            isExpanded: true,
            style: styleExploitation(
              TaillesContenu.t15,
              couleur: AppColors.anthracite,
            ),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: AppColors.neutre0,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, // px-3
                vertical: AppSpacing.xsPlus, // py-2.5
              ),
              border: bordure,
              enabledBorder: bordure,
              focusedBorder: bordure.copyWith(
                borderSide: const BorderSide(color: AppColors.gold),
              ),
            ),
            // Les sept options de la vue, dans son ordre
            // (`accueil_pwa.periodes`).
            items: [
              for (final p in PeriodeTableauDeBord.values)
                DropdownMenuItem(value: p, child: Text(p.libelle)),
            ],
            onChanged: (p) {
              if (p != null) periodes.definir(p);
            },
          ),
        ),
        // `@if ($filtrePeriode === 'personnalisee')` : les deux bornes,
        // séparées par « Au » (`accueil_pwa.periode_au`), et titrées « Du » /
        // « Au » comme les `title` de la vue.
        if (selection.periode == PeriodeTableauDeBord.personnalisee)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ChampDatePeriode(
                cle: const Key('tdb-periode-du'),
                titre: 'Du',
                valeur: selection.du,
                initiale: aujourdhui,
                onChoix: periodes.definirDu,
                onEffacer: periodes.effacerDu,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Au',
                style: styleExploitation(
                  TaillesContenu.t13,
                  couleur: AppColors.neutre400,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              ChampDatePeriode(
                cle: const Key('tdb-periode-au'),
                titre: 'Au',
                valeur: selection.au,
                initiale: aujourdhui,
                onChoix: periodes.definirAu,
                onEffacer: periodes.effacerAu,
              ),
            ],
          ),
        // « Actualiser » — `wire:click="$refresh"` : un rafraîchissement du
        // CADRE. Ici, chaque lecture de l'écran est relancée (aucune n'a de
        // cache) ; rien n'est affirmé d'autre.
        Tooltip(
          message: 'Actualiser',
          child: _BoutonEnTete(
            cle: const Key('tdb-actualiser'),
            onTap: () => ref
              ..invalidate(tableauDeBordProvider)
              ..invalidate(seriesTableauDeBordProvider)
              ..invalidate(stockPilotageProvider)
              ..invalidate(parcPilotageProvider)
              ..invalidate(reservationsPilotageProvider)
              ..invalidate(journalVentesProvider)
              ..invalidate(sourcesCroiseLuesProvider),
            enfant: const IconeTrace(
              trace: TracesAccueil.actualiser,
              taille: MesuresAccueil.iconeActualiser,
              couleur: AppColors.neutre500,
            ),
          ),
        ),
        // « Exporter » — `wire:click="ouvrirExport"` puis `genererExport` : la
        // modale partagée, puis le rapport par défaut du composant, la
        // SYNTHÈSE du tableau de bord (`lignesIndicateurs`), en PDF ou en
        // tableur (lot C, 14/10/2026 — jusque-là, ce bouton produisait le
        // PDF du pilotage consolidé, que le serveur ne produit pas).
        // Le bouton « Exporter » de la barre du pilotage (`ouvrirExport('pdf')`,
        // même `genererExport` au serveur) appelle la même action depuis le
        // 14/10/2026 (lot D, D415) : l'écart résiduel du lot C est fermé.
        _BoutonEnTete(
          cle: const Key('tdb-exporter'),
          onTap: () => exporterSyntheseAccueil(context, ref),
          enfant: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const IconeTrace(
                trace: TracesAccueil.document,
                taille: MesuresAccueil.iconeExporter,
                couleur: AppColors.neutre600,
              ),
              const SizedBox(width: AppSpacing.xxs), // gap-1.5
              Text(
                'Exporter',
                style: styleExploitation(
                  TaillesContenu.t15,
                  poids: FontWeight.w600,
                  couleur: AppColors.neutre600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// `btn flex items-center gap-1.5 px-3 py-2.5 rounded-lg border
/// border-slate-200 bg-white`.
class _BoutonEnTete extends StatelessWidget {
  const _BoutonEnTete({
    required this.cle,
    required this.onTap,
    required this.enfant,
  });

  final Key cle;
  final VoidCallback onTap;
  final Widget enfant;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.neutre0,
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      child: InkWell(
        key: cle,
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, // px-3
            vertical: AppSpacing.xsPlus, // py-2.5
          ),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.neutre200),
            borderRadius: BorderRadius.circular(AppRadius.roundedLg),
          ),
          child: enfant,
        ),
      ),
    );
  }
}

/// Le corps de la « Vue d'exploitation », dans l'ordre de la vue.
///
/// [tableau] `null` sans [bandeEnEchec] : aucun droit de lecture sur M11 — ni
/// bande, ni graphiques (le récapitulatif vérifie le droit lui-même).
/// [bandeEnEchec] : le droit est là mais la LECTURE a échoué — l'encadré
/// « Non consulté » à la place de la bande, les graphiques suivent leur propre
/// lecture.
class _Corps extends ConsumerWidget {
  const _Corps({required this.tableau, this.bandeEnEchec = false});

  final TableauDeBord? tableau;
  final bool bandeEnEchec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tableau = this.tableau;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BarreAccesRapides(),
        if (tableau != null)
          BandeIndicateurs(
            tableau: tableau,
            libelles: EcranTableauDeBord.libelles,
            valeur: valeurIndicateurAffichee,
            note: noteCarteIndicateur,
          )
        else if (bandeEnEchec)
          const BandeNonConsultee(),
        // Le tableau des arrivées du jour (l.432-541) et ses trois gestes —
        // porté le 14/10/2026 (lot C).
        const TableReservationsDuJour(),
        const BandeauAlertesStock(),
        const RecapitulatifJournee(),
        if (tableau != null || bandeEnEchec) const _Graphiques(),
        const TableChambresDisponibles(),
        const ConsultationDeSecours(),
      ],
    );
  }
}

/// La ligne des graphiques (`grid grid-cols-1 xl:grid-cols-3 gap-5 mb-5`, la
/// carte du chiffre d'affaires en `xl:col-span-2`) puis « Statistiques de
/// ventes par activité » (`mb-5`).
///
/// Les graphiques ont leur **propre chargement** : ils n'empêchent pas la bande
/// de s'afficher, et leur échec ne l'efface pas.
class _Graphiques extends ConsumerWidget {
  const _Graphiques();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final series = ref.watch(seriesTableauDeBordProvider);
    final mois = ref.watch(moisSerieProvider);
    final large = MediaQuery.sizeOf(context).width >= AppBreakpoints.xl;

    // `null` : la lecture a ÉCHOUÉ. Les trois cartes restent, chacune avec la
    // phrase de la vue (`lecture_impossible`) à la place de son canevas : un
    // graphique vide se lirait comme une activité nulle (la vue, l.636-647).
    Widget cartes(SeriesTableauDeBord? series) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.mdPlus),
          child: large
              ? LayoutBuilder(
                  builder: (context, contraintes) {
                    // Une colonne de la grille de trois, gouttières de
                    // 20 px (`gap-5`) : la carte du chiffre d'affaires en
                    // couvre deux ET la gouttière qui les sépare.
                    const ecart = AppSpacing.mdPlus;
                    final colonne = (contraintes.maxWidth - 2 * ecart) / 3;
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 2 * colonne + ecart,
                            child: _ca(series, mois, ref),
                          ),
                          const SizedBox(width: ecart),
                          Expanded(
                            child: GraphiqueRepartition(
                              parts: series?.ventilation,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ca(series, mois, ref),
                    const SizedBox(height: AppSpacing.mdPlus),
                    GraphiqueRepartition(parts: series?.ventilation),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.mdPlus),
          child: GraphiqueActivites(parts: series?.ventilation),
        ),
      ],
    );

    return series.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => cartes(null),
      data: (r) => switch (r) {
        SeriesRecues(:final series) => cartes(series),
        // Un refus sur les SÉRIES seulement : la bande reste affichée
        // au-dessus, et l'écran dit ce qui manque plutôt que de rendre des
        // cadres vides.
        SeriesRefusees(:final motif) => _NoteGraphiques(
          cle: const Key('tdb-series-refus'),
          texte: motif,
        ),
      },
    );
  }

  Widget _ca(SeriesTableauDeBord? series, int mois, WidgetRef ref) =>
      GraphiqueCaDepenses(
        series: series,
        mois: mois,
        onMois: (m) => ref.read(moisSerieProvider.notifier).definir(m),
      );
}

class _NoteGraphiques extends StatelessWidget {
  const _NoteGraphiques({required Key cle, required this.texte})
    : super(key: cle);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.mdPlus),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.mdPlus),
        decoration: carteAccueil(),
        child: Text(
          texte,
          style: styleExploitation(
            TaillesContenu.t13,
            couleur: AppColors.neutre500,
          ),
        ),
      ),
    );
  }
}

/// Met en forme la valeur d'un indicateur SANS la recalculer — la bande ET les
/// cartes du pilotage consolidé qui reprennent ses indicateurs (« Chiffre
/// d'affaires encaissé », « Trésorerie (caisse) », « Valeur du stock »)
/// passent par ici : la vue
/// les écrit toutes par `MontantFcfa::format`, une seule mise en forme.
///
/// Un indicateur sans source s'écrit « — » : jamais « 0 FCFA », qui se lit
/// comme une journée sans recette (Article 7).
///
/// Le pourcentage s'écrit comme la vue (`$kpi['valeur'] . ' %'`), point
/// décimal compris : « 10.00 % ».
String valeurIndicateurAffichee(IndicateurTableauDeBord indicateur) {
  if (!indicateur.estDisponible) return '—';
  final nombre = double.tryParse(indicateur.valeur);
  if (nombre == null) return indicateur.valeur;

  return switch (indicateur.unite) {
    UniteIndicateur.montant => formaterFcfa(nombre.round()),
    UniteIndicateur.pourcentage => '${indicateur.valeur} %',
    UniteIndicateur.nombre => '${nombre.round()}',
  };
}

/// La note d'un indicateur, telle que la carte de la bande l'écrit : la note de
/// la vue (`kpi.<clé>.note`), suivie de la [IndicateurTableauDeBord.mention]
/// quand la valeur est une somme partielle (« · hors 1 article(s) sans coût »,
/// D119) — ou la RAISON de l'absence, jamais la note d'un chiffre qui n'existe
/// pas. Une seule mise en forme : la bande ET la carte « Valeur du stock » du
/// pilotage consolidé passent par ici (12/10/2026).
String noteIndicateurAffichee(IndicateurTableauDeBord indicateur) {
  final raison = indicateur.raisonAbsence;
  if (raison != null) return raison;
  return noteCarteIndicateur(indicateur);
}

/// La note d'une carte de la BANDE : celle de la vue, toujours — même sous un
/// « — ».
///
/// ## Écart à la vue nommé, et pourquoi la raison n'est plus rendue ici
///
/// Le partiel de la vue (`accueil-cartes-kpi`, lu par `accueil.blade.php`)
/// écrit sous chaque valeur la note de langue `kpi.<clé>.note`, courte ; il
/// n'a pas d'état « sans source » (chaque chiffre y est calculé) et ne porte
/// aucune infobulle. Jusqu'au 13/10/2026, la carte du poste remplaçait cette
/// note par la RAISON DATÉE de l'absence (« Ce chiffre se lit dans la
/// comptabilité… (constaté le 10/10/2026, revu le 12/10/2026). », plusieurs
/// lignes) : la carte grandissait, et
/// toute la seconde rangée de la bande descendait de 173 px (relevé de
/// géométrie `livewire/accueil`, huit éléments hors position). Décision du PO
/// du 13/10/2026 (« regarde ce qui est fait dans tatacora laravel vue ») : la
/// carte suit la vue — même note, même hauteur.
///
/// Ce qui reste du poste, et qui n'invente rien d'affiché : la VALEUR reste
/// « — » (gris), jamais un zéro (Article 7) ; `:total` d'un indicateur sans
/// source s'écrit « — » ; la mention d'une somme partielle (« · hors N
/// article(s) sans coût », D119) suit la note d'un chiffre ÉTABLI, comme
/// avant. La raison complète n'est plus rendue par la bande : elle reste
/// portée par l'indicateur ([IndicateurTableauDeBord.raisonAbsence]) et rendue
/// en mention par l'aperçu de l'état « Tableau de bord » (M14,
/// `apercuTableauDeBord`) pour les huit indicateurs, et par les cartes
/// « Trésorerie (caisse) » et « Valeur du stock » du pilotage consolidé
/// ([noteIndicateurAffichee]).
String noteCarteIndicateur(IndicateurTableauDeBord indicateur) {
  final base = (EcranTableauDeBord.notes[indicateur.cle] ?? '').replaceAll(
    ':total',
    indicateur.estDisponible ? indicateur.precedent : '—',
  );
  // Un indicateur sans source n'a jamais de mention (`indisponible`).
  final mention = indicateur.mention;
  return mention == null ? base : '$base · $mention';
}

/// Applique UNE fois la période demandée par l'adresse (`#[Url]` de la vue).
class _AppliquePeriodeDemandee extends ConsumerStatefulWidget {
  const _AppliquePeriodeDemandee({required this.periode, required this.child});

  final PeriodeTableauDeBord? periode;
  final Widget child;

  @override
  ConsumerState<_AppliquePeriodeDemandee> createState() =>
      _EtatAppliquePeriodeDemandee();
}

class _EtatAppliquePeriodeDemandee
    extends ConsumerState<_AppliquePeriodeDemandee> {
  @override
  void initState() {
    super.initState();
    final p = widget.periode;
    if (p == null) return;
    // Hors de la construction : un fournisseur ne se modifie pas pendant elle.
    Future.microtask(() {
      if (mounted) ref.read(periodeTableauDeBordProvider.notifier).definir(p);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// « La période demandée (« x ») n'existe pas… » — `accueil_pwa.periode_inconnue`
/// (l.309-313) : `rounded-xl px-4 py-3 mb-5 text-[13px]`, fond `#FFFBEB`,
/// liseré `#FDE68A`, texte `#78350F`.
class _BandeauPeriodeInconnue extends StatelessWidget {
  const _BandeauPeriodeInconnue({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('tdb-periode-inconnue'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.mdPlus), // mb-5
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md, // px-4
        vertical: AppSpacing.sm, // py-3
      ),
      decoration: BoxDecoration(
        color: PaletteMaitre.ambre50,
        border: Border.all(color: PaletteMaitre.ambre200),
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
      ),
      child: Text(
        "La période demandée (« $code ») n'existe pas. Les chiffres ci-dessous sont ceux de la période par défaut, « ${PeriodeTableauDeBord.parDefaut.libelle} » — ils ne répondent pas à la demande qui a été faite.",
        style: styleExploitation(
          TaillesContenu.t13,
          couleur: PaletteMaitre.ambre900,
        ),
      ),
    );
  }
}
