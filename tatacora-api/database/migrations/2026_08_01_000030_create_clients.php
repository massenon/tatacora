<?php

declare(strict_types=1);

use Database\Migrations\Concerns\HasAuditColumns;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class () extends Migration {
    use HasAuditColumns;

    public function up(): void
    {
        // RG-18 : fiche client UNIQUE, partagée par tous les modules — jamais dupliquée.
        Schema::create('clients', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('nom');
            $table->string('prenom')->nullable();
            $table->string('telephone');
            $table->string('email')->nullable();
            $table->string('piece_identite')->nullable(); // chemin fichier scanné
            $table->enum('type_client', ['particulier', 'groupe', 'agence', 'structure']);
            $table->decimal('solde', 15, 2)->default(0); // suivi soldes/avances, EF-M3-04
            $this->auditColumns($table);
            $table->timestamps();

            $table->index(['nom', 'telephone']); // support détection de doublon RG-18
        });

        // MySQL, révisé 15/08/2026 — pg_trgm (similarité trigram, tolère les
        // fautes de frappe) n'existe pas en MySQL. Remplacé par un index
        // FULLTEXT natif : capacité différente, pas une simple substitution
        // de syntaxe — FULLTEXT fait une recherche par mots entiers (avec un
        // seuil de longueur minimale, InnoDB : 3 caractères par défaut), PAS
        // une tolérance aux fautes de frappe caractère par caractère comme
        // pg_trgm. MOTEUR_DE_RECHERCHE_GLOBALE_TOPBAR.md doit être revu
        // séparément pour refléter ce changement de comportement, pas
        // seulement de syntaxe (nouveau point d'action, non encore traité).
        \Illuminate\Support\Facades\DB::statement(
            'ALTER TABLE clients ADD FULLTEXT clients_nom_fulltext (nom)',
        );
    }

    public function down(): void
    {
        Schema::dropIfExists('clients');
    }
};
