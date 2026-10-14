<?php

declare(strict_types=1);

namespace App\Shared\Rbac\Policies;

use App\Models\User;

/**
 * Policy de base réutilisable par tous les domaines — 2ᵉ niveau RBAC,
 * appliqué au niveau de l'entité là où le Middleware l'applique à la route.
 *
 * Chaque domaine en hérite et déclare son module :
 *
 *     final class ReservationPolicy extends BasePolicy
 *     {
 *         protected string $module = 'M1';
 *     }
 *
 * Les tables sensibles (factures, écritures, stock, paie) redéfinissent
 * `delete()` pour retourner systématiquement false — aucune suppression
 * physique de donnée transactionnelle (03_DATABASE_ENGINEERING.md §15).
 *
 * @see RG-16
 */
abstract class BasePolicy
{
    /** Code module de la matrice RBAC ('M1' à 'M14', 'ROLES', 'PARAM'). */
    protected string $module = '';

    public function viewAny(User $user): bool
    {
        return $this->auMoinsLecture($user);
    }

    public function view(User $user): bool
    {
        return $this->auMoinsLecture($user);
    }

    public function create(User $user): bool
    {
        return $this->accesComplet($user);
    }

    public function update(User $user): bool
    {
        return $this->accesComplet($user);
    }

    /**
     * Par défaut aucune suppression n'est autorisée : sur ce projet, la
     * suppression physique est l'exception, pas la règle. Un domaine qui en a
     * réellement besoin doit la rouvrir explicitement — jamais l'inverse.
     */
    public function delete(User $user): bool
    {
        return false;
    }

    protected function auMoinsLecture(User $user): bool
    {
        return $user->estActif()
            && in_array($user->niveauSurModule($this->module), ['C', 'L'], true);
    }

    protected function accesComplet(User $user): bool
    {
        return $user->estActif() && $user->niveauSurModule($this->module) === 'C';
    }
}
