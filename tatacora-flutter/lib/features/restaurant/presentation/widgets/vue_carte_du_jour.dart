import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/donnees_absentes.dart';
import '../../../../core/format/formats.dart';
import '../../../../core/rbac/garde_acces.dart';
import '../../../../core/di/providers.dart';
import '../../../bar/presentation/widgets/modale_retrait_carte.dart';
import '../providers_restaurant.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/liste_paginee.dart';
import '../../domain/calcul_restaurant.dart'
    show lireDixMilliemes, lisibleDixMilliemes;
import '../../domain/entities/carte_restaurant.dart';
import '../../domain/messages_restaurant.dart';
import '../../impression/etat_carte_restaurant.dart';
import 'coquille_restaurant.dart';
import 'modale_lien_stock_plat.dart';
import 'tableau_restaurant.dart';

/// Le suffixe monétaire de cet écran, exposé pour les vues d'onglet.
///
/// Une seule source, sur la carte comme sur le catalogue : « FCFA », partout,
/// PWA comprise — décision du Product Owner du 11/09/2026 (PA-186), qui
/// renverse l'alignement sur « F » de PA-185. Ne pas réaligner sur « F ».
String? prixCarte(String? brut) =>
    formaterMontantDecimal(brut, suffixe: EtatCarteRestaurant.devise);

/// Les colonnes de l'onglet « Carte du jour », dans l'ordre de la VUE
/// (`pwa/carte/corps.blade.php` l.314-330) : Article, Catégorie, Prix,
/// Disponible, Article de stock, Stock vendable, Réserve, puis une colonne
/// d'actions SANS titre (`<th class="px-3 py-2.5"></th>`, l.330).
///
/// Exposées pour le test de conformité : elles doivent rester celles de la vue.
const List<ColonneRestaurant> colonnesCarteDuJour = [
  // `$entete(..., true)` : seul « Article » est `text-left` (l.314).
  ColonneRestaurant('Article'),
  ColonneRestaurant('Catégorie', aDroite: true),
  ColonneRestaurant('Prix', aDroite: true),
  ColonneRestaurant('Disponible', aDroite: true),
  ColonneRestaurant('Article de stock', aDroite: true),
  ColonneRestaurant('Stock vendable', aDroite: true),
  ColonneRestaurant('Réserve', aDroite: true),
  ColonneRestaurant('', aDroite: true),
];

/// L'onglet **« Carte du jour »** — `pwa/carte/corps.blade.php` l.297-454.
///
/// ## La colonne « Stock vendable » porte l'Article 7 à elle seule
///
/// Trois états, jamais deux :
///
///  - un **chiffre** — le nombre de portions que le stock cuisine permet
///    encore de servir ;
///  - la pastille **« rupture »** — zéro portion, et le chiffre existe ;
///  - **« non suivi »** — personne n'a compté, et [MotifSansStock] dit
///    pourquoi.
///
/// Afficher `0` dans le troisième cas ferait retirer de la carte un plat que
/// personne n'a compté. C'est le mot de la vue (`badge_non_suivi`) et
/// l'arbitrage du serveur (`LignePlatCarteResource` : « `portions_vendables`
/// peut valoir `null`, et ce n'est pas `0` »).
///
/// ## Deux colonnes de la vue n'ont AUCUNE source sur ce poste (09/10/2026)
///
/// « Disponible » (la disponibilité du jour vient d'`indisponibilites_carte`,
/// l.321) et « Réserve » (le stock détenu hors du point de vente, dérivé de
/// `mouvements_stock` et du lien direct à un article, l.390-393) : aucune table
/// locale ne les porte (D15 pour la première ; la seconde exige le lien direct,
/// que ce poste ne pose pas). Elles restent EN PLACE et rendent « — » avec leur
/// raison en infobulle — la vue fait de même pour « Réserve » quand la donnée
/// n'a pas pu être lue (l.398) ; un zéro se lirait « rien en réserve » ou
/// « tout est indisponible ».
///
/// ## Ce qui a une source depuis la v14 (09/10/2026)
///
/// Les marques « provisoire » et « corrigé à la main » sous le prix
/// (l.349-360) : `plats_local.prix_provisoire` est cochée à la saisie du plat,
/// `prix_corrige_main` est DÉDUITE quand le prix d'un plat provisoire change.
/// Et le libellé de la fiche technique en vert dans « Article de stock »
/// (l.373-380), que l'écran ne pouvait pas nommer tant qu'il n'avait aucune
/// table de fiches.
///
/// ## Le stock vendable ne tient pas compte des ventes de ce poste
///
/// Ce que la vue appelle « non suivi » pour un plat à fiche seule, ce poste le
/// CALCULE (le serveur aussi, côté API) : les portions que le stock du point
/// cuisine permet encore de servir. Mais aucune vente de ce poste ne retire de
/// stock (RG-05 non portée : la clôture d'un panier et l'émission de la facture
/// sont deux écritures, et la question de rupture n'a pas de place au point de
/// vente) : le chiffre peut donc dépasser le stock réel d'autant. La phrase est
/// DITE sous le tableau dès qu'un chiffre existe
/// ([MessagesRestaurant.stockSansLesVentes]) — un indicateur qui affirme un
/// état qu'il n'a pas vérifié est le défaut que ce dépôt a rencontré dix fois.
class VueCarteDuJour extends StatelessWidget {
  const VueCarteDuJour({super.key, required this.lignes, this.cleFiltre});

