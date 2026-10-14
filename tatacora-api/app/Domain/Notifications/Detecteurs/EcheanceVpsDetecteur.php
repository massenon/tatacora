<?php

declare(strict_types=1);

namespace App\Domain\Notifications\Detecteurs;

use App\Domain\Notifications\Contracts\DetecteurDeclencheurInterface;
use App\Domain\Notifications\Support\MontantNotification;
use App\Domain\Rh\Services\LivreDePaieService;
use Carbon\CarbonImmutable;

/**
 * Déclencheur `echeance_vps` — maître : `notifications-engine.js` l.208-224.
 *
 * `LivreDePaieService::totaux()`/`echeanceVps()` sont RÉUTILISÉS, jamais
 * recomposés : le VPS y est un taux CONFIRMÉ (4 % du brut total, sans
 * plafond — `docs/…` et le docblock du service), à la différence de la CNSS
 * « risques professionnels », que ce même service refuse délibérément de
 * chiffrer (PA-53). Une occurrence par période, à destination du Comptable,
 * comme au maître — une seule ligne existe s'il y a eu de la paie ce mois-ci.
 */
final class EcheanceVpsDetecteur implements DetecteurDeclencheurInterface
{
    public function __construct(private readonly LivreDePaieService $livreDePaie)
    {
    }

    /**
     * @return list<array{reference: string, destinataire: string, variables: array<string, string>}>
     */
    public function detecter(): array
    {
        $periode = CarbonImmutable::now()->format('Y-m');

        if ($this->livreDePaie->bulletinsRetenus($periode)->isEmpty()) {
            return [];
        }

        $totaux = $this->livreDePaie->totaux($periode);
        $echeance = $this->livreDePaie->echeanceVps($periode);

        if ($echeance === null) {
            return [];
        }

        return [[
            'reference' => 'vps-' . $periode,
            'destinataire' => 'Comptable',
            'variables' => [
                'periode' => $periode,
                'montant' => MontantNotification::format($totaux['vps']),
                'echeance' => $echeance,
            ],
        ]];
    }
}
