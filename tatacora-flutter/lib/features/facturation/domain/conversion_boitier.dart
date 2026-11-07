/// La CONVERSION d'une facture TATACORA en JSON du pilote CC300 — des fonctions
/// PURES, sans réseau ni base (`docs/SPEC_FACTURATION_NORMALISEE_MECEF.md` §4).
///
/// ## Ce que le pilote impose, et que cette conversion tient
///
///  * montants en `float32` : seuls des ENTIERS FCFA sont envoyés, et jamais un
///    nombre au-delà de 2^24 − 1 (au-delà, le boîtier arrondirait en silence) ;
///  * `specific_tax` et `original_price` ne sont JAMAIS envoyés : le pilote les
///    déclare en chaînes alors que son schéma les dit nombres — les envoyer fait
///    échouer son décodage (réponse vide, 200) ;
///  * `seller_name` ≤ 30, `label` ≤ 60 ; les textes sont rendus ASCII
///    (le protocole série du boîtier n'a pas de table de caractères documentée),
///    `< > & CR LF` — que le pilote remplace par des entités qui rallongent le
///    texte —, virgule, point-virgule, tabulation et `*` — séparateurs du
///    protocole — deviennent des espaces ;
///  * somme des lignes = total = somme des paiements, vérifiée AVANT d'envoyer.
library;

import 'dart:convert';

import 'erreur_boitier.dart';

/// Le plus grand entier exactement représentable en `float32`.
const int maxEntierFloat32 = 16777215;

const int longueurMaxNomVendeur = 30;
const int longueurMaxLibelle = 60;
const int longueurMaxCodeBarre = 24;

/// Le libellé EXACT que le boîtier exige pour la taxe de séjour (groupe F).
const String libelleTaxeDeSejour = 'TAXE DE SEJOUR';

/// Les groupes de taxe du boîtier utilisés ici.
enum GroupeTaxe {
  /// Exonéré.
  a('A'),

  /// Taxable (TVA 18 %).
  b('B'),

  /// Réservé à la taxe de séjour (article nommé `TAXE DE SEJOUR`).
  f('F');

  const GroupeTaxe(this.code);
  final String code;
}

/// Les modes de paiement du pilote : espèces `E`, mobile money `M`, carte `C`,
/// chèque `D`, virement `V`, autre `A`.
enum ModePaiementPilote {
  especes('E'),
  mobileMoney('M'),
  carte('C'),
  cheque('D'),
  virement('V'),
  autre('A');

  const ModePaiementPilote(this.code);
  final String code;
}

/// Traduit un mode de paiement de TATACORA (`especes`, `mobile_money`, `carte`,
/// `virement`, `cheque`, `autre`, ou le libellé d'un écran) en mode du pilote.
/// `null` : mode inconnu — JAMAIS un repli sur « espèces ». Le crédit n'est pas
/// un paiement : une facture à crédit n'est pas normalisable.
ModePaiementPilote? modePaiementPilote(String? brut) {
  final cle = transcrireAscii(
    brut ?? '',
  ).toLowerCase().trim().replaceAll(RegExp(r'[\s\-]+'), '_');
  return switch (cle) {
    'especes' || 'espece' || 'cash' => ModePaiementPilote.especes,
    'mobile_money' ||
    'mobilemoney' ||
    'momo' ||
    'mobile' => ModePaiementPilote.mobileMoney,
    'carte' || 'carte_bancaire' || 'cb' || 'tpe' => ModePaiementPilote.carte,
    'cheque' || 'cheques' => ModePaiementPilote.cheque,
    'virement' || 'virement_bancaire' => ModePaiementPilote.virement,
    'autre' => ModePaiementPilote.autre,
    _ => null,
  };
}

/// Une ligne de la demande : TOUJOURS positive (un avoir se dit par `rt`/`rn`,
/// pas par une quantité négative).
final class LigneDemande {
  const LigneDemande({
    required this.libelle,
    required this.prixUnitaire,
    required this.quantite,
    required this.groupe,
    this.codeArticle,
  });

  final String libelle;

  /// FCFA entiers, prix TTC.
  final int prixUnitaire;
  final int quantite;
  final GroupeTaxe groupe;
  final String? codeArticle;

  int get montant => prixUnitaire * quantite;
}

final class PaiementDemande {
  const PaiementDemande({required this.mode, required this.montant});

  final ModePaiementPilote mode;

  /// FCFA entiers.
  final int montant;
}

