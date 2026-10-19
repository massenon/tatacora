<?php

declare(strict_types=1);

namespace App\Shared\Rbac\Services;

use App\Models\User;
use App\Shared\Parametres\Services\OptionsSystemeService;

/**
 * QUI PEUT ARCHIVER un élément de référentiel — la règle, écrite UNE fois.
 *
 * Directive du Product Owner du 03/09/2026 : `administrateur` et `super_admin`
 * archivent sans condition ; tout autre rôle en `C` sur le module seulement
 * quand la bascule `activation_suppression` est ouverte en Paramètres ; un
 * rôle en `L` ou sans accès, jamais. Le détail du raisonnement vit sur
 * `App\Pwa\Support\AutoriseArchivage`.
 *
 * ## Pourquoi la règle a quitté le trait PWA (15/10/2026)
 *
 * Elle était `protected` dans `AutoriseArchivage`, lisible par les seuls
 * composants Livewire. La synchronisation hors connexion porte désormais
 * l'archivage d'un fournisseur (`actif` dans le payload, décision PO du
 * 15/10/2026) : la recopier dans le gestionnaire en aurait fait deux auteurs,
 * et deux auteurs divergent au premier changement de la directive. Le trait
 * DÉLÈGUE ici, le gestionnaire aussi.
 */
class DroitArchivageService
{
    public function __construct(
        private readonly OptionsSystemeService $options,
    ) {
    }

    public function peutArchiver(?User $utilisateur, string $module): bool
    {
        if (! $utilisateur instanceof User || ! $utilisateur->estActif()) {
            return false;
        }

        if ($utilisateur->niveauSurModule($module) !== 'C') {
            return false;
        }

        if (in_array((string) $utilisateur->role?->libelle, User::ROLES_ADMINISTRATION, true)) {
            return true;
        }

        return $this->options->suppressionActive();
    }
}
