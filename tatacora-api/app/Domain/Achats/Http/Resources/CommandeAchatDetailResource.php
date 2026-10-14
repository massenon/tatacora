<?php

declare(strict_types=1);

namespace App\Domain\Achats\Http\Resources;

use App\Domain\Achats\Models\CommandeAchat;
use App\Domain\Achats\Models\LigneCommandeAchat;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Une commande d'achat, ses lignes et ce qui en a réellement été reçu —
 * EF-M7-02, EF-M7-03.
 *
 * ## Pourquoi le « déjà reçu » figure ici
 *
 * La modale de réception du prototype affiche trois colonnes par article :
 * commandé, déjà reçu, reçu maintenant — et propose le reste par défaut. Sans
 * le « déjà reçu », une seconde réception repartirait de la quantité commandée
 * entière et ferait entrer la marchandise **deux fois** en stock.
 *
 * ## Ce chiffre est RECONSTITUÉ, et il le dit
 *
 * `bons_reception` n'a **aucune table de lignes** (PA-39) : le reçu se relit
 * des `mouvements_stock` d'entrée dont le motif nomme le bon
 * (`ControleTroisVoiesService::quantitesRecues()`). C'est fonctionnel et
 * fragile — une entrée saisie à la main avec un motif ressemblant serait
 * comptée comme une réception. Le drapeau `recu_reconstitue` porte cet aveu
 * jusqu'à l'écran plutôt que de le laisser dans un commentaire de code.
 *
 * @property-read array{
 *     commande: CommandeAchat,
 *     quantites_recues: array<string, string>
 * } $resource
 */
class CommandeAchatDetailResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $commande = $this->resource['commande'];
        $recues = $this->resource['quantites_recues'];

        return [
            'id' => $commande->id,
            'date_commande' => $commande->date_commande->toDateString(),
            'statut' => $commande->statut,

            'fournisseur_id' => $commande->fournisseur_id,
            'fournisseur' => $commande->fournisseur === null ? null : [
                'id' => $commande->fournisseur->id,
                'raison_sociale' => $commande->fournisseur->raison_sociale,
                'contact' => $commande->fournisseur->contact,
                'conditions_paiement' => $commande->fournisseur->conditions_paiement,
            ],

            'montant_total' => $commande->montantTotal(),
            'montant_lecture_seule' => true,
            'receptionnable' => ! $commande->estCloturee(),
            'cloturable' => $commande->statut === 'receptionnee',
            'recu_reconstitue' => true,

            'lignes' => $commande->lignes
                ->map(fn (LigneCommandeAchat $ligne): array => $this->ligne($ligne, $recues))
                ->all(),

            'receptions' => BonReceptionResource::collection($commande->receptions)
                ->toArray($request),
        ];
    }

    /**
     * @param  array<string, string>  $recues
     * @return array<string, mixed>
     */
    private function ligne(LigneCommandeAchat $ligne, array $recues): array
    {
        $commandee = (string) $ligne->quantite_commandee;
        $recue = $recues[$ligne->article_id] ?? '0.00';

        // `bcsub` puis plancher à zéro : un excédent ne devient pas un reste
        // NÉGATIF à recevoir. La modale poserait alors une quantité négative
        // par défaut, que le formulaire refuserait sans expliquer pourquoi.
        // L'excédent, lui, reste visible par `quantite_recue > commandee` et
        // c'est le rapprochement qui le qualifie.
        $reste = bcsub($commandee, $recue, 2);

        return [
            'id' => $ligne->id,
            'article_id' => $ligne->article_id,
            'article_libelle' => $ligne->article?->libelle,
            'unite_mesure' => $ligne->article?->unite_mesure,
            'quantite_commandee' => $commandee,
            'prix_unitaire' => (string) $ligne->prix_unitaire,
            'montant' => $ligne->montant(),
            'quantite_recue' => $recue,
            'reste_a_recevoir' => bccomp($reste, '0.00', 2) > 0 ? $reste : '0.00',
        ];
    }
}
