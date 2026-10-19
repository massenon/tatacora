<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * `lignes_vente.prix_catalogue` — lot S3 de synchronisation, décision du
 * Product Owner du 15/10/2026.
 *
 * Une vente faite HORS CONNEXION porte le prix que le poste a annoncé au
 * client : il fait foi (`prix_unitaire`). Le prix du catalogue serveur au
 * moment de la synchronisation est conservé À CÔTÉ, sur la ligne même, pour
 * que l'écart reste lisible sur le document — sans jointure vers un
 * catalogue qui aura changé d'ici l'inventaire.
 *
 * NULL sur toute vente faite EN LIGNE : le prix y est figé depuis le
 * catalogue, il n'y a pas d'écart possible, et « aucun écart » ne doit pas
 * se lire comme « écart de zéro ».
 */
return new class () extends Migration {
    public function up(): void
    {
        Schema::table('lignes_vente', function (Blueprint $table) {
            $table->decimal('prix_catalogue', 15, 2)->nullable()->after('prix_unitaire');
        });
    }

    public function down(): void
    {
        Schema::table('lignes_vente', function (Blueprint $table) {
            $table->dropColumn('prix_catalogue');
        });
    }
};
