<?php

declare(strict_types=1);

namespace App\Domain\Ventes\Models;

use App\Domain\Caisse\Models\SessionCaisse;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Crm\Models\Client;
use App\Models\User;
use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Vente encaissee au point de vente — registre unique, multi-modules.
 *
 * Une vente porte des lignes de plusieurs modules a la fois (M4 Restaurant,
 * M5 Bar, et demain M1/M8/M9) : c'est ce qui la distingue de `VenteBar`, qui
 * ne connait que des boissons. Le module est estampille sur la LIGNE, jamais
 * deduit apres coup de sa categorie — `ventes-engine.js` l.267-273 : deviner
 * sur une donnee financiere est exactement ce que ce depot s'interdit.
 *
 * @see RG-15 Journalisation — `utilisateur_id` est une vraie cle etrangere
 *      depuis la reprise `2026_09_01_100000_reprendre_ventes_en_uuid`, et
 *      `restrictOnDelete` interdit le seul geste qui effacerait l'imputation.
 * @see RG-02 Aucune suppression : une vente s'ANNULE (`statut`,
 *      `motif_annulation`, `annulee_at`), elle ne disparait jamais.
 *
 * @property string $id
 * @property string $numero
 * @property string|null $session_id
 * @property string $point_vente
 * @property string|null $client_id
 * @property string|null $client_mention
 * @property string|null $table
 * @property string|null $table_id
 * @property string $montant_total
 * @property string $mode_paiement
 * @property bool $encaisse
 * @property string $statut
 * @property string|null $motif_annulation
 * @property \Illuminate\Support\Carbon|null $annulee_at
 * @property string|null $utilisateur_id
 * @property string|null $ecriture_id
 * @property array<int, array<string, mixed>>|null $stock_non_impacte
 * @property \Illuminate\Support\Carbon|null $created_at
 */
class Vente extends Model
{
    use Auditable;
    use HasUuids;

    /** Registre ferme des statuts — une vente est validee, ou annulee. */
    public const STATUTS = ['validee', 'annulee'];

    protected $table = 'ventes';

    protected $fillable = [
        'id',
        'numero',
        'session_id',
        'point_vente',
        'client_id',
        'client_mention',
        'table',
        'table_id',
        'montant_total',
        'mode_paiement',
        'encaisse',
        'statut',
        'motif_annulation',
        'annulee_at',
        'utilisateur_id',
        'ecriture_id',
        'stock_non_impacte',
    ];

    /**
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'montant_total' => 'decimal:2',
            'encaisse' => 'boolean',
            'stock_non_impacte' => 'array',
            'annulee_at' => 'datetime',
            'date_creation' => 'datetime',
            'date_modification' => 'datetime',
        ];
    }

    /**
     * @return HasMany<LigneVente, $this>
     */
    public function lignes(): HasMany
    {
        return $this->hasMany(LigneVente::class, 'vente_id');
    }

    /**
     * @return BelongsTo<User, $this>
     */
    public function utilisateur(): BelongsTo
    {
        return $this->belongsTo(User::class, 'utilisateur_id');
    }

    /**
     * @return BelongsTo<Client, $this>
     */
    public function client(): BelongsTo
    {
        return $this->belongsTo(Client::class, 'client_id');
    }

    /**
     * @return BelongsTo<SessionCaisse, $this>
     */
    public function session(): BelongsTo
    {
        return $this->belongsTo(SessionCaisse::class, 'session_id');
    }

    public function estAnnulee(): bool
    {
        return $this->statut === 'annulee';
    }

    /**
     * La vente a-t-elle atteint le grand livre ?
     *
     * Le lien est la SEULE preuve : compter les ecritures d'une periode ou
     * lire un total ne dit pas si CETTE vente y figure. `ecriture_id` designe
     * la ligne de contrepartie de sa piece (voir la migration
     * `2026_09_02_600000`), et son absence signifie exactement une chose — la
     * vente est anterieure au 31/08/2026, ou elle a ete posee en direct par
     * un seeder. `VenteService::comptabiliser()` est le rattrapage.
     */
    public function estComptabilisee(): bool
    {
        return $this->ecriture_id !== null;
    }

    /**
     * @return BelongsTo<EcritureComptable, $this>
     */
    public function ecriture(): BelongsTo
    {
        return $this->belongsTo(EcritureComptable::class, 'ecriture_id');
    }

    /**
     * Vrai quand au moins une ligne n'a pas decremente le stock.
     *
     * Le detail vit dans `stock_non_impacte`, ecrit a l'encaissement par
     * `VenteService`. Le recalculer a l'affichage donnerait une reponse
     * differente le jour ou le lien de stock manquant serait pose : la vente
     * passee, elle, n'aurait toujours rien decremente.
     */
    public function aDesLignesSansImpactStock(): bool
    {
        return ($this->stock_non_impacte ?? []) !== [];
    }

    /**
     * La somme BRUTE des lignes — les prix figes du catalogue, avant remise.
     */
    public function totalLignes(): string
    {
        $total = '0.00';

        foreach ($this->lignes as $ligne) {
            $total = bcadd($total, (string) $ligne->montant, 2);
        }

        return $total;
    }

    /**
     * La remise deduite a l'encaissement — directive PO du 02/09/2026.
     *
     * DERIVEE de la seule verite persistee : lignes brutes − `montant_total`
     * (net). Aucune colonne de remise sur la vente, deliberement : une copie
     * du montant divergerait de la difference reelle au premier correctif, et
     * c'est la difference que le ticket doit dire. Zero = pas de ligne
     * « Remise » sur les documents.
     */
    public function remiseDeduite(): string
    {
        $remise = bcsub($this->totalLignes(), (string) $this->montant_total, 2);

        return bccomp($remise, '0.00', 2) > 0 ? $remise : '0.00';
    }
}
