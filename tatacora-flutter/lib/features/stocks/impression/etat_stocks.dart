import 'dart:convert';

import '../domain/entities/etat_stock.dart';

/// L'export du **référentiel des stocks** — le bouton d'export de la page
/// (`stocks.blade.php` l.243-244), tableur seulement.
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
/// ## Le tableur est un CSV, et le PDF n'est pas produit
///
/// Convention RG-19 : BOM UTF-8 et point-virgule. Le choix du PDF reste offert
/// par la modale partagée et répond par un message : aucun A4 de cet état
/// n'existe sur ce poste (en-tête unique et visas, arbitrage PA-192).
/// Les montants et les quantités partent en nombres BRUTS : un tableur ne sait
/// pas additionner « 12 sacs ».
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
    'Le stock ne compte que les mouvements saisis sur ce poste : les ventes '
        "du bar et du restaurant n'y écrivent aucune sortie.",
    'Aucune écriture comptable n\'est produite : un mouvement de stock '
        'n\'est pas un mouvement d\'argent, et sa valorisation comptable '
        'n\'est pas portée sur ce poste (état du 12/10/2026).',
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
      final journalier = l.estJournalier;

      tampon.writeln(
        [
          l.libelle,
          l.categorie ?? _tiret,
          l.uniteMesure,
          l.pointLibelle ?? _tiret,
          l.suivi.libelle,
          journalier ? 'non suivi' : l.stock,
          journalier ? _tiret : l.seuilAlerte,
          l.prixAchat ?? _tiret,
          l.cmpInconnu ? _tiret : l.coutMoyenPondere,
          (journalier || l.valeurInconnue) ? _tiret : l.valeurStock,
        ].map(_e).join(';'),
      );
    }

    return tampon.toString();
  }

  List<int> csvOctets() => utf8.encode(csv());

  /// Le point-virgule est le séparateur : un point-virgule DANS une valeur
  /// casserait la colonne, et un saut de ligne casserait la ligne.
  static String _e(String v) =>
      v.replaceAll(';', ',').replaceAll('\n', ' ').replaceAll('\r', ' ');
}
