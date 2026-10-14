<?php

declare(strict_types=1);

namespace App\Shared\ReportEngine\Renderers;

use App\Shared\ReportEngine\Data\EnTeteRapport;
use App\Shared\ReportEngine\Data\EtatResultat;

/**
 * Contrat d'un format de sortie.
 *
 * Les deux implémentations reçoivent **exactement les mêmes** `EnTeteRapport`
 * et `EtatResultat` : c'est ce qui garantit mécaniquement le point 7 de la
 * grille `RESPECT_TABLEAU_RAPPORT.md` (« Export PDF ET Excel à partir de la
 * MÊME structure de données, jamais deux calculs séparés qui pourraient
 * diverger »). Un moteur de rendu ne calcule rien, il met en forme.
 */
interface RenduDocument
{
    /** `pdf` ou `excel` — valeurs de l'`enum` `etats_generes.format`. */
    public function format(): string;

    public function extension(): string;

    public function typeMime(): string;

    public function rendre(EnTeteRapport $entete, EtatResultat $etat): string;
}
