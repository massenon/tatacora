/// L'onglet **« Plan d'Hébergement »** — le parc, ses cartes et son CRUD.
///
/// Vue Blade maîtresse (PA-183) : pwa/hebergement/hebergement.blade.php
/// (panneau `panneau-plan-hebergement`, l.126-367).
///
/// ## Pourquoi cet onglet existe (14/09/2026)
///
/// Il était **refusé**, et le refus reposait sur une raison qui a cessé d'être
/// vraie : « `unites_hebergement.statut` porte le cycle mais PERSONNE ne
/// l'écrit ». Le serveur l'écrit depuis le 31/08/2026, et surtout le poste est
/// passé **zéro réseau** : le parc descendait de `GET /hebergement/parc`, et
/// plus rien ne l'alimentait. Un poste neuf affichait « le parc n'a pas encore
/// été renseigné » — un message honnête décrivant un état dont **aucun chemin
/// ne permettait de sortir**, et aucune réservation n'était possible.
///
/// Décision du Product Owner du 14/09/2026 : le parc se saisit sur le poste.
///
/// ## La pastille est un CALCUL, jamais la colonne lue seule
///
/// C'est la première phrase de l'en-tête de la vue, et RG-02 : elle porte la
/// disponibilité **du jour**, dérivée des réservations. `etat_du_jour.dart` en
/// tient la dérivation, avec l'ordre des tests — la maintenance prime, puis le
/// ménage, puis qui dort là ce soir, puis qui est attendu. Sans état calculé,
/// la pastille dit « — » (l.233) : elle ne retombe pas sur « Libre ».
///
/// ## Reprise sur la structure de la vue (09/10/2026)
///
/// Barre d'outils (l.159-198), grille de cartes TOUJOURS posée (l.226-322),
/// puis l'état vide OU la pagination (l.326-358). Le nombre de colonnes suit
/// les points de rupture de la FENÊTRE (`md` 768 px : 2 ; `xl` 1 280 px : 3),
/// jamais la largeur du contenu — une barre latérale déployée fausserait la
/// décision.
///
/// ## Ce que la vue pose et que cet onglet NE REND PAS
///
/// Chaque refus est daté et vérifié contre les tables locales : une raison qui
/// a cessé d'être vraie transforme une décision en oubli, et c'est exactement
/// ce qui était arrivé au refus précédent (PA-144).
///
/// - ~~**Check-in et check-out réels** (l.260-273)~~ — PORTÉS le 14/10/2026
///   (lot D, D416) : `sejours_local` existe depuis D408, et les deux boutons
///   passent par `SejourDao`, comme l'accueil — réservation du jour de l'unité
///   (`reservationDuJourDeLUnite`), séjour en cours (`reservationAuSejourEnCoursDeLUnite`),
///   refus et succès aux mots du composant ([MessagesPlanHebergement]). Le
///   motif du 09/10/2026 (« cette table n'existe pas sur ce poste ») est périmé.
/// - **Le PDF de l'export** (l.185-188 et le partiel `modale-export`),
///   09/10/2026 : le choix « PDF Officiel A4 » est offert comme à la vue, mais
///   aucun A4 du parc n'existe (en-tête unique et visas, arbitrage PA-192) ; le
///   clic répond par [MessagesPlanHebergement.pdfNonProduit]. Le tableur (CSV)
///   est réellement écrit ([EtatParc]).
/// - **« Importer »** (l.140-145) : la vue le déclare elle-même refusé,
///   `unites_hebergement` n'ayant aucun moteur d'import.
/// - **La barre d'action groupée** « Supprimer » (l.200-213) : refusée par la
///   vue elle-même — le « D » de CRUD n'existe nulle part dans ce dépôt.
/// - **Bouton « Supprimer » conditionné par la bascule `suppressionActive()`**
///   (vue d'hébergement, l.305-316) — PORTÉ le 13/10/2026, décision du Product
///   Owner (« comme dans la vue ») : le bouton n'existe que si la bascule
///   « Suppression d'un enregistrement » est ouverte en Paramètres
///   (`suppressionActiveProvider`, lu de `parametres_systeme_local`), pour
///   TOUS les rôles qui écrivent — la vue n'y fait pas l'exception des
///   administrateurs de `AutoriseArchivage`. Fermée (son défaut), le bouton est
///   RETIRÉ, pas grisé. L'ancien motif (« aucune table de paramètres locale »)
///   était périmé depuis la v11.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_colors.dart';
// `app_spacing.dart` réexporte `app_radius.dart` : l'importer en plus est
// inutile, et l'analyseur le signale.
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/modale_export.dart';
import '../../../../shared_widgets/toast_export.dart';
import '../../../parametres/presentation/providers_options_systeme.dart';
import '../../../restaurant/presentation/widgets/corps_carte_commun.dart'
    show grandEcranCarte, styleContenuCarte;
