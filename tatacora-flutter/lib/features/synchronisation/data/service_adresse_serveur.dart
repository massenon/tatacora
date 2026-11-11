import '../../transverse/data/configuration_poste.dart';
import '../../transverse/data/journal_securite_dao.dart';
import '../../transverse/domain/journal_poste.dart';
import '../domain/adresse_serveur.dart';
import '../domain/appairage.dart';
import 'descente_catalogue.dart';
import 'transport_synchronisation.dart';

/// L'ADRESSE DU SERVEUR du poste : la lire, la tester, l'enregistrer
/// (29/10/2026, demande du Product Owner). Appelé par Paramètres →
/// « Synchronisation » (Administrateurs seulement).
///
/// ## Ce que ce service écrit, et ne touche pas
///
/// Il écrit `poste.json` ([EcrivainConfigurationPoste]) et UNE ligne du journal
/// de sécurité du poste ([JournalSecuriteDao.tracer], « Adresse du serveur
/// modifiée », ancienne → nouvelle adresse, auteur et machine). Il ne touche
/// NI à la file d'envoi (`operations_sync_local`), NI aux curseurs : seul le
/// repli de la descente du catalogue est levé, pour que le poste réessaie sans
/// attendre le délai de l'ancien serveur. Jamais le jeton n'est lu pour être
/// affiché ou journalisé.
///
/// ## Le poste fonctionne sans le serveur
///
/// Enregistrer une adresse ne fait AUCUNE requête et ne bloque rien. Seul
/// [tester] interroge le réseau, à la demande, et sans rien écrire.
class ServiceAdresseServeur {
  ServiceAdresseServeur({
    required this._transport,
    required this._urlParDefaut,
    required this._journal,
    LecteurConfigurationPoste? lecteur,
    EcrivainConfigurationPoste? ecrivain,
    this._descente,
    DateTime Function()? maintenant,
  }) : _lecteur = lecteur ?? LecteurConfigurationPoste(),
       _ecrivain = ecrivain ?? EcrivainConfigurationPoste(),
       _maintenant = maintenant ?? DateTime.now;

  final TransportSynchronisation _transport;

  /// L'adresse de l'API du BUILD, valeur par défaut. `null` : démonstration.
  final String? _urlParDefaut;
  final JournalSecuriteDao _journal;
  final LecteurConfigurationPoste _lecteur;
  final EcrivainConfigurationPoste _ecrivain;
  final DescenteCatalogue? _descente;
  final DateTime Function() _maintenant;

  /// L'adresse en vigueur : celle choisie à l'écran, sinon celle du build.
  /// `null` en démonstration.
  Future<EtatAdresseServeur?> etat() async {
    final defaut = racineDepuisUrlApi(_urlParDefaut);
    if (defaut == null) return null;
    final choisie = await _lecteur.adresseServeurChoisie();
    final enregistree = racineDepuisUrlApi(await _lecteur.adresseServeur());
    return EtatAdresseServeur(
      racine: choisie && enregistree != null ? enregistree : defaut,
      choisie: choisie,
      appaire: await _lecteur.appairage() != null,
    );
  }

  /// `GET <racine>/up` — l'endroit public où Laravel dit qu'il est en vie. Sans
  /// jeton, sans écriture. Rend la phrase à afficher et si elle est bonne.
  Future<({String message, bool succes})> tester(String saisie) async {
    final resultat = validerAdresseServeur(saisie);
    if (resultat is AdresseInvalide) {
      return (message: resultat.message, succes: false);
    }
    if (!await _lecteur.synchronisationActivee()) {
      return (message: TextesAppairage.desactivee, succes: false);
    }
    final adresse = (resultat as AdresseValide).adresse;
    final issue = await _transport.get(Uri.parse(adresse.urlSante));
    return switch (issue) {
      ServeurInjoignable() => (
        message: TextesAppairage.serveurInjoignable,
        succes: false,
      ),
      ReponseHttp(statut: >= 200 && < 300) => (
        message: TextesEssaiAdresse.reponse(adresse.racine),
        succes: true,
      ),
      ReponseHttp(:final statut) => (
        message: TextesEssaiAdresse.reponseInattendue(statut),
        succes: false,
      ),
    };
  }

  /// Enregistre [saisie] (validée ici, une seconde fois). [effacerJeton] : le
  /// jeton d'appairage de l'ancien serveur part dans la même écriture.
  Future<ResultatEnregistrementAdresse> enregistrer(
    String saisie, {
    required String auteurLogin,
    bool effacerJeton = false,
  }) async {
    final resultat = validerAdresseServeur(saisie);
    if (resultat is AdresseInvalide) {
      return AdresseRefusee(resultat.message);
    }
    final adresse = (resultat as AdresseValide).adresse;
    final avant = await etat();
    if (avant == null) {
      return const AdresseRefusee(TextesAppairage.demonstration);
    }
    if (avant.racine == adresse.racine && !effacerJeton) {
      // Même adresse : si elle venait du build, la poser en fait un CHOIX
      // inutile ; on ne touche à rien.
      return AdresseInchangee(adresse.racine);
    }
    try {
      await _ecrivain.enregistrerAdresseServeur(
        adresse.urlApi,
        par: auteurLogin,
        le: _maintenant(),
        effacerJeton: effacerJeton,
      );
    } on ConfigurationPosteIllisible catch (e) {
      return AdresseRefusee(e.toString());
    }
    await _journal.tracer(
      action: ActionJournalPoste.adresseServeurModifiee,
      auteurLogin: auteurLogin,
      cibleLogin: '${avant.racine} → ${adresse.racine}',
    );
    // Les états de reprise réseau de l'ancien serveur ne valent pas pour le
    // nouveau. La file et les curseurs, eux, ne bougent pas.
    try {
      await _descente?.leverRepli();
    } on Object {
      // Au mieux : le repli expirera de lui-même.
    }
    return AdresseEnregistree(
      adresse.racine,
      jetonEfface: effacerJeton && avant.appaire,
    );
  }
}

/// L'adresse en vigueur sur ce poste.
final class EtatAdresseServeur {
  const EtatAdresseServeur({
    required this.racine,
    required this.choisie,
    required this.appaire,
  });

  /// `https://hote` — celle qui sert aux requêtes.
  final String racine;

  /// Choisie à l'écran (`true`) ou reprise du build (`false`).
  final bool choisie;

  /// Le poste porte un jeton d'appairage.
  final bool appaire;
}

sealed class ResultatEnregistrementAdresse {
  const ResultatEnregistrementAdresse();
}

final class AdresseEnregistree extends ResultatEnregistrementAdresse {
  const AdresseEnregistree(this.racine, {required this.jetonEfface});

  final String racine;
  final bool jetonEfface;
}

final class AdresseInchangee extends ResultatEnregistrementAdresse {
  const AdresseInchangee(this.racine);

  final String racine;
}

final class AdresseRefusee extends ResultatEnregistrementAdresse {
  const AdresseRefusee(this.message);

  final String message;
}

/// Les phrases de l'essai de l'adresse.
abstract final class TextesEssaiAdresse {
  static String reponse(String racine) =>
      'Le serveur répond à cette adresse ($racine). Rien n’a été enregistré.';
  static String reponseInattendue(int code) =>
      'Une machine répond à cette adresse, mais pas comme le serveur '
      'LogiReStock (code $code). Vérifiez l’adresse. Rien n’a été enregistré.';
}
