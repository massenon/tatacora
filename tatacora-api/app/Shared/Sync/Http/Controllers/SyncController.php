<?php

declare(strict_types=1);

namespace App\Shared\Sync\Http\Controllers;

use App\Shared\Sync\Http\Requests\SynchroniserRequest;
use App\Shared\Sync\Services\SynchronisationService;
use App\Shared\Sync\Support\PosteDuJeton;
use Illuminate\Http\JsonResponse;

/**
 * Endpoint de synchronisation differee — LARAVEL_SYNC_FLUTTER.md §2.
 *
 * Simple orchestrateur : toute la logique est dans SynchronisationService.
 */
class SyncController
{
    public function __construct(
        private readonly SynchronisationService $synchronisation,
    ) {
    }

    public function __invoke(SynchroniserRequest $request): JsonResponse
    {
        $valide = $request->validated();

        // §8 — le `poste_id` doit etre celui du jeton (PA-66).
        //
        // Le document affirmait cette verification depuis l'origine ; elle
        // n'existait pas : `poste_id` etait une chaine libre que le client
        // choisissait. Ce n'est pas une escalade de privileges — un jeton vole
        // porte deja les droits de son proprietaire — mais le `poste_id`
        // commande la classification des conflits (RG-17) : un client qui
        // annonce un autre poste que le sien fait passer ses propres ecritures
        // pour celles d'un tiers, et l'arbitrage porte alors sur une provenance
        // fausse. Il pollue aussi les traces de `journal_securite` et de
        // `sessions_synchronisation`.
        //
        // Le refus porte sur le LOT entier, contrairement au refus RBAC de
        // PA-65 : ce n'est pas une operation qui est en cause mais l'identite
        // du lot lui-meme. En accepter une partie inscrirait une provenance
        // fausse en base.
        //
        // La règle (et le piège de `Sanctum::actingAs`) vit dans
        // `PosteDuJeton`, partagée depuis le 15/10/2026 avec le
        // téléchargement du catalogue.
        if (! PosteDuJeton::concorde($request, $valide['poste_id'])) {
            return response()->json(['message' => __('sync.poste_non_reconnu')], 403);
        }

        $reponse = $this->synchronisation->traiterLot(
            posteId: $valide['poste_id'],
            operations: $valide['operations'],
            utilisateurId: (string) $request->user()->id,
        );

        // 200 et non 207 : le lot a bien ete traite. Le statut par operation
        // porte le detail (§2.2) — un code HTTP global masquerait le fait
        // qu'une partie du lot a reussi.
        return response()->json($reponse);
    }
}