import '../../domain/entities/categorie_hebergement.dart';
import '../../domain/entities/etat_du_jour.dart';
import '../../domain/entities/unite_hebergement.dart';
import '../../domain/messages_sejour.dart' show RefusSejour;
import '../../domain/refus_parc.dart';
import '../../impression/etat_parc.dart';
import '../fiche_reservation.dart';
import '../providers_hebergement.dart';
import 'bouton_hebergement.dart';
import 'modale_archivage_unite.dart';
import 'modale_unite.dart';

/// Ce que dit l'onglet quand un geste n'a pas de source sur ce poste.
abstract final class MessagesPlanHebergement {
  // ⚠ « Le check-in / check-out ne peut pas être enregistré sur ce poste »
  // est RETIRÉ le 14/10/2026 (lot D, D416) : `sejours_local` existe depuis
  // D408 et les deux boutons passent par `SejourDao`, comme l'accueil. Les
  // phrases ci-dessous sont celles du composant (`hebergement_pwa.hebergement`).

  /// `hebergement.checkin_impossible` — aucune arrivée attendue aujourd'hui.
  static String checkinImpossible(String numero) =>
      "Aucune arrivée n'est attendue aujourd'hui sur l'unité $numero.";

  /// `hebergement.checkout_impossible` — aucun séjour en cours.
  static String checkoutImpossible(String numero) =>
      'Aucun séjour en cours sur l\'unité $numero.';

  /// `hebergement.checkin_fait`.
  static String checkinFait(String client, String numero) =>
      "Check-in effectué : $client occupe l'unité $numero.";

  /// `hebergement.checkout_fait`.
  static String checkoutFait(String numero) =>
      "Check-out effectué. L'unité $numero passe en nettoyage avant d'être "
      'reproposée.';

  /// Le choix « PDF Officiel A4 Imprimable » de la modale d'export.
  static const String pdfNonProduit =
      'Le PDF Officiel A4 du parc n’est pas produit sur ce poste : seul le '
      'tableur (CSV) est écrit. Rien n’a été exporté.';

  /// La ligne d'aide posée sous les deux choix de la modale, avant le clic.
  static const String aidePdf =
      'Le PDF n’est pas produit sur ce poste : seul le tableur (CSV) est écrit.';
}

class VuePlanHebergement extends ConsumerWidget {
  const VuePlanHebergement({super.key});

