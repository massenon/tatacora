import 'dart:async';
import 'dart:convert';

import '../domain/client_mecef.dart';
import '../domain/conversion_boitier.dart';
import '../domain/erreur_boitier.dart';
import 'pilote_boitier.dart';

/// Le client du boîtier CC300 : il implémente [ClientMecef] en parlant au
/// pilote local (`eltrade-cc300-driver`, `http://localhost:38917`).
///
/// ## Le protocole, et pourquoi chaque pas existe
///
///  1. la demande est CONVERTIE et ses sommes vérifiées AVANT toute requête ;
///  2. `GET /info` AVANT : l'IFU du boîtier doit être celui de l'entreprise, et
///     le compteur (ventes ou avoirs) est noté — c'est lui qui tranchera le cas
///     d'une réponse perdue ;
///  3. [surEnvoi] range ce compteur sur la pièce AVANT le `POST` ;
///  4. `POST /bill` (30 s). Le pilote répond 200 MÊME EN CAS D'ÉCHEC : le corps
///     est VALIDÉ — un `qr_code` non vide, `F;NIM;code;IFU;date`, du NIM du
///     boîtier, sans « E: » ;
///  5. succès net : `GET /info` APRÈS, le compteur doit valoir avant + 1 ;
///  6. tout autre cas (corps vide ou erroné, coupure, délai) : `GET /info` pour
///     trancher — compteur inchangé : rien n'a été facturé ([EnAttente],
///     rejouable) ; compteur avancé : [AVerifier], JAMAIS rejouée.
///
/// ## Jamais deux `POST /bill` à la fois
///
/// Un verrou par poste (en mémoire, partagé par toutes les instances) : un
/// second appel pendant qu'un envoi est en cours rend [EnAttente] sans toucher
/// au boîtier — il ne se met pas en file, il se rejoue.
class ClientMecefBoitier implements ClientMecef {
  ClientMecefBoitier({
    required this._pilote,
    required String ifuEntreprise,
    DateTime Function()? maintenant,
    this.attenteApresDelai = const Duration(seconds: 6),
  }) : _ifu = ifuEntreprise.trim(),
       _maintenant = maintenant ?? DateTime.now;

  final PiloteBoitier _pilote;

  /// Après un DÉLAI, le boîtier peut encore terminer : on lui laisse ce temps
  /// avant de relire son compteur (un compteur lu trop tôt dirait « rien » d'une
  /// facture en cours d'enregistrement).
  final Duration attenteApresDelai;
  final String _ifu;
  final DateTime Function() _maintenant;

  /// Le verrou du poste : un seul envoi à la fois, toutes instances confondues.
  static bool _envoiEnCours = false;

  /// Pour les tests : le verrou est-il pris ?
  static bool get verrouPris => _envoiEnCours;

  @override
  bool get estModeReel => true;

  @override
  Future<IssueCertification> certifier(
    DemandeNormalisation demande, {
    String? compteurAvantPrecedent,
    FutureOr<void> Function(String compteurAvant)? surEnvoi,
  }) async {
    // 1. Conversion et sommes : AVANT toute requête.
    final String json;
    try {
      json = construireJsonPilote(demande);
    } on ErreurBoitier catch (e) {
      return EnAttente(e.message);
    }

    if (_envoiEnCours) return const EnAttente(TextesBoitier.enCours);
    _envoiEnCours = true;
    try {
      return await _certifierSousVerrou(
        demande,
        json,
        compteurAvantPrecedent,
        surEnvoi,
      );
    } finally {
      _envoiEnCours = false;
    }
  }

  int? _compteur(InfoBoitier info, DemandeNormalisation d) =>
      d.estAvoir ? info.compteurAvoirs : info.compteurVentes;

  Future<IssueCertification> _certifierSousVerrou(
    DemandeNormalisation demande,
    String json,
    String? compteurAvantPrecedent,
    FutureOr<void> Function(String compteurAvant)? surEnvoi,
  ) async {
    // 2. L'état du boîtier AVANT.
    final InfoBoitier avant;
    try {
      avant = await _pilote.info();
    } on ErreurBoitier catch (e) {
      return EnAttente(e.message);
    }
    if (_ifu.isNotEmpty && avant.ifu != _ifu) {
      return EnAttente(TextesBoitier.ifuDifferent(avant.ifu, _ifu));
    }
    final compteurAvant = _compteur(avant, demande);
    if (compteurAvant == null) {
      return const EnAttente(
        'Le compteur du boîtier est illisible : la facture n’est pas envoyée '
        'pour ne pas risquer de la facturer deux fois.',
      );
    }

    // Une tentative précédente dont l'issue n'a pas été tranchée : le compteur
    // dit si elle a abouti.
    final precedent = int.tryParse(compteurAvantPrecedent ?? '');
    if (precedent != null && compteurAvant > precedent) {
      return AVerifier(
        TextesBoitier.enregistreeSansCode(precedent, compteurAvant),
        compteurAvant: '$precedent',
        compteurApres: '$compteurAvant',
      );
    }

    // 3. La trace de l'envoi, rangée AVANT que la requête parte.
    await surEnvoi?.call('$compteurAvant');

    // 4. L'envoi.
    final issue = await _pilote.poster(json);
    switch (issue) {
      case PostNonEnvoye(:final cause):
        return EnAttente(cause.message);
      case PostRepondu(:final reponse):
        if (reponse.statut == 503) {
          return const EnAttente(TextesBoitier.appareilAbsent);
        }
        if (reponse.statut == 400) {
          return Refusee(TextesBoitier.refus(_detailRefus(reponse.corps)));
        }
        if (reponse.statut == 200) {
          final qr = _qrValide(reponse.corps, avant.nim);
          if (qr != null) {
            return _apresSucces(demande, qr, compteurAvant);
          }
        }
        return _trancher(
          demande,
          compteurAvant,
          const ErreurBoitier(
            CauseBoitier.reponseInvalide,
            TextesBoitier.reponseInvalide,
          ),
        );
      case PostIncertain(:final cause):
        if (cause.cause == CauseBoitier.delai &&
            attenteApresDelai > Duration.zero) {
          await Future<void>.delayed(attenteApresDelai);
        }
        return _trancher(demande, compteurAvant, cause, incertaine: true);
    }
  }

