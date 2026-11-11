import '../../../../core/impression/visas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../stocks/data/stocks_api.dart';
import '../../../stocks/domain/entities/etat_stock.dart';
import '../../domain/decimal_texte.dart';
import '../../domain/entities/commande_achat.dart';
import '../../impression/etat_liste_achats.dart';
import '../providers_achats.dart';
import 'coquille_achats.dart';
import 'modale_commande.dart';

/// L'onglet **« Besoins »** — la première section de
/// `pwa/achats/approvisionnement.blade.php`.
///
/// ## Il est servi par M6, et aucune route M7 ne le double
///
/// Il liste les articles sous leur seuil, ce que `GET /stocks/etat?sous_seuil`
/// rend déjà. Le dupliquer sous M7 ferait **deux chemins de calcul pour le même
/// chiffre**, exactement ce que PA-121 interdit : le jour où l'un des deux
/// prédicats changerait, l'écran Stocks et celui-ci afficheraient deux vérités
/// sur le même article. Le rôle `achats` porte `M6 = 'L'` à la matrice.
///
/// ## Ce que la page possède, et ce que l'onglet possède
///
/// Comme dans la vue, la **recherche**, « Exporter » et « Commander la
/// sélection » sont ceux de la PAGE : l'écran les rend en haut et pilote cet
/// onglet (le terme lui est passé ; [EtatVueBesoins.commander] et
/// [EtatVueBesoins.construireListe] sont appelés depuis l'en-tête).
///
/// ## « Point » reste « — » ; « Prix d'achat » a une source depuis le 09/10/2026
///
/// **Point** : le stock affiché est CONSOLIDÉ sur tous les points (la vue le
/// dit : *« articles ne porte aucun point »*). Ce poste connaît bien un point
/// de RATTACHEMENT par article (M6, v12), mais ce n'est pas la portée du stock
/// affiché : le montrer sous « Point » ferait lire « 12 sacs au magasin » d'un
/// stock qui est la somme de trois points. Refusé, avec sa raison en infobulle.
///
/// **Prix d'achat** : la vue écrit « — » faute de colonne. Ce poste a une
/// source — le DERNIER prix d'achat de M6, le coût de la dernière entrée
/// valorisée. ⚠ La réception de M7 n'en est PAS une : elle n'écrit aucun coût,
/// comme au serveur (D132) — seule une entrée de la modale « Mouvement » de M6
/// (ou l'ouverture d'un article) en porte un. Il est affiché, et « — » reste la
/// valeur d'un article jamais valorisé, réceptionné ou non. Ce n'est jamais le
/// **coût moyen pondéré** (une moyenne d'achats passés). Celui-ci, en revanche,
/// pré-remplit le prix unitaire de la commande — comme la vue — quand il est
/// connu (voir `commander`).
/// L'export, lui, garde la portée du calcul et le coût moyen pondéré sous leur
/// vrai nom.
///
/// ## Le filtre MASQUE les lignes, il ne les reconstruit pas
///
/// La règle est du maître : chaque ligne porte une case à cocher et une
/// quantité saisie ; re-rendre le tableau effacerait la sélection en cours,
/// *« et l'utilisateur ne s'en apercevrait qu'après avoir cliqué sur Commander
/// la sélection »*. La sélection vit donc dans l'état de ce widget, indexée par
/// article, et survit au filtrage.
class VueBesoins extends ConsumerStatefulWidget {
  const VueBesoins({super.key, required this.terme});

  /// Le terme de la recherche de la page.
  final String terme;

  @override
  ConsumerState<VueBesoins> createState() => EtatVueBesoins();
}

class EtatVueBesoins extends ConsumerState<VueBesoins> {
  /// Les parts des colonnes, mesurées sur la vue à 1 383 px (relevé
  /// navigateur des `<th>`) : Article, Point, Stock, Seuil, Manque,
  /// Prix d'achat, À commander. La case à cocher a sa largeur propre.
  static const _parts = [134, 125, 107, 108, 139, 186, 199];

  /// La sélection, **indépendante de l'affichage** : cocher puis filtrer ne
  /// décoche rien.
  final Set<String> _decoches = {};
  final Map<String, String> _quantites = {};
  final Map<String, TextEditingController> _controleurs = {};

  /// Le dernier état reçu du serveur, pour les deux boutons de l'en-tête de la
  /// page, qui agissent sur cet onglet sans en posséder les données.
  EtatStock? _etat;

