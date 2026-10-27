/// Les fichiers d'essai du reçu de dépense (lot L4) : de VRAIS petits fichiers
/// produits par GD (png, jpeg, gif, bmp, webp), jamais des en-têtes écrits à la main.
library;

import 'dart:convert';
import 'dart:typed_data';

const String _base64Png =
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAAFklEQVQImWM8ISfHwMDAxMDAwMDAAAANBAEIG3S2BgAAAABJRU5ErkJggg==';

const String _base64Jpeg =
    '/9j/4AAQSkZJRgABAQEAYABgAAD//gA7Q1JFQVRPUjogZ2QtanBlZyB2MS4wICh1c2luZyBJSkcgSlBFRyB2ODApLCBxdWFsaXR5ID0gMzAK/9sAQwAbEhQXFBEbFxYXHhwbIChCKyglJShROj0wQmBVZWRfVV1baniZgWpxkHNbXYW1hpCeo6utq2eAvMm6pseZqKuk/9sAQwEcHh4oIyhOKytOpG5dbqSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSk/8AAEQgAAgACAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/aAAwDAQACEQMRAD8Ao0UUVznsH//Z';

const String _base64Gif = 'R0lGODdhAgACAIAAAMweHAAAACwAAAAAAgACAAACAoRRADs=';

const String _base64Bmp =
    'Qk1CAAAAAAAAADYAAAAoAAAAAgAAAAIAAAABABgAAAAAAAwAAAAAAAAAAAAAAAAAAAAAAAAAHh7IHh7IAAAeHsgeHsgAAA==';

const String _base64Webp =
    'UklGRjoAAABXRUJQVlA4IC4AAACwAQCdASoCAAIAAUAmJaACdLoABDAAAP7x3I/4DdfFtMv/vYL/3YL/3YL/WwAA';

Uint8List octetsPng() => base64Decode(_base64Png);
Uint8List octetsJpeg() => base64Decode(_base64Jpeg);
Uint8List octetsGif() => base64Decode(_base64Gif);
Uint8List octetsBmp() => base64Decode(_base64Bmp);
Uint8List octetsWebp() => base64Decode(_base64Webp);

/// [octets] complétés par des zéros jusqu'à [taille] octets (la fin d'un PNG
/// n'est pas relue par un décodeur d'en-tête : le fichier reste une image).
Uint8List complete(Uint8List octets, int taille) {
  final sortie = Uint8List(taille)..setRange(0, octets.length, octets);
  return sortie;
}

/// Les fichiers d'essai NOMMÉS, y compris ceux qui ne sont PAS des images.
Map<String, List<int>> corpusRecus() => {
  'png': octetsPng(),
  'jpeg': octetsJpeg(),
  'gif': octetsGif(),
  'bmp': octetsBmp(),
  'webp': octetsWebp(),
  'texte': utf8.encode('Ceci est un texte, pas une image.\n'),
  'vide': const <int>[],
  'png-signature-seule': const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
  'jpeg-trois-octets': const [0xFF, 0xD8, 0xFF],
  'bm-puis-du-texte': utf8.encode('BM et puis du texte sans en-tete DIB.....'),
  'gif-signature-seule': utf8.encode('GIF89a'),
  'riff-sans-webp': utf8.encode('RIFF\u0000\u0000\u0000\u0000WAVEfmt '),
  'svg': utf8.encode(
    '<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"></svg>',
  ),
  'pdf': utf8.encode('%PDF-1.4\n1 0 obj\n<<>>\nendobj\n'),
  'png-tronque-a-20-octets': octetsPng().sublist(0, 20),
  'png-a-la-borne': complete(octetsPng(), 400 * 1024),
  'png-un-octet-de-trop': complete(octetsPng(), 400 * 1024 + 1),
};