  /// `grid-cols-1 md:grid-cols-2 xl:grid-cols-3` (l.226), sur la largeur de la
  /// FENÊTRE.
  static int colonnesPour(double fenetre) => fenetre >= AppBreakpoints.xl
      ? 3
      : fenetre >= AppBreakpoints.md
      ? 2
      : 1;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pagination = ref.watch(parcPagineProvider);
    final etats = ref.watch(etatsDuJourProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _BarreOutils(),
        // `mb-4` (l.159).
        const SizedBox(height: AppSpacing.md),
        pagination.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          // Le message est affiché tel quel : le masquer derrière « une
          // erreur est survenue » oblige à ouvrir les journaux pour un
          // diagnostic que l'utilisateur pourrait faire lui-même.
          error: (erreur, _) => Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text('$erreur', textAlign: TextAlign.center),
          ),
          data: (page) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _Grille(
                unites: page.unites,
                // `asData?.value` plutôt que `valueOrNull` : ce dernier
                // n'existe pas sur la version de Riverpod épinglée ici. Une
                // carte sans état calculé n'est pas rendue « Libre » : sa
                // pastille dit « — », comme la vue (l.228, l.233).
                etats: etats.asData?.value ?? const {},
              ),
              if (page.total == 0)
                const _ParcVide()
              else
                _Pagination(
                  page: page.page,
                  total: page.total,
                  totalPages: page.totalPages,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/* ====================================================================== */
/* La barre d'outils — recherche, filtre, actualiser, exporter, ajouter    */
/* ====================================================================== */

class _BarreOutils extends ConsumerWidget {
  const _BarreOutils();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peutEcrire = ref.watch(peutEcrireHebergementProvider);

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // « Actualiser » — un rafraîchissement du CADRE, comme la vue :
        // jamais une méthode qui affirmerait une relecture qu'elle n'aurait
        // pas faite (PA-59/60/61). `p-2.5 border border-slate-200`.
        Tooltip(
          message: 'Actualiser',
          child: InkWell(
            key: const Key('plan-actualiser'),
            onTap: () => rafraichirListes(ref),
            borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.xsPlus),
              decoration: BoxDecoration(
                color: AppColors.neutre0,
                border: Border.all(color: Ardoise.c200),
                borderRadius: BorderRadius.circular(AppRadius.roundedLg),
              ),
              child: const Icon(
                Icons.refresh,
                size: AppLayout.iconeChamp,
                color: Ardoise.c500,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        _BoutonExporter(onPressed: () => _exporter(context, ref)),
        // 1er niveau du RBAC : il ne protège rien, mais un bouton offert
        // puis refusé ferait perdre la saisie.
        if (peutEcrire) ...[
          const SizedBox(width: AppSpacing.xs),
          BoutonHebergement(
            cle: const Key('plan-ajouter'),
            libelle: 'Ajouter hébergement',
            icone: Icons.add,
            plein: true,
            onPressed: () => ouvrirModaleUnite(context, ref),
          ),
        ],
      ],
    );

    if (!grandEcranCarte(context)) {
      // `flex-col` : une colonne, `gap-3`. Les actions, elles, passent à la
      // ligne quand la colonne est plus étroite qu'elles (INSTRUCTION2.txt,
      // 13/10/2026 : aucun débordement) — la vue déborderait.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _ChampRecherche(),
          const SizedBox(height: AppSpacing.sm),
          const Align(
            alignment: Alignment.centerLeft,
            child: _FiltreCategorie(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            key: const Key('plan-actions-a-la-ligne'),
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: actions.children.where((w) => w is! SizedBox).toList(),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Expanded(child: _ChampRecherche()),
        const SizedBox(width: AppSpacing.sm),
        const _FiltreCategorie(),
        const SizedBox(width: AppSpacing.sm),
        actions,
      ],
    );
  }

  /// « Générer & Télécharger » : la modale de format de la vue, puis le
  /// document.
  ///
  /// L'export porte sur CE QUI EST AFFICHÉ, TOUTES PAGES confondues, et il DIT
  /// son filtre (PA-119). Une liste vide se **refuse** : un fichier sans ligne
  /// se lirait « le parc est vide », alors qu'il veut dire « le filtre n'a rien
  /// retenu ».
  static Future<void> _exporter(BuildContext context, WidgetRef ref) async {
    final format = await choisirFormatExport(
      context,
      titre: "Exporter — Unités d'hébergement",
      sousTitre: "Le parc tel qu'il est affiché, filtres compris.",
      // PDF présélectionné comme la vue (demande du PO du 14/10/2026) ; son
      // refus est dit après le clic.
      aide: MessagesPlanHebergement.aidePdf,
    );
    if (format == null || !context.mounted) return;

    if (format == FormatExport.pdf) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            MessagesPlanHebergement.pdfNonProduit,
            key: Key('plan-export-pdf-absent'),
          ),
        ),
      );
      return;
    }

    final unites = await ref.read(parcFiltreProvider.future);
    if (!context.mounted) return;
    if (unites.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(EtatParc.refusVide, key: Key('plan-export-vide')),
        ),
      );
      return;
    }

    final etats = await ref.read(etatsDuJourProvider.future);
    final categories = await ref.read(categoriesParcProvider.future);
    final categorieId = ref.read(filtreCategorieParcProvider);
    final etat = EtatParc(
      unites: unites,
      etats: etats,
      portee: EtatParc.decrireFiltre(
        categorie: libelleCategorie(categories, categorieId),
        recherche: ref.read(rechercheParcProvider).trim(),
      ),
      aujourdHui: ref.read(horlogeHebergementProvider)(),
    );
    if (!context.mounted) return;
    // La fenêtre « Enregistrer sous », puis le toast commun (14/10/2026).
    await executerExport(
      context,
      () => ref.read(exporterParcProvider)(etat),
      cleSucces: const Key('plan-export-fait'),
    );
  }
}

