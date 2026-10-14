// Vue Blade maîtresse (PA-183) : pwa/rh/paie.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/formats.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared_widgets/modale_export.dart';
import '../../../shared_widgets/toast_export.dart';
import '../../restaurant/presentation/widgets/corps_carte_commun.dart';
import '../domain/entities/employe.dart';
import '../domain/entities/periode_paie.dart';
import '../domain/services/livre_de_paie_service.dart';
import 'providers_rh.dart';
import 'widgets/modales_paie.dart';
import 'widgets/panneaux_paie.dart';

/// **M13 Personnel & Paie** — le dossier du personnel, les bulletins, le livre,
/// les déclarations et les barèmes.
///
/// ## L'ordre des blocs est celui de la vue
///
/// En-tête (l.105-131) ; bandeau « taux non paramétrés » (l.137-144) ; bande
/// d'indicateurs repliable (l.148-194) ; onglets (l.197-203) ; bandeau
/// permanent des risques professionnels (l.213-217) ; filtres (l.220-256) ;
/// panneau de l'onglet (l.279-773) ; modales après `</main>` (l.858-1188).
///
/// ## Aucun montant de paie n'est saisi
///
/// Le net, la CNSS, l'ITS et la part patronale sont **calculés** par
/// `CalculPaieService` et rendus en lecture seule. Le seul montant saisi de
/// l'écran est le salaire de base, qui est une donnée du contrat de travail —
/// pas un résultat de calcul. Le prototype d'origine offrait un champ « Net à
/// payer » : c'est l'un des anti-patterns nommés en tête du dépôt.
///
/// ## Le coût employeur est TOUJOURS une fourchette (PA-53)
///
/// Le taux CNSS de risques professionnels est « 1 % à 4 % selon l'activité » et
/// n'est pas confirmé pour l'hôtellerie-restauration. **Aucun total de charge
/// patronale n'apparaît nulle part sur cet écran** — ni en tableau, ni en
/// indicateur, ni dans le bulletin, ni à l'export. Retenir 2,5 % « au milieu »
/// serait exactement l'hypothèse refusée : sur une masse salariale annuelle,
/// l'écart entre 1 % et 4 % est un redressement.
///
/// Le bandeau ambre qui l'explique reste affiché **sur les cinq onglets** : une
/// fourchette sans son explication se lirait comme une imprécision d'affichage.
///
/// ## Cet écran ne demande AUCUN réseau
///
/// Tout vient de la base locale. Il n'a donc ni bandeau « hors connexion », ni
/// badge « en attente de synchronisation » — `bulletins_paie` n'est pas au
/// registre des tables synchronisables, et annoncer une attente qui ne finira
/// jamais serait PA-59/60/61. Ce qui est enregistré l'est **sur ce poste**.
///
/// ## Écarts à la vue, datés (09/10/2026)
///
/// - **Texte du bandeau « taux non paramétrés »** (`rh_pwa.referentiel_texte`) :
///   la vue dit « Ils sont posés par le référentiel de paie, et un
///   Administrateur peut les renseigner depuis l'écran Paramètres. ». Vérifié
///   contre le poste : l'écran Paramètres n'y écrit aucun taux de paie (aucune
///   table locale, aucune clé `taux_*`) ; la phrase décrirait un geste que ce
///   poste ne fait pas. Remplacée par ce qui est vrai ici — le référentiel
///   confirmé est réinstallé à chaque ouverture de l'écran. Longueur voisine :
///   le bandeau garde ses trois lignes et la page sa mise en page.
/// - **Les contrôles `<select>` n'ont pas de largeur** à la vue : voir les
///   jetons `AppLayout.filtre*Paie`.
/// - **L'état replié de la bande d'indicateurs** n'est pas retenu d'une session
///   à l'autre (la vue le garde en `localStorage`) : aucun magasin de
///   préférences n'est embarqué.
/// - **Le bandeau vert de succès** de la vue (`session('pwa-succes')`, l.90-96)
///   est un `SnackBar` : un message de bilan, pas un bloc de page.
///
/// @see EF-M13-01 Dossier du personnel
/// @see EF-M13-07 Calcul de la paie conforme à la réglementation béninoise
/// @see RG-15 Journalisation des opérations
class EcranPaie extends ConsumerWidget {
  const EcranPaie({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final referentiel = ref.watch(referentielPaieProvider);

    // La consultation s'ouvre sur l'identifiant porté par le fournisseur : la
    // ligne de l'effectif, celle du registre et la fin d'un établissement
    // ouvrent ainsi le MÊME document.
    ref.listen<String?>(bulletinAfficheProvider, (avant, apres) {
      if (apres != null && avant == null) ouvrirBulletin(context, ref);
    });

    return referentiel.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (erreur, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text('$erreur', textAlign: TextAlign.center),
        ),
      ),
      data: (etat) => PageCarte(
        largeurMax: AppLayout.pagePaie,
        enfants: [
          const _EnTetePage(),
          // Le référentiel peut être incomplet malgré l'amorçage — une clé
          // effacée à la main, par exemple. L'écran le DIT et nomme les clés,
          // plutôt que d'afficher des tirets sans raison.
          if (!etat.complet)
            _BandeauReferentiel(clesAbsentes: etat.clesAbsentes),
          const _BandeIndicateurs(),
          const _BarreOnglets(),
          // KPI → onglets → encart ambre : l'ordre du maître.
          const _BandeauRisquesProfessionnels(),
          const _BarreFiltres(),
          const _PanneauCourant(),
        ],
      ),
    );
  }
}

