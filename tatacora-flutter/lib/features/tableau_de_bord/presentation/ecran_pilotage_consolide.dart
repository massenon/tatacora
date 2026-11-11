// Vue Blade maîtresse (PA-183) : pwa/livewire/accueil.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../comptabilite/domain/consultation_comptable.dart'
    show repartitionStatuts;
import '../../comptabilite/presentation/exercice_consulte.dart';
import '../../comptabilite/presentation/providers_comptabilite.dart'
    show comptabiliteDaoProvider;
import '../../comptabilite/presentation/providers_consultation_comptable.dart'
    show lireDonneesComptabilite;
import '../../comptabilite/presentation/providers_etats_financiers.dart'
    show lireDonneesEtats;
import '../../../core/fichiers/enregistrement_export.dart';
import '../../../core/format/formats.dart';
import '../../../core/impression/entete_parametree.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared_widgets/modale_export.dart';
import '../../../shared_widgets/toast_export.dart';
import '../../hebergement/domain/entities/historique_reservations.dart';
import '../../hebergement/domain/entities/reservation.dart';
import '../../hebergement/domain/entities/unite_hebergement.dart';
import '../../depenses/domain/filtre_depenses.dart';
import '../../depenses/domain/indicateurs_depenses.dart';
import '../../depenses/presentation/providers_depenses.dart';
import '../../facturation/domain/creances.dart';
import '../../facturation/presentation/providers_paiements.dart';
import '../../hebergement/presentation/providers_hebergement.dart';
import '../../rh/domain/services/livre_de_paie_service.dart';
import '../../rh/presentation/providers_rh.dart';
import '../../../core/di/providers.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../stocks/data/stocks_api.dart';
import '../../stocks/domain/entities/etat_stock.dart';
import '../../stocks/presentation/providers_stocks.dart';
import '../../ventes/domain/journal_ventes.dart';
import '../../ventes/presentation/providers_ventes.dart';
import '../../vehicules/presentation/providers_vehicules.dart';
import '../../tourisme/domain/departs.dart';
import '../../tourisme/presentation/providers_tourisme.dart';
import '../../../core/navigation/navigation_tatacora.dart';
import '../domain/analytique_locale.dart' show decimaleDeCentimes;
import '../domain/modules_pilotage.dart';
import '../data/pilotage_api.dart';
import '../domain/entities/pilotage.dart';
import '../domain/entities/tableau_de_bord.dart';
import '../domain/indicateurs_locaux.dart';
import '../domain/periode_locale.dart';
import '../domain/pilotage_local.dart';
import '../impression/etat_pilotage.dart';
// L'écran hôte : la période d'en-tête (« Exercice entier » la règle), les
// libellés et notes des indicateurs M11 (une seule copie, relue contre
// `lang/fr/accueil_pwa.php`) et leur mise en forme. Import circulaire assumé :
// l'hôte monte cet onglet, cet onglet pilote la période de l'hôte — comme la
// vue, où les deux vivent dans le même composant.
import 'ecran_tableau_de_bord.dart'
    show
        EcranTableauDeBord,
        noteIndicateurAffichee,
        periodeTableauDeBordProvider,
        valeurIndicateurAffichee;
import 'widgets/champ_date_periode.dart';
import 'widgets/graphique_creances_anciennete.dart';
import 'widgets/graphique_marge_centres.dart';
import 'widgets/modale_stocks_critiques.dart';
// « Exporter » de la barre = la synthèse de l'en-tête (D415) : import
// circulaire assumé, la modale des rapports lit déjà cet onglet.
import 'widgets/modale_rapport_accueil.dart' show exporterSyntheseAccueil;

// La mention vit au domaine (la bande d'indicateurs la dit aussi) ; ce
// fichier la rend toujours accessible à ses lecteurs historiques.
export '../domain/indicateurs_locaux.dart' show mentionStockSansCout;

/// L'onglet **« Pilotage consolidé »** — `tableau-de-bord.html` l.162-227 et
/// `pages/m11-pilotage.js`. C'est l'ancien `m11-pilotage.html`, que le maître
/// a lui-même retiré du menu (« Page conservée pour compatibilité — le
/// pilotage consolidé est désormais un onglet du Tableau de bord »).
///
/// ## Ce qui est établi sur le poste, ce qui ne l'est pas (revu le 13/10/2026)
///
/// ⚠ Jusqu'au 13/10/2026 ce tableau disait les marges « Non consulté », le
/// graphique des créances par ancienneté « non rendu » et les quatre cartes
/// M8 / M9 / M13 / M3 « non rendues » : FAUX depuis la fin du Pilotage
/// (décision du PO, D370). Relu contre le code ci-dessous le 13/10/2026.
///
/// | Bloc | Source | Verdict |
/// |---|---|---|
/// | Carte « Valeur du stock » | indicateur `valeur_stock` de la BANDE (M11), même voie que CA et trésorerie | établi depuis le 12/10/2026 (lisait M6 jusque-là) |
/// | Alertes de stock, carte « Stocks » par module | M6 (`StocksApi.etat`) | établi |
/// | Masse salariale | bulletins du mois (M13) | établi, « Aucun bulletin établi ce mois-ci » sans bulletin |
/// | Occupation, meilleures ventes | réservations, parc, ventes | établi |
/// | Cartes M1, point de vente, stocks | idem | établi |
/// | Carte « Dépense courante » | `depenses_local` | établi (refus levé) |
/// | Cartes « Chiffre d'affaires encaissé » et « Trésorerie (caisse) » | indicateurs M11 de la BANDE (`TableauDeBordLocal`), même fenêtre | établi depuis le 12/10/2026 (R1, D289) |
/// | Résultat net, valeur ajoutée, bilan | M10 consolidé (`PilotageApi.indicateurs`) | « Non consulté » : aucun compte de résultat, balance ni bilan n'est calculé sur ce poste (`PilotageApi.raisonAbsence`, datée du 13/10/2026) |
/// | Marge sur coûts directs par activité | `PilotageApi.analytique` → `analytique_locale.dart`, réplique d'`AnalytiqueService` sur l'exercice OUVERT le plus récent | établi depuis le 13/10/2026 (D370), confronté au vrai service ; « Non consulté » sans droit M10 ou sans exercice ouvert, comme la vue |
/// | Créances clients | `creances.dart` (encaissements écrits depuis le lot 5, D234) | établi depuis le 12/10/2026 (D282) |
/// | « À traiter » : créances, factures non soldées, réservations en attente | `totauxCreances` (droit M3) et la bande M11 | établi depuis le 12/10/2026 (R3, D289) |
/// | Créances par ancienneté (graphique) | `creancesParAnciennete` (`modules_pilotage.dart`), réplique d'`Accueil::creancesParAnciennete` | établi depuis le 13/10/2026 (D370), confronté au serveur ; « Non consulté » sans droit M3 |
/// | Cartes Véhicules, Tourisme, Personnel & paie, Clients & créances | M8, M9, M13, M3 (`modules_pilotage.dart`) | établies depuis le 13/10/2026 (D370) ; chacune gardée par le droit de lecture ET le masquage par rôle de la barre latérale ([carteModuleVisible]) |
///
/// Un refus du maître reste déclaré, par son jeton `maitre-refuse:` à
/// l'endroit où il aurait vécu ([_CarteReserves]) : la réserve « N ligne(s)
/// sans centre analytique » — impossible par construction
/// (`ecritures_comptables.centre_id` NOT NULL). Ce jeton est un HISTORIQUE :
/// le comparateur de la vue ne lit que les jetons `blade-refuse:`.
///
/// ⚠ Deux refus déclarés ici sont LEVÉS, et leurs jetons retirés : la carte
/// « Dépense courante » le 10/10/2026 (motif « aucune table `depenses` »
/// périmé avec la v10) et le graphique des créances par ancienneté le
/// 13/10/2026 (motif « aucun service serveur ne calcule de tranches » périmé :
/// `Accueil::creancesParAnciennete` les calcule, et le poste les réplique).
/// PA-144 : un motif de refus qui a cessé d'être vrai transforme une décision
/// en oubli.
///
/// « À traiter » porte les cinq familles d'alertes de la vue
/// (`Accueil::alertesPilotage`) : comptabilité (M10, non évaluée sur ce poste,
/// raison dite), créances clients (M3), factures non soldées et réservations en
/// attente (M11), stock sous seuil (M6) — avec le compte des sources
/// consultées. ⚠ Revu le 12/10/2026 (R3, D289) : ce paragraphe disait que les
/// créances n'avaient « aucune source » ; faux depuis le lot 5 (D234). Les
/// alertes du PROTOTYPE que la vue elle-même ne porte pas (créances à plus de
/// 90 jours, bulletins manquants, salariés sans numéro CNSS, restes à encaisser
/// véhicules et circuits) ne sont pas rendues ici non plus. **Aucune n'est
/// affichée à vide, et l'écran ne dit jamais « tout est au vert »** — voir
/// [_CarteATraiter].
///
/// ## Une seule base, des sources qui répondent bloc par bloc
///
/// Chaque bloc a ses issues : une source refusée n'efface pas les autres.
class EcranPilotageConsolide extends ConsumerWidget {
  const EcranPilotageConsolide({
    super.key,
    this.tableau,
    this.bandeEnChargement = false,
  });

  /// La bande est en cours de calcul (aucune réponse encore) : ses deux cartes
  /// disent « Chargement… », le mot des autres cartes en attente — pas « Non
  /// consulté », qui affirmerait une lecture refusée (réserve 5, 12/10/2026).
  final bool bandeEnChargement;

  /// La réponse de la BANDE d'indicateurs (M11) — la même instance que
  /// l'onglet d'exploitation affiche : ses bornes (un seul calcul de fenêtre
  /// par affichage), son libellé de période et ses indicateurs, que les cartes
  /// « Chiffre d'affaires encaissé » et « Trésorerie (caisse) » et les alertes
  /// « À traiter » reprennent tels quels, comme la vue reprend `$indicateurs`.
  /// `null` si le tableau n'a pas été reçu (droit de lecture refusé,
  /// chargement) — les blocs qui en dépendent le disent.
  final TableauDeBord? tableau;

  DateTime? get debutPeriode => tableau?.debut;
  DateTime? get finExcluePeriode => tableau?.finExclue;

