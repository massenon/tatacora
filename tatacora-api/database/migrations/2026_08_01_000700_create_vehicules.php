<?php

declare(strict_types=1);

use Database\Migrations\Concerns\HasAuditColumns;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\{Schema};

return new class () extends Migration {
    use HasAuditColumns;

    public function up(): void
    {
        Schema::create('vehicules', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->enum('categorie', ['voiture', '4x4', 'pickup', 'moto', 'scooter', 'velo', 'bus']);
            $table->string('immatriculation')->unique();
            $table->unsignedSmallInteger('annee');
            $table->string('transmission')->nullable();
            $table->unsignedSmallInteger('capacite')->nullable();
            $table->decimal('tarif_jour', 15, 2);
            $table->enum('statut', ['disponible', 'loue', 'entretien', 'hors_service'])->default('disponible');
            $table->timestamps();
        });

        // guides créée en §14 (Tourisme) mais référencée ici — migration différée
        // de contrat_location.guide_id ajoutée à la fin de create_tourisme.php (§14)
        // pour respecter l'ordre de dépendance sans dupliquer la déclaration de table.

        Schema::create('contrats_location', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('vehicule_id')->constrained('vehicules')->restrictOnDelete();
            $table->foreignUuid('client_id')->constrained('clients')->restrictOnDelete();
            $table->date('date_debut');
            $table->date('date_fin');
            // guide_id ajouté par migration différée (§14) — nullable, package optionnel EF-M8-04
            $table->string('piece_identite')->nullable(); // requis si categorie != moto — RG-09, validé en FormRequest
            $table->string('permis_conduire')->nullable();
            $this->auditColumns($table);
            $table->timestamps();

            // Index de performance pour VerificationChevauchementService,
            // meme principe que reservations (03_DATABASE_ENGINEERING.md §3).
            $table->index(['vehicule_id', 'date_debut', 'date_fin']);
        });

        \Illuminate\Support\Facades\DB::statement('ALTER TABLE contrats_location ADD CONSTRAINT chk_contrats_location_dates CHECK (date_fin > date_debut)');

        // RG-08 - MySQL, revise 15/08/2026 : meme principe que RG-01 sur
        // reservations (Partie 1 §7) - EXCLUDE USING gist remplacee par
        // VerificationChevauchementService (verrou pessimiste applicatif),
        // absence d'equivalent MySQL natif. Voir 03_DATABASE_ENGINEERING.md §7.

        Schema::create('entretiens_vehicule', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('vehicule_id')->constrained('vehicules')->restrictOnDelete();
            $table->enum('type', ['entretien', 'carburation']);
            $table->date('date');
            $table->decimal('cout', 15, 2);
            $table->foreignUuid('chauffeur_id')->nullable()->constrained('employes')->nullOnDelete();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('entretiens_vehicule');
        Schema::dropIfExists('contrats_location');
        Schema::dropIfExists('vehicules');
    }
};
