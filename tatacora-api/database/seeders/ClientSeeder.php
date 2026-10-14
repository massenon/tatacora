<?php

declare(strict_types=1);

namespace Database\Seeders;

use App\Domain\Crm\Models\Client;
use Illuminate\Database\Seeder;
use Illuminate\Support\Str;

/**
 * Clients de démonstration — SEEDER_TEST_LARAVEL.md §3 : les 6 clients du
 * prototype, mêmes noms, téléphones et types.
 *
 * ## Deux écarts à la spécification, mesurés le 28/08/2026
 *
 * 1. **`nom`/`prenom` sont deux colonnes**, la spécification n'en écrivait
 *    qu'une (« Jean KORA ») : le prénom est séparé pour les particuliers, les
 *    structures n'en ont pas.
 * 2. **La colonne `solde` n'est PAS semée** (la spécification posait
 *    150 000 F sur l'agence et 12 000 F sur Fatima YARO). PA-126 a établi que
 *    cette colonne est MORTE — rien ne l'écrit, et le solde affiché se
 *    CALCULE des lignes (restes à payer + consommations). Un solde semé ici
 *    serait un chiffre que les écrans contrediraient : la dette de
 *    démonstration naîtra de vraies réservations avec acompte partiel, jamais
 *    d'une colonne posée à la main.
 *
 * Sans clients, aucune réservation n'est possible : `reservations.client_id`
 * est une vraie clé étrangère (PA-116), jamais un texte libre.
 *
 * Dév/Recette UNIQUEMENT. Idempotent.
 */
class ClientSeeder extends Seeder
{
    public function run(): void
    {
        if (Client::query()->exists()) {
            return;
        }

        $clients = [
            ['nom' => 'KORA', 'prenom' => 'Jean', 'telephone' => '01 97 35 59 74', 'email' => 'jean.kora@mail.com', 'type_client' => 'particulier'],
            ['nom' => 'Agence Bénin Tour', 'prenom' => null, 'telephone' => '01 21 45 67 89', 'email' => 'contact@benintour.bj', 'type_client' => 'agence'],
            ['nom' => 'MENSAH', 'prenom' => 'Adjoa', 'telephone' => '01 33 22 11 00', 'email' => 'adjoa.m@mail.com', 'type_client' => 'particulier'],
            ['nom' => 'Groupe scolaire ESCO', 'prenom' => null, 'telephone' => '01 40 55 66 77', 'email' => 'direction@esco.edu', 'type_client' => 'groupe'],
            ['nom' => 'AMEGAN', 'prenom' => 'Kokou', 'telephone' => '01 55 44 33 22', 'email' => 'k.amegan@mail.com', 'type_client' => 'particulier'],
            ['nom' => 'YARO', 'prenom' => 'Fatima', 'telephone' => '01 66 77 88 99', 'email' => 'fatima.yaro@mail.com', 'type_client' => 'particulier'],
        ];

        foreach ($clients as $c) {
            Client::create(array_merge(['id' => (string) Str::uuid()], $c));
        }
    }
}
