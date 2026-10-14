<?php

declare(strict_types=1);

namespace App\Shared\Audit\Models;

use App\Models\User;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Journal d'audit de toute action sensible — RG-15.
 *
 * Alimenté EXCLUSIVEMENT par le trait Auditable, jamais par une écriture
 * manuelle depuis un contrôleur (03_DATABASE_ENGINEERING.md §13).
 *
 * La durée de rétention contractuelle n'est pas encore tranchée (PA-08) :
 * `PurgerJournalAuditJob` reste désactivé tant que le Product Owner n'a pas
 * statué — jamais activé par défaut avec une valeur arbitraire.
 *
 * @property string $id
 * @property string|null $utilisateur_id
 * @property string $action
 * @property string $entite_concernee
 * @property string $entite_id
 * @property array<string, mixed>|null $valeur_avant
 * @property array<string, mixed>|null $valeur_apres
 * @property \Illuminate\Support\Carbon $date_heure
 * @property string|null $adresse_poste
 */
class JournalAudit extends Model
{
    use HasUuids;

    protected $table = 'journal_audit';

    public $timestamps = false;

    protected $fillable = [
        'id',
        'utilisateur_id',
        'action',
        'entite_concernee',
        'entite_id',
        'valeur_avant',
        'valeur_apres',
        'adresse_poste',
    ];

    protected function casts(): array
    {
        return [
            'valeur_avant' => 'array',
            'valeur_apres' => 'array',
            'date_heure' => 'datetime',
        ];
    }

    /**
     * @return BelongsTo<User, $this>
     */
    public function utilisateur(): BelongsTo
    {
        return $this->belongsTo(User::class, 'utilisateur_id');
    }
}
