<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Pwa\Livewire\Transverse\Parametres;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Parametres\Services\EnregistrerParametreService;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use Carbon\Carbon;
use Illuminate\Support\Facades\Validator;
use RuntimeException;

/**
 * Les paramètres du système enregistrés sur un poste — audit de couverture
 * du 18/10/2026 (lot 10e, « tous les modules »).
 *
 * ## Un ENREGISTREMENT, pas une clé
 *
 * L'opération porte le LOT soumis par l'écran Paramètres du poste
 * (`valeurs`, clé → valeur), sous un identifiant propre à ce geste : c'est la
 * forme que `EnregistrerParametreService` exige, la cohérence se jugeant sur
 * l'état RÉSULTANT (activer la TVA et saisir son taux dans le même envoi).
 * Clé par clé, l'activation arriverait seule et serait refusée.
 *
 * ## Dernier écrit gagnant, clé par clé
 *
 * Une clé modifiée au serveur APRÈS la saisie du poste (horodatage client)
 * garde la valeur du serveur : elle est rendue dans `cles_conservees`, et la
 * descente la rapporte au poste. Les autres passent par le service, lui
 * seul — registre fermé, normalisation, gardes PA-61/PA-62, audit.
 *
 * Module `PARAM`, celui de l'écran (RG-16 : un module transverse est un
 * module).
 */
final class GestionnaireParametres extends GestionnaireAbstrait
{
    public function __construct(private readonly EnregistrerParametreService $parametres)
    {
    }

    public function table(): string
    {
        return 'parametres_systeme';
    }

    public function module(): string
    {
        return Parametres::MODULE;
    }

    public function serviceDomaine(): string
    {
        return EnregistrerParametreService::class;
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $validateur = Validator::make($payload, [
            'valeurs' => ['required', 'array', 'min:1'],
        ]);
        $nonScalaires = array_filter(
            is_array($payload['valeurs'] ?? null) ? $payload['valeurs'] : [],
            static fn (mixed $v): bool => $v !== null && ! is_scalar($v),
        );

        if ($validateur->fails() || $nonScalaires !== []) {
            throw new RuntimeException($validateur->fails()
                ? (string) $validateur->errors()->first()
                : __('sync.parametres.valeur_non_scalaire', ['cles' => implode(', ', array_keys($nonScalaires))]));
        }

        /** @var array<string, scalar|null> $valeurs */
        $valeurs = $payload['valeurs'];
        $retenues = [];
        $conservees = [];

        foreach ($valeurs as $cle => $valeur) {
            $stocke = ParametreSysteme::query()->where('cle', (string) $cle)->first();

            if ($stocke !== null && $this->plusRecentAuServeur($stocke, $contexte->horodatageClient)) {
                $conservees[] = (string) $cle;

                continue;
            }

            $retenues[(string) $cle] = $valeur;
        }

        $modifiees = $retenues === [] ? [] : $this->parametres->enregistrer($retenues);

        return new EcritureSynchronisee($entiteId, complements: [
            'cles_modifiees' => $modifiees,
            'cles_conservees' => $conservees,
        ]);
    }

    private function plusRecentAuServeur(ParametreSysteme $stocke, Carbon $saisie): bool
    {
        $serveur = $stocke->updated_at ?? $stocke->created_at;

        return $serveur !== null && Carbon::parse($serveur)->greaterThan($saisie);
    }
}
