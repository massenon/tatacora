<?php

declare(strict_types=1);

namespace App\Domain\Achats\Http\Requests;

use App\Domain\Achats\Models\Fournisseur;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Création et modification d'un fournisseur — EF-M7-01.
 *
 * ## `categorie` et `conditions_paiement` restent des chaînes libres, et c'est
 * une question ouverte, pas un oubli
 *
 * Le prototype les rend en listes fermées (« Denrées alimentaires »,
 * « Comptant », « 30 jours »…), le schéma les déclare `string` nullable. Fermer
 * le registre ici rendrait **inmodifiable** tout fournisseur déjà enregistré
 * hors de ces listes : à la première correction de son numéro de téléphone, la
 * validation refuserait sa catégorie historique, et l'utilisateur n'aurait
 * aucun moyen de comprendre pourquoi. La liste du prototype n'a par ailleurs
 * pas été arbitrée pour le Bénin — elle ne connaît ni prestataire de service ni
 * transporteur. L'arbitrage appartient au Product Owner ; il est signalé, pas
 * tranché ici.
 *
 * `evaluation`, à l'inverse, EST un registre fermé : la colonne est un `enum`
 * MySQL, et une valeur hors liste serait rejetée par la base avec un message
 * SQL illisible plutôt que par une erreur de validation lisible.
 *
 * ## Aucun champ calculé
 *
 * Le prototype affiche un montant commandé et un encours par fournisseur.
 * Aucun des deux ne se saisit : le premier se somme depuis les lignes de
 * commande, le second n'a **aucune table** (voir `AchatController`). Les
 * refuser explicitement plutôt que les ignorer est la leçon de PA-24 : un
 * champ ignoré laisse le client croire qu'il a compté.
 */
final class EnregistrerFournisseurRequest extends FormRequest
{
    /**
     * Champs que le référentiel ne stocke pas parce qu'il les calcule — ou
     * parce qu'aucune table ne les porte.
     *
     * @var list<string>
     */
    public const CHAMPS_CALCULES = [
        'montant_commande',
        'montant_regle',
        'encours',
        'total_du',
        'nombre_commandes',
    ];

    public function authorize(): bool
    {
        $fournisseur = $this->route('fournisseur');

        return $fournisseur instanceof Fournisseur
            ? ($this->user()?->can('update', $fournisseur) ?? false)
            : ($this->user()?->can('create', Fournisseur::class) ?? false);
    }

    /**
     * @return array<string, array<int, mixed>>
     */
    public function rules(): array
    {
        $modification = $this->route('fournisseur') instanceof Fournisseur;

        $regles = [
            'raison_sociale' => ['required', 'string', 'max:255'],
            'contact' => ['sometimes', 'nullable', 'string', 'max:255'],
            'categorie' => ['sometimes', 'nullable', 'string', 'max:255'],
            'conditions_paiement' => ['sometimes', 'nullable', 'string', 'max:255'],
            'evaluation' => ['sometimes', 'nullable', Rule::in(Fournisseur::EVALUATIONS)],

            // UUID fourni par le client à la création — convention offline-first
            // du projet. `unique` et non un écrasement silencieux : un second
            // POST sur le même identifiant est une anomalie qui doit se voir.
            'id' => $modification
                ? ['prohibited']
                : ['sometimes', 'uuid', Rule::unique('fournisseurs', 'id')],
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
            'raison_sociale.required' => __('achats.validation.raison_sociale_obligatoire'),
            'evaluation.in' => __('achats.validation.evaluation_inconnue'),
        ];

        foreach (self::CHAMPS_CALCULES as $champ) {
            $messages[$champ . '.prohibited'] = __('achats.validation.valeur_calculee');
        }

        return $messages;
    }
}