/// Tout ce qu'il faut pour normaliser UNE pièce.
final class DemandeNormalisation {
  const DemandeNormalisation({
    required this.pieceId,
    required this.numero,
    required this.lignes,
    required this.paiements,
    required this.clientNom,
    required this.operateurId,
    required this.operateurNom,
    this.referenceAvoir,
    this.clientIfu,
  });

  final String pieceId;

  /// Le numéro comptable de la pièce, pour les messages.
  final String numero;
  final List<LigneDemande> lignes;
  final List<PaiementDemande> paiements;
  final String clientNom;

  /// L'IFU de l'acheteur : le poste n'en connaît pas (question ouverte n° 8).
  final String? clientIfu;
  final String operateurId;
  final String operateurNom;

  /// Un avoir : le « NIM-TC » de la facture d'origine (`rn`). `null` : une vente.
  final String? referenceAvoir;

  bool get estAvoir => referenceAvoir != null;

  int get totalLignes => lignes.fold(0, (t, l) => t + l.montant);
  int get totalPaiements => paiements.fold(0, (t, p) => t + p.montant);
}

/// Les groupes de taxe de la configuration : TVA active → B (taxable), sinon A
/// (exonéré) ; une ligne « taxe de séjour » → F.
GroupeTaxe groupeDeTaxe({required bool tvaActive, required String libelle}) {
  if (estTaxeDeSejour(libelle)) return GroupeTaxe.f;
  return tvaActive ? GroupeTaxe.b : GroupeTaxe.a;
}

/// « Taxe de séjour », « TAXE DE SEJOUR », « Taxe de sejour (nuit) »…
bool estTaxeDeSejour(String libelle) => transcrireAscii(
  libelle,
).toLowerCase().replaceAll(RegExp(r'\s+'), ' ').contains('taxe de sejour');

/// La table de transcription vers l'ASCII (Latin-1 et les extensions courantes
/// du français) ; tout autre caractère non ASCII disparaît.
const Map<String, String> _transcriptions = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'å': 'a', 'æ': 'ae', //
  'ç': 'c', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'í': 'i', 'ì': 'i', //
  'î': 'i', 'ï': 'i', 'ñ': 'n', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', //
  'õ': 'o', 'œ': 'oe', 'ø': 'o', 'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', //
  'ý': 'y', 'ÿ': 'y', 'ß': 'ss', //
  'À': 'A', 'Â': 'A', 'Ä': 'A', 'Á': 'A', 'Ã': 'A', 'Å': 'A', 'Æ': 'AE', //
  'Ç': 'C', 'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E', 'Í': 'I', 'Ì': 'I', //
  'Î': 'I', 'Ï': 'I', 'Ñ': 'N', 'Ó': 'O', 'Ò': 'O', 'Ô': 'O', 'Ö': 'O', //
  'Õ': 'O', 'Œ': 'OE', 'Ø': 'O', 'Ú': 'U', 'Ù': 'U', 'Û': 'U', 'Ü': 'U', //
  'Ý': 'Y', 'Ÿ': 'Y', //
  '’': "'", '‘': "'", '`': "'", '´': "'", '“': '"', '”': '"', '«': '"', //
  '»': '"', '–': '-', '—': '-', '…': '...', '€': 'EUR', ' ': ' ', //
  ' ': ' ', '°': 'o', //
};

/// Rend [texte] en ASCII : lettres accentuées transcrites, apostrophes et
/// guillemets typographiques redressés, le reste non ASCII retiré.
String transcrireAscii(String texte) {
  final sortie = StringBuffer();
  // Par rune : un caractère hors du plan de base (emoji) n'est jamais coupé.
  for (final rune in texte.runes) {
    final c = String.fromCharCode(rune);
    if (rune < 128) {
      sortie.write(c);
    } else {
      sortie.write(_transcriptions[c] ?? '');
    }
  }
  return sortie.toString();
}

