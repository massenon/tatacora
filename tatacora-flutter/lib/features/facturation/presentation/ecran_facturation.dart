// Vue Blade maîtresse (PA-183) : pwa/facturation/facturation.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/format/formats.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared_widgets/bouton_standard.dart';
import '../../../shared_widgets/tableau_tatacora.dart';
import '../domain/certification_mecef.dart';
import '../domain/entities/piece_facturation.dart';
import '../impression/etat_registre_factures.dart';
import '../impression/ticket_facture.dart';
import 'providers_facturation.dart';
import 'widgets/vue_ticket.dart';

// L'annulation par avoir vit dans son fichier de modale (`Tailles` déclarées,
// hors `<main>`) ; elle reste atteignable d'ici, comme avant.
export 'widgets/dialogue_avoir.dart';

/// **M2 Facturation** — le registre, ses trois origines, et le ticket.
///
/// ## Un seul registre, trois origines
///
/// Les onglets d'origine sont un **filtre**, pas trois listes. C'est visible
/// dans le code : un seul `registreProvider`, à qui l'on passe une origine. La
/// numérotation, l'annulation et l'impression n'existent qu'en un exemplaire.
///
/// ## Le bandeau MECeF dit la vérité, et il la dérive
///
/// « MECeF — non certifiées, démonstration ». Il ne vient pas d'un littéral
/// posé à l'écran mais de [CertificationMecef], qui la dérive du **numéro
/// fiscal réellement porté** par chaque pièce. Le jour où l'inscription DGI
/// (PA-17) aboutira, le bandeau changera parce que les pièces auront changé —
/// pas parce que quelqu'un aura pensé à modifier une chaîne. C'est exactement
/// la parade de PA-61.
///
/// ## Ce que cet écran ne propose pas, délibérément
///
/// **Aucune suppression.** La correction passe par un avoir, et l'action
/// s'appelle « Annuler par avoir » plutôt qu'« Annuler » — le libellé dit ce
/// qui va se produire : une seconde pièce, avec son propre numéro.
class EcranFacturation extends ConsumerWidget {
  const EcranFacturation({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registre = ref.watch(registreProvider);
    final pieces = registre.value ?? const <PieceFacturation>[];

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
              const _EnTetePage(),
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: AppColors.neutre0,
                  borderRadius: BorderRadius.circular(AppRadius.roundedXl),
                  border: Border.all(color: AppColors.neutre200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _BarreRegistre(pieces: pieces),
                    _Compteurs(pieces: pieces),
                    registre.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.all(AppSpacing.xl),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (e, _) => Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Center(child: Text('$e')),
                      ),
                      data: (liste) => _Registre(pieces: liste),
                    ),
                    _PiedRegistre(total: pieces.length),
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

TextStyle _t(
  double taille, {
  FontWeight? poids,
  Color? couleur,
  double? espacement,
  String? famille,
}) => TextStyle(
  fontFamily: famille ?? AppTextStyles.police,
  fontSize: taille,
  fontWeight: poids,
  color: couleur,
  height: 1.5,
  letterSpacing: espacement,
);

/// L'en-tête de page de la vue : icône, titre, sous-titre (au mot).
///
/// ## Le bloc « Jeu de démonstration » du maître est REFUSÉ
///
/// `m2-facturation.html` l.33-39 posait un second tableau, sous le registre :
/// des factures livrées avec le prototype, que sa propre légende décrit comme
/// ne provenant pas des points de vente. Sur un poste réel, ce bloc mettrait
/// de fausses pièces dans un registre fiscal, à côté des vraies et numérotées
/// comme elles. C'est la version tableau de PA-113 : un document de
/// démonstration cesse d'être inoffensif dès qu'il est remis à quelqu'un.
/// Ses trois modales tombent avec lui :
///
///  - maitre-refuse:m2-facturation.html#modale-export
///  - maitre-refuse:m2-facturation.html#modale-import
///  - maitre-refuse:m2-facturation.html#modale-suppression
class _EnTetePage extends StatelessWidget {
  const _EnTetePage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.mdPlus), // mb-5
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.receipt_long_outlined,
                size: AppLayout.iconeTitrePage,
                color: AppColors.navy,
              ),
              const SizedBox(width: AppSpacing.xsPlus), // gap-2.5
              Text(
                'Facturation & Caisse MECeF',
                style: _t(
                  TaillesContenu.lg,
                  poids: FontWeight.bold,
                  couleur: AppColors.navy,
                ).copyWith(height: TaillesContenu.interligneLg),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs), // mt-1.5
          Text(
            'Émission de factures normalisées MECeF (DGI Bénin), '
            'consolidation multi-activités et suivi des encaissements',
            style: _t(TaillesContenu.t15, couleur: AppColors.neutre500),
          ),
        ],
      ),
    );
  }
}

