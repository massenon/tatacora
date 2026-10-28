<?php

declare(strict_types=1);

namespace App\Domain\Vehicules\Etats;

use App\Domain\Vehicules\Models\ContratLocation;
use App\Shared\ReportEngine\Contracts\EtatInterface;
use App\Shared\ReportEngine\Data\EtatResultat;

/**
 * État des locations de véhicules — EF-M14-02 appliqué à M8.
 *
 * `montant()` est CALCULÉ (`tarif_jour × nombreJours()`, `ContratLocation`) —
 * jamais une seconde formule.
 *
 * ## Les contrats ANNULÉS (`statut = annule`, `ContratLocationService::annuler`)
 *
 * Par DÉFAUT ils sont exclus des lignes, du nombre et du montant : ils ne sont
 * pas du chiffre d'affaires. Le filtre `inclure_annules` (case « Inclure les
 * contrats annulés », décochée par défaut — PRD corrections Locations, R4) les
 * ajoute à l'état sous deux garanties, décidées par le PO (28/10/2026) :
 *
 *  - un contrat annulé n'est JAMAIS compté : ni dans « Contrats », ni dans
 *    « Montant total ». Il est listé À PART — après tous les contrats actifs —
 *    avec le statut « Annulé » (colonne « Statut », ajoutée seulement quand la
 *    case est cochée) et une cellule « Montant » VIDE : afficher son montant
 *    théorique dans la colonne qu'on additionne ferait lire un total faux ;
 *  - la période de l'état DIT si les annulés sont exclus ou inclus (et, inclus,
 *    qu'ils ne sont pas comptés), pour qu'un document imprimé ne se lise pas
 *    sans cette précision.
 *
 * Ce document ne prétend à aucun « reste dû » (pas de suivi de règlement ici),
 * à la différence de M7 où `montant_regle` existe réellement.
 *
 * @see EF-M14-02 Bibliothèque d'états standards par module
 * @see PA-50 historique : le statut n'existait pas encore
 */
class EtatLocations implements EtatInterface
{
    public function module(): string
    {
        return 'M8';
    }

    /**
     * @param  array<string, string>  $filtres
     */
    public function libelle(array $filtres): string
    {
        return __('etats_m14.locations.libelle');
    }

    /**
     * @param  array<string, string>  $filtres
     */
    public function periode(array $filtres): string
    {
        $debut = $filtres['date_debut'] ?? null;
        $fin = $filtres['date_fin'] ?? null;

        $annules = self::inclureAnnules($filtres)
            ? __('etats_m14.locations.annules_inclus')
            : __('etats_m14.locations.annules_exclus');

        // ⚠ La DERNIÈRE clé de ce corps doit rester celle de « sans filtre »
        // (`periode_toutes`) : `tool/etats/exporter_registre.php` la lit ainsi.
        if (filled($debut) && filled($fin)) {
            return __('etats_m14.periode_du_au', ['debut' => $debut, 'fin' => $fin]) . ' · ' . $annules;
        }

        return __('etats_m14.locations.periode_toutes') . ' · ' . $annules;
    }

    /**
     * La case « Inclure les contrats annulés » : décochée (absente) = exclus.
     *
     * @param  array<string, string>  $filtres
     */
    public static function inclureAnnules(array $filtres): bool
    {
        return in_array(strtolower(trim((string) ($filtres['inclure_annules'] ?? ''))), ['1', 'true', 'on', 'oui'], true);
    }

    /**
     * @param  array<string, string>  $filtres  `date_debut`, `date_fin`
     */
    public function calculer(array $filtres): EtatResultat
    {
        $debut = $filtres['date_debut'] ?? null;
        $fin = $filtres['date_fin'] ?? null;

        $inclureAnnules = self::inclureAnnules($filtres);

        $requete = ContratLocation::query()->with(['client', 'vehicule'])
            ->orderByDesc('date_debut');

        if (! $inclureAnnules) {
            $requete->where('statut', '!=', 'annule');
        }

        if (filled($debut)) {
            $requete->whereDate('date_debut', '>=', $debut);
        }
        if (filled($fin)) {
            $requete->whereDate('date_debut', '<=', $fin);
        }

        $lignes = [];
        $lignesAnnulees = [];
        $montantCumule = '0.00';

        foreach ($requete->get() as $contrat) {
            $annule = $contrat->statut === 'annule';
            $montant = $contrat->montant();

            $ligne = [
                (string) $contrat->client?->nomComplet(),
                $contrat->vehicule->categorie . ' — ' . $contrat->vehicule->immatriculation,
                $contrat->date_debut->format('d/m/Y'),
                $contrat->date_fin->format('d/m/Y'),
                (string) $contrat->nombreJours(),
                // Un annulé n'a pas de montant dans l'état : cellule vide.
                $annule ? '' : $montant,
            ];

            if ($inclureAnnules) {
                $ligne[] = $annule
                    ? __('vehicules.pwa.contrat_annule')
                    : __('vehicules.pwa.contrat_actif');
            }

            if ($annule) {
                $lignesAnnulees[] = $ligne;

                continue;
            }

            $montantCumule = bcadd($montantCumule, $montant, 2);
            $lignes[] = $ligne;
        }

        // Le nombre est celui des contrats COMPTÉS, avant l'ajout des annulés.
        $nombre = count($lignes);
        $lignes = [...$lignes, ...$lignesAnnulees];

        $entetes = [
            __('etats_m14.locations.col_client'),
            __('etats_m14.locations.col_vehicule'),
            __('etats_m14.locations.col_debut'),
            __('etats_m14.locations.col_fin'),
            __('etats_m14.locations.col_jours'),
            __('etats_m14.locations.col_montant'),
        ];
        if ($inclureAnnules) {
            $entetes[] = __('etats_m14.locations.col_statut');
        }

        return new EtatResultat(
            kpis: [
                __('etats_m14.locations.kpi_nombre') => (string) $nombre,
                __('etats_m14.locations.kpi_montant') => $montantCumule,
            ],
            entetes: $entetes,
            lignes: $lignes,
            filtresAppliques: array_filter([
                'date_debut' => $debut,
                'date_fin' => $fin,
                'inclure_annules' => $inclureAnnules ? '1' : null,
            ]),
        );
    }
}
