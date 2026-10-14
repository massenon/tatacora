<?php

declare(strict_types=1);

namespace App\Domain\Carte\Models;

use App\Models\User;
use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Une ligne de l'historique des prix de la carte — M4 et M5.
 *
 * ## Modèle EN LECTURE — l'Observer est l'unique auteur
 *
 * Aucun service d'écriture n'existe pour ce modèle, et ce n'est pas un oubli :
 * `CarteBoissonObserver` et `PlatObserver` sont le SEUL chemin qui crée une
 * ligne ici, sur l'événement `updated` de `CarteBoisson`/`Plat`. Écrire
 * directement dans cette table depuis un composant Livewire ou un futur
 * service produirait une trace sans le changement qui l'a causée, ou
 * l'inverse — le même défaut que ce dépôt refuse pour tout référentiel à
 * auteur unique (PA-160/161).
 *
 * @see EF-M4-01 Gestion des menus et cartes
 * @see EF-M5-02 Carte des boissons
 * @see \App\Domain\Bar\Observers\CarteBoissonObserver
 * @see \App\Domain\Restaurant\Observers\PlatObserver
 *
 * @property string $id
 * @property string $source
 * @property string $source_id
 * @property string $champ
 * @property string|null $ancien_prix
 * @property string|null $nouveau_prix
 */
class HistoriquePrixCarte extends Model
{
    use Auditable;
    use HasUuids;

    /** Les deux rayons de la carte, tels que les Observers les nomment. */
    public const SOURCE_BOISSON = 'carte_boisson';

    public const SOURCE_PLAT = 'plat';

    /** Les deux champs de prix retracés — voir l'entête de la migration. */
    public const CHAMP_PRIX_VENTE = 'prix_vente';

    public const CHAMP_PRIX_CORRIGE_MAIN = 'prix_corrige_main';

    protected $table = 'historique_prix_carte';

    protected $fillable = [
        'id',
        'source',
        'source_id',
        'champ',
        'ancien_prix',
        'nouveau_prix',
    ];

    /**
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'ancien_prix' => 'decimal:2',
            'nouveau_prix' => 'decimal:2',
            'date_creation' => 'datetime',
            'date_modification' => 'datetime',
        ];
    }

    /**
     * L'opérateur qui a changé le prix — colonne d'audit du trait
     * `Auditable`, écrite par l'Observer au moment de la trace. C'est elle
     * que la modale « Historique des prix » lit pour la colonne « Par ».
     *
     * @return BelongsTo<User, $this>
     */
    public function utilisateurCreation(): BelongsTo
    {
        return $this->belongsTo(User::class, 'utilisateur_creation_id');
    }
}
