<?php

declare(strict_types=1);

namespace App\Domain\Achats\Http\Resources;

use App\Domain\Achats\Models\CommandeAchat;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Une commande d'achat, telle que la lit le registre des commandes.
 *
 * ## Le montant est CALCULÉ, et il sort en CHAÎNE
 *
 * `commandes_achat` n'a aucune colonne de montant : le total se somme depuis
 * les lignes par `bcadd` (`CommandeAchat::montantTotal()`). Il descend en
 * chaîne, jamais en float — un `DECIMAL(15,2)` converti puis réarrondi côté
 * client ferait diverger l'affichage du chiffre réellement stocké, exactement
 * comme le tarif figé d'une réservation (PA-55).
 *
 * `montant_lecture_seule` est envoyé pour que le client n'ait pas à le
 * redécouvrir : le formulaire du prototype porte « Montant estimé » en saisie,
 * et `CreerCommandeAchatRequest` le refuse.
 *
 * ## `receptionnable` est dérivé, pas stocké
 *
 * L'écran conditionne son bouton « Réceptionner » à l'état de la commande
 * (`m7-approvisionnement.html`). Le calcul vient de `estCloturee()`, la même
 * méthode que celle sur laquelle `ReceptionService` refuse réellement : deux
 * lectures indépendantes finiraient par diverger, et l'écran proposerait un
 * bouton que le serveur refuse — ou masquerait une action permise.
 *
 * ## Aucun « réglé », aucun « reste dû »
 *
 * Le prototype affiche les deux colonnes. Aucune table de règlement
 * fournisseur n'existe au schéma. Voir `AchatController` : ils sont refusés,
 * pas rendus à zéro.
 *
 * @property-read CommandeAchat $resource
 */
class CommandeAchatResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $commande = $this->resource;

        return [
            'id' => $commande->id,
            'date_commande' => $commande->date_commande->toDateString(),
            'statut' => $commande->statut,

            // Vraie clé étrangère, résolue ici pour que l'écran n'ait pas à
            // faire un appel par ligne. Jamais du texte libre.
            'fournisseur_id' => $commande->fournisseur_id,
            'fournisseur' => $commande->relationLoaded('fournisseur') && $commande->fournisseur !== null
                ? [
                    'id' => $commande->fournisseur->id,
                    'raison_sociale' => $commande->fournisseur->raison_sociale,
                ]
                : null,

            // --- Valeurs CALCULÉES, en lecture seule ---
            'nombre_lignes' => $commande->lignes->count(),
            'montant_total' => $commande->montantTotal(),
            'montant_lecture_seule' => true,
            'receptionnable' => ! $commande->estCloturee(),
            'cloturable' => $commande->statut === 'receptionnee',
        ];
    }
}
