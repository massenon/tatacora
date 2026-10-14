/// RG-18 — la détection de doublon du référentiel client.
///
/// ## Le maître en fait un AVERTISSEMENT, jamais un blocage
///
/// `prototype_v2/pages/m3-clients-creances.js` l.44-48 l'écrit lui-même :
/// *« la détection est un avertissement, pas un blocage. Deux clients
/// homonymes existent réellement — bloquer la saisie obligerait l'utilisateur
/// à inventer un nom faux, ce qui est pire. »* Au Gîte, deux « KORA Jean »
/// peuvent se présenter le même mois ; refuser le second ferait saisir
/// « KORA Jean 2 », et le référentiel unique que RG-18 protège serait perdu
/// par le geste censé le protéger.
///
/// ## Deux critères, et le second porte un seuil
///
/// `m3-clients-creances.js` l.49-57 : le **nom normalisé** identique, ou le
/// **téléphone** identique une fois les non-chiffres retirés. Le seuil de huit
/// chiffres est celui du maître, et il n'est pas décoratif : un numéro partiel
/// — « 01 90 » tapé puis abandonné — correspondrait à tout le référentiel, et
/// l'avertissement s'afficherait en permanence jusqu'à ce qu'on cesse de le
/// lire.
library;

import 'entities/client.dart';

/// La clé de comparaison d'un nom — `m3-clients-creances.js` l.37-41.
///
/// Le maître replie les accents par `normalize('NFD')`, que Dart n'expose pas.
/// Le repli est donc écrit ici, lettre par lettre, pour le français et pour
/// lui seul : une table explicite se relit, là où une bibliothèque de plus
/// serait un poids embarqué sur un poste de comptoir.
String cleDeNom(String? nom) {
  const accents = {
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'á': 'a',
    'ã': 'a',
    'å': 'a',
    'ç': 'c',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'ì': 'i',
    'í': 'i',
    'î': 'i',
    'ï': 'i',
    'ñ': 'n',
    'ò': 'o',
    'ó': 'o',
    'ô': 'o',
    'ö': 'o',
    'õ': 'o',
    'ù': 'u',
    'ú': 'u',
    'û': 'u',
    'ü': 'u',
    'ý': 'y',
    'ÿ': 'y',
    'œ': 'oe',
    'æ': 'ae',
  };
  final tampon = StringBuffer();
  for (final c in (nom ?? '').toLowerCase().split('')) {
    final replie = accents[c] ?? c;
    for (final u in replie.split('')) {
      final code = u.codeUnitAt(0);
      final estMinuscule = code >= 0x61 && code <= 0x7A;
      final estChiffre = code >= 0x30 && code <= 0x39;
      if (estMinuscule || estChiffre) tampon.write(u);
    }
  }
  return tampon.toString();
}

/// Les chiffres d'un numéro — `m3-clients-creances.js` l.51.
String chiffresDe(String? telephone) {
  final tampon = StringBuffer();
  for (final c in (telephone ?? '').split('')) {
    final code = c.codeUnitAt(0);
    if (code >= 0x30 && code <= 0x39) tampon.write(c);
  }
  return tampon.toString();
}

/// Le seuil du maître — `m3-clients-creances.js` l.54.
const int chiffresMinimumPourRapprocherUnNumero = 8;

/// Les clients existants qui pourraient être celui qu'on est en train de
/// saisir. Fonction **pure** : la règle ne vit pas dans le widget.
List<Client> doublonsPotentiels({
  required List<Client> referentiel,
  required String nom,
  required String telephone,
}) {
  final cle = cleDeNom(nom);
  final chiffres = chiffresDe(telephone);
  return [
    for (final c in referentiel)
      if ((cle.isNotEmpty && cleDeNom(c.nom) == cle) ||
          (chiffres.length >= chiffresMinimumPourRapprocherUnNumero &&
              chiffresDe(c.telephone) == chiffres))
        c,
  ];
}
