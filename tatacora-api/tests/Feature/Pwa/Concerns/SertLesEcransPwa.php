<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa\Concerns;

use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Illuminate\Support\Facades\Hash;

/**
 * « Sers-moi cet écran, pour de vrai. »
 *
 * Les gardes de conformité lisent le HTML **rendu**, jamais le source du
 * composant. C'est la leçon exacte du défaut de la balise `<title>` : le code
 * porte `#[Title(...)]` sur chaque page et les cinq pages mesurées rendaient
 * toutes `TATACORA AFRIQUE`. Une garde qui aurait relu l'attribut PHP aurait
 * été verte pendant que chaque onglet du navigateur affichait la même chose.
 *
 * Ce trait fournit donc les deux seules choses dont les gardes ont besoin :
 * un Administrateur réel (pas un `actingAs()` sur un utilisateur sans rôle —
 * le RBAC de 2ᵉ niveau le refuserait) et le contenu servi par la route.
 */
trait SertLesEcransPwa
{
    private ?User $administrateurPwa = null;

    /**
     * Un Administrateur — le seul profil qui atteint les 44 routes. Un rôle
     * plus étroit ferait passer une partie du balayage par des 403, c'est-à-
     * dire par un balayage à vide sur les écrans qu'il ne voit pas.
     */
    protected function administrateurPwa(): User
    {
        if ($this->administrateurPwa instanceof User) {
            return $this->administrateurPwa;
        }

        return $this->administrateurPwa = User::create([
            'login' => 'garde.conformite',
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', 'administrateur')->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }

    /**
     * Le HTML servi par un écran, ou `null` si la route n'a pas répondu 200.
     * Le code HTTP est rendu par référence pour que l'appelant puisse le
     * nommer dans son message — « 500 » et « 403 » ne se corrigent pas de la
     * même façon.
     *
     * @param  array<string, mixed>  $ecran
     *
     * @param-out int $code
     */
    protected function htmlDe(array $ecran, ?int &$code = null): ?string
    {
        if (($ecran['invite'] ?? false) === true) {
            // ⚠ `actingAs()` PERSISTE d'un appel a l'autre dans le meme test.
            // Sans cette deconnexion, /pwa/connexion etait demande avec la
            // session posee par l'ecran precedent (l'ordre est alphabetique,
            // /pwa/clients vient avant) et repondait 302 — un faux echec qui
            // aurait fini par faire desarmer la garde.
            $this->app['auth']->logout();
            $this->app['auth']->forgetGuards();

            $reponse = $this->get((string) $ecran['url']);
        } else {
            $reponse = $this->actingAs($this->administrateurPwa())->get((string) $ecran['url']);
        }

        $code = $reponse->getStatusCode();

        return $code === 200 ? (string) $reponse->getContent() : null;
    }
}
