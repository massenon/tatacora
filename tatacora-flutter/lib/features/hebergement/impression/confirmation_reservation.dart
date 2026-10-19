import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/format/formats.dart';
import '../../../core/impression/entete_etablissement.dart';
import '../../../core/impression/texte_ticket.dart';
import '../domain/entities/reservation.dart';

/// Le document remis au client **au moment où la réservation est prise**.
///
/// ## ⚠ CE DOCUMENT N'EST PAS UNE FACTURE, et son titre le dit
///
/// C'est l'écart le plus important de ce module, et il est délibéré.
///
/// Le maître (`reservations-services.js`, `imprimerFacture`) appelle ce papier
/// « Facture » et sa modale propose « Imprimer la facture ». Mais le document
/// qu'il produit **n'a pas de numéro**, pas d'IFU, pas de RCCM, aucun cachet —
/// et son propre pied de page l'admet : *« Document généré automatiquement,
/// prototype de démonstration »*.
///
/// Au Bénin, une facture est une **facture normalisée MECeF** : elle porte un
/// numéro d'une séquence continue et un cachet fiscal électronique
/// (`MECEF_INTEGRATION_SPEC.md` §1). Imprimer « FACTURE » en tête d'un papier
/// qui n'a rien de tout cela, et le remettre à un client, c'est produire un
/// faux document fiscal — la version papier de PA-61, celle qu'on ne rattrape
/// pas. Le dépôt refuse déjà d'imprimer un IFU d'exemple pour la même raison.
///
/// Le document est donc titré **« CONFIRMATION DE RÉSERVATION »**, et il porte
/// une mention explicite : la facture normalisée est émise à l'encaissement.
/// La modale, elle, garde les mots du maître — c'est l'écran que le client a
/// validé des yeux, et « imprimer la facture » y désigne ce geste-ci.
///
/// ## Aucun numéro n'est ALLOUÉ ici
///
/// `FactureDao.numeroSuivant()` **alloue et persiste** — ce n'est jamais une
/// lecture (PA-101). Ce module ne l'appelle pas, ne touche pas au registre, et
/// n'écrit rien : réserver un numéro pour un document non fiscal brûlerait des
/// numéros de la séquence continue, et le trou serait à justifier.
///
/// @see prototype_v2/pages/reservations-services.js — `imprimerFacture()`
/// @see PA-101 — ticket et facture sont deux papiers de la MÊME pièce ; ce
///      document n'est ni l'un ni l'autre.
final class ConfirmationReservation {
  const ConfirmationReservation({
    required this.reservation,
    required this.emiseLe,
    this.entete = const EnteteEtablissement(),
  });

  static const String titre = 'CONFIRMATION DE RÉSERVATION';

  /// La mention qui empêche ce papier d'être pris pour une facture.
  ///
  /// Elle est **au corps du document**, pas en pied de page en petits
  /// caractères : c'est la première chose qu'un client regarde s'il cherche
  /// une facture, et un pied de page se lit rarement.
  static const String mention =
      'Ce document confirme une réservation. Il ne vaut pas facture : la '
      'facture normalisée est émise à l’encaissement.';

  static const List<String> entetes = [
    'Service',
    'Désignation',
    'Qté',
    'Prix unitaire',
    'Sous-total',
  ];

  final Reservation reservation;

  /// Injectée, jamais lue de l'horloge à la composition : un document testé
  /// sur `DateTime.now()` n'est reproductible aucun deux jours de suite.
  final DateTime emiseLe;

  final EnteteEtablissement entete;

  /// Le même document sous l'en-tête lu des paramètres au moment d'éditer
  /// (`lireEnteteEtablissementProvider`).
  ConfirmationReservation avecEntete(EnteteEtablissement autre) =>
      ConfirmationReservation(
        reservation: reservation,
        emiseLe: emiseLe,
        entete: autre,
      );

  /// Les lignes du tableau, telles qu'elles s'impriment.
  List<List<String>> get lignes => [
    for (final l in reservation.lignes)
      [
        l.service.nom,
        l.libelle,
        '${l.quantite}',
        formaterFcfa(l.prixUnitaire),
        formaterFcfa(l.sousTotal),
      ],
  ];

  /// Le récapitulatif — **les cinq lignes du maître**, dans son ordre.
  ///
  /// Le calcul vient de l'entité, jamais refait ici : une seconde formule
  /// finirait par diverger, et c'est le papier remis au client qui
  /// l'emporterait sur l'écran.
  List<(String, String, bool)> get recapitulatif {
    final r = reservation.recapitulatif;
    return [
      ('Sous-total', formaterFcfa(r.sousTotal), false),
      ('Remise', '- ${formaterFcfa(r.montantRemise)}', false),
      ('Total à payer', formaterFcfa(r.total), true),
      ('Acompte versé', '- ${formaterFcfa(r.acompte)}', false),
      ('Reste à payer', formaterFcfa(r.reste), true),
    ];
  }

