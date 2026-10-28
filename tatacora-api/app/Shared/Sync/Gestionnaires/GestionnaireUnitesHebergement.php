<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Hebergement\Http\Requests\EnregistrerUniteHebergementRequest;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Hebergement\Services\ParcHebergementService;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
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
 * ## Modification : acceptée, dernier écrit gagnant
 *
 * Décision du Product Owner du 15/10/2026, qui REMPLACE le refus du lot S2
 * (« le serveur est maître, modification refusée » ne vaut plus).
 * Par `ParcHebergementService::modifierUnite()` (le chemin
 * que l'écran PWA emprunte aussi), règles d'`EnregistrerUniteHebergementRequest`
 * sur les seuls champs présents ; catégorie citée traduite. `statut` reste
 * ignoré (cycle de `SejourService`). `actif: false` ARCHIVE (`hors_service`,
 * verrou d'engagement du service), `actif: true` restaure — sous
 * `DroitArchivageService` (M1), comme l'écran.
 */
final class GestionnaireUnitesHebergement extends GestionnaireReferentielAbstrait
{
    protected const REFERENCES = ['categorie_id' => 'categories_hebergement'];

    protected const REQUETE = EnregistrerUniteHebergementRequest::class;

    protected const PARAMETRE_ROUTE = 'unite';

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

    protected function trouver(string $entiteId): Model
    {
        return UniteHebergement::query()->lockForUpdate()->findOrFail($entiteId);
    }

    protected function ecrireModification(Model $element, array $donnees, ContexteSynchronisation $contexte): void
    {
        /** @var UniteHebergement $element */
        $this->parc->modifierUnite($element, $donnees);
    }

    /** A5 : la purge définitive d'une unité archivée (28/10/2026). */
    public function accepteSuppression(): bool
    {
        return true;
    }

    /** Les verrous et les phrases sont ceux du service de parc, jamais réécrits ici. */
    public function supprimer(string $entiteId, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $this->parc->purger($this->trouver($entiteId));

        return new EcritureSynchronisee($entiteId);
    }

    protected function archivable(): bool
    {
        return true;
    }

    protected function archiver(Model $element): void
    {
        /** @var UniteHebergement $element */
        $this->parc->archiver($element);
    }

    protected function restaurer(Model $element): void
    {
        /** @var UniteHebergement $element */
        $this->parc->restaurer($element);
    }
}
