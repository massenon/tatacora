// Vue Blade maîtresse (PA-183) : pwa/pos/historique-ventes.blade.php
// (le bouton « Ticket 80 mm » du détail d'une vente, l.506-507) et
// pwa/pos/comptant.blade.php (le même bouton de la modale « Vente encaissée »,
// l.553-554) — la fenêtre qu'ils ouvrent est `pwa/pos/ticket-thermique.blade.php`.
/// Le **ticket de caisse 80 mm** d'UNE vente — troisième papier de la même vente
/// (PA-101, décision du PO du 01/09/2026, en attendant la validation de l'API
/// MECeF).
///
/// ## Ce n'est pas le ticket de la FACTURE
///
/// `TicketFacture` compose le rouleau d'une PIÈCE du registre de facturation. Ce
/// ticket-ci est celui de la VENTE, comme `ticket-thermique.blade.php` : une
/// vente peut exister sans facture, et son ticket doit alors s'imprimer quand
/// même. Mêmes lignes figées, même total, même règlement que la vente ; l'en-tête
/// vient du même objet que tous les papiers ([EnteteEtablissement]).
///
/// ## Ce que le ticket dit, et ne peut pas taire
///
///  - **le titre « TICKET DE VENTE »** et la mention qui borne sa portée :
///    « Document transactionnel unitaire. Ne vaut pas facture normalisée. » ;
///  - **ce qui s'est passé** : « Total encaissé », ou « Total porté en note de
///    chambre » — une note n'est pas de l'argent dans le tiroir ;
///  - **l'annulation**, quand la vente l'est ; **les articles sans lien au stock**,
///    quand il y en a ;
///  - **le pied MECeF** : « Certification MECeF : en attente d'inscription auprès
///    de la DGI. » — honnête aujourd'hui, jamais figé en « certifiée ».
///
/// Aucun cachet fiscal n'est inventé (`MECEF_INTEGRATION_SPEC.md` §5) : son
/// emplacement ne s'imprime pas tant que MECeF n'est pas configurée, ce qui est
/// le cas de ce poste.
///
/// ## Tout texte passe par `LigneTicket`
///
/// Comme le ticket de facture : les polices intégrées du PDF ne couvrent que
/// Latin-1, et l'apostrophe typographique disparaîtrait du papier sans un mot.
library;

import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../../../core/impression/entete_etablissement.dart';
import '../../facturation/impression/ticket_facture.dart'
    show LigneTicket, StyleLigneTicket, TicketFacture, formatRouleau80mm;
import '../domain/entities/vente.dart';

/// Un ticket de vente composé : la liste exacte des textes qui seront imprimés.
final class TicketVenteCompose {
  const TicketVenteCompose(this.lignes, {required this.vente});

  final List<LigneTicket> lignes;
  final Vente vente;

  /// Tous les textes du document — la liste sur laquelle se vérifie l'absence
  /// de caractère non imprimable.
  List<String> get textes => [
    for (final l in lignes) ...[
      if (!l.estSeparateur) l.gauche,
      if (l.droite != null) l.droite!,
    ],
  ];

  /// Le ticket en une seule chaîne — pour un aperçu, une trace ou un test.
  String get texteBrut => [
    for (final l in lignes)
      l.estSeparateur
          ? '-' * 40
          : (l.droite == null ? l.gauche : '${l.gauche}  ${l.droite}'),
  ].join('\n');

  Future<Uint8List> pdf() async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: formatRouleau80mm,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [for (final l in lignes) _rendre(l)],
        ),
      ),
    );
    return doc.save();
  }

  static pw.Widget _rendre(LigneTicket l) {
    if (l.estSeparateur) return pw.Divider(height: 4);

    final style = switch (l.style) {
      StyleLigneTicket.titre => pw.TextStyle(
        fontSize: 12,
        fontWeight: pw.FontWeight.bold,
      ),
      StyleLigneTicket.sousTitre => const pw.TextStyle(fontSize: 8),
      StyleLigneTicket.total => pw.TextStyle(
        fontSize: 11,
        fontWeight: pw.FontWeight.bold,
      ),
      StyleLigneTicket.mention => const pw.TextStyle(fontSize: 7),
      _ => const pw.TextStyle(fontSize: 9),
    };

    if (l.droite == null) return pw.Text(l.gauche, style: style);
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: pw.Text(l.gauche, style: style)),
        pw.SizedBox(width: 4),
        pw.Text(l.droite!, style: style),
      ],
    );
  }
}

