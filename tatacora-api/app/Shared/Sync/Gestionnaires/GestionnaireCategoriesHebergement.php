<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Hebergement\Http\Requests\EnregistrerCategorieHebergementRequest;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Services\ParcHebergementService;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Support\ContexteSynchronisation;
use Illuminate\Database\Eloquent\Model;

/**
 * Catégories d'hébergement créées hors connexion (M1, EF-M1-01) — lot S2,
 * décision du Product Owner du 15/10/2026. Patron commun :
 * `GestionnaireReferentielAbstrait`.
 *
 * ## Le parc remonte désormais — et pourquoi ce n'est pas revenir sur PA-118
 *
 * Jusqu'au 15/10/2026, `unites_hebergement` n'était pas au registre et « le
 * parc descendait, il ne remontait jamais ». PA-118 refusait le « Plan
 * d'Hébergement » du prototype parce qu'une unité créée au comptoir ne
 * partait nulle part — un parc local divergent. La décision du Product Owner
 * du 15/10/2026 lève la cause : la création hors connexion remonte, et le
 * serveur FUSIONNE sur la clé naturelle au lieu de doubler le parc.
 *
 * ## Clé naturelle : le libellé normalisé
 *
 * L'écran en ligne l'impose déjà unique (`unique:categories_hebergement`) et
 * le poste aussi (`ParcDao._exigerLibelleLibre`). La contrainte d'unicité est
 * retirée de la validation synchronisée — un libellé pris FUSIONNE, il n'est
 * pas refusé ; tarif et capacité restent ceux du serveur.
 *
 * ## Module M1, niveau C — celui de l'écran PWA Hébergement (`MODULE = 'M1'`).
 *
 * ## Modification : acceptée, dernier écrit gagnant
 *
 * Décision du Product Owner du 15/10/2026, qui REMPLACE le refus du lot S2
 * (« le serveur est maître, modification refusée » ne vaut plus).
 * Par `ParcHebergementService::modifierCategorie()`, règles
 * d'`EnregistrerCategorieHebergementRequest` sur les seuls champs présents —
 * unicité du libellé COMPRISE (hors la catégorie elle-même) : renommer en un
 * libellé déjà pris est refusé avec la phrase de l'écran. Le poste resté hors
 * ligne qui rétablirait un ancien tarif perd l'arbitrage sur l'horodatage de
 * saisie. Une catégorie ne s'archive pas.
 */
final class GestionnaireCategoriesHebergement extends GestionnaireReferentielAbstrait
{
    protected const REQUETE = EnregistrerCategorieHebergementRequest::class;

    protected const PARAMETRE_ROUTE = 'categorie';

    public function __construct(
        private readonly ParcHebergementService $parc,
        ResolveurCorrespondances $correspondances,
    ) {
        parent::__construct($correspondances);
    }

    public function table(): string
    {
        return 'categories_hebergement';
    }

    public function module(): string
    {
        return 'M1';
    }

    public function serviceDomaine(): string
    {
        return ParcHebergementService::class;
    }

    protected function validerCreation(array $payload): array
    {
        return $this->valider(
            $payload,
            $this->sansUnicite($this->reglesDeLApi(EnregistrerCategorieHebergementRequest::class), 'libelle'),
            EnregistrerCategorieHebergementRequest::class,
        );
    }

    protected function equivalent(array $donnees): ?Model
    {
        return $this->premierDeCle(
            CategorieHebergement::query()->orderBy('created_at')->orderBy('id'),
            $this->cle((string) $donnees['libelle']),
            fn (CategorieHebergement $c): string => $this->cle($c->libelle),
        );
    }

    protected function ecrire(string $entiteId, array $donnees, ContexteSynchronisation $contexte): void
    {
        $this->parc->creerCategorie([...$donnees, 'id' => $entiteId]);
    }

    protected function trouver(string $entiteId): Model
    {
        return CategorieHebergement::query()->lockForUpdate()->findOrFail($entiteId);
    }

    protected function ecrireModification(Model $element, array $donnees, ContexteSynchronisation $contexte): void
    {
        /** @var CategorieHebergement $element */
        $this->parc->modifierCategorie($element, $donnees);
    }
}
