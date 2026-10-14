/// L'annulation d'une réservation avec commission et remboursement (EF-M1-06) —
/// RÉPLIQUE de `AnnulationReservationService` et de la validation du composant
/// `Hebergement\Reservations`, en FONCTIONS PURES (aucune base, aucun écran).
///
/// ## Qui lit le taux par défaut sur ce poste (pièges 1 et 9)
///
/// `hebergement_taux_annulation_moins_24h` a UN lecteur : ce fichier
/// ([tauxParDefaut]). Il est déclaré au registre des paramètres. Avant le lot 6
/// (12/10/2026) la clé n'était lue par personne : son aide promettait de
/// « pré-remplir le formulaire d'annulation » qui n'existait pas.
///
/// ## Ce que dit le serveur, et que ce fichier reprend
///
/// * la commission porte sur le MONTANT GLOBAL (sous-total moins remise), jamais
///   sur l'acompte (compte rendu client §4.3, non négociable) ;
/// * le remboursement se saisit en POURCENTAGE de l'acompte ou en FCFA, jamais
///   les deux, et ne dépasse jamais l'acompte réellement encaissé ;
/// * le taux de 50 % « à moins de 24 h » n'est PAS un automatisme : le délai est
///   INFORMATIF, le taux appliqué est celui que l'opérateur valide ;
/// * les montants se calculent comme `bcmath` — par troncature, aux mêmes
///   endroits que le serveur ([DecimalBc]) ; les résultats sont des CENTIMES
///   entiers.
///
/// @see EF-M1-06 Annulation de réservation avec commission et remboursement
/// @see RG-02 Libération automatique après annulation
library;

import '../../../core/format/decimal_bc.dart';
import 'messages_annulation.dart';

/// Le littéral `'100'` des divisions du serveur.
final DecimalBc _cent = DecimalBc(BigInt.from(100), 0);

/// Les deux façons de saisir le remboursement — registre fermé du serveur.
abstract final class ModesRemboursement {
  static const String pourcentage = 'pourcentage';
  static const String montant = 'montant';
  static const List<String> tous = [pourcentage, montant];
}

/// `AnnulationReservationService::CLE_TAUX_MOINS_24H` et ses voisines.
abstract final class ReglesAnnulation {
  /// Le taux de référence retenu en séance — utilisé UNIQUEMENT comme repli
  /// quand l'Administrateur n'a jamais renseigné le paramètre.
  static const String tauxReference = '50.00';

  /// « Moins de 24 heures avant la prestation ».
  static const int seuilHeures = 24;
}

/// Le taux à PRÉ-REMPLIR : le paramètre, ou `50.00` à défaut. Jamais imposé,
/// l'opérateur le modifie.
String tauxParDefaut(Map<String, String> valeurs) =>
    valeurs['hebergement_taux_annulation_moins_24h'] ??
    ReglesAnnulation.tauxReference;

/// Délai, en heures, entre [maintenant] et le début de la journée d'arrivée.
///
/// `reservations.date_arrivee` est une DATE sans heure d'arrivée connue : minuit
/// du jour d'arrivée sert de référence, comme au serveur. Négatif quand la date
/// est déjà passée. Le jour est lu par ses COMPOSANTES : une arrivée stockée en
/// UTC ne doit pas glisser d'un jour selon le fuseau du poste.
double delaiHeuresAvantArrivee(DateTime arrivee, DateTime maintenant) {
  final reference = DateTime(arrivee.year, arrivee.month, arrivee.day);
  return reference.difference(maintenant).inSeconds / 3600.0;
}

/// Le cas de référence validé en séance : moins de 24 h avant la prestation.
bool estSousLeSeuil(DateTime arrivee, DateTime maintenant) =>
    delaiHeuresAvantArrivee(arrivee, maintenant) < ReglesAnnulation.seuilHeures;

/// `number_format($h, 1)` de PHP : une décimale, virgule de milliers, point
/// décimal — c'est ce que la vue imprime, sans localisation.
String formaterHeures(double heures) {
  final signe = heures < 0 ? '-' : '';
  final absolu = heures.abs().toStringAsFixed(1);
  final point = absolu.indexOf('.');
  final entier = absolu.substring(0, point);
  final tampon = StringBuffer();
  for (var i = 0; i < entier.length; i++) {
    if (i > 0 && (entier.length - i) % 3 == 0) tampon.write(',');
    tampon.write(entier[i]);
  }
  return '$signe$tampon${absolu.substring(point)}';
}

