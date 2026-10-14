<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Http\Requests;

use App\Domain\Stocks\Models\MouvementStock;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Valide l'enregistrement d'un mouvement de stock — EF-M6-02, EF-M6-06.
 *
 * @see RG-06 Blocage au-delà du disponible, avec échappatoire contrôlée
 * @see RG-15 Traçabilité intégrale
 *
 * ## Aucune valeur calculée n'est acceptée, et il ne faut jamais en ajouter
 *
 * `stock`, `stock_disponible`, `quantite_stock`, `cout_moyen_pondere` et
 * `valeur_stock` sont explicitement **interdits** plutôt qu'ignorés. La
 * différence compte : un champ ignoré laisse le client croire qu'il a été pris
 * en compte, et l'écart ne se voit qu'à l'inventaire suivant. Un champ refusé
 * se voit tout de suite (PA-24).
 *
 * ## `inventaire` n'est PAS un type saisissable
 *
 * Le registre est fermé à `entree`, `sortie` et `perte`. Un écart d'inventaire
 * naît d'un comptage clôturé (`InventaireService::cloturer()`), qui fige la
 * quantité théorique à l'ouverture et la compare au constaté. L'ouvrir à la
 * saisie libre permettrait de réécrire n'importe quel solde sans qu'aucun
 * comptage n'ait eu lieu — c'est-à-dire de rendre l'inventaire inopposable.
 *
 * ## `id` est refusé, et c'est un manque assumé
 *
 * La convention offline-first du projet veut un UUID fourni par le client, qui
 * sert de clé de déduplication. `MouvementStockService` ne l'accepte pas, et
 * `mouvements_stock` n'est pas au registre `TABLES_SYNCHRONISABLES` : aucun
 * chemin de rejeu n'existe. Accepter l'identifiant sans l'honorer laisserait
 * croire à une idempotence qui n'existe pas — le défaut nommé en PA-59/60/61.
 * Le refuser dit la vérité : cette écriture exige le réseau et n'est pas
 * rejouable. L'arbitrage appartient à l'Architecte.
 */
final class EnregistrerMouvementRequest extends FormRequest
{
    /** Registre FERMÉ des types saisissables — `inventaire` en est exclu. */
    public const TYPES_SAISISSABLES = ['entree', 'sortie', 'perte'];

    /**
     * Champs calculés que le client pourrait être tenté de soumettre. Aucun
     * n'est stocké : ils se déduisent tous de `mouvements_stock`.
     *
     * @var list<string>
     */
    public const CHAMPS_CALCULES = [
        'stock',
        'stock_disponible',
        'quantite_stock',
        'cout_moyen_pondere',
        'valeur_stock',
    ];

    public function authorize(): bool
    {
        return $this->user()?->can('create', MouvementStock::class) ?? false;
    }

    /**
     * @return array<string, array<int, mixed>>
     */
    public function rules(): array
    {
        $regles = [
            // Vraies clés étrangères, jamais du texte libre : un mouvement
            // orphelin serait rejeté par la base avec un message SQL illisible.
            'article_id' => ['required', 'uuid', 'exists:articles,id'],
            'point_id' => ['required', 'uuid', 'exists:points_stockage,id'],
            'type_mouvement' => ['required', Rule::in(self::TYPES_SAISISSABLES)],

            // `gt:0` et non `min:0` : une quantité saisie à zéro n'est pas un
            // mouvement, c'est une saisie inachevée. L'enregistrer produirait
            // une ligne d'historique qui ne dit rien et fausserait le compteur
            // de mouvements.
            'quantite' => ['required', 'numeric', 'gt:0', 'decimal:0,2'],

            // Obligatoire : EF-M6-06 exige « qui, quoi, quand, pourquoi ».
            // Un mouvement sans motif rend l'historique inopposable, et la
            // colonne est NOT NULL au schéma de toute façon.
            'motif' => ['required', 'string', 'max:255'],

            // Réservé aux entrées VALORISÉES (réception fournisseur). Sur une
            // sortie il n'aurait aucun effet : les sorties ne modifient pas le
            // coût moyen pondéré, c'est le principe même de la méthode. Le
            // laisser passer laisserait croire l'inverse.
            'cout_unitaire' => [
                'sometimes',
                'nullable',
                'prohibited_unless:type_mouvement,entree',
                'numeric',
                'min:0',
                'decimal:0,4',
            ],

            // RG-06 : le forçage de rupture est une décision explicite, jamais
            // un défaut. Il n'a de sens que sur un mouvement sortant — un
            // ajout de stock ne peut pas être en rupture.
            //
            // La règle ne se déclenche que sur une valeur VRAIE : un client qui
            // envoie systématiquement `false` dans son formulaire ne décide
            // rien, et le refuser transformerait un no-op en erreur.
            'validation_rupture' => [
                'sometimes',
                'boolean',
                Rule::prohibitedIf(
                    fn (): bool => $this->input('type_mouvement') === 'entree'
                        && $this->boolean('validation_rupture'),
                ),
            ],

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
            'type_mouvement.in' => __('stocks.validation.type_inconnu'),
            'quantite.gt' => __('stocks.validation.quantite_positive'),
            'motif.required' => __('stocks.validation.motif_obligatoire'),
            'article_id.exists' => __('stocks.validation.article_inexistant'),
            'point_id.exists' => __('stocks.validation.point_inexistant'),
            'cout_unitaire.prohibited_unless' => __('stocks.validation.cout_reserve_entree'),
            'validation_rupture.prohibited' => __('stocks.validation.rupture_sur_sortie'),
            'id.prohibited' => __('stocks.validation.identifiant_non_accepte'),
        ];

        foreach (self::CHAMPS_CALCULES as $champ) {
            $messages[$champ . '.prohibited'] = __('stocks.validation.valeur_calculee');
        }

        return $messages;
    }
}
