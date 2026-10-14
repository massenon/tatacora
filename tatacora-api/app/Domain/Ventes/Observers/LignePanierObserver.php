<?php

declare(strict_types=1);

namespace App\Domain\Ventes\Observers;

use App\Domain\Ventes\Models\LignePanier;
use App\Domain\Ventes\Models\Panier;
use RuntimeException;

/**
 * Un panier CLOTURE n'accepte plus aucune ligne — ni ajout, ni retrait, ni
 * changement de quantite (R-b).
 *
 * ## Pourquoi la garde vit ici et pas seulement dans le service
 *
 * `PanierService` refuse deja ces gestes, et ce refus est ce que l'operateur
 * lit. Mais il ne couvre que le chemin qu'il porte : un job, un import ou un
 * futur service ecrirait sans passer par lui. C'est la lecon de
 * `EcritureComptableObserver`, et celle de PA-100 — « ne pas confondre la
 * garde du service avec la protection ». Ici, la protection est cet Observer.
 *
 * ## Le RETRAIT d'une ligne est autorise tant que le panier est OUVERT
 *
 * Et c'est un ecart assume a la regle generale « aucune suppression » du
 * depot, qui vise les tables transactionnelles — factures, ecritures, stock,
 * paie. Une ligne de panier ouvert n'est pas une piece : c'est une commande en
 * train de se composer, que le maitre laisse defaire d'une croix
 * (`pos.html`, bouton de retrait de ligne). La conserver « annulee » ferait
 * porter au ticket des articles que le client n'a jamais commandes.
 *
 * La frontiere est nette : des que le panier est CLOTURE, plus rien ne bouge,
 * et la vente qui en est issue, elle, ne se supprime jamais — elle s'annule.
 *
 * @see docs/PROPOSITION_MODELE_PANIER_POS.md §5 R-b
 */
class LignePanierObserver
{
    public function creating(LignePanier $ligne): void
    {
        $this->refuserSiCloture($ligne);
    }

    public function updating(LignePanier $ligne): void
    {
        $this->refuserSiCloture($ligne);
    }

    public function deleting(LignePanier $ligne): void
    {
        $this->refuserSiCloture($ligne);
    }

    /**
     * Le panier est relu EN BASE, jamais pris sur la relation deja chargee :
     * un objet charge avant la cloture porterait encore `ouvert`, et la garde
     * laisserait passer exactement ce qu'elle refuse.
     */
    private function refuserSiCloture(LignePanier $ligne): void
    {
        $panier = Panier::find($ligne->panier_id);

        if ($panier === null || $panier->estOuvert()) {
            return;
        }

        throw new RuntimeException(__('ventes.panier_cloture_immuable'));
    }
}