  FenetreTableauDeBord? get _fenetre =>
      debutPeriode == null || finExcluePeriode == null
      ? null
      : FenetreTableauDeBord.entre(debutPeriode!, finExcluePeriode!);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // La respiration latérale du maître : `lg:mx-[33px]`, annulée sous
    // 1024 px — « 66 px prélevés sur une largeur de téléphone écraseraient
    // les cartes » (commentaire du maître, l.157-161). Largeur d'ÉCRAN, pas
    // du conteneur (Article 5).
    final large = MediaQuery.sizeOf(context).width >= AppBreakpoints.lg;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md + (large ? AppSpacing.mx33 : 0),
        AppSpacing.md,
        AppSpacing.md + (large ? AppSpacing.mx33 : 0),
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _BarreFiltresPilotage(),
          const SizedBox(height: AppSpacing.md),
          _GrilleKpisPilotage(
            tableau: tableau,
            bandeEnChargement: bandeEnChargement,
          ),
          const SizedBox(height: AppSpacing.mdPlus),
          _RangeeCartes(
            gauche: _CarteATraiter(tableau: tableau),
            droite: const _CarteReserves(),
          ),
          const SizedBox(height: AppSpacing.mdPlus),
          _RangeeCartes(
            gauche: const _CarteMargeCentres(),
            droite: const _CarteCreancesAnciennete(),
          ),
          const SizedBox(height: AppSpacing.mdPlus),
          _TitreSection('Occupation & meilleures ventes'),
          const SizedBox(height: AppSpacing.sm),
          _BlocOccupation(debut: debutPeriode, finExclue: finExcluePeriode),
          const SizedBox(height: AppSpacing.md),
          _GrilleTopVentes(debut: debutPeriode, finExclue: finExcluePeriode),
          const SizedBox(height: AppSpacing.lg),
          _TitreSection('Par module'),
          const SizedBox(height: AppSpacing.sm),
          _GrilleModules(fenetre: _fenetre, tableau: tableau),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

/* ====================================================================== */
/* Providers — chaque source serveur a SES issues, aucune n'efface l'autre */
/* ====================================================================== */

/// L'horloge du tableau de bord — injectable : la période (« Ce mois » par
/// défaut) dépend du jour, et un test qui lirait l'heure réelle serait vert un jour et
/// rouge le lendemain.
///
/// Sélecteur d'exercice global (PO, 20/10/2026) : c'est l'horloge de
/// l'EXERCICE CONSULTÉ — aujourd'hui pour l'exercice en cours, son dernier
/// jour pour un exercice passé (`exercice_consulte.dart`).
final horlogeTableauDeBordProvider = Provider<DateTime Function()>(
  (ref) => ref.watch(horlogeExerciceConsulteProvider),
);

/// La masse salariale du MOIS COURANT — somme des bruts des bulletins retenus
/// (annulés exclus), jamais le coût employeur total (PA-53 : le taux de
/// risques professionnels n'est pas confirmé, donc aucun total n'existe).
///
/// `null` sans droit de lecture sur M13 : le chiffre n'est ni zéro ni absent, il
/// n'a pas été lu — la carte dit « Non consulté », comme la vue.
final masseSalarialePilotageProvider = FutureProvider.autoDispose<TotauxLivre?>(
  (ref) async {
    if (!ref.read(droitsProvider).peutLire(ModuleTatacora.m13Rh)) return null;
    final maintenant = ref.read(horlogeTableauDeBordProvider)();
    final periode =
        '${maintenant.year}-${maintenant.month.toString().padLeft(2, '0')}';
    return ref.read(livreDePaieServiceProvider).totaux(periode);
  },
);

/// Les dépenses courantes de la fenêtre affichée — `DepenseService::filtrer`
/// du serveur : `date_transaction` entre `du` et `au` INCLUS, où `au` est la
/// veille de la borne exclue. Les indicateurs sont ceux de l'écran Dépense
/// courante ([IndicateursDepenses]), jamais une seconde somme.
final depensesPilotageProvider = FutureProvider.autoDispose
    .family<IndicateursDepenses, FenetreTableauDeBord>((ref, fenetre) async {
      final toutes = await ref.read(depotDepensesProvider).depenses();
      final dernierJour = DateTime(
        fenetre.finExclue.year,
        fenetre.finExclue.month,
        fenetre.finExclue.day - 1,
      );
      return IndicateursDepenses.calculer(
        filtrerDepenses(
          toutes,
          FiltreDepenses(du: fenetre.debut, au: dernierJour),
        ),
      );
    });

final pilotageApiProvider = Provider<PilotageApi>(
  (ref) => PilotageApi(
    base: ref.watch(baseLocaleProvider),
    // Les six indicateurs comptables se calculent sur ce poste.
    etats: () => lireDonneesEtats(ref),
    decompteStatuts: (exerciceId) async {
      final d = await lireDonneesComptabilite(
        ref.read(comptabiliteDaoProvider),
      );
      final r = repartitionStatuts(d.ecritures, exerciceId: exerciceId);
      return (brouillons: r.brouillon, validees: r.validee);
    },
  ),
);

/// L'exercice comptable courant. `autoDispose` : quitter l'écran oublie la
/// réponse — M11 n'a aucun cache (PA-120).
final exercicePilotageProvider =
    FutureProvider.autoDispose<SourcePilotage<ExercicePilotage>>(
      (ref) => ref.watch(pilotageApiProvider).exercice(),
    );

/// Reporte l'issue de l'exercice sur une lecture qui en dépend : un refus ou
/// une coupure en amont N'EST PAS transformé en « réponse illisible ».
SourcePilotage<T> _reporter<T>(SourcePilotage<ExercicePilotage> exercice) =>
    switch (exercice) {
      SourceRecue<ExercicePilotage>() => throw StateError(
        'Un exercice reçu ne se reporte pas : il se consomme.',
      ),
      SourceRefusee<ExercicePilotage>(:final motif, :final codeHttp) =>
        SourceRefusee<T>(motif: motif, codeHttp: codeHttp),
      SourceInjoignable<ExercicePilotage>() => SourceInjoignable<T>(),
      SourceAbsente<ExercicePilotage>(:final raison) => SourceAbsente<T>(
        raison,
      ),
    };

final comptaPilotageProvider =
    FutureProvider.autoDispose<SourcePilotage<ComptaPilotage>>((ref) async {
      final exercice = await ref.watch(exercicePilotageProvider.future);
      if (exercice is! SourceRecue<ExercicePilotage>) {
        return _reporter<ComptaPilotage>(exercice);
      }
      return ref.watch(pilotageApiProvider).indicateurs(exercice.donnee.id);
    });

final analytiquePilotageProvider =
    FutureProvider.autoDispose<SourcePilotage<AnalytiquePilotage>>((ref) async {
      final exercice = await ref.watch(exercicePilotageProvider.future);
      if (exercice is! SourceRecue<ExercicePilotage>) {
        return _reporter<AnalytiquePilotage>(exercice);
      }
      return ref.watch(pilotageApiProvider).analytique(exercice.donnee.id);
    });

/// La visibilité d'une carte « Par module » — `MenuLateral::peutVoirRoute` :
/// le droit de LECTURE du module, puis le masquage par rôle de la barre
/// latérale (`ROUTES_MASQUEES_PAR_ROLE`, le gérant ne voit pas Tourisme,
/// Véhicules, Personnel ni Clients). Une carte non autorisée n'est jamais
/// calculée puis masquée.
bool carteModuleVisible(Ref ref, ModuleTatacora module, String entreeMenu) {
  if (!ref.read(droitsProvider).peutLire(module)) return false;
  final role = ref.read(sessionProvider)?.role ?? '';
  return !entreeMasqueePourRole(role, entreeMenu);
}

/// La carte « Location de véhicules » (M8) — `Accueil::moduleVehicules`, sur
/// la fenêtre [aujourd'hui, aujourd'hui + 14 jours] de l'écran M8.
final vehiculesPilotageProvider = FutureProvider.autoDispose<ModuleVehicules?>((
  ref,
) async {
  if (!carteModuleVisible(
    ref,
    ModuleTatacora.m8Vehicules,
    'Véhicules & Locations',
  )) {
    return null;
  }
  final dao = ref.read(vehiculeDaoProvider);
  return moduleVehicules(
    parc: await dao.parc(),
    contrats: await dao.contrats(),
    aujourdhui: ref.read(horlogeTableauDeBordProvider)(),
  );
});

/// La carte « Tourisme & circuits » (M9) — `Accueil::moduleTourisme` : les
/// départs DÉRIVÉS de la fenêtre [aujourd'hui, aujourd'hui + 30 jours] de
/// l'écran M9, départs planifiés seulement (un départ annulé n'en est plus un),
/// agrégés par la MÊME fonction que la bande de l'écran ([agregerDeparts]).
final tourismePilotageProvider = FutureProvider.autoDispose<AgregatsDeparts?>((
  ref,
) async {
  if (!carteModuleVisible(ref, ModuleTatacora.m9Tourisme, 'Tourisme')) {
    return null;
  }
  final maintenant = ref.read(horlogeTableauDeBordProvider)();
  final debut = jourDe(maintenant);
  final lu = await ref
      .read(tourismeDaoProvider)
      .reservationsSurFenetre(
        debut,
        debut.add(const Duration(days: PeriodeTourisme.joursParDefaut)),
      );
  return agregerDeparts([
    for (final d in departsDerives(lu.reservations))
      if (!d.annule) d,
  ]);
});

/// La carte « Clients & créances » (M3) et le graphique « Créances par
/// ancienneté » — `Accueil::creancesParAnciennete` sur les créances du poste
/// (`creancesProvider`, le prédicat de `SoldeClientService`). `null` sans droit
/// de lecture sur M3 : la vue dit alors « Non consulté ».
final creancesAnciennetePilotageProvider =
    FutureProvider.autoDispose<List<TrancheCreance>?>((ref) async {
      if (!ref.read(droitsProvider).peutLire(ModuleTatacora.m3Crm)) return null;
      final creances = await ref.watch(creancesProvider.future);
      return creancesParAnciennete(
        creances,
        ref.read(horlogeTableauDeBordProvider)(),
      );
    });

/// L'état de stock — la même lecture que l'écran M6 (`StocksApi.etat`),
/// jamais un second calcul (PA-121).
final stockPilotageProvider = FutureProvider.autoDispose<ResultatStock>(
  (ref) => ref.watch(stocksApiProvider).etat(),
);

/// Le parc et les réservations — base locale, M1 est répliqué.
final parcPilotageProvider = FutureProvider.autoDispose<List<UniteHebergement>>(
  (ref) => ref.watch(depotReservationProvider).unites(),
);

final reservationsPilotageProvider =
    FutureProvider.autoDispose<List<Reservation>>(
      (ref) => ref.watch(depotReservationProvider).reservations(),
    );

/// La carte M1 — les MÊMES calculs que le panneau d'historique
/// (`KpisHistorique.calculer`), jamais une seconde dérivation (PA-121).
final kpisM1PilotageProvider = Provider.autoDispose<KpisHistorique?>((ref) {
  final reservations = ref.watch(reservationsPilotageProvider).value;
  if (reservations == null) return null;
  return KpisHistorique.calculer(
    filtrerHistorique(
      reservations,
      filtre: const FiltreHistorique(),
      maintenant: DateTime.now(),
    ),
  );
});

/// La carte POS — les ventes VALIDÉES d'aujourd'hui, par les calculs du
/// journal des ventes (`KpisJournalVentes.calculer`).
final ventesJourPilotageProvider = Provider.autoDispose<KpisJournalVentes?>((
  ref,
) {
  final journal = ref.watch(journalVentesProvider).value;
  if (journal == null) return null;
  final maintenant = DateTime.now();
  final jour = DateTime(maintenant.year, maintenant.month, maintenant.day);
  return KpisJournalVentes.calculer(
    filtrerVentes(journal.ventes, FiltreVentes(debut: jour, fin: jour)),
  );
});

/// Le motif affiché pour une source indisponible.
///
/// ⚠ Cette fonction portait la quatrième issue de PA-155 — un 401 sur un
/// poste dont le compte n'a pas de jumeau serveur — en la lisant dans
/// `etatJetonApiProvider`. Les deux ont disparu le 14/09/2026 avec la couche
/// réseau : **il n'y a plus de serveur, donc plus de jumeau, plus de 401 et
/// plus de session à expirer**. Le motif que porte la source est désormais le
/// seul qui existe, et il est écrit par `PilotageApi` lui-même.
///
/// Elle est conservée parce que ses quatre appelants disent la même chose au
/// même endroit : le jour où un client MECeF/DGI rétablira une source
/// distante, c'est ici que sa nuance se remettra, et à un seul endroit.
String motifRefusPilotage(SourceRefusee<Object?> refus) => refus.motif;

/* ====================================================================== */
/* Barre de filtres                                                        */
/* ====================================================================== */

/// « du / au / Exercice entier / Exporter » — la barre de filtres de la vue
/// d'accueil, panneau pilotage. (« PDF » jusqu'au 12/10/2026 : la vue écrit
/// « Exporter » depuis la dérogation du PO du 01/09/2026.)
///
/// ## Ce que fait le serveur (relu le 12/10/2026)
///
/// Les deux dates écrivent `du` et `au` ET basculent `filtrePeriode` sur
/// « personnalisee » ; « Exercice entier » fait `$set('filtrePeriode',
/// 'annee')`. `filtrePeriode` est LA période de tout le tableau de bord
/// (`Accueil::periode()` → `Periode::resoudre`) : ces bornes commandent la
/// bande, le chiffre d'affaires encaissé, la trésorerie, les alertes, le taux
/// d'occupation, les classements — pas seulement M10. ⚠ L'infobulle du
/// 12/10/2026 matin (« ces bornes ne commandaient que les indicateurs
/// comptables consolidés (M10) ») était FAUSSE et a été retirée (R2, D289).
///
/// ## Tout est porté depuis le 12/10/2026 (D296)
///
/// « Du » et « Au » écrivent la borne ET basculent la période sur « Période
/// personnalisée » ; « Exercice entier » la règle sur « Cette année »
/// (`Periode::annee()`, l'année civile ENTIÈRE). Le sélecteur de ce poste
/// porte désormais le registre CALENDAIRE de la vue (`Periode::resoudre`) :
/// l'écart « à date » / année civile nommé ici le matin du 12/10/2026 a
/// disparu, et la phrase « Période personnalisée : non portée » avec lui.
class _BarreFiltresPilotage extends ConsumerWidget {
  const _BarreFiltresPilotage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(periodeTableauDeBordProvider);
    final periodes = ref.read(periodeTableauDeBordProvider.notifier);
    final aujourdhui = ref.read(horlogeTableauDeBordProvider)();
    final etiquette = TextStyle(
      fontSize: TaillesContenu.t12,
      color: Ardoise.c500,
    );

