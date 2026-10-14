<?php

declare(strict_types=1);

namespace App\Domain\Achats\Http\Requests;

use App\Domain\Achats\Models\CommandeAchat;
use Illuminate\Foundation\Http\FormRequest;

/**
 * Enregistrement d'un bon de réception — EF-M7-03, RG-10.
 *
 * ## La conformité ne se saisit PAS
 *
 * `bons_reception.conformite` est le verdict de RG-10, produit par
 * `ReceptionService::evaluerConformite()` à partir des quantités reçues et de
 * la tolérance paramétrée. L'accepter en entrée permettrait de déclarer
 * « totale » une livraison amputée de moitié, et la créance sur le fournisseur
 * serait perdue sans que rien ne le signale. Elle est donc **interdite**.
 *
 * Même raison pour `statut` : il est posé par le service selon le verdict.
 *
 * ## La tolérance non plus
 *
 * RG-10 la veut paramétrable (`parametres_systeme.tolerance_reception_pct`),
 * modifiable depuis l'écran Paramètres (PA-124). La passer dans la requête
 * ferait de chaque réception sa propre règle — c'est-à-dire qu'il n'y aurait
 * plus de règle. Non configurée, `ReceptionService` **refuse de calculer** et
 * le dit ; c'est la même discipline que le taux d'IS (PA-19) et la charge
 * patronale de risques professionnels (PA-53).
 *
 * ## Une quantité reçue est strictement positive
 *
 * Un article non livré s'omet ; il ne se déclare pas à zéro. Le service
 * ignorerait la ligne pour le mouvement de stock mais la compterait dans le
 * verdict de conformité — deux comportements pour une même saisie, ce qui
 * finit toujours par surprendre quelqu'un. `gt:0` ferme le cas, et l'absence
 * de l'article vaut déjà « rien reçu » pour RG-10.
 *
 * ## Un article ne peut pas figurer deux fois
 *
 * Le service reçoit une carte `article_id => quantité` : la seconde occurrence
 * écraserait la première, et la marchandise entrerait en stock amputée de la
 * première ligne. Refusé en amont.
 */
final class EnregistrerReceptionRequest extends FormRequest
{
    /**
     * Champs produits par RG-10, jamais soumis.
     *
     * @var list<string>
     */
    public const CHAMPS_CALCULES = [
        'conformite',
        'statut',
        'tolerance_pct',
        'ecart_pct',
    ];

    public function authorize(): bool
    {
        $commande = $this->route('commande');

        return $commande instanceof CommandeAchat
            && ($this->user()?->can('update', $commande) ?? false);
    }

    /**
     * @return array<string, array<int, mixed>>
     */
    public function rules(): array
    {
        $regles = [
            'point_stockage_id' => ['required', 'uuid', 'exists:points_stockage,id'],
            'date_reception' => ['sometimes', 'nullable', 'date'],

            'lignes' => ['required', 'array', 'min:1'],
            'lignes.*.article_id' => ['required', 'uuid', 'exists:articles,id', 'distinct'],
            'lignes.*.quantite_recue' => ['required', 'numeric', 'gt:0', 'decimal:0,2'],

            'utilisateur_id' => ['prohibited'],
            'id' => ['prohibited'],
        ];

        foreach (self::CHAMPS_CALCULES as $champ) {
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
            'point_stockage_id.exists' => __('achats.validation.point_inexistant'),
            'lignes.required' => __('achats.validation.reception_lignes_obligatoires'),
            'lignes.min' => __('achats.validation.reception_lignes_obligatoires'),
            'lignes.*.article_id.exists' => __('achats.validation.article_inexistant'),
            'lignes.*.article_id.distinct' => __('achats.validation.article_en_double'),
            'lignes.*.quantite_recue.gt' => __('achats.validation.quantite_positive'),
            'id.prohibited' => __('achats.validation.identifiant_non_accepte'),
            'utilisateur_id.prohibited' => __('achats.validation.valeur_calculee'),
        ];

        foreach (self::CHAMPS_CALCULES as $champ) {
            $messages[$champ . '.prohibited'] = __('achats.validation.valeur_calculee');
        }

        return $messages;
    }

    /**
     * Quantités reçues dans la forme attendue par `ReceptionService` :
     * `article_id => quantité`, en CHAÎNE — `bccomp` et `bcsub` n'acceptent
     * rien d'autre, et un float y perdrait les centimes.
     *
     * @return array<string, string>
     */
    public function quantitesRecues(): array
    {
        /** @var array<string, mixed> $valide */
        $valide = $this->validated();

        /** @var list<array<string, mixed>> $lignes */
        $lignes = is_array($valide['lignes']) ? array_values($valide['lignes']) : [];

        $quantites = [];

        foreach ($lignes as $ligne) {
            $quantites[(string) $ligne['article_id']] = (string) $ligne['quantite_recue'];
        }

        return $quantites;
    }
}
