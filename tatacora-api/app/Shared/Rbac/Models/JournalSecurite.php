<?php

declare(strict_types=1);

namespace App\Shared\Rbac\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Journal des tentatives d'intrusion — SECURITY_STRICT.md §10.
 *
 * Volontairement distinct de `journal_audit` : celui-ci trace les actions
 * métier légitimes (RG-15), celui-là les connexions échouées, accès RBAC
 * refusés et tentatives d'URL directe.
 */
class JournalSecurite extends Model
{
    use HasUuids;

    protected $table = 'journal_securite';

    public $timestamps = false;

    protected $fillable = [
        'id',
        'type_evenement',
        'login_tente',
        'utilisateur_id',
        'adresse_ip',
        'module_concerne',
    ];

    protected function casts(): array
    {
        return ['date_heure' => 'datetime'];
    }
}
