/// **La facture sur papier A4 — le second papier de la même pièce.**
///
/// ## La question du Product Owner, et la réponse du dépôt
///
/// *« Ticket sur papier ou facture sur papier A4 ? »* — **les deux, et ce sont
/// deux documents différents.** `05_MODULE_SPECIFICATIONS.md` §M14 sépare les
/// **documents transactionnels unitaires** (ticket de vente, contrat de
/// location) des **états périodiques agrégés** du Hub M14. La facture A4 est du
/// premier type : elle s'édite depuis l'écran du module d'origine, jamais
/// depuis le Hub — mais elle porte *« malgré tout l'en-tête normalisée unique
/// du même `ReportHeaderService` (RG-19 s'applique aux deux catégories sans
/// exception) »*.
///
/// ## Ce module est un RENDU, et rien d'autre
///
/// Aucune table, aucune migration, **aucune séquence de numéros**. Ticket
/// 80 mm et facture A4 sont la **même pièce** ([PieceFacturation]) : le
/// registre est unique et la séquence l'est aussi — propriété n°3 du registre
/// (PA-99). Ce fichier ne fait que choisir ce qui s'imprime, et où.
///
/// Le domaine ne connaît pas le papier : rien de `domain/` n'a été touché pour
/// livrer ce document.
///
/// ## ⚠ LE PIÈGE PRINCIPAL — aucun cachet fiscal n'est inventé ici
///
/// La facture normalisée MECeF porte un *« cachet fiscal électronique,
/// matérialisé par un QR code »* (`MECEF_INTEGRATION_SPEC.md` §1). Mais le §5
/// du même document est catégorique : le **format exact du cachet et du QR
/// n'est pas public**, il est communiqué après approbation du SFE, et il *« ne
/// doit donc pas être complété par une supposition »* — contrairement au
/// protocole de synchronisation, ce contrat est **imposé par un tiers**.
///
/// Ce module n'émet donc **aucun code-barres, aucun QR, aucun cachet**. Il
/// réserve et **nomme** l'emplacement : un cadre qui dit en clair que le cachet
/// sera apposé après certification (PA-17). Un QR d'apparence officielle sur un
/// document remis à un client serait **PA-61 sous forme physique** — un objet
/// qui affirme une certification qui n'a pas eu lieu, cette fois sur du papier
/// qu'on ne rattrape pas.
///
/// `facture_a4_test.dart` interdit structurellement l'ajout d'un code-barres
/// dans ce fichier : c'est une garde à liste fermée, pas une intention.
///
/// ## Les caractères : normalisation, PAS de police embarquée
///
/// Décision prise et assumée. Les polices intégrées du PDF couvrent Latin-1 :
/// le tiret cadratin et l'apostrophe typographique **disparaissent en
/// silence** (voir `core/impression/texte_ticket.dart`). L'A4 pourrait
/// justifier une police Unicode embarquée là où la thermique ne le justifiait
/// pas — trois raisons de ne pas le faire, dans cet ordre :
///
///  1. **le ticket et la facture doivent dire la même chose.** Deux politiques
///     de caractères sur la même pièce donneraient « Natitingou — Bénin » sur
///     l'A4 et « Natitingou - Bénin » sur le rouleau ; on éprouverait l'un et
///     on livrerait l'autre ;
///  2. **aucune police ne se télécharge à l'exécution** — le poste du Gîte
///     encaisse hors connexion, et ce serait le seul endroit du logiciel qui
///     exigerait Internet. Embarquer un fichier de police resterait acceptable,
///     le récupérer au démarrage ne l'est pas ; aucun fichier de police n'est
///     présent au dépôt, et en télécharger un pour le livrer contredirait la
///     règle qu'il prétend respecter ;
///  3. la normalisation existe, elle est éprouvée, et elle n'interdit rien pour
///     plus tard.
///
/// Le garde-fou porte, comme sur le ticket, sur le **document effectivement
/// composé** ([FactureA4Composee.textes]) et non sur un échantillon écrit à
/// côté.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/impression/entete_etablissement.dart';
import '../../../core/impression/texte_ticket.dart';
import '../../pos/domain/place_hebergement.dart';
import '../domain/certification_mecef.dart';
import '../domain/entities/piece_facturation.dart';
import 'ticket_facture.dart' show TicketFacture;

