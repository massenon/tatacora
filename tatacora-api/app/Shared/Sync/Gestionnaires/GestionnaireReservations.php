<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Hebergement\Services\ReservationService;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;

/**
 * Réservations créées hors connexion (M1) — par `ReservationService`, et par
 * lui seul.
 *
 * ## Passage OBLIGATOIRE par le service
 *
 * C'est lui qui porte le verrou de RG-01. Une insertion directe ferait de la
 * synchronisation le seul chemin par lequel une double-réservation devient
 * possible — précisément le scénario que RG-01 existe pour empêcher.
 *
 * ## Modification : REFUSÉE (15/10/2026)
 *
 * Avant le registre de gestionnaires, une `modification` sur `reservations`
 * tombait dans l'`UPDATE` brut du moteur : déplacer un séjour sans repasser
 * par RG-01, basculer `statut` en `annulee` sans `AnnulationReservationService`
 * (ni commission, ni remboursement, ni pièce), réécrire `acompte` sans
 * écriture — trois contournements par une seule porte.
 *
 * L'API elle-même n'offre AUCUNE route de modification générique d'une
 * réservation (seulement la création et l'annulation, chacune avec son
 * service) : la synchronisation n'a pas à offrir plus que l'API. Le refus est
 * explicite (« modification non synchronisable ») ; un protocole de
 * déplacement / annulation hors connexion relève d'un lot ultérieur, chaque
 * geste par son propre service.
 *
 * ## Date métier
 *
 * L'acompte d'une réservation produit sa pièce (`comptabiliserAcompte`) : elle
 * est datée de la date métier du contexte — la saisie au poste — et non du
 * jour de réception (D246, décision PO du 15/10/2026).
 */
final class GestionnaireReservations extends GestionnaireAbstrait
{
    public function __construct(
        private readonly ReservationService $reservations,
        private readonly ResolveurCorrespondances $correspondances,
    ) {
    }

    public function table(): string
    {
        return 'reservations';
    }

    public function module(): string
    {
        return 'M1';
    }

    public function serviceDomaine(): string
    {
        return ReservationService::class;
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        // Les références citées passent par les correspondances : un client
        // créé hors connexion et fusionné côté serveur doit être retrouvé sous
        // son identifiant serveur, sans quoi la clé étrangère casserait.
        foreach (['client_id' => 'clients', 'unite_id' => 'unites_hebergement'] as $champ => $tableCible) {
            if (isset($payload[$champ]) && is_string($payload[$champ])) {
                $payload[$champ] = $this->correspondances->resoudre($tableCible, $payload[$champ]);
            }
        }

        $this->reservations->creer([...$payload, 'id' => $entiteId], $contexte->dateMetierJour());

        return new EcritureSynchronisee($entiteId);
    }
}
