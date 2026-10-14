<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class () extends Migration {
    public function up(): void
    {
        // RG-15 — alimentée exclusivement par le Trait Auditable (Shared/Audit),
        // jamais par une écriture manuelle depuis un contrôleur.
        Schema::create('journal_audit', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('utilisateur_id')->nullable()->constrained('utilisateurs')->nullOnDelete();
            $table->string('action'); // Création, Modification, Suppression, Validation...
            $table->string('entite_concernee'); // nom de la table/du modèle
            $table->uuid('entite_id');
            $table->json('valeur_avant')->nullable();
            $table->json('valeur_apres')->nullable();
            $table->timestamp('date_heure')->useCurrent();
            $table->string('adresse_poste')->nullable(); // IP ou identifiant du poste Desktop/Mobile

            $table->index(['entite_concernee', 'entite_id']); // recherche d'historique par entité
            $table->index('date_heure'); // purge/rétention par ancienneté
        });

        // RG-17 — traçabilité de la synchronisation offline/online (LARAVEL_SYNC_FLUTTER.md)
        Schema::create('sessions_synchronisation', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('poste_id'); // identifiant de l'installation Flutter (mobile/desktop)
            $table->timestamp('date_sync');
            $table->unsignedInteger('nb_enregistrements')->default(0);
            $table->unsignedInteger('conflits_detectes')->default(0);
            $table->enum('statut', ['succes', 'partiel', 'echec'])->default('succes');
            $table->timestamps();
        });

        // File d'arbitrage manuel des conflits financiers — RG-17, jamais de
        // résolution automatique sur factures/paiements/mouvements_caisse/mouvements_stock.
        Schema::create('conflits_synchronisation', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('session_id')->constrained('sessions_synchronisation')->restrictOnDelete();
            $table->string('table_concernee');
            $table->uuid('entite_id');
            $table->json('version_locale');
            $table->json('version_serveur');
            $table->enum('statut', ['en_attente_arbitrage', 'resolu_local', 'resolu_serveur', 'resolu_fusion'])
                ->default('en_attente_arbitrage');
            $table->foreignUuid('arbitre_par_id')->nullable()->constrained('utilisateurs')->nullOnDelete();
            $table->timestamp('date_arbitrage')->nullable();
            $table->timestamps();
        });

        // Ajoutée en correctif — SECURITY_STRICT.md §10. Distincte de journal_audit :
        // trace les tentatives d'INTRUSION (connexions échouées, RBAC refusé, accès
        // URL direct bloqué), jamais les actions métier légitimes.
        Schema::create('journal_securite', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->enum('type_evenement', ['connexion_echouee', 'acces_refuse_rbac', 'tentative_url_directe']);
            $table->string('login_tente')->nullable();
            $table->foreignUuid('utilisateur_id')->nullable()->constrained('utilisateurs')->nullOnDelete();
            $table->string('adresse_ip')->nullable();
            $table->string('module_concerne')->nullable();
            $table->timestamp('date_heure')->useCurrent();

            $table->index(['type_evenement', 'date_heure']); // requête d'alerte force brute (SECURITY_STRICT.md §10)
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('journal_securite');
        Schema::dropIfExists('conflits_synchronisation');
        Schema::dropIfExists('sessions_synchronisation');
        Schema::dropIfExists('journal_audit');
    }
};