/// Page A4 portrait, marges de 18 mm.
///
/// C'est ce qui distingue ce document du rouleau : `formatRouleau80mm` a une
/// hauteur infinie et 80 mm de large, cette page-ci a deux dimensions finies et
/// des marges. Composer l'un au format de l'autre sort tronqué ou minuscule.
const PdfPageFormat formatFactureA4 = PdfPageFormat(
  21.0 * PdfPageFormat.cm,
  29.7 * PdfPageFormat.cm,
  marginAll: 1.8 * PdfPageFormat.cm,
);

/// L'auteur de l'édition — **jamais une valeur générique**.
///
/// `RESPECT_TABLEAU_RAPPORT.md` §4 recense « Auteur affiché = "Administrateur"
/// par défaut » comme non-conformité fréquente, née d'une *« valeur de test
/// laissée en dur, jamais reliée à la session RBAC réelle »*. Il n'existe donc
/// **aucune valeur par défaut** ici : le champ est requis, et la présentation
/// le dérive de la session réellement connectée. Sans session, il n'y a pas
/// d'édition — plutôt qu'une édition signée par personne.
final class AuteurEdition {
  const AuteurEdition({required this.nom, required this.role});

  final String nom;
  final String role;

  String get libelle => '$nom — $role';
}

/// Une facture A4 **composée** : exactement les textes qui seront imprimés.
///
/// Même principe que `TicketCompose` : le document est un **objet** avant
/// d'être un PDF, [pdf] ne rend rien d'autre que ce que porte cet objet, et
/// [textes] est donc, par construction, ce que le papier recevra.
final class FactureA4Composee {
  const FactureA4Composee({
    required this.piece,
    required this.entete,
    required this.auteur,
    required this.dateEdition,
    required this.lignesEntete,
    required this.titre,
    required this.identification,
    required this.colonnes,
    required this.lignesTableau,
    required this.recapitulatif,
    required this.libelleTotal,
    required this.montantTotal,
    required this.cachetFiscal,
    required this.mentions,
    required this.piedDePage,
    required this.gabaritPagination,
    this.filigrane,
  });

  final PieceFacturation piece;
  final EnteteEtablissement entete;
  final AuteurEdition auteur;
  final DateTime dateEdition;

  /// L'en-tête institutionnelle, telle que [EnteteEtablissement] la compose.
  final List<String> lignesEntete;

  /// « FACTURE F-2026-00042 » ou « AVOIR … ».
  final String titre;

  /// Le bloc d'identification de la pièce, libellé puis valeur.
  final List<(String, String)> identification;

  final List<String> colonnes;
  final List<List<String>> lignesTableau;

  /// ⚠ **Q3** — le récapitulatif nomme séparément ce qui compose le total.
  final List<(String, String)> recapitulatif;

  final String libelleTotal;
  final String montantTotal;

  /// L'emplacement réservé du cachet fiscal — du **texte**, jamais un code.
  final List<String> cachetFiscal;

  final List<String> mentions;
  final List<String> piedDePage;

  /// Gabarit de pagination : les chiffres y sont substitués au rendu.
  ///
  /// Il figure dans [textes] pour que la pagination, composée au moment du
  /// rendu et non ici, reste couverte par le garde-fou des caractères.
  final String gabaritPagination;

  /// `null` dès qu'une certification réelle a lieu — **dérivé, jamais posé**.
  final String? filigrane;

  /// **Tous** les textes du document.
  List<String> get textes => [
    ...lignesEntete,
    titre,
    for (final (libelle, valeur) in identification) ...[libelle, valeur],
    ...colonnes,
    for (final ligne in lignesTableau) ...ligne,
    for (final (libelle, valeur) in recapitulatif) ...[libelle, valeur],
    libelleTotal,
    montantTotal,
    ...cachetFiscal,
    ...mentions,
    ...piedDePage,
    gabaritPagination,
    ?filigrane,
  ];

  /// Le document en une seule chaîne — pour un test, une trace, un aperçu.
  String get texteBrut => textes.join('\n');

  String _pagination(int page, int total) => gabaritPagination
      .replaceAll('{page}', '$page')
      .replaceAll('{total}', '$total');

