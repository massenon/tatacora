<?php

declare(strict_types=1);

namespace App\Pwa\Support;

use App\Domain\Facturation\Models\Facture;
use App\Domain\Ventes\Models\Vente;

/**
 * Les colonnes « Origine » et « Mode de paiement » du registre des factures (10/11/2026, constat du PO :
 * le web affichait « — » là où le poste dit « POS au comptant » et « mobile_money »).
 *
 * L'ORIGINE est une colonne de `factures` depuis la numérotation du 17/10/2026 (le poste l'envoie, le
 * serveur la range) ; elle n'était simplement plus lue. Le MODE de paiement n'est écrit nulle part sur la
 * facture : on le LIT là où il vit — le paiement actif de la facture, ou, pour un ticket du comptoir, la
 * vente qui l'a produit (encaissée à la vente, sans paiement au serveur). Aucune valeur inventée : sans
 * source, « — » (Article 7).
 */
final class OrigineEtModeFacture
{
    /** @var array<string, string> */
    private const MODES = [
        'especes' => 'Espèces',
        'mobile_money' => 'Mobile Money',
        'virement' => 'Virement',
        'credit' => 'Crédit',
        'note_chambre' => 'Note de chambre',
        'cheque' => 'Chèque',
        'carte' => 'Carte bancaire',
    ];

    public static function origine(Facture $facture): string
    {
        $origine = (string) ($facture->origine ?? '');

        if ($origine === '') {
            return MontantFcfa::TIRET;
        }

        $cle = 'facturation_pwa.origine.'.$origine;
        $libelle = (string) __($cle);

        // Une origine inconnue du registre est dite en clair, jamais « facturation_pwa.origine.x ».
        return $libelle === $cle ? $origine : $libelle;
    }

    public static function mode(Facture $facture): string
    {
        $codes = $facture->relationLoaded('paiements')
            ? $facture->paiements->where('statut', 'actif')->pluck('mode_paiement')->unique()->values()->all()
            : $facture->paiements()->where('statut', 'actif')->pluck('mode_paiement')->unique()->values()->all();

        if ($codes === [] && (string) $facture->origine === 'pos_comptant') {
            $ventes = $facture->lignes->whereIn('source_module', ['M4', 'M5'])->pluck('source_id')->unique()->values()->all();
            $codes = $ventes === [] ? [] : Vente::query()->whereIn('id', $ventes)->pluck('mode_paiement')->unique()->values()->all();
        }

        if ($codes === []) {
            return MontantFcfa::TIRET;
        }

        return implode(', ', array_map(static fn (string $c): string => self::MODES[$c] ?? $c, $codes));
    }
}
