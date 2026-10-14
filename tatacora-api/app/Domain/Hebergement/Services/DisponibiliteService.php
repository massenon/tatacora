<?php

declare(strict_types=1);

namespace App\Domain\Hebergement\Services;

use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Shared\Integrite\Services\VerificationChevauchementService;
use Illuminate\Database\Eloquent\Collection as EloquentCollection;
use Illuminate\Support\Collection;

/**
 * Calcul de la disponibilité des unités d'hébergement — RG-02.
 *
 * **Toujours calculée, jamais stockée.** Aucune colonne `disponible` n'existe
 * sur `unites_hebergement` et il ne faut jamais en ajouter : une annulation
 * doit libérer l'unité instantanément dans le calendrier, sans qu'aucun
 * traitement n'ait à propager l'information. Une disponibilité dénormalisée
 * serait fausse dès la première annulation qu'un job aurait manquée — et
 * personne ne le remarquerait avant une double-réservation réelle.
 *
 * @see EF-M1-01 Consultation des disponibilités
 * @see EF-M1-07 Planning d'occupation
 * @see RG-02 Libération automatique après annulation
 */
class DisponibiliteService
{
    public function __construct(
        private readonly VerificationChevauchementService $verification,
    ) {
    }

    /**
     * Une unité précise est-elle libre sur la période demandée ?
     */
    public function uniteEstDisponible(
        string $uniteId,
        string $dateArrivee,
        string $dateDepart,
        ?string $exclureReservationId = null,
    ): bool {
        $unite = UniteHebergement::find($uniteId);

        if ($unite === null || ! $unite->estCommercialisable()) {
            return false;
        }

        return $this->verification->plagesEnConflit(
            tablePlages: 'reservations',
            colonneRessource: 'unite_id',
            ressourceId: $uniteId,
            colonneDebut: 'date_arrivee',
            colonneFin: 'date_depart',
            debut: $dateArrivee,
            fin: $dateDepart,
            exclureId: $exclureReservationId,
        ) === [];
    }

    /**
     * Unités libres sur la période, éventuellement filtrées par catégorie.
     *
     * @return Collection<int, UniteHebergement>
     */
    public function unitesDisponibles(
        string $dateArrivee,
        string $dateDepart,
        ?string $categorieId = null,
    ): Collection {
        // Une seule requête pour les unités occupées, puis un filtre en
        // mémoire : interroger la disponibilité unité par unité produirait un
        // N+1 sur le planning d'occupation, qui affiche tout le parc
        // (PROMPT_AVOID_ERREURS_LARAVEL_LIVEWIRE.md, point 8).
        $unitesOccupees = Reservation::query()
            ->whereNot('statut', 'annulee')
            ->where('date_arrivee', '<', $dateDepart)
            ->where('date_depart', '>', $dateArrivee)
            ->pluck('unite_id')
            ->unique()
            ->all();

        return UniteHebergement::query()
            ->when($categorieId !== null, fn ($q) => $q->where('categorie_id', $categorieId))
            ->whereNotIn('id', $unitesOccupees)
            ->get()
            ->filter(fn (UniteHebergement $unite): bool => $unite->estCommercialisable())
            ->values();
    }

    /**
     * Planning d'occupation d'une période (EF-M1-07) : pour chaque unité, les
     * réservations actives qui la couvrent.
     *
     * @return Collection<array-key, EloquentCollection<int, Reservation>>
     */
    public function planningOccupation(string $dateDebut, string $dateFin): Collection
    {
        $parUnite = Reservation::query()
            ->with('client')
            ->whereNot('statut', 'annulee')
            ->where('date_arrivee', '<', $dateFin)
            ->where('date_depart', '>', $dateDebut)
            ->get()
            ->groupBy('unite_id')
            ->all();

        return collect($parUnite);
    }
}
