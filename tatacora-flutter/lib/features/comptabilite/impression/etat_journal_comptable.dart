import 'dart:convert';

import '../../../core/format/formats.dart';
import '../../../core/impression/etat_tabulaire_a4.dart';
import '../domain/entities/comptabilite.dart';
import '../domain/montant_comptable.dart';

/// L'export du **journal comptable** — le bouton « Exporter » du hub
/// Comptabilité, onglet Journal (directive du PO du 14/10/2026).
///
/// ## Un export porte sur CE QUI EST AFFICHÉ, et il DIT son filtre (PA-119)
///
/// Les lignes reçues sont celles de l'onglet Journal, déjà retenues par
/// `porteeEcritures` (exercice, statuts, journal) et dans son ordre — TOUTES
/// pages confondues, pas la seule page affichée. La portée (exercice, statut,
/// journal) est écrite dans le document : un journal qui ne dit pas sa portée
/// se lit comme le journal entier de l'exercice.
///
/// ## « Excel » est rendu en CSV, et l'écart est nommé
///
/// Convention serveur RG-19, celle de tous les CSV du poste : BOM UTF-8 et
/// point-virgule. Débit et crédit partent en nombres BRUTS à deux décimales
/// (`chaineDepuisCentimes`, « 12500.00 ») : un tableur ne sait pas additionner
/// « 12 500 FCFA ». Aucune bibliothèque XLSX n'est embarquée (PA-111).
///
/// ## Le PDF est l'état A4 PAYSAGE du gabarit commun
///
/// Huit colonnes — date, n° pièce, journal, compte, libellé, débit, crédit,
/// statut — et la ligne des totaux débit / crédit, montants en FCFA à droite
/// ([etatA4]).
final class EtatJournalComptable {
  const EtatJournalComptable({
    required this.lignes,
    required this.portee,
    required this.journaux,
    required this.comptes,
    required this.centres,
  });

  /// Les écritures retenues, dans l'ordre de l'écran.
  final List<EcritureComptable> lignes;

  /// « Exercice 2026 · Statut : Toutes · Journal : VT — Ventes ».
  final String portee;

  /// Les journaux, par identifiant — pour le CODE du journal de chaque ligne.
  final Map<String, JournalComptable> journaux;

  /// Les comptes mouvementés, par identifiant.
  final Map<String, CompteDuPlan> comptes;

  /// Les centres de coût, par identifiant — le libellé de la ligne les cite,
  /// comme l'écran (« libellé · centre »).
  final Map<String, CentreDeCout> centres;

  static const String titre = 'Journal comptable';

  /// Le préfixe du fichier écrit.
  static const String prefixeFichier = 'journal_comptable';

  /// Une liste vide se REFUSE : un journal sans ligne se lirait « aucune
  /// écriture », alors qu'il veut dire « le filtre n'a rien retenu ».
  static const String refusVide =
      "Rien à exporter : aucune écriture ne correspond à l'exercice et aux "
      'filtres affichés.';

  static const List<String> entetes = [
    'Date',
    'N° pièce',
    'Journal',
    'Compte',
    'Libellé',
    'Débit',
    'Crédit',
    'Statut',
  ];

  static const String _tiret = '—';

  bool get vide => lignes.isEmpty;

  int get totalDebit => lignes.fold<int>(0, (s, e) => s + e.debitCentimes);

  int get totalCredit => lignes.fold<int>(0, (s, e) => s + e.creditCentimes);

  /// La portée en clair : exercice, statut retenu, journal.
  static String decrirePortee({
    required ExerciceComptable exercice,
    required String statut,
    JournalComptable? journal,
  }) => [
    'Exercice ${exercice.annee}',
    'Statut : $statut',
    'Journal : ${journal == null ? 'tous' : '${journal.code} — ${journal.libelle}'}',
  ].join(' · ');

  /// Les mentions qui bornent le document.
  static const List<String> mentions = [
    "Ce document reprend l'onglet Journal tel qu'il est affiché à l'écran, "
        'filtres compris, toutes pages confondues, et rien d\'autre.',
    'Une écriture « Brouillon » peut encore être modifiée : seule une '
        'écriture « Validée » est immuable.',
  ];

  String csv() {
    final tampon = StringBuffer('\u{FEFF}')
      ..writeln('${_e(titre)};${_e(portee)}')
      ..writeln();

    for (final mention in mentions) {
      tampon.writeln(_e(mention.replaceFirst('Ce document', 'Ce fichier')));
    }
    tampon.writeln();

    tampon.writeln(entetes.map(_e).join(';'));
    for (final e in lignes) {
      tampon.writeln(_cellules(e, papier: false).map(_e).join(';'));
    }

    return tampon.toString();
  }

  List<int> csvOctets() => utf8.encode(csv());

  /// Le « PDF Officiel A4 Imprimable » du journal affiché — paysage, totaux
  /// débit / crédit en gras.
  EtatTabulaireA4 etatA4() => EtatTabulaireA4(
    titre: titre,
    portee: portee,
    mentions: mentions,
    colonnes: const [
      ColonneEtat('Date', largeur: 1),
      ColonneEtat('N° pièce', largeur: 1.4),
      ColonneEtat('Journal', largeur: 0.8),
      ColonneEtat('Compte', largeur: 1),
      ColonneEtat('Libellé', largeur: 3.2),
      ColonneEtat.nombre('Débit', largeur: 1.4),
      ColonneEtat.nombre('Crédit', largeur: 1.4),
      ColonneEtat('Statut', largeur: 1),
    ],
    lignes: [for (final e in lignes) _cellules(e, papier: true)],
    totaux: [
      'TOTAUX',
      '',
      '',
      '',
      '${lignes.length} ligne(s)',
      _fcfa(totalDebit),
      _fcfa(totalCredit),
      '',
    ],
  );

  /// Les cellules d'une écriture, les mêmes au tableur et au papier ; seuls
  /// les montants changent de forme : nombre brut au CSV, FCFA au PDF (le
  /// zéro y est un tiret, comme à l'écran).
  List<String> _cellules(EcritureComptable e, {required bool papier}) {
    final centre = centres[e.centreId];
    String montant(int centimes) => papier
        ? (centimes == 0 ? _tiret : _fcfa(centimes))
        : chaineDepuisCentimes(centimes);

    return [
      _date(e.dateEcriture),
      e.numeroPiece ?? _tiret,
      journaux[e.journalId]?.code ?? _tiret,
      comptes[e.compteId]?.numero ?? _tiret,
      centre == null ? e.libelle : '${e.libelle} · ${centre.libelle}',
      montant(e.debitCentimes),
      montant(e.creditCentimes),
      switch (e.statut) {
        StatutEcriture.brouillon => 'Brouillon',
        StatutEcriture.validee => 'Validée',
      },
    ];
  }

  static String _fcfa(int centimes) =>
      formaterMontantDecimal(chaineDepuisCentimes(centimes), suffixe: 'FCFA') ??
      _tiret;

  /// `d/m/Y` — la date comptable `AAAA-MM-JJ`, sans fuseau.
  static String _date(String iso) {
    final p = iso.split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : iso;
  }

  /// Le point-virgule est le séparateur : un point-virgule DANS une valeur
  /// casserait la colonne, et un saut de ligne casserait la ligne.
  static String _e(String v) =>
      v.replaceAll(';', ',').replaceAll('\n', ' ').replaceAll('\r', ' ');
}
