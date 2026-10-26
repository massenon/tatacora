// Vue Blade maîtresse (PA-183) : pwa/stocks/stocks.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/fichiers/selecteur_fichiers.dart';
import '../../../core/format/formats.dart';
import '../../../core/rbac/garde_acces.dart' show ModuleTatacora;
import '../../../core/responsive/rangee_flex_wrap.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared_widgets/bouton_standard.dart';
import '../../../shared_widgets/modale_export.dart';
import '../../../shared_widgets/toast_export.dart';
import '../../achats/domain/entities/archivage_fournisseur.dart';
import '../../achats/presentation/widgets/modale_archivage_achats.dart';
import '../../parametres/presentation/providers_options_systeme.dart'
    show peutArchiverProvider;
import '../data/stocks_api.dart';
import '../domain/entities/etat_stock.dart';
import '../domain/import_articles.dart';
import '../domain/messages_stock.dart';
import '../impression/etat_stocks.dart';
import '../domain/stock_en_attente.dart';
import 'providers_stocks.dart';
import 'widgets/modale_article.dart';
import 'widgets/modale_import_articles.dart';
import 'widgets/modale_mouvement.dart';
import 'widgets/table_stocks.dart';

/// L'écran **Gestion des Stocks** — la vue `stocks/stocks`.
///
/// ## Source LOCALE depuis le 09/10/2026 (décision du Product Owner)
///
/// Jusqu'à cette date l'écran n'affichait, en production, qu'une note grise :
/// `StocksApi` ne rendait que des refus, parce que le stock était calculé par
/// un serveur que ce poste n'a plus. Il lit maintenant `articles_local`,
/// `points_stockage_local` et `mouvements_stock_local`, que le seul
/// `StocksDao` écrit (voir `core/database/tables/stocks_tables.dart` : qui
/// écrit, qui lit, qui descend). Le stock est la somme des mouvements, le coût
/// moyen pondéré est rejoué depuis les entrées valorisées : aucun des deux
/// n'est une colonne, aucun ne se saisit.
///
/// ## Ce que ce stock ne sait PAS, et que l'écran DIT
///
///  * **Les ventes ne le décrémentent pas.** Le bar et le restaurant n'écrivent
///    aucune sortie (RG-05 n'est pas portée) : le stock affiché peut dépasser
///    le stock réel d'autant. Une note sous le tableau le dit en toutes
///    lettres — un chiffre exact en apparence est le défaut de ce dépôt
///    (PA-59/60/61).
///  * **Aucune écriture comptable.** Le poste tient une comptabilité depuis le
///    10/10/2026, mais aucun mouvement de stock n'y est comptabilisé (état du
///    12/10/2026) ; un mouvement de stock n'est de toute façon pas un
///    mouvement d'argent.
///    Aucune valorisation comptable (variation de stock, comptes 603x) n'est
///    produite.
///  * **Du stock sans coût a une valeur INCONNUE**, rendue « — » avec sa
///    raison, jamais zéro ; le compteur de ces articles est dit sous le
///    tableau.
///
/// ## Ce que la vue propose et qui n'est pas rendu (écarts nommés, 21/10/2026)
///
///  * **L'import CSV et son modèle** (vue l.232-235) : PORTÉS le 14/10/2026
///    (demande du PO) — `domain/import_articles.dart`, réplique de
///    `Stocks::lancerImport` ; le modèle s'enregistre par la fenêtre
///    « Enregistrer sous » du poste.
///  * **La pagination** (vue l.433-443) : PORTÉE le 21/10/2026, aux mots de la
///    vue (« Précédent », « Suivant »), 25 articles par page comme
///    `Stocks::PAR_PAGE` — l'ancienne règle de 10 lignes du 14/10/2026 cède au
///    maître ; le pied n'existe que s'il y a plusieurs pages (`hasPages()`).
///  * **L'ARCHIVAGE est PORTÉ** (21/10/2026) : la case de sélection de chaque
///    ligne et celle de l'en-tête (« Tout sélectionner »), la barre de sélection
///    groupée (« sélectionné(s) », « Supprimer »), le bouton « Supprimer » de
///    la ligne (qui ARCHIVE, `actif = false`), le badge « Archivé », « Restaurer »
///    et la modale « Confirmer la suppression » (vue l.261-283, 304-314,
///    331-336, 343-346, 417-425, 777-798). Les cases et « Supprimer » sont
///    RETIRÉS (pas grisés) pour qui ne peut pas archiver — la règle unique
///    `peutArchiver` (droit C sur M6 ET rôle d'administration OU bascule
///    « Suppression d'un enregistrement »), reçue de [peutArchiverProvider],
///    jamais rejouée ici. Un article archivé RESTE dans la liste, marqué ;
///    « Restaurer » n'est pas derrière la bascule. Les quatre verrous du
///    serveur (stock, commande en cours, carte, recette) sont rejoués sur les
///    données locales par `StocksDao.verrousArticle`, à l'ouverture de la
///    modale ET de nouveau à l'exécution. L'archivage part au serveur
///    (`actif: false`), qui l'applique sous SES verrous : un refus revient
///    dans « À traiter ».
///
///  * **L'en-tête d'impression de la vue** (`hidden print:block`, l.112-115) :
///    la vue l'écrit EN DUR pour l'impression du navigateur — « TATACORA AFRIQUE — GÎTE CHEZ NOËL », puis le titre et l'horodatage. Ce poste n'imprime pas l'écran ; il exporte
///    l'état A4 (`EtatStocks`), dont l'en-tête est LU des Paramètres (raison
///    sociale, adresse, IFU…, `EnteteEtablissement`). Y coller une seconde ligne
///    en dur contredirait la raison sociale saisie. Écart nommé, pas un refus.
///  * **Le bloc d'entrée de la fiche article** : porté, voir
///    `modale_article.dart`.
class EcranStocks extends ConsumerWidget {
  const EcranStocks({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultat = ref.watch(etatStockProvider);

    return SingleChildScrollView(
      // `max-w-[1440px] mx-auto p-5 lg:p-8` : 32 px au poste de travail.
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppLayout.maxContentWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _EnTete(),
              resultat.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) =>
                    _Note(cle: const Key('stocks-erreur'), texte: '$e'),
                data: (r) => switch (r) {
                  StockRecu(:final etat) => _Corps(etat: etat),
                  StockRefuse(:final motif) => _Note(
                    cle: const Key('stocks-refus'),
                    texte: motif,
                  ),
                  // Jamais produit : une base locale n'est pas hors connexion.
                  // L'arm reste parce que le type scellé est partagé ; il ne
                  // dit rien d'une coupure qui n'existe pas.
                  StockInjoignable() => const _Note(
                    cle: Key('stocks-hors-ligne'),
                    texte: 'Le stock n’a pas pu être lu.',
                  ),
                },
              ),
            ],
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
  double interligne = 1.5,
}) => TextStyle(
  fontFamily: AppTextStyles.police,
  fontSize: taille,
  fontWeight: poids,
  color: couleur,
  height: interligne,
  letterSpacing: espacement,
);

