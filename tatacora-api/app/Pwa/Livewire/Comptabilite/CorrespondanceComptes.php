<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Comptabilite;

use App\Domain\Comptabilite\Services\CorrespondanceComptesService;
use App\Domain\Comptabilite\Support\RolesCorrespondance;
use App\Pwa\Livewire\Concerns\FormulaireModal;
use App\Shared\Parametres\Services\EnregistrerParametreService;
use Illuminate\View\View;
use Livewire\Attributes\Title;
use RuntimeException;

/**
 * Correspondance des comptes — écran du hub de la comptabilité, créé le
 * 26/10/2026 sur ordre du PO : « on peut impérativement modifier les comptes
 * sur poste et le web ».
 *
 * Écran AJOUTÉ, absent du maître : `structure-ajout:m10-correspondance-comptes.html#page`.
 *
 * ## Ce que l'écran fait
 *
 * Liste les rôles comptables (produits par module, TVA, trésoreries, tiers,
 * résultat), le compte ACTUEL de chacun, son défaut, et permet de le changer.
 * Un changement est UN paramètre (`compte_<rôle>`) écrit par
 * `EnregistrerParametreService` — le seul chemin d'écriture des paramètres :
 * registre fermé, validation (format, existence au plan, classe cohérente avec
 * le rôle, compte imputable), dernier écrit gagnant, journal d'audit avec
 * l'ancienne valeur, descente vers les postes.
 *
 * ## Ce que l'écran DIT
 *
 * Un changement vaut pour les pièces FUTURES ; une pièce déjà passée n'est
 * jamais réécrite (RG-11). La phrase est affichée en tête
 * (`comptes_correspondance.avertissement`).
 *
 * ## Droits
 *
 * Module M10 : lecture pour qui consulte la comptabilité, écriture pour qui
 * a `C` (administrateurs, gérant, comptable) — les règles existantes, aucune
 * nouvelle. `exigerEcriture(self::MODULE)` garde chaque action.
 *
 * @see RG-10 paramétrage sans déploiement
 * @see RG-11 immutabilité des pièces
 * @see RG-15 traçabilité des actions sensibles
 */
#[Title('Correspondance des comptes — TATACORA AFRIQUE')]
class CorrespondanceComptes extends PageComptabilite
{
    use FormulaireModal;

    public const MODULE = 'M10';

    /** Le rôle en cours d'édition — validé contre le registre fermé. */
    public string $roleEdite = '';

    public string $numeroEdite = '';

    /**
     * @return array<string, list<string>>
     */
    protected function formulaires(): array
    {
        return [
            'role' => ['roleEdite', 'numeroEdite'],
        ];
    }

    public function ouvrirEditionRole(string $role, CorrespondanceComptesService $comptes): void
    {
        $this->ouvrirFormulaire('role');

        // Un rôle hors registre vient du navigateur : refusé avant tout affichage.
        if (! RolesCorrespondance::existe($role)) {
            abort(404);
        }

        $this->roleEdite = $role;
        $this->numeroEdite = $comptes->compte($role);
    }

    public function enregistrerRole(EnregistrerParametreService $service): void
    {
        $this->exigerEcriture(self::MODULE);
        // Le refus d'une saisie précédente ne survit pas à la saisie suivante.
        $this->resetValidation();

        // Vide : rien à enregistrer — « Rétablir le défaut » est le geste qui
        // vide le paramètre, il ne se fait pas par accident.
        if (trim($this->numeroEdite) === '') {
            $this->addError('numeroEdite', __('comptes_correspondance.champ_compte_requis'));

            return;
        }

        $this->ecrire($service, trim($this->numeroEdite), 'comptes_correspondance.enregistre');
    }

    /** Vide le paramètre : le rôle revient à son compte par défaut. */
    public function retablirRole(EnregistrerParametreService $service): void
    {
        $this->exigerEcriture(self::MODULE);
        $this->resetValidation();

        if (! RolesCorrespondance::existe($this->roleEdite)) {
            abort(404);
        }

        $this->ecrire($service, '', 'comptes_correspondance.retabli');
    }

    public function fermerModales(): void
    {
        $this->etatFormulaire = null;
        $this->resetValidation();
    }

    public function render(CorrespondanceComptesService $comptes): View
    {
        $utilisateur = auth()->user();

        return view('pwa.comptabilite.correspondance-comptes', array_merge($this->socle(), [
            'lignes' => $comptes->lignes(),
            'groupes' => RolesCorrespondance::GROUPES,
            'peutEcrire' => $utilisateur !== null
                && $utilisateur->estActif()
                && $utilisateur->niveauSurModule(self::MODULE) === 'C',
            'roleEdite' => RolesCorrespondance::existe($this->roleEdite) ? $this->roleEdite : null,
            'definitionEditee' => RolesCorrespondance::ROLES[$this->roleEdite] ?? null,
            'defautEdite' => RolesCorrespondance::existe($this->roleEdite)
                ? RolesCorrespondance::defaut($this->roleEdite)
                : null,
            'attenduEdite' => RolesCorrespondance::existe($this->roleEdite)
                ? CorrespondanceComptesService::attendu(RolesCorrespondance::ROLES[$this->roleEdite]['prefixes'])
                : null,
        ]))->layout('layouts.pwa', ['title' => __('comptes_correspondance.titre_page')]);
    }

    private function ecrire(EnregistrerParametreService $service, string $numero, string $cleMessage): void
    {
        if (! RolesCorrespondance::existe($this->roleEdite)) {
            abort(404);
        }

        try {
            $modifiees = $service->enregistrer([CorrespondanceComptesService::cle($this->roleEdite) => $numero]);
        } catch (RuntimeException $refus) {
            // Le refus du service est affiché tel quel : il dit quoi corriger.
            $this->addError('numeroEdite', $refus->getMessage());

            return;
        }

        if ($modifiees === []) {
            $this->terminerFormulaire(__('comptes_correspondance.aucun_changement'));

            return;
        }

        $this->terminerFormulaire(__($cleMessage, [
            'numero' => app(CorrespondanceComptesService::class)->compte($this->roleEdite),
        ]));
    }
}
