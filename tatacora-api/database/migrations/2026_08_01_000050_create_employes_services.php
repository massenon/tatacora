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
        // Namespacé App\Domain\Rh\Models\Service en PHP — collision de nom documentée
        // dans ARBORESCENCE_COMPLETE_PROJET.md.
        Schema::create('services', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('libelle');
            $table->timestamps();
        });

        Schema::create('employes', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('nom');
            $table->string('prenom');
            $table->string('poste');
            $table->foreignUuid('service_id')->constrained('services')->restrictOnDelete();
            $table->date('date_embauche');
            $table->decimal('salaire_base', 15, 2);
            $table->enum('statut', ['actif', 'conge', 'suspendu', 'parti'])->default('actif');
            $this->auditColumns($table);
            $table->timestamps();
        });

        // Complète utilisateurs.employe_id (nullable — un utilisateur système n'est
        // pas nécessairement un employé salarié, cf. 03_DATABASE_ENGINEERING.md §2).
        Schema::table('utilisateurs', function (Blueprint $table) {
            $table->foreignUuid('employe_id')->nullable()->after('role_id')
                ->constrained('employes')->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('utilisateurs', function (Blueprint $table) {
            $table->dropConstrainedForeignId('employe_id');
        });
        Schema::dropIfExists('employes');
        Schema::dropIfExists('services');
    }
};
