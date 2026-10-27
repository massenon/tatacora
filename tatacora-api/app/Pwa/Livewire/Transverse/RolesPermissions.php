<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Transverse;

use App\Models\User;
use App\Pwa\Livewire\Concerns\FormulaireModal;
use App\Shared\Rbac\Models\Role;
use App\Shared\Rbac\Services\RolePermissionService;
use Illuminate\View\View;
use Livewire\Attributes\Title;
use RuntimeException;

/**
 * Rôles & Permissions — maitre : `prototype_v2/pages/roles-permissions.html`.
 *
 * Deux blocs dans l'ordre du maitre : la grille de cartes de roles (l.35) puis
 * la « Matrice complète des permissions » (l.38-51), avec sa legende a trois
 * entrees et sa premiere colonne collante.
 *
 * ## DIRECTIVE DU PRODUCT OWNER (01/09/2026) : L'ECRAN DEVIENT EDITABLE
 *
 * Les quatre refus ci-dessous sont LEVÉS. `RolePermissionService` (recherché
 * avant création — aucun Service RBAC n'existait) écrit désormais réellement
 * `permission_role`, avec une seule règle métier : le verrouillage de
 * soi-même sur `administrateur`/`ROLES` (voir son en-tête).
 *
 * ## LA MATRICE EST LUE, JAMAIS RECOPIEE — ça, ça ne change pas
 *
 * `LARAVEL_PWA.md` §5 : « Policy Laravel identique a celle utilisee par l'API
 * Flutter — MEME classe, pas une copie adaptee au contexte web. » La regle
 * vaut pour la source des droits : chaque case vient de
 * `Role::niveauSurModule()`, qui derive les permissions reellement attachees.
 * C'est la meme methode que `User::niveauSurModule()`, donc que
 * `VerifierAccesModule` et que le menu lateral. `RolePermissionService::
 * definirNiveau()` synchronise les LIGNES de `permission_role`, jamais une
 * colonne `niveau` inventée : la lecture n'a donc pas bougé.
 *
 * ⚠ La consequence mérite d'etre connue : `niveauSurModule()` rend `'L'` des
 * qu'UNE permission existe sur le module et `'C'` au-dela. Un role a qui l'on
 * n'aurait donne que `supprimer` s'afficherait donc « L ». C'est le
 * comportement du serveur, pas une approximation de cet ecran — le corriger
 * ici creerait precisement la divergence que §5 interdit. C'est pourquoi
 * `definirNiveau()` synchronise TOUJOURS l'ensemble des actions du niveau
 * (`ACTIONS_PAR_NIVEAU`), jamais une action isolée.
 *
 * ÉCART DÉLIBÉRÉ — `roles-permissions.html` l.145-146 et l.156-157
 * Le maitre : « Modifier les droits » sur chaque carte ET sur chaque en-tete
 * de colonne.
 * Ici : le geste n'existe que sur la CARTE (une modale par rôle, tous les
 * modules à la fois) — pas sur l'en-tête de colonne (qui éditerait un module
 * à la fois, sur tous les rôles). Le maître propose les deux chemins vers le
 * MÊME résultat ; en porter un seul évite deux formulaires qui écriraient la
 * même chose par deux routes.
 *
 * ## Ce qui n'est TOUJOURS PAS porté — Article 8
 *
 * ÉCART DÉLIBÉRÉ — `roles-permissions.html` l.129-131 (« Compte démo »)
 * Le maitre : le compte de demonstration rattache a chaque role, avec ses
 * initiales, tire de `COMPTES_DEMO`.
 * Ici : le NOMBRE de comptes reels qui portent le role.
 * Raison : Article 6 — les jeux de donnees figes de la maquette ne se portent
 * jamais. Et ce nombre est l'information utile : c'est lui qui dit si un role
 * est supprimable, ce que le maitre calcule par ailleurs
 * (`RBAC.rolesUtilises()`, l.109). Afficher un identifiant de compte sur une
 * page consultable serait par ailleurs distribuer des logins.
 *
 * Refus déclarés :
 *   maitre-refuse:roles-permissions.html#compte-demo
 *   maitre-refuse:roles-permissions.html#niveau-derive
 * @see RG-16 Contrôle d'accès basé sur les rôles
 * @see LARAVEL_PWA.md §5
 */
#[Title('Rôles & Permissions — LogiReStock — TATACORA AFRIQUE')]
class RolesPermissions extends PageTransverse
{
    use FormulaireModal;

    /** Le module RBAC de l'écran — `data-module="ROLES"` au maître. */
    public const MODULE = 'ROLES';

