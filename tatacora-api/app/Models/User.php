<?php

declare(strict_types=1);

namespace App\Models;

use App\Domain\Rh\Models\Employe;
use App\Shared\Rbac\Models\Role;
use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
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
 * @property-read Role|null $role
 */
class User extends Authenticatable
{
    use HasApiTokens;

    /** @use HasFactory<UserFactory> */
    use HasFactory;

    use HasUuids;
    use Notifiable;

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
        return $this->role?->niveauSurModule($module) ?? '-';
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
}
