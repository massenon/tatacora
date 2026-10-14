import '../../comptabilite/data/moteur_comptable.dart';
import '../domain/categories_depense.dart';

/// Un franc CFA vaut cent centimes de pièce : le XOF n'a pas de sous-unité en
/// circulation, mais le moteur calcule en centimes entiers (D193).
const int centimesParFranc = 100;

/// Une ligne d'achat telle que la pièce la lit : son libellé, son compte de
/// charge, son prix en FRANCS (entier).
typedef LigneDePiece = ({String libelle, String compte, int montant});

/// Le libellé de la pièce : « Dépense — {libellé de la dépense} »
/// (`depenses.libelle_ecriture` du serveur, mot pour mot).
String libellePieceDepense(String libelleDepense) =>
    'Dépense — $libelleDepense';

/// La pièce comptable d'une dépense — **fonction pure**, réplique de
/// `DepenseService::lignesDeLaPiece` et de l'en-tête de pièce de
/// `DepenseService::enregistrer`.
///
/// ## Ce que la pièce contient (et c'est exactement le serveur)
///
/// * une ligne de CHARGE au DÉBIT par ligne d'achat, sur le compte saisi, au
///   libellé de la ligne (à défaut, celui de la dépense) ;
/// * UNE ligne de TRÉSORERIE au CRÉDIT du total, sur le compte de la trésorerie
///   choisie, au libellé de la dépense ;
/// * le journal de la trésorerie (caisse -> CAI, mobile money et banque -> BQ).
///
/// La contrepartie est ajoutée ICI et jamais par l'appelant : une pièce à sens
/// unique est refusée comme déséquilibrée.
///
/// ## Le centre de coût
///
/// [centreId] est le centre EXPLICITE de la dépense : il s'applique à chaque
/// ligne de charge ET à la ligne de trésorerie (le serveur pose
/// `centre_id => $centreId ?: null` sur les deux). Absent, c'est le défaut du
/// compte qui joue ; un compte sans défaut est refusé par le moteur avec la
/// phrase de RG-12 (`depenses.centre_absent`), jamais deviné.
///
/// ## Les montants
///
/// Des francs entiers en entrée, des CENTIMES entiers en sortie (le moteur ne
/// calcule jamais en flottant). Le total est la somme des lignes ; aucun total
/// n'est reçu de l'appelant.
///
/// @see EF-M10-02 Saisie des écritures comptables
/// @see RG-12 Centre de coût obligatoire
DemandePiece pieceDeLaDepense({
  required TresorerieDepense tresorerie,
  required String dateIso,
  required String libelleDepense,
  required List<LigneDePiece> lignes,
  String? centreId,
}) {
  final centre = (centreId == null || centreId.isEmpty) ? null : centreId;
  var totalCentimes = 0;
  final charges = <LigneDemandee>[];

  for (final ligne in lignes) {
    final centimes = ligne.montant * centimesParFranc;
    totalCentimes += centimes;
    final propre = ligne.libelle.trim();
    charges.add(
      LigneDemandee(
        compte: ligne.compte,
        debitCentimes: centimes,
        libelle: propre.isEmpty ? libelleDepense : propre,
        centreId: centre,
      ),
    );
  }

  return DemandePiece(
    journal: tresorerie.journal,
    date: dateIso,
    libelle: libellePieceDepense(libelleDepense),
    lignes: [
      ...charges,
      LigneDemandee(
        compte: tresorerie.compte,
        creditCentimes: totalCentimes,
        libelle: libelleDepense,
        centreId: centre,
      ),
    ],
  );
}
