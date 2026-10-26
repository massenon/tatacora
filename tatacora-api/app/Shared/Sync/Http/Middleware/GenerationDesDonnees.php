<?php

declare(strict_types=1);

namespace App\Shared\Sync\Http\Middleware;

use App\Shared\Backup\Services\ReinitialisationDonneesTestService;
use App\Shared\Sync\Services\GenerationDonneesService;
use App\Shared\Sync\Services\JournalEnvoiService;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * La génération des données sur les routes de SYNCHRONISATION (décision du
 * PO du 19/10/2026) — voir `GenerationDonneesService`.
 *
 *  - toute réponse porte `X-Tatacora-Generation` (et sa date) : le poste
 *    retient la génération avec laquelle il travaille ; et
 *    `X-Tatacora-Phase-Essais` : le poste affiche, comme la PWA, que la
 *    phase d'essais en production est en cours ;
 *  - une requête qui rappelle une AUTRE génération (`generation`, corps ou
 *    paramètre) est refusée AVANT tout traitement : 409, code
 *    `generation_perimee`. Rien n'est écrit, rien n'est servi : un poste
 *    d'avant la réinitialisation ne renvoie pas ses essais, et ne reçoit pas
 *    un catalogue qu'il mêlerait aux siens.
 */
final class GenerationDesDonnees
{
    public const ENTETE = 'X-Tatacora-Generation';

    public const ENTETE_DEPUIS = 'X-Tatacora-Generation-Depuis';

    public const CODE_PERIMEE = 'generation_perimee';

    /** `1` pendant la phase d'essais en production : les postes le disent. */
    public const ENTETE_PHASE_ESSAIS = 'X-Tatacora-Phase-Essais';

    public function __construct(
        private readonly GenerationDonneesService $generations,
        private readonly ReinitialisationDonneesTestService $reinitialisation,
        private readonly JournalEnvoiService $envoi,
    ) {
    }

    /** Le poste du refus : celui que la requête déclare, à défaut le nom de son jeton. */
    private function posteDe(Request $request): ?string
    {
        $declare = $request->input('poste_id');

        if (is_string($declare) && $declare !== '') {
            return $declare;
        }

        $jeton = $request->user()?->currentAccessToken();

        return $jeton instanceof \Laravel\Sanctum\PersonalAccessToken ? $jeton->name : null;
    }

    public function handle(Request $request, Closure $next): Response
    {
        $courante = $this->generations->courante();
        $rappelee = $request->input('generation');

        if (is_string($rappelee) && ! $this->generations->concorde($rappelee)) {
            // Journal d'envoi (26/10/2026) : le refus est compté pour ce poste.
            $this->envoi->noterGenerationPerimee($this->posteDe($request));
            $reponse = response()->json([
                'code' => self::CODE_PERIMEE,
                'message' => __('sync.generation_perimee', ['date' => $courante->created_at->format('d/m/Y H:i')]),
                'generation' => $courante->generation,
                'reinitialisee_le' => $courante->created_at->toIso8601String(),
            ], 409);
        } else {
            $reponse = $next($request);
        }

        $reponse->headers->set(self::ENTETE, $courante->generation);
        $reponse->headers->set(self::ENTETE_DEPUIS, $courante->created_at->toIso8601String());
        $reponse->headers->set(self::ENTETE_PHASE_ESSAIS, $this->reinitialisation->enPhaseEssais() ? '1' : '0');

        return $reponse;
    }
}
