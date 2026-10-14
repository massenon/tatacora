<?php

declare(strict_types=1);

namespace App\Domain\Achats\Models;

use App\Domain\Stocks\Models\Article;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Ligne de commande d'achat (M7).
 *
 * @property string $id
 * @property string $commande_id
 * @property string $article_id
 * @property string $quantite_commandee
 * @property string $prix_unitaire
 */
class LigneCommandeAchat extends Model
{
    use HasUuids;

    protected $table = 'lignes_commande_achat';

    protected $fillable = ['id', 'commande_id', 'article_id', 'quantite_commandee', 'prix_unitaire'];

    protected function casts(): array
    {
        return ['quantite_commandee' => 'decimal:2', 'prix_unitaire' => 'decimal:2'];
    }

    /**
     * @return BelongsTo<Article, $this>
     */
    public function article(): BelongsTo
    {
        return $this->belongsTo(Article::class, 'article_id');
    }

    /**
     * Montant de la ligne — CALCULÉ, jamais stocké.
     *
     * Aucune colonne `montant` n'existe au schéma, et c'est heureux : une
     * valeur figée divergerait de `quantite_commandee × prix_unitaire` dès la
     * première correction. `bcmul` et non une multiplication flottante, comme
     * partout ailleurs sur ce projet.
     */
    public function montant(): string
    {
        return bcmul((string) $this->quantite_commandee, (string) $this->prix_unitaire, 2);
    }
}
