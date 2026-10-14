<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Compte du plan comptable SYSCOHADA revise (M10).
 *
 * @property string $id
 * @property string $numero_compte
 * @property string $libelle
 * @property string $classe
 * @property string|null $nature
 */
class CompteComptable extends Model
{
    use HasUuids;

    /**
     * Les classes SYSCOHADA que le schema admet — `create_comptabilite.php`
     * l.51 : « classe SYSCOHADA (1 a 9) ».
     */
    public const CLASSES_SYSCOHADA = ['1', '2', '3', '4', '5', '6', '7', '8', '9'];

    /**
     * Les classes que l'ECRAN presente — `m10-plan-comptable.html` l.29 et
     * l.63-64 : « Comptes SYSCOHADA revise (Classes 1 a 7) », sept boutons de
     * filtre.
     *
     * ⚠ **Les deux listes ne coincident pas, et c'est le piege de cet ecran.**
     * Le schema admet 8 (HAO) et 9 (analytique) ; l'ecran n'a aucun bouton pour
     * les atteindre. Un compte de classe 8 serait donc invisible sans que rien
     * ne le signale — un plan comptable ampute qui a l'air complet. La ressource
     * du plan comptable compte donc separement les classes hors ecran plutot
     * que de les taire (Article 7 : « — » quand la donnee n'existe pas,
     * jamais un silence).
     */
    public const CLASSES_ECRAN = ['1', '2', '3', '4', '5', '6', '7'];

    protected $table = 'plan_comptable';

    protected $fillable = ['id', 'numero_compte', 'libelle', 'classe', 'nature', 'centre_cout_defaut_id'];

    /**
     * @return HasMany<EcritureComptable, $this>
     */
    public function ecritures(): HasMany
    {
        return $this->hasMany(EcritureComptable::class, 'compte_id');
    }
}
