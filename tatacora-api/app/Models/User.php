<?php

declare(strict_types=1);

namespace App\Models;

use App\Domain\Rh\Models\Employe;
use App\Shared\Rbac\Models\Role;
use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

/**
 * Compte d'accès applicatif — table `utilisateurs`.
 *
 * Distinct de l'employé : un utilisateur système n'est pas nécessairement un
 * salarié (ex. Administrateur externe) — 03_DATABASE_ENGINEERING.md §2.
 *
 * Authentification par jetons Sanctum (client Flutter multi-plateforme),
 * jamais par session cookie — 02_SOFTWARE_ARCHITECTURE.md §3.1.
 *
 * @property string $id
 * @property string $login
 * @property string|null $email
 * @property string $mot_de_passe_hash
 * @property string $role_id
 * @property string $statut
 * @property \Illuminate\Support\Carbon|null $derniere_connexion
 * @property bool $must_change_password
 * @property \Illuminate\Support\Carbon|null $temp_expires_at
 * @property string|null $previous_password_hash
 * @property string|null $recovery_code_hash
 * @property \Illuminate\Support\Carbon|null $recovery_code_generated_at
 * @property \Illuminate\Support\Carbon|null $supprime_le
 * @property-read Role|null $role
 */
class User extends Authenticatable
{
    use HasApiTokens;

    /** @use HasFactory<UserFactory> */
    use HasFactory;

    use HasUuids;
    use Notifiable;

    /**
     * SUPPRESSION LOGIQUE d'un compte (décision du PO du 03/11/2026) : la colonne
     * `supprime_le` tient lieu de `deleted_at`. La portée globale écarte les comptes
     * supprimés de TOUTE requête (connexion, listes, jetons) ; l'auteur d'une
     * saisie se relit par `withTrashed()` (relations `belongsTo` des modèles).
     */
    use SoftDeletes;

    public const DELETED_AT = 'supprime_le';

    protected $table = 'utilisateurs';

    protected $fillable = [
        'id',
        'login',
        'email',
        'mot_de_passe_hash',
        'role_id',
        'statut',
    ];

    protected $hidden = [
        'mot_de_passe_hash',
        'remember_token',
        'previous_password_hash',
        'recovery_code_hash',
    ];

    protected function casts(): array
    {
        return [
            'mot_de_passe_hash' => 'hashed',
            'derniere_connexion' => 'datetime',
            'must_change_password' => 'boolean',
            'temp_expires_at' => 'datetime',
            'recovery_code_generated_at' => 'datetime',
            'supprime_le' => 'datetime',
        ];
    }

    /**
     * La colonne de mot de passe du schéma est `mot_de_passe_hash`
     * (vocabulaire métier français, 00_MASTER_INSTRUCTIONS.md §7),
     * pas le `password` attendu par défaut de Laravel.
     */
    public function getAuthPassword(): string
    {
        return $this->mot_de_passe_hash;
    }

    /**
     * @return BelongsTo<Role, $this>
     */
    public function role(): BelongsTo
    {
        return $this->belongsTo(Role::class, 'role_id');
    }

    /**
     * Fiche employé rattachée, si le compte en a une.
     *
     * Nullable délibérément : `utilisateurs.employe_id` l'est au schéma, et un
     * compte technique (import, job planifié) n'a pas de fiche RH. Les états
     * (RG-19) affichent alors le `login` plutôt qu'un nom fabriqué.
     *
     * @return BelongsTo<Employe, $this>
     */
    public function employe(): BelongsTo
    {
        return $this->belongsTo(Employe::class, 'employe_id');
    }

    /**
     * Niveau d'accès de l'utilisateur sur un module ('C', 'L' ou '-').
     */
    public function niveauSurModule(string $module): string
    {
        // Droit IMPLICITE des utilisateurs système (11/11/2026, PO) : voir
        // `MODULES_IMPLICITES_SYSTEME`. Un seul endroit, relu par le menu, les gardes, la page et
        // la réponse de connexion que le poste mémorise.
        if (in_array($module, self::MODULES_IMPLICITES_SYSTEME, true) && $this->estRoleSystemeImportExport()) {
            return 'C';
        }

        return $this->role?->niveauSurModule($module) ?? '-';
    }

