<?php

declare(strict_types=1);

namespace App\Domain\Achats\Models;

use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Bon de commande fournisseur (M7).
 *
 * `fournisseur_id` est une VRAIE cle etrangere. L'anti-pattern « Fournisseur en
 * texte libre » trouve dans le prototype casserait silencieusement le
 * rapprochement a trois voies (EF-M7-04), qui suppose une relation exacte.
 *
 * @see EF-M7-02 Emission de commandes d'achat
 * @see RG-15 Journalisation (trait Auditable)
 *
 * @property string $id
 * @property string $fournisseur_id
 * @property \Illuminate\Support\Carbon $date_commande
 * @property string $statut
 * @property string $utilisateur_id
 */
class CommandeAchat extends Model
{
    use Auditable;
    use HasUuids;

    /**
     * Registre FERMÉ des statuts de l'enum du schéma — celui qu'on FILTRE.
     *
     * À ne pas confondre avec `CommandeAchatService::STATUTS_SAISISSABLES`,
     * qui n'en compte que deux : les trois autres sont produits par une
     * réception réelle. Filtrer un état constaté et le poser à la main sont
     * deux gestes différents, et la seconde liste est délibérément plus courte.
     *
     * @var list<string>
     */
    public const STATUTS = [
        'brouillon',
        'envoyee',
        'receptionnee_partiellement',
        'receptionnee',
        'cloturee',
    ];

    /**
     * Pagination du registre des commandes. Sans danger ici : c'est un journal
     * qu'on parcourt, et **aucun total n'est rendu au-dessus d'une page**. Les
     * compteurs du tableau de bord se lisent en interrogeant le registre par
     * statut (`?statut=envoyee`), qui rend son propre `meta.total` — jamais en
     * additionnant ce que la page montre.
     */
    public const PAR_PAGE_DEFAUT = 50;

    public const PAR_PAGE_MAX = 200;

    protected $table = 'commandes_achat';

    // `montant_regle` est ecrit par `ReglementFournisseurService` — RECALCULE
    // depuis les reglements, jamais saisi par un formulaire (PA-165).
    protected $fillable = ['id', 'fournisseur_id', 'date_commande', 'statut', 'utilisateur_id', 'montant_regle'];

    protected function casts(): array
    {
        return [
            'date_commande' => 'date',
            'date_creation' => 'datetime',
            'date_modification' => 'datetime',
        ];
    }

    /**
     * @return HasMany<LigneCommandeAchat, $this>
     */
    public function lignes(): HasMany
    {
        return $this->hasMany(LigneCommandeAchat::class, 'commande_id');
    }

    /**
     * @return HasMany<BonReception, $this>
     */
    public function receptions(): HasMany
    {
        return $this->hasMany(BonReception::class, 'commande_id');
    }

    /**
     * @return BelongsTo<Fournisseur, $this>
     */
    public function fournisseur(): BelongsTo
    {
        return $this->belongsTo(Fournisseur::class, 'fournisseur_id');
    }

    public function estCloturee(): bool
    {
        return in_array($this->statut, ['receptionnee', 'cloturee'], true);
    }

    /**
     * Montant total de la commande — CALCULÉ depuis ses lignes.
     *
     * `commandes_achat` ne porte **aucune** colonne de montant, et le
     * prototype en attend une (« Montant estimé » saisi au formulaire de
     * `m7-achats.html`). C'est le même refus que le « Stock disponible »
     * éditable de M6 (PA-24) : un total saisi ne bougerait plus quand une
     * ligne change, et il se lit exactement comme un total juste.
     *
     * Somme par `bcadd`, jamais par `sum()` sur des flottants : sur une
     * commande à trente lignes, l'écart d'arrondi finit par se voir sur la
     * facture fournisseur.
     */
    public function montantTotal(): string
    {
        $total = '0.00';

        foreach ($this->lignes as $ligne) {
            $total = bcadd($total, $ligne->montant(), 2);
        }

        return $total;
    }
}
