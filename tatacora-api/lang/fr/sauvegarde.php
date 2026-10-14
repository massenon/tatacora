<?php

declare(strict_types=1);

/*
 * Messages de la sauvegarde quotidienne (LISTE_DES_CRON_JOBS_CPANEL.md).
 *
 * Ils atterrissent dans `failed_jobs` et sont lus par l'Administrateur, pas par
 * un exploitant : ils restent techniques, mais français comme le reste.
 */

return [
    'repertoire_inaccessible' => 'Répertoire de sauvegarde inaccessible : :repertoire',
    'echec' => 'La sauvegarde a échoué : :raison',
    'echec_raison_absente' => 'fichier vide ou absent',
];