  final List<LigneCarteRestaurant> lignes;

  /// La recherche et les filtres : les changer ramène la pagination à la
  /// page 1.
  final Object? cleFiltre;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // `mb-3` — 12 px (l.304).
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CadreTableauRestaurant(
            // `carte_pwa.commun.tableau_titre` (l.306).
            titre: '${lignes.length} article(s)',
            // `carte_pwa.commun.tableau_aside` (l.307).
            aside: 'Le stock vendable est calculé, jamais saisi.',
            // Dix articles par page (PO, 14/10/2026) ; les exports lisent la
            // carte ENTIÈRE.
            corps: ListePaginee<LigneCarteRestaurant>(
              elements: lignes,
              prefixeCle: 'carte-restaurant-pagination',
              cleRemiseAZero: cleFiltre,
              constructeur: (_, page) => TableauRestaurant(
                gabarit: GabaritTableau.carteVue,
                pleineLargeur: true,
                colonnes: colonnesCarteDuJour,
                clesLignes: [
                  for (final l in page) Key('carte-restaurant-ligne-${l.id}'),
                ],
                lignes: [
                  for (final l in page)
                    [
                      _Article(ligne: l),
                      Text(
                        l.categorieLibelle,
                        style: TextesRestaurant.secondaire,
                      ),
                      _Prix(ligne: l),
                      _Disponible(ligne: l),
                      _ArticleDeStock(ligne: l),
                      _StockVendable(ligne: l),
                      const _SansSource(
                        cle: Key('carte-restaurant-reserve-inconnue'),
                        quoi: 'Les réserves hors point de vente',
                      ),
                      _Actions(ligne: l),
                    ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// L'état vide de la vue (l.298-301) :
/// `bg-white rounded-xl border border-slate-200 py-14 text-center
/// text-slate-400 text-[13px]`.
class EtatVideCarteRestaurant extends StatelessWidget {
  const EtatVideCarteRestaurant({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('carte-restaurant-vide'),
      padding: const EdgeInsets.symmetric(vertical: AppSpacingLarge.p14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: Ardoise.c200),
      ),
      child: Text(
        // `carte_pwa.commun.vide`.
        'Aucun article ne correspond à ces critères.',
        style: TextesRestaurant.corps.copyWith(color: Ardoise.c400),
      ),
    );
  }
}

/// La première cellule — `corps.blade.php` l.338-345.
///
/// La vue y empile le nom, puis le motif d'indisponibilité en ambre. Le second
/// n'existe pas ici (aucune disponibilité n'est lue, voir l'en-tête).
class _Article extends StatelessWidget {
  const _Article({required this.ligne});

  final LigneCarteRestaurant ligne;

  @override
  Widget build(BuildContext context) {
    final retrait = ligne.indisponibilite;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(ligne.libelle, style: TextesRestaurant.corpsFort),
        if (retrait != null)
          // `{{ libelleMotif() }} — {{ commentaire }}` (l.341-343), ambre.
          Text(
            retrait.commentaire == null
                ? retrait.libelle
                : '${retrait.libelle} — ${retrait.commentaire}',
            key: Key('carte-restaurant-retrait-${ligne.id}'),
            style: TextesRestaurant.mention.copyWith(
              color: PaletteMaitre.ambre700,
            ),
          ),
      ],
    );
  }
}

/// « Disponible » — `corps.blade.php` l.363-370 : « oui » (émeraude) ou « non »
/// (ambre), lu de `indisponibilites_carte_local`.
class _Disponible extends StatelessWidget {
  const _Disponible({required this.ligne});

  final LigneCarteRestaurant ligne;

  @override
  Widget build(BuildContext context) {
    final oui = !ligne.estRetire;
    return Container(
      key: Key('carte-restaurant-disponible-${ligne.id}'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxs,
        vertical: AppSpacing.demi,
      ),
      decoration: BoxDecoration(
        color: oui ? PaletteMaitre.emeraude50 : PaletteMaitre.ambre50,
        borderRadius: BorderRadius.circular(AppSpacing.unit),
      ),
      child: Text(
        // `carte_pwa.commun.export_oui` / `export_non`.
        oui ? 'oui' : 'non',
        style: TextesRestaurant.mention.copyWith(
          fontWeight: FontWeight.w600,
          color: oui ? PaletteMaitre.emeraude700 : PaletteMaitre.ambre700,
        ),
      ),
    );
  }
}

/// `text-right font-semibold` en doré — `corps.blade.php` l.354 — et, SOUS le
/// prix, les deux marques de la vue (l.355-360) : des `<div>` de 10 px, rouge
/// semi-gras pour « provisoire », ambre normal pour « corrigé à la main ». Un
/// prix provisoire non marqué se lit comme un tarif ferme.
class _Prix extends StatelessWidget {
  const _Prix({required this.ligne});

  final LigneCarteRestaurant ligne;

  @override
  Widget build(BuildContext context) {
    final prix = prixCarte(ligne.prixVente);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          // « — » et non « 0 F » : un prix que personne n'a rendu n'est pas un
          // plat offert.
          prix ?? CarteIndicateurRestaurant.absent,
          style: TextesRestaurant.corps.copyWith(
            fontWeight: FontWeight.w600,
            color: prix == null ? Ardoise.c400 : AppColors.gold,
          ),
        ),
        if (ligne.prixProvisoire)
          Text(
            // `carte_pwa.commun.marque_provisoire`.
            'provisoire',
            key: Key('carte-restaurant-marque-provisoire-${ligne.id}'),
            style: TextesRestaurant.mention.copyWith(
              fontSize: TaillesContenu.t10,
              fontWeight: FontWeight.w600,
              color: PaletteMaitre.rouge600,
            ),
          ),
        if (ligne.prixCorrigeMain)
          Text(
            // `carte_pwa.commun.marque_corrige_main`.
            'corrigé à la main',
            key: Key('carte-restaurant-marque-corrige-${ligne.id}'),
            style: TextesRestaurant.mention.copyWith(
              fontSize: TaillesContenu.t10,
              color: PaletteMaitre.ambre600,
            ),
          ),
      ],
    );
  }
}