/// `champ w-full border border-slate-200 rounded-lg pl-10 pr-4 py-2.5 text-sm
/// bg-white` (l.162-164), loupe à `left-3.5` (l.161).
class _ChampRecherche extends ConsumerWidget {
  const _ChampRecherche();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bordure = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      borderSide: const BorderSide(color: Ardoise.c200),
    );
    final texte = styleContenuCarte(TaillesContenu.sm, couleur: Ardoise.c700);

    return TextField(
      key: const Key('plan-recherche'),
      style: texte,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AppColors.neutre0,
        hintText: 'Rechercher bungalow, chambre ou tente...',
        hintStyle: texte.copyWith(color: Ardoise.c400),
        // `py-2.5` plus la bordure, que la boîte du navigateur compte et pas
        // celle de Flutter.
        contentPadding: const EdgeInsets.only(
          right: AppSpacing.md,
          top: AppSpacing.xsPlus + AppLayout.bordureControle,
          bottom: AppSpacing.xsPlus + AppLayout.bordureControle,
        ),
        // `left-3.5` pour la loupe, `pl-10` pour le texte.
        prefixIcon: const Padding(
          padding: EdgeInsets.only(left: AppSpacing.smPlus),
          child: Icon(
            Icons.search,
            size: AppLayout.iconeChamp,
            color: JetonsCssMaitre.neutre400,
          ),
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: AppSpacing.xlPlus,
          minHeight: 0,
        ),
        border: bordure,
        enabledBorder: bordure,
        focusedBorder: bordure.copyWith(
          borderSide: const BorderSide(color: AppColors.navy),
        ),
      ),
      onChanged: (terme) {
        ref.read(rechercheParcProvider.notifier).definir(terme);
        // Revenir en page 1 : sans cela, un filtre qui réduit le résultat
        // laisserait l'utilisateur sur une page vide.
        ref.read(pageParcProvider.notifier).definir(1);
      },
    );
  }
}

/// `<select class="champ text-[13px] border border-slate-300 rounded-lg px-3
/// py-2 bg-white">` (l.168).
///
/// Un menu qui ne construit ses entrées qu'à l'ouverture, et non un
/// `DropdownButton` : ce dernier garde TOUTES ses entrées dans l'arbre, et la
/// mesure y trouverait un second « Bungalow » sous le champ.
class _FiltreCategorie extends ConsumerWidget {
  const _FiltreCategorie();

  /// La valeur de « Toutes les catégories » : `PopupMenuButton` prend `null`
  /// pour une annulation, jamais pour un choix.
  static const String _toutes = '';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories =
        ref.watch(categoriesParcProvider).asData?.value ?? const [];
    final retenue = ref.watch(filtreCategorieParcProvider);
    final style = styleContenuCarte(TaillesContenu.t13, couleur: Ardoise.c700);