    /**
     * Les seize modules du maitre (l.91-95), dans son ordre et avec SES
     * abreviations — « CRM », « Tab. de Bord », « RH », « États ». Ce ne sont
     * pas celles du menu lateral, et les harmoniser serait le dixieme interdit
     * de l'Article 1.
     *
     * @var array<string, string>
     */
    public const MODULES = [
        'M1' => 'Hébergement',
        'M2' => 'Facturation',
        'M3' => 'CRM',
        'M4' => 'Restaurant',
        'M5' => 'Bar',
        'M6' => 'Stocks',
        'M7' => 'Achats',
        'M8' => 'Véhicules',
        'M9' => 'Tourisme',
        'M10' => 'Comptabilité',
        'M11' => 'Tab. de Bord',
        'M12' => 'Notifications',
        'M13' => 'RH',
        'M14' => 'États',
        'ROLES' => 'Rôles',
        'PARAM' => 'Paramètres',
    ];

    /**
     * Les onze roles du maitre (l.96-100). La cle est celle que
     * `roles.libelle` stocke — le seeder y ecrit `administrateur`, `gerant`…
     *
     * Un role absent de cette table est rendu par le repli du maitre (l.104) :
     * tirets remplaces par des espaces, premiere lettre en capitale. Un role
     * ajoute demain s'affiche donc, au lieu de disparaitre.
     *
     * @var array<string, string>
     */
    public const ROLES = [
        'administrateur' => 'Administrateur système',
        'gerant' => 'Gérant / Direction',
        'receptionniste' => 'Réceptionniste',
        'cuisine' => 'Resp. Restaurant/Cuisine',
        'barman' => 'Barman',
        'magasinier' => 'Magasinier',
        'achats' => 'Resp. Achats',
        'vehicules' => 'Resp. Véhicules',
        'guide' => 'Guide Touristique',
        'rh' => 'Resp. RH',
        'comptable' => 'Comptable',
    ];

    // ---------------------------------------------------- formulaire « nouveau rôle »
    public string $libelleRoleSaisi = '';

    public string $descriptionRoleSaisi = '';

    // ---------------------------------------------------- formulaire « modifier droits »
    public ?string $roleEnEditionId = null;

    public string $roleEnEditionCode = '';

    public string $roleEnEditionLibelle = '';

    /** @var array<string, string> */
    public array $niveauxSaisis = [];

    /**
     * @return array<string, list<string>>
     */
    protected function formulaires(): array
    {
        return [
            'nouveau_role' => ['libelleRoleSaisi', 'descriptionRoleSaisi'],
            'droits' => ['roleEnEditionId', 'roleEnEditionCode', 'roleEnEditionLibelle', 'niveauxSaisis'],
            'retablir_socle' => [],
        ];
    }

    public function ouvrirFormulaireRole(): void
    {
        $this->ouvrirFormulaire('nouveau_role');
    }

    public function enregistrerRole(RolePermissionService $service): void
    {
        $donnees = $this->validerEcriture([
            'libelleRoleSaisi' => ['required', 'string', 'max:100'],
            'descriptionRoleSaisi' => ['nullable', 'string', 'max:255'],
        ]);

        try {
            $service->creerRole(
                (string) $donnees['libelleRoleSaisi'],
                filled($donnees['descriptionRoleSaisi']) ? (string) $donnees['descriptionRoleSaisi'] : null,
            );
        } catch (RuntimeException $refus) {
            $this->addError('libelleRoleSaisi', $refus->getMessage());

            return;
        }

        $this->terminerFormulaire(__('pwa.roles.nouveau_role_cree'));
    }

    /**
     * Ouvre « Modifier les droits » — un rôle, TOUS ses modules à la fois.
     */
    public function ouvrirFormulaireDroits(string $roleId): void
    {
        $this->ouvrirFormulaire('droits');

        $role = Role::with('permissions')->findOrFail($roleId);

        $this->roleEnEditionId = $role->getKey();
        $this->roleEnEditionCode = $role->libelle;
        $this->roleEnEditionLibelle = self::libelleRole($role->libelle);

        $niveaux = [];
        foreach (array_keys(self::MODULES) as $module) {
            $niveaux[$module] = $role->niveauSurModule($module);
        }
        $this->niveauxSaisis = $niveaux;
    }

    /**
     * ⚠ MANQUAIT alors que deux boutons « Annuler » l'appelaient déjà :
     * `ChargementDesEcransPwaTest` l'a attrapé le 01/09/2026 — un clic en
     * production levait MethodNotFound. Le trait `FormulaireModal` ne
     * fournit PAS cette action publique : chaque composant la déclare.
     */
    public function fermerModales(): void
    {
        $this->etatFormulaire = null;
        $this->resetValidation();
    }

