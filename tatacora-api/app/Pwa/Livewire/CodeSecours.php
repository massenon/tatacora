<?php

declare(strict_types=1);

namespace App\Pwa\Livewire;

use App\Shared\Auth\Services\MotDePassePerduService;
use Illuminate\View\View;
use Livewire\Component;
use RuntimeException;

/**
 * « J'ai perdu mon mot de passe administrateur » — nom d'utilisateur + code de
 * secours + nouveau mot de passe (décision du PO du 29/10/2026).
 *
 * Accessible SANS session, depuis le message « Contactez l'administrateur » de
 * l'écran de connexion : c'est le recours du DERNIER administrateur. Un compte
 * non administrateur ne peut pas l'emprunter ; le refus est un seul message,
 * que le compte existe ou non (`MotDePassePerduService`). Les essais sont
 * limités (5, puis 15 minutes) par compte et par adresse.
 *
 * Après un succès : le code est consommé et un NOUVEAU est affiché, une seule
 * fois (`$nouveauCode`, vidé dès que la page est quittée). Le mot de passe saisi
 * et le code saisi sont purgés après chaque tentative.
 *
 * Aucun module RBAC : aucune session n'existe encore (même famille que
 * `Connexion::seConnecter()`, inscrite dans `ECRITURES_HORS_MODULE`).
 */
class CodeSecours extends Component
{
    public string $login = '';

    public string $code = '';

    public string $nouveauMotDePasse = '';

    public string $confirmationMotDePasse = '';

    public ?string $nouveauCode = null;

    public function reinitialiserParCodeDeSecours(MotDePassePerduService $service): void
    {
        $this->resetErrorBag();

        // La forme d'abord : une saisie incomplète ne consomme aucun essai.
        $this->validate([
            'login' => ['required', 'string'],
            'code' => ['required', 'string'],
            'nouveauMotDePasse' => ['required', 'string', 'min:'.MotDePassePerduService::LONGUEUR_MIN],
            'confirmationMotDePasse' => ['required', 'string'],
        ], [
            'login.required' => __('pwa.code_secours.login_requis'),
            'code.required' => __('pwa.code_secours.code_requis'),
            'nouveauMotDePasse.required' => __('pwa.changement_mdp.nouveau_requis'),
            'nouveauMotDePasse.min' => __('pwa.changement_mdp.trop_court'),
            'confirmationMotDePasse.required' => __('pwa.changement_mdp.confirmation_requise'),
        ]);

        if ($this->nouveauMotDePasse !== $this->confirmationMotDePasse) {
            $this->addError('confirmationMotDePasse', __('pwa.profil.mdp_confirmation_invalide'));

            return;
        }

        try {
            $this->nouveauCode = $service->reinitialiserParCodeDeSecours(
                $this->login,
                $this->code,
                $this->nouveauMotDePasse,
                request()->ip(),
            );
        } catch (RuntimeException $refus) {
            $this->addError('identifiants', $refus->getMessage());
        } finally {
            // Jamais conservés en mémoire de composant au-delà de l'essai.
            $this->reset(['code', 'nouveauMotDePasse', 'confirmationMotDePasse']);
        }
    }

    public function render(): View
    {
        return view('pwa.livewire.code-secours')->layout('layouts.pwa-invite', [
            'titre' => __('pwa.code_secours.titre_page'),
        ]);
    }
}
