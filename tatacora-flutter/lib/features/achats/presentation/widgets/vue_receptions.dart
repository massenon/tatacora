import '../../../../core/impression/visas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared_widgets/liste_paginee.dart';
import '../../data/achats_api.dart';
import '../../domain/entities/bon_reception.dart';
import '../../impression/etat_liste_achats.dart';
import '../providers_achats.dart';
import 'barre_outils_achats.dart';
import 'coquille_achats.dart';

/// L'onglet **« Réceptions »** — vue Blade
/// `pwa/achats/approvisionnement.blade.php` (onglet `receptions`).
///
/// ## « Point » et « Articles » ont une source sur ce poste (09/10/2026)
///
/// Le serveur ne conserve ni le point de stockage ni les lignes d'un bon
/// (PA-39) : la vue écrit « — » dans ces deux colonnes. Ce poste les conserve
/// (`bons_reception_local.point_stockage_id`, `lignes_bon_reception_local`) et
/// les affiche : le libellé du point qui a reçu l'entrée de stock, et le
/// nombre d'articles reçus. « — » reste la valeur d'une source muette
/// (`BonReception.pointLibelle` / `nombreArticles` à `null`), jamais un zéro.
///
/// Le « N° » reste absent : un bon n'a aucune séquence, seulement un
/// identifiant. Le fabriquer à l'affichage donnerait un numéro qui changerait
/// au prochain tri.
///
/// ## Aucun filtre de conformité — comme la vue (PA-185)
///
/// La vue n'offre pas de filtre sur cet onglet : la conformité y est une
/// COLONNE, lue ligne à ligne. Ce client proposait jusqu'au 11/09/2026 un
/// filtre à trois valeurs qu'aucun écran de la PWA ne porte — un ajout
/// interdit par l'Article 1 (n° 07), retiré sur décision du Product Owner
/// (« tout aligner »). La liste est donc toujours le registre entier, et la
/// portée de ses exports le dit : « Toutes les réceptions », le libellé de la
/// PWA (`pwa.appro.toutes_receptions`).
class VueReceptions extends ConsumerStatefulWidget {
  const VueReceptions({super.key});

  @override
  ConsumerState<VueReceptions> createState() => _VueReceptionsState();
}