  @override
  void dispose() {
    for (final c in _controleurs.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Le maître coche tout par défaut (`checked`) : on vient sur cet onglet
  /// pour commander ce qui manque, pas pour tout re-sélectionner.
  bool _coche(String id) => !_decoches.contains(id);

  TextEditingController _controleur(LigneStock l) {
    return _controleurs.putIfAbsent(l.id, () {
      final suggeree =
          quantiteSuggeree(seuilAlerte: l.seuilAlerte, stock: l.stock) ?? '';
      _quantites[l.id] = suggeree;
      return TextEditingController(text: suggeree);
    });
  }

  List<LigneStock> _visibles(List<LigneStock> lignes) {
    final terme = widget.terme.trim().toLowerCase();
    if (terme.isEmpty) return lignes;

    return lignes
        .where(
          (l) =>
              l.libelle.toLowerCase().contains(terme) ||
              l.portee.toLowerCase().contains(terme),
        )
        .toList(growable: false);
  }

  /// La liste à exporter : **ce qui est affiché**, filtre compris. `null` quand
  /// rien n'est affiché — l'export se refuse alors, avec sa raison.
  ListeAchats? construireListe() {
    final etat = _etat;
    if (etat == null) return null;
    final visibles = _visibles(etat.lignes);
    if (visibles.isEmpty) return null;

    final terme = widget.terme.trim();
    return ListeAchats(
      titre: 'Articles à réapprovisionner',
      // pdf/approvisionnement-bon.blade.php (PA-195).
      visas: Visas.approvisionnement,
      portee: Portee(
        filtre: terme.isEmpty
            ? 'Articles sous leur seuil d’alerte — aucun filtre de recherche'
            : 'Articles sous leur seuil d’alerte — recherche « $terme »',
        lignesRapportees: visibles.length,
        totalServeur: etat.lignes.length,
      ),
      entetes: const [
        'Article',
        'Portée du calcul',
        'Stock',
        'Seuil',
        'Manque',
        'Coût moyen pondéré',
      ],
      colonnesNumeriques: const {2, 3, 4, 5},
      lignes: [
        for (final l in visibles)
          [
            l.libelle,
            l.portee,
            l.stock,
            l.seuilAlerte,
            soustraire(l.seuilAlerte, l.stock) ?? '—',
            l.cmpInconnu ? '—' : l.coutMoyenPondere,
          ],
      ],
    );
  }

  /// « Commander la sélection » de l'en-tête de la page.
  Future<void> commander() async {
    final etat = _etat;
    final lignes = etat == null ? <LigneStock>[] : _visibles(etat.lignes);
    final selection = <LigneSaisieCommande>[
      for (final l in lignes)
        if (_coche(l.id) && estStrictementPositif(_quantites[l.id] ?? ''))
          LigneSaisieCommande(
            articleId: l.id,
            libelle: l.libelle,
            uniteMesure: l.uniteMesure,
            quantite: _quantites[l.id]!,
            // PRÉ-REMPLI avec le coût moyen pondéré connu de l'article, comme la
            // vue (`prix_unitaire` = `cout_moyen_pondere`) et comme elle le dit
            // au-dessus de la grille : c'est une valorisation d'achats passés,
            // PAS un tarif négocié. Un article sans entrée valorisée n'a pas de
            // coût (« — ») : le champ reste VIDE, jamais un « 0.00 » plausible.
            prixUnitaire: l.cmpInconnu
                ? ''
                : arrondirAuCentieme(l.coutMoyenPondere) ?? '',
          ),
    ];

    if (selection.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          key: Key('besoins-selection-vide'),
          content: Text(
            'Sélectionnez au moins un article à commander, avec une quantité '
            'strictement positive.',
          ),
        ),
      );
      return;
    }

    final creee = await ouvrirModaleCommande(context, selection: selection);
    if (creee == null || !mounted) return;

    // Le registre est relu de la base : la commande créée porte un montant
    // CALCULÉ de ses lignes, et l'insérer en mémoire afficherait un chiffre
    // fabriqué ici.
    ref.invalidate(commandesProvider(null));
    ref.invalidate(kpisApprovisionnementProvider);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        // « enregistré sur ce poste », jamais « en attente de
        // synchronisation » : les commandes ne partent nulle part (zéro
        // réseau), et l'annoncer décrirait une attente sans fin
        // (PA-59/60/61).
        content: Text(
          'Bon de commande enregistré sur ce poste — '
          '${creee.commande.montantTotal}.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resultat = ref.watch(besoinsProvider);

    return resultat.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          NoteAchats(cle: const Key('besoins-erreur'), texte: '$e'),
      data: (r) => switch (r) {
        StockRecu(:final etat) => _corps(etat),
        StockRefuse(:final motif) => NoteAchats(
          cle: const Key('besoins-refus'),
          texte: motif,
        ),
        // Jamais produite (le stock est local) : le type la garde, et le
        // `switch` doit rester exhaustif.
        StockInjoignable() => const NoteAchats(
          cle: Key('besoins-hors-ligne'),
          texte:
              'Le stock n’a pas pu être lu : aucun besoin n’est affiché, '
              'plutôt qu’un stock d’hier qui ferait commander des caisses '
              'déjà en réserve.',
        ),
      },
    );
  }