  /// Rend le PDF, au format A4.
  ///
  /// Aucune chaîne n'est introduite ici : tout vient des champs déjà
  /// normalisés. Ajouter un `pw.Text('…')` littéral dans cette méthode
  /// contournerait le garde-fou — c'est la seule faute à surveiller en revue
  /// sur ce fichier, avec l'ajout d'un code-barres.
  Future<Uint8List> pdf() async {
    final doc = pw.Document();
    final logo = entete.logo;

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: formatFactureA4,
          buildBackground: (context) => _fondFiligrane(),
        ),
        header: (context) => _entete(logo),
        footer: (context) =>
            _pied(_pagination(context.pageNumber, context.pagesCount)),
        build: (context) => [
          _titre(),
          pw.SizedBox(height: 10),
          _identification(),
          pw.SizedBox(height: 14),
          _tableau(),
          pw.SizedBox(height: 10),
          _recapitulatif(),
          pw.SizedBox(height: 16),
          _cachetEtMentions(),
        ],
      ),
    );
    return doc.save();
  }

  /* ================================================================== */
  /* Rendu                                                               */
  /* ================================================================== */

  /// Le filigrane, en diagonale et en gris clair.
  ///
  /// Contrairement au rouleau — où un filigrane diagonal sortirait illisible
  /// ou par-dessus les montants sur une thermique en noir pur — une page A4
  /// part sur une laser ou une jet d'encre, qui rendent les gris. Le cadre
  /// reste tout de même posé en tête de page (voir [_titre]) : une photocopie
  /// en noir et blanc peut perdre un gris clair, pas un cadre.
  pw.Widget _fondFiligrane() {
    final texte = filigrane;
    if (texte == null) return pw.SizedBox();
    return pw.Center(
      child: pw.Transform.rotate(
        angle: 0.7,
        child: pw.Text(
          texte,
          style: pw.TextStyle(
            fontSize: 46,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.grey300,
          ),
        ),
      ),
    );
  }

  pw.Widget _entete(Uint8List? logo) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (logo != null) ...[
            pw.SizedBox(
              width: 48,
              height: 48,
              child: pw.Image(pw.MemoryImage(logo), fit: pw.BoxFit.contain),
            ),
            pw.SizedBox(width: 12),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < lignesEntete.length; i++)
                  pw.Text(
                    lignesEntete[i],
                    style: i == 0
                        ? pw.TextStyle(
                            fontSize: 15,
                            fontWeight: pw.FontWeight.bold,
                          )
                        : const pw.TextStyle(fontSize: 8),
                  ),
              ],
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Divider(height: 1, thickness: 1),
      pw.SizedBox(height: 10),
    ],
  );

  pw.Widget _titre() => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Text(
        titre,
        style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold),
      ),
      if (filigrane != null) ...[
        pw.SizedBox(height: 6),
        pw.Container(
          padding: const pw.EdgeInsets.all(5),
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
          child: pw.Center(
            child: pw.Text(
              filigrane!,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ),
      ],
    ],
  );

  pw.Widget _identification() => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      for (final (libelle, valeur) in identification)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 120,
                child: pw.Text(
                  libelle,
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey700,
                  ),
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  valeur,
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );

  pw.Widget _tableau() => pw.Table(
    border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey600),
    columnWidths: const {
      0: pw.FlexColumnWidth(5),
      1: pw.FlexColumnWidth(2),
      2: pw.FlexColumnWidth(2),
      3: pw.FlexColumnWidth(1.2),
      4: pw.FlexColumnWidth(2.4),
    },
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [for (final c in colonnes) _cellule(c, gras: true)],
      ),
      for (final ligne in lignesTableau)
        pw.TableRow(
          children: [
            for (var i = 0; i < ligne.length; i++)
              _cellule(ligne[i], aDroite: i >= 2),
          ],
        ),
    ],
  );

  static pw.Widget _cellule(
    String texte, {
    bool gras = false,
    bool aDroite = false,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    child: pw.Text(
      texte,
      textAlign: aDroite ? pw.TextAlign.right : pw.TextAlign.left,
      style: pw.TextStyle(
        fontSize: 9,
        fontWeight: gras ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );

  pw.Widget _recapitulatif() => pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.end,
    children: [
      pw.SizedBox(
        width: 260,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            for (final (libelle, valeur) in recapitulatif)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(libelle, style: const pw.TextStyle(fontSize: 10)),
                    pw.Text(valeur, style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ),
            pw.Divider(height: 6, thickness: 1),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  libelleTotal,
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  montantTotal,
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );

  /// L'emplacement du cachet fiscal — **réservé et nommé**, jamais rempli.
  pw.Widget _cachetEtMentions() => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Container(
        width: 200,
        height: 112,
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(width: 1, color: PdfColors.grey600),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < cachetFiscal.length; i++)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 2),
                child: pw.Text(
                  cachetFiscal[i],
                  style: pw.TextStyle(
                    fontSize: i == 0 ? 9 : 7,
                    fontWeight: i == 0
                        ? pw.FontWeight.bold
                        : pw.FontWeight.normal,
                    color: i == 0 ? PdfColors.black : PdfColors.grey700,
                  ),
                ),
              ),
          ],
        ),
      ),
      pw.SizedBox(width: 12),
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (final m in mentions)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Text(
                  m,
                  style: const pw.TextStyle(
                    fontSize: 7.5,
                    color: PdfColors.grey700,
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );

  pw.Widget _pied(String pagination) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Divider(height: 1, thickness: 0.5),
      pw.SizedBox(height: 4),
      for (final ligne in piedDePage)
        pw.Text(
          ligne,
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
        ),
      pw.SizedBox(height: 2),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          pagination,
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
        ),
      ),
    ],
  );
}