/// Le montant TOTAL d'une réservation pour la commission, ou `null` s'il est
/// INCONNU : une réservation sans tarif figé (reprise de la v1, `tarif_nuit` à
/// 0) et sans ligne de service ne permet aucun calcul fiable — le serveur la
/// REFUSE (`annulation_montant_total_inconnu`) plutôt que d'inventer un montant.
///
/// [tarifNuit] et [nuits] servent à une réservation antérieure aux lignes ; sinon
/// le total vient des lignes (le récapitulatif de la fiche) : c'est
/// `Reservation.recapitulatif.total`, passé en [totalDuRecapitulatifFrancs].
int? montantTotalCentimes({
  required int tarifNuit,
  required bool aDesLignes,
  required int totalDuRecapitulatifFrancs,
}) {
  if (!aDesLignes && tarifNuit == 0) return null;
  return totalDuRecapitulatifFrancs * 100;
}

/// Le pourcentage de l'ACOMPTE proposé par défaut : ce qu'il resterait de
/// l'acompte après la commission théorique, jamais négatif. Un simple point de
/// départ — seule la valeur effectivement soumise compte.
///
/// Rend la CHAÎNE du serveur : `'0'` (littéral) ou `bcdiv(.., 2)` (`'75.00'`).
String pourcentageRembourseSuggere({
  required int acompteCentimes,
  required int? totalCentimes,
  required String taux,
}) {
  if (acompteCentimes <= 0) return '0';
  if (totalCentimes == null) return '0';

  final tauxLu = DecimalBc.lire(taux);
  if (tauxLu == null) return '0';

  final commission = DecimalBc.centimes(
    totalCentimes,
  ).fois(tauxLu, 4).divise(_cent, 2);
  final acompte = DecimalBc.centimes(acompteCentimes);
  final suggere = acompte.moins(commission, 2);
  if (suggere.estNegatif) return '0';

  return suggere.fois(_cent, 4).divise(acompte, 2).toString();
}

/// Ce que l'annulation fixe, en centimes.
final class ResultatAnnulation {
  const ResultatAnnulation({
    required this.tauxCentiemes,
    required this.totalCentimes,
    required this.commissionCentimes,
    required this.rembourseCentimes,
    required this.modeSaisie,
  });

  /// Le taux normalisé à deux décimales, en centièmes de pour cent (`50.00` -> 5000).
  final int tauxCentiemes;
  final int totalCentimes;
  final int commissionCentimes;
  final int rembourseCentimes;
  final String modeSaisie;
}

/// `AnnulationReservationService::annuler`, étage par étage : réservation déjà
/// annulée, montant total inconnu, taux hors bornes, puis le remboursement. Lève
/// [RefusAnnulation] dans l'ORDRE du serveur, avec ses phrases.
///
/// Le champ de chaque refus est celui auquel le composant le rattache : les
/// `InvalidArgumentException` (taux, remboursement) sous `aRembourseValeur`, les
/// `RuntimeException` (déjà annulée, total inconnu) sous la bannière
/// `annulation`.
ResultatAnnulation calculerAnnulation({
  required bool dejaAnnulee,
  required int? totalCentimes,
  required int acompteCentimes,
  required String tauxSaisi,
  required String modeSaisi,
  required String valeurSaisie,
}) {
  if (dejaAnnulee) {
    throw const RefusAnnulation(
      MessagesAnnulation.dejaAnnulee,
      champ: 'annulation',
    );
  }
  if (totalCentimes == null) {
    throw const RefusAnnulation(
      MessagesAnnulation.montantTotalInconnu,
      champ: 'annulation',
    );
  }

  // `normaliserTaux` : `bcadd($taux, '0', 2)`, puis bornes 0..100.
  final taux = DecimalBc.lire(tauxSaisi);
  if (taux == null) {
    throw const RefusAnnulation(
      MessagesAnnulation.malForme,
      champ: 'aRembourseValeur',
    );
  }
  final tauxNormalise = taux.versEchelle(2);
  if (tauxNormalise.compare(DecimalBc(BigInt.zero, 2), 2) < 0 ||
      tauxNormalise.compare(DecimalBc(BigInt.from(10000), 2), 2) > 0) {
    throw const RefusAnnulation(
      MessagesAnnulation.tauxInvalide,
      champ: 'aRembourseValeur',
    );
  }

  // `bcdiv(bcmul($montantTotal, $taux, 4), '100', 2)`.
  final commission = DecimalBc.centimes(
    totalCentimes,
  ).fois(tauxNormalise, 4).divise(_cent, 2);

  final rembourse = _calculerRemboursement(
    acompteCentimes,
    modeSaisi,
    valeurSaisie,
  );

  return ResultatAnnulation(
    tauxCentiemes: tauxNormalise.unites.toInt(),
    totalCentimes: totalCentimes,
    commissionCentimes: commission.unites.toInt(),
    rembourseCentimes: rembourse,
    modeSaisie: modeSaisi,
  );
}