/// Le corps de la page : les cinq cartes, les filtres, puis la carte du
/// tableau, puis ce que le stock ne sait pas.
class _Corps extends ConsumerWidget {
  const _Corps({required this.etat});

  final EtatStock etat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lignes = filtrerLignes(
      etat.lignes,
      terme: ref.watch(rechercheStockProvider),
      categorie: ref.watch(categorieStockProvider),
      suivi: ref.watch(suiviStockProvider),
      etat: ref.watch(etatFiltreProvider),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Kpis(kpis: etat.kpis),
        _Filtres(
          categories: ref.watch(categoriesStockProvider(etat.lignes)),
          onExporter: () => _exporter(context, ref, lignes, etat),
        ),
        _CarteTableau(
          lignes: lignes,
          cleFiltre: (
            ref.watch(rechercheStockProvider),
            ref.watch(categorieStockProvider),
            ref.watch(suiviStockProvider),
            ref.watch(etatFiltreProvider),
          ),
          onFiche: (l) => _ouvrirFiche(context, ref, l),
          onMouvement: (l) => _ouvrirMouvement(context, ref, l),
          onModifier: (l) => _modifier(context, ref, l),
        ),
        if (etat.arreteAu.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              // Sans cette date, deux écrans ouverts à dix minutes d'intervalle
              // donneraient deux chiffres sans qu'on sache lequel est le plus
              // récent — et un état de stock ne se rapproche de rien.
              'Arrêté au ${etat.arreteAu}',
              key: const Key('stocks-arrete-au'),
              style: _t(TaillesContenu.t11, couleur: AppColors.neutre400),
            ),
          ),
        _Limites(kpis: etat.kpis),
      ],
    );
  }

  void _ouvrirFiche(BuildContext context, WidgetRef ref, LigneStock ligne) {
    ref.read(demandeFicheProvider.notifier).article(ligne.id);
    context.go('/stocks/inventaires');
  }

  Future<void> _ouvrirMouvement(
    BuildContext context,
    WidgetRef ref,
    LigneStock ligne,
  ) async {
    // Le refus de la vue (l.380-383) : un article en suivi journalier n'a pas de
    // stock à mouvementer. La fenêtre ne s'ouvre pas, et le refus NOMME
    // l'article — « son stock n'est pas suivi » sans dire lequel obligerait à
    // deviner sur une liste de vingt-cinq lignes. (`StocksDao` refuse de toute
    // façon : l'ouverture d'une fenêtre ne protège rien.)
    if (ligne.estJournalier) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('stocks-refus-journalier'),
          duration: const Duration(seconds: 6),
          content: Text(MessagesStock.refusJournalier(ligne.libelle)),
        ),
      );
      return;
    }

    final mouvement = await ouvrirModaleMouvement(context, article: ligne);
    if (mouvement == null) return;

    // Le stock affiché est une somme de mouvements : après un mouvement, il
    // n'est plus le bon. Le recalculer ici (`stock ± quantité`) donnerait une
    // seconde arithmétique, fausse dès que le coût moyen change — on relit.
    ref.invalidate(etatStockProvider);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          mouvement.ruptureForcee
              ? 'Sortie forcée enregistrée et tracée.'
              : '${mouvement.libelleType} de ${mouvement.quantite} '
                    '${ligne.uniteMesure} enregistrée sur ce poste.',
        ),
      ),
    );
  }

  Future<void> _modifier(
    BuildContext context,
    WidgetRef ref,
    LigneStock ligne,
  ) async {
    final modifie = await ouvrirModaleArticle(
      context,
      article: ligne,
      categoriesConnues: ref.read(categoriesStockProvider(etat.lignes)),
    );
    if (modifie == null) return;

    ref.invalidate(etatStockProvider);
    if (!context.mounted) return;

    // `faireEntrerLeStock` rend SON message quand un mouvement a eu lieu ;
    // sinon la fiche seule est annoncée (jamais une entrée qui n'a pas eu lieu).
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          modifie.messageEntree ?? 'Article « ${modifie.libelle} » mis à jour.',
        ),
      ),
    );
  }

  /// « Exporter » : la modale de format de la vue, puis le fichier.
  ///
  /// L'export porte sur CE QUI EST AFFICHÉ, toutes lignes confondues, et il DIT
  /// son filtre (PA-119). Une liste vide se REFUSE : un fichier sans ligne se
  /// lirait « il n'y a aucun article », alors qu'il veut dire « le filtre n'a
  /// rien retenu ». Le PDF est l'état A4 des mêmes colonnes (directive du PO
  /// du 14/10/2026).
  Future<void> _exporter(
    BuildContext context,
    WidgetRef ref,
    List<LigneStock> lignes,
    EtatStock etat,
  ) async {
    // Le filtre est calculé AVANT la modale : la vue le dit dans son sous-titre
    // (`sous_titre_filtre`), et un export qui ne dit pas son filtre laisse croire
    // qu'il porte sur tout (PA-119).
    final points = ref.read(pointsStockProvider).value ?? const [];
    final pointId = ref.read(pointStockProvider);
    final portee = EtatStocks.decrireFiltre(
      recherche: ref.read(rechercheStockProvider),
      categorie: ref.read(categorieStockProvider),
      point: points.where((p) => p.id == pointId).firstOrNull?.libelle,
      suivi: ref.read(suiviStockProvider),
      etat: ref.read(etatFiltreProvider),
    );

    final format = await choisirFormatExport(
      context,
      titre: 'Exporter — Articles en stock',
      sousTitre: 'Le document porte les filtres affichés : $portee',
    );
    if (format == null || !context.mounted) return;

    if (lignes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(EtatStocks.refusVide, key: Key('stocks-export-vide')),
        ),
      );
      return;
    }

    final fichier = EtatStocks(
      lignes: lignes,
      portee: portee,
      arreteAu: etat.arreteAu,
      sansValorisation: etat.kpis.sansValorisation,
    );
    // La fenêtre « Enregistrer sous », puis le toast commun (14/10/2026).
    await executerExport(
      context,
      () => switch (format) {
        FormatExport.pdf => ref.read(exporterStocksPdfProvider)(fichier),
        FormatExport.excel => ref.read(exporterStocksProvider)(fichier),
      },
      cleSucces: const Key('stocks-export-fait'),
    );
  }
}

