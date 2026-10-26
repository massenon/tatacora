import '../../transverse/data/configuration_poste.dart';
import '../domain/appairage.dart';
import 'transport_synchronisation.dart';

/// L'APPAIRAGE du poste (lot F2a, 15/10/2026) : appairer, tester, dissocier.
///
/// Appelé par l'onglet « Synchronisation » de Paramètres (Administrateurs
/// seulement). Le jeton obtenu est écrit dans `poste.json`
/// ([EcrivainConfigurationPoste]) — jamais dans la base Drift, qui se copie et
/// s'exporte. Le mot de passe du compte serveur ne quitte pas [appairer] : il
/// part dans le corps de `POST /login` et n'est écrit ni gardé nulle part.
class ServiceAppairage {
  ServiceAppairage({
    required this._transport,
    required String? urlServeur,
    LecteurConfigurationPoste? lecteur,
    EcrivainConfigurationPoste? ecrivain,
    DateTime Function()? maintenant,
  }) : _url = urlServeur,
       _lecteur = lecteur ?? LecteurConfigurationPoste(),
       _ecrivain = ecrivain ?? EcrivainConfigurationPoste(),
       _maintenant = maintenant ?? DateTime.now;

  final TransportSynchronisation _transport;

  /// L'adresse de l'API du BUILD (`Environnement.actuel.baseUrl`) — jamais
  /// une saisie : un build de production ne doit pas pouvoir pointer
  /// ailleurs depuis l'interface. `null` en démonstration.
  final String? _url;
  final LecteurConfigurationPoste _lecteur;
  final EcrivainConfigurationPoste _ecrivain;
  final DateTime Function() _maintenant;

  /// L'appairage actuel du poste (relu du fichier).
  Future<AppairagePoste?> appairageActuel() => _lecteur.appairage();

  /// `POST /login` avec `poste` = [nomPoste] nettoyé ; le jeton rendu est
  /// enregistré. Les refus sont des phrases de [TextesAppairage], jamais la
  /// réponse du serveur.
  Future<ResultatAppairage> appairer({
    required String identifiant,
    required String motDePasse,
    required String nomPoste,
  }) async {
    final url = _url;
    if (url == null) {
      return const AppairageRefuse(TextesAppairage.demonstration);
    }
    if (!await _lecteur.synchronisationActivee()) {
      return const AppairageRefuse(TextesAppairage.desactivee);
    }
    final login = identifiant.trim();
    if (login.isEmpty || motDePasse.isEmpty || nomPoste.trim().isEmpty) {
      return const AppairageRefuse(TextesAppairage.champsObligatoires);
    }
    final poste = nettoyerNomPoste(nomPoste);
    if (poste == null) {
      return const AppairageRefuse(TextesAppairage.nomPosteInvalide);
    }

    final issue = await _transport.post(
      urlServeur(url, '/login'),
      corps: {'identifiant': login, 'mot_de_passe': motDePasse, 'poste': poste},
    );
    switch (issue) {
      case ServeurInjoignable():
        return const AppairageRefuse(TextesAppairage.serveurInjoignable);
      case ReponseHttp(:final statut) when statut != 200:
        return AppairageRefuse(messageRefusConnexion(statut));
      case ReponseHttp(:final corps):
        final jeton = corps?['token'];
        if (jeton is! String || jeton.isEmpty) {
          return const AppairageRefuse(
            'Réponse inattendue du serveur : aucun jeton reçu, l’appairage '
            'n’a pas été enregistré.',
          );
        }
        final utilisateur = corps?['utilisateur'];
        final compte = utilisateur is Map && utilisateur['login'] is String
            ? utilisateur['login'] as String
            : login;
        try {
          await _ecrivain.enregistrerAppairage(
            AppairagePoste(
              posteId: poste,
              jetonApi: jeton,
              serveur: url,
              appaireLe: _maintenant(),
              compte: compte,
            ),
          );
        } on ConfigurationPosteIllisible catch (e) {
          return AppairageRefuse(e.toString());
        }
        return AppairageReussi(posteId: poste, compte: compte);
    }
  }

  /// `GET /utilisateur` avec le jeton du poste. Rend la phrase à afficher. Un
  /// succès efface un refus consigné : le moteur d'envoi reprend.
  Future<String> testerConnexion() async {
    if (!await _lecteur.synchronisationActivee()) {
      return TextesAppairage.desactivee;
    }
    final appairage = await _lecteur.appairage();
    if (appairage == null) return TextesAppairage.nonAppaire;
    final issue = await _transport.get(
      urlServeur(appairage.serveur, '/utilisateur'),
      jeton: appairage.jetonApi,
    );
    switch (issue) {
      case ServeurInjoignable():
        return TextesAppairage.serveurInjoignable;
      case ReponseHttp(statut: 200, :final corps):
        try {
          await _ecrivain.effacerRefus();
        } on ConfigurationPosteIllisible {
          // Le refus reste consigné ; la phrase dit tout de même la vérité
          // sur le jeton.
        }
        final login = corps?['login'];
        return TextesAppairage.connexionEtablie(
          login is String ? login : appairage.compte,
        );
      case ReponseHttp(statut: 401):
        return TextesAppairage.jetonRefuse;
      case ReponseHttp(:final statut) when statut >= 500:
        return TextesAppairage.erreurServeur(statut);
      case ReponseHttp(:final statut):
        return TextesAppairage.reponseInattendue(statut);
    }
  }

  /// « Dissocier » : `POST /logout` tenté (son issue n'arrête rien — un poste
  /// hors connexion doit pouvoir être dissocié), puis le jeton est retiré du
  /// fichier. La file d'envoi n'est pas touchée.
  Future<String> dissocier() async {
    final appairage = await _lecteur.appairage();
    // Synchronisation désactivée : aucune requête, le jeton est retiré du
    // poste (le serveur le gardera valide jusqu'à son expiration ou sa
    // révocation depuis « Postes & Appairage »).
    if (appairage != null && await _lecteur.synchronisationActivee()) {
      try {
        await _transport.post(
          urlServeur(appairage.serveur, '/logout'),
          jeton: appairage.jetonApi,
        );
      } on Object {
        // Au mieux : le jeton est retiré du poste quoi qu'il arrive.
      }
    }
    try {
      await _ecrivain.retirerAppairage();
    } on ConfigurationPosteIllisible catch (e) {
      return e.toString();
    }
    return TextesAppairage.dissocie;
  }
}
