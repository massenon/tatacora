<?php

declare(strict_types=1);

namespace App\Shared\Sync\Http\Controllers;

use App\Domain\Facturation\Models\Avoir;
use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Services\EmissionFactureService;
use App\Domain\Facturation\Services\ModeFacturation;
use App\Domain\Facturation\Services\StatutNormalisation;
use App\Models\User;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\DocumentsDesAutresPostes;
use App\Shared\Sync\Support\PosteDuJeton;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Les deux gestes de facturation qui se font EN LIGNE depuis un poste (décisions du PO du
 * 07/11/2026), par le jeton d'appairage :
 *
 *  * `POST /api/v1/sync/factures/{facture}/avoir` — l'AVOIR (annulation du TTC entier, ou
 *    partiel) d'une facture. Il naît AU SERVEUR, sous l'identifiant du serveur, et descend au
 *    poste par la synchronisation (jamais écrit sur le poste par cette réponse). Normalisé
 *    ensuite selon le mode : e-MECeF = le serveur (type FA) ; boîtier = le poste avec boîtier.
 *    C'est la SEULE porte d'un avoir sur une facture NORMALISÉE : la file du poste le refuse.
 *  * `POST /api/v1/sync/factures/{facture}/normalisation` — la demande IMMÉDIATE de
 *    normalisation e-MECeF. Le serveur normalise (`MecefClientEmecef`, création puis
 *    confirmation) ; le RÉSULTAT revient dans la réponse. Le jeton e-MECeF n'en sort jamais,
 *    et le poste n'appelle jamais la DGI. Idempotent : une facture déjà normalisée n'est
 *    JAMAIS retransmise, sa normalisation est simplement rendue.
 *
 * Contrôles, dans l'ordre : compte actif (401), poste du jeton (403), droit d'ÉCRITURE sur M2
 * (403), facture connue (404 `facture_inconnue` : le poste la monte puis réessaie), règles.
 * Aucun secret dans aucune réponse.
 */
final class FacturesEnLigneController
{
    private const MODULE = 'M2';

    public function __construct(
        private readonly EmissionFactureService $emission,
        private readonly DocumentsDesAutresPostes $autresPostes,
    ) {
    }

    public function avoir(Request $request, string $facture): JsonResponse
    {
        $garde = $this->garde($request);

        if ($garde instanceof JsonResponse) {
            return $garde;
        }

        [$utilisateur, $poste] = $garde;

        $valide = validator($request->all(), [
            'motif' => ['required', 'string', 'max:500'],
            'montant' => ['nullable', 'integer', 'gt:0'],
            'demande_id' => ['nullable', 'uuid'],
        ], [
            'motif.required' => __('validation.required', ['attribute' => 'motif']),
            'montant.integer' => __('sync.factures.avoir_montant_invalide'),
            'montant.gt' => __('sync.factures.avoir_montant_invalide'),
        ]);

        if ($valide->fails()) {
            return response()->json(['message' => (string) $valide->errors()->first(), 'errors' => $valide->errors()], 422);
        }

        $document = Facture::query()->find($facture);

        if ($document === null) {
            return response()->json(['code' => 'facture_inconnue', 'message' => __('facturation.en_ligne.facture_inconnue')], 404);
        }

        $donnees = $valide->validated();
        $demande = isset($donnees['demande_id']) ? 'avoir-en-ligne:'.$donnees['demande_id'] : null;

        // Rejeu (réponse perdue) : la même demande rend le MÊME avoir, jamais un second.
        if ($demande !== null && ($dejaId = Cache::get($demande)) !== null) {
            $existant = Avoir::query()->find($dejaId);

            if ($existant !== null) {
                return $this->reponseAvoir($document, $existant, true);
            }
        }

        $entier = ! isset($donnees['montant']);

        try {
            if ($entier) {
                $dejaEntier = Avoir::query()->where('facture_id', $document->id)
                    ->where('montant', '>=', (string) $document->montant_ttc)->first();

                if ($dejaEntier !== null) {
                    return $this->reponseAvoir($document, $dejaEntier, true);
                }

                $this->autresPostes->verifierAnnulation('factures', $document->id, new ContexteSynchronisation(
                    $poste,
                    $utilisateur,
                    now(),
                    now(),
                ));
            }

            $avoir = DB::transaction(function () use ($document, $donnees, $entier, $utilisateur): Avoir {
                auth()->setUser($utilisateur);

                return $this->emission->emettreAvoir(
                    $document,
                    $entier ? (string) $document->montant_ttc : number_format((float) $donnees['montant'], 2, '.', ''),
                    trim((string) $donnees['motif']),
                );
            });
        } catch (\InvalidArgumentException|RuntimeException $refus) {
            return response()->json(['code' => 'avoir_refuse', 'message' => $refus->getMessage()], 422);
        }

        if ($demande !== null) {
            Cache::put($demande, (string) $avoir->id, now()->addDay());
        }

        return $this->reponseAvoir($document, $avoir->refresh(), false);
    }

