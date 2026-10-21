// Vue Blade maîtresse (PA-183) : pwa/pos/comptant.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart' show droitsProvider;
import '../../../../core/format/formats.dart';
import '../../../../core/rbac/garde_acces.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../caisse/presentation/providers_caisse.dart'
    show sessionDuBarProvider;
import '../../../facturation/domain/entities/piece_facturation.dart';
import '../../../facturation/presentation/providers_facturation.dart'
    show emettrePourPanierProvider;
import '../../../facturation/presentation/widgets/vue_ticket.dart'
    show imprimerLaFactureA4Depuis;
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../../restaurant/presentation/widgets/textes_modale_restaurant.dart';
import '../../../ventes/domain/entities/vente.dart';
import '../../../ventes/presentation/providers_ventes.dart';
import '../../domain/entities/panier.dart';
import '../../domain/entities/reference_catalogue.dart';
import '../../domain/messages_ventes.dart' show RefusVente;
import '../providers_pos.dart';

/// Les quatre modales du comptoir que la vue pose sous ses trois panneaux
/// (`pwa/pos/comptant.blade.php` l.431-745) : « Vente encaissée » (le ticket),
/// « Journal du jour », « Annuler cette vente » et « Stock insuffisant ».
///
/// Elles sont rendues dans le châssis partagé des modales
/// ([CoquilleModaleRestaurant], l'équivalent de `x-pwa.modale`), à l'échelle
/// typographique DÉCLARÉE : les modales sont hors de `<main>`.
///
/// ## Ce que ces modales rendent, et ce qu'elles ne rendent pas
///
/// * La **remise** (ligne « Remise », `- montant`) du ticket n'est PAS rendue : le
///   panier de ce poste ne porte aucune remise (`paniers_local` n'a ni type ni
///   valeur de remise), donc `remiseDeduite()` vaut toujours zéro. Mention de
///   MESURE : « Remise ».
/// * Le **numéro de vente** est la référence locale de huit caractères
///   (`Vente.referenceLocale`) : aucune séquence `V-AAAA-NNNNN` n'existe sur ce
///   poste (deux postes hors ligne attribueraient les mêmes numéros).
/// * Les « articles sans lien au stock » du ticket et du journal lisent le
///   catalogue d'AUJOURD'HUI (`CatalogueDao.referencesSansLienDeStock`), là où le
///   serveur écrit `stock_non_impacte` à la vente.

TextStyle _t(
  double taille, {
  FontWeight? poids,
  Color? couleur,
  String famille = AppTextStyles.police,
}) => TextStyle(
  fontFamily: famille,
  fontSize: taille,
  fontWeight: poids,
  color: couleur,
);

/* ====================================================================== */
/* « Vente encaissée » — le ticket (l.431-492)                              */
/* ====================================================================== */

/// Ouvre la modale « Vente encaissée » pour le panier [cloture] qui vient d'être
/// encaissé. [piece] est la facture émise pour cette vente, `null` quand
/// l'émission a échoué : le bouton « Facture » la ré-émet alors (rattrapage).
Future<void> ouvrirVenteEncaissee(
  BuildContext context,
  WidgetRef ref, {
  required Panier cloture,
  PieceFacturation? piece,
}) async {
  final sansLien = await ref
      .read(catalogueDaoProvider)
      .referencesSansLienDeStock();
  final libelles = await ref.read(tablesPosDaoProvider).libelles();
  final tableId = cloture.tableId;
  final vente = Vente.depuisPanier(
    cloture,
    libelleTable: tableId == null ? null : libelles[tableId],
    numeroFacture: piece?.numero,
    sansLienStock: sansLien,
  );
  if (vente == null || !context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierColor: AppColors.voileModale,
    builder: (_) =>
        ModaleVenteEncaissee(vente: vente, panier: cloture, piece: piece),
  );
}

class ModaleVenteEncaissee extends ConsumerWidget {
  const ModaleVenteEncaissee({
    required this.vente,
    required this.panier,
    this.piece,
    super.key,
  });

