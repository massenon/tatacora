<?php

declare(strict_types=1);

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

/**
 * L'UNIQUE auteur du référentiel des canaux de réservation — PA-163.
 *
 * Les sept canaux sont ceux du maître (`canaux-engine.js`,
 * `CANAUX_INITIAUX`), libellés EXACTS — la règle PA-160/161 : un référentiel
 * a un seul auteur, et une sélection par motif approximatif est le piège qui
 * a fait vendre la mauvaise contenance de Béninoise. « Physique » ouvre la
 * liste : c'est le canal de qui se présente au comptoir, et le maître écrit
 * qu'il ne disparaîtra jamais.
 *
 * Idempotent par le NOM (unique au schéma) : relancer ne double rien, et un
 * canal désactivé par un Administrateur n'est PAS réactivé — `actif` n'est
 * écrit qu'à la création.
 */
class CanauxReservationSeeder extends Seeder
{
    /**
     * @var list<string>
     */
    public const CANAUX_INITIAUX = [
        'Physique',
        'Téléphone',
        'WhatsApp',
        'Booking.com',
        'Site web',
        'Facebook',
        'Agence partenaire',
    ];

    public function run(): void
    {
        if (! Schema::hasTable('canaux_reservation')) {
            return;
        }

        foreach (self::CANAUX_INITIAUX as $nom) {
            if (DB::table('canaux_reservation')->where('nom', $nom)->exists()) {
                continue;
            }

            DB::table('canaux_reservation')->insert([
                'id' => (string) Str::uuid(),
                'nom' => $nom,
                'actif' => true,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }
    }
}
