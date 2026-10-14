<?php

declare(strict_types=1);

namespace App\Domain\Ventes\Observers;

use App\Domain\Ventes\Models\Panier;
use RuntimeException;

/**
 * Un panier ne se supprime pas, et un panier cloture ne se rouvre pas — R-b.
 *
 * ## Pourquoi un Observer et pas un controle de service
 *
 * Meme raison que `EcritureComptableObserver` : l'Observer couvre TOUS les
 * chemins d'ecriture — un `update()` appele depuis un futur service, un job,
 * une commande artisan, un import. Un controle place dans `PanierService` ne
 * protegerait que le chemin que ce service porte aujourd'hui.
 *
 * ## Ce qui est refuse, et ce qui ne l'est pas
 *
 * - La SUPPRESSION, toujours. Un panier abandonne reste la trace qu'une table
 *   a ete ouverte puis quittee ; l'effacer rendrait cette minute
 *   indistinguable d'une table jamais servie. C'est le « D » de CRUD, qui
 *   n'existe nulle part dans ce depot.
 * - La REOUVERTURE d'un panier cloture. Rouvrir serait le chemin par lequel on
 *   modifie une vente deja enregistree, voire une facture deja emise : R-b
 *   nomme exactement ce risque (« le panier devient le chemin par lequel on
 *   modifie une facture certifiee »). La correction passe par le geste metier
 *   — annuler la vente (`VenteService::annuler`), jamais par le panier.
 *
 * Ce qui reste modifiable APRES cloture : rien. Les seuls champs que la cloture
 * elle-meme renseigne (`statut`, `vente_id`, `cloture_at`) sont ecrits au
 * moment ou le panier est encore ouvert — ils passent donc par le premier
 * controle, pas par le second.
 *
 * @see docs/PROPOSITION_MODELE_PANIER_POS.md §5 R-b
 * @see RG-02 Aucune suppression sur une table transactionnelle
 */
class PanierObserver
{
    public function updating(Panier $panier): void
    {
        // `getOriginal()` : l'etat AVANT modification. Lire `$panier->statut`
        // rendrait la valeur qu'on est en train de poser, et la garde
        // laisserait passer la reouverture qu'elle existe pour refuser.
        if ($panier->getOriginal('statut') !== Panier::STATUT_CLOTURE) {
            return;
        }

        throw new RuntimeException(__('ventes.panier_cloture_immuable'));
    }

    public function deleting(Panier $panier): void
    {
        throw new RuntimeException(__('ventes.panier_indestructible'));
    }
}
