<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Bar\Http\Requests\EnregistrerBoissonRequest;
use App\Domain\Bar\Http\Requests\LierBoissonAuStockRequest;
use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Bar\Services\CarteBoissonService;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Support\ContexteSynchronisation;
use Illuminate\Database\Eloquent\Model;

/**
 * Boissons de la carte du bar créées hors connexion (M5, EF-M5-02) — lot S2,
 * décision du Product Owner du 15/10/2026. Patron commun :
 * `GestionnaireReferentielAbstrait`.
 *
 * ## Clé naturelle : le libellé normalisé
 *
 * La règle du poste (`CatalogueDao.libelleBoissonExiste`) : deux « Béninoise
 * 33 cl » mettent deux entrées au point de vente, et le barman ne peut pas
 * savoir laquelle décrémente quoi — « deux contenances = deux articles »,
 * donc un libellé, une boisson. L'article lié n'entre pas dans la clé : la
 * même boisson liée à deux articles différents par deux postes reste UNE
 * boisson, et c'est le lien du serveur qui fait foi.
 *
 * ## L'article cité est traduit, puis exigé
 *
 * `article_id` est NOT NULL au schéma (RG-05) : il passe par les
 * correspondances (article créé hors connexion et fusionné), puis par la
 * règle `exists` de l'API — un article jamais synchronisé est rejeté avec la
 * phrase de l'écran en ligne. Le poste doit donc pousser l'article AVANT la
 * boisson, dans sa file.
 *
 * ## Module M5, niveau C — celui de `POST /bar/boissons`.
 *
 * ## Modification : acceptée, dernier écrit gagnant
 *
 * Décision du Product Owner du 15/10/2026, qui REMPLACE le refus du lot S2
 * (« le serveur est maître, modification refusée » ne vaut plus).
 * Par `CarteBoissonService::modifier()` (marques de prix
 * PA-161 comprises), règles de `PUT /bar/boissons/{boisson}` sur les seuls
 * champs présents ; l'article cité est traduit par les correspondances.
 * Une boisson ne s'archive pas : demander `actif: false` est refusé.
 *
 * ## Le conditionnement part avec le lien (poste, 26/10/2026)
 *
 * À l'API, `unites_vendables_par_unite_stock` n'est pas dans
 * `EnregistrerBoissonRequest` : il relève de « Lier au stock »
 * (`LierBoissonAuStockRequest`). Le POSTE n'a pas deux routes : « Nouvelle
 * boisson » (article ET conditionnement) et « Lier au stock » / « Modifier le
 * lien » (l'un, l'autre ou les deux) arrivent par ce gestionnaire. Les ignorer
 * laissait le défaut du schéma (1) : un casier de 24 liquidé comme une
 * bouteille à l'unité, chaque vente sortant un casier ENTIER. La règle est
 * celle de `LierBoissonAuStockRequest` à la lettre (`numeric`, `gt:0`), avec
 * `sometimes` : une opération d'avant n'en porte pas, et le serveur garde
 * alors son conditionnement.
 */
final class GestionnaireCartesBoisson extends GestionnaireReferentielAbstrait
{
    protected const REFERENCES = ['article_id' => 'articles'];

    protected const REQUETE = EnregistrerBoissonRequest::class;

    protected const PARAMETRE_ROUTE = 'boisson';

    public function __construct(
        private readonly CarteBoissonService $carte,
        ResolveurCorrespondances $correspondances,
    ) {
        parent::__construct($correspondances);
    }

    public function table(): string
    {
        return 'cartes_boisson';
    }

    public function module(): string
    {
        return 'M5';
    }

    public function serviceDomaine(): string
    {
        return CarteBoissonService::class;
    }

    protected function validerCreation(array $payload): array
    {
        return $this->valider(
            $payload,
            [...$this->reglesDeLApi(EnregistrerBoissonRequest::class), ...$this->reglesDuConditionnement()],
            EnregistrerBoissonRequest::class,
        );
    }

    protected function validerModification(Model $element, array $payload): array
    {
        return $this->validerPartiel(
            $element,
            $payload,
            [...$this->reglesDeLApi(EnregistrerBoissonRequest::class, static::PARAMETRE_ROUTE, $element), ...$this->reglesDuConditionnement()],
            EnregistrerBoissonRequest::class,
        );
    }

    /**
     * @return array<string, list<mixed>>
     */
    private function reglesDuConditionnement(): array
    {
        $regles = (new LierBoissonAuStockRequest())->rules()['unites_vendables_par_unite_stock'];

        return [
            'unites_vendables_par_unite_stock' => ['sometimes', ...array_values(array_filter(
                $regles,
                static fn (mixed $regle): bool => $regle !== 'required',
            ))],
        ];
    }

    protected function equivalent(array $donnees): ?Model
    {
        return $this->premierDeCle(
            CarteBoisson::query()->orderBy('date_creation')->orderBy('id'),
            $this->cle((string) $donnees['libelle']),
            fn (CarteBoisson $b): string => $this->cle($b->libelle),
        );
    }

    protected function ecrire(string $entiteId, array $donnees, ContexteSynchronisation $contexte): void
    {
        $this->carte->creer([...$donnees, 'id' => $entiteId]);
    }

    protected function trouver(string $entiteId): Model
    {
        return CarteBoisson::query()->lockForUpdate()->findOrFail($entiteId);
    }

    protected function ecrireModification(Model $element, array $donnees, ContexteSynchronisation $contexte): void
    {
        /** @var CarteBoisson $element */
        $this->carte->modifier($element, $donnees);
    }
}
