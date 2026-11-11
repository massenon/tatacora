/// Le DÉPÔT et le RETRAIT de la signature et du cachet des documents A4 DEPUIS CE POSTE
/// (décision du PO du 11/11/2026 : « téléverser la signature et le cachet depuis le poste,
/// comme au web »).
///
/// ## Conception
///
///  1. **Le fichier est choisi** par la fenêtre « Ouvrir » native (`SelecteurFichiers`) : le
///     paquet `file_selector_windows` est déjà là, aucune dépendance ajoutée.
///  2. **Validation locale** ([preparerImageDocument]) : le type est LU DES OCTETS (jamais
///     l'extension) ; PNG et JPEG de 400 Ko au plus sont gardés TELS QUELS ; plus gros, ou
///     WebP / GIF / BMP, l'image est réduite ou convertie par le paquet `image` (déjà direct
///     depuis le lot des reçus) avec la règle du serveur (`reduction_recu.dart`). Seul un
///     fichier vide, non image ou illisible est refusé — jamais pour son poids, comme au web.
///  3. **Enregistrement LOCAL immédiat** (le poste imprime avec, sans réseau), puis opération
///     `depots_images_document` dans la FILE D'ENVOI, dans la même transaction que l'écriture
///     de la file : nature + type MIME + contenu en base64 (400 Ko au plus avant encodage).
///     Chaque geste porte un identifiant neuf : c'est lui que le serveur reconnaît au rejeu.
///     « Retirer » est une opération de retrait. Le serveur ne juge pas le module du compte
///     d'appairage : le droit est celui de l'écran (administrateur, RBAC local).
///  4. **La descente continue** : une image déposée au web arrive ici ; une image déposée ici
///     arrive au web et aux autres postes. Pas de boucle : l'empreinte est celle des octets
///     envoyés, que le serveur garde tels quels (≤ 400 Ko), et la descente laisse en paix une
///     nature dont le dernier geste n'est pas encore accusé ([naturesEnSuspens]) — sinon elle
///     écraserait l'image saisie hors réseau par l'ancienne du serveur.
library;

import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/di/providers.dart';
import '../../depenses/domain/recu_depense.dart';
import '../../depenses/domain/reduction_recu.dart';
import '../../synchronisation/data/operations_sync_dao.dart';
import '../../synchronisation/domain/charges_synchronisation.dart';
import '../../synchronisation/domain/operation_sync.dart';
import 'images_document_poste.dart';

/// Les extensions proposées par la fenêtre « Ouvrir » : PNG, JPG ou WebP — ce que dit l'écran.
const List<String> extensionsImageDocument = ['png', 'jpg', 'jpeg', 'webp'];

