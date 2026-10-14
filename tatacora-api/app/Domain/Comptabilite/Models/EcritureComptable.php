<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Models;

use App\Domain\Comptabilite\Observers\EcritureComptableObserver;
use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Attributes\ObservedBy;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Ecriture comptable (M10).
 *
 * @see RG-11 Immutabilité — une écriture validée ne se modifie pas, elle se
 *      contre-passe (colonne `ecriture_contrepassee_id`). Garantie par
 *      `EcritureComptableObserver`, jamais par un service : l'Observer couvre
 *      tous les chemins d'écriture, y compris la synchronisation différée.
 * @see RG-12 Centre de coût obligatoire — `centre_id` est NOT NULL au schéma,
 *      la règle est donc portée par la base, pas seulement par du code.
 * @see RG-15 Journalisation (trait Auditable)
 *
 * @property string $id
 * @property string $exercice_id
 * @property string $compte_id
 * @property string|null $numero_piece Alloué par `PasserEcritureService::passer()` depuis le
 *                                      01/09/2026 (Vague E, PA-52 partiellement refermée) — `null`
 *                                      sur toute écriture antérieure, jamais un numéro inventé.
 * @property \Illuminate\Support\Carbon $date_ecriture
 * @property string $libelle
 * @property string $debit
 * @property string $credit
 * @property string $statut
 * @property string|null $ecriture_contrepassee_id
 */
#[ObservedBy(EcritureComptableObserver::class)]
class EcritureComptable extends Model
{
    use Auditable;
    use HasUuids;

    /**
     * Registre FERME des statuts d'ecriture — l'`enum` du schema le tient
     * deja, la constante le nomme pour que le code n'ait pas a le deviner.
     */
    public const STATUTS = ['brouillon', 'validee'];

    /**
     * Valeur de filtre signifiant « les deux statuts ».
     *
     * Ce n'est PAS un statut : elle ne peut jamais atteindre la colonne. La
     * separer evite le piege du registre ouvert — un troisieme statut ajoute
     * demain n'obtiendra pas un comportement par omission.
     */
    public const FILTRE_STATUT_TOUTES = 'toutes';

    /** Les valeurs admises par le parametre `statut` des etats de M10. */
    public const FILTRES_STATUT = ['toutes', 'brouillon', 'validee'];

    protected $table = 'ecritures_comptables';

    protected $fillable = [
        'id', 'exercice_id', 'journal_id', 'compte_id', 'centre_id',
        'date_ecriture', 'libelle', 'debit', 'credit', 'statut',
        'ecriture_contrepassee_id', 'numero_piece',
    ];

    protected function casts(): array
    {
        return [
            'date_ecriture' => 'date',
            'debit' => 'decimal:2',
            'credit' => 'decimal:2',
        ];
    }

    /**
     * @return BelongsTo<CompteComptable, $this>
     */
    public function compte(): BelongsTo
    {
        return $this->belongsTo(CompteComptable::class, 'compte_id');
    }

    /**
     * @return BelongsTo<ExerciceComptable, $this>
     */
    public function exercice(): BelongsTo
    {
        return $this->belongsTo(ExerciceComptable::class, 'exercice_id');
    }

    /**
     * @return BelongsTo<JournalComptable, $this>
     */
    public function journal(): BelongsTo
    {
        return $this->belongsTo(JournalComptable::class, 'journal_id');
    }

    /**
     * @return BelongsTo<CentreCout, $this>
     */
    public function centre(): BelongsTo
    {
        return $this->belongsTo(CentreCout::class, 'centre_id');
    }
}
