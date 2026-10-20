/// Le VOYANT de synchronisation de la barre supérieure (lot F3, demande du
/// Product Owner du 16/10/2026 : « une synchronisation manuelle à partir d'un
/// bouton sur le topbar qui ouvre un modal »). Pur, sans base ni widget.
///
/// ## Une couleur ne dit que ce qui est VÉRIFIÉ (piège 1)
///
/// | Teinte | Quand | Ce que la phrase affirme |
/// |---|---|---|
/// | gris | démonstration, poste non appairé, serveur injoignable sans rien en attente | rien ne part (ou : on ne sait pas joindre le serveur) |
/// | rouge | refus du jeton, serveur réinitialisé, opération rejetée / en conflit / bloquée | quelque chose attend un humain |
/// | orange | opérations en attente ou en cours d'envoi | N opérations ne sont pas encore au serveur |
/// | vert | AUCUNE opération en attente, aucune à traiter | tout ce que ce poste a saisi est au serveur |
///
/// Le vert ne se dit pas « synchronisé » au sens large : il ne garantit pas
/// que le poste a REÇU tout ce que les autres ont saisi depuis (la descente
/// a son propre bilan, dit dans la modale).
library;

import 'bilan_synchronisation.dart';
import 'operation_sync.dart';

/// La couleur du voyant. Registre fermé.
enum TeinteVoyant { gris, rouge, orange, vert }

/// Ce que montre le bouton : une teinte, un badge (ou rien), une phrase.
final class VoyantSynchronisation {
  const VoyantSynchronisation({
    required this.teinte,
    required this.phrase,
    this.badge,
  });

  final TeinteVoyant teinte;

  /// Le nombre du badge — `null` : aucun badge (jamais un « 0 »).
  final int? badge;

  /// La phrase de l'état — infobulle du bouton, en-tête de la modale.
  final String phrase;

  @override
  bool operator ==(Object other) =>
      other is VoyantSynchronisation &&
      other.teinte == teinte &&
      other.badge == badge &&
      other.phrase == phrase;

  @override
  int get hashCode => Object.hash(teinte, badge, phrase);

  @override
  String toString() => 'Voyant(${teinte.name}, $badge, $phrase)';
}

/// Les phrases du voyant.
abstract final class TextesVoyant {
  static const demonstration = 'Démonstration : aucune synchronisation.';
  static const nonAppaire =
      'Poste non appairé : rien ne part, rien ne descend.';
  static const jetonRefuse =
      'Jeton refusé par le serveur — réappairer le poste.';
  static const serveurReinitialise =
      'Le serveur a été réinitialisé : réinitialisez ce poste avant de '
      'reprendre la synchronisation.';
  static String aTraiter(int n) =>
      '$n opération(s) refusée(s), en conflit ou bloquée(s) : à traiter.';
  static String enAttente(int n) =>
      '$n opération(s) en attente d\'envoi au serveur.';
  static String enAttenteInjoignable(int n) =>
      '$n opération(s) en attente : serveur injoignable, nouvel essai '
      'automatique plus tard.';
  static const injoignable =
      'Serveur injoignable : nouvel essai automatique plus tard.';
  static const toutEnvoye = 'Tout ce que ce poste a saisi est au serveur.';
  static const enCours = 'Synchronisation en cours…';
}

/// Le voyant d'un état. [refusJeton] : un 401/403 consigné à l'appairage
/// (plus rien ne part avant réappairage). [bilan] : le dernier passage du
/// moteur dans CETTE session (`null` : aucun).
VoyantSynchronisation voyantDe({
  required bool interdite,
  required bool appaire,
  required bool refusJeton,
  bool serveurReinitialise = false,
  required Map<StatutOperationSync, int> comptes,
  required BilanSynchronisation? bilan,
  required bool enCours,
}) {
  int n(StatutOperationSync s) => comptes[s] ?? 0;
  final aTraiter =
      n(StatutOperationSync.rejete) +
      n(StatutOperationSync.conflit) +
      n(StatutOperationSync.bloque);
  final attente =
      n(StatutOperationSync.enAttente) + n(StatutOperationSync.enCours);
  int? badge(int v) => v > 0 ? v : null;

  if (interdite) {
    return const VoyantSynchronisation(
      teinte: TeinteVoyant.gris,
      phrase: TextesVoyant.demonstration,
    );
  }
  if (!appaire) {
    return VoyantSynchronisation(
      teinte: TeinteVoyant.gris,
      badge: badge(attente),
      phrase: TextesVoyant.nonAppaire,
    );
  }
  if (refusJeton) {
    return VoyantSynchronisation(
      teinte: TeinteVoyant.rouge,
      badge: badge(attente + aTraiter),
      phrase: TextesVoyant.jetonRefuse,
    );
  }
  if (serveurReinitialise) {
    return VoyantSynchronisation(
      teinte: TeinteVoyant.rouge,
      badge: badge(attente + aTraiter),
      phrase: TextesVoyant.serveurReinitialise,
    );
  }
  if (aTraiter > 0) {
    return VoyantSynchronisation(
      teinte: TeinteVoyant.rouge,
      badge: aTraiter,
      phrase: TextesVoyant.aTraiter(aTraiter),
    );
  }
  if (enCours) {
    return VoyantSynchronisation(
      teinte: TeinteVoyant.orange,
      badge: badge(attente),
      phrase: TextesVoyant.enCours,
    );
  }
  final injoignable = bilan?.etat == EtatSynchronisation.serveurIndisponible;
  if (attente > 0) {
    return VoyantSynchronisation(
      teinte: TeinteVoyant.orange,
      badge: attente,
      phrase: injoignable
          ? TextesVoyant.enAttenteInjoignable(attente)
          : TextesVoyant.enAttente(attente),
    );
  }
  if (injoignable) {
    return const VoyantSynchronisation(
      teinte: TeinteVoyant.gris,
      phrase: TextesVoyant.injoignable,
    );
  }
  return const VoyantSynchronisation(
    teinte: TeinteVoyant.vert,
    phrase: TextesVoyant.toutEnvoye,
  );
}
