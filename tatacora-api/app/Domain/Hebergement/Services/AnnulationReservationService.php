<?php

declare(strict_types=1);

namespace App\Domain\Hebergement\Services;

use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Services\PasserEcritureService;
use App\Domain\Comptabilite\Support\ComptesSyscohada;
use App\Domain\Depenses\Services\DepenseService;
use App\Domain\Hebergement\Models\Reservation;
use App\Models\User;
use App\Shared\Parametres\Services\ParametreSystemeService;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use InvalidArgumentException;
use RuntimeException;

/**
 * Annulation de réservation avec commission et remboursement — EF-M1-06.
 *
 * @see `Rapport_Presentation_Echange_TATACORA_AFRIQUE.pdf` §4.3, §4.4, §6.1, §6.3
 *      (séance client du 18 et 20/08/2026, taux de référence 50 % confirmé en
 *      séance sous réserve de paramétrage — §6.3)
 *
 * ## Ce que ce service fait, dans l'ordre du principe fonctionnel du client
 *
 * 1. identifier la réservation (passée en paramètre par l'appelant — écran
 *    ou test, jamais retrouvée ici par du texte libre) ;
 * 2. calculer le délai entre l'instant présent et la date prévue
 *    ({@see delaiHeuresAvantArrivee}) — INFORMATIF, voir plus bas pourquoi il
 *    ne branche PAS automatiquement le taux ;
 * 3. appliquer le taux TRANSMIS par l'appelant (jamais recalculé ici : la
 *    décision reste humaine, voir plus bas) ;
 * 4. déterminer le montant conservé (commission) et le montant remboursé ;
 * 5. enregistrer l'opération — les huit colonnes de la migration
 *    2026_09_03_220000, avec auteur et horodatage ;
 * 6. « mettre à jour automatiquement la situation financière du client » : la
 *    moitié CAISSE de cette phrase est tenue ici (RG rappelée par le dépôt —
 *    tout mouvement d'argent produit sa vraie écriture comptable, même
 *    transaction, refus si la pièce est refusée). La moitié CRÉANCE — un
 *    solde relevé au-delà de ce qui a été encaissé — N'EST PAS tenue : elle
 *    dépendrait d'un `Paiement` qui n'a AUCUN writer dans tout ce dépôt
 *    (constat du 31/08/2026), et l'inventer ici serait la même faute que
 *    PA-21 sous une forme neuve. Hors périmètre de cette tâche, nommé plutôt
 *    que masqué.
 *
 * ## Pourquoi le taux « 50 % si < 24h » n'est PAS un automatisme fermé
 *
 * Le compte rendu client valide EXPLICITEMENT un seul cas : « annulation à
 * MOINS DE 24 HEURES → 50 % ». Sa propre note de bas de page (§4.4, en
 * italique) dit le reste : « le taux de 50 % ET LES AUTRES CONDITIONS
 * PRÉCISES D'ANNULATION devront être confirmés et validés par TATACORA
 * AFRIQUE avant leur paramétrage définitif ». Un barème à paliers (0 % au-delà
 * de 24h, 25 % entre 24 et 48h, etc.) serait un chiffre plausible inventé
 * pour le cas complémentaire — exactement ce que la Règle n°2 du dépôt
 * interdit (« aucune donnée réglementaire n'est devinée »).
 *
 * Ce service calcule et EXPOSE donc le délai ({@see delaiHeuresAvantArrivee},
 * {@see estSousLeSeuil}) pour que l'écran l'affiche, mais le TAUX appliqué
 * est toujours celui que l'opérateur a validé dans le formulaire — pré-rempli
 * avec le taux paramétrable ({@see tauxParDefaut}), modifiable ligne par
 * ligne, comme l'exige l'instruction du Product Owner. Le jour où
 * TATACORA AFRIQUE confirme un barème à plusieurs paliers, il se branche ICI,
 * à un seul endroit.
 *
 * ## Commission sur le MONTANT GLOBAL — jamais sur l'acompte (§4.3, non négociable)
 *
 * `montant_commission_annulation = montant_total × taux / 100`. Si ce
 * montant dépasse l'acompte réellement détenu, le remboursement est
 * simplement nul (on ne peut pas restituer un argent qui n'a jamais été
 * encaissé) — le service ne fabrique jamais un remboursement négatif.
 *
 * ## Remboursement : deux façons de saisir le MÊME nombre
 *
 * L'opérateur choisit `pourcentage` (fraction de l'ACOMPTE à restituer) ou
 * `montant` (chiffre FCFA direct) — jamais les deux à la fois, jamais stocké
 * deux fois (PA-121). Le remboursement ne peut jamais dépasser l'acompte
 * réellement versé : restituer plus que ce qui a été encaissé viderait la
 * caisse d'un argent qu'elle n'a jamais reçu.
 *
 * ## Caisse ↔ comptabilité, ou rien du tout
 *
 * Remboursement > 0 : une pièce est passée AVANT l'écriture des colonnes
 * d'annulation, dans la MÊME transaction — DÉBIT 4191 « Clients — avances
 * et acomptes reçus » (la dette envers le client s'éteint), CRÉDIT 5711
 * « Caisse en monnaie nationale » (l'argent sort réellement du tiroir). Si la pièce est refusée
 * (compte, journal, exercice, centre absent), RIEN n'est écrit — ni pièce, ni
 * annulation. Remboursement = 0 : aucune pièce n'est fabriquée — un mouvement
 * de caisse qui n'a jamais eu lieu ne doit jamais apparaître au grand livre.
 *
 * @see EF-M1-06 Annulation de réservation avec commission et remboursement
 * @see RG-02 Libération automatique après annulation (déléguée à
 *      ReservationService::annuler(), inchangée, pour ne rien casser des
 *      chemins API/synchronisation qui l'appellent déjà)
 */
