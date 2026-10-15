<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Stocks\Http\Requests\EnregistrerPointStockageRequest;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\ReferentielPointStockageService;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Support\ContexteSynchronisation;
use Illuminate\Database\Eloquent\Model;

/**
 * Points de stockage créés hors connexion (M6) — lot S2, décision du Product
 * Owner du 15/10/2026. Patron commun : `GestionnaireReferentielAbstrait`.
 *
 * ## Clé naturelle : le libellé normalisé
 *
 * C'est la règle du poste lui-même (`StocksDao.creerPoint` refuse un libellé
 * déjà pris, sans casse) : deux points homonymes se choisiraient au hasard
 * dans un sélecteur, et un mouvement serait imputé à l'autre sans que rien
 * ne le dise. Le type n'entre PAS dans la clé : « Bar » de type `bar` et
 * « Bar » sans type sont le même comptoir, saisi deux fois.
 *
 * ## Module M6, niveau C
 *
 * Le droit de la modale du poste (écran Stocks) et de toutes les écritures du
 * référentiel M6 (`POST /stocks/articles` : `module:M6,C`). Aucune route ne
 * crée de point côté serveur : la requête de règles et le service sont nés
 * avec ce lot.
 *
 * ## Modification refusée
 *
 * Renommer un point hors connexion renommerait, pour tous les postes, le lieu
 * où le stock de chaque article est compté — le serveur en est maître.
 */
final class GestionnairePointsStockage extends GestionnaireReferentielAbstrait
{
    public function __construct(
        private readonly ReferentielPointStockageService $referentiel,
        ResolveurCorrespondances $correspondances,
    ) {
        parent::__construct($correspondances);
    }

    public function table(): string
    {
        return 'points_stockage';
    }

    public function module(): string
    {
        return 'M6';
    }

    public function serviceDomaine(): string
    {
        return ReferentielPointStockageService::class;
    }

    protected function validerCreation(array $payload): array
    {
        return $this->valider(
            $payload,
            $this->reglesDeLApi(EnregistrerPointStockageRequest::class),
            EnregistrerPointStockageRequest::class,
        );
    }

    protected function equivalent(array $donnees): ?Model
    {
        return $this->premierDeCle(
            PointStockage::query()->orderBy('date_creation')->orderBy('id'),
            $this->cle((string) $donnees['libelle']),
            fn (PointStockage $p): string => $this->cle($p->libelle),
        );
    }

    protected function ecrire(string $entiteId, array $donnees, ContexteSynchronisation $contexte): void
    {
        $this->referentiel->creer([...$donnees, 'id' => $entiteId]);
    }
}
