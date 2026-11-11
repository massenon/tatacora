/// FAUX pilote du boîtier CC300, pour s'entraîner et essayer le poste SANS boîtier.
///
///     dart run tool/faux_pilote_boitier.dart [--ifu 0000000000000] [--port 38917] [--mode normal]
///
/// Il imite le contrat du vrai pilote (`eltrade-cc300-driver`, docs/SPEC_FACTURATION_NORMALISEE_MECEF.md §4) :
/// `GET /check`, `GET /info`, `POST /bill`. NIM `ECHANTILLON`, compteurs en mémoire, QR rendu
/// `F;ECHANTILLON;ECHA-NTIL-LON0-FAUX-<n>;<IFU>;<date>` : MANIFESTEMENT factice, sans valeur fiscale.
///
/// Modes (pannes jouées par le vrai pilote) : `normal`, `absent` (503 partout), `vide` (200 avec
/// `qr_code` vide, compteur inchangé), `erreur` (200 avec `qr_code` « E: … »), `perdu` (la facture
/// est enregistrée, compteur avancé, mais la réponse est un corps vide : cas « à vérifier »).
/// N'écoute que sur 127.0.0.1. À arrêter avec Ctrl+C.
library;

import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  String option(String nom, String defaut) {
    final i = args.indexOf('--$nom');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : defaut;
  }

  final ifu = option('ifu', '0000000000000');
  final port = int.parse(option('port', '38917'));
  final mode = option('mode', 'normal');
  var ventes = 0;
  var avoirs = 0;

  final serveur = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln(
    'Faux pilote sur http://127.0.0.1:$port — IFU $ifu — mode $mode',
  );

  String horodatage() {
    final d = DateTime.now();
    String n(int v) => v.toString().padLeft(2, '0');
    return '${d.year}${n(d.month)}${n(d.day)}${n(d.hour)}${n(d.minute)}${n(d.second)}';
  }

  await for (final r in serveur) {
    final rep = r.response..headers.contentType = ContentType.json;
    void envoyer(int statut, String corps) {
      rep.statusCode = statut;
      rep.write(corps);
      rep.close();
    }

    stdout.writeln('${r.method} ${r.uri.path}');
    if (mode == 'absent') {
      envoyer(503, '{"status":"DeviceNotConnected"}');
      continue;
    }
    switch (r.uri.path) {
      case '/check':
        envoyer(200, '{"status":"Ready"}');
      case '/info':
        await Future<void>.delayed(const Duration(seconds: 1));
        envoyer(
          200,
          jsonEncode({
            'NIM': 'ECHANTILLON',
            'IFU': ifu,
            'TIME': DateTime.now().toIso8601String(),
            'COUNTER': '${ventes + avoirs}',
            'SellBillCounter': '$ventes',
            'SettlementBillCounter': '$avoirs',
            'TaxA': '0.00',
            'TaxB': '18.00',
            'TaxC': '0.00',
            'TaxD': '18.00',
            'CompanyName': 'SOCIETE EXEMPLE SARL',
            'LastConnectionToServer': DateTime.now().toIso8601String(),
            'DocumentOnDeviceCount': '${ventes + avoirs}',
            'UploadedDocumentCount': '${ventes + avoirs}',
          }),
        );
      case '/bill':
        final corps = await utf8.decoder.bind(r).join();
        Map<String, Object?> bill;
        try {
          bill = jsonDecode(corps) as Map<String, Object?>;
        } on Object {
          envoyer(400, '{"errors":"[JSON illisible]"}');
          continue;
        }
        if (bill['products'] is! List ||
            bill['payments'] is! List ||
            (bill['vt'] == null && bill['rt'] == null)) {
          envoyer(400, '{"errors":"[Facture non conforme au schema]"}');
          continue;
        }
        if (mode == 'vide') {
          envoyer(200, '{"qr_code":""}');
          continue;
        }
        if (mode == 'erreur') {
          envoyer(200, '{"qr_code":"E: erreur simulee du boitier"}');
          continue;
        }
        final avoir = bill['rt'] != null;
        avoir ? avoirs++ : ventes++;
        if (mode == 'perdu') {
          envoyer(200, '');
          continue;
        }
        final n = avoir ? avoirs : ventes;
        envoyer(
          200,
          jsonEncode({
            'qr_code':
                'F;ECHANTILLON;ECHA-NTIL-LON0-FAUX-${n.toString().padLeft(4, '0')};$ifu;${horodatage()}',
          }),
        );
      default:
        envoyer(404, '{"status":"NotFound"}');
    }
  }
}
