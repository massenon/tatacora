<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Models;

use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Carbon;

/**
 * Facture PROFORMA — document commercial NON FISCAL (PO, 07/11/2026). Voir docs/SPEC_FACTURE_PROFORMA.md.
 *
 * Aucune méthode de ce modèle ne parle de MECeF, de QR ou de normalisation : elle n'en a jamais.
 */
class Proforma extends Model
{
    use Auditable;
    use HasUuids;

    public const BROUILLON = 'brouillon';

    public const EMISE = 'emise';

    public const CONVERTIE = 'convertie';

    public const ANNULEE = 'annulee';

    public const STATUTS = [self::BROUILLON, self::EMISE, self::CONVERTIE, self::ANNULEE];

    /** Libellé « Expirée » : DÉRIVÉ, jamais stocké. */
    public const EXPIREE = 'expiree';

    protected $table = 'proformas';

    protected $fillable = [
        'id', 'numero', 'annee', 'rang', 'reference', 'statut', 'client_id', 'client_nom', 'client_telephone',
        'client_ifu', 'objet', 'date_emission', 'ville', 'valide_jusqu_au', 'total', 'facture_id',
        'motif_annulation', 'source_module', 'source_id', 'origine',
    ];

    protected function casts(): array
    {
        return [
            'date_emission' => 'date',
            'valide_jusqu_au' => 'date',
            'annee' => 'integer',
            'rang' => 'integer',
            'total' => 'integer',
            'date_creation' => 'datetime',
            'date_modification' => 'datetime',
        ];
    }

    /** @return HasMany<LigneProforma, $this> */
    public function lignes(): HasMany
    {
        return $this->hasMany(LigneProforma::class, 'proforma_id')->orderBy('position');
    }

    /** Modifiable tant qu'elle n'est ni convertie ni annulée. */
    public function estModifiable(): bool
    {
        return in_array($this->statut, [self::BROUILLON, self::EMISE], true);
    }

    /** Émise, validité enregistrée et dépassée : « Expirée » (affichage ; la conversion reste possible). */
    public function estExpiree(?Carbon $aujourdhui = null): bool
    {
        return $this->statut === self::EMISE
            && $this->valide_jusqu_au !== null
            && $this->valide_jusqu_au->lt(($aujourdhui ?? now())->startOfDay());
    }

    /** Le statut affiché : le stocké, sauf « expirée » (dérivé). */
    public function statutAffiche(?Carbon $aujourdhui = null): string
    {
        return $this->estExpiree($aujourdhui) ? self::EXPIREE : $this->statut;
    }
}
