/// Les deux gestes de facturation qui ne se font QU'EN LIGNE, depuis ce poste
/// (décisions du PO du 07/11/2026) :
///
///  * **l'avoir d'une facture NORMALISÉE** (annulation ou partiel) — créé AU SERVEUR, sous
///    l'identifiant du serveur, puis descendu ici par la synchronisation. Hors ligne ou
///    interrupteur « Synchronisation activée » éteint : refusé avec la phrase « Un avoir sur
///    une facture normalisée se fait en ligne : reconnectez le poste au serveur », et RIEN
///    n'est écrit localement (ce service n'écrit jamais d'avoir) ;
///  * **la normalisation e-MECeF** depuis le poste, quand il est EN LIGNE : le serveur
///    normalise (création puis confirmation à la DGI avec SON jeton — le jeton ne descend
///    JAMAIS ici, et ce poste n'appelle JAMAIS la DGI) et le RÉSULTAT revient dans la réponse
///    pour être écrit sur la facture du poste. Hors ligne : « La normalisation e-MECeF se fait
///    en ligne : reconnectez le poste au serveur », la facture reste « en attente ».
///
/// Les deux passent par le jeton d'appairage, après lecture de l'INTERRUPTEUR (règle des
/// chemins réseau de ce poste) et de la génération des données.
library;

import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../synchronisation/data/descente_catalogue_dao.dart';
import '../../synchronisation/data/transport_synchronisation.dart';
import '../../transverse/data/configuration_poste.dart';
import '../domain/entities/piece_facturation.dart';
import '../domain/ifu_client.dart';
import '../domain/repositories/facture_repository.dart';
import '../domain/statut_normalisation.dart';
import 'facture_dao.dart';

/// Ce que rend un geste en ligne.
sealed class IssueEnLigne {
  const IssueEnLigne();
}

/// L'avoir existe au serveur ; il descendra ici (rien n'est écrit localement par ce geste).
final class AvoirCree extends IssueEnLigne {
  const AvoirCree({
    required this.numeroAvoir,
    required this.entier,
    this.normalisationStatut,
    this.rejeu = false,
  });

  final String numeroAvoir;

  /// `true` : avoir du TTC entier (la facture sera marquée annulée à la descente).
  final bool entier;

  /// L'état de normalisation de l'avoir au serveur (`normalisee`, `en_attente`…), `null` pour
  /// l'avoir d'une facture simple.
  final String? normalisationStatut;
  final bool rejeu;
}

/// Le serveur a rendu le résultat de la normalisation ; il est écrit sur la facture.
final class NormalisationServeur extends IssueEnLigne {
  const NormalisationServeur({
    required this.piece,
    required this.statut,
    this.motif,
    this.rejeu = false,
  });

  final PieceFacturation piece;
  final StatutNormalisation statut;
  final String? motif;
  final bool rejeu;
}

/// Refusé, avec une phrase en français ; rien n'a été écrit.
final class RefusEnLigne extends IssueEnLigne {
  const RefusEnLigne(this.phrase);
  final String phrase;
}

class ServiceFacturationEnLigne {
  ServiceFacturationEnLigne({
    required this._transport,
    required this._url,
    required this._base,
    this._demonstration = false,
    LecteurConfigurationPoste? lecteur,
    this._envoyerLaFile,
    this._descendre,
    Uuid? uuid,
  }) : _lecteur = lecteur ?? LecteurConfigurationPoste(),
       _uuid = uuid ?? const Uuid(),
       _factures = FactureDao(_base);

  final TransportSynchronisation _transport;
  final String? _url;
  final AppDatabase _base;
  final bool _demonstration;
  final LecteurConfigurationPoste _lecteur;

  /// Envoie la file du poste (la facture arrive au serveur avant qu'on lui parle d'elle).
  final Future<void> Function()? _envoyerLaFile;

  /// Reçoit ce que le serveur détient (l'avoir créé redescend).
  final Future<void> Function()? _descendre;
  final Uuid _uuid;
  final FactureDao _factures;

  static const String _nonConnue =
      'Cette facture n’est pas encore connue du serveur : envoyez d’abord les '
      'opérations en attente du poste (synchronisation), puis recommencez.';

