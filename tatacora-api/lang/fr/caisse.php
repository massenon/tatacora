<?php

declare(strict_types=1);

/*
 * Refus de `SessionCaisseService` (lot S3 de synchronisation, 15/10/2026) qui
 * n'avaient pas d'équivalent à l'écran en ligne : la PWA ne peut ni clôturer
 * une session déjà close (elle ne voit que l'ouverte), ni dater une clôture.
 * Les refus que l'écran connaissait déjà gardent leur phrase
 * (`pos_pwa.comptant.*`).
 */

return [
    'point_inconnu' => 'Point de caisse inconnu : « :point ». Les caisses sont celles de la réception, du restaurant et du bar.',
    'montant_invalide' => 'Le montant doit être un nombre positif ou nul.',
    'deja_cloturee' => 'Cette caisse est déjà clôturée : une clôture ne se refait pas. '
        . 'Un écart constaté après coup se traite par une pièce de régularisation.',
    'cloture_avant_ouverture' => 'La clôture ne peut pas précéder l\'ouverture de la caisse.',
];
