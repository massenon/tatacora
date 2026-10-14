<?php

declare(strict_types=1);

namespace App\Domain\Notifications\Models;

use App\Models\User;
use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Un message COMPOSÉ — file d'attente ou journal, selon `statut`.
 *
 * @see \App\Domain\Notifications\Services\DetectionNotificationsService
 *
 * @property string $id
 * @property string $modele_id
 * @property string $canal
 * @property string $reference
 * @property string $destinataire
 * @property string|null $email_destinataire
 * @property string|null $objet
 * @property string $contenu
 * @property int $longueur
 * @property string $statut
 * @property string|null $commentaire
 * @property string|null $motif_abandon
 * @property string|null $utilisateur_modification_id
 * @property \Illuminate\Support\Carbon|null $date_modification
 * @property-read ModeleNotification $modele
 * @property-read User|null $traitePar
 */
class MessageNotificationCompose extends Model
{
    use Auditable;
    use HasUuids;

    protected $table = 'notifications_composees';

    public const STATUT_EN_ATTENTE = 'en_attente';

    public const STATUT_TRAITE_MANUELLEMENT = 'traite_manuellement';

    public const STATUT_ABANDONNE = 'abandonne';

    /**
     * Un message RÉELLEMENT parti par e-mail — troisième sort, distinct des
     * deux gestes manuels. Voir la migration `2026_09_05_100000` pour le
     * pourquoi de ce troisième état.
     */
    public const STATUT_ENVOYE = 'envoye';

    protected $fillable = [
        'id',
        'modele_id',
        'canal',
        'reference',
        'destinataire',
        'email_destinataire',
        'objet',
        'contenu',
        'longueur',
        'statut',
        'commentaire',
        'motif_abandon',
    ];

    protected function casts(): array
    {
        return [
            'longueur' => 'integer',
            'date_creation' => 'datetime',
            'date_modification' => 'datetime',
        ];
    }

    /**
     * @return BelongsTo<ModeleNotification, $this>
     */
    public function modele(): BelongsTo
    {
        return $this->belongsTo(ModeleNotification::class, 'modele_id');
    }

    /**
     * Qui a transmis à la main ou abandonné — les colonnes d'audit du dépôt,
     * jamais une seconde colonne dédiée (voir le docblock de la migration).
     *
     * @return BelongsTo<User, $this>
     */
    public function traitePar(): BelongsTo
    {
        return $this->belongsTo(User::class, 'utilisateur_modification_id');
    }

    public function enAttente(): bool
    {
        return $this->statut === self::STATUT_EN_ATTENTE;
    }
}
