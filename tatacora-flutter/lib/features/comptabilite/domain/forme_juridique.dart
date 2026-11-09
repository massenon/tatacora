/// La FORME JURIDIQUE de l'établissement, telle que ce poste la lit — miroir de
/// `FormeJuridique` du serveur (09/11/2026, décision du PO : « le Gîte est une
/// ENTREPRISE INDIVIDUELLE, pas une SARL »).
///
/// Réglée au SERVEUR par un administrateur (refusée tant qu'une affectation du
/// résultat est active) et DESCENDUE ici en lecture seule avec les autres
/// paramètres (clé [cleFormeJuridique]) : comme le mode de la facturation, elle se
/// règle là où l'on sait si une affectation est active.
///
/// Elle commande les règles de l'affectation du résultat
/// (`affectation_resultat.dart`) : une entreprise individuelle n'a ni réserve
/// légale, ni dividendes, ni procès-verbal d'assemblée ; une SARL ou une SA a une
/// réserve légale obligatoire et des dividendes encadrés.
///
/// Une valeur inconnue (clé absente, base ancienne, valeur illisible) vaut
/// ENTREPRISE INDIVIDUELLE : le défaut du Gîte, et le sens prudent (ni dividende
/// ni réserve légale offerts).
library;

/// La clé du paramètre système (reçu du serveur, jamais écrit ici).
const String cleFormeJuridique = 'forme_juridique';

enum FormeJuridique {
  entrepriseIndividuelle('entreprise_individuelle', 'Entreprise individuelle'),
  sarl('sarl', 'SARL'),
  sa('sa', 'SA');

  const FormeJuridique(this.code, this.libelle);

  final String code;

  /// `comptabilite.forme_juridique_<code>` du serveur.
  final String libelle;

  /// Une société (SARL, SA) a des associés, une réserve légale et des dividendes.
  bool get estSociete => this != FormeJuridique.entrepriseIndividuelle;

  /// Jamais d'exception : une valeur inconnue est l'entreprise individuelle.
  static FormeJuridique depuisCode(String? valeur) {
    final v = (valeur ?? '').trim().toLowerCase();
    for (final f in values) {
      if (f.code == v) return f;
    }
    return FormeJuridique.entrepriseIndividuelle;
  }
}