/// Les phrases propres à ce poste — ce que la vue ne dit pas parce que son
/// serveur sait faire ce que ce poste ne sait pas encore.
abstract final class TextesStocks {
  static const String ventesSansSortie =
      'Ce stock ne compte que les mouvements saisis ici : les ventes '
      'du bar et du restaurant n’y écrivent aucune sortie, il peut donc '
      'dépasser le stock réel d’autant.';

  static const String sansComptabilite =
      'Ces mouvements ne produisent aucune écriture comptable : un mouvement '
      'de stock n’est pas un mouvement d’argent.';

  static String sansValorisation(int n) =>
      '$n article(s) ont du stock mais aucune entrée valorisée : leur valeur '
      'est inconnue (« — »), elle n’est pas comptée dans le total.';
}

/// L'en-tête de la vue : titre, sous-titre dont « calculé depuis les
/// mouvements » est en gras, deux liens et « + Nouvel article ».
class _EnTete extends ConsumerWidget {
  const _EnTete();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.mdPlus), // mb-5
      child: Wrap(
        // `flex flex-wrap items-start justify-between gap-3`
        alignment: WrapAlignment.spaceBetween,
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.inventory_2_outlined,
                    size: AppLayout.iconeTitrePage,
                    color: AppColors.navy,
                  ),
                  const SizedBox(width: AppSpacing.xsPlus), // gap-2.5
                  Text(
                    'Gestion des Stocks',
                    style: _t(
                      TaillesContenu.lg,
                      poids: FontWeight.bold,
                      couleur: AppColors.navy,
                      interligne: TaillesContenu.interligneLg,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs), // mt-1.5
              Text.rich(
                TextSpan(
                  style: _t(TaillesContenu.t15, couleur: AppColors.neutre500),
                  children: const [
                    TextSpan(
                      text:
                          'Référentiel valorisé au coût moyen pondéré — le '
                          'stock affiché est ',
                    ),
                    TextSpan(
                      text: 'calculé depuis les mouvements',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(text: ', il ne se saisit jamais.'),
                  ],
                ),
              ),
            ],
          ),
          Wrap(
            spacing: AppSpacing.xs, // gap-2
            children: [
              // Le bouton standard (14/10/2026) : `text-[13px] px-3.5 py-2
              // border` pour les deux liens, `px-4 bg-[var(--navy)]
              // font-semibold` pour « + Nouvel article ».
              BoutonStandard(
                key: const Key('stocks-inventaires'),
                libelle: 'Inventaires & fiches',
                onPressed: () => context.go('/stocks/inventaires'),
              ),
              BoutonStandard(
                key: const Key('stocks-approvisionnement'),
                libelle: 'Approvisionnement',
                onPressed: () => context.go('/approvisionnement'),
              ),
              // Le bouton de la vue, à sa place et à son libellé.
              BoutonStandard(
                key: const Key('stocks-nouvel-article'),
                libelle: '+ Nouvel article',
                variante: VarianteBouton.primaire,
                onPressed: () => _creer(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _creer(BuildContext context, WidgetRef ref) async {
    final lignes = switch (ref.read(etatStockProvider).value) {
      StockRecu(:final etat) => etat.lignes,
      _ => const <LigneStock>[],
    };

    final cree = await ouvrirModaleArticle(
      context,
      categoriesConnues: ref.read(categoriesStockProvider(lignes)),
    );
    if (cree == null) return;

    ref.invalidate(etatStockProvider);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        // « enregistré sur ce poste », jamais « en attente de
        // synchronisation » : rien ne part, et l'annoncer décrirait une
        // attente sans fin (PA-59/60/61).
        content: Text('Article « ${cree.libelle} » créé.'),
      ),
    );
  }
}

/// Les CINQ cartes de la vue (`grid-cols-2 lg:grid-cols-5 gap-3 mb-5`, l.145-
/// 179). Les deux compteurs de suivi sont REELS depuis la v12 : l'article porte
/// son mode de suivi, et ils portent sur tout le référentiel de la portée.
/// « En rupture » n'est pas une carte de la vue ; il est dit dans le détail de
/// « Sous seuil ».
class _Kpis extends StatelessWidget {
  const _Kpis({required this.kpis});

  final KpisStock kpis;

  @override
  Widget build(BuildContext context) {
    final cartes = <(Key, String, String, String?, Color?)>[
      (
        const Key('stocks-kpi-references'),
        'Références',
        '${kpis.references}',
        '${kpis.permanents} suivies · ${kpis.journaliers} journalières',
        null,
      ),
      (
        const Key('stocks-kpi-valeur'),
        'Valeur du stock',
        formaterFcfa(int.parse(kpis.valeurStock)),
        'au coût moyen pondéré',
        null,
      ),
      (
        const Key('stocks-kpi-sous-seuil'),
        'Sous seuil',
        // L'alarme porte sur TOUT le référentiel de la portée, pas sur les
        // lignes affichées : masquer les articles sains ne change pas le
        // nombre d'articles à réapprovisionner.
        '${kpis.sousSeuil}',
        'à réapprovisionner',
        kpis.sousSeuil > 0 ? PaletteMaitre.rouge600 : PaletteMaitre.emeraude600,
      ),
      (
        const Key('stocks-kpi-mouvements'),
        'Mouvements 30 j',
        '${kpis.mouvements30Jours}',
        null,
        null,
      ),
      (
        const Key('stocks-kpi-suivi'),
        'Gros / petit stock',
        '${kpis.permanents} / ${kpis.journaliers}',
        'suivi vs journalier',
        null,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.mdPlus),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < cartes.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _Carte(
                  cle: cartes[i].$1,
                  libelle: cartes[i].$2,
                  valeur: cartes[i].$3,
                  detail: cartes[i].$4,
                  accent: cartes[i].$5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Carte extends StatelessWidget {
  const _Carte({
    required Key cle,
    required this.libelle,
    required this.valeur,
    this.detail,
    this.accent,
  }) : super(key: cle);

  final String libelle;
  final String valeur;
  final String? detail;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.smPlus), // p-3.5
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: AppColors.neutre200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            libelle.toUpperCase(),
            style: _t(
              TaillesContenu.t10,
              poids: FontWeight.bold,
              couleur: AppColors.neutre400,
              espacement: 1,
            ),
          ),
          const SizedBox(height: AppSpacing.demi), // mt-0.5
          Text(
            valeur,
            style: _t(
              TaillesContenu.lg,
              poids: FontWeight.bold,
              couleur: accent ?? AppColors.navy,
              interligne: TaillesContenu.interligneLg,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: AppSpacing.demi),
            Text(
              detail!,
              style: _t(TaillesContenu.t11, couleur: AppColors.neutre400),
            ),
          ],
        ],
      ),
    );
  }
}

