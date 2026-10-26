/// Les libellés des ZONES DE SIGNATURES des états d'export — un seul endroit.
///
/// Directive §6.2, décision du Product Owner du 11/09/2026 (PA-192 (a)) : tout
/// export PDF porte une zone de signatures. Chaque liste est la TRADUCTION de
/// celle du gabarit serveur qui produit le même document
/// (`tatacora-api/resources/views/pdf/<gabarit>.blade.php`, inclusion de
/// `pdf.partials.signatures`) ; `test/core/impression/pdf_directive_test.dart`
/// relit ces gabarits et échoue sur la moindre divergence — une liste recopiée
/// ici sans cette garde ne vérifierait qu'elle-même.
///
/// Un document qui porte des visas PROPRES à son circuit (magasinier,
/// responsable achats…) les garde, comme côté serveur : c'est une zone de
/// signatures, et elle nomme mieux qui signe.
abstract final class Visas {
  /// Les visas de la directive, au mot — `rapports.signatures.*`.
  static const directive = [
    'Visa Ordonnateur / Caissier',
    'Visa Direction / Contrôle',
  ];

  /// `pdf/achats.blade.php` et `pdf/fournisseurs-liste.blade.php`.
  static const achats = ['Visa Responsable Achats', 'Visa Direction Générale'];

  /// `pdf/approvisionnement-bon.blade.php`.
  static const approvisionnement = [
    'Visa Magasinier',
    'Visa Responsable Achats',
  ];

  /// `pdf/fiche-stock.blade.php`.
  static const ficheStock = [
    'Signature Magasinier / Contrôleur',
    'Signature Direction / Validation',
  ];

  /// `pdf/depenses-rapport.blade.php` — l'état des dépenses (Lot J1, porté en
  /// A4 le 14/10/2026 par `etat_depenses.dart`).
  static const depenses = [
    'Visa Caissier / Ordonnateur',
    'Visa Direction / Comptable',
  ];

  /// `pdf/stocks-etat.blade.php` — l'état des articles en stock (Lot J1, porté
  /// en A4 le 14/10/2026 par `etat_stocks.dart`).
  static const etatStocks = [
    'Signature Magasinier / Gestionnaire',
    'Signature Direction / Validation',
  ];

  /// `pdf/inventaire-rapport.blade.php` — le rapport d'inventaire physique
  /// (21/10/2026), dont le gabarit nomme ses propres visas.
  static const inventaire = [
    'Visa Agent Recenseur',
    'Visa Responsable Magasin / Direction',
  ];

  /// `pdf/ventes-rapport.blade.php` — `pos_pwa.document.visa_*`.
  static const journalVentes = [
    'Visa Caissier / Barman',
    'Visa Direction / Contrôle',
  ];
}
