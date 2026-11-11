/// Les réglages de l'OPÉRATEUR que le boîtier exige (`seller_id`,
/// `seller_name`), reçus du serveur en lecture seule (`mecef_operateur_id`,
/// `mecef_operateur_nom`). Seul lecteur de ces deux clés sur ce poste.
library;

import 'package:drift/drift.dart' show BooleanExpressionOperators;

import '../../../core/database/app_database.dart';
import '../../../core/impression/entete_etablissement.dart';
import '../../comptabilite/domain/calcul_tva.dart';
import '../../parametres/data/parametres_dao.dart';
import '../domain/client_mecef.dart';
import '../domain/conversion_boitier.dart';
import '../domain/entities/piece_facturation.dart';
import '../domain/erreur_boitier.dart';
import '../domain/ifu_client.dart';
import '../domain/mode_facturation.dart';
import '../domain/repositories/facture_repository.dart';
import '../domain/statut_normalisation.dart';
import 'client_mecef_boitier.dart';
import 'facture_dao.dart';
import 'lecteur_mode_facturation.dart';
import 'pilote_boitier.dart';

/// `seller_name` : 30 caractères au plus (`bill.spec.json` du pilote).
const int longueurMaxNomOperateur = 30;

final class OperateurFacturation {
  const OperateurFacturation({required this.id, required this.nom});

  final String id;
  final String nom;

  bool get complet => id.isNotEmpty && nom.isNotEmpty;

  /// Lit l'opérateur des paramètres reçus du serveur.
  factory OperateurFacturation.depuisParametres(Map<String, String> valeurs) =>
      OperateurFacturation(
        id: (valeurs['mecef_operateur_id'] ?? '').trim(),
        nom: (valeurs['mecef_operateur_nom'] ?? '').trim(),
      );
}

// ===========================================================================
// Le SERVICE de normalisation de ce poste — lot 2 (07/11/2026).
// ===========================================================================

/// Ce que [ServiceNormalisation.normaliser] rend.
sealed class ResultatNormalisationPiece {
  const ResultatNormalisationPiece();
}

/// Le mode de ce poste n'est pas « boîtier » : AUCUNE requête n'a été faite, la
/// pièce n'a pas bougé.
final class NormalisationIgnoree extends ResultatNormalisationPiece {
  const NormalisationIgnoree(this.certifiePar);
  final CertifiePar certifiePar;
}

/// La pièce était déjà normalisée : rien n'a été refait (idempotence).
final class DejaNormalisee extends ResultatNormalisationPiece {
  const DejaNormalisee(this.piece);
  final PieceFacturation piece;
}

/// Une tentative a eu lieu ; [piece] porte son issue.
final class NormalisationFaite extends ResultatNormalisationPiece {
  const NormalisationFaite(this.piece, this.issue);
  final PieceFacturation piece;
  final IssueCertification issue;
}

/// La normalisation des pièces de CE poste par son boîtier CC300.
///
///  * **Aucune requête si le mode effectif n'est pas « boîtier »** (mode du serveur
///    surchargé par le réglage local, voir `mode_facturation.dart`).
///  * Une pièce déjà normalisée n'est jamais renormalisée.
///  * Une facture annulée ne se normalise pas ; un avoir ne se normalise que si sa
///    facture d'origine l'est (`rn` = son NIM-TC).
///  * Le résultat est rangé par [FactureDao] (écrivain unique des pièces) et part
///    au serveur par la file d'envoi — le serveur le RANGE, il n'appelle jamais le
///    boîtier. L'interrupteur « Synchronisation activée » gouverne cette file.
///  * Toute issue, échec compris, se range sur la pièce avec un motif en français :
///    rien n'est jamais perdu en silence.
class ServiceNormalisation {
  ServiceNormalisation(
    this._base, {
    LecteurModeFacturation? lecteur,
    PiloteBoitier Function(String racine)? fabriquePilote,
    FactureDao? factures,
    this._attenteApresDelai = const Duration(seconds: 6),
  }) : _lecteur = lecteur ?? LecteurModeFacturation(_base),
       _fabriquePilote =
           fabriquePilote ?? ((racine) => PiloteBoitier(racine: racine)),
       _factures = factures ?? FactureDao(_base);

  final AppDatabase _base;
  final LecteurModeFacturation _lecteur;
  final PiloteBoitier Function(String racine) _fabriquePilote;
  final FactureDao _factures;
  final Duration _attenteApresDelai;

