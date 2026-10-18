<?php

declare(strict_types=1);

namespace App\Shared\Sync\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Ce que le serveur sait d'un poste : sa dernière descente, ce qu'il déclare
 * en attente d'envoi, la dernière demande qu'il a lue. Écrit par
 * `SuiviPostesService` seul.
 */
class EtatPosteSynchronisation extends Model
{
    use HasUuids;

    protected $table = 'etats_postes_synchronisation';

    protected $fillable = ['poste_id', 'utilisateur_id', 'derniere_descente_le', 'en_attente', 'demande_lue_le'];

    protected function casts(): array
    {
        return [
            'derniere_descente_le' => 'datetime',
            'demande_lue_le' => 'datetime',
            'en_attente' => 'integer',
        ];
    }
}
