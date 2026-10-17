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
use Illuminate\Validation\Rules\Unique;
use Illuminate\Validation\ValidationException;
use LogicException;
use RuntimeException;

/**
 * Les choix PAR DÉFAUT d'un gestionnaire — tous du côté prudent.
 *
 * - Niveau `C` : toute opération synchronisée est une écriture (PA-65).
 * - Modification REFUSÉE : une table doit l'accepter explicitement, en la
 *   faisant passer par son service. Oublier de la déclarer donne un rejet
 *   lisible, jamais une écriture brute. (Le catalogue entier l'accepte depuis
 *   la décision PO du 15/10/2026 — `GestionnaireReferentielAbstrait`.)
 * - Modification d'un identifiant inconnu : rejetée (`modificationSurInconnu()`
 *   rend `null`), sauf déclaration contraire de la table.
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

    public function modulesRequis(array $payload): array
    {
        return [$this->module()];
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

    /** Par défaut : le poste n'écrit localement aucune ligne dérivée. */
    public function tablesMiroirs(): array
    {
        return [];
    }

    /** Par défaut : pas un document — la création sur un identifiant existant reste rejetée. */
    public function reprendreExistant(string $entiteId, ContexteSynchronisation $contexte): ?EcritureSynchronisee
    {
        return null;
    }

    /** Par défaut : la modification d'un identifiant inconnu reste rejetée. */
    public function modificationSurInconnu(string $entiteId, array $payload, ContexteSynchronisation $contexte): ?EcritureSynchronisee
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

    /**
     * Valide une modification PARTIELLE comme l'API valide un `PUT` — décision
     * du Product Owner du 15/10/2026 : seuls les champs PRÉSENTS dans le
     * payload sont modifiés.
     *
     * Les règles de l'API sont appliquées aux seuls champs présents (un champ
     * `required` absent n'est pas un champ effacé : il garde sa valeur), sur
     * les données de l'élément COMPLÉTÉES par le payload — une règle croisée
     * (`date_fin` ≥ `date_debut`) se juge sur l'état résultant. Un champ
     * présent et interdit (`prohibited` : stock, CMP, prix d'achat, coût
     * matière…) est refusé avec la phrase de l'API, exactement comme la
     * route. Un champ inconnu des règles est ignoré, comme `validated()`.
     *
     * @param  array<string, mixed>  $payload
     * @param  array<string, mixed>  $regles  règles de modification de l'API
     * @param  class-string<FormRequest>  $requete  source des messages
     * @return array<string, mixed> les seuls champs présents, validés
     *
     * @throws DonneesSynchroniseesInvalidesException
     */
    protected function validerPartiel(Model $element, array $payload, array $regles, string $requete): array
    {
        $presentes = array_filter(
            $regles,
            static function (string $champ) use ($payload): bool {
                $racine = explode('.', $champ)[0];

                return array_key_exists($racine, $payload);
            },
            ARRAY_FILTER_USE_KEY,
        );

        if ($presentes === []) {
            return [];
        }

        $actuelles = array_intersect_key($element->getAttributes(), $regles);
        $valides = $this->valider([...$actuelles, ...$payload], $presentes, $requete);

        return array_intersect_key($valides, $payload);
    }

    /**
     * Le cas d'une modification dont la cible n'existe pas côté serveur, pour
     * un RÉFÉRENTIEL : la création s'est perdue en route (décision PO du
     * 15/10/2026). Le payload est traité comme une création s'il satisfait
     * les règles de CRÉATION (fusion sur la clé naturelle comprise) ; sinon
     * rejet, motif `sync.modification_inconnue_incomplete` et erreurs par
     * champ. Un archivage demandé (`actif` faux) est appliqué ensuite, par la
     * même règle de droits — jamais sur une cible de fusion, qui n'est pas
     * l'élément du poste.
     *
     * @param  array<string, mixed>  $payload
     */
    protected function creerDepuisModification(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $actif = array_key_exists('actif', $payload) ? $this->booleen($payload['actif']) : null;

        try {
            $ecriture = $this->creer($entiteId, $payload, $contexte);
        } catch (DonneesSynchroniseesInvalidesException $e) {
            throw new DonneesSynchroniseesInvalidesException(
                __('sync.modification_inconnue_incomplete', ['raison' => $e->getMessage()]),
                $e->erreurs,
            );
        }

        if ($ecriture->fusionneAvec === null && $actif === false) {
            $this->modifier($entiteId, ['actif' => false], $contexte);
        }

        return new EcritureSynchronisee(
            $ecriture->entiteId,
            $ecriture->fusionneAvec,
            [...$ecriture->complements, 'cree_depuis_modification' => true],
        );
    }

    /**
     * `actif` du payload, lu comme l'API lit un booléen.
     *
     * @throws RuntimeException valeur illisible
     */
    protected function booleen(mixed $valeur): bool
    {
        $booleen = is_bool($valeur) ? $valeur : filter_var($valeur, FILTER_VALIDATE_BOOLEAN, FILTER_NULL_ON_FAILURE);

        if ($booleen === null) {
            throw new RuntimeException(__('sync.archive_valeur_invalide'));
        }

        return $booleen;
    }

    /**
     * Les règles SANS leur contrainte d'unicité sur les champs nommés.
     *
     * Pourquoi (15/10/2026) : à l'écran en ligne, un libellé déjà pris est une
     * faute de saisie — la règle `unique` la refuse. Par la synchronisation,
     * c'est le cas même que la décision du Product Owner traite : l'élément
     * existe déjà côté serveur, et il faut FUSIONNER, pas rejeter. Retirer la
     * seule contrainte d'unicité (et rien d'autre) laisse toutes les autres
     * règles de l'API s'appliquer telles quelles.
     *
     * @param  array<string, mixed>  $regles
     * @return array<string, mixed>
     */
    protected function sansUnicite(array $regles, string ...$champs): array
    {
        foreach ($champs as $champ) {
            if (! isset($regles[$champ])) {
                continue;
            }

            $liste = is_string($regles[$champ]) ? explode('|', $regles[$champ]) : (array) $regles[$champ];

            $regles[$champ] = array_values(array_filter(
                $liste,
                static fn (mixed $regle): bool => ! $regle instanceof Unique
                    && ! (is_string($regle) && str_starts_with($regle, 'unique:')),
            ));
        }

        return $regles;
    }
}
