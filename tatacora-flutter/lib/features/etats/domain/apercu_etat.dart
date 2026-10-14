/// L'aperçu d'un état — ce que `EtatInterface::calculer([])` rend au serveur,
/// composé ici sur la base du poste.
///
/// @see EF-M14-02 Bibliothèque d'états standards par module
/// @see EF-M14-03 Génération à la demande
/// @see RG-19 Moteur d'états
///
/// ## Un résultat, jamais un document
///
/// `EtatResultat` du serveur porte quatre choses : des indicateurs, des
/// en-têtes, des lignes, les filtres appliqués. L'aperçu de la vue
/// (`studio.blade.php` l.133-203) n'en affiche que les trois premières, plus le
/// titre, la période et le nombre de lignes. Rien ici ne compose d'en-tête de
/// rapport, ne choisit de format, n'archive : c'est le rôle de
/// `GenerateurEtatService`, et ce poste n'a ni ce moteur ni de document à
/// remettre (PA-192, non tranché).
///
/// ## Les cellules sont du TEXTE, comme au serveur
///
/// La vue écrit `{{ $cellule }}` : une chaîne. Un montant s'y lit `12500.00`
/// (deux décimales, sans séparateur), une date `09/10/2026`. Les reproduire
/// tels quels est ce qui rend l'aperçu comparable à celui de la PWA ; un
/// montant formaté « 12 500 FCFA » serait une autre présentation que personne
/// n'a demandée.
///
/// Une cellule VIDE se rend « — » (`MontantFcfa::TIRET`, vue l.168) : c'est le
/// seul mot du tiret, et il dit « pas de valeur », jamais « zéro ».
library;

/// Un indicateur de l'en-tête d'aperçu : un libellé et une valeur, en texte.
final class IndicateurApercu {
  const IndicateurApercu(this.libelle, this.valeur);

  final String libelle;
  final String valeur;

  @override
  String toString() => '$libelle = $valeur';
}

/// Le tiret de la vue pour une cellule vide.
const String tiretApercu = '—';

/// Un état calculé sur le poste.
final class ApercuEtat {
  const ApercuEtat({
    required this.code,
    required this.titre,
    required this.periode,
    required this.moduleSource,
    required this.indicateurs,
    required this.entetes,
    required this.lignes,
    this.mentions = const <String>[],
  });

  /// Le code du registre fermé.
  final String code;

  final String titre;

  /// La phrase de période (`EtatInterface::periode`).
  final String periode;

  /// Le code du module source (`M6`…), celui qui porte le droit.
  final String moduleSource;

  final List<IndicateurApercu> indicateurs;
  final List<String> entetes;
  final List<List<String>> lignes;

  /// Ce que cet aperçu NE MESURE PAS sur ce poste, une phrase par élément.
  ///
  /// Le serveur n'en a pas : il calcule tout. Ici, un indicateur ou une
  /// colonne dont la source manque rend « — », et la phrase qui dit pourquoi
  /// est portée par l'aperçu lui-même — elle est ainsi testable, imprimable
  /// plus tard, et ne vieillit pas dans un coin d'écran.
  final List<String> mentions;

  int get nombreLignes => lignes.length;
  bool get estVide => lignes.isEmpty;

  /// La valeur d'un indicateur par son libellé, ou `null`.
  String? indicateur(String libelle) {
    for (final i in indicateurs) {
      if (i.libelle == libelle) return i.valeur;
    }
    return null;
  }
}

/// Ce que l'aperçu d'un état peut rendre.
///
/// Deux issues : « calculé » et « refusé ». « Injoignable » n'existe pas : le
/// poste ne joint personne, et une issue qu'aucun chemin ne produit est une
/// branche morte (D170).
sealed class ResultatApercu {
  const ResultatApercu();
}

final class ApercuRecu extends ResultatApercu {
  const ApercuRecu(this.apercu);
  final ApercuEtat apercu;
}

/// L'état est listé, mais ce poste ne peut pas le calculer — ou son lecteur
/// n'a pas le droit de lire son module source. [motif] est la raison VRAIE et
/// DATÉE, jamais une phrase générique : « donnée non disponible » ne dit pas
/// ce qui manque.
final class ApercuRefuse extends ResultatApercu {
  const ApercuRefuse({required this.motif, this.titre, this.moduleSource});
  final String motif;

  /// Le titre de l'état refusé, pour que l'en-tête de l'aperçu reste celui de
  /// la vue.
  final String? titre;
  final String? moduleSource;
}

/* ====================================================================== */
/* Formats du serveur                                                      */
/* ====================================================================== */

/// Un montant en francs entiers, écrit comme la colonne `DECIMAL(15,2)` du
/// serveur le rend : `12500.00`.
String montantServeur(int francs) => '$francs.00';

/// `09/10/2026` — `format('d/m/Y')` de PHP.
String dateServeur(DateTime d) =>
    '${_deux(d.day)}/${_deux(d.month)}/${d.year.toString().padLeft(4, '0')}';

/// `09/10/2026 14:03` — `format('d/m/Y H:i')`.
String dateHeureServeur(DateTime d) =>
    '${dateServeur(d)} ${_deux(d.hour)}:${_deux(d.minute)}';

/// `09/10/2026 à 14:03` — `format('d/m/Y à H:i')`, l'instant d'une photographie
/// (« Arrêté au … »).
String instantServeur(DateTime d) =>
    '${dateServeur(d)} à ${_deux(d.hour)}:${_deux(d.minute)}';

/// `2026-10-09` -> `09/10/2026`. Une date illisible est rendue telle quelle :
/// une date devinée serait pire qu'une date mal formatée.
String dateIsoServeur(String iso) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(iso);
  if (m == null) return iso;
  return '${m.group(3)}/${m.group(2)}/${m.group(1)}';
}

String _deux(int n) => n.toString().padLeft(2, '0');
