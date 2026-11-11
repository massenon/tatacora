/// Ce qu'un changement de prix de la carte TRACE — réplique de
/// `TraceurHistoriquePrix` (serveur, demande du PO du 01/09/2026 : « on doit
/// retracer les changements de prix »). Pur, sans base.
///
/// ## La règle, dite une fois
///
/// Deux champs sont retracés, dans cet ordre : `prix_vente`, puis
/// `prix_corrige_main` (la marque « le tarif imprimé a été remplacé à la
/// main »). Une trace n'existe QUE parce que la comparaison a dit « différent »,
/// jamais parce qu'une sauvegarde a eu lieu : modifier le seul prix ne trace pas
/// la marque, enregistrer sans rien changer ne trace rien. Un passage de/vers
/// `null` EST un changement ; deux `null` sont identiques.
///
/// Les valeurs sont des chaînes `decimal:2` comme la table du serveur
/// (« 1500.00 ») ; la marque booléenne est portée dans les mêmes colonnes, en
/// « 1.00 » / « 0.00 ». Le franc CFA n'a pas de sous-unité : le prix est un
/// entier de francs, l'écran du serveur ne montrerait de toute façon que des
/// « .00 ».
///
/// ## Confronté au VRAI serveur
///
/// `changement_prix_carte_contre_serveur_test.dart` rejoue des scénarios sur
/// `TraceurHistoriquePrix` lui-même (script `tool/carte/rejouer_historique_prix.php`,
/// en transaction annulée) et compare, trace pour trace.
library;

/// Les deux rayons de la carte, tels que les observateurs du serveur les nomment
/// (`HistoriquePrixCarte::SOURCE_*`).
enum SourceCarte {
  boisson('carte_boisson'),
  plat('plat');

  const SourceCarte(this.code);

  final String code;

  static SourceCarte? depuisCode(String code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

/// Le champ de prix retracé (`HistoriquePrixCarte::CHAMP_*`).
const String champPrixVente = 'prix_vente';
const String champPrixCorrigeMain = 'prix_corrige_main';

/// Les champs retracés, dans l'ordre où ils apparaissent à l'écran.
const List<String> champsDePrixTraces = [champPrixVente, champPrixCorrigeMain];

/// Un changement à tracer : le champ, la valeur d'avant et celle d'après.
final class ChangementPrix {
  const ChangementPrix({
    required this.champ,
    required this.ancien,
    required this.nouveau,
  });

  final String champ;

  /// `decimal:2` en chaîne ; `null` : « pas de valeur ».
  final String? ancien;
  final String? nouveau;

  @override
  bool operator ==(Object other) =>
      other is ChangementPrix &&
      other.champ == champ &&
      other.ancien == ancien &&
      other.nouveau == nouveau;

  @override
  int get hashCode => Object.hash(champ, ancien, nouveau);

  @override
  String toString() => 'ChangementPrix($champ: $ancien -> $nouveau)';
}

/// Un montant en francs entiers, dit comme la table du serveur.
String decimal2DeFrancs(int francs) => '$francs.00';

/// La marque booléenne, dite comme la table du serveur.
String decimal2DeMarque(bool marque) => marque ? '1.00' : '0.00';

/// Les changements à tracer entre l'état [avant] et l'état [apres] d'un article
/// de la carte. Vide : rien n'a changé du côté du prix.
///
/// [prixAvant] / [prixApres] : francs entiers. [corrigeAvant] / [corrigeApres] :
/// la marque « corrigé à la main » ; `null` des deux côtés pour un article qui
/// ne la porte pas (les boissons du poste n'ont pas cette colonne).
List<ChangementPrix> changementsDePrix({
  required int? prixAvant,
  required int? prixApres,
  bool? corrigeAvant,
  bool? corrigeApres,
}) {
  final valeurs = <String, (String?, String?)>{
    champPrixVente: (
      prixAvant == null ? null : decimal2DeFrancs(prixAvant),
      prixApres == null ? null : decimal2DeFrancs(prixApres),
    ),
    champPrixCorrigeMain: (
      corrigeAvant == null ? null : decimal2DeMarque(corrigeAvant),
      corrigeApres == null ? null : decimal2DeMarque(corrigeApres),
    ),
  };
  return [
    for (final champ in champsDePrixTraces)
      if (valeurs[champ]!.$1 != valeurs[champ]!.$2)
        ChangementPrix(
          champ: champ,
          ancien: valeurs[champ]!.$1,
          nouveau: valeurs[champ]!.$2,
        ),
  ];
}
