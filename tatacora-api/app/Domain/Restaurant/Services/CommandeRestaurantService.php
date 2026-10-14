<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Services;

use App\Domain\Restaurant\Events\CommandeTransmiseCuisine;
use App\Domain\Restaurant\Models\CommandeRestaurant;
use App\Domain\Restaurant\Models\LigneCommandeRestaurant;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Cycle de vie d'une commande restaurant (M4).
 *
 * @see EF-M4-03 Prise de commande
 * @see EF-M4-05 Bon de cuisine
 * @see RG-05 Sortie de stock automatique
 */
class CommandeRestaurantService
{
    public function __construct(
        private readonly DeductionStockCuisineService $deduction,
    ) {
    }

    /**
     * Crée une commande en préparation. **Aucun stock n'est encore engagé** :
     * un serveur qui compose une commande peut encore la modifier ou l'annuler
     * sans que la cuisine ait rien entamé.
     *
     * @param  list<array{plat_id: string, quantite: int}>  $lignes
     */
    public function creer(array $lignes, ?string $clientId = null, ?string $tableOuChambreId = null): CommandeRestaurant
    {
        if ($lignes === []) {
            throw new RuntimeException(__('restaurant.commande_vide'));
        }

        return DB::transaction(function () use ($lignes, $clientId, $tableOuChambreId) {
            $commande = CommandeRestaurant::create([
                'client_id' => $clientId,
                'table_ou_chambre_id' => $tableOuChambreId,
                'date_commande' => now(),
                'statut' => 'en_preparation',
            ]);

            foreach ($lignes as $ligne) {
                LigneCommandeRestaurant::create([
                    'commande_id' => $commande->id,
                    'plat_id' => $ligne['plat_id'],
                    'quantite' => $ligne['quantite'],
                ]);
            }

            return $commande->refresh();
        });
    }

    /**
     * Transmission en cuisine — RG-05 s'applique ICI.
     *
     * La déduction de stock et le changement de statut sont dans la même
     * transaction : si un ingrédient manque (RG-06), la commande n'est pas
     * transmise et reste modifiable. Le contraire — une commande transmise dont
     * le stock n'a pas suivi — laisserait la cuisine avec un bon qu'elle ne
     * peut pas honorer.
     *
     * @throws \App\Domain\Stocks\Exceptions\RuptureStockException
     * @throws \App\Domain\Restaurant\Exceptions\RecetteManquanteException
     */
    public function transmettreEnCuisine(CommandeRestaurant $commande, bool $validationRupture = false): CommandeRestaurant
    {
        if ($commande->estTransmise()) {
            // Une seconde transmission décrémenterait le stock deux fois pour
            // une seule commande — l'erreur ne se verrait qu'à l'inventaire.
            throw new RuntimeException(__('restaurant.deja_transmise'));
        }

        if ($commande->statut === 'annulee') {
            throw new RuntimeException(__('restaurant.annulee_non_transmissible'));
        }

        return DB::transaction(function () use ($commande, $validationRupture) {
            $sorties = $this->deduction->deduire($commande, $validationRupture);

            $commande->update(['statut' => 'transmise_cuisine']);

            // Émis après succès : les consommateurs n'ont pas de droit de veto.
            CommandeTransmiseCuisine::dispatch($commande->id, $sorties);

            return $commande->refresh();
        });
    }

    /**
     * Annulation — possible uniquement avant transmission.
     *
     * Après transmission, les denrées sont engagées : l'annulation devient une
     * perte de stock à constater, pas un simple changement de statut. Ce cas
     * relève d'un mouvement `perte` explicite, décidé par un responsable.
     */
    public function annuler(CommandeRestaurant $commande): CommandeRestaurant
    {
        if ($commande->estTransmise()) {
            throw new RuntimeException(__('restaurant.annulation_apres_transmission'));
        }

        $commande->update(['statut' => 'annulee']);

        return $commande->refresh();
    }

    public function marquerServie(CommandeRestaurant $commande): CommandeRestaurant
    {
        if (! $commande->estTransmise()) {
            throw new RuntimeException(__('restaurant.service_avant_transmission'));
        }

        $commande->update(['statut' => 'servie']);

        return $commande->refresh();
    }
}
