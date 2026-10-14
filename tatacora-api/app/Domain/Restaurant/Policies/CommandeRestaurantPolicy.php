<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Policies;

use App\Shared\Rbac\Policies\BasePolicy;

/**
 * RBAC du domaine Restaurant (M4) — 2e niveau.
 *
 * Table transactionnelle : une commande s'annule (`statut = 'annulee'`), elle
 * ne se supprime pas. Apres transmission en cuisine, meme l'annulation est
 * refusee — les denrees sont engagees, la correction passe par une perte de
 * stock explicite.
 *
 * @see RG-16
 */
final class CommandeRestaurantPolicy extends BasePolicy
{
    protected string $module = 'M4';
}
