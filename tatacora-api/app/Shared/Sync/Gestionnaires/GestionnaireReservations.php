<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Hebergement\Models\CanalReservation;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Services\AnnulationReservationService;
use App\Domain\Hebergement\Services\ReservationService;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\DocumentsDesAutresPostes;
use App\Shared\Sync\Support\EcritureSynchronisee;
use Illuminate\Support\Facades\Validator;
use InvalidArgumentException;
use RuntimeException;

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
 * ## Modification : deux gestes, chacun par SON service (lot F6, 17/10/2026)
 *
 * - ANNULATION (`statut: annulee` + `taux`, `mode_remboursement`,
 *   `valeur_remboursement`) → `AnnulationReservationService` : commission,
 *   remboursement et sa pièce, comme à la PWA. Une réservation d'un autre
 *   poste ne s'annule que par l'administration ou le comptable (Q3,
 *   `DocumentsDesAutresPostes`). Rejeu : déjà annulée → rendue telle quelle.
 * - DÉPLACEMENT (`unite_id`, `date_arrivee`, `date_depart`) →
 *   `ReservationService::modifier`, sous le verrou de RG-01 : un
 *   chevauchement est refusé avec la phrase du service.
 *
 * Tout autre champ reste refusé. Historique ci-dessous (15/10/2026).
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
        private readonly AnnulationReservationService $annulation,
        private readonly DocumentsDesAutresPostes $autresPostes,
    ) {
    }

    /** Les champs d'un DÉPLACEMENT. */
    public const CHAMPS_DEPLACEMENT = ['unite_id', 'date_arrivee', 'date_depart'];

    /** Les champs d'une ANNULATION. */
    public const CHAMPS_ANNULATION = ['statut', 'taux', 'mode_remboursement', 'valeur_remboursement'];

    public function accepteModification(): bool
    {
        return true;
    }

    public function modifier(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $reservation = Reservation::query()->findOrFail($entiteId);

        if (($payload['statut'] ?? null) === 'annulee') {
            $this->refuserLesAutresChamps($payload, self::CHAMPS_ANNULATION);

            if ($reservation->statut === 'annulee') {
                return new EcritureSynchronisee($entiteId);
            }

            $this->autresPostes->verifierAnnulation('reservations', $entiteId, $contexte);
            $conditions = $this->validerGeste($payload, [
                'taux' => ['required', 'numeric'],
                'mode_remboursement' => ['required', 'string'],
                'valeur_remboursement' => ['required', 'numeric'],
            ]);
            try {
                $this->annulation->annuler($reservation, [
                    'taux' => (string) $conditions['taux'],
                    'mode_remboursement' => (string) $conditions['mode_remboursement'],
                    'valeur_remboursement' => (string) $conditions['valeur_remboursement'],
                ], $contexte->utilisateur);
            } catch (InvalidArgumentException $e) {
                // Un refus de SAISIE du service (taux, remboursement) : un rejet
                // avec sa phrase, jamais une erreur technique.
                throw new RuntimeException($e->getMessage(), previous: $e);
            }

            return new EcritureSynchronisee($entiteId);
        }

        $this->refuserLesAutresChamps($payload, self::CHAMPS_DEPLACEMENT);

        if ($payload === []) {
            throw new RuntimeException(__('sync.modification_non_synchronisable'));
        }

        if ($reservation->statut === 'annulee') {
            throw new RuntimeException(__('sync.reservations.annulee'));
        }

        $donnees = $this->validerGeste($payload, [
            'unite_id' => ['sometimes', 'string'],
            'date_arrivee' => ['sometimes', 'date_format:Y-m-d'],
            'date_depart' => ['sometimes', 'date_format:Y-m-d'],
        ]);

        if (isset($donnees['unite_id'])) {
            $donnees['unite_id'] = $this->correspondances->resoudre('unites_hebergement', (string) $donnees['unite_id']);
        }

        $this->reservations->modifier($reservation, $donnees);

        return new EcritureSynchronisee($entiteId);
    }

    /**
     * @param  array<string, mixed>  $payload
     * @param  list<string>  $admis
     */
    private function refuserLesAutresChamps(array $payload, array $admis): void
    {
        $refuses = array_diff(array_keys($payload), $admis);

        if ($refuses !== []) {
            throw new RuntimeException(__('sync.reservations.champ_non_modifiable', ['champs' => implode(', ', $refuses)]));
        }
    }

    /**
     * @param  array<string, mixed>  $payload
     * @param  array<string, mixed>  $regles
     * @return array<string, mixed>
     */
    private function validerGeste(array $payload, array $regles): array
    {
        $validateur = Validator::make($payload, $regles);

        if ($validateur->fails()) {
            throw new RuntimeException((string) $validateur->errors()->first());
        }

        return $validateur->validated();
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

        // Lot 10f : le canal arrive par son NOM (le poste ne connaît pas les
        // identifiants du serveur) ; un nom inconnu laisse la réservation
        // sans canal plutôt que de la refuser.
        $nomCanal = $payload['canal'] ?? null;
        unset($payload['canal']);

        if (is_string($nomCanal) && $nomCanal !== '') {
            $payload['canal_id'] = CanalReservation::query()->where('nom', $nomCanal)->value('id');
        }

        $this->reservations->creer([...$payload, 'id' => $entiteId], $contexte->dateMetierJour());

        return new EcritureSynchronisee($entiteId);
    }
}
