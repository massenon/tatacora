<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Rh;

use App\Domain\Rh\Models\Conge;
use App\Domain\Rh\Models\Employe;
use App\Domain\Rh\Models\Planning;
use App\Domain\Rh\Services\CongeService;
use App\Domain\Rh\Services\EmployeService;
use App\Domain\Rh\Services\PlanningService;
use App\Pwa\Livewire\Concerns\FormulaireModal;
use App\Pwa\Livewire\PageMetier;
use Carbon\CarbonImmutable;
use Illuminate\View\View;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use RuntimeException;

/**
 * Plannings d'équipe et congés (M13) — EF-M13-02 / EF-M13-04, RG-13 / RG-14.
 *
 * Écran créé le 21/10/2026 (décision du PO : « écrans PWA + poste +
 * synchronisation ») : les services de domaine existaient, aucun écran ne les
 * portait. Il n'écrit QUE par eux :
 *
 *  - `PlanningService::planifier` — un employé n'est jamais à deux endroits
 *    sur le même créneau (RG-13, sous verrou), ni planifié pendant un congé
 *    validé ;
 *  - `CongeService::demander` — toujours acceptée ; `valider` — préavis et
 *    couverture de service (RG-14), paramétrés, jamais devinés ; `refuser` —
 *    la demande reste, avec sa trace.
 *
 * Aucun geste de suppression n'existe : une erreur de planning se corrige par
 * un nouveau créneau, un congé refusé se conserve.
 *
 * @see EF-M13-02 Planification des équipes
 * @see EF-M13-04 Congés et absences avec workflow de validation
 */
#[Layout('layouts.pwa')]
#[Title('Congés & Plannings — LogiReStock — TATACORA AFRIQUE')]
class CongesPlannings extends PageMetier
{
    use FormulaireModal;

    public const MODULE = 'M13';

    public const ONGLETS = ['plannings', 'conges'];

    #[Url(as: 'onglet')]
    public string $onglet = 'plannings';

    /** Le jour des plannings affichés (`AAAA-MM-JJ`) ; vide = aujourd'hui. */
    #[Url(as: 'date')]
    public string $jour = '';

    #[Url(as: 'service')]
    public string $service = '';

    #[Url(as: 'statut')]
    public string $statutConge = '';

    // ------------------------------------------------- formulaire « planning »
    public ?string $employePlanning = null;

    public ?string $servicePlanning = null;

    public string $datePlanning = '';

    public string $heureDebutPlanning = '08:00';

    public string $heureFinPlanning = '16:00';

    // --------------------------------------------------- formulaire « congé »
    public ?string $employeConge = null;

    public string $typeConge = 'annuel';

    public string $debutConge = '';

    public string $finConge = '';

    protected function formulaires(): array
    {
        return [
            'planning' => ['employePlanning', 'servicePlanning', 'datePlanning', 'heureDebutPlanning', 'heureFinPlanning'],
            'conge' => ['employeConge', 'typeConge', 'debutConge', 'finConge'],
        ];
    }

    // =====================================================================
    // Écritures
    // =====================================================================

    public function ouvrirPlanification(): void
    {
        $this->ouvrirFormulaire('planning');

        $this->datePlanning = $this->jourAffiche()->toDateString();
        $this->heureDebutPlanning = '08:00';
        $this->heureFinPlanning = '16:00';
    }

    public function enregistrerPlanning(): void
    {
        $donnees = $this->validerEcriture([
            'employePlanning' => ['required', 'string', 'exists:employes,id'],
            'servicePlanning' => ['required', 'string', 'exists:services,id'],
            'datePlanning' => ['required', 'date_format:Y-m-d'],
            'heureDebutPlanning' => ['required', 'date_format:H:i'],
            'heureFinPlanning' => ['required', 'date_format:H:i', 'after:heureDebutPlanning'],
        ]);

        try {
            app(PlanningService::class)->planifier([
                'employe_id' => $donnees['employePlanning'],
                'service_id' => $donnees['servicePlanning'],
                'date' => $donnees['datePlanning'],
                'heure_debut' => $donnees['heureDebutPlanning'],
                'heure_fin' => $donnees['heureFinPlanning'],
            ]);
        } catch (RuntimeException $e) {
            // RG-13 (chevauchement) et « en congé validé » : la phrase du service.
            $this->addError('employePlanning', $e->getMessage());

            return;
        }

        $this->jour = (string) $donnees['datePlanning'];
        $this->terminerFormulaire(__('rh_conges_pwa.planning_enregistre'));
    }

