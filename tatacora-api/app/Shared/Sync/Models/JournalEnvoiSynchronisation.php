<?php

declare(strict_types=1);

namespace App\Shared\Sync\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Ce que le serveur a livré à UN poste pour UNE table, par le flux
 * `GET /api/v1/referentiels`. Écrite UNIQUEMENT par `JournalEnvoiService`.
 *
 * @property string $id
 * @property string $poste_id
 * @property string $table_concernee
 * @property int $livres_total
 * @property int $dernier_passage_nb
 * @property \Illuminate\Support\Carbon|null $derniere_livraison_le
 * @property int $en_attente_droits
 * @property \Illuminate\Support\Carbon|null $droits_constates_le
 */
class JournalEnvoiSynchronisation extends Model
{
    use HasUuids;

    protected $table = 'journal_envoi_synchronisation';

    protected $fillable = [
        'poste_id', 'table_concernee', 'livres_total', 'dernier_passage_nb', 'derniere_livraison_le',
        'en_attente_droits', 'droits_constates_le',
    ];

    protected function casts(): array
    {
        return [
            'livres_total' => 'integer',
            'dernier_passage_nb' => 'integer',
            'en_attente_droits' => 'integer',
            'derniere_livraison_le' => 'datetime',
            'droits_constates_le' => 'datetime',
        ];
    }
}
