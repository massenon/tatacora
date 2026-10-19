/// Le serveur a été RÉINITIALISÉ depuis la dernière synchronisation de ce
/// poste (19/10/2026, décision du PO : essais en production, puis
/// réinitialisation sur le web et les postes). La génération des données
/// rappelée par le poste est refusée (409 `generation_perimee`) : il ne
/// synchronise plus avant sa propre réinitialisation.
library;

/// Les mots de cet état, partagés par l'écran de synchronisation et
/// l'onglet de réinitialisation d'Import & Export.
abstract final class TextesReinitialisationServeur {
  static String constatee(DateTime le) {
    String deux(int n) => n.toString().padLeft(2, '0');
    final l = le.toLocal();
    return 'Le serveur a été réinitialisé le ${deux(l.day)}/${deux(l.month)}/'
        '${l.year} à ${deux(l.hour)}:${deux(l.minute)} : ce poste ne '
        'synchronise plus. Réinitialisez-le (Import & Export → Réinitialiser '
        'comme neuf) ; ses opérations non envoyées sont des essais et seront '
        'abandonnées.';
  }
}
