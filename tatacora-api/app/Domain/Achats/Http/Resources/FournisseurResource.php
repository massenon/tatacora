<?php

declare(strict_types=1);

namespace App\Domain\Achats\Http\Resources;

use App\Domain\Achats\Models\Fournisseur;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Un fournisseur du référentiel — EF-M7-01.
 *
 * `evaluation` descend TELLE QUELLE, `null` compris. `null` veut dire « pas
 * encore évalué », ce qui n'est pas « À revoir » : le prototype rend les deux
 * par un badge, et les confondre reprocherait à un fournisseur neuf une
 * mauvaise note que personne ne lui a donnée. La traduction des quatre valeurs
 * en libellés affichables appartient au client (i18n), pas à l'API.
 *
 * **Aucun encours, aucun montant dû.** Le prototype affiche « Fournisseurs à
 * payer » et « Total dû » (`m7-approvisionnement.html`, onglet « Dettes
 * fournisseurs ») : aucune table du schéma ne porte de facture ni de règlement
 * fournisseur — voir `AchatController` pour le refus complet et sa raison.
 * Rendre `0` ici afficherait « aucune dette » sous un écran qui n'a jamais rien
 * consulté.
 *
 * @property-read Fournisseur $resource
 */
class FournisseurResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->resource->id,
            'raison_sociale' => $this->resource->raison_sociale,
            'contact' => $this->resource->contact,
            'categorie' => $this->resource->categorie,
            'conditions_paiement' => $this->resource->conditions_paiement,
            'evaluation' => $this->resource->evaluation,
        ];
    }
}