/// Une cellule dont la donnée n'a aucune source sur ce poste : « — » et la
/// raison en infobulle, jamais un zéro (Article 7).
class _SansSource extends StatelessWidget {
  const _SansSource({required this.cle, required this.quoi});

  final Key cle;
  final String quoi;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: donneeNonDisponible(quoi),
      child: Text(
        CarteIndicateurRestaurant.absent,
        key: cle,
        style: TextesRestaurant.mention,
      ),
    );
  }
}

/// La colonne « Article de stock » — `corps.blade.php` l.373-380, rendue COMME
/// LA VUE (`CarteRestaurant::lienAffiche()`, l.312-327) : quand le plat n'a pas
/// de lien direct, le libellé de sa FICHE TECHNIQUE en vert, puis « Fiche
/// technique (N ingrédient(s)) » en dessous.
///
/// Jusqu'au 09/10/2026 l'écran mettait en vert l'ingrédient LIMITANT à la place,
/// faute de table de fiches (écart daté, retiré). Le lien DIRECT à un article
/// n'est pas porté sur ce poste : une cellule rend donc toujours la fiche. Le
/// vert de la vue est posé même sur une fiche VIDE (`accent` toujours vrai) ;
/// « 0 ingrédient(s) » le dit en clair, et la bande d'indicateurs compte ces
/// plats parmi ceux qui ne décrémentent rien.
class _ArticleDeStock extends StatelessWidget {
  const _ArticleDeStock({required this.ligne});

  final LigneCarteRestaurant ligne;

