<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Support;

use App\Shared\Parametres\Services\ParametreSystemeService;

/**
 * Paramètres FICTIFS pour la génération des documents ÉCHANTILLONS (`presentation/`).
 *
 * Il remplace, le temps d'un rendu, la lecture de `parametres_systeme` : aucune base n'est
 * consultée, donc aucune valeur réelle du Gîte (IFU, RCCM, signature, mode de facturation
 * courant) ne peut se retrouver sur un échantillon. Ce qui n'est pas listé ici retombe sur les
 * valeurs PAR DÉFAUT du dépôt (`ReportHeaderService::DEFAUTS`).
 */
final class ParametresEchantillon extends ParametreSystemeService
{
    /** IFU factice, 13 chiffres, clairement fictif. */
    public const IFU_FICTIF = '0000000000000';

    /**
     * @param array<string, string> $valeurs
     */
    public function __construct(private readonly array $valeurs)
    {
    }

    public function get(string $cle, ?string $defaut = null): ?string
    {
        return $this->valeurs[$cle] ?? $defaut;
    }

    public function estRenseigne(string $cle): bool
    {
        return filled($this->get($cle));
    }
}
