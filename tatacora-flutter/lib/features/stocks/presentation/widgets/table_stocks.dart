import 'package:flutter/material.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../achats/presentation/widgets/composants_crud_achats.dart'
    show CaseSelectionAchats;
import '../../../restaurant/presentation/widgets/coquille_restaurant.dart';
import '../../../restaurant/presentation/widgets/tableau_restaurant.dart';
import '../../domain/entities/etat_stock.dart';
import '../../domain/stock_en_attente.dart';

/// Le gabarit du tableau des stocks — `stocks.blade.php` l.301-330 :
/// `<thead class="bg-[var(--navy)] text-[11px] uppercase tracking-wide
/// text-white/90 font-semibold">`, cellules `px-4 py-2.5`, rangées
/// `border-t border-slate-100`.
const GabaritTableau gabaritStocks = GabaritTableau(
  enteteFond: AppColors.navy,
  entete: TextesRestaurant.enteteColonneNavy,
  cellule: EdgeInsets.symmetric(
    horizontal: AppSpacing.md, // px-4
    vertical: AppSpacing.xsPlus, // py-2.5
  ),
  enBas: false,
);

/// La raison d'un « — » dans « Valeur d'achat » : elle dit LAQUELLE des deux
/// valeurs manque.
///
/// ⚠ ÉCART AVEC LA VUE, nommé (09/10/2026, repris le 21/10/2026 — règle des
/// phrases fausses, piège 13). La vue pose, en infobulle sur chaque « — » de « Point » et de « Valeur d'achat » (clé `stocks_pwa.liste.jamais_receptionne`) : « Jamais réceptionné : ni point de rattachement, ni prix d'achat. Les deux se posent à la première entrée de stock. » Cette phrase promet que la première entrée de stock pose LE POINT : ni le serveur (`MouvementStockService` n'écrit jamais `point_stockage_id`) ni ce poste ne le font — le point se pose par le formulaire de l'article, le prix par une entrée VALORISÉE, et l'un peut exister sans l'autre. Sur un article rattaché mais jamais valorisé, elle mentirait deux fois. Le poste dit donc, par cellule, ce qui manque réellement. Un test relit la vue et le serveur : il rougit le jour où la phrase de la vue devient vraie.
const String raisonSansPrixAchat =
    "Aucune entrée valorisée : le dernier prix d'achat n'est pas connu.";

/// La raison d'un « — » dans « Point ».
const String raisonSansPoint =
    "Aucun point de rattachement n'est renseigné pour cet article.";

/// La raison d'un « — » dans « Valeur stock » : du stock, mais aucun coût.
const String raisonValeurInconnue =
    "Du stock existe mais aucune entrée n'a été valorisée : le coût est "
    "inconnu, la valeur n'est pas affichée.";

/// Le tableau des articles — `stocks.blade.php`, la table des lignes. Ses
/// colonnes portent les clés `stocks_pwa.liste.col_*` de la vue (`__('stocks_pwa.liste.'.$colonne['cle'])`,
/// l.316), dans l'ordre de `$colonnes` (l.61-77).
///
/// ## Les chiffres traversent en CHAÎNES
///
/// Stock, coût moyen pondéré et valorisation sont écrits par `calculerEtat`
/// (quantités à deux décimales, coût à quatre, valeur en francs entiers). Les
/// reconvertir en `double` pour les réafficher les réarrondirait : l'écran
/// dirait un autre chiffre que le fichier remis au Gérant, qui part du même
/// calcul. La comparaison au seuil, elle, ne produit qu'un **état**.
///
/// ## L'état se lit sur le STOCK, comme dans la vue
///
/// Rouge gras en rupture, ambre gras sous le seuil, semi-gras sinon (l.377) —
/// sans colonne « État » : la vue n'en a pas. Un article journalier n'a pas de
/// stock : « non suivi », jamais « 0 ».
class TableStocks extends StatelessWidget {
  const TableStocks({
    super.key,
    required this.lignes,
    this.enAttente = StockEnAttente.vide,
    required this.onFiche,
    required this.onMouvement,
    required this.onModifier,
    this.peutArchiver = false,
    this.selection = const {},
    this.onBasculerTout,
    this.onBasculer,
    this.onSupprimer,
    this.onRestaurer,
  });

