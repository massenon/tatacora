import '../../../core/database/app_database.dart';
import '../../parametres/data/parametres_dao.dart';
import '../../transverse/data/configuration_poste.dart';
import '../domain/adresse_boitier.dart';
import '../domain/mode_facturation.dart';

/// L'état de la facturation normalisée de CE poste : ce que le serveur a
/// descendu, ce que le poste a surchargé, et ce qui en résulte.
final class EtatFacturationPoste {
  const EtatFacturationPoste({
    required this.modeServeur,
    required this.surcharge,
    required this.certifiePar,
    required this.adresseBoitier,
    required this.adresseBoitierChoisie,
  });

  /// Le dernier mode connu du serveur (« désactivé » tant qu'il n'a rien
  /// descendu).
  final ModeFacturation modeServeur;

  /// Le réglage local « ce poste certifie par », ou `null` (suivre le serveur).
  final SurchargeFacturation? surcharge;

  /// Ce que ce poste FAIT.
  final CertifiePar certifiePar;

  /// L'adresse du pilote en vigueur (la saisie, sinon le défaut).
  final String adresseBoitier;

  final bool adresseBoitierChoisie;
}

/// Lit le mode : la valeur descendue du serveur (`parametres_systeme_local`,
/// qui garde la dernière valeur connue hors ligne) et `poste.json`. Rien n'est
/// mis en cache : un réglage vaut pour l'opération qui suit.
class LecteurModeFacturation {
  LecteurModeFacturation(this._base, {LecteurConfigurationPoste? lecteur})
    : _lecteur = lecteur ?? LecteurConfigurationPoste();

  final AppDatabase _base;
  final LecteurConfigurationPoste _lecteur;

  Future<EtatFacturationPoste> lire() async {
    final valeurs = await ParametresDao(_base).lireTout();
    final modeServeur = modeDesParametres(valeurs);
    final surcharge = SurchargeFacturation.depuisCode(
      await _lecteur.surchargeFacturation(),
    );
    final choisie = await _lecteur.adresseBoitier();
    return EtatFacturationPoste(
      modeServeur: modeServeur,
      surcharge: surcharge,
      certifiePar: certifiePar(modeServeur: modeServeur, surcharge: surcharge),
      adresseBoitier: choisie ?? adresseBoitierParDefaut,
      adresseBoitierChoisie: choisie != null,
    );
  }
}
