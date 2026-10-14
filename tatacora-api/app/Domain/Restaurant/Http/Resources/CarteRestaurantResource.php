<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Http\Resources;

use App\Domain\Restaurant\ReadModels\CarteRestaurant;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * L'écran « Carte du restaurant » entier — `m4-restaurant-carte.html`.
 *
 * ## Ce que le client en fait
 *
 * `indicateurs` remplit la bande de six cartes, `couverture` l'onglet
 * « Couverture du stock », `lignes` l'onglet « Carte du jour ». Les trois
 * viennent du **même** parcours : un total qui ne fait pas la somme des lignes
 * affichées juste en dessous est le défaut que cette route existe pour rendre
 * impossible.
 *
 * ## Deux indicateurs du maître restent ABSENTS — « Prix provisoires » ne l'est plus
 *
 * `carte-module.js` en affiche six. « Retirés du jour » et le sous-titre
 * « N disponible(s) » de la première carte n'ont toujours aucune colonne au
 * schéma : les rendre à `0` annoncerait « aucun plat retiré » sous un écran
 * qui n'a jamais rien consulté — l'indicateur qui affirme un état qu'il n'a
 * pas vérifié (PA-59/60/61). Ils sont omis, et `indicateurs_absents` les nomme
 * **avec leur raison** pour que le client affiche « — » plutôt qu'un chiffre.
 *
 * ⚠ **« Prix provisoires » a QUITTÉ cette liste le 02/09/2026** : son motif —
 * « aucune colonne au schéma » — était devenu faux avec la migration
 * `2026_09_02_200000`, qui pose `plats.prix_provisoire`. L'indicateur est
 * désormais COMPTÉ sur la vraie colonne. Un motif de refus périmé transforme
 * une décision en oubli (PA-144).
 *
 * En échange, deux indicateurs que le maître n'a pas sont rendus parce qu'ils
 * sont réellement calculables et qu'ils comptent ici : `sous_seuil` (ingrédient
 * sous son seuil d'alerte) et `cout_matiere_inconnu` (plats dont on ignore ce
 * qu'ils coûtent).
 *
 * ## `point_cuisine_id` est remonté, et son absence est une information
 *
 * `null` veut dire qu'aucun point de stockage de type `cuisine` n'existe :
 * aucune portion n'est alors calculable, et le client doit le DIRE plutôt que
 * d'afficher une carte sans stock qui passerait pour une carte en rupture.
 *
 * @property-read CarteRestaurant $resource
 */
class CarteRestaurantResource extends JsonResource
{
    /**
     * Indicateurs du maître qu'aucune colonne ne permet de produire.
     *
     * @var array<string, string>
     */
    private const INDICATEURS_ABSENTS = [
        'disponibles' => 'restaurant.absent.disponibilite',
        'indisponibles' => 'restaurant.absent.disponibilite',
    ];

    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $carte = $this->resource;

        $absents = [];

        foreach (self::INDICATEURS_ABSENTS as $indicateur => $cle) {
            $absents[$indicateur] = __($cle);
        }

        return [
            'lignes' => LignePlatCarteResource::collection($carte->lignes)->resolve($request),
            'indicateurs' => $carte->indicateurs,
            'indicateurs_absents' => $absents,
            'couverture' => $carte->couverture,
            // Un export porte sur ce qui est affiché, et il DIT son filtre
            // (PA-119) : sans cela, un état partiel passe pour un état complet.
            'filtres_appliques' => $carte->filtresAppliques,
            'point_cuisine_id' => $carte->pointCuisineId,
            'arrete_au' => $carte->arreteAu,
        ];
    }
}