    return SizedBox(
      width: AppLayout.filtreCategorieParc,
      child: PopupMenuButton<String>(
        key: const Key('plan-filtre-categorie'),
        tooltip: '',
        padding: EdgeInsets.zero,
        position: PopupMenuPosition.under,
        initialValue: retenue ?? _toutes,
        onSelected: (valeur) {
          ref
              .read(filtreCategorieParcProvider.notifier)
              .definir(valeur == _toutes ? null : valeur);
          ref.read(pageParcProvider.notifier).definir(1);
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: _toutes,
            child: Text('Toutes les catégories', style: style),
          ),
          for (final categorie in categories)
            PopupMenuItem(
              value: categorie.id,
              child: Text(categorie.libelle, style: style),
            ),
        ],
        child: Container(
          // `px-3 py-2` plus la bordure de 1 px.
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: AppColors.neutre0,
            border: Border.all(color: Ardoise.c300),
            borderRadius: BorderRadius.circular(AppRadius.roundedLg),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  libelleCategorie(categories, retenue) ??
                      'Toutes les catégories',
                  style: style,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(
                Icons.expand_more,
                size: AppLayout.iconeChamp,
                color: Ardoise.c500,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// « Générer & Télécharger » : `btn flex … px-4 py-2.5 rounded-lg border
/// border-slate-300 bg-white text-[15px] font-semibold text-slate-700`
/// (l.185-188).
class _BoutonExporter extends StatelessWidget {
  const _BoutonExporter({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const Key('plan-exporter'),
      onTap: onPressed,
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xsPlus,
        ),
        decoration: BoxDecoration(
          color: AppColors.neutre0,
          border: Border.all(color: Ardoise.c300),
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        ),
        child: Text(
          'Générer & Télécharger',
          style: styleContenuCarte(
            TaillesContenu.t15,
            poids: FontWeight.w600,
            couleur: Ardoise.c700,
          ),
        ),
      ),
    );
  }
}

/* ====================================================================== */
/* La grille de cartes                                                     */
/* ====================================================================== */

class _Grille extends StatelessWidget {
  const _Grille({required this.unites, required this.etats});

  final List<UniteHebergement> unites;
  final Map<String, EtatDuJour> etats;

  @override
  Widget build(BuildContext context) {
    final colonnes = VuePlanHebergement.colonnesPour(
      MediaQuery.sizeOf(context).width,
    );

    // Une rangée par ligne de grille, étirée à sa carte la plus haute
    // (`align-items: stretch`) : c'est ce qui range les boutons de bas de
    // carte (`mt-auto`) sur une même ligne.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var debut = 0; debut < unites.length; debut += colonnes) ...[
          // `gap-5` — 20 px, entre rangées comme entre colonnes (l.226).
          if (debut > 0) const SizedBox(height: AppSpacing.mdPlus),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var j = 0; j < colonnes; j++) ...[
                  if (j > 0) const SizedBox(width: AppSpacing.mdPlus),
                  Expanded(
                    child: debut + j < unites.length
                        ? _CarteUnite(
                            unite: unites[debut + j],
                            etat: etats[unites[debut + j].id],
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _CarteUnite extends ConsumerWidget {
  const _CarteUnite({required this.unite, required this.etat});

  final UniteHebergement unite;

  /// `null` : aucun état calculé — la pastille dit « — ».
  final EtatDuJour? etat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peutEcrire = ref.watch(peutEcrireHebergementProvider);

    return Container(
      key: Key('plan-carte-${unite.id}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        border: Border.all(color: Ardoise.c200),
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            // `flex items-start justify-between` : dans la vue, le code de
            // l'unité est un élément de flex qui PASSE À LA LIGNE quand il est
            // long ; ici il prend la place laissée par la pastille, jamais plus
            // (INSTRUCTION2.txt : aucun débordement, 13/10/2026).
            children: [
              Flexible(child: _codeUnite()),
              const SizedBox(width: AppSpacing.xs),
              _pastille(),
            ],
          ),
          // `mb-2.5` — 10 px.
          const SizedBox(height: AppSpacing.xsPlus),
          // `unites_hebergement` ne porte ni nom ni description : la carte
          // affiche la catégorie, seule autre colonne.
          Text(
            unite.categorieLibelle,
            style: styleContenuCarte(
              TaillesContenu.t15,
              poids: FontWeight.bold,
              couleur: Ardoise.c800,
            ),
          ),
          // `my-3 pt-3 border-t border-slate-100` (l.240).
          Container(
            margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Ardoise.c100)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    'Tarif de base :',
                    style: styleContenuCarte(
                      TaillesContenu.t15,
                      couleur: Ardoise.c500,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  formaterFcfa(unite.tarifBase),
                  key: Key('plan-tarif-${unite.id}'),
                  style: styleContenuCarte(
                    TaillesContenu.t15,
                    poids: FontWeight.bold,
                    couleur: AppColors.gold,
                  ).copyWith(fontFamily: AppTextStyles.policeMonospace),
                ),
              ],
            ),
          ),
          // `mt-auto` : les boutons restent au bas d'une carte plus courte que
          // sa voisine de rangée.
          const Spacer(),
          if (peutEcrire) _actions(context, ref),
        ],
      ),
    );
  }

