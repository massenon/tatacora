/// Les refus du moteur comptable.
///
/// Un refus est un FAIT NOMMÉ, pas une chaîne : [MotifRefus] est un registre
/// fermé (un cas ajouté demain ne doit pas obtenir un comportement par
/// omission) et [RefusComptable.message] est la phrase EXACTE du serveur
/// (`MessagesComptables`), jamais une reformulation.
///
/// ## Les deux familles du serveur, conservées
///
/// Le serveur lève `EcritureImmuableException` (RG-11 : écriture validée,
/// contre-passation interdite, exercice clôturé…) ou `RuntimeException` (tout le
/// reste). [MotifRefus.immuabilite] reproduit cette séparation, parce qu'un
/// appelant traite différemment « corrigez par contre-passation » et « cet
/// exercice n'existe pas ».
///
/// ## `contrainteBase` n'a PAS de phrase du serveur
///
/// Une ligne négative, ou à la fois débit et crédit, ou portant un centre qui
/// n'existe pas, est refusée au serveur par une contrainte MySQL : une erreur
/// SQL, sans phrase écrite pour l'exploitant. Le poste refuse aussi, au même
/// endroit du déroulement, mais DIT quelque chose de lisible ; la phrase est
/// donc de ce dépôt (écart nommé, ticket D194).
library;

import 'messages_comptables.dart';

enum MotifRefus {
  journalInconnu(false),
  compteInconnu(false),
  compteDivision(false),
  exerciceAbsent(false),
  exerciceNonOuvert(false),
  centreAbsent(false),
  pieceVide(false),
  pieceSansMontant(false),
  pieceDesequilibree(false),
  contrainteBase(false),
  montantIllisible(false),
  ecritureDejaValidee(false),
  exerciceAnneeInvalide(false),
  exerciceDejaExistant(false),
  exerciceDejaCloture(false),
  clotureBrouillonsRestants(false),
  compteNumeroInvalide(false),
  compteLibelleRequis(false),
  compteNatureInvalide(false),
  compteDejaExistant(false),
  ecritureIntrouvable(false),
  auteurAbsent(false),
  planFichierInvalide(false),

  /// La clôture annuelle (26/10/2026) — les refus de `ClotureExerciceService`.
  clotureDemarrageImpossible(false),
  clotureRepriseImpossible(false),
  clotureExigeEnCloture(false),
  clotureOrdre(false),
  clotureConditionsNonReunies(false),
  clotureSuivantClos(false),
  reouvertureReservee(false),
  reouvertureNonCloture(false),
  reouvertureMotif(false),
  reouvertureSuivantClos(false),
  archiveSansCloture(false),
  archiveAlteree(false),
  archiveClotureRouverte(false),

  /// RG-11 — les cinq refus que le serveur porte par `EcritureImmuableException`.
  ecritureImmuable(true),
  suppressionInterdite(true),
  contrepassationSurBrouillon(true),
  dejaContrepassee(true),
  exerciceClos(true);

  const MotifRefus(this.immuabilite);

  /// Vrai quand le serveur lève `EcritureImmuableException`.
  final bool immuabilite;
}

/// Un refus du moteur comptable : rien n'a été écrit.
final class RefusComptable implements Exception {
  const RefusComptable(this.motif, this.message);

  final MotifRefus motif;

  /// La phrase du serveur, variables remplacées.
  final String message;

  /// Raccourci : un refus dont la phrase vient de la langue du serveur.
  factory RefusComptable.dit(
    MotifRefus motif,
    String cle, [
    Map<String, String> variables = const {},
  ]) => RefusComptable(motif, MessagesComptables.dire(cle, variables));

  @override
  String toString() => 'RefusComptable(${motif.name}): $message';
}
