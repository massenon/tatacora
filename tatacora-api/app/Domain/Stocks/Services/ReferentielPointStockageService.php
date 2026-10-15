<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Services;

use App\Domain\Stocks\Models\PointStockage;

/**
 * Référentiel des points de stockage — création (M6, EF-M6-01).
 *
 * Né le 15/10/2026 (lot S2 de synchronisation) : jusque-là, aucun code ne
 * créait de point hors du semeur. Le poste Flutter en crée hors connexion,
 * et la décision du Product Owner du 15/10/2026 les fait remonter — par un
 * service de domaine, comme tout référentiel, pour que l'audit RG-15
 * (`Auditable` sur `PointStockage`) soit tenu et que l'écran en ligne qui
 * viendrait un jour emprunte le même chemin.
 *
 * Modification depuis la décision du Product Owner du 15/10/2026
 * (« offline-first total ») : un poste renomme ou retype un point hors
 * connexion, et la synchronisation l'applique en dernier écrit gagnant — par
 * ce service. (Le refus du lot S2, « le serveur est maître », est levé.)
 * Pas d'archivage : aucun écran ne le demande.
 */
class ReferentielPointStockageService
{
    /**
     * @param  array<string, mixed>  $donnees données validées par
     *                                        `EnregistrerPointStockageRequest`
     */
    public function creer(array $donnees): PointStockage
    {
        return PointStockage::create($donnees);
    }

    /**
     * @param  array<string, mixed>  $donnees  champs validés par les règles
     *                                         d'`EnregistrerPointStockageRequest`
     */
    public function modifier(PointStockage $point, array $donnees): PointStockage
    {
        unset($donnees['id']);

        $point->update($donnees);

        return $point->refresh();
    }
}
