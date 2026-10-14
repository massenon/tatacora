<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Table des jetons Sanctum — support de l'authentification du client Flutter.
 *
 * ## Pourquoi elle n'existait pas
 *
 * Les 32 routes de `routes/api.php` sont derriere `auth:sanctum`, mais aucun
 * jeton n'etait jamais emis et cette table n'a jamais ete creee. Depuis
 * Sanctum 4, le paquet ne charge plus ses migrations depuis `vendor/` : elles
 * doivent etre publiees. L'API etait donc inaccessible a tout client.
 *
 * ## Pourquoi elle n'est pas la migration publiee telle quelle
 *
 * La migration livree par Sanctum declare `$table->morphs('tokenable')`, ce
 * qui produit un `tokenable_id` en `BIGINT UNSIGNED`. Or `utilisateurs.id`
 * est un `uuid` (CHAR(36)) : la publier sans modification aurait cree une
 * colonne incapable de porter la cle a laquelle elle se rapporte. D'ou
 * `uuidMorphs`.
 *
 * La cle primaire reste un auto-incrementement : elle n'est jamais emise par
 * un client hors connexion (un jeton s'obtient en ligne, par definition) et
 * Sanctum la manipule directement.
 *
 * @see 02_SOFTWARE_ARCHITECTURE.md §5 (authentification), RG-16
 */
return new class () extends Migration {
    public function up(): void
    {
        Schema::create('personal_access_tokens', function (Blueprint $table) {
            $table->id();
            $table->uuidMorphs('tokenable');
            // `name` porte le nom du poste : il sert a revoquer le jeton
            // anterieur du MEME poste sans deconnecter les autres.
            $table->string('name', 100);
            $table->string('token', 64)->unique();
            $table->text('abilities')->nullable();
            $table->timestamp('last_used_at')->nullable();
            $table->timestamp('expires_at')->nullable()->index();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('personal_access_tokens');
    }
};