    return Wrap(
      spacing: AppSpacing.sm, // gap-3
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // `<label class="text-[12px] text-slate-500">` puis l'`<input
        // type="date">` — les mêmes propriétés `du`/`au` que l'en-tête.
        Text('Du', style: etiquette),
        ChampDatePeriode(
          cle: const Key('pilotage-f-debut'),
          titre: 'Du',
          valeur: selection.du,
          initiale: aujourdhui,
          onChoix: periodes.saisirDu,
          onEffacer: periodes.viderDu,
        ),
        Text('Au', style: etiquette),
        ChampDatePeriode(
          cle: const Key('pilotage-f-fin'),
          titre: 'Au',
          valeur: selection.au,
          initiale: aujourdhui,
          onChoix: periodes.saisirAu,
          onEffacer: periodes.viderAu,
        ),
        InkWell(
          key: const Key('pilotage-btn-reset'),
          // `wire:click="$set('filtrePeriode', 'annee')"` : la période de TOUT
          // le tableau de bord, pas un filtre de cet onglet.
          onTap: () => ref
              .read(periodeTableauDeBordProvider.notifier)
              .definir(PeriodeTableauDeBord.annee),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, // px-3
              vertical: AppSpacing.xs, // py-2
            ),
            decoration: BoxDecoration(
              color: AppColors.neutre0,
              border: Border.all(color: Ardoise.c300),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Text(
              'Exercice entier',
              style: TextStyle(
                fontSize: TaillesContenu.t12,
                color: AppColors.anthracite,
              ),
            ),
          ),
        ),
        // « Exporter » (`pwa.export.bouton`), plus « PDF » : DÉROGATION du PO
        // du 01/09/2026, rappelée le 02/09/2026 (export unifié, registre
        // `DerogationsMaquette` : export_bouton_unique) — le bouton ouvre la
        // modale partagée, qui offre les deux formats, et « PDF » en promettait
        // un seul (accueil.blade.php l.867-873). Porté le 12/10/2026.
        //
        // Depuis le 14/10/2026 (lot D, D415) : `ouvrirExport('pdf')` puis
        // `genererExport`, le MÊME geste que l'« Exporter » de l'en-tête — la
        // SYNTHÈSE du tableau de bord, PDF présélectionné. Ce bouton produisait
        // l'état « Pilotage consolidé », que le serveur ne produit pas.
        InkWell(
          key: const Key('pilotage-btn-exporter'),
          onTap: () => exporterSyntheseAccueil(context, ref),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, // px-4
              vertical: AppSpacing.xs, // py-2
            ),
            decoration: BoxDecoration(
              color: AppColors.navy,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Text(
              TextesExport.bouton,
              style: TextStyle(
                fontSize: TaillesContenu.t13,
                fontWeight: FontWeight.w600,
                color: AppColors.neutre0,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// `wire:click="ouvrirExport('pdf')"` : la modale partagée (`modale-export`,
/// titre `accueil_pwa.export_titre`, sous-titre `modale_rapport.note`), le
/// PDF présélectionné, puis le document.
///
/// ⚠ Depuis le 14/10/2026 (lot D, D415), les DEUX boutons « Exporter » de la
/// vue — barre du pilotage et en-tête — appellent `exporterSyntheseAccueil`
/// (la synthèse de `genererExport`, comme le serveur). Cette action ne sert
/// plus que l'onglet du tableau croisé, qui la gardait déjà.
///
/// - **PDF Officiel A4** : l'état « Pilotage consolidé — tous modules »,
///   composé AU CLIC sur ce qui est affiché (PA-119) et remis à l'action
///   injectable [exporterEtatPilotagePdfProvider] (fenêtre « Enregistrer
///   sous »).
/// - **Tableur** : refusé, avec sa raison ([tableurPilotageNonProduit]),
///   comme le PDF l'est aux Notifications. Le seul document de ce poste porte
///   des montants MIS EN FORME (« 12 505 FCFA ») : en faire un CSV
///   enfreindrait la convention des tableurs (nombres bruts), et rien n'en
///   compose d'autre.
Future<void> exporterTableauDeBord(
  BuildContext context,
  WidgetRef ref, {
  required FenetreTableauDeBord? fenetre,
  required TableauDeBord? tableau,
}) async {
  final format = await choisirFormatExport(
    context,
    titre: titreExportPilotage,
    sousTitre: noteExportPilotage,
    aide: tableurPilotageNonProduit,
  );
  if (format == null || !context.mounted) return;

  switch (format) {
    case FormatExport.pdf:
      // ⚠ Défaut corrigé le 14/10/2026 (passe finale) : depuis D415, ce PDF
      // n'est plus produit que depuis l'onglet du TABLEAU CROISÉ, qui ne
      // regarde AUCUNE des sources du pilotage (comptabilité, analytique,
      // stock, créances, masse salariale, dépenses — toutes `autoDispose`).
      // `composerEtatPilotage` les lit par `.value` : sans lecteur, elles
      // valaient `null`, et le papier disait « Masse salariale non consultée
      // à l'édition » et « — » aux créances d'un compte qui a le droit et la
      // donnée — un état faux. On les tient en vie et on attend leur lecture
      // AVANT de composer ; une source en échec reste « non consultée ».
      final abonnements = [
        ref.listenManual(comptaPilotageProvider, (_, _) {}),
        ref.listenManual(analytiquePilotageProvider, (_, _) {}),
        ref.listenManual(stockPilotageProvider, (_, _) {}),
        ref.listenManual(creancesProvider, (_, _) {}),
        ref.listenManual(masseSalarialePilotageProvider, (_, _) {}),
        if (fenetre != null)
          ref.listenManual(depensesPilotageProvider(fenetre), (_, _) {}),
      ];
      try {
        await Future.wait<Object?>([
          for (final lecture in <Future<Object?>>[
            ref.read(comptaPilotageProvider.future),
            ref.read(analytiquePilotageProvider.future),
            ref.read(stockPilotageProvider.future),
            ref.read(creancesProvider.future),
            ref.read(masseSalarialePilotageProvider.future),
            if (fenetre != null)
              ref.read(depensesPilotageProvider(fenetre).future),
          ])
            lecture.then<Object?>((v) => v, onError: (Object _) => null),
        ]);
        if (!context.mounted) return;
        final etat = composerEtatPilotage(
          ref,
          fenetre: fenetre,
          tableau: tableau,
        );
        await executerExport(
          context,
          () => ref.read(exporterEtatPilotagePdfProvider)(etat),
          cleSucces: const Key('pilotage-export-fait'),
        );
      } finally {
        for (final a in abonnements) {
          a.close();
        }
      }
    case FormatExport.excel:
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              tableurPilotageNonProduit,
              key: Key('pilotage-export-tableur-absent'),
            ),
          ),
        );
  }
}

/// `accueil_pwa.export_titre` — le titre de la modale d'export de la vue
/// d'accueil, relu par PHP (`indicateurs_contre_serveur_test.dart`).
const String titreExportPilotage = 'Exporter le tableau de bord';

/// La note des rapports (clé `note` du bloc `modale_rapport` de la langue
/// d'accueil) — le sous-titre que la vue passe à la modale partagée
/// (l.1749), relu par PHP. Écrite sans le chemin complet de la clé : un
/// commentaire qui le porterait fournirait au comparateur un « libellé »
/// de la modale des rapports que rien ne rend.
const String noteExportPilotage =
    "Chaque rapport porte sur ce que cet écran affiche déjà. « État des stocks » et « État de créances » sont des états à l'instant : la période sélectionnée ne s'y applique pas. Les autres portent sur la période choisie en haut de page.";

/// Le refus du tableur, dit dans la modale (ligne d'aide) et au choix.
///
/// ÉCART — accueil.blade.php l.1748-1749 (modale partagée) et
/// `Accueil::genererExport` : la vue produit aussi un tableur. Ici : refusé.
/// Raison : le seul document du pilotage composé sur ce poste
/// ([EtatPilotage]) porte des montants mis en forme ; le serveur exporte un
/// « rapport » (`lignesRapport`, synthèse par défaut) qui n'est pas porté.
const String tableurPilotageNonProduit =
    "Le pilotage consolidé ne s'exporte qu'en PDF.";

/* ====================================================================== */
/* KPI consolidés                                                          */
/* ====================================================================== */

String _fcfa(String brut) =>
    formaterMontantDecimal(brut, suffixe: 'FCFA') ?? brut;

/// La valeur du stock telle que M11 la dit : le montant, et — seulement s'il y
/// a des articles sans coût — ce qu'il ne comprend pas.
String valeurStockPilotage(KpisStock k) => k.sansValorisation == 0
    ? _fcfa(k.valeurStock)
    : '${_fcfa(k.valeurStock)} (hors ${mentionStockSansCout(k)})';

/// Les clés des trois indicateurs M11 que le pilotage reprend de la bande —
/// celles de `TableauDeBordService::indicateurs()`.
const String cleChiffreAffairesEncaisse = 'chiffre_affaires_encaisse';
const String cleTresorerieCaisse = 'tresorerie_caisse';
const String cleValeurStock = 'valeur_stock';

/// `accueil_pwa.pilotage.resultat_net_source` — le détail de la carte
/// « Résultat net » quand la comptabilité n'a pas été lue.
const String comptabiliteNonConsultee = 'Comptabilité non consultée';

/// La valeur AFFICHÉE d'un indicateur de la bande, pour une carte du
/// pilotage : la même chaîne que la carte de la bande (une seule mise en
/// forme, `valeurIndicateurAffichee`), ou `null` — « Non consulté » — quand la
/// bande n'a pas été reçue ou que l'indicateur n'y est pas établi. Jamais un
/// zéro à la place (Article 7). L'écran ET le PDF passent par ici.
String? valeurPilotageDeLaBande(TableauDeBord? tableau, String cle) {
  final indicateur = tableau?.parCle(cle);
  if (indicateur == null || !indicateur.estDisponible) return null;
  return valeurIndicateurAffichee(indicateur);
}

/// La ligne « Valeur au coût moyen » de la carte Stocks (M6) : la valeur de la
/// BANDE (D399), suivie de ce qu'elle ne comprend pas — « (hors 2 article(s)
/// sans coût) » (D119) —, « — » quand la bande ne l'établit pas.
String valeurStockDuModule(TableauDeBord? tableau) {
  final valeur = valeurPilotageDeLaBande(tableau, cleValeurStock);
  if (valeur == null) return '—';
  final mention = tableau?.parCle(cleValeurStock)?.mention;
  // La mention porte déjà son « hors » (« hors 2 article(s) sans coût »).
  return mention == null || mention.isEmpty ? valeur : '$valeur ($mention)';
}

/// Les six cartes du `#kpis` — `m11-pilotage.js`, `rendreKpis`.
///
/// `grid grid-cols-2 sm:grid-cols-3 xl:grid-cols-6` : « à lg, six colonnes
/// laissaient 122 px de contenu utile par carte — insuffisant pour un montant
/// à 17 px gras » (commentaire du maître, l.172-175).
class _GrilleKpisPilotage extends ConsumerWidget {
  const _GrilleKpisPilotage({
    required this.tableau,
    required this.bandeEnChargement,
  });

  final TableauDeBord? tableau;
  final bool bandeEnChargement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compta = _valeurSource(ref.watch(comptaPilotageProvider));

    final donnee = compta is SourceRecue<ComptaPilotage> ? compta.donnee : null;

    final tresorerie = tableau?.parCle(cleTresorerieCaisse);
    final stock = tableau?.parCle(cleValeurStock);

    final cartes = <Widget>[
      // Carte 1 — libellé `kpi.chiffre_affaires_encaisse.libelle`, valeur
      // `$indicateurs['chiffre_affaires_encaisse']`, détail
      // `$periode->libelle()`. L'indicateur M11 de la BANDE, pas une lecture
      // M10 : jusqu'au 12/10/2026 la carte lisait `PilotageApi` et affichait
      // « indisponible » sur un chiffre que le poste calcule depuis D234
      // (réserve R1 du contrôle, BLOQUANTE).
      _CarteKpi(
        cle: const Key('pilotage-kpi-ca'),
        libelle: EcranTableauDeBord.libelles[cleChiffreAffairesEncaisse]!,
        valeur: valeurPilotageDeLaBande(tableau, cleChiffreAffairesEncaisse),
        texteVide: bandeEnChargement ? 'Chargement…' : 'Non consulté',
        detail: bandeEnChargement ? '' : (tableau?.libellePeriode ?? '—'),
      ),
      // Carte 2 — la seule des trois qui relève de M10 (`$comptables`). Les
      // mots de la vue : « Non consulté » et « Comptabilité non consultée » ;
      // la raison datée les suit, parce que « non consultée » ne dit pas
      // POURQUOI (`PilotageApi.raisonAbsence`).
      _CarteKpi(
        cle: const Key('pilotage-kpi-resultat'),
        libelle: 'Résultat net',
        valeur: donnee == null ? null : _fcfa(donnee.resultatNet),
        accent: donnee == null
            ? null
            : (donnee.resultatNegatif
                  ? PaletteMaitre.rouge600
                  : PaletteMaitre.emeraude600),
        detail: switch (compta) {
          // PA-49 : l'intitulé dit ce qui est réellement calculé. Tant que
          // rien n'est comptabilisé en classe 89, c'est un résultat AVANT
          // impôt (`accueil_pwa.pilotage.avant_impot` / `exercice`).
          SourceRecue<ComptaPilotage>(:final donnee) =>
            donnee.impotNonComptabilise
                ? 'Exercice ${donnee.annee} · avant impôt'
                : 'Exercice ${donnee.annee}',
          SourceRefusee<ComptaPilotage> r =>
            '$comptabiliteNonConsultee — ${motifRefusPilotage(r)}',
          SourceInjoignable<ComptaPilotage>() => comptabiliteNonConsultee,
          SourceAbsente<ComptaPilotage>(:final raison) =>
            '$comptabiliteNonConsultee — $raison',
          null => 'Chargement…',
        },
      ),
      // Carte 3 — libellé `kpi.tresorerie_caisse.libelle`, valeur
      // `$indicateurs['tresorerie_caisse']` (rouge si négative), détail
      // `kpi.tresorerie_caisse.note`. Même correction que la carte 1.
      _CarteKpi(
        cle: const Key('pilotage-kpi-tresorerie'),
        libelle: EcranTableauDeBord.libelles[cleTresorerieCaisse]!,
        valeur: valeurPilotageDeLaBande(tableau, cleTresorerieCaisse),
        accent:
            tresorerie != null &&
                tresorerie.estDisponible &&
                tresorerie.valeur.startsWith('-')
            ? PaletteMaitre.rouge600
            : null,
        texteVide: bandeEnChargement ? 'Chargement…' : 'Non consulté',
        detail: bandeEnChargement
            ? ''
            : (tresorerie == null
                  ? '—'
                  : (tresorerie.raisonAbsence ??
                        EcranTableauDeBord.notes[cleTresorerieCaisse]!)),
      ),
      _carteCreances(ref.watch(creancesProvider)),
      _carteMasseSalariale(ref.watch(masseSalarialePilotageProvider)),
      // Carte 5 — libellé `kpi.valeur_stock.libelle`, valeur
      // `$indicateurs['valeur_stock']`, accent '' (navy), détail
      // `kpi.valeur_stock.note` (accueil.blade.php l.928-933). L'indicateur
      // M11 de la BANDE, par la même voie que les cartes 1 et 3 : jusqu'au
      // 12/10/2026 la carte lisait l'état M6 (`stockPilotageProvider`), avec
      // un détail « N référence(s) · N sous seuil » et un accent ambre que la
      // vue ne porte pas (réserve 6 du recontrôle).
      //
      // ÉCART DÉLIBÉRÉ — accueil.blade.php l.932.
      // La vue : le détail est la note seule.
      // Ici : la note, puis « · hors N article(s) sans coût » quand des
      // articles en stock n'ont aucune entrée valorisée — la note de la carte
      // de la bande, mot pour mot (`noteIndicateurAffichee`).
      // Raison : D119 — un article sans coût compte pour zéro franc dans la
      // somme ; un chiffre minoré qui ne le dit pas se lit comme exact, sur
      // l'écran où l'on décide. Sans article sans coût, le détail est celui
      // de la vue au mot.
      _CarteKpi(
        cle: const Key('pilotage-kpi-stock'),
        libelle: EcranTableauDeBord.libelles[cleValeurStock]!,
        valeur: valeurPilotageDeLaBande(tableau, cleValeurStock),
        texteVide: bandeEnChargement ? 'Chargement…' : 'Non consulté',
        detail: bandeEnChargement
            ? ''
            : (stock == null ? '—' : noteIndicateurAffichee(stock)),
      ),
    ];

