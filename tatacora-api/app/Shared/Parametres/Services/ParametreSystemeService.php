<?php

declare(strict_types=1);

namespace App\Shared\Parametres\Services;

use App\Shared\Parametres\Models\ParametreSysteme;

/**
 * Acces aux parametres metier stockes en base.
 *
 * Distinction structurante (MECEF_INTEGRATION_SPEC.md §7.1) :
 * - un IDENTIFIANT (n° contribuable MECeF, IFU, taux CNSS) est un parametre
 *   metier, modifiable sans deploiement : il vit ici ;
 * - un SECRET (cle API) vit en `.env`, jamais ici.
 *
 * Ce service ne doit donc JAMAIS servir a lire une cle API : la tentation
 * « un seul ecran de parametrage, c'est plus simple » est precisement l'erreur
 * que la documentation interdit.
 */
class ParametreSystemeService
{
    public function get(string $cle, ?string $defaut = null): ?string
    {
        return ParametreSysteme::where('cle', $cle)->value('valeur') ?? $defaut;
    }

    public function estRenseigne(string $cle): bool
    {
        return filled($this->get($cle));
    }
}
