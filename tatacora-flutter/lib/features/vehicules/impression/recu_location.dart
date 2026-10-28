import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/format/formats.dart';
import '../../../core/impression/entete_etablissement.dart';
import '../../../core/impression/texte_ticket.dart';
import '../domain/entities/contrat_location.dart';

/// Le REÇU de location (PDF A4) d'UN contrat — le jumeau de
/// `pdf/location-recu.blade.php` du serveur (`Locations::imprimerRecu`) : mêmes
/// lignes, mêmes libellés (`vehicules.pwa.recu_*`), même ordre.
///
/// ## Ce n'est pas une facture
///
/// La mention est au CORPS, comme la confirmation de réservation (PA-113) : la
/// facture normalisée MECeF est émise à l'encaissement. **Aucun numéro n'est
/// alloué** : le N° est celui du contrat (`LOC-…`), le tiret s'il n'en a pas
/// encore (le poste n'invente aucun numéro). Rien n'est écrit.
///
/// ## Un contrat ANNULÉ ne montre AUCUN montant
///
/// Bandeau « ANNULÉ » bien visible, puis « aucun montant n'est dû » : ni
/// total, ni acompte, ni reste dû. Un acompte versé n'est pas un dû, mais
/// l'écrire sur un contrat annulé se lirait comme une créance.
///
/// ## Le tarif journalier n'est écrit que s'il EXPLIQUE le montant figé
///
/// Le montant est figé à la signature ; le tarif du véhicule a pu changer
/// depuis. Le tarif ne s'imprime donc que si tarif × jours = montant (calcul
/// en entiers), sinon le tiret — la règle exacte de
/// `ContratLocationService::donneesRecu`.
///
/// ## Remis à un client : ni visa, ni pied de rapport
///
/// Classé « document client » par `pdf_directive_test`.
final class RecuLocation {
  const RecuLocation({
    required this.contrat,
    required this.emisLe,
    required this.emisPar,
    this.tarifJour,
    this.entete = const EnteteEtablissement(),
  });

  static const String titre = 'REÇU DE LOCATION';
  static const String bandeauAnnule = 'ANNULÉ';

  static const String mention =
      'Ce document atteste un contrat de location. Il ne vaut pas facture : la '
      "facture normalisée est émise à l'encaissement.";

  static const String mentionAnnule =
      "Ce contrat est annulé : aucun montant n'est dû au titre de ce contrat.";

  final ContratLocation contrat;

  /// Injectée, jamais lue de l'horloge à la composition.
  final DateTime emisLe;

  /// « Nom — Rôle » de l'utilisateur connecté, comme `ReportHeaderService`.
  final String emisPar;

  /// Le tarif journalier COURANT du véhicule (« 70000.00 »), ou `null`.
  final String? tarifJour;

  final EnteteEtablissement entete;

  RecuLocation avecEntete(EnteteEtablissement autre) => RecuLocation(
    contrat: contrat,
    emisLe: emisLe,
    emisPar: emisPar,
    tarifJour: tarifJour,
    entete: autre,
  );

  static const String _tiret = '—';

  /// Les centimes d'un décimal du schéma (« 70000.00 »), ou `null`.
  static int? _centimes(String? brut) {
    if (brut == null) return null;
    final texte = brut.trim();
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(texte)) return null;
    final point = texte.indexOf('.');
    final entier = int.parse(point < 0 ? texte : texte.substring(0, point));
    final decimale = point < 0
        ? 0
        : int.parse(
            texte.substring(point + 1).padRight(2, '0').substring(0, 2),
          );
    return entier * 100 + decimale;
  }

  /// Le tarif n'est rendu que s'il explique le montant figé.
  String? get tarifExplique {
    final tarif = _centimes(tarifJour);
    final montant = _centimes(contrat.montant);
    if (tarif == null || montant == null) return null;
    return tarif * contrat.nombreJours == montant ? tarifJour : null;
  }

  static String _fcfa(String? brut) =>
      formaterMontantDecimal(brut, suffixe: 'FCFA') ?? _tiret;

  /// Les lignes du reçu, dans l'ordre du gabarit serveur.
  List<(String, String)> get lignes {
    final annule = contrat.annule;
    final acompte = contrat.acompte;
    final reste = contrat.resteDu;
    final centimesReste = _centimes(reste);

    return [
      ('N° du contrat', contrat.numero ?? _tiret),
      ('Client', _vide(contrat.clientNom)),
      ('Véhicule', _vide(contrat.immatriculation)),
      ('Période', 'Du ${_date(contrat.debut)} au ${_date(contrat.fin)}'),
      ('Durée', '${contrat.nombreJours} jour(s)'),
      if (!annule) ...[
        ('Tarif journalier', _fcfa(tarifExplique)),
        ('Montant total', _fcfa(contrat.montant)),
        (
          'Acompte versé',
          // `formatOuTiret` : un acompte nul se rend « — ».
          acompte == null || _centimes(acompte) == 0 ? _tiret : _fcfa(acompte),
        ),
        (
          'Reste dû',
          reste == null || contrat.montant == null
              ? _tiret
              : (centimesReste ?? 0) > 0
              ? _fcfa(reste)
              : 'Soldé',
        ),
      ],
      ('Statut', annule ? 'Annulé' : 'Actif'),
      ('Émis le', formaterDate(emisLe)),
      ('Émis par', emisPar),
    ];
  }

  static String _vide(String? v) => v == null || v.isEmpty ? _tiret : v;

  /// `AAAA-MM-JJ` en `JJ/MM/AAAA`.
  static String _date(String iso) {
    final p = iso.split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : iso;
  }

  static String _t(String source) => texteTicket(source);

  Future<Uint8List> pdf() async {
    final doc = pw.Document();
    final logo = entete.logo;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => _entete(logo),
        build: (context) => [
          if (contrat.annule) ...[_bandeau(), pw.SizedBox(height: 10)],
          _tableau(),
          pw.SizedBox(height: 16),
          _encadre(mention),
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
              // Le point unique `EnteteEtablissement` : jamais recopié.
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

  pw.Widget _bandeau() => pw.Column(
    children: [
      pw.Container(
        width: double.infinity,
        alignment: pw.Alignment.center,
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(width: 2, color: PdfColors.red800),
        ),
        child: pw.Text(
          _t(bandeauAnnule),
          style: pw.TextStyle(
            fontSize: 22,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.red800,
          ),
        ),
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        _t(mentionAnnule),
        style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.red800),
      ),
    ],
  );

  pw.Widget _tableau() => pw.Table(
    columnWidths: {
      0: const pw.FlexColumnWidth(2),
      1: const pw.FlexColumnWidth(3),
    },
    border: const pw.TableBorder(
      horizontalInside: pw.BorderSide(width: 0.4, color: PdfColors.grey400),
      bottom: pw.BorderSide(width: 0.4, color: PdfColors.grey400),
    ),
    children: [
      for (final (cle, valeur) in lignes)
        pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 5,
                horizontal: 4,
              ),
              child: pw.Text(
                _t(cle),
                style: const pw.TextStyle(
                  fontSize: 9.5,
                  color: PdfColors.grey700,
                ),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 5,
                horizontal: 4,
              ),
              child: pw.Text(
                _t(valeur),
                style: pw.TextStyle(
                  fontSize: 9.5,
                  fontWeight: _fort(cle)
                      ? pw.FontWeight.bold
                      : pw.FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
    ],
  );

  static bool _fort(String cle) => cle == 'Montant total' || cle == 'Reste dû';

  pw.Widget _encadre(String texte) => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
    child: pw.Text(_t(texte), style: const pw.TextStyle(fontSize: 9)),
  );
}