/// La première rangée de la carte : titre du registre à gauche, recherche,
/// filtres et « Exporter » à droite (`px-4 py-3 border-b`).
///
/// Le filtre d'ORIGINE n'est pas dans la vue (« aucune colonne d'origine au
/// schéma ») mais ce client en porte une, réelle : il est conservé, rangé à
/// côté du filtre d'activité, là où le maître posait « Toutes les origines ».
class _BarreRegistre extends ConsumerStatefulWidget {
  const _BarreRegistre({required this.pieces});

  final List<PieceFacturation> pieces;

  @override
  ConsumerState<_BarreRegistre> createState() => _BarreRegistreState();
}

class _BarreRegistreState extends ConsumerState<_BarreRegistre> {
  final _terme = TextEditingController();

  @override
  void dispose() {
    _terme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final module = ref.watch(moduleFiltreProvider);
    final origine = ref.watch(origineFiltreeProvider);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md, // px-4
        vertical: AppSpacing.sm, // py-3
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.neutre200)),
      ),
      child: Wrap(
        // `flex flex-wrap items-start justify-between gap-3`
        alignment: WrapAlignment.spaceBetween,
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Registre des factures émises',
                style: _t(
                  TaillesContenu.t14,
                  poids: FontWeight.bold,
                  couleur: AppColors.navy,
                ),
              ),
              const SizedBox(height: AppSpacing.demi), // mt-0.5
              Text(
                'Une seule séquence de numéros, toutes origines confondues — '
                'POS au comptant, séjours clôturés et factures directes.',
                style: _t(TaillesContenu.t11, couleur: AppColors.neutre400),
              ),
            ],
          ),
          Wrap(
            spacing: AppSpacing.xs, // gap-2
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: AppLayout.rechercheFacture, // w-48
                child: TextField(
                  key: const Key('facturation-recherche'),
                  controller: _terme,
                  style: _t(TaillesContenu.t13),
                  decoration: InputDecoration(
                    hintText: 'N°, client…',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xxs, // py-1.5
                    ),
                    border: _bordure(),
                    enabledBorder: _bordure(),
                    focusedBorder: _bordure(couleur: AppColors.gold),
                  ),
                  onChanged: (v) =>
                      ref.read(rechercheFactureProvider.notifier).definir(v),
                ),
              ),
              _Liste<ModuleFacturable?>(
                cle: const Key('facturation-filtre-module'),
                valeur: module,
                items: [
                  // La première entrée du maître, à valeur vide.
                  const DropdownMenuItem<ModuleFacturable?>(
                    child: Text('Toutes les activités'),
                  ),
                  for (final m in ModuleFacturable.values)
                    DropdownMenuItem<ModuleFacturable?>(
                      value: m,
                      child: Text(m.libelle),
                    ),
                ],
                onChanged: (m) =>
                    ref.read(moduleFiltreProvider.notifier).definir(m),
              ),
              _Bouton(
                cle: const Key('facturation-exporter'),
                libelle: 'Exporter',
                onTap: () => _exporter(context),
              ),
              // Après « Exporter » : la vue n'a pas ce filtre, et le poser avant
              // décalerait de 164 px le bouton qu'elle place là.
              _Liste<OrigineFacture?>(
                cle: const Key('facturation-filtre-origine'),
                valeur: origine,
                items: [
                  const DropdownMenuItem<OrigineFacture?>(
                    child: Text('Toutes les origines'),
                  ),
                  for (final o in OrigineFacture.values)
                    DropdownMenuItem<OrigineFacture?>(
                      key: Key('facturation-origine-${o.code}'),
                      value: o,
                      child: Text(o.libelle),
                    ),
                ],
                onChanged: (o) =>
                    ref.read(origineFiltreeProvider.notifier).definir(o),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// UN bouton « Exporter » (dérogation du Product Owner du 01/09/2026,
  /// `DerogationsMaquette::export_bouton_unique`) : le format s'y choisit.
  void _exporter(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(
        title: Text('Exporter — Registre des factures'),
        content: _BarreExports(),
      ),
    );
  }

  static OutlineInputBorder _bordure({Color couleur = AppColors.neutre300}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        borderSide: BorderSide(color: couleur),
      );
}