  /// `font-mono-tatacora text-[15px] bg-slate-100 px-2 py-0.5 rounded
  /// font-semibold` (l.231).
  Widget _codeUnite() => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.xs,
      vertical: AppSpacing.demi,
    ),
    decoration: BoxDecoration(
      color: Ardoise.c100,
      borderRadius: BorderRadius.circular(AppRadius.rounded),
    ),
    child: Text(
      unite.numero,
      style: styleContenuCarte(
        TaillesContenu.t15,
        poids: FontWeight.w600,
      ).copyWith(fontFamily: AppTextStyles.policeMonospace),
    ),
  );

  /// La pastille — les couleurs de la vue (`COULEURS_STATUT`), au bit près.
  /// Sans état calculé : `#F3F4F6` / `#6B7280` et « — » (l.233).
  Widget _pastille() {
    final (fond, texte) = switch (etat) {
      EtatDuJour.libre => (AppColors.badgeVertFond, AppColors.succes),
      EtatDuJour.occupee => (AppColors.badgeRougeFond, AppColors.erreur),
      EtatDuJour.reservee => (AppColors.reserveGoldFond, AppColors.gold),
      EtatDuJour.nettoyage => (AppColors.badgeBleuFond, AppColors.info),
      EtatDuJour.horsService ||
      null => (AppColors.badgeGrisFond, AppColors.badgeGrisTexte),
    };

    return Container(
      key: Key('plan-pastille-${unite.id}'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xsPlus,
        vertical: AppSpacing.unit,
      ),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(AppRadius.rounded),
      ),
      child: Text(
        etat?.libelle ?? tiretPastille,
        style: styleContenuCarte(
          TaillesContenu.t15,
          poids: FontWeight.w600,
          couleur: texte,
        ),
      ),
    );
  }

  /// Le tiret de la vue (`MontantFcfa::TIRET`) : un état non calculé n'est ni
  /// « Libre » ni « Hors service ».
  static const String tiretPastille = '—';

  /// `flex gap-2 mt-auto` (l.250) : le bouton du cycle, puis les gestes de la
  /// carte. Étirés à la hauteur du plus haut.
  Widget _actions(BuildContext context, WidgetRef ref) {
    final archivee = etat == EtatDuJour.horsService;
    // `@if (OptionsSystemeService::suppressionActive())` : fermée pendant le
    // chargement — un bouton destructeur n'apparaît pas par défaut d'information.
    final suppression = ref.watch(suppressionActiveProvider).value ?? false;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _actionPrincipale(context, ref)),
          const SizedBox(width: AppSpacing.xs),
          if (archivee)
            _BoutonSecondaire(
              cle: Key('plan-restaurer-${unite.id}'),
              libelle: 'Réintégrer au parc',
              onPressed: () async {
                await ref.read(parcDaoProvider).restaurer(unite.id);
                rafraichirListes(ref);
              },
            )
          else ...[
            _BoutonIcone(
              cle: Key('plan-modifier-${unite.id}'),
              infobulle: 'Modifier',
              icone: Icons.edit_outlined,
              couleur: Ardoise.c500,
              onPressed: () => ouvrirModaleUnite(context, ref, unite: unite),
            ),
            if (suppression) ...[
              const SizedBox(width: AppSpacing.xs),
              _BoutonIcone(
                cle: Key('plan-archiver-${unite.id}'),
                infobulle: 'Supprimer',
                icone: Icons.delete_outline,
                couleur: AppColors.erreur,
                onPressed: () => ouvrirArchivageUnite(context, ref, unite),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// Le bouton du cycle (l.252-291) : un `switch` sur l'état du jour, et
  /// « Indisponible » par défaut — y compris sans état calculé.
  Widget _actionPrincipale(BuildContext context, WidgetRef ref) {
    switch (etat) {
      case EtatDuJour.libre:
        return _BoutonCarte(
          cle: Key('plan-reserver-${unite.id}'),
          libelle: 'Réserver cette unité',
          icone: Icons.add,
          fond: AppColors.navy,
          onPressed: () => ouvrirFicheReservation(context, uniteId: unite.id),
        );

      case EtatDuJour.reservee:
        // `effectuerCheckIn` : la réservation du jour de l'unité, puis
        // `SejourService::checkin` — ici `SejourDao.checkin`, comme l'accueil
        // (lot D, D416).
        return _BoutonCarte(
          cle: Key('plan-checkin-${unite.id}'),
          libelle: 'Effectuer Check-In Client',
          icone: Icons.person_outline,
          fond: AppColors.gold,
          onPressed: () => _checkin(context, ref),
        );

      case EtatDuJour.occupee:
        // `effectuerCheckOut` : le séjour en cours de l'unité, puis
        // `SejourService::checkout` — ici `SejourDao.checkout`.
        return _BoutonCarte(
          cle: Key('plan-checkout-${unite.id}'),
          libelle: 'Effectuer Check-Out',
          icone: Icons.logout,
          fond: AppColors.erreur,
          onPressed: () => _checkout(context, ref),
        );

      case EtatDuJour.nettoyage:
        return _BoutonCarte(
          cle: Key('plan-nettoye-${unite.id}'),
          libelle: 'Marquer Nettoyé & Prêt',
          icone: Icons.check,
          fond: AppColors.succes,
          onPressed: () async {
            await ref.read(parcDaoProvider).marquerNettoyee(unite.id);
            rafraichirListes(ref);
          },
        );

      case EtatDuJour.horsService || null:
        // La vue garde son bouton VISIBLE et inerte (« Indisponible », l.286) :
        // sa présence dit que la fonction existe et qu'il manque une condition.
        return _BoutonCarte(
          cle: Key('plan-indisponible-${unite.id}'),
          libelle: 'Indisponible',
          icone: Icons.circle_outlined,
          fond: JetonsCssMaitre.neutre400,
          onPressed: null,
        );
    }
  }

  /// `Hebergement::effectuerCheckIn` : refus du composant (aucune arrivée) ou
  /// du service (`RefusSejour`) DITS, rien d'écrit ; sinon le message de
  /// succès du composant et les listes relues.
  Future<void> _checkin(BuildContext context, WidgetRef ref) async {
    final messager = ScaffoldMessenger.of(context);
    final dao = ref.read(sejourDaoProvider);
    final cible = await dao.reservationDuJourDeLUnite(unite.id);
    if (cible == null) {
      _direA(messager, MessagesPlanHebergement.checkinImpossible(unite.numero));
      return;
    }
    try {
      await dao.checkin(cible.reservationId);
    } on RefusSejour catch (refus) {
      _direA(messager, refus.message);
      return;
    }
    rafraichirListes(ref);
    ref.invalidate(reservationsAuSejourOuvertProvider);
    _direA(
      messager,
      // « Client inconnu » : la fiche introuvable, comme le serveur.
      MessagesPlanHebergement.checkinFait(
        cible.client ?? 'Client inconnu',
        unite.numero,
      ),
    );
  }

  /// `Hebergement::effectuerCheckOut` — même forme que [_checkin].
  Future<void> _checkout(BuildContext context, WidgetRef ref) async {
    final messager = ScaffoldMessenger.of(context);
    final dao = ref.read(sejourDaoProvider);
    final reservationId = await dao.reservationAuSejourEnCoursDeLUnite(
      unite.id,
    );
    if (reservationId == null) {
      _direA(
        messager,
        MessagesPlanHebergement.checkoutImpossible(unite.numero),
      );
      return;
    }
    try {
      await dao.checkout(reservationId);
    } on RefusSejour catch (refus) {
      _direA(messager, refus.message);
      return;
    }
    rafraichirListes(ref);
    ref.invalidate(reservationsAuSejourOuvertProvider);
    _direA(messager, MessagesPlanHebergement.checkoutFait(unite.numero));
  }

  static void _direA(ScaffoldMessengerState messager, String message) {
    messager
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message, key: const Key('plan-cycle-message'))),
      );
  }
}

