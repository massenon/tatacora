<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Hebergement\Models\CanalReservation;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Services\AnnulationReservationService;
use App\Domain\Hebergement\Services\ReservationService;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use Illuminate\Support\Facades\DB;
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
 *   remboursement et sa pièce, comme à la PWA. **Le serveur ne juge PAS qui
 *   annule** (décision du PO du 09/11/2026 : « aucune opération ne doit bloquer la
 *   synchronisation ») : une annulation envoyée par un poste appairé est ACCEPTÉE
 *   quel que soit le poste d'origine de la réservation et le compte d'appairage ; le
 *   contrôle « qui peut annuler » est fait AU POSTE, par le droit local `ANNULATIONS`.
 *   Ce qui reste refusé est de COHÉRENCE métier (réservation inconnue, taux ou
 *   remboursement invalides, montant total inconnu). La TRAÇABILITÉ est posée avec
 *   l'annulation : le login LOCAL de l'auteur (`auteur`), le poste et le moment où il l'a
 *   saisie (`horodatage_client`) — au lieu du seul compte d'appairage et de l'heure de
 *   réception. (La règle Q3 du 17/10/2026, « l'administration et le comptable »,
 *   `DocumentsDesAutresPostes`, est RETIRÉE pour les réservations ; elle subsiste, ailleurs,
 *   pour les autres documents.) Rejeu : déjà annulée → rendue telle quelle.
 * - DÉPLACEMENT (`unite_id`, `date_arrivee`, `date_depart`) →
 *   `ReservationService::modifier`, sous le verrou de RG-01 : un
 *   chevauchement est refusé avec la phrase du service.
 *
 * - FICHE (09/11/2026, décision du PO : « toute modification — service, prix, acompte,
 *   dates, unité, tag — se propage complètement et identiquement à tous les postes ») :
 *   `client_id`, `tarif_nuit`, `acompte`, `remise_type`, `remise_valeur`, `mode_paiement`,
 *   `canal` (par son NOM) et `lignes` (la composition COURANTE des services, remplacée en
 *   bloc, prix et libellé FIGÉS par le poste : voir
 *   {@see ReservationService::remplacerLignesFigees()}). Le poste n'envoie que les champs
 *   CHANGÉS (dernier écrit gagnant, clé par clé). Le déplacement garde son verrou RG-01,
 *   dans la même transaction que le reste. Comme à la PWA, la modification ne repasse PAS
 *   la pièce de l'acompte (`ReservationService::modifier` ne touche pas à la comptabilité).
 *
 * La CRÉATION porte aussi `lignes` (jamais perdues à l'envoi).
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
    ) {
    }

    /** Les champs d'un DÉPLACEMENT. */
    public const CHAMPS_DEPLACEMENT = ['unite_id', 'date_arrivee', 'date_depart'];

    /** Les champs de la FICHE (09/11/2026), modifiables avec le déplacement. */
    public const CHAMPS_FICHE = ['client_id', 'tarif_nuit', 'acompte', 'remise_type', 'remise_valeur', 'mode_paiement', 'canal', 'lignes'];

    /** Le catalogue de chaque service : la table dont `source_id` désigne une ligne. */
    private const TABLE_DU_SERVICE = [
        'restauration' => 'plats',
        'bar' => 'cartes_boisson',
        'tourisme' => 'circuits',
        'vehicule' => 'vehicules',
        // Chambres SUPPLÉMENTAIRES d'une réservation multi-chambres (10/11/2026) : la source est
        // l'unité d'hébergement ; la première chambre reste dans `unite_id`.
        'hebergement' => 'unites_hebergement',
    ];

    /** Les champs d'une ANNULATION. */
    public const CHAMPS_ANNULATION = ['statut', 'taux', 'mode_remboursement', 'valeur_remboursement', 'auteur'];

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

            $conditions = $this->validerGeste($payload, [
                'taux' => ['required', 'numeric'],
                'mode_remboursement' => ['required', 'string'],
                'valeur_remboursement' => ['required', 'numeric'],
                'auteur' => ['sometimes', 'nullable', 'string', 'max:150'],
            ]);
            try {
                $this->annulation->annuler($reservation, [
                    'taux' => (string) $conditions['taux'],
                    'mode_remboursement' => (string) $conditions['mode_remboursement'],
                    'valeur_remboursement' => (string) $conditions['valeur_remboursement'],
                    // Le moment et la personne de la SAISIE au poste, et le poste.
                    'date' => $contexte->horodatageClient->copy()->utc(),
                    'auteur_login' => ($conditions['auteur'] ?? '') === '' ? null : (string) $conditions['auteur'],
                    'poste' => $contexte->posteId,
                ], $contexte->utilisateur);
            } catch (InvalidArgumentException $e) {
                // Un refus de SAISIE du service (taux, remboursement) : un rejet
                // avec sa phrase, jamais une erreur technique.
                throw new RuntimeException($e->getMessage(), previous: $e);
            }

            return new EcritureSynchronisee($entiteId);
        }

        $this->refuserLesAutresChamps($payload, [...self::CHAMPS_DEPLACEMENT, ...self::CHAMPS_FICHE]);

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
            'client_id' => ['sometimes', 'string'],
            'tarif_nuit' => ['sometimes', 'numeric', 'min:0'],
            'acompte' => ['sometimes', 'numeric', 'min:0'],
            'remise_type' => ['sometimes', 'in:aucune,pourcentage,montant'],
            'remise_valeur' => ['sometimes', 'numeric', 'min:0'],
            'mode_paiement' => ['sometimes', 'nullable', 'in:especes,mobile_money,virement,cheque,credit'],
            'canal' => ['sometimes', 'nullable', 'string'],
            'lignes' => ['sometimes', 'array'],
            'lignes.*.service' => ['required', 'in:' . implode(',', array_keys(self::TABLE_DU_SERVICE))],
            'lignes.*.source_id' => ['required', 'string'],
            'lignes.*.libelle' => ['required', 'string'],
            'lignes.*.quantite' => ['required', 'numeric', 'gt:0'],
            'lignes.*.prix_unitaire' => ['required', 'numeric', 'min:0'],
        ]);

        if (isset($donnees['unite_id'])) {
            $donnees['unite_id'] = $this->correspondances->resoudre('unites_hebergement', (string) $donnees['unite_id']);
        }

        if (isset($donnees['client_id'])) {
            $donnees['client_id'] = $this->correspondances->resoudre('clients', (string) $donnees['client_id']);
        }

        // La CHECK du schéma exige valeur = 0 quand le type est « aucune ».
        if (($donnees['remise_type'] ?? $reservation->remise_type) === 'aucune' && array_key_exists('remise_valeur', $donnees)) {
            $donnees['remise_valeur'] = '0';
        }

        if (array_key_exists('canal', $donnees)) {
            $donnees['canal_id'] = is_string($donnees['canal']) && $donnees['canal'] !== ''
                ? CanalReservation::query()->where('nom', $donnees['canal'])->value('id')
                : null;
            unset($donnees['canal']);
        }

        $lignes = null;

        if (array_key_exists('lignes', $donnees)) {
            $lignes = $this->lignesDuPoste($donnees['lignes']);
            unset($donnees['lignes']);
        }

        try {
            DB::transaction(function () use ($reservation, $donnees, $lignes): void {
                $courante = $donnees === [] ? $reservation : $this->reservations->modifier($reservation, $donnees);

                if ($lignes !== null) {
                    $this->reservations->remplacerLignesFigees($courante, $lignes);
                } elseif ($donnees !== []) {
                    $courante->touch();
                }
            });
        } catch (InvalidArgumentException $e) {
            // Un refus de SAISIE (service inconnu, source disparue, quantité) : un rejet
            // avec la phrase du service, jamais une erreur technique.
            throw new RuntimeException($e->getMessage(), previous: $e);
        }

        return new EcritureSynchronisee($entiteId);
    }

    /**
     * Les services du poste, leurs sources résolues par les correspondances (un circuit
     * fusionné au serveur sur son nom doit être retrouvé sous son identifiant serveur).
     *
     * @param  list<array<string, mixed>>  $lignes
     * @return list<array{service: string, source_id: string, libelle: string, quantite: string, prix_unitaire: string}>
     */
    private function lignesDuPoste(array $lignes): array
    {
        return array_map(fn (array $l): array => [
            'service' => (string) $l['service'],
            'source_id' => $this->correspondances->resoudre(self::TABLE_DU_SERVICE[(string) $l['service']], (string) $l['source_id']),
            'libelle' => (string) $l['libelle'],
            'quantite' => (string) $l['quantite'],
            'prix_unitaire' => (string) $l['prix_unitaire'],
        ], array_values($lignes));
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

        // Les services (09/11/2026) : écrits avec la fiche, dans la même transaction —
        // jamais une réservation sans les lignes que le poste lui a mises.
        $lignes = null;

        if (isset($payload['lignes']) && is_array($payload['lignes']) && $payload['lignes'] !== []) {
            $validees = $this->validerGeste(['lignes' => $payload['lignes']], [
                'lignes' => ['array'],
                'lignes.*.service' => ['required', 'in:' . implode(',', array_keys(self::TABLE_DU_SERVICE))],
                'lignes.*.source_id' => ['required', 'string'],
                'lignes.*.libelle' => ['required', 'string'],
                'lignes.*.quantite' => ['required', 'numeric', 'gt:0'],
                'lignes.*.prix_unitaire' => ['required', 'numeric', 'min:0'],
            ]);
            $lignes = $this->lignesDuPoste($validees['lignes']);
        }

        unset($payload['lignes']);

        try {
            DB::transaction(function () use ($payload, $entiteId, $contexte, $lignes): void {
                $reservation = $this->reservations->creer([...$payload, 'id' => $entiteId], $contexte->dateMetierJour());

                if ($lignes !== null) {
                    $this->reservations->remplacerLignesFigees($reservation, $lignes);
                }
            });
        } catch (InvalidArgumentException $e) {
            throw new RuntimeException($e->getMessage(), previous: $e);
        }

        return new EcritureSynchronisee($entiteId);
    }
}
