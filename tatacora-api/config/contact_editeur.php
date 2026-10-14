<?php

declare(strict_types=1);

/**
 * Coordonnées de l'éditeur — maître : `prototype_v2/pages/contact-editeur.html` l.163-164.
 *
 * Deux adresses, comme au maître. Configurable par variable d'environnement
 * (jamais en dur ailleurs dans le code) pour qu'un changement d'éditeur ne
 * suppose pas de retoucher `MessageEditeurService`.
 *
 * DÉCISION DU PRODUCT OWNER DU 14/10/2026 : le courriel part au SUPPORT,
 * `SUPPORT_MAIL` (défaut `rarhodes06@gmail.com`). `CONTACT_EDITEUR_DESTINATAIRES`
 * (liste séparée par des virgules) reste prioritaire s'il est posé.
 */
return [
    'destinataires' => array_values(array_filter(array_map(
        'trim',
        explode(',', (string) env('CONTACT_EDITEUR_DESTINATAIRES', env('SUPPORT_MAIL', 'rarhodes06@gmail.com'))),
    ))),
];
