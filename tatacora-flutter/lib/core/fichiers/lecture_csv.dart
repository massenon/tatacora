/// La lecture d'un CSV choisi par l'utilisateur — UN seul lecteur pour les
/// imports du poste (import d'articles de l'écran Stocks, onglet « Importer
/// les données » de l'écran Import & Export).
///
/// Comme `fgetcsv` / `str_getcsv` du serveur : guillemets, guillemets doublés,
/// séparateur et saut de ligne protégés entre guillemets. Le BOM UTF-8 de tête
/// est retiré (Excel en écrit un, les CSV du poste aussi).
library;

/// Le BOM UTF-8, tel qu'il apparaît en tête d'un texte décodé.
const String bomUtf8 = '\u{FEFF}';

/// Découpe [contenu] en lignes de champs, au séparateur [separateur].
///
/// Une ligne blanche rend `['']` : sa POSITION est conservée pour que les
/// numéros de ligne restent ceux qu'Excel affiche à l'utilisateur.
List<List<String>> lireCsv(String contenu, {String separateur = ';'}) {
  assert(separateur.length == 1, 'un séparateur est un seul caractère');
  var texte = contenu;
  if (texte.startsWith(bomUtf8)) texte = texte.substring(1);

  final lignes = <List<String>>[];
  var champs = <String>[];
  final champ = StringBuffer();
  var entreGuillemets = false;
  var i = 0;

  void finirChamp() {
    champs.add(champ.toString());
    champ.clear();
  }

  void finirLigne() {
    finirChamp();
    lignes.add(champs);
    champs = <String>[];
  }

  while (i < texte.length) {
    final c = texte[i];
    if (entreGuillemets) {
      if (c == '"') {
        if (i + 1 < texte.length && texte[i + 1] == '"') {
          champ.write('"');
          i++;
        } else {
          entreGuillemets = false;
        }
      } else {
        champ.write(c);
      }
    } else if (c == '"') {
      entreGuillemets = true;
    } else if (c == separateur) {
      finirChamp();
    } else if (c == '\r') {
      // `\r\n` : le `\n` qui suit ferme la ligne.
      if (!(i + 1 < texte.length && texte[i + 1] == '\n')) finirLigne();
    } else if (c == '\n') {
      finirLigne();
    } else {
      champ.write(c);
    }
    i++;
  }
  if (champ.isNotEmpty || champs.isNotEmpty) finirLigne();
  return lignes;
}

/// Le séparateur d'un CSV : le point-virgule OU la virgule, celui des deux que
/// la PREMIÈRE ligne emploie le plus — à égalité, le point-virgule
/// (`ControleImportService::analyserCsv` du serveur).
String separateurDe(String contenu) {
  var texte = contenu;
  if (texte.startsWith(bomUtf8)) texte = texte.substring(1);
  final fin = texte.indexOf(RegExp('[\r\n]'));
  final premiere = fin < 0 ? texte : texte.substring(0, fin);
  final pointsVirgules = ';'.allMatches(premiere).length;
  final virgules = ','.allMatches(premiere).length;
  return pointsVirgules >= virgules ? ';' : ',';
}
