<?php

declare(strict_types=1);

namespace App\Domain\Hebergement\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Occurrence effective d'un sejour : check-in / check-out reels (M1).
 *
 * Distinct de la reservation : une reservation peut ne jamais donner lieu a un
 * sejour (no-show), et les dates reelles different souvent des dates prevues.
 *
 * @see EF-M1-03 Check-in
 * @see EF-M1-04 Check-out
 *
 * @property string $id
 * @property string $reservation_id
 * @property \Illuminate\Support\Carbon|null $date_checkin_reel
 * @property \Illuminate\Support\Carbon|null $date_checkout_reel
 * @property array<int, mixed>|null $occupants
 */
class Sejour extends Model
{
    use HasUuids;

    protected $table = 'sejours';

    protected $fillable = ['id', 'reservation_id', 'date_checkin_reel', 'date_checkout_reel', 'occupants'];

    protected function casts(): array
    {
        return [
            'date_checkin_reel' => 'datetime',
            'date_checkout_reel' => 'datetime',
            'occupants' => 'array',
        ];
    }

    /**
     * @return BelongsTo<Reservation, $this>
     */
    public function reservation(): BelongsTo
    {
        return $this->belongsTo(Reservation::class, 'reservation_id');
    }

    public function estEnCours(): bool
    {
        return $this->date_checkin_reel !== null && $this->date_checkout_reel === null;
    }
}
