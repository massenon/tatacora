<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Http\Resources;

use App\Domain\Crm\Models\Client;
use App\Domain\Restaurant\Models\CommandeRestaurant;
use App\Domain\Restaurant\Models\LigneCommandeRestaurant;
use App\Domain\Restaurant\Models\Plat;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Détail d'une commande — c'est le BON DE CUISINE d'EF-M4-05.
 *
 * ## Ce qu'un bon de cuisine porte, et ce qu'il ne porte pas
 *
 * Il porte ce qui sert à produire : le plat, la quantité, la table ou la
 * chambre, l'heure. Il ne porte **aucun prix** — d'une part la cuisine n'en a
 * pas l'usage, d'autre part `lignes_commande_restaurant` ne fige aucun prix
 * unitaire, si bien qu'un montant y serait recalculé au tarif du jour et
 * deviendrait faux pour toute commande antérieure à un changement de carte.
 *
 * ## `recette_incomplete` est la seule alerte utile de ce document
 *
 * Un plat dont la fiche technique n'a aucun ingrédient se transmet et se vend,
 * mais ne sort AUCUN stock (décision du PO du 30/10/2026, « le stock s'ajoute
 * après » : il faisait auparavant échouer la transmission, par
 * `RecetteManquanteException`). Le signaler sur le détail de la commande dit à
 * la cuisine que rien n'a été décrémenté pour ce plat. C'est le même chiffre que
 * la colonne « lié au stock » de la carte, calculé au même endroit.
 *
 * ## EF-M4-05 est servi en LECTURE, pas en temps réel
 *
 * `05_MODULE_SPECIFICATIONS.md` §M4 demande une notification poussée
 * (WebSocket ou scrutation courte) : « la cuisine doit voir la commande
 * apparaître sans action manuelle de la salle ». Cette route rend le contenu
 * du bon ; le canal de poussée relève de M12, qui n'existe pas (l'API WhatsApp
 * n'est pas contractée). L'écart est nommé, pas masqué — annoncer un temps réel
 * que rien ne produit serait PA-59/60/61.
 *
 * @property-read CommandeRestaurant $resource
 */
class BonCuisineResource extends JsonResource
{
    /**
     * @param  array<string, int>  $ingredientsParRecette  nombre d'ingrédients, par identifiant de recette
     */
    public function __construct(CommandeRestaurant $resource, private readonly array $ingredientsParRecette)
    {
        parent::__construct($resource);
    }

    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $client = $this->resource->client;
        $lignes = [];

        /** @var LigneCommandeRestaurant $ligne */
        foreach ($this->resource->lignes as $ligne) {
            $plat = $ligne->plat;
            $recetteId = $plat instanceof Plat ? (string) $plat->recette_id : '';
            $nbIngredients = $this->ingredientsParRecette[$recetteId] ?? 0;

            $lignes[] = [
                'id' => $ligne->id,
                'plat_id' => $ligne->plat_id,
                'plat_libelle' => $plat instanceof Plat ? $plat->libelle : null,
                'quantite' => $ligne->quantite,
                'recette_id' => $plat instanceof Plat ? $plat->recette_id : null,
                'nb_ingredients' => $nbIngredients,
                // Ce plat fera échouer la transmission tant que sa fiche est
                // vide : le dire ici, c'est le corriger avant le comptoir.
                'recette_incomplete' => $nbIngredients === 0,
            ];
        }

        return [
            'id' => $this->resource->id,
            'statut' => $this->resource->statut,
            'date_commande' => $this->resource->date_commande->toIso8601String(),
            'table_ou_chambre_id' => $this->resource->table_ou_chambre_id,
            'client_id' => $this->resource->client_id,
            'client_nom' => $client instanceof Client ? $client->nomComplet() : null,
            'lignes' => $lignes,
            'transmise' => $this->resource->estTransmise(),
        ];
    }
}
