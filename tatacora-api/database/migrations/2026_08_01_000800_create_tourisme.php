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
        Schema::create('circuits', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('nom');
            $table->enum('theme', ['aventure', 'culture', 'faune', 'nature']);
            $table->string('zone'); // Nord Bénin, Sud Bénin, Togo, Tout le Bénin
            $table->string('duree'); // ex. "3 jours / 2 nuits" — texte libre, cf. prototype déjà validé
            $table->decimal('prix', 15, 2);
            $table->unsignedSmallInteger('capacite_max');
            $table->timestamps();
        });

        Schema::create('guides', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('nom');
            $table->string('certification')->nullable();
            $table->string('zone_competence')->nullable(); // Sud Bénin / Nord Bénin
            $table->decimal('tarif_jour', 15, 2);
            $table->timestamps();
        });

        Schema::create('reservations_tour', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('circuit_id')->constrained('circuits')->restrictOnDelete();
            $table->foreignUuid('client_id')->constrained('clients')->restrictOnDelete();
            $table->foreignUuid('guide_id')->constrained('guides')->restrictOnDelete();
            $table->date('date_circuit');
            $table->unsignedSmallInteger('nb_participants');
            $table->enum('statut', ['reservee', 'en_cours', 'terminee', 'annulee'])->default('reservee');
            $this->auditColumns($table);
            $table->timestamps();
        });

        \Illuminate\Support\Facades\DB::statement('ALTER TABLE reservations_tour ADD CONSTRAINT chk_reservations_tour_participants CHECK (nb_participants > 0)');

        // Migration différée : contrats_location.guide_id (M8, §13) — dépendance
        // sur `guides` créée seulement ici, EF-M8-04 (package véhicule + guide).
        Schema::table('contrats_location', function (Blueprint $table) {
            $table->foreignUuid('guide_id')->nullable()->after('client_id')
                ->constrained('guides')->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('contrats_location', function (Blueprint $table) {
            $table->dropConstrainedForeignId('guide_id');
        });
        Schema::dropIfExists('reservations_tour');
        Schema::dropIfExists('guides');
        Schema::dropIfExists('circuits');
    }
};
