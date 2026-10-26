/// QUI écrit, et DEPUIS QUEL POSTE — le contexte que les écrivains de la base
/// consignent avec ce qu'ils écrivent (schéma v38, 26/10/2026).
///
/// ## Pourquoi ce n'est pas un paramètre de chaque écrivain
///
/// La file d'envoi (`OperationsSyncDao.enfiler`) est appelée par des dizaines
/// d'écrivains métier, dont certains reçoivent l'identifiant du compte et
/// d'autres non (le catalogue du bar, par exemple). Leur ajouter à tous un
/// paramètre « login » aurait fait ce que la décision du 15/10/2026 veut
/// éviter : autant de façons d'oublier. Le contexte vit donc sur la base, posé
/// UNE fois par le fournisseur de la base (`baseLocaleProvider`) et relu à
/// l'instant de l'écriture — `login` est celui du compte CONNECTÉ à cet
/// instant, jamais un compte « système » inventé.
///
/// ## Ce que « poste » veut dire
///
/// Le NOM de la machine (`Platform.localHostname`). La vue du serveur affiche
/// ici l'adresse réseau de l'appelant (`adresse_poste`) : un poste de comptoir
/// n'a pas d'adresse stable, son nom l'est. L'écart est dit au journal d'audit.
///
/// `null` : l'auteur est inconnu (mode démonstration, test, écriture d'avant la
/// v38) — l'écran dit « — », il n'invente rien.
library;

import 'dart:io';

/// L'auteur d'une écriture : le login du compte connecté et le nom du poste.
typedef AuteurEcriture = ({String? login, String? poste});

/// Personne n'est connu.
const AuteurEcriture aucunAuteurEcriture = (login: null, poste: null);

/// Le nom de la machine, ou `null` si le système ne le donne pas. Jamais une
/// chaîne vide : un nom vide se lirait comme un nom.
String? nomDuPosteLocal() {
  try {
    final nom = Platform.localHostname.trim();
    return nom.isEmpty ? null : nom;
  } on Object {
    return null;
  }
}
