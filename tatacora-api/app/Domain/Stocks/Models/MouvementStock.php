<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Models;

use App\Models\User;
use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Toute entree/sortie de stock — la SEULE source de verite du stock (M6).
 *
 * Table en ajout seul par conception : un mouvement errone se corrige par un
 * mouvement inverse, jamais par une modification ou une suppression. C'est ce
 * qui rend l'historique de stock opposable lors d'un inventaire.
 *
 * @see RG-15 Tracabilite integrale
 *
 * @property string $id
 * @property string $article_id
 * @property string $point_id
 * @property string $type_mouvement
 * @property string $quantite
 * @property string|null $motif
 * @property string|null $utilisateur_id
 * @property \Illuminate\Support\Carbon $date_mouvement
 */
class MouvementStock extends Model
{
    use Auditable;
    use HasUuids;

    protected $table = 'mouvements_stock';

    protected $fillable = [
        'id', 'article_id', 'point_id', 'type_mouvement',
        'quantite', 'motif', 'utilisateur_id', 'date_mouvement',
    ];

    protected function casts(): array
    {
        return [
            'quantite' => 'decimal:2',
            'date_mouvement' => 'datetime',
        ];
    }

    /**
     * @return BelongsTo<Article, $this>
     */
    public function article(): BelongsTo
    {
        return $this->belongsTo(Article::class, 'article_id');
    }

    /**
     * @return BelongsTo<PointStockage, $this>
     */
    public function point(): BelongsTo
    {
        return $this->belongsTo(PointStockage::class, 'point_id');
    }

    /**
     * @return BelongsTo<User, $this>
     */
    public function utilisateur(): BelongsTo
    {
        return $this->belongsTo(User::class, 'utilisateur_id');
    }
}
