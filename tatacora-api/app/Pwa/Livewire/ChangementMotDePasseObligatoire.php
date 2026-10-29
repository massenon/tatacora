<?php

declare(strict_types=1);

namespace App\Pwa\Livewire;

use App\Models\User;
use App\Shared\Auth\Services\MotDePassePerduService;
use Illuminate\Support\Facades\Auth;
use Illuminate\View\View;
use Livewire\Component;
use RuntimeException;

/**
 * « Définissez votre nouveau mot de passe » — la SEULE page qu'atteint un compte
 * dont le mot de passe a été réinitialisé par un administrateur (décision du PO
 * du 29/10/2026). `ExigerChangementMotDePasse` ferme toutes les autres.
 *
 * Règles : celles de « Mon profil » (8 caractères au moins, confirmation à
 * l'identique), PLUS : différent du mot de passe temporaire et différent de
 * l'ancien (`MotDePassePerduService`). Un temporaire expiré (24 h) n'ouvre plus
 * rien : il faut en faire générer un nouveau.
 *
 * Après le changement, la session est FERMÉE (et ses jetons, et son « se
 * souvenir de moi ») : on se reconnecte avec le nouveau mot de passe.
 *
 * Aucun module RBAC : le geste ne porte que sur le compte qui le fait, comme
 * `MonProfil::changerMotDePasse()` (inscrit dans `ECRITURES_HORS_MODULE`).
 */
class ChangementMotDePasseObligatoire extends Component
{
    public string $nouveauMotDePasse = '';

    public string $confirmationMotDePasse = '';

    public function definirNouveauMotDePasse(MotDePassePerduService $service): mixed
    {
        /** @var User|null $utilisateur */
        $utilisateur = Auth::user();

        if ($utilisateur === null) {
            abort(401, __('auth.requise'));
        }

        $donnees = $this->validate([
            'nouveauMotDePasse' => ['required', 'string', 'min:'.MotDePassePerduService::LONGUEUR_MIN],
            'confirmationMotDePasse' => ['required', 'string'],
        ], [
            'nouveauMotDePasse.required' => __('pwa.changement_mdp.nouveau_requis'),
            'nouveauMotDePasse.min' => __('pwa.changement_mdp.trop_court'),
            'confirmationMotDePasse.required' => __('pwa.changement_mdp.confirmation_requise'),
        ]);

        if ($donnees['nouveauMotDePasse'] !== $donnees['confirmationMotDePasse']) {
            $this->addError('confirmationMotDePasse', __('pwa.profil.mdp_confirmation_invalide'));

            return null;
        }

        // Un compte qui n'a rien à changer n'a rien à faire ici.
        if (! $utilisateur->must_change_password) {
            return $this->redirectRoute('pwa.accueil', navigate: true);
        }

        try {
            $service->definirApresChangementObligatoire($utilisateur, $donnees['nouveauMotDePasse']);
        } catch (RuntimeException $refus) {
            $this->reset(['nouveauMotDePasse', 'confirmationMotDePasse']);
            $this->addError('nouveauMotDePasse', $refus->getMessage());

            return null;
        }

        // La session est coupée : on se reconnecte avec le nouveau mot de passe.
        Auth::logout();
        session()->invalidate();
        session()->regenerateToken();
        session()->flash('pwa-connexion-info', __('pwa.changement_mdp.succes'));

        return $this->redirectRoute('pwa.connexion', navigate: true);
    }

    public function render(): View
    {
        return view('pwa.livewire.changement-mot-de-passe-obligatoire')->layout('layouts.pwa-invite', [
            'titre' => __('pwa.changement_mdp.titre_page'),
        ]);
    }
}
