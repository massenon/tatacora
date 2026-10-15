import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/impression/texte_ticket.dart';
import 'package:tatacora_flutter/features/facturation/impression/essai_qr_thermique.dart';
import 'package:tatacora_flutter/features/facturation/impression/ticket_facture.dart';

/// **La planche d'essai QR — ce qu'un test peut en dire, et ce qu'il ne peut
/// pas.**
///
/// ## Ce que ces tests prouvent
///
/// Que la planche est **au format rouleau**, que chaque carré est **légendé de
/// sa taille**, et surtout que son contenu est **manifestement non fiscal** :
/// aucun numéro de facture, aucun NIM, aucun cachet. Un QR d'apparence
/// officielle sorti d'une imprimante de comptoir finirait agrafé à un
/// document ; le contenu de test est choisi pour qu'un scan révèle
/// immédiatement qu'il ne s'agit de rien.
///
/// ## Ce qu'ils ne prouvent PAS, et c'est tout l'objet de la planche
///
/// **Qu'un QR sorte lisible d'une thermique 80 mm.** C'est une question de
/// papier, d'encre et de résolution de tête d'impression : elle se tranche en
/// imprimant la planche et en la scannant, pas en écrivant une assertion.
void main() {
  test('la planche est composée au format ROULEAU, pas en A4', () async {
    // Une planche composée en A4 sortirait tronquée sur la moitié droite : les
    // tailles imprimées ne seraient plus celles annoncées par les légendes, et
    // l'essai entier ne voudrait plus rien dire.
    final octets = await EssaiQrThermique.composer().pdf();

    expect(formatRouleau80mm.width, closeTo(226.77, 0.1));
    expect(String.fromCharCodes(octets.take(4)), '%PDF');
    expect(octets.length, greaterThan(1000));
  });

  test('chaque carré est légendé de sa taille, en millimètres', () {
    // Sans légende, la planche ne répond à rien : on saurait qu'un carré se
    // scanne, sans pouvoir dire lequel commander.
    final planche = EssaiQrThermique.composer();

    expect(planche.tailles, taillesEssaiQrMm);
    expect(planche.legendes, hasLength(planche.tailles.length));
    for (var i = 0; i < planche.tailles.length; i++) {
      expect(planche.legendes[i], contains('${planche.tailles[i]} mm'));
    }
  });

  test('les tailles sont CROISSANTES et tiennent sur 80 mm de papier', () {
    final planche = EssaiQrThermique.composer();

    for (var i = 1; i < planche.tailles.length; i++) {
      expect(planche.tailles[i], greaterThan(planche.tailles[i - 1]));
    }
    // 80 mm de rouleau, 4 mm de marge de chaque côté : 72 mm utiles. Un carré
    // plus large serait rogné par le pilote, et l'essai conclurait « illisible »
    // sur un défaut de composition plutôt que sur le papier.
    expect(planche.tailles.last, lessThanOrEqualTo(72));
  });

  test('⚠ le contenu encodé est MANIFESTEMENT non fiscal', () {
    // C'est la garde qui compte. Un QR d'apparence officielle sur du papier
    // de caisse serait PA-61 sous forme physique, et le papier ne se rattrape
    // pas.
    final planche = EssaiQrThermique.composer();

    expect(planche.contenus, hasLength(planche.tailles.length));
    for (final contenu in planche.contenus) {
      expect(contenu, startsWith('TATACORA-ESSAI-QR-'));
      expect(contenu, endsWith('mm'));
      for (final interdit in [
        'MECEF',
        'MECeF',
        'NIM',
        'CACHET',
        'FACTURE',
        'F-2026',
      ]) {
        expect(
          contenu.toUpperCase().contains(interdit.toUpperCase()),
          isFalse,
          reason:
              'un scan de « $contenu » ne doit laisser aucun doute : ce '
              'papier n’est pas un document fiscal',
        );
      }
    }
  });

  test(
    'le contenu suit la taille : deux carrés n’encodent pas la même chose',
    () {
      // Un contenu identique partout ferait croire à un scan réussi alors qu'on
      // aurait lu le carré d'à côté — le plus grand, précisément celui qu'on
      // cherche à éviter.
      expect(contenuEssaiQr(10), 'TATACORA-ESSAI-QR-10mm');
      expect(contenuEssaiQr(35), 'TATACORA-ESSAI-QR-35mm');
      expect(EssaiQrThermique.composer().contenus.toSet(), hasLength(6));
    },
  );

  test('la planche DIT ce qu’elle est, en clair, sur le papier', () {
    final planche = EssaiQrThermique.composer();

    expect(planche.texteBrut, contains('ESSAI DE LISIBILITÉ QR'));
    expect(planche.texteBrut, contains('n\'est PAS un document fiscal'));
    expect(planche.texteBrut, contains('aucun cachet'));
    // Et elle porte la consigne : sans elle, la planche revient annotée
    // « ça marche » sans qu'on sache de quelle taille on parle.
    expect(planche.texteBrut, contains('scanner chaque carré'));
  });

  test('aucun caractère de la planche ne sera perdu à l’impression', () {
    final planche = EssaiQrThermique.composer();

    for (final texte in planche.textes) {
      expect(caracteresNonImprimables(texte), isEmpty, reason: texte);
    }
  });

  test('GARDE — le générateur de QR n’accède à AUCUN réseau', () {
    // `package:barcode` (re-exporté par `package:pdf`) ne dépend que de
    // `meta` et `qr`, tous deux purs Dart. Le poste du Gîte encaisse hors
    // connexion : une planche d'essai qui exigerait Internet serait la seule
    // pièce du logiciel à le faire, et on ne s'en apercevrait qu'au Bénin.
    //
    // La garde est lisible plutôt que déclarative : le fichier de
    // composition ne doit importer ni `dart:io`, ni un client HTTP.
    final source = File(
      'lib/features/facturation/impression/essai_qr_thermique.dart',
    ).readAsStringSync();

    expect(source, isNotEmpty);
    for (final interdit in [
      "import 'dart:io'",
      'package:dio',
      'package:http',
      'HttpClient',
    ]) {
      expect(
        source.contains(interdit),
        isFalse,
        reason: '« $interdit » ferait dépendre une impression du réseau',
      );
    }
  });
}