  final Vente vente;
  final Panier panier;
  final PieceFacturation? piece;

  /// `pos_pwa.comptant.ticket_titre`.
  static const String titre = 'Vente encaissée';

  /// Les entêtes du maître, à la lettre (`pos_pwa.document.entete_*`) : sans
  /// accent sur « Quantite ».
  static const List<String> entetes = [
    'Article',
    'Quantite',
    'Prix unitaire',
    'Montant',
  ];

  /// `pos_pwa.comptant.ticket_porte_en_note`.
  static const String porteEnNote =
      'Porté en note de chambre : ce montant n’est PAS dans le tiroir. Il devient une créance, réglée au départ du client.';

  /// `pos_pwa.comptant.ticket_stock` : « Leur fiche technique est absente »
  /// quand les lignes sont des plats, « Leur lien au stock est absent » (le mot
  /// du journal) dès qu'une boisson sans article de stock en fait partie — une
  /// boisson n'a pas de fiche technique.
  static String texteStock(Vente v) {
    final n = v.lignesSansImpactStock.length;
    final liste = v.lignesSansImpactStock.join(', ');
    final seulementDesPlats = v.lignes
        .where((l) => l.sansLienStock)
        .every((l) => l.module == ModuleVendable.m4Restaurant);
    return seulementDesPlats
        ? '$n article(s) n’ont décrémenté aucun stock : $liste. Leur fiche technique est absente.'
        : '$n article(s) n’ont décrémenté aucun stock : $liste. Leur lien au stock est absent.';
  }

  Future<void> _facture(BuildContext context, WidgetRef ref) async {
    final messager = ScaffoldMessenger.of(context);
    var courante = piece;
    if (courante == null) {
      // Rattrapage : la vente est encaissée, seule la pièce manque.
      try {
        courante = await ref.read(emettrePourPanierProvider)(panier);
      } on Object catch (e) {
        messager.showSnackBar(
          SnackBar(
            content: Text(
              'Facture non émise : $e La vente est clôturée à '
              '${panier.montantCloture} FCFA ; la facture reste à émettre.',
            ),
          ),
        );
        return;
      }
    }
    if (context.mounted) {
      await imprimerLaFactureA4Depuis(context, ref, courante);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = vente.mode?.libelle ?? 'règlement non renseigné';

    return CoquilleModaleRestaurant(
      cle: const Key('modale-vente-encaissee'),
      titre: titre,
      // `$derniereVente->numero . ' — ' . mode`.
      sousTitre: '${vente.referenceLocale} — $mode',
      largeur: LargeursPos.modaleVenteEncaissee,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // `text-[11px] uppercase text-slate-500 border-b border-slate-200`.
          Container(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Ardoise.c200)),
            ),
            child: Row(
              children: [
                for (final (i, e) in entetes.indexed)
                  Expanded(
                    flex: i == 0 ? 3 : 2,
                    child: Text(
                      e.toUpperCase(),
                      textAlign: switch (i) {
                        0 => TextAlign.left,
                        1 => TextAlign.center,
                        _ => TextAlign.right,
                      },
                      style: _t(Tailles.t11, couleur: Ardoise.c500),
                    ),
                  ),
              ],
            ),
          ),
          for (final l in vente.lignes)
            Container(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Ardoise.c100)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(l.libelle, style: _t(Tailles.t13)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '${l.quantite}',
                      textAlign: TextAlign.center,
                      style: _t(Tailles.t13),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      formaterFcfa(l.prixUnitaire),
                      textAlign: TextAlign.right,
                      style: _t(Tailles.t13),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      formaterFcfa(l.montant),
                      textAlign: TextAlign.right,
                      style: _t(Tailles.t13, poids: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          // `flex justify-between font-bold text-base border-t border-slate-300
          // pt-2` : « Total », le net encaissé.
          Container(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Ardoise.c300)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total',
                  style: _t(
                    Tailles.t16,
                    poids: FontWeight.bold,
                    couleur: AppColors.navy,
                  ),
                ),
                Text(
                  formaterFcfa(vente.montant),
                  key: const Key('vente-encaissee-total'),
                  style: _t(
                    Tailles.t16,
                    poids: FontWeight.bold,
                    couleur: AppColors.navy,
                  ),
                ),
              ],
            ),
          ),
          if (vente.encaisse == false) ...[
            const SizedBox(height: AppSpacing.sm),
            _Pave(
              cle: const Key('vente-encaissee-note'),
              texte: porteEnNote,
              fond: PaletteMaitre.ambre50,
              bord: PaletteMaitre.ambre200,
              couleur: PaletteMaitre.ambre800,
            ),
          ],
          if (vente.aDesLignesSansImpactStock) ...[
            const SizedBox(height: AppSpacing.sm),
            _Pave(
              cle: const Key('vente-encaissee-stock'),
              texte: texteStock(vente),
              fond: PaletteMaitre.rouge50,
              bord: PaletteMaitre.rouge200,
              couleur: PaletteMaitre.rouge700,
            ),
          ],
        ],
      ),
      actions: [
        // `ticket_thermique` — la MÊME vente sur le rouleau 80 mm.
        OutlinedButton(
          key: const Key('vente-encaissee-ticket-80'),
          onPressed: () => ref.read(imprimerTicketVenteProvider)(vente),
          child: const Text(
            'Ticket 80 mm',
            style: TextesModaleRestaurant.bouton,
          ),
        ),
        // `ticket_facture_a4` — « Facture », bordure or.
        OutlinedButton(
          key: const Key('vente-encaissee-facture'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.gold,
            side: const BorderSide(color: AppColors.gold),
          ),
          onPressed: () => _facture(context, ref),
          child: const Text('Facture', style: TextesModaleRestaurant.bouton),
        ),
        FilledButton(
          key: const Key('vente-encaissee-fermer'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer', style: TextesModaleRestaurant.bouton),
        ),
      ],
    );
  }
}

