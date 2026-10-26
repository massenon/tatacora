import 'dart:convert';

import '../../../core/format/formats.dart';
import '../../../core/impression/etat_tabulaire_a4.dart';
import '../../../core/impression/visas.dart';
import '../domain/calcul_inventaire.dart';
import '../domain/calcul_stock.dart';

/// L'export du **rapport d'inventaire physique** — le bouton « Exporter » de la
/// feuille de comptage (vue `inventaires.blade.php`), tableur (CSV) et PDF A4.
///
/// @see RG-19 Convention d'export
/// @see EF-M6-05 Inventaire physique avec écarts
///
/// ## Ce que le papier dit
///
/// Le gabarit du serveur (`pdf/inventaire-rapport.blade.php`) imprime les
/// articles COMPTÉS : le stock théorique figé, le compté, l'écart et sa valeur.
/// Cet état fait de même, avec les trois chiffres de sa tête (articles
/// comptés, écarts détectés, impact valorisé) et ses visas propres (« Visa Agent
/// Recenseur », « Visa Responsable Magasin / Direction »).
///
/// Deux écarts avec le serveur, NOMMÉS :
///
///  * le serveur ne produit QUE le PDF, même quand le tableur est choisi
///    (`Inventaires::exporterInventaire` ignore le format) ; ce poste écrit le
///    tableur quand on le demande ;
///  * un écart dont l'article n'a aucune entrée valorisée a une valeur « — »,
///    pas « 0 FCFA » : son coût est INCONNU, et un zéro se somme.
///
/// Le rapport est celui d'un comptage EN COURS (la feuille affichée), non
/// clôturé : il le dit.
final class EtatInventaire {
  const EtatInventaire({
    required this.point,
    required this.date,
    required this.feuille,
  });

  /// Le libellé du point inventorié.
  final String point;

  /// Le jour d'ouverture de l'inventaire.
  final DateTime date;

  final FeuilleComptage feuille;

  static const String titre = 'Inventaire physique';

  /// Le préfixe du fichier écrit (`rapport_inventaire_` côté serveur).
  static const String prefixeFichier = 'rapport_inventaire';

  /// `stocks_pwa.export.liste_vide` — un comptage où rien n'est compté ne se
  /// rapporte pas : le papier serait une page blanche.
  static const String refusVide =
      'Rien à exporter : aucun article n’a encore été compté.';

  static const List<String> entetes = [
    'Article',
    'Stock Théorique',
    'Stock Compté',
    'Écart',
    'Valeur Écart (FCFA)',
  ];

  static const String _tiret = '—';

  /// Les lignes COMPTÉES de la feuille, dans son ordre.
  List<LigneFeuille> get lignes => [
    for (final l in feuille.lignes)
      if (l.compte) l,
  ];

  bool get vide => lignes.isEmpty;

  /// `periode_inventaire` : « [point] — inventaire du [date] ».
  String get portee => '$point — inventaire du ${formaterDate(date)}';

  List<String> get mentions => [
    'Comptage en cours : l’inventaire n’est pas clôturé et aucune '
        'régularisation n’est encore écrite.',
    if (feuille.nonComptes > 0)
      '${feuille.nonComptes} article(s) ne sont pas encore comptés : ils ne '
          'figurent pas dans ce document.',
    if (feuille.ecartsSansCout > 0)
      '${feuille.ecartsSansCout} écart(s) n’ont aucune entrée valorisée : leur '
          'valeur est « $_tiret », jamais zéro.',
  ];

  List<String> _cellules(LigneFeuille l, {required bool papier}) {
    final ecart = l.ecartCentiemes!;
    final valeur = l.valoriseFrancs;
    return [
      l.libelle,
      ecrireCentiemes(l.theoriqueCentiemes),
      ecrireCentiemes(l.constateCentiemes!),
      ecart > 0 ? '+${ecrireCentiemes(ecart)}' : ecrireCentiemes(ecart),
      valeur == null ? _tiret : (papier ? formaterFcfa(valeur) : '$valeur'),
    ];
  }

  String csv() {
    final tampon = StringBuffer('\u{FEFF}')
      ..writeln('${_e(titre)};${_e(portee)}')
      ..writeln()
      ..writeln(
        _e(
          '${lignes.length} article(s) comptés · ${feuille.ecarts} écart(s) · '
          'impact valorisé ${formaterFcfa(feuille.impactFrancs)}',
        ),
      );
    for (final m in mentions) {
      tampon.writeln(_e(m));
    }
    tampon
      ..writeln()
      ..writeln(entetes.map(_e).join(';'));
    for (final l in lignes) {
      tampon.writeln(_cellules(l, papier: false).map(_e).join(';'));
    }
    return tampon.toString();
  }

  List<int> csvOctets() => utf8.encode(csv());

  /// Le « PDF Officiel A4 Imprimable » : les articles comptés, leurs écarts, et
  /// le bilan en tête de page.
  EtatTabulaireA4 etatA4() => EtatTabulaireA4(
    titre: titre,
    visas: Visas.inventaire,
    portee: portee,
    mentions: mentions,
    colonnes: [
      const ColonneEtat('Article', largeur: 2.2),
      for (final e in entetes.skip(1)) ColonneEtat.nombre(e),
    ],
    lignes: [for (final l in lignes) _cellules(l, papier: true)],
    resume:
        '${lignes.length} article(s) comptés · ${feuille.ecarts} écart(s) · '
        'impact valorisé ${formaterFcfa(feuille.impactFrancs)}',
  );

  static String _e(String v) =>
      v.replaceAll(';', ',').replaceAll('\n', ' ').replaceAll('\r', ' ');
}