  /// Ce poste certifie-t-il par son boîtier ? (pour afficher ou masquer le
  /// bouton « Normaliser » sans rien appeler.)
  Future<bool> boitierActif() async =>
      (await _lecteur.lire()).certifiePar == CertifiePar.boitier;

  /// Normalise (ou RÉESSAIE) la pièce [pieceId].
  Future<ResultatNormalisationPiece> normaliser(String pieceId) async {
    final etat = await _lecteur.lire();
    if (etat.certifiePar != CertifiePar.boitier) {
      return NormalisationIgnoree(etat.certifiePar);
    }

    final piece = await _factures.parId(pieceId);
    if (piece == null) throw PieceIntrouvable(pieceId);
    if (piece.estNormalisee) return DejaNormalisee(piece);

    final valeurs = await ParametresDao(_base).lireTout();
    final entete = EnteteEtablissement.depuisParametres(valeurs);
    final ifu = (entete.ifu ?? '').trim();

    // Les refus LOCAUX (avant toute requête) se rangent comme les autres issues.
    final refus = await _refusLocal(piece, ifu);
    if (refus != null) {
      final enregistree = await _factures.enregistrerIssueNormalisation(
        piece.id,
        EnAttente(refus),
        voie: VoieNormalisation.boitier,
      );
      return NormalisationFaite(enregistree, EnAttente(refus));
    }

    final DemandeNormalisation demande;
    try {
      demande = await _construireDemande(piece, valeurs);
    } on ErreurBoitier catch (e) {
      final issue = EnAttente(e.message);
      final enregistree = await _factures.enregistrerIssueNormalisation(
        piece.id,
        issue,
        voie: VoieNormalisation.boitier,
      );
      return NormalisationFaite(enregistree, issue);
    }

    final client = ClientMecefBoitier(
      pilote: _fabriquePilote(etat.adresseBoitier),
      ifuEntreprise: ifu,
      attenteApresDelai: _attenteApresDelai,
    );
    final issue = await client.certifier(
      demande,
      compteurAvantPrecedent: piece.normalisationCompteurAvant,
      surEnvoi: (compteur) => _factures.noterTentativeNormalisation(
        piece.id,
        compteurAvant: compteur,
        voie: VoieNormalisation.boitier,
      ),
    );
    final enregistree = await _factures.enregistrerIssueNormalisation(
      piece.id,
      issue,
      voie: VoieNormalisation.boitier,
    );
    return NormalisationFaite(enregistree, issue);
  }

  /// Une raison, en français, de ne pas même essayer ; `null` si tout va bien.
  Future<String?> _refusLocal(PieceFacturation piece, String ifu) async {
    if (!RegExp(r'^[0-9]{13}$').hasMatch(ifu)) {
      return 'L’IFU de l’entreprise doit compter 13 chiffres (Paramètres → '
          'Identité & Légal) : il est exigé pour normaliser.';
    }
    if (!IfuClient.valide(piece.acheteurIfu)) return TextesIfuClient.invalide;
    if (piece.estAnnulee && !piece.estAvoir) {
      return 'Cette facture est annulée : une facture annulée ne se normalise '
          'pas (sa correction est son avoir).';
    }
    if (piece.estAvoir) {
      final origine = await _factures.parNumero(piece.avoirDe!);
      if (origine == null || !origine.estNormalisee) {
        return 'La facture d’origine ${piece.avoirDe} n’est pas normalisée : '
            'son avoir n’a pas à l’être.';
      }
    }
    return null;
  }

