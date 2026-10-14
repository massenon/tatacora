// Vue Blade maîtresse (PA-183) : pwa/pos/historique-ventes.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/formats.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared_widgets/pied_pagination.dart';
import '../../../shared_widgets/tableau_tatacora.dart';
import '../domain/journal_ventes.dart';
import 'providers_ventes.dart';
import 'widgets/barre_filtres_ventes.dart';
import 'widgets/table_ventes.dart';

/// **Historique des ventes** — `prototype_v2/pages/historique-ventes.html`.
///
/// ## Le journal des VENTES, pas le registre des factures
///
/// C'est le piège de cet écran, et `shell.js` le nomme sur l'entrée de menu :
/// *« une vente peut exister sans facture, et une vente annulée reste une vente
/// là où une facture annulée produit un avoir »*. Les deux écrans lisent donc
/// des tables différentes et **n'affichent jamais le même total** :
///
/// | | Historique des ventes | Facturation |
/// |---|---|---|
/// | Source | `paniers_local` | `pieces_facturation_local` |
/// | Ce qui manque à l'autre | les ventes **sans facture** | les **avoirs** |
/// | Une annulation | reste une vente, sans contre-partie | produit une **pièce** de montant négatif |
/// | Ce qu'on y cherche | une table, un poste, un service | un numéro de pièce, un client |
///
/// Cet écran n'affiche donc **aucun avoir** et n'additionne **aucun montant
/// négatif** ; le registre des factures, lui, ne connaît pas les ventes que
/// personne n'a facturées. Les confondre ferait chercher une vente dans un
/// registre qui ne la contient pas — et conclure qu'elle n'a jamais eu lieu.
///
/// ## Un écran local, comme tous ceux du poste
///
/// Ses trois lectures viennent de Drift. Il n'a donc ni bandeau de coupure, ni
/// issue « injoignable », ni bouton de réessai — il n'y a rien à joindre.
/// ⚠ Revu le 13/10/2026 : ce paragraphe disait « M11, Paramètres, M6 et M7
/// exigent le réseau ». C'était vrai à sa livraison, FAUX depuis : Paramètres,
/// M6, M7 et M4 sont locaux depuis le 09/10/2026, M11 et M14 depuis le
/// 10/10/2026, et le poste est zéro réseau — aucun écran n'exige plus le
/// réseau (vérifié le 12/10/2026).
///
/// ⚠ Et il ne dit **jamais** « en attente de synchronisation » : le poste est
/// zéro réseau, ces ventes ne partiront jamais. Un badge d'attente sur ce qui
/// ne partira jamais est la famille PA-59/60/61.
///
/// ## Le bandeau « Journal enregistré sur ce poste » est RETIRÉ (13/10/2026)
///
/// Demande du Product Owner (`INSTRUCTION3.txt`, §4.A) : la vue n'a pas ce
/// bandeau, et l'écran s'aligne sur elle. Rien ne le remplace — aucune phrase
/// de l'écran ne promet un envoi au serveur, et un test le vérifie sur tout le
/// texte rendu.
///
/// ## La pagination (décision du Product Owner du 13/10/2026)
///
/// Demandée par le PO (`INSTRUCTION3.txt`, §4.C), puis portée AUSSI dans la vue
/// le même jour (« pour que les deux applications restent identiques ») :
/// `HistoriqueVentes::VENTES_PAR_PAGE` = 10, pied « Affichage de X-Y sur Z » /
/// « ← Précédent » / « Page P / N » / « Suivant → » aux mots du pied
/// « Réservations en cours » de l'hébergement, les deux boutons TOUJOURS rendus
/// et désactivés aux bornes, retour en page 1 quand un filtre change
/// (`PiedPagination` ici). Les indicateurs et les exports portent sur la liste
/// FILTRÉE ENTIÈRE, jamais sur la seule page : une page n'est pas un filtre
/// (PA-119).
class EcranHistoriqueVentes extends ConsumerStatefulWidget {
  const EcranHistoriqueVentes({super.key});

