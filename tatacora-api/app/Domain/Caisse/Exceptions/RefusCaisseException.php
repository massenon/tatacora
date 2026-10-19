<?php

declare(strict_types=1);

namespace App\Domain\Caisse\Exceptions;

use RuntimeException;

/**
 * Refus MÉTIER d'une ouverture ou d'une clôture de caisse (point inconnu,
 * caisse déjà ouverte, déjà clôturée, clôture antérieure à l'ouverture,
 * montant invalide).
 *
 * Classe à part, et non une RuntimeException nue (15/10/2026) : l'écran
 * PosComptant n'attrape QUE ces refus. Une erreur SQL (QueryException, qui
 * est aussi une RuntimeException) continue d'y remonter en erreur, comme
 * avant l'extraction de SessionCaisseService — le poste réplique ce
 * comportement (caisse_contre_serveur_test).
 */
final class RefusCaisseException extends RuntimeException
{
}
