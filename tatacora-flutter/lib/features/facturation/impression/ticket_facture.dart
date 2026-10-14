/// Composition du ticket **au format rouleau 80 mm**.
///
/// ## Le défaut que ce module existe pour rendre impossible
///
/// Constaté en D0.6 : les polices intégrées au format PDF couvrent **Latin-1**,
/// pas l'Unicode. Les accents passent — `GÎTE`, `NOËL`, `braisé` sortent
/// corrects — mais le tiret cadratin `—` et l'**apostrophe typographique `’`**
/// **disparaissent sans erreur ni message**. « l’addition » sortirait
/// « laddition », et personne ne saurait dire d'où vient la faute.
///
/// `core/impression/texte_ticket.dart` normalise ; ce module garantit que
/// **rien ne contourne la normalisation**.
///
/// ## Pourquoi le ticket est un OBJET avant d'être un PDF
///
/// [TicketCompose] porte la liste des textes **déjà normalisés**, et
/// [TicketCompose.pdf] ne rend rien d'autre que ces textes-là. Le garde-fou
/// s'applique donc au **document effectivement composé**, et non à un
/// échantillon écrit à côté dans un test — c'est la différence entre vérifier
/// et espérer.
///
/// C'est la leçon de D0.6, où une assertion « les accents survivent » ne
/// vérifiait que des octets non nuls et passait au vert en masquant le défaut
/// qu'elle prétendait couvrir.
///
/// ## Ce que ce module ne prouve toujours pas
///
/// Ni la **largeur réelle du papier**, ni le **jeu de caractères du pilote**,
/// ni la **lisibilité**. Cela demande la machine du comptoir, et aucun test ne
/// peut le rapporter.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/impression/entete_etablissement.dart';
import '../../../core/impression/texte_ticket.dart';
import '../domain/certification_mecef.dart';
import '../domain/entities/piece_facturation.dart';

/// Format d'un rouleau thermique courant : 80 mm de large, hauteur libre.
///
/// C'est ce format qui fait la différence avec une page A4, et c'est lui qu'il
/// faut composer — un ticket composé en A4 sort tronqué sur la moitié droite,
/// ou minuscule, selon le pilote.
const PdfPageFormat formatRouleau80mm = PdfPageFormat(
  80 * PdfPageFormat.mm,
  double.infinity,
  marginAll: 4 * PdfPageFormat.mm,
);

/// Rôle d'une ligne du ticket — commande sa taille et sa graisse.
enum StyleLigneTicket {
  titre,
  sousTitre,
  corps,
  article,
  total,
  mention,
  filigrane,
  separateur,
}

/// Une ligne du ticket, **déjà normalisée**.
///
/// Le constructeur passe systématiquement par [texteTicket] : il n'existe aucun
/// chemin permettant de poser un texte brut sur un ticket. C'est ce qui rend le
/// garde-fou structurel plutôt que déclaratif.
final class LigneTicket {
  LigneTicket(
    String gauche, {
    String? droite,
    this.style = StyleLigneTicket.corps,
  }) : gauche = texteTicket(gauche),
       droite = droite == null ? null : texteTicket(droite);

  /// Le séparateur horizontal — aucune chaîne, donc rien à normaliser.
  const LigneTicket.separateur()
    : gauche = '',
      droite = null,
      style = StyleLigneTicket.separateur;

  final String gauche;
  final String? droite;
  final StyleLigneTicket style;

  bool get estSeparateur => style == StyleLigneTicket.separateur;
}

// L'en-tête a quitté ce fichier en D4 : la facture A4 doit porter la MÊME
// identité d'établissement que le rouleau, et deux jeux de valeurs auraient
// divergé — c'est la non-conformité n°1 de `RESPECT_TABLEAU_RAPPORT.md` §4.
// Elle vit désormais dans `core/impression/entete_etablissement.dart`, point
// de composition unique des deux papiers.

/// Un ticket composé : la liste exacte des textes qui seront imprimés.
final class TicketCompose {
  const TicketCompose(this.lignes, {required this.piece});

  final List<LigneTicket> lignes;
  final PieceFacturation piece;

  /// **Tous** les textes du document, gauche et droite confondus.
  ///
  /// C'est sur cette liste que se vérifie l'absence de caractère non
  /// imprimable : elle est, par construction, exactement ce que [pdf] rend.
  List<String> get textes => [
    for (final l in lignes) ...[
      if (!l.estSeparateur) l.gauche,
      if (l.droite != null) l.droite!,
    ],
  ];

  /// Le ticket en une seule chaîne — pratique pour un test, une trace ou un
  /// aperçu à l'écran.
  String get texteBrut => [
    for (final l in lignes)
      l.estSeparateur
          ? '-' * 40
          : (l.droite == null ? l.gauche : '${l.gauche}  ${l.droite}'),
  ].join('\n');

