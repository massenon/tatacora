<?php

declare(strict_types=1);

namespace App\Domain\Rh\Models;

use App\Models\User;
use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Demande de congé ou d'absence — EF-M13-04.
 *
 * @see EF-M13-04 Congés et absences avec workflow de validation
 * @see RG-14 Délai de préavis et couverture minimale
 *
 * Le workflow est porté par `statut_validation`
 * (`en_attente` → `valide` | `refuse`). Une demande refusée **conserve sa
 * trace** : un employé dont le congé a été refusé doit pouvoir le prouver.
 *
 * @property string $id
 * @property string $employe_id
 * @property string $type
 * @property \Illuminate\Support\Carbon $date_debut
 * @property \Illuminate\Support\Carbon $date_fin
 * @property string $statut_validation
 * @property string|null $validateur_id
 * @property-read Employe $employe
 */
class Conge extends Model
{
    use Auditable;
    use HasUuids;

    /** Seuls les congés validés consomment de la couverture de service. */
    public const STATUT_VALIDE = 'valide';

    public const STATUT_EN_ATTENTE = 'en_attente';

    public const STATUT_REFUSE = 'refuse';

    /**
     * Les natures d'absence — registre FERMÉ (21/10/2026), relu par la PWA, le
     * poste et la synchronisation : `type` n'est pas du texte libre.
     *
     * @var list<string>
     */
    public const TYPES = ['annuel', 'maladie', 'exceptionnel', 'maternite'];

    protected $table = 'conges';

    protected $fillable = [
        'id', 'employe_id', 'type', 'date_debut', 'date_fin',
        'statut_validation', 'validateur_id',
    ];

    protected function casts(): array
    {
        return [
            'date_debut' => 'date',
            'date_fin' => 'date',
        ];
    }

    /**
     * Nombre de jours d'absence — CALCULÉ, jamais stocké.
     *
     * Bornes **incluses** : un congé du 10 au 10 dure un jour, pas zéro. Ce
     * n'est pas la même convention que RG-01 (bornes semi-ouvertes sur des
     * nuitées) — une nuitée se compte entre deux dates, un jour d'absence se
     * compte sur la date elle-même.
     */
    public function nombreJours(): int
    {
        return (int) $this->date_debut->diffInDays($this->date_fin) + 1;
    }

    public function estValide(): bool
    {
        return $this->statut_validation === self::STATUT_VALIDE;
    }

    /**
     * Préavis effectivement respecté, en jours, à la date de référence donnée.
     */
    public function preavisEnJours(\Illuminate\Support\Carbon $reference): int
    {
        return (int) $reference->startOfDay()->diffInDays($this->date_debut->startOfDay(), false);
    }

    /**
     * @return BelongsTo<Employe, $this>
     */
    public function employe(): BelongsTo
    {
        return $this->belongsTo(Employe::class, 'employe_id');
    }

    /**
     * @return BelongsTo<User, $this>
     */
    public function validateur(): BelongsTo
    {
        return $this->belongsTo(User::class, 'validateur_id');
    }
}
