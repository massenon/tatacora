<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Services\PlanComptableService;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Services\SignalementAnomalies;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use RuntimeException;

/**
 * Les COMPTES du plan comptable créés sur un poste (M10) — hub comptable,
 * « + Créer un compte ». D246 rouvert par décision du PO du 28/10/2026 : le
 * poste fait ce que le web fait, et son compte rejoint le plan du serveur.
 *
 * Par `PlanComptableService::creerCompte`, et lui seul : mêmes validations
 * (`NUMERO_COMPTE_FORMAT`, libellé obligatoire, nature du registre fermé) et
 * mêmes PHRASES que l'écran web. Création seule : la PWA n'a aucun geste de
 * correction d'un compte.
 *
 * ## Un numéro déjà pris
 *
 * Le numéro est la clé naturelle du compte. Trois cas, jamais un doublon :
 *  * même identifiant : rejeu, le résultat d'origine est rendu ;
 *  * autre identifiant, MÊME libellé et MÊME nature : le poste a recréé hors
 *    ligne le compte que le serveur a déjà — FUSION (`fusionne_avec`), rien
 *    n'est écrit ;
 *  * autre identifiant, libellé ou nature DIFFÉRENTS : refus à la phrase du
 *    service (« Le compte … existe déjà »). Deux comptes qui ne disent pas la
 *    même chose ne se fondent pas en silence.
 */
final class GestionnairePlanComptable extends GestionnaireDocumentAbstrait
{
    public function __construct(
        private readonly PlanComptableService $plan,
        ResolveurCorrespondances $correspondances,
        SignalementAnomalies $anomalies,
    ) {
        parent::__construct($correspondances, $anomalies);
    }

    public function table(): string
    {
        return 'plan_comptable';
    }

    public function module(): string
    {
        return 'M10';
    }

    public function serviceDomaine(): string
    {
        return PlanComptableService::class;
    }

    public function reprendreExistant(string $entiteId, ContexteSynchronisation $contexte): ?EcritureSynchronisee
    {
        return CompteComptable::query()->whereKey($entiteId)->exists() ? $this->resultat($entiteId) : null;
    }

    protected function resultat(string $entiteId): EcritureSynchronisee
    {
        return new EcritureSynchronisee($entiteId, complements: [
            'numero' => (string) CompteComptable::query()->findOrFail($entiteId)->numero_compte,
        ]);
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        // Forme laxiste : un numéro, un libellé ou une nature faux doivent
        // atteindre le service, qui les refuse avec SA phrase.
        $donnees = $this->validerForme($payload, [
            'numero_compte' => ['nullable', 'string'],
            'libelle' => ['nullable', 'string', 'max:255'],
            'nature' => ['nullable', 'string'],
        ]);

        $numero = (string) ($donnees['numero_compte'] ?? '');
        $libelle = (string) ($donnees['libelle'] ?? '');
        $nature = (string) ($donnees['nature'] ?? '');

        $existant = $numero === '' ? null : CompteComptable::query()->where('numero_compte', $numero)->first();

        if ($existant !== null) {
            if (mb_strtolower(trim($libelle)) === mb_strtolower(trim((string) $existant->libelle))
                && $nature === (string) $existant->nature) {
                return new EcritureSynchronisee($entiteId, fusionneAvec: (string) $existant->id, complements: [
                    'numero' => $numero,
                ]);
            }

            throw new RuntimeException(__('comptabilite.compte_deja_existant', ['numero' => $numero]));
        }

        $this->plan->creerCompte($numero, $libelle, $nature, $entiteId);

        return $this->resultat($entiteId);
    }
}
