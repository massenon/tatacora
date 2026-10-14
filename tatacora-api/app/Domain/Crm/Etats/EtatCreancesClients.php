<?php

declare(strict_types=1);

namespace App\Domain\Crm\Etats;

use App\Domain\Crm\Services\SoldeClientService;
use App\Shared\ReportEngine\Contracts\EtatInterface;
use App\Shared\ReportEngine\Data\EtatResultat;

/**
 * État des créances clients — EF-M14-02 appliqué à M3.
 *
 * Réutilise `SoldeClientService::registre()`/`totaux()` — LA source unique du
 * solde client (PA-126) — jamais une seconde requête sur `factures`, qui
 * finirait par diverger de l'écran Clients & Créances.
 *
 * ## Ce que ce solde EST, et ce qu'il n'est PAS — voir `SoldeClientService`
 *
 * C'est un MAXIMUM (PA-21 : aucun recouvrement n'est enregistré nulle part
 * dans ce dépôt) et il exclut la balance âgée par tranches (PA-20, non
 * arbitrée). Ce document n'invente ni recouvrement ni ancienneté.
 *
 * @see EF-M3-04 Suivi des soldes et créances
 * @see EF-M14-02 Bibliothèque d'états standards par module
 * @see PA-20, PA-21, PA-126
 */
class EtatCreancesClients implements EtatInterface
{
    public function __construct(private readonly SoldeClientService $soldes)
    {
    }

    public function module(): string
    {
        return 'M3';
    }

    /**
     * @param  array<string, string>  $filtres
     */
    public function libelle(array $filtres): string
    {
        return __('etats_m14.creances.libelle');
    }

    /**
     * @param  array<string, string>  $filtres
     */
    public function periode(array $filtres): string
    {
        return __('etats_m14.arrete_au', ['date' => now()->format('d/m/Y à H:i')]);
    }

    /**
     * @param  array<string, string>  $filtres  `toutes` (inclure les clients soldés)
     */
    public function calculer(array $filtres): EtatResultat
    {
        $toutes = filter_var($filtres['toutes'] ?? false, FILTER_VALIDATE_BOOLEAN);

        $registre = $this->soldes->registre(null, $toutes ? null : 'debiteur');
        $totaux = $this->soldes->totaux();

        $lignes = array_map(static fn (object $ligne): array => [
            trim($ligne->nom . ' ' . ($ligne->prenom ?? '')),
            $ligne->telephone,
            $ligne->type_client,
            (string) $ligne->pieces,
            $ligne->solde,
        ], $registre);

        return new EtatResultat(
            kpis: [
                __('etats_m14.creances.kpi_clients_debiteurs') => (string) $totaux['nb_clients'],
                __('etats_m14.creances.kpi_pieces') => (string) $totaux['nb_pieces'],
                __('etats_m14.creances.kpi_total_du') => $totaux['total_du'],
            ],
            entetes: [
                __('etats_m14.creances.col_client'),
                __('etats_m14.creances.col_telephone'),
                __('etats_m14.creances.col_type'),
                __('etats_m14.creances.col_pieces'),
                __('etats_m14.creances.col_solde'),
            ],
            lignes: $lignes,
            filtresAppliques: array_filter([
                'toutes' => $toutes ? 'oui' : null,
            ]),
        );
    }
}
