// Vue Blade maîtresse (PA-183) : pwa/depenses/depenses.blade.php
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/format/formats.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../restaurant/presentation/widgets/coquille_restaurant.dart';
import '../../restaurant/presentation/widgets/corps_carte_commun.dart'
    show styleContenuCarte;
import '../domain/entities/depense.dart';
import '../domain/indicateurs_depenses.dart';
import 'providers_depenses.dart';
import 'widgets/barre_filtres_depenses.dart';
import 'widgets/modale_depense.dart';
import 'widgets/table_depenses.dart';

/// L'écran **Dépense courante** (M10) — `depenses.blade.php`.
///
/// @see EF-M10-02 Saisie des écritures comptables
/// @see RG-11 Immuabilité — la correction passe par contre-passation
/// @see RG-19 Convention d'export
///
/// ## LOCAL PUR — c'est le premier écran de M10 dans ce cas
///
/// Tout vient de la base Drift du poste, et rien n'en part. C'est l'inverse de
/// M4, M6, M7, M8, M11 et Paramètres, qui exigent le réseau. Il n'y a donc
/// aucune branche « si connecté », aucun badge de synchronisation, et l'écran
/// ne dit jamais « en attente » : `depenses` n'est à aucun registre
/// synchronisable, une opération en file y serait rejetée à chaque tentative,
/// et l'annoncer serait l'indicateur qui affirme un état qu'il n'a pas vérifié
/// (PA-59/60/61).
///
/// ## L'ordre des blocs est celui de la vue
///
/// En-tête (l.86-100) ; bande d'indicateurs repliable (l.152-202) ; cadre du
/// tableau avec sa barre de contrôles (l.205-305) ; modales après `</main>`
/// (l.324-517). Un bloc « Ce que cet écran ne rend pas » figurait ici entre le
/// tableau et le bas de page : la vue le retire par directive du Product Owner
/// du 02/09/2026 (l.307-318, « un écran dit ce qu'il FAIT »). Il a été retiré
/// le 09/10/2026 ; ce qui reste non porté se déclare ICI, dans le code, avec
/// sa raison, et dans le contrôle qui le concerne.
///
/// ## La pièce comptable est rendue depuis la v16 (10/10/2026)
///
/// La pastille « non comptabilisée » et le bouton « Comptabiliser »
/// (l.283-287), le refus de rattrapage (l.107-111) et l'indicateur « Sans
/// écriture » (l.196-200) sont RENDUS : le poste a un moteur
/// comptable, et chacun se lit de `Depense.estComptabilisee` (la clé étrangère
/// vers la pièce), jamais d'un drapeau. Le champ « Centre de coût » est dans la
/// modale (l.481-490).
///
/// ## Le bandeau de rattrapage n'est plus rendu (PO, 14/10/2026)
///
/// Directive du Product Owner du 14/10/2026 : le bandeau ambre « N dépense(s)
/// ne portent aucune écriture comptable… » (vue l.120-133) est RETIRÉ de
/// l'écran. Son `<select>` « Centre de coût de la pièce (obligatoire pour
/// comptabiliser) » (vue l.126-131) passe dans une fenêtre « Comptabiliser la
/// dépense » (`widgets/modale_comptabiliser_depense.dart`), ouverte par le
/// bouton « Comptabiliser » de la ligne.
///
/// ## Le rattrapage exige un centre EXPLICITE (10/10/2026)
///
/// La fenêtre démarre sur « Choisir un centre » : la dépense ne mémorise aucun
/// centre, et aucun compte de charge n'en porte par défaut ; « Comptabiliser »
/// y reste grisé tant qu'aucun centre n'est choisi. Le centre choisi va aux
/// lignes de charge ET de trésorerie ; sans centre, le moteur refuse avec la
/// phrase de RG-12. Cela remplace le D209 du ticket (« ne peut aboutir que si
/// le compte porte un centre par défaut »), périmé depuis que le serveur a
/// changé `DepenseService::comptabiliser`.
///
/// ⚠ **Un libellé de la vue n'est pas rendu, et ce n'est pas un oubli** :
/// « TATACORA AFRIQUE » (vue l.80-83, `<h2>` de l'en-tête d'impression,
/// `hidden print:block`). Ce client n'a pas de feuille d'impression d'écran : le
/// seul document de cet écran est le CSV, qui porte son titre et sa portée mais
/// pas la marque, et le choix PDF n'est pas produit (voir
/// [BarreFiltresDepenses.pdfNonProduit]). C'était déjà l'unique libellé absent
/// de la page à la mesure précédente.
///
/// ## Ce que la vue porte et que cet écran ne peut pas rendre (09/10/2026)
///
/// - **Lien « reçu »** (l.272-274) : aucune colonne ne porte de pièce jointe
///   et aucun sélecteur de fichier n'est embarqué. La pastille « sans reçu »
///   est vraie pour toutes les lignes et son infobulle le dit.
/// - **État replié des indicateurs, d'une session à l'autre** (l.152) : la vue
///   le retient en `localStorage`. Aucun magasin de préférences n'est embarqué.
/// - **Le choix PDF de l'export** : voir [BarreFiltresDepenses.pdfNonProduit].
///
/// - Modifier ou supprimer une dépense : la vue ne l'offre pas non plus. Le
///   « D » de CRUD n'existe nulle part dans ce dépôt, et le serveur n'annule
///   jamais la pièce d'une dépense : ce poste ne porte que ce qu'il fait.
class EcranDepenses extends ConsumerWidget {
  const EcranDepenses({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liste = ref.watch(depensesFiltreesProvider);
    final depenses = switch (liste) {
      AsyncData(value: final v) => v,
      _ => null,
    };
    final filtre = ref.watch(filtreDepensesProvider);
    final succes = ref.watch(messageSuccesDepenseProvider);
    final refusRattrapage = ref.watch(refusRattrapageDepenseProvider);
    final largeur = MediaQuery.sizeOf(context).width;

    return SingleChildScrollView(
      // `p-4 sm:p-5 lg:p-8` (l.77) : le point de rupture est celui de l'ÉCRAN.
      padding: EdgeInsets.all(
        largeur >= AppBreakpoints.lg
            ? AppSpacing.xl
            : largeur >= AppBreakpoints.sm
            ? AppSpacing.mdPlus
            : AppSpacing.md,
      ),
      child: Align(
        alignment: Alignment.topCenter,
        // `max-w-[1500px] mx-auto` (l.77).
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.pageDepenses),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _EnTete(),
              // `mb-5` — 20 px.
              const SizedBox(height: AppSpacing.mdPlus),
              if (succes != null) ...[
                _BandeauSucces(message: succes),
                // `mb-4` — 16 px.
                const SizedBox(height: AppSpacing.md),
              ],
              if (refusRattrapage != null) ...[
                _BandeauRefusRattrapage(message: refusRattrapage),
                const SizedBox(height: AppSpacing.md),
              ],
              // Le bandeau ambre de rattrapage de la vue (l.120-133) n'est
              // plus rendu : directive du Product Owner du 14/10/2026.
              _Indicateurs(depenses: depenses),
              const SizedBox(height: AppSpacing.mdPlus),
              CadreTableauRestaurant(
                corps: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BarreFiltresDepenses(depenses: depenses),
                    TableDepenses(depenses: depenses, filtre: filtre.applique),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// L'en-tête de la vue (l.86-100) : le titre, le sous-titre et son lien, le
/// bouton « Nouvelle Dépense ».
class _EnTete extends ConsumerStatefulWidget {
  const _EnTete();

  @override
  ConsumerState<_EnTete> createState() => _EnTeteState();
}

class _EnTeteState extends ConsumerState<_EnTete> {
  /// Le lien « Approvisionnement » du sous-titre. Il vit dans un état parce
  /// qu'un `TapGestureRecognizer` se libère : posé dans un widget sans état, il
  /// fuirait à chaque reconstruction.
  late final TapGestureRecognizer _versApprovisionnement;

  @override
  void initState() {
    super.initState();
    _versApprovisionnement = TapGestureRecognizer()
      ..onTap = () {
        // `maybeOf` et non `of` : hors routeur — dans un test de widget, par
        // exemple — le lien ne fait rien plutôt que de lever. Le sous-titre
        // reste lisible, ce qui est sa fonction première.
        GoRouter.maybeOf(context)?.go('/approvisionnement');
      };
  }

  @override
  void dispose() {
    _versApprovisionnement.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final peutEcrire = ref
        .watch(droitsProvider)
        .peutEcrire(ModuleTatacora.m10Comptabilite);
    final sousTitre = styleContenuCarte(
      TaillesContenu.t12,
      couleur: Ardoise.c500,
    );

    // `flex flex-wrap items-start justify-between gap-3` (l.86).
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.start,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        ConstrainedBox(
          // `max-w-3xl` sur le sous-titre (l.89) : sans cette borne, la phrase
          // prend toute la ligne et le bouton passe SOUS le titre.
          constraints: const BoxConstraints(maxWidth: AppLayout.largeur3xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Le titre de la vue (l.88), au mot. MESURÉ : 17 px à
              // 1 383 px, pas 18,5 — `lg:text-xl` ne s'applique pas dans
              // `<main>`, où `main .text-lg` l'emporte en spécificité
              // (`app.css`).
              const Text('Dépense courante', style: TextesRestaurant.titrePage),
              // `mt-1` — 4 px.
              const SizedBox(height: AppSpacing.unit),
              // Le sous-titre de la vue (l.89-93), en morceaux : son fragment
              // en gras et son lien vers l'Approvisionnement en font partie.
              // Il n'est pas décoratif — il dit ce qui distingue une dépense
              // décaissée d'un achat fournisseur, et c'est la confusion que le
              // manuel signale en alerte au chapitre 9.1.
              Text.rich(
                TextSpan(
                  style: sousTitre,
                  children: [
                    const TextSpan(text: 'Les charges d\'exploitation '),
                    const TextSpan(
                      text: 'décaissées directement',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const TextSpan(
                      text:
                          ' — le marché du matin, un transport, un dépannage. '
                          'Elles n\'ont ni bon de commande ni délai de '
                          'règlement : une dépense suivie auprès d\'un '
                          'fournisseur relève de ',
                    ),
                    TextSpan(
                      text: 'Approvisionnement',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.gold,
                      ),
                      recognizer: _versApprovisionnement,
                    ),
                    const TextSpan(
                      text:
                          '. Confondre les deux ferait apparaître en dettes '
                          'fournisseurs des sommes déjà sorties de la caisse.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Le bouton n'apparaît pas sans droit d'écriture sur M10 : présenter un
        // formulaire à quelqu'un qui ne pourra pas l'enregistrer lui fait
        // perdre sa saisie et ne lui apprend rien.
        if (peutEcrire)
          FilledButton.icon(
            key: const Key('depenses-nouvelle'),
            onPressed: () => ouvrirModaleDepense(context),
            style: FilledButton.styleFrom(
              // `px-4 py-2.5` (l.96).
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xsPlus,
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: AppColors.navy,
              foregroundColor: AppColors.neutre0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.roundedLg),
              ),
              iconSize: AppLayout.iconeBoutonNouvelleDepense,
            ),
            icon: const Icon(Icons.add),
            // Le libellé de la vue (l.98), majuscule comprise ; `text-sm
            // font-semibold`.
            label: Text(
              'Nouvelle Dépense',
              style: styleContenuCarte(
                TaillesContenu.sm,
                poids: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

/// Le bandeau vert qui suit un enregistrement (l.102-105).
class _BandeauSucces extends ConsumerWidget {
  const _BandeauSucces({required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      key: const Key('depenses-succes'),
      // `px-4 py-3` (l.103).
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.succesFond,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: AppColors.succes),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: styleContenuCarte(
                TaillesContenu.t13,
                poids: FontWeight.w600,
                couleur: AppColors.succes,
              ),
            ),
          ),
          // Le bandeau de la vue disparaît à la navigation suivante ; ici il
          // reste tant qu'on ne le ferme pas — d'où ce bouton, qui n'est pas
          // dans la vue.
          IconButton(
            key: const Key('depenses-succes-fermer'),
            tooltip: 'Fermer',
            icon: const Icon(Icons.close),
            onPressed: () =>
                ref.read(messageSuccesDepenseProvider.notifier).effacer(),
          ),
        ],
      ),
    );
  }
}

/// La bande des six indicateurs (l.152-202), **repliable à toutes les
/// largeurs** comme la vue.
class _Indicateurs extends ConsumerWidget {
  const _Indicateurs({required this.depenses});

  final List<Depense>? depenses;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deplies = ref.watch(kpisDepliesProvider);
    final k = depenses == null ? null : IndicateursDepenses.calculer(depenses!);
    final largeur = MediaQuery.sizeOf(context).width;

    // `grid sm:grid-cols-3 xl:grid-cols-6 grid-cols-2` (l.159).
    final colonnes = largeur >= AppBreakpoints.xl
        ? 6
        : largeur >= AppBreakpoints.sm
        ? 3
        : 2;

    final cartes = <Widget>[
      _CarteIndicateur(
        cle: const Key('depenses-kpi-total'),
        libelle: 'Total décaissé',
        valeur: k == null ? null : formaterFcfa(k.total),
        detail: k == null ? _detailEnCours : '${k.nombre} dépense(s)',
        infobulle: k == null ? _lectureEnCours : null,
      ),
      _CarteIndicateur(
        cle: const Key('depenses-kpi-moyenne'),
        libelle: 'Dépense moyenne',
        // « — » quand aucune dépense n'est saisie : zéro franc dépensé et
        // aucune dépense ne disent pas la même chose (Article 7).
        valeur: k?.moyenne == null ? null : formaterFcfa(k!.moyenne!),
        detail: 'sur la période filtrée',
        infobulle: k != null && k.moyenne == null
            ? 'Aucune dépense dans la liste affichée : il n’y a rien à '
                  'moyenner.'
            : (k == null ? _lectureEnCours : null),
      ),
      _CarteIndicateur(
        cle: const Key('depenses-kpi-marche'),
        libelle: 'Marché',
        valeur: k == null ? null : formaterFcfa(k.marche),
        detail: 'denrées',
        infobulle: k == null ? _lectureEnCours : null,
      ),
      _CarteIndicateur(
        cle: const Key('depenses-kpi-services'),
        libelle: 'Services',
        valeur: k == null ? null : formaterFcfa(k.services),
        detail: 'charges externes',
        infobulle: k == null ? _lectureEnCours : null,
      ),
      _CarteIndicateur(
        cle: const Key('depenses-kpi-caisse'),
        libelle: 'Caisse',
        valeur: k == null ? null : formaterFcfa(k.caisse),
        detail: 'espèces',
        infobulle: k == null ? _lectureEnCours : null,
      ),
      // Le sixième se LIT des pièces (vue l.196-200) : en alerte quand il n'est
      // pas nul, pour qu'il ne passe pas pour un chiffre ordinaire. Tant que la
      // base n'a pas répondu, « — » : « 0 » dirait « tout est comptabilisé »
      // sans que personne l'ait vérifié.
      _CarteIndicateur(
        cle: const Key('depenses-kpi-sans-ecriture'),
        libelle: 'Sans écriture',
        valeur: k == null ? null : '${k.sansEcriture}',
        couleurValeur: k == null
            ? null
            : (k.sansEcriture > 0 ? AppColors.erreur : AppColors.succes),
        detail: k == null
            ? _detailEnCours
            : (k.sansEcriture > 0 ? 'à régulariser' : 'tout est comptabilisé'),
        infobulle: k == null ? _lectureEnCours : null,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // La bascule de la vue (l.153-157) — visible à TOUTES les largeurs
        // depuis le 03/09/2026 : au-delà de 640 px, six cartes mangeaient la
        // hauteur du tableau sans qu'aucun contrôle ne permette de les
        // replier. Elle n'a pas d'icône à la vue : tout le bandeau est la
        // zone de clic.
        InkWell(
          key: const Key('depenses-kpis-bascule'),
          borderRadius: BorderRadius.circular(AppRadius.roundedXl),
          onTap: () => ref.read(kpisDepliesProvider.notifier).basculer(),
          child: Container(
            // `px-4 py-3 border border-slate-200 rounded-xl bg-white`.
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.neutre0,
              borderRadius: BorderRadius.circular(AppRadius.roundedXl),
              border: Border.all(color: Ardoise.c200),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // `text-sm font-bold text-slate-700` (l.155).
                Text(
                  'Indicateurs de la période',
                  style: styleContenuCarte(
                    TaillesContenu.sm,
                    poids: FontWeight.bold,
                    couleur: Ardoise.c700,
                  ),
                ),
                // `hidden sm:inline` (l.156) : masquée sous 640 px.
                if (largeur >= AppBreakpoints.sm)
                  Text(
                    'Repliez la bande pour gagner de la hauteur de tableau.',
                    style: styleContenuCarte(
                      TaillesContenu.t11,
                      couleur: Ardoise.c400,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (deplies) ...[
          // `mt-3` — 12 px.
          const SizedBox(height: AppSpacing.sm),
          for (var debut = 0; debut < cartes.length; debut += colonnes) ...[
            // `gap-3` — 12 px entre les rangées.
            if (debut > 0) const SizedBox(height: AppSpacing.sm),
            // `IntrinsicHeight` et non `stretch` seul : une `Row` étirée dans
            // une liste défilante reçoit une hauteur INFINIE et fait exploser
            // la contrainte (doctrine §3.3).
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < colonnes; i++) ...[
                    // `gap-3` — 12 px entre les colonnes.
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
          ],
        ],
      ],
    );
  }

  /// La seconde ligne d'une carte dont la base n'a pas encore répondu.
  static const String _detailEnCours = 'lecture en cours';

  static const String _lectureEnCours =
      'La base locale n’a pas encore répondu. Aucun chiffre n’est affiché '
      'plutôt qu’un zéro qui aurait l’air d’une mesure.';
}

/// Une carte de la bande (l.160-200) : `bg-white rounded-xl border
/// border-slate-200 p-3.5`, libellé en capitales, valeur à 18 px, détail.
///
/// ## Pourquoi pas `CarteIndicateurRestaurant`
///
/// Cette carte-là suit `carte-module.js` : libellé en `font-semibold`, valeur
/// à 17 px. La vue de la dépense courante pose son libellé SANS graisse, sa
/// valeur en `text-[18px] font-bold tabular-nums` (palier non remappé par
/// `app.css`) et sa seconde ligne en `mt-0.5`. Les y ramener serait
/// approximer (Article 1).
///
/// [valeur] `null` : la donnée n'existe pas, la carte affiche « — » et
/// [infobulle] dit pourquoi. Jamais « 0 ».
class _CarteIndicateur extends StatelessWidget {
  const _CarteIndicateur({
    required Key cle,
    required this.libelle,
    required this.valeur,
    required this.detail,
    this.infobulle,
    this.couleurValeur,
  }) : super(key: cle);

  final String libelle;
  final String? valeur;
  final String detail;

  /// La couleur de la valeur quand elle n'est pas le navy ordinaire (le compteur
  /// de vigilance de la vue, `var(--erreur)` / `var(--succes)`).
  final Color? couleurValeur;

  /// La raison d'une absence — au survol, jamais dans la carte.
  final String? infobulle;

  @override
  Widget build(BuildContext context) {
    final carte = Container(
      // `p-3.5` — 14 px.
      padding: const EdgeInsets.all(AppSpacing.smPlus),
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: Ardoise.c200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // `text-[11px] uppercase tracking-wide text-slate-400` (l.161).
          Text(
            libelle.toUpperCase(),
            style: styleContenuCarte(
              TaillesContenu.t11,
              couleur: Ardoise.c400,
              interlettrage: TaillesContenu.t11 * AppTextStyles.suiviLarge,
            ),
          ),
          // `mt-1` — 4 px.
          const SizedBox(height: AppSpacing.unit),
          // `text-[18px] font-bold mt-1 tabular-nums` (l.162).
          Text(
            valeur ?? CarteIndicateurRestaurant.absent,
            style: styleContenuCarte(
              TaillesContenu.t18,
              poids: FontWeight.bold,
              couleur: valeur == null
                  ? Ardoise.c400
                  : (couleurValeur ?? AppColors.navy),
            ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          // `mt-0.5` — 2 px.
          const SizedBox(height: AppSpacing.demi),
          // `text-[11px] text-slate-400` (l.163).
          Text(
            detail,
            style: styleContenuCarte(TaillesContenu.t11, couleur: Ardoise.c400),
          ),
        ],
      ),
    );

    if (infobulle == null) return carte;
    return Tooltip(message: infobulle!, child: carte);
  }
}

/// Les libellés du bandeau de rattrapage, **au mot** de `lang/fr/depenses_pwa.php`
/// — et un test les confronte au VRAI traducteur PHP
/// (`depenses_contre_serveur_test.dart`, opération `libelles`) plutôt que de les
/// figer deux fois.
///
/// Le bandeau n'est plus rendu (PO, 14/10/2026) : [centre] et [choisir]
/// servent la fenêtre « Comptabiliser la dépense » ; [bandeau] est gardé parce
/// que ce test le lit encore.
abstract final class LibellesRattrapage {
  /// `rattrapage_centre` : le libellé du `<select>`.
  static const String centre =
      'Centre de coût de la pièce (obligatoire pour comptabiliser)';

  /// `rattrapage_centre_choisir` : l'option vide, état de départ du choix.
  static const String choisir = 'Choisir un centre';

  /// `rattrapage_bandeau` : la phrase du bandeau.
  static String bandeau(Object nombre) =>
      '$nombre dépense(s) ne portent aucune écriture comptable : elles '
      'manquent au grand livre, à la balance et au compte de résultat tant '
      'que la pièce n\'a pas été passée.';
}

/// Le refus d'un rattrapage (`@error('rattrapage')`, l.107-111) : la phrase du
/// moteur, qui est celle du serveur.
class _BandeauRefusRattrapage extends ConsumerWidget {
  const _BandeauRefusRattrapage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      key: const Key('depenses-refus-rattrapage'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.badgeRougeFond,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: AppColors.bordureRefusRouge),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: styleContenuCarte(
                TaillesContenu.t13,
                poids: FontWeight.w600,
                couleur: AppColors.erreur,
              ),
            ),
          ),
          // La vue efface le refus à la navigation suivante ; ici il reste
          // jusqu'au prochain geste ou jusqu'à ce qu'on le ferme.
          IconButton(
            key: const Key('depenses-refus-rattrapage-fermer'),
            tooltip: 'Fermer',
            icon: const Icon(Icons.close),
            onPressed: () =>
                ref.read(refusRattrapageDepenseProvider.notifier).effacer(),
          ),
        ],
      ),
    );
  }
}