/// Un dépôt refusé — la phrase est dite à l'écran.
final class RefusImageDocument implements Exception {
  const RefusImageDocument(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Une image prête à être rangée et envoyée : PNG ou JPEG, 400 Ko au plus.
final class ImageDocumentPrete {
  const ImageDocumentPrete(this.octets, this.mime);

  final Uint8List octets;
  final String mime;
}

/// Prépare l'image CHOISIE. Refuse (phrases du web : `depenses.recu_vide`, `validation.image`,
/// `depenses.recu_illisible`) un fichier vide, qui n'est pas une image, ou illisible — jamais
/// pour son poids.
///
/// Le décodage (une photo de 12 Mpx) se fait dans un isolat.
Future<ImageDocumentPrete> preparerImageDocument(List<int> octets) async {
  if (octets.isEmpty) throw const RefusImageDocument(TextesRecu.vide);
  final type = typeRecuDepuisOctets(octets);
  if (type == null) throw const RefusImageDocument(TextesRecu.nonImage);
  final brut = octets is Uint8List ? octets : Uint8List.fromList(octets);

  final directe = type == TypeRecu.png || type == TypeRecu.jpeg;
  if (directe && brut.length <= tailleMaxRecuOctets) {
    return ImageDocumentPrete(brut, type.mime);
  }

  final converti = await Isolate.run(() => _convertirOuReduire(brut, directe));
  if (converti == null) throw const RefusImageDocument(TextesRecu.illisible);
  final mime = typeRecuDepuisOctets(converti)?.mime;
  if (mime == null || converti.length > tailleMaxRecuOctets) {
    throw const RefusImageDocument(TextesRecu.illisible);
  }
  return ImageDocumentPrete(converti, mime);
}

/// PUR et SYNCHRONE (lourd) : un PNG/JPEG trop gros est réduit en JPEG ; un WebP, GIF ou BMP
/// est converti en PNG (transparence gardée), puis réduit en JPEG s'il dépasse encore 400 Ko.
Uint8List? _convertirOuReduire(Uint8List brut, bool directe) {
  if (!directe) {
    img.Image? decode;
    try {
      decode = img.decodeImage(brut);
    } on Object {
      return null;
    }
    if (decode == null || decode.width < 1 || decode.height < 1) return null;
    final png = Uint8List.fromList(
      img.encodePng(decode.frames.length > 1 ? decode.frames.first : decode),
    );
    if (png.length <= tailleMaxRecuOctets) return png;
  }
  return reduireImageRecu(brut);
}

/// Le dépôt local d'une image de document : fichier rangé, puis opération enfilée.
class DepotImagesDocumentPoste {
  DepotImagesDocumentPoste(this._db, this._images, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final ImagesDocumentPoste _images;
  final Uuid _uuid;

  /// Range [choisi] localement et l'enfile au serveur. Rien n'est écrit sur un refus ; si
  /// l'enfilement échoue, l'image précédente est rétablie (le fichier et la file restent d'accord).
  ///
  /// @throws RefusImageDocument fichier vide, non image ou illisible
  Future<void> deposer(ImageDocument nature, List<int> choisi) async {
    final prete = await preparerImageDocument(choisi);
    final avant = await _images.lire(nature);
    if (!await _images.ranger(nature, prete.octets)) {
      throw const RefusImageDocument(TextesRecu.illisible);
    }
    try {
      await _enfiler(
        chargeDepotImageDocument(
          nature: nature.nom,
          typeMime: prete.mime,
          octetsBase64: base64Encode(prete.octets),
        ),
      );
    } on Object {
      await _retablir(nature, avant);
      rethrow;
    }
  }

  /// Retire l'image locale et enfile le retrait. Sans image ici, rien à retirer.
  Future<void> retirer(ImageDocument nature) async {
    final avant = await _images.lire(nature);
    if (avant == null) return;
    await _images.retirer(nature);
    try {
      await _enfiler(chargeRetraitImageDocument(nature: nature.nom));
    } on Object {
      await _retablir(nature, avant);
      rethrow;
    }
  }

  /// Les natures dont un geste n'est pas encore accusé par le serveur (en attente, en cours,
  /// bloqué) : la descente n'y touche pas, l'image locale est la seule copie qui compte.
  Future<Set<ImageDocument>> naturesEnSuspens() async {
    final suspens = <ImageDocument>{};
    for (final o in await OperationsSyncDao(
      _db,
    ).operations(table: TableSynchronisee.depotsImagesDocument)) {
      if (o.statut != StatutOperationSync.enAttente &&
          o.statut != StatutOperationSync.enCours &&
          o.statut != StatutOperationSync.bloque) {
        continue;
      }
      final charge = jsonDecode(o.payload);
      final nom = charge is Map ? charge['nature'] : null;
      for (final n in ImageDocument.values) {
        if (n.nom == nom) suspens.add(n);
      }
    }
    return suspens;
  }

  Future<void> _enfiler(Map<String, Object?> charge) => _db.transaction(
    () => OperationsSyncDao(_db).enfiler(
      table: TableSynchronisee.depotsImagesDocument,
      entiteId: _uuid.v4(),
      type: TypeOperationSync.creation,
      payload: charge,
    ),
  );

  Future<void> _retablir(ImageDocument nature, Uint8List? avant) async {
    if (avant == null) {
      await _images.retirer(nature);
    } else {
      await _images.ranger(nature, avant);
    }
  }
}

final depotImagesDocumentProvider = Provider<DepotImagesDocumentPoste>(
  (ref) => DepotImagesDocumentPoste(
    ref.watch(baseLocaleProvider),
    ref.watch(imagesDocumentPosteProvider),
  ),
);