/* ====================================================================== */
/* En-tête                                                                 */
/* ====================================================================== */

class _EnTetePage extends ConsumerWidget {
  const _EnTetePage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return EnTeteCarte(
      icone: Icons.people_outline,
      titre: 'Personnel & Paie',
      cleTitre: const Key('paie-titre'),
      // `text-[15px] text-slate-500 mt-1.5` : le sous-titre, en fragments —
      // la vue pose deux `<strong>`.
      sousTitre: const [
        TextSpan(
          text:
              'CNSS 3,6 % salarié · ITS progressif · charges patronales CNSS '
              '15,4 % + ',
        ),
        TextSpan(
          text: 'VPS 4 %',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        TextSpan(text: '. Le net à payer est '),
        TextSpan(
          text: 'calculé',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        TextSpan(text: ', jamais saisi.'),
      ],
      // `flex flex-wrap gap-2 items-center` (l.114).
      boutons: [
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Période',
              style: styleContenuCarte(
                TaillesContenu.t12,
                couleur: Ardoise.c500,
              ),
            ),
            const _ChoixPeriode(),
            BoutonEnteteCarte(
              key: const Key('paie-exporter'),
              libelle: TextesExport.bouton,
              style: StyleBoutonEntete.plein,
              onPressed: () => _exporter(context, ref),
            ),
          ],
        ),
      ],
    );
  }

  /// « Exporter » : la modale de format de la vue, puis le document.
  ///
  /// Un export est une LECTURE, offerte à tout rôle qui peut ouvrir l'écran
  /// (PA-119). Il porte sur CE QUI EST AFFICHÉ, et il DIT son filtre. Une
  /// liste vide se **refuse** : un fichier sans ligne se lirait « aucun
  /// employé », alors qu'il veut dire « le filtre n'a rien retenu ».
  ///
  /// - **Tableur Excel** : le CSV (BOM UTF-8, point-virgule), enregistré par
  ///   la fenêtre « Enregistrer sous ».
  /// - **PDF Officiel A4** : l'état A4 des mêmes colonnes, montants en FCFA,
  ///   totaux des bulletins (`exporterPaiePdfProvider`, directive du PO du
  ///   14/10/2026). Ce n'est pas le bulletin individuel.
  static Future<void> _exporter(BuildContext context, WidgetRef ref) async {
    final etat = await ref.read(etatPaieProvider.future);
    if (!context.mounted) return;

    final format = await choisirFormatExport(
      context,
      titre: 'Exporter — ${etat.titreOnglet}',
    );
    if (format == null || !context.mounted) return;

    final messageur = ScaffoldMessenger.of(context);

    if (etat.vide) {
      messageur.showSnackBar(
        const SnackBar(
          content: Text(
            'Aucune ligne à exporter : la liste affichée est vide.',
            key: Key('paie-export-vide'),
          ),
        ),
      );
      return;
    }

    // La fenêtre « Enregistrer sous », puis le toast commun (14/10/2026).
    await executerExport(
      context,
      () => switch (format) {
        FormatExport.pdf => ref.read(exporterPaiePdfProvider)(etat),
        FormatExport.excel => ref.read(exporterPaieProvider)(etat),
      },
      cleSucces: const Key('paie-export-fait'),
    );
  }
}

