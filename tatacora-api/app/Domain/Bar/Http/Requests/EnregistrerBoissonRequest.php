<?php

declare(strict_types=1);

namespace App\Domain\Bar\Http\Requests;

use App\Domain\Bar\Models\CarteBoisson;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Valide la creation et la modification d'une boisson de la carte (M5).
 *
 * **Aucun champ de stock n'est accepte, et il ne faut jamais en ajouter.**
 * Le formulaire du prototype comportait « Stock disponible » en saisie libre
 * (PA-24) : la moindre reintroduction de ce champ ferait diverger le stock
 * affiche du stock reel des la premiere vente. Le stock se lit, il ne se
 * saisit pas — StockTheoriqueService en est la seule source.
 *
 * @see EF-M5-02 Carte des boissons
 * @see RG-05 Le lien article_id rend la decrementation possible
 */
final class EnregistrerBoissonRequest extends FormRequest
{
    public function authorize(): bool
    {
        $boisson = $this->route('boisson');

        return $boisson instanceof CarteBoisson
            ? ($this->user()?->can('update', $boisson) ?? false)
            : ($this->user()?->can('create', CarteBoisson::class) ?? false);
    }

    /**
     * @return array<string, array<int, mixed>>
     */
    public function rules(): array
    {
        return [
            'libelle' => ['required', 'string', 'max:255'],
            // Vraie cle etrangere vers le referentiel Stocks : sans elle,
            // aucune vente ne pourrait decrementer quoi que ce soit.
            'article_id' => ['required', 'uuid', 'exists:articles,id'],
            'categorie' => ['required', Rule::in(['locale', 'maison', 'importee'])],
            'prix_vente' => ['required', 'numeric', 'min:0'],

            // PA-161 (b) — les deux marques de prix. `boolean` et non
            // `in:0,1` : Laravel accepte alors « true », « 1 » et 1, les trois
            // formes qu'un formulaire et un client JSON envoient reellement.
            // `sometimes` : une modification qui ne les soumet pas les laisse
            // en place, elle ne les efface pas.
            'prix_provisoire' => ['sometimes', 'boolean'],
            'prix_corrige_main' => ['sometimes', 'boolean'],

            'id' => ['sometimes', 'uuid'],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'article_id.required' => __('bar.validation.article_obligatoire'),
            'article_id.exists' => __('bar.validation.article_inexistant'),
            'categorie.in' => __('bar.validation.categorie_inconnue'),
        ];
    }
}
