import 'ifu_client.dart';

/// L'ACHETEUR d'une facture, tel que l'opérateur le saisit à la VALIDATION de la facturation,
/// dans chaque flux (décision du PO du 07/11/2026, point 2) : POS hébergement (séjour, note de
/// chambre), POS vente, location, tourisme.
///
///  * [ifu] : l'IFU du client — FACULTATIF, 13 chiffres s'il est rempli, vide = client sans IFU ;
///  * [nom] : le nom du client tel qu'il part à la normalisation (à défaut : celui de la fiche,
///    puis « Client divers ») ;
///  * [retenir] : « Retenir pour ce client » — DÉCOCHÉ par défaut ; coché, le serveur range
///    l'IFU sur la fiche du client ;
///  * [normaliserMaintenant] : « Normaliser maintenant » — DÉCOCHÉ par défaut, jamais
///    automatique ; sans effet quand ce poste ne normalise pas (mode désactivé). Un échec de
///    la normalisation ne bloque JAMAIS la facture ni l'encaissement.
final class AcheteurFacture {
  const AcheteurFacture({
    this.ifu,
    this.nom,
    this.retenir = false,
    this.normaliserMaintenant = false,
  });

  final String? ifu;
  final String? nom;
  final bool retenir;
  final bool normaliserMaintenant;

  /// L'IFU nettoyé (séparateurs ôtés), `null` si vide.
  String? get ifuNet => IfuClient.nettoyer(ifu);

  /// Vide = valide ; sinon exactement 13 chiffres.
  bool get ifuValide => IfuClient.valide(ifu);

  String? get nomNet {
    final n = (nom ?? '').trim();
    return n.isEmpty ? null : n;
  }

  static const AcheteurFacture aucun = AcheteurFacture();
}