  TextStyle _t({FontWeight? poids, Color? couleur, double? taille}) =>
      TextStyle(
        fontFamily: AppTextStyles.police,
        fontSize: taille ?? TaillesContenu.t13,
        height: AppLayout.interligneContenu,
        fontWeight: poids,
        color: couleur,
      );

  Widget _corps(EtatStock etat) {
    _etat = etat;
    final visibles = _visibles(etat.lignes);
    final entete = _t(
      taille: TaillesContenu.t11,
      poids: FontWeight.w600,
      couleur: AppColors.neutre0,
    ).copyWith(letterSpacing: 0.5);

    Widget titre(String libelle, {bool droite = false}) => Text(
      libelle.toUpperCase(),
      textAlign: droite ? TextAlign.right : TextAlign.left,
      style: entete,
    );

    return CadreListeAchats(
      titre: 'Articles à réapprovisionner',
      // Le sous-titre de la vue, au mot : `pwa.appro.besoins_detail` puis
      // `pwa.appro.besoins_portee`, rendus côte à côte. Apostrophes DROITES,
      // comme la vue.
      sousTitre:
          'Stock calculé ≤ seuil d\'alerte. Le compteur « Articles sous '
          'seuil » porte sur TOUT le référentiel, jamais sur les seules '
          'lignes affichées : la recherche masque des lignes, elle ne '
          'réduit pas ce qu\'il y a à commander.',
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Rangee(
            parts: _parts,
            fond: AppColors.navy,
            vertical: AppSpacing.xsPlus,
            debut: const SizedBox(width: AppLayout.colonneSelection),
            cellules: [
              titre('Article'),
              titre('Point'),
              titre('Stock', droite: true),
              titre('Seuil', droite: true),
              titre('Manque', droite: true),
              titre('Prix d’achat', droite: true),
              titre('À commander', droite: true),
            ],
          ),
          if (visibles.isEmpty)
            const _EtatVideBesoins()
          else
            for (final l in visibles) _ligne(l),
        ],
      ),
    );
  }

  Widget _ligne(LigneStock l) {
    return _Rangee(
      parts: _parts,
      haut: true,
      vertical: AppSpacing.xs,
      debut: SizedBox(
        width: AppLayout.colonneSelection,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Checkbox(
            key: Key('besoin-coche-${l.id}'),
            // `aria-label` de la vue (`achats_pwa.tableau.selection_ligne`).
            semanticLabel: 'Sélectionner cette ligne',
            value: _coche(l.id),
            onChanged: (v) => setState(() {
              if (v ?? false) {
                _decoches.remove(l.id);
              } else {
                _decoches.add(l.id);
              }
            }),
          ),
        ),
      ),
      cellules: [
        Text(
          l.libelle,
          key: Key('besoin-ligne-${l.id}'),
          style: _t(poids: FontWeight.w500),
        ),
        Tooltip(
          message:
              'Le stock affiché est consolidé sur tous les points de '
              'stockage : un point de rattachement ne dirait pas où il se '
              'trouve.',
          child: Text('—', style: _t(couleur: AppColors.neutre500)),
        ),
        Text(
          '${l.stock} ${l.uniteMesure}',
          textAlign: TextAlign.right,
          style: _t(
            poids: l.enRupture ? FontWeight.bold : FontWeight.w600,
            couleur: l.enRupture ? AppColors.erreur : null,
          ),
        ),
        Text(
          l.seuilAlerte,
          textAlign: TextAlign.right,
          style: _t(couleur: AppColors.neutre400),
        ),
        Text(
          // `null` s'affiche « — » : un manque qu'on ne sait pas calculer
          // n'est pas un manque nul.
          soustraire(l.seuilAlerte, l.stock) ?? '—',
          key: Key('besoin-manque-${l.id}'),
          textAlign: TextAlign.right,
          style: _t(poids: FontWeight.w600, couleur: AppColors.erreur),
        ),
        // « Prix d'achat » : le DERNIER prix d'achat connu (le coût de la
        // dernière entrée valorisée, M6 — une réception de M7 n'en est PAS
        // une, D132), et « — » quand aucune entrée n'a été valorisée. Jamais le coût
        // moyen pondéré, qui est une moyenne d'achats passés. La vue, elle,
        // écrit « — » (sa source n'a pas de colonne) : ce poste a une source.
        _PrixAchat(ligne: l),
        Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: AppLayout.champQuantiteAchats,
            child: TextField(
              key: Key('besoin-qte-${l.id}'),
              controller: _controleur(l),
              textAlign: TextAlign.right,
              style: _t(),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => _quantites[l.id] = v,
            ),
          ),
        ),
      ],
    );
  }
}

