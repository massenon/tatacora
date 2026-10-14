/// L'archivage d'un fournisseur — réplique de `Achats::confirmerArchivageFournisseur`
/// (le lot composé) et de `archiverFournisseurs` (l'exécution), M7, D63.
library;

/// Le lot que la modale de confirmation présente — `composerLotArchivage` du
/// serveur (`AutoriseArchivage`).
///
/// Trois états, et le premier est celui qui compte : **BLOQUÉ** (rien n'est
/// archivable : le bouton de confirmation DISPARAÎT), **PARTIEL** (une partie
/// part, l'écran annonce combien resteront), **NOMINAL**.
///
/// ⚠ Les motifs datent de l'OUVERTURE. Ils ne protègent rien : le verrou qui
/// tranche est celui que l'exécution recontrôle au moment d'agir (un engagement
/// peut naître entre l'ouverture et le clic).
final class LotArchivage {
  const LotArchivage({
    required this.ids,
    required this.motifs,
    required this.conserves,
    required this.bloque,
    required this.libelle,
  });

  /// Les fournisseurs qui partiront, dans l'ordre de la raison sociale.
  final List<String> ids;

  /// Un motif par fournisseur engagé : « [nom] — [verrou] ».
  final List<String> motifs;

  /// Combien resteront (engagés ailleurs).
  final int conserves;

  /// Vrai quand RIEN n'est archivable — y compris quand la sélection ne porte
  /// que des fiches DÉJÀ archivées (le serveur ouvre alors la modale bloquée,
  /// sans motif : il ne retourne pas, D271).
  final bool bloque;

  /// Le nom de l'élément quand le lot visé n'en compte qu'un, sinon vide.
  final String libelle;

  /// La question de la modale : le nom si le lot en compte un, sinon le NOMBRE de
  /// fournisseurs qui PARTENT (`count($fournisseursAArchiver)`, jamais le total
  /// sélectionné).
  String? get element => libelle.isEmpty ? null : libelle;
  int? get nombre => libelle.isEmpty ? ids.length : null;
}

/// Ce que l'exécution rend : combien ont été archivés, et le dernier refus d'un
/// fournisseur devenu engagé entre l'ouverture et le clic.
///
/// Les deux coexistent (`archiverFournisseurs`) : un refus n'empêche PAS les
/// autres archivages du lot — perdre le lot entier pour une ligne devenue
/// engagée serait le refus d'opération de PA-65 appliqué à l'envers.
final class ResultatArchivage {
  const ResultatArchivage({required this.archives, required this.refus});

  final int archives;

  /// Le dernier refus (`addError('archivage', …)` : le dernier écrit gagne).
  final String? refus;
}