  @override
  ConsumerState<EcranHistoriqueVentes> createState() =>
      _EtatEcranHistoriqueVentes();
}

class _EtatEcranHistoriqueVentes extends ConsumerState<EcranHistoriqueVentes> {
  /// La bande d'indicateurs est repliable, dépliée par défaut : un écran qui
  /// s'ouvre vide se lit comme un écran cassé. La vue retient l'état dans le
  /// navigateur ; ici il vaut pour la durée de l'écran.
  bool _indicateursOuverts = true;

  @override
  Widget build(BuildContext context) {
    final journal = ref.watch(journalVentesProvider);

    return SingleChildScrollView(
      // `max-w-[1600px] mx-auto p-5 lg:p-8` : 32 px au poste de travail.
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppLayout.pageHistoriqueVentes,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _EnTetePage(),
              _BandeIndicateurs(
                ouverts: _indicateursOuverts,
                onBasculer: () =>
                    setState(() => _indicateursOuverts = !_indicateursOuverts),
              ),
              const _CarteJournal(),
              journal.when(
                loading: () => const SizedBox.shrink(),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    key: const Key('ventes-erreur'),
                    'Le journal local n’a pas pu être lu : $e',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                data: (donnees) => _NotePaniersOuverts(journal: donnees),
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
  String famille = AppTextStyles.police,
  double espacement = 0,
}) => TextStyle(
  fontFamily: famille,
  fontSize: taille,
  fontWeight: poids,
  color: couleur,
  height: 1.5,
  letterSpacing: espacement,
);

/// L'en-tête de la vue : titre (sans icône), puis le sous-titre en 12 px dont
/// « ventes » est en gras et les deux exemples de numéros en police à chasse
/// fixe (`max-w-3xl`).
///
/// Le sous-titre n'est pas décoratif : il porte la règle qui commande tout
/// l'écran — c'est le journal des ventes, pas celui des factures.
class _EnTetePage extends StatelessWidget {
  const _EnTetePage();

  /// Le texte de la vue, au mot : les spans ci-dessous en sont DÉCOUPÉS, jamais
  /// réécrits à la main — une phrase recollée à la main finit par diverger.
  static const String sousTitre =
      'Le journal des ventes, pas des factures. Une vente peut exister sans '
      'facture si l’émission a échoué ; une vente annulée reste une vente, là '
      'où une facture annulée produit un avoir. Ici on retrouve un '
      'V-2026-00016, pas un F-2026-00042.';

  /// Le mot en gras et les deux exemples en police à chasse fixe.
  static List<InlineSpan> _spans(TextStyle mono) {
    const gras = 'ventes';
    const exemples = ['V-2026-00016', 'F-2026-00042'];

    final spans = <InlineSpan>[];
    var reste = sousTitre;

    void couper(String motif, TextStyle? style) {
      final i = reste.indexOf(motif);
      spans
        ..add(TextSpan(text: reste.substring(0, i)))
        ..add(TextSpan(text: motif, style: style));
      reste = reste.substring(i + motif.length);
    }

    couper(gras, const TextStyle(fontWeight: FontWeight.bold));
    couper(exemples[0], mono);
    couper(exemples[1], mono);
    spans.add(TextSpan(text: reste));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final base = _t(TaillesContenu.t12, couleur: AppColors.neutre500);
    final mono = base.copyWith(fontFamily: AppTextStyles.policeMonospace);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.mdPlus), // mb-5
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Historique des ventes',
            style: _t(
              TaillesContenu.lg,
              poids: FontWeight.bold,
              couleur: AppColors.navy,
            ).copyWith(height: TaillesContenu.interligneLg),
          ),
          const SizedBox(height: AppSpacing.unit), // mt-1
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppLayout.largeur3xl),
            child: Text.rich(
              key: const Key('ventes-sous-titre'),
              TextSpan(style: base, children: _spans(mono)),
            ),
          ),
        ],
      ),
    );
  }
}

