<?php

declare(strict_types=1);

namespace App\Domain\Rh\Services;

use App\Domain\Rh\Models\Conge;
use App\Domain\Rh\Models\Employe;
use App\Models\User;
use App\Shared\Parametres\Services\ParametreSystemeService;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Workflow de validation des congés — EF-M13-04, RG-14.
 *
 * @see EF-M13-04 Congés et absences avec workflow de validation
 * @see RG-14 Délai de préavis et couverture minimale
 *
 * > « Une demande de congé ne peut être validée sans respect du délai de
 * > préavis paramétré et de la couverture minimale du service concerné. »
 *
 * ## Les deux seuils sont paramétrés, jamais devinés
 *
 * `01_BUSINESS_ANALYSIS_SPEC.md` §RG-14 nomme explicitement les deux
 * paramètres. Aucun repli n'est fourni : sans valeur configurée, la validation
 * **refuse** plutôt que de laisser passer — même discipline que la tolérance
 * de réception (RG-10) et le taux de TVA. Un délai de préavis deviné ferait
 * accepter ou refuser des congés sur un critère que personne n'a décidé.
 *
 * ## La demande reste possible, c'est la VALIDATION qui est conditionnée
 *
 * RG-14 porte sur « validée », pas sur « déposée ». Un employé peut déposer
 * une demande hors délai — c'est au responsable de la refuser en connaissance
 * de cause, pas au système d'empêcher l'expression du besoin.
 */
class CongeService
{
    public const CLE_PREAVIS = 'delai_preavis_conge_jours';

    public const CLE_COUVERTURE = 'couverture_minimale_par_service';

    public function __construct(
        private readonly ParametreSystemeService $parametres,
    ) {
    }

    /**
     * Dépôt d'une demande — toujours accepté, jamais pré-filtré.
     *
     * @param  array{employe_id: string, type: string, date_debut: string, date_fin: string, id?: string}  $donnees
     */
    public function demander(array $donnees): Conge
    {
        $employe = Employe::findOrFail($donnees['employe_id']);

        if (! $employe->estEnPoste()) {
            throw new RuntimeException(__('rh.employe_hors_effectif', ['statut' => $employe->statut]));
        }

        return Conge::create([
            ...$donnees,
            'statut_validation' => Conge::STATUT_EN_ATTENTE,
        ])->refresh();
    }

    /**
     * Validation — RG-14 s'applique ICI.
     *
     * @throws RuntimeException préavis insuffisant, couverture compromise, ou paramètre absent
     */
    public function valider(Conge $conge, User $validateur, ?Carbon $reference = null): Conge
    {
        if ($conge->statut_validation !== Conge::STATUT_EN_ATTENTE) {
            throw new RuntimeException(__('rh.conge_deja_traite'));
        }

        $this->verifierPreavis($conge, $reference ?? Carbon::now());
        $this->verifierCouverture($conge);

        return DB::transaction(function () use ($conge, $validateur): Conge {
            $conge->update([
                'statut_validation' => Conge::STATUT_VALIDE,
                'validateur_id' => $validateur->id,
            ]);

            return $conge->refresh();
        });
    }

    /**
     * Refus — conserve la trace, ne supprime jamais la demande.
     */
    public function refuser(Conge $conge, User $validateur): Conge
    {
        if ($conge->statut_validation !== Conge::STATUT_EN_ATTENTE) {
            throw new RuntimeException(__('rh.conge_deja_traite'));
        }

        $conge->update([
            'statut_validation' => Conge::STATUT_REFUSE,
            'validateur_id' => $validateur->id,
        ]);

        return $conge->refresh();
    }

    /**
     * Nombre d'employés du service déjà absents sur au moins un jour de la
     * période demandée.
     *
     * Le chevauchement se calcule en bornes **incluses** : un congé du 10 au
     * 12 et un autre du 12 au 15 se recoupent bien sur le 12, et laissent donc
     * le service à découvert ce jour-là.
     */
    public function absentsSurPeriode(string $serviceId, string $debut, string $fin, ?string $exclureId = null): int
    {
        return Conge::query()
            ->where('statut_validation', Conge::STATUT_VALIDE)
            ->whereHas('employe', fn ($q) => $q->where('service_id', $serviceId))
            ->when($exclureId !== null, fn ($q) => $q->where('id', '!=', $exclureId))
            ->whereDate('date_debut', '<=', $fin)
            ->whereDate('date_fin', '>=', $debut)
            ->distinct()
            ->count('employe_id');
    }

    // ------------------------------------------------------------ Contrôles

    private function verifierPreavis(Conge $conge, Carbon $reference): void
    {
        $preavisExige = $this->parametreObligatoire(self::CLE_PREAVIS);
        $preavisReel = $conge->preavisEnJours($reference);

        if ($preavisReel < (int) $preavisExige) {
            throw new RuntimeException(__('rh.preavis_insuffisant', [
                'exige' => $preavisExige,
                'reel' => max(0, $preavisReel),
            ]));
        }
    }

    /**
     * La couverture minimale s'apprécie sur l'effectif **restant en poste**,
     * congés validés déduits — c'est le nombre de personnes réellement
     * présentes qui fait tourner un service, pas l'effectif théorique.
     */
    private function verifierCouverture(Conge $conge): void
    {
        $minimum = (int) $this->parametreObligatoire(self::CLE_COUVERTURE);

        $serviceId = $conge->employe->service_id;

        $effectif = Employe::query()
            ->where('service_id', $serviceId)
            ->where('statut', 'actif')
            ->count();

        // +1 : la demande en cours de validation compte parmi les absents.
        $absents = $this->absentsSurPeriode(
            $serviceId,
            $conge->date_debut->toDateString(),
            $conge->date_fin->toDateString(),
            $conge->id,
        ) + 1;

        $restants = $effectif - $absents;

        if ($restants < $minimum) {
            throw new RuntimeException(__('rh.couverture_insuffisante', [
                'restants' => max(0, $restants),
                'minimum' => $minimum,
            ]));
        }
    }

    /**
     * Refus explicite si le paramètre n'est pas configuré.
     *
     * Même discipline que `ReceptionService::tolerancePourcentage()` : un
     * seuil deviné ferait accepter ou refuser des congés sur un critère
     * arbitraire, et personne ne s'en apercevrait avant un conflit social.
     */
    private function parametreObligatoire(string $cle): string
    {
        $valeur = $this->parametres->get($cle);

        if (blank($valeur)) {
            throw new RuntimeException(__('rh.parametre_absent', ['cle' => $cle]));
        }

        return $valeur;
    }
}
