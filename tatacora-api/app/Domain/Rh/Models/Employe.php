<?php

declare(strict_types=1);

namespace App\Domain\Rh\Models;

use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Dossier du personnel (M13).
 *
 * Référencé en clé étrangère par `plannings`, `presences`, `conges`,
 * `bulletins_paie`, `departs_employes` — jamais un champ texte libre.
 * L'anti-pattern « Employé en texte libre » a été trouvé QUATRE fois dans le
 * prototype (Paie, Présences, Congés, Départs) : chaque occurrence produirait
 * des enregistrements orphelins invisibles dans le dossier du bon salarié.
 *
 * Distinct du compte d'accès applicatif (`utilisateurs`) : tout employé n'a pas
 * de compte, et tout compte n'appartient pas à un employé
 * (03_DATABASE_ENGINEERING.md §2).
 *
 * @see RG-15 Journalisation (trait Auditable)
 *
 * @property string $id
 * @property string|null $matricule
 * @property string|null $numero_cnss
 * @property string|null $type_contrat
 * @property \Illuminate\Support\Carbon|null $date_fin_contrat
 * @property string $nom
 * @property string|null $prenom
 * @property string|null $email
 * @property string $poste
 * @property string $service_id
 * @property \Illuminate\Support\Carbon $date_embauche
 * @property string $salaire_base
 * @property string $statut
 */
class Employe extends Model
{
    use Auditable;
    use HasUuids;

    protected $table = 'employes';

    /** Les seuls types de contrat offerts — registre du maitre, jeu fermé. */
    public const TYPES_CONTRAT = ['CDI', 'CDD', 'Stage', 'Journalier'];

    /** Les seuls statuts au schéma (`enum` de `employes.statut`). */
    public const STATUTS = ['actif', 'conge', 'suspendu', 'parti'];

    protected $fillable = [
        'id',
        'matricule',
        'nom',
        'prenom',
        'email',
        'poste',
        'service_id',
        'date_embauche',
        'numero_cnss',
        'type_contrat',
        'date_fin_contrat',
        'salaire_base',
        'statut',
    ];

    protected function casts(): array
    {
        return [
            'date_embauche' => 'date',
            'date_fin_contrat' => 'date',
            // Salaire : DECIMAL(15,2). Le net à payer n'est JAMAIS stocké ici —
            // il est calculé par CalculPaieService (sprint M13), jamais saisi
            // (A1_MASTER_PROMPT.md §2.2).
            'salaire_base' => 'decimal:2',
            'date_creation' => 'datetime',
            'date_modification' => 'datetime',
        ];
    }

    /**
     * @return BelongsTo<Service, $this>
     */
    public function service(): BelongsTo
    {
        return $this->belongsTo(Service::class, 'service_id');
    }

    public function estEnPoste(): bool
    {
        return in_array($this->statut, ['actif', 'conge'], true);
    }

    /**
     * Le nom complet, dans l'ordre du maître (`m13-paie.js` : nom puis prénoms).
     *
     * Une seule implémentation : l'écran, le bulletin imprimé et l'export
     * doivent nommer le salarié de la même façon, sinon un rapprochement
     * manuel entre deux documents devient impossible.
     */
    public function nomComplet(): string
    {
        return trim($this->nom.' '.(string) $this->prenom);
    }

    /**
     * ⚠ Sans numéro CNSS, le bulletin se CALCULE mais le salarié ne peut pas
     * figurer à la déclaration — c'est le signal que le maître affiche en
     * badge « absent » et en alerte de tête. Le prédicat est ici pour qu'il
     * n'y ait qu'une seule définition de « absent » dans l'écran, l'export et
     * le document imprimé.
     */
    public function sansNumeroCnss(): bool
    {
        return blank($this->numero_cnss);
    }
}