  /// Le succès net : le compteur APRÈS donne le « TC ».
  Future<IssueCertification> _apresSucces(
    DemandeNormalisation demande,
    _Qr qr,
    int compteurAvant,
  ) async {
    final InfoBoitier apres;
    try {
      apres = await _pilote.info();
    } on ErreurBoitier {
      return AVerifier(
        'La facture est enregistrée (le boîtier a rendu son code) mais son '
        'compteur n’a pas pu être relu : vérifiez le boîtier avant de remettre '
        'le ticket.',
        compteurAvant: '$compteurAvant',
        qrCode: qr.brut,
        nim: qr.nim,
        codeMecef: qr.code,
      );
    }
    final tc = _compteur(apres, demande);
    if (tc == null || tc != compteurAvant + 1) {
      return AVerifier(
        'La facture est enregistrée (le boîtier a rendu son code) mais son '
        'compteur est inattendu (avant $compteurAvant, après '
        '${tc ?? 'illisible'}) : vérifiez le boîtier avant de remettre le '
        'ticket.',
        compteurAvant: '$compteurAvant',
        compteurApres: tc?.toString(),
        qrCode: qr.brut,
        nim: qr.nim,
        codeMecef: qr.code,
      );
    }
    return Certifiee(
      CertificationMecefResultat(
        nim: qr.nim,
        compteur: tc,
        codeMecef: qr.code,
        qrCode: qr.brut,
        dateCertification: qr.date ?? _maintenant(),
      ),
    );
  }

  /// Pas de code valide, ou réponse perdue : le COMPTEUR tranche.
  Future<IssueCertification> _trancher(
    DemandeNormalisation demande,
    int compteurAvant,
    ErreurBoitier cause, {
    bool incertaine = false,
  }) async {
    final InfoBoitier apres;
    try {
      apres = await _pilote.info();
    } on ErreurBoitier {
      return AVerifier(
        TextesBoitier.sansReponseNiCompteur,
        compteurAvant: '$compteurAvant',
      );
    }
    final c = _compteur(apres, demande);
    if (c == null) {
      return AVerifier(
        TextesBoitier.sansReponseNiCompteur,
        compteurAvant: '$compteurAvant',
      );
    }
    if (c > compteurAvant) {
      return AVerifier(
        TextesBoitier.enregistreeSansCode(compteurAvant, c),
        compteurAvant: '$compteurAvant',
        compteurApres: '$c',
      );
    }
    // Compteur inchangé : rien n'a été facturé, la pièce se rejoue — en gardant
    // le compteur noté quand la requête est partie sans réponse (le rejeu le
    // compare avant de reposter).
    return EnAttente(
      cause.message,
      incertaine: incertaine,
      compteurAvant: incertaine ? '$compteurAvant' : null,
    );
  }

  /// Un `qr_code` valide : non vide, `F;NIM;code;IFU;date`, cinq champs, du NIM
  /// du boîtier, sans « E: » ; `null` sinon.
  static _Qr? _qrValide(String corps, String nimAttendu) {
    final Object? json;
    try {
      json = jsonDecode(corps);
    } on Object {
      return null;
    }
    if (json is! Map<String, Object?>) return null;
    final brut = json['qr_code'];
    if (brut is! String) return null;
    final qr = brut.trim();
    if (qr.isEmpty || qr.contains('E:')) return null;
    final champs = qr.split(';');
    if (champs.length != 5 || champs[0] != 'F') return null;
    final nim = champs[1].trim();
    final code = champs[2].trim();
    if (nim.isEmpty || code.isEmpty || champs[3].trim().isEmpty) return null;
    if (nimAttendu.isNotEmpty && nim != nimAttendu) return null;
    return _Qr(qr, nim, code, _dateDuQr(champs[4].trim()));
  }

  static DateTime? _dateDuQr(String s) {
    final m = RegExp(
      r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$',
    ).firstMatch(s);
    if (m == null) return null;
    final v = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
    return DateTime(v[0], v[1], v[2], v[3], v[4], v[5]);
  }

  /// Le détail d'un refus 400 du pilote (`{"errors": "[…]"}`), sans jamais citer
  /// la facture. Court, en clair.
  static String _detailRefus(String corps) {
    try {
      final json = jsonDecode(corps);
      if (json is Map<String, Object?>) {
        final e = '${json['errors'] ?? ''}'.trim();
        if (e.isNotEmpty) {
          final net = nettoyerTexte(e.replaceAll(RegExp(r'[\[\]]'), ''), 160);
          if (net.isNotEmpty) return net;
        }
      }
    } on Object {
      // Corps illisible : message générique ci-dessous.
    }
    return 'le contenu de la facture ne respecte pas le format du boîtier.';
  }
}

final class _Qr {
  const _Qr(this.brut, this.nim, this.code, this.date);
  final String brut;
  final String nim;
  final String code;
  final DateTime? date;
}
