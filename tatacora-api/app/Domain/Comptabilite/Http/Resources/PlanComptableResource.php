<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Resources;

use App\Domain\Comptabilite\ReadModels\PlanComptable;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * L'ecran « Plan Comptable » d'un seul parcours — EF-M10-01.
 *
 * ## Pourquoi les decomptes voyagent avec les lignes
 *
 * Le sous-titre du maitre (l.29) annonce l'effectif du plan, et les huit
 * boutons de filtre sont au-dessus du tableau. Les servir par une seconde
 * requete ferait afficher un effectif qui ne correspond plus aux lignes des que
 * le referentiel bouge entre les deux appels — PA-121, un total qui ne fait pas
 * la somme de ce qu'on voit juste en dessous.
 *
 * ## `classes_hors_ecran` est le champ qui SIGNALE un trou
 *
 * Les classes 8 (HAO) et 9 (analytique) existent au schema et n'ont aucun
 * bouton a l'ecran. Ce decompte est vide dans le cas normal ; s'il ne l'est
 * pas, des comptes reels sont inatteignables et le client doit le dire. Sans
 * lui, le plan aurait l'air complet — « un plan SYSCOHADA incomplet se signale,
 * il ne s'invente pas ».
 *
 * @property-read PlanComptable $resource
 */
class PlanComptableResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            // Effectif de TOUT le referentiel, classes hors ecran comprises, et
            // independant du filtre : c'est le « <N> comptes » du sous-titre.
            'total' => $this->resource->total,
            // Les sept classes de l'ecran, ZEROS COMPRIS. Une classe absente
            // serait indiscernable d'une classe vide (Article 7).
            'classes' => (object) $this->resource->comptesParClasse,
            'classes_hors_ecran' => (object) $this->resource->comptesParClasseHorsEcran,
            // Comptes dont `nature` est nulle : cellule vide a l'ecran, defaut
            // de referentiel ici.
            'sans_nature' => $this->resource->sansNature,
            'filtres_appliques' => (object) $this->resource->filtresAppliques,
            'lignes' => CompteComptableResource::collection($this->resource->comptes)->resolve($request),
        ];
    }
}
