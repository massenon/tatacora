<?php

declare(strict_types=1);

namespace App\Domain\Vehicules\Models;

use App\Domain\Crm\Models\Client;
use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Contrat de location de véhicule — EF-M8-03, EF-M8-04.
 *
 * @see EF-M8-03 Contrat avec vérification de pièce d'identité et de permis
 * @see EF-M8-04 Package véhicule + guide touristique
 * @see RG-08 Prévention des doubles locations
 * @see RG-09 Pièces justificatives conditionnelles
 * @see RG-15 Journalisation (trait Auditable)
 *
 * ## Cette table n'a PAS de colonne `statut` — PA-50
 *
 * Contrairement à `reservations`, le schéma documenté
 * (`FULL_MIGRATIONS_DATABASE_PART2.md` §13) ne prévoit aucun statut. Ce n'est
 * pas un écart d'implémentation : la colonne est absente de la spécification
 * elle-même.
 *
 * **Conséquence concrète, non contournée ici** : un contrat saisi par erreur
 * bloque son véhicule sur toute sa plage, définitivement. Aucune annulation
 * n'est possible, et aucune suppression n'est autorisée sur une table
 * transactionnelle (`03_DATABASE_ENGINEERING.md` §15). M1 dispose de RG-02
 * pour ce cas ; M8 n'a aucun équivalent.
 *
 * Aucune méthode `annuler()` n'est donc exposée : une méthode qui ne libère
 * rien laisserait croire que le cas est traité.
 *
 * @property string $id
 * @property string $vehicule_id
 * @property string $client_id
 * @property string|null $guide_id
 * @property \Illuminate\Support\Carbon $date_debut
 * @property \Illuminate\Support\Carbon $date_fin
 * @property string|null $piece_identite
 * @property string|null $permis_conduire
 * @property-read Vehicule $vehicule
 */
class ContratLocation extends Model
{
    use Auditable;
    use HasUuids;

    protected $table = 'contrats_location';

    protected $fillable = [
        'id', 'vehicule_id', 'client_id', 'guide_id',
        'date_debut', 'date_fin', 'piece_identite', 'permis_conduire',
    ];

    protected function casts(): array
    {
        return [
            'date_debut' => 'date',
            'date_fin' => 'date',
            'date_creation' => 'datetime',
            'date_modification' => 'datetime',
        ];
    }

    /**
     * Nombre de jours facturés — CALCULÉ, jamais stocké ni saisi.
     */
    public function nombreJours(): int
    {
        return (int) $this->date_debut->diffInDays($this->date_fin);
    }

    /**
     * Montant de la location au tarif journalier du véhicule.
     *
     * `bcmul` et non une multiplication PHP : le tarif est un `DECIMAL(15,2)`,
     * et un parc de 65 000 F/jour sur trois semaines dériverait en flottant.
     */
    public function montant(): string
    {
        return bcmul((string) $this->vehicule->tarif_jour, (string) $this->nombreJours(), 2);
    }

    /**
     * Le package EF-M8-04 est simplement un contrat portant un guide.
     */
    public function estPackageAvecGuide(): bool
    {
        return $this->guide_id !== null;
    }

    /**
     * @return BelongsTo<Vehicule, $this>
     */
    public function vehicule(): BelongsTo
    {
        return $this->belongsTo(Vehicule::class, 'vehicule_id');
    }

    /**
     * @return BelongsTo<Client, $this>
     */
    public function client(): BelongsTo
    {
        return $this->belongsTo(Client::class, 'client_id');
    }
}
