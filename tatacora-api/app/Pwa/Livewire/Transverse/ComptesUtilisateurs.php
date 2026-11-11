<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Transverse;

use App\Models\User;
use App\Pwa\Support\AutoriseEcriture;
use App\Shared\Auth\Services\MotDePassePerduService;
use App\Shared\Auth\Services\SuppressionCompteService;
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
 * ## Supprimer un compte (décision du PO du 03/11/2026)
 *
 * « Supprimer » est une suppression LOGIQUE, réservée au super administrateur et
 * aux comptes non administrateurs (`User::peutSupprimerDesComptes`,
 * `User::estSupprimable`, appliqués par `SuppressionCompteService`). Le bouton
 * n'apparaît que si l'auteur le peut ET que la cible l'est ; la confirmation
 * s'ouvre derrière `@if`. La suppression est ensuite publiée vers les postes
 * (descente `utilisateurs`).
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

    /** Le compte dont la SUPPRESSION attend confirmation. */
    public ?string $compteASupprimer = null;

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

    /** Ouvre la confirmation de suppression ; n'écrit rien. */
    public function ouvrirSuppression(string $compteId): void
    {
        $this->resultat = null;
        $this->refus = null;
        $this->compteACibler = null;
        $this->compteASupprimer = $compteId;

        if ($compteId === Auth::id()) {
            $this->refus = __('pwa.comptes.refus_suppression_soi_meme');
            $this->compteASupprimer = null;
        }
    }

    public function supprimerCompte(SuppressionCompteService $service): void
    {
        $auteur = $this->exigerEcriture(self::MODULE);
        $compteId = $this->compteASupprimer;
        $this->compteASupprimer = null;
        $this->refus = null;

        if ($compteId === null) {
            return;
        }

        try {
            $supprime = $service->supprimer($auteur, $compteId, request()->ip());
        } catch (RuntimeException $refus) {
            $this->refus = $refus->getMessage();

            return;
        }

        session()->flash('compte-supprime', __('pwa.comptes.supprime_succes', ['login' => $supprime->login]));
    }

    public function fermerModales(): void
    {
        $this->compteASupprimer = null;
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
            'expireLe' => \App\Shared\Support\HeureLocale::formater($fait['expireLe'], 'd/m/Y H:i'),
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
        $aSupprimer = $this->compteASupprimer === null ? null : $comptes->firstWhere('id', $this->compteASupprimer);

        return view('pwa.transverse.comptes-utilisateurs', array_merge($this->socle(), [
            'comptes' => $comptes,
            'compteCourantId' => $courant?->id,
            'peutReinitialiser' => $courant?->estAdministrateur() ?? false,
            'cible' => $cible,
            'aSupprimer' => $aSupprimer,
            'peutSupprimer' => $courant?->peutSupprimerDesComptes() ?? false,
            'roles' => RolesPermissions::ROLES,
            'statuts' => MonProfil::STATUTS,
        ]))->layout('layouts.pwa', ['title' => __('pwa.comptes.titre_page')]);
    }
}