/// `btn w-full flex items-center justify-center gap-2 text-white text-[15px]
/// font-semibold py-2.5 rounded-lg` (l.255).
class _BoutonCarte extends StatelessWidget {
  const _BoutonCarte({
    required this.cle,
    required this.libelle,
    required this.icone,
    required this.fond,
    required this.onPressed,
  });

  final Key cle;
  final String libelle;
  final IconData icone;
  final Color fond;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: fond,
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      child: InkWell(
        key: cle,
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xsPlus),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icone,
                size: AppLayout.iconeCarteUnite,
                color: AppColors.neutre0,
              ),
              // `gap-2` — 8 px.
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  libelle,
                  textAlign: TextAlign.center,
                  style: styleContenuCarte(
                    TaillesContenu.t15,
                    poids: FontWeight.w600,
                    couleur: AppColors.neutre0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `btn p-2.5 rounded-lg border border-slate-200 …` (l.300-304, l.311-315).
class _BoutonIcone extends StatelessWidget {
  const _BoutonIcone({
    required this.cle,
    required this.infobulle,
    required this.icone,
    required this.couleur,
    required this.onPressed,
  });

  final Key cle;
  final String infobulle;
  final IconData icone;
  final Color couleur;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: infobulle,
      child: InkWell(
        key: cle,
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xsPlus),
          decoration: BoxDecoration(
            border: Border.all(color: Ardoise.c200),
            borderRadius: BorderRadius.circular(AppRadius.roundedLg),
          ),
          child: Icon(icone, size: AppLayout.iconeCarteUnite, color: couleur),
        ),
      ),
    );
  }
}

/// `btn px-3 py-2.5 rounded-lg border border-slate-200 text-[13px]
/// font-semibold text-slate-600` — « Réintégrer au parc » (l.295-298).
class _BoutonSecondaire extends StatelessWidget {
  const _BoutonSecondaire({
    required this.cle,
    required this.libelle,
    required this.onPressed,
  });

  final Key cle;
  final String libelle;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: cle,
      onTap: onPressed,
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          border: Border.all(color: Ardoise.c200),
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        ),
        child: Text(
          libelle,
          style: styleContenuCarte(
            TaillesContenu.t13,
            poids: FontWeight.w600,
            couleur: Ardoise.c600,
          ),
        ),
      ),
    );
  }
}

/* ====================================================================== */
/* Pagination et état vide                                                 */
/* ====================================================================== */

/// La pagination (l.341-357) : `flex items-center justify-between px-1 py-4`.
class _Pagination extends ConsumerWidget {
  const _Pagination({
    required this.page,
    required this.total,
    required this.totalPages,
  });

  final int page;
  final int total;
  final int totalPages;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debut = total == 0 ? 0 : (page - 1) * lignesParPageParc + 1;
    final fin = (page * lignesParPageParc).clamp(0, total);
    final texte = styleContenuCarte(
      TaillesContenu.xs,
      couleur: Ardoise.c500,
    ).copyWith(height: TaillesContenu.interligneXs);
    final fort = texte.copyWith(fontWeight: FontWeight.bold);

