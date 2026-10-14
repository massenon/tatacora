<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Transverse;

use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\View\View;
use Livewire\Component;

/**
 * Le VERROU DE SESSION — écran demandé par le Product Owner le 01/09/2026,
 * sans équivalent au maître (`prototype_v2/` n'a aucune notion d'inactivité :
 * c'est une maquette statique, jamais laissée ouverte sur un vrai poste).
 * Transcrit ici depuis zéro, en respectant les mêmes règles que le reste de
 * la coquille.
 *
 * ## Ce que « suspendue, pas fermée » veut dire, et pourquoi c'est délibéré
 *
 * Ce composant ne touche JAMAIS à `Auth::logout()`, à la session HTTP, ni à
 * aucun état Livewire de la page sous-jacente (un panier ouvert au POS
 * comptant, une modale à moitié remplie). Il pose un voile opaque PAR-DESSUS
 * la page — un mécanisme entièrement côté client (Alpine, voir
 * `pwa.partials.verrou-session`) — et ce composant ne fait qu'UNE chose :
 * vérifier un mot de passe SANS ré-authentifier (`Auth::validate()`, jamais
 * `Auth::attempt()`, qui régénérerait la session et pourrait interrompre une
 * requête Livewire en vol sur un autre composant de la même page).
 *
 * ## Pourquoi `deverrouiller()` n'exige AUCUN droit de module
 *
 * Comme `Connexion::seConnecter()` et `PageMetier::seDeconnecter()` — voir
 * `PwaEcritureAutoriseeTest::METHODES_DE_LECTURE`, catégorie 2 : le verrou
 * protège la SESSION, pas une table métier. Exiger un niveau RBAC ici
 * enfermerait dehors, verrou compris, un rôle dont la matrice a été mal
 * configurée entre-temps — exactement ce que la même règle refuse déjà pour
 * la déconnexion.
 *
 * ## Le mot de passe ne transite JAMAIS en clair vers un journal
 *
 * `motDePasse` est réinitialisée après CHAQUE tentative, échec compris —
 * jamais conservée en mémoire de composant plus longtemps qu'il ne faut pour
 * l'essai en cours.
 *
 * @see resources/views/pwa/partials/verrou-session.blade.php (l'overlay, le minuteur d'inactivité)
 * @see resources/views/layouts/pwa.blade.php (le seul point de montage)
 */
final class VerrouSession extends Component
{
    /** 15 minutes — la durée annoncée à l'écran, une seule fois, ici. */
    public const INACTIVITE_SECONDES = 15 * 60;

    public string $motDePasse = '';

    /**
     * Vérifie le mot de passe de l'utilisateur COURANT et lève le verrou
     * côté client par un événement — jamais une redirection, jamais un
     * rechargement : la page sous le voile n'a pas bougé.
     */
    public function deverrouiller(): void
    {
        $utilisateur = Auth::user();

        if ($utilisateur === null) {
            // Une session expirée côté serveur pendant que le voile était
            // affiché : le verrou ne peut plus rien déverrouiller localement,
            // la seule issue honnête est de renvoyer vers la connexion.
            $this->redirectRoute('pwa.connexion', navigate: true);

            return;
        }

        // Même clé de limitation que `Connexion::seConnecter()`, appliquée
        // à l'utilisateur déjà identifié plutôt qu'au couple login+IP : ici
        // l'identité n'est plus en question, seul le mot de passe l'est.
        $cle = 'verrou-session|' . $utilisateur->id;

        if (RateLimiter::tooManyAttempts($cle, 5)) {
            $this->reset('motDePasse');
            $this->addError('motDePasse', __('pwa.verrou.trop_de_tentatives', [
                'secondes' => RateLimiter::availableIn($cle),
            ]));

            return;
        }

        $valide = Auth::validate([
            'login' => $utilisateur->login,
            'password' => $this->motDePasse,
        ]);

        $this->reset('motDePasse');

        if (! $valide) {
            RateLimiter::hit($cle, 60);
            $this->addError('motDePasse', __('pwa.verrou.erreur'));

            return;
        }

        RateLimiter::clear($cle);
        $this->resetValidation();
        $this->dispatch('session-deverrouillee');
    }

    public function render(): View
    {
        return view('pwa.livewire.verrou-session');
    }
}
