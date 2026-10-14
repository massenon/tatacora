<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Requests;

/**
 * Un exercice et un statut, rien de plus.
 *
 * Sert la Balance Generale (`m10-balance.html`, qui n'a AUCUN controle de
 * filtre) et le selecteur de comptes mouvementes du Grand Livre.
 */
final class ConsulterEtatComptableRequest extends RequeteExerciceRequest
{
}
