<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Models;

use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Ligne de comptage — EF-M6-05.
 *
 * `quantite_theorique` est FIGEE a l'ouverture de l'inventaire : la recalculer
 * a la cloture donnerait un ecart faux si un mouvement survient pendant le
 * comptage, ce qui est le cas des qu'un comptage dure une matinee.
 *
 * `quantite_constatee` est nullable tant que l'article n'a pas ete compte —
 * distinguer « non compte » de « compte a zero » est essentiel : le second est
 * une rupture, le premier un oubli.
 *
 * @property string $id
 * @property string $inventaire_id
 * @property string $article_id
 * @property string $quantite_theorique
 * @property string|null $quantite_constatee
 * @property string|null $ecart
 * @property-read Article $article
 */
class LigneInventaire extends Model
{
    use Auditable;
    use HasUuids;

    protected $table = 'lignes_inventaire';

    protected $fillable = [
        'id', 'inventaire_id', 'article_id',
        'quantite_theorique', 'quantite_constatee', 'ecart',
    ];

    protected function casts(): array
    {
        return [
            'quantite_theorique' => 'decimal:2',
            'quantite_constatee' => 'decimal:2',
            'ecart' => 'decimal:2',
        ];
    }

    /**
     * @return BelongsTo<Inventaire, $this>
     */
    public function inventaire(): BelongsTo
    {
        return $this->belongsTo(Inventaire::class, 'inventaire_id');
    }

    /**
     * @return BelongsTo<Article, $this>
     */
    public function article(): BelongsTo
    {
        return $this->belongsTo(Article::class, 'article_id');
    }
}