  final List<LigneStock> lignes;

  /// La règle d'archivage (`AutoriseArchivage::peutArchiver()`), REÇUE de
  /// l'écran : la vue ne la rejoue jamais (`$peutArchiver`). Elle commande la
  /// colonne des cases à cocher (en-tête et lignes) et le bouton « Supprimer »
  /// de chaque ligne — retirés, pas grisés, pour qui ne peut pas archiver.
  final bool peutArchiver;

  /// Les articles cochés (affichés seulement : l'écran les recoupe).
  final Set<String> selection;
  final ValueChanged<bool>? onBasculerTout;
  final void Function(String id, bool coche)? onBasculer;
  final void Function(LigneStock)? onSupprimer;

  /// « Restaurer » d'un article archivé : offert à tout qui écrit sur M6, hors
  /// de la règle d'archivage (restaurer n'est pas supprimer).
  final void Function(LigneStock)? onRestaurer;

  /// Ce que les ventes du bar encore en file sortiront (RG-05) : une mention
  /// sous le stock, jamais une soustraction.
  final StockEnAttente enAttente;

  /// Les trois actions de ligne de la vue (l.406-411).
  ///
  /// Injectées plutôt que câblées ici : ce widget ne connaît ni le routeur ni
  /// les modales, et reste montable dans un test sans `ProviderScope`.
  final void Function(LigneStock) onFiche;
  final void Function(LigneStock) onMouvement;
  final void Function(LigneStock) onModifier;

