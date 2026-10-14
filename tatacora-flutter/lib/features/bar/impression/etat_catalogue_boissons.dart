import 'dart:convert';

import '../domain/entities/boisson.dart';

/// L'export du **catalogue des boissons** — la modale « Exporter » du moteur
/// CRUD (`crud-ui.js` l.142-160), remplie par `colonnesExport` de
/// `m5-bar.html` l.113-118.
///
/// ## Les quatre colonnes du maître sont écrites, et la quatrième est CALCULÉE
///
/// `m5-bar.html` déclare `nom, categorie, prix, stock_disponible`. Les quatre
/// partent au fichier — mais la quatrième ne vient pas d'une saisie : elle est
/// calculée par `StockTheoriqueService` et rendue en lecture seule
/// (`BoissonResource`, PA-24). C'est la différence avec M4, où deux colonnes
/// annoncées n'existaient nulle part et ont dû être retirées.
///
/// ## Une case vide et un zéro ne disent pas la même chose (Article 7)
///
/// `stock_disponible` vaut `null` quand aucun `PointStockage` de type `bar`
/// n'existe : le serveur ne le sait pas, il ne dit pas que le casier est vide.
/// Le fichier porte alors une **case vide**, jamais `0` — un comptable qui lit
/// `0` conclut « rupture » et commande.
///
/// [colonnes] est la **seule** liste : c'est elle que la modale annonce et
/// c'est elle que le fichier porte. Une seconde liste écrite à la main
/// promettrait un jour une colonne que le fichier ne contient pas.
final class EtatCatalogueBoissons {
  const EtatCatalogueBoissons._();

  /// Les quatre colonnes du maître, avec ses noms.
  static const List<String> colonnes = [
    'nom',
    'categorie',
    'prix',
    'stock_disponible',
  ];

  /// Ce que le maître annonce et que le fichier ne peut pas porter.
  ///
  /// **Vide, et c'est un fait mesuré, pas un oubli** : les quatre colonnes
  /// d'export de `m5-bar.html` ont toutes une source. La liste existe pour que
  /// la modale ait la même forme qu'en M4, et pour que le jour où une colonne
  /// cesserait d'avoir une source, il y ait un endroit où le dire.
  static const List<(String, String)> colonnesAbsentes = <(String, String)>[];

  /// CSV — BOM UTF-8 et point-virgule, convention serveur RG-19.
  ///
  /// Le maître écrit « Le fichier CSV (compatible Excel) » : ici le mot du
  /// maître et le format livré coïncident.
  static String csv(List<Boisson> boissons, {required String filtre}) {
    final tampon = StringBuffer('\u{FEFF}')
      ..writeln('Boissons;${filtre.replaceAll(';', ',')}')
      ..writeln()
      ..writeln(colonnes.join(';'));

    for (final b in boissons) {
      tampon.writeln(
        [
          b.libelle.replaceAll(';', ','),
          // La catégorie brute reste vide si le serveur n'en a rendu aucune :
          // une case vide dit « on ne sait pas ».
          (b.categorieLibelle ?? '').replaceAll(';', ','),
          // Nombres bruts : un tableur ne sait pas additionner « 1 000 FCFA ».
          b.prixVente,
          // `?? ''` et JAMAIS `?? '0'` — voir l'en-tête.
          b.stockDisponible ?? '',
        ].join(';'),
      );
    }

    return tampon.toString();
  }

  static List<int> csvOctets(
    List<Boisson> boissons, {
    required String filtre,
  }) => utf8.encode(csv(boissons, filtre: filtre));
}
