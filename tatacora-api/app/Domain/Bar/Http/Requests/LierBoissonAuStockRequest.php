<?php

declare(strict_types=1);

namespace App\Domain\Bar\Http\Requests;

use App\Domain\Bar\Models\CarteBoisson;
use Illuminate\Foundation\Http\FormRequest;

/**
 * Valide « Lier au stock » d'une boisson — l'article de stock ET son
 * conditionnement, ensemble (M5).
 *
 * ## Pourquoi une requête distincte d'`EnregistrerBoissonRequest`
 *
 * Celle-ci n'accepte pas `unites_vendables_par_unite_stock` : un client de
 * l'API pouvait changer l'article lié par `PUT /bar/boissons/{id}`, mais pas
 * dire combien d'unités vendables tient une unité de stock. Le lien aurait
 * changé et le conditionnement serait resté celui de l'ancien article — un
 * casier de 24 relié à une bouteille à l'unité. C'est le défaut exact que la
 * PWA a fermé (`CarteBar`, point 1 de son en-tête : « le taux de conversion
 * était saisi, prévisualisé, puis JETÉ »). Les deux valeurs ne se séparent
 * donc pas, et vont à `CarteBoissonService::lierAuStock()` — le chemin de la
 * PWA, pas une seconde écriture.
 *
 * Les règles sont celles d'`EcranDeCarte::enregistrerLienAuStock()`, à la
 * lettre : deux canaux qui valideraient différemment finiraient par accepter
 * au navigateur ce que l'API refuse, ou l'inverse.
 *
 * @see EF-M5-02 Carte des boissons
 * @see RG-05 Sortie de stock automatique — le conditionnement est consommé
 *      par `VenteBarService` et `VenteService`
 */
final class LierBoissonAuStockRequest extends FormRequest
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
        return [
            'article_id' => ['required', 'uuid', 'exists:articles,id'],
            // `gt:0` et non `min:0` : la décrémentation vaut
            // `quantité vendue / conditionnement` — zéro la rendrait impossible.
            'unites_vendables_par_unite_stock' => ['required', 'numeric', 'gt:0'],
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
        ];
    }
}
