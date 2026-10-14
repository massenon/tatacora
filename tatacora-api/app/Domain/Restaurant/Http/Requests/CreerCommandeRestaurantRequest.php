<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Http\Requests;

use App\Domain\Restaurant\Models\CommandeRestaurant;
use Illuminate\Foundation\Http\FormRequest;

/**
 * Prise de commande en salle ou en chambre — EF-M4-03.
 *
 * ## `table_ou_chambre_id` est un UUID libre, et c'est une lacune de schéma
 *
 * La colonne est déclarée « référence libre table salle OU
 * `unites_hebergement` (room-service) » et ne porte **aucune clé étrangère, ni
 * aucun discriminant de type**. Conséquences, toutes les deux réelles :
 * l'existence de la cible ne peut pas être vérifiée, et rien ne distingue une
 * table d'une chambre — donc EF-M4-03 (« par table OU par chambre ») ne peut
 * pas être restitué à l'affichage. Le format UUID est le seul contrôle
 * possible ici. Inventer une table de salle ou deviner le type d'après une
 * jointure opportuniste serait pire : le room-service serait facturé à une
 * table, ou l'inverse. La lacune est signalée au rapport, pas comblée seul.
 *
 * ## Aucun prix n'est accepté, ni rendu
 *
 * `lignes_commande_restaurant` porte `plat_id` et `quantite`, **pas de
 * `prix_unitaire`** — contrairement à `lignes_vente_bar` qui, elle, fige le
 * sien. Un total de commande calculé au prix courant serait donc faux pour
 * toute commande passée avant un changement de carte, sans que rien ne le
 * signale. La commande ne transporte donc aucun montant : le bon de cuisine
 * n'en a pas besoin, et EF-M4-07 (transfert vers la facturation) est hors
 * périmètre de ce lot pour exactement cette raison.
 *
 * ## Une quantité à zéro n'est pas une ligne
 *
 * `gt:0`, jamais `min:0` : une quantité saisie à zéro deviendrait une portion
 * transmise en cuisine et décrémentée du stock — le piège que le portage du
 * panier a nommé (`QuantiteSaisie`, PA-98).
 */
final class CreerCommandeRestaurantRequest extends FormRequest
{
    /**
     * @var list<string>
     */
    public const CHAMPS_REFUSES = [
        // `commandes_restaurant` n'est PAS au registre `TABLES_SYNCHRONISABLES`
        // du serveur : aucun rejeu, aucune deduplication. Accepter un
        // identifiant fourni par le client laisserait croire a une idempotence
        // qui n'a pas lieu — meme refus, mot pour mot, que sur une commande
        // d'achat.
        'id',
        'statut',
        'montant',
        'montant_total',
        'total',
        'prix_unitaire',
    ];

    public function authorize(): bool
    {
        return $this->user()?->can('create', CommandeRestaurant::class) ?? false;
    }

    /**
     * @return array<string, array<int, mixed>>
     */
    public function rules(): array
    {
        $regles = [
            'lignes' => ['required', 'array', 'min:1'],
            'lignes.*.plat_id' => ['required', 'uuid', 'exists:plats,id'],
            'lignes.*.quantite' => ['required', 'integer', 'gt:0', 'max:65535'],

            // Vraie clé étrangère, nullable au schéma : une commande de
            // passage n'a pas de client au référentiel.
            'client_id' => ['sometimes', 'nullable', 'uuid', 'exists:clients,id'],

            'table_ou_chambre_id' => ['sometimes', 'nullable', 'uuid'],
        ];

        foreach (self::CHAMPS_REFUSES as $champ) {
            $regles[$champ] = ['prohibited'];
        }

        return $regles;
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        $messages = [
            'lignes.required' => __('restaurant.commande_vide'),
            'lignes.min' => __('restaurant.commande_vide'),
            'lignes.*.plat_id.required' => __('restaurant.validation.plat_obligatoire'),
            'lignes.*.plat_id.exists' => __('restaurant.validation.plat_inexistant'),
            'lignes.*.quantite.required' => __('restaurant.validation.quantite_obligatoire'),
            'lignes.*.quantite.gt' => __('restaurant.validation.quantite_positive'),
            'client_id.exists' => __('restaurant.validation.client_inexistant'),
            'statut.prohibited' => __('restaurant.validation.statut_non_saisissable'),
            'id.prohibited' => __('restaurant.validation.identifiant_non_accepte'),
        ];

        foreach (['montant', 'montant_total', 'total', 'prix_unitaire'] as $champ) {
            $messages[$champ . '.prohibited'] = __('restaurant.validation.montant_sans_schema');
        }

        return $messages;
    }

    /**
     * @return list<array{plat_id: string, quantite: int}>
     */
    public function lignes(): array
    {
        $lignes = [];

        /** @var array<int, array{plat_id: string, quantite: mixed}> $brutes */
        $brutes = $this->validated()['lignes'] ?? [];

        foreach ($brutes as $brute) {
            $lignes[] = [
                'plat_id' => (string) $brute['plat_id'],
                'quantite' => (int) $brute['quantite'],
            ];
        }

        return $lignes;
    }
}