  static TextStyle _t({
    FontWeight? poids,
    Color? couleur,
    double taille = TaillesContenu.t13,
  }) => TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: taille,
    fontWeight: poids,
    color: couleur,
    height: 1.5,
  );

  @override
  Widget build(BuildContext context) {
    return TableauRestaurant(
      gabarit: gabaritStocks,
      pleineLargeur: true,
      repartitionProportionnelle: true,
      // Les colonnes de la vue, dans son ordre et sa casse (l.61-77) ;
      // l'écran les met en capitales comme le fait `uppercase`.
      largeursFixes: peutArchiver
          ? const {0: AppLayout.colonneSelection}
          : const {},
      colonnes: [
        // La case « tout sélectionner » (`stocks_pwa.archivage.selection_tout`) :
        // un `<th>` sans texte, rendu pour qui peut archiver SEULEMENT.
        if (peutArchiver)
          ColonneRestaurant(
            '',
            enteteSpecial: CaseSelectionAchats(
              cle: const Key('stocks-tout'),
              valeur:
                  lignes.isNotEmpty &&
                  lignes.every((l) => selection.contains(l.id)),
              etiquette: 'Tout sélectionner',
              surMarine: true,
              onChanged: (c) => onBasculerTout?.call(c),
            ),
          ),
        const ColonneRestaurant('Article'),
        ColonneRestaurant('Catégorie'),
        ColonneRestaurant('Unité'),
        ColonneRestaurant('Point'),
        ColonneRestaurant('Suivi'),
        ColonneRestaurant('Stock', aDroite: true),
        ColonneRestaurant('Seuil', aDroite: true),
        ColonneRestaurant("Valeur d'achat", aDroite: true),
        ColonneRestaurant('CMP', aDroite: true),
        ColonneRestaurant('Valeur stock', aDroite: true),
        ColonneRestaurant('Actions', aDroite: true),
      ],
      // La clé est posée sur la première cellule de la ligne (piège 10).
      clesLignes: [for (final l in lignes) Key('stocks-ligne-${l.id}')],
      lignes: [
        for (final l in lignes) [if (peutArchiver) _case(l), ..._cellules(l)],
      ],
    );
  }

  Widget _case(LigneStock l) => CaseSelectionAchats(
    cle: Key('stocks-case-${l.id}'),
    valeur: selection.contains(l.id),
    etiquette: 'Sélectionner cette ligne',
    onChanged: (c) => onBasculer?.call(l.id, c),
  );

  List<Widget> _cellules(LigneStock l) {
    final journalier = l.estJournalier;
    final prix = l.prixAchat;

    return [
      // `font-medium`, puis la pastille « Archivé » : un article archivé RESTE
      // dans la liste, marqué — le masquer le rendrait indiscernable d'un
      // article inexistant, et « reste restaurable » ne serait tenu nulle part.
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(l.libelle, style: _t(poids: FontWeight.w500)),
          ),
          if (!l.actif) ...[
            const SizedBox(width: AppSpacing.unit), // ml-1
            _BadgeArchive(cle: Key('stocks-archive-${l.id}')),
          ],
        ],
      ),
      // `text-slate-600`.
      Text(l.categorie ?? '—', style: _t(couleur: Ardoise.c600)),
      Text(l.uniteMesure, style: _t(couleur: Ardoise.c600)),
      l.pointLibelle == null
          ? Tooltip(
              message: raisonSansPoint,
              child: Text('—', style: _t(couleur: Ardoise.c300)),
            )
          : Text(l.pointLibelle!, style: _t(couleur: Ardoise.c600)),
      _BadgeSuivi(suivi: l.suivi, cle: Key('stocks-suivi-${l.id}')),
      // Rouge gras en rupture, ambre gras sous le seuil, semi-gras sinon
      // (l.377). Journalier : « non suivi » en gris clair, jamais « 0 ».
      journalier
          ? Text(
              'non suivi',
              key: Key('stocks-non-suivi-${l.id}'),
              style: _t(couleur: Ardoise.c300),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.stock,
                  key: Key('stocks-stock-${l.id}'),
                  style: _t(
                    poids: FontWeight.w600,
                    couleur: l.enRupture
                        ? PaletteMaitre.rouge600
                        : (l.sousSeuil ? PaletteMaitre.ambre600 : null),
                  ),
                ),
                if (enAttente.pour(l.id) > 0)
                  Text(
                    TextesStockEnAttente.sortie(enAttente.pour(l.id)),
                    key: Key('stocks-en-attente-${l.id}'),
                    style: _t(couleur: Ardoise.c400),
                  ),
              ],
            ),
      // Le seuil n'a pas de sens sans stock (l.380).
      Text(journalier ? '—' : l.seuilAlerte, style: _t(couleur: Ardoise.c400)),
      // Le DERNIER prix d'achat, jamais le CMP (l.382-390).
      prix == null
          ? Tooltip(
              message: raisonSansPrixAchat,
              child: Text(
                '—',
                key: Key('stocks-prix-absent-${l.id}'),
                style: _t(couleur: Ardoise.c300),
              ),
            )
          : Text(_fcfa(prix), style: _t()),
      _Cmp(ligne: l),
      // Journalier : « — » (l.403). Du stock sans aucun coût : « — » aussi,
      // avec sa raison — la valeur est INCONNUE, pas nulle.
      (journalier || l.valeurInconnue)
          ? Tooltip(
              message: journalier ? 'Stock non suivi.' : raisonValeurInconnue,
              child: Text(
                '—',
                key: Key('stocks-valeur-inconnue-${l.id}'),
                style: _t(couleur: Ardoise.c300),
              ),
            )
          : Text(
              formaterFcfa(int.parse(l.valeurStock)),
              key: Key('stocks-valeur-${l.id}'),
              style: _t(poids: FontWeight.w600),
            ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Action(
            cle: Key('stocks-fiche-${l.id}'),
            libelle: 'Fiche',
            onTap: () => onFiche(l),
          ),
          const SizedBox(width: AppSpacing.unit),
          _Action(
            cle: Key('stocks-mouvement-${l.id}'),
            libelle: 'Mouvement',
            onTap: () => onMouvement(l),
          ),
          const SizedBox(width: AppSpacing.unit),
          _Action(
            cle: Key('stocks-modifier-${l.id}'),
            libelle: 'Modifier',
            onTap: () => onModifier(l),
          ),
          // « Supprimer » du maître, rendu comme ARCHIVAGE (le mot est celui que
          // le client a validé, le geste pose `actif = false`) ; un article déjà
          // archivé offre « Restaurer » à la place.
          if (!l.actif) ...[
            const SizedBox(width: AppSpacing.unit),
            _Action(
              cle: Key('stocks-restaurer-${l.id}'),
              libelle: 'Restaurer',
              onTap: () => onRestaurer?.call(l),
            ),
          ] else if (peutArchiver) ...[
            const SizedBox(width: AppSpacing.unit),
            _Action(
              cle: Key('stocks-supprimer-${l.id}'),
              libelle: 'Supprimer',
              danger: true,
              onTap: () => onSupprimer?.call(l),
            ),
          ],
        ],
      ),
    ];
  }

  /// Un coût au franc : la vue passe par `MontantFcfa::format`, qui arrondit.
  static String _fcfa(String decimal) =>
      formaterMontantDecimal(decimal, suffixe: 'FCFA') ?? decimal;
}

