<?php

declare(strict_types=1);

namespace App\Domain\Hebergement\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Ligne de service d'une réservation — PA-163.
 *
 * Quatre services (`restauration`, `bar`, `tourisme`, `vehicule`) — jamais
 * l'hébergement, qui vit sur `reservations.unite_id` (voir la migration).
 * `libelle` et `prix_unitaire` sont FIGÉS à l'ajout (PA-55/PA-98) :
 * l'affichage ne relit jamais le catalogue.
 *
 * @property string $id
 * @property string $reservation_id
 * @property string $service
 * @property string $source_id
 * @property string $libelle
 * @property string $quantite
 * @property string $prix_unitaire
 * @property string $montant
 */
class LigneReservation extends Model
{
    use HasUuids;

    protected $table = 'lignes_reservation';

    /**
     * Registre FERMÉ — la même liste que la contrainte CHECK du schéma et
     * que `ReservationService::CATALOGUES` : trois écritures d'une seule
     * vérité, chacune vérifiée par les tests contre les autres.
     *
     * @var list<string>
     */
    public const SERVICES = ['restauration', 'bar', 'tourisme', 'vehicule'];

    protected $fillable = [
        'id',
        'reservation_id',
        'service',
        'source_id',
        'libelle',
        'quantite',
        'prix_unitaire',
        'montant',
    ];

    protected function casts(): array
    {
        return [
            'quantite' => 'decimal:2',
            'prix_unitaire' => 'decimal:2',
            'montant' => 'decimal:2',
        ];
    }

    /**
     * @return BelongsTo<Reservation, $this>
     */
    public function reservation(): BelongsTo
    {
        return $this->belongsTo(Reservation::class, 'reservation_id');
    }
}
