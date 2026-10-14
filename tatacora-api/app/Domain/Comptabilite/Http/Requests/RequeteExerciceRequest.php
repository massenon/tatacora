<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Requests;

use App\Domain\Comptabilite\Models\EcritureComptable;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Socle de tout etat de M10 : un exercice, un statut.
 *
 * ## `exercice_id` est OBLIGATOIRE, jamais defaut
 *
 * `MODULE_COMPTABILITE_COMPLET.md` §1 : « Tout ecran de M10 filtre
 * systematiquement par `exercice_id` — jamais un etat "toutes annees
 * confondues" par defaut, qui n'aurait pas de sens comptable. »
 *
 * Il aurait ete tentant de retomber sur l'exercice `ouvert` en l'absence de
 * parametre. Ce serait un defaut : l'ecran afficherait un exercice que
 * l'utilisateur n'a pas choisi, et le jour d'une bascule d'exercice, deux
 * postes ouverts sur la meme page rendraient deux annees differentes sans que
 * rien ne le dise. Le client choisit, via
 * `GET /comptabilite/exercices` — d'ou l'existence de cette route.
 *
 * ## `statut` est un registre FERME, et son defaut est celui du document
 *
 * Ni les extraits de `MODULE_COMPTABILITE_COMPLET.md` §2 et §4, ni le maitre, ne
 * filtrent sur le statut : le Journal General est defini comme « **toutes** les
 * ecritures », et la requete de Balance du document ne porte aucune clause sur
 * `statut`. Le defaut est donc `toutes`, ce que la documentation ecrit — pas ce
 * qu'on aurait suppose.
 *
 * ⚠ **Cela contredit `EcritureComptableService::soldeCompte()`**, qui filtre sur
 * `validee` en le motivant (« un brouillon n'est pas opposable »). La
 * contradiction est reelle, elle n'est PAS tranchee ici, et elle est posee en
 * question au Comptable dans le rapport de ce lot. En attendant, l'API ne
 * choisit pas en silence : le filtre est explicite, et
 * `repartition_statuts` compte toujours ce qui a ete laisse de cote.
 */
abstract class RequeteExerciceRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /**
     * @return array<string, array<int, mixed>>
     */
    public function rules(): array
    {
        return array_merge([
            'exercice_id' => ['required', 'uuid', 'exists:exercices_comptables,id'],
            'statut' => ['sometimes', 'nullable', Rule::in(EcritureComptable::FILTRES_STATUT)],
        ], $this->reglesSupplementaires());
    }

    /**
     * @return array<string, array<int, mixed>>
     */
    protected function reglesSupplementaires(): array
    {
        return [];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return array_merge([
            'exercice_id.required' => __('comptabilite.validation.exercice_requis'),
            'exercice_id.exists' => __('comptabilite.validation.exercice_inexistant'),
            'statut.in' => __('comptabilite.validation.statut_inconnu', [
                'valeurs' => implode(', ', EcritureComptable::FILTRES_STATUT),
            ]),
        ], $this->messagesSupplementaires());
    }

    /**
     * @return array<string, string>
     */
    protected function messagesSupplementaires(): array
    {
        return [];
    }

    public function exerciceId(): string
    {
        return (string) $this->input('exercice_id');
    }

    /**
     * La valeur de filtre demandee, telle qu'elle sera renvoyee dans
     * `filtres_appliques` : un etat DIT son filtre (PA-119).
     */
    public function filtreStatut(): string
    {
        $valeur = $this->input('statut');

        return is_string($valeur) && $valeur !== ''
            ? $valeur
            : EcritureComptable::FILTRE_STATUT_TOUTES;
    }

    /**
     * Les statuts reellement inclus dans la requete.
     *
     * `toutes` se DEPLIE en la liste des statuts du registre, plutot que de
     * devenir une absence de clause `whereIn` : le jour ou un troisieme statut
     * apparaitra a l'`enum`, il faudra decider s'il entre dans les etats —
     * l'absence de clause l'y aurait fait entrer sans que personne ne le
     * decide.
     *
     * @return list<string>
     */
    public function statuts(): array
    {
        $filtre = $this->filtreStatut();

        return $filtre === EcritureComptable::FILTRE_STATUT_TOUTES
            ? EcritureComptable::STATUTS
            : [$filtre];
    }
}
