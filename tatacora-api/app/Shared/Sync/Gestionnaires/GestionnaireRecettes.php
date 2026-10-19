<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Restaurant\Http\Requests\EnregistrerCompositionRequest;
use App\Domain\Restaurant\Http\Requests\EnregistrerRecetteRequest;
use App\Domain\Restaurant\Models\Recette;
use App\Domain\Restaurant\Services\CompositionRecetteService;
use App\Domain\Restaurant\Services\ReferentielRecetteService;
use App\Pwa\Support\ReglesDeLApi;
use App\Shared\Sync\Exceptions\DonneesSynchroniseesInvalidesException;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Support\ContexteSynchronisation;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\ValidationException;

/**
 * Fiches techniques créées hors connexion (M4, EF-M4-02) — lot S2, décision
 * du Product Owner du 15/10/2026. Patron commun :
 * `GestionnaireReferentielAbstrait`.
 *
 * Un plat exige sa fiche (`plats.recette_id` NOT NULL). Le poste crée la
 * fiche ET sa composition d'un même geste (`RestaurantDao.enregistrerRecette`) :
 * le payload porte donc l'en-tête (`libelle`) et, facultativement, les
 * `lignes` (`article_id`, `quantite_unitaire` en unités décimales — le poste
 * convertit ses millièmes).
 *
 * ## Validation : deux requêtes de l'API, aucune troisième liste
 *
 * L'en-tête par `EnregistrerRecetteRequest` (coût matière INTERDIT : il se
 * calcule), la composition par `EnregistrerCompositionRequest` — règles,
 * phrases ET contrôle des ingrédients en double (`withValidator`), les mêmes
 * que `PUT /restaurant/recettes/{recette}/composition`. Chaque article cité
 * est d'abord traduit par les correspondances.
 *
 * ## Clé naturelle : le libellé normalisé
 *
 * Le libellé est la seule donnée obligatoire de la fiche. En cas de fusion,
 * la composition reçue est IGNORÉE (validée, mais jamais écrite) : le
 * serveur est maître, et deux grammages de la même fiche n'ont pas à être
 * fondus — celui du serveur décrémente le stock, le poste le reçoit au
 * prochain téléchargement.
 *
 * ## Création : par `ReferentielRecetteService`, puis `CompositionRecetteService`
 *
 * La composition passe par `remplacerComposition()`, seul auteur de
 * `ingredients_recette` et du coût matière (`recalculer()`).
 *
 * ## Module M4, niveau C — celui de `POST /restaurant/recettes`.
 *
 * ## Modification : acceptée, dernier écrit gagnant
 *
 * Décision du Product Owner du 15/10/2026, qui REMPLACE le refus du lot S2
 * (« le serveur est maître, modification refusée » ne vaut plus). L'en-tête
 * par `ReferentielRecetteService::modifier()` (règles de modification
 * d'`EnregistrerRecetteRequest`, coût matière INTERDIT) ; la composition,
 * si `lignes` est présent, REMPLACÉE en entier par
 * `CompositionRecetteService::remplacerComposition()` — les mêmes règles que
 * `PUT /restaurant/recettes/{recette}/composition`, articles traduits par les
 * correspondances. Une composition reçue d'un poste plus ancien que la
 * dernière appliquée perd l'arbitrage (horodatage de saisie). Une fiche ne
 * s'archive pas.
 */
final class GestionnaireRecettes extends GestionnaireReferentielAbstrait
{
    protected const REQUETE = EnregistrerRecetteRequest::class;

    protected const PARAMETRE_ROUTE = 'recette';

    public function __construct(
        private readonly ReferentielRecetteService $referentiel,
        private readonly CompositionRecetteService $compositions,
        ResolveurCorrespondances $correspondances,
    ) {
        parent::__construct($correspondances);
    }

    public function table(): string
    {
        return 'recettes';
    }

    public function module(): string
    {
        return 'M4';
    }

