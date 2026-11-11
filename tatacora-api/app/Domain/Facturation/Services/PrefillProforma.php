<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Services;

use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Tourisme\Models\ReservationTour;
use App\Domain\Vehicules\Models\ContratLocation;

/**
 * Le PRÉREMPLISSAGE d'une proforma depuis un module (PO, 07/11/2026, point 4) : client (nom, téléphone, IFU
 * si connu), objet et lignes, à partir de ce qui existe RÉELLEMENT.
 *
 *  - location  : le contrat (véhicule x jours au tarif journalier) ;
 *  - tourisme  : la réservation de circuit (circuit x participants) ;
 *  - hebergement : la réservation (nuitées au tarif figé + lignes de services) ;
 *  - evenement : AUCUN module « événement » n'existe (ni atelier, ni réception, ni devis) : proforma vide.
 *
 * Les lignes restent modifiables. Ce qui n'est pas connu n'est pas inventé : une réservation sans tarif figé
 * donne une ligne d'hébergement à 0 FCFA, que l'utilisateur complète. Les remises de réservation ne sont pas reprises.
 */
class PrefillProforma
{
    /**
     * @return array{client_id: ?string, client_nom: string, client_telephone: string, client_ifu: string, objet: string, source_module: string, source_id: ?string, lignes: list<array{designation: string, quantite: int, prix_unitaire: int}>}|null
     */
    public function depuis(string $flux, ?string $source): ?array
    {
        return match ($flux) {
            'location' => $this->location($source),
            'tourisme' => $this->tourisme($source),
            'hebergement' => $this->hebergement($source),
            'evenement' => $this->base('evenement', null, null),
            default => null,
        };
    }

    private function location(?string $id): ?array
    {
        $contrat = $id === null ? null : ContratLocation::query()->with(['vehicule', 'client'])->find($id);

        if ($contrat === null) {
            return null;
        }

        $v = $contrat->vehicule;
        $jours = max(1, $contrat->nombreJours());
        $designation = sprintf('Location %s %s du %s au %s', $v->categorie, $v->immatriculation, $contrat->date_debut->format('d/m/Y'), $contrat->date_fin->format('d/m/Y'));

        return [...$this->base('location', $contrat->client, $contrat->id), 'objet' => sprintf('Location de véhicule — %s %s', $v->categorie, $v->immatriculation),
            'lignes' => [['designation' => $designation, 'quantite' => $jours, 'prix_unitaire' => $this->francs((string) $v->tarif_jour)]]];
    }

    private function tourisme(?string $id): ?array
    {
        $r = $id === null ? null : ReservationTour::query()->with(['circuit', 'client'])->find($id);

        if ($r === null) {
            return null;
        }

        return [...$this->base('tourisme', $r->client, $r->id), 'objet' => sprintf('Circuit touristique — %s', $r->circuit->nom),
            'lignes' => [['designation' => sprintf('Circuit %s du %s (par participant)', $r->circuit->nom, $r->date_circuit->format('d/m/Y')),
                'quantite' => max(1, (int) $r->nb_participants), 'prix_unitaire' => $this->francs((string) $r->circuit->prix)]]];
    }

    private function hebergement(?string $id): ?array
    {
        $r = $id === null ? null : Reservation::query()->with(['client', 'unite', 'lignes'])->find($id);

        if ($r === null) {
            return null;
        }

        $lignes = [['designation' => sprintf('Hébergement — unité %s, du %s au %s', $r->unite->numero, $r->date_arrivee->format('d/m/Y'), $r->date_depart->format('d/m/Y')),
            'quantite' => max(1, $r->nombreNuitees()), 'prix_unitaire' => $r->tarif_nuit === null ? 0 : $this->francs((string) $r->tarif_nuit)]];

        foreach ($r->lignes as $ligne) {
            $lignes[] = ['designation' => (string) $ligne->libelle, 'quantite' => max(1, (int) $ligne->quantite), 'prix_unitaire' => $this->francs((string) $ligne->prix_unitaire)];
        }

        return [...$this->base('hebergement', $r->client, $r->id), 'objet' => sprintf('Séjour du %s au %s', $r->date_arrivee->format('d/m/Y'), $r->date_depart->format('d/m/Y')), 'lignes' => $lignes];
    }

    /** @return array{client_id: ?string, client_nom: string, client_telephone: string, client_ifu: string, objet: string, source_module: string, source_id: ?string, lignes: list<array{designation: string, quantite: int, prix_unitaire: int}>} */
    private function base(string $flux, ?object $client, ?string $source): array
    {
        return [
            'client_id' => $client?->id,
            'client_nom' => $client === null ? '' : trim(($client->prenom ?? '').' '.($client->nom ?? '')),
            'client_telephone' => (string) ($client->telephone ?? ''),
            'client_ifu' => (string) ($client->ifu ?? ''),
            'objet' => '',
            'source_module' => $flux,
            'source_id' => $source,
            'lignes' => [],
        ];
    }

    private function francs(string $decimal): int
    {
        return (int) round((float) $decimal);
    }
}
