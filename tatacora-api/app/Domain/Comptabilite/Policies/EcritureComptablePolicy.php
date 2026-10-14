<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Policies;

use App\Models\User;
use App\Shared\Rbac\Policies\BasePolicy;

/**
 * RBAC des ecritures comptables (M10) — 2e niveau.
 *
 * @see RG-11 Immutabilite et contre-passation
 * @see RG-16 RBAC de 2e niveau
 *
 * ## `delete()` et `update()` sont REDEFINIS, alors que la base suffirait
 *
 * `BasePolicy::delete()` rend deja `false`. La redefinition est explicite ici
 * parce que M10 est le cas le plus strict du depot : une ecriture ne se
 * supprime JAMAIS, meme en brouillon — un trou dans la sequence est ce qu'un
 * controle fiscal recherche. Ecrit noir sur blanc, le refus se relit ; herite,
 * il se perdrait le jour ou quelqu'un rouvrirait la base.
 *
 * `update()` refuse de meme : la seule correction admise est la
 * contre-passation, qui est une CREATION d'ecriture inverse, pas une
 * modification.
 *
 * ⚠ **Ce n'est pas la garde qui protege reellement.** RG-11 vit dans
 * `EcritureComptableObserver`, seul chemin qui couvre la synchronisation
 * differee, les jobs et les commandes artisan — une Policy ne protege que les
 * appelants qui pensent a l'interroger. C'est la lecon de PA-100 : ne pas
 * confondre la garde du service avec la protection. Ces deux refus sont
 * delibérément redondants ; le verrou est ailleurs.
 */
final class EcritureComptablePolicy extends BasePolicy
{
    protected string $module = 'M10';

    /**
     * Aucune modification directe — RG-11. La correction est une
     * contre-passation, donc une creation.
     */
    public function update(User $user): bool
    {
        return false;
    }

    /**
     * Aucune suppression, meme en brouillon —
     * `03_DATABASE_ENGINEERING.md` §15.
     */
    public function delete(User $user): bool
    {
        return false;
    }
}