    return LayoutBuilder(
      builder: (context, contraintes) {
        final colonnes = contraintes.maxWidth >= AppBreakpoints.xl
            ? 6
            : (contraintes.maxWidth >= AppBreakpoints.sm ? 3 : 2);
        final largeur =
            (contraintes.maxWidth - AppSpacing.sm * (colonnes - 1)) / colonnes;
        return Wrap(
          spacing: AppSpacing.sm, // gap-3
          runSpacing: AppSpacing.sm,
          children: [
            for (final carte in cartes) SizedBox(width: largeur, child: carte),
          ],
        );
      },
    );
  }
}

/// La sixième carte du maître : « Masse salariale ».
///
/// Trois états qui ne se disent pas pareil (`accueil.blade.php`) : droit M13
/// absent -> « Non consulté » ; droit présent mais AUCUN bulletin établi ce
/// mois-ci -> « Aucun bulletin établi ce mois-ci » (une paie non encore
/// établie, pas une masse salariale nulle) ; sinon le brut des bulletins.
Widget _carteMasseSalariale(AsyncValue<TotauxLivre?> masse) {
  const cle = Key('pilotage-kpi-masse-salariale');
  const libelle = 'Masse salariale';
  return switch (masse) {
    AsyncData(:final value) when value == null => const _CarteKpi(
      cle: cle,
      libelle: libelle,
      valeur: null,
      texteVide: 'Non consulté',
      // ÉCART DÉLIBÉRÉ (10/10/2026, D174) — `accueil.blade.php` l.944.
      // La vue : `$paie['effectif'] ?? 0` écrit « 0 salarié(s) · coût réel non
      // arrêté » sous « Non consulté ».
      // Ici : « — ».
      // Raison : un « 0 » sur une source NON LUE est un zéro plausible ; la vue
      // contredit sa propre règle (l.1197 : jamais de zéro sur une lecture qui
      // n'a pas eu lieu).
      detail: '—',
    ),
    AsyncData(:final value) when value!.effectif == 0 => const _CarteKpi(
      cle: cle,
      libelle: libelle,
      valeur: null,
      texteVide: 'Aucun bulletin établi ce mois-ci',
      detail: '0 salarié(s) · coût réel non arrêté',
    ),
    AsyncData(:final value) => _CarteKpi(
      cle: cle,
      libelle: libelle,
      valeur: _fcfa('${value!.brut}'),
      detail: '${value.effectif} salarié(s) · coût réel non arrêté',
    ),
    AsyncError() => const _CarteKpi(
      cle: cle,
      libelle: libelle,
      valeur: null,
      texteVide: 'Non lue',
      detail: 'La masse salariale n’a pas pu être lue.',
    ),
    _ => const _CarteKpi(
      cle: cle,
      libelle: libelle,
      valeur: null,
      texteVide: 'Chargement…',
      detail: '',
    ),
  };
}

/// La carte « Créances clients » — `accueil.blade.php`, `$carteKpi(
/// __('accueil_pwa.pilotage.creances_clients'), MontantFcfa::format(
/// $creances['total_du']), '', __('accueil_pwa.creances.pieces', …))`.
///
/// Depuis le lot 5 (12/10/2026, D234) le poste ÉCRIT les encaissements
/// (`PaiementsFactureDao`) : le reste dû de chaque facture est établi par la
/// formule unique de `creances.dart`, et le total est `totauxCreances` — celui
/// de Clients & créances, de la bande M11 et de l'état M14. Jusque-là la carte
/// disait « indisponible » parce qu'aucun paiement n'était écrit ; cette
/// prémisse est tombée (réserve R-A du recontrôle du lot 7, D282).
Widget _carteCreances(AsyncValue<List<CreanceFacture>> creances) {
  const cle = Key('pilotage-kpi-creances');
  const libelle = 'Créances clients';
  return switch (creances) {
    AsyncData(:final value) => switch (totauxCreances(value)) {
      final t => _CarteKpi(
        cle: cle,
        libelle: libelle,
        valeur: _fcfa(centiemesEnChaine(t.totalDuCentimes)),
        detail: piecesNonSoldeesPilotage(t.nbPieces, t.nbClients),
      ),
    },
    AsyncError() => const _CarteKpi(
      cle: cle,
      libelle: libelle,
      valeur: null,
      texteVide: 'Non lue',
      detail: 'Les créances n’ont pas pu être lues.',
    ),
    _ => const _CarteKpi(
      cle: cle,
      libelle: libelle,
      valeur: null,
      texteVide: 'Chargement…',
      detail: '',
    ),
  };
}

/// `accueil_pwa.creances.pieces` — « :nombre pièce(s) non soldée(s) chez
/// :clients client(s) ».
String piecesNonSoldeesPilotage(int pieces, int clients) =>
    '$pieces pièce(s) non soldée(s) chez $clients client(s)';

SourcePilotage<ComptaPilotage>? _valeurSource(
  AsyncValue<SourcePilotage<ComptaPilotage>> async,
) => async.value;

/// Une carte KPI de la vue (`$carteKpi`).
///
/// `valeur: null` rend le mot de la vue — « Non consulté »
/// (`accueil_pwa.non_consulte`), en gris pâle — jamais 0 F, qui se lit comme
/// un vrai chiffre. (« indisponible », le mot de l'ancien maître, a été
/// remplacé le 12/10/2026 : la vue fait foi, PA-183.)
class _CarteKpi extends StatelessWidget {
  const _CarteKpi({
    required Key cle,
    required this.libelle,
    required this.valeur,
    required this.detail,
    this.accent,
    this.texteVide = 'Non consulté',
  }) : super(key: cle);

  final String libelle;
  final String? valeur;

  /// Le texte d'une valeur absente — « Non consulté » par défaut, ou une
  /// absence RÉELLE nommée (« Aucun bulletin établi ce mois-ci »).
  final String texteVide;
  final String detail;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md), // p-4
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        border: Border.all(color: AppColors.neutre200),
        borderRadius: BorderRadius.circular(AppRadius.xl), // rounded-xl
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            libelle.toUpperCase(),
            style: TextStyle(
              fontSize: TaillesContenu.t11,
              fontWeight: FontWeight.w600,
              // `tracking-wide` = 0,025em, multiplié par la taille (R8) : la
              // valeur en dur 0.6 n'était pas celle de la vue — 0,2625 px, car
              // `text-[11px]` rend à 10,5 px dans `<main>` (`TaillesContenu.t11`).
              letterSpacing: TaillesContenu.t11 * AppTextStyles.suiviLarge,
              color: Ardoise.c400,
            ),
          ),
          const SizedBox(height: AppSpacing.unit),
          Text(
            valeur ?? texteVide,
            // `break-words` du maître : un montant long passe à la ligne au
            // lieu de sortir du cadre — « un montant tronqué est un montant
            // faux, et il ne se voit pas ».
            softWrap: true,
            style: TextStyle(
              fontSize: TaillesContenu.t17,
              fontWeight: FontWeight.bold,
              // `leading-tight` = 1,25 (R8 ; la valeur en dur était 1.2).
              height: Tailles.interligneSerre,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: valeur == null ? Ardoise.c300 : (accent ?? AppColors.navy),
            ),
          ),
          const SizedBox(height: AppSpacing.unit),
          Text(
            detail,
            style: TextStyle(
              fontSize: TaillesContenu.t11,
              // `leading-snug` = 1,375 (R8 ; la valeur en dur était 1.35).
              height: Tailles.interligneSnug,
              color: Ardoise.c400,
            ),
          ),
        ],
      ),
    );
  }
}

/* ====================================================================== */
/* À traiter                                                               */
/* ====================================================================== */

enum _GraviteAlerte { rouge, amber, info }

final class _Alerte {
  const _Alerte(this.gravite, this.titre, this.detail);

  final _GraviteAlerte gravite;
  final String titre;
  final String detail;
}

/// « À traiter » — `Accueil::alertesPilotage` du serveur, réplique.
///
/// ## Cinq familles, dans l'ORDRE du serveur, chacune derrière son droit
///
/// 1. M10 — comptabilité déséquilibrée, brouillons : non évaluées sur ce poste
///    (aucun compte de résultat ni balance n'y est calculé), et une ligne
///    grise le dit avec sa raison datée.
/// 2. M3 — « :montant de créances clients » (ambre), si le rôle LIT M3 et si
///    le total dû est STRICTEMENT positif (`bccomp(total_du, '0.00') === 1`) ;
///    détail `accueil_pwa.creances.pieces`. Total = `totauxCreances`, celui de
///    la carte « Créances clients » — une formule.
/// 3. M11 — « :nombre facture(s) non soldée(s) » (ambre) et « :nombre
///    réservation(s) en attente » (info), si la bande a été reçue et si chaque
///    nombre est > 0 ; détails = notes des deux indicateurs. Les nombres sont
///    CEUX DE LA BANDE (même fenêtre), comme le serveur relit `$indicateurs`.
/// 4. M6 — articles critiques (ambre), titre du serveur
///    (`alertes.stock_critique`), si le rôle LIT M6 ; le compte est celui de
///    `Accueil::articlesCritiques()` — TOUS les articles dont le solde est au
///    seuil ou dessous, journaliers compris, plafonné à 50 — et non le
///    « sous seuil » de l'écran Stocks (D298).
///
/// ⚠ Aucun tri : le serveur rend ses alertes dans l'ordre d'insertion, et
/// l'alerte de stock (ambre) vient APRÈS les réservations en attente (info).
/// La vue affirme pourtant en commentaire « dans l'ordre de gravité du
/// maître » — incohérence du SERVEUR, répliquée et notée (D289), jamais
/// corrigée ici seul. Le tri par gravité que ce poste appliquait a été retiré.
///
/// ## « Aucune alerte » n'est jamais « tout va bien »
///
/// Le message vide est celui de la vue, QUALIFIÉ : « Aucune alerte
/// opérationnelle sur les sources consultées. », suivi du compte « N
/// source(s) consultée(s) sur 4 ». Il remplace le « Rien à traiter — tous les
/// indicateurs sont au vert » du prototype, qui affirmait un état non vérifié
/// (PA-59/60/61). Une source non lue pour une autre raison que le droit garde
/// sa ligne grise, avec sa raison.
///
/// ⚠ Revu le 12/10/2026 (R3, D289) : ce commentaire disait que les créances
/// n'avaient « aucun calcul serveur » ; faux — `SoldeClientService::totaux()`
/// les calcule, et ce poste aussi depuis le lot 5 (D234).
class _CarteATraiter extends ConsumerWidget {
  const _CarteATraiter({required this.tableau});

  final TableauDeBord? tableau;

  /// Les sources que la vue sait lire : M10, M3, M11, M6
  /// (`$possibles` de `alertesPilotage`).
  static const int sourcesPossibles = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compta = ref.watch(comptaPilotageProvider).value;
    final stock = ref.watch(stockPilotageProvider).value;
    final creances = ref.watch(creancesProvider);
    final droits = ref.watch(droitsProvider);

    final alertes = <_Alerte>[];
    final indisponibles = <String>[];
    var sourcesLues = 0;
    // `$articlesCritiques->isNotEmpty()` : le bouton « Voir les articles ».
    var critiquesPilotage = 0;