    /**
     * Ce compte peut-il modifier CE champ de son propre profil ? [champ] est
     * l'une des clés de `ChampsProfil::DROITS`. Le droit est un module RBAC
     * transverse, binaire : seul `C` autorise ; `L` ou `-` refusent. Un compte
     * inactif ne modifie rien. Autorité unique, relue par le serveur à chaque
     * enregistrement — masquer le champ dans l'écran ne protège rien.
     */
    public function peutModifierSonProfil(string $champ): bool
    {
        $droit = \App\Pwa\Support\ChampsProfil::DROITS[$champ] ?? null;

        return $droit !== null && $this->estActif() && $this->niveauSurModule($droit) === 'C';
    }

    /**
     * Les DEUX rôles qui administrent — auteur unique de cette liste.
     *
     * Elle était écrite dans `AutoriseArchivage`, qui la lisait seul. Un
     * second geste réservé aux mêmes rôles est arrivé le 06/09/2026 (l'entrée
     * de stock depuis la fiche article, directive PO) : recopier la liste en
     * aurait fait deux, et deux listes finissent par diverger — c'est la règle
     * que ce dépôt applique partout ailleurs.
     *
     * ⚠ Ce n'est PAS un droit RBAC. Le niveau sur le module (`C`) reste exigé
     * en plus, et par le même chemin que partout : `User::niveauSurModule()`.
     * Un rôle d'administration sans droit sur le module ne passe pas.
     *
     * @var list<string>
     */
    public const ROLES_ADMINISTRATION = ['administrateur', 'super_admin'];

    /**
     * Les rôles « SYSTÈME » d'Import & Export (PO, 11/11/2026) : `super_admin`, `administrateur`,
     * `comptable`, `gerant` ET `barman` ont TOUJOURS l'accès complet à l'écran, quelle que soit la
     * ligne `IMPORT_EXPORT` en base. Les autres rôles du socle (réceptionniste, cuisine, magasinier,
     * achats, véhicules, guide, rh) restent pilotés par leur droit. Auteur unique de la liste ; le
     * poste la miroite (`rolesSystemeImportExport`). La sauvegarde étant la copie intégrale de la
     * base, le barman y accède par décision du PO.
     *
     * @var list<string>
     */
    public const ROLES_SYSTEME_IMPORT_EXPORT = ['super_admin', 'administrateur', 'comptable', 'gerant', 'barman'];

    /**
     * Les modules dont les rôles `ROLES_SYSTEME_IMPORT_EXPORT` ont TOUJOURS l'écriture,
     * même sans RBAC (ligne absente, `-` ou `L` en base) — directive PO du 11/11/2026 : « Import &
     * Export, avec ses trois onglets ». Droit implicite documenté, pas un masquage : il est servi
     * par `niveauSurModule()`, donc par le menu, `VerifierAccesModule`, la page et la connexion.
     * La matrice stockée n'est pas modifiée (l'écran Rôles & Permissions montre la ligne réelle).
     * La purge reste réservée au `super_admin` (`estSuperAdmin()`).
     *
     * @var list<string>
     */
    public const MODULES_IMPLICITES_SYSTEME = ['IMPORT_EXPORT'];

    /**
     * Les rôles qui passent les gestes comptables réservés (réouverture d'exercice, affectation du
     * résultat et sa contre-passation) : le comptable ET le gérant (11/11/2026, PO : « le gérant a
     * par défaut tous les écrans du comptable »). Un seul endroit ; le poste le miroite
     * (`rolesComptabiliteSensible`). L'administrateur n'y figure PAS : ce n'est pas un droit de plus.
     *
     * @var list<string>
     */
    public const ROLES_COMPTABILITE_SENSIBLE = ['comptable', 'gerant'];

