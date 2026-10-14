<?php

declare(strict_types=1);

namespace App\Domain\Achats\Policies;

use App\Shared\Rbac\Policies\BasePolicy;

/**
 * RBAC des commandes d'achat et de leurs réceptions (M7) — 2e niveau.
 *
 * `delete()` reste à `false` (hérité de `BasePolicy`) et aucune route de
 * suppression n'existe : `commandes_achat`, `lignes_commande_achat` et
 * `bons_reception` sont des tables transactionnelles. Un bon de réception
 * supprimé laisserait derrière lui l'entrée de stock qu'il a générée, sans
 * plus rien pour l'expliquer — le stock resterait juste et le justificatif
 * aurait disparu.
 */
final class CommandeAchatPolicy extends BasePolicy
{
    protected string $module = 'M7';
}
