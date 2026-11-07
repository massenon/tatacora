import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Un FAUX pilote du boîtier CC300 : un vrai serveur HTTP sur la boucle locale
/// (dart:io), qui parle comme `eltrade-cc300-driver` — y compris ses défauts
/// (200 sur un échec, corps vide, `{error_message: …}` non JSON). Les tests du
/// client le confrontent à de vraies requêtes TCP, pas à une simulation de
/// `HttpClient`.
class FauxPilote {
  FauxPilote._(this._serveur);

  final HttpServer _serveur;

  /// Les requêtes reçues, dans l'ordre : `GET /check`, `POST /bill`…
  final List<String> requetes = [];

  /// Les corps des `POST /bill` reçus.
  final List<String> corpsPost = [];

  /// Combien de `POST /bill` sont en cours en même temps, et le maximum vu.
  int enCours = 0;
  int maxEnParallele = 0;

  /// `true` : l'appareil est débranché (503 `DeviceNotConnected`).
  bool appareilAbsent = false;

  /// Les compteurs de `/info`.
  int compteurVentes = 40;
  int compteurAvoirs = 0;

  String nim = 'ED04000623';
  String ifu = '3201910768821';
  String taxeB = '18.00';

  /// Le comportement de `POST /bill` : rend (statut, corps) ou `null` pour ne
  /// jamais répondre (délai), après [delaiPost].
  FutureOr<({int statut, String corps})?> Function(String corps)? surBill;

  Duration delaiPost = Duration.zero;
  Duration delaiInfo = Duration.zero;

  /// `true` : coupe la connexion APRÈS avoir traité le `POST` (réponse perdue).
  bool couperApresTraitement = false;

  /// Un enregistrement dans le boîtier : le compteur avance quand le boîtier a
  /// « facturé », réponse reçue ou non.
  bool incrementerCompteurAuPost = true;

  static Future<FauxPilote> demarrer() async {
    final serveur = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final faux = FauxPilote._(serveur);
    serveur.listen(faux._servir);
    return faux;
  }

  String get racine => 'http://127.0.0.1:${_serveur.port}';

  Future<void> arreter() => _serveur.close(force: true);

  Future<void> _servir(HttpRequest r) async {
    requetes.add('${r.method} ${r.uri.path}');
    final reponse = r.response;
    void ecrire(int statut, String corps) {
      reponse
        ..statusCode = statut
        ..headers.contentType = ContentType.json
        ..write(corps);
    }

    try {
      if (appareilAbsent) {
        await utf8.decoder.bind(r).join();
        ecrire(503, '{"status": "DeviceNotConnected"}');
        await reponse.close();
        return;
      }
      switch (r.uri.path) {
        case '/check':
          ecrire(200, '{"status": "Ready"}');
        case '/info':
          if (delaiInfo > Duration.zero) await Future<void>.delayed(delaiInfo);
          ecrire(
            200,
            jsonEncode({
              'NIM': nim,
              'IFU': ifu,
              'TIME': '2026-11-07 10:00:00 +0100 WAT',
              'COUNTER': '${compteurVentes + compteurAvoirs + 5}',
              'SellBillCounter': '$compteurVentes',
              'SettlementBillCounter': '$compteurAvoirs',
              'TaxA': '0.00',
              'TaxB': taxeB,
              'TaxC': '0.00',
              'TaxD': '18.00',
              'CompanyName': 'GITE CHEZ NOEL',
              'CompanyLocationAddress': 'NATITINGOU',
              'CompanyLocationCity': 'NATITINGOU',
              'CompanyContactPhone': '97355974',
              'CompanyContactEmail': 'contact@exemple.bj',
              'LastConnectionToServer': '2026-11-07 09:55:00 +0100 WAT',
              'DocumentOnDeviceCount': '45',
              'UploadedDocumentCount': '44',
            }),
          );
        case '/bill':
          enCours++;
          if (enCours > maxEnParallele) maxEnParallele = enCours;
          final corps = await utf8.decoder.bind(r).join();
          corpsPost.add(corps);
          try {
            if (delaiPost > Duration.zero) {
              await Future<void>.delayed(delaiPost);
            }
            final repondre = surBill;
            final issue = repondre == null ? null : await repondre(corps);
            if (incrementerCompteurAuPost) {
              final avoir = corps.contains('"rt"');
              if (avoir) {
                compteurAvoirs++;
              } else {
                compteurVentes++;
              }
            }
            if (couperApresTraitement || issue == null) {
              final socket = await reponse.detachSocket(writeHeaders: false);
              socket.destroy();
              return;
            }
            ecrire(issue.statut, issue.corps);
          } finally {
            enCours--;
          }
        default:
          ecrire(404, '{}');
      }
    } on Object {
      // Connexion fermée par le client (délai) : rien à répondre.
    }
    try {
      await reponse.close();
    } on Object {
      // Déjà coupée.
    }
  }
}

/// Le `qr_code` que rend le vrai pilote pour une facture réussie.
String qrDuPilote({
  String nim = 'ED04000623',
  String code = 'NW34NID6ZHANFNMZ2IU7LL3H',
  String ifu = '3201910768821',
  String date = '20261107100000',
}) => 'F;$nim;$code;$ifu;$date';
