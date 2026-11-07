<?php

declare(strict_types=1);

namespace App\Pwa\Support;

use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Services\ModeFacturation;
use App\Domain\Facturation\Services\StatutNormalisation;
use App\Pwa\Livewire\Facturation\Facturation;

/**
 * L'ÉTIQUETTE d'une facture à l'écran, selon le MODE (décision du PO du 07/11/2026) :
 *  - désactivé = facturation SIMPLE : « émise », jamais « certifiée », aucune mention ;
 *  - e-MECeF / boîtier : « normalisée » seulement si le numéro réel ET le QR sont là ;
 *    sinon l'état de la normalisation (en attente, refusée, à vérifier) — une facture
 *    émise sans normalisation dit « en attente de normalisation ».
 *
 * Hors du composant Livewire : une méthode publique d'un composant est une ACTION.
 */
final class EtiquetteFacture
{
    /** @return array{libelle: string, fond: string, texte: string} */
    public static function pour(Facture $facture, ModeFacturation $mode): array
    {
        $emise = ['libelle' => 'émise', 'fond' => '#E8F5E9', 'texte' => '#2E7D32'];

        if ($facture->estNormalisee()) {
            return ['libelle' => 'normalisée', 'fond' => '#E8F5E9', 'texte' => '#2E7D32'];
        }

        if ($mode === ModeFacturation::Desactive) {
            return $facture->statut === 'echec_certification' || $facture->statut === 'brouillon'
                ? (Facturation::STATUTS[$facture->statut] ?? $emise)
                : $emise;
        }

        return match (StatutNormalisation::depuis($facture->normalisation_statut)) {
            StatutNormalisation::Refusee => ['libelle' => 'normalisation refusée', 'fond' => '#FDECEC', 'texte' => '#C62828'],
            StatutNormalisation::AVerifier => ['libelle' => 'normalisation à vérifier', 'fond' => '#FDF3E0', 'texte' => '#B8891E'],
            default => ['libelle' => 'en attente de normalisation', 'fond' => '#FDF3E0', 'texte' => '#B8891E'],
        };
    }
}
