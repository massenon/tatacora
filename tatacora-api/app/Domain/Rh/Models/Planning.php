<?php

declare(strict_types=1);

namespace App\Domain\Rh\Models;

use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Créneau de planning d'un employé — EF-M13-02.
 *
 * @see EF-M13-02 Planification des équipes et horaires par service
 * @see RG-13 Non-double-affectation d'un employé
 *
 * ## Le créneau est (date, heure_debut, heure_fin), pas un intervalle unique
 *
 * Le chevauchement se joue donc sur les **heures**, mais seulement à
 * l'intérieur d'une même journée : deux créneaux 08h–12h à deux dates
 * différentes ne se chevauchent évidemment pas. C'est la raison d'être du
 * paramètre `filtresSupplementaires` ajouté à
 * `VerificationChevauchementService` — plutôt que de dupliquer le verrou.
 *
 * ## Aucune colonne `statut` — même famille que PA-50
 *
 * Un créneau saisi par erreur ne peut être ni annulé ni marqué inactif. Il
 * n'existe donc aucun équivalent de RG-02 ici, et `PlanningService` n'expose
 * volontairement aucune méthode d'annulation.
 *
 * @property string $id
 * @property string $employe_id
 * @property string $service_id
 * @property \Illuminate\Support\Carbon $date
 * @property string $heure_debut
 * @property string $heure_fin
 */
class Planning extends Model
{
    use Auditable;
    use HasUuids;

    protected $table = 'plannings';

    protected $fillable = ['id', 'employe_id', 'service_id', 'date', 'heure_debut', 'heure_fin'];

    protected function casts(): array
    {
        return ['date' => 'date'];
    }

    /**
     * @return BelongsTo<Employe, $this>
     */
    public function employe(): BelongsTo
    {
        return $this->belongsTo(Employe::class, 'employe_id');
    }

    /**
     * @return BelongsTo<Service, $this>
     */
    public function service(): BelongsTo
    {
        return $this->belongsTo(Service::class, 'service_id');
    }
}
