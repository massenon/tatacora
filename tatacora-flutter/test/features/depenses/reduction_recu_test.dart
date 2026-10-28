@Timeout(Duration(minutes: 3))
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tatacora_flutter/features/depenses/domain/recu_depense.dart';
import 'package:tatacora_flutter/features/depenses/domain/reduction_recu.dart';

import 'support/corpus_recus.dart';

/// La RÉDUCTION d'un reçu trop lourd (PO, 28/10/2026) : une image de plus de
/// 400 Ko est réduite en JPEG, jamais refusée pour son poids. La parité avec le
/// serveur (mêmes constantes, même décision) est dans
/// `depenses_recu_contre_serveur_test.dart`.
void main() {
  RecuAccepte accepte(IssueRecu i) {
    expect(i, isA<RecuAccepte>(), reason: i is RecuRefuse ? i.phrase : '');
    return i as RecuAccepte;
  }

  test('une image de plus de 400 Ko est RÉDUITE en JPEG qui tient dans la '
      'limite — plus de refus pour le poids', () async {
    final lourde = imageLourdePng();
    expect(lourde.length, greaterThan(tailleMaxRecuOctets));

    final r = accepte(await preparerRecu(lourde));

    expect(r.reduit, isTrue);
    expect(r.type, TypeRecu.jpeg);
    expect(r.octets!.length, lessThanOrEqualTo(tailleMaxRecuOctets));
    expect(r.tailleOrigine, lourde.length);
    // C'est bien un JPEG lisible, et la porte de dépôt du serveur l'accepte.
    expect(typeRecuDepuisOctets(r.octets!), TypeRecu.jpeg);
    expect(verifierRecu(r.octets!), isA<RecuAccepte>());
    final lu = img.decodeJpg(r.octets!)!;
    expect(lu.width / lu.height, closeTo(1200 / 800, 0.02));
  });

  test('le grand côté est ramené à 2048 px, proportions gardées', () async {
    final r = accepte(await preparerRecu(imageLisseLourdePng()));

    final lu = img.decodeJpg(r.octets!)!;
    expect(r.reduit, isTrue);
    expect(lu.width, coteMaxRecuPx);
    expect(lu.height, (2000 * coteMaxRecuPx / 3000).round());
    expect(r.octets!.length, lessThanOrEqualTo(tailleMaxRecuOctets));
  });

  test('un fichier de 400 Ko ou moins est GARDÉ tel quel : mêmes octets, même '
      'type', () async {
    final png = octetsPng();
    final r = accepte(await preparerRecu(png));
    expect(r.reduit, isFalse);
    expect(r.octets, png);
    expect(r.type, TypeRecu.png);

    // Pile à la borne : gardé ; l'image PNG complétée de zéros reste une image.
    final borne = complete(octetsPng(), tailleMaxRecuOctets);
    final b = accepte(await preparerRecu(borne));
    expect(b.reduit, isFalse);
    expect(b.octets!.length, tailleMaxRecuOctets);
  });

  test(
    'un octet de plus que la borne : RÉDUIT au lieu d’être refusé (ce '
    'cas était le refus « ne peut pas peser plus de 400 kilo-octets »)',
    () async {
      final r = accepte(
        await preparerRecu(complete(octetsPng(), tailleMaxRecuOctets + 1)),
      );
      expect(r.reduit, isTrue);
      expect(r.type, TypeRecu.jpeg);
      expect(r.octets!.length, lessThanOrEqualTo(tailleMaxRecuOctets));
    },
  );

  test('une image transparente est posée sur fond BLANC', () async {
    final image = img.Image(width: 1400, height: 1400, numChannels: 4);
    for (final p in image) {
      if (p.x < 700) {
        p
          ..r = (p.x * 7 + p.y * 13) % 256
          ..g = (p.x * 11 + p.y * 3) % 256
          ..b = (p.x * 5 + p.y * 17) % 256
          ..a = 255;
      } else {
        p
          ..r = 0
          ..g = 0
          ..b = 0
          ..a = 0;
      }
    }
    final png = img.encodePng(image, level: 0);
    expect(png.length, greaterThan(tailleMaxRecuOctets));

    final r = accepte(await preparerRecu(png));
    final lu = img.decodeJpg(r.octets!)!;
    final p = lu.getPixel((lu.width * 0.9).round(), lu.height ~/ 2);
    expect(p.r, greaterThan(240));
    expect(p.g, greaterThan(240));
    expect(p.b, greaterThan(240));
  });

  test('l’orientation EXIF est appliquée : une photo « couchée » ressort '
      'debout', () async {
    final image = img.Image(width: 1200, height: 800);
    var n = 0;
    for (final p in image) {
      n = (n * 1103515245 + 12345) & 0x7fffffff;
      p
        ..r = n % 256
        ..g = (n >> 8) % 256
        ..b = (n >> 16) % 256;
    }
    image.exif.imageIfd.orientation = 6;
    final jpeg = img.encodeJpg(image, quality: 100);
    expect(jpeg.length, greaterThan(tailleMaxRecuOctets));

    final r = accepte(await preparerRecu(jpeg));
    final lu = img.decodeJpg(r.octets!)!;
    expect(lu.height, greaterThan(lu.width), reason: 'portrait après rotation');
  });

  test('un fichier vide, ou qui n’est pas une image, reste refusé avec la '
      'phrase du web — même lourd', () async {
    expect(
      (await preparerRecu(const <int>[]) as RecuRefuse).phrase,
      TextesRecu.vide,
    );
    expect(
      (await preparerRecu(Uint8List(900 * 1024)..fillRange(0, 900, 65))
              as RecuRefuse)
          .phrase,
      TextesRecu.nonImage,
    );
  });

  test('une image lourde qu’on ne sait pas lire est refusée « illisible » '
      '— le seul refus qui reste pour une image', () async {
    final png = imageLourdePng();
    // Signature et IHDR intacts, corps remplacé par du vide : finfo dit « image »,
    // aucun décodeur ne la lit.
    final abimee = Uint8List.fromList(png)
      ..fillRange(100, png.length, 0)
      ..setRange(0, 100, png.sublist(0, 100));
    final r = await preparerRecu(abimee);
    expect(r, isA<RecuRefuse>());
    expect((r as RecuRefuse).phrase, TextesRecu.illisible);
  });

  test('vide ET type ET poids : les phrases du web, ordre de Laravel', () {
    // La porte de DÉPÔT (verifierRecu) garde sa borne : c'est la phrase du
    // serveur à un dépôt hors limite (413).
    expect(
      (verifierRecu(complete(octetsPng(), tailleMaxRecuOctets + 1))
              as RecuRefuse)
          .phrase,
      TextesRecu.tropLourd,
    );
  });
}