    /**
     * Un compte suspendu ou désactivé n'accède à rien, quel que soit son rôle.
     */
    public function estActif(): bool
    {
        return $this->statut === 'actif';
    }

    /**
     * Le mot de passe TEMPORAIRE posé par un administrateur est-il expiré ?
     *
     * Vrai seulement si un changement est exigé ET que l'échéance est passée :
     * un compte ordinaire (aucun temporaire) n'expire jamais.
     */
    public function motDePasseTemporaireExpire(): bool
    {
        return $this->must_change_password
            && $this->temp_expires_at !== null
            && $this->temp_expires_at->isPast();
    }

    /**
     * Le SUPER_ADMIN — directive PO du 03/09/2026. Seul role autorise a
     * PURGER les archives (suppression physique d'un element deja archive) ;
     * partout ailleurs il agit par ses droits `C`, comme les autres. Les
     * tables financieres restent hors d'atteinte meme pour lui (RG-03/RG-11).
     */
    public function estSuperAdmin(): bool
    {
        return $this->role?->libelle === 'super_admin';
    }

    /**
     * L'un des deux rôles d'administration — voir `ROLES_ADMINISTRATION`.
     *
     * Distinct d'`estSuperAdmin()`, qui ne nomme QU'UN rôle et ne sert qu'à la
     * purge des archives. Les confondre donnerait au super_admin seul des
     * gestes que la directive accorde aussi à l'administrateur.
     */
    public function estAdministrateur(): bool
    {
        return in_array((string) $this->role?->libelle, self::ROLES_ADMINISTRATION, true);
    }

    /** Rôle « système » d'Import & Export — voir `ROLES_SYSTEME_IMPORT_EXPORT`. */
    public function estRoleSystemeImportExport(): bool
    {
        return in_array((string) $this->role?->libelle, self::ROLES_SYSTEME_IMPORT_EXPORT, true);
    }

    /** Le comptable OU le gérant — voir `ROLES_COMPTABILITE_SENSIBLE`. */
    public function estComptableOuGerant(): bool
    {
        return in_array((string) $this->role?->libelle, self::ROLES_COMPTABILITE_SENSIBLE, true);
    }

    /**
     * Le module dont l'écriture (`C`) est exigée EN PLUS du rôle pour supprimer
     * un compte : celui de l'écran « Comptes utilisateurs » (menu `ROLES`).
     */
    public const MODULE_SUPPRESSION_COMPTES = 'ROLES';

    /**
     * QUI peut supprimer un compte (décision du PO du 03/11/2026) : un SUPER
     * ADMINISTRATEUR actif, avec l'écriture sur ROLES. Auteur unique de la règle :
     * l'écran, le service et la synchronisation la demandent ici, aucun ne la
     * recopie. Un simple administrateur désactive, il ne supprime pas.
     */
    public function peutSupprimerDesComptes(): bool
    {
        return $this->estActif()
            && $this->estSuperAdmin()
            && $this->niveauSurModule(self::MODULE_SUPPRESSION_COMPTES) === 'C';
    }

    /**
     * QUI peut être supprimé : un compte dont le rôle n'administre PAS. Un
     * administrateur ou un super administrateur se désactive, il ne se supprime
     * pas — ce qui garantit aussi qu'on ne supprime jamais le dernier
     * administrateur (ce n'est jamais un administrateur qui part).
     */
    public function estSupprimable(): bool
    {
        return $this->supprime_le === null && ! $this->estAdministrateur();
    }

    /** Le compte a-t-il été supprimé (suppression logique) ? */
    public function estSupprime(): bool
    {
        return $this->supprime_le !== null;
    }

    /**
     * Le nom d'un auteur tel que les listes l'affichent : son login, suivi de
     * « (compte supprimé) » quand le compte l'est. Ce qu'il a saisi garde son nom.
     */
    public function libelleAuteur(): string
    {
        return $this->estSupprime()
            ? __('pwa.comptes.auteur_supprime', ['login' => $this->login])
            : $this->login;
    }
}
