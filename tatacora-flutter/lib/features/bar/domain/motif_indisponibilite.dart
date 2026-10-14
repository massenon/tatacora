/// Les motifs de retrait de la carte du jour — le registre FERMÉ
/// `IndisponibiliteCarte::MOTIFS` du serveur, dans son ordre.
///
/// ## Une seconde liste, et sa garde
///
/// La modale en a besoin AVANT tout appel réseau : elle propose les motifs,
/// elle ne les découvre pas. C'est donc une copie — et c'est exactement la
/// forme du défaut que la PWA a connu (`hors_saison` / `retrait` contre
/// `saison` / `retire`, pour des libellés identiques à l'écran). La copie est
/// tenue par `test/features/bar/motif_indisponibilite_test.dart`, qui RELIT le
/// fichier PHP : un motif ajouté, retiré ou renommé au serveur fait échouer la
/// suite au lieu de partir en 422 au comptoir.
///
/// `temporaire` est une propriété du motif, jamais de l'enregistrement : une
/// rupture revient au réapprovisionnement, un retrait est une décision
/// commerciale (`IndisponibiliteCarte::estTemporaire()`).
///
/// @see EF-M5-02 Carte des boissons
enum MotifIndisponibilite {
  rupture('rupture', 'Rupture du jour', temporaire: true),
  saison('saison', 'Hors saison', temporaire: true),
  retire('retire', 'Retiré de la carte', temporaire: false);

  const MotifIndisponibilite(
    this.code,
    this.libelle, {
    required this.temporaire,
  });

  /// Ce qui part au serveur.
  final String code;

  final String libelle;
  final bool temporaire;
}
