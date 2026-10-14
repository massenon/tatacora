<?php

declare(strict_types=1);

namespace App\Domain\Bar\Http\Requests;

use App\Domain\Bar\Models\CarteBoisson;
use Illuminate\Foundation\Http\FormRequest;

/**
 * « Remettre » une boisson à la carte (M5) — aucun champ, mais une écriture :
 * l'indisponibilité en cours est LEVÉE (`date_retour_disponibilite`), jamais
 * effacée.
 *
 * Une requête sans règle existe pour porter le 2e niveau RBAC, la `Policy`,
 * comme toute écriture de ce domaine : le middleware `module:` seul ne
 * vérifie pas la ressource.
 *
 * @see EF-M5-02 Carte des boissons
 */
final class RemettreBoissonALaCarteRequest extends FormRequest
{
    public function authorize(): bool
    {
        $boisson = $this->route('boisson');

        return $boisson instanceof CarteBoisson
            && ($this->user()?->can('update', $boisson) ?? false);
    }

    /**
     * @return array<string, array<int, string>>
     */
    public function rules(): array
    {
        return [];
    }
}
