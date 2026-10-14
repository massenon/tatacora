<?php

declare(strict_types=1);

namespace Database\Seeders;

use App\Domain\Ventes\Models\TableSalle;
use App\Domain\Ventes\Services\TableSalleService;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Schema;

/**
 * L'UNIQUE auteur du référentiel des tables de salle — le jeu initial du
 * maître (`tables-engine.js`, `jeuInitial()`) : treize tables, six au
 * restaurant, quatre au jardin, trois à la plage, quatre places chacune.
 *
 * ## Le jeu vit dans le SERVICE, pas ici
 *
 * `TableSalleService::JEU_INITIAL` est la seule liste : « Rétablir le jeu
 * initial » (écran Paramètres) et ce seeder passent tous deux par
 * `retablirJeuInitial()` — deux listes auraient fini par diverger, et le
 * bouton de l'écran aurait rétabli un jeu différent de celui du premier
 * démarrage (PA-160/PA-161 : un référentiel a UN SEUL AUTEUR, et un doublon
 * décroché est à un `db:seed --class=` du défaut).
 *
 * Idempotent : `retablirJeuInitial()` crée ce qui manque et ne double rien.
 * ⚠ Sur une base DÉJÀ exploitée il réactive les treize tables d'origine et
 * désactive les autres — c'est le contrat du bouton, et la raison pour
 * laquelle ce seeder ne tourne qu'au premier semis : il se retire si une
 * table existe déjà.
 */
class TablesSalleSeeder extends Seeder
{
    public function run(): void
    {
        if (! Schema::hasTable('tables_salle')) {
            return;
        }

        // Une base déjà dotée de tables a pu être remaniée depuis Paramètres :
        // re-semer écraserait la configuration de l'exploitant — le bouton
        // « Rétablir le jeu initial » existe pour que ce geste reste un CHOIX.
        if (TableSalle::query()->exists()) {
            return;
        }

        app(TableSalleService::class)->retablirJeuInitial();
    }
}
