// Vue Blade maîtresse (PA-183) : pwa/rh/paie.blade.php
import 'dart:convert';

/// Le tiret du maître — « — » : la donnée n'existe pas. Jamais une cellule
/// vide, qui laisserait croire à un oubli d'affichage.
const String tiretPaie = '—';

/// L'export tableur de l'écran Personnel & Paie — le bouton « Exporter ».
///
/// ## Un export porte sur CE QUI EST AFFICHÉ, et il DIT son filtre (PA-119)
///
/// Les lignes reçues sont celles de l'onglet courant, déjà filtrées. La portée
/// (onglet, période, service, contrat, statut, recherche) est écrite **dans le
/// fichier**, pas seulement à l'écran : un document qui ne dit pas sa portée se
/// lit comme s'il portait tout le personnel.
///
/// ## Aucune colonne « Coût employeur » à valeur unique
///
/// Le coût employeur est TOUJOURS une fourchette : le taux CNSS de risques
/// professionnels n'est pas confirmé pour l'hôtellerie-restauration. L'onglet
/// des bulletins exporte la part patronale CONFIRMÉE, l'onglet du livre rend
/// le coût total sur une cellule « min — max ». Un chiffre unique dans un
/// classeur serait repris tel quel dans une déclaration : un export est le
/// dernier endroit où le refus pourrait se perdre.
///
/// ## « Excel » est rendu en CSV, et l'écart est nommé
///
/// Convention serveur RG-19 : BOM UTF-8 et point-virgule, ce qu'attend un Excel
/// en configuration française. Aucune bibliothèque XLSX n'est embarquée — même
/// écart que pour la dépense courante (PA-111). Les montants partent en
/// **nombres bruts** : un tableur ne sait pas additionner « 56 000 FCFA ».
///
/// ## Les en-têtes sont ceux de la vue
///
/// `App\Exports\PaieExport::entetesDe()` : même casse que le maître
/// (« Matricule », pas « MATRICULE ») — `uppercase` est une règle CSS qui ne
/// s'applique pas à un fichier.
final class EtatPaie {
  const EtatPaie({
    required this.cleOnglet,
    required this.titreOnglet,
    required this.entetes,
    required this.lignes,
    required this.portee,
  });

  /// `personnel`, `bulletins`… — sert à nommer le fichier (`paie_<onglet>`).
  final String cleOnglet;

  /// Le libellé de l'onglet exporté.
  final String titreOnglet;

  /// Les colonnes, au mot de la vue.
  final List<String> entetes;

  /// Les lignes réellement affichées, une cellule par colonne.
  final List<List<String>> lignes;

  /// La portée du document, en une ligne.
  final String portee;

  bool get vide => lignes.isEmpty;

  /// Le préfixe du fichier écrit — `paie_<onglet>_<horodatage>.csv`.
  String get prefixeFichier => 'paie_$cleOnglet';

  /// Les mentions qui bornent le document. Une mention qui borne la portée
  /// d'un document s'imprime avec lui (PA-135).
  static const List<String> mentions = [
    'Ce fichier reprend l’onglet tel qu’il est affiché à l’écran, et rien '
        'd’autre.',
    'Les montants sont en FCFA, en nombres bruts. Aucun total de charge '
        'patronale n’y figure : le taux de risques professionnels n’est pas '
        'confirmé, le coût employeur est donc toujours donné en fourchette.',
  ];

  String csv() {
    final tampon = StringBuffer('\u{FEFF}')
      ..writeln('${_e(titreOnglet)};${_e(portee)}')
      ..writeln();

    for (final mention in mentions) {
      tampon.writeln(_e(mention));
    }
    tampon.writeln();

    tampon.writeln(entetes.map(_e).join(';'));
    for (final ligne in lignes) {
      tampon.writeln(ligne.map(_e).join(';'));
    }

    return tampon.toString();
  }

  List<int> csvOctets() => utf8.encode(csv());

  /// Le point-virgule est le séparateur : un point-virgule DANS une valeur
  /// casserait la colonne, et un saut de ligne casserait la ligne.
  static String _e(String v) =>
      v.replaceAll(';', ',').replaceAll('\n', ' ').replaceAll('\r', ' ');
}
