<?php

declare(strict_types=1);

/*
 * Messages du domaine Facturation (M2).
 */

return [
    'immuable' => 'La facture :numero est certifiée : elle ne peut plus être modifiée '
        // Article 8 (02/09/2026) : la reference RG-03 vit ici, jamais a l'ecran.
        . 'ni supprimée. Émettez un avoir pour la corriger.',
    // Article 8 (02/09/2026) : la reference RG-03 vit ici, jamais a l'ecran.
    'immuable_sans_numero' => 'Cette facture ne peut être ni modifiée ni supprimée. '
        . 'La seule correction possible est l\'émission d\'un avoir.',
    'avoir_sur_non_certifiee' => 'Un avoir ne se rattache qu\'à une facture certifiée : '
        . 'une facture brouillon se corrige directement.',
    // Article 8 (02/09/2026) : la reference RG-03 vit ici, jamais a l'ecran.
    'ligne_sur_certifiee' => 'Aucune ligne ne peut être ajoutée à une facture certifiée.',
    'deja_certifiee' => 'Cette facture est déjà certifiée : la recertifier écraserait son NIM.',
    'avoir_montant_excessif' => 'Le montant de l\'avoir ne peut pas dépasser celui de la facture.',
    'libelle_avoir' => 'Avoir sur facture :numero',

    // e-MECeF (07/11/2026, lot 3) — erreurs de l'API de la DGI, classées ; aucune ne cite le jeton.
    'emecef' => [
        'jeton_refuse' => 'La DGI a refusé le jeton e-MECeF : vérifiez-le dans Paramètres, ou remplacez-le.',
        'limite' => 'La DGI limite les envois : nouvel essai dans :secondes s.',
        'injoignable' => 'La DGI est injoignable (réseau ou délai) : nouvel essai automatique.',
        'erreur_serveur' => 'La DGI a rencontré une erreur (code :code) : nouvel essai automatique.',
        'refus' => 'La DGI a refusé la facture : :detail',
        'refus_sans_detail' => 'aucun détail fourni.',
        'reponse_invalide' => 'La DGI a répondu sans les éléments attendus : la facture n\'est pas normalisée, nouvel essai automatique.',
        'reponse_invalide_apres_confirmation' => 'La confirmation a été envoyée à la DGI mais sa réponse est inutilisable : '
            . 'ne retransmettez pas, vérifiez la facture auprès de la DGI.',
        'configuration_incomplete' => 'Facturation e-MECeF incomplète : :manques',
        'totaux_incoherents' => 'Les totaux de la facture ne concordent pas avec ses lignes (écart de :ecart FCFA) : corrigez avant de normaliser.',
        'avoir_sans_origine' => 'L\'avoir ne peut pas être normalisé : la facture d\'origine n\'est pas normalisée.',
        'client_de_passage' => 'Client de passage',
        'attente_poste' => 'En attente de normalisation par le poste de la réception (boîtier CC300).',
    ],

    // Facturation normalisée (07/11/2026) — le serveur range le résultat d'un poste, sans re-certifier.
    'normalisation_deja_faite' => 'Cette pièce est déjà normalisée : une normalisation ne s\'écrase jamais.',
    'normalisation_identite_invalide' => 'Le numéro fiscal reçu n\'a pas la forme « NIM-compteur ».',
    'normalisation_qr_invalide' => 'Le code QR fiscal reçu est vide ou n\'a pas la forme attendue (F;NIM;code;IFU;date).',
    'normalisation_statut_inconnu' => 'Le statut de normalisation « :statut » est inconnu.',
    'normalisation_mode_inconnu' => 'La voie de normalisation « :mode » est inconnue.',

    // Facturation normalisée — décisions du PO du 07/11/2026.
    // IFU du CLIENT (point 2) : un seul champ, mêmes règles et mêmes phrases au web et au poste.
    'ifu_client' => [
        'label' => 'IFU du client',
        'nom_label' => 'Nom du client',
        'aide' => 'Facultatif : 13 chiffres. Laissez vide pour un client sans IFU.',
        'invalide' => 'L\'IFU du client doit compter exactement 13 chiffres (laissez vide pour un client sans IFU).',
        'retenir' => 'Retenir pour ce client',
        'nom_divers' => 'Client divers',
    ],

    // Comportement par MODE (point 3).
    'mode' => [
        'en_attente' => 'Facture en attente de normalisation',
        'normaliser_maintenant' => 'Normaliser maintenant',
        'normaliser' => 'Normaliser',
        'normaliser_desactive' => 'La facturation normalisée est désactivée : cette facture reste un document non normalisé.',
        'normaliser_poste' => 'En mode boîtier, la normalisation se fait au poste de la réception (boîtier CC300) : elle ne se fait pas depuis le web.',
        'normalisee' => 'Facture :numero normalisée.',
        'normalisation_en_attente' => 'La facture est émise, mais la normalisation n\'a pas abouti : :motif. Vous pourrez la relancer avec « Normaliser ».',
        'facture_emise_normalisation_en_attente' => 'Facture émise. La normalisation n\'a pas abouti (:motif) : la facture reste en attente, rejouable.',
    ],

    'en_ligne' => [
        'facture_inconnue' => 'Cette facture n\'est pas encore connue du serveur : envoyez d\'abord les opérations en attente du poste (synchronisation), puis recommencez.',
    ],

    // Avoir d'une facture NORMALISÉE (point 4) : EN LIGNE seulement.
    'avoir_en_ligne' => 'Un avoir sur une facture normalisée se fait en ligne : reconnectez le poste au serveur.',
    'avoir_en_ligne_refuse_file' => 'Un avoir sur une facture normalisée se fait en ligne : il ne passe pas par la file d\'envoi du poste. Reconnectez le poste au serveur et émettez l\'avoir depuis l\'écran Facturation.',

    // Encaissement (PA-165) — quatre refus locaux, tous corrigibles sur place.
    'encaissement_facture_non_figee' => 'Cette facture n\'est pas encore figée : émettez-la avant d\'encaisser.',
    'encaissement_mode_inconnu' => 'Le mode de paiement « :mode » n\'existe pas au registre.',
    'encaissement_montant_invalide' => 'Le montant encaissé doit être supérieur à zéro.',
    'encaissement_superieur_au_reste' => 'Le montant dépasse le reste dû (:reste F). Un trop-perçu ne s\'enregistre pas : encaissez le reste dû exact.',
    'encaissement_caisse_fermee' => 'Aucune session de caisse n\'est ouverte : ouvrez la caisse avant d\'encaisser.',

    // Annulation d'un encaissement (PA-168)
    'paiement_deja_annule' => 'Cet encaissement est déjà annulé.',
    'paiement_motif_requis' => 'Un motif est obligatoire pour annuler un encaissement.',
    'paiement_piece_introuvable' => 'La pièce comptable de cet encaissement est introuvable ou déséquilibrée (:libelle) : l\'annulation est refusée plutôt que de contre-passer à moitié.',
];
