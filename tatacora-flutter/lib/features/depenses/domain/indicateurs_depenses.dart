import 'categories_depense.dart';
import 'entities/depense.dart';

/// Les six indicateurs de la bande du maître, **calculés sur la liste
/// AFFICHÉE**, filtres compris.
///
/// C'est ce que fait le serveur : sa bande lit la même collection filtrée que
/// son tableau. Calculer les cartes sur le registre entier pendant que le
/// tableau montre une semaine afficherait deux vérités sur le même écran.
///
/// ## Le sixième se LIT des pièces, depuis la v16
///
/// « Sans écriture » compte les dépenses de la liste affichée qui n'ont pas de
/// pièce comptable (`Depense.estComptabilisee`, lue de la clé étrangère). Avant
/// la v16 le poste n'avait ni moteur ni pièce : la carte disait « — », parce que
/// « 0 » aurait affirmé « tout est comptabilisé » sans que personne l'ait vérifié
/// (PA-59/60/61). Elle le peut maintenant, et son « 0 » est une mesure : la liste
/// affichée ne contient aucune dépense sans pièce.
final class IndicateursDepenses {
  const IndicateursDepenses({
    required this.total,
    required this.nombre,
    required this.moyenne,
    required this.marche,
    required this.services,
    required this.caisse,
    required this.sansEcriture,
  });

  /// « Total décaissé » — somme des montants, donc somme des lignes.
  final int total;

  /// Le détail de la première carte : « N dépense(s) ».
  final int nombre;

  /// « Dépense moyenne ». `null` quand il n'y a aucune dépense : le maître
  /// écrit « — » dans ce cas, et zéro franc dépensé ne dit pas la même chose
  /// qu'aucune dépense saisie.
  ///
  /// ⚠ **Division ENTIÈRE**, là où le serveur rend deux décimales. Le XOF n'a
  /// pas de sous-unité en circulation : afficher « 12 333,33 F » suggérerait
  /// une précision qui n'existe pas. L'écart est nommé, pas masqué.
  final int? moyenne;

  /// « Marché » — le total des LIGNES de cette famille, jamais des pièces.
  final int marche;

  /// « Services » — idem.
  final int services;

  /// « Caisse » — les espèces seules. Une dépense réglée en Mobile Money ou par
  /// banque n'y entre pas : c'est ce que la carte annonce, « espèces ».
  final int caisse;

  /// « Sans écriture » — les dépenses affichées sans pièce comptable.
  final int sansEcriture;

  factory IndicateursDepenses.calculer(List<Depense> depenses) {
    var total = 0;
    var marche = 0;
    var services = 0;
    var caisse = 0;
    var sansEcriture = 0;

    for (final depense in depenses) {
      final montant = depense.montantTotal;
      total += montant;
      marche += depense.totalDeLaFamille(FamilleDepense.marche);
      services += depense.totalDeLaFamille(FamilleDepense.services);
      if (depense.tresorerie == TresorerieDepense.caisse) caisse += montant;
      // Lot F4 : une dépense descendue a sa pièce AU SERVEUR — elle ne manque
      // pas au grand livre, et n'appelle aucun rattrapage ici.
      if (!depense.estComptabilisee && !depense.pieceAuServeur) sansEcriture++;
    }

    return IndicateursDepenses(
      total: total,
      nombre: depenses.length,
      moyenne: depenses.isEmpty ? null : total ~/ depenses.length,
      marche: marche,
      services: services,
      caisse: caisse,
      sansEcriture: sansEcriture,
    );
  }
}