  /// Rend le PDF, au format rouleau 80 mm.
  ///
  /// Aucune chaîne n'est introduite ici : tout vient de [lignes], déjà
  /// normalisées. Ajouter un `pw.Text('…')` littéral dans cette méthode
  /// contournerait le garde-fou — c'est la seule faute à surveiller en revue
  /// sur ce fichier.
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
      StyleLigneTicket.corps => const pw.TextStyle(fontSize: 9),
      StyleLigneTicket.article => const pw.TextStyle(fontSize: 9),
      StyleLigneTicket.total => pw.TextStyle(
        fontSize: 11,
        fontWeight: pw.FontWeight.bold,
      ),
      StyleLigneTicket.mention => const pw.TextStyle(fontSize: 7),
      StyleLigneTicket.filigrane => pw.TextStyle(
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
      ),
      StyleLigneTicket.separateur => const pw.TextStyle(fontSize: 9),
    };

    final contenu = l.droite == null
        ? pw.Text(l.gauche, style: style)
        : pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: pw.Text(l.gauche, style: style)),
              pw.SizedBox(width: 4),
              pw.Text(l.droite!, style: style),
            ],
          );

    if (l.style != StyleLigneTicket.filigrane) return contenu;

    // Le filigrane est rendu en **cadre**, pas en texte tourné derrière la
    // page. Une thermique de comptoir imprime en noir sur blanc, sans
    // niveaux de gris utilisables : un filigrane diagonal y sortirait soit
    // illisible, soit par-dessus les montants. Un cadre reste visible sur du
    // papier de caisse, ce qui est le seul critère qui compte ici.
    return pw.Container(
      margin: const pw.EdgeInsets.symmetric(vertical: 3),
      padding: const pw.EdgeInsets.all(3),
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
      child: pw.Center(child: contenu),
    );
  }
}

/// Compose le ticket d'une pièce de facturation.
final class TicketFacture {
  const TicketFacture._();

  /// Montant en francs CFA, séparé par milliers.
  ///
  /// Le séparateur est une **espace ordinaire**, pas une espace fine insécable
  /// (U+202F) : celle-ci est hors Latin-1 et serait supprimée en silence par
  /// les polices intégrées du PDF. C'est le même défaut que le tiret cadratin,
  /// sur un caractère qu'on ne pense jamais à vérifier parce qu'il est
  /// invisible.
  static String montant(int valeur) {
    final negatif = valeur < 0;
    final chiffres = valeur.abs().toString();
    final tampon = StringBuffer();
    for (var i = 0; i < chiffres.length; i++) {
      if (i > 0 && (chiffres.length - i) % 3 == 0) tampon.write(' ');
      tampon.write(chiffres[i]);
    }
    return '${negatif ? '-' : ''}$tampon FCFA';
  }

  static String _horodatage(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

  /// Compose le ticket.
  ///
  /// ## Ce que le ticket dit toujours, et qu'il ne peut pas taire
  ///
  ///  - **la mention MECeF réelle** — `« MECeF — non certifiée, démonstration »`
  ///    tant qu'aucun vrai numéro n'est porté. Elle se dérive de la pièce, pas
  ///    d'un drapeau (PA-61) ;
  ///  - **le filigrane « DOCUMENT DE DÉMONSTRATION »**, obligation ouverte du
  ///    dépôt, sur toute pièce non certifiée. Il disparaîtra de lui-même le
  ///    jour où une certification réelle aura lieu — parce qu'il est dérivé,
  ///    et non posé à la main ;
  ///  - **la nature de la pièce** : un avoir s'annonce comme tel, avec le
  ///    numéro de la facture qu'il neutralise. Un document à montant négatif
  ///    qui ne dirait pas ce qu'il est serait pris pour une facture fausse.
  static TicketCompose composer(
    PieceFacturation piece, {
    EnteteEtablissement entete = const EnteteEtablissement(),
  }) {
    final lignes = <LigneTicket>[
      LigneTicket(entete.etablissement, style: StyleLigneTicket.titre),
      LigneTicket(entete.localite, style: StyleLigneTicket.sousTitre),
      const LigneTicket.separateur(),

      LigneTicket(
        piece.estAvoir ? 'AVOIR ${piece.numero}' : piece.numero,
        style: StyleLigneTicket.titre,
      ),
      if (piece.estAvoir)
        LigneTicket(
          'Neutralise la facture ${piece.avoirDe}',
          style: StyleLigneTicket.sousTitre,
        ),
      if (piece.estAvoir && piece.motifAvoir != null)
        LigneTicket(
          'Motif : ${piece.motifAvoir}',
          style: StyleLigneTicket.sousTitre,
        ),

      LigneTicket(
        _horodatage(piece.dateEmission),
        droite: piece.pointVente ?? piece.origine.libelle,
        style: StyleLigneTicket.sousTitre,
      ),
      LigneTicket(piece.clientNom, style: StyleLigneTicket.corps),

      // Une facture annulée reste imprimable : c'est même le seul moyen de
      // justifier l'avoir qui la neutralise. Elle le dit, en revanche.
      if (piece.estAnnulee)
        LigneTicket(
          'ANNULÉE — ${piece.motifAnnulation ?? 'motif non renseigné'}',
          style: StyleLigneTicket.corps,
        ),

      const LigneTicket.separateur(),

      for (final l in piece.lignes)
        LigneTicket(
          '${l.libelle} x ${l.quantite}',
          droite: montant(l.montant),
          style: StyleLigneTicket.article,
        ),

      const LigneTicket.separateur(),
      LigneTicket(
        'TOTAL',
        droite: montant(piece.montantTotal),
        style: StyleLigneTicket.total,
      ),

      if (piece.modePaiement != null)
        LigneTicket(
          'Règlement : ${piece.modePaiement}',
          style: StyleLigneTicket.sousTitre,
        ),

      const LigneTicket.separateur(),

      // Dérivée de la pièce, jamais d'une configuration : c'est PA-61.
      LigneTicket(piece.libelleCertification, style: StyleLigneTicket.mention),

      if (!piece.estCertifiee)
        LigneTicket(
          CertificationMecef.filigraneDemonstration,
          style: StyleLigneTicket.filigrane,
        ),
    ];

    return TicketCompose(List.unmodifiable(lignes), piece: piece);
  }
}
