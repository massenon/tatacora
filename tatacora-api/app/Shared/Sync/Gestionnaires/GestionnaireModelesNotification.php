<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Notifications\Models\ModeleNotification;
use App\Domain\Notifications\Services\ModeleNotificationService;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use Illuminate\Support\Facades\Validator;
use RuntimeException;

/**
 * Les modèles de notification (M12) saisis sur un poste — lot 10f (audit de
 * couverture du 18/10/2026). Une CONFIGURATION, jamais un envoi : les
 * messages tracés restent sur leur poste.
 *
 * Par `ModeleNotificationService`, et lui seul (registres fermés des
 * déclencheurs et des canaux, contenu exigé). Clé naturelle (événement,
 * canal) : le même couple saisi sur deux postes FUSIONNE. La modification
 * porte l'état entier (événement compris, jamais modifié) : un modèle
 * inconnu du serveur s'y retrouve par son couple, ou y naît.
 */
final class GestionnaireModelesNotification extends GestionnaireAbstrait
{
    public function __construct(private readonly ModeleNotificationService $modeles)
    {
    }

    public function table(): string
    {
        return 'modeles_notification';
    }

    public function module(): string
    {
        return 'M12';
    }

    public function serviceDomaine(): string
    {
        return ModeleNotificationService::class;
    }

    public function accepteModification(): bool
    {
        return true;
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $d = $this->validerModele($payload);
        $existant = $this->homonyme((string) $d['evenement'], (string) $d['canal']);

        if ($existant !== null) {
            return new EcritureSynchronisee($entiteId, fusionneAvec: (string) $existant->id);
        }

        $this->modeles->creerModele($d, $entiteId);

        return new EcritureSynchronisee($entiteId);
    }

    public function modifier(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $d = $this->validerModele($payload);
        $this->modeles->modifierModele(ModeleNotification::query()->findOrFail($entiteId), $d);

        return new EcritureSynchronisee($entiteId);
    }

    public function modificationSurInconnu(string $entiteId, array $payload, ContexteSynchronisation $contexte): ?EcritureSynchronisee
    {
        $d = $this->validerModele($payload);
        $existant = $this->homonyme((string) $d['evenement'], (string) $d['canal']);

        if ($existant === null) {
            return $this->creer($entiteId, $payload, $contexte);
        }

        $this->modeles->modifierModele($existant, $d);

        return new EcritureSynchronisee($entiteId, fusionneAvec: (string) $existant->id);
    }

    private function homonyme(string $evenement, string $canal): ?ModeleNotification
    {
        return ModeleNotification::query()->where('evenement', $evenement)->where('canal', $canal)->first();
    }

    /**
     * @param  array<string, mixed>  $payload
     * @return array<string, mixed>
     */
    private function validerModele(array $payload): array
    {
        $validateur = Validator::make($payload, [
            'evenement' => ['required', 'string'],
            'canal' => ['required', 'string'],
            'objet' => ['nullable', 'string', 'max:255'],
            'contenu_template' => ['required', 'string'],
            'actif' => ['required', 'boolean'],
        ]);

        if ($validateur->fails()) {
            throw new RuntimeException((string) $validateur->errors()->first());
        }

        return $validateur->validated();
    }
}
