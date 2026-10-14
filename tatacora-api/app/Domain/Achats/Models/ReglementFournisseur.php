<?php

declare(strict_types=1);

namespace App\Domain\Achats\Models;

use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Règlement d'une commande fournisseur (M7) — PA-165.
 *
 * Un FAIT de décaissement : qui a payé, combien, quand, par quelle
 * trésorerie. `commandes_achat.montant_regle` est recalculé depuis ces
 * lignes par `ReglementFournisseurService`, jamais incrémenté à la main.
 *
 * @property string $id
 * @property string $commande_id
 * @property string $montant
 * @property string $tresorerie
 * @property \Illuminate\Support\Carbon $date_reglement
 * @property string $statut
 * @property string|null $motif_annulation
 * @property string|null $annule_par_id
 * @property \Illuminate\Support\Carbon|null $date_annulation
 */
class ReglementFournisseur extends Model
{
    use Auditable;
    use HasUuids;

    protected $table = 'reglements_fournisseur';

    protected $fillable = [
        'id',
        'commande_id',
        'montant',
        'tresorerie',
        'date_reglement',
        // Annulation (PA-168) — écrites EXCLUSIVEMENT par
        // ReglementFournisseurService::annuler().
        'statut',
        'motif_annulation',
        'annule_par_id',
        'date_annulation',
    ];

    protected function casts(): array
    {
        return [
            'montant' => 'decimal:2',
            'date_reglement' => 'date',
            'date_annulation' => 'datetime',
            'date_creation' => 'datetime',
            'date_modification' => 'datetime',
        ];
    }

    /**
     * @return BelongsTo<CommandeAchat, $this>
     */
    public function commande(): BelongsTo
    {
        return $this->belongsTo(CommandeAchat::class, 'commande_id');
    }
}