/// `text-[11.5px] rounded-lg px-3 py-2` bordé : les encadrés du ticket.
class _Pave extends StatelessWidget {
  const _Pave({
    required this.cle,
    required this.texte,
    required this.fond,
    required this.bord,
    required this.couleur,
  });

  final Key cle;
  final String texte;
  final Color fond;
  final Color bord;
  final Color couleur;

  @override
  Widget build(BuildContext context) => Container(
    key: cle,
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
    decoration: BoxDecoration(
      color: fond,
      border: Border.all(color: bord),
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
    ),
    child: Text(texte, style: _t(Tailles.t12, couleur: couleur)),
  );
}

/* ====================================================================== */
/* « Journal du jour » (l.494-583)                                          */
/* ====================================================================== */

/// Les ventes de la session de caisse OUVERTE — `$ventesDeLaSession` de la vue :
/// celles que `session_encaissement_id` rattache à la session, annulées
/// comprises (elles restent au journal, marquées).
final ventesDeLaSessionProvider = FutureProvider.autoDispose
    .family<List<Vente>, String>((ref, sessionId) async {
      final journal = await ref.watch(journalVentesProvider.future);
      final paniers = await ref.watch(paniersProvider.future);
      final ids = {
        for (final p in paniers)
          if (p.sessionEncaissementId == sessionId &&
              p.statut != StatutPanier.ouvert)
            p.id,
      };
      return [
        for (final v in journal.ventes)
          if (ids.contains(v.id)) v,
      ];
    });

/// Les quatre indicateurs de la modale, calculés comme la vue : sur les ventes
/// VALIDÉES (les annulées n'entrent ni au chiffre d'affaires ni au panier
/// moyen).
({int chiffreAffaires, int encaisse, int panierMoyen, int articles})
indicateursDuJour(List<Vente> ventes) {
  final validees = ventes.where((v) => v.estValidee).toList();
  final ca = validees.fold(0, (t, v) => t + v.montant);
  final encaisse = validees
      .where((v) => v.encaisse == true)
      .fold(0, (t, v) => t + v.montant);
  final articles = validees.fold(0, (t, v) => t + v.nombreArticles);
  // `bcdiv($caJour, $nombre, 2)` : le panier moyen, au franc le plus proche.
  final moyen = validees.isEmpty
      ? 0
      : (ca * 2 + validees.length) ~/ (2 * validees.length);
  return (
    chiffreAffaires: ca,
    encaisse: encaisse,
    panierMoyen: moyen,
    articles: articles,
  );
}

