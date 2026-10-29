<?php

declare(strict_types=1);

namespace App\Pwa\Livewire;

use App\Pwa\Support\EmpreinteMotDePasseEnSession;
use App\Shared\Auth\Http\Controllers\AuthController;
use App\Shared\Rbac\Models\JournalSecurite;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\View\View;
use Livewire\Attributes\Validate;
use Livewire\Component;

// Le nom d'onglet est le <h1> de la page suivi de la marque (contrat de
// `BaliseTitrePwaTest`, même règle que les autres pages), et il vient de la
// langue : `pwa.connexion.titre_page`, passé par `render()` sous `titre`,
// que `layouts/pwa-invite` lit AVANT `$title`.
//
// L'attribut `#[Title('LogiRestock TATACORA AFRIQUE — LogiReStock — TATACORA AFRIQUE')]`
// qui figurait ici a été RETIRÉ le 13/10/2026 (PA-209, ticket D390) : il
// n'était jamais lu — `$titre ?? $title` s'arrête au premier — et portait
// encore le nom d'un autre produit (décision du PO, PA-208). Le titre rendu
// est tenu par `AucunLogiRestockAfficheTest` et `BaliseTitrePwaTest`.
class Connexion extends Component
{
    #[Validate('required|string', message: 'L\'identifiant est obligatoire.')]
    public string $login = '';

    #[Validate('required|string', message: 'Le mot de passe est obligatoire.')]
    public string $motDePasse = '';

    public function seConnecter(): mixed
    {
        $this->validate();

        $cle = 'connexion-pwa|' . mb_strtolower($this->login) . '|' . request()->ip();

        if (RateLimiter::tooManyAttempts($cle, 5)) {
            $this->addError('identifiants', __('pwa.connexion.trop_de_tentatives', [
                'secondes' => RateLimiter::availableIn($cle),
            ]));

            return null;
        }

        $identifiants = [
            'login' => $this->login,
            'password' => $this->motDePasse,
        ];

        if (! Auth::attempt($identifiants)) {
            RateLimiter::hit($cle, AuthController::BLOCAGE_SECONDES);
            $this->tracerEchec();
            $this->reset('motDePasse');

            $this->addError('identifiants', __('auth.failed'));

            return null;
        }

        $utilisateur = Auth::user();

        if ($utilisateur === null || ! $utilisateur->estActif()) {
            Auth::logout();
            $this->tracerEchec();
            $this->reset('motDePasse');
            $this->addError('identifiants', __('auth.compte_desactive'));

            return null;
        }

        // Mot de passe TEMPORAIRE posé par un administrateur (29/10/2026) : expiré
        // (24 h), il n'ouvre rien ; valide, il n'ouvre QUE « Définissez votre
        // nouveau mot de passe » (`ExigerChangementMotDePasse` ferme le reste).
        if ($utilisateur->motDePasseTemporaireExpire()) {
            Auth::logout();
            $this->reset('motDePasse');
            $this->addError('identifiants', __('pwa.changement_mdp.expire'));

            return null;
        }

        RateLimiter::clear($cle);
        session()->regenerate();

        // L'empreinte du mot de passe est rangée dans la session : si un
        // administrateur réinitialise ce compte, `FermerLesSessionsPerimees` la
        // voit changer et ferme cette session. Sans cela, elle ne serait rangée
        // qu'à la requête suivante — APRÈS une réinitialisation éventuelle.
        EmpreinteMotDePasseEnSession::poser($utilisateur);

        if ($utilisateur->must_change_password) {
            $utilisateur->forceFill(['derniere_connexion' => now()])->save();

            return $this->redirectRoute('pwa.changement-mot-de-passe', navigate: true);
        }

        // Les modales d'ouverture (alertes-ouverture.js du maitre) se
        // montrent UNE fois par connexion : le drapeau est pose ici,
        // consomme par AlertesOuvertureModales — rouvrir un onglet ne
        // reaffiche rien, une nouvelle connexion, si.
        // Cle LITTERALE, exigee par `SessionSansDonneeMetierTest` (une cle
        // calculee est illisible, donc non relue) ; l'egalite avec
        // `AlertesOuvertureModales::CLE_SESSION` est PROUVEE par
        // `AlertesOuvertureModalesTest` — le lien est teste, pas suppose.
        session()->put('alertes_ouverture_en_attente', true);
        $utilisateur->forceFill(['derniere_connexion' => now()])->save();

        return $this->redirectRoute('pwa.accueil', navigate: true);
    }

    private function tracerEchec(): void
    {
        JournalSecurite::create([
            'type_evenement' => 'connexion_echouee',
            'login_tente' => $this->login,
            'adresse_ip' => request()->ip(),
        ]);
    }

    public function render(): View
    {
        return view('pwa.livewire.connexion')->layout('layouts.pwa-invite', [
            'titre' => __('pwa.connexion.titre_page'),
        ]);
    }
}
