<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Rh\Models\Employe;
use App\Domain\Rh\Models\Service;
use App\Domain\Rh\Services\EmployeService;
use App\Shared\Mail\Support\AdresseEmailFacultative;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Services\SignalementAnomalies;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use RuntimeException;

/**
 * Le dossier des employés (M13) saisi sur un poste — audit de couverture du
 * 18/10/2026 (« tout ce que la PWA enregistre, tous les modules »).
 *
 * Par `EmployeService`, et lui seul : le MATRICULE est celui du serveur
 * (sa séquence) et il est rendu au poste, qui remplace le sien. Le service
 * est désigné par son identifiant (correspondance) ou, à défaut, par son
 * LIBELLÉ (créé s'il manque : aucun écrivain ne le sème au serveur). Aucun
 * rapprochement d'homonymes : deux personnes peuvent porter le même nom.
 * Modification : les champs du dossier ; `statut: parti` seul = archivage.
 */
final class GestionnaireEmployes extends GestionnaireDocumentAbstrait
{
    public const CHAMPS = [
        'nom', 'prenom', 'poste', 'service_id', 'service_libelle', 'date_embauche', 'salaire_base',
        'numero_cnss', 'type_contrat', 'date_fin_contrat', 'statut', 'email',
    ];

    public function __construct(
        private readonly EmployeService $employes,
        ResolveurCorrespondances $correspondances,
        SignalementAnomalies $anomalies,
    ) {
        parent::__construct($correspondances, $anomalies);
    }

    public function table(): string
    {
        return 'employes';
    }

    public function module(): string
    {
        return 'M13';
    }

    public function serviceDomaine(): string
    {
        return EmployeService::class;
    }

    public function accepteModification(): bool
    {
        return true;
    }

    protected function resultat(string $entiteId): EcritureSynchronisee
    {
        return new EcritureSynchronisee($entiteId, complements: [
            'matricule' => (string) Employe::query()->findOrFail($entiteId)->matricule,
        ]);
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $donnees = $this->validerForme($payload, [
            'nom' => ['required', 'string', 'max:255'],
            'prenom' => ['nullable', 'string', 'max:255'],
            'poste' => ['required', 'string', 'max:255'],
            'service_id' => ['nullable', 'string'],
            'service_libelle' => ['nullable', 'string'],
            'date_embauche' => ['required', 'date_format:Y-m-d'],
            'salaire_base' => ['required', 'integer', 'min:0'],
            'numero_cnss' => ['nullable', 'string', 'max:255'],
            'type_contrat' => ['nullable', 'in:CDI,CDD,Stage,Journalier'],
            'date_fin_contrat' => ['nullable', 'date_format:Y-m-d'],
            'statut' => ['nullable', 'in:actif,conge,suspendu,parti'],
            // 28/10/2026 : e-mail facultatif, même règle que l'écran (normalisé par le poste).
            'email' => AdresseEmailFacultative::REGLES,
        ]);

        $this->employes->creerEmploye([
            ...$donnees,
            'service_id' => $this->service($donnees),
            'salaire_base' => $this->francs((int) $donnees['salaire_base']),
        ], $entiteId);

        return $this->resultat($entiteId);
    }

    public function modifier(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $refuses = array_diff(array_keys($payload), self::CHAMPS);

        if ($refuses !== []) {
            throw new RuntimeException(__('sync.rh.champ_non_modifiable', ['champs' => implode(', ', $refuses)]));
        }

        $employe = Employe::query()->findOrFail($entiteId);

        if (array_keys($payload) === ['statut'] && $payload['statut'] === 'parti') {
            if ($employe->statut !== 'parti') {
                $this->employes->archiver($employe);
            }

            return $this->resultat($entiteId);
        }

        $donnees = $payload;

        if (array_key_exists('email', $payload)) {
            $this->validerForme(['email' => $payload['email']], ['email' => AdresseEmailFacultative::REGLES]);
        }

        if (isset($payload['service_id']) || isset($payload['service_libelle'])) {
            $donnees['service_id'] = $this->service($payload);
        }

        unset($donnees['service_libelle']);

        if (isset($donnees['salaire_base'])) {
            $donnees['salaire_base'] = $this->francs((int) $donnees['salaire_base']);
        }

        $this->employes->mettreAJourEmploye($employe, $donnees);

        return $this->resultat($entiteId);
    }

    /**
     * @param  array<string, mixed>  $donnees
     */
    private function service(array $donnees): string
    {
        if (! empty($donnees['service_id'])) {
            $service = Service::find($this->resoudre('services', $donnees['service_id']));

            if ($service !== null) {
                return (string) $service->id;
            }
        }

        $libelle = trim((string) ($donnees['service_libelle'] ?? ''));

        if ($libelle === '') {
            throw new RuntimeException(__('sync.rh.service_inconnu', ['libelle' => $libelle]));
        }

        // Un service que le serveur n'a pas encore (référentiel non semé) est
        // créé par son libellé — sa clé naturelle : un employé n'attend jamais
        // indéfiniment un référentiel que personne n'écrit au serveur.
        return (string) Service::query()->firstOrCreate(['libelle' => $libelle])->id;
    }
}