  /// Le poste est-il en état de parler au serveur ? Sinon : [RefusEnLigne], sans requête.
  Future<Object> _connexion(String phraseHorsLigne) async {
    if (_demonstration || _url == null) return RefusEnLigne(phraseHorsLigne);
    // L'INTERRUPTEUR, relu à chaque geste : éteint, aucun réseau.
    if (!await _lecteur.synchronisationActivee()) {
      return RefusEnLigne(phraseHorsLigne);
    }
    final appairage = await _lecteur.appairage();
    if (appairage == null || appairage.refus != null) {
      return RefusEnLigne(phraseHorsLigne);
    }
    return appairage;
  }

  /// L'avoir de la facture [pieceId] : du TTC entier si [montantFrancs] est `null`.
  ///
  /// Lève les refus LOCAUX de la règle (motif vide, facture introuvable, déjà annulée, montant
  /// nul ou excessif) AVANT toute requête ; ne lève jamais pour le réseau.
  Future<IssueEnLigne> avoir(
    String pieceId, {
    required String motif,
    int? montantFrancs,
  }) async {
    final motifNet = motif.trim();
    if (motifNet.isEmpty) throw const MotifAnnulationRequis();
    final piece = await _factures.parId(pieceId);
    if (piece == null) throw PieceIntrouvable(pieceId);
    if (piece.estAvoir) throw AvoirNonAnnulable(piece.numero);
    if (piece.estAnnulee) throw FactureDejaAnnulee(piece.numero);
    if (montantFrancs != null) {
      if (montantFrancs <= 0) throw const AvoirMontantNul();
      if (montantFrancs > piece.montantTotal) throw const AvoirExcessif();
    }

    final connexion = await _connexion(TextesFacturationModes.avoirEnLigne);
    if (connexion is RefusEnLigne) return connexion;
    final appairage = connexion as AppairagePoste;
    if (!await _factures.partAuServeur(pieceId)) {
      return const RefusEnLigne(_nonConnue);
    }

    final demande = _uuid.v4();
    final generation = await DescenteCatalogueDao(_base).generation();

    Future<IssueHttp> poster() => _transport.post(
      urlServeur(appairage.serveur, '/sync/factures/$pieceId/avoir'),
      jeton: appairage.jetonApi,
      corps: {
        'poste_id': appairage.posteId,
        'generation': ?generation,
        'motif': motifNet,
        'montant': ?montantFrancs,
        'demande_id': demande,
      },
    );

    var issue = await poster();
    if (issue is ReponseHttp &&
        issue.statut == 404 &&
        issue.corps?['code'] == 'facture_inconnue' &&
        _envoyerLaFile != null) {
      // La facture n'est pas encore montée : le poste l'envoie, puis réessaie UNE fois.
      await _envoyerLaFile();
      issue = await poster();
    }

    final refus = _refus(issue, TextesFacturationModes.avoirEnLigne);
    if (refus != null) return refus;
    final data = (issue as ReponseHttp).corps?['data'];
    if (data is! Map) return const RefusEnLigne(_reponseIllisible);

    // L'avoir existe au serveur : la descente le rapporte (best-effort, jamais bloquante).
    await _essayer(_descendre);
    return AvoirCree(
      numeroAvoir: '${data['numero_avoir'] ?? ''}',
      entier: data['entier'] == true,
      normalisationStatut: data['normalisation_statut'] as String?,
      rejeu: data['rejeu'] == true,
    );
  }

