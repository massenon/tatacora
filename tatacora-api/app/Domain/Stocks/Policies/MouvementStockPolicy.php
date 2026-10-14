<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Policies;

use App\Models\User;
use App\Shared\Rbac\Policies\BasePolicy;

/**
 * RBAC de `mouvements_stock` (M6) — 2ᵉ niveau, au niveau de l'entité.
 *
 * ## Un mouvement ne se modifie ni ne se supprime — JAMAIS
 *
 * La table est en ajout seul par conception : un mouvement erroné se corrige
 * par un mouvement inverse, qui laisse les deux lignes visibles. C'est ce qui
 * rend l'historique de stock opposable lors d'un inventaire — un historique
 * réécrit ne prouve plus rien.
 *
 * `delete()` est déjà `false` chez `BasePolicy` ; il est redéclaré ici pour que
 * la décision soit lisible sur la table concernée, et pour qu'une réouverture
 * du défaut chez le parent ne la rouvre pas ici par effet de bord.
 *
 * `update()` est refusé pour la même raison. `ArticlePolicy`, elle, l'autorise :
 * un article est un référentiel, un mouvement est une transaction.
 *
 * @see RG-15 Traçabilité intégrale
 * @see 03_DATABASE_ENGINEERING.md §15 — aucune suppression physique
 */
final class MouvementStockPolicy extends BasePolicy
{
    protected string $module = 'M6';

    public function update(User $user): bool
    {
        return false;
    }

    public function delete(User $user): bool
    {
        return false;
    }
}
