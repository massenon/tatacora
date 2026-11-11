import 'dart:convert';

import '../../../core/format/formats.dart';
import '../../../core/impression/etat_tabulaire_a4.dart';
import '../../../core/impression/visas.dart';
import '../domain/categories_depense.dart';
import '../domain/entities/depense.dart';
import '../domain/filtre_depenses.dart';

/// L'export de la dépense courante — le bouton « Exporter » de la barre.
///
/// ## Un export porte sur CE QUI EST AFFICHÉ, et il DIT son filtre (PA-119)
///
/// La liste reçue est déjà filtrée : rendre le registre entier à quelqu'un qui
/// a filtré lui ferait envoyer au comptable un document qu'il croit avoir
/// vérifié. La portée est écrite **dans le fichier**, pas seulement à l'écran —
/// un document qui ne dit pas sa portée se lit comme s'il portait tout.
///
/// ## « Excel » est rendu en CSV, et l'écart est nommé
///
/// Convention serveur RG-19 : BOM UTF-8 et point-virgule, ce qu'attend un Excel
/// en configuration française. Aucune bibliothèque XLSX n'est embarquée — même
/// écart qu'en PA-111.
///
/// ## Les montants partent en nombres BRUTS
///
/// Un tableur ne sait pas additionner « 56 000 FCFA ». La colonne est un
/// nombre ; l'unité est dite une fois, dans l'en-tête.
///
/// ## La comptabilisation est DITE, ligne par ligne (depuis la v16)
///
/// La septième colonne du serveur, « Comptabilisation » (`comptabilisée` /
/// `non comptabilisée`), est reprise mot pour mot : elle se lit de
/// `Depense.estComptabilisee`, la clé étrangère vers la pièce, jamais d'un
/// drapeau — une dépense antérieure à la v16 sortirait sinon « comptabilisée »
/// alors qu'aucune pièce n'existe. Une huitième colonne, « Pièce comptable »,
/// porte le numéro du moteur (`CAI-2026-00007`) ou « — » : c'est la référence
/// que le Comptable cherchera au grand livre (ajout de ce poste, absent du
/// classeur du serveur).
final class EtatDepenses {
  const EtatDepenses({
    required this.lignes,
    required this.portee,
    this.libelles = const LibellesDesComptes(),
  });

  /// Les libellés des comptes (le plan, puis l'ancien registre à six chiffres).
  final LibellesDesComptes libelles;

  /// La liste filtrée, telle qu'elle est affichée.
  final List<Depense> lignes;

  /// [FiltreDepenses.description] — « recherche « … » · à partir du … ».
  final String portee;

  /// Le titre du document, au mot du serveur (`export_document`).
  static const String titre = 'État des dépenses courantes';

  /// Le préfixe du fichier écrit (`export_fichier`).
  static const String prefixeFichier = 'etat_depenses';

  /// Les colonnes du fichier : les six du tableau qui ont une source sur ce
  /// poste, « Comptabilisation » du serveur, puis « Pièce comptable ».
  ///
  /// La septième colonne du tableau, « Pièces » (le reçu et son état), est
  /// absente, comme à l'export du serveur (`DepensesExport` : sept colonnes dont
  /// « Comptabilisation », jamais le reçu) : un fichier image ne se range pas
  /// dans une cellule. Le motif est dit en mention.
  static const List<String> entetes = [
    'Date',
    'Libellé',
    'Nature',
    'Charge (SYSCOHADA)',
    'Trésorerie',
    'Montant (FCFA)',
    'Comptabilisation',
    'Pièce comptable',
  ];

  /// Les deux valeurs de « Comptabilisation » (`export_comptabilisee`,
  /// `export_non_comptabilisee` du serveur).
  static const String comptabilisee = 'comptabilisée';
  static const String nonComptabilisee = 'non comptabilisée';

  /// Lot F4 : une dépense descendue d'un autre poste (pièce au serveur).
  static const String pieceAuServeur = 'pièce au serveur';

  bool get vide => lignes.isEmpty;