/// Le dernier prix d'achat connu d'un besoin, ou « — » avec sa raison.
class _PrixAchat extends StatelessWidget {
  const _PrixAchat({required this.ligne});

  final LigneStock ligne;

  @override
  Widget build(BuildContext context) {
    final prix = formaterMontantDecimal(ligne.prixAchat, suffixe: 'FCFA');
    final style = TextStyle(
      fontFamily: AppTextStyles.police,
      fontSize: TaillesContenu.t13,
      height: AppLayout.interligneContenu,
      color: AppColors.neutre500,
    );
    if (prix == null) {
      return Tooltip(
        message:
            'Aucune entrée valorisée pour cet article : son prix d’achat '
            'n’est pas connu.',
        child: Text(
          '—',
          key: Key('besoin-prix-absent-${ligne.id}'),
          textAlign: TextAlign.right,
          style: style,
        ),
      );
    }
    return Text(
      prix,
      key: Key('besoin-prix-${ligne.id}'),
      textAlign: TextAlign.right,
      style: style,
    );
  }
}

/// Une rangée du tableau : `px-4`, parts entières mesurées sur la vue.
class _Rangee extends StatelessWidget {
  const _Rangee({
    required this.parts,
    required this.cellules,
    required this.debut,
    required this.vertical,
    this.fond,
    this.haut = false,
  });

  final List<int> parts;
  final List<Widget> cellules;
  final Widget debut;
  final double vertical;
  final Color? fond;
  final bool haut;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: fond,
        border: haut
            ? const Border(top: BorderSide(color: AppColors.neutre100))
            : null,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: vertical,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          debut,
          for (final (i, c) in cellules.indexed)
            Expanded(
              flex: parts[i],
              child: Padding(
                // `px-4` de chaque cellule : la moitié de chaque côté d'une
                // frontière suffit à séparer deux textes alignés à droite.
                padding: const EdgeInsets.only(right: AppSpacing.md),
                child: c,
              ),
            ),
        ],
      ),
    );
  }
}

/// L'état vide du moteur de la vue : `flex flex-col items-center py-16
/// text-center`, icône `h-10`, deux lignes.
class _EtatVideBesoins extends StatelessWidget {
  const _EtatVideBesoins();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacingLarge.p16),
      child: Column(
        children: [
          const Icon(
            Icons.search,
            size: AppSpacingLarge.p10,
            color: AppColors.neutre300,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            // Le texte du maître, au mot.
            'Aucun article sous son seuil. Rien à commander.',
            key: const Key('besoins-vide'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTextStyles.police,
              fontSize: TaillesContenu.sm,
              height: AppLayout.interligneContenu,
              fontWeight: FontWeight.w600,
              color: AppColors.neutre500,
            ),
          ),
          const SizedBox(height: AppSpacing.unit),
          Text(
            'Essayez de modifier votre recherche ou vos filtres.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTextStyles.police,
              fontSize: TaillesContenu.t12,
              height: AppLayout.interligneContenu,
              color: AppColors.neutre400,
            ),
          ),
        ],
      ),
    );
  }
}