class _VueReceptionsState extends ConsumerState<VueReceptions> {
  /// La recherche porte sur « N°, commande, fournisseur… ».
  ///
  /// La vue ne filtre pas cet onglet (`Approvisionnement::receptions()` ne
  /// lit aucun terme). Le champ est donc rendu **désactivé**, avec sa raison —
  /// un champ actif qui ne filtre rien laisse croire qu'aucune réception ne
  /// correspond.
  final _recherche = TextEditingController();

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  ListeAchats? _liste(PageAchats<BonReception> page) {
    if (page.elements.isEmpty) return null;

    return ListeAchats(
      titre: 'Bons de réception',
      // pdf/approvisionnement-bon.blade.php (PA-195).
      visas: Visas.approvisionnement,
      portee: Portee(
        // Sans filtre, la liste EST le registre entier : un export le dit.
        filtre: 'Toutes les réceptions',
        lignesRapportees: page.elements.length,
        totalServeur: page.total,
      ),
      entetes: const [
        'Référence',
        'Commande',
        'Fournisseur',
        'Date',
        'Point',
        'Articles',
        'Conformité',
      ],
      colonnesNumeriques: const {5},
      lignes: [
        for (final b in page.elements)
          [
            b.id,
            b.commandeId,
            b.fournisseurRaisonSociale ?? '—',
            b.dateReception,
            b.pointLibelle ?? '—',
            b.nombreArticles?.toString() ?? '—',
            b.libelleConformite,
          ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final resultat = ref.watch(receptionsProvider(null));

    return resultat.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          NoteAchats(cle: const Key('receptions-erreur'), texte: '$e'),
      data: (r) => switch (r) {
        AchatsRecu(:final donnees) => _corps(donnees),
        AchatsRefuse(:final motif) => NoteAchats(
          cle: const Key('receptions-refus'),
          texte: motif,
        ),
        // Jamais produite (la base est locale) ; le type la garde.
        AchatsInjoignable() => const NoteAchats(
          cle: Key('receptions-hors-ligne'),
          texte: 'La base du poste n’a pas répondu : aucun bon n’est affiché.',
        ),
      },
    );
  }

  Widget _corps(PageAchats<BonReception> page) {
    // La page défile d'un bloc (`<main>` de la vue) : cette liste s'y loge.
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        CadreListeAchats(
          titre: 'Bons de réception',
          // ÉCART NOMMÉ (D276) — la vue dit : « Chaque réception a généré une
          // entrée de stock valorisée au prix de la commande, qui a recalculé le
          // coût moyen pondéré de l'article. » (`lang/fr/achats_pwa.php`,
          // `appro.receptions_detail`, onglet Réceptions de la vue
          // d'approvisionnement). C'est FAUX, et le serveur EXÉCUTÉ le
          // prouve (`tool/achats/rejouer_receptions.php`) : `ReceptionService`
          // appelle `entree()` sans coût, le coût moyen pondéré et le dernier prix
          // d'achat de l'article sont INCHANGÉS après une réception. Décision du
          // Lead (12/10/2026) : un poste n'affiche pas une affirmation fausse sur
          // de l'argent, la règle d'honnêteté prévaut sur la fidélité littérale.
          // Phrase VRAIE, au plus près des mots de la vue ; la vue Blade est à
          // faire corriger par l'Architecte (ticket D276).
          sousTitre:
              'Chaque réception a généré une entrée de stock, non valorisée : '
              "le coût moyen pondéré de l'article n'est pas recalculé à la "
              'réception.',
          outils: BarreOutilsAchats(
            cle: const Key('outils-receptions'),
            prefixeCle: 'rec',
            placeholder:
                'Recherche non servie par cet onglet — voir les écarts',
            controleurRecherche: _recherche,
            // Le champ n'appelle rien : le laisser filtrer localement une liste
            // paginée dirait « aucune réception » sur un registre qui en
            // contient. Il reste visible, à sa place, mais GRISÉ — un champ
            // actif qui ne filtre rien laisse croire qu'aucune réception ne
            // correspond.
            rechercheActive: false,
            onRecherche: (_) {},
            construireListe: () => _liste(page),
          ),
          corps: page.elements.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Center(
                    child: Text(
                      // Le texte de la vue, au mot.
                      'Aucune réception enregistrée.',
                      key: const Key('receptions-vide'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                )
              // Dix bons par page (PO, 14/10/2026) ; l'export emporte toutes
              // les lignes reçues (`_liste`), jamais la seule page.
              : ListePaginee<BonReception>(
                  elements: page.elements,
                  prefixeCle: 'receptions-pagination',
                  constructeur: (_, tranche) => _table(tranche),
                ),
        ),
        // Le bloc « Ce que cet onglet ne rend pas » qui suivait est RETIRÉ
        // (directive absolue du PO, 14/10/2026). Écarts toujours vrais : pas
        // de colonne « N° » (aucune séquence) ; la recherche de la page ne
        // filtre pas cet onglet (`Approvisionnement::receptions()` non plus).
      ],
    );
  }

  Widget _table(List<BonReception> bons) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Référence')),
          DataColumn(label: Text('Commande')),
          DataColumn(label: Text('Fournisseur')),
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('Point')),
          DataColumn(label: Text('Articles'), numeric: true),
          DataColumn(label: Text('Conformité')),
        ],
        rows: [
          for (final b in bons)
            DataRow(
              cells: [
                DataCell(Text(b.id, key: Key('reception-ref-${b.id}'))),
                DataCell(Text(b.commandeId)),
                DataCell(
                  // `null` n'est pas une chaîne vide : le tiret dit que la
                  // relation n'a pas été jointe, pas que le fournisseur
                  // s'appelle « ».
                  Text(b.fournisseurRaisonSociale ?? '—'),
                ),
                DataCell(Text(b.dateReception)),
                // « — » quand la source ne conserve pas la donnée : jamais un
                // point deviné, jamais « 0 article ».
                DataCell(
                  Text(
                    b.pointLibelle ?? '—',
                    key: Key('reception-point-${b.id}'),
                  ),
                ),
                DataCell(
                  Text(
                    b.nombreArticles?.toString() ?? '—',
                    key: Key('reception-articles-${b.id}'),
                  ),
                ),
                DataCell(_Conformite(bon: b)),
              ],
            ),
        ],
      ),
    );
  }
}

class _Conformite extends StatelessWidget {
  const _Conformite({required this.bon});

  final BonReception bon;

  @override
  Widget build(BuildContext context) {
    // `null` = code inconnu du client : gris et code brut, jamais une couleur
    // qui trancherait sur un verdict qu'on ne sait pas lire.
    final (couleur, fond) = switch (bon.avecEcart) {
      false => (AppColors.succes, AppColors.succesFond),
      true => (AppColors.gold, AppColors.reserveGoldFond),
      null => (AppColors.neutre500, AppColors.neutre100),
    };

    return PastilleAchats(
      cle: Key('reception-conformite-${bon.id}'),
      texte: bon.libelleConformite,
      couleur: couleur,
      fond: fond,
    );
  }
}