  Future<DemandeNormalisation> _construireDemande(
    PieceFacturation piece,
    Map<String, String> valeurs,
  ) async {
    final tva = ParametresTva.depuis(valeurs);
    if (tva.estActive) {
      final String convention;
      try {
        convention = tva.conventionOuRefus();
      } on RefusTva catch (e) {
        throw ErreurBoitier(CauseBoitier.nonConvertible, e.message);
      }
      if (convention != ConventionsPrix.ttc) {
        throw const ErreurBoitier(
          CauseBoitier.nonConvertible,
          'La convention de prix « HT » n’est pas prise en charge pour la '
          'normalisation sur ce poste : le boîtier exige des prix TTC.',
        );
      }
    }
    final operateur = OperateurFacturation.depuisParametres(valeurs);
    if (!operateur.complet) {
      throw const ErreurBoitier(
        CauseBoitier.nonConvertible,
        'L’identifiant et le nom de l’opérateur ne sont pas reçus du serveur : '
        'réglez-les au serveur (Paramètres → Facturation normalisée).',
      );
    }

    // Une ligne d'avoir porte une quantité NÉGATIVE : le boîtier reçoit des
    // montants positifs, le sens se dit par `rt`/`rn`.
    final lignes = [
      for (final l in piece.lignes)
        LigneDemande(
          libelle: l.libelle,
          prixUnitaire: l.prixUnitaire.abs(),
          quantite: l.quantite.abs(),
          groupe: groupeDeTaxe(tvaActive: tva.estActive, libelle: l.libelle),
          codeArticle: l.codeArticle,
        ),
    ];
    final total = lignes.fold<int>(0, (t, l) => t + l.montant);

    final paiements = piece.estAvoir
        ? await _paiementsDeLAvoir(piece, total)
        : await _paiementsDeLaFacture(piece, total);

    String? reference;
    if (piece.estAvoir) {
      final origine = await _factures.parNumero(piece.avoirDe!);
      reference = origine?.numeroMecef;
    }

    return DemandeNormalisation(
      pieceId: piece.id,
      numero: piece.numero,
      lignes: lignes,
      paiements: paiements,
      // L'ACHETEUR saisi (07/11/2026) : nom saisi, sinon celui de la pièce, sinon « Client
      // divers » ; IFU facultatif (vide = client sans IFU, la clé n'est pas envoyée).
      clientNom: IfuClient.nomPourNormalisation(
        piece.acheteurNom,
        repli: piece.clientNom,
      ),
      clientIfu: IfuClient.nettoyer(piece.acheteurIfu),
      operateurId: operateur.id,
      operateurNom: operateur.nom,
      referenceAvoir: reference,
    );
  }

  /// Les règlements ACTIFS de la facture ; sans règlement enregistré, une vente
  /// au comptant se lit sur le mode de la pièce (réglée à l'émission).
  Future<List<PaiementDemande>> _paiementsDeLaFacture(
    PieceFacturation piece,
    int total,
  ) async {
    final lignes =
        await (_base.select(_base.paiementsFactureLocal)..where(
              (p) => p.pieceId.equals(piece.id) & p.statut.equals('actif'),
            ))
            .get();
    if (lignes.isNotEmpty) {
      final resultat = <PaiementDemande>[];
      for (final p in lignes) {
        final mode = modePaiementPilote(p.modePaiement);
        if (mode == null) {
          throw ErreurBoitier(
            CauseBoitier.nonConvertible,
            'Mode de règlement « ${p.modePaiement} » inconnu du boîtier : '
            'la facture n’est pas normalisée.',
          );
        }
        if (p.montantCentimes % 100 != 0) {
          throw const ErreurBoitier(
            CauseBoitier.nonConvertible,
            'Un règlement comporte des centimes : le boîtier ne reçoit que des '
            'francs entiers.',
          );
        }
        resultat.add(
          PaiementDemande(mode: mode, montant: p.montantCentimes ~/ 100),
        );
      }
      return resultat;
    }
    final modePiece = modePaiementPilote(piece.modePaiement);
    if (piece.origine == OrigineFacture.posComptant && modePiece != null) {
      return [PaiementDemande(mode: modePiece, montant: total)];
    }
    throw const ErreurBoitier(
      CauseBoitier.nonConvertible,
      'La facture n’est pas réglée : enregistrez le règlement avant de la '
      'normaliser.',
    );
  }

  /// L'avoir rembourse le montant de ses lignes dans le mode du règlement
  /// principal de la facture d'origine (question ouverte n° 4 de la spécification).
  Future<List<PaiementDemande>> _paiementsDeLAvoir(
    PieceFacturation avoir,
    int total,
  ) async {
    final origine = await _factures.parNumero(avoir.avoirDe!);
    if (origine == null) {
      throw const ErreurBoitier(
        CauseBoitier.nonConvertible,
        'La facture d’origine de cet avoir est introuvable.',
      );
    }
    final reglements = await _paiementsDeLaFacture(
      origine,
      origine.montantTotal,
    );
    reglements.sort((a, b) => b.montant.compareTo(a.montant));
    return [PaiementDemande(mode: reglements.first.mode, montant: total)];
  }
}