/// Compose la facture A4 d'une pièce de facturation.
final class FactureA4 {
  const FactureA4._();

  /// Ce que la facture A4 dit toujours, et qu'elle ne peut pas taire :
  ///
  ///  - **l'en-tête officielle** de `DIRECTIVE_EXPORT_PDF.md`, composée par le
  ///    point unique et non recopiée ici ;
  ///  - **l'auteur réel** de l'édition — jamais « Administrateur » par défaut ;
  ///  - **ce qui compose le total**, hébergement et consommations nommés
  ///    séparément (⚠ Q3) ;
  ///  - **la mention MECeF réelle**, dérivée de la pièce et non d'un drapeau ;
  ///  - **le filigrane « DOCUMENT DE DÉMONSTRATION »** tant qu'aucune
  ///    certification réelle n'a eu lieu — il disparaîtra de lui-même, sans que
  ///    personne modifie une chaîne ;
  ///  - **l'emplacement réservé du cachet fiscal**, vide et nommé comme tel.
  static FactureA4Composee composer(
    PieceFacturation piece, {
    required AuteurEdition auteur,
    required DateTime dateEdition,
    EnteteEtablissement entete = const EnteteEtablissement(),
  }) {
    final estAvoir = piece.estAvoir;

    return FactureA4Composee(
      piece: piece,
      entete: entete,
      auteur: auteur,
      dateEdition: dateEdition,
      lignesEntete: entete.lignesA4,
      titre: _t(estAvoir ? 'AVOIR ${piece.numero}' : 'FACTURE ${piece.numero}'),
      identification: [
        for (final (libelle, valeur) in <(String, String?)>[
          ('Date d\'émission', _horodatage(piece.dateEmission)),
          ('Client', piece.clientNom),
          if (estAvoir) ('Neutralise la facture', piece.avoirDe),
          if (estAvoir) ('Motif de l\'avoir', piece.motifAvoir),
          if (piece.estAnnulee)
            ('Pièce annulée', piece.motifAnnulation ?? 'motif non renseigné'),
          ('Origine', piece.origine.libelle),
          if (piece.pointVente != null) ('Point de vente', piece.pointVente),
          if (piece.modePaiement != null) ('Règlement', piece.modePaiement),
          if (piece.reservationId != null) ('Réservation', piece.reservationId),
        ])
          if (valeur != null) (_t(libelle), _t(valeur)),
      ],
      colonnes: [
        _t('Désignation'),
        _t('Activité'),
        _t('Prix unitaire'),
        _t('Qté'),
        _t('Montant'),
      ],
      lignesTableau: [
        for (final l in piece.lignes)
          [
            _t(l.libelle),
            _t(l.module.libelle),
            _t(TicketFacture.montant(l.prixUnitaire)),
            _t('${l.quantite}'),
            _t(TicketFacture.montant(l.montant)),
          ],
      ],
      recapitulatif: [
        for (final (libelle, valeur) in _composition(piece))
          (_t(libelle), _t(TicketFacture.montant(valeur))),
      ],
      libelleTotal: _t(estAvoir ? 'TOTAL DE L\'AVOIR' : 'TOTAL À PAYER'),
      montantTotal: _t(TicketFacture.montant(piece.montantTotal)),
      cachetFiscal: [
        _t('Cachet fiscal MECeF'),
        _t('Emplacement réservé — aucun cachet n\'est apposé.'),
        _t(
          'Le cachet et son QR code seront apposés après certification par la '
          // Code interne (PA-17) retiré du papier, 14/10/2026.
          'DGI. L\'inscription n\'est pas effectuée.',
        ),
        _t(
          'Le format exact du cachet n\'est pas public : il est communiqué à '
          'l\'entreprise après approbation de son système de facturation. '
          'Rien n\'en est supposé ici.',
        ),
      ],
      mentions: [
        // Dérivée de la pièce, jamais d'une configuration : c'est PA-61.
        _t(piece.libelleCertification),
        _t(
          'Montants en francs CFA (XOF). Ce document ne porte aucune '
          // 09/10/2026 : « aucun taux de TVA n'est configuré » devenait faux
          // dès qu'un taux se saisit dans Paramètres, alors qu'aucun module ne
          // l'applique encore. La phrase dit désormais ce qui reste vrai dans
          // les deux cas.
          'ventilation HT/TVA : ce poste ne calcule aucune TVA, et un '
          'montant de taxe non vérifié sur une pièce immuable serait une '
          // Code interne (PA-62) retiré du papier, 14/10/2026.
          'affirmation fiscale que rien ne justifie.',
        ),
        _t(
          'La correction d\'une facture passe exclusivement par un avoir : '
          'aucune pièce n\'est supprimée du registre.',
        ),
      ],
      piedDePage: [
        _t(
          'TATACORA AFRIQUE — Gîte Chez Noël · Projet PAEB · '
          'Cabinet FAGUEZ SARL',
        ),
        _t('Édité le ${_horodatage(dateEdition)} par ${auteur.libelle}'),
      ],
      gabaritPagination: _t('Page {page} / {total}'),
      // Dérivé de la pièce : le jour d'une certification réelle il disparaît
      // sans que personne modifie une chaîne (PA-61).
      filigrane: piece.estCertifiee
          ? null
          : _t(CertificationMecef.filigraneDemonstration),
    );
  }

