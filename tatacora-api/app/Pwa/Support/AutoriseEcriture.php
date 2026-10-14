<?php

declare(strict_types=1);

namespace App\Pwa\Support;

use App\Models\User;
use App\Shared\Rbac\Models\JournalSecurite;

/**
 * Trait de contrôle des autorisations d'écriture (CRUD) selon le RBAC de l'utilisateur.
 */
trait AutoriseEcriture
{
    /**
     * Exige le niveau de création/modification ('C') sur le module ou refuse l'action.
     *
     * @param string $module Code du module (ex: 'M1', 'M6', 'PARAM')
     * @return User
     */
    protected function exigerEcriture(string $module): User
    {
        /** @var User|null $utilisateur */
        $utilisateur = auth()->user();

        if ($utilisateur === null || ! $utilisateur->estActif()) {
            $this->tracerRefusEcriture(null, $module);
            abort(401, __('auth.requise'));
        }

        if ($utilisateur->niveauSurModule($module) !== 'C') {
            $this->tracerRefusEcriture($utilisateur->id, $module);
            abort(403, __('auth.module_refuse'));
        }

        return $utilisateur;
    }

    private function tracerRefusEcriture(?string $utilisateurId, string $module): void
    {
        JournalSecurite::create([
            'type_evenement' => 'acces_refuse_rbac',
            'utilisateur_id' => $utilisateurId,
            'adresse_ip' => request()->ip(),
            'module_concerne' => $module,
        ]);
    }
}
