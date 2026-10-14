<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Http\Resources;

use App\Domain\Restaurant\Models\Recette;
use App\Domain\Restaurant\ReadModels\CoutMatiere;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Une fiche technique et son coût matière — EF-M4-02.
 *
 * ## `recettes.cout_matiere_calcule` N'EST PAS LU ICI
 *
 * La colonne existe, mais rien ne l'écrivait avant
 * `CompositionRecetteService` : elle vaut `0.00` sur toute recette créée avant
 * ce lot, et elle ne sait de toute façon pas dire « inconnu » (elle est NOT
 * NULL DEFAULT 0). La servir telle quelle afficherait « coût matière : 0 F »,
 * donc « marge : prix de vente entier », sur l'écran où l'on fixe un prix —
 * même forme que PA-126. Le coût est donc **recalculé** à chaque lecture, par
 * la même fonction que celle qui l'écrit.
 *
 * ## Trois états, pas deux
 *
 * `cout_matiere: null` + `composition_vide: true` → aucune ligne.
 * `cout_matiere: null` + `cout_matiere_incomplet: true` → au moins un
 * ingrédient jamais réceptionné, donc sans coût moyen pondéré ;
 * `articles_sans_cout` les nomme, pour que la correction soit possible.
 * Un montant → tous les ingrédients sont valorisés.
 *
 * @property-read Recette $resource
 */
class RecetteResource extends JsonResource
{
    public function __construct(Recette $resource, private readonly CoutMatiere $cout)
    {
        parent::__construct($resource);
    }

    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->resource->id,
            'libelle' => $this->resource->libelle,
            'cout_matiere' => $this->cout->montant,
            'cout_matiere_incomplet' => $this->cout->incomplet,
            'composition_vide' => $this->cout->compositionVide,
            'articles_sans_cout' => $this->cout->articlesSansCout,
            // La marque « composition provisoire » (04/09/2026) : les quantites
            // de cette fiche ont ete POSEES pour debloquer le service, jamais
            // pesees. Le cout ci-dessus est donc calcule sur des grammages que
            // personne n'a mesures — le taire ferait lire un cout matiere de
            // reference la ou il n'y a qu'un ordre de grandeur.
            'composition_provisoire' => $this->resource->composition_provisoire === true,
        ];
    }
}