    public function normaliser(Request $request, string $facture): JsonResponse
    {
        $garde = $this->garde($request);

        if ($garde instanceof JsonResponse) {
            return $garde;
        }

        $document = Facture::query()->find($facture);

        if ($document === null) {
            return response()->json(['code' => 'facture_inconnue', 'message' => __('facturation.en_ligne.facture_inconnue')], 404);
        }

        // Déjà normalisée : rendue telle quelle, JAMAIS retransmise (idempotent).
        if ($document->normalisation_statut === StatutNormalisation::Normalisee->value) {
            return $this->reponseNormalisation($document, true);
        }

        if (ModeFacturation::courant() !== ModeFacturation::Emecef) {
            return response()->json([
                'code' => 'mode_non_emecef',
                'message' => ModeFacturation::courant() === ModeFacturation::Boitier
                    ? __('facturation.mode.normaliser_poste')
                    : __('facturation.mode.normaliser_desactive'),
            ], 422);
        }

        try {
            $document = $this->emission->normaliserLaFacture($document);
        } catch (RuntimeException $refus) {
            return response()->json(['code' => 'normalisation_refusee', 'message' => $refus->getMessage()], 422);
        }

        return $this->reponseNormalisation($document, false);
    }

    /** @return array{0: User, 1: string}|JsonResponse */
    private function garde(Request $request): array|JsonResponse
    {
        $utilisateur = $request->user();

        if (! $utilisateur instanceof User || ! $utilisateur->estActif()) {
            return response()->json(['message' => __('sync.referentiels.compte_inactif')], 401);
        }

        $poste = (string) $request->input('poste_id', '');

        if ($poste === '' || strlen($poste) > 255) {
            return response()->json([
                'message' => 'Le poste est obligatoire.',
                'errors' => ['poste_id' => ['Le champ poste id est obligatoire.']],
            ], 422);
        }

        if (! PosteDuJeton::concorde($request, $poste)) {
            return response()->json(['message' => __('sync.poste_non_reconnu')], 403);
        }

        if ($utilisateur->niveauSurModule(self::MODULE) !== 'C') {
            return response()->json(['message' => __('auth.module_refuse')], 403);
        }

        return [$utilisateur, $poste];
    }

    private function reponseAvoir(Facture $facture, Avoir $avoir, bool $rejeu): JsonResponse
    {
        return response()->json(['data' => [
            'facture_id' => (string) $facture->id,
            'avoir_id' => (string) $avoir->id,
            'numero_avoir' => $avoir->numero,
            'montant' => (string) $avoir->montant,
            'entier' => bccomp((string) $avoir->montant, (string) $facture->montant_ttc, 2) >= 0,
            'normalisation_statut' => $avoir->normalisation_statut,
            'normalisation_mode' => $avoir->normalisation_mode,
            'normalisation_motif' => $avoir->normalisation_motif,
            'rejeu' => $rejeu,
        ]]);
    }

    /** Le résultat de la normalisation, tel que le poste l'écrit sur sa facture. Jamais un secret. */
    private function reponseNormalisation(Facture $facture, bool $rejeu): JsonResponse
    {
        $facture->refresh();

        return response()->json(['data' => [
            'facture_id' => (string) $facture->id,
            'normalisation_statut' => $facture->normalisation_statut,
            'normalisation_mode' => $facture->normalisation_mode,
            'normalisation_motif' => $facture->normalisation_motif,
            'numero_mecef' => $facture->estNormalisee() ? $facture->numero_mecef : null,
            'qr_code' => $facture->estNormalisee() ? $facture->qr_code_fiscal : null,
            'code_mecef' => $facture->estNormalisee() ? $facture->code_mecef : null,
            'compteur' => $facture->normalisation_compteur,
            'date' => $facture->normalisee_le?->toIso8601String(),
            'rejeu' => $rejeu,
        ]]);
    }
}
