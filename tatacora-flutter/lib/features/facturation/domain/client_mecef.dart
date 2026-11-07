import 'dart:async';

import 'conversion_boitier.dart';

/// Le CONTRAT de certification de ce poste — miroir de `MecefClientInterface`
/// (serveur) : « certifier cette pièce » et « êtes-vous le mode réel ? ».
/// L'implémentation de ce lot est `ClientMecefBoitier` (le boîtier CC300) ; le
/// mode e-MECeF se joue AU SERVEUR, ce poste n'en a pas.
abstract interface class ClientMecef {
  /// Certifie [demande]. Ne lève jamais pour une issue prévue (appareil absent,
  /// refus, délai) : elle se DIT par [IssueCertification].
  ///
  /// [compteurAvantPrecedent] : le compteur noté par une tentative précédente
  /// dont l'issue n'a pas été tranchée ; [surEnvoi] est appelé AVEC le compteur
  /// lu avant que la requête de facturation ne parte — l'appelant le range sur
  /// la pièce, pour qu'un arrêt brutal ne perde pas la trace de l'envoi.
  Future<IssueCertification> certifier(
    DemandeNormalisation demande, {
    String? compteurAvantPrecedent,
    FutureOr<void> Function(String compteurAvant)? surEnvoi,
  });

  /// Une certification RÉELLE (jamais une démonstration).
  bool get estModeReel;
}

/// Le résultat d'une certification réussie.
final class CertificationMecefResultat {
  const CertificationMecefResultat({
    required this.nim,
    required this.compteur,
    required this.codeMecef,
    required this.qrCode,
    required this.dateCertification,
  });

  /// Le NIM du boîtier (`ED04000623`).
  final String nim;

  /// « TC » : le compteur de la facture, lu après la vente.
  final int compteur;

  /// Le code MECeF/DGI (le 3ᵉ champ du QR).
  final String codeMecef;

  /// `F;NIM;code;IFU;date`, à imprimer en QR.
  final String qrCode;

  final DateTime dateCertification;

  /// L'identité fiscale de la pièce, et la valeur de `rn` de ses avoirs.
  String get numeroMecef => '$nim-$compteur';
}

/// L'issue d'une certification.
sealed class IssueCertification {
  const IssueCertification();
}

final class Certifiee extends IssueCertification {
  const Certifiee(this.resultat);
  final CertificationMecefResultat resultat;
}

/// Rien n'a été enregistré : la pièce attend et se rejoue.
///
/// [incertaine] : la requête de facturation est PARTIE et sa réponse s'est
/// perdue ; le compteur n'a pas bougé, mais le boîtier peut encore finir (délai).
/// Le compteur lu avant l'envoi reste alors sur la pièce : le rejeu le compare
/// avant de reposter.
final class EnAttente extends IssueCertification {
  const EnAttente(this.motif, {this.incertaine = false, this.compteurAvant});
  final String motif;
  final bool incertaine;
  final String? compteurAvant;
}

/// Le boîtier a explicitement refusé la pièce.
final class Refusee extends IssueCertification {
  const Refusee(this.motif);
  final String motif;
}

/// On ne peut pas trancher : JAMAIS rejouée automatiquement. [qrCode], s'il est
/// présent, est celui que le boîtier a rendu (la facture existe) sans que son
/// compteur ait pu être confirmé.
final class AVerifier extends IssueCertification {
  const AVerifier(
    this.motif, {
    this.compteurAvant,
    this.compteurApres,
    this.qrCode,
    this.nim,
    this.codeMecef,
  });

  final String motif;
  final String? compteurAvant;
  final String? compteurApres;
  final String? qrCode;
  final String? nim;
  final String? codeMecef;
}
