/// La RÉDUCTION d'un reçu en image trop lourd (PO, 28/10/2026).
///
/// Avant ce jour, un reçu de plus de 400 Ko était REFUSÉ, comme au web. Le
/// Product Owner veut l'inverse : le poids n'est plus une cause de refus, le
/// reçu est réduit jusqu'à tenir dans la limite. Le serveur fait la même chose
/// à la saisie web (`RecuDepenseService::preparer`) : les deux acceptent le même
/// fichier et donnent le même résultat de RÈGLE.
///
/// ## La règle (identique au serveur — constantes confrontées par
/// `depenses_recu_contre_serveur_test.dart`)
///
///  1. un fichier de [tailleMaxRecuKo] Ko au plus est gardé TEL QUEL (octets,
///     type et empreinte d'origine) : la réduction ne touche que l'excès ;
///  2. sinon l'image est décodée, remise à l'endroit (orientation EXIF), posée
///     sur fond BLANC (un JPEG n'a pas de transparence), ramenée à
///     [coteMaxRecuPx] pixels sur son grand côté, puis encodée en JPEG à la
///     première qualité de [qualitesRecu] qui tient dans la limite ;
///  3. si aucune qualité ne suffit, les dimensions sont multipliées par
///     [facteurReductionRecu] et on recommence, jusqu'à [coteMinRecuPx]
///     (plancher théorique : une image de 64 px tient toujours en 400 Ko).
///
/// Le résultat est donc toujours un JPEG de 400 Ko au plus, que la porte de
/// dépôt du serveur accepte. Les octets produits ne sont pas identiques à ceux
/// du serveur (deux encodeurs) ; la règle l'est : même décision, même type,
/// même borne.
///
/// ## Ce qui reste refusé
///
/// Un fichier vide, qui n'est pas une image (mêmes phrases que le web), ou qu'on
/// ne sait pas décoder ([TextesRecu.illisible]). Jamais pour son poids.
///
/// ## Aucune nouvelle dépendance
///
/// Le paquet `image` était déjà dans l'arbre (tiré par `pdf`) ; il est
/// seulement déclaré direct. Le calcul est lourd (décoder une photo de 12 Mpx) :
/// [preparerRecu] le fait dans un isolat, l'interface ne gèle pas.
///
/// @see RecuDepenseService (serveur) — la même règle, en PHP/GD.
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'recu_depense.dart';

/// Grand côté maximal, en pixels, d'une image réduite —
/// `RecuDepenseService::COTE_MAX_PX`.
const int coteMaxRecuPx = 2048;

/// Qualités JPEG essayées, de la meilleure à la plus faible —
/// `RecuDepenseService::QUALITES`.
const List<int> qualitesRecu = [85, 75, 65, 55, 45, 35];

/// Facteur appliqué aux dimensions quand aucune qualité ne suffit —
/// `RecuDepenseService::FACTEUR_REDUCTION`.
const double facteurReductionRecu = 0.8;

/// Plancher du grand côté — `RecuDepenseService::COTE_MIN_PX`.
const int coteMinRecuPx = 64;

/// Réduit [octets] en JPEG de [tailleMaxRecuOctets] au plus, ou `null` si le
/// fichier ne se décode pas. PUR et SYNCHRONE (donc lourd) : l'appelant le lance
/// dans un isolat ([preparerRecu]).
Uint8List? reduireImageRecu(List<int> octets) {
  final brut = Uint8List.fromList(octets);
  img.Image? decode;
  try {
    decode = img.decodeImage(brut);
  } on Object {
    return null;
  }
  if (decode == null || decode.width < 1 || decode.height < 1) return null;

  // Première image d'un GIF animé ; orientation EXIF appliquée.
  var source = decode.frames.length > 1 ? decode.frames.first : decode;
  source = img.bakeOrientation(source);
  final largeur = source.width;
  final hauteur = source.height;
  // Sur fond BLANC : composer sur un canevas blanc, jamais en laissant l'alpha
  // devenir noir à l'encodage.
  final opaque = source.convert(numChannels: 4);

  final echelle = coteMaxRecuPx / (largeur > hauteur ? largeur : hauteur);
  final reduction = echelle < 1 ? echelle : 1.0;
  var l = (largeur * reduction).round().clamp(1, largeur);
  var h = (hauteur * reduction).round().clamp(1, hauteur);

  Uint8List dernier = Uint8List(0);
  while (true) {
    final redimensionnee = (l == largeur && h == hauteur)
        ? opaque
        : img.copyResize(
            opaque,
            width: l,
            height: h,
            interpolation: img.Interpolation.average,
          );
    final toile = img.Image(width: l, height: h, numChannels: 3)
      ..clear(img.ColorRgb8(255, 255, 255));
    img.compositeImage(toile, redimensionnee);

    for (final qualite in qualitesRecu) {
      dernier = img.encodeJpg(toile, quality: qualite);
      if (dernier.length <= tailleMaxRecuOctets) return dernier;
    }

    if ((l > h ? l : h) <= coteMinRecuPx) return dernier;
    l = (l * facteurReductionRecu).floor().clamp(1, l);
    h = (h * facteurReductionRecu).floor().clamp(1, h);
  }
}

/// Prépare le reçu CHOISI : gardé tel quel s'il tient en 400 Ko, réduit sinon.
/// Refuse seulement un fichier vide, qui n'est pas une image, ou illisible.
///
/// Le décodage se fait dans un isolat : une photo de téléphone ne gèle pas la
/// fenêtre.
Future<IssueRecu> preparerRecu(List<int> octets) async {
  if (octets.isEmpty) return const RecuRefuse(TextesRecu.vide);
  final type = typeRecuDepuisOctets(octets);
  // Le type d'abord, SANS le poids : un fichier lourd qui n'est pas une image
  // reste refusé par la phrase du validateur.
  if (type == null) return const RecuRefuse(TextesRecu.nonImage);

  final brut = octets is Uint8List ? octets : Uint8List.fromList(octets);
  if (brut.length <= tailleMaxRecuOctets) {
    return RecuAccepte(type, octets: brut, tailleOrigine: brut.length);
  }

  final reduit = await Isolate.run(() => reduireImageRecu(brut));
  if (reduit == null) return const RecuRefuse(TextesRecu.illisible);

  // Filet : ce qu'on remet passe la porte de dépôt, 400 Ko compris.
  final issue = verifierRecu(reduit);
  if (issue is RecuRefuse) return issue;
  return RecuAccepte(
    (issue as RecuAccepte).type,
    octets: reduit,
    reduit: true,
    tailleOrigine: brut.length,
  );
}
