import 'dart:convert';

import '../../../core/format/formats.dart';
import '../../../core/impression/etat_tabulaire_a4.dart';
import '../../../core/impression/visas.dart';

import '../domain/entities/etat_stock.dart';

/// L'export du **référentiel des stocks** — le bouton d'export de la page
/// (`stocks.blade.php` l.243-244), tableur (CSV) et PDF A4.
///
/// @see RG-19 Convention d'export
/// @see EF-M14-02 État des stocks
///
/// ## Un export porte sur CE QUI EST AFFICHÉ, et il DIT son filtre (PA-119)
///
/// La vue exporte la liste filtrée, toutes pages confondues (`genererExport`).
/// La liste reçue ici est donc les lignes affichées, et la portée est écrite
/// **dans le fichier** : un document qui ne dit pas sa portée se lit comme s'il
/// portait tout le référentiel. Une liste vide se REFUSE — un fichier sans
/// ligne se lirait « il n'y a aucun article », alors qu'il veut dire « le
/// filtre n'a rien retenu ».
///
/// ## Les dix colonnes de `StocksExport::headings()`, mot pour mot
///
/// Relues sur le fichier PHP par un test : une liste recopiée à la main ne
/// vérifierait qu'elle-même. Deux écarts avec le fichier du serveur, NOMMÉS :
///
///  * une catégorie absente s'écrit « — », pas « Général » : le serveur invente
///    une catégorie qu'aucun article ne porte ;
///  * un article qui a du stock mais aucune entrée valorisée a une valeur
///    « — », pas un zéro : son coût est INCONNU, et un zéro de tableur se
///    somme.
///
/// ## Le tableur est un CSV ; le PDF est l'état A4 des mêmes colonnes
///
/// Convention RG-19 : BOM UTF-8 et point-virgule. Les montants et les
/// quantités partent en nombres BRUTS : un tableur ne sait pas additionner
/// « 12 sacs ». Le « PDF Officiel A4 Imprimable » (directive du PO du
/// 14/10/2026) reprend colonnes, lignes, filtre et mentions, en paysage (dix
/// colonnes), montants en FCFA à droite ([etatA4]).
final class EtatStocks {
  const EtatStocks({
    required this.lignes,
    required this.portee,
    required this.arreteAu,
    required this.sansValorisation,
  });

  /// Les lignes affichées, dans l'ordre de l'écran.
  final List<LigneStock> lignes;

  /// Le filtre réellement appliqué, en clair ([EtatStocks.decrireFiltre]).
  final String portee;

  /// L'instant où ce poste a arrêté ses comptes (`EtatStock.arreteAu`).
  final String arreteAu;

  /// Les articles qui ont du stock sans aucune entrée valorisée, sur TOUT le
  /// référentiel (`KpisStock.sansValorisation`).
  final int sansValorisation;

  static const String titre = 'État des Stocks';

  /// Le préfixe du fichier écrit (`etat_des_stocks_` côté serveur).
  static const String prefixeFichier = 'etat_des_stocks';

  /// `stocks_pwa.export.filtre_aucun`.
  static const String sansFiltre = 'aucun filtre, le référentiel entier';

  /// `stocks_pwa.export.liste_vide` — une liste vide se REFUSE.
  static const String refusVide =
      'Rien à exporter : aucun article ne correspond aux filtres affichés.';

  /// `StocksExport::headings()`, dans son ordre.
  static const List<String> entetes = [
    'Désignation Article',
    'Catégorie',
    'Unité de Mesure',
    'Point',
    'Suivi',
    'Stock Calculé',
    "Seuil d'Alerte",
    "Valeur d'Achat (FCFA)",
    'Coût Moyen Pondéré (FCFA)',
    'Valeur Totale du Stock (FCFA)',
  ];

  static const String _tiret = '—';

  bool get vide => lignes.isEmpty;

