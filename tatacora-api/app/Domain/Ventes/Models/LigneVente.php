<?php

declare(strict_types=1);

namespace App\Domain\Ventes\Models;

use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Ligne d'une vente encaissee.
 *
 * ## `code` et `nom` sont FIGES a l'encaissement, et ce n'est pas une copie
 *
 * Le libelle et le prix unitaire sont recopies depuis le catalogue au moment
 * de la vente, jamais relus a l'affichage — meme raisonnement que `tarifNuit`
 * (PA-55) et que les lignes de panier (PA-98) : une hausse de tarif demain ne
 * doit pas reecrire le montant d'une vente d'aujourd'hui, et un article
 * renomme ne doit pas rendre illisible un ticket ancien.
 *
 * `code` reste une CHAINE et non une cle etrangere : une meme vente melange
 * des boissons (`cartes_boisson`) et des plats (`plats`), deux tables
 * differentes. C'est la question Q1 de `PROPOSITION_MODELE_PANIER_POS.md`,
 * ouverte aupres de l'Architecte — la trancher ici en inventant une colonne
 * par table ferait diverger le serveur du client Flutter, qui a retenu le
 * registre ferme plus une verification d'existence.
 *
 * @property string $id
 * @property string $vente_id
 * @property string|null $code
 * @property string $nom
 * @property string|null $categorie
 * @property string $module
 * @property string $prix_unitaire
 * @property int $quantite
 * @property string $montant
 */
class LigneVente extends Model
{
    use Auditable;
    use HasUuids;

    protected $table = 'lignes_vente';

    protected $fillable = [
        'id',
        'vente_id',
        'code',
        'nom',
        'categorie',
        'module',
        'prix_unitaire',
        'quantite',
        'montant',
    ];

    /**
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'prix_unitaire' => 'decimal:2',
            'quantite' => 'integer',
            'montant' => 'decimal:2',
            'date_creation' => 'datetime',
            'date_modification' => 'datetime',
        ];
    }

    /**
     * @return BelongsTo<Vente, $this>
     */
    public function vente(): BelongsTo
    {
        return $this->belongsTo(Vente::class, 'vente_id');
    }
}
