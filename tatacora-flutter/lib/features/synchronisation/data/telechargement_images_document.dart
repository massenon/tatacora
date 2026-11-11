/// La DESCENTE de la signature et du cachet des documents A4 (PO, 07/11/2026) : à chaque
/// synchronisation, après la descente du catalogue, une requête
/// `GET /api/v1/sync/apparence-documents` avec l'empreinte de ce que le poste a déjà. Le serveur
/// ne renvoie les octets que d'une image CHANGÉE ; une image retirée du serveur l'est du poste.
///
/// Jamais bloquant : un échec (réseau, droit, image illisible) ne change rien à l'envoi ni à la
/// descente, et laisse les images actuelles — le prochain passage reprend.
library;

import 'dart:convert';

import '../../facturation/data/images_document_poste.dart';
import 'transport_synchronisation.dart';

class TelechargementImagesDocument {
  TelechargementImagesDocument(
    this._transport,
    this._images, [
    this._enSuspens,
  ]);

  final TransportSynchronisation _transport;
  final ImagesDocumentPoste _images;

  /// Les natures dont un dépôt ou un retrait FAIT DEPUIS CE POSTE n'est pas encore accusé
  /// (11/11/2026) : la descente les laisse en paix — le serveur ne connaît pas encore l'image
  /// du poste, et la lui substituer effacerait ce que l'utilisateur vient de déposer.
  final Future<Set<ImageDocument>> Function()? _enSuspens;

  /// Rend le nombre d'images mises à jour (ou retirées).
  Future<int> rafraichir({
    required String serveur,
    required String posteId,
    required String? jeton,
    String? generation,
  }) async {
    final connues = <String, String>{};
    for (final i in ImageDocument.values) {
      final e = await _images.empreinte(i);
      if (e != null) connues[i.nom] = e;
    }
    final issue = await _transport.get(
      urlServeur(serveur, '/sync/apparence-documents').replace(
        queryParameters: {
          'poste_id': posteId,
          'generation': ?generation,
          ...connues,
        },
      ),
      jeton: jeton,
    );
    if (issue is! ReponseHttp || issue.statut != 200) return 0;
    final data = issue.corps?['data'];
    if (data is! Map) return 0;

    final suspens = await _enSuspens?.call() ?? const <ImageDocument>{};
    var changees = 0;
    for (final i in ImageDocument.values) {
      if (suspens.contains(i)) continue;
      final brute = data[i.nom];
      if (brute == null) {
        if (await _images.lire(i) != null) {
          await _images.retirer(i);
          changees++;
        }
        continue;
      }
      if (brute is! Map) continue;
      final base64 = brute['octets_base64'];
      if (base64 is! String) continue; // inchangée : l'empreinte suffit
      final List<int> octets;
      try {
        octets = base64Decode(base64);
      } on FormatException {
        continue;
      }
      if (await _images.ranger(i, octets)) changees++;
    }
    return changees;
  }
}
