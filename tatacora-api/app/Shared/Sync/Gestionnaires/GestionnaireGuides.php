<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Tourisme\Http\Requests\EnregistrerGuideRequest;
use App\Domain\Tourisme\Models\Guide;
use App\Shared\Sync\Models\AnomalieSynchronisation;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Services\SignalementAnomalies;
use App\Shared\Sync\Support\ContexteSynchronisation;
use Illuminate\Database\Eloquent\Model;

/**
 * Guides (M9) créés ou modifiés sur un poste — lot F4 (17/10/2026).
 *
 * Règles du catalogue (fusion sur le nom, dernier écrit gagnant). Le poste
 * ne saisit pas le TARIF JOURNALIER (`guides_local` n'a pas la colonne) ; la
 * colonne du serveur est obligatoire. Un guide créé par un poste est donc
 * rangé à 0 et SIGNALÉ (`guide_sans_tarif`) — la règle du PO du 15/10/2026
 * (« ne bride pas les postes » : enregistré et signalé, jamais refusé), et
 * jamais un tarif deviné. Une modification venue du poste ne touche jamais
 * le tarif saisi au serveur.
 */
final class GestionnaireGuides extends GestionnaireReferentielAbstrait
{
    protected const REQUETE = EnregistrerGuideRequest::class;

    protected const PARAMETRE_ROUTE = 'guide';

    public function __construct(
        ResolveurCorrespondances $correspondances,
        private readonly SignalementAnomalies $anomalies,
    ) {
        parent::__construct($correspondances);
    }

    public function table(): string
    {
        return 'guides';
    }

    public function module(): string
    {
        return 'M9';
    }

    public function serviceDomaine(): string
    {
        return Guide::class;
    }

    protected function validerCreation(array $payload): array
    {
        return $this->valider($payload, (new EnregistrerGuideRequest())->rules(), EnregistrerGuideRequest::class);
    }

    protected function equivalent(array $donnees): ?Model
    {
        return $this->premierDeCle(
            Guide::query()->orderBy('created_at')->orderBy('id'),
            $this->cle((string) $donnees['nom']),
            fn (Guide $g): string => $this->cle($g->nom),
        );
    }

    protected function ecrire(string $entiteId, array $donnees, ContexteSynchronisation $contexte): void
    {
        $sansTarif = ($donnees['tarif_jour'] ?? null) === null;

        Guide::create([...$donnees, 'tarif_jour' => $donnees['tarif_jour'] ?? '0.00', 'id' => $entiteId]);

        if ($sansTarif) {
            $this->anomalies->signaler($contexte, 'guides', $entiteId, AnomalieSynchronisation::GUIDE_SANS_TARIF);
        }
    }

    protected function trouver(string $entiteId): Model
    {
        return Guide::query()->lockForUpdate()->findOrFail($entiteId);
    }

    protected function ecrireModification(Model $element, array $donnees, ContexteSynchronisation $contexte): void
    {
        if (($donnees['tarif_jour'] ?? null) === null) {
            unset($donnees['tarif_jour']);
        }

        $element->update($donnees);
    }
}
