<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Http\Requests;

use App\Domain\Restaurant\Models\Menu;
use App\Domain\Restaurant\Services\CarteRestaurantService;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Filtres de l'écran « Carte du restaurant » — EF-M4-01.
 *
 * Reprend les trois contrôles du maître (`m4-restaurant-carte.html` l.63-79) :
 * recherche libre, sélecteur de catégorie, sélecteur d'état.
 *
 * ## UN état du maître reste REFUSÉ explicitement
 *
 * « Retirés du jour » (`indisponible`) n'a aucune colonne au schéma. Trois
 * comportements étaient possibles — l'accepter et l'ignorer, l'accepter et
 * rendre une liste vide, le refuser en le disant. Les deux premiers sont
 * exactement PA-119 : un filtre appliqué qui n'en est pas un rend la carte
 * ENTIÈRE sous un intitulé qui promet le contraire, et le serveur retirerait
 * de la vente un plat qui n'a jamais été retiré — ou l'inverse. Le refus est
 * donc le livrable, avec sa raison dans le message.
 *
 * ⚠ « Prix provisoire » (`provisoire`) était refusé **au même motif, et ce
 * motif est faux depuis la migration `2026_09_02_200000`** : `plats` porte
 * `prix_provisoire`. Il est ACCEPTÉ depuis le 02/09/2026 et filtre sur la
 * vraie colonne. Un motif de refus périmé transforme une décision en oubli
 * (PA-144) — quatrième occurrence de cette phrase dans le dépôt.
 */
final class FiltrerCarteRequest extends FormRequest
{
    /**
     * Le contrôle d'accès en lecture est porté par `module:M4,L` sur la route.
     * Le redoubler ici renverrait 403 sur un chemin déjà fermé.
     */
    public function authorize(): bool
    {
        return true;
    }

    /**
     * @return array<string, array<int, mixed>>
     */
    public function rules(): array
    {
        return [
            'recherche' => ['sometimes', 'nullable', 'string', 'max:255'],
            'categorie' => ['sometimes', 'nullable', Rule::in(Menu::TYPES)],
            'etat' => ['sometimes', 'nullable', Rule::in(CarteRestaurantService::ETATS)],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'categorie.in' => __('restaurant.validation.categorie_inconnue'),
            'etat.in' => $this->messageEtat(),
        ];
    }

    /**
     * Le message DIT lequel des deux cas on refuse. « Valeur invalide » sur
     * `indisponible` enverrait chercher une faute de frappe pendant que la
     * cause est l'absence de colonne.
     */
    private function messageEtat(): string
    {
        $etat = $this->input('etat');

        if (is_string($etat) && in_array($etat, CarteRestaurantService::ETATS_SANS_SCHEMA, true)) {
            return __('restaurant.validation.etat_sans_schema');
        }

        return __('restaurant.validation.etat_inconnu');
    }

    public function filtre(string $nom): ?string
    {
        $valeur = $this->input($nom);

        return is_string($valeur) && $valeur !== '' ? $valeur : null;
    }
}
