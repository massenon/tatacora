<?php

declare(strict_types=1);

namespace App\Domain\Vehicules\Policies;

use App\Shared\Rbac\Policies\BasePolicy;

/**
 * 2ᵉ niveau RBAC sur les contrats de location — RG-16.
 *
 * Nom de classe aligné sur le modèle (`ContratLocation` →
 * `ContratLocationPolicy`) : la découverte automatique de Laravel repose sur
 * cette convention, et un écart la rend silencieusement inopérante — incident
 * déjà rencontré sur `CarteBoisson`, où un contrôle d'accès absent se
 * manifestait par un 403 remplacé par un 422.
 *
 * `delete()` n'est pas redéfinie : `BasePolicy` renvoie déjà `false` pour tout
 * le monde, aucune suppression physique n'étant autorisée sur une table
 * transactionnelle (`03_DATABASE_ENGINEERING.md` §15). Voir aussi PA-50 —
 * l'absence de colonne `statut` prive ce module de toute annulation propre.
 */
final class ContratLocationPolicy extends BasePolicy
{
    protected string $module = 'M8';
}
