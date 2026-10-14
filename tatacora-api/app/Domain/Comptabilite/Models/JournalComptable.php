<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Journal comptable (M10) — VTE, ACH, BQ, CAI, OD.
 *
 * @see EF-M10-06 Edition des etats reglementaires SYSCOHADA
 *
 * ## Pourquoi une route sert ce referentiel plutot que le client
 *
 * `m10-journal.html` l.73 ecrit ses trois journaux EN DUR
 * (`const JOURNAUX = { VTE, ACH, OD }`), la ou le schema et
 * `MODULE_COMPTABILITE_COMPLET.md` §2 en nomment cinq. Recopier cette liste
 * dans le client en ferait une deuxieme source de verite, qui divergerait au
 * premier journal ajoute : le filtre proposerait un code que la base ne connait
 * pas, ou tairait un journal reellement mouvemente. Une meme donnee, une seule
 * source (Article 10 de `DIRECTIVE_CONFORMITE_100.md`).
 *
 * @property string $id
 * @property string $code
 * @property string $libelle
 */
class JournalComptable extends Model
{
    use HasUuids;

    protected $table = 'journaux_comptables';

    protected $fillable = ['id', 'code', 'libelle'];

    /**
     * @return HasMany<EcritureComptable, $this>
     */
    public function ecritures(): HasMany
    {
        return $this->hasMany(EcritureComptable::class, 'journal_id');
    }
}
