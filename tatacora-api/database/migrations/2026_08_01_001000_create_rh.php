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
        // `services` et `employes` déjà créées en Partie 1 §6 (référentiels transverses,
        // nécessaires dès utilisateurs.employe_id) — cette migration ajoute le reste du domaine RH.

        Schema::create('plannings', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('employe_id')->constrained('employes')->restrictOnDelete();
            $table->foreignUuid('service_id')->constrained('services')->restrictOnDelete();
            $table->date('date');
            $table->time('heure_debut');
            $table->time('heure_fin');
            $table->timestamps();

            // Index de performance pour VerificationChevauchementService,
            // meme principe que reservations/contrats_location.
            $table->index(['employe_id', 'date', 'heure_debut', 'heure_fin']);
        });

        \Illuminate\Support\Facades\DB::statement('ALTER TABLE plannings ADD CONSTRAINT chk_plannings_heures CHECK (heure_fin > heure_debut)');

        // RG-13 - MySQL, revise 15/08/2026 : EXCLUDE USING gist remplacee par
        // VerificationChevauchementService. Particularite par rapport a
        // RG-01/RG-08 (03_DATABASE_ENGINEERING.md §11) : le chevauchement se
        // verifie sur (employe_id, date) EGAL, PUIS heure_debut/heure_fin qui
        // se chevauchent - pas une simple comparaison de deux colonnes date,
        // la requete du service doit filtrer explicitement sur la meme date
        // avant de comparer les heures :
        //   Planning::where('employe_id', $employeId)
        //     ->where('date', $date)
        //     ->where('heure_debut', '<', $heureFin)
        //     ->where('heure_fin', '>', $heureDebut)
        //     ->exists();

        Schema::create('presences', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('employe_id')->constrained('employes')->restrictOnDelete();
            $table->date('date');
            $table->time('heure_arrivee')->nullable();
            $table->time('heure_depart')->nullable();
            $table->enum('statut', ['present', 'retard', 'absent']);
            $table->timestamps();

            $table->unique(['employe_id', 'date']); // un seul pointage par employé et par jour
        });

        Schema::create('conges', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('employe_id')->constrained('employes')->restrictOnDelete();
            $table->string('type'); // congé annuel, maladie, exceptionnel...
            $table->date('date_debut');
            $table->date('date_fin');
            $table->enum('statut_validation', ['en_attente', 'valide', 'refuse'])->default('en_attente');
            $table->foreignUuid('validateur_id')->nullable()->constrained('utilisateurs')->nullOnDelete();
            $table->timestamps();
        });

        \Illuminate\Support\Facades\DB::statement('ALTER TABLE conges ADD CONSTRAINT chk_conges_dates CHECK (date_fin >= date_debut)');
        // RG-14 (délai de préavis, couverture minimale) validée en FormRequest,
        // PAS en contrainte SQL — dépend de paramètres système modifiables
        // (config('tatacora.delai_preavis_conge_jours')), cf. 06_DEVELOPMENT_STANDARDS.md §2.2.

        Schema::create('primes_sanctions', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('employe_id')->constrained('employes')->restrictOnDelete();
            $table->enum('type', ['prime', 'avance_salaire', 'sanction']);
            $table->decimal('montant', 15, 2);
            $table->text('motif')->nullable();
            $table->date('date');
            $this->auditColumns($table);
            $table->timestamps();
        });

        Schema::create('evaluations', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('employe_id')->constrained('employes')->restrictOnDelete();
            $table->string('periode');
            $table->decimal('note_globale', 4, 2); // ex. 15.50 / 20
            $table->text('commentaire')->nullable();
            $table->foreignUuid('evaluateur_id')->constrained('utilisateurs')->restrictOnDelete();
            $table->timestamps();
        });

        Schema::create('bulletins_paie', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('employe_id')->constrained('employes')->restrictOnDelete();
            $table->string('periode'); // 'YYYY-MM'
            $table->decimal('salaire_base', 15, 2);
            $table->decimal('total_primes', 15, 2)->default(0);
            $table->decimal('total_retenues', 15, 2)->default(0);
            $table->decimal('charges_sociales', 15, 2)->default(0); // taux CNSS — paramètre système, jamais codé en dur
            $table->decimal('net_a_payer', 15, 2);
            $table->enum('statut', ['brouillon', 'validee'])->default('brouillon');
            $this->auditColumns($table);
            $table->timestamps();

            $table->unique(['employe_id', 'periode']); // un seul bulletin par employé et par mois
            // Génère ecritures_comptables à la validation (listener GenererEcritureDepuisPaie) —
            // pas de saisie manuelle de l'écriture de paie.
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('bulletins_paie');
        Schema::dropIfExists('evaluations');
        Schema::dropIfExists('primes_sanctions');
        Schema::dropIfExists('conges');
        Schema::dropIfExists('presences');
        Schema::dropIfExists('plannings');
    }
};
