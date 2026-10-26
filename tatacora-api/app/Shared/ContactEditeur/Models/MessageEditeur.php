<?php

declare(strict_types=1);

namespace App\Shared\ContactEditeur\Models;

use App\Models\User;
use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Un envoi vers l'éditeur — message libre ou signalement de bug.
 *
 * @see \App\Shared\ContactEditeur\Services\MessageEditeurService
 *
 * @property string $id
 * @property string $type
 * @property string $objet
 * @property string|null $module_concerne
 * @property string $corps
 * @property string|null $etapes
 * @property string|null $capture_nom
 * @property string|null $capture_chemin
 * @property string $statut
 * @property int $tentatives
 * @property string|null $derniere_erreur
 * @property \Illuminate\Support\Carbon|null $derniere_tentative_le
 * @property \Illuminate\Support\Carbon|null $envoye_le
 * @property string|null $utilisateur_creation_id
 * @property \Illuminate\Support\Carbon|null $date_creation
 * @property-read User|null $auteur
 */
class MessageEditeur extends Model
{
    use Auditable;
    use HasUuids;

    protected $table = 'messages_editeur';

    /** Les deux valeurs du registre fermé `type` — jamais une troisième devinée. */
    public const TYPE_MESSAGE = 'message';

    public const TYPE_BUG = 'bug';

    public const STATUT_A_TRANSMETTRE = 'a_transmettre';

    public const STATUT_TRANSMIS = 'transmis';

    /** Au-delà, la relance horaire s'arrête ; « Renvoyer » (poste) ou la commande reprend. */
    public const TENTATIVES_MAX = 5;

    protected $fillable = [
        'id',
        'type',
        'objet',
        'module_concerne',
        'corps',
        'etapes',
        'capture_nom',
        'capture_chemin',
        'statut',
    ];

    protected function casts(): array
    {
        return [
            'tentatives' => 'integer',
            'derniere_tentative_le' => 'datetime',
            'envoye_le' => 'datetime',
            'date_creation' => 'datetime',
            'date_modification' => 'datetime',
        ];
    }

    /**
     * @return BelongsTo<User, $this>
     */
    public function auteur(): BelongsTo
    {
        return $this->belongsTo(User::class, 'utilisateur_creation_id');
    }

    public function estTransmis(): bool
    {
        return $this->statut === self::STATUT_TRANSMIS;
    }
}
