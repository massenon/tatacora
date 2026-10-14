<?php

declare(strict_types=1);

namespace App\Domain\Hebergement\Models;

use App\Domain\Crm\Models\Client;
use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Réservation d'hébergement (M1).
 *
 * @see EF-M1-02 Création, modification et annulation de réservation
 * @see RG-01 Prévention des doubles réservations — garantie par
 *      VerificationChevauchementService (verrou pessimiste en transaction),
 *      jamais par une simple requête WHERE avant insertion.
 * @see RG-15 Journalisation (trait Auditable)
 *
 * @property string $id
 * @property string $client_id
 * @property string $unite_id
 * @property \Illuminate\Support\Carbon $date_arrivee
 * @property \Illuminate\Support\Carbon $date_depart
 * @property string $statut
 * @property string $acompte
 * @property string|null $canal_id
 * @property string|null $tarif_nuit
 * @property string $remise_type
 * @property string $remise_valeur
 * @property string|null $mode_paiement
 * @property string|null $taux_annulation
 * @property string|null $montant_total_annulation
 * @property string|null $montant_commission_annulation
 * @property string|null $montant_rembourse_annulation
 * @property string|null $mode_saisie_remboursement
 * @property \Illuminate\Support\Carbon|null $date_annulation
 * @property string|null $utilisateur_annulation_id
 * @property string|null $ecriture_remboursement_id
 */
class Reservation extends Model
{
    use Auditable;
    use HasUuids;

    protected $table = 'reservations';

    protected $fillable = [
        'id',
        'client_id',
        'unite_id',
        'date_arrivee',
        'date_depart',
        'statut',
        'acompte',
        // La fiche du maître, au schéma depuis PA-163 (01/09/2026). Toutes
        // optionnelles : un lot Flutter qui ne les envoie pas reste valide.
        'canal_id',
        'tarif_nuit',
        'remise_type',
        'remise_valeur',
        'mode_paiement',
        // L'annulation (EF-M1-06, séance client 18-20/08/2026) — écrites
        // EXCLUSIVEMENT par AnnulationReservationService, jamais saisies
        // directement : voir la migration 2026_09_03_220000 pour la raison
        // de chaque colonne.
        'taux_annulation',
        'montant_total_annulation',
        'montant_commission_annulation',
        'montant_rembourse_annulation',
        'mode_saisie_remboursement',
        'date_annulation',
        'utilisateur_annulation_id',
        'ecriture_remboursement_id',
    ];

    protected function casts(): array
    {
        return [
            'date_arrivee' => 'date',
            'date_depart' => 'date',
            // Montant : DECIMAL(15,2), jamais un flottant (AVOID_INSTRUCTIONS.md §6)
            'acompte' => 'decimal:2',
            'tarif_nuit' => 'decimal:2',
            'remise_valeur' => 'decimal:2',
            'date_creation' => 'datetime',
            'date_modification' => 'datetime',
            'taux_annulation' => 'decimal:2',
            'montant_total_annulation' => 'decimal:2',
            'montant_commission_annulation' => 'decimal:2',
            'montant_rembourse_annulation' => 'decimal:2',
            'date_annulation' => 'datetime',
        ];
    }

    /**
     * Nombre de nuitées — CALCULÉ, jamais stocké ni soumis dans un formulaire.
     *
     * Le schéma ne porte volontairement aucune colonne `nb_nuitees` : une valeur
     * dérivable d'une source de vérité unique ne doit pas pouvoir diverger
     * d'elle (A1_MASTER_PROMPT.md §2.2).
     */
    public function nombreNuitees(): int
    {
        return (int) $this->date_arrivee->diffInDays($this->date_depart);
    }

    /**
     * Vraie clé étrangère vers la fiche client unique (RG-18) — jamais un
     * champ texte libre recopiant le nom du client.
     *
     * @return BelongsTo<Client, $this>
     */
    public function client(): BelongsTo
    {
        return $this->belongsTo(Client::class, 'client_id');
    }

    /**
     * @return BelongsTo<UniteHebergement, $this>
     */
    public function unite(): BelongsTo
    {
        return $this->belongsTo(UniteHebergement::class, 'unite_id');
    }

    /**
     * @return BelongsTo<CanalReservation, $this>
     */
    public function canal(): BelongsTo
    {
        return $this->belongsTo(CanalReservation::class, 'canal_id');
    }

    /**
     * Les lignes de services de la fiche — quatre services, jamais cinq :
     * l'hébergement vit sur `unite_id` (voir la migration de PA-163).
     *
     * @return \Illuminate\Database\Eloquent\Relations\HasMany<LigneReservation, $this>
     */
    public function lignes(): \Illuminate\Database\Eloquent\Relations\HasMany
    {
        return $this->hasMany(LigneReservation::class, 'reservation_id');
    }

    /**
     * Une réservation annulée n'occupe plus l'unité (RG-02).
     */
    public function estActive(): bool
    {
        return $this->statut !== 'annulee';
    }

