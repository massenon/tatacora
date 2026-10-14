<?php

declare(strict_types=1);

namespace Database\Seeders\Concerns;

use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

/**
 * Le compte technique d'amorçage — parce que `mouvements_stock.utilisateur_id`
 * est NOT NULL, et que c'est une bonne nouvelle.
 *
 * ## Le problème, et pourquoi il ne se contourne pas
 *
 * RG-15 impose qu'un mouvement de stock porte son auteur : la colonne est une
 * vraie clé étrangère non nulle vers `utilisateurs`. Un seeder qui pose un
 * stock initial doit donc nommer QUI l'a posé — la spécification
 * (`SEEDER_TEST_LARAVEL.md` §5) a vieilli sur ce point, son code ne
 * renseignait pas la colonne et échouerait aujourd'hui.
 *
 * ## Ce que ce compte N'EST PAS : un mot de passe par défaut
 *
 * La règle du dépôt est absolue : « un mot de passe posé par un seeder serait
 * connu de quiconque lit le code, et personne ne le changerait ». Ce compte
 * la respecte doublement :
 *
 * 1. son mot de passe est un aléa de 64 caractères généré À L'EXÉCUTION,
 *    haché puis oublié — personne, y compris l'auteur du seeder, ne peut le
 *    connaître ;
 * 2. son statut est `desactive` : même si le hachage fuyait, la connexion
 *    est refusée avant toute vérification de mot de passe (RG-15 — un compte
 *    désactivé reste en base pour que ses écritures gardent leur auteur,
 *    mais n'ouvre pour personne).
 *
 * Le rôle attribué est `magasinier` (le moins doté qui ait un sens pour un
 * stock initial) — sans effet réel, le statut fermant tout, mais un rôle
 * `administrateur` sur un compte technique serait une invitation à le
 * « réactiver pour dépanner ».
 */
trait CompteAmorcage
{
    protected function compteAmorcageId(): string
    {
        $existant = User::query()->where('login', 'amorcage.systeme')->first();
        if ($existant !== null) {
            return $existant->id;
        }

        return User::create([
            'login' => 'amorcage.systeme',
            'mot_de_passe_hash' => Hash::make(Str::random(64)),
            'role_id' => Role::where('libelle', 'magasinier')->firstOrFail()->id,
            'statut' => 'desactive',
        ])->id;
    }
}
