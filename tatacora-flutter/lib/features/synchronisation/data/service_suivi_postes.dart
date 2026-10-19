import '../../transverse/data/configuration_poste.dart';
import 'transport_synchronisation.dart';

/// Ce que le serveur sait d'un poste (`GET /api/v1/sync/postes`).
final class EtatPosteServeur {
  const EtatPosteServeur({
    required this.posteId,
    required this.utilisateur,
    required this.derniereMontee,
    required this.derniereDescente,
    required this.enAttente,
    required this.demandeSuivie,
    this.appaire = false,
    this.jetonUtiliseLe,
  });

  final String posteId;
  final String? utilisateur;
  final DateTime? derniereMontee;
  final DateTime? derniereDescente;
  final int? enAttente;
  final bool demandeSuivie;

  /// Un jeton du nom de ce poste existe au serveur (19/10/2026).
  final bool appaire;
  final DateTime? jetonUtiliseLe;
}

/// L'état des postes et la dernière demande, ou la raison de leur absence.
sealed class IssueSuiviPostes {
  const IssueSuiviPostes();
}

final class SuiviPostesLu extends IssueSuiviPostes {
  const SuiviPostesLu({
    required this.demandeeLe,
    required this.postes,
    this.cePoste,
  });

  final DateTime? demandeeLe;
  final List<EtatPosteServeur> postes;

  /// Le nom de CE poste : il ne révoque pas son propre appairage (il se
  /// « Dissocie », Paramètres → Synchronisation).
  final String? cePoste;
}

final class SuiviPostesIndisponible extends IssueSuiviPostes {
  const SuiviPostesIndisponible(this.raison);

  final String raison;
}

/// L'écran « Synchroniser les postes » du poste (décision PO du 18/10/2026) :
/// la même page que la PWA, servie par l'API. Lire l'état des postes et
/// DEMANDER la synchronisation exigent le serveur : hors réseau, l'écran le
/// dit (rien n'est inventé ici).
class ServiceSuiviPostes {
  ServiceSuiviPostes({
    required this._transport,
    required String? urlServeur,
    LecteurConfigurationPoste? lecteur,
  }) : _url = urlServeur,
       _lecteur = lecteur ?? LecteurConfigurationPoste();

  final TransportSynchronisation _transport;
  final String? _url;
  final LecteurConfigurationPoste _lecteur;

  static const String horsReseau =
      'Le serveur ne répond pas : l’état des postes et la demande de '
      'synchronisation exigent une connexion au serveur.';
  static const String nonAppaire =
      'Ce poste n’est pas appairé à un serveur : rien à lire ni à demander.';

  Future<IssueSuiviPostes> lire() async {
    final appairage = await _appairage();
    if (appairage == null) return const SuiviPostesIndisponible(nonAppaire);
    final issue = await _transport.get(
      urlServeur(appairage.serveur, '/sync/postes'),
      jeton: appairage.jetonApi,
    );
    final data = _donnees(issue);
    if (data is! Map) return const SuiviPostesIndisponible(horsReseau);
    final postes = data['postes'];
    return SuiviPostesLu(
      cePoste: appairage.posteId,
      demandeeLe: _date(data['demandee_le']),
      postes: [
        if (postes is List)
          for (final p in postes.whereType<Map<Object?, Object?>>())
            EtatPosteServeur(
              posteId: '${p['poste_id']}',
              utilisateur: p['utilisateur'] as String?,
              derniereMontee: _date(p['derniere_montee']),
              derniereDescente: _date(p['derniere_descente']),
              enAttente: p['en_attente'] as int?,
              demandeSuivie: p['demande_suivie'] == true,
              appaire: p['appaire'] == true,
              jetonUtiliseLe: _date(p['jeton_utilise_le']),
            ),
      ],
    );
  }

  /// Enregistre la demande au serveur ; rend son heure, ou `null` hors
  /// réseau.
  Future<DateTime?> demander() async {
    final appairage = await _appairage();
    if (appairage == null) return null;
    final issue = await _transport.post(
      urlServeur(appairage.serveur, '/sync/demande'),
      jeton: appairage.jetonApi,
    );
    final data = _donnees(issue);
    return data is Map ? _date(data['demandee_le']) : null;
  }

  /// Révoque l'appairage d'un AUTRE poste (Administrateurs, 19/10/2026) :
  /// ses jetons sont supprimés au serveur, le poste révoqué reçoit 401 et
  /// garde sa file intacte. Rend la phrase à dire.
  Future<String> revoquer(String posteId) async {
    final appairage = await _appairage();
    if (appairage == null) return nonAppaire;
    final issue = await _transport.post(
      urlServeur(
        appairage.serveur,
        '/sync/postes/${Uri.encodeComponent(posteId)}/revocation',
      ),
      jeton: appairage.jetonApi,
    );
    if (issue is! ReponseHttp) return horsReseau;
    if (issue.estSucces) return revocationFaite(posteId);
    if (issue.statut == 403) return revocationReservee;
    final message = issue.corps?['message'];
    return message is String && message.isNotEmpty ? message : horsReseau;
  }

  static String revocationFaite(String poste) =>
      'Appairage du poste « $poste » révoqué.';
  static const String revocationReservee =
      "Seul un Administrateur peut révoquer l'appairage d'un poste.";

  Future<AppairagePoste?> _appairage() async {
    if (_url == null) return null;
    final a = await _lecteur.appairage();
    return a == null || a.refus != null ? null : a;
  }

  static Object? _donnees(IssueHttp issue) {
    if (issue is! ReponseHttp || !issue.estSucces) return null;
    return issue.corps == null ? null : issue.corps!['data'];
  }

  static DateTime? _date(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;
}
