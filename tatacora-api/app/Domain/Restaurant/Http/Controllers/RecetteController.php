<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Http\Controllers;

use App\Domain\Restaurant\Http\Requests\EnregistrerCompositionRequest;
use App\Domain\Restaurant\Http\Requests\EnregistrerRecetteRequest;
use App\Domain\Restaurant\Http\Requests\FiltrerRecettesRequest;
use App\Domain\Restaurant\Http\Resources\RecetteDetailResource;
use App\Domain\Restaurant\Http\Resources\RecetteResource;
use App\Domain\Restaurant\Models\Recette;
use App\Domain\Restaurant\Services\CompositionRecetteService;
use App\Domain\Restaurant\Services\ReferentielRecetteService;
use App\Domain\Stocks\Models\Article;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

/**
 * Fiches techniques de recette — M4, EF-M4-02.
 *
 * @see EF-M4-02 Gestion des fiches techniques (ingrédients, quantités, coût matière)
 * @see RG-05 Sortie de stock automatique — c'est cette composition qui la rend possible
 *
 * ## Ces routes ferment PA-23
 *
 * Le prototype porte la composition d'un plat dans un `textarea` libre
 * (« Ingrédients principaux : Poulet, plantain mûr, poivron »). PA-23 et
 * `SPEC_ECRAN_M4_RESTAURANT.md` §6 le disent tous les deux : **ne jamais porter
 * ce champ tel quel**. Une chaîne de caractères ne se rattache à aucun article,
 * donc ne décrémente aucun stock, et la fiche technique ne sert à rien.
 * `PUT /restaurant/recettes/{recette}/composition` est le sous-formulaire
 * réclamé — de vraies clés étrangères vers `articles`, avec leurs quantités.
 *
 * Ce que PA-23 laisse ouvert et que ce lot ne tranche pas : la maquette de cet
 * écran. Ces routes livrent le contrat de données ; le dessin du
 * sous-formulaire appartient à l'Architecte.
 *
 * ## Aucune suppression de recette
 *
 * `plats.recette_id` est NOT NULL et en `restrictOnDelete()` : un plat sans
 * fiche technique ne peut pas exister au schéma. Vider une composition erronée
 * se fait par un `PUT` à `lignes: []`, ce qui rend le plat visiblement « ne
 * décrémente rien » sur la carte et fait refuser sa transmission en cuisine —
 * un état franc, à la place d'une composition fausse qui décrémenterait les
 * mauvais articles en silence.
 */
class RecetteController
{
    public function __construct(
        private readonly CompositionRecetteService $compositions,
        private readonly ReferentielRecetteService $referentiel,
    ) {
    }

    /**
     * Référentiel des fiches techniques — la source du sélecteur « Recette »
     * du formulaire de plat.
     *
     * Le coût matière est **recalculé** pour chaque ligne, jamais lu dans
     * `recettes.cout_matiere_calcule` : cette colonne n'était écrite par
     * personne avant ce lot, et elle ne sait pas dire « inconnu ».
     */
    public function index(FiltrerRecettesRequest $request): AnonymousResourceCollection
    {
        $requete = Recette::query()
            ->when(
                $request->filtre('recherche'),
                fn (Builder $q, string $terme): Builder => $q->where('libelle', 'like', '%' . $terme . '%'),
            )
            ->orderBy('libelle')
            ->orderBy('id');

        $page = $requete->paginate($request->parPage());

        return RecetteResource::collection($page->through(
            fn (Recette $recette): RecetteResource => new RecetteResource(
                $recette,
                $this->compositions->coutMatiere($recette),
            ),
        ));
    }

    /**
     * Fiche technique détaillée — la composition ligne à ligne, avec le coût
     * unitaire de chaque ingrédient et le total.
     */
    public function show(Recette $recette): RecetteDetailResource
    {
        return $this->detail($recette);
    }

    public function store(EnregistrerRecetteRequest $request): JsonResponse
    {
        $recette = $this->referentiel->creer($request->validated());

        return (new RecetteResource($recette, $this->compositions->coutMatiere($recette)))
            ->response()
            ->setStatusCode(201);
    }

    /**
     * Remplacement intégral de la composition — EF-M4-02.
     *
     * Remplacement et non fusion : `ingredients_recette` n'a pas d'identité de
     * ligne propre (clé primaire composite), et un enregistrement ligne à ligne
     * laisserait en place tout ingrédient retiré du formulaire. Le plat
     * continuerait alors de décrémenter un article que sa fiche ne mentionne
     * plus, et l'écart n'apparaîtrait qu'à l'inventaire — imputé à tort à une
     * perte physique.
     *
     * Le coût matière est recalculé et persisté dans le même geste : c'est le
     * seul chemin du dépôt qui écrit `recettes.cout_matiere_calcule`.
     */
    public function composition(EnregistrerCompositionRequest $request, Recette $recette): RecetteDetailResource
    {
        $recette = $this->compositions->remplacerComposition($recette, $request->lignes());

        return $this->detail($recette);
    }

    /**
     * Compose la ressource détaillée : composition, articles et coût, tous
     * issus du même service.
     */
    private function detail(Recette $recette): RecetteDetailResource
    {
        $lignes = $this->compositions->lignes($recette);

        $articles = Article::query()
            ->whereIn('id', array_column($lignes, 'article_id'))
            ->get()
            ->keyBy('id');

        $composition = [];

        foreach ($lignes as $ligne) {
            $article = $articles->get($ligne['article_id']);

            $composition[] = [
                'article' => $article instanceof Article ? $article : null,
                'article_id' => $ligne['article_id'],
                'quantite_unitaire' => $ligne['quantite_unitaire'],
            ];
        }

        return new RecetteDetailResource(
            $recette,
            $this->compositions->coutMatiere($recette),
            $composition,
        );
    }
}
