/// Le TRANSPORT HTTP de la synchronisation (lot F2a, 15/10/2026) — le seul
/// endroit du poste qui parle au serveur TATACORA.
///
/// ## Une interface, deux implémentations
///
/// [TransportSynchronisation] est ce que l'appairage et le moteur d'envoi
/// connaissent : une requête JSON part, une [IssueHttp] revient — jamais une
/// exception. [TransportHttp] l'implémente sur `package:http` ; un test lui
/// passe le `MockClient` du paquet, ou implémente l'interface directement.
///
/// ## Ce que le transport garantit
///
///  * `Accept: application/json` sur toute requête (sans lui, Laravel répond
///    à un refus par une redirection HTML vers une page de connexion) ;
///  * le jeton en `Authorization: Bearer …`, jamais dans l'URL ;
///  * 20 s au plus pour établir la connexion, 20 s au plus pour la requête
///    entière ;
///  * aucune réponse (délai, réseau coupé, nom introuvable, TLS refusé) rend
///    [ServeurInjoignable] — la TENTATIVE est l'autorité, aucune sonde de
///    connectivité n'est consultée (au Gîte, un routeur allumé au lien amont
///    coupé se dit « connecté ») ;
///  * le corps n'est JAMAIS journalisé : il porte un mot de passe à
///    l'appairage et un jeton dans sa réponse.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Le délai d'établissement de la connexion, puis de la requête entière.
const Duration delaiTransport = Duration(seconds: 20);

/// L'issue d'une requête : une réponse, ou pas de réponse du tout.
sealed class IssueHttp {
  const IssueHttp();
}

/// Le serveur a RÉPONDU — quel que soit le code.
final class ReponseHttp extends IssueHttp {
  const ReponseHttp({
    required this.statut,
    required this.corps,
    this.entetes = const {},
  });

  final int statut;

  /// Le corps décodé (objet JSON), ou `null` s'il n'est pas du JSON objet.
  final Map<String, Object?>? corps;

  /// Les en-têtes, noms en minuscules.
  final Map<String, String> entetes;

  bool get estSucces => statut >= 200 && statut < 300;
}

/// Aucune réponse : délai dépassé, connexion refusée, réseau absent.
final class ServeurInjoignable extends IssueHttp {
  const ServeurInjoignable(this.raison);

  /// La raison TECHNIQUE (type d'erreur), pour le journal de la file —
  /// jamais affichée telle quelle à l'opérateur.
  final String raison;
}

/// Ce que l'appairage et le moteur d'envoi savent du réseau.
abstract interface class TransportSynchronisation {
  /// `POST` d'un corps JSON. [jeton] : le jeton Sanctum du poste, s'il y en a.
  Future<IssueHttp> post(Uri url, {Map<String, Object?>? corps, String? jeton});

  /// `GET`.
  Future<IssueHttp> get(Uri url, {String? jeton});
}

/// [TransportSynchronisation] sur `package:http`.
final class TransportHttp implements TransportSynchronisation {
  /// [client] : un `MockClient` en test. Par défaut, un client `dart:io` dont
  /// la connexion est bornée à [delai].
  TransportHttp({http.Client? client, this.delai = delaiTransport})
    : _client =
          client ?? IOClient(HttpClient()..connectionTimeout = delaiTransport);

  final http.Client _client;
  final Duration delai;

  static Map<String, String> _entetes(String? jeton, {bool json = false}) => {
    'Accept': 'application/json',
    if (json) 'Content-Type': 'application/json; charset=utf-8',
    if (jeton != null && jeton.isNotEmpty) 'Authorization': 'Bearer $jeton',
  };

  @override
  Future<IssueHttp> post(
    Uri url, {
    Map<String, Object?>? corps,
    String? jeton,
  }) => _executer(
    () => _client.post(
      url,
      headers: _entetes(jeton, json: true),
      body: jsonEncode(corps ?? const <String, Object?>{}),
    ),
  );

  @override
  Future<IssueHttp> get(Uri url, {String? jeton}) =>
      _executer(() => _client.get(url, headers: _entetes(jeton)));

  Future<IssueHttp> _executer(Future<http.Response> Function() requete) async {
    final http.Response reponse;
    try {
      reponse = await requete().timeout(delai);
    } on TimeoutException {
      return const ServeurInjoignable('délai dépassé');
    } on SocketException catch (e) {
      return ServeurInjoignable('réseau : ${e.osError?.message ?? e.message}');
    } on HandshakeException {
      return const ServeurInjoignable('TLS : poignée de main refusée');
    } on http.ClientException catch (e) {
      return ServeurInjoignable('client HTTP : ${e.message}');
    } on HttpException catch (e) {
      return ServeurInjoignable('HTTP : ${e.message}');
    } on Exception catch (e) {
      // Une adresse illisible, par exemple : aucune réponse non plus.
      return ServeurInjoignable('requête impossible : ${e.runtimeType}');
    }
    return ReponseHttp(
      statut: reponse.statusCode,
      corps: _decoder(reponse.bodyBytes),
      entetes: {
        for (final e in reponse.headers.entries) e.key.toLowerCase(): e.value,
      },
    );
  }

  static Map<String, Object?>? _decoder(List<int> octets) {
    if (octets.isEmpty) return null;
    try {
      final valeur = jsonDecode(utf8.decode(octets));
      return valeur is Map<String, Object?> ? valeur : null;
    } on FormatException {
      return null;
    }
  }
}

/// `<base>/<chemin>`, sans double barre : la base se déclare avec ou sans
/// barre finale.
Uri urlServeur(String base, String chemin) {
  final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  final c = chemin.startsWith('/') ? chemin : '/$chemin';
  return Uri.parse('$b$c');
}

/// L'en-tête par lequel le serveur donne sa GÉNÉRATION des données
/// (19/10/2026), en minuscules comme [ReponseHttp.entetes].
const String enteteGeneration = 'x-tatacora-generation';

/// Le refus « le serveur a été réinitialisé depuis » : 409, code
/// `generation_perimee`. Rend la date de la réinitialisation (à défaut,
/// [maintenant]), ou `null` si [issue] n'est pas ce refus.
DateTime? reinitialisationRefusee(IssueHttp issue, DateTime maintenant) {
  if (issue is! ReponseHttp ||
      issue.statut != 409 ||
      issue.corps?['code'] != 'generation_perimee') {
    return null;
  }
  return DateTime.tryParse('${issue.corps?['reinitialisee_le']}') ?? maintenant;
}
