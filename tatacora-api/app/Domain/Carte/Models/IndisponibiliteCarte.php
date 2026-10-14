<?php

declare(strict_types=1);

namespace App\Domain\Carte\Models;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Restaurant\Models\Plat;
use App\Models\User;
use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Retrait d'un article de la carte du jour — M4 et M5.
 *
 * ## Pourquoi un domaine `Carte` plutôt que `Bar` ou `Restaurant`
 *
 * Le maître traite les deux ensemble : `carte-engine.js` s'annonce lui-même
 * « MOTEUR DE CARTE — Restaurant (M4) et Bar (M5) », et la disponibilité y est
 * une seule mécanique appliquée aux deux rayons. Loger la table dans l'un des
 * deux domaines aurait obligé l'autre à en référencer le modèle sans relation
 * documentée au CdCF §8. Le dépôt porte déjà trois domaines transverses de
 * cette nature (`Ventes`, `Depenses`, `Caisse`) : celui-ci suit le précédent.
 *
 * ## Les motifs sont ceux du MAÎTRE
 *
 * `rupture` / `saison` / `retire` — `carte-engine.js` l.51-55. La PWA écrivait
 * `rupture` / `hors_saison` / `retrait` pour des libellés affichés identiques :
 * la divergence était invisible à l'écran et se serait vue le jour d'un export.
 *
 * `temporaire` n'est pas stocké : c'est une propriété du motif, pas de
 * l'enregistrement. Une colonne l'aurait dupliqué, donc rendu capable de
 * mentir. Elle commande le réapprovisionnement — une rupture revient toute
 * seule au prochain achat, un retrait est une décision commerciale.
 *
 * @see EF-M4-01 Gestion des menus et cartes
 * @see EF-M5-02 Carte des boissons
 * @see RG-15 Journalisation (trait Auditable)
 *
 * @property string $id
 * @property string|null $boisson_id
 * @property string|null $plat_id
 * @property string $motif
 * @property string|null $commentaire
 * @property \Illuminate\Support\Carbon $date_indisponibilite
 * @property string $utilisateur_id
 * @property \Illuminate\Support\Carbon|null $date_retour_disponibilite
 * @property string|null $utilisateur_retour_id
 */
class IndisponibiliteCarte extends Model
{
    use Auditable;
    use HasUuids;

    /**
     * Registre FERMÉ des motifs, avec leur libellé et leur caractère
     * temporaire — l'ordre est celui du maître.
     *
     * @var array<string, array{libelle: string, temporaire: bool}>
     */
    public const MOTIFS = [
        'rupture' => ['libelle' => 'Rupture du jour', 'temporaire' => true],
        'saison' => ['libelle' => 'Hors saison', 'temporaire' => true],
        'retire' => ['libelle' => 'Retiré de la carte', 'temporaire' => false],
    ];

    protected $table = 'indisponibilites_carte';

    protected $fillable = [
        'id',
        'boisson_id',
        'plat_id',
        'motif',
        'commentaire',
        'date_indisponibilite',
        'utilisateur_id',
        'date_retour_disponibilite',
        'utilisateur_retour_id',
    ];

    /**
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'date_indisponibilite' => 'datetime',
            'date_retour_disponibilite' => 'datetime',
            'date_creation' => 'datetime',
            'date_modification' => 'datetime',
        ];
    }

    /**
     * @return BelongsTo<CarteBoisson, $this>
     */
    public function boisson(): BelongsTo
    {
        return $this->belongsTo(CarteBoisson::class, 'boisson_id');
    }

    /**
     * @return BelongsTo<Plat, $this>
     */
    public function plat(): BelongsTo
    {
        return $this->belongsTo(Plat::class, 'plat_id');
    }

    /**
     * @return BelongsTo<User, $this>
     */
    public function utilisateur(): BelongsTo
    {
        return $this->belongsTo(User::class, 'utilisateur_id');
    }

    /**
     * Indisponibilités ENCORE actives — celles que rien n'a levées.
     *
     * @param  Builder<IndisponibiliteCarte>  $requete
     * @return Builder<IndisponibiliteCarte>
     */
    public function scopeEnCours(Builder $requete): Builder
    {
        return $requete->whereNull('date_retour_disponibilite');
    }

    public function estEnCours(): bool
    {
        return $this->date_retour_disponibilite === null;
    }

    /**
     * Une rupture ou une fin de saison se lèvent d'elles-mêmes au
     * réapprovisionnement ; un retrait est une décision qui se reprend
     * explicitement. Les confondre ferait disparaître un plat de la carte sans
     * que personne ne sache s'il faut le racheter.
     */
    public function estTemporaire(): bool
    {
        return self::MOTIFS[$this->motif]['temporaire'];
    }

    public function libelleMotif(): string
    {
        return self::MOTIFS[$this->motif]['libelle'];
    }
}
