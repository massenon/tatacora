import 'dart:convert';

import '../domain/entities/etat_du_jour.dart';
import '../domain/entities/unite_hebergement.dart';

/// L'export du **parc d'hébergement** — le bouton d'export du plan
/// (`hebergement.blade.php` l.185-188), tableur seulement.
///
/// ⚠ Le libellé du bouton n'est volontairement pas recopié ici : ce fichier est
/// importé par `providers_hebergement.dart`, donc atteint par d'autres écrans,
/// et le comparateur de libellés cherche par sous-chaîne dans tout ce qu'un
/// écran atteint — une citation en commentaire ferait compter « porté » un
/// libellé qu'aucun de ces écrans ne rend (PA-189, D35).
///
/// @see RG-19 Convention d'export
/// @see RG-02 La pastille est la disponibilité du JOUR, jamais la colonne
///
/// ## Un export porte sur CE QUI EST AFFICHÉ, et il DIT son filtre (PA-119)
///
/// La vue exporte `parcFiltre()` — le parc filtré, TOUTES pages confondues,
/// pas la page courante (`genererExport`, l.571-614). La liste reçue ici est
/// donc le parc filtré entier, et la portée est écrite **dans le fichier** : un
/// document qui ne dit pas sa portée se lit comme s'il portait tout le parc.
///
/// ## Les mêmes colonnes que la vue, et le même « statut »
///
/// `HebergementExport::headings()` pose quatre colonnes — code, catégorie,
/// tarif de base, statut. Le statut est l'ÉTAT DU JOUR déjà dérivé par l'écran,
/// reçu et jamais recalculé : une seconde dérivation finirait par contredire
/// celle de l'écran sur le même jeu de lignes. Le fichier DIT à quelle date il
/// vaut — un état du jour relu une semaine plus tard n'est plus celui-là.
///
/// ## « Excel » est rendu en CSV, et le PDF n'est pas produit
///
/// Convention RG-19 : BOM UTF-8 et point-virgule, ce qu'attend un Excel en
/// configuration française ; aucune bibliothèque XLSX n'est embarquée. Le choix
/// « PDF Officiel A4 » reste offert par la modale de la vue et répond par un
/// message : aucun A4 du parc n'existe (en-tête unique et visas, arbitrage
/// PA-192). Le tarif part en nombre BRUT : un tableur ne sait pas additionner
/// « 28 000 FCFA », l'unité est dite une fois dans l'en-tête.
final class EtatParc {
  const EtatParc({
    required this.unites,
    required this.etats,
    required this.portee,
    required this.aujourdHui,
  });

  /// Le parc filtré entier, dans l'ordre de l'écran (`orderBy('numero')`).
  final List<UniteHebergement> unites;

  /// L'état du jour de chaque unité (`etatsDuJourProvider`).
  final Map<String, EtatDuJour> etats;

  /// Le filtre réellement appliqué, en clair ([EtatParc.decrireFiltre]).
  final String portee;

  /// La date à laquelle l'état du jour est vrai. Passée, jamais lue d'une
  /// horloge ici : le test fixe la sienne.
  final DateTime aujourdHui;

  /// Le titre du document — `export_titre` de la vue, sans son préfixe.
  static const String titre = "Unités d'hébergement";

  /// Le préfixe du fichier écrit (`hebergement_parc_` côté serveur).
  static const String prefixeFichier = 'hebergement_parc';

  /// `export_sans_filtre` (`hebergement_pwa.php` l.132).
  static const String sansFiltre = 'Aucun filtre — parc complet';

  /// `export_vide` (`hebergement_pwa.php` l.133) — une liste vide se REFUSE.
  static const String refusVide =
      "Aucune unité ne correspond aux filtres : il n'y a rien à exporter.";

  /// Les quatre colonnes de `HebergementExport::headings()`, dans son ordre :
  /// `champ_code`, `champ_categorie`, `tarif_de_base`, `col_statut`.
  static const List<String> entetes = [
    'Code unité',
    'Catégorie',
    'Tarif de base (FCFA)',
    'Statut',
  ];

  bool get vide => unites.isEmpty;

  /// Le filtre en clair, au format de `libelleDuFiltre()` (l.756-773) : la
  /// catégorie, puis la recherche, séparées par « · ».
  static String decrireFiltre({String? categorie, String recherche = ''}) {
    final morceaux = [
      if (categorie != null && categorie.isNotEmpty) categorie,
      if (recherche.isNotEmpty) recherche,
    ];
    return morceaux.isEmpty ? sansFiltre : morceaux.join(' · ');
  }

  /// Les mentions qui bornent le document (PA-135 : une mention qui borne la
  /// portée s'imprime avec lui).
  List<String> get mentions => [
    "Ce fichier reprend le parc tel qu'il est affiché à l'écran, filtres "
        'compris, toutes pages confondues, et rien d\'autre.',
    'Le statut est la disponibilité DU JOUR (${_date(aujourdHui)}), dérivée '
        'des réservations : il ne vaut pas pour une autre date.',
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

    for (final unite in unites) {
      tampon.writeln(
        [
          unite.numero,
          unite.categorieLibelle,
          // Nombre brut : ni séparateur de milliers, ni unité.
          unite.tarifBase.toString(),
          // Une unité sans état calculé n'est pas « Libre » : elle porte le
          // tiret, jamais un statut plausible.
          etats[unite.id]?.libelle ?? '—',
        ].map(_e).join(';'),
      );
    }

    return tampon.toString();
  }

  List<int> csvOctets() => utf8.encode(csv());

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// Le point-virgule est le séparateur : un point-virgule DANS une valeur
  /// casserait la colonne, et un saut de ligne casserait la ligne.
  static String _e(String v) =>
      v.replaceAll(';', ',').replaceAll('\n', ' ').replaceAll('\r', ' ');
}
