<?php

declare(strict_types=1);

/*
 * Messages du noyau d'intégrité partagé (RG-01, RG-08, RG-13).
 *
 * Ce libellé est volontairement générique : le service de vérification de
 * chevauchement sert l'hébergement, les véhicules et les plannings RH. Chaque
 * domaine passe son propre message — celui-ci n'est que le repli.
 */

return [
    'chevauchement_generique' => 'Cette ressource est déjà réservée sur cette période.',
];
