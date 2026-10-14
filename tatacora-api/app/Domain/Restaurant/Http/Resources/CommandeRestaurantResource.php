<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Http\Resources;

use App\Domain\Crm\Models\Client;
use App\Domain\Restaurant\Models\CommandeRestaurant;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Une commande au registre — EF-M4-03.
 *
 * ## Aucun montant, et c'est délibéré
 *
 * `lignes_commande_restaurant` porte `plat_id` et `quantite`, **sans
 * `prix_unitaire`** — contrairement à `lignes_vente_bar`. Un total calculé au
 * prix courant serait donc juste sur une commande du jour et faux sur toute
 * commande antérieure à un changement de carte, sans que rien ne le signale.
 * Un chiffre faux mais plausible ne se voit pas (PA-110). Le registre ne rend
 * donc aucun montant ; la lacune de schéma est signalée au rapport.
 *
 * ## `table_ou_chambre_id` descend brut, sans être qualifié
 *
 * La colonne ne porte aucun discriminant de type : rien, au schéma, ne dit si
 * l'identifiant désigne une table de salle ou une chambre. Le deviner par une
 * jointure opportuniste ferait afficher « Chambre » sur une table, ou
 * l'inverse — et un room-service serait servi à l'étage pendant que le client
 * attend en salle.
 *
 * @property-read CommandeRestaurant $resource
 */
class CommandeRestaurantResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $client = $this->resource->client;

        return [
            'id' => $this->resource->id,
            'statut' => $this->resource->statut,
            'date_commande' => $this->resource->date_commande->toIso8601String(),
            'table_ou_chambre_id' => $this->resource->table_ou_chambre_id,
            'client_id' => $this->resource->client_id,
            // `nomComplet()`, jamais une concatenation recopiee ici : une
            // seconde formule divergerait a la premiere correction de saisie.
            'client_nom' => $client instanceof Client ? $client->nomComplet() : null,
            // La relation est chargee par le controleur : `lignes()->count()`
            // ferait une requete PAR LIGNE de la page, soit cinquante requetes
            // pour un registre de cinquante commandes.
            'nb_lignes' => $this->resource->lignes->count(),
        ];
    }
}