class AnnulationReservationService
{
    /**
     * Clé du paramètre système — taux de référence pour une annulation à
     * moins de 24h, PARAMÉTRABLE sans redéploiement (§4.4, §6.2, §6.3 :
     * « le taux applicable en cas d'annulation tardive sera paramétrable »).
     */
    public const CLE_TAUX_MOINS_24H = 'hebergement_taux_annulation_moins_24h';

    /**
     * Le taux de référence retenu en séance (§4.4, §6.3) — utilisé UNIQUEMENT
     * comme repli quand l'Administrateur n'a jamais renseigné le paramètre,
     * jamais recopié en dur ailleurs.
     */
    public const TAUX_REFERENCE_PAR_DEFAUT = '50.00';

    /** Le seuil validé en séance — « moins de 24 heures avant la prestation ». */
    public const SEUIL_HEURES = 24;

    /**
     * 4191 « Clients — avances et acomptes reçus (arrhes de réservation,
     * EF-M1-06) » — ATELIER_PLAN_COMPTABLE.md, seul compte du plan documenté
     * qui porte les arrhes d'hébergement. Aucun autre n'est substitué : un
     * compte manquant se refuse, ne s'invente pas (règle du dépôt).
     */
    public const COMPTE_AVANCES_CLIENTS = ComptesSyscohada::AVANCES_CLIENTS;

    private const PRECISION = 2;

    public function __construct(
        private readonly ReservationService $reservations,
        private readonly PasserEcritureService $ecritures,
        private readonly ParametreSystemeService $parametres,
    ) {
    }

    /**
     * Le taux à PRÉ-REMPLIR dans le formulaire — jamais imposé, l'opérateur
     * le modifie ligne par ligne (instruction du Product Owner, 01/09/2026).
     */
    public function tauxParDefaut(): string
    {
        return (string) $this->parametres->get(self::CLE_TAUX_MOINS_24H, self::TAUX_REFERENCE_PAR_DEFAUT);
    }

    /**
     * Délai, en heures, entre MAINTENANT et le début de la journée d'arrivée.
     *
     * `reservations.date_arrivee` est une DATE, sans heure d'arrivée connue
     * du schéma : convention EXPLICITE et documentée, pas une donnée
     * réglementaire devinée — minuit du jour d'arrivée sert de référence,
     * faute d'heure de check-in paramétrée ailleurs dans ce dépôt. Négatif
     * quand la date d'arrivée est déjà passée.
     */
    public function delaiHeuresAvantArrivee(Reservation $reservation, ?Carbon $maintenant = null): float
    {
        $maintenant ??= Carbon::now();
        $reference = Carbon::parse($reservation->date_arrivee->toDateString())->startOfDay();

        // Différence de timestamps, jamais `diffInHours()` : cette méthode a
        // changé de signe selon les versions de Carbon entre l'appelant et
        // l'appelé (`$abs`) — la soustraction directe ne laisse aucune
        // ambiguïté. Positif : la date d'arrivée est encore à venir.
        return ($reference->getTimestamp() - $maintenant->getTimestamp()) / 3600.0;
    }

    /** Le cas de référence validé en séance : moins de 24h avant la prestation. */
    public function estSousLeSeuil(Reservation $reservation, ?Carbon $maintenant = null): bool
    {
        return $this->delaiHeuresAvantArrivee($reservation, $maintenant) < self::SEUIL_HEURES;
    }

