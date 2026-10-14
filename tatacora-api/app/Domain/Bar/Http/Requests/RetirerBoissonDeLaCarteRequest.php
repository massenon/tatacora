<?php

declare(strict_types=1);

namespace App\Domain\Bar\Http\Requests;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Carte\Models\IndisponibiliteCarte;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Valide « Retirer de la carte du jour » d'une boisson (M5) — le motif et son
 * commentaire.
 *
 * Les règles sont celles d'`EcranDeCarte::enregistrerRetraitDeLaCarte()`, à
 * la lettre : deux canaux qui valideraient différemment finiraient par
 * accepter au navigateur ce que l'API refuse, ou l'inverse. Le motif est lu
 * du registre FERMÉ `IndisponibiliteCarte::MOTIFS` — jamais une seconde liste,
 * c'est celle qui avait divergé (`hors_saison` / `retrait` contre `saison` /
 * `retire`) sans que rien ne se voie à l'écran.
 *
 * @see EF-M5-02 Carte des boissons
 */
final class RetirerBoissonDeLaCarteRequest extends FormRequest
{
    public function authorize(): bool
    {
        $boisson = $this->route('boisson');

        return $boisson instanceof CarteBoisson
            && ($this->user()?->can('update', $boisson) ?? false);
    }

    /**
     * @return array<string, array<int, mixed>>
     */
    public function rules(): array
    {
        return [
            'motif' => ['required', 'string', Rule::in(array_keys(IndisponibiliteCarte::MOTIFS))],
            'commentaire' => ['nullable', 'string', 'max:255'],
        ];
    }
}
