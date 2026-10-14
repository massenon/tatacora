<?php

declare(strict_types=1);

namespace Database\Seeders;

use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Sessions de caisse OUVERTES — le préalable de tout POS.
 *
 * ## Le fait que ce seeder contourne, et qu'il ne corrige pas
 *
 * « Rien n'ouvre de session de caisse : ni modèle, ni service, ni route »
 * (plan CRUD, fait c) — `VenteBarService::enregistrer()` exige pourtant un
 * `sessionCaisseId`. Sans ce seeder, AUCUNE vente n'est possible nulle part :
 * les écrans POS sont « impossibles », pas « à faire ». Ce seeder ouvre trois
 * sessions pour que la démonstration vende ; le modèle `SessionCaisse`, le
 * service d'ouverture/clôture (PA-21) et l'écran restent À FAIRE — c'est
 * pourquoi l'écriture passe par `DB::table`, il n'existe aucun modèle à
 * appeler.
 *
 * ## Les points de vente sont ceux du SCHÉMA, pas ceux de la salle
 *
 * L'enum `sessions_caisse.point_vente` connaît TROIS valeurs : `reception`,
 * `restaurant`, `bar`. « Plage » et « Jardin » (demandés le 28/08/2026) sont
 * des ZONES DE TABLES de salle au maître (`tables-engine.js`) — le schéma
 * serveur n'a aucune table de salle (elle est locale au client Flutter,
 * schéma v6). Une session « plage » est donc IMPOSSIBLE ici sans décision de
 * schéma : signalé au rapport, pas contourné par une valeur d'enum inventée.
 *
 * Chaque session porte son ouvreur réel (RG-15) : la réception, le gérant au
 * restaurant, le barman au bar. Fonds de caisse : valeurs de démarrage.
 *
 * Dév/Recette UNIQUEMENT. Idempotent. Dépend d'`UtilisateurSeeder`.
 */
class SessionCaisseSeeder extends Seeder
{
    public function run(): void
    {
        if (DB::table('sessions_caisse')->exists()) {
            return;
        }

        $sessions = [
            ['point_vente' => 'reception', 'login' => 'reception', 'montant_fond' => 20000],
            ['point_vente' => 'restaurant', 'login' => 'n.nabogou', 'montant_fond' => 10000],
            ['point_vente' => 'bar', 'login' => 'barman', 'montant_fond' => 10000],
        ];

        foreach ($sessions as $s) {
            DB::table('sessions_caisse')->insert([
                'id' => (string) Str::uuid(),
                'point_vente' => $s['point_vente'],
                'utilisateur_ouverture_id' => User::query()->where('login', $s['login'])->firstOrFail()->id,
                'date_ouverture' => now()->startOfDay()->addHours(7),
                'montant_fond' => $s['montant_fond'],
                // Ouvertes : `date_cloture` NULL — la clôture est un geste
                // métier (PA-21), pas une donnée d'amorçage.
                'date_cloture' => null,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }
    }
}
