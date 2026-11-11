<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Hebergement\Models\CanalReservation;
use App\Domain\Hebergement\Services\CanalReservationService;
use App\Pwa\Livewire\Transverse\Parametres;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use Illuminate\Support\Facades\Validator;
use RuntimeException;

/**
 * Les canaux de réservation saisis sur un poste (Paramètres › « Canaux de
 * réservation ») — complément de la PWA du 21/10/2026 (« tout au complet »).
 *
 * Par `CanalReservationService`, et lui seul : trois gestes fermés, jamais une
 * suppression (« un canal utilisé ne se supprime pas, il se désactive »). Le
 * module est celui de l'écran qui les administre (`PARAM`, niveau `C`).
 *
 * ## Clé naturelle : le NOM (insensible à la casse)
 *
 * Le même nom saisi sur deux postes FUSIONNE (le service refuse déjà un
 * doublon à l'écran : ici, c'est le cas que la décision du Product Owner du
 * 15/10/2026 traite). Les réservations d'un poste citent leur canal par ce
 * nom (`GestionnaireReservations`).
 *
 * ## La modification porte l'ÉTAT ENTIER, et l'ancien nom
 *
 * `nom` et `actif`, plus `ancien_nom` quand le geste est un renommage : un
 * canal aligné par son nom à la descente garde l'identifiant LOCAL du poste,
 * que le serveur ne connaît pas — l'ancien nom le retrouve (comme le couple
 * du modèle de notification). Sans lui, renommer « Physique » en « Comptoir »
 * créerait un second canal au lieu de renommer le premier.
 */
final class GestionnaireCanauxReservation extends GestionnaireAbstrait
{
    public function __construct(private readonly CanalReservationService $canaux)
    {
    }

    public function table(): string
    {
        return 'canaux_reservation';
    }

    public function module(): string
    {
        return Parametres::MODULE;
    }

    public function serviceDomaine(): string
    {
        return CanalReservationService::class;
    }

    public function accepteModification(): bool
    {
        return true;
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $d = $this->validerCanal($payload);
        $existant = $this->homonyme((string) $d['nom']);

        if ($existant !== null) {
            return new EcritureSynchronisee($entiteId, fusionneAvec: (string) $existant->id);
        }

        $canal = $this->canaux->ajouter((string) $d['nom'], $entiteId);

        if (($d['actif'] ?? true) === false) {
            $this->canaux->basculer((string) $canal->id);
        }

        return new EcritureSynchronisee($entiteId);
    }

    public function modifier(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $this->appliquer(CanalReservation::query()->findOrFail($entiteId), $this->validerCanal($payload));

        return new EcritureSynchronisee($entiteId);
    }

    /**
     * Un canal que le serveur ne connaît pas sous cet identifiant : retrouvé
     * par son ANCIEN nom (renommage d'un canal aligné par son nom), ou par son
     * nom ; créé s'il manque.
     */
    public function modificationSurInconnu(string $entiteId, array $payload, ContexteSynchronisation $contexte): ?EcritureSynchronisee
    {
        $d = $this->validerCanal($payload);
        $existant = (isset($d['ancien_nom']) ? $this->homonyme((string) $d['ancien_nom']) : null)
            ?? $this->homonyme((string) $d['nom']);

        if ($existant === null) {
            return $this->creer($entiteId, $payload, $contexte);
        }

        $this->appliquer($existant, $d);

        return new EcritureSynchronisee($entiteId, fusionneAvec: (string) $existant->id);
    }

    /**
     * @param  array<string, mixed>  $d
     */
    private function appliquer(CanalReservation $canal, array $d): void
    {
        if (trim((string) $d['nom']) !== (string) $canal->nom) {
            $canal = $this->canaux->renommer((string) $canal->id, (string) $d['nom']);
        }

        if (array_key_exists('actif', $d) && (bool) $d['actif'] !== (bool) $canal->actif) {
            $this->canaux->basculer((string) $canal->id);
        }
    }

    private function homonyme(string $nom): ?CanalReservation
    {
        return CanalReservation::query()
            ->whereRaw('LOWER(nom) = ?', [mb_strtolower(trim($nom))])
            ->first();
    }

    /**
     * @param  array<string, mixed>  $payload
     * @return array<string, mixed>
     */
    private function validerCanal(array $payload): array
    {
        $validateur = Validator::make($payload, [
            'nom' => ['required', 'string', 'max:100'],
            'ancien_nom' => ['nullable', 'string', 'max:100'],
            'actif' => ['sometimes', 'boolean'],
        ]);

        if ($validateur->fails()) {
            throw new RuntimeException((string) $validateur->errors()->first());
        }

        return $validateur->validated();
    }
}