  @override
  Widget build(BuildContext context) {
    // Le lien DIRECT d'abord (`lienDirectAffiche`, sans accent) : l'article de
    // stock et son conditionnement lisible (« 24 par casier »).
    if (ligne.aLienDirect) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            ligne.articleStockLibelle!,
            key: Key('carte-restaurant-fiche-${ligne.id}'),
            style: TextesRestaurant.secondaire,
          ),
          Text(
            conversionLisible(
              ligne.unitesVendables!,
              ligne.articleStockUnite ?? 'unité',
            ),
            key: Key('carte-restaurant-conversion-${ligne.id}'),
            style: TextesRestaurant.mentionFine,
          ),
        ],
      );
    }

    final fiche = ligne.recetteLibelle;
    if (fiche == null) {
      return Tooltip(
        // `sans_lien_restaurant`, la phrase de la vue (l.378).
        message:
            'Fiche technique absente : une recette ne se décrémente '
            'pas comme un article.',
        child: const Text(
          CarteIndicateurRestaurant.absent,
          style: TextesRestaurant.mention,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          fiche,
          key: Key('carte-restaurant-fiche-${ligne.id}'),
          // `text-[12px] text-emerald-700 font-medium` (l.375, accent vrai).
          style: TextesRestaurant.secondaire.copyWith(
            color: PaletteMaitre.emeraude700,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          // `carte_pwa.restaurant.fiche_technique`.
          'Fiche technique (${ligne.nbIngredients} ingrédient(s))',
          style: TextesRestaurant.mentionFine,
        ),
      ],
    );
  }
}

/// La colonne « Stock vendable » — `cellule-stock.blade.php`.
class _StockVendable extends StatelessWidget {
  const _StockVendable({required this.ligne});

  final LigneCarteRestaurant ligne;

  @override
  Widget build(BuildContext context) {
    final portions = ligne.portionsVendables;

    // « non suivi » — le mot de la vue (`badge_non_suivi`). Le motif
    // accompagne toujours l'absence : un tiret qui ne dit pas pourquoi renvoie
    // chercher un bug là où il n'y en a pas.
    if (portions == null) {
      return Tooltip(
        message:
            ligne.motifSansStock?.explication ??
            MotifSansStock.inconnu.explication,
        child: Text(
          'non suivi',
          key: Key('carte-restaurant-non-suivi-${ligne.id}'),
          style: TextesRestaurant.mention,
        ),
      );
    }

    if (ligne.rupture) {
      return PastilleRestaurant(
        cle: Key('carte-restaurant-rupture-${ligne.id}'),
        texte: 'rupture',
        fond: PaletteMaitre.rouge50,
        couleur: PaletteMaitre.rouge700,
        compacte: true,
      );
    }

    final limitant = ligne.ingredientLimitant;

    return Tooltip(
      // Ce qui borne le chiffre : « 4 portions » sans dire ce qui manque
      // n'indique pas quoi racheter. Une infobulle, pas une ligne de plus : la
      // vue n'en pose pas.
      message: limitant == null
          ? 'Portions encore servables au point cuisine.'
          : 'Limité par : ${limitant.libelle}'
                '${limitant.uniteMesure == null ? '' : ' (${limitant.uniteMesure})'}.',
      child: Text(
        '$portions',
        key: Key('carte-restaurant-portions-${ligne.id}'),
        style: TextesRestaurant.corps.copyWith(
          fontWeight: FontWeight.bold,
          // `text-amber-600` quand l'ingrédient est sous son seuil d'alerte.
          color: ligne.sousSeuil ? PaletteMaitre.ambre600 : AppColors.navy,
        ),
      ),
    );
  }
}

/// La colonne d'actions — `corps.blade.php` l.402-446.
///
/// ## Les boutons DISENT qu'ils ne peuvent pas, ils ne sont pas inertes
///
/// Chaque geste de la vue écrit dans les plats, leur disponibilité, leur lien
/// au stock ou leur prix. Ce poste n'a aucune source locale pour M4 (décision
/// du Product Owner du 08/10/2026 : la source locale de M4 vient après
/// Paramètres, M6 et M7), et le client n'appelle plus aucun serveur
/// (`RestaurantApi`). Un bouton qui ne fait rien empêche de savoir si la
/// fonction manque ou si l'écran est cassé (Article 3.3) : chacun affiche
/// donc le message de `core/donnees_absentes.dart`. Les modales que ces
/// boutons ouvriraient sont REFUSÉES, avec leur raison, dans l'en-tête de
/// `ecran_carte_restaurant.dart`.
///
/// Quatre boutons sur sept : « Remettre » n'existe que pour un plat retiré,
/// « Modifier le lien » et « Délier » que pour un plat à lien direct
/// (l.403-419) — trois états que ce poste ne peut pas lire. Deviner lequel
/// afficher serait affirmer un état qu'on n'a pas vérifié.
class _Actions extends ConsumerWidget {
  const _Actions({required this.ligne});

