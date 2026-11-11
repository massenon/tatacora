/// Le NUMÉRO d'une facture proforma : `N°0045 FP-GCN/2026` (PO, 07/11/2026).
///
/// Le poste n'attribue AUCUN numéro définitif : hors ligne il émet un numéro
/// PROVISOIRE `PROV-FP-AAAA-NNNNN` (même mécanisme que les factures `PROV-…`),
/// que le serveur remplace à l'accusé de synchronisation par le numéro continu
/// de l'année (sous verrou, sans trou ni doublon). Jumeau de
/// `ProformaService::formaterNumero` (serveur).
library;

/// `N°0045 FP-GCN/2026` — le rang sur 4 chiffres, la RÉFÉRENCE FACTURE du réglage
/// (copiée à l'émission), l'année.
String formaterNumeroProforma(int rang, String reference, int annee) =>
    'N°${rang.toString().padLeft(4, '0')} FP-$reference/$annee';

/// `PROV-FP-2026-00007` — le numéro provisoire du poste.
String formaterNumeroProformaProvisoire(int annee, int ordre) =>
    'PROV-FP-$annee-${ordre.toString().padLeft(5, '0')}';

/// Un numéro provisoire n'est jamais un numéro définitif.
bool estNumeroProformaProvisoire(String numero) =>
    numero.startsWith('PROV-FP-');
