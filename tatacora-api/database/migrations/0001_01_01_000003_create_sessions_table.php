<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * La table `sessions` du framework — 06/09/2026, PA-183.
 *
 * ## Pourquoi elle manquait, et pourquoi le défaut n'était visible qu'en ligne
 *
 * Laravel crée d'ordinaire `sessions` dans sa migration
 * `create_users_table`, remplacée ici par `create_utilisateurs.php` : la
 * table est partie avec elle, sans que rien ne le signale.
 *
 * En développement, `SESSION_DRIVER=file` : les sessions vivent dans
 * `storage/framework/sessions`, aucune table n'est lue, et les 1 445 tests
 * passent. En production, `.env.production.example` pose
 * `SESSION_DRIVER=database` — le bon choix sur un hébergement mutualisé où
 * plusieurs processus PHP se partagent les requêtes, mais il exige une table
 * que personne ne créait. Résultat : la PREMIÈRE requête du premier visiteur
 * échoue, avant toute page, avant toute authentification. C'est le défaut de
 * la famille PA-59/60/61 vu de l'autre côté : ce n'est pas un indicateur qui
 * ment, c'est un chemin que rien n'empruntait jamais avant la mise en ligne.
 *
 * Le schéma est celui de Laravel 12, à l'identique — cette table appartient
 * au framework, pas au domaine : `user_id` y est un entier non signé dans le
 * squelette d'origine, mais les comptes de ce dépôt portent des UUID
 * (`utilisateurs.id` en CHAR(36)). La colonne est donc typée en conséquence,
 * sans clé étrangère : une session expirée ne doit jamais retenir la
 * suppression d'un compte, et le nettoyage des sessions est l'affaire du
 * ramasse-miettes de Laravel.
 */
return new class () extends Migration {
    public function up(): void
    {
        Schema::create('sessions', function (Blueprint $table) {
            $table->string('id')->primary();
            $table->char('user_id', 36)->nullable()->index();
            $table->string('ip_address', 45)->nullable();
            $table->text('user_agent')->nullable();
            $table->longText('payload');
            $table->integer('last_activity')->index();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('sessions');
    }
};