/// La carte des filtres (`bg-white rounded-xl border p-3.5 mb-4`, l.182-246) :
/// recherche avec loupe (`flex-1 min-w-[220px]`), catégorie, point, suivi, état,
/// puis — repoussés à droite par un espace élastique — « Importer »,
/// « Modèle » et « Exporter ».
///
/// Sur une fenêtre trop étroite pour tenir sur une rangée, la barre passe à la
/// ligne comme le `flex-wrap` de la vue.
class _Filtres extends ConsumerStatefulWidget {
  const _Filtres({required this.categories, required this.onExporter});

  final List<String> categories;
  final VoidCallback onExporter;

  @override
  ConsumerState<_Filtres> createState() => _FiltresState();
}

class _FiltresState extends ConsumerState<_Filtres> {
  final _terme = TextEditingController();

  @override
  void dispose() {
    _terme.dispose();
    super.dispose();
  }

  void _dire(String texte, {Key? cle}) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(texte, key: cle)));
  }

  /// « Importer » — la modale de la vue ; le bilan est DIT à la fermeture.
  Future<void> _importer() async {
    final bilan = await ouvrirModaleImportArticles(context);
    if (bilan == null || !mounted) return;
    _dire(
      TextesImportArticles.bilan(bilan.crees),
      cle: const Key('stocks-import-bilan'),
    );
  }

  /// « Modèle » — `telechargerModeleCsv()` : le fichier est ENREGISTRÉ par la
  /// fenêtre « Enregistrer sous » du poste, et son chemin est dit.
  Future<void> _enregistrerModele() async {
    final chemin = await ref
        .read(selecteurFichiersProvider)
        .enregistrerSous(
          nomSuggere: TextesImportArticles.nomModele,
          octets: modeleImportArticlesOctets(),
        );
    if (chemin == null || !mounted) return;
    _dire(
      'Modèle enregistré : $chemin',
      cle: const Key('stocks-modele-enregistre'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final points = ref.watch(pointsStockProvider).value ?? const [];
    final bordure = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      borderSide: const BorderSide(color: AppColors.neutre300),
    );

    final recherche = TextField(
      key: const Key('stocks-recherche'),
      controller: _terme,
      style: _t(TaillesContenu.t13),
      decoration: InputDecoration(
        hintText: 'Rechercher un article…',
        isDense: true,
        prefixIcon: const Padding(
          padding: EdgeInsets.only(left: AppSpacing.sm),
          child: Icon(
            Icons.search,
            size: AppLayout.iconeChamp,
            color: AppColors.neutre400,
          ),
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: AppSpacing.xl + AppSpacing.unit, // pl-9
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
      onChanged: (v) => ref.read(rechercheStockProvider.notifier).definir(v),
    );

    final listes = <Widget>[
      _Liste<String?>(
        cle: const Key('stocks-filtre-categorie'),
        valeur: ref.watch(categorieStockProvider),
        items: [
          const DropdownMenuItem<String?>(child: Text('Toutes catégories')),
          for (final c in widget.categories)
            DropdownMenuItem<String?>(value: c, child: Text(c)),
        ],
        onChanged: (c) => ref.read(categorieStockProvider.notifier).definir(c),
      ),
      _Liste<String?>(
        cle: const Key('stocks-filtre-point'),
        valeur: ref.watch(pointStockProvider),
        items: [
          const DropdownMenuItem<String?>(child: Text('Tous les points')),
          for (final p in points)
            DropdownMenuItem<String?>(value: p.id, child: Text(p.libelle)),
        ],
        // Le point change la PORTÉE du calcul : c'est le stock qui est
        // recalculé à ce point, pas un filtre d'affichage.
        onChanged: (p) => ref.read(pointStockProvider.notifier).definir(p),
      ),
      // « Tous les suivis » (l.206-215) : les VALEURS sont le registre fermé
      // `SuiviArticle`, les LIBELLÉS ceux de la vue.
      _Liste<SuiviArticle?>(
        cle: const Key('stocks-filtre-suivi'),
        valeur: ref.watch(suiviStockProvider),
        items: const [
          DropdownMenuItem<SuiviArticle?>(child: Text('Tous les suivis')),
          DropdownMenuItem<SuiviArticle?>(
            value: SuiviArticle.permanent,
            child: Text('Gros stock (permanent)'),
          ),
          DropdownMenuItem<SuiviArticle?>(
            value: SuiviArticle.journalier,
            child: Text('Petit stock (journalier)'),
          ),
        ],
        onChanged: (s) => ref.read(suiviStockProvider.notifier).definir(s),
      ),
      _Liste<EtatStockFiltre>(
        cle: const Key('stocks-filtre-etat'),
        valeur: ref.watch(etatFiltreProvider),
        items: [
          for (final e in EtatStockFiltre.values)
            DropdownMenuItem(value: e, child: Text(e.libelle)),
        ],
        onChanged: (e) =>
            e == null ? null : ref.read(etatFiltreProvider.notifier).definir(e),
      ),
    ];

    // `text-[12px] px-3 py-2 rounded-lg` (vue l.232-245) : le bouton standard,
    // variante compacte (14/10/2026). « Importer » ouvre la modale de la vue
    // et CRÉE les articles ; « Modèle » enregistre le CSV vide aux colonnes
    // attendues là où l'utilisateur le décide.
    final boutons = <Widget>[
      BoutonStandard(
        key: const Key('stocks-importer'),
        libelle: TextesImportArticles.valider,
        compact: true,
        onPressed: _importer,
      ),
      BoutonStandard(
        key: const Key('stocks-modele'),
        libelle: TextesImportArticles.modele,
        compact: true,
        onPressed: _enregistrerModele,
      ),
      BoutonStandard(
        key: const Key('stocks-exporter'),
        libelle: TextesExport.bouton,
        compact: true,
        variante: VarianteBouton.primaire,
        onPressed: widget.onExporter,
      ),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md), // mb-4
      padding: const EdgeInsets.all(AppSpacing.smPlus),
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: AppColors.neutre200),
      ),
      // `flex flex-wrap gap-2.5 items-center` : la recherche et l'espace sont
      // élastiques (`flex-1`), le reste garde sa largeur, et la rangée passe à
      // la ligne quand elle ne tient pas — comme le navigateur, par mesure.
      child: RangeeFlexWrap(
        ecart: AppSpacing.xsPlus,
        ecartLignes: AppSpacing.xsPlus,
        children: [
          // `relative flex-1 min-w-[220px]`.
          ElementElastique(
            largeurMin: AppLayout.rechercheClients,
            child: recherche,
          ),
          ...listes,
          // `<div class="flex-1">` : l'espace qui repousse les boutons.
          const ElementElastique(child: SizedBox.shrink()),
          ...boutons,
        ],
      ),
    );
  }
}

