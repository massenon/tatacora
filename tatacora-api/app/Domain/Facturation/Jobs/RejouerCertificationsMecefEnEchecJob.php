<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Jobs;

use App\Domain\Facturation\Models\Avoir;
use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Services\EmissionFactureService;
use App\Domain\Facturation\Services\ModeFacturation;
use App\Domain\Facturation\Services\StatutNormalisation;
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
     * @return array{tentees: int, certifiees: int, echecs: int, avoirs: int}
     */
    public function handle(EmissionFactureService $emission): array
    {
        $mode = ModeFacturation::courant();

        // Boîtier : le serveur ne certifie PAS — le poste de la réception reprend ses
        // factures « en attente de normalisation » à son passage.
        if ($mode === ModeFacturation::Boitier) {
            return ['tentees' => 0, 'certifiees' => 0, 'echecs' => 0, 'avoirs' => 0];
        }

        $factures = Facture::query()
            ->whereIn('statut', ['echec_certification', 'en_attente_certification'])
            // e-MECeF : une facture « à vérifier » (confirmation sans réponse) n'est JAMAIS
            // retransmise automatiquement ; une normalisée ne l'est jamais non plus.
            ->when($mode === ModeFacturation::Emecef, static fn ($q) => $q->where(static function ($w): void {
                $w->whereNull('normalisation_statut')
                    ->orWhereIn('normalisation_statut', [StatutNormalisation::EnAttente->value, StatutNormalisation::Refusee->value]);
            }))
            // Retry-After et réseau tombé : pas avant l'heure dite.
            ->where(static function ($q): void {
                $q->whereNull('emecef_prochain_essai_le')->orWhere('emecef_prochain_essai_le', '<=', now());
            })
            ->orderBy('date_emission')
            ->limit(self::MAX_PAR_PASSAGE)
            ->get();

        $certifiees = 0;
        $echecs = 0;

        foreach ($factures as $facture) {
            try {
                $resultat = $emission->certifier($facture);

                // e-MECeF : une erreur classée est CONSIGNÉE sur la facture, sans exception.
                if ($mode === ModeFacturation::Emecef && ! $resultat->estNormalisee()) {
                    $echecs++;

                    Log::warning('Normalisation e-MECeF en attente', [
                        'facture_id' => $facture->id,
                        'statut' => $resultat->normalisation_statut,
                    ]);

                    continue;
                }

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

        $avoirs = 0;

        // e-MECeF : les avoirs de factures normalisées, en attente ou refusés.
        if ($mode === ModeFacturation::Emecef) {
            $enAttente = Avoir::query()
                ->whereIn('normalisation_statut', [StatutNormalisation::EnAttente->value, StatutNormalisation::Refusee->value])
                ->where(static function ($q): void {
                    $q->whereNull('emecef_prochain_essai_le')->orWhere('emecef_prochain_essai_le', '<=', now());
                })
                ->limit(self::MAX_PAR_PASSAGE)
                ->get();

            foreach ($enAttente as $avoir) {
                if ($emission->certifierAvoir($avoir)->normalisation_statut === StatutNormalisation::Normalisee->value) {
                    $avoirs++;
                }
            }
        }

        return [
            'tentees' => $factures->count(),
            'certifiees' => $certifiees,
            'echecs' => $echecs,
            'avoirs' => $avoirs,
        ];
    }
}