    public function serviceDomaine(): string
    {
        return ReferentielRecetteService::class;
    }

    protected function validerCreation(array $payload): array
    {
        $lignes = $payload['lignes'] ?? null;
        unset($payload['lignes']);

        $donnees = $this->valider(
            $payload,
            $this->reglesDeLApi(EnregistrerRecetteRequest::class),
            EnregistrerRecetteRequest::class,
        );

        if ($lignes !== null) {
            $donnees['lignes'] = $this->validerComposition($lignes);
        }

        return $donnees;
    }

    protected function equivalent(array $donnees): ?Model
    {
        return $this->premierDeCle(
            Recette::query()->orderBy('date_creation')->orderBy('id'),
            $this->cle((string) $donnees['libelle']),
            fn (Recette $r): string => $this->cle($r->libelle),
        );
    }

    protected function ecrire(string $entiteId, array $donnees, ContexteSynchronisation $contexte): void
    {
        $lignes = $donnees['lignes'] ?? null;
        unset($donnees['lignes']);

        $recette = $this->referentiel->creer([...$donnees, 'id' => $entiteId]);

        if ($lignes !== null) {
            $this->compositions->remplacerComposition($recette, $lignes);
        }
    }

    protected function trouver(string $entiteId): Model
    {
        return Recette::query()->lockForUpdate()->findOrFail($entiteId);
    }

    protected function validerModification(Model $element, array $payload): array
    {
        $avecLignes = array_key_exists('lignes', $payload);
        $lignes = $payload['lignes'] ?? null;
        unset($payload['lignes']);

        $donnees = $this->validerPartiel(
            $element,
            $payload,
            $this->reglesDeLApi(EnregistrerRecetteRequest::class, 'recette', $element),
            EnregistrerRecetteRequest::class,
        );

        if ($avecLignes) {
            $donnees['lignes'] = $this->validerComposition($lignes);
        }

        return $donnees;
    }

    protected function ecrireModification(Model $element, array $donnees, ContexteSynchronisation $contexte): void
    {
        /** @var Recette $element */
        $lignes = $donnees['lignes'] ?? null;
        unset($donnees['lignes']);

        if ($donnees !== []) {
            $this->referentiel->modifier($element, $donnees);
        }

        if ($lignes !== null) {
            $this->compositions->remplacerComposition($element, $lignes);
        }
    }

    /**
     * @return list<array{article_id: string, quantite_unitaire: string}>
     *
     * @throws DonneesSynchroniseesInvalidesException
     */
    private function validerComposition(mixed $lignes): array
    {
        if (is_array($lignes)) {
            foreach ($lignes as $rang => $ligne) {
                if (is_array($ligne) && is_string($ligne['article_id'] ?? null) && $ligne['article_id'] !== '') {
                    $lignes[$rang]['article_id'] = $this->correspondances->resoudre('articles', $ligne['article_id']);
                }
            }
        }

        $regles = ReglesDeLApi::pourCreation(EnregistrerCompositionRequest::class, [
            'lignes' => 'lignes',
            'lignes.*.article_id' => 'lignes.*.article_id',
            'lignes.*.quantite_unitaire' => 'lignes.*.quantite_unitaire',
        ]);

        // L'instance porte les lignes : son `withValidator()` (ingrédient en
        // double) les lit par `input()`, comme sur la route.
        $requete = EnregistrerCompositionRequest::create('/', 'PUT', ['lignes' => $lignes]);
        $validateur = Validator::make(['lignes' => $lignes], $regles, $requete->messages());
        $requete->withValidator($validateur);

        try {
            $valides = $validateur->validate();
        } catch (ValidationException $e) {
            throw DonneesSynchroniseesInvalidesException::depuis($e);
        }

        return array_values(array_map(
            static fn (array $ligne): array => [
                'article_id' => (string) $ligne['article_id'],
                'quantite_unitaire' => (string) $ligne['quantite_unitaire'],
            ],
            $valides['lignes'],
        ));
    }
}
