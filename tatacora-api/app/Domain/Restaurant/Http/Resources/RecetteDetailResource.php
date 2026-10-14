<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Http\Resources;

use App\Domain\Restaurant\Models\Recette;
use App\Domain\Restaurant\ReadModels\CoutMatiere;
use App\Domain\Stocks\Models\Article;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Fiche technique DÉTAILLÉE : la composition ligne à ligne — EF-M4-02.
 *
 * C'est le sous-formulaire réclamé par PA-23, en remplacement du textarea
 * « Ingrédients principaux » du prototype. Chaque ligne porte l'article réel,
 * son unité de mesure, sa quantité, et le coût unitaire qui sert au total.
 *
 * ## `cout_unitaire: null` nomme l'article jamais réceptionné
 *
 * Le coût moyen pondéré d'un article jamais reçu vaut zéro. Ce n'est pas un
 * prix : c'est une absence de prix. Le rendre à `"0.0000"` ferait apparaître un
 * ingrédient gratuit dans une fiche technique, et le total en dessous serait
 * sous-évalué sans que rien ne le signale.
 *
 * @property-read Recette $resource
 */
class RecetteDetailResource extends JsonResource
{
    /**
     * @param  list<array{article: Article|null, article_id: string, quantite_unitaire: string}>  $composition
     */
    public function __construct(
        Recette $resource,
        private readonly CoutMatiere $cout,
        private readonly array $composition,
    ) {
        parent::__construct($resource);
    }

    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $lignes = [];

        foreach ($this->composition as $ligne) {
            $article = $ligne['article'];
            $cmp = $article instanceof Article ? (string) $article->cout_moyen_pondere : '0';
            $valorise = bccomp($cmp, '0', 4) > 0;

            $lignes[] = [
                'article_id' => $ligne['article_id'],
                'article_libelle' => $article instanceof Article ? $article->libelle : null,
                'unite_mesure' => $article instanceof Article ? $article->unite_mesure : null,
                'quantite_unitaire' => $ligne['quantite_unitaire'],
                'cout_unitaire' => $valorise ? $cmp : null,
                'cout_ligne' => $valorise ? bcmul($ligne['quantite_unitaire'], $cmp, 2) : null,
            ];
        }

        return [
            'id' => $this->resource->id,
            'libelle' => $this->resource->libelle,
            'cout_matiere' => $this->cout->montant,
            'cout_matiere_incomplet' => $this->cout->incomplet,
            'composition_vide' => $this->cout->compositionVide,
            'articles_sans_cout' => $this->cout->articlesSansCout,
            'composition' => $lignes,
            // La marque « composition provisoire » (04/09/2026) : les quantites
            // de cette fiche ont ete POSEES pour debloquer le service, jamais
            // pesees. Le cout ci-dessus est donc calcule sur des grammages que
            // personne n'a mesures — le taire ferait lire un cout matiere de
            // reference la ou il n'y a qu'un ordre de grandeur.
            'composition_provisoire' => $this->resource->composition_provisoire === true,
        ];
    }
}