    /**
     * Annule la réservation en appliquant taux, commission et remboursement.
     *
     * @param  array{taux: string, mode_remboursement: string, valeur_remboursement: string}  $conditions
     *
     * @throws InvalidArgumentException taux hors bornes, mode inconnu, ou
     *                                   remboursement supérieur à l'acompte
     * @throws RuntimeException réservation déjà annulée, ou montant total
     *                          inconnu (aucun tarif figé — réservation
     *                          antérieure à PA-163)
     */
    public function annuler(Reservation $reservation, array $conditions, User $auteur): Reservation
    {
        if ($reservation->statut === 'annulee') {
            throw new RuntimeException(__('hebergement_pwa.reservations.annulation_impossible'));
        }

        $montantTotal = $reservation->montantTotal();

        if ($montantTotal === null) {
            // Article 9 du dépôt : refuser plutôt qu'inventer. Une
            // réservation sans tarif figé n'a pas de montant global fiable —
            // calculer une commission dessus produirait un chiffre sans
            // fondement sur une opération qui touche la caisse.
            throw new RuntimeException(__('hebergement.annulation_montant_total_inconnu'));
        }

        $taux = $this->normaliserTaux((string) $conditions['taux']);
        $commission = bcdiv(bcmul($montantTotal, $taux, 4), '100', self::PRECISION);

        $acompte = (string) $reservation->acompte;
        $montantRembourse = $this->calculerRemboursement(
            $acompte,
            (string) $conditions['mode_remboursement'],
            (string) $conditions['valeur_remboursement'],
        );

        return DB::transaction(function () use (
            $reservation,
            $conditions,
            $taux,
            $montantTotal,
            $commission,
            $montantRembourse,
            $auteur
        ): Reservation {
            // RG-02 : la même primitive que tout autre chemin d'annulation
            // (API, synchronisation) — jamais réécrite ici, voir l'entête de
            // classe.
            $this->reservations->annuler($reservation);

            $ecritureId = null;

            if (bccomp($montantRembourse, '0.00', self::PRECISION) > 0) {
                $ecritureId = $this->passerEcritureRemboursement($reservation, $montantRembourse);
            }

            $reservation->update([
                'taux_annulation' => $taux,
                'montant_total_annulation' => $montantTotal,
                'montant_commission_annulation' => $commission,
                'montant_rembourse_annulation' => $montantRembourse,
                'mode_saisie_remboursement' => (string) $conditions['mode_remboursement'],
                'date_annulation' => Carbon::now(),
                'utilisateur_annulation_id' => $auteur->id,
                'ecriture_remboursement_id' => $ecritureId,
            ]);

            return $reservation->refresh();
        });
    }

    private function normaliserTaux(string $taux): string
    {
        $normalise = bcadd($taux, '0', self::PRECISION);

        if (bccomp($normalise, '0', self::PRECISION) < 0 || bccomp($normalise, '100', self::PRECISION) > 0) {
            throw new InvalidArgumentException(__('hebergement.annulation_taux_invalide'));
        }

        return $normalise;
    }

    /**
     * Dérive le montant remboursé de la saisie de l'opérateur, quelle que
     * soit la façon dont il l'a exprimée — jamais plus que l'acompte détenu.
     */
    private function calculerRemboursement(string $acompte, string $mode, string $valeur): string
    {
        $valeur = bcadd($valeur, '0', self::PRECISION + 2);

        if (bccomp($valeur, '0', self::PRECISION) < 0) {
            throw new InvalidArgumentException(__('hebergement.annulation_remboursement_negatif'));
        }

        $montant = match ($mode) {
            'pourcentage' => bcdiv(bcmul($acompte, $valeur, 4), '100', self::PRECISION),
            'montant' => bcadd($valeur, '0', self::PRECISION),
            default => throw new InvalidArgumentException(__('hebergement.annulation_mode_remboursement_inconnu', ['mode' => $mode])),
        };

        if (bccomp($montant, $acompte, self::PRECISION) > 0) {
            throw new InvalidArgumentException(__('hebergement.annulation_remboursement_superieur_acompte'));
        }

        return $montant;
    }

    /**
     * Pose la pièce du remboursement — DÉBIT 4191, CRÉDIT 5711, journal
     * CAI — et renvoie l'identifiant de la ligne DÉBIT (le compte spécifique
     * à cette opération, symétrique du choix fait pour `ventes.ecriture_id`).
     *
     * La trésorerie est TOUJOURS la caisse : le compte rendu client et
     * l'instruction du Product Owner ne parlent que d'argent qui « sort
     * réellement de la caisse », jamais d'un virement ou d'un Mobile Money.
     * Le compte et le journal viennent de `DepenseService::TRESORERIES`,
     * jamais recopiés en dur ici (PA-121).
     */
    private function passerEcritureRemboursement(Reservation $reservation, string $montant): string
    {
        $tresorerie = DepenseService::TRESORERIES['caisse'];

        $piece = $this->ecritures->passerEtValider([
            'journal' => $tresorerie['journal'],
            'date' => Carbon::now()->toDateString(),
            'libelle' => __('hebergement.annulation_libelle_ecriture', [
                'client' => (string) ($reservation->client?->nomComplet() ?? $reservation->id),
            ]),
            'lignes' => [
                [
                    'compte' => self::COMPTE_AVANCES_CLIENTS,
                    'debit' => $montant,
                    'credit' => '0.00',
                ],
                [
                    'compte' => $tresorerie['compte'],
                    'debit' => '0.00',
                    'credit' => $montant,
                ],
            ],
        ]);

        return $this->ligneAvancesClients($piece);
    }

    /**
     * @param  Collection<int, EcritureComptable>  $piece
     */
    private function ligneAvancesClients(Collection $piece): string
    {
        foreach ($piece as $ecriture) {
            if (bccomp((string) $ecriture->debit, '0.00', self::PRECISION) > 0) {
                return $ecriture->id;
            }
        }

        // Inatteignable tant que `passerEcritureRemboursement()` construit la
        // pièce ci-dessus : si ce refus tombe, la forme de la pièce a changé.
        throw new RuntimeException(__('hebergement.annulation_ligne_ecriture_absente'));
    }
}