/// `calculerRemboursement` : jamais plus que l'acompte détenu.
int _calculerRemboursement(int acompteCentimes, String mode, String saisie) {
  final lue = DecimalBc.lire(saisie);
  if (lue == null) {
    throw const RefusAnnulation(
      MessagesAnnulation.malForme,
      champ: 'aRembourseValeur',
    );
  }
  // `bcadd($valeur, '0', PRECISION + 2)` : quatre décimales.
  final valeur = lue.versEchelle(4);
  if (valeur.compare(DecimalBc(BigInt.zero, 2), 2) < 0) {
    throw const RefusAnnulation(
      MessagesAnnulation.remboursementNegatif,
      champ: 'aRembourseValeur',
    );
  }

  final acompte = DecimalBc.centimes(acompteCentimes);
  final DecimalBc montant;
  switch (mode) {
    case ModesRemboursement.pourcentage:
      // `bcdiv(bcmul($acompte, $valeur, 4), '100', 2)`.
      montant = acompte.fois(valeur, 4).divise(_cent, 2);
    case ModesRemboursement.montant:
      // `bcadd($valeur, '0', 2)`.
      montant = valeur.versEchelle(2);
    default:
      throw RefusAnnulation(
        MessagesAnnulation.modeInconnu(mode),
        champ: 'aRembourseValeur',
      );
  }

  if (montant.compare(acompte, 2) > 0) {
    throw const RefusAnnulation(
      MessagesAnnulation.remboursementSuperieurAcompte,
      champ: 'aRembourseValeur',
    );
  }
  return montant.unites.toInt();
}

/// La validation Livewire du formulaire (`validerEcriture`), champ par champ :
///
/// ```php
/// 'aTaux'              => ['required', 'numeric', 'min:0', 'max:100'],
/// 'aModeRemboursement' => ['required', 'in:pourcentage,montant'],
/// 'aRembourseValeur'   => ['required', 'numeric', 'min:0'],
/// ```
///
/// Rend les messages par propriété du composant, dans l'ordre des champs ; un
/// champ vide ne dit que « obligatoire » (les autres règles ne s'appliquent pas
/// à une valeur vide), et `min`/`max` ne jugent qu'un NOMBRE. Vide = rien à
/// refuser.
Map<String, List<String>> validerSaisieAnnulation({
  required String? taux,
  required String? mode,
  required String? valeur,
}) {
  bool vide(String? v) => v == null || v.trim().isEmpty;
  final erreurs = <String, List<String>>{};

  if (vide(taux)) {
    erreurs['aTaux'] = [MessagesAnnulation.obligatoire('a taux')];
  } else {
    final lu = DecimalBc.lire(taux!);
    if (lu == null) {
      erreurs['aTaux'] = [MessagesAnnulation.nombre('a taux')];
    } else {
      final messages = <String>[];
      if (lu.estNegatif) {
        messages.add(MessagesAnnulation.minimum('a taux', '0'));
      }
      if (lu.compareTo(DecimalBc(BigInt.from(100), 0)) > 0) {
        messages.add(MessagesAnnulation.maximum('a taux', '100'));
      }
      if (messages.isNotEmpty) erreurs['aTaux'] = messages;
    }
  }

  if (vide(mode)) {
    erreurs['aModeRemboursement'] = [
      MessagesAnnulation.obligatoire('a mode remboursement'),
    ];
  } else if (!ModesRemboursement.tous.contains(mode)) {
    erreurs['aModeRemboursement'] = [
      MessagesAnnulation.invalide('a mode remboursement'),
    ];
  }

  if (vide(valeur)) {
    erreurs['aRembourseValeur'] = [
      MessagesAnnulation.obligatoire('a rembourse valeur'),
    ];
  } else {
    final lu = DecimalBc.lire(valeur!);
    if (lu == null) {
      erreurs['aRembourseValeur'] = [
        MessagesAnnulation.nombre('a rembourse valeur'),
      ];
    } else if (lu.estNegatif) {
      erreurs['aRembourseValeur'] = [
        MessagesAnnulation.minimum('a rembourse valeur', '0'),
      ];
    }
  }

  return erreurs;
}
