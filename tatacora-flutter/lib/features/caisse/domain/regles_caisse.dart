/// Les règles de la caisse — FONCTIONS PURES, montants en centimes entiers.
///
/// Réplique de `PosComptant::ouvrirCaisse`, `cloturerCaisse`,
/// `theoriqueDeLaSession` : le serveur n'a pas de service de domaine pour la
/// caisse, ces règles vivent dans un composant d'écran. Ici elles vivent dans le
/// domaine, sans Drift ni widget, pour qu'un test les éprouve seules — puis le
/// vrai composant PHP les confronte (`caisse_contre_serveur_test.dart`).
///
/// @see EF-M5-06 Vente au comptoir du bar
/// @see RG-15 Qui a ouvert la caisse
library;

import 'entities/session_caisse.dart';
import 'messages_caisse.dart';
import 'montant_caisse.dart';

/// Le champ d'une saisie refusée, pour que l'écran pose le message SOUS le bon
/// champ (le `@error('fondCaisseSaisi')` de la vue).
enum ChampCaisse {
  fond('fondCaisseSaisi', MessagesCaisse.attributFond),
  constate('montantConstateSaisi', MessagesCaisse.attributConstate);

  const ChampCaisse(this.propriete, this.attribut);

  /// Le nom de la propriété Livewire du serveur.
  final String propriete;

  /// L'attribut que Laravel écrit dans le message de validation.
  final String attribut;
}

/// Un geste refusé : rien n'a été écrit.
class RefusCaisse implements Exception {
  const RefusCaisse(this.message, {this.champ});

  final String message;

  /// Le champ visé, ou `null` pour un refus qui ne tient pas à une saisie
  /// (droit manquant).
  final ChampCaisse? champ;

  @override
  String toString() => message;
}

final RegExp _videAuSensDePhp = RegExp(r'^[ \t\n\r\v\x00]*$');

/// `['required', 'numeric', 'min:0']` — le contrôle de FORME de `validerEcriture`.
///
/// L'ordre est celui de Laravel : `required` (vide ou espaces seuls), puis
/// `numeric` (`is_numeric`), puis `min:0` sur la valeur EXACTE. Un seul message
/// sort : `min:0` sur une valeur non numérique compare une LONGUEUR, jamais
/// refusée.
///
/// Les deux refus qui suivent au serveur — plage de la colonne, `bcsub` — ne
/// sont PAS ici : ils tombent plus tard dans le déroulement du composant (après
/// « déjà ouverte » / « aucune caisse »), et l'ordre se voit dans le message
/// rendu. Voir [centimesStockables] et [exigerBienFormePourBc].
DecimalSaisi validerMontantSaisi(String? brut, ChampCaisse champ) {
  final valeur = brut ?? '';
  // `required` de Laravel : `trim()` de PHP (espace, \t, \n, \r, \v, NUL) — pas
  // le `trim()` de Dart, qui retire aussi l'espace insécable.
  if (_videAuSensDePhp.hasMatch(valeur)) {
    throw RefusCaisse(MessagesCaisse.obligatoire(champ.attribut), champ: champ);
  }
  final decimal = DecimalSaisi.lire(valeur);
  if (decimal == null) {
    throw RefusCaisse(MessagesCaisse.nombre(champ.attribut), champ: champ);
  }
  if (!decimal.respecteMinZero) {
    throw RefusCaisse(
      MessagesCaisse.minimum(champ.attribut, '0'),
      champ: champ,
    );
  }
  return decimal;
}

/// Ce que la colonne `DECIMAL(15,2)` stockerait (arrondi), ou le refus.
///
/// Le serveur écrit puis reçoit une `QueryException` (« Out of range value ») :
/// rien n'est écrit. Ici le refus précède l'écriture, avec sa propre phrase.
int centimesStockables(DecimalSaisi decimal, ChampCaisse champ) {
  final centimes = decimal.centimesArrondis;
  if (centimes == null) {
    throw RefusCaisse(MessagesCaisse.horsPlage, champ: champ);
  }
  return centimes;
}

/// `bcsub` du montant compté : le serveur accepte « 1.5e3 » au contrôle
/// `numeric`, puis plante (`ValueError`, HTTP 500) AVANT d'écrire — la session
/// reste ouverte. Le poste refuse, avec sa propre phrase.
void exigerBienFormePourBc(DecimalSaisi decimal, ChampCaisse champ) {
  if (!decimal.estBienFormePourBc) {
    throw RefusCaisse(MessagesCaisse.malForme, champ: champ);
  }
}

/// `theoriqueDeLaSession` : fond + espèces encaissées de la session.
///
/// Les espèces sont les ventes VALIDÉES réglées en `especes` de la session
/// (maître `caisse-ui.js` l.134-137) : Mobile Money, carte, virement, note de
/// chambre et ventes annulées n'y entrent pas.
int theoriqueCentimes({
  required int fondCentimes,
  required int especesCentimes,
}) => fondCentimes + especesCentimes;

/// L'écart ANNONCÉ à la clôture, en centimes : `bcsub(constaté, théorique, 2)`
/// sur la saisie brute (voir [DecimalSaisi.ecartTronque]).
int ecartAnnonceCentimes(DecimalSaisi constate, int theoriqueCentimes) =>
    constate.ecartTronque(theoriqueCentimes);

/// Le message d'issue d'une clôture, aux mots du serveur.
///
/// « aucun écart » seulement si l'écart est EXACTEMENT nul ; un écart de
/// quelques centimes dit « écart de 0 FCFA » — comportement du serveur
/// (`bccomp($ecart, '0.00')` avant l'arrondi du format), répliqué.
String messageCloture(PointDeVenteCaisse point, int ecartCentimes) {
  if (ecartCentimes == 0) return MessagesCaisse.clotureeSansEcart(point.code);
  return MessagesCaisse.cloturee(
    point.code,
    formaterCentimesEnFcfa(ecartCentimes),
  );
}

/// Le message d'issue d'une ouverture : « Caisse bar ouverte. ».
String messageOuverture(PointDeVenteCaisse point) =>
    MessagesCaisse.ouverte(point.code);
