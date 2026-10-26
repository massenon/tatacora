<?php

declare(strict_types=1);

namespace App\Shared\Sync\Models;

use App\Models\User;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Une opération REÇUE d'un poste par `POST /api/v1/sync`, avec son issue et sa
 * cause. Écrite UNIQUEMENT par `JournalReceptionService` (réception) et
 * `CorrectionReceptionService` (corriger, relancer, ignorer).
 *
 * @property string $id
 * @property string $uuid_operation
 * @property string|null $session_id
 * @property string $poste_id
 * @property string|null $utilisateur_id
 * @property string $table_concernee
 * @property string $entite_id
 * @property string $type_operation
 * @property \Illuminate\Support\Carbon|null $horodatage_poste
 * @property \Illuminate\Support\Carbon $recu_le
 * @property string $issue
 * @property string|null $code_motif
 * @property string|null $motif
 * @property string|null $cause
 * @property array<string, mixed>|null $details
 * @property int $tentatives
 * @property \Illuminate\Support\Carbon $derniere_tentative_le
 * @property array<string, mixed>|null $payload
 * @property array<string, mixed>|null $payload_corrige
 * @property string|null $traitement
 * @property string|null $traite_par
 * @property \Illuminate\Support\Carbon|null $traite_le
 * @property string|null $motif_traitement
 * @property string|null $operation_relance_id
 */
class JournalReceptionSynchronisation extends Model
{
    use HasUuids;

    public const ACCEPTEE = 'acceptee';

    public const FUSIONNEE = 'fusionnee';

    public const DUPLIQUEE = 'dupliquee';

    public const SIGNALEE = 'signalee';

    public const CONSERVEE = 'conservee';

    public const CONFLIT = 'conflit';

    public const REJETEE = 'rejetee';

    public const ERREUR = 'erreur';

    /** Les issues qui attendent un humain (rejet, conflit, erreur, signalement). */
    public const ISSUES_A_TRAITER = [self::REJETEE, self::CONFLIT, self::ERREUR, self::SIGNALEE];

    public const A_TRAITER = 'a_traiter';

    public const CORRIGE = 'corrige';

    public const RELANCE = 'relance';

    public const IGNORE = 'ignore';

    protected $table = 'journal_reception_synchronisation';

    protected $fillable = [
        'id', 'uuid_operation', 'session_id', 'poste_id', 'utilisateur_id', 'table_concernee', 'entite_id',
        'type_operation', 'horodatage_poste', 'recu_le', 'issue', 'code_motif', 'motif', 'cause', 'details',
        'tentatives', 'derniere_tentative_le', 'payload', 'payload_corrige', 'traitement', 'traite_par',
        'traite_le', 'motif_traitement', 'operation_relance_id',
    ];

    protected function casts(): array
    {
        return [
            'horodatage_poste' => 'datetime',
            'recu_le' => 'datetime',
            'derniere_tentative_le' => 'datetime',
            'traite_le' => 'datetime',
            'details' => 'array',
            'payload' => 'array',
            'payload_corrige' => 'array',
            'tentatives' => 'integer',
        ];
    }

    /** @return BelongsTo<User, $this> */
    public function utilisateur(): BelongsTo
    {
        return $this->belongsTo(User::class, 'utilisateur_id');
    }

    /** @return BelongsTo<User, $this> */
    public function traitePar(): BelongsTo
    {
        return $this->belongsTo(User::class, 'traite_par');
    }

    /** Une issue qui attend un humain et n'a pas encore été prise en charge. */
    public function estATraiter(): bool
    {
        return $this->traitement === self::A_TRAITER || $this->traitement === self::CORRIGE;
    }
}
