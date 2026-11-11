<?php

declare(strict_types=1);

namespace App\Pwa\Support;

use App\Domain\Facturation\Models\Avoir;
use App\Domain\Facturation\Models\Facture;

/**
 * Le numéro que la colonne « N° » du registre des factures affiche (PO, 09/11/2026).
 *
 *  - le numéro FISCAL (NIM / numéro MECeF) quand la pièce porte une certification RÉELLE ;
 *  - SINON le numéro INTERNE de la séquence du dépôt (`F-AAAA-NNNNN`, `AV-…` pour un avoir) :
 *    jamais « — » pour une pièce qui a un numéro interne.
 *
 * Un numéro de démonstration (`MECEF-DEMO-…`) n'est pas fiscal : il ne passe pas devant le numéro interne.
 * Une facture SIMPLE (mode désactivé) affiche son numéro interne SANS aucune mention de normalisation
 * (décision du PO) ; la légende « n° interne » ne parle que de la nature du numéro. Une seule règle, lue par
 * l'écran, l'impression du registre, le PDF et le tableur : les quatre portent la même valeur. Le poste
 * (`PieceFacturation.numeroRegistre`) applique la même règle, relue par un test contre ce code.
 */
final class NumeroRegistre
{
    /**
     * @return array{valeur: string, interne: bool} `interne` : la valeur est le numéro du dépôt, pas le numéro fiscal
     */
    public static function pour(Facture|Avoir $piece): array
    {
        $fiscal = (string) $piece->numero_mecef;

        if ($fiscal !== '' && ! str_starts_with($fiscal, 'MECEF-DEMO-')) {
            return ['valeur' => $fiscal, 'interne' => false];
        }

        $interne = (string) $piece->numero;

        return $interne !== ''
            ? ['valeur' => $interne, 'interne' => true]
            : ['valeur' => MontantFcfa::TIRET, 'interne' => false];
    }

    /** La valeur seule — export, PDF. */
    public static function valeur(Facture|Avoir $piece): string
    {
        return self::pour($piece)['valeur'];
    }
}
