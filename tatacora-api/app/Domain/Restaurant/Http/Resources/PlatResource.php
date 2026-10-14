<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Http\Resources;

use App\Domain\Restaurant\Models\Menu;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Models\Recette;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Un plat du catalogue — le tableau de `m4-restauration.html` et le sélecteur
 * de plats du point de vente.
 *
 * ## `categorie` descend, mais elle vient du menu
 *
 * Le maître la porte sur le plat ; le schéma la porte sur `menus.type`. Elle
 * est donc **projetée** ici, pas stockée deux fois : deux colonnes décrivant la
 * même chose divergeraient au premier reclassement de menu (Article 10 de la
 * directive de conformité).
 *
 * ## Aucun stock, aucun coût matière sur cette ressource
 *
 * Ce sont des calculs, et ils vivent sur `GET /restaurant/carte`. Les
 * dupliquer ici en ferait deux chemins de calcul pour le même chiffre —
 * exactement ce que PA-121 interdit.
 *
 * @property-read Plat $resource
 */
class PlatResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $menu = $this->resource->menu;
        $recette = $this->resource->recette;

        return [
            'id' => $this->resource->id,
            'libelle' => $this->resource->libelle,
            'prix_vente' => (string) $this->resource->prix_vente,

            'menu_id' => $this->resource->menu_id,
            'menu' => $menu instanceof Menu ? [
                'id' => $menu->id,
                'libelle' => $menu->libelle,
                'type' => $menu->type,
            ] : null,
            'categorie' => $menu instanceof Menu ? $menu->type : null,

            'recette_id' => $this->resource->recette_id,
            'recette' => $recette instanceof Recette ? [
                'id' => $recette->id,
                'libelle' => $recette->libelle,
            ] : null,
        ];
    }
}