/// Compose le ticket 80 mm d'une vente.
final class TicketVente {
  const TicketVente._();

  /// `pos_pwa.document.ticket_titre`.
  static const String titre = 'TICKET DE VENTE';

  /// `pos_pwa.document.ticket_mention`.
  static const String mention =
      'Document transactionnel unitaire. Ne vaut pas facture normalisée.';

  /// `pos_pwa.document.ticket_thermique_pied`.
  static const String pied =
      'Certification MECeF : en attente d’inscription auprès de la DGI.';

  static String _horodatage(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

  static TicketVenteCompose composer(
    Vente vente, {
    EnteteEtablissement entete = const EnteteEtablissement(),
    DateTime? edition,
    String? auteur,
  }) {
    final lignes = <LigneTicket>[
      LigneTicket(entete.etablissement, style: StyleLigneTicket.titre),
      LigneTicket(entete.localite, style: StyleLigneTicket.sousTitre),
      const LigneTicket.separateur(),
      LigneTicket(titre, style: StyleLigneTicket.titre),
      LigneTicket(
        'N° ${vente.referenceLocale}',
        droite: _horodatage(vente.date),
        style: StyleLigneTicket.sousTitre,
      ),
      if (edition != null)
        LigneTicket(
          'Édité le ${_horodatage(edition)}'
          '${auteur == null ? '' : ' — Auteur : $auteur'}',
          style: StyleLigneTicket.sousTitre,
        ),
      LigneTicket(
        'Poste : ${vente.pointVente ?? vente.clientNom ?? '—'}'
        '${vente.tableLibelle == null ? '' : ' · ${vente.tableLibelle}'}',
        style: StyleLigneTicket.sousTitre,
      ),
      // La mention client (texte libre du comptoir) : absente, pas de ligne.
      if (vente.clientNom != null && vente.clientNom!.trim().isNotEmpty)
        LigneTicket(
          'Client : ${vente.clientNom}',
          style: StyleLigneTicket.sousTitre,
        ),
      const LigneTicket.separateur(),
      LigneTicket('Article', droite: 'Montant', style: StyleLigneTicket.corps),
      for (final l in vente.lignes)
        LigneTicket(
          '${l.libelle} x ${l.quantite}',
          droite: TicketFacture.montant(l.montant),
          style: StyleLigneTicket.article,
        ),
      const LigneTicket.separateur(),
      // La REMISE (`pos_pwa.document.remise`) : dérivée, lignes brutes − net
      // encaissé, seulement si elle est positive.
      if (vente.remiseDeduite > 0)
        LigneTicket(
          'Remise',
          droite: '- ${TicketFacture.montant(vente.remiseDeduite)}',
          style: StyleLigneTicket.corps,
        ),
      LigneTicket(
        // Le libellé DIT ce qui s'est passé : une note de chambre n'est pas un
        // encaissement, c'est une créance réglée au départ du client.
        vente.encaisse == false
            ? 'Total porté en note de chambre'
            : 'Total encaissé',
        droite: TicketFacture.montant(vente.montant),
        style: StyleLigneTicket.total,
      ),
      LigneTicket(
        'Règlement : ${vente.mode?.libelle ?? 'non renseigné'}',
        style: StyleLigneTicket.sousTitre,
      ),
      if (vente.estAnnulee)
        LigneTicket(
          'Vente annulée'
          '${vente.motifAnnulation == null ? '' : ' — ${vente.motifAnnulation}'}'
          '. Elle reste au journal : rien n’est effacé.',
          style: StyleLigneTicket.corps,
        ),
      if (vente.aDesLignesSansImpactStock)
        LigneTicket(
          '${vente.lignesSansImpactStock.length} article(s) n’ont décrémenté '
          'aucun stock : ${vente.lignesSansImpactStock.join(', ')}. Leur lien '
          'au stock est absent.',
          style: StyleLigneTicket.corps,
        ),
      const LigneTicket.separateur(),
      LigneTicket(mention, style: StyleLigneTicket.mention),
      LigneTicket(pied, style: StyleLigneTicket.mention),
    ];

    return TicketVenteCompose(List.unmodifiable(lignes), vente: vente);
  }
}
