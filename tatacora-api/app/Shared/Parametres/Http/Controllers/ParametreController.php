<?php

declare(strict_types=1);

namespace App\Shared\Parametres\Http\Controllers;

use App\Domain\Comptabilite\Services\CalculTvaService;
use App\Domain\Facturation\Providers\MecefServiceProvider;
use App\Shared\Parametres\Data\DefinitionParametre;
use App\Shared\Parametres\Data\RegistreParametres;
use App\Shared\Parametres\Http\Requests\EnregistrerParametresRequest;
use App\Shared\Parametres\Services\EnregistrerParametreService;
use App\Shared\Parametres\Services\ParametreSystemeService;
use Illuminate\Http\JsonResponse;
use RuntimeException;

/**
 * API de l'écran Paramètres (module RBAC `PARAM`).
 *
 * Simple orchestrateur : les gardes vivent dans
 * {@see EnregistrerParametreService}, pas ici.
 *
 * ## La lecture rend des ÉTATS DÉRIVÉS, pas les commutateurs bruts
 *
 * C'est l'obligation laissée ouverte par PA-61. Un écran qui afficherait
 * `tva_active = true` dirait « TVA active » alors que le taux peut être absent
 * et que chaque facture lèverait ; un badge MECeF dérivé de la seule présence
 * de la clé passerait au vert le jour de l'inscription DGI pendant que toutes
 * les factures partiraient encore en démonstration. `etatTva()` et
 * `etatConfiguration()` répondent, eux, sur ce qui est réellement en place.
 *
 * Les valeurs brutes sont renvoyées **en plus** — l'écran doit bien remplir ses
 * champs — mais aucun badge ne se compose à partir d'elles.
 */
class ParametreController
{
    public function __construct(
        private readonly ParametreSystemeService $lecture,
        private readonly EnregistrerParametreService $ecriture,
        private readonly CalculTvaService $tva,
    ) {
    }

    public function index(): JsonResponse
    {
        $definitions = array_map(
            fn (DefinitionParametre $d): array => [
                'cle' => $d->cle,
                'groupe' => $d->groupe,
                'libelle' => $d->libelle,
                'type' => $d->type,
                'choix' => $d->choix,
                'aide' => $d->aide,
                'valeur' => $this->lecture->get($d->cle),
            ],
            RegistreParametres::definitions(),
        );

        $etatTva = $this->tva->etatTva();
        $etatMecef = MecefServiceProvider::etatConfiguration();

        return response()->json([
            'data' => [
                'parametres' => $definitions,
                // Les états dérivés, seule source des badges de l'écran.
                'etats' => [
                    'tva' => [
                        'code' => $etatTva,
                        'libelle' => __('parametres.etats.tva.' . $etatTva),
                    ],
                    'mecef' => [
                        'code' => $etatMecef,
                        'libelle' => __('parametres.etats.mecef.' . $etatMecef),
                    ],
                ],
            ],
        ]);
    }

    public function update(EnregistrerParametresRequest $request): JsonResponse
    {
        /** @var array<string, scalar|null> $soumis */
        $soumis = $request->validated()['parametres'];

        try {
            $modifiees = $this->ecriture->enregistrer($soumis);
        } catch (RuntimeException $e) {
            // 422 et non 500 : le lot est refusé pour ce qu'il contient, pas
            // parce que le serveur est en panne. L'écran doit pouvoir montrer
            // le motif à l'Administrateur plutôt qu'une erreur technique.
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return response()->json([
            'message' => $modifiees === []
                ? __('parametres.aucun_changement')
                : __('parametres.enregistre'),
            'data' => ['modifiees' => $modifiees],
        ]);
    }
}