    // --- M10 -------------------------------------------------------------
    switch (compta) {
      case SourceRecue<ComptaPilotage>(:final donnee):
        sourcesLues++;
        if (!donnee.equilibre) {
          // `accueil_pwa.alertes.compta_desequilibree` et `…_detail`, au mot
          // (apostrophes droites de la vue). UNE alerte, comme la vue : le
          // serveur combine balance et bilan dans un seul champ `equilibre`.
          alertes.add(
            const _Alerte(
              _GraviteAlerte.rouge,
              'Comptabilité déséquilibrée',
              "Aucun état financier n'est exploitable tant que l'écart "
                  'subsiste. Vérifiez la balance générale.',
            ),
          );
        }
        if (donnee.brouillons > 0) {
          alertes.add(
            _Alerte(
              _GraviteAlerte.amber,
              // `accueil_pwa.alertes.brouillons` / `brouillons_detail`.
              '${donnee.brouillons} écriture(s) en brouillon',
              "Elles n'entrent dans aucun état et bloqueront la clôture.",
            ),
          );
        }
      case SourceRefusee<ComptaPilotage> r:
        indisponibles.add(
          'Comptabilité — alertes non évaluées : '
          '${motifRefusPilotage(r)}',
        );
      case SourceInjoignable<ComptaPilotage>():
        indisponibles.add(
          'Comptabilité — alertes non évaluées : serveur injoignable.',
        );
      case SourceAbsente<ComptaPilotage>(:final raison):
        indisponibles.add('Comptabilité — alertes non évaluées : $raison');
      case null:
        indisponibles.add('Comptabilité — chargement…');
    }

    // --- M3 : créances clients ---------------------------------------------
    // Le droit d'abord : sans lecture de M3, la source n'est ni lue ni
    // comptée, et aucune alerte n'en sort (comme `peutLire(MODULE_CLIENT)`).
    if (droits.peutLire(ModuleTatacora.m3Crm)) {
      switch (creances) {
        case AsyncData(:final value):
          sourcesLues++;
          final t = totauxCreances(value);
          // `bccomp($creances['total_du'], '0.00', 2) === 1` : STRICTEMENT
          // positif — un total nul n'est pas une créance à traiter.
          if (t.totalDuCentimes > 0) {
            alertes.add(
              _Alerte(
                _GraviteAlerte.amber,
                alerteCreancesClients(
                  _fcfa(centiemesEnChaine(t.totalDuCentimes)),
                ),
                piecesNonSoldeesPilotage(t.nbPieces, t.nbClients),
              ),
            );
          }
        case AsyncError():
          indisponibles.add(
            'Créances — alertes non évaluées : les créances n’ont pas pu être '
            'lues.',
          );
        default:
          indisponibles.add('Créances — chargement…');
      }
    }

    // --- M11 : factures non soldées, réservations à confirmer ----------------
    // Les deux viennent de la BANDE déjà calculée, sur sa fenêtre : les
    // relire ferait deux formules qui finiraient par diverger (PA-121).
    final bande = tableau;
    if (bande != null) {
      sourcesLues++;
      final factures = _nombreDeLaBande(bande, 'factures_impayees');
      if (factures > 0) {
        alertes.add(
          _Alerte(
            _GraviteAlerte.amber,
            alerteFacturesNonSoldees(factures),
            EcranTableauDeBord.notes['factures_impayees']!,
          ),
        );
      }
      final enAttente = _nombreDeLaBande(bande, 'reservations_en_attente');
      if (enAttente > 0) {
        alertes.add(
          _Alerte(
            _GraviteAlerte.info,
            alerteReservationsEnAttente(enAttente),
            EcranTableauDeBord.notes['reservations_en_attente']!,
          ),
        );
      }
    }

    // --- M6 : articles critiques ---------------------------------------------
    // Le droit d'abord, comme `peutLire(MODULE_STOCKS)` : sans lecture de M6,
    // la source n'est ni lue, ni comptée, ni NOMMÉE — le serveur n'affiche
    // aucune ligne « non évaluée » pour un module que le rôle ne lit pas.
    // Le compte est celui de `Accueil::articlesCritiques()` (confronté par PHP),
    // pas `kpis.sousSeuil` de M6 : voir [nombreArticlesCritiques].
    if (droits.peutLire(ModuleTatacora.m6Stocks)) {
      switch (stock) {
        case StockRecu(:final etat):
          sourcesLues++;
          final critiques = nombreArticlesCritiques(etat.lignes);
          critiquesPilotage = critiques;
          if (critiques > 0) {
            alertes.add(
              _Alerte(
                _GraviteAlerte.amber,
                // `accueil_pwa.alertes.stock_critique` / `stock_critique_detail`.
                '$critiques article(s) sous le seuil de réapprovisionnement',
                'Réapprovisionnement à déclencher.',
              ),
            );
          }
        // `StocksApi.etat` ne refuse que sans droit de lecture, écarté
        // ci-dessus ; la branche reste pour l'exhaustivité du registre.
        case StockRefuse(:final motif):
          indisponibles.add('Stocks — alertes non évaluées : $motif');
        case StockInjoignable():
          indisponibles.add(
            'Stocks — alertes non évaluées : le stock n’a pas pu être lu.',
          );
        case null:
          indisponibles.add('Stocks — chargement…');
      }
    }

    // AUCUN tri : l'ordre d'insertion est celui du serveur (voir l'en-tête).

    return _CadreCarte(
      entete: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'À traiter',
            style: TextStyle(
              fontSize: TaillesContenu.t14,
              fontWeight: FontWeight.bold,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: AppSpacing.demi),
          Text(
            'Alertes opérationnelles, tous modules confondus.',
            style: TextStyle(fontSize: TaillesContenu.t11, color: Ardoise.c400),
          ),
        ],
      ),
      enfant: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // `@empty` : `accueil_pwa.alertes.aucune`, `px-4 py-4 text-[13px]
          // text-slate-500` — qualifié « sur les sources consultées », jamais
          // un vert inconditionnel.
          if (alertes.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                'Aucune alerte opérationnelle sur les sources consultées.',
                key: const Key('pilotage-alertes-aucune'),
                style: TextStyle(
                  fontSize: TaillesContenu.t13,
                  color: Ardoise.c500,
                ),
              ),
            ),
          for (final (index, a) in alertes.indexed)
            _LigneAlerte(key: Key('pilotage-alerte-$index'), alerte: a),
          for (final (index, message) in indisponibles.indexed)
            Padding(
              key: Key('pilotage-alertes-indisponible-$index'),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Text(
                message,
                style: TextStyle(
                  fontSize: TaillesContenu.t11_5,
                  color: Ardoise.c500,
                ),
              ),
            ),
          // `accueil_pwa.alertes.sources`, `px-4 py-3 text-[11px]
          // text-slate-400`.
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Text(
              sourcesConsulteesPilotage(sourcesLues, sourcesPossibles),
              key: const Key('pilotage-alertes-sources'),
              style: TextStyle(
                fontSize: TaillesContenu.t11,
                color: Ardoise.c400,
              ),
            ),
          ),
          // `@if ($articlesCritiques->isNotEmpty())` : `px-4 pb-4`, un bouton
          // `text-[12px] font-semibold px-3 py-1.5 rounded-lg border
          // border-slate-200` qui ouvre la modale des articles sous le seuil
          // (`$set('etatFormulaire', 'stocks-critiques')`) — 13/10/2026,
          // INSTRUCTION1.txt du PO (§2.C « Voir les articles »).
          if (critiquesPilotage > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  key: const Key('pilotage-voir-articles'),
                  onTap: () => ouvrirModaleStocksCritiques(context),
                  borderRadius: BorderRadius.circular(AppRadius.roundedLg),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Ardoise.c200),
                      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
                    ),
                    child: Text(
                      'Voir les articles',
                      style: TextStyle(
                        fontSize: TaillesContenu.t12,
                        fontWeight: FontWeight.w600,
                        color: Ardoise.c700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Un indicateur NOMBRE de la bande, en entier — `(int) $indicateurs[…]
  /// ['valeur']`. Absent ou non établi : 0, donc aucune alerte (le serveur
  /// n'en émet que sur un nombre > 0).
  static int _nombreDeLaBande(TableauDeBord bande, String cle) {
    final i = bande.parCle(cle);
    if (i == null || !i.estDisponible) return 0;
    return int.tryParse(i.valeur) ?? 0;
  }
}

/// `accueil_pwa.alertes.creances` — « :montant de créances clients ».
String alerteCreancesClients(String montant) => '$montant de créances clients';

/// `accueil_pwa.alertes.factures_non_soldees`.
String alerteFacturesNonSoldees(int nombre) =>
    '$nombre facture(s) non soldée(s)';

/// `accueil_pwa.alertes.reservations_en_attente`.
String alerteReservationsEnAttente(int nombre) =>
    '$nombre réservation(s) en attente';

/// `accueil_pwa.alertes.sources`.
String sourcesConsulteesPilotage(int lues, int total) =>
    '$lues source(s) consultée(s) sur $total — celles que votre rôle vous '
    'donne le droit de lire.';

class _LigneAlerte extends StatelessWidget {
  const _LigneAlerte({super.key, required this.alerte});

  final _Alerte alerte;

  @override
  Widget build(BuildContext context) {
    // Les trois teintes du maître : point coloré + titre foncé.
    final (point, titre) = switch (alerte.gravite) {
      _GraviteAlerte.rouge => (PaletteMaitre.rouge600, PaletteMaitre.rouge900),
      _GraviteAlerte.amber => (AppColors.gold, PaletteMaitre.ambre900),
      _GraviteAlerte.info => (Ardoise.c500, Ardoise.c700),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md, // px-4
        vertical: AppSpacing.sm, // py-3
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Ardoise.c100)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Container(
              width: AppSpacing.xs,
              height: AppSpacing.xs,
              decoration: BoxDecoration(color: point, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alerte.titre,
                  style: TextStyle(
                    fontSize: TaillesContenu.t13,
                    fontWeight: FontWeight.w600,
                    color: titre,
                  ),
                ),
                const SizedBox(height: AppSpacing.demi),
                Text(
                  alerte.detail,
                  style: TextStyle(
                    fontSize: TaillesContenu.t11_5,
                    color: Ardoise.c500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/* ====================================================================== */
/* Ce que ces chiffres ne disent pas                                       */
/* ====================================================================== */

final class _Reserve {
  const _Reserve({
    required this.titre,
    required this.detail,
    required this.module,
  });

  final String titre;
  final String detail;
  final String module;
}

/// « Ce que ces chiffres ne disent pas » — la section qui compte, d'après le
/// maître lui-même : « un tableau de bord qui agrège sept modules en six
/// cases propres, sans dire lesquelles reposent sur une estimation, est plus
/// dangereux qu'aucun tableau de bord ».
///
/// ## Un refus déclaré vit ici — maitre-refuse:tableau-de-bord#reserve-lignes-non-ventilees
///
/// ÉCART DÉLIBÉRÉ — `m11-pilotage.js`, `rendreReserves`.
/// Le prototype : la réserve « N ligne(s) sans centre analytique — X F
/// échappent à la ventilation par activité (RG-12) ».
/// Ici : jamais rendue.
/// Raison : impossible par construction — `ecritures_comptables.centre_id`
/// est NOT NULL (RG-12 tenue par la base), et le serveur refuse lui-même
/// d'exposer ce compteur : « il serait bloqué à zéro par construction et
/// rassurerait sans jamais rien mesurer (PA-59/60/61) »
/// (`AnalytiqueResource`, lu le 27/08/2026 — `ventilation_garantie_par_schema`
/// nomme la raison à sa place).
///
/// ## Cinq réserves du maître attendent leur source, nommées ici
///
/// « Coût employeur non arrêté » (PA-53 — aucune route M13), « N article(s)
/// vendus à un prix provisoire » et « N article(s) sans prix » (aucun drapeau
/// de prix provisoire au schéma serveur de la carte), « N vente(s) sans
/// impact sur le stock » (les fiches techniques ne sont pas répliquées,
/// PA-134), « N départ(s) à durée indéterminée » (la lecture de
/// `circuits.duree` vit au serveur, PA-51 — la rejouer ici en divergerait),
/// « Matrice RBAC amendée » (le serveur n'expose pas d'état d'amendement).
class _CarteReserves extends StatelessWidget {
  const _CarteReserves();

  /// Les QUATRE réserves de la vue, dans son ordre et à ses mots
  /// (`accueil.blade.php` l.1025-1030, `accueil_pwa.reserves.*`) : la vue les
  /// rend TOUJOURS, sans condition (13/10/2026, INSTRUCTION1.txt du PO §2.D).
  ///
  /// ## Un écart, nommé (piège 13, décision D276)
  ///
  /// La troisième dit, au serveur : « Recouvrements partiels non enregistrés —
  /// Les encaissements partiels ne sont pas enregistrés : le montant dû affiché
  /// est un maximum. » C'est FAUX sur ce poste depuis le lot 5 (12/10/2026) :
  /// `PaiementsFactureDao` enregistre chaque encaissement, partiel compris, et
  /// le reste dû les déduit (`creances.dart`). C'est faux au serveur aussi
  /// (`EncaissementFactureService`, PA-165). Une phrase fausse sur de l'argent
  /// ne s'affiche pas : la VRAIE la remplace, avec le maximum des mots de la
  /// vue, et l'Architecte est saisi. Un test épingle la phrase de la vue à la
  /// source (il rougira le jour où elle sera corrigée) et refuse la fausse dans
  /// le code rendu.
  static const List<_Reserve> reserves = [
    _Reserve(
      titre: 'Résultat affiché avant impôt',
      detail:
          // Guillemets SIMPLES partout : le comparateur de la vue ne recolle que
          // des morceaux d'une même sorte de guillemets.
          'Impôt sur les bénéfices : le taux d\'IS n\'est pas encore arrêté. '
          'Aucun résultat net n\'est affiché ici — seule la marge brute de la '
          'période.',
      module: 'Comptabilité',
    ),
    _Reserve(
      titre: 'Charges de structure non réparties',
      detail:
          'Charges de structure non réparties : « Dépenses cumulées » est le '
          'total des charges validées, il n\'est ventilé par activité nulle '
          'part.',
      module: 'Analytique',
    ),
    _Reserve(
      titre: 'Recouvrements partiels enregistrés',
      detail:
          'Les encaissements partiels sont enregistrés : le montant dû affiché '
          'est déjà diminué des paiements reçus.',
      module: 'Créances',
    ),
    _Reserve(
      titre: 'Valeur du stock non comparable',
      detail:
          'La valeur du stock est une photographie à l\'instant : elle ne se '
          'compare pas à la période précédente, et aucune variation n\'est '
          'affichée pour elle.',
      module: 'Stocks',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return _CadreCarte(
      // L'en-tête ambré du maître (`background:#FFFBEB`, texte `#78350F`).
      fondEntete: PaletteMaitre.ambre50,
      entete: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ce que ces chiffres ne disent pas',
            style: TextStyle(
              fontSize: TaillesContenu.t14,
              fontWeight: FontWeight.bold,
              color: PaletteMaitre.ambre900,
            ),
          ),
          const SizedBox(height: AppSpacing.demi),
          Text(
            'Incertitudes déclarées par les moteurs eux-mêmes. Un tableau de '
            'bord qui les masquerait serait plus dangereux qu\'utile.',
            style: TextStyle(
              fontSize: TaillesContenu.t11,
              color: PaletteMaitre.ambre900,
            ),
          ),
        ],
      ),
      enfant: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, r) in reserves.indexed)
            _LigneReserve(key: Key('pilotage-reserve-$index'), reserve: r),
        ],
      ),
    );
  }
}

class _LigneReserve extends StatelessWidget {
  const _LigneReserve({required this.reserve, super.key});

  final _Reserve reserve;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Ardoise.c100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  reserve.titre,
                  style: TextStyle(
                    fontSize: TaillesContenu.t13,
                    fontWeight: FontWeight.w600,
                    color: PaletteMaitre.ambre900,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _BadgeModule(reserve.module),
            ],
          ),
          const SizedBox(height: AppSpacing.unit),
          Text(
            reserve.detail,
            style: TextStyle(
              fontSize: TaillesContenu.t11_5,
              color: Ardoise.c500,
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeModule extends StatelessWidget {
  const _BadgeModule(this.module);

  final String module;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.xxs, // px-1.5
      vertical: AppSpacing.demi, // py-0.5
    ),
    decoration: BoxDecoration(
      color: Ardoise.c100,
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
    child: Text(
      module,
      style: TextStyle(fontSize: TaillesContenu.t10, color: Ardoise.c500),
    ),
  );
}

/* ====================================================================== */
/* Graphiques                                                              */
/* ====================================================================== */

class _CarteMargeCentres extends ConsumerWidget {
  const _CarteMargeCentres();

  /// `accueil_pwa.marge.vide` — `$margeActivite === []`.
  static const String vide =
      'Aucune écriture analytique sur l\'exercice ouvert.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // La vue : `peutLire(MODULE_COMPTABILITE)`, sinon `null` -> « Non
    // consulté » — vérifié AVANT tout calcul.
    final autorise = ref
        .watch(droitsProvider)
        .peutLire(ModuleTatacora.m10Comptabilite);
    final analytique = autorise
        ? ref.watch(analytiquePilotageProvider).value
        : null;

    return _CadrePlein(
      titre: 'Marge sur coûts directs par activité',
      sousTitre:
          'Charges de structure non réparties : ce sont des marges, pas des '
          'résultats nets.',
      enfant: !autorise
          ? const _NoteSource(
              cle: Key('pilotage-centres-non-consulte'),
              texte: 'Non consulté',
            )
          : switch (analytique) {
              // Calculée sur le poste depuis le 13/10/2026 (fin du Pilotage,
              // décision du PO) : réplique de `AnalytiqueService` sur les
              // écritures de l'exercice ouvert (`analytique_locale.dart`).
              SourceRecue<AnalytiquePilotage>(:final donnee) =>
                donnee.centresActifs.isEmpty
                    ? const _NoteSource(
                        cle: Key('pilotage-centres-vide'),
                        texte: vide,
                      )
                    : GraphiqueMargeCentres(centres: donnee.centresActifs),
              SourceRefusee<AnalytiquePilotage> r => _NoteSource(
                cle: const Key('pilotage-centres-refus'),
                texte: motifRefusPilotage(r),
              ),
              // Le poste est zéro réseau : cette issue ne se produit plus, et
              // la phrase qu'elle portait (« calculées par le serveur… hors
              // connexion ») était PÉRIMÉE. La vue dit « Non consulté ».
              SourceInjoignable<AnalytiquePilotage>() => const _NoteSource(
                cle: Key('pilotage-centres-non-consulte'),
                texte: 'Non consulté',
              ),
              // `accueil_pwa.non_consulte` (la vue, `$margeActivite === null` :
              // aucun exercice ouvert), suivi de la raison datée.
              SourceAbsente<AnalytiquePilotage>(:final raison) => _NoteSource(
                cle: const Key('pilotage-centres-absent'),
                texte: 'Non consulté : $raison',
              ),
              null => const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Center(child: CircularProgressIndicator()),
              ),
            },
    );
  }
}

