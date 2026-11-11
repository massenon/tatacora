import 'dart:async';

import 'package:tatacora_flutter/features/synchronisation/data/transport_synchronisation.dart';

/// Une requête de FICHIER vue par le faux transport (lot L4).
final class RequeteFichierVue {
  RequeteFichierVue({
    required this.methode,
    required this.url,
    required this.octets,
    required this.type,
    required this.entetes,
    required this.jeton,
  });

  final String methode;
  final Uri url;

  /// Le corps envoyé (`PUT`), vide pour un `GET`.
  final List<int> octets;
  final String? type;
  final Map<String, String> entetes;
  final String? jeton;

  String get chemin => url.path;
}

/// Un faux [TransportFichiers] : chaque requête est consignée, la réponse vient
/// de [repondre]. [journal] (facultatif) reçoit « fichier » à chaque requête,
/// pour comparer l'ORDRE avec un faux transport JSON qui écrit dans le même.
final class FauxTransportFichiers implements TransportFichiers {
  FauxTransportFichiers(this.repondre, {this.journal});

  FutureOr<IssueHttp> Function(RequeteFichierVue requete) repondre;
  final List<String>? journal;
  final List<RequeteFichierVue> requetes = [];

  List<RequeteFichierVue> get depots => [
    for (final r in requetes)
      if (r.methode == 'PUT') r,
  ];

  @override
  Future<IssueHttp> deposer(
    Uri url, {
    required List<int> octets,
    required String type,
    Map<String, String> entetes = const {},
    String? jeton,
  }) async {
    final r = RequeteFichierVue(
      methode: 'PUT',
      url: url,
      octets: List<int>.of(octets),
      type: type,
      entetes: entetes,
      jeton: jeton,
    );
    requetes.add(r);
    journal?.add('PUT ${url.path}');
    return repondre(r);
  }

  @override
  Future<IssueHttp> telecharger(Uri url, {String? jeton}) async {
    final r = RequeteFichierVue(
      methode: 'GET',
      url: url,
      octets: const [],
      type: null,
      entetes: const {},
      jeton: jeton,
    );
    requetes.add(r);
    journal?.add('GET ${url.path}');
    return repondre(r);
  }
}

/// Le 200 du dépôt, avec l'accusé du serveur.
ReponseHttp depotAccepte({bool rejeu = false}) => ReponseHttp(
  statut: 200,
  corps: {
    'data': {'rejeu': rejeu},
  },
);

/// Un refus JSON du serveur.
ReponseHttp refusServeur(
  int statut,
  String code,
  String message, {
  bool champ = true,
}) => ReponseHttp(
  statut: statut,
  corps: {
    'code': code,
    'message': message,
    if (champ)
      'errors': {
        'photoRecu': [message],
      },
  },
);