Future<void> ouvrirJournalDuJour(BuildContext context) => showDialog<void>(
  context: context,
  barrierColor: AppColors.voileModale,
  builder: (_) => const ModaleJournalDuJour(),
);

class ModaleJournalDuJour extends ConsumerWidget {
  const ModaleJournalDuJour({super.key});

  /// `pos_pwa.comptant.journal_du_jour`.
  static const String titre = 'Journal du jour';

  /// Les six entêtes du maître, à la lettre (`pos_pwa.document.entete_*`).
  static const List<String> entetes = [
    'N°',
    'Heure',
    'Table / chambre',
    'Règlement',
    'Montant',
    'Statut',
  ];

  /// `pos_pwa.comptant.journal_vide`.
  static const String vide = 'Aucune vente aujourd’hui.';

  static String _heure(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionDuBarProvider).value;
    final ventes = session == null
        ? const <Vente>[]
        : (ref.watch(ventesDeLaSessionProvider(session.id)).value ??
              const <Vente>[]);
    final k = indicateursDuJour(ventes);
    final peutEcrire = ref
        .watch(droitsProvider)
        .peutEcrire(ModuleTatacora.m5Bar);

    Widget kpi(Key cle, String libelle, String valeur, {Color? couleur}) =>
        Expanded(
          child: Container(
            key: cle,
            padding: const EdgeInsets.all(AppSpacing.xsPlus),
            decoration: BoxDecoration(
              color: Ardoise.c50,
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  libelle.toUpperCase(),
                  style: _t(Tailles.t10, couleur: Ardoise.c400),
                ),
                Text(
                  valeur,
                  style: _t(
                    Tailles.t15,
                    poids: FontWeight.bold,
                    couleur: couleur ?? AppColors.navy,
                    famille: AppTextStyles.policeMonospace,
                  ),
                ),
              ],
            ),
          ),
        );

    TextStyle entete() =>
        _t(Tailles.t11, poids: FontWeight.w600, couleur: AppColors.neutre0);

    return CoquilleModaleRestaurant(
      cle: const Key('modale-journal-du-jour'),
      titre: titre,
      // `caisse_ventes` : « N vente(s) » — TOUTES les ventes de la session.
      sousTitre: '${ventes.length} vente(s)',
      largeur: LargeursPos.modaleJournalDuJour,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // `journal_ca`, `journal_encaisse`, `journal_panier_moyen`,
              // `journal_articles`.
              kpi(
                const Key('journal-kpi-ca'),
                "Chiffre d'affaires",
                formaterFcfa(k.chiffreAffaires),
              ),
              const SizedBox(width: AppSpacing.xsPlus),
              kpi(
                const Key('journal-kpi-encaisse'),
                'Encaissé',
                formaterFcfa(k.encaisse),
                couleur: PaletteMaitre.emeraude600,
              ),
              const SizedBox(width: AppSpacing.xsPlus),
              kpi(
                const Key('journal-kpi-panier-moyen'),
                'Panier moyen',
                formaterFcfa(k.panierMoyen),
              ),
              const SizedBox(width: AppSpacing.xsPlus),
              kpi(
                const Key('journal-kpi-articles'),
                'Articles vendus',
                '${k.articles}',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: LargeursPos.hauteurTableauJournal,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // En-tête NAVY (01/09/2026).
                  Container(
                    color: AppColors.navy,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: AppSpacing.xxs,
                    ),
                    child: Row(
                      children: [
                        for (final (i, e) in entetes.indexed)
                          Expanded(
                            flex: const [2, 1, 2, 2, 2, 2][i],
                            child: Text(
                              e.toUpperCase(),
                              textAlign: i == 4
                                  ? TextAlign.right
                                  : TextAlign.left,
                              style: entete(),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (ventes.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.lg,
                      ),
                      child: Text(
                        vide,
                        key: const Key('journal-vide'),
                        textAlign: TextAlign.center,
                        style: _t(Tailles.t13, couleur: Ardoise.c400),
                      ),
                    )
                  else
                    for (final v in ventes)
                      Container(
                        key: Key('journal-vente-${v.id}'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Ardoise.c100),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text(
                                v.referenceLocale,
                                style: _t(
                                  Tailles.t11,
                                  couleur: Ardoise.c500,
                                  famille: AppTextStyles.policeMonospace,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                _heure(v.date),
                                style: _t(Tailles.t12, couleur: Ardoise.c500),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                v.tableLibelle ?? '—',
                                style: _t(Tailles.t12, couleur: Ardoise.c500),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                v.mode?.libelle ?? 'non renseigné',
                                style: _t(Tailles.t12, couleur: Ardoise.c500),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                formaterFcfa(v.montant),
                                textAlign: TextAlign.right,
                                style: _t(
                                  Tailles.t12,
                                  poids: FontWeight.w500,
                                  couleur: Ardoise.c800,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: v.estAnnulee
                                    // `journal_annulee`, badge rouge.
                                    ? Container(
                                        key: Key('journal-annulee-${v.id}'),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AppSpacing.xs,
                                          vertical: AppSpacing.demi,
                                        ),
                                        decoration: BoxDecoration(
                                          color: PaletteMaitre.rouge50,
                                          borderRadius: BorderRadius.circular(
                                            AppRadius.rounded,
                                          ),
                                        ),
                                        child: Text(
                                          'annulée',
                                          style: _t(
                                            Tailles.t11,
                                            poids: FontWeight.w600,
                                            couleur: PaletteMaitre.rouge700,
                                          ),
                                        ),
                                      )
                                    // `journal_annuler`, lien rouge.
                                    : InkWell(
                                        key: Key('journal-annuler-${v.id}'),
                                        onTap: peutEcrire
                                            ? () => ouvrirAnnulationVente(
                                                context,
                                                v,
                                              )
                                            : null,
                                        child: Text(
                                          'annuler',
                                          style:
                                              _t(
                                                Tailles.t11,
                                                couleur: PaletteMaitre.rouge600,
                                              ).copyWith(
                                                decoration:
                                                    TextDecoration.underline,
                                              ),
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          key: const Key('journal-fermer'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer', style: TextesModaleRestaurant.bouton),
        ),
      ],
    );
  }
}

/* ====================================================================== */
/* « Annuler cette vente » (l.690-724)                                      */
/* ====================================================================== */

/// Ouvre la modale d'annulation d'une vente ; rend `true` si elle a été annulée.
///
/// ⚠ Le châssis `modale-archivage` n'est PAS employé ici, et la vue en donne la
/// raison : il ne porte aucun champ, alors que le motif est OBLIGATOIRE (RG-02,
/// le journal doit dire pourquoi).
Future<bool?> ouvrirAnnulationVente(BuildContext context, Vente vente) =>
    showDialog<bool>(
      context: context,
      barrierColor: AppColors.voileModale,
      builder: (_) => ModaleAnnulationVente(vente: vente),
    );

class ModaleAnnulationVente extends ConsumerStatefulWidget {
  const ModaleAnnulationVente({required this.vente, super.key});

  final Vente vente;

  /// `pos_pwa.comptant.annulation_titre`.
  static const String titre = 'Annuler cette vente';

  /// `annulation_message` — dit en sous-titre, comme la vue.
  static const String message =
      'Les sorties de stock correspondantes seront compensées par un mouvement inverse.';

  /// `annulation_detail`.
  static const String detail =
      'La vente reste au journal, marquée annulée : rien n’est effacé.';

  /// `annulation_motif`.
  static const String motif = 'Motif de l’annulation';

  @override
  ConsumerState<ModaleAnnulationVente> createState() =>
      _EtatModaleAnnulationVente();
}

class _EtatModaleAnnulationVente extends ConsumerState<ModaleAnnulationVente> {
  final _saisie = TextEditingController();
  String? _erreur;
  bool _envoi = false;

  @override
  void dispose() {
    _saisie.dispose();
    super.dispose();
  }

  Future<void> _annuler() async {
    final messager = ScaffoldMessenger.of(context);
    final navigateur = Navigator.of(context);
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    try {
      await annulerUneVente(ref, widget.vente.id, _saisie.text);
    } on RefusVente catch (e) {
      // Le refus se pose sous le champ (`addError('motifAnnulation', …)`).
      if (mounted) {
        setState(() {
          _envoi = false;
          _erreur = e.message;
        });
      }
      return;
    }
    navigateur.pop(true);
    messager.showSnackBar(
      SnackBar(
        content: Text(
          'Vente ${widget.vente.referenceLocale} annulée. Elle reste au journal.',
          key: const Key('annulation-vente-message'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleRestaurant(
      cle: const Key('modale-annulation-vente'),
      titre: ModaleAnnulationVente.titre,
      sousTitre: ModaleAnnulationVente.message,
      largeur: LargeursPos.modaleAnnulationVente,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            ModaleAnnulationVente.detail,
            style: _t(Tailles.t12, couleur: Ardoise.c500),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            ModaleAnnulationVente.motif,
            style: _t(
              Tailles.t13,
              poids: FontWeight.w600,
              couleur: Ardoise.c700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            key: const Key('annulation-vente-motif'),
            controller: _saisie,
            enabled: !_envoi,
            style: _t(Tailles.t13),
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              errorText: _erreur,
              errorMaxLines: 4,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('annulation-vente-renoncer'),
          onPressed: _envoi ? null : () => Navigator.of(context).pop(false),
          // `pwa.modale.annuler`.
          child: const Text('Annuler', style: TextesModaleRestaurant.bouton),
        ),
        FilledButton(
          key: const Key('annulation-vente-confirmer'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.erreur),
          onPressed: _envoi ? null : _annuler,
          // `annulation_confirmer`.
          child: const Text(
            'Annuler la vente',
            style: TextesModaleRestaurant.bouton,
          ),
        ),
      ],
    );
  }
}

/* ====================================================================== */
/* « Stock insuffisant » (l.726-742)                                        */
/* ====================================================================== */

/// Ouvre la modale de rupture ; rend `true` si l'opérateur choisit « Vendre
/// quand même », `false` ou `null` sinon — le panier reste alors intact.
Future<bool?> ouvrirModaleRupture(BuildContext context, String message) =>
    showDialog<bool>(
      context: context,
      barrierColor: AppColors.voileModale,
      builder: (_) => ModaleRupture(message: message),
    );

class ModaleRupture extends StatelessWidget {
  const ModaleRupture({required this.message, super.key});

  /// Le message de la rupture constatée (`$ruptureConstatee`).
  final String message;

  /// `pos_pwa.comptant.rupture_titre`.
  static const String titre = 'Stock insuffisant';

  /// `rupture_aide`.
  static const String aide =
      'Vendre quand même créera un stock négatif, tracé comme rupture forcée. Le panier reste intact.';

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleRestaurant(
      cle: const Key('modale-rupture'),
      titre: titre,
      largeur: LargeursPos.modaleAnnulationVente,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            key: const Key('rupture-message'),
            style: _t(Tailles.t13, couleur: Ardoise.c700),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            aide,
            key: const Key('rupture-aide'),
            style: _t(Tailles.t12, couleur: Ardoise.c500),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('rupture-annuler'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Annuler', style: TextesModaleRestaurant.bouton),
        ),
        // `rupture_confirmer`, fond « alerte » comme la vue.
        FilledButton(
          key: const Key('rupture-confirmer'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.alerte),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(
            'Vendre quand même',
            style: TextesModaleRestaurant.bouton,
          ),
        ),
      ],
    );
  }
}