/// Le sélecteur de période — `<input type="month">` du maître (l.116).
class _ChoixPeriode extends ConsumerWidget {
  const _ChoixPeriode();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periode = ref.watch(periodeValideProvider);

    return InkWell(
      key: const Key('paie-periode'),
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      onTap: () async {
        final choisi = await showDatePicker(
          context: context,
          initialDate: DateTime(periode.annee, periode.mois),
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
          // Le maître choisit un MOIS, pas un jour : le sélecteur s'ouvre donc
          // sur l'année, et seul le mois de la date retenue compte.
          initialDatePickerMode: DatePickerMode.year,
        );
        if (choisi == null) return;

        ref
            .read(periodePaieProvider.notifier)
            .definir(PeriodePaie.deLaDate(choisi).code);
        if (context.mounted) rafraichirPaie(ref);
      },
      child: Container(
        width: AppLayout.champMoisPaie,
        // `text-[13px] border border-slate-300 rounded-lg px-2.5 py-2`.
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xsPlus,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
          border: Border.all(color: Ardoise.c300),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                periode.libelleLong,
                style: styleContenuCarte(TaillesContenu.t13),
              ),
            ),
            const Icon(
              Icons.calendar_today_outlined,
              size: AppLayout.iconeChamp,
              color: Ardoise.c500,
            ),
          ],
        ),
      ),
    );
  }
}

/* ====================================================================== */
/* Bandeaux                                                                */
/* ====================================================================== */

/// Le référentiel de taux est incomplet — **et l'écran nomme les clés**
/// (l.137-144).
class _BandeauReferentiel extends StatelessWidget {
  const _BandeauReferentiel({required this.clesAbsentes});

  final List<String> clesAbsentes;

