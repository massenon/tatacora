<?php

declare(strict_types=1);

namespace App\Domain\Achats\Http\Controllers;

use App\Domain\Achats\Http\Requests\EnregistrerFournisseurRequest;
use App\Domain\Achats\Http\Requests\FiltrerFournisseursRequest;
use App\Domain\Achats\Http\Resources\FournisseurResource;
use App\Domain\Achats\Models\Fournisseur;
use App\Domain\Achats\Services\ReferentielFournisseurService;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

/**
 * Référentiel fournisseurs — M7, EF-M7-01.
 *
 * Alimente l'onglet « Fournisseurs » de `prototype_v2/pages/m7-achats.html` :
 * annuaire recherchable, filtre par évaluation, formulaire de création et de
 * modification. C'est aussi la source du sélecteur « Fournisseur » de la
 * modale « Nouveau bon de commande » — le prototype y propose une liste écrite
 * en dur dans son JavaScript, ce qui est précisément l'anti-pattern que la
 * clé étrangère `commandes_achat.fournisseur_id` existe pour empêcher.
 *
 * Simple orchestrateur (`06_DEVELOPMENT_STANDARDS.md` §2.2).
 *
 * ## Aucune suppression, et ce n'est pas une omission
 *
 * `DELETE` n'est routé nulle part : un fournisseur est référencé par des
 * commandes d'achat, et sa disparition rendrait leur historique illisible
 * juste au moment où on en aurait besoin — un litige. La clé étrangère est
 * d'ailleurs en `restrictOnDelete()`. `CommandeAchatPolicy::delete()` et
 * `FournisseurPolicy::delete()` renvoient `false` en second niveau.
 *
 * Conséquence assumée et signalée : `fournisseurs` n'a **aucune colonne
 * `actif`**. Un fournisseur avec qui l'on cesse de travailler ne peut donc être
 * ni supprimé ni désactivé — il restera au sélecteur. L'arbitrage (ajouter la
 * colonne) appartient à l'Architecte ; le contourner par une suppression
 * physique casserait l'historique.
 */
class FournisseurController
{
    public function __construct(
        private readonly ReferentielFournisseurService $referentiel,
    ) {
    }

    /**
     * Annuaire fournisseurs — EF-M7-01.
     *
     * Paginé, et sans danger : c'est une liste qu'on parcourt et qu'on
     * recherche, et **aucun total n'est rendu au-dessus d'une page**. La
     * différence avec `/stocks/points`, servi entier, tient à la recherche : un
     * point de stockage absent de la page ne serait atteignable par aucun
     * moyen depuis la modale de mouvement, alors qu'un fournisseur se retrouve
     * en tapant son nom.
     */
    public function index(FiltrerFournisseursRequest $request): AnonymousResourceCollection
    {
        $requete = Fournisseur::query()
            ->when(
                $request->filtre('recherche'),
                // Les deux colonnes recherchables du prototype
                // (`colonnesRecherchables`) : raison sociale et contact.
                fn (Builder $q, string $terme): Builder => $q->where(
                    fn (Builder $sous): Builder => $sous
                        ->where('raison_sociale', 'like', '%' . $terme . '%')
                        ->orWhere('contact', 'like', '%' . $terme . '%'),
                ),
            )
            ->when(
                $request->filtre('evaluation'),
                fn (Builder $q, string $evaluation): Builder => $q->where('evaluation', $evaluation),
            )
            ->when(
                $request->filtre('categorie'),
                fn (Builder $q, string $categorie): Builder => $q->where('categorie', $categorie),
            )
            // Départage par `id` : plusieurs fournisseurs peuvent partager la
            // même raison sociale abrégée, et un ordre indéterminé ferait
            // apparaître ou disparaître une ligne entre deux pages.
            ->orderBy('raison_sociale')
            ->orderBy('id');

        return FournisseurResource::collection($requete->paginate($request->parPage()));
    }

    /**
     * Fiche détail d'un fournisseur — l'un des quatre écrans de M7.
     */
    public function show(Fournisseur $fournisseur): FournisseurResource
    {
        return new FournisseurResource($fournisseur);
    }

    public function store(EnregistrerFournisseurRequest $request): JsonResponse
    {
        $fournisseur = $this->referentiel->creer($request->validated());

        return (new FournisseurResource($fournisseur))
            ->response()
            ->setStatusCode(201);
    }

    public function update(EnregistrerFournisseurRequest $request, Fournisseur $fournisseur): FournisseurResource
    {
        return new FournisseurResource(
            $this->referentiel->modifier($fournisseur, $request->validated()),
        );
    }
}