  /// Le total décaissé du document — somme des montants, eux-mêmes sommes des
  /// lignes. Aucun flottant n'apparaît.
  int get total =>
      lignes.fold<int>(0, (somme, depense) => somme + depense.montantTotal);

  /// Les mentions qui bornent le document.
  static const List<String> mentions = [
    'Ce fichier reprend la liste filtrée telle qu\'elle est affichée à '
        'l\'écran, et rien d\'autre.',
    'La colonne « Comptabilisation » dit, dépense par dépense, si une pièce '
        'comptable existe. Une dépense « non comptabilisée » manque au grand '
        'livre, à la balance et au compte de résultat tant que sa pièce n\'a '
        'pas été passée.',
    'Les reçus joints ne figurent pas dans ce fichier : la colonne « Pièces » '
        'du tableau (le reçu et son état) n\'est pas exportée.',
    'Une dépense portant plusieurs achats rend ses natures et ses comptes '
        'distincts dans la même cellule, comme à l\'écran.',
  ];

  String csv() {
    final tampon = StringBuffer('\u{FEFF}')
      ..writeln('${_e(titre)};${_e(portee)}')
      ..writeln();

    for (final mention in mentions) {
      tampon.writeln(_e(mention));
    }
    tampon.writeln();

    tampon.writeln(entetes.map(_e).join(';'));

    for (final depense in lignes) {
      tampon.writeln(_cellules(depense, papier: false).map(_e).join(';'));
    }

    return tampon.toString();
  }

  List<int> csvOctets() => utf8.encode(csv());

  /// Les cellules d'une dépense — les MÊMES pour le tableur et le papier ;
  /// seul le montant change de forme : nombre brut au CSV (ni séparateur de
  /// milliers, ni unité), « 56 000 FCFA » au PDF.
  List<String> _cellules(Depense depense, {required bool papier}) => [
    _date(depense.dateTransaction),
    depense.libelle,
    depense.naturesAffichees,
    _comptes(depense, libelles),
    depense.tresorerie?.libelle ?? tiretAbsence,
    papier
        ? formaterFcfa(depense.montantTotal)
        : depense.montantTotal.toString(),
    depense.estComptabilisee
        ? comptabilisee
        : depense.pieceAuServeur
        ? pieceAuServeur
        : nonComptabilisee,
    depense.numeroPiece ?? tiretAbsence,
  ];

  /// Le « PDF Officiel A4 Imprimable » (directive du PO du 14/10/2026) : les
  /// colonnes, les lignes, la portée et les mentions du CSV, plus le total
  /// décaissé. Huit colonnes : PAYSAGE. Les visas sont ceux du gabarit serveur
  /// du même état (`pdf/depenses-rapport.blade.php`), pas ceux de la directive.
  EtatTabulaireA4 etatA4() => EtatTabulaireA4(
    titre: titre,
    portee: portee,
    visas: Visas.depenses,
    mentions: [
      for (final m in mentions) m.replaceFirst('Ce fichier', 'Ce document'),
    ],
    colonnes: [
      for (final (i, entete) in entetes.indexed)
        i == 5
            ? ColonneEtat.nombre(entete)
            : ColonneEtat(entete, largeur: i == 1 ? 2.2 : (i == 3 ? 2 : 1.2)),
    ],
    lignes: [for (final d in lignes) _cellules(d, papier: true)],
    totaux: [
      'Total',
      '${lignes.length} dépense(s)',
      '',
      '',
      '',
      formaterFcfa(total),
      '',
      '',
    ],
  );

  /// Les comptes distincts d'une dépense, dans l'ordre de ses lignes.
  static String _comptes(Depense depense, LibellesDesComptes libelles) {
    final vus = <String>[];
    for (final ligne in depense.lignes) {
      final affiche = ligne.compteAffiche(libelles);
      if (!vus.contains(affiche)) vus.add(affiche);
    }
    return vus.isEmpty ? tiretAbsence : vus.join(' | ');
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// Le point-virgule est le séparateur : un point-virgule DANS une valeur
  /// casserait la colonne, et un saut de ligne casserait la ligne.
  static String _e(String v) =>
      v.replaceAll(';', ',').replaceAll('\n', ' ').replaceAll('\r', ' ');
}