  /// ⚠ **Q3 — hébergement et consommations restent NOMMÉS séparément.**
  ///
  /// « Votre chambre, vos consommations » est une phrase qu'on prononce au
  /// comptoir ; « 174 500 F » n'en est pas une. C'est aussi la seule forme qui
  /// reste juste quelle que soit la réponse à Q3.
  ///
  /// ## Pourquoi la valeur, et pas `CompositionFactureSejour.composer`
  ///
  /// La fabrique **lit Q3** et refuse sous l'autre branche
  /// (`PlaceHebergement.ligneDePanier`). L'appeler ici ferait échouer
  /// l'**impression** d'une pièce déjà émise le jour de l'arbitrage, et
  /// surtout ferait de ce fichier un second endroit où Q3 est lue — alors que
  /// `place_hebergement.dart` doit rester le seul.
  ///
  /// Ce module lit une pièce **déjà figée** : ses lignes sont la source, il n'y
  /// a aucune composition à décider. Le type nommé est réutilisé pour ce qu'il
  /// est — deux montants qui portent un nom.
  static List<(String, int)> _composition(PieceFacturation piece) {
    final hebergement = piece.ventilation[ModuleFacturable.m1Hebergement];
    if (hebergement != null) {
      final vue = CompositionFactureSejour(
        hebergement: hebergement,
        consommations: piece.montantTotal - hebergement,
      );
      return [
        ('Hébergement', vue.hebergement),
        ('Consommations', vue.consommations),
      ];
    }

    // Pas de nuitée : la ventilation par activité dit tout de même d'où vient
    // l'argent, plutôt qu'un total seul.
    return [
      for (final e in piece.ventilation.entries) (e.key.libelle, e.value),
    ];
  }

  static String _horodatage(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year} à '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

  /// Le seul chemin par lequel un texte entre dans le document.
  static String _t(String source) => texteTicket(source);
}
