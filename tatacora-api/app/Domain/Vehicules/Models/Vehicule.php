<?php

declare(strict_types=1);

namespace App\Domain\Vehicules\Models;

use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Véhicule du parc — EF-M8-01.
 *
 * @see EF-M8-01 Référentiel véhicules
 * @see RG-09 Pièces justificatives conditionnelles
 *
 * ## Catégories : l'enum de la base et la liste du prototype divergent
 *
 * Le CdCF §12.8 liste 7 catégories, le prototype n'en implémente que 5
 * (`SPEC_ECRAN_M8_VEHICULES.md` §6) : `scooter` et `velo` sont absents du parc
 * réel au moment du prototypage. L'enum en base les porte quand même,
 * délibérément — « l'enum categorie doit rester extensible ». Ne pas la
 * restreindre aux 5 valeurs du prototype.
 *
 * @property string $id
 * @property string $categorie
 * @property string $immatriculation
 * @property int $annee
 * @property string $transmission
 * @property int $capacite
 * @property string $tarif_jour
 * @property string $statut
 */
class Vehicule extends Model
{
    use Auditable;
    use HasUuids;

    /**
     * Catégories dispensées de permis de conduire — RG-09.
     *
     * La règle du CdCF est littéralement « hors motos » ; c'est donc `moto`
     * seul qui figure ici, et non une interprétation élargie.
     *
     * **Point ouvert PA-50** : l'enum en base contient aussi `scooter` et
     * `velo`. Exiger un permis de conduire pour louer un vélo est
     * vraisemblablement involontaire, mais aucun document ne les dispense — la
     * liste n'est donc pas élargie sans arbitrage. Cette constante est le seul
     * endroit à modifier le jour où la décision tombe.
     */
    public const CATEGORIES_SANS_PERMIS = ['moto'];

    /** Un véhicule en entretien ou hors service ne se loue pas. */
    public const STATUTS_LOUABLES = ['disponible', 'loue'];

    /**
     * Le complément exact de `STATUTS_LOUABLES` — « immobilisé » au sens de
     * l'écran M8 et de la carte d'accueil. Écrit UNE fois (02/09/2026) : la
     * liste vivait en littéral dans `Locations::render()`, et une seconde
     * copie sur l'accueil aurait divergé au premier statut ajouté.
     */
    public const STATUTS_IMMOBILISES = ['entretien', 'hors_service'];

    protected $table = 'vehicules';

    protected $fillable = [
        'id', 'categorie', 'immatriculation', 'annee',
        'transmission', 'capacite', 'tarif_jour', 'statut',
    ];

    protected function casts(): array
    {
        return [
            'annee' => 'integer',
            'capacite' => 'integer',
            // Montant : DECIMAL(15,2), jamais un flottant.
            'tarif_jour' => 'decimal:2',
        ];
    }

    /**
     * RG-09 — ce véhicule exige-t-il un permis de conduire ?
     *
     * Exposé sur le modèle plutôt que dans le `FormRequest` : la même question
     * se pose à la validation, à l'affichage du formulaire côté Flutter et au
     * contrôle avant signature. Trois copies de la condition finiraient par
     * diverger — c'est précisément ainsi qu'une règle conditionnelle devient
     * appliquée à un endroit et oubliée à un autre.
     */
    public function exigePermis(): bool
    {
        return ! in_array($this->categorie, self::CATEGORIES_SANS_PERMIS, true);
    }

    /**
     * Louable **au sens du statut opérationnel** — indépendant du calendrier.
     *
     * Le statut n'est pas la disponibilité (même distinction qu'en M1, RG-02) :
     * un véhicule `loue` reste louable pour une période future.
     */
    public function estLouable(): bool
    {
        return in_array($this->statut, self::STATUTS_LOUABLES, true);
    }

    /**
     * @return HasMany<ContratLocation, $this>
     */
    public function contrats(): HasMany
    {
        return $this->hasMany(ContratLocation::class, 'vehicule_id');
    }

    /**
     * @return HasMany<EntretienVehicule, $this>
     */
    public function entretiens(): HasMany
    {
        return $this->hasMany(EntretienVehicule::class, 'vehicule_id');
    }
}
