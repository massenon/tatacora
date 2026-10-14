<?php

declare(strict_types=1);

namespace App\Domain\Crm\Services;

use App\Domain\Hebergement\Models\Reservation;
use Illuminate\Support\Collection;

/**
 * Historique consolidé d'un client — EF-M3-02.
 *
 * **Vue agrégée, jamais une dénormalisation stockée sur `clients`.** Le CdCF §8
 * documente quatre relations depuis `clients` : `reservations`, `factures`,
 * `contrats_location`, `reservations_tour`. L'historique les interroge à la
 * demande ; aucune colonne récapitulative n'est ajoutée à la fiche client.
 *
 * ## Pourquoi ce service déclare ses sources indisponibles
 *
 * Trois des quatre domaines sources (M2 Facturation, M8 Véhicules, M9 Tourisme)
 * ne sont pas encore implémentés. Un historique qui les omettrait silencieusement
 * serait pire qu'un historique absent : un gérant consultant la fiche d'un client
 * y lirait « aucune facture » et en conclurait qu'il ne doit rien, alors que la
 * réponse exacte est « la facturation n'est pas encore dans le système ».
 *
 * La réponse porte donc explicitement, pour chaque source, si elle est
 * `disponible` ou `en_attente_de_module`. L'interface doit afficher cette
 * distinction — elle ne doit jamais présenter un historique partiel comme complet.
 */
class ClientHistoriqueService
{
    /**
     * Les quatre sources documentées au CdCF §8, avec l'état d'implémentation
     * de leur domaine. Passer une source à `true` est la seule modification
     * requise ici quand son sprint la livre.
     *
     * @var array<string, array{libelle: string, module: string, disponible: bool}>
     */
    private const SOURCES = [
        'sejours' => ['libelle' => 'Séjours', 'module' => 'M1', 'disponible' => true],
        'factures' => ['libelle' => 'Factures', 'module' => 'M2', 'disponible' => false],
        'locations' => ['libelle' => 'Locations de véhicule', 'module' => 'M8', 'disponible' => false],
        'circuits' => ['libelle' => 'Circuits touristiques', 'module' => 'M9', 'disponible' => false],
    ];

    /**
     * @return array{
     *     sejours: Collection<int, Reservation>,
     *     sources: array<string, array{libelle: string, module: string, statut: string}>,
     *     complet: bool
     * }
     */
    public function pourClient(string $clientId): array
    {
        return [
            'sejours' => $this->sejours($clientId),
            'sources' => $this->etatDesSources(),
            // Tant que ce drapeau est faux, aucune conclusion négative ne peut
            // être tirée de l'historique (« ce client n'a aucune facture »).
            'complet' => $this->toutesSourcesDisponibles(),
        ];
    }

    /**
     * Séjours du client, les plus récents en premier — M1, seule source
     * réellement disponible à ce jour.
     *
     * @return Collection<int, Reservation>
     */
    public function sejours(string $clientId): Collection
    {
        return Reservation::query()
            ->with('unite')
            ->where('client_id', $clientId)
            ->orderByDesc('date_arrivee')
            ->get();
    }

    /**
     * Compteurs de synthèse — calculés, jamais stockés sur la fiche client.
     *
     * @return array{nb_sejours: int, nb_sejours_annules: int, nb_nuitees_totales: int}
     */
    public function statistiques(string $clientId): array
    {
        $sejours = $this->sejours($clientId);
        $actifs = $sejours->filter(fn (Reservation $r): bool => $r->estActive());

        return [
            'nb_sejours' => $actifs->count(),
            'nb_sejours_annules' => $sejours->count() - $actifs->count(),
            'nb_nuitees_totales' => (int) $actifs->sum(fn (Reservation $r): int => $r->nombreNuitees()),
        ];
    }

    /**
     * @return array<string, array{libelle: string, module: string, statut: string}>
     */
    public function etatDesSources(): array
    {
        $etat = [];

        foreach (self::SOURCES as $cle => $source) {
            $etat[$cle] = [
                'libelle' => $source['libelle'],
                'module' => $source['module'],
                'statut' => $source['disponible'] ? 'disponible' : 'en_attente_de_module',
            ];
        }

        return $etat;
    }

    public function toutesSourcesDisponibles(): bool
    {
        foreach (self::SOURCES as $source) {
            if (! $source['disponible']) {
                return false;
            }
        }

        return true;
    }
}
