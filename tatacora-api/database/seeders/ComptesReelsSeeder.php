<?php

declare(strict_types=1);

namespace Database\Seeders;

use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use RuntimeException;

/**
 * Les COMPTES RÉELS de l'exploitation — amorçage de Production (PA-167,
 * demande du Product Owner du 01/09/2026 : trois comptes actuels, les autres
 * seront ajoutés ensuite avec leurs rôles).
 *
 * ## AUCUN mot de passe n'entre jamais dans ce fichier
 *
 * La règle du dépôt est absolue : un mot de passe posé dans un seeder est
 * connu de quiconque lit le code, pour toujours (l'historique git ne
 * s'efface pas). Les mots de passe viennent de `.env` — jamais commité,
 * posé sur le serveur uniquement :
 *
 *     COMPTE_RODRIGUE_MOT_DE_PASSE=…
 *     COMPTE_BIENVENU_MOT_DE_PASSE=…
 *     COMPTE_NOEL_MOT_DE_PASSE=…
 *
 * Une variable absente ou vide REFUSE le seeder entier : trois comptes dont
 * un sans mot de passe seraient un amorçage à moitié fait qui se lirait
 * comme réussi (PA-59/60/61).
 *
 * ## Un mot de passe déjà posé n'est JAMAIS réécrit
 *
 * Le seeder est idempotent par `login`, et l'idempotence protège d'abord le
 * mot de passe : un compte existant n'est pas touché — relancer le seeder
 * après qu'un utilisateur a changé son mot de passe ne doit pas le
 * réinitialiser à la valeur du `.env`.
 *
 * ## Les comptes de démonstration se DÉSACTIVENT, jamais supprimés
 *
 * RG-15 : une vente doit continuer de porter le nom de qui l'a encaissée.
 * `desactiverComptesDemonstration()` passe les onze comptes de
 * `UtilisateurSeeder` à `desactive` (le registre du schéma : actif / suspendu / desactive) — un compte désactivé ne peut plus se
 * connecter, son historique reste.
 *
 * ## Hors de `DatabaseSeeder`, délibérément
 *
 * `DatabaseSeeder` est le jeu de démonstration (Dév/Recette uniquement).
 * Celui-ci se lance seul, sur le serveur :
 *
 *     php artisan db:seed --class=ComptesReelsSeeder
 *
 * @see docs/DEPLOIEMENT_LOGIRESTOCK.md la procédure complète
 */
class ComptesReelsSeeder extends Seeder
{
    /**
     * Rôles PAR DÉFAUT, surchargés par `COMPTE_<LOGIN>_ROLE` dans `.env` —
     * le Product Owner attribuera les rôles définitifs (sa demande du
     * 01/09/2026 le dit : « on peut ajouter les autres comptes après et
     * leur attribuer des rôles »).
     *
     * @var list<array{login: string, env: string, role_defaut: string}>
     */
    private const COMPTES = [
        ['login' => 'rodrigue', 'env' => 'COMPTE_RODRIGUE_MOT_DE_PASSE', 'role_defaut' => 'administrateur'],
        ['login' => 'bienvenu', 'env' => 'COMPTE_BIENVENU_MOT_DE_PASSE', 'role_defaut' => 'gerant'],
        // administrateur depuis le 01/09/2026 — décision explicite du PO.
        ['login' => 'noel', 'env' => 'COMPTE_NOEL_MOT_DE_PASSE', 'role_defaut' => 'administrateur'],
        // SUPER_ADMIN — directive PO du 03/09/2026 : le seul role qui purge
        // les archives (PA-177). Comme les trois autres, le mot de passe vit
        // dans le `.env` du poste, jamais ici.
        ['login' => 'super_admin', 'env' => 'COMPTE_SUPER_ADMIN_MOT_DE_PASSE', 'role_defaut' => 'super_admin'],
    ];

    public function run(): void
    {
        // 1. TOUT vérifier avant de RIEN écrire : un refus au deuxième compte
        //    laisserait un amorçage à moitié fait.
        $aCreer = [];

        foreach (self::COMPTES as $compte) {
            if (User::query()->where('login', $compte['login'])->exists()) {
                continue;
            }

            // Lu de `config/comptes_reels.php`, jamais `env()` directement :
            // avec `config:cache` (production cPanel), `env()` rend NUL hors
            // de `config/` et ce seeder aurait refuse un `.env` correct.
            $motDePasse = (string) config('comptes_reels.mots_de_passe.'.$compte['login'], '');

            if ($motDePasse === '') {
                throw new RuntimeException(
                    "ComptesReelsSeeder : la variable {$compte['env']} est absente du .env. "
                    .'Aucun mot de passe ne vit dans le code — posez la variable sur le '
                    .'serveur, puis relancez. Rien n\'a été écrit.',
                );
            }

            $role = (string) config('comptes_reels.roles.'.$compte['login'], '');
            if ($role === '') {
                $role = $compte['role_defaut'];
            }

            $roleModele = Role::where('libelle', $role)->first();

            if ($roleModele === null) {
                throw new RuntimeException(
                    "ComptesReelsSeeder : le rôle « {$role} » n'existe pas au référentiel. "
                    .'Rien n\'a été écrit.',
                );
            }

            $aCreer[] = [
                'login' => $compte['login'],
                'mot_de_passe' => $motDePasse,
                'role_id' => $roleModele->id,
            ];
        }

        // 2. Créer.
        foreach ($aCreer as $compte) {
            User::create([
                'id' => (string) Str::uuid(),
                'login' => $compte['login'],
                'mot_de_passe_hash' => Hash::make($compte['mot_de_passe']),
                'role_id' => $compte['role_id'],
                'statut' => 'actif',
            ]);
        }

        // 3. Les comptes de démonstration encore actifs se désactivent.
        $this->desactiverComptesDemonstration();
    }

    private function desactiverComptesDemonstration(): void
    {
        $loginsDemonstration = array_column(UtilisateurSeeder::COMPTES, 'login');

        User::query()
            ->whereIn('login', $loginsDemonstration)
            ->where('statut', 'actif')
            ->update(['statut' => 'desactive']);
    }
}