/// `text-[13px] border border-slate-300 rounded-lg px-3 py-2`
class _Liste<T> extends StatelessWidget {
  const _Liste({
    required Key cle,
    required this.valeur,
    required this.items,
    required this.onChanged,
  }) : super(key: cle);

  final T valeur;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        border: Border.all(color: AppColors.neutre300),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: valeur,
            isDense: true,
            itemHeight: null,
            iconSize: AppLayout.iconeChamp,
            style: _t(TaillesContenu.t13, couleur: AppColors.neutre700),
            items: items,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}

/// Les articles par page — `Stocks::PAR_PAGE` (vue l.1077 du composant).
const int articlesParPage = 25;

/// La carte du tableau : le décompte et la mention « Stock calculé — non
/// modifiable ici », puis soit l'état vide de la vue, soit le tableau et son
/// pied de pagination.
class _CarteTableau extends ConsumerStatefulWidget {
  const _CarteTableau({
    required this.lignes,
    required this.cleFiltre,
    required this.onFiche,
    required this.onMouvement,
    required this.onModifier,
  });

  final List<LigneStock> lignes;

  /// Les filtres posés : les changer ramène la pagination à la page 1.
  final Object cleFiltre;
  final void Function(LigneStock) onFiche;
  final void Function(LigneStock) onMouvement;
  final void Function(LigneStock) onModifier;

