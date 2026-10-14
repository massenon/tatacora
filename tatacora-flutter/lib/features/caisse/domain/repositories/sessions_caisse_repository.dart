import '../entities/session_caisse.dart';

/// Les sessions de caisse du poste — **l'interface**, jamais le DAO.
///
/// Les deux lectures « session ouverte » ne sont PAS la même question, et le
/// serveur les distingue :
///
/// * [sessionOuverte] — celle d'UN point de vente. C'est la lecture de
///   `PosComptant::sessionOuverte()` : la barre de session de l'écran POS, le
///   refus d'ouvrir une seconde caisse, la clôture.
/// * [sessionOuverteLaPlusRecente] — celle de TOUS les points confondus. C'est
///   la lecture d'`EncaissementFactureService::encaisser()` (l.97-100) et de
///   `IndicateurCaisse::pour()` : « le tiroir ouvert », sans demander lequel.
///
/// Les confondre ferait encaisser une facture dans le tiroir du bar, ou
/// rapporter « Caisse fermée » quand le restaurant est ouvert.
abstract interface class SessionsCaisseRepository {
  Future<SessionCaisse?> sessionOuverte(PointDeVenteCaisse point);

  Future<SessionCaisse?> sessionOuverteLaPlusRecente();

  /// Toutes les sessions, de la plus récente à la plus ancienne.
  Future<List<SessionCaisse>> sessions();

  /// `PosComptant::ouvrirCaisse`. Lève `RefusCaisse` — rien n'est écrit.
  Future<SessionCaisse> ouvrir({
    required PointDeVenteCaisse point,
    required String? fondSaisi,
    required String auteurId,
    required bool peutEcrire,
  });

  /// `PosComptant::cloturerCaisse`. Lève `RefusCaisse` — rien n'est écrit.
  ///
  /// [especesEncaisseesCentimes] : les ventes validées en espèces de la
  /// session. `null` = aucune source sur ce poste : le théorique et l'écart
  /// restent `null`, jamais zéro.
  Future<ClotureCaisse> cloturer({
    required PointDeVenteCaisse point,
    required String? constateSaisi,
    required bool peutEcrire,
    int? especesEncaisseesCentimes,
  });
}
