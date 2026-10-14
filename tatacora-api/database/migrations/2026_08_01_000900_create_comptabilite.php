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
        // Ajoutée en correctif — 03_DATABASE_ENGINEERING.md §11. Créée en premier :
        // ecritures_comptables la référence (exercice_id NOT NULL).
        Schema::create('exercices_comptables', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->unsignedSmallInteger('annee')->unique(); // ex. 2026
            $table->date('date_debut');
            $table->date('date_fin');
            $table->enum('statut', ['ouvert', 'en_cloture', 'cloture'])->default('ouvert');
            $table->timestamp('date_cloture')->nullable();
            // Note libre — MODULE_COMPTABILITE_COMPLET_PART4.md §1.2, saisie par le
            // Comptable, aucune donnée calculable automatiquement par nature.
            $table->text('evenements_posterieurs')->nullable();
            $table->foreignUuid('utilisateur_cloture_id')->nullable()
                ->constrained('utilisateurs')->nullOnDelete();
            $table->timestamps();
        });

        \Illuminate\Support\Facades\DB::statement('ALTER TABLE exercices_comptables ADD CONSTRAINT chk_exercices_comptables_dates CHECK (date_fin > date_debut)');

        // centres_cout créée AVANT plan_comptable (inversion par rapport à l'ordre
        // de lecture de 03_DATABASE_ENGINEERING.md §11) — nécessaire pour que
        // plan_comptable.centre_cout_defaut_id puisse la référencer dès sa création.
        Schema::create('centres_cout', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('libelle'); // Hébergement, Restaurant, Bar, Tourisme, Véhicules, RH, Structure
            $table->string('type')->nullable();
            $table->timestamps();
        });

        // Table singulière par nature (référentiel unique) — cf. 03_DATABASE_ENGINEERING.md §11
        Schema::create('plan_comptable', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('numero_compte')->unique();
            $table->string('libelle');
            $table->string('classe'); // classe SYSCOHADA (1 à 9)
            $table->string('nature')->nullable(); // actif/passif/charge/produit
            // Suggestion de saisie UNIQUEMENT — jamais contraignant. L'écriture réelle
            // porte toujours son propre centre_id (NOT NULL, RG-12) ; cette colonne ne
            // fait que pré-remplir ce choix. Voir ATELIER_PLAN_COMPTABLE.md pour le
            // mapping compte → centre de coût suggéré, propre à TATACORA.
            $table->foreignUuid('centre_cout_defaut_id')->nullable()
                ->constrained('centres_cout')->nullOnDelete();
            $table->timestamps();
        });

        Schema::create('journaux_comptables', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('code')->unique(); // VTE, ACH, BQ, CAI, OD
            $table->string('libelle');
            $table->timestamps();
        });

        Schema::create('ecritures_comptables', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('exercice_id')->constrained('exercices_comptables')->restrictOnDelete();
            $table->foreignUuid('journal_id')->constrained('journaux_comptables')->restrictOnDelete();
            $table->foreignUuid('compte_id')->constrained('plan_comptable')->restrictOnDelete();
            $table->foreignUuid('centre_id')->constrained('centres_cout')->restrictOnDelete(); // NOT NULL — RG-12
            $table->date('date_ecriture');
            $table->string('libelle');
            $table->decimal('debit', 15, 2)->default(0);
            $table->decimal('credit', 15, 2)->default(0);
            $table->enum('statut', ['brouillon', 'validee'])->default('brouillon');
            // Auto-référence — contre-passation (RG-11), jamais un UPDATE de l'écriture originale
            $table->foreignUuid('ecriture_contrepassee_id')->nullable()
                ->constrained('ecritures_comptables')->nullOnDelete();
            $this->auditColumns($table);
            $table->timestamps();
        });

        \Illuminate\Support\Facades\DB::statement('ALTER TABLE ecritures_comptables ADD CONSTRAINT chk_ecritures_montants_positifs CHECK (debit >= 0 AND credit >= 0)');
        \Illuminate\Support\Facades\DB::statement('ALTER TABLE ecritures_comptables ADD CONSTRAINT chk_ecritures_debit_ou_credit CHECK (NOT (debit > 0 AND credit > 0))'); // une écriture est débit OU crédit, jamais les deux

        Schema::create('budgets', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('centre_id')->constrained('centres_cout')->restrictOnDelete();
            $table->string('periode'); // format 'YYYY-MM' ou 'YYYY' selon granularité
            $table->decimal('montant_prevu', 15, 2);
            // montant_realise NON stocké — calculé à la demande par agrégation de
            // ecritures_comptables sur le centre_id/periode (même principe que le
            // stock théorique, 03_DATABASE_ENGINEERING.md §7), jamais dénormalisé.
            $table->timestamps();
        });

        Schema::create('comptes_bancaires', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('banque');
            $table->string('numero');
            $table->decimal('solde_theorique', 15, 2)->default(0);
            $table->timestamps();
        });

        Schema::create('releves_bancaires', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('compte_bancaire_id')->constrained('comptes_bancaires')->restrictOnDelete();
            $table->date('date');
            $table->string('libelle');
            $table->decimal('montant', 15, 2);
            $table->foreignUuid('ecriture_rapprochee_id')->nullable()
                ->constrained('ecritures_comptables')->nullOnDelete();
            $table->enum('statut_rapprochement', ['non_rapproche', 'rapproche', 'litige'])
                ->default('non_rapproche');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('releves_bancaires');
        Schema::dropIfExists('comptes_bancaires');
        Schema::dropIfExists('budgets');
        Schema::dropIfExists('ecritures_comptables');
        Schema::dropIfExists('journaux_comptables');
        // plan_comptable AVANT centres_cout — inversé par rapport à l'ordre précédent,
        // nécessaire depuis l'ajout de plan_comptable.centre_cout_defaut_id (FK).
        Schema::dropIfExists('plan_comptable');
        Schema::dropIfExists('centres_cout');
        // exercices_comptables en dernier — ecritures_comptables la référençait (déjà droppée ci-dessus)
        Schema::dropIfExists('exercices_comptables');
    }
};