    public function ouvrirDemandeConge(): void
    {
        $this->ouvrirFormulaire('conge');

        $this->typeConge = Conge::TYPES[0];
        $this->debutConge = CarbonImmutable::today()->addDays(7)->toDateString();
        $this->finConge = CarbonImmutable::today()->addDays(7)->toDateString();
    }

    public function enregistrerConge(): void
    {
        $donnees = $this->validerEcriture([
            'employeConge' => ['required', 'string', 'exists:employes,id'],
            'typeConge' => ['required', 'string', 'in:'.implode(',', Conge::TYPES)],
            'debutConge' => ['required', 'date_format:Y-m-d'],
            'finConge' => ['required', 'date_format:Y-m-d', 'after_or_equal:debutConge'],
        ]);

        try {
            app(CongeService::class)->demander([
                'employe_id' => $donnees['employeConge'],
                'type' => $donnees['typeConge'],
                'date_debut' => $donnees['debutConge'],
                'date_fin' => $donnees['finConge'],
            ]);
        } catch (RuntimeException $e) {
            $this->addError('employeConge', $e->getMessage());

            return;
        }

        $this->onglet = 'conges';
        $this->terminerFormulaire(__('rh_conges_pwa.conge_demande'));
    }

    public function validerConge(string $congeId): void
    {
        $utilisateur = $this->exigerEcriture(self::MODULE);
        $conge = Conge::query()->findOrFail($congeId);

        try {
            app(CongeService::class)->valider($conge, $utilisateur);
        } catch (RuntimeException $e) {
            // RG-14 : préavis, couverture, paramètre absent — dits tels quels.
            $this->addError('conge-'.$conge->id, $e->getMessage());

            return;
        }

        session()->flash('pwa-succes', __('rh_conges_pwa.conge_valide'));
    }

    public function refuserConge(string $congeId): void
    {
        $utilisateur = $this->exigerEcriture(self::MODULE);
        $conge = Conge::query()->findOrFail($congeId);

        try {
            app(CongeService::class)->refuser($conge, $utilisateur);
        } catch (RuntimeException $e) {
            $this->addError('conge-'.$conge->id, $e->getMessage());

            return;
        }

        session()->flash('pwa-succes', __('rh_conges_pwa.conge_refuse'));
    }

    public function fermerModales(): void
    {
        $this->etatFormulaire = null;
        $this->resetValidation();
    }

    // =====================================================================
    // Lectures
    // =====================================================================

    public function render(): View
    {
        $jour = $this->jourAffiche();

        $plannings = Planning::query()
            ->with(['employe', 'service'])
            ->whereDate('date', $jour->toDateString())
            ->when($this->service !== '', fn ($q) => $q->where('service_id', $this->service))
            ->orderBy('heure_debut')
            ->get();

        $conges = Conge::query()
            ->with(['employe.service', 'validateur'])
            ->when(
                in_array($this->statutConge, [Conge::STATUT_EN_ATTENTE, Conge::STATUT_VALIDE, Conge::STATUT_REFUSE], true),
                fn ($q) => $q->where('statut_validation', $this->statutConge),
            )
            ->orderByDesc('date_debut')
            ->get();

        return view('pwa.rh.conges-plannings', array_merge($this->socle(), [
            'onglet' => in_array($this->onglet, self::ONGLETS, true) ? $this->onglet : 'plannings',
            'jourAffiche' => $jour,
            'plannings' => $plannings,
            'conges' => $conges,
            'services' => app(EmployeService::class)->services(),
            'employesEnPoste' => Employe::query()
                ->whereIn('statut', ['actif', 'conge'])
                ->orderBy('nom')
                ->get(),
            'typesConge' => Conge::TYPES,
            'enAttente' => $conges->where('statut_validation', Conge::STATUT_EN_ATTENTE)->count(),
            'enCongeAujourdhui' => Conge::query()
                ->where('statut_validation', Conge::STATUT_VALIDE)
                ->whereDate('date_debut', '<=', CarbonImmutable::today()->toDateString())
                ->whereDate('date_fin', '>=', CarbonImmutable::today()->toDateString())
                ->count(),
            'peutEcrire' => auth()->user()?->niveauSurModule(self::MODULE) === 'C',
        ]));
    }

    private function jourAffiche(): CarbonImmutable
    {
        // Un jour illisible ou impossible (saisie forgée dans l'adresse) retombe
        // sur aujourd'hui : jamais une erreur 500.
        if (preg_match('/^(\d{4})-(\d{2})-(\d{2})$/', $this->jour, $m) !== 1
            || ! checkdate((int) $m[2], (int) $m[3], (int) $m[1])) {
            return CarbonImmutable::today();
        }

        return CarbonImmutable::create((int) $m[1], (int) $m[2], (int) $m[3]);
    }
}