  @override
  Widget build(BuildContext context) {
    final style = styleContenuCarte(
      TaillesContenu.t13,
      couleur: PaletteMaitre.rouge900,
    );

    return KeyedSubtree(
      key: const Key('paie-bandeau-referentiel'),
      child: EncadreCarte(
        fond: PaletteMaitre.rouge50,
        bordure: PaletteMaitre.rouge200,
        enfant: Text.rich(
          TextSpan(
            style: style,
            children: [
              TextSpan(
                text: 'Les taux de paie ne sont pas paramétrés.',
                style: style.copyWith(fontWeight: FontWeight.bold),
              ),
              TextSpan(
                text:
                    ' Aucun calcul n’est possible tant que les taux confirmés '
                    'ne sont pas en base : ${clesAbsentes.join(', ')}. Ils '
                    'sont posés par le référentiel de paie de ce poste, qui '
                    'les réinstalle à chaque ouverture de cet écran. Aucune '
                    'valeur n’est supposée à leur place — un taux plausible '
                    'inscrit quelque part deviendrait la règle de production, '
                    'et personne ne le rouvrirait.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Le bandeau **permanent** de la paie — il porte le refus de PA-53
/// (l.213-217).
///
/// Il reste affiché sur les cinq onglets : un coût employeur en fourchette sans
/// son explication se lirait comme une imprécision d'affichage.
class _BandeauRisquesProfessionnels extends StatelessWidget {
  const _BandeauRisquesProfessionnels();

  @override
  Widget build(BuildContext context) {
    final style = styleContenuCarte(
      TaillesContenu.t13,
      couleur: PaletteMaitre.ambre900,
    );
    final gras = style.copyWith(fontWeight: FontWeight.bold);

    return KeyedSubtree(
      key: const Key('paie-bandeau-rp'),
      child: EncadreCarte(
        fond: PaletteMaitre.ambre50,
        bordure: PaletteMaitre.ambre200,
        enfant: Text.rich(
          TextSpan(
            style: style,
            children: [
              TextSpan(
                text: 'Charge patronale incomplète — un seul taux manque.',
                style: gras,
              ),
              const TextSpan(text: ' CNSS '),
              TextSpan(text: 'risques professionnels : 1 % à 4 %', style: gras),
              const TextSpan(
                text:
                    ' selon le niveau de risque de l’entreprise. La catégorie '
                    'applicable à l’hôtellerie-restauration n’est pas '
                    'confirmée par la CNSS, et elle n’est pas supposée ici : '
                    'sur une masse salariale annuelle, l’écart entre 1 % et '
                    '4 % est un redressement. Tous les coûts employeur sont '
                    'donc affichés en ',
              ),
              TextSpan(text: 'fourchette', style: gras),
              const TextSpan(
                text:
                    '. CNSS pension 6,4 %, prestations familiales 9 % et VPS '
                    '4 % sont, eux, confirmés.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ====================================================================== */
/* Bande d'indicateurs                                                     */
/* ====================================================================== */

/// La bande des six indicateurs (l.148-194), **repliable** comme la vue.
class _BandeIndicateurs extends ConsumerWidget {
  const _BandeIndicateurs();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final indicateurs = ref.watch(indicateursPaieProvider).value;

    return AccordeonIndicateurs(
      cleBouton: const Key('paie-kpis-bascule'),
      titre: 'Indicateurs de la paie',
      contenu: GrilleIndicateurs(
        cartes: indicateurs == null ? _cartesEnCours : _cartes(indicateurs),
      ),
    );
  }

  /// La base n'a pas encore répondu : un tiret, jamais un zéro qui aurait
  /// l'air d'une mesure.
  static const List<Widget> _cartesEnCours = [
    CarteKpi(
      cle: Key('paie-kpi-effectif'),
      libelle: 'Effectif actif',
      valeur: tiret,
    ),
    CarteKpi(
      cle: Key('paie-kpi-masse'),
      libelle: 'Masse salariale',
      valeur: tiret,
    ),
    CarteKpi(
      cle: Key('paie-kpi-cout'),
      libelle: 'Coût employeur',
      valeur: tiret,
    ),
    CarteKpi(cle: Key('paie-kpi-net'), libelle: 'Net du mois', valeur: tiret),
    CarteKpi(
      cle: Key('paie-kpi-vps'),
      libelle: 'VPS à reverser',
      valeur: tiret,
    ),
    CarteKpi(
      cle: Key('paie-kpi-manquants'),
      libelle: 'Bulletins manquants',
      valeur: tiret,
    ),
  ];

  List<Widget> _cartes(IndicateursPaie i) {
    final cout = i.coutMasse;

    return [
      CarteKpi(
        cle: const Key('paie-kpi-effectif'),
        libelle: 'Effectif actif',
        valeur: '${i.effectifAffiche}',
        detail: '${i.effectifTotal} au total',
      ),
      CarteKpi(
        cle: const Key('paie-kpi-masse'),
        libelle: 'Masse salariale',
        valeur: formaterFcfa(i.masseSalariale),
        detail: 'Salaires de base',
      ),
      // ⚠ FOURCHETTE, jamais un chiffre unique : la valeur est la borne BASSE
      // et le détail nomme la borne haute. Afficher la seule borne basse comme
      // « le » coût serait communiquer un coût réel qui ne l'est pas.
      CarteKpi(
        cle: const Key('paie-kpi-cout'),
        libelle: 'Coût employeur',
        valeur: cout == null ? tiret : formaterFcfa(cout.coutMin),
        detail: cout == null ? tiret : 'à ${formaterFcfa(cout.coutMax)}',
        accent: PaletteMaitre.ambre600,
      ),
      CarteKpi(
        cle: const Key('paie-kpi-net'),
        libelle: 'Net du mois',
        valeur: formaterFcfa(i.totaux.net),
        detail: '${i.totaux.effectif} bulletin(s)',
      ),
      CarteKpi(
        cle: const Key('paie-kpi-vps'),
        libelle: 'VPS à reverser',
        valeur: formaterFcfa(i.totaux.ventilation.vps),
        detail: '4 % — au plus tard le 10',
      ),
      CarteKpi(
        cle: const Key('paie-kpi-manquants'),
        libelle: 'Bulletins manquants',
        valeur: '${i.bulletinsManquants}',
        detail: i.sansNumeroCnss > 0
            ? '${i.sansNumeroCnss} sans n° CNSS'
            : 'Tous immatriculés',
        accent: i.bulletinsManquants > 0
            ? PaletteMaitre.rouge600
            : PaletteMaitre.emeraude600,
      ),
    ];
  }
}

/* ====================================================================== */
/* Onglets et filtres                                                      */
/* ====================================================================== */

/// `flex flex-wrap gap-1.5 mb-4` — le style d'onglet de `Onglets::classes()`
/// (`px-3.5 py-2 rounded-lg text-[13px] font-semibold`, actif navy et blanc,
/// inactif blanc, `slate-500` et bordé).
class _BarreOnglets extends ConsumerWidget {
  const _BarreOnglets();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actif = ref.watch(ongletPaieProvider);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Wrap(
        spacing: AppSpacing.xxs,
        runSpacing: AppSpacing.xxs,
        children: [
          for (final onglet in OngletPaie.values)
            Material(
              key: Key('paie-onglet-${onglet.name}'),
              color: onglet == actif ? AppColors.navy : AppColors.neutre0,
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
              child: InkWell(
                onTap: () =>
                    ref.read(ongletPaieProvider.notifier).definir(onglet),
                borderRadius: BorderRadius.circular(AppRadius.roundedLg),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.smPlus,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.roundedLg),
                    // Le contour existe aussi sur l'onglet actif (marine sur
                    // marine) : la vue étire tous les boutons à la hauteur du
                    // plus haut, ici le contour fait le même office.
                    border: Border.all(
                      color: onglet == actif ? AppColors.navy : Ardoise.c200,
                    ),
                  ),
                  child: Text(
                    onglet.libelle,
                    style: styleContenuCarte(
                      TaillesContenu.t13,
                      poids: FontWeight.w600,
                      couleur: onglet == actif
                          ? AppColors.neutre0
                          : Ardoise.c500,
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

/// Les filtres (l.220-256) : `bg-white rounded-xl border border-slate-200
/// p-3.5 mb-4`, puis une rangée `flex flex-wrap gap-2.5 items-center` — la
/// recherche (`flex-1 min-w-[200px]`), trois listes, un espaceur `flex-1`, le
/// bouton « + Employé ».
class _BarreFiltres extends ConsumerStatefulWidget {
  const _BarreFiltres();

  @override
  ConsumerState<_BarreFiltres> createState() => _BarreFiltresState();
}

class _BarreFiltresState extends ConsumerState<_BarreFiltres> {
  final _terme = TextEditingController();

  @override
  void dispose() {
    _terme.dispose();
    super.dispose();
  }

  /// La valeur « tous » d'une liste de la vue : `value=""`.
  static const String _tous = '';

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(servicesRhProvider).value ?? const [];
    final peutEcrire = ref.watch(peutEcrirePaieProvider);

    final bordure = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      borderSide: const BorderSide(color: Ardoise.c300),
    );

    // `relative flex-1 min-w-[200px]` : la loupe est à `left-3`, `pl-9` lui
    // réserve la place.
    final recherche = TextField(
      key: const Key('paie-recherche'),
      controller: _terme,
      style: styleContenuCarte(TaillesContenu.t13),
      decoration: InputDecoration(
        hintText: 'Nom, matricule, poste…',
        hintStyle: styleContenuCarte(TaillesContenu.t13, couleur: Ardoise.c400),
        isDense: true,
        prefixIcon: const Padding(
          padding: EdgeInsets.only(left: AppSpacing.sm),
          child: Icon(
            Icons.search,
            size: AppLayout.iconeChamp,
            color: Ardoise.c400,
          ),
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: AppLayout.prefixeRechercheEtats,
          minHeight: 0,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        border: bordure,
        enabledBorder: bordure,
        focusedBorder: bordure.copyWith(
          borderSide: const BorderSide(color: AppColors.gold),
        ),
      ),
      onChanged: (valeur) =>
          ref.read(recherchePersonnelProvider.notifier).definir(valeur),
    );

    final service = ListeFiltre<String>(
      cleListe: const Key('paie-filtre-service'),
      largeur: AppLayout.filtreServicePaie,
      valeur: ref.watch(filtreServicePaieProvider) ?? _tous,
      options: [
        (_tous, 'Tous les services'),
        for (final s in services) (s.id, s.libelle),
      ],
      onChange: (v) => ref
          .read(filtreServicePaieProvider.notifier)
          .definir(v == null || v == _tous ? null : v),
    );

    final contrat = ListeFiltre<String>(
      cleListe: const Key('paie-filtre-contrat'),
      largeur: AppLayout.filtreContratPaie,
      valeur: ref.watch(filtreContratProvider)?.code ?? _tous,
      options: [
        (_tous, 'Tous les contrats'),
        for (final type in TypeContrat.values) (type.code, type.code),
      ],
      onChange: (v) => ref
          .read(filtreContratProvider.notifier)
          .definir(TypeContrat.values.where((t) => t.code == v).firstOrNull),
    );

    final statut = ListeFiltre<FiltreStatutPersonnel>(
      cleListe: const Key('paie-filtre-statut'),
      largeur: AppLayout.filtreStatutPaie,
      valeur: ref.watch(filtreStatutPaieProvider),
      options: [for (final f in FiltreStatutPersonnel.values) (f, f.libelle)],
      onChange: (v) => ref
          .read(filtreStatutPaieProvider.notifier)
          .definir(v ?? FiltreStatutPersonnel.actifs),
    );

    final bouton = peutEcrire
        ? BoutonEnteteCarte(
            key: const Key('paie-nouvel-employe'),
            libelle: '+ Employé',
            style: StyleBoutonEntete.plein,
            onPressed: () => ouvrirFicheEmploye(context, ref),
          )
        : null;

    return Container(
      // `p-3.5 mb-4`.
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.smPlus),
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: Ardoise.c200),
      ),
      child: LayoutBuilder(
        builder: (context, contraintes) {
          // `gap-2.5` — 10 px.
          const ecart = AppSpacing.xsPlus;
          final fixes =
              service.largeur + contrat.largeur + statut.largeur + ecart * 3;
          final minimum =
              AppLayout.rechercheMinCarteRestaurant +
              fixes +
              (bouton == null ? 0 : AppLayout.boutonNouvelEmployePaie + ecart);

          if (contraintes.maxWidth >= minimum) {
            return Row(
              children: [
                Expanded(child: recherche),
                const SizedBox(width: ecart),
                service,
                const SizedBox(width: ecart),
                contrat,
                const SizedBox(width: ecart),
                statut,
                // `<div class="flex-1"></div>` : il se partage l'espace libre
                // avec la recherche, à parts égales.
                const SizedBox(width: ecart),
                const Expanded(child: SizedBox.shrink()),
                if (bouton != null) ...[const SizedBox(width: ecart), bouton],
              ],
            );
          }

          // Trop étroit : `flex-wrap` — la recherche prend sa ligne.
          return Wrap(
            spacing: ecart,
            runSpacing: ecart,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(width: contraintes.maxWidth, child: recherche),
              service,
              contrat,
              statut,
              ?bouton,
            ],
          );
        },
      ),
    );
  }
}

/* ====================================================================== */
/* Le panneau de l'onglet courant                                          */
/* ====================================================================== */

class _PanneauCourant extends ConsumerWidget {
  const _PanneauCourant();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (ref.watch(ongletPaieProvider)) {
      case OngletPaie.personnel:
        return PanneauPersonnel(
          onEtablir: (employe) => ouvrirEtablissement(context, ref, employe),
          onModifier: (employe) =>
              ouvrirFicheEmploye(context, ref, employe: employe),
          onArchiver: (id) => ouvrirArchivage(context, ref, employeId: id),
        );
      case OngletPaie.bulletins:
        return PanneauBulletins(
          onGenererManquants: () => _genererManquants(context, ref),
          onAnnuler: (bulletin) => ouvrirAnnulation(context, ref, bulletin),
        );
      case OngletPaie.livre:
        return const PanneauLivre();
      case OngletPaie.declarations:
        return const PanneauDeclarations();
      case OngletPaie.bareme:
        return const PanneauBareme();
    }
  }

  /// « Générer les bulletins manquants ».
  ///
  /// Un salarié **refusé** (barème ITS dépassé) n'interrompt pas les autres :
  /// son motif est rendu, nommé. Échouer le lot entier ferait perdre neuf
  /// bulletins corrects pour un cas non tranché.
  Future<void> _genererManquants(BuildContext context, WidgetRef ref) async {
    final bilan = await ref
        .read(bulletinPaieServiceProvider)
        .etablirBulletinsManquants(ref.read(periodeValideProvider).code);

    if (!context.mounted) return;
    rafraichirPaie(ref);

    final messages = <String>[
      if (bilan.sansEffet) 'Tous les bulletins sont déjà établis.',
      if (bilan.etablis > 0) '${bilan.etablis} bulletin(s) établi(s).',
      for (final refus in bilan.refus) '${refus.employe} : ${refus.motif}',
    ];

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          messages.join('\n'),
          key: const Key('paie-bilan-generation'),
        ),
      ),
    );
  }
}
