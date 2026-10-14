<?php

declare(strict_types=1);

namespace App\Domain\Ventes\Models;

use App\Domain\Ventes\Observers\LignePanierObserver;
use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Attributes\ObservedBy;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Une ligne de panier — prix ET libelle FIGES a l'ajout.
 *
 * ## Pourquoi figer, et pourquoi les DEUX
 *
 * Un panier de sejour reste ouvert « de l'arrivee au depart » : plusieurs
 * jours pendant lesquels la carte peut changer. Relire le prix a l'affichage
 * reecrirait le montant deja annonce au client ; relire le libelle rendrait
 * illisible un panier dont l'article a ete renomme. C'est le raisonnement de
 * `tarifNuit` (PA-55) et des lignes de vente (PA-98), applique une couche plus
 * tot.
 *
 * ## Ils ne viennent JAMAIS de l'appelant
 *
 * `PanierService::ajouterLigne()` ne recoit qu'un MODULE et une REFERENCE : il
 * relit le catalogue lui-meme. L'ecran du maitre, lui, porte le montant dans
 * le DOM (`data-ajouter`) et le renvoie tel quel — le reprendre laisserait
 * n'importe qui appeler l'action avec le prix de son choix, et le panier, le
 * ticket puis la facture l'auraient repris sans un mot.
 *
 * ## `reference_id` reste une CHAINE, pas une cle etrangere
 *
 * Une meme ligne vise `cartes_boisson` (M5) ou `plats` (M4), deux tables
 * differentes : c'est la question Q1 de `PROPOSITION_MODELE_PANIER_POS.md`,
 * ouverte aupres de l'Architecte. Le service verifie l'EXISTENCE reelle contre
 * la table du module avant d'ecrire — l'absence de contrainte n'est pas une
 * absence de controle.
 *
 * @see docs/PROPOSITION_MODELE_PANIER_POS.md §5 R-c, §8 Q1
 *
 * @property string $id
 * @property string $panier_id
 * @property string $module
 * @property string $reference_id
 * @property string $libelle
 * @property string $prix_unitaire
 * @property int $quantite
 */
#[ObservedBy(LignePanierObserver::class)]
class LignePanier extends Model
{
    use Auditable;
    use HasUuids;

    protected $table = 'lignes_panier';

    protected $fillable = [
        'id',
        'panier_id',
        'module',
        'reference_id',
        'libelle',
        'prix_unitaire',
        'quantite',
    ];

    /**
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'prix_unitaire' => 'decimal:2',
            'quantite' => 'integer',
            'date_creation' => 'datetime',
            'date_modification' => 'datetime',
        ];
    }

    /**
     * @return BelongsTo<Panier, $this>
     */
    public function panier(): BelongsTo
    {
        return $this->belongsTo(Panier::class, 'panier_id');
    }

    /**
     * Le montant de la ligne — bcmath, jamais un flottant.
     */
    public function montant(): string
    {
        return bcmul((string) $this->prix_unitaire, (string) $this->quantite, Panier::PRECISION);
    }
}
