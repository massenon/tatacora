/// Le TÉLÉCHARGEMENT À LA DEMANDE du reçu d'une dépense (lot L4, décision du PO
/// du 27/10/2026).
///
/// La descente ne porte que la RÉFÉRENCE du reçu (empreinte, taille, type) :
/// jamais le fichier, jamais en masse. Le fichier ne vient qu'au clic de
/// l'opérateur sur « reçu » d'une dépense d'un autre poste, par
/// `GET /sync/depenses/{id}/recu`. Une fois téléchargé, il est vérifié (image
/// reconnue, taille bornée, empreinte égale à celle de la référence), rangé
/// dans `recus_depenses/`, et ne se retélécharge plus.
///
/// ## Aucune requête hors des règles de la synchronisation
///
/// L'interrupteur « Synchronisation activée » est relu à CHAQUE demande
/// ([LecteurConfigurationPoste.synchronisationActivee]) : éteint, le poste ne
/// touche pas le réseau — il dit pourquoi le reçu n'est pas là. Démonstration,
/// poste non appairé, jeton refusé, autre serveur : de même, une phrase, pas
/// de requête.
library;

import '../../../core/database/app_database.dart';
import '../../depenses/data/depense_dao.dart';
import '../../depenses/data/recus_depenses_locaux.dart';
import '../../depenses/domain/recu_depense.dart';
import '../../transverse/data/configuration_poste.dart';
import 'descente_catalogue_dao.dart';
import 'transport_synchronisation.dart';

/// L'issue d'une demande de reçu.
sealed class IssueRecuDistant {
  const IssueRecuDistant();
}

/// Le fichier est sur ce poste (déjà là, ou téléchargé à l'instant).
final class RecuDisponible extends IssueRecuDistant {
  const RecuDisponible({required this.octets, required this.type});

  final List<int> octets;
  final TypeRecu type;
}

/// Le fichier n'a pas pu venir : la phrase DIT pourquoi.
final class RecuIndisponible extends IssueRecuDistant {
  const RecuIndisponible(this.phrase);

  final String phrase;
}

/// Les phrases de ce que le téléchargement ne peut pas faire.
abstract final class TextesRecuDistant {
  static const String demonstration =
      'Démonstration : aucun reçu ne se télécharge.';
  static const String desactivee =
      'La synchronisation est désactivée sur ce poste : le reçu ne peut pas '
      'être téléchargé. Réactivez-la dans Paramètres, onglet Synchronisation.';
  static const String nonAppaire =
      'Ce poste n’est pas appairé au serveur : le reçu ne peut pas être '
      'téléchargé.';
  static const String refuse =
      'Le serveur a refusé ce poste : le reçu ne peut pas être téléchargé.';
  static const String autreServeur =
      'Ce poste est appairé à un autre serveur que celui de ce logiciel : le '
      'reçu ne peut pas être téléchargé.';
  static const String reinitialise =
      'Le serveur a été réinitialisé depuis : le reçu ne peut pas être '
      'téléchargé avant la réinitialisation de ce poste.';
  static const String injoignable =
      'Le serveur est injoignable ou indisponible : réessayez quand le réseau '
      'revient.';
  static const String introuvable = 'Ce reçu n’est plus sur le serveur.';
  static const String droit =
      'Votre compte n’a pas le droit de lire les dépenses sur le serveur.';
  static const String inconnue = 'Cette dépense n’a pas de reçu.';
  static const String illisible =
      'Le fichier reçu du serveur n’est pas une image reconnue : il n’a pas '
      'été conservé.';
  static const String empreinte =
      'Le fichier reçu ne correspond pas à son empreinte : il n’a pas été '
      'conservé. Réessayez.';
  static const String tropLourd =
      'Le fichier annoncé par le serveur est trop lourd pour ce poste : il '
      'n’a pas été téléchargé.';
}

class TelechargementRecuDepense {
  TelechargementRecuDepense({
    required this._db,
    required this._transport,
    required this._recus,
    required String? urlServeur,
    required this._demonstration,
    LecteurConfigurationPoste? lecteur,
    this.tailleMaxOctets = 5 * 1024 * 1024,
  }) : _url = urlServeur,
       _lecteur = lecteur ?? LecteurConfigurationPoste();

