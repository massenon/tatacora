<?php

declare(strict_types=1);

namespace App\Domain\Tourisme\Models;

use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Guide touristique — EF-M9-02.
 *
 * @see EF-M9-02 Référentiel des guides (certification, zone de compétence, tarif)
 *
 * ## Le référentiel entier n'a aucun écran au prototype
 *
 * `SPEC_ECRAN_M9_TOURISME.md` §6 le signale comme « l'écart le plus important
 * de ce module » : contrairement à M2-M8 où seule la couche transactionnelle
 * manquait au-dessus d'un catalogue existant, ici c'est un **référentiel
 * entier** qui n'a jamais été maquetté. Les champs implémentés viennent donc
 * du schéma et d'EF-M9-02, pas d'un écran validé par le client.
 *
 * ## Pas de colonne `statut` — PA-51
 *
 * Un guide qui quitte le gîte ne peut pas être désactivé : il restera
 * affectable indéfiniment. Même famille de lacune que `contrats_location`
 * (PA-50). Aucun contournement n'est inventé ici.
 *
 * @property string $id
 * @property string $nom
 * @property string $certification
 * @property string $zone_competence
 * @property string $tarif_jour
 */
class Guide extends Model
{
    use Auditable;
    use HasUuids;

    protected $table = 'guides';

    protected $fillable = ['id', 'nom', 'certification', 'zone_competence', 'tarif_jour'];

    protected function casts(): array
    {
        return ['tarif_jour' => 'decimal:2'];
    }

    /**
     * Le guide est-il compétent sur la zone du circuit ?
     *
     * Comparaison insensible à la casse et aux espaces : `zone` et
     * `zone_competence` sont deux `varchar` libres de tables différentes, rien
     * ne garantit une saisie identique au caractère près.
     *
     * **Consultative, jamais bloquante** : rien dans EF-M9-02 n'interdit
     * d'affecter un guide hors de sa zone — un remplacement en urgence est un
     * cas d'exploitation normal. Le refuser bloquerait le gîte un jour de
     * maladie.
     */
    public function competentSurZone(string $zone): bool
    {
        return mb_strtolower(trim($this->zone_competence)) === mb_strtolower(trim($zone));
    }

    /**
     * @return HasMany<ReservationTour, $this>
     */
    public function affectations(): HasMany
    {
        return $this->hasMany(ReservationTour::class, 'guide_id');
    }
}
