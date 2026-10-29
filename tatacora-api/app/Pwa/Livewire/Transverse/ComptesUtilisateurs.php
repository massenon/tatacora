<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Transverse;

use App\Models\User;
use App\Pwa\Support\AutoriseEcriture;
use App\Shared\Auth\Services\MotDePassePerduService;
use Illuminate\Support\Facades\Auth;
use Illuminate\View\View;
use Livewire\Attributes\Title;
use RuntimeException;

/**
 * Comptes utilisateurs — la liste des comptes et « Réinitialiser le mot de
 * passe » (décision du PO du 29/10/2026, option A : pas de « mot de passe
 * oublié » automatique par e-mail).
 *
 * ## Ce que fait le geste
 *
 * Un administrateur choisit un AUTRE compte : l'application génère un mot de
 * passe temporaire (14 caractères, sans caractère ambigu), le montre UNE seule
 * fois à l'administrateur (bouton « Copier »), pose son empreinte et marque le
 * compte « changement obligatoire ». Le temporaire expire après 24 h. Toutes
 * les règles vivent dans `MotDePassePerduService` — ce composant n'en recalcule
 * aucune.
 *
 * ## Le secret ne survit pas à la fermeture
 *
 * `$resultat` porte le temporaire le temps de la fenêtre qui l'affiche ;
 * `fermerModales()` le vide, et aucune autre propriété ne le copie. Il ne figure
 * ni au journal d'audit ni dans les logs.
 *
 * ## Le droit
 *
 * Route sous `module:ROLES,L` ; le geste exige en plus `C` sur ROLES
 * (`exigerEcriture`) ET l'un des deux rôles d'administration (le service le
 * relit). Un administrateur ne réinitialise pas son propre compte ici : il
 * passe par « Mon profil », avec l'ancien mot de passe.
 *
 * @see RG-15 Traçabilité des actions sensibles
 * @see RG-16 Contrôle d'accès basé sur les rôles
 */
#[Title('Comptes utilisateurs — LogiReStock — TATACORA AFRIQUE')]
class ComptesUtilisateurs extends PageTransverse
{
    use AutoriseEcriture;

    public const MODULE = 'ROLES';

    /** Le compte dont la réinitialisation attend confirmation. */
    public ?string $compteACibler = null;

    /** @var array{login: string, motDePasse: string, expireLe: string}|null */
    public ?array $resultat = null;

    public ?string $refus = null;

    /** Ouvre la confirmation ; n'écrit rien. */
    public function ouvrirReinitialisation(string $compteId): void
    {
        $this->resultat = null;
        $this->refus = null;
        $this->compteACibler = $compteId;

        if ($compteId === Auth::id()) {
            $this->refus = __('pwa.comptes.refus_soi_meme');
            $this->compteACibler = null;
        }
    }

    public function fermerModales(): void
    {
        $this->compteACibler = null;
        $this->resultat = null;
        $this->refus = null;
    }

    public function reinitialiserMotDePasse(MotDePassePerduService $service): void
    {
        $auteur = $this->exigerEcriture(self::MODULE);
        $compteId = $this->compteACibler;
        $this->compteACibler = null;
        $this->refus = null;

        if ($compteId === null) {
            return;
        }

        try {
            $fait = $service->reinitialiserParAdministrateur($auteur, $compteId, request()->ip());
        } catch (RuntimeException $refus) {
            $this->refus = $refus->getMessage();

            return;
        }

        $this->resultat = [
            'login' => $fait['login'],
            'motDePasse' => $fait['motDePasse'],
            'expireLe' => $fait['expireLe']->format('d/m/Y H:i'),
        ];
    }

    public function render(): View
    {
        /** @var User|null $courant */
        $courant = Auth::user();

        $comptes = User::query()
            ->with(['role', 'employe'])
            ->orderBy('login')
            ->get();

        $cible = $this->compteACibler === null ? null : $comptes->firstWhere('id', $this->compteACibler);

        return view('pwa.transverse.comptes-utilisateurs', array_merge($this->socle(), [
            'comptes' => $comptes,
            'compteCourantId' => $courant?->id,
            'peutReinitialiser' => $courant?->estAdministrateur() ?? false,
            'cible' => $cible,
            'roles' => RolesPermissions::ROLES,
            'statuts' => MonProfil::STATUTS,
        ]))->layout('layouts.pwa', ['title' => __('pwa.comptes.titre_page')]);
    }
}