  @override
  ConsumerState<_CarteTableau> createState() => _CarteTableauState();
}

class _CarteTableauState extends ConsumerState<_CarteTableau> {
  int _page = 1;

  /// Les articles cochés. Comme `Stocks::$selection`, elle ne vaut que pour CE
  /// QUI EST AFFICHÉ : un filtre, une page ou une recherche qui change la remet
  /// à zéro, sinon « Supprimer » porterait sur des lignes que l'écran ne montre
  /// plus (le défaut que PA-119 nomme pour l'export, transposé à un geste
  /// destructeur).
  final Set<String> _selection = {};

  @override
  void didUpdateWidget(covariant _CarteTableau ancien) {
    super.didUpdateWidget(ancien);
    // Rester en page 3 d'un résultat qui n'en a plus qu'une montrerait un
    // tableau vide sous un filtre qui trouve pourtant des lignes.
    if (ancien.cleFiltre != widget.cleFiltre) {
      _page = 1;
      _selection.clear();
    }
  }

  void _dire(String texte, {required Key cle, bool erreur = false}) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          backgroundColor: erreur ? AppColors.erreur : null,
          content: Text(texte, key: cle),
        ),
      );
  }

  /// `Stocks::confirmerArchivageArticle` puis `archiverArticles` : une ligne
  /// (son identifiant) ou la sélection AFFICHÉE.
  ///
  /// Le droit d'archiver est exigé DÈS l'ouverture, puis le lot est composé par
  /// le DAO (verrous rejoués sur les données locales) : BLOQUÉ (le bouton
  /// disparaît), PARTIEL (le décompte de ce qui restera) ou NOMINAL. Une
  /// sélection qui ne porte que des articles déjà archivés ouvre la modale
  /// BLOQUÉE, sans motif — la vue ne retourne que si la sélection est vide.
  Future<void> _confirmerArchivage(List<String> ids) async {
    if (ids.isEmpty) return;

    final ouverture = await ref.read(preparerArchivageArticlesProvider)(ids);
    if (!mounted) return;

    final LotArchivage lot;
    switch (ouverture) {
      case StocksOk(:final valeur):
        lot = valeur;
      case StocksRefuse(:final motif):
        _dire(motif, cle: const Key('stocks-archivage-refus'), erreur: true);
        return;
    }

    final confirme = await ouvrirArchivageAchats(
      context,
      // Une ligne : son nom, en gras. Plusieurs : le nombre qui PART.
      element: lot.element,
      nombre: lot.nombre,
      messagesVerrou: lot.motifs,
      bloque: lot.bloque,
      conserves: lot.conserves,
    );
    if (confirme != true || !mounted) return;

    final resultat = await ref.read(archiverArticlesProvider)(lot.ids);
    if (!mounted) return;

    switch (resultat) {
      case StocksOk(:final valeur):
        setState(_selection.clear);
        ref.invalidate(etatStockProvider);
        // Le succès ET le refus coexistent : un article devenu engagé entre
        // l'ouverture et le clic n'empêche pas les autres archivages du lot.
        // La vue les pose ensemble (bandeau vert, toast rouge) ; deux SnackBar se
        // mettraient en file et le refus resterait caché — ils partent donc dans
        // UNE seule, qui garde les deux messages.
        final succes = valeur.archives > 0
            ? MessagesStock.archivesSucces(valeur.archives)
            : null;
        if (valeur.refus != null) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              SnackBar(
                key: const Key('stocks-archivage-refus'),
                backgroundColor: AppColors.erreur,
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (succes != null)
                      Text(succes, key: const Key('stocks-archivage-succes')),
                    Text(valeur.refus!),
                  ],
                ),
              ),
            );
        } else if (succes != null) {
          _dire(succes, cle: const Key('stocks-archivage-succes'));
        }
      case StocksRefuse(:final motif):
        _dire(motif, cle: const Key('stocks-archivage-refus'), erreur: true);
    }
  }

  /// « Restaurer » : remet `actif = true`. Seul le droit d'écriture est exigé.
  Future<void> _restaurer(LigneStock ligne) async {
    final resultat = await ref.read(restaurerArticleProvider)(ligne.id);
    if (!mounted) return;
    switch (resultat) {
      case StocksOk(:final valeur):
        ref.invalidate(etatStockProvider);
        _dire(
          MessagesStock.restaure(valeur),
          cle: const Key('stocks-restaure'),
        );
      case StocksRefuse(:final motif):
        _dire(motif, cle: const Key('stocks-archivage-refus'), erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lignes = widget.lignes;
    final pages = lignes.isEmpty
        ? 1
        : (lignes.length + articlesParPage - 1) ~/ articlesParPage;
    final page = _page < 1 ? 1 : (_page > pages ? pages : _page);
    final premier = (page - 1) * articlesParPage;
    final dernier = premier + articlesParPage > lignes.length
        ? lignes.length
        : premier + articlesParPage;

    final peutArchiver = ref.watch(
      peutArchiverProvider(ModuleTatacora.m6Stocks),
    );
    final affiches = [for (final l in lignes.sublist(premier, dernier)) l.id];
    final selection = _selection.intersection(affiches.toSet());

    final carte = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: AppColors.neutre200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, // px-4
              vertical: AppSpacing.xsPlus, // py-2.5
            ),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.neutre200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  // `nombre_articles` : le TOTAL filtré, pas la page.
                  '${lignes.length} article(s)',
                  style: _t(TaillesContenu.t12, couleur: AppColors.neutre500),
                ),
                Text(
                  'Stock calculé — non modifiable ici',
                  style: _t(TaillesContenu.t11, couleur: AppColors.neutre400),
                ),
              ],
            ),
          ),
          if (lignes.isEmpty)
            // Un écran qui ne rend jamais rien passe pour cassé (leçon PA-90).
            Padding(
              key: const Key('stocks-vide'),
              padding: const EdgeInsets.all(AppSpacingLarge.p10),
              child: Column(
                children: [
                  const Icon(
                    Icons.search,
                    size: 34,
                    color: AppColors.neutre300,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Aucun résultat',
                    style: _t(
                      TaillesContenu.t15,
                      poids: FontWeight.w600,
                      couleur: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.unit),
                  Text(
                    'Aucun article ne correspond à ces filtres.',
                    style: _t(TaillesContenu.t13, couleur: AppColors.neutre500),
                  ),
                ],
              ),
            )
          else ...[
            // L'export reçoit la liste filtrée ENTIÈRE (`_exporter`), jamais la
            // page affichée.
            Consumer(
              builder: (context, ref, _) => TableStocks(
                lignes: lignes.sublist(premier, dernier),
                // RG-05 : ce que les ventes encore en file sortiront — dit,
                // jamais soustrait (`stock_en_attente.dart`).
                enAttente:
                    ref.watch(stockEnAttenteProvider).value ??
                    StockEnAttente.vide,
                onFiche: widget.onFiche,
                onMouvement: widget.onMouvement,
                onModifier: widget.onModifier,
                peutArchiver: peutArchiver,
                selection: selection,
                onBasculerTout: (coche) => setState(() {
                  _selection
                    ..clear()
                    ..addAll(coche ? affiches : const <String>[]);
                }),
                onBasculer: (id, coche) => setState(() {
                  coche ? _selection.add(id) : _selection.remove(id);
                }),
                onSupprimer: (l) => _confirmerArchivage([l.id]),
                onRestaurer: _restaurer,
              ),
            ),
            // `@if ($lignes->hasPages())` : le pied n'existe que s'il y a
            // plusieurs pages.
            if (pages > 1)
              _PiedPagination(
                premier: premier + 1,
                dernier: dernier,
                total: lignes.length,
                precedent: page <= 1
                    ? null
                    : () => setState(() => _page = page - 1),
                suivant: page >= pages
                    ? null
                    : () => setState(() => _page = page + 1),
              ),
          ],
        ],
      ),
    );

    // La barre de sélection groupée précède le cadre (vue l.274-283) : elle
    // n'existe que pour qui peut archiver ET quand une ligne est cochée.
    if (!peutArchiver || selection.isEmpty) return carte;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BarreSelection(
          nombre: selection.length,
          onSupprimer: () => _confirmerArchivage([
            for (final id in affiches)
              if (selection.contains(id)) id,
          ]),
          onEffacer: () => setState(_selection.clear),
        ),
        carte,
      ],
    );
  }
}

