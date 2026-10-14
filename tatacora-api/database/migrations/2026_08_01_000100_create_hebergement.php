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
        Schema::create('categories_hebergement', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('libelle'); // Bungalow, Chambre, Tente
            $table->unsignedSmallInteger('capacite_max');
            $table->decimal('tarif_base', 15, 2);
            $table->timestamps();
        });

        Schema::create('unites_hebergement', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('categorie_id')->constrained('categories_hebergement')->restrictOnDelete();
            $table->string('numero');
            $table->enum('statut', ['libre', 'occupee', 'reservee', 'nettoyage', 'hors_service'])
                ->default('libre'); // état opérationnel UNIQUEMENT — jamais source de la disponibilité (RG-02)
            $table->timestamps();
        });

        Schema::create('reservations', function (Blueprint $table) {
            $table->uuid('id')->primary(); // UUID généré côté client Flutter (offline-first)
            $table->foreignUuid('client_id')->constrained('clients')->restrictOnDelete();
            $table->foreignUuid('unite_id')->constrained('unites_hebergement')->restrictOnDelete();
            $table->date('date_arrivee');
            $table->date('date_depart');
            $table->enum('statut', ['en_attente', 'confirmee', 'en_cours', 'terminee', 'annulee'])
                ->default('en_attente');
            $table->decimal('acompte', 15, 2)->default(0); // EF-M1-06
            $this->auditColumns($table);
            $table->timestamps();

            // Index de performance pour VerificationChevauchementService
            // (03_DATABASE_ENGINEERING.md §3) - accelere la requete de
            // chevauchement, ne remplace pas la garantie d'integrite elle-meme.
            $table->index(['unite_id', 'date_arrivee', 'date_depart']);
        });

        // Blueprint::check() n'existe pas nativement en Laravel - portable
        // MySQL/MariaDB/PostgreSQL (MySQL 8.0.16+/MariaDB 10.2.1+ le supportent).
        \Illuminate\Support\Facades\DB::statement('ALTER TABLE reservations ADD CONSTRAINT chk_reservations_dates CHECK (date_depart > date_arrivee)');

        // RG-01 - le non-chevauchement d'une meme unite est garanti par
        // VerificationChevauchementService (verrou pessimiste applicatif),
        // PAS par une contrainte SQL - EXCLUDE USING gist (PostgreSQL) n'a
        // aucun equivalent MySQL. Voir 03_DATABASE_ENGINEERING.md §3.

        Schema::create('sejours', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('reservation_id')->constrained('reservations')->restrictOnDelete();
            $table->timestamp('date_checkin_reel')->nullable();
            $table->timestamp('date_checkout_reel')->nullable();
            $table->json('occupants')->nullable(); // pièces d'identité des occupants, EF-M1-04
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('sejours');
        Schema::dropIfExists('reservations');
        Schema::dropIfExists('unites_hebergement');
        Schema::dropIfExists('categories_hebergement');
    }
};
