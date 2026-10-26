/// Un fichier ZIP « stocké » (sans compression), écrit en pur Dart — 26/10/2026,
/// pour « Télécharger l'archive (ZIP) » de la clôture annuelle.
///
/// ## Pourquoi pas de bibliothèque
///
/// L'archive légale d'une clôture tient en quatre fichiers (CSV, PDF déjà
/// compressé, manifeste) : la compression n'y gagnerait presque rien, et une
/// dépendance de plus à un poste hors ligne n'est pas gratuite. Le format ZIP
/// « stored » est trivial : un en-tête local + les octets par fichier, puis le
/// répertoire central et sa fin. Un test relit le résultat avec le VRAI
/// `ZipArchive` de PHP (le même qui écrit l'archive du serveur).
///
/// Les noms sont en UTF-8 (drapeau « langage », bit 11). La date des fichiers
/// est celle de [le] (jamais `now()` caché : une archive se reproduit à
/// l'identique à date égale), sans secondes impaires (le format DOS compte par
/// deux secondes).
library;

import 'dart:convert';
import 'dart:typed_data';

/// Le CRC-32 (IEEE, polynôme réfléchi 0xEDB88320) de [octets].
int crc32(List<int> octets) {
  var crc = 0xFFFFFFFF;
  for (final b in octets) {
    crc = _table[(crc ^ b) & 0xFF] ^ (crc >> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

final List<int> _table = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

/// Un ZIP contenant [fichiers] (nom → octets), dans l'ordre de la table.
Uint8List zipStocke(Map<String, List<int>> fichiers, {required DateTime le}) {
  final date = _dateDos(le);
  final heure = _heureDos(le);
  final sortie = BytesBuilder();
  final repertoire = BytesBuilder();
  var decalage = 0;

  void u16(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
  void u32(BytesBuilder b, int v) =>
      b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);

  for (final MapEntry(key: nom, value: octets) in fichiers.entries) {
    final nomOctets = utf8.encode(nom);
    final crc = crc32(octets);

    // En-tête local.
    u32(sortie, 0x04034B50);
    u16(sortie, 20); // version nécessaire
    u16(sortie, 0x0800); // nom en UTF-8
    u16(sortie, 0); // méthode : stockée
    u16(sortie, heure);
    u16(sortie, date);
    u32(sortie, crc);
    u32(sortie, octets.length);
    u32(sortie, octets.length);
    u16(sortie, nomOctets.length);
    u16(sortie, 0); // pas de champ supplémentaire
    sortie
      ..add(nomOctets)
      ..add(octets);

    // Entrée du répertoire central.
    u32(repertoire, 0x02014B50);
    u16(repertoire, 20); // version de fabrication
    u16(repertoire, 20); // version nécessaire
    u16(repertoire, 0x0800);
    u16(repertoire, 0);
    u16(repertoire, heure);
    u16(repertoire, date);
    u32(repertoire, crc);
    u32(repertoire, octets.length);
    u32(repertoire, octets.length);
    u16(repertoire, nomOctets.length);
    u16(repertoire, 0); // champ supplémentaire
    u16(repertoire, 0); // commentaire
    u16(repertoire, 0); // disque de départ
    u16(repertoire, 0); // attributs internes
    u32(repertoire, 0); // attributs externes
    u32(repertoire, decalage);
    repertoire.add(nomOctets);

    decalage += 30 + nomOctets.length + octets.length;
  }

  final tailleRepertoire = repertoire.length;
  sortie.add(repertoire.toBytes());
  u32(sortie, 0x06054B50);
  u16(sortie, 0);
  u16(sortie, 0);
  u16(sortie, fichiers.length);
  u16(sortie, fichiers.length);
  u32(sortie, tailleRepertoire);
  u32(sortie, decalage);
  u16(sortie, 0);
  return sortie.toBytes();
}

int _dateDos(DateTime d) {
  final annee = (d.year < 1980 ? 1980 : d.year) - 1980;
  return (annee << 9) | (d.month << 5) | d.day;
}

int _heureDos(DateTime d) => (d.hour << 11) | (d.minute << 5) | (d.second ~/ 2);
