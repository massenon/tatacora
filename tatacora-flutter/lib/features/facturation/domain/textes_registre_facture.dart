/// Les phrases d'AIDE du registre des factures vide — celles du web (`lang/fr/pwa.php`, groupe
/// `facturation`), reprises au mot près (PO, 09/11/2026 : « j'ai enregistré une réservation et je ne vois ni
/// facture ni proforma »). `textes_registre_facture_test.dart` relit le fichier du serveur et confronte
/// chaque phrase : un mot changé d'un seul côté fait rougir le test.
library;

abstract final class TextesRegistreFacture {
  /// `pwa.facturation.registre_vide_aide` : ce qu'une réservation ne fait PAS, et ce qui facture.
  static const String registreVideAide =
      'Une réservation ne crée pas de facture : clôturez le séjour pour facturer, '
      'ou créez une proforma depuis la réservation.';

  /// `pwa.facturation.numero_interne` : la légende discrète qui suit le numéro INTERNE de la colonne « N° »
  /// (le numéro fiscal, lui, s'affiche seul). Aucune mention de normalisation : une facture simple n'en dit rien.
  static const String numeroInterne = 'n° interne';

  /// `pwa.facturation.registre_vide_lien` : le bouton qui mène aux proformas.
  static const String registreVideLien = 'Voir les proformas';

  /// `pwa.facturation.registre_hors_exercice` : des factures existent, hors de l'exercice consulté.
  static const String registreHorsExercice =
      ':nombre facture(s) émise(s) en dehors de l\'exercice consulté (:annee) : '
      'choisissez un autre exercice dans la barre supérieure.';

  /// La phrase rendue, `:nombre` et `:annee` remplacés.
  static String horsExercice({required int nombre, required int annee}) =>
      registreHorsExercice
          .replaceAll(':nombre', '$nombre')
          .replaceAll(':annee', '$annee');
}
