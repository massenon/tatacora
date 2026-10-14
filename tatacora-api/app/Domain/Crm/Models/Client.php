<?php

declare(strict_types=1);

namespace App\Domain\Crm\Models;

use App\Shared\Audit\Traits\Auditable;
use Database\Factories\ClientFactory;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

/**
 * Fiche client unique, partagée par TOUS les modules (M3).
 *
 * @see RG-18 Fiche client unique — `clients` est référencée par clé étrangère
 *      depuis `reservations`, `factures`, `contrats_location`, `reservations_tour`.
 *      Aucun champ client n'est jamais dupliqué en texte libre ailleurs : une
 *      faute de frappe créerait un client fantôme, invisible dans l'historique
 *      du bon tiers (A1_MASTER_PROMPT.md §2.3).
 * @see RG-15 Journalisation (trait Auditable)
 *
 * @property string $id
 * @property string $nom
 * @property string|null $prenom
 * @property string $telephone
 * @property string|null $email
 * @property string|null $piece_identite
 * @property string $type_client
 * @property string $solde
 * @property bool $actif l'ARCHIVE du referentiel (03/09/2026) — hors `$fillable` : seul `ReferentielClientService` la bascule
 */
class Client extends Model
{
    use Auditable;

    /** @use HasFactory<ClientFactory> */
    use HasFactory;

    use HasUuids;

    protected $table = 'clients';

    protected $fillable = [
        'id',
        'nom',
        'prenom',
        'telephone',
        'email',
        'piece_identite',
        'type_client',
        'solde',
    ];

    protected function casts(): array
    {
        return [
            // Montant : DECIMAL(15,2), jamais un flottant (AVOID_INSTRUCTIONS.md §6)
            'solde' => 'decimal:2',
            // L'ARCHIVE du référentiel (03/09/2026). Absente de `$fillable`
            // volontairement : `ReferentielClientService` est le seul chemin
            // qui la bascule, et il porte le verrou d'engagement.
            'actif' => 'boolean',
            'date_creation' => 'datetime',
            'date_modification' => 'datetime',
        ];
    }

    /**
     * @return Factory<self>
     */
    protected static function newFactory(): Factory
    {
        return ClientFactory::new();
    }

    /**
     * Nom d'affichage — calculé, jamais une colonne dénormalisée qui
     * divergerait de `nom`/`prenom` à la première correction de saisie.
     */
    public function nomComplet(): string
    {
        return trim($this->prenom . ' ' . $this->nom);
    }
}
