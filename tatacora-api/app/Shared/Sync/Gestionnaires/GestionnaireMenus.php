<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Restaurant\Http\Requests\EnregistrerMenuRequest;
use App\Domain\Restaurant\Models\Menu;
use App\Domain\Restaurant\Services\CartePlatMenuService;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Support\ContexteSynchronisation;
use Illuminate\Database\Eloquent\Model;

/**
 * Menus créés hors connexion (M4, EF-M4-01/06) — lot S2, décision du Product
 * Owner du 15/10/2026. Patron commun : `GestionnaireReferentielAbstrait`.
 *
 * Un plat exige son menu (`plats.menu_id` NOT NULL) : sans ce gestionnaire,
 * un plat créé sur un poste dans un menu créé sur ce même poste ne pourrait
 * jamais remonter.
 *
 * ## Clé naturelle : libellé normalisé ET type
 *
 * La catégorie d'un plat EST le type de son menu (`EnregistrerPlatRequest`
 * refuse `categorie` pour cette raison). Fusionner « Carte de saison » local
 * dans « Carte de saison » spécial reclasserait tous les plats du poste ; le
 * type entre donc dans la clé. Les dates de saison, non : elles encadrent le
 * menu, elles ne le définissent pas, et celles du serveur font foi.
 *
 * ## Module M4, niveau C — celui de `POST /restaurant/menus`.
 *
 * ## Modification : acceptée, dernier écrit gagnant
 *
 * Décision du Product Owner du 15/10/2026, qui REMPLACE le refus du lot S2
 * (« le serveur est maître, modification refusée » ne vaut plus).
 * Par `CartePlatMenuService::modifierMenu()`, règles de
 * `PUT /restaurant/menus/{menu}` sur les seuls champs présents (la saison
 * inversée se juge sur l'état résultant). Un menu ne s'archive pas.
 */
final class GestionnaireMenus extends GestionnaireReferentielAbstrait
{
    protected const REQUETE = EnregistrerMenuRequest::class;

    protected const PARAMETRE_ROUTE = 'menu';

    public function __construct(
        private readonly CartePlatMenuService $carte,
        ResolveurCorrespondances $correspondances,
    ) {
        parent::__construct($correspondances);
    }

    public function table(): string
    {
        return 'menus';
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
        return $this->valider(
            $payload,
            $this->reglesDeLApi(EnregistrerMenuRequest::class),
            EnregistrerMenuRequest::class,
        );
    }

    protected function equivalent(array $donnees): ?Model
    {
        return $this->premierDeCle(
            Menu::query()->orderBy('date_creation')->orderBy('id'),
            $this->cle((string) $donnees['libelle'], (string) $donnees['type']),
            fn (Menu $m): string => $this->cle($m->libelle, $m->type),
        );
    }

    protected function ecrire(string $entiteId, array $donnees, ContexteSynchronisation $contexte): void
    {
        $this->carte->creerMenu([...$donnees, 'id' => $entiteId]);
    }

    protected function trouver(string $entiteId): Model
    {
        return Menu::query()->lockForUpdate()->findOrFail($entiteId);
    }

    protected function ecrireModification(Model $element, array $donnees, ContexteSynchronisation $contexte): void
    {
        /** @var Menu $element */
        $this->carte->modifierMenu($element, $donnees);
    }
}