/// Le cadre « Créances par ancienneté » — PORTÉ le 13/10/2026 (fin du
/// Pilotage, décision du PO) : le graphique de la vue
/// (`graphe-creances`, `Accueil::creancesParAnciennete`), puis la note « Âge
/// compté depuis la date d'émission de la facture. ». Sans droit de lecture sur
/// M3 : « Non consulté », comme la vue.
///
/// L'ancien cadre disait « Non rendu sur ce poste : le graphique … n'est pas
/// encore porté » (D282) : il l'est.
class _CarteCreancesAnciennete extends ConsumerWidget {
  const _CarteCreancesAnciennete();

  /// `accueil_pwa.creances.age_source`.
  static const String ageSource =
      'Âge compté depuis la date d\'émission de la facture.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tranches = ref.watch(creancesAnciennetePilotageProvider);
    final valeur = tranches.value;
    return _CadrePlein(
      titre: 'Créances par ancienneté',
      sousTitre: 'Au-delà de 90 jours, le recouvrement devient incertain.',
      enfant: tranches.isLoading && !tranches.hasValue
          ? const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            )
          : valeur == null
          ? const _NoteSource(
              cle: Key('pilotage-creances-non-consulte'),
              texte: 'Non consulté',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GraphiqueCreancesAnciennete(
                  key: const Key('pilotage-creances-graphique'),
                  tranches: valeur,
                ),
                const SizedBox(height: AppSpacing.xs), // mt-2
                Text(
                  ageSource,
                  key: const Key('pilotage-creances-age'),
                  style: TextStyle(
                    fontSize: TaillesContenu.t11,
                    color: Ardoise.c400,
                  ),
                ),
              ],
            ),
    );
  }
}

/* ====================================================================== */
/* Occupation & meilleures ventes                                          */
/* ====================================================================== */

class _BlocOccupation extends ConsumerWidget {
  const _BlocOccupation({required this.debut, required this.finExclue});

  final DateTime? debut;
  final DateTime? finExclue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unites = ref.watch(parcPilotageProvider).value;
    final reservations = ref.watch(reservationsPilotageProvider).value;

    if (unites == null || reservations == null) {
      return const SizedBox.shrink();
    }

