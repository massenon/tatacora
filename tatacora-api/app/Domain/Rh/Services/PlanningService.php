<?php

declare(strict_types=1);

namespace App\Domain\Rh\Services;

use App\Domain\Rh\Models\Conge;
use App\Domain\Rh\Models\Employe;
use App\Domain\Rh\Models\Planning;
use App\Shared\Integrite\Services\VerificationChevauchementService;
use RuntimeException;

/**
 * Planification des équipes — EF-M13-02, RG-13.
 *
 * @see EF-M13-02
 * @see RG-13 Non-double-affectation d'un employé
 *
 * > « Un employé ne peut être planifié sur deux services simultanément sur un
 * > même créneau horaire. »
 *
 * ## Troisième usage du même verrou
 *
 * `05_MODULE_SPECIFICATIONS.md` §M13 : « RG-13,
 * `VerificationChevauchementService` sur `plannings` ». C'est le même service
 * que RG-01 (hébergement) et RG-08 (véhicules) — la ressource verrouillée
 * étant ici l'**employé**, et non une unité ou un véhicule.
 *
 * La différence, qui a demandé une extension du service partagé : un créneau
 * porte une `date` **et** des heures. Sans filtre sur la date, deux créneaux
 * 08h–12h à deux jours différents seraient vus comme un conflit.
 *
 * ## Un employé en congé validé n'est pas planifiable
 *
 * Règle dérivée, non énoncée par RG-13, mais nécessaire : planifier quelqu'un
 * dont l'absence est déjà validée produit un planning que personne ne pourra
 * tenir. Elle est appliquée ici et tracée en PA-53.
 */
class PlanningService
{
    /** `plannings` n'a aucune colonne `statut` : rien à exclure. */
    private const STATUTS_INACTIFS = [];

    public function __construct(
        private readonly VerificationChevauchementService $chevauchement,
    ) {
    }

    /**
     * @param  array{employe_id: string, service_id: string, date: string, heure_debut: string, heure_fin: string, id?: string}  $donnees
     *
     * @throws \App\Shared\Integrite\Exceptions\ChevauchementDetecteException
     * @throws RuntimeException si l'employé est absent ou en congé validé
     */
    public function planifier(array $donnees): Planning
    {
        $employe = Employe::findOrFail($donnees['employe_id']);

        $this->verifierEmployeEnPoste($employe);
        $this->verifierAbsenceDeConge($employe->id, $donnees['date']);

        return $this->chevauchement->executerSousVerrou(
            tablePlages: 'plannings',
            // La ressource verrouillée est l'EMPLOYÉ : c'est lui qui ne peut
            // pas être à deux endroits, pas le service.
            tableRessource: 'employes',
            colonneRessource: 'employe_id',
            ressourceId: $employe->id,
            colonneDebut: 'heure_debut',
            colonneFin: 'heure_fin',
            debut: $donnees['heure_debut'],
            fin: $donnees['heure_fin'],
            ecriture: fn (): Planning => Planning::create($donnees)->refresh(),
            statutsInactifs: self::STATUTS_INACTIFS,
            messageConflit: __('rh.planning_chevauchement'),
            // Le chevauchement ne vaut qu'à l'intérieur d'une même journée.
            filtresSupplementaires: ['date' => $donnees['date']],
        );
    }

    /**
     * L'employé est-il libre sur ce créneau ? Lecture sans verrou, destinée à
     * l'affichage d'un planning — ne remplace jamais `planifier()`.
     */
    public function estLibre(
        string $employeId,
        string $date,
        string $heureDebut,
        string $heureFin,
        ?string $exclureId = null,
    ): bool {
        return $this->chevauchement->plagesEnConflit(
            tablePlages: 'plannings',
            colonneRessource: 'employe_id',
            ressourceId: $employeId,
            colonneDebut: 'heure_debut',
            colonneFin: 'heure_fin',
            debut: $heureDebut,
            fin: $heureFin,
            statutsInactifs: self::STATUTS_INACTIFS,
            exclureId: $exclureId,
            filtresSupplementaires: ['date' => $date],
        ) === [];
    }

    /**
     * Effectif planifié sur un service à une date — base de RG-14.
     */
    public function effectifPlanifie(string $serviceId, string $date): int
    {
        return Planning::query()
            ->where('service_id', $serviceId)
            ->whereDate('date', $date)
            ->distinct()
            ->count('employe_id');
    }

    private function verifierEmployeEnPoste(Employe $employe): void
    {
        if (! $employe->estEnPoste()) {
            throw new RuntimeException(__('rh.employe_hors_effectif', [
                'statut' => $employe->statut,
            ]));
        }
    }

    /**
     * @throws RuntimeException si un congé validé couvre la date visée
     */
    private function verifierAbsenceDeConge(string $employeId, string $date): void
    {
        $enConge = Conge::query()
            ->where('employe_id', $employeId)
            ->where('statut_validation', Conge::STATUT_VALIDE)
            // Bornes INCLUSES : un congé du 10 au 12 couvre bien le 12.
            ->whereDate('date_debut', '<=', $date)
            ->whereDate('date_fin', '>=', $date)
            ->exists();

        if ($enConge) {
            throw new RuntimeException(__('rh.employe_en_conge', ['date' => $date]));
        }
    }
}