  /// La normalisation e-MECeF de [pieceId], demandée AU SERVEUR (idempotente : une facture
  /// déjà normalisée n'est jamais retransmise, son résultat est rendu).
  Future<IssueEnLigne> normaliserParLeServeur(String pieceId) async {
    final piece = await _factures.parId(pieceId);
    if (piece == null) throw PieceIntrouvable(pieceId);
    if (piece.estAvoir) {
      return const RefusEnLigne(
        'Un avoir se normalise par le serveur à sa création : rien à demander ici.',
      );
    }
    if (piece.estAnnulee) {
      return const RefusEnLigne(
        'Cette facture est annulée : une facture annulée ne se normalise pas '
        '(sa correction est son avoir).',
      );
    }
    if (!IfuClient.valide(piece.acheteurIfu)) {
      return RefusEnLigne(TextesIfuClient.invalide);
    }

    final connexion = await _connexion(
      TextesFacturationModes.normalisationEnLigne,
    );
    if (connexion is RefusEnLigne) return connexion;
    final appairage = connexion as AppairagePoste;
    if (!await _factures.partAuServeur(pieceId)) {
      return const RefusEnLigne(_nonConnue);
    }

    final generation = await DescenteCatalogueDao(_base).generation();
    Future<IssueHttp> poster() => _transport.post(
      urlServeur(appairage.serveur, '/sync/factures/$pieceId/normalisation'),
      jeton: appairage.jetonApi,
      corps: {'poste_id': appairage.posteId, 'generation': ?generation},
    );

    var issue = await poster();
    if (issue is ReponseHttp &&
        issue.statut == 404 &&
        issue.corps?['code'] == 'facture_inconnue' &&
        _envoyerLaFile != null) {
      await _envoyerLaFile();
      issue = await poster();
    }

    final refus = _refus(issue, TextesFacturationModes.normalisationEnLigne);
    if (refus != null) return refus;
    final data = (issue as ReponseHttp).corps?['data'];
    if (data is! Map) return const RefusEnLigne(_reponseIllisible);

    final statut = StatutNormalisation.depuisCode(
      '${data['normalisation_statut']}',
    );
    if (statut == null) return const RefusEnLigne(_reponseIllisible);

    final ecrite = await _factures.adopterResultatServeur(
      pieceId,
      statut: statut,
      motif: data['normalisation_motif'] as String?,
      numeroMecef: data['numero_mecef'] as String?,
      qrCode: data['qr_code'] as String?,
      codeMecef: data['code_mecef'] as String?,
      compteur: data['compteur'] as String?,
      date: DateTime.tryParse('${data['date']}')?.toLocal(),
    );
    return NormalisationServeur(
      piece: ecrite,
      statut: ecrite.normalisationStatut ?? statut,
      motif: ecrite.normalisationMotif,
      rejeu: data['rejeu'] == true,
    );
  }

  static const String _reponseIllisible =
      'Le serveur a répondu sans les éléments attendus : rien n’a été écrit sur '
      'ce poste.';

  /// La phrase d'un refus, ou `null` si la réponse est un succès. [horsLigne] : la phrase du
  /// geste quand le serveur ne répond pas.
  RefusEnLigne? _refus(IssueHttp issue, String horsLigne) {
    switch (issue) {
      case ServeurInjoignable():
        return RefusEnLigne(horsLigne);
      case ReponseHttp(estSucces: true):
        return null;
      case ReponseHttp(statut: 401):
        return const RefusEnLigne(
          'Le serveur a refusé ce poste : l’appairage doit être refait.',
        );
      case ReponseHttp(statut: 403):
        return const RefusEnLigne(
          'Votre compte n’a pas le droit d’écrire en facturation sur le '
          'serveur, ou ce poste n’est pas reconnu.',
        );
      case ReponseHttp(statut: 404, :final corps)
          when corps?['code'] == 'facture_inconnue':
        return const RefusEnLigne(_nonConnue);
      case ReponseHttp(statut: 409):
        return const RefusEnLigne(
          'Le serveur a été réinitialisé depuis : ce poste doit d’abord se '
          'réinitialiser.',
        );
      case ReponseHttp(:final statut) when statut == 408 || statut >= 500:
        return RefusEnLigne(horsLigne);
      case ReponseHttp(:final corps, :final statut):
        final message = corps?['message'];
        return RefusEnLigne(
          message is String && message.isNotEmpty
              ? message
              : 'Refusé par le serveur (HTTP $statut).',
        );
    }
  }

  Future<void> _essayer(Future<void> Function()? geste) async {
    if (geste == null) return;
    try {
      await geste();
    } on Object {
      // La descente suivante la rattrapera : l'avoir existe déjà au serveur.
    }
  }
}