/// `text-[13px] border border-slate-300 rounded-lg px-2.5 py-1.5`
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
          horizontal: AppSpacing.xsPlus, // px-2.5
          vertical: AppSpacing.xxs, // py-1.5
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: valeur,
            isDense: true,
            itemHeight: null,
            // L'icône par défaut (24 px) grandit la liste au-delà de sa ligne.
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

class _Bouton extends StatelessWidget {
  const _Bouton({required Key cle, required this.libelle, required this.onTap})
    : super(key: cle);

  final String libelle;
  final VoidCallback onTap;

  /// Le bouton standard (PO, 14/10/2026), `px-3 py-1.5`.
  @override
  Widget build(BuildContext context) => BoutonStandard(
    libelle: libelle,
    margeHorizontale: AppSpacing.sm,
    margeVerticale: AppSpacing.xxs,
    onPressed: onTap,
  );
}

/// La rangée de compteurs (`px-4 py-2.5 border-b bg-slate-50`) : pièces,
/// avoirs, montant, et la mention de certification — **dérivée des pièces**
/// (PA-119/PA-61), jamais figée : elle dit « non certifiées, démonstration »
/// tant qu'aucune pièce ne porte un vrai numéro MECeF.
class _Compteurs extends StatelessWidget {
  const _Compteurs({required this.pieces});

  final List<PieceFacturation> pieces;

  @override
  Widget build(BuildContext context) {
    final avoirs = pieces.where((p) => p.estAvoir).length;
    final montant = pieces.fold<int>(0, (t, p) => t + p.montantTotal);
    final certifiees = pieces
        .where((p) => CertificationMecef.estReelle(p.numeroMecef))
        .length;

    // Le libellé et sa valeur sont deux textes distincts, comme les deux
    // nœuds de la vue (`Pièces <strong>0</strong>`).
    Widget compteur(String cle, String libelle, String valeur) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$libelle ',
          style: _t(TaillesContenu.t12, couleur: AppColors.neutre500),
        ),
        Text(
          valeur,
          key: Key(cle),
          style: _t(
            TaillesContenu.t12,
            poids: FontWeight.bold,
            couleur: AppColors.navy,
          ),
        ),
      ],
    );

    final styleMecef = _t(
      TaillesContenu.t12,
      couleur: AppColors.reserveGoldTexte,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xsPlus,
      ),
      decoration: const BoxDecoration(
        color: AppColors.neutre50,
        border: Border(bottom: BorderSide(color: AppColors.neutre200)),
      ),
      child: Wrap(
        spacing: AppSpacing.md, // gap-4
        runSpacing: AppSpacing.unit,
        children: [
          compteur('facturation-kpi-factures', 'Pièces', '${pieces.length}'),
          compteur('facturation-kpi-avoirs', 'Avoirs', '$avoirs'),
          compteur(
            'facturation-kpi-net',
            'Montant',
            TicketFacture.montant(montant),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('MECeF — ', style: styleMecef),
              Text(
                certifiees == 0
                    ? 'non certifiées, démonstration'
                    : '$certifiees pièce(s) certifiée(s)',
                key: const Key('facturation-bandeau-mecef'),
                style: styleMecef.copyWith(fontWeight: FontWeight.bold),
              ),
              if (certifiees > 0)
                Text(' sur ${pieces.length} affichée(s)', style: styleMecef),
            ],
          ),
        ],
      ),
    );
  }
}

