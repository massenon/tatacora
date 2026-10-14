<?php

declare(strict_types=1);

namespace App\Domain\TableauxDeBord\Http\Controllers;

use App\Domain\TableauxDeBord\Data\Periode;
use App\Domain\TableauxDeBord\Services\TableauDeBordService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Tableau de bord global — EF-M11-01, EF-M11-03, EF-M11-04.
 *
 * Simple orchestrateur : aucun calcul en ligne ici
 * (`SPEC_ECRAN_M11_TABLEAU_DE_BORD.md` §4, « chaque KPI est une méthode
 * dédiée d'un `TableauDeBordService`, jamais un calcul en ligne dans le
 * contrôleur »).
 *
 * L'export (EF-M11-05) n'est pas exposé ici : il passe par le Hub M14
 * (`POST /api/v1/etats/generer` avec `etat=tableau-de-bord`), sans quoi une
 * seconde route d'export finirait par diverger de la première.
 */
class TableauDeBordController
{
    public function __construct(
        private readonly TableauDeBordService $indicateurs,
    ) {
    }

    public function __invoke(Request $request): JsonResponse
    {
        $valide = $request->validate([
            'periode' => ['sometimes', Rule::in(Periode::CODES)],
        ]);

        $periode = Periode::depuisCode($valide['periode'] ?? Periode::DEFAUT);

        return response()->json([
            'data' => [
                'periode' => [
                    'code' => $periode->code,
                    'libelle' => $periode->libelle(),
                    'debut' => $periode->debut->toIso8601String(),
                    // Borne EXCLUE, exposée telle quelle : un client qui
                    // recalculerait un intervalle inclusif décalerait ses
                    // propres agrégats d'une journée.
                    'fin_exclue' => $periode->fin->toIso8601String(),
                    'nombre_jours' => $periode->nombreJours(),
                ],
                'indicateurs' => $this->indicateurs->indicateurs($periode),
                // Exposé à côté de l'encaissé, jamais à sa place : l'écart
                // entre les deux est l'information de recouvrement.
                'chiffre_affaires_facture' => $this->indicateurs->chiffreAffairesFacture($periode),
                'effectif' => $this->indicateurs->effectif(),
            ],
        ]);
    }
}
