/// Un nombre frappé au clavier, **validé sans jamais être converti**.
///
/// ## Pourquoi pas `double.tryParse`
///
/// Convertir « 12.35 » en `double` puis le réafficher le réarrondirait, et
/// l'écran dirait un autre chiffre que celui qui est écrit dans
/// `mouvements_stock_local` — celui-là même qui sert ensuite à justifier un écart
/// d'inventaire. La règle du projet est que les quantités et les montants
/// restent des **chaînes** de la frappe au corps de la requête (PA-134).
///
/// Ce fichier ne fait donc que **reconnaître une forme** et **normaliser le
/// séparateur décimal**. Aucun chiffre n'est ajouté, retiré ni arrondi : la
/// virgule devient un point, un point de plus, rien d'autre.
///
/// ## La virgule n'est pas un détail
///
/// Au Gîte on tape « 12,5 ». Sans normalisation, la lecture refuserait une
/// chaîne que l'écran vient d'accepter, sur une saisie qui paraît juste. La
/// refuser serait pire : elle est correcte en français.
library;

/// La forme acceptée : un entier, éventuellement suivi d'une partie décimale
/// d'**au plus deux chiffres**.
///
/// Deux décimales et non quatre : `quantite` et `seuil_alerte` sont des
/// centièmes (`DECIMAL(10,2)` au serveur, dont ce poste reprend les échelles).
/// Accepter davantage ici ferait refuser plus loin une saisie que l'écran vient
/// d'accepter — l'utilisateur corrigerait au hasard.
final _forme = RegExp(r'^\d+([.,]\d{1,2})?$');

/// Même forme, mais jusqu'à **quatre** décimales : `cout_unitaire` est posé
/// `decimal:0,4`, parce qu'un coût moyen pondéré se calcule plus finement que
/// le franc pour ne pas dériver sur un cumul de réceptions.
final _formeCout = RegExp(r'^\d+([.,]\d{1,4})?$');

/// `null` si [saisie] est une quantité valide, sinon le message à afficher.
///
/// [strictementPositif] distingue les deux règles du serveur : `min:0` sur un
/// seuil d'alerte (zéro est un seuil légitime — « alerter dès la rupture »),
/// `gt:0` sur une quantité de mouvement (zéro n'est pas un mouvement, c'est une
/// saisie inachevée, et l'enregistrer produirait une ligne d'historique qui ne
/// dit rien).
String? erreurNombre(
  String saisie, {
  required bool strictementPositif,
  bool quatreDecimales = false,
}) {
  final texte = saisie.trim();
  if (texte.isEmpty) return 'Ce champ est obligatoire.';

  final forme = quatreDecimales ? _formeCout : _forme;
  if (!forme.hasMatch(texte)) {
    return quatreDecimales
        ? 'Nombre attendu, au plus quatre décimales (ex. 1250 ou 1250,75).'
        : 'Nombre attendu, au plus deux décimales (ex. 12 ou 12,5).';
  }

  if (strictementPositif && _estZero(texte)) {
    // Le message dit POURQUOI : « quantité invalide » renverrait l'utilisateur
    // essayer la même chose.
    return 'Une quantité à zéro n’est pas un mouvement : elle produirait une '
        'ligne d’historique qui ne dit rien.';
  }
  return null;
}

/// La saisie telle qu'elle est lue : virgule remplacée par un point.
///
/// **Aucune conversion numérique.** Les chiffres frappés sont ceux qui partent,
/// dans le même ordre et en même nombre.
String normaliserNombre(String saisie) => saisie.trim().replaceAll(',', '.');

/// Vrai si tous les chiffres de [texte] sont des zéros — « 0 », « 0,00 ».
///
/// Contrôle **textuel**, jamais `double.parse(t) == 0` : c'est la seule façon
/// de ne pas rouvrir la porte à la conversion que ce fichier existe pour
/// éviter.
bool _estZero(String texte) =>
    !texte.split('').any((c) => '123456789'.contains(c));
