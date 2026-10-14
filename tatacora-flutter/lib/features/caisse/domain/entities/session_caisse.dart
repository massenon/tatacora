/// Les points de vente que le serveur connaît pour une session de caisse — l'`enum`
/// de `sessions_caisse.point_vente` (`create_facturation`, l.61).
///
/// Registre fermé : un point ajouté demain n'obtient aucun comportement par
/// omission. Seul [bar] est ouvert par l'écran POS comptant
/// (`PosComptant::POINT_CAISSE`) ; [reception] et [restaurant] sont lus par les
/// mêmes lecteurs que le serveur (indicateur de la barre supérieure,
/// encaissement de facture) mais aucun geste de ce poste ne les ouvre — le
/// serveur non plus, hors seeder de démonstration.
enum PointDeVenteCaisse {
  reception('reception', 'Réception'),
  restaurant('restaurant', 'Restaurant'),
  bar('bar', 'Bar');

  const PointDeVenteCaisse(this.code, this.libelle);

  /// La valeur de l'`enum` du serveur — celle que les messages de
  /// `PosComptant` écrivent tels quels (« Caisse bar ouverte. »).
  final String code;

  /// Le libellé de `IndicateurCaisse::LIBELLES_POINT_VENTE` (« Bar »,
  /// « Réception »). ⚠ Le serveur emploie DEUX formes pour le même point : le
  /// code brut dans le POS, ce libellé dans la barre supérieure.
  final String libelle;

  static PointDeVenteCaisse? depuisCode(String code) {
    for (final p in values) {
      if (p.code == code) return p;
    }
    return null;
  }
}

/// Une session de caisse, telle que l'écran la lit. Montants en CENTIMES.
/// Le point de vente de l'écran POS comptant — `PosComptant::POINT_CAISSE`.
///
/// Défini ICI (domaine) et non dans les providers : `PanierDao.cloturer` doit le
/// connaître pour rattacher l'encaissement à la session ouverte de ce point
/// (D221, option a), et une couche de données n'importe pas la présentation.
const PointDeVenteCaisse pointDeCaisseDuComptoir = PointDeVenteCaisse.bar;

final class SessionCaisse {
  const SessionCaisse({
    required this.id,
    required this.point,
    required this.utilisateurOuvertureId,
    required this.dateOuverture,
    required this.fondCentimes,
    this.dateCloture,
    this.theoriqueCentimes,
    this.constateCentimes,
  });

  final String id;
  final PointDeVenteCaisse point;
  final String utilisateurOuvertureId;
  final DateTime dateOuverture;
  final int fondCentimes;
  final DateTime? dateCloture;
  final int? theoriqueCentimes;
  final int? constateCentimes;

  /// « Ouverte » veut dire `date_cloture IS NULL`, rien d'autre.
  bool get estOuverte => dateCloture == null;
}

/// Le résultat d'une clôture : la session close, et l'écart ANNONCÉ.
///
/// `ecartCentimes` n'est JAMAIS stocké (le serveur non plus) : il est calculé à
/// la clôture, annoncé, et se perd. Depuis le lot 5 il est TOUJOURS calculé,
/// comme au serveur (les espèces de la session ont une source).
final class ClotureCaisse {
  const ClotureCaisse({required this.session, required this.ecartCentimes});

  final SessionCaisse session;
  final int ecartCentimes;
}