/// La barre de sélection groupée (vue l.274-283) : `flex items-center gap-3
/// bg-[var(--navy)] text-white rounded-lg px-4 py-2.5 mb-3 text-xs` — le décompte
/// (« sélectionné(s) », son nombre en gras), un espace élastique, « Supprimer »
/// souligné et la croix qui efface la sélection.
class _BarreSelection extends StatelessWidget {
  const _BarreSelection({
    required this.nombre,
    required this.onSupprimer,
    required this.onEffacer,
  });

  final int nombre;
  final VoidCallback onSupprimer;
  final VoidCallback onEffacer;

  @override
  Widget build(BuildContext context) {
    final base = _t(
      TaillesContenu.xs,
      couleur: AppColors.neutre0,
      interligne: TaillesContenu.interligneXs,
    );

    return Container(
      key: const Key('stocks-selection'),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm), // mb-3
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md, // px-4
        vertical: AppSpacing.xsPlus, // py-2.5
      ),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      ),
      child: Row(
        children: [
          Text.rich(
            TextSpan(
              style: base,
              children: [
                TextSpan(
                  text: '$nombre',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const TextSpan(text: ' sélectionné(s)'),
              ],
            ),
            key: const Key('stocks-selection-compte'),
          ),
          const Spacer(),
          InkWell(
            key: const Key('stocks-selection-supprimer'),
            onTap: onSupprimer,
            child: Text(
              'Supprimer',
              style: base.copyWith(
                decoration: TextDecoration.underline,
                decorationColor: AppColors.neutre0.withValues(alpha: 0.4),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          InkWell(
            key: const Key('stocks-selection-effacer'),
            onTap: onEffacer,
            child: Text(
              '✕',
              semanticsLabel: 'Annuler',
              style: base.copyWith(
                color: AppColors.neutre0.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Le pied de la vue (l.433-443) : `px-4 py-3 border-t border-slate-200 flex
/// items-center justify-between`, le décompte « 1 – 25 / 60 » à gauche, les
/// deux boutons à droite — « « Précédent » et « Suivant » » (`pagination.*`,
/// `&laquo;` et `&raquo;`), `text-[12px] px-3 py-1.5 rounded-lg border`,
/// grisés aux bornes.
class _PiedPagination extends StatelessWidget {
  const _PiedPagination({
    required this.premier,
    required this.dernier,
    required this.total,
    required this.precedent,
    required this.suivant,
  });

  final int premier;
  final int dernier;
  final int total;
  final VoidCallback? precedent;
  final VoidCallback? suivant;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('stocks-pagination'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md, // px-4
        vertical: AppSpacing.sm, // py-3
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.neutre200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$premier – $dernier / $total',
            key: const Key('stocks-pagination-decompte'),
            style: _t(TaillesContenu.t12, couleur: AppColors.neutre500),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              BoutonStandard(
                key: const Key('stocks-pagination-precedent'),
                libelle: '« Précédent',
                compact: true,
                margeVerticale: AppSpacing.xxs, // py-1.5
                onPressed: precedent,
              ),
              const SizedBox(width: AppSpacing.xs), // gap-2
              BoutonStandard(
                key: const Key('stocks-pagination-suivant'),
                libelle: 'Suivant »',
                compact: true,
                margeVerticale: AppSpacing.xxs,
                onPressed: suivant,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ce que ce stock ne sait pas — dit sous le tableau, en clair.
///
/// Jamais en infobulle : c'est la phrase qui empêche un chiffre exact en
/// apparence d'être pris pour le stock réel (PA-59/60/61).
class _Limites extends StatelessWidget {
  const _Limites({required this.kpis});

  final KpisStock kpis;

  @override
  Widget build(BuildContext context) {
    final style = _t(TaillesContenu.t12, couleur: AppColors.neutre500);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        key: const Key('stocks-limites'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            TextesStocks.ventesSansSortie,
            key: const Key('stocks-limite-ventes'),
            style: style,
          ),
          const SizedBox(height: AppSpacing.unit),
          Text(
            TextesStocks.sansComptabilite,
            key: const Key('stocks-limite-comptabilite'),
            style: style,
          ),
          if (kpis.sansValorisation > 0) ...[
            const SizedBox(height: AppSpacing.unit),
            Text(
              TextesStocks.sansValorisation(kpis.sansValorisation),
              key: const Key('stocks-limite-valorisation'),
              style: style,
            ),
          ],
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required Key cle, required this.texte}) : super(key: cle);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.neutre100,
        borderRadius: BorderRadius.circular(AppSpacing.md),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.neutre500),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              texte,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: AppColors.neutre500),
            ),
          ),
        ],
      ),
    );
  }
}