/// La bande d'indicateurs : un bandeau repliable, puis cinq cartes
/// (`grid-cols-2 sm:grid-cols-3 xl:grid-cols-5 gap-3 mt-3`).
class _BandeIndicateurs extends ConsumerWidget {
  const _BandeIndicateurs({required this.ouverts, required this.onBasculer});

  final bool ouverts;
  final VoidCallback onBasculer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpis = ref.watch(kpisJournalVentesProvider);
    final colonnes = MediaQuery.sizeOf(context).width >= AppBreakpoints.xl
        ? 5
        : (MediaQuery.sizeOf(context).width >= AppBreakpoints.sm ? 3 : 2);

    final cartes = <Widget>[
      _CarteKpi(
        cle: const Key('ventes-kpi-nombre'),
        libelle: 'Ventes',
        valeur: '${kpis.ventes}',
        detail: '${kpis.annulees} annulée(s)',
      ),
      _CarteKpi(
        cle: const Key('ventes-kpi-ca'),
        libelle: 'Chiffre d’affaires',
        valeur: formaterFcfa(kpis.chiffreAffaires),
        // Le détail de la vue, augmenté du seul cas qu'elle ne connaît pas.
        // Sans cette phrase, la somme « Encaissé + Porté en note » serait
        // inférieure au chiffre d'affaires sans que rien ne l'explique, et
        // l'écart passerait pour une erreur de calcul.
        detail: kpis.ventesSansReglement == 0
            ? 'Ventes validées'
            : 'Ventes validées — dont ${kpis.ventesSansReglement} sans '
                  'règlement renseigné '
                  '(${formaterFcfa(kpis.montantSansReglement)})',
      ),
      _CarteKpi(
        cle: const Key('ventes-kpi-encaisse'),
        libelle: 'Encaissé',
        valeur: formaterFcfa(kpis.encaisse),
        detail: 'Réellement dans le tiroir',
        accent: CouleursTableau.accentSucces,
      ),
      _CarteKpi(
        cle: const Key('ventes-kpi-note'),
        libelle: 'Porté en note',
        valeur: formaterFcfa(kpis.enNote),
        detail: 'Créance client, réglée au départ',
        accent: kpis.enNote > 0 ? CouleursTableau.accentAlerte : null,
      ),
      // ⚠ La cinquième carte de la vue, SANS chiffre.
      //
      // Elle compte les ventes dont des articles n'ont décrémenté aucun stock.
      // Ce client n'écrit **aucun** mouvement de stock : les trois tables de
      // stock restent délibérément vides (PA-134). Afficher `0` reprendrait
      // mot pour mot « Toutes les ventes ont décrémenté » sur un écran qui n'a
      // rien décrémenté du tout — l'indicateur qui affirme un état qu'il n'a
      // pas vérifié.
      const _CarteKpi(
        cle: Key('ventes-kpi-stock'),
        libelle: 'Sans impact stock',
        valeur: null,
        // Court, parce que la rangée de cartes s'étire sur la plus haute : une
        // phrase de six lignes ici repousserait tout le tableau. La raison
        // complète est ci-dessus — afficher 0 dirait « toutes les ventes ont
        // décrémenté ».
        // « (PA-134) » retiré du texte affiché le 14/10/2026 (directive PO).
        detail: 'Non tenu ici',
      ),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.mdPlus), // mb-5
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: AppColors.neutre0,
            borderRadius: BorderRadius.circular(AppRadius.roundedXl),
            child: InkWell(
              key: const Key('ventes-indicateurs-bascule'),
              onTap: onBasculer,
              borderRadius: BorderRadius.circular(AppRadius.roundedXl),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, // px-4
                  vertical: AppSpacing.sm, // py-3
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.roundedXl),
                  border: Border.all(color: AppColors.neutre200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Indicateurs du journal',
                      style: _t(
                        TaillesContenu.sm,
                        poids: FontWeight.bold,
                        couleur: AppColors.neutre700,
                      ),
                    ),
                    if (MediaQuery.sizeOf(context).width >= AppBreakpoints.sm)
                      Text(
                        'Repliez la bande pour gagner de la hauteur de '
                        'tableau.',
                        style: _t(
                          TaillesContenu.t11,
                          couleur: AppColors.neutre400,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (ouverts)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm), // mt-3
              child: LayoutBuilder(
                builder: (context, c) {
                  final largeur =
                      (c.maxWidth - (colonnes - 1) * AppSpacing.sm) / colonnes;
                  return Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final carte in cartes)
                        SizedBox(width: largeur, child: carte),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _CarteKpi extends StatelessWidget {
  const _CarteKpi({
    required Key cle,
    required this.libelle,
    required this.valeur,
    required this.detail,
    this.accent,
  }) : super(key: cle);

  final String libelle;
  final String? valeur;
  final String detail;
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
            // `uppercase` est une transformation CSS : on l'applique plutôt que
            // de recopier des libellés déjà en capitales.
            libelle.toUpperCase(),
            style: _t(
              TaillesContenu.t11,
              poids: FontWeight.w600,
              couleur: AppColors.neutre400,
              espacement: 0.5,
            ),
          ),
          const SizedBox(height: AppSpacing.unit), // mt-1
          Text(
            valeur ?? 'Non consulté',
            style: _t(
              TaillesContenu.t17,
              poids: FontWeight.bold,
              couleur: valeur == null
                  ? AppColors.neutre500
                  : (accent ?? AppColors.navy),
            ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          const SizedBox(height: AppSpacing.unit), // mt-1
          Text(
            detail,
            style: _t(TaillesContenu.t11, couleur: AppColors.neutre400),
          ),
        ],
      ),
    );
  }
}

