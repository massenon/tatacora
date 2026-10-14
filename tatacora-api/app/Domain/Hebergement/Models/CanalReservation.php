<?php

declare(strict_types=1);

namespace App\Domain\Hebergement\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Canal de réservation — référentiel administrable (PA-163).
 *
 * Un canal se DÉSACTIVE, il ne s'efface jamais : la FK `restrictOnDelete`
 * de `reservations.canal_id` le garantit au schéma, et la règle vient du
 * maître (`canaux-engine.js`) — l'effacer perdrait l'historique de l'analyse
 * par canal, qui est la raison d'être du champ.
 *
 * @property string $id
 * @property string $nom
 * @property bool $actif
 */
class CanalReservation extends Model
{
    use HasUuids;

    protected $table = 'canaux_reservation';

    protected $fillable = [
        'id',
        'nom',
        'actif',
    ];

    protected function casts(): array
    {
        return [
            'actif' => 'boolean',
        ];
    }

    /**
     * L'inverse de `Reservation::canal()` — sert uniquement à compter les
     * réservations par canal (écran Paramètres, onglet « Canaux de
     * réservation ») : jamais chargée pour autre chose qu'un `withCount`.
     *
     * @return HasMany<Reservation, $this>
     */
    public function reservations(): HasMany
    {
        return $this->hasMany(Reservation::class, 'canal_id');
    }

    /**
     * Les canaux proposables à la saisie — actifs, PLUS celui déjà retenu par
     * la fiche rouverte : un canal désactivé après coup ne doit pas
     * disparaître d'une réservation qui le porte, sans quoi rouvrir la fiche
     * effacerait silencieusement le canal d'origine (règle du maître,
     * `canaux-engine.js` `proposables()`).
     *
     * @return \Illuminate\Database\Eloquent\Collection<int, self>
     */
    public static function proposables(?string $canalRetenuId = null): \Illuminate\Database\Eloquent\Collection
    {
        return self::query()
            ->where('actif', true)
            ->when($canalRetenuId !== null, fn ($q) => $q->orWhere('id', $canalRetenuId))
            ->orderBy('created_at')
            ->get();
    }
}
