<?php

declare(strict_types=1);

/**
 * Réglages d'exploitation propres à TATACORA, lus du `.env` seulement.
 */
return [
    /*
     * La PHASE D'ESSAIS EN PRODUCTION (décision du Product Owner du
     * 19/10/2026 : « les essais en production suivis de la réinitialisation »).
     *
     * Tant qu'elle vaut `true`, la réinitialisation « comme neuf » reste
     * possible en Production — avec ses trois autres verrous (bascule,
     * rôle d'administration, saisie de « VIDER ») et la sauvegarde
     * préalable. On la RETIRE du `.env` le jour de la mise en service
     * réelle : la réinitialisation redevient impossible en Production, quel
     * que soit le rôle. `php artisan tatacora:verifier-production` le signale
     * tant qu'elle est posée.
     */
    'phase_essais' => filter_var(env('TATACORA_PHASE_ESSAIS', false), FILTER_VALIDATE_BOOLEAN),
];
