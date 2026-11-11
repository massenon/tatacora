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

        // 1. EMISSION (sans réseau, tous modes) : une facture restée « en attente » est ÉMISE
        // (figée, simple). Jamais de numéro fictif : le mode désactivé n'invente rien.
        Facture::query()
            ->where('statut', 'en_attente_certification')
            ->orderBy('date_emission')
            ->limit(self::MAX_PAR_PASSAGE * 4)
            ->get()
            ->each(static fn (Facture $f) => $emission->figerEmission($f));

        // Désactivé et boîtier : le serveur ne normalise PAS (le poste reprend ses factures
        // « en attente de normalisation » à son passage, par bouton).
        if ($mode !== ModeFacturation::Emecef) {
            return ['tentees' => 0, 'certifiees' => 0, 'echecs' => 0, 'avoirs' => 0];
        }

        // 2. e-MECeF : le rejeu ne REPREND que ce qu'un utilisateur a déjà demandé par le
        // bouton « Normaliser » (statut posé : en attente ou refusée). La normalisation n'est
        // JAMAIS automatique à l'émission (décision du PO du 07/11/2026). Une facture « à
        // vérifier » n'est jamais retransmise ; une normalisée ne l'est jamais non plus.
        $factures = Facture::query()
            ->whereIn('normalisation_statut', [StatutNormalisation::EnAttente->value, StatutNormalisation::Refusee->value])
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
                $resultat = $emission->normaliserLaFacture($facture);

                if (! $resultat->estNormalisee()) {
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

                Log::warning('Normalisation e-MECeF en échec', [
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
