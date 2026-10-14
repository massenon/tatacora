import 'dart:convert';

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
  /// La septième colonne du tableau, « Pièces » (le reçu), est absente : aucun
  /// reçu ne peut être joint sur ce poste, et une colonne vide sur toutes les
  /// lignes n'apprend rien. Le motif est dit en mention.
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
    'Aucun reçu n\'est joint : ce poste n\'a pas de sélecteur de fichier. La '
        'colonne « Pièces » du tableau n\'est donc pas exportée.',
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
      tampon.writeln(
        [
          _date(depense.dateTransaction),
          depense.libelle,
          depense.naturesAffichees,
          _comptes(depense, libelles),
          depense.tresorerie?.libelle ?? tiretAbsence,
          // Nombre brut : ni séparateur de milliers, ni unité.
          depense.montantTotal.toString(),
          depense.estComptabilisee ? comptabilisee : nonComptabilisee,
          depense.numeroPiece ?? tiretAbsence,
        ].map(_e).join(';'),
      );
    }

    return tampon.toString();
  }

  List<int> csvOctets() => utf8.encode(csv());

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
