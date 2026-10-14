<?php

declare(strict_types=1);

namespace App\Domain\Notifications\Detecteurs;

use App\Domain\Notifications\Contracts\DetecteurDeclencheurInterface;
use App\Domain\Notifications\Support\MontantNotification;
use App\Domain\Vehicules\Models\ContratLocation;
use Illuminate\Support\Carbon;

/**
 * Déclencheur `restitution_vehicule` — maître : `notifications-engine.js`
 * l.178-193.
 *
 * Tout contrat de location dont `date_fin` tombe AUJOURD'HUI. `M8` n'a NI
 * colonne `statut` sur `contrats_location`, NI suivi d'acompte/paiement
 * (`contrats_location` ne porte que les dates et l'identité — PA-50) : le
 * « reste dû » du maître n'a donc pas d'équivalent partiel ici, et
 * `reste_du` porte le MONTANT TOTAL du contrat (`ContratLocation::montant()`)
 * — le solde le plus honnête que ce schéma permette de calculer, jamais un
 * suivi de règlement qui n'existe pas.
 */
final class RestitutionVehiculeDetecteur implements DetecteurDeclencheurInterface
{
    /**
     * @return list<array{reference: string, destinataire: string, variables: array<string, string>}>
     */
    public function detecter(): array
    {
        $aujourdhui = Carbon::today();

        return ContratLocation::query()
            ->with(['client', 'vehicule'])
            ->whereDate('date_fin', $aujourdhui)
            ->get()
            ->map(static function (ContratLocation $contrat) {
                $client = $contrat->client;
                $vehicule = $contrat->vehicule;

                return [
                    'reference' => $contrat->id,
                    'destinataire' => $client?->nomComplet() ?? '—',
                    'email' => $client?->email,
                    'variables' => [
                        'client' => $client?->nomComplet() ?? '—',
                        'vehicule' => $vehicule->categorie . ' — ' . $vehicule->immatriculation,
                        'date' => $contrat->date_fin->format('d/m/Y'),
                        'reste_du' => MontantNotification::format($contrat->montant()),
                    ],
                ];
            })
            ->values()
            ->all();
    }
}
