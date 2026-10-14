<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Resources;

use App\Domain\Comptabilite\Models\JournalComptable;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Un journal comptable — la source des boutons de filtre de
 * `m10-journal.html` (l.32).
 *
 * Le maitre construit son libelle de bouton comme « Ventes (VTE) » (l.78) : le
 * libelle puis le code entre parentheses. Les deux descendent separement, la
 * mise en forme appartient au client — recopier la phrase ici la figerait cote
 * serveur alors que c'est du copywriting d'ecran, et l'Article 0 donne le
 * maitre pour autorite sur ce qui se voit.
 *
 * @property-read JournalComptable $resource
 */
class JournalComptableResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->resource->id,
            'code' => $this->resource->code,
            'libelle' => $this->resource->libelle,
        ];
    }
}