/// Le CMP et, quand elle est mesurable ET non nulle, la dérive contre le
/// dernier prix d'achat (l.397-400) : « +0 % » sur un article jamais
/// réceptionné affirmerait une stabilité que rien n'a mesurée.
class _Cmp extends StatelessWidget {
  const _Cmp({required this.ligne});

  final LigneStock ligne;

  @override
  Widget build(BuildContext context) {
    final derive = ligne.deriveCmp;
    final style = TableStocks._t();

    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(
            text: ligne.cmpInconnu
                ? '—'
                : TableStocks._fcfa(ligne.coutMoyenPondere),
          ),
          if (derive != null && derive != 0)
            TextSpan(
              // `ml-1 text-[10px]`, rouge en hausse, vert en baisse.
              text: ' ${derive > 0 ? '+' : ''}$derive%',
              style: TextStyle(
                fontSize: TaillesContenu.t10,
                color: derive > 0
                    ? PaletteMaitre.rouge500
                    : PaletteMaitre.emeraude600,
              ),
            ),
        ],
      ),
      key: Key('stocks-cmp-${ligne.id}'),
    );
  }
}

/// `px-2 py-0.5 rounded text-[11px] font-semibold`, bleu pour le permanent et
/// ardoise pour le journalier (l.370).
class _BadgeSuivi extends StatelessWidget {
  const _BadgeSuivi({required this.suivi, required Key cle}) : super(key: cle);

  final SuiviArticle suivi;

  @override
  Widget build(BuildContext context) {
    final journalier = suivi == SuiviArticle.journalier;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs, // px-2
        vertical: AppSpacing.demi, // py-0.5
      ),
      decoration: BoxDecoration(
        color: journalier ? Ardoise.c100 : PaletteMaitre.bleu50,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        suivi.libelle,
        style: TableStocks._t(
          taille: TaillesContenu.t11,
          poids: FontWeight.w600,
          couleur: journalier ? Ardoise.c600 : PaletteMaitre.bleu700,
        ),
      ),
    );
  }
}

/// `ml-1 text-[10px] px-1.5 py-0.5 rounded` sur fond gris (`#F3F4F6`, texte
/// `#6B7280`) : « Archivé ».
class _BadgeArchive extends StatelessWidget {
  const _BadgeArchive({required Key cle}) : super(key: cle);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxs, // px-1.5
        vertical: AppSpacing.demi, // py-0.5
      ),
      decoration: BoxDecoration(
        color: AppColors.badgeGrisFond,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        'Archivé',
        style: TableStocks._t(
          taille: TaillesContenu.t10,
          couleur: AppColors.badgeGrisTexte,
        ),
      ),
    );
  }
}

/// `text-[12px] px-2 py-1 rounded-lg border border-slate-300` ; « Supprimer »
/// porte `border-red-200 text-[var(--erreur)]`.
class _Action extends StatelessWidget {
  const _Action({
    required Key cle,
    required this.libelle,
    required this.onTap,
    this.danger = false,
  }) : super(key: cle);

  final String libelle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.unit,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
          border: Border.all(
            color: danger ? PaletteMaitre.rouge200 : Ardoise.c300,
          ),
        ),
        child: Text(
          libelle,
          style: TableStocks._t(
            taille: TaillesContenu.t12,
            couleur: danger ? AppColors.erreur : null,
          ),
        ),
      ),
    );
  }
}
