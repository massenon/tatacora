/// La MENTION client d'une vente au comptoir — « Client (facultatif) : Nom à
/// imprimer sur le ticket » (directive du PO du 02/09/2026).
///
/// Un texte libre, jamais une fiche client : il est posé sur le panier ouvert
/// (`paniers_local.client_nom`), recopié sur la vente à la clôture, imprimé sur
/// le ticket (« Client : … ») et envoyé au serveur dans la charge de la vente
/// (`client_nom`, conservé en `ventes.client_mention`). Le panier abandonné ou
/// annulé l'emporte avec lui.
///
/// ## La règle, telle que le serveur l'applique
///
/// Réplique exacte de `VenteService::normaliserMentionClient` (confrontée à
/// ce code par `mention_client_contre_serveur_test`) :
///
/// * chaque caractère de CONTRÔLE (C0, DEL, C1 : saut de ligne, tabulation,
///   octet de commande…) devient une espace : il casserait le ticket thermique ;
/// * les espaces de bord tombent ;
/// * au plus [longueurMax] caractères (la colonne du serveur) — comptés en
///   points de code, comme MySQL en `utf8mb4` ;
/// * le vide devient `null` : « aucune mention » et « mention vide » ne se
///   distinguent pas.
library;

/// Voir la bibliothèque.
abstract final class MentionClient {
  /// `ventes.client_mention` est une `string` de 255 caractères.
  static const int longueurMax = 255;

  static final RegExp _controles = RegExp(r'[\u0000-\u001F\u007F-\u009F]');
  static final RegExp _espacesDeBord = RegExp(r'^ +| +$');

  /// La mention à conserver pour la saisie [brut], ou `null` s'il n'y en a pas.
  static String? normaliser(String? brut) {
    if (brut == null) return null;
    var texte = brut.replaceAll(_controles, ' ').replaceAll(_espacesDeBord, '');
    if (texte.runes.length > longueurMax) {
      texte = String.fromCharCodes(texte.runes.take(longueurMax));
    }
    texte = texte.replaceAll(_espacesDeBord, '');
    return texte.isEmpty ? null : texte;
  }
}
