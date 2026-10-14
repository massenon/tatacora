<?php

declare(strict_types=1);

namespace App\Pwa\Support;

use Illuminate\Support\Facades\Auth;

/**
 * Trait universel de déconnexion d'un utilisateur depuis la coquille Livewire.
 */
trait FermeSession
{
    public function seDeconnecter(): mixed
    {
        Auth::logout();
        session()->invalidate();
        session()->regenerateToken();

        return $this->redirectRoute('pwa.connexion', navigate: true);
    }
}