/// La carte du journal : la barre de filtres, la ligne « Filtre appliqué », puis
/// le tableau (`bg-white rounded-xl border overflow-hidden mb-4`).
class _CarteJournal extends ConsumerStatefulWidget {
  const _CarteJournal();

  /// Ventes par page — comme le pied de l'onglet « Réservations en cours »
  /// (`PAR_PAGE_RESERVATIONS`), dont ce pied reprend les mots.
  static const int ventesParPage = 10;

  @override
  ConsumerState<_CarteJournal> createState() => _EtatCarteJournal();
}

class _EtatCarteJournal extends ConsumerState<_CarteJournal> {
  int _page = 1;

  @override
  Widget build(BuildContext context) {
    // Un filtre changé ramène à la première page : rester en page 3 d'un
    // résultat qui n'en a plus qu'une montrerait un tableau vide sous un
    // filtre qui trouve pourtant des ventes.
    ref.listen(filtreVentesProvider, (_, _) => setState(() => _page = 1));

    final ventes = ref.watch(ventesAfficheesProvider);
    final filtre = ref.watch(filtreVentesProvider);
    final tranche = TranchePage.de(
      total: ventes.length,
      page: _page,
      parPage: _CarteJournal.ventesParPage,
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: AppColors.neutre200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BarreFiltresVentes(),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.neutre100)),
            ),
            child: Text(
              'Filtre appliqué : ${filtre.mention}',
              style: _t(TaillesContenu.t11, couleur: AppColors.neutre400),
            ),
          ),
          TableauVentes(ventes: tranche.decouper(ventes)),
          PiedPagination(
            key: const Key('ventes-pagination'),
            tranche: tranche,
            prefixeCle: 'ventes-pagination',
            onPage: (p) => setState(() => _page = p),
          ),
        ],
      ),
    );
  }
}

class _NotePaniersOuverts extends StatelessWidget {
  const _NotePaniersOuverts({required this.journal});

  final JournalVentes journal;

  @override
  Widget build(BuildContext context) {
    if (journal.paniersOuverts == 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: CouleursTableau.alerteFond,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        key: const Key('ventes-paniers-ouverts'),
        '${journal.paniersOuverts} panier(s) encore ouvert(s) ne figurent pas '
        'au journal : rien n’y est encore encaissé, et le mode de règlement se '
        'fige à la clôture. Ils sont au point de vente.',
        style: _t(TaillesContenu.t12, couleur: CouleursTableau.alerteTexte),
      ),
    );
  }
}
