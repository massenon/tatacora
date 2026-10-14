<?php

declare(strict_types=1);

namespace App\Domain\Hebergement\Models;

use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Unité physique d'hébergement : bungalow n°, chambre n°, tente n° (M1).
 *
 * **`statut` n'est PAS la disponibilité.** Cette colonne porte un état
 * opérationnel (nettoyage, hors service) et rien d'autre. La disponibilité
 * d'une unité sur une période se calcule toujours depuis les réservations
 * actives, via `DisponibiliteService` — RG-02. Lire `statut` pour répondre
 * « cette unité est-elle libre du 1er au 4 ? » donnerait une réponse fausse
 * dès qu'une réservation future existe, et une annulation ne la corrigerait
 * jamais.
 *
 * @property string $id
 * @property string $categorie_id
 * @property string $numero
 * @property string $statut
 */
class UniteHebergement extends Model
{
    // `Auditable` depuis le 02/09/2026 (migration
    // `ajouter_audit_unites_hebergement`) : l'onglet « Restaurer »
    // d'Import & Export affiche « ARCHIVÉ LE » et « PAR » pour une unité
    // `hors_service` — sans ces colonnes, personne ne pouvait dire qui
    // avait retiré une unité du parc, seul référentiel archivable qui
    // échappait encore à RG-15.
    use Auditable;
    use HasUuids;

    protected $table = 'unites_hebergement';

    protected $fillable = ['id', 'categorie_id', 'numero', 'statut'];

    /**
     * @return BelongsTo<CategorieHebergement, $this>
     */
    public function categorie(): BelongsTo
    {
        return $this->belongsTo(CategorieHebergement::class, 'categorie_id');
    }

    /**
     * @return HasMany<Reservation, $this>
     */
    public function reservations(): HasMany
    {
        return $this->hasMany(Reservation::class, 'unite_id');
    }

    /**
     * Une unité hors service ou en nettoyage n'est pas commercialisable, quelle
     * que soit l'absence de réservation sur la période. C'est le seul usage
     * légitime de `statut` dans une décision de disponibilité — un filtre
     * supplémentaire, jamais la source de vérité.
     */
    public function estCommercialisable(): bool
    {
        return ! in_array($this->statut, ['hors_service', 'nettoyage'], true);
    }
}
