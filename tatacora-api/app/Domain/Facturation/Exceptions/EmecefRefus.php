<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Exceptions;

use App\Domain\Facturation\Services\StatutNormalisation;

/** La DGI a explicitement refusé la facture (`errorCode`/`errorDesc`, 400/422) : « refusée ». */
final class EmecefRefus extends EmecefErreur
{
    public static function depuis(string $description): self
    {
        $net = trim(preg_replace('/\s+/', ' ', $description) ?? '');

        return new self(__('facturation.emecef.refus', ['detail' => $net === '' ? __('facturation.emecef.refus_sans_detail') : mb_substr($net, 0, 240)]));
    }

    public function statut(): StatutNormalisation
    {
        return StatutNormalisation::Refusee;
    }
}
