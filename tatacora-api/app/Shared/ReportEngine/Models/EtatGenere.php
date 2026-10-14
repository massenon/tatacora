<?php

declare(strict_types=1);

namespace App\Shared\ReportEngine\Models;

use App\Models\User;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Archivage horodaté de tout état généré — EF-M14-06.
 *
 * Distincte de `journal_audit` volontairement : « volume et cycle de rétention
 * différents » (`05_MODULE_SPECIFICATIONS.md` §M14). Un état consulté cent fois
 * par jour saturerait le journal d'audit métier, dont la valeur probante tient
 * précisément à sa lisibilité.
 *
 * @property string $id
 * @property string $module
 * @property string $nom_etat
 * @property array<string, string> $filtres_appliques
 * @property string $utilisateur_id
 * @property \Illuminate\Support\Carbon $date_edition
 * @property string $format
 * @property string|null $chemin_fichier_archive
 */
class EtatGenere extends Model
{
    use HasUuids;

    protected $table = 'etats_generes';

    protected $fillable = [
        'id', 'module', 'nom_etat', 'filtres_appliques',
        'utilisateur_id', 'date_edition', 'format', 'chemin_fichier_archive',
    ];

    protected function casts(): array
    {
        return [
            'filtres_appliques' => 'array',
            'date_edition' => 'datetime',
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