/// Le tableau du registre — les colonnes du maître, dans son ordre, aux
/// largeurs relevées dans le navigateur (`<table class="w-full">`, `px-4
/// py-2.5`). La case de sélection du maître n'est pas rendue (aucun geste de
/// groupe côté client) ; sa largeur est réservée pour que les colonnes tombent
/// où elles tombent dans la vue.
class _Registre extends ConsumerWidget {
  const _Registre({required this.pieces});

  final List<PieceFacturation> pieces;

  static const _titres = [
    'N°',
    'Date',
    'Client',
    'Origine',
    'Activités',
    'Montant',
    'Mode de paiement',
    'Statut',
    '',
  ];
  static const _parts = [677, 892, 1056, 1135, 1600, 1042, 2083, 985, 600];
  static const _aDroite = {'Montant'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: AppColors.navy,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xsPlus),
          child: _Rangee(
            cellules: [
              for (final t in _titres)
                Text(
                  t.toUpperCase(),
                  textAlign: _aDroite.contains(t)
                      ? TextAlign.right
                      : TextAlign.left,
                  style: _t(
                    TaillesContenu.t11,
                    poids: FontWeight.w600,
                    couleur: AppColors.neutre0.withValues(alpha: 0.90),
                    espacement: 0.5,
                  ),
                ),
            ],
          ),
        ),
        if (pieces.isEmpty)
          Container(
            key: const Key('facturation-registre-vide'),
            padding: const EdgeInsets.all(AppSpacingLarge.p10),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Aucun résultat',
                  style: _t(
                    TaillesContenu.t13,
                    poids: FontWeight.w600,
                    couleur: AppColors.neutre500,
                  ),
                ),
                Text(
                  'Essayez de modifier votre recherche ou vos filtres.',
                  style: _t(TaillesContenu.t13, couleur: AppColors.neutre400),
                ),
                Text(
                  'Aucune facture émise. Encaissez au point de vente ou '
                  'clôturez un séjour.',
                  style: _t(TaillesContenu.t13, couleur: AppColors.neutre400),
                ),
              ],
            ),
          )
        else
          for (final piece in pieces)
            InkWell(
              key: Key('facturation-piece-${piece.id}'),
              // Le ticket, son impression, la facture A4 et l'annulation par
              // avoir restent atteignables depuis la ligne.
              onTap: () => afficherTicket(context, piece),
              child: Container(
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.neutre100)),
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.xsPlus,
                ),
                child: _Rangee(cellules: _cellules(piece)),
              ),
            ),
      ],
    );
  }

  /// Une ligne — `ligneFacture()` du maître. Le numéro en police à chasse fixe,
  /// la date et les activités en ardoise, le montant en gras (rouge s'il est
  /// négatif : un avoir), « — » quand la donnée n'existe pas.
  static List<Widget> _cellules(PieceFacturation piece) {
    final activites = piece.lignes
        .map((l) => l.module.libelle)
        .toSet()
        .join(', ');

    return [
      CelluleTableau(piece.numero, monospace: true),
      CelluleTableau(formaterDate(piece.dateEmission), secondaire: true),
      CelluleTableau(piece.clientNom),
      CelluleTableau(piece.origine.libelle, secondaire: true),
      CelluleTableau(activites.isEmpty ? '—' : activites, secondaire: true),
      CelluleTableau(
        formaterFcfa(piece.montantTotal),
        gras: true,
        couleur: piece.montantTotal < 0 ? CouleursTableau.montantNegatif : null,
      ),
      CelluleTableau(piece.modePaiement ?? '—', secondaire: true),
      if (piece.avoirDe != null)
        PastilleStatut.neutre('avoir de ${piece.avoirDe}')
      else if (piece.estAnnulee)
        const PastilleStatut.refus('annulée')
      else
        const PastilleStatut.succes('émise'),
      const SizedBox.shrink(),
    ];
  }
}

/// Une rangée de cellules `px-4`, aux parts de largeur de la vue, après la
/// colonne réservée à la case de sélection.
class _Rangee extends StatelessWidget {
  const _Rangee({required this.cellules});