    /**
     * « Tout retirer » (modale-role du maître) : pose « - » sur chaque module
     * DANS LA SAISIE — rien n'est enregistré tant que l'Administrateur ne
     * valide pas. Le verrou administrateur/ROLES tient : la case n'est pas
     * rendue en select pour lui, et `enregistrerDroits()` refuse de toute
     * façon de le désarmer côté serveur.
     */
    public function toutRetirer(): void
    {
        $this->exigerEcriture(self::MODULE);

        foreach (array_keys(self::MODULES) as $code) {
            if ($code === 'ROLES' && $this->roleEnEditionCode === 'administrateur') {
                continue;
            }

            $this->niveauxSaisis[$code] = '-';
        }
    }

    public function enregistrerDroits(RolePermissionService $service): void
    {
        $regles = ['roleEnEditionId' => ['required', 'string']];
        foreach (array_keys(self::MODULES) as $module) {
            $regles["niveauxSaisis.{$module}"] = ['required', 'in:C,L,-'];
        }

        $donnees = $this->validerEcriture($regles);

        $role = Role::findOrFail($donnees['roleEnEditionId']);

        foreach ($donnees['niveauxSaisis'] as $module => $niveau) {
            try {
                $service->definirNiveau($role, (string) $module, (string) $niveau);
            } catch (RuntimeException $refus) {
                $this->addError('niveauxSaisis.' . $module, $refus->getMessage());

                return;
            }
        }

        $this->terminerFormulaire(__('pwa.roles.modifier_droits_enregistre'));
    }

    /**
     * Ouvre la confirmation « Rétablir le socle du CdCF » — jamais
     * `wire:confirm` (boîte native interdite, `MotifsInterditsPwaTest`).
     */
    public function ouvrirRetablirSocle(): void
    {
        $this->ouvrirFormulaire('retablir_socle');
    }

    public function retablirSocle(RolePermissionService $service): void
    {
        $this->exigerEcriture(self::MODULE);

        $nombre = $service->retablirSocle();

        $this->terminerFormulaire(__('pwa.roles.retablir_socle_fait', ['nombre' => $nombre]));
    }

    public function render(RolePermissionService $service): View
    {
        $roles = Role::query()
            ->with('permissions')
            ->withCount('utilisateurs')
            ->orderBy('libelle')
            ->get();

        $lignes = [];
        $cartes = [];

        foreach ($roles as $role) {
            $droits = [];

            foreach (array_keys(self::MODULES) as $module) {
                $droits[$module] = $role->niveauSurModule($module);
            }

            $lignes[$role->libelle] = $droits;

            $cartes[] = [
                'id' => $role->getKey(),
                'code' => $role->libelle,
                'libelle' => self::libelleRole($role->libelle),
                'initiales' => mb_strtoupper(mb_substr($role->libelle, 0, 2)),
                'complet' => count(array_filter($droits, static fn (string $d): bool => $d === 'C')),
                'lecture' => count(array_filter($droits, static fn (string $d): bool => $d === 'L')),
                // Le nombre de comptes REELS qui portent le role. C'est ce qui
                // dit si un role est supprimable, et c'est un nombre, pas un
                // identifiant : une page consultable ne distribue pas de logins.
                'comptes' => (int) $role->utilisateurs_count,
                // Dérivé, jamais stocké — `null` pour un rôle ajouté hors socle.
                'conforme' => $service->estConformeAuSocle($role),
            ];
        }

        return view('pwa.transverse.roles-permissions', array_merge($this->socle(), [
            'cartes' => $cartes,
            'matrice' => $lignes,
            // Le badge global du maître (`etat-matrice`) — DÉRIVÉ des cartes :
            // conforme si aucun rôle du socle ne s'en écarte (un rôle ajouté,
            // `conforme === null`, ne rend pas la matrice « amendée » à lui
            // seul : il n'appartient pas au socle qu'on compare).
            'matriceConformeAuSocle' => collect($cartes)->every(
                static fn (array $carte): bool => $carte['conforme'] !== false,
            ),
            // Le total de comptes actifs, pour que « 0 compte » se distingue
            // d'un referentiel vide (Article 7).
            'comptes' => User::query()->count(),
            'peutEcrire' => $this->peutEcrire(),
        ]))->layout('layouts.pwa', ['title' => __('pwa.roles.titre_page')]);
    }

    /**
     * Le libelle affiche d'un role — celui du maitre, ou son repli (l.104).
     */
    protected static function libelleRole(string $code): string
    {
        if (isset(self::ROLES[$code])) {
            return self::ROLES[$code];
        }

        return mb_convert_case(str_replace('_', ' ', $code), MB_CASE_TITLE, 'UTF-8');
    }

    private function peutEcrire(): bool
    {
        $utilisateur = auth()->user();

        return $utilisateur instanceof User
            && $utilisateur->estActif()
            && $utilisateur->niveauSurModule(self::MODULE) === 'C';
    }
}
