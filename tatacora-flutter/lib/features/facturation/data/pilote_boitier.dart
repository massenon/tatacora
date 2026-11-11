import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/erreur_boitier.dart';

/// Ce que `GET /info` rend — les champs lus, tous en chaînes comme le pilote
/// les écrit (`cmd/app.go`, `DeviceInfo`).
final class InfoBoitier {
  const InfoBoitier({
    required this.nim,
    required this.ifu,
    required this.time,
    required this.counter,
    required this.sellBillCounter,
    required this.settlementBillCounter,
    required this.tauxA,
    required this.tauxB,
    required this.tauxC,
    required this.tauxD,
    required this.nomEntreprise,
    required this.derniereConnexionDgi,
    required this.documentsSurLAppareil,
    required this.documentsTransmis,
  });

  final String nim;
  final String ifu;
  final String time;
  final String counter;
  final String sellBillCounter;
  final String settlementBillCounter;
  final String tauxA;
  final String tauxB;
  final String tauxC;
  final String tauxD;
  final String nomEntreprise;
  final String derniereConnexionDgi;
  final String documentsSurLAppareil;
  final String documentsTransmis;

  /// Le compteur des ventes (entier), `null` s'il n'est pas lisible.
  int? get compteurVentes => int.tryParse(sellBillCounter.trim());

  /// Le compteur des avoirs (entier), `null` s'il n'est pas lisible.
  int? get compteurAvoirs => int.tryParse(settlementBillCounter.trim());

  /// Les phrases de « Tester le boîtier ».
  String get resume =>
      'Boîtier prêt — NIM $nim, IFU $ifu, taux A $tauxA %, B $tauxB %, '
      'C $tauxC %, D $tauxD %. Dernière connexion à la DGI : '
      '${derniereConnexionDgi.isEmpty ? 'inconnue' : derniereConnexionDgi}. '
      'Documents sur le boîtier : $documentsSurLAppareil, transmis : '
      '$documentsTransmis.';
}

/// La réponse brute d'un `POST /bill` qui a reçu une réponse HTTP.
final class ReponsePost {
  const ReponsePost(this.statut, this.corps);

  final int statut;
  final String corps;
}

/// L'issue d'un `POST /bill`.
sealed class IssuePost {
  const IssuePost();
}

/// Le pilote a répondu (200 même en cas d'échec : le corps se VALIDE).
final class PostRepondu extends IssuePost {
  const PostRepondu(this.reponse);
  final ReponsePost reponse;
}

/// Rien n'est parti : la connexion n'a pas pu s'ouvrir. Le boîtier n'a rien reçu,
/// l'essai peut être rejoué sans risque.
final class PostNonEnvoye extends IssuePost {
  const PostNonEnvoye(this.cause);
  final ErreurBoitier cause;
}

/// La requête est partie, la réponse n'est pas revenue (délai, coupure) : le
/// boîtier a PEUT-ÊTRE enregistré la facture — le compteur tranche.
final class PostIncertain extends IssuePost {
  const PostIncertain(this.cause);
  final ErreurBoitier cause;
}

/// Le pilote du boîtier CC300 (`eltrade-cc300-driver`) : trois appels HTTP, et
/// rien d'autre. Sans authentification : il n'appelle QUE [racine].
class PiloteBoitier {
  PiloteBoitier({
    required this.racine,
    this.delaiConnexion = const Duration(seconds: 3),
    this.delaiVerification = const Duration(seconds: 5),
    this.delaiInfo = const Duration(seconds: 20),
    this.delaiEnvoi = const Duration(seconds: 30),
    HttpClient Function()? fabrique,
  }) : _fabrique = fabrique ?? HttpClient.new;

  /// `http://hote:port`, sans barre finale (déjà validée).
  final String racine;
  final Duration delaiConnexion;
  final Duration delaiVerification;

  /// `GET /info` dure environ 4 s.
  final Duration delaiInfo;

  /// `POST /bill` dure plusieurs secondes : 30 s.
  final Duration delaiEnvoi;
  final HttpClient Function() _fabrique;

  Uri _uri(String chemin) => Uri.parse('$racine$chemin');

  /// `GET /check` : 200 `{"status":"Ready"}` ; 503 `DeviceNotConnected`.
  Future<void> verifier() async {
    final r = await _get('/check', delaiVerification);
    if (r.statut == 503) {
      throw const ErreurBoitier(
        CauseBoitier.appareilAbsent,
        TextesBoitier.appareilAbsent,
      );
    }
    final json = _objet(r.corps);
    if (r.statut != 200 || json?['status'] != 'Ready') {
      throw const ErreurBoitier(
        CauseBoitier.reponseInvalide,
        'Le pilote a répondu autre chose que « prêt » : vérifiez l’adresse du '
        'pilote.',
      );
    }
  }