  final AppDatabase _db;
  final TransportFichiers _transport;
  final RecusDepensesLocaux _recus;
  final String? _url;
  final bool _demonstration;
  final LecteurConfigurationPoste _lecteur;

  /// La borne d'un fichier téléchargé : le web borne ses dépôts à 400 Ko, mais
  /// un reçu plus ancien peut être plus gros ; au-delà, on ne le prend pas.
  final int tailleMaxOctets;

  /// Le fichier du reçu de [depenseId] : celui du poste s'il y est, sinon
  /// téléchargé.
  Future<IssueRecuDistant> obtenir(String depenseId) async {
    final dao = DepenseDao(_db, recus: _recus);
    final depense = await dao.parId(depenseId);
    final recu = depense?.recu;
    if (recu == null) return const RecuIndisponible(TextesRecuDistant.inconnue);

    // Le fichier est déjà là : aucune requête.
    final present = await _recus.lire(recu.nom);
    if (present != null) {
      final type = typeRecuDepuisOctets(present);
      if (type != null) return RecuDisponible(octets: present, type: type);
    }

    if (_demonstration || _url == null) {
      return const RecuIndisponible(TextesRecuDistant.demonstration);
    }
    // L'INTERRUPTEUR, relu à chaque demande.
    if (!await _lecteur.synchronisationActivee()) {
      return const RecuIndisponible(TextesRecuDistant.desactivee);
    }
    final appairage = await _lecteur.appairage();
    if (appairage == null) {
      return const RecuIndisponible(TextesRecuDistant.nonAppaire);
    }
    if (appairage.refus != null) {
      return const RecuIndisponible(TextesRecuDistant.refuse);
    }
    if (_sansBarre(appairage.serveur) != _sansBarre(_url)) {
      return const RecuIndisponible(TextesRecuDistant.autreServeur);
    }
    final etat = DescenteCatalogueDao(_db);
    if (await etat.reinitialisationServeur() != null) {
      return const RecuIndisponible(TextesRecuDistant.reinitialise);
    }
    final generation = await etat.generation();

    final issue = await _transport.telecharger(
      urlServeur(appairage.serveur, '/sync/depenses/$depenseId/recu').replace(
        queryParameters: {
          'poste_id': appairage.posteId,
          'generation': ?generation,
        },
      ),
      jeton: appairage.jetonApi,
    );

    switch (issue) {
      case ServeurInjoignable():
        return const RecuIndisponible(TextesRecuDistant.injoignable);
      case ReponseHttp(statut: 404):
        return const RecuIndisponible(TextesRecuDistant.introuvable);
      case ReponseHttp(statut: 401):
        return const RecuIndisponible(TextesRecuDistant.refuse);
      case ReponseHttp(statut: 403):
        return const RecuIndisponible(TextesRecuDistant.droit);
      case ReponseHttp(statut: 409):
        return const RecuIndisponible(TextesRecuDistant.reinitialise);
      case ReponseHttp(:final statut)
          when statut == 408 || statut == 429 || statut >= 500:
        return const RecuIndisponible(TextesRecuDistant.injoignable);
      case ReponseHttp(:final statut, :final octets) when statut == 200:
        return _ranger(dao, depenseId, recu, octets, issue.entetes);
      case ReponseHttp(:final statut):
        return RecuIndisponible('Refusé par le serveur (HTTP $statut).');
    }
  }

  Future<IssueRecuDistant> _ranger(
    DepenseDao dao,
    String depenseId,
    RecuDepense reference,
    List<int> octets,
    Map<String, String> entetes,
  ) async {
    if (octets.length > tailleMaxOctets) {
      return const RecuIndisponible(TextesRecuDistant.tropLourd);
    }
    final type = typeRecuDepuisOctets(octets);
    if (type == null) {
      return const RecuIndisponible(TextesRecuDistant.illisible);
    }

    final observee = RecusDepensesLocaux.empreinte(octets);
    final annoncee = entetes['x-recu-sha256'];
    if ((reference.sha256 != null && reference.sha256 != observee) ||
        (annoncee != null && annoncee != observee)) {
      return const RecuIndisponible(TextesRecuDistant.empreinte);
    }
    final range = await _recus.ranger(depenseId, type, octets);
    await dao.retenirFichierTelecharge(depenseId, range: range, type: type);
    return RecuDisponible(octets: octets, type: type);
  }

  static String _sansBarre(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}
