<?php

declare(strict_types=1);

namespace App\Domain\Achats\Etats;

use App\Domain\Achats\Models\CommandeAchat;
use App\Shared\ReportEngine\Contracts\EtatInterface;
use App\Shared\ReportEngine\Data\EtatResultat;

/**
 * État des achats et dettes fournisseurs — EF-M14-02 appliqué à M7.
 *
 * Le « reste dû » est `CommandeAchat::montantTotal() - montant_regle` :
 * `montant_regle` est écrit par `ReglementFournisseurService`, RECALCULÉ
 * depuis les règlements (PA-165), jamais saisi — ce document ne reconstruit
 * donc aucune seconde somme, il lit la même colonne que l'écran Achats.
 *
 * @see EF-M14-02 Bibliothèque d'états standards par module
 */
class EtatAchatsFournisseurs implements EtatInterface
{
    public function module(): string
    {
        return 'M7';
    }

    /**
     * @param  array<string, string>  $filtres
     */
    public function libelle(array $filtres): string
    {
        return __('etats_m14.achats.libelle');
    }

    /**
     * @param  array<string, string>  $filtres
     */
    public function periode(array $filtres): string
    {
        $debut = $filtres['date_debut'] ?? null;
        $fin = $filtres['date_fin'] ?? null;

        if (filled($debut) && filled($fin)) {
            return __('etats_m14.periode_du_au', ['debut' => $debut, 'fin' => $fin]);
        }

        return __('etats_m14.achats.periode_toutes');
    }

    /**
     * @param  array<string, string>  $filtres  `date_debut`, `date_fin`, `dues_seulement`
     */
    public function calculer(array $filtres): EtatResultat
    {
        $duesSeulement = filter_var($filtres['dues_seulement'] ?? false, FILTER_VALIDATE_BOOLEAN);
        $debut = $filtres['date_debut'] ?? null;
        $fin = $filtres['date_fin'] ?? null;

        $requete = CommandeAchat::query()->with(['fournisseur', 'lignes'])->orderByDesc('date_commande');

        if (filled($debut)) {
            $requete->whereDate('date_commande', '>=', $debut);
        }
        if (filled($fin)) {
            $requete->whereDate('date_commande', '<=', $fin);
        }

        $lignes = [];
        $montantCumule = '0.00';
        $resteCumule = '0.00';

        foreach ($requete->get() as $commande) {
            $montant = $commande->montantTotal();
            $reste = bcsub($montant, (string) $commande->montant_regle, 2);

            if ($duesSeulement && bccomp($reste, '0.00', 2) <= 0) {
                continue;
            }

            $montantCumule = bcadd($montantCumule, $montant, 2);
            $resteCumule = bcadd($resteCumule, $reste, 2);

            $lignes[] = [
                (string) $commande->fournisseur?->raison_sociale,
                $commande->date_commande->format('d/m/Y'),
                $commande->statut,
                $montant,
                (string) $commande->montant_regle,
                $reste,
            ];
        }

        return new EtatResultat(
            kpis: [
                __('etats_m14.achats.kpi_nombre') => (string) count($lignes),
                __('etats_m14.achats.kpi_montant') => $montantCumule,
                __('etats_m14.achats.kpi_reste_du') => $resteCumule,
            ],
            entetes: [
                __('etats_m14.achats.col_fournisseur'),
                __('etats_m14.achats.col_date'),
                __('etats_m14.achats.col_statut'),
                __('etats_m14.achats.col_montant'),
                __('etats_m14.achats.col_regle'),
                __('etats_m14.achats.col_reste_du'),
            ],
            lignes: $lignes,
            filtresAppliques: array_filter([
                'date_debut' => $debut,
                'date_fin' => $fin,
                'dues_seulement' => $duesSeulement ? 'oui' : null,
            ]),
        );
    }
}