  /// `GET /info` (environ 4 s). 503 : appareil absent. Un corps qui n'est pas
  /// du JSON complet est une erreur (le pilote écrit 200 PUIS son message
  /// d'erreur).
  Future<InfoBoitier> info() async {
    final r = await _get('/info', delaiInfo);
    if (r.statut == 503) {
      throw const ErreurBoitier(
        CauseBoitier.appareilAbsent,
        TextesBoitier.appareilAbsent,
      );
    }
    final json = _objet(r.corps);
    String champ(String nom) => '${json?[nom] ?? ''}'.trim();
    if (r.statut != 200 || json == null || champ('NIM').isEmpty) {
      throw const ErreurBoitier(
        CauseBoitier.reponseInvalide,
        'Le boîtier n’a pas renvoyé ses informations : vérifiez qu’il est '
        'branché et réessayez.',
      );
    }
    return InfoBoitier(
      nim: champ('NIM'),
      ifu: champ('IFU'),
      time: champ('TIME'),
      counter: champ('COUNTER'),
      sellBillCounter: champ('SellBillCounter'),
      settlementBillCounter: champ('SettlementBillCounter'),
      tauxA: champ('TaxA'),
      tauxB: champ('TaxB'),
      tauxC: champ('TaxC'),
      tauxD: champ('TaxD'),
      nomEntreprise: champ('CompanyName'),
      derniereConnexionDgi: champ('LastConnectionToServer'),
      documentsSurLAppareil: champ('DocumentOnDeviceCount'),
      documentsTransmis: champ('UploadedDocumentCount'),
    );
  }

  /// `POST /bill`. Distingue « rien n'est parti » de « parti, réponse perdue ».
  Future<IssuePost> poster(String json) async {
    final client = _fabrique()..connectionTimeout = delaiConnexion;
    final HttpClientRequest requete;
    try {
      requete = await client.postUrl(_uri('/bill')).timeout(delaiConnexion);
    } on Object catch (e) {
      client.close(force: true);
      return PostNonEnvoye(_erreurDeConnexion(e));
    }
    try {
      requete.headers.contentType = ContentType(
        'application',
        'json',
        charset: 'utf-8',
      );
      requete.add(utf8.encode(json));
      final reponse = await requete.close().timeout(delaiEnvoi);
      final corps = await reponse
          .transform(utf8.decoder)
          .join()
          .timeout(delaiEnvoi);
      return PostRepondu(ReponsePost(reponse.statusCode, corps));
    } on TimeoutException {
      return const PostIncertain(
        ErreurBoitier(CauseBoitier.delai, TextesBoitier.delaiEnvoi),
      );
    } on Object {
      return const PostIncertain(
        ErreurBoitier(CauseBoitier.reponseInvalide, TextesBoitier.delaiEnvoi),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<ReponsePost> _get(String chemin, Duration delai) async {
    final client = _fabrique()..connectionTimeout = delaiConnexion;
    try {
      final requete = await client.getUrl(_uri(chemin)).timeout(delaiConnexion);
      final reponse = await requete.close().timeout(delai);
      final corps = await reponse.transform(utf8.decoder).join().timeout(delai);
      return ReponsePost(reponse.statusCode, corps);
    } on TimeoutException {
      throw const ErreurBoitier(
        CauseBoitier.delai,
        TextesBoitier.delaiVerification,
      );
    } on ErreurBoitier {
      rethrow;
    } on Object catch (e) {
      throw _erreurDeConnexion(e);
    } finally {
      client.close(force: true);
    }
  }

  ErreurBoitier _erreurDeConnexion(Object e) => e is TimeoutException
      ? const ErreurBoitier(
          CauseBoitier.piloteInjoignable,
          'Le pilote du boîtier ne répond pas : vérifiez qu’il est démarré '
          'sur ce poste.',
        )
      : ErreurBoitier(
          CauseBoitier.piloteInjoignable,
          TextesBoitier.piloteInjoignable(racine),
        );

  static Map<String, Object?>? _objet(String corps) {
    try {
      final v = jsonDecode(corps);
      return v is Map<String, Object?> ? v : null;
    } on Object {
      return null;
    }
  }
}