  final LigneCarteRestaurant ligne;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ligne.id;
    final peutEcrire = ref
        .watch(droitsProvider)
        .peutEcrire(ModuleTatacora.m4Restaurant);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (peutEcrire && ligne.estRetire)
          _BoutonLigne(
            cle: Key('carte-restaurant-remettre-$id'),
            libelle: 'Remettre',
            onTap: () async {
              await remettreArticle(
                context,
                () => ref.read(retraitsPlatsProvider).remettre(id),
              );
              invaliderRestaurant(ref);
            },
          )
        else if (peutEcrire)
          _BoutonLigne(
            cle: Key('carte-restaurant-rendre-indispo-$id'),
            libelle: 'Rendre indispo.',
            onTap: () async {
              final fait = await ouvrirModaleRetraitArticle(
                context,
                libelle: ligne.libelle,
                soumettre: (motif, commentaire) => ref
                    .read(retraitsPlatsProvider)
                    .retirer(
                      platId: id,
                      motif: motif,
                      commentaire: commentaire,
                    ),
              );
              if (fait ?? false) invaliderRestaurant(ref);
            },
          ),
        // `ml-1` — 4 px entre deux boutons.
        const SizedBox(width: AppSpacing.unit),
        // `corps.blade.php` l.411-414 : « Modifier le lien » quand un article
        // est lié, « Lier au stock » sinon ; « Délier » (l.416-419) seulement
        // avec un lien. Le droit d'écriture M4 est exigé (une modale qu'on ne
        // pourrait pas soumettre ferait perdre la saisie).
        if (peutEcrire) ...[
          _BoutonLigne(
            cle: Key('carte-restaurant-lier-$id'),
            libelle: ligne.aLienDirect
                ? TextesLienPlat.boutonModifier
                : TextesLienPlat.boutonLier,
            onTap: () async {
              final fait = await ouvrirModaleLienStockPlat(
                context,
                ligne: ligne,
              );
              if (fait ?? false) invaliderRestaurant(ref);
            },
          ),
          if (ligne.aLienDirect) ...[
            const SizedBox(width: AppSpacing.unit),
            _BoutonLigne(
              cle: Key('carte-restaurant-delier-$id'),
              libelle: TextesLienPlat.boutonDelier,
              onTap: () async {
                final fait = await ouvrirDialogueDelierPlat(
                  context,
                  ligne: ligne,
                );
                if (fait ?? false) invaliderRestaurant(ref);
              },
            ),
          ],
        ],
        const SizedBox(width: AppSpacing.unit),
        _BoutonLigne(
          cle: Key('carte-restaurant-prix-$id'),
          libelle: 'Prix',
          message: ecritureNonDisponible('Le nouveau prix'),
        ),
        const SizedBox(width: AppSpacing.unit),
        _BoutonLigne(
          cle: Key('carte-restaurant-historique-prix-$id'),
          libelle: 'Historique des prix',
          message: donneeNonDisponible('Les changements de prix'),
        ),
      ],
    );
  }
}

/// `text-[11px] px-2 py-0.5 rounded border border-slate-300` (l.405).
class _BoutonLigne extends StatelessWidget {
  const _BoutonLigne({
    required this.cle,
    required this.libelle,
    this.message,
    this.onTap,
  });

  final Key cle;
  final String libelle;

  /// Le geste que ce poste ne porte pas : le bouton DIT pourquoi.
  final String? message;

  /// Le geste porté : il écrit.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: cle,
      borderRadius: BorderRadius.circular(AppRadius.rounded),
      onTap:
          onTap ??
          () => ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message ?? ''))),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.demi,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: Ardoise.c300),
          borderRadius: BorderRadius.circular(AppRadius.rounded),
        ),
        child: Text(
          libelle,
          style: TextesRestaurant.mention.copyWith(color: Ardoise.c700),
        ),
      ),
    );
  }
}

/// `StockDeCarteService::conversionLisible` : « 24 par casier » se lit bien ;
/// moins d'une unité vendable par unité de stock, c'est « N unités par vente ».
String conversionLisible(String conversion, String unite) {
  final v = lireDixMilliemes(conversion);
  if (v == null || v <= 0) return conversion;
  if (v > 10000) return '${lisibleDixMilliemes(v)} par $unite';
  if (v == 10000) return '1 $unite par vente';
  return '${lisibleDixMilliemes(100000000 ~/ v)} $unite par vente';
}
