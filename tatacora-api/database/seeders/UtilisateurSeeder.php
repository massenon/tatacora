<?php

declare(strict_types=1);

namespace Database\Seeders;

use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\App;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use RuntimeException;

/**
 * Les 11 comptes de démonstration — SEEDER_TEST_LARAVEL.md §2, un par rôle.
 *
 * ## ⚠ MOTS DE PASSE CONNUS (`demo-<login>`) — DÉV/RECETTE UNIQUEMENT
 *
 * La règle du dépôt est qu'un mot de passe posé par un seeder est connu de
 * quiconque lit le code. Elle est vraie, et c'est POURQUOI ce seeder :
 *
 * 1. **REFUSE de s'exécuter hors `local`/`development`/`testing`** — il lève,
 *    il ne saute pas : un `db:seed` lancé par erreur en Production doit
 *    échouer bruyamment, pas planter onze portes d'entrée en silence ;
 * 2. n'est exécutable que par `DatabaseSeeder`, lui-même exclu du pipeline de
 *    Production (`CPANEL_DEPLOYMENT.md` §4).
 *
 * Demandé nommément par le Product Owner (28/08/2026) pour la recette de la
 * PWA : sans comptes, personne ne peut ouvrir l'écran de connexion.
 * `01_BUSINESS_ANALYSIS_SPEC.md` §3 porte les identités.
 */
class UtilisateurSeeder extends Seeder
{
    /** @var list<array{login: string, role: string}> */
    // `public` depuis PA-167 : `ComptesReelsSeeder` lit cette liste pour
    // DESACTIVER les comptes de demonstration en Production — une seconde
    // liste recopiee aurait diverge au premier compte ajoute ici.
    public const COMPTES = [
        ['login' => 'admin', 'role' => 'administrateur'],
        ['login' => 'n.nabogou', 'role' => 'gerant'],
        ['login' => 'reception', 'role' => 'receptionniste'],
        ['login' => 'cuisine', 'role' => 'cuisine'],
        ['login' => 'barman', 'role' => 'barman'],
        ['login' => 'magasin', 'role' => 'magasinier'],
        ['login' => 'achats', 'role' => 'achats'],
        ['login' => 'garage', 'role' => 'vehicules'],
        ['login' => 'guide', 'role' => 'guide'],
        ['login' => 'rh', 'role' => 'rh'],
        ['login' => 'comptable', 'role' => 'comptable'],
    ];

    public function run(): void
    {
        if (! App::environment(['local', 'development', 'testing'])) {
            // Message développeur/exploitant, jamais affiché à un utilisateur.
            throw new RuntimeException(
                'UtilisateurSeeder pose des mots de passe de demonstration : '
                .'il refuse de tourner hors local/development/testing.',
            );
        }

        foreach (self::COMPTES as $c) {
            if (User::query()->where('login', $c['login'])->exists()) {
                continue;
            }

            User::create([
                'id' => (string) Str::uuid(),
                'login' => $c['login'],
                'mot_de_passe_hash' => Hash::make('demo-'.$c['login']),
                'role_id' => Role::where('libelle', $c['role'])->firstOrFail()->id,
                'statut' => 'actif',
            ]);
        }
    }
}
