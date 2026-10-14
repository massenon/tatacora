import 'dart:convert';

/// L'export de M8 — les boutons « Excel » et « PDF » de l'en-tête
/// (`m8-locations.html` l.41-42), servis par `etatCourant()`
/// (`m8-locations.js` l.407-448).
///
/// ## Un export porte sur CE QUI EST AFFICHÉ, et il DIT son filtre (PA-119)
///
/// Le maître construit son état **depuis l'onglet actif** : « Disponibilité du
/// parc » sur Parc, « Immobilisations du parc » sur Immobilisations,
/// « Contrats de location » sinon. Chacun a ses propres en-têtes. Rendre le
/// registre entier à quelqu'un qui a filtré lui ferait envoyer au comptable un
/// document qu'il croit avoir vérifié.
///
/// ## « Excel » est rendu en CSV, et l'écart est nommé, pas masqué
///
/// Convention serveur RG-19 : BOM UTF-8 et point-virgule, ce qu'attend un Excel
/// en configuration française. Aucune bibliothèque XLSX n'est embarquée —
/// l'écart est le même qu'en PA-111.
///
/// ## Les colonnes sans source partent VIDES, jamais à zéro
///
/// Le maître exporte « Acompte » et « Reste dû » sur les contrats. Ni l'un ni
/// l'autre n'a de colonne au schéma (PA-50). Une case vide dit « on ne sait
/// pas » ; un `0` dirait « soldé », et c'est sur ce fichier qu'on décide de
/// relancer un client.
final class EtatVehicules {
  const EtatVehicules({
    required this.titre,
    required this.periode,
    required this.entetes,
    required this.lignes,
    this.mentions = const [],
  });

  /// Le titre du maître pour cet onglet.
  final String titre;

  /// « Du … au … » ou « Toutes périodes » — la formulation du maître
  /// (`m8-locations.js` l.408).
  final String periode;

  final List<String> entetes;

  /// Une valeur `null` s'écrit **vide**, jamais « 0 » ni « — » : dans un
  /// tableur, un tiret casse le typage de la colonne.
  final List<List<String?>> lignes;

  /// Ce que ce document ne peut pas porter, écrit **dans le fichier**.
  ///
  /// Une mention qui borne la portée d'un document s'imprime avec lui
  /// (PA-135) : l'afficher à l'écran sans l'écrire laisserait le fichier
  /// circuler comme pièce complète.
  final List<String> mentions;

  bool get vide => lignes.isEmpty;

  String csv() {
    final tampon = StringBuffer('\u{FEFF}')
      ..writeln('${_e(titre)};${_e(periode)}')
      ..writeln();

    for (final m in mentions) {
      tampon.writeln(_e(m));
    }
    if (mentions.isNotEmpty) tampon.writeln();

    tampon.writeln(entetes.map(_e).join(';'));

    for (final ligne in lignes) {
      tampon.writeln(ligne.map((c) => _e(c ?? '')).join(';'));
    }

    return tampon.toString();
  }

  List<int> csvOctets() => utf8.encode(csv());

  static String _e(String v) => v.replaceAll(';', ',').replaceAll('\n', ' ');
}
