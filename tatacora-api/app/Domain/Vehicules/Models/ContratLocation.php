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
 * ## Le statut (`actif` | `annule`) — PA-50 levé le 26/10/2026
 *
 * Le schéma documenté ne prévoyait aucun statut ; la colonne a été ajoutée
 * ensuite (`add_missing_pwa_columns`) et l'annulation existe : elle passe par
 * `ContratLocationService::annuler()`, le seul chemin (PWA et synchronisation
 * d'un poste), et un contrat annulé ne bloque plus son véhicule (RG-08). Rien
 * n'est jamais supprimé : le contrat annulé reste lisible.
 *
 * @property string $id
 * @property string $vehicule_id
 * @property string $client_id
 * @property string|null $guide_id
 * @property \Illuminate\Support\Carbon $date_debut
 * @property \Illuminate\Support\Carbon $date_fin
 * @property string|null $piece_identite
 * @property string|null $permis_conduire
 * @property string|null $statut
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