    final o = calculerOccupation(
      unites: unites,
      reservations: reservations,
      // L'horloge du tableau de bord, pas `DateTime.now()` : « occupées à
      // l'instant » dépend du jour, et un test n'a pas à attendre minuit.
      maintenant: ref.read(horlogeTableauDeBordProvider)(),
      fenetre: debut == null || finExclue == null
          ? null
          : FenetreTableauDeBord.entre(debut!, finExclue!),
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        border: Border.all(color: AppColors.neutre200),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Wrap(
        spacing: AppSpacing.lg, // gap-6
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _LibelleMajuscule('Taux d\'occupation'),
              Text(
                o.taux == null ? '—' : '${o.taux} %',
                key: const Key('pilotage-occupation-taux'),
                style: TextStyle(
                  fontSize: TaillesContenu.xxl, // text-2xl
                  fontWeight: FontWeight.bold,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
          // La vue (`accueil.blade.php` l.1100-1109) : le taux, puis
          // `accueil_pwa.occupation.sous_titre` (`text-[12px] text-slate-500
          // flex-1 min-w-[240px]`). « Occupées à l'instant » et la phrase des
          // nuitées étaient des AJOUTS de l'ancien maître, retirés le
          // 13/10/2026 (fin du Pilotage) : la vue ne les a pas.
          ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: AppLayout.detailOccupation,
              maxWidth: AppLayout.panneauLateral,
            ),
            child: Text(
              'Taux calculé en nuitées vendues, rapportées à la capacité de la '
              'période.',
              key: const Key('pilotage-occupation-detail'),
              style: TextStyle(
                fontSize: TaillesContenu.t12,
                color: Ardoise.c500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LibelleMajuscule extends StatelessWidget {
  const _LibelleMajuscule(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) => Text(
    texte.toUpperCase(),
    style: TextStyle(
      fontSize: TaillesContenu.t11,
      // `tracking-wide`, le même jeton que `_CarteKpi` (R8).
      letterSpacing: TaillesContenu.t11 * AppTextStyles.suiviLarge,
      color: Ardoise.c400,
    ),
  );
}

/// Les quatre classements du maître.
///
/// ÉCART DÉLIBÉRÉ — `assets/js/indicateurs-engine.js`, `topVentes`.
/// Le prototype : la table de faits agrège les ventes de l'établissement
/// entier (un seul poste dans la maquette).
/// Ici : le journal des ventes est celui de CE poste — les paniers ne sont
/// pas synchronisés — et la mention sous la grille le dit.
/// Raison : contrainte de plateforme (offline-first) ; annoncer un palmarès
/// d'établissement sur les données d'un poste serait un chiffre plus petit
/// que la réalité sans que rien ne le signale (PA-120).
class _GrilleTopVentes extends ConsumerWidget {
  const _GrilleTopVentes({required this.debut, required this.finExclue});

  final DateTime? debut;
  final DateTime? finExclue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final journal = ref.watch(journalVentesProvider).value;
    final reservations = ref.watch(reservationsPilotageProvider).value;

    if (journal == null || reservations == null) {
      return const SizedBox.shrink();
    }

    if (debut == null || finExclue == null) {
      // Sans bornes, un classement « toutes périodes » se ferait passer pour
      // celui de la période affichée en tête d'écran.
      return const _NoteSource(
        cle: Key('pilotage-top-ventes-sans-periode'),
        texte:
            'La période n’est pas connue : les classements ne sont pas '
            'calculables.',
      );
    }

    final classements = classerMeilleuresVentes(
      ventes: journal.ventes,
      reservations: reservations,
      debut: debut!,
      finExclue: finExclue!,
    );

    return LayoutBuilder(
      builder: (context, contraintes) {
        // `grid-cols-1 md:grid-cols-2 xl:grid-cols-4`.
        final colonnes = contraintes.maxWidth >= AppBreakpoints.xl
            ? 4
            : (contraintes.maxWidth >= AppBreakpoints.md ? 2 : 1);
        final largeur =
            (contraintes.maxWidth - AppSpacing.sm * (colonnes - 1)) / colonnes;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final c in classements)
                  SizedBox(width: largeur, child: _CarteClassement(c)),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Ventes et réservations enregistrées sur ce poste.',
              key: const Key('pilotage-top-ventes-portee'),
              style: TextStyle(
                fontSize: TaillesContenu.t11,
                color: Ardoise.c400,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CarteClassement extends StatelessWidget {
  const _CarteClassement(this.classement);

  final ClassementPilotage classement;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('pilotage-classement-${classement.libelle}'),
      padding: const EdgeInsets.all(AppSpacing.smPlus), // p-3.5
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        border: Border.all(color: AppColors.neutre200),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Le titre du classement : `accueil_pwa.top_ventes.<clé>` (food,
          // drinks, circuit, location), composé à la volée par la vue.
          _LibelleMajuscule(classement.libelle),
          // Le critère est ANNONCÉ : un classement par quantité et un
          // classement par montant ne donnent pas le même ordre, et le
          // lecteur doit savoir lequel il regarde (le maître, au mot).
          Text(
            classement.tri.libelle,
            style: TextStyle(fontSize: TaillesContenu.t11, color: Ardoise.c400),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (classement.vide)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                'Aucune vente sur cette période.',
                style: TextStyle(
                  fontSize: TaillesContenu.t12,
                  color: Ardoise.c400,
                ),
              ),
            )
          else
            for (final (index, l) in classement.lignes.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    SizedBox(
                      width: AppSpacing.md,
                      child: Text(
                        '${index + 1}.',
                        style: TextStyle(
                          fontSize: TaillesContenu.t11,
                          color: Ardoise.c400,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        l.nom,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: TaillesContenu.t13,
                          color: Ardoise.c700,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      classement.tri == TriClassement.quantite
                          ? '${l.quantite}'
                          : _grouperEntier(l.montant),
                      style: TextStyle(
                        fontSize: TaillesContenu.t13,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.unit),
                    Text(
                      classement.tri == TriClassement.quantite
                          ? 'vendu(s)'
                          : 'F',
                      style: TextStyle(
                        fontSize: TaillesContenu.t11,
                        color: Ardoise.c400,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// « 12 345 » — le montant seul, l'unité est portée par le libellé voisin.
String _grouperEntier(int montant) {
  final texte = formaterMontantDecimal('$montant', suffixe: 'FCFA');
  return texte == null ? '$montant' : texte.substring(0, texte.length - 2);
}

/* ====================================================================== */
/* Par module                                                              */
/* ====================================================================== */

/// Les cartes « Par module » — `m11-pilotage.js`, `rendreModules`.
///
/// ## La carte « Dépense courante » est RENDUE depuis le 10/10/2026
///
/// Le refus `maitre-refuse:tableau-de-bord#carte-depense-courante` disait
/// « aucune table `depenses` n'existe ». C'était vrai le 27/08/2026 ; c'est
/// faux depuis la v10 (`depenses_local`, `lignes_depense_local`). Le motif a
/// cessé d'être vrai, la décision est levée (PA-144). Ses quatre lignes —
/// « Total décaissé », « Nombre », « Marché », « Services » — sont celles de
/// l'écran Dépense courante ([IndicateursDepenses]), calculées sur la fenêtre
/// affichée.
///
/// Reste non rendue : la vigilance « N dépense(s) sans reçu » du maître. Le
/// poste ne conserve aucun reçu (`depenses_local` n'a pas de colonne de
/// justificatif) : l'afficher à « 0 » dirait « tout est justifié ».
class _GrilleModules extends ConsumerWidget {
  const _GrilleModules({required this.fenetre, required this.tableau});

  /// La fenêtre affichée en tête d'écran, ou `null` si elle n'est pas connue :
  /// une carte « sur la période » sans période serait sur toutes les périodes.
  final FenetreTableauDeBord? fenetre;

  /// La bande M11 : la carte « Stocks » y lit sa valeur, comme la vue
  /// (`Accueil::cartesParModule`, l.2284 : `$indicateurs['valeur_stock']`).
  final TableauDeBord? tableau;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m1 = ref.watch(kpisM1PilotageProvider);
    final pos = ref.watch(ventesJourPilotageProvider);
    final stock = ref.watch(stockPilotageProvider).value;
    final compta = ref.watch(comptaPilotageProvider).value;
    final vehicules = ref.watch(vehiculesPilotageProvider).value;
    final tourisme = ref.watch(tourismePilotageProvider).value;
    final role = ref.watch(sessionProvider)?.role ?? '';
    // « Personnel & paie » : `$paie !== null` (droit M13) ET l'entrée du menu.
    final paie = !entreeMasqueePourRole(role, 'Personnel & Paie')
        ? ref.watch(masseSalarialePilotageProvider).value
        : null;
    // « Clients & créances » : les tranches (droit M3) ET l'entrée du menu.
    final tranches = !entreeMasqueePourRole(role, 'Clients & Créances')
        ? ref.watch(creancesAnciennetePilotageProvider).value
        : null;
    final creances = tranches == null
        ? null
        : ref.watch(creancesProvider).value;
    final paiements = tranches == null
        ? null
        : ref.watch(paiementsFactureProvider).value;
    // Chaque carte est gardée par le droit de SON module, comme la vue : une
    // carte non autorisée n'est jamais calculée puis masquée.
    final depenses =
        fenetre != null &&
            ref.watch(droitsProvider).peutLire(ModuleTatacora.m10Comptabilite)
        ? ref.watch(depensesPilotageProvider(fenetre!)).value
        : null;

    final cartes = <Widget>[
      if (m1 != null)
        _CarteModule(
          cle: const Key('pilotage-module-m1'),
          titre: 'Réservations & hébergement',
          module: 'M1',
          lignes: [
            ('À venir', '${m1.aVenir}', null),
            ('En cours', '${m1.enCours}', null),
            ('Nuitées', '${m1.nuitees}', null),
            (
              'Reste à encaisser',
              _fcfa('${m1.resteAEncaisser}'),
              m1.resteAEncaisser > 0 ? PaletteMaitre.rouge600 : null,
            ),
          ],
        ),
      if (pos != null)
        _CarteModule(
          cle: const Key('pilotage-module-pos'),
          titre: 'Point de vente — aujourd’hui',
          module: 'M4 / M5',
          lignes: [
            ('Ventes', '${pos.ventes}', null),
            ('Chiffre d’affaires', _fcfa('${pos.chiffreAffaires}'), null),
            (
              'Panier moyen',
              _fcfa(
                '${pos.ventes == 0 ? 0 : (pos.chiffreAffaires / pos.ventes).round()}',
              ),
              null,
            ),
            ('Porté en note de chambre', _fcfa('${pos.enNote}'), null),
          ],
          // La note du maître — « N vente(s) ne décrémentent aucun stock » —
          // n'est pas évaluable : les fiches techniques ne sont pas
          // répliquées (PA-134), et le poste ne sait pas quelles ventes
          // décrémentent quoi. Nommée, pas devinée.
        ),
      if (stock is StockRecu)
        _CarteModule(
          cle: const Key('pilotage-module-m6'),
          titre: 'Stocks',
          module: 'M6',
          lignes: [
            // ÉCART DÉLIBÉRÉ — `m11-pilotage.js`, `rendreModules` (bloc
            // Stocks). Le prototype : une ligne « Achat journalier (non
            // suivi) » (`d.stock.journaliers`). Ici : absente. Raison :
            // `GET /stocks/etat` ne distingue pas les articles permanents des
            // achats journaliers (`KpisStock`, lu le 27/08/2026) — rendre la
            // ligne exigerait de recompter côté client ce que le serveur n'a
            // pas compté.
            ('Références suivies', '${stock.etat.kpis.references}', null),
            // La valeur vient de la BANDE, comme la vue (`Accueil.php`
            // l.2281-2284 : `$indicateurs['valeur_stock']['valeur']`, un tiret
            // quand la bande n'est pas mesurée) — plus de M6 (14/10/2026).
            // Une seule lecture pour la carte KPI et la carte du module : deux
            // chiffres pour la même grandeur seraient deux vérités.
            //
            // ⚠ Défaut corrigé le 14/10/2026 (passe finale) : en passant à la
            // bande (D399), la carte avait PERDU la mention « (hors N
            // article(s) sans coût) » (D119) — un minorant affiché comme le
            // total, à côté de la carte KPI qui, elle, la porte. La mention
            // part avec la valeur, ici comme sur la bande.
            ('Valeur au coût moyen', valeurStockDuModule(tableau), null),
            (
              'Sous seuil',
              '${stock.etat.kpis.sousSeuil}',
              stock.etat.kpis.sousSeuil > 0 ? PaletteMaitre.ambre600 : null,
            ),
          ],
        ),
      // 4. Location de véhicules (M8) — `Accueil::cartesParModule` l.2297.
      if (vehicules != null)
        _CarteModule(
          cle: const Key('pilotage-module-m8'),
          titre: 'Location de véhicules',
          module: 'M8',
          lignes: [
            ('Parc', '${vehicules.parc}', null),
            ('Contrats actifs', '${vehicules.contratsActifs}', null),
            (
              'Chiffre d’affaires',
              vehicules.chiffreAffaires == null
                  ? '—'
                  : _fcfa(vehicules.chiffreAffaires!),
              null,
            ),
            ('Jours loués', '${vehicules.joursLoues}', null),
          ],
          note: vehicules.immobilises > 0
              ? '${vehicules.immobilises} véhicule(s) immobilisé(s).'
              : null,
        ),
      // 5. Tourisme & circuits (M9) — l.2322.
      if (tourisme != null)
        _CarteModule(
          cle: const Key('pilotage-module-m9'),
          titre: 'Tourisme & circuits',
          module: 'M9',
          lignes: [
            ('Départs planifiés', '${tourisme.departs}', null),
            (
              'Places vendues',
              '${tourisme.placesVendues} / ${tourisme.capaciteOfferte}',
              null,
            ),
            (
              'Remplissage',
              // `null` n'est pas « 0 % » : sans capacité, pas de taux.
              tourisme.tauxRemplissage == null
                  ? '—'
                  : '${nombreCommePhp(tourisme.tauxRemplissage!)} %',
              tourisme.tauxRemplissage != null && tourisme.tauxRemplissage! < 50
                  ? PaletteMaitre.ambre600
                  : null,
            ),
            ('Chiffre d’affaires', _fcfa('${tourisme.chiffreAffaires}'), null),
          ],
          note: tourisme.dureeIndeterminee > 0
              ? '${tourisme.dureeIndeterminee} départ(s) à durée indéterminée.'
              : null,
        ),
      // 6. Personnel & paie (M13) — l.2350. Le coût employeur est une
      // FOURCHETTE (PA-53), jamais un total unique ; la note est fixe.
      if (paie != null)
        _CarteModule(
          cle: const Key('pilotage-module-m13'),
          titre: 'Personnel & paie',
          module: 'M13',
          lignes: [
            ('Effectif actif', '${paie.effectif}', null),
            ('Masse salariale', _fcfa('${paie.brut}'), null),
            (
              'Coût employeur',
              '${_fcfa('${paie.coutMin}')} à ${_fcfa('${paie.coutMax}')}',
              PaletteMaitre.ambre700,
            ),
            ('VPS à reverser', _fcfa('${paie.ventilation.vps}'), null),
          ],
          note:
              'Fourchette : le taux de risques professionnels n’est pas '
              'confirmé.',
        ),
      // 7. Clients & créances (M3) — l.2381 : totaux de `SoldeClientService`,
      // la tranche « plus de 90 jours » du graphique (jamais une seconde
      // lecture) et l'encaissé ACTIF des 30 derniers jours.
      if (tranches != null && creances != null && paiements != null)
        () {
          final totaux = totauxCreances(creances);
          final plus90 = tranches
              .firstWhere((t) => t.cle == 'plus_90')
              .montantCentimes;
          final encaisse30j = encaisseDepuisCentimes(
            paiements,
            ilYa30Jours(ref.read(horlogeTableauDeBordProvider)()),
          );
          return _CarteModule(
            cle: const Key('pilotage-module-m3'),
            titre: 'Clients & créances',
            module: 'M3',
            lignes: [
              ('Clients débiteurs', '${totaux.nbClients}', null),
              (
                'Total dû',
                _fcfa(decimaleDeCentimes(totaux.totalDuCentimes)),
                null,
              ),
              (
                'Dont + de 90 jours',
                _fcfa(decimaleDeCentimes(plus90)),
                plus90 > 0 ? PaletteMaitre.rouge600 : null,
              ),
              (
                'Encaissé sur 30 jours',
                _fcfa(decimaleDeCentimes(encaisse30j)),
                PaletteMaitre.emeraude600,
              ),
            ],
          );
        }(),
      if (compta is SourceRecue<ComptaPilotage>)
        _CarteModule(
          cle: const Key('pilotage-module-m10'),
          titre: 'Comptabilité',
          module: 'M10',
          lignes: [
            ('Valeur ajoutée', _fcfa(compta.donnee.valeurAjoutee), null),
            (
              'Excédent brut',
              _fcfa(compta.donnee.excedentBrut),
              compta.donnee.excedentBrutNegatif ? PaletteMaitre.rouge600 : null,
            ),
            ('Total bilan', _fcfa(compta.donnee.totalBilan), null),
            ('Pièces saisies', '${compta.donnee.pieces}', null),
          ],
          note: compta.donnee.brouillons > 0
              ? '${compta.donnee.brouillons} brouillon(s) à trancher.'
              : null,
        ),
      if (depenses != null)
        _CarteModule(
          cle: const Key('pilotage-module-depenses'),
          titre: 'Dépense courante',
          module: 'M10',
          lignes: [
            ('Total décaissé', _fcfa('${depenses.total}'), null),
            ('Nombre', '${depenses.nombre}', null),
            ('Marché', _fcfa('${depenses.marche}'), null),
            ('Services', _fcfa('${depenses.services}'), null),
          ],
        ),
    ];

    if (cartes.isEmpty) {
      return Text(
        'Aucun module ne remonte de données.',
        key: const Key('pilotage-modules-vide'),
        style: TextStyle(fontSize: TaillesContenu.t13, color: Ardoise.c400),
      );
    }

    return LayoutBuilder(
      builder: (context, contraintes) {
        // `grid-cols-1 md:grid-cols-2 xl:grid-cols-3`.
        final colonnes = contraintes.maxWidth >= AppBreakpoints.xl
            ? 3
            : (contraintes.maxWidth >= AppBreakpoints.md ? 2 : 1);
        final largeur =
            (contraintes.maxWidth - AppSpacing.sm * (colonnes - 1)) / colonnes;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final carte in cartes) SizedBox(width: largeur, child: carte),
          ],
        );
      },
    );
  }
}

class _CarteModule extends StatelessWidget {
  const _CarteModule({
    required Key cle,
    required this.titre,
    required this.module,
    required this.lignes,
    this.note,
  }) : super(key: cle);

  final String titre;
  final String module;

  /// `(libellé, valeur, couleur d'accent)` — la valeur à DROITE, toujours.
  final List<(String, String, Color?)> lignes;

  final String? note;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        border: Border.all(color: AppColors.neutre200),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  titre,
                  style: TextStyle(
                    fontSize: TaillesContenu.t13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navy,
                  ),
                ),
              ),
              _BadgeModule(module),
            ],
          ),
          const SizedBox(height: AppSpacing.xsPlus),
          for (final (libelle, valeur, accent) in lignes)
            Container(
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.unit, // py-1
              ),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Ardoise.c50)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      libelle,
                      style: TextStyle(
                        fontSize: TaillesContenu.t12,
                        color: Ardoise.c500,
                      ),
                    ),
                  ),
                  Text(
                    valeur,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: TaillesContenu.t13,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: accent ?? AppColors.navy,
                    ),
                  ),
                ],
              ),
            ),
          if (note != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              note!,
              style: TextStyle(
                fontSize: TaillesContenu.t10_5,
                color: PaletteMaitre.ambre700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/* ====================================================================== */
/* Export PDF                                                              */
/* ====================================================================== */

/// L'état à imprimer — construit **au clic**, sur ce qui est affiché
/// (PA-119). Les réserves partent dans le document : un état exporté qui les
/// perdrait circulerait comme un chiffre définitif (le maître, au mot).
///
/// [tableau] est la réponse de la bande que l'écran affiche : les KPI « Chiffre
/// d'affaires encaissé », « Trésorerie (caisse) » et « Valeur du stock » du
/// document sont lus par la MÊME fonction que les cartes
/// ([valeurPilotageDeLaBande]) — le papier dit la valeur de l'écran, au
/// caractère près (R1, 12/10/2026).
EtatPilotage composerEtatPilotage(
  WidgetRef ref, {
  FenetreTableauDeBord? fenetre,
  TableauDeBord? tableau,
}) {
  final compta = ref.read(comptaPilotageProvider).value;
  final analytique = ref.read(analytiquePilotageProvider).value;
  final stock = ref.read(stockPilotageProvider).value;
  final creances = ref.read(creancesProvider).value;

  final donnee = compta is SourceRecue<ComptaPilotage> ? compta.donnee : null;

  final lignes = <List<String>>[];
  if (donnee != null) {
    lignes.addAll([
      ['Comptabilité', 'Chiffre d’affaires', _fcfa(donnee.chiffreAffaires)],
      ['Comptabilité', 'Valeur ajoutée', _fcfa(donnee.valeurAjoutee)],
      [
        'Comptabilité',
        'Excédent brut d’exploitation',
        _fcfa(donnee.excedentBrut),
      ],
      [
        'Comptabilité',
        'Résultat net${donnee.impotNonComptabilise ? ' (avant impôt)' : ''}',
        _fcfa(donnee.resultatNet),
      ],
      ['Comptabilité', 'Trésorerie', _fcfa(donnee.tresorerie)],
      ['Comptabilité', 'Total bilan', _fcfa(donnee.totalBilan)],
    ]);
  }
  // La valeur du stock n'est plus une ligne lue en M6 (« Valeur au coût moyen
  // pondéré ») : c'est la carte « Valeur du stock » des KPI ci-dessous, lue de
  // la bande comme à l'écran (12/10/2026). Deux montants pour la même grandeur
  // sur un document seraient deux vérités.
  if (stock is StockRecu) {
    lignes.add([
      'Stocks',
      'Articles sous seuil',
      '${stock.etat.kpis.sousSeuil}',
    ]);
  }
  // Ce que la valeur du stock ne comprend pas PART avec elle (D119) : le
  // lecteur du papier n'a pas la note de la carte sous les yeux.
  // (Une mention n'existe que sur un indicateur ÉTABLI : un indicateur
  // indisponible n'en porte jamais.)
  final mentionStock = tableau?.parCle(cleValeurStock)?.mention;
  if (mentionStock != null) {
    lignes.add(['RÉSERVE', 'Valeur du stock $mentionStock', '']);
  }

  // Personnel & paie : le brut des bulletins du mois, jamais le coût employeur
  // (PA-53). Trois états, comme la carte : non consulté (droit absent), aucun
  // bulletin, ou un montant.
  final masse = ref.read(masseSalarialePilotageProvider).value;
  if (masse == null) {
    lignes.add(['RÉSERVE', 'Masse salariale non consultée à l’édition', '—']);
  } else if (masse.effectif == 0) {
    lignes.add([
      'Personnel & paie',
      'Masse salariale',
      'Aucun bulletin établi ce mois-ci',
    ]);
  } else {
    lignes.add([
      'Personnel & paie',
      'Masse salariale (brut, ${masse.effectif} salarié(s))',
      _fcfa('${masse.brut}'),
    ]);
  }

  // Dépense courante : sur la FENÊTRE affichée, comme la carte.
  final depenses = fenetre == null
      ? null
      : ref.read(depensesPilotageProvider(fenetre)).value;
  if (depenses != null) {
    lignes.addAll([
      ['Dépense courante', 'Total décaissé', _fcfa('${depenses.total}')],
      ['Dépense courante', 'Nombre', '${depenses.nombre}'],
      ['Dépense courante', 'Marché', _fcfa('${depenses.marche}')],
      ['Dépense courante', 'Services', _fcfa('${depenses.services}')],
    ]);
  }

  // Les mêmes réserves que l'écran — jamais une seconde liste.
  if (donnee?.impotNonComptabilise ?? false) {
    lignes.add(['RÉSERVE', 'Résultat affiché AVANT impôt', '']);
  }
  if (analytique is SourceRecue<AnalytiquePilotage> &&
      !analytique.donnee.repartitionStructureEffectuee) {
    lignes.add(['RÉSERVE', 'Charges de structure non réparties', '']);
  }
  // Et le périmètre de ce que le document NE couvre pas — un lecteur du PDF
  // n'a pas l'écran sous les yeux.
  if (donnee == null) {
    // La raison DATÉE de la carte « Résultat net », pas un « indisponible »
    // muet : le lecteur du papier n'a pas l'infobulle.
    lignes.add([
      'RÉSERVE',
      '$comptabiliteNonConsultee à l’édition'
          '${compta is SourceAbsente<ComptaPilotage> ? ' : ${compta.raison}' : ''}',
      '—',
    ]);
  }
  if (stock is! StockRecu) {
    lignes.add(['RÉSERVE', 'Stocks indisponibles à l’édition', '—']);
  }
  lignes.addAll(reservesBandeNonConsultee(tableau));

  return EtatPilotage(
    // La fenêtre de la bande — celle des deux KPI M11 du document — puis, à
    // défaut, l'exercice ; jamais « Toutes périodes », qui se lirait comme un
    // cumul depuis l'ouverture.
    periode:
        fenetre?.libelle ??
        tableau?.libellePeriode ??
        (donnee != null ? 'Exercice ${donnee.annee}' : 'Période non précisée'),
    kpis: {
      EcranTableauDeBord.libelles[cleChiffreAffairesEncaisse]!:
          valeurPilotageDeLaBande(tableau, cleChiffreAffairesEncaisse) ?? '—',
      'Résultat net': donnee == null
          ? '—'
          : '${_fcfa(donnee.resultatNet)}'
                '${donnee.impotNonComptabilise ? ' (avant impôt)' : ''}',
      EcranTableauDeBord.libelles[cleTresorerieCaisse]!:
          valeurPilotageDeLaBande(tableau, cleTresorerieCaisse) ?? '—',
      // La carte affichée, au mot près (PA-119) : « — » seulement si la
      // lecture n'a pas abouti au clic — jamais un zéro à sa place.
      'Créances clients': creances == null
          ? '—'
          : _fcfa(centiemesEnChaine(totauxCreances(creances).totalDuCentimes)),
      // La carte 5, au caractère près : la même fonction que l'écran.
      EcranTableauDeBord.libelles[cleValeurStock]!:
          valeurPilotageDeLaBande(tableau, cleValeurStock) ?? '—',
    },
    lignes: lignes,
  );
}

/// Les trois KPI du document lus de la BANDE (« Chiffre d'affaires encaissé »,
/// « Trésorerie (caisse) », « Valeur du stock »), dans l'ordre des cartes.
const List<String> _clesBandeDuDocument = [
  cleChiffreAffairesEncaisse,
  cleTresorerieCaisse,
  cleValeurStock,
];

/// Les lignes `RÉSERVE` des KPI de la bande imprimés « — ».
///
/// ⚠ Ajouté le 12/10/2026 (contrôle du lot 1, A-1) : un PDF exporté pendant le
/// calcul de la bande, ou après son échec, imprimait ces trois cartes à « — »
/// SANS rien dire, alors que « Résultat net », la masse salariale et les stocks
/// disent chacun pourquoi ils manquent. Le lecteur du papier n'a pas l'écran
/// (« Chargement… », « Non consulté ») sous les yeux.
///
/// - Bande non reçue (`tableau == null` : calcul en cours, en échec, ou droit
///   M11 refusé — le document ne sait pas lequel, et n'en affirme aucun) : UNE
///   ligne qui nomme les trois cartes.
/// - Bande reçue mais indicateur non établi : une ligne par indicateur, avec
///   la raison que la bande donne (`raisonAbsence`), quand elle en donne une.
List<List<String>> reservesBandeNonConsultee(TableauDeBord? tableau) {
  String libelle(String cle) => EcranTableauDeBord.libelles[cle]!;
  if (tableau == null) {
    return [
      [
        'RÉSERVE',
        '${libelle(cleChiffreAffairesEncaisse)}, '
            '${libelle(cleTresorerieCaisse)} et ${libelle(cleValeurStock)} '
            "non consultés à l'édition : indicateurs de la bande non reçus "
            '(calcul en cours, en échec ou non autorisé)',
        '—',
      ],
    ];
  }
  return [
    for (final cle in _clesBandeDuDocument)
      if (valeurPilotageDeLaBande(tableau, cle) == null)
        [
          'RÉSERVE',
          "${libelle(cle)} non consulté à l'édition"
              '${switch (tableau.parCle(cle)?.raisonAbsence) {
                final String r => ' : $r',
                null => '',
              }}',
          '—',
        ],
  ];
}

/// L'export PDF — une action INJECTABLE, jamais un `layoutPdf` ni une
/// écriture de fichier dans l'écran. Enregistré par la fenêtre « Enregistrer
/// sous » (14/10/2026) ; rend le CHEMIN écrit, `null` : annulé.
final exporterEtatPilotagePdfProvider =
    Provider<Future<String?> Function(EtatPilotage)>(
      (ref) =>
          (etat) async => ref
              .read(enregistrementExportProvider)
              .exporter(
                base: 'pilotage_consolide',
                type: TypeFichierEnregistre.pdf,
                octets: await etat
                    .avecEntete(
                      await ref.read(lireEnteteEtablissementProvider)(),
                    )
                    .pdf(),
              ),
    );

/* ====================================================================== */
/* Charpente commune                                                       */
/* ====================================================================== */

/// Deux cartes côte à côte à `xl`, empilées avant — `grid grid-cols-1
/// xl:grid-cols-2 gap-3`. Largeur d'ÉCRAN (Article 5).
class _RangeeCartes extends StatelessWidget {
  const _RangeeCartes({required this.gauche, required this.droite});

  final Widget gauche;
  final Widget droite;

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.sizeOf(context).width >= AppBreakpoints.xl;
    if (!large) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          gauche,
          const SizedBox(height: AppSpacing.sm),
          droite,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: gauche),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: droite),
      ],
    );
  }
}

