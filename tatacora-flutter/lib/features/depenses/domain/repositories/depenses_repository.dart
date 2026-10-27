import '../categories_depense.dart';
import '../entities/depense.dart';
import '../recu_depense.dart';

/// Le contrat du dépôt des dépenses.
///
/// Il ne dit **pas** d'où vient la donnée — c'est ce qui interdit aux écrans
/// une branche « si connecté ». Ici, la seule implémentation est locale
/// (`DepenseDao`), et elle le restera tant que `depenses` ne sera pas au
/// registre synchronisable du serveur.
///
/// Aucune méthode de suppression, et ce n'est pas un oubli : le « D » de CRUD
/// n'existe nulle part dans ce dépôt. Le serveur n'offre, lui non plus, aucune
/// annulation de dépense : `DepenseService` ne contre-passe jamais la pièce
/// d'une dépense, et ce poste ne porte que ce que le serveur fait. Une dépense
/// saisie par erreur se corrige hors de cet écran, par une écriture de
/// contre-passation (RG-11) que le moteur sait passer mais qu'aucun geste de
/// dépense n'appelle.
abstract interface class DepensesRepository {
  /// Toutes les dépenses du poste, de la plus récente à la plus ancienne.
  Future<List<Depense>> depenses();

  /// Enregistre une dépense **et ses lignes ET sa pièce comptable**, dans une
  /// seule transaction.
  ///
  /// Un seul appel avec la liste complète, jamais une dépense par ligne :
  /// boucler produirait N pièces et laisserait la moitié d'un marché du matin
  /// enregistrée si la sixième ligne était refusée.
  ///
  /// Le montant décaissé n'est **pas** un paramètre : il est recalculé des
  /// lignes. Un total fourni par l'appelant serait un montant que personne n'a
  /// vérifié.
  ///
  /// [centreId] est le centre de coût EXPLICITE de la dépense ; absent, c'est le
  /// défaut du compte, et un compte sans défaut est refusé (RG-12).
  /// [auteurId] est celui qui passe la pièce (RG-15).
  ///
  /// [recu] est le reçu en image (facultatif, comme au web) : jugé par la règle
  /// du web (image, 400 Ko), rangé hors de la base, sa référence écrite avec la
  /// dépense en `en_attente` d'envoi.
  ///
  /// Lève `RefusDepense` (saisie) ou `RefusComptable` (pièce refusée par le
  /// moteur, avec la phrase du serveur) — et rien d'autre n'est écrit : ni
  /// dépense, ni ligne, ni pièce, ni numéro de séquence consommé.
  Future<Depense> enregistrer({
    required DateTime dateTransaction,
    required TresorerieDepense tresorerie,
    required String libelle,
    required List<SaisieLigneDepense> lignes,
    required String auteurId,
    String? centreId,
    RecuAJoindre? recu,
  });

  /// Rattrapage : passe la pièce d'une dépense qui n'en a pas. Voir
  /// `DepenseDao.comptabiliser`.
  ///
  /// [centreId] est le centre de coût de la pièce — un paramètre OBLIGATOIRE du
  /// geste, comme `DepenseService::comptabiliser(Depense, string $centreId)` : la
  /// dépense n'en mémorise aucun. Vide, il est refusé (RG-12) tant que le compte
  /// de charge n'en porte pas un par défaut.
  Future<Depense> comptabiliser(
    String depenseId, {
    required String auteurId,
    required String centreId,
  });
}
