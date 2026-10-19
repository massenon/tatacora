<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Tourisme\Http\Requests\EnregistrerCircuitRequest;
use App\Domain\Tourisme\Models\Circuit;
use App\Shared\Sync\Support\ContexteSynchronisation;
use Illuminate\Database\Eloquent\Model;

/**
 * Circuits (prestations touristiques, M9) créés ou modifiés sur un poste —
 * lot F4, décision du Product Owner du 17/10/2026 (« les activités et
 * réservations liées au tourisme … en synchronisation »).
 *
 * Une DÉFINITION du catalogue : création fusionnée sur la clé naturelle (le
 * nom), modification au dernier écrit gagnant — les règles du catalogue
 * (`GestionnaireReferentielAbstrait`). Le serveur n'a pas de service de
 * circuits : la PWA écrit le modèle (`Departs::enregistrerPrestation`), et
 * ce gestionnaire fait de même, sous les mêmes règles
 * (`EnregistrerCircuitRequest`). Une durée absente est rangée VIDE
 * (« indéterminée » pour `ReservationTourService`).
 */
final class GestionnaireCircuits extends GestionnaireReferentielAbstrait
{
    protected const REQUETE = EnregistrerCircuitRequest::class;

    protected const PARAMETRE_ROUTE = 'circuit';

    public function table(): string
    {
        return 'circuits';
    }

    public function module(): string
    {
        return 'M9';
    }

    public function serviceDomaine(): string
    {
        return Circuit::class;
    }

    protected function validerCreation(array $payload): array
    {
        return $this->valider($payload, (new EnregistrerCircuitRequest())->rules(), EnregistrerCircuitRequest::class);
    }

    protected function equivalent(array $donnees): ?Model
    {
        return $this->premierDeCle(
            Circuit::query()->orderBy('created_at')->orderBy('id'),
            $this->cle((string) $donnees['nom']),
            fn (Circuit $c): string => $this->cle($c->nom),
        );
    }

    protected function ecrire(string $entiteId, array $donnees, ContexteSynchronisation $contexte): void
    {
        Circuit::create([...$donnees, 'duree' => $donnees['duree'] ?? '', 'id' => $entiteId]);
    }

    protected function trouver(string $entiteId): Model
    {
        return Circuit::query()->lockForUpdate()->findOrFail($entiteId);
    }

    protected function ecrireModification(Model $element, array $donnees, ContexteSynchronisation $contexte): void
    {
        if (array_key_exists('duree', $donnees) && $donnees['duree'] === null) {
            $donnees['duree'] = '';
        }

        $element->update($donnees);
    }
}
