<?php

declare(strict_types=1);

/**
 * Messages du check-in / check-out et du cycle opérationnel de l'unité (M1).
 *
 * Fichier neuf : `hebergement.php` sert la réservation et la disponibilité —
 * ce qui se vend. Ces messages-ci portent sur ce qui se PASSE dans la chambre,
 * une question différente, et l'arbitrage entre les deux sources est écrit en
 * tête de `SejourService`. Les mélanger aurait effacé cette frontière dans le
 * fichier même qui la nomme.
 */
return [

    'reservation_annulee' => "Cette réservation est annulée : aucun client n'est attendu. "
        .'Rétablissez une réservation valide avant de faire une arrivée.',

    'deja_arrive' => "L'arrivée a déjà été enregistrée le :date. "
        .'La ressaisir créerait un second séjour pour un seul client.',

    'deja_parti' => 'Le départ a déjà été enregistré le :date.',

    'pas_en_nettoyage' => "L'unité :unite n'est pas en nettoyage (état actuel : :statut). "
        .'Seule une unité libérée par un départ est à remettre en service.',

    'unite_hors_service' => "L'unité :unite est hors service : son état ne se change pas par une "
        .'arrivée ou un départ. Levez la maintenance d\'abord.',

];
