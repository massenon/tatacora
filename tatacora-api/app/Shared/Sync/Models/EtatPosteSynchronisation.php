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

    protected $fillable = ['poste_id', 'utilisateur_id', 'derniere_descente_le', 'en_attente', 'demande_lue_le', 'dernier_controle_le',
        // Journal d'envoi (26/10/2026) : curseur rendu, redescente demandée, 409 « génération périmée ».
        'curseur_descente', 'descente_complete', 'descente_complete_le', 'redescente_demandee_le',
        'redescente_demandee_par', 'redescente_faite_le', 'generation_perimee_le', 'generation_perimee_nb',
    ];

    protected function casts(): array
    {
        return [
            'derniere_descente_le' => 'datetime',
            'demande_lue_le' => 'datetime',
            'dernier_controle_le' => 'datetime',
            'en_attente' => 'integer',
            'descente_complete' => 'boolean',
            'descente_complete_le' => 'datetime',
            'redescente_demandee_le' => 'datetime',
            'redescente_faite_le' => 'datetime',
            'generation_perimee_le' => 'datetime',
            'generation_perimee_nb' => 'integer',
        ];
    }
}
