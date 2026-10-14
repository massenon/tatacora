<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Jobs;

use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Services\EmissionFactureService;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Illuminate\Support\Facades\Log;
use Throwable;

/**
 * Rejeu des certifications MECeF en échec — RG-03, toutes les 30 minutes.
 *
 * ## Pourquoi un rejeu différé et non un blocage
 *
 * La facture est émise et remise au client **immédiatement**, même si la DGI
 * est injoignable (MECEF_INTEGRATION_SPEC.md §2). Bloquer l'émission sur la
 * disponibilité d'un service externe rendrait la réception du gîte dépendante
 * d'une panne à Cotonou — inacceptable pour un encaissement.
 *
 * Ce job rattrape donc les factures restées en `echec_certification`.
 *
 * ## Une facture en échec n'est jamais abandonnée en silence
 *
 * Chaque tentative infructueuse est journalisée. Sans cela, une facture
 * pourrait rester non certifiée indéfiniment sans que personne ne le sache —
 * et c'est précisément ce qu'un contrôle fiscal cherche.
 */
class RejouerCertificationsMecefEnEchecJob implements ShouldQueue
{
    use Queueable;

    /**
     * Plafond par passage : le job tourne toutes les 30 minutes, il n'a pas à
     * rattraper tout l'arriéré d'un coup. Un lot borné évite de saturer la
     * passerelle DGI si elle vient tout juste de revenir.
     */
    private const MAX_PAR_PASSAGE = 50;

    /**
     * @return array{tentees: int, certifiees: int, echecs: int}
     */
    public function handle(EmissionFactureService $emission): array
    {
        $factures = Facture::query()
            ->whereIn('statut', ['echec_certification', 'en_attente_certification'])
            ->orderBy('date_emission')
            ->limit(self::MAX_PAR_PASSAGE)
            ->get();

        $certifiees = 0;
        $echecs = 0;

        foreach ($factures as $facture) {
            try {
                $emission->certifier($facture);
                $certifiees++;
            } catch (Throwable $e) {
                $echecs++;

                // Le statut est ramené à `echec_certification` pour que la
                // facture reste visible comme non conforme, plutôt que de
                // rester en « attente » indéfiniment — l'attente laisse croire
                // que le traitement suit son cours.
                $facture->update(['statut' => 'echec_certification']);

                Log::warning('Certification MECeF en échec', [
                    'facture_id' => $facture->id,
                    'motif' => $e->getMessage(),
                ]);
            }
        }

        return [
            'tentees' => $factures->count(),
            'certifiees' => $certifiees,
            'echecs' => $echecs,
        ];
    }
}
