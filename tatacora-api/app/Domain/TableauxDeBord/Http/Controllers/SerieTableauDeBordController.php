<?php

declare(strict_types=1);

namespace App\Domain\TableauxDeBord\Http\Controllers;

use App\Domain\TableauxDeBord\Data\Periode;
use App\Domain\TableauxDeBord\Services\TableauDeBordService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Séries du tableau de bord — EF-M11-01 (graphiques).
 *
 * ## Pourquoi une route DISTINCTE de `/tableau-de-bord`
 *
 * Le prototype pose deux commandes indépendantes sur le même écran : le filtre
 * de période, qui gouverne la bande d'indicateurs, et un sélecteur **3 / 6 /
 * 12 mois** propre au graphique du chiffre d'affaires. Les servir ensemble
 * obligerait à recalculer les huit KPI chaque fois que quelqu'un bascule de 3
 * à 6 mois — huit agrégats pour un geste qui n'en concerne aucun.
 *
 * La ventilation par activité, elle, suit bien la période : elle est donc
 * exposée ici avec le même paramètre `periode` que la bande.
 *
 * L'export (EF-M11-05) reste au Hub M14, comme pour la bande : une seconde
 * route d'export finirait par diverger de la première.
 */
class SerieTableauDeBordController
{
    public function __construct(
        private readonly TableauDeBordService $indicateurs,
    ) {
    }

    public function __invoke(Request $request): JsonResponse
    {
        $valide = $request->validate([
            'periode' => ['sometimes', Rule::in(Periode::CODES)],
            // Borne FERMÉE, validée ici ET dans le service : une URL
            // composée à la main ne doit pas pouvoir demander cinquante ans
            // de série sur un hébergement mutualisé.
            'mois' => ['sometimes', 'integer', 'min:1', 'max:'.TableauDeBordService::MOIS_MAX],
        ]);

        $periode = Periode::depuisCode($valide['periode'] ?? Periode::DEFAUT);
        $mois = (int) ($valide['mois'] ?? 6);

        return response()->json([
            'data' => [
                'mensuelle' => $this->indicateurs->serieMensuelle($mois),
                'ventilation_activite' => $this->indicateurs->ventilationParActivite($periode),
                'periode' => [
                    'code' => $periode->code,
                    'libelle' => $periode->libelle(),
                ],
            ],
        ]);
    }
}
