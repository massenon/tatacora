<?php

declare(strict_types=1);

namespace App\Shared\ImportExport\Models;

use App\Models\User;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Une entrée de l'« Historique des imports » — un LOT confirmé, jamais une
 * ligne (le trait `Auditable` trace déjà chaque fiche créée, une par une).
 *
 * Maître : `import-export.html` colonne latérale de l'onglet 1, et
 * `import-export-engine.js` §3 (`historiserImport`).
 *
 * Écrite exclusivement par `ImportReferentielsService::appliquer()`, dans la
 * MÊME transaction que l'import : un historique écrit hors transaction
 * annoncerait un import qu'un rollback a effacé (PA-59/60/61).
 *
 * @property string $id
 * @property string $module_cle
 * @property int $nombre_lignes
 * @property string|null $utilisateur_id
 * @property \Illuminate\Support\Carbon $date_heure
 */
class JournalImport extends Model
{
    use HasUuids;

    protected $table = 'journal_imports';

    public $timestamps = false;

    protected $fillable = ['id', 'module_cle', 'nombre_lignes', 'utilisateur_id', 'date_heure'];

    protected function casts(): array
    {
        return [
            'nombre_lignes' => 'integer',
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
