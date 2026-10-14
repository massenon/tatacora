/// ⚠ **LE PIÈGE MECeF — la règle vit ici, et nulle part ailleurs.**
///
/// MECeF est **factice** dans tout le dépôt : `MecefClientFake` produit un
/// numéro `MECEF-DEMO-XXXXXXXX` et un cachet qui dit littéralement
/// `DONNEES-NON-CERTIFIEES-DEMO`. L'inscription DGI — **PA-17**, délai annoncé
/// jusqu'à 72 h — n'est pas lancée. **Aucune facture de ce client ne peut donc
/// être certifiée**, et aucune ne doit se déclarer telle.
///
/// ## Pourquoi un fichier entier pour un booléen
///
/// Parce que c'est exactement le défaut **PA-61**, et qu'il a déjà été commis
/// une fois sur ce dépôt. Le badge MECeF de l'écran Paramètres dérivait `active`
/// de la **configuration** — numéro contribuable renseigné, clé d'API présente —
/// alors que le conteneur liait le faux client dans les deux branches de son
/// ternaire. Le jour de l'inscription DGI, c'est-à-dire le jour où l'on cesse
/// de se méfier, le badge serait passé au vert pendant que chaque facture
/// partait toujours en démonstration.
///
/// **Un indicateur d'état se dérive de ce qui est réellement en place, jamais
/// de ce qui est configuré pour l'être.** Ici, ce qui est « réellement en
/// place » est un **numéro fiscal réel sur la pièce**. Pas une clé de
/// configuration, pas un drapeau, pas une intention — un numéro, et pas un
/// numéro de démonstration.
///
/// ## Divergence constatée avec le serveur, et elle est dans le mauvais sens
///
/// Côté Laravel, `Facture::estCertifiee()` rend `$this->statut === 'certifiee'`.
/// En mode démonstration, `RejouerCertificationsMecefEnEchecJob` fait
/// **exactement** passer une facture à `certifiee` avec un numéro
/// `MECEF-DEMO-…` : `estCertifiee()` y répond donc `true` sur une pièce sans
/// aucune valeur fiscale. Le prédicat qui rattrape la nuance existe —
/// `Facture::estCertificationDemonstration()` — et **n'a aucun appelant hors
/// des tests** ; le filigrane « DOCUMENT DE DÉMONSTRATION » qu'il doit
/// déclencher reste une obligation ouverte du dépôt.
///
/// Ce client ne reproduit pas cette forme : [estReelle] part du numéro, un
/// numéro de démonstration ne compte pas, et le filigrane est **posé sur le
/// ticket** (voir `../impression/ticket_facture.dart`). La divergence est
/// consignée en PA-99 plutôt que corrigée d'un seul côté.
library;

/// La certification fiscale MECeF, telle qu'elle se **constate**.
final class CertificationMecef {
  const CertificationMecef._();

  /// Le libellé affiché tant que la certification n'a pas lieu.
  ///
  /// Il dit ce qui est, et il est repris tel quel à l'écran, sur le ticket et
  /// dans les exports — trois endroits qui doivent dire la même chose, sans
  /// quoi l'un d'eux finira par dire autre chose.
  static const String libelleDemonstration =
      'MECeF — non certifiée, démonstration';

  /// Le filigrane porté par tout document sortant de ce client.
  ///
  /// Obligation ouverte du dépôt, rappelée par PA-61 : une pièce non certifiée
  /// remise à un client doit le dire sur le document lui-même, pas seulement à
  /// l'écran de celui qui l'a émise.
  static const String filigraneDemonstration = 'DOCUMENT DE DÉMONSTRATION';

  /// Marqueurs qui disqualifient un numéro, quel que soit le reste.
  ///
  /// `MECEF-DEMO-` est le préfixe réellement produit par `MecefClientFake`.
  /// `DEMONSTRATION` couvre les variantes saisies à la main. La comparaison est
  /// **insensible à la casse**, comme la vérification du prototype.
  static const List<String> marqueursDemonstration = [
    'DEMO',
    'DEMONSTRATION',
    'NON-CERTIFIE',
    'NON-CERTIFIEE',
  ];

  /// La pièce porte-t-elle une certification fiscale **réelle** ?
  ///
  /// Deux conditions, et aucune n'est facultative :
  ///
  ///  1. un numéro fiscal **existe** — pas une intention, pas une clé de
  ///     configuration, pas un statut ;
  ///  2. ce numéro **n'est pas un numéro de démonstration**.
  ///
  /// Retirer la seconde suffirait à faire passer au vert toutes les factures du
  /// jour où le faux client commence à renseigner un numéro : c'est PA-61 mot
  /// pour mot.
  static bool estReelle(String? numeroMecef) {
    final n = numeroMecef?.trim();
    if (n == null || n.isEmpty) return false;

    final majuscules = n.toUpperCase();
    for (final marqueur in marqueursDemonstration) {
      if (majuscules.contains(marqueur)) return false;
    }
    return true;
  }

  /// Le libellé de certification d'une pièce — jamais « certifiée » par défaut.
  static String libelle(String? numeroMecef) =>
      estReelle(numeroMecef) ? 'MECeF $numeroMecef' : libelleDemonstration;
}