  final List<Widget> cellules;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: AppLayout.colonneSelection),
        for (var i = 0; i < cellules.length; i++)
          Expanded(
            flex: _Registre._parts[i],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Align(
                alignment: i == 5
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: cellules[i],
              ),
            ),
          ),
      ],
    );
  }
}

/// `px-4 py-3 border-t border-slate-100 text-xs` — le décompte de la vue.
/// Le registre n'est pas paginé ici : tout ce qui correspond est affiché.
class _PiedRegistre extends StatelessWidget {
  const _PiedRegistre({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    Widget fort(String t) => Text(
      t,
      style: _t(
        TaillesContenu.t12,
        poids: FontWeight.bold,
        couleur: AppColors.neutre500,
      ),
    );
    final base = _t(TaillesContenu.t12, couleur: AppColors.neutre500);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.neutre100)),
      ),
      child: Row(
        children: [
          Text('Affichage de ', style: base),
          fort(total == 0 ? '0' : '1'),
          Text('-', style: base),
          fort('$total'),
          Text(' sur ', style: base),
          fort('$total'),
        ],
      ),
    );
  }
}

/// Le choix du format d'export — **ce qui est AFFICHÉ**.
///
/// C'est la règle que le maître écrit au-dessus de sa fonction d'export, et
/// elle est reprise telle quelle : le filtre d'origine s'applique au document.
/// Quelqu'un qui filtre sur les séjours et exporte attend les séjours — lui
/// rendre le registre entier lui ferait envoyer au comptable un document qu'il
/// croit avoir vérifié.
///
/// Une liste vide se REFUSE : le maître affiche « Rien à exporter : la liste
/// filtrée est vide. » plutôt que de produire un document d'une page blanche.
class _BarreExports extends ConsumerWidget {
  const _BarreExports();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registre = ref.watch(registreProvider);
    final origine = ref.watch(origineFiltreeProvider);
    final pieces = registre.value ?? const <PieceFacturation>[];

    EtatRegistreFactures etat() => EtatRegistreFactures(
      pieces: pieces,
      // Le filtre est DIT sur le document : sans cette mention, un extrait se
      // lirait comme un registre complet, et c'est sur un registre qu'on
      // rapproche une caisse.
      filtre: origine == null
          ? 'Toutes origines'
          : 'Origine : ${origine.libelle}',
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Bouton standard (PO, 14/10/2026).
        BoutonStandard(
          key: const Key('facturation-export-excel'),
          libelle: 'Export Excel',
          onPressed: () => _exporter(context, ref, etat()),
        ),
        const SizedBox(width: AppSpacing.xs),
        BoutonStandard(
          key: const Key('facturation-export-pdf'),
          libelle: 'Export PDF',
          variante: VarianteBouton.primaire,
          onPressed: () => _imprimer(context, ref, etat()),
        ),
      ],
    );
  }

  /// Vrai quand il y a quelque chose à exporter ; sinon le dit et refuse.
  bool _verifier(BuildContext context, EtatRegistreFactures etat) {
    if (!etat.estVide) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Rien à exporter : la liste filtrée est vide.',
          key: Key('facturation-export-vide'),
        ),
      ),
    );
    return false;
  }

  Future<void> _imprimer(
    BuildContext context,
    WidgetRef ref,
    EtatRegistreFactures etat,
  ) async {
    if (!_verifier(context, etat)) return;
    await ref.read(imprimerRegistreProvider)(etat);
  }

  Future<void> _exporter(
    BuildContext context,
    WidgetRef ref,
    EtatRegistreFactures etat,
  ) async {
    if (!_verifier(context, etat)) return;

    final chemin = await ref.read(exporterRegistreProvider)(etat);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Export enregistré sur ce poste : $chemin',
          key: const Key('facturation-export-chemin'),
        ),
      ),
    );
  }
}

/// Ouvre l'aperçu du ticket.
///
/// Fonction partagée plutôt que recopiée : les deux points de vente et l'écran
/// Facturation doivent ouvrir **le même** ticket, sans quoi l'un des trois
/// finirait par en présenter une variante.
Future<void> afficherTicket(BuildContext context, PieceFacturation piece) =>
    showDialog<void>(
      context: context,
      builder: (context) => VueTicket(piece: piece),
    );
