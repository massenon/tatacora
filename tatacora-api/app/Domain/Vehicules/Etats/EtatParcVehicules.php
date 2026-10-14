<?php

declare(strict_types=1);

namespace App\Domain\Vehicules\Etats;

use App\Domain\Vehicules\Models\Vehicule;
use App\Shared\ReportEngine\Contracts\EtatInterface;
use App\Shared\ReportEngine\Data\EtatResultat;

/**
 * État du parc de véhicules — EF-M14-02 appliqué à M8.
 *
 * Passe par le moteur partagé (RG-19) : l'en-tête lui est imposée, il n'y a
 * pas accès.
 *
 * @see EF-M8-01
 * @see EF-M14-02
 */
class EtatParcVehicules implements EtatInterface
{
    private const PRECISION = 2;

    public function module(): string
    {
        return 'M8';
    }

    /**
     * @param  array<string, string>  $filtres
     */
    public function libelle(array $filtres): string
    {
        return __('vehicules.etat.libelle');
    }

    /**
     * Un parc est une photographie, pas un intervalle : afficher une plage
     * laisserait croire à un cumul de période.
     *
     * @param  array<string, string>  $filtres
     */
    public function periode(array $filtres): string
    {
        return __('vehicules.etat.arrete_au', ['date' => now()->format('d/m/Y à H:i')]);
    }

    /**
     * @param  array<string, string>  $filtres  `categorie`, `statut`
     */
    public function calculer(array $filtres): EtatResultat
    {
        $categorie = $filtres['categorie'] ?? null;
        $statut = $filtres['statut'] ?? null;

        $vehicules = Vehicule::query()
            ->when(filled($categorie), fn ($q) => $q->where('categorie', $categorie))
            ->when(filled($statut), fn ($q) => $q->where('statut', $statut))
            ->orderBy('categorie')
            ->orderBy('immatriculation')
            ->get();

        $lignes = [];
        $tarifCumule = '0.00';
        $louables = 0;

        foreach ($vehicules as $vehicule) {
            if ($vehicule->estLouable()) {
                $louables++;
                // Seuls les véhicules louables entrent dans le potentiel
                // journalier : compter un véhicule hors service gonflerait un
                // chiffre d'affaires théorique inatteignable.
                $tarifCumule = bcadd($tarifCumule, (string) $vehicule->tarif_jour, self::PRECISION);
            }

            $lignes[] = [
                (string) $vehicule->immatriculation,
                (string) $vehicule->categorie,
                (string) $vehicule->annee,
                (string) $vehicule->capacite,
                (string) $vehicule->tarif_jour,
                (string) $vehicule->statut,
                $vehicule->exigePermis()
                    ? __('vehicules.etat.permis_oui')
                    : __('vehicules.etat.permis_non'),
            ];
        }

        return new EtatResultat(
            kpis: [
                __('vehicules.etat.kpi_vehicules') => (string) $vehicules->count(),
                __('vehicules.etat.kpi_louables') => (string) $louables,
                __('vehicules.etat.kpi_immobilises') => (string) ($vehicules->count() - $louables),
                __('vehicules.etat.kpi_valeur_jour') => $tarifCumule,
            ],
            entetes: [
                __('vehicules.etat.col_immatriculation'),
                __('vehicules.etat.col_categorie'),
                __('vehicules.etat.col_annee'),
                __('vehicules.etat.col_capacite'),
                __('vehicules.etat.col_tarif'),
                __('vehicules.etat.col_statut'),
                __('vehicules.etat.col_permis'),
            ],
            lignes: $lignes,
            filtresAppliques: array_filter([
                'categorie' => $categorie,
                'statut' => $statut,
            ]),
        );
    }
}
