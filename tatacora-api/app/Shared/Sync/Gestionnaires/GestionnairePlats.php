<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Restaurant\Http\Requests\EnregistrerPlatRequest;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Services\CartePlatMenuService;
use App\Shared\Sync\Exceptions\DonneesSynchroniseesInvalidesException;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Support\ContexteSynchronisation;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\ValidationException;

/**
 * Plats créés hors connexion (M4, EF-M4-01) — lot S2, décision du Product
 * Owner du 15/10/2026. Patron commun : `GestionnaireReferentielAbstrait`.
 *
 * ## Un plat cite son menu et sa fiche — tous deux traduits, puis exigés
 *
 * `menu_id` et `recette_id` sont NOT NULL au schéma. Ils passent par les
 * correspondances (menu ou fiche créés sur ce poste et fusionnés), puis par
 * les règles `exists` de l'API : le poste pousse donc menu et fiche AVANT le
 * plat. Les gestionnaires `menus` et `recettes` existent pour cette raison.
 *
 * ## Clé naturelle : le libellé normalisé DANS son menu
 *
 * « Poulet DG » au menu local et « Poulet DG » au menu de fête sont deux
 * lignes de carte, chacune à son prix. Le menu est comparé APRÈS traduction :
 * deux postes qui ont créé chacun le même menu puis le même plat fusionnent
 * sur le même plat serveur.
 *
 * ## Validation : `EnregistrerPlatRequest`
 *
 * Ingrédients en texte libre, catégorie, disponibilité, coût matière et marge
 * sont INTERDITS comme à l'API (PA-23, PA-24).
 *
 * ## Le lien direct au stock (« Lier au stock », poste v36)
 *
 * `article_id` (traduit par les correspondances) et
 * `unites_vendables_par_unite_stock` partent ensemble, à la création comme en
 * modification (`null` des deux = délier). Écrits par `CartePlatMenuService`.
 *
 * ## Module M4, niveau C — celui de `POST /restaurant/plats`.
 *
 * ## Modification : acceptée, dernier écrit gagnant
 *
 * Décision du Product Owner du 15/10/2026, qui REMPLACE le refus du lot S2
 * (« le serveur est maître, modification refusée » ne vaut plus).
 * Par `CartePlatMenuService::modifierPlat()` (cohérence du
 * lien direct, marques de prix), règles de `PUT /restaurant/plats/{plat}`
 * sur les seuls champs présents ; menu et fiche cités traduits par les
 * correspondances. Coût matière, marge, stock restent INTERDITS. Un plat ne
 * s'archive pas.
 */
final class GestionnairePlats extends GestionnaireReferentielAbstrait
{
    protected const REFERENCES = ['menu_id' => 'menus', 'recette_id' => 'recettes', 'article_id' => 'articles'];

    /**
     * Le lien DIRECT au stock (« Lier au stock », poste v36) : les DEUX champs
     * vont ensemble. Ils ne sont pas dans `EnregistrerPlatRequest` (l'API les
     * pose par `CartePlatMenuService::lierAuStock`), donc `validated()` les
     * jetterait en silence — le poste croirait avoir lié un plat qui ne l'est
     * pas. Ils sont validés ICI, puis écrits par le service (qui refuse un
     * article sans conditionnement, et l'inverse).
     */
    private const CHAMPS_LIEN = ['article_id', 'unites_vendables_par_unite_stock'];

    protected const REQUETE = EnregistrerPlatRequest::class;

    protected const PARAMETRE_ROUTE = 'plat';

    public function __construct(
        private readonly CartePlatMenuService $carte,
        ResolveurCorrespondances $correspondances,
    ) {
        parent::__construct($correspondances);
    }

    public function table(): string
    {
        return 'plats';
    }

    public function module(): string
    {
        return 'M4';
    }

    public function serviceDomaine(): string
    {
        return CartePlatMenuService::class;
    }

    protected function validerCreation(array $payload): array
    {
        [$lien, $payload] = $this->separerLien($payload);

        $donnees = $this->valider(
            $payload,
            $this->reglesDeLApi(EnregistrerPlatRequest::class),
            EnregistrerPlatRequest::class,
        );

        return [...$donnees, ...$this->validerLien($lien)];
    }

    protected function validerModification(Model $element, array $payload): array
    {
        [$lien, $payload] = $this->separerLien($payload);

        return [...parent::validerModification($element, $payload), ...$this->validerLien($lien)];
    }

    /**
     * @param  array<string, mixed>  $payload
     * @return array{0: array<string, mixed>, 1: array<string, mixed>}
     */
    private function separerLien(array $payload): array
    {
        $lien = array_intersect_key($payload, array_flip(self::CHAMPS_LIEN));

        return [$lien, array_diff_key($payload, $lien)];
    }

    /**
     * Seuls les champs PRÉSENTS sont validés ; `null` est accepté (retrait du
     * lien : les deux colonnes partent ensemble). La cohérence article /
     * conditionnement est celle du service, jugée sur l'état résultant.
     *
     * @param  array<string, mixed>  $lien
     * @return array<string, mixed>
     */
    private function validerLien(array $lien): array
    {
        if ($lien === []) {
            return [];
        }

        $regles = [
            'article_id' => ['nullable', 'uuid', 'exists:articles,id'],
            'unites_vendables_par_unite_stock' => ['nullable', 'numeric', 'gt:0', 'max:99999999999'],
        ];

        $messages = [
            'article_id.exists' => __('carte.article_stock_inconnu', ['article' => (string) ($lien['article_id'] ?? '')]),
        ];

        try {
            return Validator::make($lien, array_intersect_key($regles, $lien), $messages)->validate();
        } catch (ValidationException $e) {
            throw DonneesSynchroniseesInvalidesException::depuis($e);
        }
    }

    protected function equivalent(array $donnees): ?Model
    {
        return $this->premierDeCle(
            Plat::query()->where('menu_id', $donnees['menu_id'])->orderBy('date_creation')->orderBy('id'),
            $this->cle((string) $donnees['libelle']),
            fn (Plat $p): string => $this->cle($p->libelle),
        );
    }

    protected function ecrire(string $entiteId, array $donnees, ContexteSynchronisation $contexte): void
    {
        $this->carte->creerPlat([...$donnees, 'id' => $entiteId]);
    }

    protected function trouver(string $entiteId): Model
    {
        return Plat::query()->lockForUpdate()->findOrFail($entiteId);
    }

    protected function ecrireModification(Model $element, array $donnees, ContexteSynchronisation $contexte): void
    {
        /** @var Plat $element */
        $this->carte->modifierPlat($element, $donnees);
    }
}