/// Nettoie un texte pour le pilote : ASCII, caractères de contrôle et
/// séparateurs du protocole (`< > & , ; * \t CR LF`) remplacés par des espaces,
/// espaces multiples réduites, puis coupé à [max] SANS couper un mot quand une
/// espace précède dans les 15 derniers caractères.
String nettoyerTexte(String brut, int max) {
  final ascii = transcrireAscii(brut)
      .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
      .replaceAll(RegExp(r'[<>&,;*]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (ascii.length <= max) return ascii;
  final coupe = ascii.substring(0, max);
  // Le mot est-il coupé ? Oui si le caractère suivant n'est pas une espace.
  if (ascii[max] != ' ') {
    final espace = coupe.lastIndexOf(' ');
    if (espace >= max - 15 && espace > 0) {
      return coupe.substring(0, espace).trimRight();
    }
  }
  return coupe.trimRight();
}

/// Le JSON du pilote, ou une [ErreurBoitier] si la demande n'est pas
/// convertible ou si les sommes ne concordent pas. Rien n'est envoyé ici.
String construireJsonPilote(DemandeNormalisation d) {
  if (d.lignes.isEmpty) {
    throw const ErreurBoitier(
      CauseBoitier.nonConvertible,
      'La facture n’a aucune ligne : rien à normaliser.',
    );
  }
  if (d.paiements.isEmpty) {
    throw const ErreurBoitier(
      CauseBoitier.nonConvertible,
      'La facture n’est pas réglée : enregistrez le règlement avant de la '
      'normaliser.',
    );
  }
  for (final l in d.lignes) {
    if (l.prixUnitaire <= 0 || l.quantite <= 0) {
      throw const ErreurBoitier(
        CauseBoitier.nonConvertible,
        'Une ligne a un prix ou une quantité nuls : corrigez avant de '
        'normaliser.',
      );
    }
    if (l.prixUnitaire > maxEntierFloat32 ||
        l.quantite > maxEntierFloat32 ||
        l.montant > maxEntierFloat32) {
      throw const ErreurBoitier(
        CauseBoitier.nonConvertible,
        'Un montant dépasse 16 777 215 FCFA : le boîtier ne le représente pas '
        'exactement.',
      );
    }
  }
  for (final p in d.paiements) {
    if (p.montant <= 0 || p.montant > maxEntierFloat32) {
      throw const ErreurBoitier(
        CauseBoitier.nonConvertible,
        'Un règlement a un montant nul ou supérieur à 16 777 215 FCFA.',
      );
    }
  }
  final lignes = d.totalLignes;
  final paiements = d.totalPaiements;
  if (lignes > maxEntierFloat32 || paiements > maxEntierFloat32) {
    throw const ErreurBoitier(
      CauseBoitier.nonConvertible,
      'Le total dépasse 16 777 215 FCFA : le boîtier ne le représente pas '
      'exactement.',
    );
  }
  if (lignes != paiements) {
    throw ErreurBoitier(
      CauseBoitier.montantsIncoherents,
      TextesBoitier.montants(lignes, paiements),
    );
  }
  final operateurId = nettoyerTexte(d.operateurId, 30);
  final operateurNom = nettoyerTexte(d.operateurNom, longueurMaxNomVendeur);
  if (operateurId.isEmpty || operateurNom.isEmpty) {
    throw const ErreurBoitier(
      CauseBoitier.nonConvertible,
      'L’identifiant et le nom de l’opérateur sont obligatoires : réglez-les '
      'au serveur (Paramètres → Facturation normalisée).',
    );
  }

  final produits = <Map<String, Object?>>[];
  for (final l in d.lignes) {
    final libelle = l.groupe == GroupeTaxe.f
        ? libelleTaxeDeSejour
        : nettoyerTexte(l.libelle, longueurMaxLibelle);
    produits.add({
      'label': libelle.isEmpty ? 'ARTICLE' : libelle,
      'tax': l.groupe.code,
      'price': l.prixUnitaire,
      'items': l.quantite,
      if (l.codeArticle != null &&
          nettoyerTexte(l.codeArticle!, longueurMaxCodeBarre).isNotEmpty)
        'bar_code': nettoyerTexte(l.codeArticle!, longueurMaxCodeBarre),
    });
  }

  final json = <String, Object?>{
    'seller_id': operateurId,
    'seller_name': operateurNom,
    // IFU du client : FACULTATIF (`bill.spec.json`) — un client sans IFU part sans la clé.
    if ((d.clientIfu ?? '').trim().isNotEmpty) 'buyer_ifu': d.clientIfu!.trim(),
    'buyer_name': nettoyerTexte(d.clientNom, 60),
    'aib': 'N/A',
    'payments': [
      for (final p in d.paiements) {'mode': p.mode.code, 'amount': p.montant},
    ],
    'products': produits,
    if (d.estAvoir) ...{'rt': 'FA', 'rn': d.referenceAvoir} else 'vt': 'FV',
  };
  return jsonEncode(json);
}
