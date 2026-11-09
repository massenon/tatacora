// Vue Blade maîtresse : pwa/facturation/proformas.blade.php (les libellés de la vue ET de ses modales, au mot près).
/// Les LIBELLÉS de la facture proforma — ceux du web (`lang/fr/proforma.php`), repris au mot près (PO,
/// 07/11/2026 : « le poste fait ce que le web fait »). `proforma_textes_test.dart` relit le fichier
/// du serveur et confronte chaque clé : un libellé modifié d'un seul côté fait rougir le test.
library;

abstract final class TextesProforma {
  /// `proforma.ui.*`
  static const Map<String, String> ui = {
    'titre': 'Factures proforma',
    'sous_titre':
        'Documents commerciaux non fiscaux : devis chiffrés remis au client, convertibles en facture.',
    'nouvelle': 'Nouvelle facture proforma',
    'recherche': 'Rechercher (numéro, client, objet)',
    'tous_statuts': 'Tous les statuts',
    'retour': 'Retour aux factures',
    'proformas_lien': 'Proformas',
    'creer_depuis_module': 'Créer une proforma',
    'creer_court': 'Proforma',
    'col_numero': 'Numéro',
    'col_date': 'Date',
    'col_client': 'Client',
    'col_objet': 'Objet',
    'col_total': 'Total',
    'col_statut': 'Statut',
    'vide': 'Aucune proforma.',
    'vide_aide':
        'Une réservation ne crée pas de facture : clôturez le séjour pour facturer, ou créez une proforma depuis la réservation (bouton « Proforma » de la carte) ou avec « Nouvelle facture proforma ».',
    'brouillon_sans_numero': 'Brouillon',
    'valable': 'Valable jusqu’au :date',
    'modifier': 'Modifier',
    'emettre': 'Émettre',
    'pdf': 'PDF A4',
    'convertir': 'Convertir en facture',
    'annuler': 'Annuler',
    'facture_liee': 'Facture :numero',
    'form_titre_creation': 'Nouvelle facture proforma',
    'form_titre_modification': 'Modifier la proforma',
    'form_client': 'Client',
    'form_telephone': 'Téléphone',
    'form_ifu': 'IFU du client (13 chiffres, facultatif)',
    'form_objet': 'Objet',
    'form_lignes': 'Lignes (prix unitaire TTC en FCFA)',
    'form_designation': 'Désignation',
    'form_quantite': 'Quantité',
    'form_prix': 'Prix unitaire',
    'form_ajouter_ligne': 'Ajouter une ligne',
    'form_retirer_ligne': 'Retirer',
    'form_enregistrer': 'Enregistrer le brouillon',
    'form_emettre': 'Enregistrer et émettre',
    'annulation_titre': 'Annuler la proforma',
    'annulation_motif': 'Motif de l’annulation',
    'conversion_titre': 'Convertir en facture',
    'conversion_message':
        'Une vraie facture sera créée avec le même client, les mêmes lignes et les mêmes montants. La proforma ne sera plus modifiable. Cette conversion ne se fait qu’une fois.',
    'conversion_expiree':
        'Cette proforma est expirée : la conversion reste possible.',
    'conversion_confirmer': 'Convertir',
    'enregistree': 'Proforma enregistrée (brouillon).',
    'emise': 'Proforma émise : :numero.',
    'annulee': 'Proforma annulée.',
    'convertie': 'Proforma convertie en facture :numero.',
  };

  /// `proforma.statut.*`
  static const Map<String, String> statut = {
    'brouillon': 'Brouillon',
    'emise': 'Émise',
    'convertie': 'Convertie',
    'annulee': 'Annulée',
    'expiree': 'Expirée',
  };
}