    return Padding(
      // `px-1 py-4`.
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.unit,
        vertical: AppSpacing.md,
      ),
      // `flex items-center justify-between` : sur une ligne, `Wrap` en
      // `spaceBetween` se comporte comme la vue ; trop étroit, les liens
      // passent dessous au lieu de déborder (INSTRUCTION2.txt, 13/10/2026).
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: AppSpacing.xs,
        children: [
          // Le décompte de la vue : « Affichage de 1-3 sur 3 », les deux
          // nombres en gras (`<strong>`). Un morceau par texte : la vue les
          // pose dans des éléments distincts.
          Row(
            key: const Key('plan-decompte'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Affichage de ', style: texte),
              Text('$debut-$fin', style: fort),
              Text(' sur ', style: texte),
              Text('$total', style: fort),
            ],
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: AppSpacing.xs,
            children: [
              _BoutonPage(
                cle: const Key('plan-page-precedent'),
                libelle: '← Précédent',
                onPressed: page <= 1
                    ? null
                    : () =>
                          ref.read(pageParcProvider.notifier).definir(page - 1),
              ),
              // `gap-2` de chaque côté (l.348), puis `text-xs text-slate-600 px-2`.
              const SizedBox(width: AppSpacing.xs),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: Text(
                  'Page $page / $totalPages',
                  key: const Key('plan-page-courante'),
                  style: texte.copyWith(color: Ardoise.c600),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _BoutonPage(
                cle: const Key('plan-page-suivant'),
                libelle: 'Suivant →',
                onPressed: page >= totalPages
                    ? null
                    : () =>
                          ref.read(pageParcProvider.notifier).definir(page + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// `btn px-3 py-1.5 text-xs rounded-lg border border-slate-200
/// disabled:opacity-40` (l.349-355).
class _BoutonPage extends StatelessWidget {
  const _BoutonPage({
    required this.cle,
    required this.libelle,
    required this.onPressed,
  });

  final Key cle;
  final String libelle;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      // `disabled:opacity-40`.
      opacity: onPressed == null ? 0.4 : 1,
      child: InkWell(
        key: cle,
        onTap: onPressed,
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
            libelle,
            style: styleContenuCarte(
              TaillesContenu.xs,
              couleur: Ardoise.c700,
            ).copyWith(height: TaillesContenu.interligneXs),
          ),
        ),
      ),
    );
  }
}

/// L'état vide (l.326-329) : `flex flex-col items-center justify-center py-16
/// text-center bg-white rounded-xl border border-slate-200 mt-4`.
///
/// ⚠ ÉCART de deux mots avec la vue, et il est délibéré. Elle écrit « aucune
/// unité d'hébergement n'existe **sur ce serveur** » ; ce poste n'a plus de
/// serveur depuis le 14/09/2026, et la phrase désignerait une machine qu'il ne
/// joint jamais. Elle dit donc « sur ce poste ».
///
/// Le bouton « Ajouter hébergement » que cet état portait en plus est RETIRÉ
/// (09/10/2026) : la vue n'en pose pas, et la barre d'outils au-dessus offre le
/// même geste — la porte de sortie de PA-128 existe toujours.
class _ParcVide extends StatelessWidget {
  const _ParcVide();

  @override
  Widget build(BuildContext context) {
    return Container(
      // `mt-4`.
      margin: const EdgeInsets.only(top: AppSpacing.md),
      padding: const EdgeInsets.symmetric(vertical: AppSpacingLarge.p16),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        border: Border.all(color: Ardoise.c200),
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
      ),
      child: Text(
        "Le parc n'a pas encore été renseigné : aucune unité d'hébergement "
        "n'existe sur ce poste.",
        key: const Key('plan-vide'),
        textAlign: TextAlign.center,
        style: styleContenuCarte(TaillesContenu.sm, couleur: Ardoise.c400),
      ),
    );
  }
}

/// Rend le libellé d'une catégorie, pour les écrans qui n'ont que son
/// identifiant. Rend `null` plutôt qu'un repli : une catégorie absente doit se
/// voir, jamais se deviner.
String? libelleCategorie(
  Iterable<CategorieHebergement> categories,
  String? id,
) {
  if (id == null) return null;
  for (final categorie in categories) {
    if (categorie.id == id) return categorie.libelle;
  }
  return null;
}

/// Les refus du parc, exposés pour que les écrans les rendent tels quels.
///
/// Réexport délibéré : un écran qui attrape un [RefusParc] n'a pas à connaître
/// le chemin du fichier de domaine, et c'est ce qui garde le message identique
/// d'un écran à l'autre.
typedef RefusDeParc = RefusParc;
