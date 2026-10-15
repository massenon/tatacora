<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Pwa\Support\ReglesDeLApi;
use App\Shared\Sync\Contracts\GestionnaireSynchronisation;
use App\Shared\Sync\Exceptions\DonneesSynchroniseesInvalidesException;
use App\Shared\Sync\Services\ClassificationConflitService;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\ValidationException;
use LogicException;

/**
 * Les choix PAR DÉFAUT d'un gestionnaire — tous du côté prudent.
 *
 * - Niveau `C` : toute opération synchronisée est une écriture (PA-65).
 * - Modification REFUSÉE : une table doit l'accepter explicitement, en la
 *   faisant passer par son service. Oublier de la déclarer donne un rejet
 *   lisible, jamais une écriture brute.
 * - `estFinanciere()` lue dans `ClassificationConflitService::TABLES_FINANCIERES`,
 *   jamais redéclarée : la liste est une donnée de sécurité à auteur unique,
 *   deux listes finiraient par diverger (RG-17).
 */
abstract class GestionnaireAbstrait implements GestionnaireSynchronisation
{
    public function niveauRequis(): string
    {
        return 'C';
    }

    public function estFinanciere(): bool
    {
        return in_array($this->table(), ClassificationConflitService::TABLES_FINANCIERES, true);
    }

    public function accepteModification(): bool
    {
        return false;
    }

    public function champDateDocument(): ?string
    {
        return null;
    }

    public function modifier(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        // Le moteur ne l'appelle jamais quand `accepteModification()` est faux ;
        // arriver ici est un bogue de programmation, qui doit remonter en 500
        // (rejeu ultérieur), pas en rejet définitif.
        throw new LogicException(__('sync.interne.modification_non_declaree', ['table' => $this->table()]));
    }

    /**
     * Les règles de la route d'API équivalente, telles quelles — jamais une
     * seconde liste écrite ici, qui resterait verte le jour où l'API durcirait
     * une contrainte (même raisonnement que `ReglesDeLApi` pour la PWA).
     *
     * @param  class-string<FormRequest>  $requete
     * @return array<string, mixed>
     */
    protected function reglesDeLApi(string $requete, ?string $parametreDeRoute = null, ?Model $modele = null): array
    {
        $champs = array_keys((new $requete())->rules());
        $identite = array_combine($champs, $champs);

        return $modele === null || $parametreDeRoute === null
            ? ReglesDeLApi::pourCreation($requete, $identite)
            : ReglesDeLApi::pourModification($requete, $parametreDeRoute, $modele, $identite);
    }

    /**
     * Valide comme l'API — mêmes règles, mêmes PHRASES — et rend les seules
     * données validées : un champ inconnu est ignoré exactement comme
     * `FormRequest::validated()` l'ignore sur la route.
     *
     * @param  array<string, mixed>  $donnees
     * @param  array<string, mixed>  $regles
     * @param  class-string<FormRequest>  $requete source des messages
     * @return array<string, mixed>
     *
     * @throws DonneesSynchroniseesInvalidesException
     */
    protected function valider(array $donnees, array $regles, string $requete): array
    {
        $requeteInstance = new $requete();
        $messages = method_exists($requeteInstance, 'messages') ? $requeteInstance->messages() : [];

        try {
            return Validator::make($donnees, $regles, $messages)->validate();
        } catch (ValidationException $e) {
            throw DonneesSynchroniseesInvalidesException::depuis($e);
        }
    }
}