  /// Les quatre lignes d'identification du maître.
  List<String> get identification => [
    'Client : ${reservation.clientNom}'
        '${reservation.typeClient == null ? '' : ' (${reservation.typeClient!.libelle})'}',
    'Période : ${formaterDate(reservation.periode.arrivee)} → '
        '${formaterDate(reservation.periode.depart)} '
        '(${reservation.nuits} nuit${reservation.nuits > 1 ? 's' : ''})',
    'Canal : ${reservation.canal?.libelle ?? '—'}   |   '
        'Mode de paiement : ${reservation.modePaiement?.libelle ?? '—'}',
    'Référence : ${reservation.reference}   |   '
        'Émis le : ${formaterDate(emiseLe)}',
  ];

  /// Normalisation Latin-1 — les polices intégrées du PDF ne vont pas plus
  /// loin, et un caractère non couvert disparaît du papier sans erreur.
  static String _t(String source) => texteTicket(source);

  Future<Uint8List> pdf() async {
    final doc = pw.Document();
    final logo = entete.logo;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => _entete(logo),
        build: (context) => [
          _identification(),
          pw.SizedBox(height: 14),
          _tableau(),
          pw.SizedBox(height: 12),
          _recapitulatif(),
          pw.SizedBox(height: 18),
          _mention(),
        ],
      ),
    );
    return doc.save();
  }

  pw.Widget _entete(Uint8List? logo) => pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 10),
    margin: const pw.EdgeInsets.only(bottom: 12),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(width: 2)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logo != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(right: 12),
            child: pw.Image(pw.MemoryImage(logo), width: 46, height: 46),
          ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // L'en-tête vient du point unique `EnteteEtablissement`, jamais
              // recopiée : `RESPECT_TABLEAU_RAPPORT.md` §4 recense l'en-tête
              // recopiée localement comme non-conformité n° 1. C'est aussi ce
              // qui garantit qu'aucun IFU d'exemple n'atteint le papier — les
              // identifiants non renseignés y sont écartés à la source.
              for (final (index, ligne) in entete.lignesA4.indexed)
                pw.Text(
                  _t(ligne),
                  style: index == 0
                      ? pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                        )
                      : const pw.TextStyle(fontSize: 8),
                ),
            ],
          ),
        ),
        pw.Text(
          _t(titre),
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
      ],
    ),
  );

  pw.Widget _identification() => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      for (final ligne in identification)
        pw.Text(_t(ligne), style: const pw.TextStyle(fontSize: 10)),
    ],
  );

  pw.Widget _tableau() {
    if (lignes.isEmpty) {
      // Une réservation d'avant le détail par service : le document le dit
      // plutôt que d'imprimer un tableau vide, qu'on prendrait pour une erreur
      // d'impression.
      return pw.Text(
        _t('Séjour enregistré avant le détail par service.'),
        style: const pw.TextStyle(fontSize: 10),
      );
    }

    return pw.TableHelper.fromTextArray(
      headers: entetes.map(_t).toList(),
      data: [for (final ligne in lignes) ligne.map(_t).toList()],
      headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 9),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellAlignments: {
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
      },
    );
  }

  pw.Widget _recapitulatif() => pw.Align(
    alignment: pw.Alignment.centerRight,
    child: pw.SizedBox(
      // Le bloc du maître, aligné à droite sur 280 px.
      width: 200,
      child: pw.Column(
        children: [
          for (final (libelle, valeur, accentue) in recapitulatif)
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              decoration: accentue
                  ? const pw.BoxDecoration(
                      border: pw.Border(top: pw.BorderSide(width: 1)),
                    )
                  : null,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    _t(libelle),
                    style: pw.TextStyle(
                      fontSize: accentue ? 11 : 9,
                      fontWeight: accentue
                          ? pw.FontWeight.bold
                          : pw.FontWeight.normal,
                    ),
                  ),
                  pw.Text(
                    _t(valeur),
                    style: pw.TextStyle(
                      fontSize: accentue ? 11 : 9,
                      fontWeight: accentue
                          ? pw.FontWeight.bold
                          : pw.FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  pw.Widget _mention() => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
    child: pw.Text(_t(mention), style: const pw.TextStyle(fontSize: 9)),
  );
}