  /// Le filtre en clair, au format de `libelleDesFiltres()` : les filtres
  /// posés, séparés par « · ».
  static String decrireFiltre({
    String recherche = '',
    String? categorie,
    String? point,
    SuiviArticle? suivi,
    EtatStockFiltre etat = EtatStockFiltre.tous,
  }) {
    final morceaux = [
      if (recherche.trim().isNotEmpty) 'Recherche « ${recherche.trim()} »',
      if (categorie != null && categorie.isNotEmpty) 'Catégorie : $categorie',
      if (point != null && point.isNotEmpty) 'Point : $point',
      if (suivi != null)
        suivi == SuiviArticle.journalier
            ? 'Petit stock (journalier)'
            : 'Gros stock (permanent)',
      if (etat != EtatStockFiltre.tous) etat.libelle,
    ];
    return morceaux.isEmpty ? sansFiltre : morceaux.join(' · ');
  }

  /// Les mentions qui bornent le document (PA-135 : une mention qui borne la
  /// portée s'imprime avec lui).
  List<String> get mentions => [
    "Ce fichier reprend les articles tels qu'ils sont affichés à l'écran, "
        'filtres compris, toutes pages confondues, et rien d\'autre.',
    'Le stock ne compte que les mouvements saisis ici : les ventes '
        "du bar et du restaurant n'y écrivent aucune sortie.",
    'Aucune écriture comptable n\'est produite : un mouvement de stock '
        'n\'est pas un mouvement d\'argent.',
    if (sansValorisation > 0)
      '$sansValorisation article(s) ont du stock sans aucune entrée '
          'valorisée : leur valeur est « $_tiret », jamais zéro.',
    'Arrêté au $arreteAu.',
  ];

  String csv() {
    final tampon = StringBuffer('\u{FEFF}')
      ..writeln('${_e(titre)};${_e('Filtre appliqué : $portee')}')
      ..writeln();

    for (final mention in mentions) {
      tampon.writeln(_e(mention));
    }
    tampon.writeln();

    tampon.writeln(entetes.map(_e).join(';'));

    for (final l in lignes) {
      tampon.writeln(_cellules(l, papier: false).map(_e).join(';'));
    }

    return tampon.toString();
  }

  List<int> csvOctets() => utf8.encode(csv());

  /// Les cellules d'un article, les mêmes au tableur et au papier ; seuls les
  /// trois montants changent de forme (nombre brut au CSV, FCFA au PDF). Le
  /// tiret d'une valeur inconnue reste un tiret.
  List<String> _cellules(LigneStock l, {required bool papier}) {
    final journalier = l.estJournalier;
    String montant(String? brut) => brut == null
        ? _tiret
        : (papier
              ? formaterMontantDecimal(brut, suffixe: 'FCFA') ?? brut
              : brut);

    return [
      l.libelle,
      l.categorie ?? _tiret,
      l.uniteMesure,
      l.pointLibelle ?? _tiret,
      l.suivi.libelle,
      journalier ? 'non suivi' : l.stock,
      journalier ? _tiret : l.seuilAlerte,
      montant(l.prixAchat),
      l.cmpInconnu ? _tiret : montant(l.coutMoyenPondere),
      (journalier || l.valeurInconnue) ? _tiret : montant(l.valeurStock),
    ];
  }

  /// Le « PDF Officiel A4 Imprimable » des articles affichés (paysage). Les
  /// visas sont ceux du gabarit serveur du même état
  /// (`pdf/stocks-etat.blade.php`), pas ceux de la directive.
  EtatTabulaireA4 etatA4() => EtatTabulaireA4(
    titre: titre,
    visas: Visas.etatStocks,
    portee: 'Filtre appliqué : $portee',
    mentions: [
      for (final m in mentions) m.replaceFirst('Ce fichier', 'Ce document'),
    ],
    colonnes: [
      for (final (i, e) in entetes.indexed)
        i >= 5 ? ColonneEtat.nombre(e) : ColonneEtat(e, largeur: 1.2),
    ],
    lignes: [for (final l in lignes) _cellules(l, papier: true)],
    resume: '${lignes.length} article(s)',
  );

  /// Le point-virgule est le séparateur : un point-virgule DANS une valeur
  /// casserait la colonne, et un saut de ligne casserait la ligne.
  static String _e(String v) =>
      v.replaceAll(';', ',').replaceAll('\n', ' ').replaceAll('\r', ' ');
}