class _TitreSection extends StatelessWidget {
  const _TitreSection(this.titre);

  final String titre;

  @override
  Widget build(BuildContext context) => Text(
    titre,
    style: TextStyle(
      fontSize: TaillesContenu.t14,
      fontWeight: FontWeight.bold,
      color: AppColors.navy,
    ),
  );
}

/// Une carte à en-tête filet — le gabarit des blocs « À traiter » et
/// « réserves ».
class _CadreCarte extends StatelessWidget {
  const _CadreCarte({
    required this.entete,
    required this.enfant,
    this.fondEntete,
  });

  final Widget entete;
  final Widget enfant;
  final Color? fondEntete;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        border: Border.all(color: AppColors.neutre200),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, // px-4
              vertical: AppSpacing.sm, // py-3
            ),
            decoration: BoxDecoration(
              color: fondEntete,
              border: const Border(
                bottom: BorderSide(color: AppColors.neutre200),
              ),
            ),
            child: entete,
          ),
          enfant,
        ],
      ),
    );
  }
}

/// Une carte pleine à titre + sous-titre — le gabarit des deux graphiques.
class _CadrePlein extends StatelessWidget {
  const _CadrePlein({
    required this.titre,
    required this.sousTitre,
    required this.enfant,
  });

  final String titre;
  final String sousTitre;
  final Widget enfant;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md), // p-4
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        border: Border.all(color: AppColors.neutre200),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titre,
            style: TextStyle(
              fontSize: TaillesContenu.t14,
              fontWeight: FontWeight.bold,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: AppSpacing.demi),
          Text(
            sousTitre,
            style: TextStyle(fontSize: TaillesContenu.t11, color: Ardoise.c400),
          ),
          const SizedBox(height: AppSpacing.sm),
          enfant,
        ],
      ),
    );
  }
}

/// Une note à la place d'un contenu qui ne peut pas s'afficher — elle DIT
/// pourquoi, jamais un cadre vide (Article 7).
class _NoteSource extends StatelessWidget {
  const _NoteSource({required Key cle, required this.texte}) : super(key: cle);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.neutre100,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        texte,
        style: TextStyle(fontSize: TaillesContenu.t12, color: Ardoise.c500),
      ),
    );
  }
}