    /**
     * L'état du séjour, DÉRIVÉ des dates à la date fournie — jamais stocké.
     *
     * Quatre états, dont un seul est une donnée : l'annulation. Les trois
     * autres se déduisent des dates (PA-111) — les stocker exigerait de les
     * faire vieillir chaque nuit. La formule vivait en privé dans l'écran
     * Réservations (`Pwa\Livewire\Hebergement\Reservations`) ; elle est
     * remontée ici le 02/09/2026 pour que la carte « Réservations &
     * hébergement » de l'accueil lise LA MÊME dérivation que l'écran — deux
     * calculs finiraient par se contredire sur deux écrans (PA-121).
     *
     * ⚠ Le jour du départ compte « en cours » (bornes inclusives) : c'est la
     * règle de l'écran Réservations, reprise telle quelle. Elle diffère de
     * l'occupation de la NUIT (RG-01, bornes semi-ouvertes) — l'état d'un
     * séjour et l'occupation d'une chambre ne répondent pas à la même
     * question.
     *
     * @return string 'a_venir'|'en_cours'|'termine'|'annulee'
     */
    public function etatDerive(\Carbon\CarbonImmutable $aujourdhui): string
    {
        $jour = $aujourdhui->toDateString();
        $arrivee = $this->date_arrivee->toDateString();
        $depart = $this->date_depart->toDateString();

        return match (true) {
            $this->statut === 'annulee' => 'annulee',
            $depart < $jour => 'termine',
            $arrivee <= $jour && $jour <= $depart => 'en_cours',
            default => 'a_venir',
        };
    }

    // =====================================================================
    // Récapitulatif — UNE formule, `bcmath`, jamais recomposée en vue
    // =====================================================================

    /**
     * Part hébergement du récapitulatif : `tarif_nuit` figé × nuitées.
     *
     * `null` quand la réservation ne porte aucun tarif figé — les fiches
     * antérieures à PA-163, et celles descendues de Flutter (PA-57). Rendre
     * `0` à la place afficherait un séjour gratuit sur l'écran même qui sert
     * à encaisser ; rendre le tarif COURANT du parc réécrirait un prix
     * convenu (PA-55). L'absence se dit, elle ne s'invente pas.
     */
    public function sousTotalHebergement(): ?string
    {
        if ($this->tarif_nuit === null) {
            return null;
        }

        return bcmul((string) $this->tarif_nuit, (string) $this->nombreNuitees(), 2);
    }

    /**
     * Sous-total de la fiche : hébergement + lignes de services.
     *
     * `null` dès que la part hébergement est inconnue — un sous-total qui ne
     * compterait que les lignes serait plausible et faux, le défaut PA-110
     * dans l'autre sens.
     */
    public function sousTotal(): ?string
    {
        $hebergement = $this->sousTotalHebergement();

        if ($hebergement === null) {
            return null;
        }

        $total = $hebergement;

        foreach ($this->lignes as $ligne) {
            $total = bcadd($total, (string) $ligne->montant, 2);
        }

        return $total;
    }

    /**
     * Montant de la remise, DÉRIVÉ du type et de la valeur saisis — le maître
     * stocke l'intention (« 10 % »), jamais un montant pré-calculé qui
     * deviendrait faux au premier ajout de ligne.
     */
    public function montantRemise(): ?string
    {
        $sousTotal = $this->sousTotal();

        if ($sousTotal === null) {
            return null;
        }

        return match ($this->remise_type) {
            'pourcentage' => bcdiv(bcmul($sousTotal, (string) $this->remise_valeur, 4), '100', 2),
            'montant' => bcadd((string) $this->remise_valeur, '0', 2),
            default => '0.00',
        };
    }

    /**
     * Reste à payer : sous-total − remise − acompte. La MÊME formule que le
     * client Flutter (PA-111 : la remise ignorée faisait réclamer au client
     * l'argent qu'on venait de lui accorder) — la reproduire fausse ici
     * recréerait le défaut sur l'autre canal.
     */
    public function resteAPayer(): ?string
    {
        $sousTotal = $this->sousTotal();
        $remise = $this->montantRemise();

        if ($sousTotal === null || $remise === null) {
            return null;
        }

        return bcsub(bcsub($sousTotal, $remise, 2), (string) $this->acompte, 2);
    }

    /**
     * Montant TOTAL de la réservation — sous-total moins remise, AVANT
     * déduction de l'acompte. C'est la grandeur sur laquelle le client a
     * validé que la commission d'annulation se calcule, JAMAIS sur le seul
     * acompte versé (`Rapport_Presentation_Echange_TATACORA_AFRIQUE.pdf`
     * §4.3). Recompose les DEUX primitives déjà éprouvées du récapitulatif —
     * `sousTotal()` et `montantRemise()` — au lieu d'une troisième formule
     * qui finirait par diverger (PA-121).
     *
     * `null` dans les mêmes conditions que `sousTotal()` : une réservation
     * sans `tarif_nuit` figé (antérieure à PA-163) ne permet aucun calcul
     * fiable — {@see \App\Domain\Hebergement\Services\AnnulationReservationService}
     * REFUSE alors l'annulation chiffrée plutôt que d'inventer un montant.
     */
    public function montantTotal(): ?string
    {
        $sousTotal = $this->sousTotal();
        $remise = $this->montantRemise();

        if ($sousTotal === null || $remise === null) {
            return null;
        }

        return bcsub($sousTotal, $remise, 2);
    }

    /**
     * La ligne de contrepartie (compte 4191) de la pièce comptable posée
     * quand l'annulation a réellement fait sortir de l'argent de la caisse —
     * `null` tant qu'aucun remboursement numéraire n'a eu lieu.
     *
     * @return BelongsTo<\App\Domain\Comptabilite\Models\EcritureComptable, $this>
     */
    public function ecritureRemboursement(): BelongsTo
    {
        return $this->belongsTo(\App\Domain\Comptabilite\Models\EcritureComptable::class, 'ecriture_remboursement_id');
    }

    /**
     * L'utilisateur qui a effectué l'annulation — `null` pour une réservation
     * jamais annulée. Distinct de `utilisateur_modification_id` (générique,
     * réécrit par tout `update()` ultérieur) : voir la migration
     * 2026_09_03_220000.
     *
     * @return BelongsTo<\App\Models\User, $this>
     */
    public function utilisateurAnnulation(): BelongsTo
    {
        return $this->belongsTo(\App\Models\User::class, 'utilisateur_annulation_id');
    }
}
