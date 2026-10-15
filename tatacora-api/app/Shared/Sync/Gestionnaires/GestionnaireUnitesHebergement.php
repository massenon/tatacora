<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Hebergement\Http\Requests\EnregistrerUniteHebergementRequest;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Hebergement\Services\ParcHebergementService;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Support\ContexteSynchronisation;
use Illuminate\Database\Eloquent\Model;

/**
 * Unités d'hébergement créées hors connexion (M1, EF-M1-01) — lot S2,
 * décision du Product Owner du 15/10/2026. Patron commun :
 * `GestionnaireReferentielAbstrait` ; la levée de PA-118 est motivée sur
 * `GestionnaireCategoriesHebergement`.
 *
 * ## Clé naturelle : le numéro normalisé, sur tout le parc
 *
 * Le numéro EST l'identité d'une unité pour qui tient le comptoir (« la
 * B-12 ») ; le poste le veut unique sur tout le parc
 * (`ParcDao._exigerNumeroLibre`), catégorie confondue. Deux « B-12 » feraient
 * réserver la mauvaise chambre. À numéro égal, la catégorie du serveur fait
 * foi, même si le poste en citait une autre.
 *
 * La catégorie citée est traduite par les correspondances (catégorie créée
 * sur ce poste et fusionnée), puis exigée (`exists`) : le poste pousse la
 * catégorie AVANT l'unité.
 *
 * ## Statut : jamais reçu
 *
 * Une unité naît `libre` (`ParcHebergementService::creerUnite()`) : le cycle
 * appartient à `SejourService`. Une unité `hors_service` (l'ARCHIVE du parc)
 * reste une cible de fusion — c'est la même chambre — et le poste en est
 * averti (`cible_archivee`).
 *
 * ## Module M1, niveau C — celui de l'écran PWA Hébergement.
 *
 * ## Modification refusée
 *
 * Renuméroter ou reclasser une unité hors connexion changerait la chambre de
 * réservations prises sur d'autres postes. Le serveur est maître.
 */
final class GestionnaireUnitesHebergement extends GestionnaireReferentielAbstrait
{
    protected const REFERENCES = ['categorie_id' => 'categories_hebergement'];

    public function __construct(
        private readonly ParcHebergementService $parc,
        ResolveurCorrespondances $correspondances,
    ) {
        parent::__construct($correspondances);
    }

    public function table(): string
    {
        return 'unites_hebergement';
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
            $this->reglesDeLApi(EnregistrerUniteHebergementRequest::class),
            EnregistrerUniteHebergementRequest::class,
        );
    }

    protected function equivalent(array $donnees): ?Model
    {
        return $this->premierDeCle(
            UniteHebergement::query()->orderBy('created_at')->orderBy('id'),
            $this->cle((string) $donnees['numero']),
            fn (UniteHebergement $u): string => $this->cle($u->numero),
        );
    }

    protected function estArchive(Model $element): bool
    {
        return $element->getAttribute('statut') === 'hors_service';
    }

    protected function ecrire(string $entiteId, array $donnees, ContexteSynchronisation $contexte): void
    {
        $this->parc->creerUnite([...$donnees, 'id' => $entiteId]);
    }
}
