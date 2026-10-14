<?php

declare(strict_types=1);

namespace App\Domain\Depenses\Models;

use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Models\User;
use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Depense courante saisie au comptoir, avec sa ventilation SYSCOHADA.
 *
 * ## `ecriture_id` designe la ligne de TRESORERIE, pas « la piece »
 *
 * `ecritures_comptables` n'a aucune colonne groupant les lignes d'une meme
 * piece (PA-52) : reconstituer la piece complete depuis cette cle est
 * impossible, et rien ici ne le repare. La ligne de tresorerie est retenue
 * parce qu'elle est la seule dont il existe exactement une par depense, quel
 * que soit le nombre de comptes de charge ventiles.
 *
 * ## `estComptabilisee()` lit la CLE, jamais un drapeau
 *
 * Un booleen `comptabilisee` serait un second etat a tenir a jour, et il
 * deviendrait faux au premier echec de reprise sans que rien ne le signale —
 * la famille de defauts PA-59/60/61. La cle etrangere est la seule preuve
 * qu'une ecriture existe reellement.
 *
 * @property string $id
 * @property string $numero
 * @property \Illuminate\Support\Carbon $date_transaction
 * @property string $tresorerie
 * @property string $compte_tresorerie
 * @property string $montant_total
 * @property string $libelle
 * @property string|null $recu_path
 * @property string|null $ecriture_id
 * @property string|null $ecriture_refus
 * @property string|null $utilisateur_id
 * @property array<int, array<string, mixed>>|null $lignes_json
 */
class Depense extends Model
{
    use Auditable;
    use HasUuids;

    protected $table = 'depenses';

    protected $fillable = [
        'id',
        'numero',
        'date_transaction',
        'tresorerie',
        'compte_tresorerie',
        'montant_total',
        'libelle',
        'recu_path',
        'ecriture_id',
        'ecriture_refus',
        'utilisateur_id',
        'lignes_json',
    ];

    /**
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'date_transaction' => 'date',
            'montant_total' => 'decimal:2',
            'lignes_json' => 'array',
            'date_creation' => 'datetime',
            'date_modification' => 'datetime',
        ];
    }

    /**
     * @return HasMany<LigneDepense, $this>
     */
    public function lignes(): HasMany
    {
        return $this->hasMany(LigneDepense::class, 'depense_id');
    }

    /**
     * @return BelongsTo<User, $this>
     */
    public function utilisateur(): BelongsTo
    {
        return $this->belongsTo(User::class, 'utilisateur_id');
    }

    /**
     * Ligne de tresorerie de la piece — voir la note de classe.
     *
     * @return BelongsTo<EcritureComptable, $this>
     */
    public function ecriture(): BelongsTo
    {
        return $this->belongsTo(EcritureComptable::class, 'ecriture_id');
    }

    public function estComptabilisee(): bool
    {
        return $this->ecriture_id !== null;
    }
}
